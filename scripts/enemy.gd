extends CharacterBody3D

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float, victim: CharacterBody3D)
signal arrow_fired(origin: Vector3, direction: Vector3, speed: float, damage: float)

const Geo = preload("res://scripts/geo.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const WolfVisual = preload("res://scripts/wolf_visual.gd")
const DevilVisual = preload("res://scripts/cinder_devil_visual.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const HeldWeapon = preload("res://scripts/held_weapon.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const MobGround = preload("res://scripts/mob_ground.gd")
const MobLod = preload("res://scripts/mob_lod.gd")
const MobWire = preload("res://scripts/mob_wire.gd")
const Arrow = preload("res://scripts/arrow.gd")
const DEVIL_HEALTH := 24.0
## How far each kind can see. Distance alone never starts a fight: the mob has
## to have the ranger in its forward cone with a clear line of sight, and it
## keeps hunting for `MobSenses.MEMORY_SECONDS` after losing that view.
const WILD_SIGHT := 23.0
const DEVIL_SIGHT := 30.0
const DEVIL_WINDUP := 0.30
const DEVIL_STRIKE := 0.16
const DEVIL_RECOVER := 0.30
const DEVIL_SLIDE_SECONDS := 0.46
const DEVIL_DAMAGE := 8.0
const DEVIL_LEAP_DAMAGE := 10.0
const DEVIL_MAX_ATTACKERS := 3
var kind := 0
var pack_index := -1
var devil_weapon := "claw"
var player: CharacterBody3D
## The frontier world, for the analytic ground and navigation field. Null in a
## bare test scene, where the locomotion helper falls back to a floor ray.
var terrain: Node3D
var targets: Array[CharacterBody3D] = []
var replica := false
## Buffered server states: a replica renders a short delay behind the host so
## uneven packets read as motion, and dead-reckons when the buffer runs dry.
var _timeline = NetReplication.mob_timeline()
var _received_pose := false
var safe_center := Vector3.ZERO
var health := 38.0
var max_health := 38.0
## Slot of the ranger whose damage landed last; the frontier reads it on death
## so off-hand skull trinkets only pay out to the killer.
var last_hitter := -1
var alive := true
var _impact_force := Vector3.ZERO
var home := Vector3.ZERO
var state := "IDLE"
var _state_time := 0.0
var _stagger_duration := 0.0
var _body: Node3D
var _wolf: WolfVisual
var _devil: DevilVisual
var _dodge
var _warning: MeshInstance3D
var _query := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()
var _senses := MobSenses.new()
var _ground: MobGround = MobGround.new()
## Set by the scene that owns the slot: true when no ranger is near enough for
## anything this body does to be seen. A mob's own distance check costs about
## six microseconds a frame, more than the work it is choosing to skip, so the
## scene does it once for all of them and the body just reads a bool.
var skip_tick := false
## Set by the scene when the body is outside the viewer's frustum. An offscreen
## monster still simulates; it just stops spending frames on its rig, and the
## pose it resumes with reads correctly because nobody watched the gap. The
## scene rewrites this from the frame that is about to be drawn, so a body is
## hidden on the frame it leaves the view and shown on the frame it returns.
var offscreen := false
var _lod_stride := 1
var _lod_phase := 0
## Whether the body owns a rig at all (inside `MobLod.RELEASE_RANGE`).
var _presenting := true
## Whether that rig is currently drawn and its clip advancing.
var _animating := true
var _anim_stride := 1
var _attacker: Node3D
var _orbit_angle := 0.0
var _orbit_dir := 1.0
var _orbit_radius := 4.0
var _orbit_phase := 0.0
var _decision_timer := 0.0
var _attack_cooldown := 0.0
var _leap_cooldown := 0.0
var _slide_cooldown := 0.0
var _slide_time := 0.0
var _slide_direction := Vector3.FORWARD
var _slide_speed := 0.0
var _leap_direction := Vector3.FORWARD
var _leap_air_time := 0.0
var _attack_damage := DEVIL_DAMAGE
var _attack_reach := 1.8
var _leap_damage := DEVIL_LEAP_DAMAGE
var _struck := false
var _shot_fired := false
var shots_fired := 0
var _move_intent := Vector3.ZERO
var _move_speed := 0.0
var _face_intent := Vector3.FORWARD
var _target: CharacterBody3D

func _ready() -> void:
	name = "BriarWolf" if kind == 0 else "CinderDevil"
	home = global_position
	# Watch the road: spawn facing the arriving ranger, like the newer mob
	# families do. Without a facing the sight cone would stare down -Z forever
	# and a whole pack could miss a ranger standing beside it.
	if is_instance_valid(player):
		var facing := player.global_position - global_position
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			rotation.y = atan2(-facing.x, -facing.z)
	max_health = 38.0 if kind == 0 else DEVIL_HEALTH
	health = max_health
	collision_layer = 2
	# Nothing here queries the physics server -- the body walks on the analytic
	# ground -- so a mask would only make this shape pair with every other mob
	# and with the ranger in the broadphase.
	collision_mask = 0
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	_ground.radius = 0.34
	_ground.terrain = terrain if terrain != null else _parent_world()
	var shape := CapsuleShape3D.new()
	if kind == 0:
		shape.radius = 0.40
		shape.height = 0.95
	else:
		# The authored cinder devil stands 2.11 m to the crown: a gaunt frame
		# on a 2.15 m capsule, not the 0.9 m primitive imp it replaced.
		shape.radius = 0.34
		shape.height = 2.15
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_build_rig()
	var warning_radius := 0.85 if kind == 2 else 1.5
	var warning_material := Geo.material(Color(0.95, 0.22, 0.08, 0.38))
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warning = Geo.cylinder(self, warning_radius, warning_radius, 0.018, Vector3(0, 0.035, 0), warning_material, 32)
	_warning.visible = false
	_query.collision_mask = 1
	# Any wilderness mob answers a neighbour's alarm, so one shot at a wolf
	# brings the rest of the pack and the devils standing nearby.
	add_to_group(MobSenses.GROUP)
	if kind == 2:
		add_to_group("cinder_devils")
		_dodge = DodgeStep.new()
		_dodge.travel = DodgeStep.TRAVEL * 0.5
		_dodge.duration = 0.22
		add_child(_dodge)
		var seeded := maxi(pack_index,0)
		_rng.seed = 7319 + seeded * 131
		_orbit_dir = 1.0 if seeded % 2 == 0 else -1.0
		_orbit_radius = 3.4 + float(seeded % 3) * 1.0
		_orbit_phase = _rng.randf() * TAU
		_attack_cooldown = 0.25 + float(seeded % 5) * 0.18
		_decision_timer = _rng.randf_range(0.15,0.45)
		devil_weapon = str(devil_weapon).to_lower()
		if devil_weapon not in ["claw","dagger","sword","bow"]:
			devil_weapon = "claw"
		match devil_weapon:
			"dagger":
				_attack_damage = 6.0
				_attack_reach = 1.6
				_leap_damage = 8.0
			"sword":
				_attack_damage = 11.0
				_attack_reach = 2.0
				_leap_damage = 13.0
			"bow":
				_attack_damage = 7.0
				_attack_reach = 0.0
				_leap_damage = 7.0
				_orbit_radius = 8.2 + float(seeded % 3) * 0.8
			_:
				_attack_damage = DEVIL_DAMAGE
				_attack_reach = 1.8
				_leap_damage = DEVIL_LEAP_DAMAGE
		_devil.set_weapon(devil_weapon)
		if is_instance_valid(player):
			var start := global_position - player.global_position
			start.y = 0.0
			if start.length_squared() > 0.0001:
				_orbit_angle = atan2(start.z,start.x)+float(seeded)*0.62
		state = "CIRCLE"

## Builds the presentation subtree. Shared by the first spawn and by a rig
## that was released at range and is being rebuilt on approach.
func _build_rig() -> void:
	_body = Node3D.new()
	add_child(_body)
	if kind == 0:
		_build_wolf_visual()
	else:
		_build_devil_visual()


## Releases the presentation subtree; see `devil_mob._release_rig`.
func _release_rig() -> void:
	if is_instance_valid(_wolf):
		_wolf.set_frozen(true)
	if is_instance_valid(_devil):
		_devil.set_frozen(true)
	_wolf = null
	_devil = null
	if is_instance_valid(_body):
		_body.free()
	_body = null


func _build_wolf_visual() -> void:
	_wolf = WolfVisual.new()
	_wolf.name = "WolfVisual"
	_body.add_child(_wolf)

func _build_devil_visual() -> void:
	_devil = DevilVisual.new()
	_devil.name = "DevilVisual"
	_body.add_child(_devil)

func get_aim_position() -> Vector3:
	return global_position + Vector3(0, 0.68 if kind == 0 else 1.25, 0)

func blood_rig() -> Node3D:
	if kind == 2 and is_instance_valid(_devil):
		var anchor := _devil.blood_anchor()
		if is_instance_valid(anchor):
			return anchor
	return _body

func blood_scale() -> float:
	return 1.35 if kind == 0 else 1.20

func blood_weapon_anchor(_hand: String = "") -> Node3D:
	if kind == 2 and is_instance_valid(_devil):
		return _devil.weapon_anchor() if is_instance_valid(_devil) else null
	return null

## The limb or muzzle that landed the blow, for the blood it carried away: a
## wolf's jaws or the cinder devil's raking hand.
func blood_strike_point() -> Vector3:
	if kind == 0 and is_instance_valid(_wolf):
		return _wolf.head_hitbox_center()
	if kind == 2 and is_instance_valid(_devil):
		return _devil.strike_hand_position()
	return get_aim_position()

func get_display_name() -> String:
	return "Briar wolf" if kind == 0 else "Cinder devil"

## The catalog id of the weapon this mob carries; empty for wolves and claw
## devils that hold nothing.
func held_weapon_id() -> String:
	return HeldWeapon.item_id(devil_weapon) if kind == 2 else ""

func head_hitbox_center() -> Vector3:
	if kind == 0 and is_instance_valid(_wolf):
		return _wolf.head_hitbox_center()
	if is_instance_valid(_devil):
		return _devil.head_hitbox_center()
	return get_aim_position()
func head_hit_profile() -> Vector2:
	if kind == 0:
		return Vector2(Hitbox.WOLF_HEAD_RADIUS,Hitbox.WOLF_HEAD_HALF_HEIGHT)
	return Vector2(Hitbox.DEVIL_HEAD_RADIUS,Hitbox.DEVIL_HEAD_HALF_HEIGHT)


func _physics_process(delta: float) -> void:
	if skip_tick:
		return
	if replica:
		# A replica still owns its presentation: on a client it is the only
		# thing drawing the mob, so it wants the same distance culling and the
		# same rig release the host's own bodies get.
		Perf.begin("mob.lod")
		_apply_presentation(_lod_distance())
		Perf.end()
		return
	if not alive:
		CorpsePhysics.settle_root(self, delta)
		return
	Perf.begin("mob.lod")
	var nearest := _lod_distance()
	_apply_presentation(nearest)
	Perf.end()
	var stride := MobLod.stride_for(nearest, _attack_ready(nearest))
	if not MobLod.due(Engine.get_physics_frames(), _lod_phase, stride):
		# No decision, but the body keeps travelling on the velocity it last
		# chose: the think rate is coarse, the motion is not.
		if _ground.velocity.length_squared() > 0.01 or not _ground.grounded:
			_ground.drive(self, delta)
		return
	if stride != _lod_stride:
		_lod_stride = stride
		_lod_phase = MobLod.phase(global_position, stride)
	# Two clocks, as in `devil_mob`: the scaled one for timers, the real frame
	# for motion.
	var frame := delta
	delta *= float(stride)
	Perf.begin("legacy.ai")
	# Sight and the pursuit memory decide aggression for the wolf and the
	# cinder devil exactly as they do for the newer mob families.
	Perf.begin("mob.senses")
	var pursuit := _senses.step(self, _candidates(), delta, _sight_range(),
		_eye_height(), safe_center)
	Perf.end()
	_target = _senses.target if is_instance_valid(_senses.target) else _resolve_target()
	if not is_instance_valid(_target) and not pursuit:
		Perf.end()
		return
	if kind == 2:
		_step_devil(delta, pursuit, frame)
		Perf.end()
		return
	_state_time += delta
	var focus := _senses.focus() if pursuit else _target.global_position
	var displacement := focus - global_position
	displacement.y = 0.0
	var distance := displacement.length()
	var target_safe := MobSenses.in_safe_ring(safe_center, focus)
	var target_direction := Vector3.ZERO
	var speed := 3.1
	if state == "STAGGER":
		if _state_time >= _stagger_duration:
			state = "IDLE"
			_state_time = 0.0
	elif state == "WINDUP":
		if _state_time >= 0.65:
			if distance < 2.1 and not target_safe and absf(_target.position.y - position.y) < 1.7:
				attacked.emit(self,13.0,_target)
			# A parry can synchronously replace the attack with STAGGER.
			if state == "WINDUP":
				state = "RECOVER"
				_state_time = 0.0
				_warning.visible = false
	elif state == "RECOVER":
		if _state_time > 0.85:
			state = "IDLE"
	else:
		if pursuit and not target_safe:
			state = "CHASE"
			target_direction = displacement.normalized()
			if not _senses.seen and distance < MobSenses.ARRIVE_DISTANCE:
				# Standing over the last sighting: sweep the ground.
				rotation.y += sin(_state_time * 1.5) * delta * 1.7
				target_direction = Vector3.ZERO
			elif _senses.seen and distance < 1.65:
				state = "WINDUP"
				_state_time = 0.0
				_warning.visible = true
				target_direction = Vector3.ZERO
		else:
			state = "IDLE"
			var to_home := home - global_position
			to_home.y = 0.0
			if to_home.length() > 1.0:
				target_direction = to_home.normalized()
				speed = 2.0
	if target_direction.length_squared() > 0.1:
		Perf.begin("mob.steer")
		target_direction = _steer(target_direction)
		Perf.end()
		rotation.y = lerp_angle(rotation.y, atan2(-target_direction.x, -target_direction.z), minf(frame * 8.0, 1.0))
	velocity.x = move_toward(velocity.x, target_direction.x * speed, frame * 12.0)
	velocity.z = move_toward(velocity.z, target_direction.z * speed, frame * 12.0)
	velocity.y = -1.0 if _ground.grounded else velocity.y - 18.0 * frame
	Perf.begin("mob.drive")
	Perf.begin("mob.slide")
	_ground.drive(self,frame)
	Perf.end()
	Perf.end()
	Perf.begin("mob.visual")
	_update_cosmetics(delta)
	Perf.end()
	Perf.end()

func _resolve_target() -> CharacterBody3D:
	var nearest := INF
	var best: CharacterBody3D = null
	for candidate in targets:
		if not is_instance_valid(candidate) or candidate.get("alive") == false:
			continue
		var offset := candidate.global_position - global_position
		var planar := offset.x * offset.x + offset.z * offset.z
		if planar < nearest:
			nearest = planar
			best = candidate
	return best if is_instance_valid(best) else player


## Everyone this mob could hunt: the local ranger plus every host seat.
func _candidates() -> Array:
	var list: Array = []
	for candidate in targets:
		if is_instance_valid(candidate) and not list.has(candidate):
			list.append(candidate)
	if is_instance_valid(player) and not list.has(player):
		list.append(player)
	return list


func _sight_range() -> float:
	return DEVIL_SIGHT if kind == 2 else WILD_SIGHT


## Eye height follows the authored body: the wolf looks out low, the cinder
## devil looks out of its horned skull about two metres up.
func _eye_height() -> float:
	var height := 0.95 if kind == 0 else 2.15
	return maxf(0.6, height * MobSenses.EYE_HEIGHT_FRACTION)


## Huntable rangers: alive and outside the town's safe ring.
func _is_hostile(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or candidate.get("alive") == false:
		return false
	return not MobSenses.in_safe_ring(safe_center, candidate.global_position)

func _update_cosmetics(_delta: float) -> void:
	if not is_instance_valid(_wolf):
		return
	var actual_velocity: Vector3 = _ground.actual
	_wolf.set_motion(Vector2(actual_velocity.x, actual_velocity.z).length())
	_wolf.set_combat(state, _state_time)

func _step_devil(delta: float, pursuit: bool, frame: float = -1.0) -> void:
	if frame < 0.0:
		frame = delta
	_state_time += delta
	_dodge.advance(frame,_ground.grounded)
	_attack_cooldown = maxf(0.0,_attack_cooldown-delta)
	_decision_timer -= delta
	_leap_cooldown = maxf(0.0,_leap_cooldown-delta)
	_slide_cooldown = maxf(0.0,_slide_cooldown-delta)
	var focus := _senses.focus()
	var to_target := focus-global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var aggro := pursuit and not MobSenses.in_safe_ring(safe_center, focus)
	if not aggro:
		if state != "RETURN":
			_enter_devil_state("RETURN")
	elif state in ["RETURN","IDLE"]:
		_enter_devil_state("CIRCLE")
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	_face_intent = Vector3.FORWARD
	match state:
		"RETURN":
			var home_offset := home-global_position
			home_offset.y = 0.0
			if home_offset.length() > 1.4:
				_move_intent = _steer_devil(home_offset.normalized())
				_move_speed = 6.0
				_face_intent = _move_intent
		"STAGGER":
			if _state_time >= _stagger_duration:
				_enter_devil_state("CIRCLE")
		"STEP":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			if not _dodge.active:
				_enter_devil_state("CIRCLE")
		"SLIDE":
			_slide_time += delta
			_slide_speed = lerpf(9.4,4.0,clampf(_slide_time/DEVIL_SLIDE_SECONDS,0.0,1.0))
			_face_intent = _slide_direction
			if _slide_time >= DEVIL_SLIDE_SECONDS or not _ground.grounded:
				_enter_devil_state("CIRCLE")
		"LEAP":
			_leap_air_time += delta
			_face_intent = _leap_direction
			if _ground.grounded and _leap_air_time > 0.18:
				if devil_weapon != "bow" and distance < 2.8 and _attack_cooldown <= 0.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS:
					_devil_begin_windup(_leap_damage)
				else:
					_decision_timer = 0.15
					_enter_devil_state("CIRCLE")
		"DIVE":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			var predicted := _target.global_position+_target.velocity*0.16
			var dive_offset := predicted-global_position
			dive_offset.y = 0.0
			if dive_offset.length_squared() > 0.0001:
				_move_intent = _steer_devil(_devil_with_separation(dive_offset.normalized()))
			_move_speed = 9.2
			if distance < 1.65 or _state_time >= 0.48:
				_devil_begin_windup(_attack_damage)
		"WINDUP":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			if _state_time >= DEVIL_WINDUP:
				_enter_devil_state("STRIKE")
		"STRIKE":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			if not _struck and _state_time >= 0.080:
				_struck = true
				_devil_strike(distance,to_target)
			if _state_time >= DEVIL_STRIKE:
				_attack_cooldown = 0.75+_rng.randf()*0.70
				_enter_devil_state("RECOVER")
		"SHOOT":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			if not _shot_fired and _state_time >= 0.30:
				_shot_fired = true
				_shoot_arrow()
			if _state_time >= 0.52:
				_attack_cooldown = 0.70+_rng.randf()*0.60
				_enter_devil_state("RECOVER")
		"RECOVER":
			if distance > 0.001:
				var retreat := -to_target.normalized()
				var tangent := Vector3(-to_target.z,0.0,to_target.x).normalized()*_orbit_dir
				_move_intent = _steer_devil((retreat+tangent*0.7).normalized())
				_move_speed = 4.8
				_face_intent = _move_intent
			if _state_time >= DEVIL_RECOVER:
				_enter_devil_state("CIRCLE")
		_:
			if _senses.seen:
				_devil_circle(delta,distance,to_target)
			else:
				_devil_hunt(delta)
	var was_grounded := _ground.grounded
	if _dodge.active:
		var step_velocity: Vector3 = _dodge.velocity()
		velocity.x = step_velocity.x
		velocity.z = step_velocity.z
	elif state == "SLIDE":
		velocity.x = _slide_direction.x*_slide_speed
		velocity.z = _slide_direction.z*_slide_speed
	elif state == "LEAP":
		velocity.x = _leap_direction.x*7.2
		velocity.z = _leap_direction.z*7.2
	else:
		var target := _move_intent*_move_speed
		var control := 32.0 if was_grounded else 9.0
		velocity.x = move_toward(velocity.x,target.x,control*frame)
		velocity.z = move_toward(velocity.z,target.z,control*frame)
	if was_grounded and velocity.y <= 0.0:
		velocity.y = -1.0
	elif not was_grounded:
		velocity.y -= 18.0*frame
	var facing := _face_intent
	if facing.length_squared() < 0.0001 or _dodge.active:
		facing = -global_basis.z
	if facing.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y,atan2(-facing.x,-facing.z),minf(frame*12.0,1.0))
	_ground.drive(self,frame)
	var actual: Vector3 = _ground.actual
	if state == "LEAP" and not was_grounded and _ground.grounded and _leap_air_time > 0.18:
		if devil_weapon != "bow" and distance < 2.8 and _attack_cooldown <= 0.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS:
			_devil_begin_windup(_leap_damage)
		else:
			_decision_timer = 0.15
			_enter_devil_state("CIRCLE")
	if is_instance_valid(_devil):
		_devil.set_motion(actual,_ground.grounded)
		_devil.set_action(state,_state_time)
		_devil.set_step(_dodge.progress if _dodge.active else -1.0,_dodge.direction)
		_devil.set_slide(_slide_time/DEVIL_SLIDE_SECONDS if state == "SLIDE" else -1.0)

func _devil_circle(delta: float, distance: float, to_player: Vector3) -> void:
	_orbit_angle += _orbit_dir*delta*(1.65+0.40*sin(_orbit_phase+_state_time*0.8))
	var predicted := _target.global_position+_target.velocity*0.10
	var radius := _orbit_radius+sin(_orbit_phase+_state_time*0.7)*0.55
	var ring := predicted+Vector3(cos(_orbit_angle),0.0,sin(_orbit_angle))*radius
	var offset := ring-global_position
	offset.y = 0.0
	var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
	var retreat_at := 7.5 if devil_weapon == "bow" else 2.4
	var close_at := 13.0 if devil_weapon == "bow" else 9.0
	if distance < retreat_at:
		direction -= to_player.normalized()*1.0
	elif distance > close_at:
		direction += to_player.normalized()*0.8
	_move_intent = _steer_devil(_devil_with_separation(direction))
	_move_speed = 6.8
	# A circling predator keeps its eyes on the quarry; facing the orbit
	# direction would swing the ranger out of the sight cone every lap.
	_face_intent = to_player
	if _decision_timer <= 0.0:
		_decision_timer = 0.38+_rng.randf()*0.35
		_devil_choose(distance,to_player)

## Lost sight but still remembers: run down the last known spot, then scan.
func _devil_hunt(delta: float) -> void:
	var offset := _senses.last_seen-global_position
	offset.y = 0.0
	if offset.length() > MobSenses.ARRIVE_DISTANCE:
		_move_intent = _steer_devil(_devil_with_separation(offset.normalized()))
		_move_speed = 5.2
		_face_intent = _move_intent
		return
	rotation.y += sin(_state_time*1.5)*delta*1.7
	_face_intent = -global_basis.z

func _devil_choose(distance: float, to_player: Vector3) -> void:
	if not _ground.grounded:
		return
	var roll := _rng.randf()
	if devil_weapon == "bow":
		if distance < 6.0:
			if _leap_cooldown <= 0.0 and roll < 0.38:
				_devil_start_leap(distance,to_player,true)
			elif _slide_cooldown <= 0.0 and roll < 0.72:
				_devil_start_slide(to_player,true)
			elif _dodge.can_step(true,false):
				_devil_start_step(to_player)
			return
		if _attack_cooldown <= 0.0 and distance <= 16.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS and _devil_has_los():
			_enter_devil_state("SHOOT")
			return
		if roll < 0.22 and _dodge.can_step(true,false):
			_devil_start_step(to_player)
		return
	if _attack_cooldown <= 0.0 and distance < 8.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS:
		_enter_devil_state("DIVE")
		return
	if _leap_cooldown <= 0.0 and roll < 0.32:
		_devil_start_leap(distance,to_player)
		return
	if roll < 0.64 and _dodge.can_step(true,false):
		_devil_start_step(to_player)
		return
	if _slide_cooldown <= 0.0 and distance > 2.3 and roll < 0.82:
		_devil_start_slide(to_player)

func _devil_start_step(to_player: Vector3) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var forward_bias := -0.30 if devil_weapon == "bow" else 0.22
	var direction := (tangent*side*0.9+to_player.normalized()*forward_bias).normalized()
	if _dodge.try_step(direction,_ground.grounded,false):
		_enter_devil_state("STEP")
		_face_intent = to_player.normalized()

func _devil_start_leap(distance: float, to_player: Vector3, retreat: bool = false) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()*_orbit_dir
	var forward := to_player.normalized()
	var direction := (forward*0.55+tangent*0.85).normalized()
	if retreat:
		direction = (-forward*0.65+tangent*0.85).normalized()
	elif distance > 4.5:
		direction = (forward*0.80+tangent*0.50).normalized()
	_leap_direction = _steer_devil(direction)
	_leap_air_time = 0.0
	_leap_cooldown = 1.05+_rng.randf()*0.40
	_enter_devil_state("LEAP")
	velocity.y = 6.5

func _devil_start_slide(to_player: Vector3, retreat: bool = false) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()*_orbit_dir
	var forward := to_player.normalized()
	var direction := (tangent*0.9+forward*0.35).normalized()
	if retreat:
		direction = (-forward*0.70+tangent*0.85).normalized()
	_slide_direction = _steer_devil(direction)
	_slide_time = 0.0
	_slide_speed = 9.6
	_slide_cooldown = 1.2+_rng.randf()*0.5
	_enter_devil_state("SLIDE")

func _devil_begin_windup(damage: float) -> void:
	_attack_damage = damage
	_struck = false
	_enter_devil_state("WINDUP")
	var to_target := _target.global_position-global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		_face_intent = to_target.normalized()

func _enter_devil_state(next: String) -> void:
	state = next
	_state_time = 0.0
	_shot_fired = false
	_warning.visible = next == "WINDUP"

func _devil_strike(distance: float, to_player: Vector3) -> void:
	if distance > _attack_reach or absf(_target.global_position.y-global_position.y) > 1.25:
		return
	if to_player.length_squared() > 0.0001 and (-global_basis.z).dot(to_player.normalized()) < 0.15:
		return
	_query.from = global_position+Vector3(0,0.5,0)
	_query.to = _target.global_position+Vector3(0,0.7,0)
	if not get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return
	attacked.emit(self,_attack_damage,_target)

func _shoot_arrow() -> void:
	if not is_instance_valid(_target) or get_parent() == null:
		return
	if not is_instance_valid(_devil):
		return
	var origin: Vector3 = _devil.get_bow_origin()
	var target := _target.global_position+Vector3(0,1.0,0)+_target.velocity*0.12
	var flight := origin.distance_to(target)/30.0
	target.y += 0.5*4.0*flight*flight
	var direction := (target-origin).normalized()
	var arrow := Arrow.new()
	# Layer 8 is the shield: a raised or carried shield intercepts the shaft
	# before it reaches the body behind it.
	arrow.hit_mask = 1 | 4 | 8
	get_parent().add_child(arrow)
	arrow.launch(origin,direction,30.0,_attack_damage,[get_rid()],origin)
	arrow_fired.emit(origin,direction,30.0,_attack_damage)
	shots_fired += 1

func _devil_has_los() -> bool:
	if not is_instance_valid(_target):
		return false
	_query.from = global_position+Vector3(0,0.55,0)
	_query.to = _target.global_position+Vector3(0,0.85,0)
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()

func _devil_with_separation(direction: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("cinder_devils"):
		if other == self or not is_instance_valid(other) or not bool(other.get("alive")):
			continue
		var offset: Vector3 = global_position-other.global_position
		offset.y = 0.0
		var spread := offset.length()
		if spread < 1.15 and spread > 0.001:
			push += offset/spread*(1.15-spread)*1.7
	return direction+push

func _pack_attackers() -> int:
	var count := 0
	for other in get_tree().get_nodes_in_group("cinder_devils"):
		if other == self or not is_instance_valid(other) or not bool(other.get("alive")):
			continue
		if other.global_position.distance_squared_to(global_position) > 196.0:
			continue
		if str(other.get("state")) in ["WINDUP","STRIKE","DIVE","SHOOT"]:
			count += 1
	return count

func _steer_devil(direction: Vector3) -> Vector3:
	_query.from = global_position+Vector3(0,0.45,0)
	_query.to = _query.from+direction*1.25
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return direction
	var left := direction.rotated(Vector3.UP,1.0)
	_query.to = _query.from+left*1.35
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return left
	return direction.rotated(Vector3.UP,-1.0)

func _steer(direction: Vector3) -> Vector3:
	_query.from = global_position + Vector3(0, 0.65, 0)
	_query.to = _query.from + direction * 1.7
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return direction
	var left := direction.rotated(Vector3.UP, 1.05)
	_query.to = _query.from + left * 1.8
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return left
	return direction.rotated(Vector3.UP, -1.05)

func stagger(seconds: float) -> void:
	if not alive:
		return
	state = "STAGGER"
	_state_time = 0.0
	_stagger_duration = maxf(0.0,seconds)
	_warning.visible = false
	velocity.x = 0.0
	velocity.z = 0.0
	if kind == 2:
		_dodge.reset()
		_slide_time = 0.0
		_attack_cooldown = maxf(_attack_cooldown,0.45)

## The killing blow's style/angle force, recorded by the damage source. It is
## only read at death; a miss does not matter.
func note_impact(force: Vector3) -> void:
	_impact_force = Vector3(force.x, 0.0, force.z)


func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	last_hitter = source_id
	var applied := amount * Hitbox.damage_multiplier(headshot)
	health = maxf(0.0, health - applied)
	DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",headshot,health <= 0.0)
	# Every mob bleeds: the wolf and the cinder devil both carry blood in this
	# world, so a landed hit always reads on the body and on the floor.
	BloodFx.wound(self,blood_rig(),get_aim_position(),applied,headshot,
		health <= 0.0,blood_scale())
	if health <= 0.0:
		_enter_dead(true)
		return
	_respond_to_attack()


## The projectile, blade or spell that landed names itself here before it
## applies damage, so the mob can turn on an archer it never saw.
func note_attacker(attacker: Node3D) -> void:
	_attacker = attacker


## A landed blow always starts the fight, and the cry pulls the neighbours in.
func _respond_to_attack() -> void:
	var attacker: Node3D = _attacker if is_instance_valid(_attacker) else null
	_attacker = null
	if attacker != null and not _is_hostile(attacker):
		return
	if attacker == null:
		var nearest := _resolve_target()
		if not is_instance_valid(nearest) or not _is_hostile(nearest):
			return
		attacker = nearest
	_senses.notice(attacker,attacker.global_position)
	MobSenses.alert_pack(self,attacker,_senses.last_seen)


## A neighbour was struck within earshot: take up the hunt where it last saw.
func hear_alert(attacker: Node3D, at: Vector3) -> void:
	if not alive or replica:
		return
	if is_instance_valid(attacker) and not _is_hostile(attacker):
		return
	_senses.notice(attacker,at)

## Feeds one authoritative pose into the render buffer. The first packet and
## any teleport restart the buffer; everything else interpolates.
func _ingest_pose(state: PackedFloat32Array, tick: int) -> void:
	var point := MobWire.position_of(state)
	var yaw: float = state[MobWire.AT_YAW]
	var speed := MobWire.velocity_of(state)
	var at := tick if tick >= 0 else _timeline.newest_tick() + 1
	var now := Time.get_ticks_msec()/1000.0
	if not _received_pose:
		_timeline.reset_to(point,speed,yaw,at,now)
		global_position = point
		rotation.y = yaw
		_received_pose = true
		return
	_timeline.push(at,point,speed,yaw,now)
	rotation.y = _timeline.sample().yaw


func _process(delta: float) -> void:
	if not replica or not alive or not _received_pose:
		return
	_timeline.advance(delta)
	var sample: Dictionary = _timeline.sample()
	global_position = sample.pos
	rotation.y = sample.yaw


## The local death: combat collision off, gravity on, the limp collapse, then
## the shared hold. Replicas call it with `announce = false` so the kill stays
## on the host.
func _enter_dead(announce: bool) -> void:
	alive = false
	state = "DEAD"
	_warning.visible = false
	var fall := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, velocity)
	# Layer 0 stops the corpse blocking bodies and arrows; mask 1 lets the dead
	# root keep falling onto the world if the mob died mid-leap.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	velocity = Vector3.ZERO
	if kind == 2 and is_instance_valid(_devil):
		# The dropped pickup owns the weapon now; keep it out of the corpse.
		_devil.set_weapon("claw")
	if announce:
		defeated.emit(self, 8 if kind == 0 else 6)
	# Collapse first, then hold the corpse for the shared five minutes. A body
	# that was killed with its rig released has no skeleton to drop: it just
	# holds, out of sight.
	if not is_instance_valid(_body):
		CorpseHold.hold(self, self)
		return
	var death_tween := create_tween()
	if kind == 0 and is_instance_valid(_wolf):
		# The wolf's imported skeleton ragdolls limp from its current pose.
		_wolf.die(fall)
		death_tween.tween_interval(0.45)
	elif is_instance_valid(_devil):
		# The imported cinder's skeleton ragdolls from its lethal pose.
		_devil.die(fall)
		death_tween.tween_interval(0.90)
	else:
		death_tween.tween_interval(0.45)
	CorpseHold.append(death_tween, self, _body)

## One body's wire record: see `scripts/mob_wire.gd` for the slot layout. The
## extra vector carries the cinder devil's dodge and slide presentation.
func snapshot(index := -1) -> PackedFloat32Array:
	return MobWire.pack(index, global_position, velocity, rotation.y,
		_state_time, health, _ground.grounded, alive, state, _packed_pose())

func _packed_pose() -> Vector4:
	if kind != 2:
		return Vector4.ZERO
	if state == "STEP":
		return Vector4(_dodge.progress if _dodge.active else -1.0,
			_dodge.direction.x,_dodge.direction.z,-1.0)
	if state == "SLIDE":
		return Vector4(_dodge.progress if _dodge.active else -1.0,
			_slide_direction.x,_slide_direction.z,
			clampf(_slide_time/DEVIL_SLIDE_SECONDS,0.0,1.0))
	return Vector4(-1,0,0,-1)

## Presentation-side mirror of the host's mob: the host owns AI, damage and
## arrows, so a replica only replays the snapshot it was handed.
func apply_snapshot(state: PackedFloat32Array, tick: int = -1) -> void:
	var previous_health := health
	var was_alive := alive
	_ingest_pose(state,tick)
	self.state = MobWire.state_of(state)
	_state_time = state[MobWire.AT_STATE_TIME]
	health = state[MobWire.AT_HEALTH]
	alive = MobWire.alive_of(state)
	velocity = MobWire.velocity_of(state)
	var grounded := MobWire.grounded_of(state)
	var pose := MobWire.extra_of(state)
	_warning.visible = self.state == "WINDUP"
	# A replica can have released its rig at range; the pose arrives with the
	# snapshot and there is nothing to drive until it is rebuilt.
	if kind == 0 and is_instance_valid(_wolf):
		_wolf.set_motion(Vector2(velocity.x,velocity.z).length())
		_wolf.set_combat(self.state,_state_time)
	elif is_instance_valid(_devil):
		_devil.set_motion(velocity,grounded)
		_devil.set_action(self.state,_state_time)
		_devil.set_step(pose.x,Vector3(pose.y,0.0,pose.z))
		_devil.set_slide(pose.w)
	if health < previous_health:
		var applied: float = previous_health - health
		DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",false,health <= 0.0)
		BloodFx.wound(self,blood_rig(),get_aim_position(),applied,false,
			health <= 0.0,blood_scale())
	if was_alive and not alive:
		_enter_dead(false)


## The frontier world, when nobody handed one in: mobs are children of the
## scene that owns it. Null outside a real world.
func _parent_world() -> Node3D:
	var parent := get_parent()
	if parent != null:
		var candidate = parent.get("world")
		if candidate is Node3D:
			return candidate
	return null


## Distance to the closest ranger this mob could hunt: what decides its stride.
func _lod_distance() -> float:
	var best := INF
	if is_instance_valid(player):
		best = global_position.distance_to(player.global_position)
	for candidate in targets:
		if is_instance_valid(candidate):
			best = minf(best, global_position.distance_to(candidate.global_position))
	return best


## Applies the one presentation decision: a body that is drawn animates, and a
## body that is hidden does neither. Called when the distance tier changes and
## by `set_offscreen` from the camera pass, so visibility always matches the
## frame being drawn.
func _sync_presentation() -> void:
	if _body == null:
		return
	var drawn := _presenting and not offscreen
	if _body.visible != drawn:
		_body.visible = drawn
	if _animating != drawn:
		_animating = drawn
		if is_instance_valid(_wolf):
			_wolf.set_frozen(not drawn)
		if is_instance_valid(_devil):
			_devil.set_frozen(not drawn)


## Called by the scene that owns the camera, once per rendered frame, after the
## camera has moved. `main.offscreen` used to be sampled four times a second by
## the physics tick, which left a body that the camera had just turned onto
## invisible for up to a quarter second -- the mobs that "popped out of
## nowhere".
func set_offscreen(value: bool) -> void:
	if value == offscreen:
		return
	offscreen = value
	_sync_presentation()


## Keeps the presentation in step with distance: a rig is freed past
## `MobLod.RELEASE_RANGE` and rebuilt inside `MobLod.REBUILD_RANGE`; the
## camera decides whether it is drawn (see `set_offscreen`). Only a real world
## does this.
func _apply_presentation(distance: float) -> void:
	# A released rig has no `_body`; that is exactly the case the rebuild below
	# exists for, so only a missing world bails out here.
	if terrain == null:
		return
	if distance > MobLod.RELEASE_RANGE:
		# Freed, not hidden: the node, render instance and skeleton cost a body
		# about fourteen microseconds a frame just by existing.
		if _body != null:
			_release_rig()
			_animating = false
		_presenting = false
		return
	if _body == null:
		# Rebuild only inside the rebuild range: the gap to the release range
		# is the hysteresis that stops a body pacing the boundary from freeing
		# and rebuilding a rig every second.
		if distance > MobLod.REBUILD_RANGE:
			_presenting = false
			return
		_build_rig()
		_anim_stride = 0
	_presenting = true
	_sync_presentation()
	var stride := MobLod.ANIMATE_STRIDE
	if stride != _anim_stride:
		_anim_stride = stride
		if is_instance_valid(_wolf):
			_wolf.set_anim_stride(stride)
		if is_instance_valid(_devil):
			_devil.set_anim_stride(stride)


## True while this mob is in, or about to start, a swing.
func _attack_ready(distance: float) -> bool:
	if state == "WINDUP" or state == "STRIKE" or state == "RECOVER" \
			or state == "SHOOT" or state == "LEAP" or state == "DIVE":
		return true
	return _attack_cooldown <= 0.0 and distance <= maxf(_attack_reach, 2.6) + 1.0
