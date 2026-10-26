extends Node3D

const Archer = preload("res://scripts/archer.gd")
const World = preload("res://scripts/range_world.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Thrown = preload("res://scripts/thrown_weapon.gd")
const Enemy = preload("res://scripts/enemy.gd")
const DevilMob = preload("res://scripts/devil_mob.gd")
const ForestMob = preload("res://scripts/forest_mob.gd")
const RangerClone = preload("res://scripts/ranger_clone.gd")
const LootRules = preload("res://scripts/loot_rules.gd")
const Hud = preload("res://scripts/hud.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Combat = preload("res://scripts/combat.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityRunner = preload("res://scripts/ability_runner.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")
const SpellProjectile = preload("res://scripts/spell_projectile.gd")
const BackstabAbility = preload("res://scripts/backstab_ability.gd")
const Stamina = preload("res://scripts/stamina.gd")
const TrinketStats = preload("res://scripts/trinket_stats.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const BloodSurface = preload("res://scripts/blood_surface.gd")
const BloodyFeet = preload("res://scripts/bloody_feet.gd")
const DodgeRoll = preload("res://scripts/dodge_roll.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const RunningSlide = preload("res://scripts/running_slide.gd")
const CoverMovement = preload("res://scripts/cover_movement.gd")
const ShoulderCamera = preload("res://scripts/shoulder_camera.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const LootPickup = preload("res://scripts/loot_pickup.gd")
const WorldUI = preload("res://scripts/world_ui.gd")
const Seat = preload("res://scripts/arena_actor.gd")
const SeatLoadout = preload("res://scripts/seat_loadout.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const NetLimits = preload("res://scripts/net_limits.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const LagCompensation = preload("res://scripts/lag_compensation.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const MobWire = preload("res://scripts/mob_wire.gd")
const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5
## A backstab needs a live body under the crosshair: frontier enemies sit on
## layer 2, so the preflight searches that layer only.
const BACKSTAB_MASK := 2
const BACKSTAB_RANGE := 8.0
const PICKUP_RADIUS := 1.6
const FULL_MESSAGE_INTERVAL := 2.5
const MAX_HEALTH := 100.0
const WORLD_SEATS := 4
const NET_TICK := 0.05
const ENEMY_TICK := 0.0667
## The longest rewind the host performs for one client action: half a second.
const MAX_LAG_TICKS := 30
const ENEMY_RELEVANCE := 70.0
# Deterministic frontier drops: every entry is a real PlayerState item id and the
# first eight cover all eight equipment categories the paperdoll understands.
const LOOT_SEQUENCE := [
	"dagger_iron", "shield_buckler", "staff_fire", "ring_copper",
	"focus_tome", "neck_ember", "armor_mail_chest", "sword_short",
	"shield_kite", "staff_bone", "ring_silver", "focus_skull",
	"neck_bone", "armor_plate_hands", "shield_tower", "ring_blood",
]

var world
var archer
var hud
var world_ui
var audio
var _player_state
var _delve_host := false
var _delve_port := 7777
var _delve_name := ""
var _world_host := false
var _world_join := ""
var _world_port := 7777
var _world_address := "127.0.0.1"
var _world_name := ""
## One-way simulated link delay and its spread, in seconds (see `LagQueue`).
var _link_lag := 0.0
var _link_jitter := 0.0
## `--net-diag` prints one line a second of what the netcode is doing, so a
## report from a real match carries numbers instead of "it feels jittery".
var _net_diag := false
var _diag_elapsed := 0.0
var _diag_corrections := 0
var _diag_rig_step := 0.0
var _diag_boom_step := 0.0
var _diag_drift := 0.0
var _diag_previous_rig := Vector3.INF
var _diag_previous_boom := -1.0
## Mob-replica smoothness over the last diagnostic second: frames a body was
## dead-reckoned, and teleports it had to be restarted across.
var _diag_mob_extrapolated := 0
var _diag_mob_restarts := 0
var _diag_mob_count := 0
var _diag_restart_base := -1
var network_role := "offline"
var local_slot := -1
var server_tick := 0
var _player_name := "Ranger"
var _endpoint := ""
var _peer_slots: Dictionary = {}
var _seats: Dictionary = {}
var _seat_list: Array = []
var _enemies_by_index: Array = []
var _snapshot_ticks := PackedInt32Array([-1,-1,-1,-1])
## The server tick this client draws the world at, learned from arrivals.
var _clock = NetReplication.NetClock.new()
## One second of mob poses so a client's swing resolves against its view.
var _lag = LagCompensation.new()
## Simulated link quality for QC (`--net-lag`, `--net-jitter`): the
## high-frequency streams are held this long before they are applied. Disabled
## unless the flags are passed, and then each handler costs one comparison.
var _link = NetReplication.LagQueue.new()
var _join_elapsed := 0.0
var _send_elapsed := 0.0
var _enemy_elapsed := 0.0
var _enemy_sends := 0
var _client_aim := Vector3.ZERO
var _client_aim_origin := Vector3.ZERO
var _client_aim_origin_valid := false
var _local_anchor_swapped := false
var _client_dead_notified := false
var _descent_refusal_cooldown := 0.0
var _anchor_player: CharacterBody3D
var _anchor_rig
var _anchor_combat
var _anchor_cover
var _anchor_ability
var combat
var ability
var roll
var step
var slide
var cover
var _next_swing_side := 0
var shoulder_camera := ShoulderCamera.new()
var _peek_requested := false
var _peek_right := Vector3.RIGHT
var _movement_direction := Vector3.ZERO
var player: CharacterBody3D
var camera: Camera3D
var enemies: Array[CharacterBody3D] = []
var arrows: Array[Node3D] = []
var thrown_weapons: Array[Node3D] = []
var loot_pickups: Array[Node3D] = []
var _loot_cursor := 0
var _full_message_cooldown := 0.0
var health := MAX_HEALTH
var stamina := Stamina.MAX
var max_health := MAX_HEALTH
var max_stamina := Stamina.MAX
## Worn trinket kit and its summed modifiers, mirrored from the rig.
var trinkets: Dictionary = {"neck":"", "ring1":"", "ring2":"", "off":""}
var trinket_stats: Dictionary = {}
## Energy Shield ward: while it runs, `ward_absorb` of every hit is paid from
## stamina at `ward_stamina_scale` times that share instead of from health.
var ward_seconds := 0.0
var ward_absorb := 0.5
var ward_stamina_scale := 2.0
var _consume_kind := ""
var _consume_time := 0.0
var _heal_remaining := 0.0
var _heal_rate := 0.0
var _sprint_exhausted := false
var gold := 0
var kills := 0
var shots := 0
var respawns := 0
var activated: Dictionary = {}
var inspecting := false
var camera_yaw := 0.22
var camera_pitch := 0.08
var camera_distance := 4.5
## How fast the third-person boom may shorten and lengthen, in metres per
## second. A resolved collision shortens the boom instantly; zooming it at a
## bounded speed keeps a passing trunk from shaking the whole view.
const CAMERA_BOOM_IN := 18.0
const CAMERA_BOOM_OUT := 5.0
## The boom length actually used. The camera collision resolves a shorter boom
## the instant scenery crosses the line behind the ranger, but snapping it back
## out the moment that scenery clears reads as the whole view jumping; it eases
## out instead. -1 means "no previous frame, take the resolved length".
var _camera_boom := -1.0
var camera_focus := Vector3.ZERO
var _camera_ready := false
var _orbiting := false
var _orbit_pointer := Vector2.ZERO
var _mouse_drawing := false
var _throw_held := false
var _cursor_free := false
var _jump_requested := false
var _interaction_id := ""
var _interaction_kind := ""
var _interaction_vendor := -1
var _interaction_allowed := false
var _entering_scene := false
var _aim_query := PhysicsRayQueryParameters3D.new()
var _aim_exclude: Array[RID] = []
var _floor_query := PhysicsRayQueryParameters3D.new()
var _bloody_feet := BloodyFeet.new()

func _ready() -> void:
	_read_arguments()
	_player_state = get_node_or_null("/root/PlayerState")
	_aim_query.collision_mask = 1 | 2
	_floor_query.collision_mask = 1
	world = World.new()
	world.name = "IronwoodFrontier"
	add_child(world)
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_meta("ironwood_player", true)
	player.set_meta("ironwood_damage_target", self)
	player.collision_layer = 4
	player.collision_mask = 1 | 2
	player.floor_snap_length = 0.6
	player.floor_max_angle = deg_to_rad(46.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.80
	var collider := CollisionShape3D.new()
	collider.position.y = 0.90
	collider.shape = capsule
	player.add_child(collider)
	add_child(player)
	player.global_position = world.player_spawn + Vector3(0, 0.15, 0)
	archer = Archer.new()
	player.add_child(archer)
	archer.set_ground_sampler(_sample_floor)
	combat = Combat.new()
	add_child(combat)
	combat.setup(archer, player.position + Vector3(0, 1.4, -24))
	combat.shot.connect(_on_arrow_released)
	combat.thrown.connect(_on_weapon_thrown)
	combat.actor = player
	# The frontier's own ranger is seat 0, so melee kills carry the same slot
	# id its arrows do and the skull trinkets can pay the killer.
	combat.source_id = 0
	roll = DodgeRoll.new()
	add_child(roll)
	step = DodgeStep.new()
	add_child(step)
	slide = RunningSlide.new()
	add_child(slide)
	cover = CoverMovement.new()
	add_child(cover)
	cover.setup(player,collider)
	combat.cover = cover
	ability = AbilityRunner.new()
	add_child(ability)
	ability.setup(self,archer,combat,WALK_SPEED)
	_bind_ability_cues(ability)
	_anchor_player = player
	_anchor_rig = archer
	_anchor_combat = combat
	_anchor_cover = cover
	_anchor_ability = ability
	camera = Camera3D.new()
	camera.name = "AdventureCamera"
	camera.fov = 59.0
	camera.near = 0.08
	camera.far = 450.0
	camera.current = true
	add_child(camera)
	audio = Audio.new()
	add_child(audio)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.bow_selected.connect(equip_bow)
	hud.armor_selected.connect(equip_armor_slot)
	hud.sword_selected.connect(equip_sword)
	hud.weapon_selected.connect(equip_weapon)
	hud.shield_selected.connect(equip_shield)
	hud.consumable_selected.connect(use_consumable)
	hud.view_toggled.connect(toggle_view)
	hud.camp_requested.connect(return_to_camp)
	hud.map_toggled.connect(toggle_map)
	hud.cursor_requested.connect(_set_cursor_free)
	hud.inventory_requested.connect(toggle_inventory)
	hud.equipment_requested.connect(toggle_equipment)
	if _player_state != null:
		archer.apply_loadout(_player_state.loadout())
		_sync_trinket_limits()
		gold = int(_player_state.credits)
	else:
		archer.set_bow(0)
		archer.set_sword(0)
		archer.set_armor_pieces({"head": 0, "chest": 0, "hands": 0, "legs": 0, "feet": 0})
	archer.loadout_changed.connect(_update_loadout)
	hud.configure_map(world.landmarks, world.map_paths, world.interactables, world.WORLD_LIMIT)
	_update_loadout()
	_refresh_backpack()
	_build_world_ui()
	Perf.begin("spawn.mobs")
	for record: Dictionary in world.enemy_spawns:
		var enemy := Enemy.new()
		enemy.kind = int(record.kind)
		enemy.pack_index = int(record.get("pack_index", -1))
		enemy.devil_weapon = str(record.get("weapon", "claw"))
		enemy.position = record.position + Vector3(0, 0.12, 0)
		enemy.player = player
		enemy.terrain = world
		enemy.safe_center = world.player_spawn
		add_child(enemy)
		enemy.defeated.connect(_on_enemy_defeated)
		enemy.attacked.connect(_on_enemy_attack)
		if enemy.kind == 2:
			enemy.arrow_fired.connect(_on_mob_arrow)
		enemies.append(enemy)
	for record: Dictionary in world.devil_spawns:
		var devil := DevilMob.new()
		devil.mob_id = str(record.mob)
		devil.position = record.position + Vector3(0, 0.12, 0)
		devil.player = player
		devil.terrain = world
		devil.safe_center = world.player_spawn
		add_child(devil)
		devil.defeated.connect(_on_enemy_defeated)
		devil.attacked.connect(_on_enemy_attack)
		enemies.append(devil)
	for record: Dictionary in world.forest_spawns:
		var forest := ForestMob.new()
		forest.mob_id = str(record.mob)
		forest.position = record.position + Vector3(0, 0.12, 0)
		forest.player = player
		forest.terrain = world
		forest.safe_center = world.player_spawn
		add_child(forest)
		forest.defeated.connect(_on_enemy_defeated)
		forest.attacked.connect(_on_enemy_attack)
		enemies.append(forest)
	for index in world.ranger_spawns.size():
		var record: Dictionary = world.ranger_spawns[index]
		var clone := RangerClone.new()
		clone.name = "RangerClone%d" % index
		clone.bounds = world.WORLD_LIMIT - 2.0
		clone.fallback_target = player
		clone.terrain = world
		add_child(clone)
		clone.configure(index,1,true,"scene")
		clone.spawn_at(record.position + Vector3(0, 0.12, 0))
		clone.defeated.connect(_on_enemy_defeated)
		clone.attacked.connect(_on_enemy_attack)
		clone.arrow_fired.connect(_on_mob_arrow)
		enemies.append(clone)
	Perf.end()
	_warm_mob_blood()
	_enemies_by_index = enemies.duplicate()
	_setup_network()
	_update_camera(1.0)
	hud.show_feedback("The old waystones have gone dark. Follow the trails north.")
	print("IRONWOOD_WORLD_READY enemies=%d waystones=3 terrain=290m" % enemies.size())
	_set_cursor_free(false)


func _read_arguments() -> void:
	# Host intent is parsed here because the frontier is the launcher for a
	# hosted delve: the hatch descent arms `delve-host` with these values.
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		var argument := str(args[index])
		if argument == "--delve-host":
			_delve_host = true
		elif argument == "--delve-port" and index + 1 < args.size():
			_delve_port = clampi(args[index + 1].to_int(), 1024, 65535)
		elif argument == "--delve-name" and index + 1 < args.size():
			_delve_name = str(args[index + 1]).strip_edges()
		elif argument == "--world-host":
			_world_host = true
		elif argument == "--world-port" and index + 1 < args.size():
			_world_port = clampi(args[index + 1].to_int(), 1024, 65535)
		elif argument == "--world-name" and index + 1 < args.size():
			_world_name = str(args[index + 1]).strip_edges()
		elif argument == "--world-join" and index + 1 < args.size():
			_world_join = str(args[index + 1]).strip_edges()
		elif argument == "--net-lag" and index + 1 < args.size():
			_link_lag = maxf(0.0,float(args[index + 1].to_float())/1000.0)
		elif argument == "--net-jitter" and index + 1 < args.size():
			_link_jitter = maxf(0.0,float(args[index + 1].to_float())/1000.0)
		elif argument == "--net-diag":
			_net_diag = true


func _build_world_ui() -> void:
	world_ui = WorldUI.new()
	world_ui.name = "WorldUI"
	world_ui.layer = 2
	add_child(world_ui)
	world_ui.configure(_player_state,get_node_or_null("/root/Session"),archer,Callable(self,"_drop_field_loot"),true)
	world_ui.opened.connect(_on_ui_opened)
	world_ui.closed.connect(_on_ui_closed)
	world_ui.loadout_changed.connect(_on_ui_loadout_changed)


func _ui_open() -> bool:
	return world_ui != null and world_ui.is_open()


func toggle_inventory() -> void:
	if world_ui == null:
		return
	if world_ui.is_open() and world_ui.active_view() == "inventory":
		world_ui.close()
		return
	if inspecting:
		toggle_view()
	world_ui.open_inventory()


func toggle_equipment() -> void:
	if world_ui == null:
		return
	if world_ui.is_open() and world_ui.active_view() == "equipment":
		world_ui.close()
		return
	if inspecting:
		toggle_view()
	world_ui.open_equipment()


func _on_ui_opened() -> void:
	# Opening cancels a live attack and frees the cursor; movement, attacks and
	# interactions stay blocked until the overlay closes.
	cancel_input()
	_jump_requested = false
	hud.close_panels()
	_set_cursor_free(true)


func _on_ui_closed() -> void:
	_set_cursor_free(false)


func _on_ui_loadout_changed() -> void:
	if _player_state == null:
		return
	if _client():
		send_action("loadout",_local_loadout())
		# The host owns the authoritative seat; the client's own replica still
		# needs the worn kit for its bar maxima and its gold share.
		var seat = _seats.get(local_slot)
		if seat != null and is_instance_valid(seat):
			seat.apply_trinkets(_player_state.trinkets())
		_refresh_backpack()
		return
	cancel_input()
	archer.apply_loadout(_player_state.loadout())
	_sync_trinket_limits()
	_update_loadout()
	_refresh_backpack()


## Worn trinkets change the maxima, movement, damage and stagger resistance.
## The rig holds the aggregated table; this body mirrors what the HUD reads.
func _sync_trinket_limits() -> void:
	if not is_instance_valid(archer):
		return
	trinkets = archer.trinkets.duplicate()
	trinket_stats = archer.trinket_stats.duplicate()
	max_health = TrinketStats.max_health(MAX_HEALTH, trinket_stats)
	max_stamina = TrinketStats.max_stamina(Stamina.MAX, trinket_stats)
	health = minf(health, max_health)
	stamina = minf(stamina, max_stamina)
	combat.stagger_scale = TrinketStats.stagger_scale(trinket_stats)
	if hud != null:
		hud.set_limits(max_health, max_stamina)


## Energy Shield: the runner calls this on a successful ward activation.
func start_ward(definition: Dictionary) -> void:
	var effect := AbilityRules.ward(definition)
	if effect.is_empty():
		return
	ward_seconds = float(effect.get("seconds", 60.0))
	ward_absorb = clampf(float(effect.get("absorb", 0.5)), 0.0, 1.0)
	ward_stamina_scale = maxf(1.0, float(effect.get("stamina_scale", 2.0)))
	archer.set_ward(true)

## Returns the damage that still reaches health after the ward's swap.
func _absorb_with_ward(applied: float) -> float:
	if ward_seconds <= 0.0 or applied <= 0.0:
		return applied
	var price: float = applied * ward_absorb * ward_stamina_scale
	var paid: float = minf(price, stamina)
	if paid <= 0.0:
		return applied
	stamina -= paid
	return applied - paid / ward_stamina_scale

func _tick_ward(delta: float) -> void:
	if ward_seconds <= 0.0:
		return
	ward_seconds = maxf(0.0, ward_seconds - delta)
	if ward_seconds <= 0.0:
		archer.set_ward(false)


## The off-hand skulls pay out on every kill this body makes. A remote seat's
## kill is healed on the host's copy of that seat, so it replicates normally.
func _grant_kill_refill(killer: int) -> void:
	if killer < 0:
		return
	if killer == _local_seat_id():
		_apply_kill_refill()
		return
	var seat = _seats.get(killer)
	if seat != null and is_instance_valid(seat) and seat.has_method("apply_kill_refill"):
		seat.apply_kill_refill()

func _apply_kill_refill() -> void:
	var heal := float(trinket_stats.get("heal_on_kill", 0.0))
	var gain := float(trinket_stats.get("stamina_on_kill", 0.0))
	if heal > 0.0:
		health = minf(max_health, health + heal)
	if gain > 0.0:
		stamina = minf(max_stamina, stamina + gain)


## TAB swaps the active hands with the bound paperdoll pair. The displaced
## pair becomes the new quick set, so the same key toggles back.
func quick_swap() -> void:
	if _player_state == null or inspecting or hud.map_open or _cursor_free or _ui_open():
		return
	var result: Dictionary = _player_state.quick_swap()
	if not bool(result.get("ok", false)):
		hud.show_feedback(str(result.get("message", "No quick swap set.")), 2.0)
		return
	if _client():
		send_action("loadout",_local_loadout())
		_refresh_backpack()
		audio.play_sound("equip")
		hud.show_feedback(str(result.get("message", "Swapped weapons.")), 1.5)
		return
	cancel_input()
	archer.apply_loadout(_player_state.loadout())
	_update_loadout()
	_refresh_backpack()
	audio.play_sound("equip")
	hud.show_feedback(str(result.get("message", "Swapped weapons.")), 1.5)


func _drop_field_loot(item_id: String) -> void:
	# The helper already removed the item from PlayerState. The pickup starts
	# unarmed so the drop lands at the ranger's feet without an instant re-pickup.
	if item_id.is_empty():
		return
	_spawn_loot(item_id,player.global_position,false,false)
	hud.show_feedback("%s dropped" % _loot_display_name(item_id),2.0)


func _physics_process(delta: float) -> void:
	Perf.begin("main.physics")
	if _link.held > 0:
		_link.release(Time.get_ticks_msec()/1000.0)
	if _net_diag:
		_diag_step(delta)
	if network_role == "client":
		_client_step(delta)
		Perf.end()
		return
	roll.advance(delta,player.is_on_floor())
	step.advance(delta,player.is_on_floor())
	# A release cue has to leave on the frame's crosshair, and the runner emits
	# its cues below, before the later draw-time refresh.
	if archer.is_ability():
		update_crosshair_aim()
	ability.advance(delta)
	_tick_ward(delta)
	var input_vector := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()
	_advance_consumable(delta)
	if inspecting or hud.map_open or _cursor_free or _ui_open():
		input_vector = Vector2.ZERO
		slide.reset()
	if _consume_kind != "":
		input_vector = Vector2.ZERO
		slide.reset()
	if combat.stagger_time > 0.0:
		input_vector = Vector2.ZERO
		step.active = false
	if ability.active and not ability.allows_movement():
		input_vector = Vector2.ZERO
		slide.reset()
	var running: bool = (cover.active or not cover.crouched and not cover.crouch_requested) and Input.is_physical_key_pressed(KEY_SHIFT) and not _sprint_exhausted and stamina > 1.0 and input_vector.length_squared() > 0.1 and _consume_kind == "" and not ability.active
	var speed: float = (2.2 if not cover.active and (cover.crouched or cover.crouch_requested) else SPRINT_SPEED if running else WALK_SPEED) * float(archer.move_scale())
	var stamina_rate: float = 0.0 if combat.blocking or ability.active else (-Stamina.SPRINT_DRAIN_PER_SECOND if running or slide.active else Stamina.REGEN_PER_SECOND * TrinketStats.stamina_regen(trinket_stats))
	stamina = clampf(stamina + delta * stamina_rate, 0.0, max_stamina)
	if stamina <= Stamina.SPRINT_EXHAUSTED:
		_sprint_exhausted = true
	elif stamina >= Stamina.SPRINT_RESUME:
		_sprint_exhausted = false
	var camera_right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var camera_back := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
	var direction := camera_right * input_vector.x + camera_back * input_vector.y
	_movement_direction = direction
	var slide_velocity: Vector3 = slide.step(delta,player,cover,direction,roll.active)
	var acceleration := 35.0 if player.is_on_floor() else 10.0
	player.velocity.x = move_toward(player.velocity.x, direction.x * speed, acceleration * delta)
	player.velocity.z = move_toward(player.velocity.z, direction.z * speed, acceleration * delta)
	var was_in_cover: bool = cover.active
	_update_combat_cover_side()
	combat.face_block(Vector3(-sin(camera_yaw),0,-cos(camera_yaw)))
	Perf.begin("player.cover")
	var covered_velocity: Vector3 = cover.step(delta,direction,_peek_requested or combat.wants_cover_exposure(),combat.cover_side,running)
	Perf.end()
	if was_in_cover:
		player.velocity.x = covered_velocity.x
		player.velocity.z = covered_velocity.z
	if slide.active:
		player.velocity.x = slide_velocity.x
		player.velocity.z = slide_velocity.z
	if step.active:
		var step_velocity: Vector3 = step.velocity()
		player.velocity.x = step_velocity.x
		player.velocity.z = step_velocity.z
	if roll.active:
		player.velocity.x = roll.direction.x * DodgeRoll.SPEED
		player.velocity.z = roll.direction.z * DodgeRoll.SPEED
	if ability.active:
		# A melee skill keeps the walk computed above; a planted skill stops
		# dead. Either way a committed travel window wins over both.
		_jump_requested = false
		var ability_velocity: Vector3 = ability.velocity()
		if not ability_velocity.is_zero_approx():
			player.velocity.x = ability_velocity.x
			player.velocity.z = ability_velocity.z
		elif not ability.allows_movement():
			player.velocity.x = 0.0
			player.velocity.z = 0.0
		else:
			# Hand the dash back to the feet: the walk target caps the residual
			# travel instead of gliding a lane past the authored distance.
			var walked := Vector2(player.velocity.x, player.velocity.z).limit_length(speed)
			player.velocity.x = walked.x
			player.velocity.z = walked.y
	if _jump_requested and not inspecting and not hud.map_open:
		player.velocity.y = 7.0
	elif player.is_on_floor():
		player.velocity.y = -1.0
	else:
		player.velocity.y -= 20.0 * delta
	if roll.takeoff_pending:
		player.velocity.y = maxf(player.velocity.y,6.0)
		roll.takeoff_pending = false
	_jump_requested = false
	var previous_position := player.global_position
	Perf.begin("player.slide")
	player.move_and_slide()
	Perf.end()
	var limit: float = world.WORLD_LIMIT - 2.0
	player.position.x = clampf(player.position.x, -limit, limit)
	player.position.z = clampf(player.position.z, -limit, limit)
	# The lunge cuts the lane it just crossed, measured after the move.
	_ability_path_strike(ability)
	var actual_velocity := (player.global_position - previous_position) / maxf(delta, 0.0001)
	slide.after_move(player,actual_velocity)
	Perf.begin("player.loot")
	_collect_loot(delta)
	_bloody_feet.update(delta,player,archer)
	Perf.end()
	archer.set_cover(cover.active,cover.normal,cover.crouch_amount,cover.peeking,cover.lean)
	archer.set_slide(slide.progress if slide.active else -1.0,slide.direction)
	archer.set_step(step.progress if step.active else -1.0,step.direction)
	archer.set_roll(roll.progress if roll.active else -1.0,roll.direction)
	archer.set_locomotion(actual_velocity, player.is_on_floor() and not roll.active)
	combat.set_motion(actual_velocity, running or roll.active or slide.active or step.active, player.is_on_floor() and not roll.active)
	if _mouse_drawing or _throw_held or combat.wants_cover_exposure() or archer.charge_frozen:
		update_crosshair_aim()
	Perf.begin("player.combat")
	combat.advance(delta)
	Perf.end()
	if not _entering_scene and world.is_over_delve_hatch(player.global_position) and player.global_position.y < 2.25:
		_enter_delve()
	elif player.position.y < -25.0:
		return_to_camp()
	if _entering_scene:
		Perf.end()
		return
	if network_role == "host":
		_host_network_step(delta)
	Perf.end()

## One line a second: the numbers that decide whether a session feels smooth.
func _diag_step(delta: float) -> void:
	var seat = _seats.get(_local_seat_id())
	if seat == null or not is_instance_valid(seat):
		return
	var boom: float = camera.global_position.distance_to(camera_focus)
	if seat.prediction_corrections != _diag_corrections:
		_diag_corrections = seat.prediction_corrections
		_diag_drift = maxf(_diag_drift,seat.prediction_drift)
	if _diag_previous_rig != Vector3.INF:
		_diag_rig_step = maxf(_diag_rig_step,seat.rig.global_position.distance_to(_diag_previous_rig))
		if _diag_previous_boom >= 0.0:
			_diag_boom_step = maxf(_diag_boom_step,absf(boom-_diag_previous_boom))
	_diag_previous_rig = seat.rig.global_position
	_diag_previous_boom = boom
	var extrapolated := 0
	var restarts := 0
	var replicas := 0
	for enemy in _enemies_by_index:
		if not is_instance_valid(enemy) or not enemy.get("replica"):
			continue
		replicas += 1
		var timeline = enemy.get("_timeline")
		if timeline == null:
			continue
		restarts += int(timeline.restarts)
		if timeline.extrapolating():
			extrapolated += 1
	_diag_mob_extrapolated = extrapolated
	_diag_mob_count = replicas
	_diag_mob_restarts = restarts - _diag_restart_base if _diag_restart_base >= 0 else 0
	_diag_restart_base = restarts
	_diag_elapsed += delta
	if _diag_elapsed < 1.0:
		return
	print("NET_DIAG role=%s slot=%d predicting=%s corrections=%d drift=%.2f rig_step=%.2f boom_step=%.2f unacked=%d held=%d health=%.0f mobs=%d starved=%d restarts=%d" % [
		network_role,_local_seat_id(),str(seat.prediction_active()),seat.prediction_corrections,
		_diag_drift,_diag_rig_step,_diag_boom_step,
		seat._prediction.next_seq-int(seat._prediction.acked),_link.held,health,
		_diag_mob_count,_diag_mob_extrapolated,_diag_mob_restarts])
	_diag_elapsed = 0.0
	_diag_rig_step = 0.0
	_diag_boom_step = 0.0
	_diag_drift = 0.0


func _process(delta: float) -> void:
	Perf.begin("main.process")
	shoulder_camera.update(delta)
	_update_camera(delta)
	if _mouse_drawing or _throw_held or _peek_requested or combat.wants_cover_exposure() or archer.charge_frozen or archer.is_ability():
		update_crosshair_aim()
	_update_interaction()
	Perf.begin("hud.frame")
	hud.reticle_visible = not _cursor_free and not inspecting and not hud.map_open
	hud.reticle = get_viewport().get_visible_rect().size * 0.5
	hud.update_status(health, stamina, gold, kills, archer.phase, archer.draw_amount, world.region_at(player.position), combat.get_attack_interval(), combat.attack_progress, combat.movement_mode, combat.blocking, combat.blocking and combat.block_time <= Combat.PARRY_WINDOW, archer.melee_progress_for("left"), archer.melee_progress_for("right"), _consume_kind, _consume_time, ability.hud_state(0), ability.hud_state(1), ability.hud_state(2))
	hud.update_world_position(player.position, archer.global_rotation.y, activated)
	hud.update_cover(cover.active,cover.low,cover.peeking,shoulder_camera.side,cover.crouched,slide.active)
	Perf.end()
	Perf.end()

func _sample_floor(point: Vector3) -> float:
	_floor_query.from = point + Vector3(0, 1.15, 0)
	_floor_query.to = point - Vector3(0, 2.4, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	return float(hit.position.y) if not hit.is_empty() else player.global_position.y

func _update_camera(delta: float) -> void:
	var focus_height: float = 1.05 if inspecting else cover.camera_height()
	var desired_focus := player.global_position + Vector3.UP*focus_height
	var factor := 1.0 if not _camera_ready else 1.0 - exp(-delta * 10.0)
	camera_focus = camera_focus.lerp(desired_focus, factor)
	var back := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch))
	var resolved := shoulder_camera.resolve(get_world_3d().direct_space_state,camera_focus,back,camera_distance,inspecting)
	var reach := resolved-camera_focus
	var allowed := reach.length()
	if _camera_boom < 0.0:
		_camera_boom = allowed
	elif allowed < 0.0001:
		_camera_boom = allowed
	else:
		# Both directions are zoomed at a bounded speed: a boom that snapped in
		# whenever a trunk crossed the line and popped back out when it cleared
		# read as the whole view shaking, which is worse than a frame of
		# see-through on a thin trunk. Pulling in is much faster than easing out.
		var speed := CAMERA_BOOM_IN if allowed < _camera_boom else CAMERA_BOOM_OUT
		_camera_boom = move_toward(_camera_boom,allowed,speed*maxf(delta,0.0))
	camera.global_position = camera_focus + reach.normalized()*_camera_boom
	if inspecting:
		if camera.global_position.distance_squared_to(camera_focus) > 0.01:
			camera.look_at(camera_focus)
	else:
		camera.look_at(camera.global_position - back)
	_camera_ready = true



func _set_cursor_free(value: bool) -> void:
	_cursor_free = value
	if value:
		cancel_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func update_crosshair_aim() -> void:
	_update_camera(0.0)
	if inspecting:
		var inspection_aim: Vector3 = player.global_position + Vector3(0,1.7,0) - archer.global_basis.z * 30.0
		combat.set_aim(inspection_aim)
		combat.clear_camera_ray()
		_client_aim = inspection_aim
		_client_aim_origin_valid = false
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	# Clip camera-side cover at the actor, never at the animated weapon tip.
	# Using the tip feeds bow rotation back into target selection and skips close targets.
	var aim_anchor: Vector3 = player.global_position + Vector3.UP*cover.camera_height()
	var actor_depth := maxf(0.0,(aim_anchor-ray_origin).dot(ray_direction))
	_aim_query.from = ray_origin + ray_direction*actor_depth
	_aim_query.to = ray_origin + ray_direction * 300.0
	# The body you are posted against is camera-side cover, not a target. The
	# shooter's own capsule is never a crosshair target either.
	_aim_exclude.clear()
	_aim_exclude.append(player.get_rid())
	var cover_rid: RID = cover.attached_surface()
	if cover_rid.is_valid():
		_aim_exclude.append(cover_rid)
	_aim_query.exclude = _aim_exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(_aim_query)
	var aim: Vector3 = hit.position if not hit.is_empty() else _aim_query.to
	combat.set_aim(aim)
	combat.set_camera_ray(ray_origin,ray_direction)
	_client_aim = aim
	_client_aim_origin = ray_origin
	_client_aim_origin_valid = true

func _update_combat_cover_side() -> void:
	cover.view_right = _peek_right
	combat.cover_side = shoulder_camera.side * (1 if _peek_right.dot(cover.normal.cross(Vector3.UP)) >= 0.0 else -1)

func _capture_attack_cover_side() -> void:
	if not _peek_requested and archer.phase == "READY":
		_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	_update_combat_cover_side()

func _diagonal_variant() -> String:
	var side := _next_swing_side
	if side == 0:
		side = 1 if shoulder_camera.side > 0 else -1
	_next_swing_side = -side
	return "diagonal_right" if side > 0 else "diagonal_left"

func begin_attack(hand: String = "right", variant: String = "") -> void:
	if hud.map_open or _ui_open():
		return
	if _client():
		if archer.weapon in ["sword","dagger","dual"]:
			var swing := variant
			if swing.is_empty():
				swing = "diagonal_left" if hand == "left" and archer.weapon == "dual" else _diagonal_variant()
			send_action("melee",{"hand":hand if archer.weapon == "dual" else "right","variant":swing,"aim":_client_aim})
		else:
			send_action("draw",_client_aim)
		return
	_cancel_consumable()
	_capture_attack_cover_side()
	update_crosshair_aim()
	var requested := hand if archer.weapon == "dual" else "right"
	var saved_side := _next_swing_side
	var started := false
	if archer.weapon in ["sword","dagger","dual"]:
		var swing := variant
		if swing.is_empty():
			if archer.weapon == "dual":
				swing = "diagonal_left" if requested == "left" else "diagonal_right"
			else:
				swing = _diagonal_variant()
		started = combat.begin_melee(requested,swing)
	else:
		started = combat.begin_draw()
	if not started:
		_next_swing_side = saved_side
		hud.show_feedback("Finish recovery and stand on solid ground." if archer.weapon in ["sword","dagger","dual"] else "Finish recovery, stand on solid ground, and use a clear cover edge or top.")

func quick_step(side: int) -> void:
	if inspecting or hud.map_open or _cursor_free or side == 0:
		return
	if _client():
		send_action("step",Vector3(cos(camera_yaw),0,-sin(camera_yaw))*signf(float(side)))
		return
	if combat.stagger_time > 0.0 or ability.active:
		return
	var direction: Vector3 = Vector3(cos(camera_yaw),0,-sin(camera_yaw))*signf(float(side))
	if not step.try_step(direction,player.is_on_floor(),roll.active):
		return
	cancel_input()
	if cover.active:
		cover.exit()
	slide.reset()
	archer.set_slide(-1.0,Vector3.FORWARD)
	stamina = maxf(0.0,stamina-DodgeStep.STAMINA_COST)

func begin_throw_attack() -> void:
	if hud.map_open or _ui_open():
		return
	if archer.weapon not in ["sword","dagger","dual"]:
		hud.show_feedback("Equip a sword with 2 or the dagger with 3 to throw.")
		return
	if _client():
		send_action("throw",_client_aim)
		return
	_cancel_consumable()
	_capture_attack_cover_side()
	update_crosshair_aim()
	if not combat.begin_throw():
		hud.show_feedback("Finish recovery and stand on solid ground to throw.")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _mouse_drawing:
			_mouse_drawing = false
			_update_combat_cover_side()
			update_crosshair_aim()
			if _client():
				send_action("release",_client_aim)
			else:
				combat.release_draw()
	if event is InputEventKey and event.keycode == KEY_T and not event.pressed:
		if _throw_held:
			_throw_held = false
			_update_combat_cover_side()
			update_crosshair_aim()
			if _client():
				send_action("throw_release",_client_aim)
			else:
				combat.release_throw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_orbiting = false
		_peek_requested = false
		if _client():
			send_action("block",{"pressed":false,"forward":Vector3(-sin(camera_yaw),0,-cos(camera_yaw))})
			send_action("peek",{"pressed":false,"right":Vector3(cos(camera_yaw),0,-sin(camera_yaw)),"side":shoulder_camera.side})
		else:
			combat.stop_block()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# The in-world kit always answers I, P and Escape first so it can close
		# without leaking keys into movement, attacks or the waystone prompts.
		if event.keycode == KEY_I:
			toggle_inventory()
			return
		if event.keycode == KEY_P:
			toggle_equipment()
			return
		if event.keycode == KEY_ESCAPE:
			if _ui_open():
				world_ui.close()
				return
			cancel_input()
			if inspecting:
				toggle_view()
			hud.close_panels()
			_set_cursor_free(true)
			return
		if _ui_open():
			return
		match event.keycode:
			KEY_1:
				if event.shift_pressed:
					activate_ability(0)
				else:
					equip_weapon("bow")
			KEY_2:
				if event.shift_pressed:
					activate_ability(1)
				else:
					equip_weapon("sword")
			KEY_3:
				if event.shift_pressed:
					activate_ability(2)
				else:
					equip_weapon("dagger")
			KEY_4: equip_shield(not archer.shield_equipped)
			KEY_5: equip_weapon("dual")
			KEY_TAB: quick_swap()
			KEY_6: use_consumable("bandage")
			KEY_7: use_consumable("potion")
			KEY_C: toggle_crouch()
			KEY_SPACE: press_jump(event.shift_pressed)
			KEY_F: toggle_cover()
			KEY_X:
				shoulder_camera.swap()
				_next_swing_side = shoulder_camera.side
				_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
				_update_combat_cover_side()
			KEY_Q: quick_step(-1)
			KEY_E: quick_step(1)
			KEY_G: interact()
			KEY_M: toggle_map()
			KEY_V: toggle_view()
			KEY_R: return_to_camp()
			KEY_N:
				audio.muted = not audio.muted
				hud.show_feedback("Sound off" if audio.muted else "Sound on")
			KEY_T:
				if not inspecting:
					hud.close_panels()
					_set_cursor_free(false)
				if not _throw_held:
					_throw_held = true
					begin_throw_attack()
	if _ui_open():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not inspecting:
				hud.close_panels()
				_set_cursor_free(false)
			_mouse_drawing = true
			begin_attack("left")
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if inspecting:
				_orbiting = true
				_orbit_pointer = event.position
			elif archer.weapon == "dual":
				hud.close_panels()
				_set_cursor_free(false)
				begin_attack("right","diagonal_right")
			else:
				hud.close_panels()
				_set_cursor_free(false)
				_peek_requested = cover.active
				_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
				if _client():
					if cover.active:
						send_action("peek",{"pressed":true,"right":_peek_right,"side":shoulder_camera.side})
					else:
						send_action("block",{"pressed":true,"forward":Vector3(-sin(camera_yaw),0,-cos(camera_yaw))})
				elif not combat.start_block(Vector3(-sin(camera_yaw),0,-cos(camera_yaw))) and not cover.active:
					hud.show_feedback("Equip a sword or dagger with 2 or 3, stand still and finish recovery to guard.")
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if event.ctrl_pressed:
				camera_distance = maxf(camera_distance - 0.45, 2.7)
			elif archer.weapon in ["sword","dagger","dual"] and not inspecting and not hud.map_open and not _cursor_free:
				begin_attack("right","stab")
			else:
				hud.show_feedback("Equip a sword with 2 to stab or swing.")
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if event.ctrl_pressed:
				camera_distance = minf(camera_distance + 0.45, 17.0)
			elif archer.weapon in ["sword","dagger","dual"] and not inspecting and not hud.map_open and not _cursor_free:
				begin_attack("right","overhead")
			else:
				hud.show_feedback("Equip a sword with 2 to stab or swing.")
	if event is InputEventMouseMotion:
		if not _cursor_free and not inspecting:
			camera_yaw -= event.relative.x * 0.004
			camera_pitch = clampf(camera_pitch + event.relative.y * 0.004, -0.7, 0.7)
		elif _orbiting and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			var change: Vector2 = event.position - _orbit_pointer
			_orbit_pointer = event.position
			camera_yaw -= change.x * 0.006
			camera_pitch = clampf(camera_pitch + change.y * 0.004, -0.10, 1.05)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(archer):
		_set_cursor_free(true)

func cancel_input() -> void:
	_mouse_drawing = false
	_throw_held = false
	_orbiting = false
	_peek_requested = false
	_cancel_consumable()
	if is_instance_valid(ability):
		ability.cancel()
	combat.stop()
	if _client():
		send_action("stop")

func equip_bow(index: int) -> void:
	if _client():
		send_action("bow",index)
		return
	cancel_input()
	archer.set_bow(index)
	audio.play_sound("equip")

func equip_sword(index: int) -> void:
	if _client():
		send_action("sword",index)
		return
	cancel_input()
	archer.set_sword(index)
	audio.play_sound("equip")

func equip_weapon(value: String) -> void:
	if value == "dual":
		if archer.weapon == "dual":
			value = "sword"
		elif archer.sword_index == 2:
			hud.show_feedback("Dual wield needs a one-handed sword and an off-hand dagger or sword. Press P to change the kit.")
			return
	if _client():
		send_action("weapon",value)
		return
	cancel_input()
	if not archer.set_weapon(value):
		hud.show_feedback("Dual wield needs a one-handed sword and an off-hand dagger or sword. Press P to change the kit.")
		return
	audio.play_sound("equip")

func equip_shield(value: bool) -> void:
	if _client():
		send_action("shield",value)
		return
	if value and not archer.can_equip_shield():
		hud.show_feedback("Shield fits the dagger or the medium arming sword.")
		return
	cancel_input()
	archer.set_shield(value)
	audio.play_sound("equip")

func toggle_cover() -> void:
	if inspecting or hud.map_open or _cursor_free:
		return
	if _client():
		send_action("cover",Vector3(-sin(camera_yaw),0,-cos(camera_yaw)))
		return
	if ability.active:
		return
	cancel_input()
	_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	_update_combat_cover_side()
	if cover.active:
		cover.exit()
	elif not roll.active and cover.try_enter(Vector3(-sin(camera_yaw),0,-cos(camera_yaw))):
		slide.reset()
		hud.show_feedback("In cover  /  LMB attacks out; scroll up stabs; scroll down overhead; RMB guards and peeks; F leaves")
	else:
		hud.show_feedback("Move closer to a tree, wall or solid debris and stand on the ground.")

func toggle_crouch() -> void:
	if inspecting or hud.map_open or _cursor_free:
		return
	if _client():
		send_action("crouch",not cover.crouch_requested)
		return
	if not player.is_on_floor() or roll.active or ability.active:
		return
	_cancel_consumable()
	var requested: bool = not cover.crouch_requested
	if requested:
		var sprinting := Input.is_physical_key_pressed(KEY_SHIFT) and not _sprint_exhausted and stamina > 1.0 and _movement_direction.length_squared() > 0.1
		slide.try_start(player,cover,sprinting,roll.active)
	else:
		slide.reset()
	cover.crouch_requested = requested

func press_jump(roll_requested: bool) -> void:
	if inspecting or hud.map_open or _cursor_free:
		return
	if _client():
		send_action("jump",roll_requested)
		return
	if ability.active:
		return
	_cancel_consumable()
	var grounded := player.is_on_floor()
	_peek_requested = false
	if not cover.prepare_jump():
		return
	slide.reset()
	step.reset()
	archer.set_slide(-1.0,Vector3.FORWARD)
	cancel_input()
	_jump_requested = roll.press_jump(_movement_direction,-archer.global_basis.z,grounded,roll_requested) or _jump_requested
	if roll.active:
		_jump_requested = false
		cancel_input()

func equip_armor_slot(slot: String, set_index: int) -> void:
	if _client():
		send_action("armor",{"slot":slot,"set":set_index})
		return
	cancel_input()
	archer.set_armor_piece(slot,set_index)
	audio.play_sound("equip")

func _armor_summary() -> String:
	return "%d%% GUARD" % int(round(archer.armor_reduction() * 100.0))

func _update_loadout() -> void:
	hud.update_loadout(archer.bow_index, archer.armor_pieces, Archer.BOW_DATA[archer.bow_index], _armor_summary(), archer.sword_index, archer.weapon, Archer.SWORD_DATA[archer.sword_index], Archer.DAGGER_DATA, archer.shield_equipped)

func activate_ability(slot: int) -> void:
	if inspecting or hud.map_open or _cursor_free or _ui_open():
		return
	if _client():
		send_action("ability",slot)
		return
	if not is_instance_valid(ability) or ability.active:
		return
	var reason: String = ability.blocker(slot)
	if not reason.is_empty():
		hud.show_feedback(reason,1.6)
		return
	# The skill spends its cost down the crosshair, so resolve the aim from the
	# camera now instead of firing on a heading left over from before the press.
	update_crosshair_aim()
	var refusal: String = _prepare_backstab(ability.actor, ability.definition(slot))
	if not refusal.is_empty():
		hud.show_feedback(refusal,1.6)
		return
	cancel_input()
	var outcome: Dictionary = ability.activate(slot)
	if not bool(outcome.get("ok",false)):
		hud.show_feedback(str(outcome.get("message","That ability is not ready.")),1.6)
		return
	var definition: Dictionary = outcome.get("definition",{})
	var sound := str(definition.get("sound",""))
	if not sound.is_empty():
		audio.play_sound(sound)
	hud.show_feedback("%s  /  -%d stamina" % [str(definition.get("name","")),int(float(definition.get("stamina_cost",0.0)))],1.2)

## A backstab needs a live body under the crosshair before it may spend
## stamina or start its clock. The resolved body rides on the runner actor so
## the blink and stab cues agree with the preflight even if the aim has moved.
func _prepare_backstab(actor, definition: Dictionary) -> String:
	if str(definition.get("effect", {}).get("kind", "")) != "backstab":
		return ""
	var target: Node3D = _backstab_target(actor)
	if target == null:
		if actor != null and is_instance_valid(actor):
			actor.remove_meta("backstab_target")
		return "No backstab target."
	actor.set_meta("backstab_target",target)
	return ""


## A bound world seat carries its own aim; the solo runner's actor is this
## scene, whose aim and body live on `combat` and `player`.
func _backstab_target(actor) -> Node3D:
	var position: Vector3 = archer.global_position
	var aim: Vector3 = combat.aim_point
	var exclude: Array[RID] = []
	if actor != null and is_instance_valid(actor) and actor is CollisionObject3D:
		position = actor.global_position
		aim = actor.combat.aim_point
		exclude.append(actor.get_rid())
	elif player is CollisionObject3D:
		exclude.append(player.get_rid())
	return BackstabAbility.find_target(get_world_3d().direct_space_state,
		position,aim,BACKSTAB_MASK,BACKSTAB_RANGE,exclude)


## The body a backstab moves. A bound world seat owns its own teleport; the
## solo frontier runner's actor is this scene, so the player capsule stands in.
func _backstab_body(actor):
	if actor != null and is_instance_valid(actor) and actor.has_method("teleport_to"):
		return actor
	return player


func _bind_ability_cues(runner) -> void:
	if runner == null or not is_instance_valid(runner):
		return
	if not runner.cue.is_connected(_on_ability_cue):
		runner.cue.connect(_on_ability_cue.bind(runner))


func _ability_authority(runner) -> bool:
	if network_role == "client":
		return false
	if runner != null and is_instance_valid(runner.actor) and runner.actor.get("authoritative") != null:
		return bool(runner.actor.authoritative)
	return true


func _on_ability_cue(id: String, cue: String, index: int, runner) -> void:
	if not is_instance_valid(runner) or not runner.active or str(runner.active_id) != id:
		return
	var definition: Dictionary = runner.active_definition
	if definition.is_empty():
		return
	var rig = runner.rig
	if rig == null or not is_instance_valid(rig):
		return
	var effect: Dictionary = definition.get("effect", {})
	var authoritative := _ability_authority(runner)
	var damage: float = AbilityRules.damage_for(definition, rig)
	match str(effect.get("kind", "")):
		"barrage", "volley", "piercing_shot":
			_ability_shots(runner, definition, index, damage, authoritative)
		"projectile":
			_ability_spell(runner, definition, damage, authoritative)
		"backstab":
			_ability_backstab(runner, cue, damage, authoritative)
		"melee_arc", "melee_ring":
			_ability_melee(runner, definition, cue, index, damage, authoritative)


func _ability_shots(runner, definition: Dictionary, index: int,
		damage: float, authoritative: bool) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var kind := str(effect.get("kind", ""))
	var rig = runner.rig
	var aim: Vector3 = runner.combat.aim_point
	# The cue lands before this rig's own pose step, so aim and resample the bow
	# before reading the hand: the arrow leaves on the live crosshair line.
	rig.aim_at(aim)
	rig.refresh_bow_pose()
	var origin: Vector3 = rig.get_arrow_origin()
	var base := aim - origin
	if base.length_squared() < 0.0001:
		base = -rig.global_basis.z
	var shots := int(effect.get("shots", 1)) if kind == "volley" else 1
	var speed := float(Archer.BOW_DATA[clampi(int(rig.bow_index), 0, 2)].speed) \
		* float(effect.get("arrow_speed_scale", 1.0))
	var pierce := int(effect.get("pierce", 0))
	for shot in shots:
		var pattern_index := index if kind == "barrage" else shot
		var offsets := AbilityFx.shot_offsets(definition, pattern_index)
		var direction := AbilityFx.rotate_direction(base, offsets.x, offsets.y)
		var excluded: Array[RID] = []
		if runner.actor is CollisionObject3D:
			excluded.append(runner.actor.get_rid())
		var source_slot := int(runner.actor.get("slot")) if runner.actor.get("slot") != null else -1
		_spawn_arrow(origin, direction, speed, damage, excluded, origin, source_slot, authoritative, pierce)
	if runner.actor == player:
		audio.play_sound("release")


func _ability_spell(runner, definition: Dictionary, damage: float,
		authoritative: bool) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = runner.rig
	var origin: Vector3 = rig.cast_origin()
	var aim: Vector3 = runner.combat.aim_point
	var direction := aim - origin
	if direction.length_squared() < 0.0001:
		direction = -rig.global_basis.z
	var spell := SpellProjectile.new()
	spell.kind = str(effect.get("projectile", "fireball"))
	spell.hit_mask = 1 | 2 | 8
	spell.shooter = runner.actor if runner.actor is Node3D else null
	add_child(spell)
	var excluded: Array[RID] = []
	if runner.actor is CollisionObject3D:
		excluded.append(runner.actor.get_rid())
	spell.launch(origin, direction, float(effect.get("speed", 22.0)), damage,
		excluded, spell.hit_mask, authoritative, rig.global_position,
		float(effect.get("radius", 0.0)), int(effect.get("pierce", 0)))
	spell.source_rig = rig
	spell.set_meta("stagger", float(effect.get("stagger", 0.0)))
	if authoritative:
		spell.detonated.connect(_on_spell_detonated.bind(spell, runner.combat))


func _on_spell_detonated(centre: Vector3, _direction: Vector3, spell, combat_ref) -> void:
	if not is_instance_valid(spell) or not is_instance_valid(combat_ref):
		return
	if spell.blast_radius <= 0.0:
		return
	combat_ref.ability_blast(centre, spell.blast_radius, spell.damage,
		float(spell.get_meta("stagger", 0.0)))


## A travelling skill sweeps the lane it has just crossed: after the body moved
## for the tick, every body inside the path arc takes one hit. The activation's
## victim set is shared with the closing thrust beat, so no body is hit twice.
func _ability_path_strike(runner) -> void:
	if not is_instance_valid(runner) or not runner.active:
		return
	var effect: Dictionary = runner.active_definition.get("effect", {})
	if not bool(effect.get("path_damage", false)):
		return
	if float(runner.elapsed) > float(runner.travel_seconds) + 0.02:
		return
	runner.combat.ability_strike(float(effect.get("path_radius", 1.0)),
		float(effect.get("path_arc_degrees", 180.0)),
		AbilityRules.damage_for(runner.active_definition, runner.rig),
		float(effect.get("stagger", 0.0)), false, false, runner.active_victims)


func _ability_melee(runner, definition: Dictionary, cue: String, index: int,
		damage: float, authoritative: bool) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = runner.rig
	var id := str(definition.get("id", ""))
	var radius := float(effect.get("radius", 1.7))
	var arc := float(effect.get("arc_degrees", 360.0))
	var ring := str(effect.get("kind", "")) == "melee_ring" or arc >= 359.0
	var forward: Vector3 = runner.combat.aim_point - rig.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	# The greatsword's wind-up is presentation only: the blade gathers speed
	# before the ring cue spends the hit.
	if cue == "wind":
		AbilityFx.blade_trail(self, rig, 0.55)
		return
	# The lunge's dash beat marks the takeoff with its wake; the thrust cue,
	# not the dash, spends the hit.
	if cue == "dash":
		AbilityFx.lunge_wake(self, rig, 0.40)
		return
	if authoritative:
		# A travelling skill already swept its lane, so the closing beat shares
		# that victim set and never hits a body the dash passed through twice.
		var victims: Dictionary = {}
		if bool(effect.get("path_damage", false)):
			victims = runner.active_victims
		runner.combat.ability_strike(radius, arc, damage,
			float(effect.get("stagger", 0.0)), ring, not ring, victims)
	if id.begins_with("shield_"):
		# The shield face is the weapon, so the impact sits on the boss instead
		# of a crescent that never matched the hands.
		AbilityFx.shield_impact(self, rig.global_position + forward * 0.95 + Vector3.UP * 1.05,
			forward, radius, id == "shield_slam")
		if ring:
			AbilityFx.ground_shockwave(self, rig.global_position, radius)
		return
	if ring:
		AbilityFx.spin_burst(self, rig.global_position, radius)
		AbilityFx.blade_trail(self, rig, 0.30)
	elif id == "double_slash":
		AbilityFx.blade_trail(self, rig, 0.24)
	elif id == "lunge_thrust":
		AbilityFx.blade_trail(self, rig, 0.18)
	else:
		var cues: Array = definition.get("cues", [])
		var alternate := 1.0 if index % 2 == 0 else -1.0
		if cues.size() <= 1:
			alternate = 0.0
		AbilityFx.slash_arc(self, rig.global_position, forward.rotated(Vector3.UP, 0.32 * alternate),
			radius, minf(arc, 200.0), AbilityFx.STEEL)


## Backstab: the blink cue smokes the old spot and, on the authority only,
## teleports behind the preflight target; the stab cue spends 2x dagger damage
## on the body the caster is now behind.
func _ability_backstab(runner, cue: String, damage: float, authoritative: bool) -> void:
	var rig = runner.rig
	var actor = runner.actor
	var target: Node3D = null
	if actor != null and is_instance_valid(actor) and actor.has_meta("backstab_target"):
		var resolved = actor.get_meta("backstab_target")
		if is_instance_valid(resolved) and resolved is Node3D:
			target = resolved
	var forward: Vector3 = runner.combat.aim_point - rig.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	if cue == "blink":
		AbilityFx.smoke_puff(self, rig.global_position, 1.0, true)
		if not authoritative or target == null:
			# Replicas never move themselves: the host's snapshot carries the
			# new position and only the smoke reads on this peer.
			return
		var spot: Dictionary = BackstabAbility.behind_spot(get_world_3d().direct_space_state, target)
		if not bool(spot.get("ok", false)):
			return
		var body = _backstab_body(actor)
		if body != null and is_instance_valid(body):
			BackstabAbility.blink(body, spot.position, float(spot.yaw))
		AbilityFx.smoke_puff(self, rig.global_position, 1.0, true)
		return
	if cue != "stab":
		return
	if target == null:
		target = _backstab_target(actor)
	if target != null and authoritative and target.get("alive") != false:
		var body = _backstab_body(actor)
		var source_slot := int(actor.get("slot")) if actor != null and actor.get("slot") != null else -1
		BackstabAbility.strike(body, target, damage, source_slot)
	if target != null:
		AbilityFx.backstab_flash(self, target.global_position - forward * 0.35 + Vector3.UP * 1.15, forward)


func use_consumable(kind: String) -> void:
	if not Archer.CONSUMABLE_DATA.has(kind):
		return
	var data: Dictionary = Archer.CONSUMABLE_DATA[kind]
	if _consume_kind != "":
		hud.show_feedback("Already using %s." % String(Archer.CONSUMABLE_DATA[_consume_kind].name))
		return
	if inspecting or hud.map_open or _cursor_free or _ui_open():
		return
	if _client():
		send_action("consume",kind)
		return
	if health >= max_health-0.001:
		hud.show_feedback("Health is already full.")
		return
	if combat.stagger_time > 0.0:
		hud.show_feedback("Recover your footing before using %s." % String(data.name).to_lower())
		return
	if not player.is_on_floor() or roll.active or slide.active or ability.active:
		hud.show_feedback("Stand on solid ground to use %s." % String(data.name).to_lower())
		return
	cancel_input()
	if cover.active:
		cover.exit()
	slide.reset()
	archer.set_slide(-1.0,Vector3.FORWARD)
	if not archer.begin_consumable(kind):
		hud.show_feedback("Finish the current action before using %s." % String(data.name).to_lower())
		return
	_consume_kind = kind
	_consume_time = 0.0
	audio.play_sound("equip")
	hud.show_feedback("Using %s  /  stand still" % String(data.name).to_lower(),1.2)

func _advance_consumable(delta: float) -> void:
	if _consume_kind != "":
		if not archer.is_consuming():
			_consume_kind = ""
			_consume_time = 0.0
		else:
			_consume_time += delta
			var data: Dictionary = Archer.CONSUMABLE_DATA[_consume_kind]
			if _consume_time >= float(data.seconds):
				var kind := _consume_kind
				_consume_kind = ""
				_consume_time = 0.0
				archer.end_consumable()
				if kind == "bandage":
					_heal_remaining = float(data.heal)
					_heal_rate = float(data.heal)/maxf(float(data.heal_seconds),0.001)
					hud.show_feedback("Bandage applied  /  %d health over %.0f s" % [int(data.heal),float(data.heal_seconds)],2.0)
				else:
					_heal(float(data.heal))
					hud.show_feedback("Healing potion  /  +%d health" % int(data.heal),1.5)
				audio.play_sound("heal")
	if _heal_remaining > 0.0:
		var amount := minf(_heal_rate*delta,_heal_remaining)
		_heal(amount)
		_heal_remaining = maxf(0.0,_heal_remaining-amount)

func _heal(amount: float) -> void:
	health = minf(max_health,health+amount)

func _cancel_consumable() -> void:
	if _consume_kind != "":
		_consume_kind = ""
		_consume_time = 0.0
		archer.cancel_consumable()

func toggle_view() -> void:
	inspecting = not inspecting
	camera_yaw = archer.global_rotation.y + (2.0 if inspecting else 0.2)
	camera_pitch = 0.12 if inspecting else 0.08
	camera_distance = 4.0 if inspecting else 4.5
	hud.set_inspecting(inspecting)
	_set_cursor_free(inspecting)

func toggle_map() -> void:
	cancel_input()
	hud.toggle_map()

func _update_interaction() -> void:
	_interaction_id = ""
	_interaction_kind = ""
	_interaction_vendor = -1
	_interaction_allowed = false
	if _ui_open():
		hud.set_interaction("")
		return
	var prompt := ""
	for item: Dictionary in world.interactables:
		# The delve hatch is entered by falling through it, not by a prompt.
		if item.kind == "delve":
			continue
		if player.position.distance_to(item.position) > 3.8:
			continue
		_interaction_id = str(item.id)
		_interaction_kind = str(item.kind)
		match _interaction_kind:
			"camp":
				prompt = "G  /  Rest at the campfire"
				_interaction_allowed = true
			"vendor":
				_interaction_vendor = int(item.get("vendor",-1))
				prompt = "G  /  Trade with %s" % item.name
				_interaction_allowed = _interaction_vendor >= 0
			"stash":
				prompt = "G  /  Open the town stash"
				_interaction_allowed = true
			"portal":
				prompt = "G  /  Step into the arena"
				_interaction_allowed = true
			"waystone":
				if activated.has(item.id):
					prompt = item.name + "  /  Restored"
				else:
					var guarded := false
					for enemy in enemies:
						if is_instance_valid(enemy) and enemy.alive and enemy.position.distance_to(item.position) < 12.0:
							guarded = true
							break
					prompt = "Defeat the nearby guardians to restore this waystone" if guarded else "G  /  Restore " + item.name
					_interaction_allowed = not guarded
			_:
				continue
		break
	hud.set_interaction(prompt)

func interact() -> void:
	if _ui_open():
		return
	_update_interaction()
	if not _interaction_allowed:
		return
	match _interaction_kind:
		"vendor":
			world_ui.open_vendor(_interaction_vendor)
		"stash":
			world_ui.open_stash()
		"portal":
			if _client():
				hud.show_feedback("The host opens the arena from their own session.",3.0)
				return
			_enter_arena()
		"camp":
			if _client():
				send_action("rest")
				hud.show_feedback("Resting at the campfire.",1.5)
				return
			health = max_health
			stamina = max_stamina
			hud.show_feedback("Rested. The town is waiting.")
		"waystone":
			if _client():
				hud.show_feedback("Only the host can restore the frontier waystones.",3.0)
				return
			activated[_interaction_id] = true
			world.activate_interactable(_interaction_id)
			_award_gold(25)
			if network_role == "host":
				_world_waystone.rpc(_interaction_id)
				_world_reward.rpc(25)
			audio.play_sound("bullseye")
			hud.show_feedback("Waystone restored  /  +25 gold")
			if activated.size() == 3:
				_award_gold(100)
				if network_role == "host":
					_world_reward.rpc(100)
				hud.show_feedback("FRONTIER RESTORED  /  All three waystones lit  /  +100 gold", 6.0)

func _preferred_name() -> String:
	var value := _delve_name.strip_edges()
	if value.is_empty():
		var cache := get_node_or_null("/root/NetCache")
		if cache != null:
			value = str(cache.player_name).strip_edges()
	return "Ranger" if value.is_empty() else value.left(16)

func _enter_arena() -> void:
	if _entering_scene:
		return
	_entering_scene = true
	cancel_input()
	_close_network()
	if _ui_open():
		world_ui.close()
	if _player_state != null:
		_player_state.save_state()
	var player_name := _preferred_name()
	var session := get_node_or_null("/root/Session")
	if session != null:
		session.arm_arena("skirmish","127.0.0.1",7777,player_name)
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cache.remember(player_name,"",7777,"arena")
	get_tree().change_scene_to_file("res://arena.tscn")

func _enter_delve() -> void:
	if _entering_scene:
		return
	_entering_scene = true
	cancel_input()
	if _ui_open():
		world_ui.close()
	if _player_state != null:
		_player_state.save_state()
	# A world host keeps the name it opened the world with; a solo fall may use
	# the remembered delve or network name.
	var player_name := _player_name if network_role == "host" else _preferred_name()
	var session := get_node_or_null("/root/Session")
	if network_role == "host":
		# Keep the live ENet server and its port: the party follows the host's
		# fall into a hosted delve instead of being dropped for a solo run.
		if session != null:
			session.arm_delve("delve-carry-host","127.0.0.1",_world_port,player_name)
			session.descend_party.rpc(_world_port)
	else:
		_close_network()
		if session != null:
			# Host Tailscale.cmd launches the frontier with --delve-host, so the
			# hatch fall is what actually opens the hosted party on that port.
			session.arm_delve("delve-host" if _delve_host else "delve-solo","127.0.0.1",_delve_port,player_name)
	get_tree().change_scene_to_file("res://delve.tscn")


## A rider cannot migrate the party by dropping alone. The host's authority
## keeps the session together; the local repl can only ask the host to lift the
## seat back out, so this view just reports it until the snapshot corrects.
func _refuse_client_descent() -> void:
	if _descent_refusal_cooldown > 0.0:
		return
	_descent_refusal_cooldown = 2.0
	cancel_input()
	hud.show_feedback("Only the host can lead the party into the delve.",3.0)


## The open-world host leads the whole party into the delve. This runs on a
## client when the host's reliable /root/Session RPC arrives, so the ENet peer
## the two peers already share is adopted by the delve scene instead of closed.
func _on_party_descent(port: int) -> void:
	if _entering_scene or network_role != "client":
		return
	_entering_scene = true
	if _ui_open():
		world_ui.close()
	if _player_state != null:
		_player_state.save_state()
	var session := get_node_or_null("/root/Session")
	if session != null:
		session.arm_delve("delve-carry-client",_world_address,port,_player_name)
	get_tree().change_scene_to_file("res://delve.tscn")

## A landed mob blow: the guard outcome, the damage, its feedback and, in a
## host session, the seat it belongs to. Wrapped by the profiler because a room
## full of attackers spends real time in here.
func _on_enemy_attack(attacker, amount: float, victim = null) -> void:
	Perf.begin("mob.hit")
	_resolve_enemy_attack(attacker, amount, victim)
	Perf.end()


func _resolve_enemy_attack(attacker, amount: float, victim = null) -> void:
	if not is_instance_valid(attacker) or not attacker.alive:
		return
	if victim != null and victim != player:
		_receive_seat_attack(attacker,amount,victim)
		return
	var outcome: int = combat.resolve_melee_defense(attacker.global_position)
	if outcome == Combat.DEFENSE_PARRY:
		attacker.stagger(Combat.PARRY_STAGGER)
		Combat.spawn_impact(self,player.global_position + Vector3(0,1.15,0),"parry")
		audio.play_sound("parry")
		hud.show_feedback("PARRY  /  counter now",1.2)
		return
	if outcome == Combat.DEFENSE_BLOCK or outcome == Combat.DEFENSE_WEAK_BLOCK:
		var cost: float = combat.block_stamina_cost()
		stamina = maxf(0.0,stamina-cost)
		var push: Vector3 = player.global_position - attacker.global_position
		push.y = 0.0
		if push.length_squared() > 0.000001:
			push = push.normalized() * Combat.BLOCK_PUSH_SPEED
			player.velocity.x = push.x
			player.velocity.z = push.z
		Combat.spawn_impact(self,player.global_position + Vector3(0,1.15,0),"block")
		audio.play_sound("block")
		if outcome == Combat.DEFENSE_WEAK_BLOCK:
			take_damage(amount * Combat.WEAK_BLOCK_DAMAGE_SCALE,false)
			if health > 0.0:
				hud.show_feedback("WEAK BLOCK  /  -%d stamina  /  dagger only softens the hit" % int(cost),1.2)
		else:
			hud.show_feedback("BLOCKED  /  -%d stamina" % int(cost),1.0)
		return
	Perf.begin("hit.damage")
	take_damage(amount)
	Perf.end()
	# The unmitigated contact is the only branch that spilled blood. The attacker
	# may carry a blade or a bare claw; `stain_attacker` owns both cases.
	BloodFx.impact(attacker,player.global_position + Vector3(0,1.1,0),
		player.global_position - attacker.global_position,amount,false)
	Perf.begin("hit.stain")
	BloodFx.stain_attacker(attacker,amount)
	Perf.end()

func _receive_seat_attack(attacker, amount: float, seat) -> void:
	if not is_instance_valid(seat):
		return
	var outcome: int = seat.receive_melee(amount,-1,attacker.global_position)
	if outcome == Combat.DEFENSE_PARRY:
		attacker.stagger(Combat.PARRY_STAGGER)
		Combat.spawn_impact(self,seat.global_position + Vector3(0,1.15,0),"parry")
		audio.play_sound("parry")
		return
	if outcome == Combat.DEFENSE_BLOCK or outcome == Combat.DEFENSE_WEAK_BLOCK:
		Combat.spawn_impact(self,seat.global_position + Vector3(0,1.15,0),"block")
		audio.play_sound("block")
		return
	BloodFx.impact(attacker,seat.global_position + Vector3(0,1.1,0),seat.global_position - attacker.global_position,amount,false)
	BloodFx.stain_attacker(attacker,amount)

func take_damage(amount: float, react: bool = true) -> void:
	_cancel_consumable()
	var applied: float = amount * (1.0 - archer.damage_reduction())
	applied = _absorb_with_ward(applied)
	health = maxf(0.0, health - applied)
	if react:
		var seconds: float = combat.stagger_from_damage(applied,max_health)
		archer.set_hit_react(seconds)
		step.reset()
	DamageNumbers.spawn(self,player.global_position,applied,"self",false,health <= 0.0)
	Perf.begin("hit.wound")
	BloodFx.wound(self,archer,player.global_position + Vector3(0,1.05,0),applied,
		false,health <= 0.0,1.0)
	Perf.end()
	audio.play_sound("hit")
	hud.flash_damage()
	if health <= 0.0:
		respawns += 1
		return_to_camp()
		hud.show_feedback("You fell. Recovered at the village campfire.", 4.0)

func return_to_camp() -> void:
	if _client():
		send_action("respawn")
		return
	cancel_input()
	_cancel_consumable()
	_heal_remaining = 0.0
	_heal_rate = 0.0
	roll.reset()
	step.reset()
	cover.reset()
	slide.reset()
	archer.set_hit_react(0.0)
	_jump_requested = false
	_movement_direction = Vector3.ZERO
	archer.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	archer.set_slide(-1.0,Vector3.FORWARD)
	archer.set_roll(-1.0,Vector3.FORWARD)
	player.global_position = world.player_spawn + Vector3(0, 0.25, 0)
	player.velocity = Vector3.ZERO
	health = max_health
	stamina = max_stamina
	ward_seconds = 0.0
	archer.set_ward(false)
	_sprint_exhausted = false
	ability.reset()
	inspecting = false
	hud.set_inspecting(false)
	camera_yaw = 0.22
	camera_pitch = 0.08
	camera_distance = 4.5
	_camera_ready = false
	hud.show_feedback("Hearthstead gate  /  Safe haven")
	_set_cursor_free(false)

func _on_arrow_released(origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	var shot_damage := Combat.damage_for(archer.bow_index, charge, archer.ranged_scale())
	var excluded: Array[RID] = [player.get_rid()]
	if is_instance_valid(archer.active_shield):
		excluded.append(archer.active_shield.get_rid())
	_spawn_arrow(origin,direction,speed,shot_damage,excluded,archer.last_arrow_visual_origin,0)
	if network_role == "host":
		_world_arrow.rpc(origin,direction,speed,archer.last_arrow_visual_origin,0)
	shots += 1
	audio.play_sound("release")

func _on_arrow_impact(enemy_hit: bool, _position: Vector3) -> void:
	if enemy_hit:
		audio.play_sound("hit")

func _on_weapon_thrown(origin: Vector3, direction: Vector3, speed: float, charge: float, weapon_name: String, weapon_index: int) -> void:
	var shot_damage := Combat.throw_damage(weapon_name,weapon_index,charge,archer.throw_scale())
	var excluded: Array[RID] = [player.get_rid()]
	_spawn_thrown(origin,direction,speed,shot_damage,weapon_name,weapon_index,excluded,0)
	if network_role == "host":
		_world_throw.rpc(origin,direction,speed,weapon_name,weapon_index,0)
	audio.play_sound("release")

func _on_enemy_defeated(enemy: Node3D, reward: int) -> void:
	var killer := -1
	if enemy.get("last_hitter") != null:
		killer = int(enemy.last_hitter)
	_grant_kill_refill(killer)
	if killer == _local_seat_id():
		reward = int(round(float(reward) * TrinketStats.gold_scale(trinket_stats)))
	_award_gold(reward)
	kills += 1
	var kind_value = enemy.get("kind")
	var drop_kind: int = int(kind_value) if kind_value != null else 0
	var drop_at: Vector3 = enemy.global_position
	var display_name := str(enemy.get_display_name())
	enemies.erase(enemy)
	hud.show_feedback("%s defeated  /  +%d gold" % [display_name, reward])
	var held_id := ""
	if enemy.has_method("held_weapon_id"):
		held_id = str(enemy.held_weapon_id())
	if not held_id.is_empty():
		# A weapon-carrying devil leaves the actual piece it was holding, on a
		# tenth of the old drop rate.
		if LootRules.drops():
			_spawn_loot(held_id, drop_at)
	elif (kills + drop_kind) % 2 == 0 and LootRules.drops():
		var item_id := str(LOOT_SEQUENCE[_loot_cursor % LOOT_SEQUENCE.size()])
		_loot_cursor += 1
		_spawn_loot(item_id, drop_at)
	if network_role == "host":
		_world_kill.rpc(reward,display_name,killer)

func _spawn_loot(item_id: String, at: Vector3, armed := true, broadcast := true) -> Node3D:
	var pickup := LootPickup.new()
	pickup.name = "Loot_" + item_id
	pickup.setup(item_id, _loot_display_name(item_id))
	pickup.set_armed(armed)
	pickup.position = _drop_floor(at)
	add_child(pickup)
	loot_pickups.append(pickup)
	if broadcast and network_role == "host":
		_world_loot.rpc(item_id,pickup.position,armed)
	return pickup

func _drop_floor(at: Vector3) -> Vector3:
	_floor_query.from = at + Vector3(0, 2.0, 0)
	_floor_query.to = at - Vector3(0, 3.0, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	return (hit.position + Vector3(0, 0.05, 0)) if not hit.is_empty() else at

func _loot_display_name(item_id: String) -> String:
	if _player_state != null and _player_state.has_method("item_name"):
		var named := str(_player_state.item_name(item_id))
		if not named.is_empty() and named != item_id:
			return named
	return item_id.capitalize()

func _backpack_capacity() -> int:
	return int(_player_state.INVENTORY_CAPACITY) if _player_state != null else 15

func _refresh_backpack() -> void:
	if hud == null:
		return
	var count: int = _player_state.inventory.size() if _player_state != null else 0
	hud.set_backpack(count, _backpack_capacity())

func _collect_loot(delta: float) -> void:
	_full_message_cooldown = maxf(0.0, _full_message_cooldown - delta)
	for index in range(loot_pickups.size() - 1, -1, -1):
		var pickup: Node3D = loot_pickups[index]
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			loot_pickups.remove_at(index)
			continue
		if _player_state == null:
			continue
		var offset: Vector3 = pickup.global_position - player.global_position
		var in_reach: bool = Vector2(offset.x, offset.z).length() <= PICKUP_RADIUS and absf(offset.y) <= 2.4
		if not in_reach:
			# A freshly dropped item arms itself once the dropper steps clear;
			# only a later approach collects it.
			if not bool(pickup.get("armed")):
				pickup.set("armed", true)
			continue
		if not bool(pickup.get("armed")):
			continue
		var item_id := str(pickup.get("item_id"))
		var result: Dictionary = _player_state.try_pickup(item_id)
		if bool(result.get("ok", false)):
			var picked := str(pickup.get("display_name"))
			loot_pickups.remove_at(index)
			pickup.queue_free()
			var capacity := _backpack_capacity()
			_refresh_backpack()
			hud.show_feedback("Picked up %s  /  backpack %d/%d" % [picked, _player_state.inventory.size(), capacity], 2.5)
		elif _full_message_cooldown <= 0.0:
			_full_message_cooldown = FULL_MESSAGE_INTERVAL
			hud.show_feedback("Backpack full  /  backpack %d/%d  /  sell or stash a piece in town" % [_player_state.inventory.size(), _backpack_capacity()], 2.5)

func _award_gold(amount: int) -> void:
	gold += amount
	if _player_state != null:
		_player_state.add_credits(amount)


## Open world (PvE town and frontier): the host simulates every ranger, enemy
## and pickup. Clients send movement/action intents and render replicated
## seats, mobs and projectiles. Each peer keeps its own PlayerState save.

func _setup_network() -> void:
	_link.configure(_link_lag,_link_jitter)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _join_failed("Could not join. Check the address, UDP port and host capacity (four rangers)."))
	multiplayer.server_disconnected.connect(func(): _connection_ended("The host closed the open world. You are alone now."))
	var session := get_node_or_null("/root/Session")
	if session != null and not session.party_descent.is_connected(_on_party_descent):
		session.party_descent.connect(_on_party_descent)
	var pending: Dictionary = session.take() if session != null else {}
	var mode := str(pending.get("mode",""))
	var pending_name := str(pending.get("name","")).strip_edges()
	_player_name = _safe_player_name(pending_name if not pending_name.is_empty() else _world_name if not _world_name.is_empty() else _preferred_name())
	if not _world_join.is_empty():
		join_world(_world_join,_world_port)
	elif _world_host:
		host_world(_world_port,_player_name)
	elif mode == "world-host":
		host_world(int(pending.get("port",_world_port)),_player_name)
	elif mode == "world-join":
		join_world(str(pending.get("address","127.0.0.1")),int(pending.get("port",7777)))


func host_world(port: int, player_name: String) -> void:
	if port < 1024 or port > 65535:
		hud.show_feedback("Choose a UDP port between 1024 and 65535.",4.0)
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port,WORLD_SEATS - 1)
	if error != OK:
		hud.show_feedback("Could not open the world on UDP %d: %s" % [port,error_string(error)],6.0)
		print("WORLD_HOST_FAILED port=",port," error=",error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	network_role = "host"
	local_slot = 0
	_player_name = _safe_player_name(player_name)
	_endpoint = "UDP %d" % port
	_world_address = "127.0.0.1"
	_world_port = port
	_update_session_line()
	hud.show_feedback("Open world on %s  /  friends: Join Game, Open world" % _endpoint,8.0)
	print("WORLD_HOST_READY port=",port)


func join_world(address: String, port: int) -> void:
	address = address.strip_edges()
	if address.is_empty() or port < 1024 or port > 65535:
		hud.show_feedback("Enter the host's address and a UDP port between 1024 and 65535.",4.0)
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address,port)
	if error != OK:
		hud.show_feedback("Could not start the connection: " + error_string(error),4.0)
		return
	multiplayer.multiplayer_peer = peer
	network_role = "client"
	local_slot = -1
	_join_elapsed = 0.0
	_set_replicas(true)
	_endpoint = "%s:%d" % [address,port]
	_world_address = address
	_world_port = port
	hud.show_feedback("Connecting to %s..." % _endpoint,4.0)


func _connected() -> void:
	if network_role != "client":
		return
	multiplayer.multiplayer_peer.get_peer(1).set_timeout(32,2000,5000)
	_world_register.rpc_id(1,_player_name,_local_loadout())


func _join_failed(message: String) -> void:
	if network_role != "client" or local_slot >= 0:
		return
	_close_network()
	_set_replicas(false)
	hud.show_feedback(message + "  Playing alone.",6.0)
	print("WORLD_JOIN_FAILED")


func _connection_ended(message: String) -> void:
	if network_role == "offline":
		return
	var last_position: Vector3 = player.global_position if is_instance_valid(player) else world.player_spawn
	_close_network()
	_set_replicas(false)
	_restore_anchor(last_position)
	hud.show_feedback(message,6.0)
	print("WORLD_CONNECTION_LOST")


func _close_network() -> void:
	if _local_anchor_swapped:
		_restore_anchor(player.global_position if is_instance_valid(player) else world.player_spawn)
	network_role = "offline"
	local_slot = -1
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for slot in _seats.keys():
		var seat = _seats[slot]
		if is_instance_valid(seat):
			seat.predicting = false
			seat.queue_free()
	_seats.clear()
	_seat_list.clear()
	_peer_slots.clear()
	server_tick = 0
	_send_elapsed = 0.0
	_enemy_elapsed = 0.0
	_clock.clear()
	_lag.clear()
	_link.clear()
	_update_session_line()


func _restore_anchor(at: Vector3) -> void:
	if not _local_anchor_swapped:
		return
	player = _anchor_player
	archer = _anchor_rig
	combat = _anchor_combat
	cover = _anchor_cover
	ability = _anchor_ability
	_local_anchor_swapped = false
	_anchor_player.visible = true
	_anchor_player.process_mode = Node.PROCESS_MODE_INHERIT
	_camera_boom = -1.0
	_anchor_player.global_position = at + Vector3(0,0.25,0)
	_anchor_player.velocity = Vector3.ZERO
	_anchor_player.collision_layer = 4
	_anchor_player.collision_mask = 1 | 2
	if world_ui != null:
		world_ui.rebind(_anchor_rig)
	_update_loadout()


func _peer_connected(peer_id: int) -> void:
	if network_role != "host":
		return
	multiplayer.multiplayer_peer.get_peer(peer_id).set_timeout(32,2000,5000)
	var slot := _free_seat_slot()
	if slot < 0:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	_peer_slots[peer_id] = slot
	_create_seat(slot,peer_id,true,"Joining ranger")
	_world_accept.rpc_id(peer_id,slot)
	_broadcast_roster()
	_update_session_line()
	print("WORLD_PEER_JOINED slot=",slot," rangers=",get_human_count())


func _peer_disconnected(peer_id: int) -> void:
	if network_role != "host" or not _peer_slots.has(peer_id):
		return
	var slot := int(_peer_slots[peer_id])
	_peer_slots.erase(peer_id)
	if _seats.has(slot):
		var seat = _seats[slot]
		if is_instance_valid(seat):
			seat.queue_free()
		_seats.erase(slot)
	_rebuild_seat_list()
	_broadcast_roster()
	_update_session_line()
	print("WORLD_PEER_LEFT slot=",slot," rangers=",get_human_count())


func _free_seat_slot() -> int:
	for slot in range(1,WORLD_SEATS):
		if not _peer_slots.values().has(slot):
			return slot
	return -1


func _create_seat(slot: int, peer_id: int, authoritative: bool, seat_name: String) -> Node3D:
	var seat = Seat.new()
	seat.slot = slot
	seat.authoritative = authoritative
	seat.is_bot = false
	seat.bounds = world.WORLD_LIMIT - 2.0
	seat.name = "Ranger%d" % slot
	seat.process_priority = -10
	add_child(seat)
	seat.fired.connect(_on_seat_fired)
	seat.thrown_weapon.connect(_on_seat_thrown)
	seat.configure(peer_id,false,_safe_player_name(seat_name),world.player_spawn + Vector3(0.75*float(slot),0.15,0.75*float(slot)))
	seat.collision_mask = 1 | 2
	seat.combat.target_mask = 2
	seat.combat.damage_enabled = authoritative
	seat.combat.lag_rewind = _lag
	_bind_ability_cues(seat.ability)
	_seats[slot] = seat
	_rebuild_seat_list()
	return seat


func _rebuild_seat_list() -> void:
	_seat_list.clear()
	var slots := _seats.keys()
	slots.sort()
	for slot in slots:
		if is_instance_valid(_seats[slot]):
			_seat_list.append(_seats[slot])


func _broadcast_roster() -> void:
	if network_role != "host":
		return
	var entries: Array = [{"slot":0,"name":_player_name}]
	for slot in _seats.keys():
		var seat = _seats[slot]
		if is_instance_valid(seat):
			entries.append({"slot":int(slot),"name":str(seat.display_name)})
	entries.sort_custom(func(a,b): return int(a.slot) < int(b.slot))
	_world_roster.rpc(entries)


@rpc("authority","call_remote","reliable")
func _world_roster(entries: Array) -> void:
	if network_role != "client":
		return
	var seen := {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := int(entry.get("slot",-1))
		if slot < 0 or slot >= WORLD_SEATS:
			continue
		seen[slot] = true
		var seat_name := _safe_player_name(str(entry.get("name","Ranger")))
		if _seats.has(slot) and is_instance_valid(_seats[slot]):
			_seats[slot].display_name = seat_name
		else:
			_create_seat(slot,0,false,seat_name)
			if slot == local_slot:
				_bind_local_seat()
	for slot in _seats.keys():
		if seen.has(slot):
			continue
		var seat = _seats[slot]
		if is_instance_valid(seat):
			seat.queue_free()
		_seats.erase(slot)
	_rebuild_seat_list()
	_update_session_line()


@rpc("authority","call_remote","reliable")
func _world_accept(slot: int) -> void:
	if network_role != "client" or slot < 1 or slot >= WORLD_SEATS:
		return
	local_slot = slot
	_snapshot_ticks[slot] = -1
	_join_elapsed = 0.0
	if not _seats.has(slot) or not is_instance_valid(_seats[slot]):
		_create_seat(slot,0,false,_player_name)
	_seats[slot].interp_delay = 0.05
	_clock.configure(60.0,0.12)
	_bind_local_seat()
	hud.show_feedback("Joined the open world.",3.0)
	print("WORLD_CLIENT_READY slot=",slot)


@rpc("any_peer","call_remote","reliable")
func _world_register(player_name: String, loadout: Dictionary) -> void:
	if network_role != "host":
		return
	var sender := _sender_id()
	if not _peer_slots.has(sender):
		return
	var slot := int(_peer_slots[sender])
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat):
		return
	seat.display_name = _safe_player_name(player_name)
	SeatLoadout.apply(seat.rig,loadout)
	_broadcast_roster()


func _bind_local_seat() -> void:
	var seat = _seats.get(local_slot)
	if seat == null or not is_instance_valid(seat):
		return
	player = seat
	archer = seat.rig
	combat = seat.combat
	cover = seat.cover
	ability = seat.ability
	seat.is_local = true
	seat.predicting = true
	_local_anchor_swapped = true
	# The client still owns its own saved kit; the seat's copies of it drive the
	# bar maxima while every hit, charge and kill stays host-authoritative.
	if _player_state != null:
		seat.apply_trinkets(_player_state.trinkets())
	health = seat.health
	stamina = seat.stamina
	max_health = seat.max_health
	max_stamina = seat.max_stamina
	trinket_stats = seat.trinket_stats.duplicate()
	if hud != null:
		hud.set_limits(max_health, max_stamina)
	_anchor_player.visible = false
	_anchor_player.collision_layer = 0
	_anchor_player.collision_mask = 0
	_anchor_player.process_mode = Node.PROCESS_MODE_DISABLED
	if world_ui != null:
		world_ui.rebind(seat.rig)
	if not seat.rig.loadout_changed.is_connected(_update_loadout):
		seat.rig.loadout_changed.connect(_update_loadout)
	_update_loadout()
	_refresh_backpack()
	camera_focus = seat.global_position + Vector3.UP * 1.05
	_camera_ready = false
	_camera_boom = -1.0


func _update_session_line() -> void:
	if hud == null:
		return
	if network_role == "offline":
		hud.set_session("")
		return
	var count := get_human_count()
	hud.set_session("OPEN WORLD  /  %s  /  %d RANGER%s" % [_endpoint,count,"" if count == 1 else "S"])


func get_human_count() -> int:
	if network_role == "host":
		return 1 + _peer_slots.size()
	if network_role == "client":
		return maxi(1,_seats.size())
	return 0


func _set_replicas(value: bool) -> void:
	for enemy in _enemies_by_index:
		if is_instance_valid(enemy):
			enemy.replica = value


func _client() -> bool:
	return network_role == "client" and local_slot >= 0


## The seat this peer owns. Offline play is seat 0 with no network peer, and a
## joined client learns its slot from the host's accept.
func _local_seat_id() -> int:
	return local_slot if local_slot >= 0 else 0


## The peer whose RPC is in flight, or -1 once this node has left the tree: a
## scene hand-off can deliver one last intent to a session that is already gone.
func _sender_id() -> int:
	var api := multiplayer
	if api == null:
		return -1
	return api.get_remote_sender_id()


func _safe_player_name(value: String) -> String:
	var clean := value.strip_edges().replace("\n"," ").replace("\r"," ").replace("\t"," ").left(16)
	return "Ranger" if clean.is_empty() else clean


func _local_loadout() -> Dictionary:
	if _player_state == null:
		return {}
	return {
		"main":str(_player_state.main_item()),
		"off":str(_player_state.off_item()),
		"bow":int(_player_state.equipped_index("bow")),
		"sword":int(_player_state.equipped_index("sword")),
		"armor":ArmorData.pack(_player_state.equipped_pieces()),
		"trinkets":_player_state.trinkets(),
	}


func _client_step(delta: float) -> void:
	if local_slot < 0:
		_join_elapsed += delta
		if _join_elapsed > 6.0:
			_join_failed("Connection timed out. The host may be offline, full, or blocked by a firewall.")
		return
	_collect_loot(delta)
	if _descent_refusal_cooldown > 0.0:
		_descent_refusal_cooldown = maxf(0.0,_descent_refusal_cooldown-delta)
	if not _entering_scene and world.is_over_delve_hatch(player.global_position) and player.global_position.y < 2.25:
		_refuse_client_descent()
		return
	if player.position.y < -25.0:
		send_action("respawn")
	update_crosshair_aim()
	var left := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
	var right_key := float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var forward := float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	var back_key := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var motion := Vector2(left - right_key,forward - back_key)
	if motion.length() > 1.0:
		motion = motion.normalized()
	if inspecting or hud.map_open or _cursor_free or _ui_open():
		motion = Vector2.ZERO
	var camera_right := Vector2(cos(camera_yaw),-sin(camera_yaw))
	var camera_back := Vector2(sin(camera_yaw),cos(camera_yaw))
	var direction := camera_right * motion.x + camera_back * motion.y
	var running: bool = Input.is_physical_key_pressed(KEY_SHIFT) and not _ui_open() and not hud.map_open
	# Prediction: this frame is integrated here and sent as its own frame, so the
	# host repeats exactly the intent the player is acting on rather than a
	# 20 Hz sample of it. The acknowledgement comes back on the next snapshot.
	_clock.advance(delta)
	var seat = _seats.get(local_slot)
	if seat == null or not is_instance_valid(seat):
		return
	var view := _view_tick()
	seat.update_input(direction,running,view)
	seat.predicted_step(delta,_seat_list)
	_world_move.rpc_id(1,direction,running,_client_aim,_snapshot_ticks[local_slot],
		_client_aim_origin if _client_aim_origin_valid else null,seat.latest_prediction_seq(),view,
		seat.input_history())


func _host_network_step(delta: float) -> void:
	if _peer_slots.is_empty():
		return
	Perf.begin("net.host")
	server_tick += 1
	var bodies: Array[CharacterBody3D] = [player]
	for seat in _seat_list:
		if is_instance_valid(seat) and seat.alive:
			bodies.append(seat)
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.targets = bodies
	for seat in _seat_list.duplicate():
		if is_instance_valid(seat):
			seat.combat.lag_tick = server_tick
			seat.step(delta,_seat_list,server_tick)
			_rescue_seat_from_hatch(seat)
	# One second of mob poses, recorded before any client intent this tick can
	# be resolved against them.
	Perf.begin("net.lag")
	_lag.record(server_tick,_enemies_by_index)
	Perf.end()
	_send_elapsed += delta
	if _send_elapsed >= NET_TICK:
		_send_elapsed = fmod(_send_elapsed,NET_TICK)
		Perf.begin("net.seats")
		_send_seat_snapshots()
		Perf.end()
	_enemy_elapsed += delta
	if _enemy_elapsed >= ENEMY_TICK:
		_enemy_elapsed = fmod(_enemy_elapsed,ENEMY_TICK)
		Perf.begin("net.mobs")
		_send_enemy_snapshots()
		Perf.end()
	Perf.end()


## Only the session authority may open the party's route down. A rider whose
## seat drops into the hatch alone is set back on the inn floor before the open
## world's client-side trigger would tear the party apart.
func _rescue_seat_from_hatch(seat) -> void:
	if not is_instance_valid(seat) or not seat.alive:
		return
	if seat.global_position.y >= 2.6 or not world.is_over_delve_hatch(seat.global_position):
		return
	seat.global_position = Vector3(16.0,3.45,44.0)
	seat.velocity = Vector3.ZERO
	if int(seat.peer_id) > 1:
		_world_notice.rpc_id(int(seat.peer_id),"Only the host can lead the party into the delve.")


func _send_seat_snapshots() -> void:
	_snapshot_ticks[0] = server_tick
	_world_seat.rpc(server_tick,0,_local_seat_snapshot())
	for seat in _seat_list:
		if not is_instance_valid(seat):
			continue
		_snapshot_ticks[seat.slot] = server_tick
		_world_seat.rpc(server_tick,seat.slot,seat.snapshot())


func _local_seat_snapshot() -> Dictionary:
	return {"slot":0,"peer":1,
		"position":player.global_position,"velocity":player.velocity,
		"health":health,"maxh":max_health,"ward":ward_seconds,
		"alive":health > 0.0,"kills":kills,"deaths":respawns,"respawn":0.0,
		"bow":archer.bow_index,
		"armor":archer.armor_bits() | (ArmorData.SHIELD_BIT if archer.shield_equipped else 0),
		"sword":archer.sword_index,"weapon":archer.weapon,
		"gear":Seat.gear_bits_for(archer),"weapon_blood":0.0,
		"stamina":stamina,"ability":ability.pack_snapshot(),
		"animation":archer.pack_animation_state(archer.get_animation_state()),"progress":combat.attack_progress,
		"movement":combat.movement_mode,
		"aim":combat.aim_point,"grounded":player.is_on_floor(),"cover":cover.pack_snapshot()}


@rpc("authority","call_remote","unreliable")
func _world_seat(tick: int, slot: int, state: Dictionary) -> void:
	if network_role != "client" or slot < 0 or slot >= WORLD_SEATS:
		return
	if _link.active():
		_link.defer(func(): _apply_world_seat(tick,slot,state))
		return
	_apply_world_seat(tick,slot,state)


func _apply_world_seat(tick: int, slot: int, state: Dictionary) -> void:
	if tick <= _snapshot_ticks[slot]:
		return
	_snapshot_ticks[slot] = tick
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat):
		return
	if slot == local_slot:
		_clock.ingest(tick,Time.get_ticks_msec()/1000.0)
	seat.apply_snapshot(state,tick,_seat_list)
	if slot != local_slot:
		return
	if seat.health < health - 0.01:
		hud.flash_damage()
		audio.play_sound("hit")
	health = seat.health
	stamina = seat.stamina
	max_health = seat.max_health
	max_stamina = seat.max_stamina
	trinket_stats = seat.trinket_stats.duplicate()
	hud.set_limits(max_health, max_stamina)
	if not seat.alive and not _client_dead_notified:
		_client_dead_notified = true
		hud.show_feedback("You fell. Recovering at the town gate.",3.0)
	elif seat.alive and _client_dead_notified:
		_client_dead_notified = false


@rpc("any_peer","call_remote","unreliable_ordered")
func _world_move(direction: Vector2, running: bool, aim: Variant, aim_tick: Variant, aim_origin: Variant = null, seq: Variant = -1, view: Variant = -1, history: Array = []) -> void:
	if network_role != "host":
		return
	var sender := _sender_id()
	if not _peer_slots.has(sender):
		return
	var slot := int(_peer_slots[sender])
	if _link.active():
		_link.defer(func(): _apply_world_move(slot,direction,running,aim,aim_tick,aim_origin,seq,view,history))
		return
	_apply_world_move(slot,direction,running,aim,aim_tick,aim_origin,seq,view,history)


func _apply_world_move(slot: int, direction: Vector2, running: bool, aim: Variant,
		aim_tick: Variant, aim_origin: Variant, seq: Variant, view: Variant,
		history: Array = []) -> void:
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat):
		return
	if not direction.is_finite():
		return
	# A frame without an aim sample still drives movement; only an aim that
	# fails validation leaves the previous point in place.
	if typeof(aim) == TYPE_VECTOR3 and typeof(aim_tick) == TYPE_INT \
			and not _set_seat_aim(slot,aim,int(aim_tick),aim_origin):
		return
	seat.accept_network_input(direction,running,
		int(seq) if typeof(seq) == TYPE_INT else -1,
		int(view) if typeof(view) == TYPE_INT else -1,
		history if typeof(history) == TYPE_ARRAY else [])


func send_action(action: String, value: Variant = null) -> void:
	if not _client():
		return
	# Locomotion intents start on this frame; combat, kits and skills stay
	# authoritative so a client never guesses its own hit.
	var seat = _seats.get(local_slot)
	if seat != null and is_instance_valid(seat):
		seat.predict_action(action,value)
	var origin: Variant = _client_aim_origin if _client_aim_origin_valid and action in ["draw","release","throw","throw_release","melee"] else null
	_world_action.rpc_id(1,action,value,_snapshot_ticks[local_slot],origin)


## The server tick this peer is currently drawing; its aim and swings are judged
## against that world, not the present one.
func _view_tick() -> int:
	if _clock.newest_tick() >= 0:
		return _clock.render_tick()
	return maxi(0,_snapshot_ticks[local_slot])


## Arms one seat's damage window with the rewind its owner needs.
func _arm_seat_lag(seat) -> void:
	seat.combat.lag_tick = server_tick
	seat.combat.lag_ticks = int(seat.lag_ticks(server_tick,MAX_LAG_TICKS)) if int(seat.peer_id) > 1 else 0


## How many ticks behind the host an archer was drawing when it released.
func _shooter_lag(slot: int) -> int:
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat) or int(seat.peer_id) <= 1:
		return 0
	return int(seat.lag_ticks(server_tick,MAX_LAG_TICKS))


@rpc("any_peer","call_remote","reliable")
func _world_action(action: String, value: Variant, aim_tick: Variant, aim_origin: Variant = null) -> void:
	if network_role != "host" or typeof(aim_tick) != TYPE_INT:
		return
	var sender := _sender_id()
	if not _peer_slots.has(sender):
		return
	var slot := int(_peer_slots[sender])
	if _link.active():
		_link.defer(func(): _apply_world_action(slot,action,value,int(aim_tick),aim_origin))
		return
	_apply_world_action(slot,action,value,int(aim_tick),aim_origin)


func _apply_world_action(slot: int, action: String, value: Variant, aim_tick: int,
		aim_origin: Variant) -> void:
	if action == "loadout":
		var seat = _seats.get(slot)
		if seat != null and is_instance_valid(seat) and typeof(value) == TYPE_DICTIONARY:
			SeatLoadout.apply(seat.rig,value)
		return
	if aim_tick > _snapshot_ticks[slot]:
		return
	_apply_seat_action(slot,action,value,aim_tick,aim_origin)


func _apply_seat_action(slot: int, action: String, value: Variant, aim_tick: int = -1, aim_origin: Variant = null) -> void:
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat):
		return
	if action == "respawn":
		seat.revive()
		return
	if action == "rest":
		if _near_camp(seat.global_position):
			seat.health = seat.max_health
			seat.stamina = seat.max_stamina
		return
	if not seat.alive:
		return
	# Every damage-capable intent carries the tick its owner was drawing, so the
	# host can rewind the mobs that peer actually saw.
	_arm_seat_lag(seat)
	match action:
		"draw":
			if typeof(value) == TYPE_VECTOR3 and _set_seat_aim(slot,value,aim_tick,aim_origin):
				seat.update_combat_cover_side()
				seat.combat.begin_draw()
		"melee":
			if typeof(value) != TYPE_DICTIONARY:
				return
			var aim = value.get("aim")
			var hand := str(value.get("hand","right"))
			var variant := str(value.get("variant","overhead"))
			if typeof(aim) != TYPE_VECTOR3 or hand not in ["left","right"] \
					or variant not in ["overhead","diagonal_left","diagonal_right","stab"]:
				return
			if _set_seat_aim(slot,aim,aim_tick,aim_origin):
				seat.update_combat_cover_side()
				seat.combat.begin_melee(hand,variant)
		"release":
			if typeof(value) == TYPE_VECTOR3 and _set_seat_aim(slot,value,aim_tick,aim_origin):
				seat.update_combat_cover_side()
				seat.combat.release_draw()
		"throw":
			if typeof(value) == TYPE_VECTOR3 and _set_seat_aim(slot,value,aim_tick,aim_origin):
				seat.update_combat_cover_side()
				seat.combat.begin_throw()
		"throw_release":
			if typeof(value) == TYPE_VECTOR3 and _set_seat_aim(slot,value,aim_tick,aim_origin):
				seat.update_combat_cover_side()
				seat.combat.release_throw()
		"step":
			if typeof(value) != TYPE_VECTOR3:
				return
			var direction: Vector3 = value
			if not direction.is_finite() or absf(direction.y) > 0.01:
				return
			var flat := Vector3(direction.x,0,direction.z)
			if absf(flat.length()-1.0) > 0.1:
				return
			seat.try_step(flat)
		"jump":
			if typeof(value) == TYPE_BOOL:
				seat.press_jump(value)
		"cover":
			if typeof(value) == TYPE_VECTOR3 and value.is_finite() and value.length_squared() > 0.01 and value.length_squared() <= 1000000.0:
				seat.toggle_cover(value.normalized())
		"crouch":
			if typeof(value) == TYPE_BOOL:
				seat.set_crouch(value)
		"block":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("pressed")) != TYPE_BOOL or typeof(value.get("forward")) != TYPE_VECTOR3:
				return
			var forward: Vector3 = value.forward
			if not forward.is_finite() or (value.pressed and forward.length_squared() < 0.25):
				return
			seat.set_block(value.pressed,Vector3(forward.x,0,forward.z))
		"peek":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("pressed")) != TYPE_BOOL or typeof(value.get("right")) != TYPE_VECTOR3 or typeof(value.get("side")) != TYPE_INT:
				return
			var right: Vector3 = value.right
			if not right.is_finite() or absf(right.y) > 0.01 or absf(right.length_squared()-1.0) > 0.01 or value.side not in [-1,1]:
				return
			seat.peek_requested = value.pressed
			seat.peek_view_right = Vector3(right.x,0,right.z).normalized()
			seat.peek_shoulder = value.side
			seat.update_combat_cover_side()
		"stop":
			seat.combat.stop()
		"bow":
			if typeof(value) == TYPE_INT and value >= 0 and value < 3:
				seat.rig.set_bow(value)
		"sword":
			if typeof(value) == TYPE_INT and value >= 0 and value < 3:
				seat.rig.set_sword(value)
		"weapon":
			if typeof(value) == TYPE_STRING and value in ["bow","sword","dagger","dual"]:
				var requested := str(value)
				if requested == "dual":
					if seat.rig.weapon == "dual":
						requested = "sword"
					elif seat.rig.sword_index == 2:
						return
				seat.combat.stop()
				seat.rig.set_weapon(requested)
		"shield":
			if typeof(value) == TYPE_BOOL:
				seat.combat.stop()
				seat.rig.set_shield(value)
		"consume":
			if typeof(value) == TYPE_STRING and value in ["bandage","potion"]:
				seat.try_consume(value)
		"ability":
			if typeof(value) != TYPE_INT or int(value) < 0 or int(value) >= AbilityRules.SLOT_COUNT:
				return
			var seat_definition: Dictionary = seat.ability.definition(int(value))
			if not seat.ability.active and seat.alive and not seat_definition.is_empty():
				# The host resolves the target from the seat's replicated aim so
				# a backstab without one never spends the seat's stamina.
				var refusal: String = _prepare_backstab(seat, seat_definition)
				if not refusal.is_empty():
					if int(slot) == local_slot:
						hud.show_feedback(refusal,1.6)
					return
			seat.try_ability(int(value))
		"armor":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("slot")) != TYPE_STRING or typeof(value.get("set")) != TYPE_INT:
				return
			var armor_slot := str(value.slot)
			var armor_set := int(value.set)
			if armor_slot in ArmorData.SLOTS and armor_set >= 0 and armor_set < ArmorData.SET_IDS.size():
				seat.rig.set_armor_piece(armor_slot,armor_set)


func _set_seat_aim(slot: int, point: Vector3, aim_tick: int = -1, aim_origin: Variant = null) -> bool:
	if not point.is_finite() or point.length_squared() > 1000000.0:
		return false
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat):
		return false
	if aim_tick >= 0:
		if aim_tick > _snapshot_ticks[slot]:
			return false
		if aim_tick < seat.aim_snapshot_tick:
			return true
		seat.aim_snapshot_tick = aim_tick
	seat.update_cover_aim_readiness()
	seat.combat.set_aim(point)
	if typeof(aim_origin) == TYPE_VECTOR3:
		var origin: Vector3 = aim_origin
		var ray: Vector3 = point-origin
		if origin.is_finite() and origin.distance_squared_to(seat.global_position) <= 144.0 \
				and ray.is_finite() and ray.length_squared() > 0.01:
			seat.combat.set_camera_ray(origin,ray)
		else:
			seat.combat.clear_camera_ray()
	else:
		seat.combat.clear_camera_ray()
	if seat.combat.blocking:
		var facing: Vector3 = point - seat.global_position
		facing.y = 0.0
		if facing.length_squared() > 0.000001:
			seat.combat.face_block(facing)
	return true


func _near_camp(point: Vector3) -> bool:
	for item: Dictionary in world.interactables:
		if str(item.kind) == "camp":
			return point.distance_to(item.position) <= 3.8
	return false


func _enemy_relevant(enemy: Node3D) -> bool:
	if not _near_ranger(enemy.global_position):
		return false
	if enemy.alive:
		return true
	return _enemy_sends % 5 == 0


func _near_ranger(point: Vector3) -> bool:
	if is_instance_valid(player) and player.global_position.distance_squared_to(point) <= ENEMY_RELEVANCE * ENEMY_RELEVANCE:
		return true
	for seat in _seat_list:
		if is_instance_valid(seat) and seat.global_position.distance_squared_to(point) <= ENEMY_RELEVANCE * ENEMY_RELEVANCE:
			return true
	return false


func _send_enemy_snapshots() -> void:
	_enemy_sends += 1
	var states: Array = []
	for index in _enemies_by_index.size():
		var enemy = _enemies_by_index[index]
		if not is_instance_valid(enemy) or not _enemy_relevant(enemy):
			continue
		states.append(enemy.snapshot(index))
	# Byte-budgeted, not count-chunked: five busy mobs already encode past the
	# clamped payload, so the packer decides how many ride in one datagram.
	for batch in NetLimits.batches(states,[server_tick]):
		_world_mobs.rpc(server_tick,batch)


@rpc("authority","call_remote","unreliable")
func _world_mobs(tick: int, states: Array) -> void:
	if network_role != "client":
		return
	if _link.active():
		_link.defer(func(): _apply_world_mobs(tick,states))
		return
	_apply_world_mobs(tick,states)


func _apply_world_mobs(tick: int, states: Array) -> void:
	_clock.ingest(tick,Time.get_ticks_msec()/1000.0)
	for entry in states:
		if entry is PackedFloat32Array:
			var index := int(entry[MobWire.AT_INDEX])
			if index < 0 or index >= _enemies_by_index.size():
				continue
			var enemy = _enemies_by_index[index]
			if is_instance_valid(enemy):
				enemy.apply_snapshot(entry,tick)
			continue
		# Ranger clones still carry their animation block as a dictionary.
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var clone_index := int(entry.get("i",-1))
		if clone_index < 0 or clone_index >= _enemies_by_index.size():
			continue
		var clone = _enemies_by_index[clone_index]
		if is_instance_valid(clone):
			clone.apply_snapshot(entry,tick)


func _on_seat_fired(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	if network_role != "host":
		return
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat) or not seat.alive:
		return
	var damage := Combat.damage_for(seat.rig.bow_index,charge)
	_spawn_arrow(origin,direction,speed,damage,[seat.get_rid()],seat.rig.last_arrow_visual_origin,slot)
	_world_arrow.rpc(origin,direction,speed,seat.rig.last_arrow_visual_origin,slot)
	shots += 1


func _on_seat_thrown(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float, weapon_name: String, weapon_index: int) -> void:
	if network_role != "host":
		return
	var seat = _seats.get(slot)
	if seat == null or not is_instance_valid(seat) or not seat.alive:
		return
	var damage := Combat.throw_damage(weapon_name,weapon_index,charge)
	_spawn_thrown(origin,direction,speed,damage,weapon_name,weapon_index,[seat.get_rid()],slot)
	_world_throw.rpc(origin,direction,speed,weapon_name,weapon_index,slot)


## The ranger body behind a shot slot: the local ranger for slot 0/-1 and the
## matching host seat otherwise. Projectiles hand this to a mob's
## `note_attacker`, so a ranged hit always names the archer that fired it.
func _shooter_for_slot(slot: int) -> Node3D:
	if slot > 0:
		var seat = _seats.get(slot)
		if is_instance_valid(seat):
			return seat as Node3D
	return player


func _spawn_arrow(origin: Vector3, direction: Vector3, speed: float, shot_damage: float, excluded: Array[RID], visual_origin: Vector3 = Vector3.INF, source_slot: int = -1, authoritative: bool = true, pierce_count: int = 0) -> void:
	var arrow := Arrow.new()
	arrow.source_id = source_slot
	if authoritative and source_slot >= 0:
		arrow.lag_comp = _lag
		arrow.lag_ticks = _shooter_lag(source_slot)
	# Mob tracers and client visuals are spawned with `authoritative = false`;
	# their `slot` is not a ranger seat, so they never name a shooter.
	arrow.shooter = _shooter_for_slot(source_slot) if authoritative else null
	arrow.hit_mask = 1 | 2 | 8
	arrow.authoritative_damage = authoritative
	add_child(arrow)
	arrow.launch(origin,direction,speed,shot_damage,excluded,visual_origin,pierce_count)
	arrow.impacted.connect(_on_arrow_impact)
	for index in range(arrows.size() - 1, -1, -1):
		if not is_instance_valid(arrows[index]):
			arrows.remove_at(index)
	arrows.append(arrow)
	if arrows.size() > 32:
		arrows.pop_front().queue_free()


func _spawn_thrown(origin: Vector3, direction: Vector3, speed: float, shot_damage: float, weapon_name: String, weapon_index: int, excluded: Array[RID], source_slot: int = -1, authoritative: bool = true) -> void:
	var thrown := Thrown.new()
	thrown.weapon = weapon_name
	thrown.weapon_index = weapon_index
	thrown.source_id = source_slot
	if authoritative and source_slot >= 0:
		thrown.lag_comp = _lag
		thrown.lag_ticks = _shooter_lag(source_slot)
	thrown.shooter = _shooter_for_slot(source_slot)
	thrown.blade_length = float(Archer.DAGGER_DATA.length) if weapon_name == "dagger" else float(Archer.SWORD_DATA[clampi(weapon_index,0,2)].length)
	thrown.authoritative_damage = authoritative
	add_child(thrown)
	thrown.launch(origin,direction,speed,shot_damage,excluded)
	thrown.impacted.connect(_on_arrow_impact)
	for index in range(thrown_weapons.size() - 1, -1, -1):
		if not is_instance_valid(thrown_weapons[index]):
			thrown_weapons.remove_at(index)
	thrown_weapons.append(thrown)
	if thrown_weapons.size() > 32:
		thrown_weapons.pop_front().queue_free()


@rpc("authority","call_remote","reliable")
func _world_notice(text: String) -> void:
	if network_role != "client":
		return
	hud.show_feedback(text,3.0)


@rpc("authority","call_remote","reliable")
func _world_arrow(origin: Vector3, direction: Vector3, speed: float, visual_origin: Variant, slot: int) -> void:
	if network_role != "client":
		return
	var start: Vector3 = visual_origin if typeof(visual_origin) == TYPE_VECTOR3 else Vector3.INF
	_spawn_arrow(origin,direction,speed,0.0,[],start,slot,false)


@rpc("authority","call_remote","reliable")
func _world_throw(origin: Vector3, direction: Vector3, speed: float, weapon_name: String, weapon_index: int, slot: int) -> void:
	if network_role != "client":
		return
	_spawn_thrown(origin,direction,speed,0.0,weapon_name,weapon_index,[],slot,false)


func _on_mob_arrow(origin: Vector3, direction: Vector3, speed: float, _damage: float) -> void:
	if network_role == "host":
		_world_mob_arrow.rpc(origin,direction,speed)


@rpc("authority","call_remote","reliable")
func _world_mob_arrow(origin: Vector3, direction: Vector3, speed: float) -> void:
	if network_role != "client":
		return
	_spawn_arrow(origin,direction,speed,0.0,[],Vector3.INF,-1,false)


@rpc("authority","call_remote","reliable")
func _world_loot(item_id: String, at: Vector3, armed: bool) -> void:
	if network_role != "client":
		return
	_spawn_loot(item_id,at,armed,false)


@rpc("authority","call_remote","reliable")
func _world_kill(reward: int, display: String, killer: int = -1) -> void:
	if network_role != "client":
		return
	if killer == _local_seat_id():
		reward = int(round(float(reward) * TrinketStats.gold_scale(trinket_stats)))
	kills += 1
	_award_gold(reward)
	hud.show_feedback("%s defeated  /  +%d gold" % [display,reward])


@rpc("authority","call_remote","reliable")
func _world_reward(amount: int) -> void:
	if network_role != "client":
		return
	_award_gold(amount)


@rpc("authority","call_remote","reliable")
func _world_waystone(id: String) -> void:
	if network_role != "client":
		return
	activated[id] = true
	world.activate_interactable(id)
	audio.play_sound("bullseye")
	hud.show_feedback("Waystone restored",2.0)


## Measures the garment of every species the frontier already fields, once, at
## load. The first blow on a body measures its rig before blood can be laid on
## it, which cost twenty to a hundred milliseconds inside the hit; doing it here
## moves that to a frame nobody is watching.
func _warm_mob_blood() -> void:
	Perf.begin("world.warm")
	# The blood atlas is procedural and built on the first stain; build it now
	# rather than inside the first blow.
	BloodFx.soak_material(0)
	var seen := {}
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("blood_rig"):
			continue
		var rig = enemy.blood_rig()
		if not is_instance_valid(rig):
			continue
		# One sample per structure: bodies of the same species share one
		# measurement anyway, so warming the first warms them all.
		var key := BloodSurface.structure_key(rig)
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		Perf.begin("world.warm.species")
		BloodSurface.body_for(rig)
		Perf.end()
	if is_instance_valid(archer):
		BloodSurface.body_for(archer)
	Perf.end()
