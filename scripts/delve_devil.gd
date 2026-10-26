extends CharacterBody3D
## Host-authoritative Cinder devil for the Sunken Delve.
##
## The run controller ticks `step` on the host with the current player list and
## peer devil list. Replicas receive `snapshot` dictionaries and glide toward the
## authoritative position, so combat state stays host-only. The visual rig is
## the shared `devil_visual.gd` presentation node.

signal died(devil)
signal struck(target, amount, position, outcome)

const Geo = preload("res://scripts/geo.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const DevilVisual = preload("res://scripts/devil_visual.gd")
const DevilMob = preload("res://scripts/devil_mob.gd")
const SpeciesVisual = preload("res://scripts/devil_mob_visual.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const Combat = preload("res://scripts/combat.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const HeldWeapon = preload("res://scripts/held_weapon.gd")

const STATE_EMERGE := "EMERGE"
const STATE_CHASE := "CHASE"
const STATE_WINDUP := "WINDUP"
const STATE_STRIKE := "STRIKE"
const STATE_RECOVER := "RECOVER"
const STATE_STAGGER := "STAGGER"
const STATE_DEAD := "DEAD"

const ROLE_IMP := "imp"
const ROLE_DEVIL := "devil"
const ROLE_BONEFIEND := "bonefiend"
const ROLE_BRUTE := "brute"
## The five imported devils that open the frontier's starting court. They keep
## their authored GLB, proportions and claw cadence; only health and damage take
## the depth curve. `devil_mob.gd` remains the one profile table.
const ROLE_HELL_GOAT := "hell_goat"
const ROLE_SUCCUBUS := "succubus"
const ROLE_SPAWN := "spawn"
const ROLE_BEAST := "beast"
const ROLE_GARGOYLE := "gargoyle"
const ROLE_RANGER := "ranger"
const SPECIES_ROLES := [ROLE_HELL_GOAT,ROLE_SUCCUBUS,ROLE_SPAWN,ROLE_BEAST,ROLE_GARGOYLE]

## Role baselines, before the depth scaling that `configure` layers on top.
## `scale` drives every dimension: rig, capsule, warning disc, reach anchors
## and blood size. `warning` and `emerge` are already in meters/seconds.
const PROFILES := {
	"imp": {"display": "Imp", "scale": 0.62, "health": 12.0, "damage": 5.0,
		"speed": 4.3, "reach": 1.6, "emerge": 0.55, "warning": 1.05,
		"cooldown_min": 0.80, "cooldown_max": 1.15},
	"devil": {"display": "Cinder devil", "scale": 1.00, "health": 24.0, "damage": 8.0,
		"speed": 3.4, "reach": 1.9, "emerge": 0.35, "warning": 1.60,
		"cooldown_min": 0.90, "cooldown_max": 1.30},
	"bonefiend": {"display": "Bonefiend", "scale": 1.15, "health": 42.0, "damage": 13.0,
		"speed": 3.5, "reach": 2.15, "emerge": 0.50, "warning": 1.75,
		"cooldown_min": 0.85, "cooldown_max": 1.20},
	"brute": {"display": "Charnel brute", "scale": 1.38, "health": 78.0, "damage": 20.0,
		"speed": 2.9, "reach": 2.45, "emerge": 0.65, "warning": 2.00,
		"cooldown_min": 1.00, "cooldown_max": 1.45},
}

## Multiplier applied to the role damage baseline by the held weapon.
const WEAPON_DAMAGE := {"claw": 1.0, "dagger": 0.75, "sword": 1.35}

## Easy-to-hard ordering of every role the delve can summon. The ladder roles
## follow their scaled health and damage; the court devils sit at 0.45 health and
## 0.65 damage of their frontier baselines, which drops the spawn and the
## succubus under a cinder devil; a crimson clone brings a player rig, armor and
## a bow, so it closes the wave. `delve.gd` schedules its spawns by this order.
const ROLE_DIFFICULTY := {
	ROLE_IMP: 0,
	ROLE_SPAWN: 1,
	ROLE_DEVIL: 2,
	ROLE_SUCCUBUS: 3,
	ROLE_HELL_GOAT: 4,
	ROLE_BONEFIEND: 5,
	ROLE_GARGOYLE: 6,
	ROLE_BEAST: 7,
	ROLE_BRUTE: 8,
	ROLE_RANGER: 9,
}

## The frontier's starting-court devils are tuned for a solo ranger's opening
## field, so the delve brings them in at a court scale that sits between the
## imps and the bonefiends at depth one instead of multiplying the wave by four.
## The depth curve still grows them at the same rate as every other role.
const COURT_HEALTH_SCALE := 0.45
const COURT_DAMAGE_SCALE := 0.65

const WINDUP_SECONDS := 0.38
const STRIKE_SECONDS := 0.14
const STRIKE_HIT_TIME := 0.06
const RECOVER_SECONDS := 0.55
const STAGGER_SECONDS := 0.8
const SEPARATION_RADIUS := 1.15
const LIMIT := 16.0

# Body proportions at role scale 1.0 (the Cinder devil profile).
const BODY_RADIUS := 0.22
const BODY_HEIGHT := 0.90
const AIM_HEIGHT := 0.55
const HEAD_HEIGHT := 0.78
const BLOOD_SIZE := 0.75
const STRIKE_HEIGHT := 0.45
# Emerge sigil at role scale 1.0. The torus radius is authored at 0.95 of the
# mesh scale so the ring reads at its nominal radius.
const EMERGE_RING_RADIUS := 0.95
const EMERGE_COLUMN_RADIUS := 0.30
const EMERGE_COLUMN_HEIGHT := 1.15

var authoritative := false
var alive := true
var _impact_force := Vector3.ZERO
# Devil-profile baselines; `configure` replaces them with the role and depth
# numbers before the first snapshot arrives.
var health := 24.0
var max_health := 24.0
## Slot of the ranger whose damage landed last; the delve reads it on death so
## off-hand skull trinkets only pay out to the killer.
var last_hitter := -1
var enemy_id := 0
var devil_weapon := "claw"
var depth := 1
var chase_speed := 3.4
var target = null
var state := STATE_EMERGE

var _role := ROLE_DEVIL
var _body_scale := 1.0
var _body_radius := BODY_RADIUS
var _body_height := BODY_HEIGHT
var _aim_height := AIM_HEIGHT
var _blood_size := BLOOD_SIZE
var _emerge_seconds := 0.35
var _warning_radius := 1.6
var _cooldown_min := 0.9
var _cooldown_max := 1.3
var _windup_seconds := WINDUP_SECONDS
var _strike_seconds := STRIKE_SECONDS
var _strike_hit_time := STRIKE_HIT_TIME
var _recover_seconds := RECOVER_SECONDS
var _state_time := 0.0
var _attack_damage := 8.0
var _attack_reach := 1.9
var _attack_cooldown := 0.0
var _struck := false
var _side_bias := 1.0
var _death_handled := false
var _received_pose := false
var _net_position := Vector3.ZERO
## Buffered server states for the replica's delayed render (see `enemy.gd`).
var _timeline = NetReplication.mob_timeline()
var _rng := RandomNumberGenerator.new()
var _visual
var _visual_kind := ""
var _warning: MeshInstance3D
var _collider: CollisionShape3D
var _shape: CapsuleShape3D
var _emerge: Node3D
var _emerge_ring: MeshInstance3D
var _emerge_column: MeshInstance3D
var _emerge_light: OmniLight3D
var _ring_material: StandardMaterial3D
var _column_material: StandardMaterial3D
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	name = "CinderDevil"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	_shape = CapsuleShape3D.new()
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	add_child(_collider)
	# The visual follows the role, which arrives in `configure`, so the correct
	# rig (procedural Cinder devil or an imported starting-court species) is
	# built once instead of being swapped after the body already exists.
	var warning_material := Geo.material(Color(0.95,0.22,0.08,0.34))
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning_material.emission_enabled = true
	warning_material.emission = Color("ff3b16")
	warning_material.emission_energy_multiplier = 2.2
	_warning = Geo.cylinder(self,1.0,1.0,0.02,Vector3(0,0.035,0),warning_material,40)
	_warning.visible = false
	_build_emerge_fx()
	_refresh_metrics()
	_query.collision_mask = 1


func configure(next_id: int, weapon: String, next_depth: int, role: String = ROLE_DEVIL) -> void:
	enemy_id = next_id
	depth = maxi(1, next_depth)
	devil_weapon = str(weapon).to_lower()
	if not WEAPON_DAMAGE.has(devil_weapon):
		devil_weapon = "claw"
	_apply_role(str(role).to_lower())
	# Per-enemy randomness: two devils in a wave never share a swing rhythm.
	_rng.seed = 4409 + maxi(enemy_id,0) * 277
	_attack_cooldown = 0.30 + _rng.randf() * 0.35
	_side_bias = 1.0 if maxi(enemy_id,0) % 2 == 0 else -1.0
	health = max_health
	alive = true
	_death_handled = false
	_impact_force = Vector3.ZERO
	_struck = false
	state = STATE_EMERGE
	_state_time = 0.0
	if is_instance_valid(_warning):
		_warning.visible = false
	_update_emerge_fx()


func spawn_at(point: Vector3, facing: Vector3 = Vector3.ZERO) -> void:
	global_position = point
	_net_position = point
	_received_pose = true
	var flat := Vector3(facing.x,0.0,facing.z)
	if flat.length_squared() > 0.0001:
		rotation.y = atan2(-flat.x,-flat.z)
	velocity = Vector3.ZERO
	alive = true
	health = max_health
	_death_handled = false
	_impact_force = Vector3.ZERO
	_struck = false
	target = null
	collision_layer = 2
	collision_mask = 1
	_attack_cooldown = 0.30 + _rng.randf() * 0.35
	state = STATE_EMERGE
	_state_time = 0.0
	if is_instance_valid(_warning):
		_warning.visible = false
	_update_emerge_fx()


func role() -> String:
	return _role


func display_name() -> String:
	if SPECIES_ROLES.has(_role):
		return str(DevilMob.PROFILES[_role]["display"])
	return str(PROFILES[_role]["display"])


## Applies the role profile plus the depth curve. Deeper chambers breed
## heavier, faster devils; speed growth is capped so they keep telegraphing
## instead of teleporting past the strike window.
func _apply_role(next_role: String) -> void:
	var known := PROFILES.has(next_role) or SPECIES_ROLES.has(next_role)
	_role = next_role if known else ROLE_DEVIL
	var step := float(maxi(1,depth) - 1)
	if SPECIES_ROLES.has(_role):
		_apply_species(step)
	else:
		_apply_depth_role(step)
	_ensure_visual()
	_refresh_metrics()


func _apply_depth_role(step: float) -> void:
	var profile: Dictionary = PROFILES[_role]
	_body_scale = float(profile["scale"])
	_body_radius = BODY_RADIUS * _body_scale
	_body_height = BODY_HEIGHT * _body_scale
	_aim_height = AIM_HEIGHT * _body_scale
	_blood_size = BLOOD_SIZE * _body_scale
	_warning_radius = float(profile["warning"])
	_emerge_seconds = float(profile["emerge"])
	_cooldown_min = float(profile["cooldown_min"])
	_cooldown_max = float(profile["cooldown_max"])
	_attack_reach = float(profile["reach"])
	_attack_damage = float(profile["damage"]) * float(WEAPON_DAMAGE.get(devil_weapon,1.0))
	_attack_damage *= 1.0 + 0.15 * step
	max_health = float(profile["health"]) * (1.0 + 0.28 * step)
	chase_speed = float(profile["speed"]) * minf(1.35, 1.0 + 0.03 * step)
	_windup_seconds = WINDUP_SECONDS
	_strike_seconds = STRIKE_SECONDS
	_strike_hit_time = STRIKE_HIT_TIME
	_recover_seconds = RECOVER_SECONDS


## The five starting-court species keep their authored proportions, claw reach
## and attack clips; the depth curve touches health, damage and speed only.
func _apply_species(step: float) -> void:
	devil_weapon = "claw"
	var profile: Dictionary = DevilMob.PROFILES[_role]
	_body_radius = float(profile["radius"])
	_body_height = maxf(float(profile["height"]), _body_radius * 2.0 + 0.02)
	_body_scale = _body_height / BODY_HEIGHT
	_aim_height = float(profile["aim"])
	_blood_size = float(profile["blood"])
	_warning_radius = clampf(float(profile["reach"]) * 0.85, 0.9, 2.2)
	_emerge_seconds = 0.5
	_windup_seconds = float(profile["windup"])
	_strike_seconds = float(profile["strike"])
	_strike_hit_time = _strike_seconds * 0.34
	_recover_seconds = float(profile["recover"])
	_cooldown_min = float(profile["cooldown"])
	_cooldown_max = _cooldown_min * 1.3
	_attack_reach = float(profile["reach"])
	_attack_damage = float(profile["damage"]) * COURT_DAMAGE_SCALE * (1.0 + 0.15 * step)
	max_health = float(profile["health"]) * COURT_HEALTH_SCALE * (1.0 + 0.28 * step)
	chase_speed = float(profile["run_speed"]) * minf(1.35, 1.0 + 0.03 * step)


## Builds the rig the current role needs. Imported species load their authored
## GLB through `DevilMobVisual`; the four depth roles keep the procedural rig.
func _ensure_visual() -> void:
	var wanted := "mob" if SPECIES_ROLES.has(_role) else "procedural"
	if _visual_kind == wanted and is_instance_valid(_visual):
		return
	if is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	if wanted == "mob":
		var species := SpeciesVisual.new()
		species.name = "DevilMobVisual"
		species.mob_id = _role
		species.profile = DevilMob.PROFILES[_role]
		add_child(species)
		_visual = species
	else:
		var demon := DevilVisual.new()
		demon.name = "DevilVisual"
		add_child(demon)
		_visual = demon
		demon.set_weapon(devil_weapon)
	_visual_kind = wanted


## Pushes the role metrics into every physical measurement: capsule, rig,
## warning disc and sigil. The imported rigs already carry authored scale.
func _refresh_metrics() -> void:
	if is_instance_valid(_shape):
		_shape.radius = _body_radius
		_shape.height = _body_height
	if is_instance_valid(_collider):
		_collider.position.y = _body_height * 0.5
	if is_instance_valid(_visual):
		_visual.scale = Vector3.ONE if _visual_kind == "mob" else Vector3.ONE * _body_scale
	if is_instance_valid(_warning):
		_warning.scale = Vector3(_warning_radius,1.0,_warning_radius)
	_update_emerge_fx()


## The imported rigs animate authored IDLE/CIRCLE/attack clips; the delve's
## EMERGE and CHASE names map onto those two locomotion states.
func _mob_state() -> String:
	if state == STATE_EMERGE:
		return "IDLE"
	if state == STATE_CHASE:
		return "CIRCLE"
	return state


func _present_motion(actual: Vector3, grounded: bool) -> void:
	if is_instance_valid(_visual):
		_visual.set_motion(actual,grounded)


func _present_state() -> void:
	if not is_instance_valid(_visual):
		return
	if _visual_kind == "mob":
		_visual.set_combat(_mob_state(),_state_time)
	else:
		_visual.set_action(state,_state_time)


func _build_emerge_fx() -> void:
	_emerge = Node3D.new()
	_emerge.name = "EmergeSigil"
	_emerge.visible = false
	add_child(_emerge)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.90
	ring.outer_radius = 1.0
	ring.rings = 12
	ring.ring_segments = 40
	_ring_material = Geo.material(Color(1.0,0.42,0.12,0.85))
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.emission_enabled = true
	_ring_material.emission = Color("ff5a1e")
	_ring_material.emission_energy_multiplier = 2.0
	_emerge_ring = Geo.mesh_node(_emerge,ring,_ring_material,Vector3(0,0.03,0))
	var column := CylinderMesh.new()
	column.bottom_radius = 1.0
	column.top_radius = 0.55
	column.height = 1.0
	column.radial_segments = 16
	_column_material = Geo.material(Color(1.0,0.48,0.16,0.5))
	_column_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_column_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_column_material.emission_enabled = true
	_column_material.emission = Color("ff7a2a")
	_column_material.emission_energy_multiplier = 1.8
	_emerge_column = Geo.mesh_node(_emerge,column,_column_material,Vector3.ZERO)
	_emerge_light = OmniLight3D.new()
	_emerge_light.light_color = Color("ff6a24")
	_emerge_light.light_energy = 0.0
	_emerge.add_child(_emerge_light)


## Presentation only: the sigil follows the state clock, so host and replicas
## fade it together and it never gates gameplay or authority.
func _update_emerge_fx() -> void:
	if not is_instance_valid(_emerge):
		return
	if state != STATE_EMERGE or not (authoritative or _received_pose):
		_emerge.visible = false
		return
	var progress := clampf(_state_time / maxf(_emerge_seconds,0.05),0.0,1.0)
	_emerge.visible = true
	_place_emerge_fx(progress,1.0-progress,sin(progress*PI))


func _place_emerge_fx(progress: float, fade: float, bloom: float) -> void:
	var ring_scale := EMERGE_RING_RADIUS * _body_scale / 0.95 * (0.72 + 0.36 * progress)
	_emerge_ring.scale = Vector3(ring_scale,0.22,ring_scale)
	var height := EMERGE_COLUMN_HEIGHT * _body_scale * (0.45 + 0.55 * progress)
	_emerge_column.scale = Vector3(EMERGE_COLUMN_RADIUS * _body_scale,height,
		EMERGE_COLUMN_RADIUS * _body_scale)
	_emerge_column.position.y = height * 0.5
	_emerge_light.position.y = height * 0.6
	_emerge_light.omni_range = 3.0 * _body_scale
	_emerge_light.light_energy = 2.4 * fade
	var ring_color := _ring_material.albedo_color
	ring_color.a = 0.85 * fade
	_ring_material.albedo_color = ring_color
	_ring_material.emission_energy_multiplier = 1.2 + 2.4 * bloom
	var column_color := _column_material.albedo_color
	column_color.a = 0.5 * fade
	_column_material.albedo_color = column_color
	_column_material.emission_energy_multiplier = 1.0 + 2.6 * bloom


func step(delta: float, actors: Array = [], peers: Array = []) -> void:
	if not authoritative or not alive:
		return
	_state_time += delta
	_attack_cooldown = maxf(0.0,_attack_cooldown-delta)
	# Pick the closest survivor while chasing so a swing is never redirected
	# mid-windup by a second player stepping closer.
	if state == STATE_CHASE or state == STATE_EMERGE or not _target_alive(target):
		target = _nearest_target(actors)
	var to_target := Vector3.ZERO
	var distance := INF
	if _target_alive(target):
		to_target = target.global_position-global_position
		to_target.y = 0.0
		distance = to_target.length()
	var move_intent := Vector3.ZERO
	var face_intent := Vector3.ZERO
	match state:
		STATE_EMERGE:
			if _state_time >= _emerge_seconds:
				_enter(STATE_CHASE)
		STATE_CHASE:
			if distance <= _attack_reach and _attack_cooldown <= 0.0:
				_begin_windup()
			elif distance < INF:
				move_intent = _steer(_with_separation(to_target.normalized(),peers))
				face_intent = to_target.normalized()
		STATE_WINDUP:
			if distance < INF:
				face_intent = to_target.normalized()
			if _state_time >= _windup_seconds:
				_enter(STATE_STRIKE)
		STATE_STRIKE:
			if distance < INF:
				face_intent = to_target.normalized()
			if not _struck and _state_time >= _strike_hit_time:
				_struck = true
				_strike()
			if _state_time >= _strike_seconds:
				_attack_cooldown = _rng.randf_range(_cooldown_min,_cooldown_max)
				_enter(STATE_RECOVER)
		STATE_RECOVER:
			if distance < INF:
				face_intent = to_target.normalized()
			if _state_time >= _recover_seconds:
				_enter(STATE_CHASE)
		STATE_STAGGER:
			if _state_time >= STAGGER_SECONDS:
				_enter(STATE_CHASE)
		_:
			pass
	if move_intent.length_squared() > 0.0001:
		var desired := move_intent.normalized()*chase_speed
		velocity.x = move_toward(velocity.x,desired.x,26.0*delta)
		velocity.z = move_toward(velocity.z,desired.z,26.0*delta)
	else:
		velocity.x = move_toward(velocity.x,0.0,26.0*delta)
		velocity.z = move_toward(velocity.z,0.0,26.0*delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 18.0*delta
	if face_intent.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y,atan2(-face_intent.x,-face_intent.z),minf(delta*10.0,1.0))
	var before := global_position
	Perf.begin("delve.slide")
	move_and_slide()
	Perf.end()
	position.x = clampf(position.x,-LIMIT,LIMIT)
	position.z = clampf(position.z,-LIMIT,LIMIT)
	var actual := (global_position-before)/maxf(delta,0.0001)
	_present_motion(actual,is_on_floor())
	_present_state()


func note_impact(force: Vector3) -> void:
	_impact_force = Vector3(force.x, 0.0, force.z)


func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	last_hitter = source_id
	var applied := amount * Hitbox.damage_multiplier(headshot)
	health = maxf(0.0,health-applied)
	DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",headshot,health <= 0.0)
	BloodFx.wound(self,blood_rig(),get_aim_position(),applied,headshot,
		health <= 0.0,blood_scale())
	if health <= 0.0:
		_die(true)


func snapshot() -> Dictionary:
	return {"id":enemy_id,"pos":position,"yaw":rotation.y,"state":state,"time":_state_time,
		"health":health,"alive":alive,"weapon":devil_weapon,"depth":depth,"role":_role}


func apply_snapshot(snapshot_state: Dictionary, tick: int = -1) -> void:
	authoritative = false
	var had_pose := _received_pose
	var previous_health := health
	enemy_id = int(snapshot_state.get("id",enemy_id))
	var next_role := str(snapshot_state.get("role",_role))
	var next_weapon := str(snapshot_state.get("weapon",devil_weapon))
	if next_role != _role or next_weapon != devil_weapon:
		devil_weapon = next_weapon
		_apply_role(next_role)
	health = float(snapshot_state.get("health",health))
	if had_pose and previous_health-health > 0.01:
		# Replicas never apply damage; the health delta is their only hit signal.
		BloodFx.wound(self,blood_rig(),get_aim_position(),previous_health-health,
			false,health <= 0.0,blood_scale())
	state = str(snapshot_state.get("state",state))
	_state_time = float(snapshot_state.get("time",_state_time))
	_present_state()
	var next_position: Vector3 = snapshot_state.get("pos",_net_position)
	_net_position = next_position
	var at := tick if tick >= 0 else _timeline.newest_tick() + 1
	var now := Time.get_ticks_msec()/1000.0
	var yaw := float(snapshot_state.get("yaw",rotation.y))
	if not _received_pose:
		_timeline.reset_to(next_position,Vector3.ZERO,yaw,at,now)
		position = next_position
		rotation.y = yaw
		_received_pose = true
	else:
		_timeline.push(at,next_position,Vector3.ZERO,yaw,now)
		rotation.y = _timeline.sample().yaw
	var next_alive := bool(snapshot_state.get("alive",alive))
	if is_instance_valid(_warning):
		_warning.visible = next_alive and state == STATE_WINDUP
	if not next_alive:
		_die(false)
	elif not _death_handled:
		alive = true


func blood_rig() -> Node3D:
	if is_instance_valid(_visual):
		var anchor: Node3D = _visual.blood_anchor()
		if is_instance_valid(anchor):
			return anchor
	return self

func blood_scale() -> float:
	return _blood_size

func blood_weapon_anchor(_hand: String = "") -> Node3D:
	if _visual_kind != "mob" and is_instance_valid(_visual):
		return _visual.weapon_anchor()
	return null

func blood_strike_point() -> Vector3:
	if is_instance_valid(_visual):
		return _visual.strike_hand_position()
	return get_aim_position()

func get_aim_position() -> Vector3:
	return global_position + Vector3(0,_aim_height,0)


func head_hitbox_center() -> Vector3:
	if is_instance_valid(_visual):
		return _visual.head_hitbox_center()
	return global_position + Vector3(0,HEAD_HEIGHT * _body_scale,0)


func head_hit_profile() -> Vector2:
	if _visual_kind == "mob" and is_instance_valid(_visual):
		return _visual.head_hit_profile()
	return Vector2(Hitbox.DEVIL_HEAD_RADIUS,Hitbox.DEVIL_HEAD_HALF_HEIGHT) * _body_scale


func get_display_name() -> String:
	return display_name()

func held_weapon_id() -> String:
	return HeldWeapon.item_id(devil_weapon)


## The delve advances living devils through `step`; a dead one still owns its
## own fall so a corpse killed during a leap reaches the chamber floor.
func _physics_process(delta: float) -> void:
	if not authoritative:
		return
	if not alive:
		CorpsePhysics.settle_root(self, delta)


func _process(delta: float) -> void:
	_update_emerge_fx()
	if authoritative or not _received_pose:
		return
	var before := position
	if state != STATE_DEAD:
		_timeline.advance(delta)
		position = _timeline.sample().pos
	if is_instance_valid(_visual):
		_present_motion((position-before)/maxf(delta,0.0001),true)
		_present_state()


func _begin_windup() -> void:
	_struck = false
	_enter(STATE_WINDUP)
	if _target_alive(target):
		var to_target: Vector3 = target.global_position-global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			rotation.y = atan2(-to_target.x,-to_target.z)


func _enter(next_state: String) -> void:
	state = next_state
	_state_time = 0.0
	if is_instance_valid(_warning):
		_warning.visible = next_state == STATE_WINDUP
	_update_emerge_fx()


func _strike() -> void:
	if not _target_alive(target):
		return
	var to_target: Vector3 = target.global_position-global_position
	to_target.y = 0.0
	if to_target.length() > _attack_reach:
		return
	if to_target.length_squared() > 0.0001:
		var facing := -global_basis.z
		if facing.dot(to_target.normalized()) < 0.0:
			return
	_query.from = global_position + Vector3(0,STRIKE_HEIGHT * _body_scale,0)
	_query.to = target.global_position + Vector3(0,0.6,0)
	if not get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return
	var outcome: int = Combat.DEFENSE_NONE
	if target.has_method("receive_melee"):
		outcome = target.receive_melee(_attack_damage,20+enemy_id,global_position,false)
	elif target.has_method("take_damage"):
		target.take_damage(_attack_damage,20+enemy_id)
	struck.emit(target,_attack_damage,global_position,outcome)
	if outcome == Combat.DEFENSE_NONE and target is Node3D:
		BloodFx.impact(self,(target as Node3D).get_aim_position(),to_target,
			_attack_damage,false)
		BloodFx.stain_attacker(self,_attack_damage)
	if outcome == Combat.DEFENSE_PARRY:
		_enter(STATE_STAGGER)


func _die(announce: bool) -> void:
	if _death_handled:
		return
	_death_handled = true
	alive = false
	state = STATE_DEAD
	_state_time = 0.0
	var fall := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, velocity)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 1
	if is_instance_valid(_warning):
		_warning.visible = false
	if is_instance_valid(_visual):
		if _visual_kind == "mob":
			_visual.die(fall)
		else:
			_visual.set_weapon("claw")
			_visual.set_action(STATE_DEAD,0.0)
			_visual.die()
	_update_emerge_fx()
	if announce:
		died.emit(self)
	if is_inside_tree():
		CorpseHold.hold(self, _visual if is_instance_valid(_visual) else self)


func _nearest_target(actors: Array):
	var nearest = null
	var best := INF
	for candidate in actors:
		if candidate == self or not _target_alive(candidate):
			continue
		var offset: Vector3 = candidate.global_position-global_position
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < best:
			best = distance
			nearest = candidate
	return nearest


func _target_alive(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.has_method("is_downed"):
		return not candidate.is_downed()
	var flag = candidate.get("alive")
	if flag == null:
		return true
	return bool(flag)


func _with_separation(direction: Vector3, peers: Array) -> Vector3:
	var push := Vector3.ZERO
	for other in peers:
		if other == self or not is_instance_valid(other):
			continue
		var flag = other.get("alive")
		if flag != null and not bool(flag):
			continue
		var offset: Vector3 = global_position-other.global_position
		offset.y = 0.0
		var spread := offset.length()
		if spread > 0.001 and spread < SEPARATION_RADIUS:
			push += offset/spread*(SEPARATION_RADIUS-spread)
	return direction + push*0.9


func _steer(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	var planar := Vector3(direction.x,0.0,direction.z).normalized()
	_query.from = global_position + Vector3(0,STRIKE_HEIGHT * _body_scale,0)
	_query.to = _query.from + planar*1.4
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return planar
	# Glide around the pillar: blend along its surface normal with the desired
	# heading, using a per-enemy side bias so both devils do not pick one edge.
	var normal: Vector3 = hit.normal
	var tangent := normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()*_side_bias
	var blended := (tangent + planar*0.35).normalized()
	_query.to = _query.from + blended*1.3
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return blended
	return (planar*0.35-tangent).normalized()
