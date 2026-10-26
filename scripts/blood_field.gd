extends Node3D

## Owns every blood stain in one scene: surface patches, body and weapon
## coatings, and the short-lived spray bursts. Spatter, body and weapon stains
## live for 60 seconds, fade over the last three, and are recycled oldest-first
## when a busy fight exceeds the render budget. Death pools are the exception:
## they take their own budget and live for the corpse's five minutes. Created
## lazily by `BloodFx.field_for`.

const BloodFx = preload("res://scripts/blood_fx.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const BloodSurface = preload("res://scripts/blood_surface.gd")

const PATCH_SEGMENTS := 12
const PATCH_RINGS := 2
## Body stains are a small conforming grid: every vertex projects onto the
## measured garment, so the sheet hugs a curved breastplate instead of floating
## in the tangent plane. 3x3 is dense enough to follow the curve yet small
## enough to read as a flat colour stain, not a 3D card.
const BODY_RINGS := 3
const BODY_SEGMENTS := 3
const MAX_BURSTS := 14
const MAX_BODY_STAINS := 10
const MAX_WEAPON_STAINS := 8
## Death pools are the most important stains in a fight, so they get their own
## budget: the sixty-second spatter recycling never evicts the pool a corpse
## is lying in. One death lays a main pool plus two draining lobes, so sixty
## meshes cover twenty corpses at once — more than a five-minute frontier fight
## leaves behind.
const MAX_POOLS := 60
const GROUND_MASK := 1
const PATCH_LIFT := 0.012
## Death pools cover a whole body, so they use a denser conformed grid than the
## spatter patches; a coarse grid would clip through terrain humps at this size.
const POOL_RINGS := 4
const POOL_SEGMENTS := 16

var max_surface_stains := 160
var lifetime := BloodFx.LIFETIME
var pool_lifetime := BloodFx.POOL_LIFETIME
var _stains: Array[Dictionary] = []
## Visible-armor signature per rig: when the cloth underneath changes, the stains
## measured against the old surface are dropped instead of floating off it.
var _body_signatures: Dictionary = {}
var _bursts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _query := PhysicsRayQueryParameters3D.new()
## Distinct owner key for pools so `_enforce_cap` counts them separately from
## the surface spatter. Never a tree node.
var _pool_owner := RefCounted.new()
## Live death pools: world position and radius, so a body can check whether a
## foot is standing in blood. Updated as pools spawn and expire.
var _pools: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 0xB100D
	set_process(true)

func _process(delta: float) -> void:
	advance(delta)

# --- public field API ------------------------------------------------------

## Directional spray at a real blade/projectile contact plus flung droplets that
## mark the ground and walls around it. Body blood comes from `wound`.
func impact(at: Vector3, direction: Vector3, amount: float, headshot: bool) -> void:
	var dir := direction
	if dir.length_squared() < 0.000001:
		dir = Vector3.UP
	dir = dir.normalized()
	var weight := clampf(amount, 4.0, 60.0)
	_spawn_burst(at, dir, weight, 1.0 + (0.25 if headshot else 0.0))
	# The blow itself leaves a splat where it stopped against scenery.
	var hit := _ray(at - dir * 0.02, at + dir * 0.55, GROUND_MASK)
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		if absf(normal.y) < 0.72:
			_spawn_patch(hit.position, normal, 0.20 + weight * 0.006, false)
	_fling(at, dir, weight, headshot)

## Flung droplets: short rays away from the contact, each leaving a small patch
## where it lands. A hit reads as a splash only when the blood also hits the
## floor and wall around the victim, not a single decal pinned under it.
func _fling(at: Vector3, direction: Vector3, amount: float, headshot: bool) -> void:
	var radius := clampf(0.06 + amount * 0.0045, 0.07, 0.30)
	var reach := 1.25 + minf(amount, 60.0) * 0.016
	var up := Vector3.UP if absf(direction.y) < 0.94 else Vector3.RIGHT
	var side := direction.cross(up)
	if side.length_squared() < 0.0001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var lift := side.cross(direction).normalized()
	# The drops that fall straight off the blade, so every contact marks the
	# floor beneath it even when the fan finds no wall.
	var below := _ray(at, at + Vector3.DOWN * (0.9 + minf(amount, 40.0) * 0.01),
		GROUND_MASK)
	if not below.is_empty():
		var floor_normal: Vector3 = below.normal
		_spawn_patch(below.position, floor_normal, radius * 0.62, false)
	var count := 3
	if amount >= 20.0:
		count += 1
	if headshot:
		count += 1
	for index in count:
		var spin := _rng.randf() * TAU
		var tilt := _rng.randf_range(0.16, 0.78)
		var flung := (direction * cos(tilt) \
			+ (side * cos(spin) + lift * sin(spin)) * sin(tilt)).normalized()
		var hit := _ray(at, at + flung * reach * _rng.randf_range(0.55, 1.0),
			GROUND_MASK)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal
		_spawn_patch(hit.position, normal, radius * _rng.randf_range(0.45, 1.0), false)

## Damage that actually landed: body coating, floor spatter, and the death
## pool. `rig` may be null for a target with no visible body.
func wound(rig: Node3D, at: Vector3, amount: float, headshot: bool,
		lethal: bool, scale: float) -> void:
	var size_scale := clampf(scale, 0.35, 2.5)
	if is_instance_valid(rig):
		_stain_body(rig, at, amount, headshot, lethal, size_scale)
	var radius := clampf(0.14 + amount * 0.0075, 0.16, 0.62) * size_scale
	_ground_splat(at, radius)
	if lethal:
		_spawn_pool(at, size_scale)
		_spawn_burst(at + Vector3(0.0, 0.12 * size_scale, 0.0), Vector3.UP,
			maxf(amount, 24.0) * 1.6, size_scale * 1.25, 0.55)

## Someone else's blood on this body: the claw, paw or muzzle that struck. No
## floor decal — the victim's `wound` already owns the ground. The scatter stays
## local to the point that was hit, so a douse lands on the face of the body
## instead of the whole spine strip.
func bloodied(rig: Node3D, at: Vector3, amount: float, scale: float) -> void:
	var size_scale := clampf(scale, 0.35, 2.5)
	if is_instance_valid(rig):
		_stain_body(rig, at, amount, false, false, size_scale, true)
	_spawn_burst(at, Vector3.UP, maxf(amount, 6.0) * 0.7, size_scale * 0.65, 0.45)

## Wet coating on the blade that dealt the blow. Parented to the weapon node so
## it tracks every swing and socket change.
func stain_weapon(anchor: Node3D, amount: float, scale: float) -> void:
	if not is_instance_valid(anchor):
		return
	var box := _anchor_bounds(anchor)
	if box.size.length_squared() < 0.000001:
		return
	var center := box.get_center()
	var axis := 2
	if box.size.x >= box.size.y and box.size.x >= box.size.z:
		axis = 0
	elif box.size.y >= box.size.z:
		axis = 1
	var tip := Vector3.ZERO
	var component: float = center[axis]
	tip[axis] = -1.0 if component < 0.0 else 1.0
	var thin := 0
	for candidate in 3:
		if candidate == axis:
			continue
		if thin == axis or box.size[candidate] < box.size[thin]:
			thin = candidate
	var wide := 3 - axis - thin
	var thin_axis := Vector3.ZERO
	thin_axis[thin] = 1.0
	var wide_axis := Vector3.ZERO
	wide_axis[wide] = 1.0
	var blade_length: float = box.size[axis]
	var blade_value = anchor.get("blade_length") if "blade_length" in anchor else null
	if blade_value != null:
		blade_length = maxf(float(blade_value), 0.05)
	# Thin, sparse coating: a few small specks and a narrow smear.
	var droplet := clampf(blade_length * 0.012, 0.004, 0.010) * scale
	var lateral := clampf(blade_length * 0.020, 0.006, 0.022)
	var surface := clampf(blade_length * 0.012, 0.005, 0.010)
	var droplet_count := 2
	if amount >= 30.0:
		droplet_count += 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in droplet_count:
		var side := 1.0 if index % 2 == 0 else -1.0
		var normal := thin_axis * side
		var radius := droplet * _rng.randf_range(0.7, 1.3)
		var side_offset := (1.0 if _rng.randf() < 0.5 else -1.0) \
			* _rng.randf_range(0.35, 0.85)
		var position := tip * blade_length * _rng.randf_range(0.14, 0.46) \
			+ wide_axis * side_offset * lateral \
			+ normal * surface
		var size := Vector3(radius, radius * 0.22, radius * _rng.randf_range(0.8, 1.5))
		tool.append_from(BloodFx.blot_mesh(), 0,
			Transform3D(_basis_from_y(normal) * Basis.from_scale(size), position))
	# A narrow, short smear: a thin dragged cut, not a thick coating.
	var smear_length := blade_length * _rng.randf_range(0.12, 0.22)
	var smear_width := lateral * _rng.randf_range(0.6, 1.0)
	var smear_side := 1.0 if _rng.randf() < 0.5 else -1.0
	var smear_normal := thin_axis * smear_side
	var smear := Transform3D(
		_basis_yz(smear_normal, tip) * Basis.from_scale(
			Vector3(smear_width, 0.004, smear_length)),
		tip * blade_length * _rng.randf_range(0.16, 0.34) \
			+ wide_axis * _rng.randf_range(0.15, 0.5) * lateral * smear_side \
			+ smear_normal * surface)
	tool.append_from(BloodFx.blot_mesh(), 0, smear)
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodCoating"
	node.set_meta("blood_stain", "coating")
	node.mesh = mesh
	node.material_override = BloodFx.blot_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor.add_child(node)
	node.position = center
	_register_stain(node, anchor, "group", MAX_WEAPON_STAINS, lifetime)

func surface_stain_count() -> int:
	var count := 0
	for stain in _stains:
		if stain.owner == null and is_instance_valid(stain.node):
			count += 1
	return count

func stain_count() -> int:
	return _stains.size()

func burst_count() -> int:
	return _bursts.size()

func clear_all() -> void:
	for stain in _stains:
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
			_release_attachment(stain.node as Node)
	for burst in _bursts:
		if is_instance_valid(burst.node):
			(burst.node as Node).queue_free()
	_stains.clear()
	_bursts.clear()

# --- lifetime --------------------------------------------------------------

func advance(delta: float) -> void:
	for index in range(_stains.size() - 1, -1, -1):
		var stain: Dictionary = _stains[index]
		var node = stain.node
		if not is_instance_valid(node):
			_stains.remove_at(index)
			continue
		stain.age = float(stain.age) + delta
		var remaining := float(stain.life) - float(stain.age)
		if remaining <= BloodFx.FADE_SECONDS:
			_apply_fade(stain, clampf(remaining / BloodFx.FADE_SECONDS, 0.0, 1.0))
		if remaining <= 0.0:
			(node as Node).queue_free()
			_release_attachment(node as Node)
			_stains.remove_at(index)
	for index in range(_bursts.size() - 1, -1, -1):
		var burst: Dictionary = _bursts[index]
		burst.age = float(burst.age) + delta
		if not is_instance_valid(burst.node) or float(burst.age) >= float(burst.life):
			if is_instance_valid(burst.node):
				(burst.node as Node).queue_free()
			_bursts.remove_at(index)
	for index in range(_pools.size() - 1, -1, -1):
		if not is_instance_valid(_pools[index].node):
			_pools.remove_at(index)

## True when a world point is inside a live death pool. Pools are flat on the
## ground, so the check is a radius in the floor plane plus a height band: a
## rooftop above a street pool is not standing in it.
func is_in_blood(at: Vector3) -> bool:
	for pool in _pools:
		if not is_instance_valid(pool.node):
			continue
		var center: Vector3 = pool.position
		if absf(at.y - center.y) > 0.8:
			continue
		var offset := at - center
		offset.y = 0.0
		if offset.length() <= float(pool.radius) * 1.1:
			return true
	return false

## A bloody footprint: an elongated patch in the travel direction, like a
## real foot print. `direction` is the horizontal travel vector. `strength`
## is 0..1 — the first steps in a pool are dense, later ones fade.
func footprint(at: Vector3, direction: Vector3, strength: float) -> void:
	if strength <= 0.01:
		return
	var hit := _ray(at + Vector3(0.0, 0.3, 0.0), at + Vector3(0.0, -1.5, 0.0),
		GROUND_MASK)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.normal
	if normal.y < 0.35:
		return
	var dir := direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var side := Vector3.UP.cross(dir).normalized()
	# Foot-sized: ~25 cm long, ~11 cm wide, scaled by how bloody the step is.
	var length := 0.125 * (0.7 + strength * 0.3)
	var width := 0.055 * (0.7 + strength * 0.3)
	var center := (hit.position as Vector3) + normal * PATCH_LIFT
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Enough samples to resolve the print's silhouette and tread, small enough
	# that two steps a second never costs anything.
	var rows := 7
	var cols := 7
	for row in rows:
		var t := float(row) / float(rows - 1)
		var taper := 0.75 + 0.25 * t
		var along := (t - 0.5) * length * 2.0
		for col in cols:
			var s := (float(col) / float(cols - 1) - 0.5) * 2.0
			var offset := dir * along + side * (s * width * taper)
			var target := center + offset
			var ray_hit := _ray(target + normal * 0.5, target - normal * 0.5,
				GROUND_MASK)
			var point := target
			if not ray_hit.is_empty():
				point = (ray_hit.position as Vector3) + normal * PATCH_LIFT
			vertices.append(point - center)
			normals.append(normal)
			uvs.append(Vector2(t, float(col) / float(cols - 1)))
	for row in rows - 1:
		for col in cols - 1:
			var a := row * cols + col
			var b := a + 1
			var c := a + cols
			var d := c + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var patch := MeshInstance3D.new()
	patch.set_meta("blood_stain", "footprint")
	patch.mesh = mesh
	# Per-instance material so each step carries its own alpha: the first steps
	# in a pool are dense, later ones wipe off as the blood runs out.
	var mat := BloodFx.footprint_material().duplicate()
	mat.albedo_color.a = clampf(0.35 + strength * 0.65, 0.15, 1.0)
	patch.material_override = mat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	patch.position = center
	add_child(patch)
	# Named after parenting so every print gets a readable, unique name instead
	# of the engine's @MeshInstance3D@N fallback.
	patch.name = "BloodFootprint"
	# Footprints fade with the floor spatter and share its render budget; they
	# are not tied to the five-minute pool that made them.
	_register_stain(patch, null, "patch", max_surface_stains, lifetime)

func _apply_fade(stain: Dictionary, factor: float) -> void:
	var node = stain.node
	if not is_instance_valid(node):
		return
	if str(stain.kind) in ["patch", "soak"]:
		(node as GeometryInstance3D).transparency = 1.0 - factor
	else:
		(node as Node3D).scale = (stain.scale as Vector3) * maxf(factor, 0.001)

func _register_stain(node: Node, stain_owner, kind: String, cap: int,
		life: float) -> void:
	var entry := {"node": node, "owner": stain_owner, "kind": kind, "age": 0.0,
		"life": life, "scale": (node as Node3D).scale if node is Node3D else Vector3.ONE}
	_stains.append(entry)
	_enforce_cap(stain_owner, cap)

func _enforce_cap(stain_owner, cap: int) -> void:
	var count := 0
	for stain in _stains:
		if stain.owner != stain_owner or not is_instance_valid(stain.node):
			continue
		if (stain.node as Node).is_queued_for_deletion():
			continue
		count += 1
	var excess := count - cap
	var index := 0
	while excess > 0 and index < _stains.size():
		var stain: Dictionary = _stains[index]
		if stain.owner != stain_owner or not is_instance_valid(stain.node) \
				or (stain.node as Node).is_queued_for_deletion():
			index += 1
			continue
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
			_release_attachment(stain.node as Node)
		_stains.remove_at(index)
		excess -= 1

func _drop_rig_stains(rig: Node3D) -> void:
	for index in range(_stains.size() - 1, -1, -1):
		var stain: Dictionary = _stains[index]
		if stain.owner != rig:
			continue
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
			_release_attachment(stain.node as Node)
		_stains.remove_at(index)

## Frees the bone attachment a stain was riding on once nothing is left on it,
## so long fights do not leave empty nodes hanging off every skeleton bone.
func _release_attachment(node: Node) -> void:
	var parent := node.get_parent()
	if parent == null or not parent.has_meta("blood_attachment"):
		return
	for other in _stains:
		var sibling = other.node
		if sibling == null or not is_instance_valid(sibling) or sibling == node:
			continue
		if sibling.is_queued_for_deletion():
			continue
		if sibling.get_parent() == parent:
			return
	parent.queue_free()

# --- body and weapon stains ------------------------------------------------

func _stain_body(rig: Node3D, at: Vector3, amount: float, headshot: bool,
		lethal: bool, scale: float, localized: bool = false) -> void:
	Perf.begin("stain.measure")
	var body := BloodSurface.body_for(rig)
	Perf.end()
	if body.is_empty():
		return
	var signature := int(body.get("signature", 0))
	if signature != int(_body_signatures.get(rig.get_instance_id(), signature)):
		_drop_rig_stains(rig)
	if _body_signatures.size() > 256:
		_body_signatures.clear()
	_body_signatures[rig.get_instance_id()] = signature
	var carrier := BloodSurface.nearest_carrier(body, at)
	if carrier.is_empty():
		return
	var anchor := BloodSurface.anchor_for(carrier)
	if anchor == null:
		return
	var center := BloodSurface.to_local(carrier, at)
	var down := BloodSurface.down_local(carrier)
	var lift := BloodSurface.LIFT * clampf(scale, 0.6, 2.2)
	# Visible flat quads: the soak texture does the shape work.
	var base := clampf(0.020 + amount * 0.0012, 0.025, 0.055) * scale
	var limit := BloodSurface.patch_extent(carrier)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed := 0
	# Main soak: the broad, flat patch that reads as a colour stain.
	var half_up := minf(base * _rng.randf_range(0.90, 1.10), limit.x * 0.7)
	var half_wide := minf(base * _rng.randf_range(0.75, 1.0), limit.y * 0.65)
	if BloodSurface.add_patch(tool, carrier, center, down, half_up,
			half_wide, BODY_RINGS, BODY_SEGMENTS, _rng.randf() * TAU, lift):
		placed += 1
	# Small extra soaks that overlap the main one, so the union reads as one
	# irregular splash rather than a ring of separate discs.
	var satellites := 1
	if amount >= 20.0:
		satellites = 2
	if headshot or lethal:
		satellites += 1
	if localized:
		satellites += 1
	for index in satellites:
		var direction := Vector3(_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		if direction.length_squared() < 0.0001:
			direction = Vector3.UP
		var sat_at: Vector3 = center + direction.normalized() \
			* base * _rng.randf_range(0.30, 0.65)
		var sat := base * _rng.randf_range(0.30, 0.50)
		if BloodSurface.add_patch(tool, carrier, sat_at, down,
				sat * _rng.randf_range(0.85, 1.10),
				sat * _rng.randf_range(0.70, 1.0),
				BODY_RINGS, BODY_SEGMENTS, _rng.randf() * TAU, lift):
			placed += 1
	if placed == 0:
		tool.clear()
		return
	Perf.begin("stain.commit")
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodSoak"
	node.set_meta("blood_stain", "wound")
	node.mesh = mesh
	node.material_override = BloodFx.soak_material(_rng.randi() % BloodFx.SPLAT_VARIANTS)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor.add_child(node)
	_register_stain(node, rig, "soak", MAX_BODY_STAINS, lifetime)
	Perf.end()

## An arrow carries a smear, not a blade coating: a wet skim on the shaft just
## behind the head and two specks. Sized from the shaft, never the fletching.
func stain_projectile(anchor: Node3D, amount: float) -> void:
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var bounds := _anchor_bounds(anchor)
	if bounds.size.length_squared() < 0.000001:
		return
	var center := bounds.get_center()
	var axis := 2
	if bounds.size.x >= bounds.size.y and bounds.size.x >= bounds.size.z:
		axis = 0
	elif bounds.size.y >= bounds.size.z:
		axis = 1
	var shaft := center
	var component: float = center[axis]
	shaft[axis] = -1.0 if component < 0.0 else 1.0
	var thin := 0
	for candidate in 3:
		if candidate == axis:
			continue
		if thin == axis or bounds.size[candidate] < bounds.size[thin]:
			thin = candidate
	var wide := 3 - axis - thin
	var thin_axis := Vector3.ZERO
	thin_axis[thin] = 1.0
	var wide_axis := Vector3.ZERO
	wide_axis[wide] = 1.0
	var length: float = bounds.size[axis]
	var shaft_radius := clampf(length * 0.008, 0.004, 0.011)
	var smear_length := clampf(0.018 + amount * 0.0008, 0.018, 0.05)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var normal := thin_axis * side
	var smear_center: Vector3 = shaft * length * _rng.randf_range(0.70, 0.88)
	_wrap_shaft(tool, smear_center, normal, wide_axis, shaft, shaft_radius,
		smear_length * 0.5, shaft_radius * 0.9)
	for index in 2:
		var speck_side := 1.0 if _rng.randf() < 0.5 else -1.0
		_wrap_shaft(tool, smear_center + shaft * _rng.randf_range(-0.02, 0.02),
			thin_axis * speck_side, wide_axis, shaft,
			shaft_radius * _rng.randf_range(0.5, 0.9), 0.004, 0.0035)
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodSmear"
	node.set_meta("blood_stain", "coating")
	node.mesh = mesh
	node.material_override = BloodFx.soak_material(_rng.randi() % BloodFx.SPLAT_VARIANTS)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor.add_child(node)
	node.position = center
	_register_stain(node, anchor, "group", MAX_WEAPON_STAINS, lifetime)

## Lays a small textured band around a thin shaft so the stain curves with it.
func _wrap_shaft(tool: SurfaceTool, center: Vector3, normal: Vector3,
		across: Vector3, axis: Vector3, radius: float, half_length: float,
		half_wide: float) -> void:
	# A band, never a full wrap: a shaft painted right round reads as goo.
	var rings := 2
	var segments := 2
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rings + 1:
		var along := float(row) / float(rings) * 2.0 - 1.0
		for column in segments + 1:
			var sideways := float(column) / float(segments) * 2.0 - 1.0
			var turn := sideways * half_wide / maxf(radius + 0.0015, 0.002)
			var direction := (normal * cos(turn) + across * sin(turn)).normalized()
			var point: Vector3 = center + axis * (along * half_length) \
				+ direction * (radius + 0.0015)
			band.set_normal(direction)
			band.set_uv(Vector2(along * 0.5 + 0.5, sideways * 0.5 + 0.5))
			band.add_vertex(point)
	var stride := segments + 1
	for row in rings:
		for column in segments:
			var a := row * stride + column
			var b := a + 1
			var c := a + stride
			var d := c + 1
			band.add_index(a)
			band.add_index(c)
			band.add_index(b)
			band.add_index(b)
			band.add_index(c)
			band.add_index(d)
	var built := band.commit()
	if built != null and built.get_surface_count() > 0:
		tool.append_from(built, 0, Transform3D())
func _anchor_bounds(anchor: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	for node in anchor.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local: AABB = anchor.global_transform.affine_inverse() \
			* mesh_node.global_transform * mesh_node.get_aabb()
		if first:
			combined = local
			first = false
		else:
			combined = combined.merge(local)
	return combined

func _basis_from_y(up: Vector3) -> Basis:
	var y := up.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _basis_yz(y_dir: Vector3, z_dir: Vector3) -> Basis:
	var y := y_dir.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var z := z_dir - y * z_dir.dot(y)
	if z.length_squared() < 0.0001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)

# --- floor patches ---------------------------------------------------------

## One main splat under the wound plus smaller satellites around it, so the
## floor around a hit is speckled instead of carrying a single tidy disc.
func _ground_splat(at: Vector3, radius: float) -> void:
	var specks := 2
	if radius >= 0.30:
		specks += 1
	for index in specks + 1:
		var spread := 0.20 if index == 0 else _rng.randf_range(0.26, 0.95)
		var speck := radius if index == 0 else radius * _rng.randf_range(0.16, 0.44)
		_ground_patch(at, speck, spread)

func _ground_patch(at: Vector3, radius: float, spread: float) -> void:
	var offset := Vector3(_rng.randf_range(-spread, spread), 0.0,
		_rng.randf_range(-spread, spread))
	var hit := _ray(at + Vector3(0.0, 0.8, 0.0) + offset,
		at + Vector3(0.0, -3.0, 0.0) + offset, GROUND_MASK)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.normal
	if normal.y < 0.42:
		return
	_spawn_patch(hit.position, normal, radius, false)

## Blood pooling under a corpse: a main pool wide enough to read around the
## body's silhouette, then two lobes draining out from under the body. Pools
## live for `pool_lifetime` (five minutes, matching the corpse) instead of the
## sixty-second spatter lifetime, and have their own render budget.
func _spawn_pool(at: Vector3, scale: float) -> void:
	var hit := _ray(at + Vector3(0.0, 0.6, 0.0), at + Vector3(0.0, -3.0, 0.0),
		GROUND_MASK)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.35:
		return
	_grow_pool(hit.position, hit.normal, 0.74 * scale, 0.28, 1.1, true)
	# The lobes creep out past the corpse so the pool is visible from above the
	# body, the way blood keeps running out of a body that has stopped moving.
	for index in 2:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(0.75, 1.35) * scale
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * distance
		var lobe := _ray(at + Vector3(0.0, 0.6, 0.0) + offset,
			at + Vector3(0.0, -3.0, 0.0) + offset, GROUND_MASK)
		if lobe.is_empty() or (lobe.normal as Vector3).y < 0.35:
			continue
		_grow_pool(lobe.position, lobe.normal,
			_rng.randf_range(0.20, 0.30) * scale, 0.30,
			_rng.randf_range(1.8, 3.2), false)

func _grow_pool(center: Vector3, normal: Vector3, radius: float,
		start_scale: float, seconds: float, creep: bool) -> MeshInstance3D:
	var pool := _spawn_patch(center, normal, radius, true)
	pool.scale = Vector3.ONE * start_scale
	var tween := pool.create_tween()
	tween.tween_property(pool, "scale", Vector3.ONE, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if creep:
		tween.tween_property(pool, "scale", Vector3.ONE * 1.18, 12.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pools.append({"node": pool, "position": center, "radius": radius})
	return pool

func _spawn_patch(center: Vector3, normal: Vector3, radius: float,
		pool: bool) -> MeshInstance3D:
	var variant := _rng.randi() % BloodFx.SPLAT_VARIANTS
	var mesh := _conform_patch(center, normal, radius,
		variant * 37 + _rng.randi() % 97,
		POOL_RINGS if pool else PATCH_RINGS,
		POOL_SEGMENTS if pool else PATCH_SEGMENTS)
	var patch := MeshInstance3D.new()
	patch.name = "BloodPool" if pool else "BloodSplat"
	patch.set_meta("blood_stain", "pool" if pool else "splat")
	patch.mesh = mesh
	patch.material_override = BloodFx.pool_material() if pool \
		else BloodFx.patch_material(variant)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	patch.position = center
	add_child(patch)
	if pool:
		_register_stain(patch, _pool_owner, "patch", MAX_POOLS, pool_lifetime)
	else:
		_register_stain(patch, null, "patch", max_surface_stains, lifetime)
	return patch

## Builds a small radial patch whose vertices are dropped onto the real surface
## so blood follows slopes and steps instead of clipping through the ground.
func _conform_patch(center: Vector3, normal: Vector3, radius: float,
		phase_seed: int, rings: int = PATCH_RINGS,
		segments: int = PATCH_SEGMENTS) -> ArrayMesh:
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var back := side.cross(up).normalized()
	var phase := float(phase_seed % 628) * 0.01
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	normals.append(up)
	uvs.append(Vector2(0.5, 0.5))
	var ring_starts: Array[int] = []
	for ring in range(1, rings + 1):
		var fraction := float(ring) / float(rings)
		ring_starts.append(vertices.size())
		for segment in segments:
			var angle := TAU * float(segment) / float(segments) + phase
			var tangent := side * cos(angle) + back * sin(angle)
			var target := center + tangent * radius * fraction
			var hit := _ray(target + up * 0.9, target - up * 0.75, GROUND_MASK)
			var point := target
			if not hit.is_empty():
				point = (hit.position as Vector3) + up * PATCH_LIFT
			else:
				point += up * PATCH_LIFT
			vertices.append(point - center)
			normals.append(up)
			uvs.append(Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * 0.5 * fraction)
	var first_ring := ring_starts[0]
	for segment in segments:
		indices.append(0)
		indices.append(first_ring + segment)
		indices.append(first_ring + (segment + 1) % segments)
	for ring in range(1, rings):
		var inner := ring_starts[ring - 1]
		var outer := ring_starts[ring]
		for segment in segments:
			var next := (segment + 1) % segments
			indices.append(inner + segment)
			indices.append(outer + segment)
			indices.append(inner + next)
			indices.append(inner + next)
			indices.append(outer + segment)
			indices.append(outer + next)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	if not is_inside_tree():
		return {}
	_query.from = from
	_query.to = to
	_query.collision_mask = mask
	_query.exclude = []
	return get_world_3d().direct_space_state.intersect_ray(_query)

# --- spray -----------------------------------------------------------------

func _spawn_burst(at: Vector3, direction: Vector3, amount: float, scale: float,
		up_bias: float = 0.0) -> void:
	while _bursts.size() >= MAX_BURSTS:
		var oldest: Dictionary = _bursts.pop_front()
		if is_instance_valid(oldest.node):
			(oldest.node as Node).queue_free()
	var burst := CPUParticles3D.new()
	burst.name = "BloodSpray"
	burst.one_shot = true
	burst.amount = clampi(int(round(26.0 + amount * 2.2)), 28, 120)
	burst.lifetime = _rng.randf_range(0.42, 0.80)
	burst.explosiveness = 0.92
	burst.direction = (direction + Vector3.UP * up_bias).normalized()
	burst.spread = 58.0
	burst.initial_velocity_min = 1.7 * scale
	burst.initial_velocity_max = 4.4 * scale
	burst.gravity = Vector3(0.0, -10.4, 0.0)
	# Drops, not motes: sub-millimetre specks vanished against the terrain, so
	# the spray uses pebble-to-marble droplets that read at combat distance.
	burst.scale_amount_min = 0.005 * scale
	burst.scale_amount_max = 0.012 * scale
	burst.mesh = BloodFx.drop_mesh()
	burst.material_override = BloodFx.drop_material()
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.color = Color(1.0, 1.0, 1.0, 1.0)
	burst.local_coords = false
	burst.position = at
	add_child(burst)
	burst.emitting = true
	_bursts.append({"node": burst, "age": 0.0, "life": burst.lifetime + 0.6})
