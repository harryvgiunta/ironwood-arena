extends SceneTree

## Imported-asset, presentation, gameplay and world-placement coverage for the
## five devil mobs. The GLBs are loaded dynamically so a missing asset reports
## a clear failure instead of aborting the test at parse time.

const Visual = preload("res://scripts/devil_mob_visual.gd")
const Mob = preload("res://scripts/devil_mob.gd")
const MobLod = preload("res://scripts/mob_lod.gd")

const MOBS := {
	"hell_goat": {
		"scene": "res://assets/characters/devils/ironwood_hell_goat.glb",
		"json": "res://assets/characters/devils/ironwood_hell_goat.json",
		"clips": {
			"idle": "HellGoat_Idle_Loop", "walk": "HellGoat_Walk_Loop",
			"run": "HellGoat_Run_Loop", "attack": "HellGoat_Attack",
			"hit": "HellGoat_Hit", "death": "HellGoat_Death",
		},
		"durations": [2.5, 1.333, 0.667, 1.45, 0.5, 1.25],
		"height": [1.95, 2.10], "span": [1.9, 2.2],
		"kind": 3, "display": "Hellish goat man",
	},
	"succubus": {
		"scene": "res://assets/characters/devils/ironwood_succubus.glb",
		"json": "res://assets/characters/devils/ironwood_succubus.json",
		"clips": {
			"idle": "Succubus_Idle_Loop", "walk": "Succubus_Walk_Loop",
			"run": "Succubus_Run_Loop", "attack": "Succubus_Attack",
			"hit": "Succubus_Hit", "death": "Succubus_Death",
		},
		"durations": [2.5, 1.333, 0.667, 1.35, 0.45, 1.2],
		"height": [2.0, 2.2], "span": [2.1, 2.5],
		"kind": 4, "display": "Succubus",
	},
	"spawn": {
		"scene": "res://assets/characters/devils/ironwood_spawn.glb",
		"json": "res://assets/characters/devils/ironwood_spawn.json",
		"clips": {
			"idle": "Spawn_Idle_Loop", "walk": "Spawn_Walk_Loop",
			"run": "Spawn_Run_Loop", "attack": "Spawn_Attack",
			"hit": "Spawn_Hit", "death": "Spawn_Death",
		},
		"durations": [2.933, 2.0, 0.667, 1.1, 0.4, 1.0],
		"height": [1.0, 1.2], "span": [0.8, 1.1],
		"kind": 5, "display": "Devil spawn",
	},
	"beast": {
		"scene": "res://assets/characters/devils/ironwood_beast.glb",
		"json": "res://assets/characters/devils/ironwood_beast.json",
		"clips": {
			"idle": "Beast_Idle_Loop", "walk": "Beast_Walk_Loop",
			"run": "Beast_Run_Loop", "attack": "Beast_Attack",
			"hit": "Beast_Hit", "death": "Beast_Death",
		},
		"durations": [2.4, 0.6, 0.6, 1.6, 0.5, 0.45],
		"height": [1.6, 1.9], "span": [2.8, 3.2],
		"kind": 6, "display": "Hell beast",
	},
	"gargoyle": {
		"scene": "res://assets/characters/devils/ironwood_gargoyle.glb",
		"json": "res://assets/characters/devils/ironwood_gargoyle.json",
		"clips": {
			"idle": "Gargoyle_Idle_Loop", "walk": "Gargoyle_Walk_Loop",
			"run": "Gargoyle_Run_Loop", "attack": "Gargoyle_Attack",
			"hit": "Gargoyle_Hit", "death": "Gargoyle_Death",
		},
		"durations": [2.5, 1.333, 0.933, 1.8, 0.5, 1.4],
		"height": [3.2, 3.45], "span": [2.8, 3.5],
		"kind": 7, "display": "Gargoyle",
	},
}

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
	world_root.name = "DevilTestWorld"
	root.add_child(world_root)
	for mob_id in MOBS:
		await _check_asset(world_root, mob_id)
		await _check_visual(world_root, mob_id)
		await _check_ground_contact(world_root, mob_id)
		await _check_gameplay(world_root, mob_id)
	await _check_ai_approach(world_root)
	await _check_frontier_instances(world_root)
	print("DEVIL_MOBS_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_asset(world_root: Node3D, mob_id: String) -> void:
	var spec: Dictionary = MOBS[mob_id]
	var packed := load(str(spec.scene)) as PackedScene
	check(packed != null, "Missing devil GLB: " + str(spec.scene))
	if packed == null:
		return
	var instance := packed.instantiate()
	world_root.add_child(instance)
	await process_frame
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh := instance.find_child("HellGoatMesh", true, false) as MeshInstance3D
	if mesh == null:
		for child in instance.find_children("*", "MeshInstance3D", true, false):
			mesh = child as MeshInstance3D
			break
	check(player != null, mob_id + " has an AnimationPlayer")
	check(skeleton != null, mob_id + " has a Skeleton3D")
	check(mesh != null, mob_id + " has a skinned MeshInstance3D")
	if player and skeleton and mesh:
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
				var loops: bool = player.get_animation(clip_name).loop_mode == Animation.LOOP_LINEAR
				check(loops == (key in ["idle", "walk", "run"]), mob_id + " loop mode for " + clip_name)
		var bone_count := skeleton.get_bone_count()
		check(bone_count >= 24 and bone_count <= 96, mob_id + " bone count is in budget (found %d)" % bone_count)
		for bone in ["root", "pelvis", "head", "jaw"]:
			check(skeleton.find_bone(bone) >= 0, mob_id + " has bone " + bone)
		var head_bone := skeleton.find_bone("head")
		if head_bone >= 0:
			var head_rest := skeleton.get_bone_global_rest(head_bone).origin
			check(head_rest.z < -0.02, mob_id + " head sits on the gameplay -Z forward side")
			check(head_rest.y > 0.45, mob_id + " head sits above the pelvis")
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
		check(bounds.position.y > -0.08 and bounds.position.y < 0.08,
			"%s rest sole sits near the ground (%.3f)" % [mob_id, bounds.position.y])
		check(bounds.size.y >= float(spec.height[0]) and bounds.size.y <= float(spec.height[1]),
			"%s height %.3f stays in range" % [mob_id, bounds.size.y])
		check(maxf(bounds.size.x, bounds.size.z) >= float(spec.span[0])
			and maxf(bounds.size.x, bounds.size.z) <= float(spec.span[1]),
			"%s footprint %.3f stays in range" % [mob_id, maxf(bounds.size.x, bounds.size.z)])
		var materials: Array[StandardMaterial3D] = []
		for surface in mesh.mesh.get_surface_count():
			var candidate := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if candidate != null:
				materials.append(candidate)
		check(not materials.is_empty(), mob_id + " has standard materials")
		var has_albedo := false
		var has_normal := false
		var has_roughness := false
		for candidate in materials:
			has_albedo = has_albedo or candidate.albedo_texture != null
			has_normal = has_normal or (candidate.normal_enabled and candidate.normal_texture != null)
			has_roughness = has_roughness or candidate.roughness_texture != null
		check(has_albedo, mob_id + " has an albedo map")
		check(has_normal, mob_id + " has a normal map")
		check(has_roughness, mob_id + " has a roughness map")
	# Adjacent metadata must describe the same deliverable.
	var metadata_text := FileAccess.get_file_as_string(str(spec.json))
	check(not metadata_text.is_empty(), "Missing metadata JSON for " + mob_id)
	if not metadata_text.is_empty():
		var metadata = JSON.parse_string(metadata_text)
		check(metadata is Dictionary, mob_id + " metadata parses")
		if metadata is Dictionary:
			check(str(metadata.get("mob", "")) == mob_id, mob_id + " metadata mob id matches")
			check(int(metadata.get("mesh_triangles", 0)) >= 12000, mob_id + " triangle budget")
			check(int(metadata.get("embedded_images", 0)) >= 4, mob_id + " embeds at least four images")
	instance.queue_free()
	await process_frame


func _check_visual(world_root: Node3D, mob_id: String) -> void:
	var visual = Visual.new()
	visual.mob_id = mob_id
	visual.profile = Mob.PROFILES[mob_id]
	world_root.add_child(visual)
	await process_frame
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.idle, mob_id + " first plays idle")
	visual.set_motion(Vector3(1.2, 0.0, 0.0), true)
	visual.set_combat("CIRCLE", 0.0)
	await process_frame
	check(visual.get_clip_name() == MOBS[mob_id].clips.walk, mob_id + " low speed selects walk")
	visual.set_motion(Vector3(4.5, 0.0, 0.0), true)
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
	check(head.y > 0.4, mob_id + " head hitbox follows the head bone")
	var profile := visual.head_hit_profile()
	check(profile.x > 0.1 and profile.y > 0.05, mob_id + " head hit profile is non-degenerate")
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
	# The authored overlays are applied per baked frame. A pelvis offset written
	# through `pose_bone.matrix` reads the previous frame's pose, compounds on
	# every key and drops the mob through the terrain while it stands idle; the
	# rest-pose bounds check cannot see that. Sample the deformed mesh across
	# each locomotion loop instead: claws stay on the floor and the loop does
	# not ride down or up between its first and last frame.
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
			check(floor_y >= -0.15 and floor_y <= 0.40,
				"%s %s keeps its claws near the floor (%.3f at %.2fs)" % [
					mob_id, clip_name, floor_y, length * float(step) / 4.0])
		check(absf(last - first) <= 0.08,
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
	# A stationary player six metres away must pull an orbiting devil into its
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
	for mob_id in ["hell_goat", "succubus", "spawn"]:
		var mob = Mob.new()
		mob.mob_id = mob_id
		mob.player = target
		mob.safe_center = Vector3(200.0, 0.0, 200.0)
		mob.position = Vector3(0.0, 0.2, 0.0)
		world_root.add_child(mob)
		var entered_attack := false
		var closest := 99.0
		for frame in 150:
			await physics_frame
			if not is_instance_valid(mob) or not mob.alive:
				break
			closest = minf(closest, Vector2(mob.global_position.x - target.global_position.x,
				mob.global_position.z - target.global_position.z).length())
			if str(mob.state) in ["WINDUP", "STRIKE", "RECOVER"]:
				entered_attack = true
				break
		check(entered_attack or closest < float(Mob.PROFILES[mob_id].reach) + 1.2,
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
		check(world.devil_spawns.size() == 16, "devil court has 16 authored placements")
		var counts := {}
		for record in world.devil_spawns:
			var mob_id := str(record.get("mob", ""))
			counts[mob_id] = int(counts.get(mob_id, 0)) + 1
			check(MOBS.has(mob_id), "devil spawn references a known mob: " + mob_id)
			check(record.has("position"), "devil spawn has a terrain position")
		for mob_id in MOBS:
			check(int(counts.get(mob_id, 0)) >= 2, mob_id + " appears at least twice in the frontier")
	var devils := get_nodes_in_group("devil_mobs")
	check(devils.size() == 16, "frontier spawns 16 live devil mobs (found %d)" % devils.size())
	var kinds := {}
	var shown := 0
	var released := 0
	for devil in devils:
		kinds[int(devil.get("kind"))] = true
		# A rig exists only while the body is close enough to be seen: past
		# `MobLod.RELEASE_RANGE` the presentation subtree is freed outright,
		# because a skinned body costs about fourteen microseconds a frame just
		# by existing. It is rebuilt when the ranger comes back.
		var range: float = devil.global_position.distance_to(frontier.player.global_position)
		if range <= MobLod.ANIMATE_RANGE:
			check(is_instance_valid(devil.get("_visual")),
				"a frontier devil in view has an imported visual")
			shown += 1
		elif range > MobLod.RELEASE_RANGE:
			check(not is_instance_valid(devil.get("_visual")),
				"a frontier devil beyond the release range carries no rig")
			released += 1
	check(shown > 0, "the frontier fields devils in view")
	check(released > 0, "the far frontier releases its devil rigs")
	for expected in [3, 4, 5, 6, 7]:
		check(kinds.has(expected), "frontier includes devil kind %d" % expected)
	# Starting court: one of each species must be inside the safe ring, on
	# screen from the south-gate spawn, and still idle after a second.
	var spawn_point: Vector3 = frontier.player.global_position
	var starting := []
	for devil in devils:
		if devil.global_position.distance_to(spawn_point) < 15.0:
			starting.append(devil)
	check(starting.size() == 5, "starting court has one mob of each species (found %d)" % starting.size())
	var starting_ids := {}
	for devil in starting:
		starting_ids[str(devil.get("mob_id"))] = true
	for mob_id in MOBS:
		check(starting_ids.has(mob_id), mob_id + " is visible in the starting court")
	for frame in 60:
		await physics_frame
	for devil in starting:
		check(str(devil.get("state")) not in ["WINDUP", "STRIKE", "RECOVER"],
			str(devil.get("mob_id")) + " stays idle inside the safe ring")
		var camera: Camera3D = frontier.camera
		if camera != null:
			check(camera.is_position_in_frustum(devil.get_aim_position()),
				str(devil.get("mob_id")) + " is inside the spawn camera frustum")
	# ...and gets it back: a released body that comes into range rebuilds its
	# rig, because a rig that never returns would be an invisible monster.
	var away := []
	for devil in devils:
		if not is_instance_valid(devil.get("_visual")):
			away.append(devil)
	if not away.is_empty():
		var returning = away[0]
		returning.global_position = frontier.player.global_position + Vector3(6.0, 0.0, 4.0)
		for frame in 12:
			await physics_frame
		check(is_instance_valid(returning.get("_visual")),
			"a released devil rebuilds its rig when it comes back into range")
		check(returning.get("_visual").get_clip_name() != "",
			"the rebuilt rig is playing a clip")
		check(not bool(returning.get("skip_tick")),
			"a devil back in relevance resumes its tick")
	# Distant bodies are not ticked at all; the scene decides that, not the body,
	# because the check used to cost more than the work it skipped.
	var culled := []
	for devil in devils:
		if is_instance_valid(devil) and bool(devil.get("skip_tick")):
			culled.append(devil)
	check(culled.size() > 0, "distant devils stop ticking")
	if not culled.is_empty():
		var woken = culled[0]
		woken.global_position = frontier.player.global_position + Vector3(-5.0, 0.0, 3.0)
		for frame in 20:
			await physics_frame
		check(not bool(woken.get("skip_tick")),
			"a culled devil resumes when a ranger comes near")
	frontier.queue_free()
	await process_frame
