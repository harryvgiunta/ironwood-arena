extends Node3D
## Presentation-only controller for the half-size Cinder devil.
## The enemy owns root motion, attacks, health and death timing. This node
## builds a compact humanoid from primitives and layers the pack's actions:
## run, leap, slide, side step, claw windup/strike and death flop.

const Geo = preload("res://scripts/geo.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const Bow = preload("res://scripts/bow.gd")
const Sword = preload("res://scripts/sword.gd")
const Dagger = preload("res://scripts/dagger.gd")

const WINDUP_SECONDS := 0.30
const STRIKE_SECONDS := 0.16
const RECOVER_SECONDS := 0.30
const DEATH_SECONDS := 0.55

var _rig: Node3D
## Frames per animation step; see `set_anim_stride`.
var _anim_stride := 1
var _anim_phase := 0
var _pelvis: Node3D
var _torso: Node3D
var _head: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _hand_l: Node3D
var _hand_r: Node3D
var _weapon_role := "claw"
var _melee_weapon: Node3D
var _bow
var _tail: Array[Node3D] = []
var _skin: StandardMaterial3D
var _hide: StandardMaterial3D
var _horn: StandardMaterial3D
var _ember: StandardMaterial3D
var _speed := 0.0
var _vertical := 0.0
var _grounded := true
var _phase := 0.0
var _time := 0.0
var _air_blend := 0.0
var _slide_blend := 0.0
var _action := "CIRCLE"
var _action_time := 0.0
var _step_progress := -1.0
var _step_direction := Vector3.RIGHT
var _slide_progress := -1.0
var _dead := false
var _death_time := 0.0

func _ready() -> void:
	_skin = Geo.material(Color("8a3730"),0.0,0.86)
	_hide = Geo.material(Color("33252a"),0.0,0.92)
	_horn = Geo.material(Color("d8c5a2"),0.0,0.7)
	_ember = Geo.material(Color("ffb066"),0.0,0.45)
	_ember.emission_enabled = true
	_ember.emission = Color("ff551d")
	_ember.emission_energy_multiplier = 2.4
	_build_body()

func _build_body() -> void:
	_rig = Node3D.new()
	_rig.name = "DevilRig"
	add_child(_rig)
	_pelvis = Node3D.new()
	_pelvis.name = "Pelvis"
	_pelvis.position = Vector3(0,0.36,0)
	_rig.add_child(_pelvis)
	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0,0.06,0)
	_pelvis.add_child(_torso)

	# Compact barrel chest and the charcoal harness.
	Geo.sphere(_torso,0.13,Vector3(0,0.10,0),_skin,Vector3(1.06,1.15,0.76))
	Geo.box(_torso,Vector3(0.235,0.115,0.165),Vector3(0,0.145,-0.008),_hide)
	Geo.box(_torso,Vector3(0.075,0.21,0.035),Vector3(0,0.15,-0.095),_hide)
	for side in [-1.0,1.0]:
		var spike := Geo.cylinder(_torso,0.032,0.0,0.13,Vector3(side*0.075,0.235,0.10),_horn,6)
		spike.rotation = Vector3(0.65,0.0,-side*0.35)
	Geo.box(_pelvis,Vector3(0.20,0.11,0.14),Vector3(0,0.01,0),_hide)

	# Head, snout, horns, ears and ember eyes.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0,0.33,0)
	_torso.add_child(_head)
	Geo.sphere(_head,0.112,Vector3(0,0.015,0),_skin,Vector3(1.0,1.05,1.06))
	Geo.box(_head,Vector3(0.11,0.065,0.10),Vector3(0,0.0,-0.105),_hide)
	Geo.box(_head,Vector3(0.09,0.022,0.035),Vector3(0,0.0,-0.158),_ember)
	for side in [-1.0,1.0]:
		var eye := Geo.sphere(_head,0.022,Vector3(side*0.050,0.055,-0.100),_ember)
		eye.scale = Vector3(1.0,0.8,0.6)
		var horn := Geo.cylinder(_head,0.030,0.0,0.155,Vector3(side*0.060,0.105,0.030),_horn,6)
		horn.rotation = Vector3(0.55,0.0,-side*0.42)
		var ear := Geo.cylinder(_head,0.025,0.0,0.075,Vector3(side*0.098,0.060,0.015),_skin,5)
		ear.rotation = Vector3(0.25,0.0,-side*0.9)

	# Two-bone arms with a three-claw hand.
	for side in [-1.0,1.0]:
		var arm := Node3D.new()
		arm.name = "ArmR" if side > 0.0 else "ArmL"
		arm.position = Vector3(side*0.152,0.195,0.005)
		_torso.add_child(arm)
		Geo.sphere(arm,0.048,Vector3.ZERO,_hide)
		Geo.cylinder(arm,0.036,0.046,0.17,Vector3(0,-0.085,0),_skin,7)
		var elbow := Node3D.new()
		elbow.position = Vector3(0,-0.17,0)
		arm.add_child(elbow)
		Geo.cylinder(elbow,0.029,0.036,0.14,Vector3(0,-0.07,0),_skin,7)
		var hand := Node3D.new()
		hand.position = Vector3(0,-0.145,-0.005)
		elbow.add_child(hand)
		Geo.sphere(hand,0.042,Vector3.ZERO,_hide)
		for claw_index in 3:
			var claw := Geo.cylinder(hand,0.014,0.0,0.065,Vector3((float(claw_index)-1.0)*0.022,-0.031,-0.040),_horn,4)
			claw.rotation = Vector3(-2.1,0.0,(float(claw_index)-1.0)*0.18)
		if side < 0.0:
			_arm_l = arm
			_elbow_l = elbow
			_hand_l = hand
		else:
			_arm_r = arm
			_elbow_r = elbow
			_hand_r = hand

	# Two-bone legs with split hooves.
	for side in [-1.0,1.0]:
		var leg := Node3D.new()
		leg.name = "LegR" if side > 0.0 else "LegL"
		leg.position = Vector3(side*0.082,0,0)
		_pelvis.add_child(leg)
		Geo.sphere(leg,0.052,Vector3.ZERO,_hide)
		Geo.cylinder(leg,0.042,0.052,0.19,Vector3(0,-0.095,0),_skin,7)
		var knee := Node3D.new()
		knee.position = Vector3(0,-0.19,0)
		leg.add_child(knee)
		Geo.cylinder(knee,0.034,0.043,0.14,Vector3(0,-0.07,0),_hide,7)
		Geo.box(knee,Vector3(0.075,0.04,0.15),Vector3(0,-0.145,-0.035),_hide)
		for toe_index in 2:
			Geo.cylinder(knee,0.016,0.0,0.055,Vector3((float(toe_index)-0.5)*0.028,-0.152,-0.115),_horn,4).rotation = Vector3(-1.35,0.0,0.0)
		if side < 0.0:
			_leg_l = leg
			_knee_l = knee
		else:
			_leg_r = leg
			_knee_r = knee

	# Tail chain: three segments plus a spade tip.
	var tail_root := Node3D.new()
	tail_root.position = Vector3(0,0.055,0.095)
	_pelvis.add_child(tail_root)
	var parent := tail_root
	for index in 3:
		var segment := Node3D.new()
		segment.position = Vector3(0,0,0.13) if index > 0 else Vector3.ZERO
		parent.add_child(segment)
		Geo.beam(segment,Vector3.ZERO,Vector3(0,-0.015+float(index)*0.008,0.14),0.019,_skin,5)
		_tail.append(segment)
		parent = segment
	var spade := Geo.cylinder(parent,0.045,0.0,0.11,Vector3(0,0.0,0.17),_hide,4)
	spade.rotation = Vector3(PI*0.5,PI*0.25,0.0)

func set_weapon(role: String) -> void:
	_weapon_role = role
	if is_instance_valid(_melee_weapon):
		_melee_weapon.queue_free()
		_melee_weapon = null
	if is_instance_valid(_bow):
		_bow.queue_free()
		_bow = null
	match role:
		"dagger":
			var dagger = Dagger.new()
			dagger.blade_length = 0.30
			_hand_r.add_child(dagger)
			dagger.position = Vector3(0,0,-0.02)
			dagger.scale = Vector3.ONE*0.9
			_melee_weapon = dagger
		"sword":
			var sword = Sword.new()
			sword.sword_kind = 0
			sword.blade_length = 0.62
			_hand_r.add_child(sword)
			sword.position = Vector3(0,0,-0.03)
			sword.scale = Vector3.ONE*0.9
			_melee_weapon = sword
		"bow":
			var bow = Bow.new()
			bow.bow_kind = 1
			bow.bow_length = 0.9
			_hand_l.add_child(bow)
			bow.position = Vector3(0,-0.02,0)
			bow.scale = Vector3.ONE*0.9
			bow.set_draw(0.0)
			bow.set_arrow_visible(false)
			_bow = bow

func blood_anchor() -> Node3D:
	return _rig if is_instance_valid(_rig) else self

func weapon_anchor() -> Node3D:
	if is_instance_valid(_melee_weapon) and _melee_weapon.visible:
		return _melee_weapon
	return null

## World point of the right hand: a clawed devil carries blood away on it.
func strike_hand_position() -> Vector3:
	if is_instance_valid(_hand_r):
		return _hand_r.global_position
	return global_position

func get_bow_origin() -> Vector3:
	if is_instance_valid(_bow):
		return _bow.get_arrow_origin()
	return _hand_l.to_global(Vector3(0,-0.02,-0.20))

func set_motion(velocity: Vector3, grounded: bool) -> void:
	_speed = Vector2(velocity.x,velocity.z).length()
	_vertical = velocity.y
	_grounded = grounded

func set_action(action: String, time: float) -> void:
	_action = action
	_action_time = time

func set_step(progress: float, direction: Vector3) -> void:
	_step_progress = progress
	var planar := Vector3(direction.x,0.0,direction.z)
	if planar.length_squared() > 0.0001:
		_step_direction = planar.normalized()

func set_slide(progress: float) -> void:
	_slide_progress = progress

func die() -> void:
	if _dead:
		return
	_dead = true
	_death_time = 0.0
	_action = "DEAD"

func is_dead() -> bool:
	return _dead

func head_hitbox_center() -> Vector3:
	if not is_instance_valid(_head):
		return global_position
	return _head.to_global(Vector3(0,0.015,0))

func head_hit_profile() -> Vector2:
	return Vector2(Hitbox.DEVIL_HEAD_RADIUS,Hitbox.DEVIL_HEAD_HALF_HEIGHT)

func _process(delta: float) -> void:
	if _anim_stride > 1:
		_anim_phase += 1
		if _anim_phase % _anim_stride != 0:
			return
		delta *= float(_anim_stride)
	Perf.begin("mob.anim")
	_sample(delta)
	Perf.end()


func _sample(delta: float) -> void:
	_time += delta
	if _dead:
		_death_time += delta
		_apply_pose(0.0)
		return
	_air_blend = move_toward(_air_blend,0.0 if _grounded else 1.0,delta*8.0)
	_slide_blend = move_toward(_slide_blend,1.0 if _slide_progress >= 0.0 else 0.0,delta*8.0)
	_phase += delta*(3.8+_speed*3.2)
	_apply_pose(delta)

func _apply_pose(_delta: float) -> void:
	# Everything is recomputed from the rest pose so no layer accumulates.
	var rig_position := Vector3.ZERO
	var rig_rotation := Vector3.ZERO
	var pelvis_rotation := Vector3.ZERO
	var torso_rotation := Vector3.ZERO
	var head_rotation := Vector3.ZERO
	var stride := clampf(_speed/6.0,0.0,1.35)
	var step_weight := 0.0
	var step_turn := 0.0
	var slide_weight := 0.0
	if not _dead:
		step_weight = sin(clampf(_step_progress,0.0,1.0)*PI) if _step_progress >= 0.0 else 0.0
		if _step_progress >= 0.0:
			var face := -global_basis.z
			var travel := Vector3(_step_direction.x,0.0,_step_direction.z)
			if travel.length_squared() > 0.0001:
				travel = travel.normalized()
				step_turn = clampf(atan2(face.cross(travel).y,face.dot(travel)),-PI*0.5,PI*0.5)
		slide_weight = _slide_blend
		var swing := sin(_phase)*0.62*stride
		var air := _air_blend
		_leg_l.rotation = Vector3(swing+air*0.8,0.0,0.0)
		_leg_r.rotation = Vector3(-swing+air*1.0,0.0,0.0)
		_knee_l.rotation = Vector3(-maxf(0.0,-sin(_phase))*0.55*stride-air*1.15,0.0,0.0)
		_knee_r.rotation = Vector3(-maxf(0.0,sin(_phase))*0.55*stride-air*1.3,0.0,0.0)
		_arm_l.rotation = Vector3(-swing*0.75-air*0.9,0.0,-0.16)
		_arm_r.rotation = Vector3(swing*0.75-air*0.9,0.0,0.16)
		_elbow_l.rotation = Vector3(-0.32-maxf(0.0,swing)*0.4,0.0,0.0)
		_elbow_r.rotation = Vector3(-0.32-maxf(0.0,-swing)*0.4,0.0,0.0)
		rig_position.y = absf(sin(_phase))*0.022*stride*(1.0-air)
		pelvis_rotation.y = step_turn*0.18*step_weight
		torso_rotation.y = step_turn*0.32*step_weight
		head_rotation.y = -step_turn*0.20*step_weight
		rig_rotation.z = step_turn*0.10*step_weight
		rig_rotation.x = -0.12*stride*(1.0-air)-0.10*air
		# Slide: low, leaning back, leading legs extended.
		rig_position.y -= 0.155*slide_weight
		rig_rotation.x += 0.38*slide_weight
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x,1.10,slide_weight)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x,0.82,slide_weight)
		_knee_l.rotation.x = lerpf(_knee_l.rotation.x,-0.16,slide_weight)
		_knee_r.rotation.x = lerpf(_knee_r.rotation.x,-0.34,slide_weight)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x,0.75,slide_weight)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x,0.75,slide_weight)
		head_rotation.x -= 0.12*slide_weight
		# Pack actions.
		match _action:
			"DIVE":
				rig_rotation.x -= 0.30
				torso_rotation.x = 0.22
				_arm_l.rotation.x = -1.35
				_arm_r.rotation.x = -1.35
				head_rotation.x = -0.15
			"WINDUP":
				var coil := clampf(_action_time/WINDUP_SECONDS,0.0,1.0)
				_arm_r.rotation.x = lerpf(_arm_r.rotation.x,-1.85,coil)
				_arm_r.rotation.z = lerpf(_arm_r.rotation.z,-0.55,coil)
				_arm_l.rotation.x = lerpf(_arm_l.rotation.x,-0.55,coil)
				torso_rotation.y = lerpf(torso_rotation.y,-0.42,coil)
				head_rotation.y = lerpf(head_rotation.y,0.20,coil)
				pelvis_rotation.y -= 0.14*coil
				rig_rotation.z -= 0.06*coil
			"STRIKE":
				var cut := clampf(_action_time/STRIKE_SECONDS,0.0,1.0)
				_arm_r.rotation.x = lerpf(-1.85,1.15,cut)
				_arm_r.rotation.z = lerpf(-0.55,0.30,cut)
				_arm_l.rotation.x = lerpf(-0.55,0.35,cut)
				torso_rotation.y = lerpf(-0.42,0.46,cut)
				head_rotation.y = lerpf(0.20,-0.18,cut)
				pelvis_rotation.y += 0.18*cut
				rig_rotation.x -= 0.22*sin(cut*PI)
			"RECOVER":
				var settle := clampf(_action_time/RECOVER_SECONDS,0.0,1.0)
				_arm_r.rotation.x = lerpf(1.15,0.15,settle)
				_arm_r.rotation.z = lerpf(0.30,0.16,settle)
				torso_rotation.y = lerpf(0.46,0.0,settle)
				head_rotation.y = lerpf(-0.18,0.0,settle)
			"STAGGER":
				var flinch := sin(clampf(_action_time/0.35,0.0,1.0)*PI)
				rig_rotation.x += 0.26*flinch
				rig_rotation.z += 0.10*sin(_action_time*30.0)*flinch
				torso_rotation.x = -0.22*flinch
				_arm_l.rotation.x = -1.15*flinch
				_arm_r.rotation.x = -1.05*flinch
				head_rotation.x = 0.25*flinch
	if is_instance_valid(_bow):
		if _action == "SHOOT":
			var aim := clampf(_action_time/0.30,0.0,1.0)
			_arm_l.rotation = Vector3(lerpf(_arm_l.rotation.x,-1.40,aim),0.0,-0.05)
			_elbow_l.rotation = Vector3(lerpf(_elbow_l.rotation.x,-0.10,aim),0.0,0.0)
			_arm_r.rotation = Vector3(lerpf(_arm_r.rotation.x,-1.05,aim),0.0,0.22)
			_elbow_r.rotation = Vector3(lerpf(_elbow_r.rotation.x,-1.30,aim),0.0,0.0)
			torso_rotation.y = lerpf(torso_rotation.y,0.18,aim)
			head_rotation.y = lerpf(head_rotation.y,-0.10,aim)
			_bow.set_draw(minf(aim,1.0) if _action_time < 0.30 else 0.0)
			_bow.set_arrow_visible(_action_time < 0.30)
		else:
			_bow.set_draw(0.0)
			_bow.set_arrow_visible(false)
	# The step layer must be applied after action poses so a step still reads
	# as lateral travel instead of being cancelled by a claw pose.
	if step_weight > 0.0:
		var step_side := signf(step_turn)
		pelvis_rotation.y += step_turn*0.14*step_weight
		torso_rotation.y += step_turn*0.20*step_weight
		rig_position.x -= step_side*0.04*step_weight
		if step_side > 0.0:
			_leg_l.rotation.z = 0.26*step_weight
			_leg_r.rotation.z = -0.08*step_weight
		else:
			_leg_l.rotation.z = 0.08*step_weight
			_leg_r.rotation.z = -0.26*step_weight
	if _dead:
		var fall := smoothstep(0.0,DEATH_SECONDS,_death_time)
		rig_rotation.z = PI*0.48*fall
		rig_position.y = -0.10*fall
		rig_rotation.x = 0.20*fall
		torso_rotation.x = -0.30*fall
		_arm_l.rotation.x = -1.1*fall
		_arm_r.rotation.x = -1.1*fall
		_leg_l.rotation.x = 0.5*fall
		_leg_r.rotation.x = 0.35*fall
	_pelvis.rotation = pelvis_rotation
	_torso.rotation = torso_rotation
	_head.rotation = head_rotation
	_rig.position = rig_position
	_rig.rotation = rig_rotation
	# Tail sway is independent of the body pose.
	for index in _tail.size():
		_tail[index].rotation = Vector3(0.0,sin(_time*3.4+float(index)*0.7)*0.22+0.06,0.0)

func get_height() -> float:
	return 0.98


## Stops the clip writing bone tracks. The last pose stays on the rig, which is
## what a body beyond the animation range shows: see `MobLod.ANIMATE_RANGE`.
func set_frozen(frozen: bool) -> void:
	set_process(not frozen)


func set_anim_stride(stride: int) -> void:
	_anim_stride = maxi(1, stride)
