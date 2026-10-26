extends SceneTree
## The camera cull must never hide a body the player can see, and must react on
## the frame the player looks at it.
##
## `main._step_mob_culling` used to run on the physics timer, four times a
## second, and sampled two points on a body. Turning onto a monster could leave
## it hidden in plain sight for a quarter of a second -- a 240 ms "pop out of
## nowhere" -- and a body whose torso straddled the screen edge could be hidden
## because both samples missed it. This suite pins both halves of the fix on the
## real frontier:
##
##  * the visible toggle follows the camera on the next rendered frame, for the
##    devil family and for `enemy.gd` bodies;
##  * the visibility test is conservative: a body just past the exact frustum
##    edge is still in view for its bounding sphere, and one clearly outside is
##    not;
##  * a host does not apply the camera cull, because it cannot know what a
##    remote camera sees.

const Enemy = preload("res://scripts/enemy.gd")
const DevilMob = preload("res://scripts/devil_mob.gd")
const MobLod = preload("res://scripts/mob_lod.gd")

var main: Node
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func _face(target: Vector3, toward: bool) -> void:
	var to: Vector3 = target - main.player.global_position
	to.y = 0.0
	var yaw := atan2(-to.x, -to.z)
	main.camera_yaw = yaw if toward else yaw + PI
	main.camera_pitch = 0.04
	main._update_camera(0.0)


func _nearest(wanted: Callable) -> Node3D:
	var best := INF
	var found: Node3D
	for enemy in main._enemies_by_index:
		if not is_instance_valid(enemy) or not wanted.call(enemy):
			continue
		var distance: float = enemy.global_position.distance_to(main.player.global_position)
		if distance < best:
			best = distance
			found = enemy
	return found


func run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for index in 20:
		await physics_frame
	check(main.network_role == "offline", "the suite runs the offline frontier")
	var devil := _nearest(func(body) -> bool: return body is DevilMob)
	var enemy := _nearest(func(body) -> bool: return body is Enemy)
	check(devil != null, "the frontier fields a devil-family body")
	check(enemy != null, "the frontier fields an enemy.gd body")
	if devil != null:
		check(devil.global_position.distance_to(main.player.global_position) <= MobLod.REBUILD_RANGE,
			"the nearest devil is inside the rebuild range")
		await _check_body(devil, "devil")
	if enemy != null:
		check(enemy.global_position.distance_to(main.player.global_position) <= MobLod.REBUILD_RANGE,
			"the nearest enemy.gd body is inside the rebuild range")
		await _check_body(enemy, "cinder devil")
	_check_sphere()
	# A host cannot know what a remote camera sees, so it must never hide a body
	# for the local view.
	if devil != null:
		main.network_role = "host"
		_face(devil.global_position, false)
		await process_frame
		check(not bool(devil.get("offscreen")),
			"a host does not mark a body offscreen")
		main.network_role = "offline"
		_face(devil.global_position, true)
		await process_frame
		check(is_instance_valid(devil.get("_body")) and devil.get("_body").visible == true,
			"the body is drawn again after the role change")
	main.queue_free()
	await process_frame
	print("MOB_CULL_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## The species sampler a body family keeps inside its presentation subtree.
func _sampler(body: Node3D):
	for key in ["_visual", "_devil", "_wolf"]:
		var candidate = body.get(key)
		if is_instance_valid(candidate):
			return candidate
	return null


## One body through the real frame pass: in view, away, and back.
func _check_body(body: Node3D, label: String) -> void:
	var at: Vector3 = body.global_position
	# Start from "looked away" so the reveal below is the transition under test.
	_face(at, false)
	await process_frame
	await process_frame
	check(bool(body.get("offscreen")), label + " is offscreen when the camera looks away")
	var hidden_rig = body.get("_body")
	check(is_instance_valid(hidden_rig) and not hidden_rig.visible,
		label + " is not drawn while offscreen")
	check(_sampler(body) != null,
		label + " keeps its rig while offscreen (a freeze, not a release)")
	# Turn onto it: the next rendered frame must show it, not the next cull tick.
	_face(at, true)
	await process_frame
	check(not bool(body.get("offscreen")), label + " comes back into view on the next frame")
	var shown_rig = body.get("_body")
	check(is_instance_valid(shown_rig) and shown_rig.visible,
		label + " is drawn on the frame the camera turns onto it")
	check(bool(body.get("_animating")), label + " resumes its clip when it is drawn")
	var sampler = _sampler(body)
	check(sampler != null and sampler.is_processing(),
		label + " sampler runs while drawn")


## The sphere test must be conservative: a body whose centre is just outside the
## exact frustum is still in view while any of it could still draw.
func _check_sphere() -> void:
	var camera: Camera3D = main.camera
	var planes := camera.get_frustum()
	var forward: Vector3 = -camera.global_transform.basis.z
	var right: Vector3 = camera.global_transform.basis.x
	var at: Vector3 = camera.global_position + forward * 8.0
	check(MobLod.in_view(planes, at), "a point in front of the camera is in view")
	var edge := 0.0
	var found := false
	for step in 500:
		var offset := float(step) * 0.05
		if not camera.is_position_in_frustum(at + right * offset):
			edge = offset
			found = true
			break
	check(found, "the frustum's side edge is found at eight metres")
	if not found:
		return
	var just_out: Vector3 = at + right * (edge + 0.4)
	var far_out: Vector3 = at + right * (edge + 8.0)
	check(not camera.is_position_in_frustum(just_out),
		"the probe point sits outside the exact frustum")
	check(MobLod.in_view(planes, just_out),
		"a body 0.4 m past the edge is still in view for its bounding sphere")
	check(not MobLod.in_view(planes, far_out),
		"a body 8 m past the edge is offscreen")
