extends SceneTree
## A mob's motion must not inherit its think rate.
##
## Mobs decide on a stride — every fourth physics tick close by, every
## twenty-fourth at distance — because a brain that runs sixty times a second
## costs a frame. That is only acceptable while the *body* still moves every
## frame: a decimated tick used to carry the accumulated delta into the motion
## step, so a mid-range wolf advanced forty centimetres on every eighth frame
## and stood perfectly still in between. It reads as stutter on every monster
## in the game, and it is invisible to a still frame or a position assertion.
##
## This suite pins the invariant: over a run of frames a walking body advances
## on *every* frame, and by an even amount. It drives the real `devil_mob`
## family, the `enemy.gd` cinder devil and the ranger clone, at a distance that
## puts each on the coarse stride.

const Mob = preload("res://scripts/devil_mob.gd")
const ForestMob = preload("res://scripts/forest_mob.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Clone = preload("res://scripts/ranger_clone.gd")
const MobLod = preload("res://scripts/mob_lod.gd")

## Frames sampled per body.
const FRAMES := 90
## A step is "even" when no frame travels more than this multiple of the mean.
const EVEN_TOLERANCE := 2.4

var world_root: Node3D
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	world_root = Node3D.new()
	world_root.name = "MotionTestWorld"
	root.add_child(world_root)
	_build_floor()
	# The body stands far enough that its stride is coarse, which is exactly the
	# case the invariant is about.
	var player := _player(Vector3.ZERO)
	check(MobLod.stride_for(24.0, false) > 1,
		"a body at 24 m thinks on a coarse stride (%d ticks)" % MobLod.stride_for(24.0, false))

	await _check_body("succubus", player, 24.0, Mob)
	await _check_body("ossuary_stalker", player, 24.0, ForestMob)
	await _check_enemy(player, 24.0)
	await _check_clone(player, 24.0)

	world_root.queue_free()
	await process_frame
	print("MOB_MOTION_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	world_root.add_child(body)


func _player(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("alive", true)
	body.position = at
	world_root.add_child(body)
	return body


## Samples the per-frame planar displacement of one body while it walks.
func _sample(body: Node3D, frames: int = FRAMES) -> PackedFloat32Array:
	var steps := PackedFloat32Array()
	var previous := body.global_position
	for index in frames:
		await physics_frame
		var now := body.global_position
		steps.append(Vector2(now.x - previous.x, now.z - previous.z).length())
		previous = now
	return steps


## Every frame of a walk must travel, and by roughly the same amount.
func _assert_even(steps: PackedFloat32Array, label: String) -> void:
	var moving := 0
	var total := 0.0
	var worst := 0.0
	for step in steps:
		total += step
		worst = maxf(worst, step)
		if step > 0.0005:
			moving += 1
	if total <= 0.0:
		check(false, label + " never moved; the probe is not driving it")
		return
	var mean := total / float(steps.size())
	check(moving >= steps.size() - 2,
		"%s moves on every frame (%d of %d)" % [label, moving, steps.size()])
	check(worst <= mean * EVEN_TOLERANCE,
		"%s advances evenly (worst %.3f m against a mean of %.3f m)" % [label, worst, mean])


## A devil-family body closing on a ranger standing 24 m away.
func _check_body(mob_id: String, player: CharacterBody3D, distance: float,
		script) -> void:
	var mob = script.new()
	mob.mob_id = mob_id
	mob.player = player
	mob.safe_center = Vector3(9000.0, 0.0, 9000.0)
	mob.position = Vector3(0.0, 0.05, distance)
	world_root.add_child(mob)
	# A mob whose profile failed to load walks home to the origin and would pass
	# every check below for the wrong reason.
	check(not (mob.get("profile") as Dictionary).is_empty(),
		mob_id + " has a loaded profile before its motion is judged")
	player.global_position = Vector3.ZERO
	# Let it notice the ranger and settle into its chase before sampling.
	for index in 24:
		await physics_frame
	_assert_even(await _sample(mob), mob_id)
	mob.queue_free()
	await process_frame


## The legacy cinder devil, which owns its own motion path.
func _check_enemy(player: CharacterBody3D, distance: float) -> void:
	var enemy = Enemy.new()
	enemy.kind = 2
	enemy.pack_index = 0
	enemy.devil_weapon = "claw"
	enemy.player = player
	enemy.safe_center = Vector3(9000.0, 0.0, 9000.0)
	enemy.position = Vector3(0.0, 0.05, distance)
	world_root.add_child(enemy)
	player.global_position = Vector3.ZERO
	for index in 30:
		await physics_frame
	_assert_even(await _sample(enemy), "cinder devil")
	enemy.queue_free()
	await process_frame


## A crimson clone patrolling in on the same stride.
func _check_clone(player: CharacterBody3D, distance: float) -> void:
	var clone = Clone.new()
	clone.name = "MotionClone"
	clone.bounds = 60.0
	world_root.add_child(clone)
	clone.configure(3, 1, true, "scene")
	clone.spawn_at(Vector3(0.0, 0.05, distance))
	clone.fallback_target = player
	player.global_position = Vector3.ZERO
	for index in 40:
		await physics_frame
	_assert_even(await _sample(clone), "ranger clone")
	clone.queue_free()
	await process_frame
