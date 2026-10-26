extends RefCounted
## Where a fighter's visible surface actually is.
##
## Blood has to lie on the clothes instead of floating beside them. The GL
## Compatibility renderer has no decal support and the collision body is only a
## capsule, so this class measures the real garment once per rig: every visible
## skinned-mesh vertex is binned into its dominant bone and stored as a radial
## profile around that bone's rest axis, while primitive-built rigs are measured
## as their own triangle soup. BloodField lays its stain patches out on those
## measurements, projecting every patch vertex onto the shell.
##
## Everything here is presentation. A failed measurement only means no body
## blood for that rig; it never gates damage.

const ANGLE_BUCKETS := 24
const AXIAL_BANDS := 12
const CELLS := ANGLE_BUCKETS * AXIAL_BANDS
## Vertices sampled per rig. A radial profile needs a dense sample to find the
## outermost garment layer, but eight thousand is already far more than the
## 288 cells a profile can store.
const MAX_SAMPLED_VERTICES := 8000
const CACHE_LIMIT := 96
## The stain sits this far off the measured surface so it never z-fights cloth.
const LIFT := 0.003

static var _cache: Dictionary = {}
## Extracted skin arrays per mesh surface. Every devil of a species shares one
## Mesh resource, so this is what stops the second body of that species from
## re-extracting (and re-allocating) every vertex in order to measure itself.
static var _surface_arrays: Dictionary = {}
## Measured bodies by structure, not by instance. The profiles are stored in
## bone-local space, so every body of one species is measured once and the copy
## handed out is rebound to the caller's own skeleton. Without this, the first
## blow on each of a hundred devils paid for a fresh measurement of the same
## garment.
static var _bodies: Dictionary = {}

# --- measurement -----------------------------------------------------------

## Measured surface for one rig, cached until its visible meshes change (armor
## swaps, equipment, death meshes). Returns {} when the rig has nothing to paint.
static func body_for(rig: Node3D) -> Dictionary:
	if not is_instance_valid(rig):
		return {}
	var key := rig.get_instance_id()
	var signature := _signature(rig)
	var entry = _cache.get(key)
	if entry != null and is_instance_valid(entry.rig) and int(entry.signature) == signature:
		return entry.body
	var species := _species_key(rig, signature)
	var template = _bodies.get(species)
	var body: Dictionary
	if template != null:
		body = _rebind(template, rig)
	else:
		body = _measure(rig)
		_bodies[species] = _template_of(body)
	body["signature"] = signature
	_cache[key] = {"signature": signature, "rig": rig, "body": body}
	_prune()
	return body


## The measurement identity of a rig: two rigs with the same key share one
## measured garment. Callers use it to warm one body per species.
static func structure_key(rig: Node3D) -> String:
	if not is_instance_valid(rig):
		return ""
	return _species_key(rig, _signature(rig))


## What makes two rigs structurally identical: the same visible skinned meshes
## and the same bone count, which is what the measured profiles depend on.
static func _species_key(rig: Node3D, signature: int) -> String:
	var skeleton := _find_skeleton(rig)
	var bones := skeleton.get_bone_count() if skeleton != null else 0
	return "%d|%d" % [signature, bones]


## A stub-free copy of a measurement: the profiles are kept, every live node
## reference is dropped.
static func _template_of(body: Dictionary) -> Dictionary:
	var template := body.duplicate(true)
	template.rig = null
	template.skeleton = null
	for profile in (template.bones as Dictionary).values():
		(profile as Dictionary).skeleton = null
	for carrier in template.primitives as Array:
		(carrier as Dictionary).node = null
	return template


## A fresh copy of a shared measurement, pointed at this rig's own nodes.
static func _rebind(template: Dictionary, rig: Node3D) -> Dictionary:
	var body := template.duplicate(true)
	body.rig = rig
	var skeleton := _find_skeleton(rig)
	body.skeleton = skeleton
	for profile in (body.bones as Dictionary).values():
		(profile as Dictionary).skeleton = skeleton
	for carrier in body.primitives as Array:
		var carrier_name := str((carrier as Dictionary).get("name", ""))
		if carrier_name.is_empty():
			continue
		(carrier as Dictionary).node = rig.find_child(carrier_name, true, false)
	return body

## The bone or primitive the blow's cloth belongs to. Thick limbs win ties, but
## proximity decides: blood lands on the body part that was actually hit.
static func nearest_carrier(body: Dictionary, at_world: Vector3) -> Dictionary:
	if not body.bones.is_empty():
		return _nearest_bone(body, at_world)
	if not body.primitives.is_empty():
		return _nearest_primitive(body, at_world)
	return {}

## Converts a world point into the carrier's own space.
static func to_local(carrier: Dictionary, at_world: Vector3) -> Vector3:
	if str(carrier.kind) == "bone":
		var skeleton: Skeleton3D = carrier.skeleton
		if not is_instance_valid(skeleton):
			return at_world
		var posed: Transform3D = skeleton.global_transform \
			* skeleton.get_bone_global_pose(int(carrier.index))
		return posed.affine_inverse() * at_world
	var node: Node3D = carrier.node
	if not is_instance_valid(node):
		return at_world
	return node.global_transform.affine_inverse() * at_world

## Gravity in the carrier's space, so drips still run down on a raised arm.
static func down_local(carrier: Dictionary) -> Vector3:
	var down := Vector3.DOWN
	if str(carrier.kind) == "bone":
		var skeleton: Skeleton3D = carrier.skeleton
		if is_instance_valid(skeleton):
			var posed: Transform3D = skeleton.global_transform \
				* skeleton.get_bone_global_pose(int(carrier.index))
			return (posed.basis.inverse() * down).normalized()
		return down
	var node: Node3D = carrier.node
	if is_instance_valid(node):
		return (node.global_basis.inverse() * down).normalized()
	return down

## Bone attachments are reused per bone and freed by BloodField once their last
## stain expires; primitive rigs parent the stain straight to the limb mesh.
static func anchor_for(carrier: Dictionary) -> Node3D:
	if str(carrier.kind) == "bone":
		var skeleton: Skeleton3D = carrier.skeleton
		if not is_instance_valid(skeleton):
			return null
		var attach_name := "BloodBone_%d" % int(carrier.index)
		var existing := skeleton.get_node_or_null(attach_name) as BoneAttachment3D
		if existing != null and not existing.is_queued_for_deletion():
			return existing
		var attachment := BoneAttachment3D.new()
		attachment.name = attach_name
		attachment.set_meta("blood_attachment", true)
		attachment.bone_name = skeleton.get_bone_name(int(carrier.index))
		skeleton.add_child(attachment)
		return attachment
	var node: Node3D = carrier.node
	return node if is_instance_valid(node) else null

# --- patch geometry ---------------------------------------------------------

## Largest half-extents that still fit the measured cloth, so a patch never
## turns into a flat sheet by running off the end of its strip.
static func patch_extent(carrier: Dictionary) -> Vector2:
	if str(carrier.kind) == "bone":
		var span: float = maxf(float(carrier.high) - float(carrier.low), 0.02)
		var arc: float = maxf(float(carrier.peak), 0.02) * TAU
		return Vector2(maxf(span * 0.42, 0.025), maxf(arc * 0.20, 0.025))
	var half: Vector3 = carrier.half
	return Vector2(maxf(half.z * 0.7, 0.02), maxf(half.x * 0.7, 0.02))

## Projects a point onto the measured surface. `lift` is added along the normal.
## Returns {} where the rig has no cloth, so stains never hang in the air.
static func surface_point(carrier: Dictionary, local_point: Vector3,
		lift: float = LIFT) -> Dictionary:
	if str(carrier.kind) == "bone":
		var axis: Vector3 = carrier.axis
		# Never extrapolate past the measured strip: a patch edge beyond the
		# crown or the cuff used to ring the air around the head and read as
		# red feathers. Samples clamp to the last measured band instead.
		var h: float = clampf(local_point.dot(axis), float(carrier.low),
			float(carrier.high))
		var planar: Vector3 = local_point - axis * h
		var angle: float = 0.0 if planar.length_squared() < 0.000001 \
			else atan2(planar.dot(carrier.v), planar.dot(carrier.u))
		var radius := _shell_radius(carrier, h, angle)
		if radius < 0.0:
			return {}
		var radial: Vector3 = carrier.u * cos(angle) + carrier.v * sin(angle)
		return {"point": axis * h + radial * (radius + lift),
			"normal": radial}
	var tris: PackedVector3Array = _primitive_tris(carrier)
	if tris.is_empty():
		return {}
	var hit := _closest_on_triangles(tris, local_point)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.normal
	var inside: Vector3 = carrier.center - hit.point
	if normal.dot(inside) > 0.0:
		normal = -normal
	hit.normal = normal
	hit.point = (hit.point as Vector3) + normal * lift
	return hit

## Appends one stain patch: a small grid whose every vertex is projected onto
## the measured surface, so the sheet hugs a curved garment instead of floating
## in the tangent plane. Because each vertex sits on the shell (only `lift`
## above it), the patch reads as a flat colour stain, not a 3D card. A vertex
## with no cloth collapses onto the patch centre rather than hanging in the air.
## `half_up` runs along the patch's long axis, `half_wide` across it.
static func add_patch(tool: SurfaceTool, carrier: Dictionary, center_local: Vector3,
		up_local: Vector3, half_up: float, half_wide: float, rings: int,
		segments: int, rotate: float = 0.0, lift: float = LIFT) -> bool:
	var middle := surface_point(carrier, center_local, lift)
	if middle.is_empty():
		return false
	var normal: Vector3 = middle.normal
	var up := up_local - normal * up_local.dot(normal)
	if up.length_squared() < 0.000001:
		up = normal.cross(Vector3.RIGHT)
		if up.length_squared() < 0.000001:
			up = normal.cross(Vector3.FORWARD)
	up = up.normalized()
	var across := normal.cross(up).normalized()
	if absf(rotate) > 0.000001:
		var turned := up * cos(rotate) + across * sin(rotate)
		across = -up * sin(rotate) + across * cos(rotate)
		up = turned.normalized()
		across = across.normalized()
	var origin: Vector3 = middle.point
	var misses := 0
	var patch := SurfaceTool.new()
	patch.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rings + 1:
		var along := float(row) / float(rings) * 2.0 - 1.0
		for column in segments + 1:
			var sideways := float(column) / float(segments) * 2.0 - 1.0
			var sample: Vector3 = center_local \
				+ up * (along * half_up) + across * (sideways * half_wide)
			var projected := surface_point(carrier, sample, lift)
			var point := origin
			var vertex_normal := normal
			if projected.is_empty():
				# A sample with no cloth collapses onto the patch centre instead
				# of floating beside the body as a flat card.
				point = origin
				misses += 1
			else:
				point = projected.point
				vertex_normal = projected.normal
			patch.set_normal(vertex_normal)
			patch.set_uv(Vector2(along * 0.5 + 0.5, sideways * 0.5 + 0.5))
			patch.add_vertex(point)
	if misses * 2 > (rings + 1) * (segments + 1):
		return false
	for row in rings:
		for column in segments:
			var a := row * (segments + 1) + column
			var b := a + 1
			var c := a + segments + 1
			var d := c + 1
			patch.add_index(a)
			patch.add_index(c)
			patch.add_index(b)
			patch.add_index(b)
			patch.add_index(c)
			patch.add_index(d)
	var built := patch.commit()
	if built == null or built.get_surface_count() == 0:
		return false
	tool.append_from(built, 0, Transform3D())
	return true

# --- bone profiles ---------------------------------------------------------

static func _measure(rig: Node3D) -> Dictionary:
	var body := {"rig": rig, "skeleton": null, "bones": {}, "primitives": []}
	var meshes := _mesh_instances(rig)
	var skeleton := _find_skeleton(rig)
	if skeleton != null:
		var skinned: Array = []
		for node in meshes:
			var mesh_node := node as MeshInstance3D
			if mesh_node.skin != null and mesh_node.is_visible_in_tree():
				skinned.append(mesh_node)
		if not skinned.is_empty():
			body.skeleton = skeleton
			body.bones = _measure_bones(skeleton, skinned).bones
	if body.bones.is_empty():
		body.primitives = _primitive_list(meshes)
	return body

## One mesh surface's vertex, bone and weight arrays, extracted once.
static func _extract(mesh: Mesh, surface: int) -> Dictionary:
	var key := mesh.get_instance_id() * 8 + surface
	var found = _surface_arrays.get(key)
	if found != null:
		return found
	var arrays := mesh.surface_get_arrays(surface)
	var entry := {
		"vertices": arrays[Mesh.ARRAY_VERTEX],
		"bones": arrays[Mesh.ARRAY_BONES],
		"weights": arrays[Mesh.ARRAY_WEIGHTS],
	}
	if _surface_arrays.size() > 256:
		_surface_arrays.clear()
	_surface_arrays[key] = entry
	return entry


static func _measure_bones(skeleton: Skeleton3D, meshes: Array) -> Dictionary:
	var empty := {"bones": {}}
	var bone_count := skeleton.get_bone_count()
	if bone_count <= 0:
		return empty
	var axes := PackedVector3Array()
	var ups := PackedVector3Array()
	var widths := PackedVector3Array()
	var rests: Array[Transform3D] = []
	axes.resize(bone_count)
	ups.resize(bone_count)
	widths.resize(bone_count)
	rests.resize(bone_count)
	for index in bone_count:
		var rest := skeleton.get_bone_global_rest(index)
		rests[index] = rest
		var direction := Vector3.UP
		var children := skeleton.get_bone_children(index)
		if not children.is_empty():
			direction = skeleton.get_bone_global_rest(children[0]).origin - rest.origin
		elif skeleton.get_bone_parent(index) >= 0:
			direction = rest.origin \
				- skeleton.get_bone_global_rest(skeleton.get_bone_parent(index)).origin
		var local := (rest.basis.inverse() * direction.normalized()).normalized()
		if local.length_squared() < 0.000001:
			local = Vector3.UP
		axes[index] = local
		var up := local.cross(Vector3.FORWARD)
		if up.length_squared() < 0.0001:
			up = local.cross(Vector3.RIGHT)
		up = up.normalized()
		ups[index] = up
		widths[index] = up.cross(local).normalized()
	# Every visible cloth vertex, once. A bone's profile has to know the
	# outermost garment over it (a belt weighted to the spine still covers the
	# hip), so neighbours are measured too, not only the bone's own weights.
	var positions := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var total := 0
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.skin == null or mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var vertices = _extract(mesh_node.mesh, surface).vertices
			if vertices != null:
				total += (vertices as PackedVector3Array).size()
	var step: int = maxi(1, int(ceil(float(total) / float(MAX_SAMPLED_VERTICES))))
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var skin: Skin = mesh_node.skin
		if skin == null or mesh_node.mesh == null:
			continue
		var mesh_transform := mesh_node.transform
		var bind_map := _bind_map(skin, skeleton)
		for surface in mesh_node.mesh.get_surface_count():
			var extracted := _extract(mesh_node.mesh, surface)
			var vertices = extracted.vertices
			var skin_bones = extracted.bones
			var skin_weights = extracted.weights
			if vertices == null or skin_bones == null or skin_weights == null:
				continue
			var vertex_count: int = (vertices as PackedVector3Array).size()
			if vertex_count == 0:
				continue
			var stride: int = maxi(1, int(skin_bones.size()) / vertex_count)
			for vertex in range(0, vertex_count, step):
				# The four heaviest influences, kept in descending order by
				# scalar locals. A per-vertex array pair here allocated twice
				# for every sampled vertex of every rig, which made measuring a
				# body cost tens of milliseconds the first time it bled.
				var bone_a := -1
				var bone_b := -1
				var bone_c := -1
				var bone_d := -1
				var weight_a := 0.0
				var weight_b := 0.0
				var weight_c := 0.0
				var weight_d := 0.0
				var total_weight := 0.0
				for slot in stride:
					var weight: float = skin_weights[vertex * stride + slot]
					if weight <= 0.0:
						continue
					total_weight += weight
					var skin_bone := int(skin_bones[vertex * stride + slot])
					var resolved := -1
					if skin_bone >= 0 and skin_bone < bind_map.size():
						resolved = bind_map[skin_bone]
					if weight > weight_a:
						bone_d = bone_c; weight_d = weight_c
						bone_c = bone_b; weight_c = weight_b
						bone_b = bone_a; weight_b = weight_a
						bone_a = resolved; weight_a = weight
					elif weight > weight_b:
						bone_d = bone_c; weight_d = weight_c
						bone_c = bone_b; weight_c = weight_b
						bone_b = resolved; weight_b = weight
					elif weight > weight_c:
						bone_d = bone_c; weight_d = weight_c
						bone_c = resolved; weight_c = weight
					elif weight > weight_d:
						bone_d = resolved; weight_d = weight
				if total_weight <= 0.0:
					continue
				positions.append(mesh_transform \
					* (vertices as PackedVector3Array)[vertex])
				var inverse := 1.0 / total_weight
				bones.append(bone_a)
				bones.append(bone_b)
				bones.append(bone_c)
				bones.append(bone_d)
				weights.append(weight_a * inverse)
				weights.append(weight_b * inverse)
				weights.append(weight_c * inverse)
				weights.append(weight_d * inverse)
	# Profiles are built from each vertex's dominant bone plus the garment layers
	# that continue along the same chain, which is cheap; the whole-garment sample
	# below is what corrects a splash onto the outermost layer in the current pose.
	var record_bones := PackedInt32Array()
	var record_h := PackedFloat32Array()
	var record_angle := PackedFloat32Array()
	var record_radius := PackedFloat32Array()
	for index in range(0, positions.size(), maxi(1, int(ceil(float(positions.size()) \
			/ float(MAX_SAMPLED_VERTICES))))):
		var dominant := -1
		var best := 0.0
		for slot in 4:
			var weight := weights[index * 4 + slot]
			if weight > best:
				best = weight
				dominant = bones[index * 4 + slot]
		if dominant < 0 or dominant >= bone_count or best <= 0.0:
			continue
		var targets := [dominant]
		var parent := skeleton.get_bone_parent(dominant)
		if parent >= 0:
			var back: Vector3 = rests[parent].origin - rests[dominant].origin
			if back.length_squared() > 0.000001:
				var back_dir: Vector3 = (rests[dominant].basis.inverse() * back) \
					.normalized()
				if back_dir.dot(axes[dominant]) < -0.6:
					targets.append(parent)
		for child in skeleton.get_bone_children(dominant):
			if targets.size() >= 5:
				break
			var offset: Vector3 = rests[child].origin - rests[dominant].origin
			if offset.length_squared() < 0.000001:
				continue
			var forward: Vector3 = (rests[dominant].basis.inverse() * offset) \
				.normalized()
			if forward.dot(axes[dominant]) > 0.6:
				targets.append(child)
		for target in targets:
			var point: Vector3 = rests[target].affine_inverse() * positions[index]
			var h: float = point.dot(axes[target])
			var planar: Vector3 = point - axes[target] * h
			var radius := planar.length()
			if radius <= 0.002 or radius > 0.9:
				continue
			record_bones.append(target)
			record_h.append(h)
			record_angle.append(atan2(planar.dot(widths[target]),
				planar.dot(ups[target])))
			record_radius.append(radius)
	var lows := PackedFloat32Array()
	var highs := PackedFloat32Array()
	lows.resize(bone_count)
	highs.resize(bone_count)
	for bone in bone_count:
		lows[bone] = INF
		highs[bone] = -INF
	for index in record_bones.size():
		var bone := record_bones[index]
		lows[bone] = minf(lows[bone], record_h[index])
		highs[bone] = maxf(highs[bone], record_h[index])
	var peaks := PackedFloat32Array()
	peaks.resize(bone_count * CELLS)
	for index in record_bones.size():
		var bone := record_bones[index]
		var span := maxf(highs[bone] - lows[bone], 0.01)
		var band := clampi(int((record_h[index] - lows[bone]) / span
			* float(AXIAL_BANDS)), 0, AXIAL_BANDS - 1)
		var bucket := int((record_angle[index] + PI) / TAU * float(ANGLE_BUCKETS)) \
			% ANGLE_BUCKETS
		var cell := bone * CELLS + band * ANGLE_BUCKETS + bucket
		peaks[cell] = maxf(peaks[cell], record_radius[index])
	var profiles := {}
	for bone in bone_count:
		if lows[bone] == INF:
			continue
		var peak := 0.0
		for band in AXIAL_BANDS:
			for bucket in ANGLE_BUCKETS:
				peak = maxf(peak, peaks[bone * CELLS + band * ANGLE_BUCKETS + bucket])
		if peak <= 0.0:
			continue
		profiles[bone] = {
			"kind": "bone",
			"skeleton": skeleton,
			"index": bone,
			"name": skeleton.get_bone_name(bone),
			"axis": axes[bone],
			"u": ups[bone],
			"v": widths[bone],
			"length": maxf(highs[bone] - lows[bone], 0.01),
			"low": lows[bone],
			"high": highs[bone],
			"peak": peak,
			"radii": peaks.slice(bone * CELLS, bone * CELLS + CELLS),
		}
	return {"bones": profiles}

## Rest-pose radius of the measured shell at a height along the bone axis and a
## specific angle, interpolated only across cells that actually hold cloth.
## Negative means the blow has no fabric under it.
static func _shell_radius(carrier: Dictionary, h: float, angle: float) -> float:
	var low: float = carrier.low
	var high: float = carrier.high
	var span := maxf(high - low, 0.01)
	var band_f := clampf((h - low) / span * float(AXIAL_BANDS) - 0.5, 0.0,
		float(AXIAL_BANDS - 1))
	var bucket_f := (angle + PI) / TAU * float(ANGLE_BUCKETS)
	if bucket_f < 0.0:
		bucket_f += float(ANGLE_BUCKETS)
	var band_a := int(floor(band_f))
	var band_b := mini(band_a + 1, AXIAL_BANDS - 1)
	var bucket_a := int(floor(bucket_f)) % ANGLE_BUCKETS
	var bucket_b := (bucket_a + 1) % ANGLE_BUCKETS
	var radii: PackedFloat32Array = carrier.radii
	var outermost := -1.0
	for corner in 4:
		var band := band_b if corner >= 2 else band_a
		var bucket := bucket_b if corner % 2 == 1 else bucket_a
		outermost = maxf(outermost, radii[band * ANGLE_BUCKETS + bucket])
	if outermost > 0.0:
		return outermost
	# Sparse seam: carry the nearest measured cell across the gap so a patch edge
	# never collapses into the bone. Past that the cloth really is absent.
	var found := _nearest_cell(carrier, band_a, bucket_a)
	if found >= 0:
		return radii[found]
	return float(carrier.peak)

static func _nearest_cell(carrier: Dictionary, band: int, bucket: int) -> int:
	var radii: PackedFloat32Array = carrier.radii
	var best := -1
	var best_distance := 0.0
	for reach in range(1, 4):
		for offset_band in range(-reach, reach + 1):
			for offset_bucket in range(-reach, reach + 1):
				if maxi(absi(offset_band), absi(offset_bucket)) != reach:
					continue
				var band_index := band + offset_band
				if band_index < 0 or band_index >= AXIAL_BANDS:
					continue
				var bucket_index := (bucket + offset_bucket + ANGLE_BUCKETS) \
					% ANGLE_BUCKETS
				var cell := band_index * ANGLE_BUCKETS + bucket_index
				if radii[cell] <= 0.0:
					continue
				var distance := sqrt(float(offset_band * offset_band) * 2.0 \
					+ float(offset_bucket * offset_bucket))
				if best < 0 or distance < best_distance:
					best = cell
					best_distance = distance
		if best >= 0:
			return best
	return -1

static func _nearest_bone(body: Dictionary, at_world: Vector3) -> Dictionary:
	var skeleton: Skeleton3D = body.skeleton
	if not is_instance_valid(skeleton):
		return {}
	var best: Dictionary = {}
	var best_score := INF
	for profile in body.bones.values():
		var carrier: Dictionary = profile
		var posed: Transform3D = skeleton.global_transform \
			* skeleton.get_bone_global_pose(int(carrier.index))
		var origin := posed.origin
		var direction: Vector3 = posed.basis * (carrier.axis as Vector3)
		var length := maxf(float(carrier.length), 0.02)
		var tip := origin + direction.normalized() * length
		var distance := _segment_distance(at_world, origin, tip)
		if distance < best_score:
			best_score = distance
			best = carrier
	return best

static func _segment_distance(point: Vector3, from: Vector3, to: Vector3) -> float:
	var span := to - from
	var length_squared := span.length_squared()
	if length_squared < 0.000001:
		return point.distance_to(from)
	var t := clampf((point - from).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(from + span * t)

# --- primitive rigs --------------------------------------------------------

static func _primitive_list(meshes: Array) -> Array:
	var primitives: Array = []
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if not mesh_node.is_visible_in_tree():
			continue
		var box := mesh_node.get_aabb()
		primitives.append({
			"kind": "primitive",
			"node": mesh_node,
			"name": str(mesh_node.name),
			"center": box.get_center(),
			"half": box.size * 0.5,
			"radius": box.size.length() * 0.25,
			"tris": PackedVector3Array(),
		})
	return primitives

static func _nearest_primitive(body: Dictionary, at_world: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for primitive in body.primitives:
		var carrier: Dictionary = primitive
		var node: Node3D = carrier.node
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var center: Vector3 = node.global_transform * (carrier.center as Vector3)
		var reach := maxf(float(carrier.radius), 0.02)
		var distance := at_world.distance_to(center) - reach
		if distance < best_distance:
			best_distance = distance
			best = carrier
	return best

static func _primitive_tris(carrier: Dictionary) -> PackedVector3Array:
	var cached: PackedVector3Array = carrier.tris
	if not cached.is_empty():
		return cached
	var node: MeshInstance3D = carrier.node
	if not is_instance_valid(node) or node.mesh == null:
		return cached
	var tris := PackedVector3Array()
	for surface in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(surface)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		if vertices == null:
			continue
		var points: PackedVector3Array = vertices
		if indices == null:
			for index in range(0, points.size() - 2, 3):
				tris.append(points[index])
				tris.append(points[index + 1])
				tris.append(points[index + 2])
		else:
			var order: PackedInt32Array = indices
			for index in range(0, order.size() - 2, 3):
				tris.append(points[order[index]])
				tris.append(points[order[index + 1]])
				tris.append(points[order[index + 2]])
	carrier.tris = tris
	return tris

static func _closest_on_triangles(tris: PackedVector3Array, point: Vector3) -> Dictionary:
	var best := Vector3.ZERO
	var best_normal := Vector3.UP
	var best_distance := INF
	var index := 0
	while index + 2 < tris.size():
		var a := tris[index]
		var b := tris[index + 1]
		var c := tris[index + 2]
		var candidate := _closest_on_triangle(point, a, b, c)
		var distance := point.distance_squared_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
			best_normal = (b - a).cross(c - a)
		index += 3
	if best_distance == INF:
		return {}
	if best_normal.length_squared() < 0.000001:
		best_normal = Vector3.UP
	return {"point": best, "normal": best_normal.normalized(),
		"distance": sqrt(best_distance)}

static func _closest_on_triangle(point: Vector3, a: Vector3, b: Vector3,
		c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)

# --- shared helpers --------------------------------------------------------

## Only the visible skinned cloth identifies a measurement: an armor swap
## invalidates the profile, while a raised bow, a dropped weapon or a corpse's
## death pose does not. Primitive rigs never change their shell.
static func _signature(rig: Node3D) -> int:
	var skeleton := _find_skeleton(rig)
	if skeleton == null:
		return 0
	var value := 17
	for node in _mesh_instances(rig):
		var mesh_node := node as MeshInstance3D
		if mesh_node.skin == null or not mesh_node.is_visible_in_tree():
			continue
		value = (value * 33 + str(mesh_node.name).hash()) % 2147483647
	return value

static func _mesh_instances(rig: Node3D) -> Array:
	var ignored: Array[Node] = []
	if rig.has_method("weapon_anchor"):
		var held = rig.weapon_anchor()
		if is_instance_valid(held):
			ignored.append(held)
	for property in ["_melee_weapon", "_bow"]:
		var held = rig.get(property)
		if is_instance_valid(held):
			ignored.append(held as Node)
	var found: Array = []
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var skip := false
		for root in ignored:
			if root == mesh_node or (is_instance_valid(root) and root.is_ancestor_of(mesh_node)):
				skip = true
				break
		if not skip:
			found.append(mesh_node)
	return found

## Imported GLB skins bind by bone name and leave `bind_bone` unset, so the
## vertex bone index has to be resolved through the skeleton itself.
static func _bind_map(skin: Skin, skeleton: Skeleton3D) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(maxi(skin.get_bind_count(), skeleton.get_bone_count()))
	for index in map.size():
		var bone := -1
		if index < skin.get_bind_count():
			bone = skin.get_bind_bone(index)
			if bone < 0:
				var bone_name := skin.get_bind_name(index)
				if not bone_name.is_empty():
					bone = skeleton.find_bone(bone_name)
		if bone < 0 and index < skeleton.get_bone_count():
			bone = index
		map[index] = bone
	return map

static func _find_skeleton(rig: Node3D) -> Skeleton3D:
	if rig is Skeleton3D:
		return rig as Skeleton3D
	var found := rig.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null

static func _prune() -> void:
	if _cache.size() <= CACHE_LIMIT:
		return
	for key in _cache.keys():
		var entry: Dictionary = _cache[key]
		if not is_instance_valid(entry.rig):
			_cache.erase(key)
