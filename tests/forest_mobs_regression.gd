extends SceneTree

## Imported-asset, presentation, gameplay and world-placement coverage for the
## three Unholy Forest mobs. The GLBs are loaded dynamically so a missing asset
## reports a clear failure instead of aborting the test at parse time.

const Visual = preload("res://scripts/forest_mob_visual.gd")
const Mob = preload("res://scripts/forest_mob.gd")
const MobLod = preload("res://scripts/mob_lod.gd")

const MOBS := {
	"hollow_warden": {
		"scene": "res://assets/characters/forest/ironwood_hollow_warden.glb",
		"json": "res://assets/characters/forest/ironwood_hollow_warden.json",
		"clips": {
			"idle": "Warden_Idle", "walk": "Warden_Walk",
			"run": "Warden_Run", "attack": "Warden_Attack",
			"hit": "Warden_Hit", "death": "Warden_Death",
		},
		"durations": [2.8, 1.4, 0.8, 1.6, 0.5, 1.45],
		# The antler rack is part of the silhouette: this mob has to be
		# unmistakably taller than a ranger before it is even close.
		"height": [3.3, 4.1], "span": [1.4, 2.3],
		"kind": 9, "display": "Hollow warden", "emissive": true,
	},
	"ossuary_stalker": {
		"scene": "res://assets/characters/forest/ironwood_ossuary_stalker.glb",
		"json": "res://assets/characters/forest/ironwood_ossuary_stalker.json",
		"clips": {
			"idle": "Stalker_Idle", "walk": "Stalker_Walk",
			"run": "Stalker_Run", "attack": "Stalker_Attack",
			"hit": "Stalker_Hit", "death": "Stalker_Death",
		},
		"durations": [2.4, 1.1, 0.7, 1.25, 0.4, 1.1],
		"height": [2.3, 2.75], "span": [0.8, 1.3],
		"kind": 10, "display": "Ossuary stalker", "emissive": false,
	},
	"gallowsroot": {
		"scene": "res://assets/characters/forest/ironwood_gallowsroot.glb",
		"json": "res://assets/characters/forest/ironwood_gallowsroot.json",
		"clips": {
			"idle": "Gallowsroot_Idle", "walk": "Gallowsroot_Walk",
			"run": "Gallowsroot_Run", "attack": "Gallowsroot_Attack",
			"hit": "Gallowsroot_Hit", "death": "Gallowsroot_Death",
		},
		"durations": [3.2, 1.8, 1.0, 2.1, 0.6, 1.8],
		"height": [2.6, 3.1], "span": [1.1, 1.7],
		"kind": 11, "display": "Gallowsroot", "emissive": true,
	},
}

## Surface types the mobset must deliver across its materials. Each mob carries
## a subset; together they cover the whole authored set.
const SURFACE_NAMES := ["forest_bark", "forest_cloth", "forest_leather", "forest_bone",
	"forest_antler", "forest_moss", "forest_void", "forest_ember"]

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	var world_root := Node3D.new()
	world_root.name = "ForestTestWorld"
	root.add_child(world_root)
	for mob_id in MOBS:
		await _check_asset(world_root, mob_id)
		await _check_visual(world_root, mob_id)
		await _check_ground_contact(world_root, mob_id)
		await _check_gameplay(world_root, mob_id)
	await _check_ai_approach(world_root)
	await _check_frontier_instances(world_root)
	print("FOREST_MOBS_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_asset(world_root: Node3D, mob_id: String) -> void:
	var spec: Dictionary = MOBS[mob_id]
	var packed := load(str(spec.scene)) as PackedScene
	check(packed != null, "Missing forest GLB: " + str(spec.scene))
	if packed == null:
		return
	var instance := packed.instantiate()
	world_root.add_child(instance)
	await process_frame
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh: MeshInstance3D = null
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var candidate := child as MeshInstance3D
		if candidate.skin != null:
			mesh = candidate
			break
	check(player != null, mob_id + " has an AnimationPlayer")
	check(skeleton != null, mob_id + " has a Skeleton3D")
	check(mesh != null, mob_id + " has a skinned MeshInstance3D")
	if player == null or skeleton == null or mesh == null:
		instance.queue_free()
		return
	var names := player.get_animation_list()
	check(names.size() == 6, mob_id + " exports exactly six clips (found %d)" % names.size())
	for key in spec.clips:
		var clip_name: String = spec.clips[key]
		check(clip_name in names, mob_id + " has clip " + clip_name)
		if clip_name in names:
			var duration: float = player.get_animation(clip_name).length
			var expected := float(spec.durations[["idle", "walk", "run", "attack", "hit", "death"].find(key)])
			check(absf(duration - expected) < 0.08,
				"%s %s duration %.3f is close to %.3f" % [mob_id, clip_name, duration, expected])
	var bone_count := skeleton.get_bone_count()
	check(bone_count >= 24 and bone_count <= 96, mob_id + " bone count is in budget (found %d)" % bone_count)
	for bone in ["root", "pelvis", "head", "jaw"]:
		check(skeleton.find_bone(bone) >= 0, mob_id + " has bone " + bone)
	var head_bone := skeleton.find_bone("head")
	if head_bone >= 0:
		var head_rest := skeleton.get_bone_global_rest(head_bone).origin
		# -Z is gameplay forward, so the head must sit on the forward side.
		check(head_rest.z < -0.015, mob_id + " head sits on the gameplay -Z forward side")
		check(head_rest.y > 0.7, mob_id + " head sits above the pelvis")
	var root_bone := skeleton.find_bone("root")
	if root_bone >= 0:
		for key in spec.clips:
			var clip_name: String = spec.clips[key]
			var length: float = player.get_animation(clip_name).length
			for time in [0.0, length * 0.5, length]:
				player.play(clip_name)
				player.seek(time, true)
				player.pause()
				await process_frame
				skeleton.force_update_all_bone_transforms()
				check(skeleton.get_bone_global_pose(root_bone).origin.length() < 0.001,
					"%s %s keeps its root bone stationary" % [mob_id, clip_name])
	var bounds := mesh.get_aabb()
	check(bounds.position.y > -0.05 and bounds.position.y < 0.08,
		"%s rest sole sits near the ground (%.3f)" % [mob_id, bounds.position.y])
	check(bounds.size.y >= float(spec.height[0]) and bounds.size.y <= float(spec.height[1]),
		"%s height %.3f stays in range" % [mob_id, bounds.size.y])
	check(maxf(bounds.size.x, bounds.size.z) >= float(spec.span[0])
		and maxf(bounds.size.x, bounds.size.z) <= float(spec.span[1]),
		"%s footprint %.3f stays in range" % [mob_id, maxf(bounds.size.x, bounds.size.z)])
	var materials: Array[StandardMaterial3D] = []
	var surface_names := []
	for surface in mesh.mesh.get_surface_count():
		var candidate := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		if candidate != null:
			materials.append(candidate)
			surface_names.append(candidate.resource_name.to_lower())
	check(not materials.is_empty(), mob_id + " has standard materials")
	for name in surface_names:
		check(name in SURFACE_NAMES, mob_id + " uses only authored surfaces (found " + name + ")")
	var has_albedo := false
	var has_normal := false
	var has_roughness := false
	var has_emissive := false
	for candidate in materials:
		has_albedo = has_albedo or candidate.albedo_texture != null
		has_normal = has_normal or (candidate.normal_enabled and candidate.normal_texture != null)
		has_roughness = has_roughness or candidate.roughness_texture != null
		has_emissive = has_emissive or (candidate.emission_enabled and candidate.emission_texture != null)
	check(has_albedo, mob_id + " has an albedo map")
	check(has_normal, mob_id + " has a normal map")
	check(has_roughness, mob_id + " has a roughness map")
	# The warden and the root burn from inside; the stalker's sockets are empty
	# black pits by design, so emission is a per-mob property, not a rule.
	check(has_emissive == bool(spec.get("emissive", false)),
		mob_id + " emissive surfaces match its design")
	# Adjacent metadata must describe the same deliverable.
	var metadata_text := FileAccess.get_file_as_string(str(spec.json))
	check(not metadata_text.is_empty(), "Missing metadata JSON for " + mob_id)
	if not metadata_text.is_empty():
		var metadata = JSON.parse_string(metadata_text)
		check(metadata is Dictionary, mob_id + " metadata parses")
		if metadata is Dictionary:
			check(str(metadata.get("mob", "")) == mob_id, mob_id + " metadata mob id matches")
			check(int(metadata.get("mesh_triangles", 0)) >= 25000, mob_id + " triangle budget")
			check(int(metadata.get("embedded_images", 0)) >= 12, mob_id + " embeds its PBR sets")
			var measured_min: Array = metadata.get("rest_bounds_min", [])
			var measured_max: Array = metadata.get("rest_bounds_max", [])
			if measured_min.size() == 3 and measured_max.size() == 3:
				var measured_height := float(measured_max[1]) - float(measured_min[1])
				check(absf(measured_height - bounds.size.y) < 0.06,
					"%s measured height agrees with the imported mesh" % mob_id)
			var clips: Dictionary = metadata.get("clips", {})
			for key in spec.clips:
				var entry: Dictionary = clips.get(key, {})
				check(str(entry.get("name", "")) == str(spec.clips[key]),
					mob_id + " metadata names clip " + str(spec.clips[key]))
			check(float(metadata.get("root_translation_drift", 1.0)) <= 0.001,
				mob_id + " keeps its root translation constant across every clip")
	instance.queue_free()
	await process_frame


func _check_visual(world_root: Node3D, mob_id: String) -> void:
	var visual = Visual.new()
	visual.mob_id = mob_id
	visual.profile = Mob.FOREST_PROFILES[mob_id]
	world_root.add_child(visual)
	await process_frame
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.idle, mob_id + " first plays idle")
	# Loop semantics are the controller's: the glTF importer is not trusted to
	# carry them, and Godot strips suffix-based hints from animation names.
	for key in ["idle", "walk", "run"]:
		var anim: Animation = visual._player.get_animation(MOBS[mob_id].clips[key])
		check(anim.loop_mode == Animation.LOOP_LINEAR,
			mob_id + " forces " + str(MOBS[mob_id].clips[key]) + " to loop")
	for key in ["attack", "hit", "death"]:
		var one_shot: Animation = visual._player.get_animation(MOBS[mob_id].clips[key])
		check(one_shot.loop_mode == Animation.LOOP_NONE,
			mob_id + " holds " + str(MOBS[mob_id].clips[key]) + " as a one-shot")
	visual.set_motion(Vector3(1.2, 0.0, 0.0), true)
	visual.set_combat("CIRCLE", 0.0)
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.walk, mob_id + " low speed selects walk")
	visual.set_motion(Vector3(5.2, 0.0, 0.0), true)
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.run, mob_id + " high speed selects run")
	visual.set_motion(Vector3.ZERO, true)
	visual.set_combat("WINDUP", 0.1)
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.attack, mob_id + " windup selects attack")
	visual.set_combat("STAGGER", 0.0)
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.hit, mob_id + " stagger selects hit")
	visual.die()
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.death, mob_id + " death selects the death clip")
	var head := visual.head_hitbox_center()
	check(head.y > 0.7, mob_id + " head hitbox follows the head bone")
	var profile := visual.head_hit_profile()
	check(profile.x > 0.1 and profile.y > 0.05, mob_id + " head hit profile is non-degenerate")
	check(is_instance_valid(visual.blood_anchor()), mob_id + " exposes a skinned blood anchor")
	visual.queue_free()
	await process_frame


## Lowest skinned vertex of the imported mesh, in the asset's own space.
func deformed_floor(instance: Node3D, skeleton: Skeleton3D) -> float:
	var lowest := INF
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.skin == null:
			continue
		var skin := mesh_instance.skin
		var bones: PackedInt32Array = []
		var binds: Array[Transform3D] = []
		for index in skin.get_bind_count():
			bones.append(skeleton.find_bone(skin.get_bind_name(index)))
			binds.append(skin.get_bind_pose(index))
		var transforms: Array[Transform3D] = []
		for index in bones.size():
			transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bones[index]) * binds[index])
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_BONES] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			if vertices.is_empty() or joints.is_empty():
				continue
			var influences := joints.size() / vertices.size()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				for influence in influences:
					var slot := vertex * influences + influence
					if weights[slot] > 0.0:
						point += (transforms[joints[slot]] * vertices[vertex]) * weights[slot]
				lowest = minf(lowest, point.y)
	return lowest


func _check_ground_contact(world_root: Node3D, mob_id: String) -> void:
	# The authored overlays are applied per baked frame, so a bad pelvis offset
	# can sink a mob through the terrain while the rest pose still looks right.
	# Sample the deformed mesh across each locomotion loop instead.
	var packed := load(str(MOBS[mob_id].scene)) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	world_root.add_child(instance)
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if player == null or skeleton == null:
		instance.queue_free()
		return
	for key in ["idle", "walk", "run"]:
		var clip_name := str(MOBS[mob_id].clips[key])
		var length := player.get_animation(clip_name).length
		var first := 0.0
		var last := 0.0
		for step in 5:
			player.play(clip_name, 0.0)
			player.seek(length * float(step) / 4.0, true)
			await process_frame
			await process_frame
			var floor_y := deformed_floor(instance, skeleton)
			if step == 0:
				first = floor_y
			last = floor_y
			check(floor_y >= -0.16 and floor_y <= 0.45,
				"%s %s keeps its lowest edge near the floor (%.3f at %.2fs)" % [
					mob_id, clip_name, floor_y, length * float(step) / 4.0])
		check(absf(last - first) <= 0.10,
			"%s %s holds its height across the loop (%.3f to %.3f)" % [mob_id, clip_name, first, last])
	instance.queue_free()
	await process_frame


func _check_gameplay(world_root: Node3D, mob_id: String) -> void:
	var spec: Dictionary = MOBS[mob_id]
	var player := CharacterBody3D.new()
	player.position = Vector3(0.0, 0.0, 3.0)
	world_root.add_child(player)
	var mob = Mob.new()
	mob.mob_id = mob_id
	mob.player = player
	mob.position = Vector3(0.0, 0.0, 0.0)
	world_root.add_child(mob)
	await process_frame
	await process_frame
	check(mob.kind == int(spec.kind), mob_id + " uses its own loot-parity kind")
	check(mob.max_health > 0.0, mob_id + " has health")
	check(mob.get_display_name() == str(spec.display), mob_id + " display name matches")
	check(mob.head_hit_profile().x > 0.1, mob_id + " exposes a head zone")
	check(mob.held_weapon_id() == "", mob_id + " is a natural-weapon mob")
	check(mob.is_in_group("forest_mobs"), mob_id + " joins the forest_mobs group")
	check(not mob.is_in_group("devil_mobs"), mob_id + " stays out of the devil group")
	var reward := [-1]
	mob.defeated.connect(func(_enemy: Node3D, value: int) -> void: reward[0] = value)
	mob.take_damage(99999.0, 0, false)
	await process_frame
	check(not mob.alive, mob_id + " dies at zero health")
	check(reward[0] > 0, mob_id + " pays gold on death")
	check(is_instance_valid(mob._visual) and mob._visual.is_dead(), mob_id + " holds its corpse pose")
	mob.queue_free()
	player.queue_free()
	await process_frame


func _check_ai_approach(world_root: Node3D) -> void:
	# A stationary player six metres away must pull an orbiting mob into its
	# attack trigger; an orbit-only AI would circle forever at `orbit` radius.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 1.0, 30.0)
	floor_shape.shape = box
	floor_body.position = Vector3(0.0, -0.5, -6.0)
	floor_body.add_child(floor_shape)
	world_root.add_child(floor_body)
	var target := CharacterBody3D.new()
	target.position = Vector3(0.0, 0.0, -6.0)
	world_root.add_child(target)
	for mob_id in ["hollow_warden", "ossuary_stalker"]:
		var mob = Mob.new()
		mob.mob_id = mob_id
		mob.player = target
		mob.safe_center = Vector3(200.0, 0.0, 200.0)
		mob.position = Vector3(0.0, 0.2, 0.0)
		world_root.add_child(mob)
		var entered_attack := false
		var closest := 99.0
		for frame in 220:
			await physics_frame
			if not is_instance_valid(mob) or not mob.alive:
				break
			closest = minf(closest, Vector2(mob.global_position.x - target.global_position.x,
				mob.global_position.z - target.global_position.z).length())
			if str(mob.state) in ["WINDUP", "STRIKE", "RECOVER"]:
				entered_attack = true
				break
		check(entered_attack or closest < float(Mob.FOREST_PROFILES[mob_id].reach) + 1.2,
			mob_id + " closes from six metres and reaches an attack state")
		mob.queue_free()
		await process_frame
	target.queue_free()
	floor_body.queue_free()
	await process_frame


func _check_frontier_instances(world_root: Node3D) -> void:
	var packed := load("res://main.tscn") as PackedScene
	check(packed != null, "main.tscn loads")
	if packed == null:
		return
	var frontier := packed.instantiate()
	world_root.add_child(frontier)
	await process_frame
	await process_frame
	var world = frontier.world
	check(world != null, "frontier exposes its generated world")
	if world != null:
		check(world.enemy_spawns.size() == 36, "existing enemy spawn contract remains 36")
		check(world.devil_spawns.size() == 16, "devil court remains 16 authored placements")
		check(world.forest_spawns.size() == 19, "the forest holds 19 authored placements (found %d)"
			% world.forest_spawns.size())
		var counts := {}
		for record in world.forest_spawns:
			var mob_id := str(record.get("mob", ""))
			counts[mob_id] = int(counts.get(mob_id, 0)) + 1
			check(MOBS.has(mob_id), "forest spawn references a known mob: " + mob_id)
			check(record.has("position"), "forest spawn has a terrain position")
		for mob_id in MOBS:
			check(int(counts.get(mob_id, 0)) >= 3, mob_id + " appears at least three times in the frontier")
	var forest_mobs := get_nodes_in_group("forest_mobs")
	check(forest_mobs.size() == 19,
		"frontier spawns 19 live forest mobs (found %d)" % forest_mobs.size())
	var kinds := {}
	var shown := 0
	var released := 0
	for mob in forest_mobs:
		kinds[int(mob.get("kind"))] = true
		# The rig exists only inside the release range; see `MobLod`.
		var range: float = mob.global_position.distance_to(frontier.player.global_position)
		if range <= MobLod.ANIMATE_RANGE:
			check(is_instance_valid(mob.get("_visual")),
				"a frontier forest mob in view has an imported visual")
			shown += 1
		elif range > MobLod.RELEASE_RANGE:
			check(not is_instance_valid(mob.get("_visual")),
				"a forest mob beyond the release range carries no rig")
			released += 1
	check(shown > 0, "the frontier fields forest mobs in view")
	check(released > 0, "the far forest releases its mob rigs")
	for expected in [9, 10, 11]:
		check(kinds.has(expected), "frontier includes forest kind %d" % expected)
	# Threshold trio: one of each species inside the safe ring, on screen from
	# the south-gate spawn, and still idle after a second.
	var spawn_point: Vector3 = frontier.player.global_position
	var threshold := []
	for mob in forest_mobs:
		if mob.global_position.distance_to(spawn_point) < 20.0:
			threshold.append(mob)
	check(threshold.size() == 3, "threshold trio has one mob of each species (found %d)" % threshold.size())
	var threshold_ids := {}
	for mob in threshold:
		threshold_ids[str(mob.get("mob_id"))] = true
	for mob_id in MOBS:
		check(threshold_ids.has(mob_id), mob_id + " is visible at the town threshold")
	for frame in 60:
		await physics_frame
	for mob in threshold:
		check(str(mob.get("state")) not in ["WINDUP", "STRIKE", "RECOVER"],
			str(mob.get("mob_id")) + " stays idle inside the safe ring")
		var camera: Camera3D = frontier.camera
		if camera != null:
			check(camera.is_position_in_frustum(mob.get_aim_position()),
				str(mob.get("mob_id")) + " is inside the spawn camera frustum")
	frontier.queue_free()
	await process_frame
