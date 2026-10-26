extends CharacterBody3D

## Authoritative frontier AI for the five imported devil mobs.
##
## The same shared state machine drives all profiles; behaviour, cadence and
## reach come from PROFILES. Presentation is entirely in DevilMobVisual, which
## samples the authored GLB clips. Damage and death stay here so the existing
## frontier combat, parry/block, damage numbers and loot paths are unchanged.

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float, victim: CharacterBody3D)

const Visual = preload("res://scripts/devil_mob_visual.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const MobGround = preload("res://scripts/mob_ground.gd")
const MobSpace = preload("res://scripts/mob_space.gd")
const MobLod = preload("res://scripts/mob_lod.gd")
const MobWire = preload("res://scripts/mob_wire.gd")

## Per-mob gameplay profiles. Health, damage, reach, speed and cadence are
## deliberately close to the existing Cinder devil pack so the new mobs remain
## additions, not a difficulty spike. `kind` keeps the deterministic frontier
## loot rotation distinct from kinds 0..2.
## How far a mob keeps from its neighbours, in metres.
const SEPARATION := 1.35
## Spacing is a soft constraint and costs a neighbour walk; ten hertz is more
## than enough to keep a pack apart, so it is re-measured one frame in six and
## the result reused. The phase is offset per mob so the work spreads across
## frames instead of landing together.
const SEPARATION_TICKS := 6
## The gap a mob keeps from a ranger's capsule.
const RANGER_CLEARANCE := 0.62
const PROFILES := {
	"hell_goat": {
		"display": "Hellish goat man", "kind": 3,
		"health": 72.0, "damage": 13.0, "reach": 2.05,
		"walk_speed": 1.50, "run_speed": 4.00, "orbit": 5.5,
		"sight": 30.0, "gold": 10,
		"radius": 0.45, "height": 2.00, "aim": 1.65,
		"windup": 0.45, "strike": 0.18, "recover": 0.55,
		"cooldown": 1.35, "lunge": 6.2, "turn": 9.0,
		"behaviour": "charger", "strafe": 0.9, "blood": 1.05,
	},
	"succubus": {
		"display": "Succubus", "kind": 4,
		"health": 46.0, "damage": 9.0, "reach": 1.85,
		"walk_speed": 1.40, "run_speed": 4.20, "orbit": 6.5,
		"sight": 28.0, "gold": 9,
		"radius": 0.32, "height": 2.05, "aim": 1.50,
		"windup": 0.36, "strike": 0.15, "recover": 0.45,
		"cooldown": 1.15, "lunge": 7.0, "turn": 10.0,
		"behaviour": "flyer", "strafe": 1.10, "blood": 0.95,
	},
	"spawn": {
		"display": "Devil spawn", "kind": 5,
		"health": 22.0, "damage": 6.0, "reach": 1.45,
		"walk_speed": 1.30, "run_speed": 4.60, "orbit": 4.0,
		"sight": 26.0, "gold": 5,
		"radius": 0.30, "height": 1.05, "aim": 0.75,
		"windup": 0.30, "strike": 0.14, "recover": 0.40,
		"cooldown": 0.90, "lunge": 8.0, "turn": 12.0,
		"behaviour": "crawler", "strafe": 1.50, "blood": 0.55,
	},
	"beast": {
		"display": "Hell beast", "kind": 6,
		"health": 130.0, "damage": 20.0, "reach": 2.50,
		"walk_speed": 1.40, "run_speed": 3.80, "orbit": 4.0,
		"sight": 26.0, "gold": 16,
		"radius": 0.55, "height": 1.65, "aim": 1.15,
		"windup": 0.65, "strike": 0.22, "recover": 0.70,
		"cooldown": 2.00, "lunge": 5.5, "turn": 5.5,
		"behaviour": "brute", "strafe": 0.2, "blood": 1.35,
	},
	"gargoyle": {
		"display": "Gargoyle", "kind": 7,
		"health": 110.0, "damage": 17.0, "reach": 3.30,
		"walk_speed": 1.00, "run_speed": 2.80, "orbit": 4.8,
		"sight": 18.0, "gold": 14,
		"radius": 0.70, "height": 3.05, "aim": 2.35,
		"windup": 0.75, "strike": 0.24, "recover": 0.85,
		"cooldown": 2.20, "lunge": 3.2, "turn": 4.5,
		"behaviour": "sentinel", "strafe": 0.0, "blood": 1.20,
	},
}

var mob_id := "hell_goat"
var profile: Dictionary = {}
## The profile's numbers, typed and copied out of the dictionary once. Every
## tick reads a dozen of them, and a member read is an order of magnitude
## cheaper than a string-keyed dictionary lookup — with a hundred and thirty
## bodies thinking thirty times a second that difference is milliseconds.
var _reach := 1.6
var _orbit := 3.0
var _walk_speed := 1.4
var _run_speed := 4.0
var _strafe := 0.6
var _windup := 0.45
var _strike := 0.18
var _recover := 0.55
var _cooldown := 0.9
var _lunge := 2.0
var _turn := 6.0
var _damage := 0.0
var _behaviour := ""
var _body_radius := 0.3
var _body_height := 1.8
var _sight := 0.0
var _aim := 1.0
var kind := 3
var player: CharacterBody3D
## The frontier world: supplies the analytic ground height and the navigation
## field this mob walks against instead of paying a physics step. Tests that
## build a mob in a bare scene leave it null and get a ray fallback.
var terrain: Node3D
var targets: Array[CharacterBody3D] = []
var replica := false
## Buffered server states for the replica's delayed render (see `enemy.gd`).
var _timeline = NetReplication.mob_timeline()
var _received_pose := false
var safe_center := Vector3.ZERO
var home := Vector3.ZERO
var health := 50.0
var max_health := 50.0
## Slot of the ranger whose damage landed last (see `enemy.gd.last_hitter`).
var last_hitter := -1
var alive := true
var _impact_force := Vector3.ZERO
var state := "IDLE"

var _state_time := 0.0
var _stagger_duration := 0.0
var _attack_cooldown := 0.0
var _struck := false
var _strike_direction := Vector3.FORWARD
var _face_intent := Vector3.FORWARD
var _move_intent := Vector3.ZERO
var _move_speed := 0.0
## The velocity the last decision asked for. Between decisions the body keeps
## travelling toward it, so the think rate and the movement rate are separate:
## a mob that is only orbiting decides five times a second and still moves every
## frame.
var _desired := Vector3.ZERO
var _strafe_dir := 1.0
var _visual
var _body: Node3D
var _query := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()
var _target: CharacterBody3D
var _senses := MobSenses.new()
var _ground: MobGround = MobGround.new()
## Cached spacing push and the frame it was measured on.
var _push := Vector3.ZERO
var _push_at := -100
var _push_phase := 0
## This mob's think rate: the stride it runs at and the offset that keeps it
## from lining up with its neighbours.
var _lod_stride := 1
var _lod_phase := 0
## Whether the rig is currently being animated and drawn.
var _presenting := true
var _anim_stride := 1
var _attacker: Node3D


func _ready() -> void:
	Perf.begin("spawn.mob")
	var table := _profiles()
	if not table.has(mob_id):
		push_error("Unknown mob id: " + mob_id)
		Perf.end()
		return
	profile = (table[mob_id] as Dictionary).duplicate(true)
	name = _node_prefix() + mob_id
	kind = int(profile.kind)
	max_health = float(profile.health)
	health = max_health
	_read_profile()
	home = global_position
	if is_instance_valid(player):
		var facing := player.global_position - global_position
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			rotation.y = atan2(-facing.x, -facing.z)
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	# The body keeps its shape so blades, arrows and spells can find it; the
	# ground motion below never asks the physics server to move it.
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	_ground.radius = _body_radius
	_ground.terrain = terrain if terrain != null else _parent_world()
	var shape := CapsuleShape3D.new()
	shape.radius = _body_radius
	shape.height = maxf(_body_height, shape.radius * 2.0 + 0.02)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_build_rig()
	add_to_group(_group_name())
	# One shared group for every wilderness mob: a struck mob's cry reaches
	# whatever is close enough to hear it.
	add_to_group(MobSenses.GROUP)
	_query.collision_mask = 1
	_rng.seed = 7919 + int(absf(global_position.x) * 13.0) + int(absf(global_position.z) * 7.0)
	_strafe_dir = 1.0 if (_rng.randi() & 1) == 0 else -1.0
	_place_on_open_ground()
	_push_phase = int(absf(global_position.x * 7.0 + global_position.z * 13.0)) % SEPARATION_TICKS
	_lod_stride = MobLod.stride_for(_lod_distance())
	_lod_phase = MobLod.phase(global_position, _lod_stride)
	_attack_cooldown = _rng.randf_range(0.25, 0.85)
	state = "IDLE"
	_state_time = 0.0
	Perf.end()


## The profile table and the identity hooks are virtual so a second mobset can
## reuse this state machine instead of forking it. The five devils keep the
## defaults; scripts/forest_mob.gd overrides them.
func _profiles() -> Dictionary:
	return PROFILES


func _group_name() -> String:
	return "devil_mobs"


func _node_prefix() -> String:
	return "Devil_"


func _visual_script():
	return Visual


func _physics_process(delta: float) -> void:
	if replica:
		# A replica still owns its presentation: on a client it is the only
		# thing drawing the mob, so it wants the same distance culling and the
		# same rig release the host's own bodies get.
		_apply_presentation(_lod_distance())
		return
	if not alive:
		CorpsePhysics.settle_root(self, delta)
		return
	# Presentation follows distance, not the think rate: a body far enough away
	# keeps its last pose and stops drawing, which is most of the frame when a
	# hundred of them are spread over the frontier.
	var nearest := _lod_distance()
	_apply_presentation(nearest)
	# Think on this mob's stride. The tick integrates the time it skipped, so
	# speeds, cooldowns and state timers stay in real time.
	var stride := MobLod.stride_for(nearest, _attack_ready(nearest))
	if not MobLod.due(Engine.get_physics_frames(), _lod_phase, stride):
		# No decision this frame, but the body still travels: the motion step is
		# a few array reads and it is what keeps a coarse think rate invisible.
		if _desired.length_squared() > 0.0001 or not _ground.grounded:
			_ground.step(self, delta, _desired, 26.0 if _ground.grounded else 7.0)
			if is_instance_valid(_visual):
				_visual.set_motion(_ground.actual, _ground.grounded)
		return
	if stride != _lod_stride:
		_lod_stride = stride
		_lod_phase = MobLod.phase(global_position, stride)
	# Two clocks: `delta` carries the skipped time for timers, state clocks and
	# cooldowns, while `frame` is the real frame and drives the motion. Moving
	# by the accumulated delta is what used to make a coarse stride jump.
	var frame := delta
	delta *= float(stride)
	Perf.begin("mob.ai")
	# Sight, not proximity, decides whether this mob is in a fight. Losing the
	# view keeps the pursuit alive for `MEMORY_SECONDS`.
	Perf.begin("mob.candidates")
	var candidates := _candidates()
	Perf.end()
	Perf.begin("mob.senses")
	var pursuit := _senses.step(self, candidates, delta, _sight_range(),
		_eye_height(), Callable(self, "_is_hostile"))
	Perf.end()
	Perf.begin("mob.target")
	_target = _senses.target if is_instance_valid(_senses.target) else _resolve_target()
	Perf.end()
	if not is_instance_valid(_target) and not pursuit:
		Perf.end()
		return
	_state_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var focus := _senses.focus() if pursuit else _target.global_position
	var to_target := focus - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector3.FORWARD
	# Town peace: a ranger inside the safe ring is never hunted, alerted or not.
	var aggro := pursuit and not MobSenses.in_safe_ring(safe_center, focus)
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	# Only an aware mob turns toward its quarry. A calm mob keeps the facing it
	# had, so walking up behind it stays possible.
	_face_intent = Vector3.ZERO
	Perf.begin("mob.state")
	match state:
		"IDLE":
			if aggro:
				_enter("CIRCLE")
			else:
				_return_home(delta)
		"RETURN":
			if aggro:
				_enter("CIRCLE")
			else:
				_return_home(delta)
		"CIRCLE":
			if not aggro:
				_enter("RETURN")
			else:
				_circle(delta, distance, direction)
		"WINDUP":
			_face_intent = direction
			if _state_time >= _windup:
				_strike_direction = direction
				_face_intent = direction
				_struck = false
				_enter("STRIKE")
		"STRIKE":
			_face_intent = _strike_direction
			if not _struck and _state_time >= _strike * 0.34:
				_struck = true
				_resolve_strike()
			if _state_time >= _strike:
				_enter("RECOVER")
				_attack_cooldown = _cooldown
		"RECOVER":
			var retreat := -direction
			var tangent := Vector3(-direction.z, 0.0, direction.x) * _strafe_dir
			_move_intent = _steer((retreat + tangent * 0.65).normalized())
			_move_speed = _walk_speed * 0.75
			_face_intent = direction
			if _state_time >= _recover:
				_enter("CIRCLE")
		"STAGGER":
			if _state_time >= _stagger_duration:
				_enter("CIRCLE")
		"DEAD":
			Perf.end()
			return
	Perf.end()
	Perf.begin("mob.separate")
	_separate()
	Perf.end()
	Perf.begin("mob.drive")
	_drive(frame)
	Perf.end()
	Perf.begin("mob.visual")
	if is_instance_valid(_visual):
		_visual.set_motion(_ground.actual, _ground.grounded)
		_visual.set_combat(state, _state_time)
	Perf.end()
	Perf.end()


func _enter(next_state: String, reset_time := true) -> void:
	state = next_state
	if reset_time:
		_state_time = 0.0


func _return_home(delta: float) -> void:
	var offset := home - global_position
	offset.y = 0.0
	if offset.length() > 1.2:
		_move_intent = _steer(offset.normalized())
		_move_speed = _walk_speed
		_face_intent = _move_intent
	elif state != "IDLE":
		_enter("IDLE")


func _circle(delta: float, distance: float, direction: Vector3) -> void:
	# Sight is gone but the pursuit memory is not: hunt the last known spot.
	if not _senses.seen:
		_hunt(delta)
		return
	var reach := _reach
	if distance <= reach + 1.15 and _attack_cooldown <= 0.0:
		_enter("WINDUP")
		return
	var behaviour := _behaviour
	if behaviour == "brute" or behaviour == "sentinel":
		if distance > reach * 1.30:
			_move_intent = _steer(direction)
			_move_speed = _run_speed if distance > reach * 2.2 else _walk_speed
			_face_intent = _move_intent
		else:
			var tangent := Vector3(-direction.z, 0.0, direction.x) * _strafe_dir
			_move_intent = _steer(tangent)
			_move_speed = _walk_speed * 0.4
			_face_intent = direction
		return
	var orbit := _orbit
	var closing := _attack_cooldown <= 0.0
	var radius := maxf(1.1, reach * 0.82) if closing else orbit
	var angle := atan2(global_position.z - _target.global_position.z,
		global_position.x - _target.global_position.x)
	angle += _strafe_dir * delta * _strafe * (1.15 + 0.25 * sin(_state_time * 0.9))
	var ring := _target.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	var offset := ring - global_position
	offset.y = 0.0
	var desired := offset.normalized() if offset.length_squared() > 0.0001 else direction
	if distance > orbit + 3.5:
		desired = direction
	_move_intent = _steer(desired)
	var desired_speed := _run_speed if distance > orbit + 2.0 else _walk_speed
	if closing:
		desired_speed = _run_speed if distance > radius + 1.4 else _walk_speed
	_move_speed = desired_speed
	_face_intent = direction


## Lost sight but still remembers: run down the place the ranger was last
## seen, then sweep the ground while the pursuit timer runs out.
func _hunt(delta: float) -> void:
	var offset := _senses.last_seen - global_position
	offset.y = 0.0
	if offset.length() > MobSenses.ARRIVE_DISTANCE:
		_move_intent = _steer(offset.normalized())
		_move_speed = _run_speed
		_face_intent = _move_intent
		return
	# Standing over the last sighting: scan the ground instead of freezing.
	rotation.y += sin(_state_time * 1.5) * delta * 1.7
	_face_intent = -global_basis.z


func _resolve_strike() -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var spent := _state_time / maxf(0.01, _strike)
	var reach := _reach * (1.0 + 0.18 * spent)
	if to_target.length() <= reach and absf(_target.global_position.y - global_position.y) < 2.4:
		attacked.emit(self, _damage, _target)

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


## How far this profile can see. Distance alone never starts a fight.
func _sight_range() -> float:
	return _sight


func _eye_height() -> float:
	return maxf(0.7, _body_height * MobSenses.EYE_HEIGHT_FRACTION)


## Huntable rangers: alive and outside the town's safe ring.
func _is_hostile(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or candidate.get("alive") == false:
		return false
	return not MobSenses.in_safe_ring(safe_center, candidate.global_position)


func _separate() -> void:
	var frame := Engine.get_physics_frames()
	if (frame + _push_phase) % SEPARATION_TICKS == 0 and frame != _push_at:
		_push_at = frame
		_measure_push()
	var push := _push
	if push.length_squared() > 0.0001:
		if _move_intent.length_squared() > 0.0001:
			_move_intent = (_move_intent + push * 0.85).normalized()
		else:
			_move_intent = push.normalized()
			_move_speed = maxf(_move_speed, _walk_speed * 0.35)


## The neighbour walk itself: every mob inside `SEPARATION`, plus the rangers'
## capsules, against the shared bucket grid.
func _measure_push() -> void:
	var push := Vector3.ZERO
	MobSpace.refresh(get_tree())
	MobSpace.gather(global_position.x, global_position.z)
	var other: Node3D = MobSpace.next_body()
	while other != null:
		if other != self and bool(other.get("alive")) != false:
			var offset: Vector3 = global_position - other.global_position
			offset.y = 0.0
			var gap := offset.length()
			if gap > 0.001 and gap < SEPARATION:
				push += offset / gap * (SEPARATION - gap)
		other = MobSpace.next_body()
	# Rangers are not on the grid: a mob keeps out of a body it can no longer
	# collide with now that nothing steps physics for it.
	for candidate in _candidates():
		if not is_instance_valid(candidate):
			continue
		var away: Vector3 = global_position - candidate.global_position
		away.y = 0.0
		var reach := _body_radius + RANGER_CLEARANCE
		var gap := away.length()
		if gap > 0.001 and gap < reach:
			push += away / gap * (reach - gap) * 1.6
	_push = push


func _drive(delta: float) -> void:
	var desired := _move_intent * _move_speed
	if state == "STRIKE":
		var spent := clampf(_state_time / maxf(0.01, _strike), 0.0, 1.0)
		desired = _strike_direction * _lunge * (1.0 - 0.62 * spent)
	elif state == "WINDUP" or state == "STAGGER":
		desired = Vector3.ZERO
	_desired = desired
	var control := 26.0 if _ground.grounded else 7.0
	if _face_intent.length_squared() > 0.0001 and state != "STAGGER":
		rotation.y = lerp_angle(rotation.y, atan2(-_face_intent.x, -_face_intent.z),
			minf(delta * _turn, 1.0))
	Perf.begin("mob.slide")
	_ground.step(self, delta, desired, control)
	Perf.end()


func _steer(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return direction
	Perf.begin("mob.steer")
	_query.from = global_position + Vector3(0.0, _body_height * 0.45, 0.0)
	_query.to = _query.from + direction.normalized() * 1.55
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		Perf.end()
		return direction
	var left := direction.rotated(Vector3.UP, 1.0)
	_query.to = _query.from + left * 1.7
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		Perf.end()
		return left
	Perf.end()
	return direction.rotated(Vector3.UP, -1.0)


func stagger(seconds: float) -> void:
	if not alive:
		return
	state = "STAGGER"
	_state_time = 0.0
	_stagger_duration = maxf(0.0, seconds)
	_struck = true
	_ground.velocity.x = 0.0
	_ground.velocity.z = 0.0


func note_impact(force: Vector3) -> void:
	_impact_force = Vector3(force.x, 0.0, force.z)


func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	last_hitter = source_id
	var applied := amount * Hitbox.damage_multiplier(headshot)
	health = maxf(0.0, health - applied)
	DamageNumbers.spawn(get_parent(), get_aim_position(), applied, "hit", headshot, health <= 0.0)
	BloodFx.wound(self, blood_rig(), get_aim_position(), applied, headshot,
		health <= 0.0, blood_scale())
	if health <= 0.0:
		_enter_dead(true)
		return
	_respond_to_attack()


## The projectile, blade or spell that landed names itself here before it
## applies damage, so this mob knows who to turn on even when the blow came
## out of the dark.
func note_attacker(attacker: Node3D) -> void:
	_attacker = attacker


## Any landed blow gives the mob the fight, and the cry pulls the neighbours
## inside `MobSenses.SHOUT_RADIUS` into the same hunt.
func _respond_to_attack() -> void:
	var attacker: Node3D = _attacker if is_instance_valid(_attacker) else null
	_attacker = null
	if attacker != null and not _is_hostile(attacker):
		return
	if attacker == null:
		# Unattributed damage (no shooter named): the nearest ranger will do.
		var nearest := _resolve_target()
		if not is_instance_valid(nearest) or not _is_hostile(nearest):
			return
		attacker = nearest
	_senses.notice(attacker, attacker.global_position)
	MobSenses.alert_pack(self, attacker, _senses.last_seen)


## A neighbour was struck within earshot: take up the hunt where it last saw.
func hear_alert(attacker: Node3D, at: Vector3) -> void:
	if not alive or replica:
		return
	if is_instance_valid(attacker) and not _is_hostile(attacker):
		return
	_senses.notice(attacker, at)


## The local death: stopped combat collision, falling root, the limp ragdoll
## and the shared hold. Replicas call it with `announce = false` so gold and the
## kill stay on the host.
func _enter_dead(announce: bool) -> void:
	alive = false
	state = "DEAD"
	_struck = true
	var fall := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, _ground.velocity)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	velocity = Vector3.ZERO
	_ground.velocity = Vector3.ZERO
	if is_instance_valid(_visual):
		_visual.die(fall)
	if announce:
		defeated.emit(self, int(profile.gold))
	# Hold the authored death pose for the shared five minutes, then dissolve.
	CorpseHold.hold(self, _body if is_instance_valid(_body) else self)


## One body's wire record: see `scripts/mob_wire.gd` for the slot layout.
func snapshot(index := -1) -> PackedFloat32Array:
	return MobWire.pack(index, global_position, _ground.velocity, rotation.y,
		_state_time, health, _ground.grounded, alive, state)


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


## Presentation-side mirror of the host's mob: the host owns AI, damage and
## gold, so a replica only replays the snapshot it was handed.
func apply_snapshot(state: PackedFloat32Array, tick: int = -1) -> void:
	var previous_health := health
	var was_alive := alive
	_ingest_pose(state,tick)
	self.state = MobWire.state_of(state)
	_state_time = state[MobWire.AT_STATE_TIME]
	health = state[MobWire.AT_HEALTH]
	alive = MobWire.alive_of(state)
	_ground.velocity = MobWire.velocity_of(state)
	if is_instance_valid(_visual):
		_visual.set_motion(_ground.velocity, MobWire.grounded_of(state))
		_visual.set_combat(self.state, _state_time)
	if health < previous_health:
		var applied: float = previous_health - health
		DamageNumbers.spawn(get_parent(), get_aim_position(), applied, "hit", false, health <= 0.0)
		BloodFx.wound(self, blood_rig(), get_aim_position(), applied, false,
			health <= 0.0, blood_scale())
	if was_alive and not alive:
		_enter_dead(false)


func get_aim_position() -> Vector3:
	return global_position + Vector3(0.0, _aim, 0.0)


## The imported body that the blood field measures for cloth stains.
func blood_rig() -> Node3D:
	if is_instance_valid(_visual):
		var anchor: Node3D = _visual.blood_anchor()
		if is_instance_valid(anchor):
			return anchor
	return _body


func blood_scale() -> float:
	return float(profile.get("blood", 1.0))


## These mobs fight with claws: nothing to stain, but the striking hand still
## comes away wet when the blow lands.
func blood_strike_point() -> Vector3:
	if is_instance_valid(_visual):
		return _visual.strike_hand_position()
	return get_aim_position()


func get_display_name() -> String:
	return str(profile.get("display", mob_id))


func held_weapon_id() -> String:
	return ""


func head_hitbox_center() -> Vector3:
	if is_instance_valid(_visual):
		return _visual.head_hitbox_center()
	return get_aim_position()


func head_hit_profile() -> Vector2:
	if is_instance_valid(_visual):
		return _visual.head_hit_profile()
	return Vector2(0.25, 0.12)


func is_dead() -> bool:
	return not alive


## The frontier world, when nobody handed one in: mobs are children of the
## scene that owns it. Null outside a real world, which the locomotion helper
## answers with a floor ray.
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


## Freezes the rig beyond the animation range. Only a real world does this: a
## mob built in a bare test scene keeps animating so its clip can be read.
## Builds the presentation subtree: the container and the species sampler.
## Used both when the body is first added and when a rig that was released at
## range is rebuilt on approach.
func _build_rig() -> void:
	_body = Node3D.new()
	add_child(_body)
	Perf.begin("spawn.body")
	_visual = _visual_script().new()
	_visual.mob_id = mob_id
	_visual.profile = profile
	_body.add_child(_visual)
	Perf.end()


## Releases the presentation subtree entirely. A skinned body costs about
## fourteen microseconds a frame simply by existing -- a node, a render
## instance and a skeleton -- which freezing its clip does not remove. Only a
## body far enough to be neither seen nor hit gives that up.
func _release_rig() -> void:
	if is_instance_valid(_visual):
		_visual.set_frozen(true)
	_visual = null
	if is_instance_valid(_body):
		_body.free()
	_body = null


func _apply_presentation(distance: float) -> void:
	# A released rig has no `_body`; that is exactly the case the rebuild below
	# exists for, so only a missing world bails out here.
	if terrain == null:
		return
	var live := MobLod.should_animate(distance)
	if live != _presenting:
		_presenting = live
		if _body == null and live:
			# Coming back into range: rebuild the rig and let the next tick's
			# `set_motion`/`set_combat` put it in the right clip.
			_build_rig()
		elif _body != null:
			_body.visible = live
			if is_instance_valid(_visual):
				_visual.set_frozen(not live)
	if not live and _body != null and distance > MobLod.RELEASE_RANGE:
		_release_rig()
		return
	if _body == null:
		return
	var stride := MobLod.anim_stride(distance)
	if stride != _anim_stride:
		_anim_stride = stride
		if is_instance_valid(_visual):
			_visual.set_anim_stride(stride)


## An authored placement can land in a cell the navigation field marks as
## taken (a boulder, a tree, a market stall). A body is nudged onto the nearest
## open ground instead of starting inside an obstacle.
func _place_on_open_ground() -> void:
	if terrain == null or not terrain.is_blocked(global_position.x, global_position.z,
			_body_radius):
		return
	for radius in [1.0, 2.0, 3.0, 4.5, 6.0]:
		for step in 8:
			var angle := float(step) * TAU / 8.0
			var x: float = global_position.x + cos(angle) * radius
			var z: float = global_position.z + sin(angle) * radius
			if not terrain.is_blocked(x, z, _body_radius):
				global_position = Vector3(x, terrain.terrain_height(x, z), z)
				home = global_position
				return


## Copies the profile's numbers into typed fields. `profile` stays the authored
## table (visuals and rewards still read it), but nothing on the tick path
## looks a key up.
func _read_profile() -> void:
	_reach = float(profile.get("reach", 1.6))
	_orbit = float(profile.get("orbit", 3.0))
	_walk_speed = float(profile.get("walk_speed", 1.4))
	_run_speed = float(profile.get("run_speed", 4.0))
	_strafe = float(profile.get("strafe", 0.6))
	_windup = float(profile.get("windup", 0.45))
	_strike = float(profile.get("strike", 0.18))
	_recover = float(profile.get("recover", 0.55))
	_cooldown = float(profile.get("cooldown", 0.9))
	_lunge = float(profile.get("lunge", 2.0))
	_turn = float(profile.get("turn", 6.0))
	_damage = float(profile.get("damage", 0.0))
	_behaviour = str(profile.get("behaviour", ""))
	_body_radius = float(profile.get("radius", 0.3))
	_body_height = float(profile.get("height", 1.8))
	_sight = float(profile.get("sight", 0.0))
	_aim = float(profile.get("aim", 1.0))


## True while this mob is in, or about to start, a swing: the window a player
## reads, and the only one that needs the fine think rate. A body that is
## merely past its cooldown but out of reach is still only orbiting.
func _attack_ready(distance: float) -> bool:
	if state == "WINDUP" or state == "STRIKE" or state == "RECOVER":
		return true
	return _attack_cooldown <= 0.0 and distance <= _reach + 1.15
