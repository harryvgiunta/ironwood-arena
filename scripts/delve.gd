extends Node3D
## Host-authoritative controller for "The Sunken Delve".
##
## A chain of ritual chambers that never ends: the party drops through the
## ceiling, touches the altar, wakes the pentagram, survives the summoned wave,
## loots the cache, then either climbs the rope to town or drops through the
## floor into a deeper depth. Odd depths are the sanctuary, even depths the
## ossuary pit; each depth rebuilds the same footprint with a new palette cycle.
## Networking follows the arena: the host simulates every body, clients send
## input and action intents, and snapshots drive the replicas. All run decisions
## travel as a reliable run state so the HUD, the FX and the caches cannot
## drift apart.

const Actor = preload("res://scripts/delve_actor.gd")
const Devil = preload("res://scripts/delve_devil.gd")
const SpeciesVisual = preload("res://scripts/devil_mob_visual.gd")
const RangerClone = preload("res://scripts/ranger_clone.gd")
const LootRules = preload("res://scripts/loot_rules.gd")
const Chest = preload("res://scripts/delve_chest.gd")
const World = preload("res://scripts/delve_world.gd")
const Hud = preload("res://scripts/delve_hud.gd")
const Archer = preload("res://scripts/archer.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Thrown = preload("res://scripts/thrown_weapon.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Combat = preload("res://scripts/combat.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")
const SpellProjectile = preload("res://scripts/spell_projectile.gd")
const BackstabAbility = preload("res://scripts/backstab_ability.gd")
const ShoulderCamera = preload("res://scripts/shoulder_camera.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const PerfOverlay = preload("res://scripts/perf_overlay.gd")
const State = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const Seat = preload("res://scripts/seat_loadout.gd")
const LootPickup = preload("res://scripts/loot_pickup.gd")
const FieldInventoryScript = preload("res://scripts/world_ui.gd")
const NetLimits = preload("res://scripts/net_limits.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const LagCompensation = preload("res://scripts/lag_compensation.gd")
## Delve devils answer the backstab preflight; the players' layer is 4.
const BACKSTAB_MASK := 2
const BACKSTAB_RANGE := 8.0

const INTERACT_RANGE := 4.0
const PICKUP_RADIUS := 1.6
const DROP_FULL_INTERVAL := 2.5
const CHEST_RANGE := 3.5
const CLEAR_DELAY := 2.2
const SNAPSHOT_INTERVAL := 0.05
## The longest rewind the host performs for one client action: half a second.
const MAX_LAG_TICKS := 30
const RUN_STATE_INTERVAL := 0.2
const REGISTER_RETRY := 0.25
const MAX_SHOTS := 128
const AUTO_BEGIN_DELAY := 2.0
const HOOK_KILL_DELAY := 2.0
# Summoning ritual and wave schedule. Odd depths are the sanctuary, even depths
# the ossuary, and each room alternates through a fresh palette cycle.
const RITUAL_SECONDS := 3.2
## Whole-wave budget, every body included: ten enemies on wave one and five more
## every wave after it (10, 15, 20, 25, 30, 35 ...), whatever the room. The court
## devils and the clones are drawn from this budget instead of being stacked on
## top of it, so `wave_total` is exactly the ramp.
const WAVE_FIRST_ENEMIES := 10
const WAVE_STEP := 5
const WAVE1_SECONDS := 30.0
const WAVE2_SECONDS := 40.0
## The crimson clones are the heaviest body in the chamber, so they hold the end
## of the schedule and only enlist from the third wave of the run.
const CLONE_FIRST_WAVE := 3
const CLONE_MAX := 4
## Cycle one's plain ladder keeps the old imps-to-devils ratio (16:10).
const CYCLE_ONE_IMP_SHARE := 0.62
const SPAWN_CURVE := 0.6
## Bodies the wave may add to the room in one frame.
const SPAWN_PER_FRAME := 3
const SPAWN_PLAYER_CLEARANCE := 3.0
const SPAWN_MUTUAL_CLEARANCE := 1.6
const DROP_LAND_Y := 1.5
const DROP_GRACE := 0.3
const RUSH_TIME_SCALE := 8.0
# Cache loot climbs in tiers. The depth picks the tier; run_seed + depth picks
# the exact piece, so every peer agrees without sharing an RNG.
const LOOT_TIERS := [
	["ring_copper","dagger_iron","shield_buckler","focus_tome","neck_bone"],
	["sword_arming","bow_recurve","shield_kite","focus_skull","neck_ember","armor_mail_chest"],
	["bow_long","sword_great","shield_tower","staff_fire","ring_blood","armor_plate_chest"],
	["staff_bone","ring_blood","armor_plate_chest","bow_long","sword_great"],
]

var world
var hud
var audio
var camera: Camera3D
## F8 frame diagnostics (see `perf_overlay.gd`).
var _perf_overlay
var actors: Array = []
var devils: Array = []
var chest
var local_slot := -1
var network_role := "offline"
var phase := "ALTAR"
var depth := 1
var chest_ready := false
var chest_open := false
var rope_lowered := false
var hole_open := false
var wave_total := 0
var wave_number := 1
var spawn_time_scale := 1.0
var run_seed := 0
var server_tick := 0
var last_snapshot_tick := -1
var projectiles: Array[Node3D] = []
var shots_fired := 0
var throws_fired := 0

var _peer_slots: Dictionary = {}
var _snapshot_ticks := PackedInt32Array([-1,-1,-1,-1])
## The server tick this client draws the world at, learned from arrivals.
var _clock = NetReplication.NetClock.new()
## One second of body poses so a client's swing resolves against its view.
var _lag = LagCompensation.new()
var _player_name := "Ranger"
var _endpoint := ""
var _remote_state: Dictionary = {}
var _join_elapsed := 0.0
var _send_elapsed := 0.0
var _carry_client := false
var _register_retry := 0.0
var _run_send_elapsed := 0.0
var _elapsed := 0.0
var _mode_elapsed := 0.0
var _wave_elapsed := 0.0
var _clear_timer := 0.0
var _wave_plan: Array = []
var _wave_cursor := 0
var _wave_clock := 0.0
var _ritual_elapsed := 0.0
var _ritual_progress := 0.0
var _drop_elapsed := 0.0
var _waves_started := 0
var _next_devil_id := 1
var _devil_nodes: Dictionary = {}
var _devil_dead_ids: Dictionary = {}
var _last_devil_tick := -1
var _last_clone_tick := -1
var _auto_start := false
var _kill_wave_hook := false
var _exit_after := 0.0
var _auto_fired := false
var _kill_fired := false
var _camera_yaw := 0.65
var _camera_pitch := 0.08
var _camera_distance := 4.5
var _shoulder_camera := ShoulderCamera.new()
var _cursor_free := true
var _mouse_drawing := false
var _throw_held := false
var _next_swing_side := 0
var _peek_held := false
var _peek_right := Vector3.RIGHT
var _query := PhysicsRayQueryParameters3D.new()
var _aim_origin := Vector3.ZERO
var _aim_origin_valid := false
var loot_pickups: Array = []
var _world_ui
var _player_state
var _drop_query := PhysicsRayQueryParameters3D.new()
var _loot_message_cooldown := 0.0

func _ready() -> void:
	name = "Delve"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world = World.new()
	add_child(world)
	world.set_sealed(false)
	# Warm the imported species before the first wave needs them.
	SpeciesVisual.warm(SpeciesVisual.SCENES.values())
	for index in 4:
		var actor := Actor.new()
		actor.slot = index
		actor.name = "Delver%d" % index
		add_child(actor)
		actor.bounds = float(World.LIMIT) - 0.4
		actor.interp_delay = 0.12
		actor.combat.lag_rewind = _lag
		actor.authoritative = false
		actor.visible = false
		actor.alive = false
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.combat.target_mask = 2
		actor.combat.damage_enabled = false
		actor.fired.connect(_on_fired)
		actor.thrown_weapon.connect(_on_thrown_weapon)
		actor.fell.connect(_on_actor_fell)
		actor.ability.cue.connect(_on_ability_cue.bind(actor))
		actors.append(actor)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 59
	camera.near = 0.08
	camera.far = 150
	add_child(camera)
	camera.position = Vector3(23,24,25)
	camera.look_at(Vector3.ZERO)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	_perf_overlay = PerfOverlay.new()
	layer.add_child(_perf_overlay)
	hud.hub_requested.connect(_hub)
	hud.surface_requested.connect(_on_surface_requested)
	_player_state = get_node_or_null("/root/PlayerState")
	if _player_state != null:
		_world_ui = FieldInventoryScript.new()
		_world_ui.name = "WorldUI"
		_world_ui.layer = layer.layer + 1
		add_child(_world_ui)
		_world_ui.opened.connect(_on_ui_opened)
		_world_ui.closed.connect(_on_ui_closed)
		_world_ui.loadout_changed.connect(_on_ui_loadout_changed)
		_world_ui.configure(_player_state,get_node_or_null("/root/Session"),null,Callable(self,"_drop_world_item"),true)
	audio = Audio.new()
	add_child(audio)
	_query.collision_mask = 1 | 2
	_drop_query.collision_mask = 1
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _connection_ended("Could not join. Check the address, UDP port and host capacity (four delvers)."))
	multiplayer.server_disconnected.connect(func(): _connection_ended("The host disconnected. Host a new delve or join another party."))
	call_deferred("_read_arguments")

func _read_arguments() -> void:
	var pending: Dictionary = {}
	var session_node := get_node_or_null("/root/Session")
	if session_node != null:
		pending = session_node.take()
	var args := OS.get_cmdline_user_args()
	var port := 7777
	var port_set := false
	var player_name := "Ranger"
	var name_set := false
	var address := ""
	var host := false
	var solo := false
	for index in args.size():
		var argument := args[index]
		if argument == "--delve-port" and index+1 < args.size():
			port = args[index+1].to_int()
			port_set = true
		elif argument == "--delve-name" and index+1 < args.size():
			player_name = args[index+1]
			name_set = true
		elif argument == "--delve-join" and index+1 < args.size():
			address = args[index+1]
		elif argument == "--delve-exit-after" and index+1 < args.size():
			_exit_after = args[index+1].to_float()
		elif argument == "--delve-host":
			host = true
		elif argument == "--delve-solo":
			solo = true
		elif argument == "--delve-auto":
			_auto_start = true
		elif argument == "--delve-kill-wave":
			_kill_wave_hook = true
		elif argument == "--delve-rush":
			# Only the spawn clock is compressed; the ritual still plays out.
			spawn_time_scale = RUSH_TIME_SCALE
	var session_port := int(pending.get("port", port))
	var session_name := str(pending.get("name", player_name))
	var final_port := port if port_set else session_port
	var final_name := player_name if name_set else session_name
	if final_name.strip_edges().is_empty():
		final_name = "Ranger"
	# Explicit command-line intent stays authoritative; the hub request fills the gap.
	if host:
		host_game(final_port,final_name,false)
	elif solo:
		host_game(final_port,final_name,true)
	elif not address.is_empty():
		join_game(address,final_port,final_name)
	else:
		match str(pending.get("mode", "")):
			"delve-solo":
				host_game(final_port,final_name,true)
			"delve-host":
				host_game(final_port,final_name,false)
			"delve-join", "delve-client":
				join_game(str(pending.get("address", address)),final_port,final_name)
			"delve-carry-host":
				adopt_host(final_port,final_name)
			"delve-carry-client":
				adopt_client(str(pending.get("address",address)),final_port,final_name)

func host_game(port: int, player_name: String, find_open_port: bool = false) -> void:
	leave_game()
	if port < 1024 or port > 65535:
		hud.set_status("Choose a UDP port between 1024 and 65535.")
		return
	if find_open_port:
		var open_port := _find_open_port(port)
		if open_port <= 0:
			hud.set_status("No free UDP port near %d. Close another host and try again." % port)
			return
		port = open_port
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port,3)
	if error != OK and find_open_port:
		# A solo run must not lose to an existing host on the default port.
		for offset in range(1,16):
			var candidate := port + offset
			if candidate > 65535:
				break
			var retry := ENetMultiplayerPeer.new()
			var retry_error := retry.create_server(candidate,3)
			if retry_error == OK:
				peer = retry
				port = candidate
				error = OK
				break
	if error != OK:
		hud.set_status("Could not host on UDP %d: %s" % [port,error_string(error)])
		return
	multiplayer.multiplayer_peer = peer
	_begin_host(port,player_name)


## Adopt the ENet server the open world was already hosting. The party and the
## bound port survive the scene change; only the simulation scene is rebuilt.
func adopt_host(port: int, player_name: String) -> void:
	var peer := multiplayer.multiplayer_peer
	if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		# The peer is gone (closed elsewhere); open a fresh delve host instead
		# of leaving the faller stranded offline.
		host_game(port,player_name,false)
		return
	_begin_host(port,player_name)
	print("DELVE_HOST_CARRIED port=%d" % port)


func _begin_host(port: int, player_name: String) -> void:
	network_role = "host"
	local_slot = 0
	# Clients already connected by the open world send `_register`; they are
	# seated from that message because `peer_connected` fired before this scene.
	_peer_slots.clear()
	_peer_slots[1] = 0
	_player_name = _safe_name(player_name)
	run_seed = randi()
	# A re-host in the same scene may follow an ossuary run; start the rebuild
	# on the sanctuary so depth one always has its altar.
	world.apply_room(World.ROOM_SANCTUARY,1)
	_on_devils_reset_local()
	for actor in actors:
		actor.authoritative = true
		actor.is_local = false
		actor.visible = false
		actor.alive = false
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.combat.target_mask = 2
		actor.combat.damage_enabled = false
	var local = actors[0]
	local.configure(1,false,_player_name,world.drop_center)
	local.visible = true
	local.is_local = true
	local.collision_layer = 4
	local.collision_mask = 1
	local.combat.target_mask = 2
	local.combat.damage_enabled = true
	_camera_yaw = atan2(local.global_position.x,local.global_position.z)
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
			addresses.append(address)
	_endpoint = "UDP %d / LAN %s / same PC 127.0.0.1" % [port,", ".join(addresses)]
	hud.configure(_endpoint)
	hud.set_status("Touch the altar to begin the descent.",2.5)
	_set_cursor_free(false)
	_remember_network(_player_name,"",port)
	_apply_loadout(0,_local_loadout())
	_bind_ui_rig()
	_mode_elapsed = 0.0
	_auto_fired = false
	_drop_party()
	_set_phase("ALTAR")
	hud.show_banner("DEPTH %d" % depth,2.0)
	_sync_run_state()
	print("DELVE_HOST_READY port=%d" % port)

func join_game(address: String, port: int, player_name: String) -> void:
	leave_game()
	if address.strip_edges().is_empty() or port < 1024 or port > 65535:
		hud.set_status("Enter a host address and a UDP port between 1024 and 65535.")
		return
	_player_name = _safe_name(player_name)
	_endpoint = "%s:%d" % [address.strip_edges(),port]
	_remember_network(_player_name,address.strip_edges(),port)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(),port)
	if error != OK:
		hud.set_status("Could not start connection: " + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	network_role = "client"
	_join_elapsed = 0.0
	hud.configure(_endpoint)
	hud.set_status("Connecting to " + _endpoint + "...")
	print("DELVE_JOIN_ATTEMPT %s:%d" % [address.strip_edges(),port])


## Adopt the live ENet client the open world already had. The connection to the
## host stays up; registration is retried until the host's delve scene answers,
## because `connected_to_server` fired before this scene existed.
func adopt_client(address: String, port: int, player_name: String) -> void:
	var peer := multiplayer.multiplayer_peer
	if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		# The peer is gone (closed elsewhere): fall back to a normal join.
		join_game(address,port,player_name)
		return
	_player_name = _safe_name(player_name)
	_endpoint = "%s:%d" % [address.strip_edges(),port]
	_remember_network(_player_name,address.strip_edges(),port)
	network_role = "client"
	local_slot = -1
	_carry_client = true
	_join_elapsed = 0.0
	_register_retry = REGISTER_RETRY
	peer.get_peer(1).set_timeout(32,2000,5000)
	hud.configure(_endpoint)
	hud.set_status("Following the party into the delve...")
	print("DELVE_CLIENT_CARRIED %s:%d" % [address.strip_edges(),port])

func leave_game() -> void:
	# A server-disconnected signal can arrive while the scene is being freed;
	# there is no MultiplayerAPI left to close at that point.
	if not is_inside_tree() or multiplayer == null:
		return
	network_role = "offline"
	local_slot = -1
	if _world_ui != null:
		if _world_ui.is_open():
			_world_ui.close()
		_world_ui.rebind(null)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer_slots.clear()
	_remote_state.clear()
	_snapshot_ticks.fill(-1)
	last_snapshot_tick = -1
	_last_devil_tick = -1
	server_tick = 0
	_send_elapsed = 0.0
	_run_send_elapsed = 0.0
	_join_elapsed = 0.0
	_carry_client = false
	_register_retry = 0.0
	_mode_elapsed = 0.0
	_elapsed = 0.0
	_wave_elapsed = 0.0
	_clear_timer = 0.0
	_wave_plan.clear()
	_wave_cursor = 0
	_wave_clock = 0.0
	_ritual_elapsed = 0.0
	_ritual_progress = 0.0
	_drop_elapsed = 0.0
	_waves_started = 0
	_auto_fired = false
	_kill_fired = false
	_next_devil_id = 1
	shots_fired = 0
	throws_fired = 0
	_mouse_drawing = false
	_throw_held = false
	_peek_held = false
	_next_swing_side = 0
	_peek_right = Vector3.RIGHT
	_cursor_free = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	phase = "ALTAR"
	depth = 1
	wave_total = 0
	wave_number = 1
	chest_ready = false
	chest_open = false
	rope_lowered = false
	hole_open = false
	_clear_devils()
	_remove_chest()
	_on_devils_reset_local()
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	projectiles.clear()
	for entry in loot_pickups:
		var pickup = entry.get("node")
		if is_instance_valid(pickup):
			pickup.queue_free()
	loot_pickups.clear()
	for actor in actors:
		actor.combat.stop()
		actor.reset_stance()
		actor.authoritative = false
		actor.is_local = false
		actor.combat.damage_enabled = false
		actor.visible = false
		actor.alive = false
		actor.collision_layer = 0
		actor.collision_mask = 0
	if world != null:
		world.set_sealed(false)
		world.set_rope_lowered(false)
		world.set_hole_open(false)
		_apply_world_ritual(false,0.0)
		world.set_beacons(false,false,false)

func _connection_ended(message: String) -> void:
	if not is_inside_tree():
		return
	leave_game()
	hud.show_connection_lost(message)
	print("DELVE_CONNECTION_ENDED %s" % message)

func _hub() -> void:
	leave_game()
	get_tree().change_scene_to_file("res://main.tscn")

func _on_surface_requested() -> void:
	if network_role == "host" and phase == "CLEARED":
		ascend_to_surface()
		return
	leave_game()
	get_tree().change_scene_to_file("res://main.tscn")

func _find_open_port(start: int) -> int:
	var last := mini(start+15,65535)
	for candidate in range(start,last+1):
		var probe := PacketPeerUDP.new()
		var error := probe.bind(candidate)
		probe.close()
		if error == OK:
			return candidate
	return 0

## The peer whose RPC is in flight, or -1 once this node has left the tree: a
## scene hand-off can deliver one last intent to a session that is already gone.
func _sender_id() -> int:
	var api := multiplayer
	if api == null:
		return -1
	return api.get_remote_sender_id()


func _safe_name(value: String) -> String:
	var result := value.strip_edges().replace("\n"," ").replace("\r"," ").replace("\t"," ").left(16)
	return "Ranger" if result.is_empty() else result

func _remember_network(player_name: String, address: String, port: int) -> void:
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cache.remember(player_name,address,port,"delve")

func _local_loadout() -> Dictionary:
	var node: Variant = get_node_or_null("/root/PlayerState")
	if node == null:
		return {}
	return {
		"main":str(node.main_item()),
		"off":str(node.off_item()),
		"bow":int(node.equipped_index("bow")),
		"sword":int(node.equipped_index("sword")),
		"armor":ArmorData.pack(node.equipped_pieces()),
		"trinkets":node.trinkets(),
	}

func _catalog_hand(value: Variant, slot: String) -> String:
	# Seat loadouts come off the wire: only real gear legal for that hand.
	if typeof(value) != TYPE_STRING:
		return ""
	var id := str(value)
	var item: Dictionary = State.ITEMS.get(id,{})
	if item.is_empty() or not Rules.allowed(item,slot):
		return ""
	return id

func _apply_loadout(slot: int, loadout: Dictionary) -> void:
	if slot < 0 or slot >= actors.size() or loadout.is_empty():
		return
	var actor = actors[slot]
	var bow: Variant = loadout.get("bow")
	var sword: Variant = loadout.get("sword")
	var armor: Variant = loadout.get("armor")
	var bow_ok := typeof(bow) == TYPE_INT and int(bow) >= 0 and int(bow) <= 2
	var sword_ok := typeof(sword) == TYPE_INT and int(sword) >= 0 and int(sword) <= 2
	var armor_ok := typeof(armor) == TYPE_INT and int(armor) >= 0 and int(armor) <= ArmorData.PIECE_MASK
	var main_raw: Variant = loadout.get("main")
	var off_raw: Variant = loadout.get("off")
	var main := _catalog_hand(main_raw,"main")
	var off := _catalog_hand(off_raw,"off")
	var hands_present := loadout.has("main") or loadout.has("off")
	var main_ok := not loadout.has("main") or (typeof(main_raw) == TYPE_STRING and (str(main_raw).is_empty() or not main.is_empty()))
	var off_ok := not loadout.has("off") or (typeof(off_raw) == TYPE_STRING and (str(off_raw).is_empty() or not off.is_empty()))
	if hands_present and main_ok and off_ok:
		# Hub kits carry the whole paperdoll; the state script derives the
		# weapon mode, staff, focus, shield and off-hand from the validated ids.
		# Explicitly empty hands are deliberate (unarmed); a malformed non-empty
		# hand falls through instead of wiping a valid seat.
		var pieces: Dictionary = ArmorData.unpack(int(armor) & ArmorData.PIECE_MASK) if armor_ok else actor.rig.armor_pieces.duplicate()
		var worn := Seat.trinkets(loadout.get("trinkets"))
		worn["off"] = off
		actor.rig.apply_loadout(State.build_loadout(main,off,pieces,worn))
		return
	if bow_ok:
		actor.rig.set_bow(int(bow))
	if sword_ok:
		actor.rig.set_sword(int(sword))
	if armor_ok:
		actor.rig.set_armor_bits(int(armor))

func get_human_count() -> int:
	if network_role == "offline":
		return 0
	var count := 0
	for actor in actors:
		if actor.peer_id > 0:
			count += 1
	return count

func _peer_connected(peer_id: int) -> void:
	if network_role != "host" or _peer_slots.has(peer_id):
		return
	_seat_peer(peer_id,"Ranger")


func _seat_peer(peer_id: int, player_name: String) -> void:
	var connection = multiplayer.multiplayer_peer.get_peer(peer_id)
	if connection != null:
		connection.set_timeout(32,2000,5000)
	var slot := _lowest_free_slot()
	if slot < 0:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	_peer_slots[peer_id] = slot
	var actor = actors[slot]
	actor.authoritative = true
	actor.configure(peer_id,false,_safe_name(player_name),_join_spawn(slot))
	actor.visible = true
	actor.is_local = false
	actor.collision_layer = 4
	actor.collision_mask = 1
	actor.combat.target_mask = 2
	actor.combat.damage_enabled = true
	_accept.rpc_id(peer_id,slot)
	_run_state.rpc_id(peer_id,_run_state_dict())
	_broadcast_names()
	print("DELVE_PEER_JOINED slot=%d humans=%d" % [slot,get_human_count()])

func _peer_disconnected(peer_id: int) -> void:
	if network_role != "host" or not _peer_slots.has(peer_id):
		return
	var slot: int = _peer_slots[peer_id]
	_peer_slots.erase(peer_id)
	_deactivate_slot(slot)
	_slot_cleared.rpc(slot)
	_broadcast_names()
	print("DELVE_PEER_LEFT slot=%d humans=%d" % [slot,get_human_count()])
	_check_party_wipe()

func _lowest_free_slot() -> int:
	for slot in range(1,actors.size()):
		if not _peer_slots.values().has(slot):
			return slot
	return -1

func _join_spawn(slot: int) -> Vector3:
	if phase == "CLEARED":
		return world.chest_position + Vector3(2.0 + float(slot)*0.6, 0.0, 2.0)
	var angle := TAU * float(slot) / 4.0
	return world.drop_center + Vector3(cos(angle)*2.4,0.0,sin(angle)*2.4)

func _deactivate_slot(slot: int) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var actor = actors[slot]
	_clear_slot_arrows(slot)
	actor.combat.stop()
	actor.authoritative = false
	actor.is_local = false
	actor.visible = false
	actor.alive = false
	actor.peer_id = 0
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.combat.damage_enabled = false

func _clear_slot_arrows(slot: int) -> void:
	for index in range(projectiles.size()-1,-1,-1):
		var projectile = projectiles[index]
		if not is_instance_valid(projectile):
			projectiles.remove_at(index)
		elif projectile.source_id == slot:
			projectile.queue_free()
			projectiles.remove_at(index)
	_clear_remote_arrows.rpc(slot)

@rpc("authority","call_remote","reliable")
func _clear_remote_arrows(slot: int) -> void:
	for projectile in projectiles:
		if is_instance_valid(projectile) and projectile.source_id == slot:
			projectile.queue_free()

@rpc("authority","call_remote","reliable")
func _slot_cleared(slot: int) -> void:
	if network_role != "client" or slot < 0 or slot >= actors.size():
		return
	actors[slot].visible = false
	actors[slot].alive = false
	actors[slot].collision_layer = 0
	actors[slot].collision_mask = 0

## Fighter names are static for a run, so they ride one reliable roster
## message on join/leave instead of every 20 Hz fighter datagram.
func _name_list() -> Array:
	var names: Array = []
	for actor in actors:
		names.append(actor.display_name)
	return names

func _broadcast_names() -> void:
	if network_role == "host":
		_names.rpc(_name_list())

@rpc("authority","call_remote","reliable")
func _names(names: Array) -> void:
	if network_role != "client":
		return
	for index in mini(names.size(),actors.size()):
		actors[index].display_name = str(names[index])

func _connected() -> void:
	if network_role != "client":
		return
	multiplayer.multiplayer_peer.get_peer(1).set_timeout(32,2000,5000)
	_register.rpc_id(1,_player_name,_local_loadout())

@rpc("any_peer","call_remote","reliable")
func _register(player_name: String, loadout: Dictionary) -> void:
	if network_role != "host":
		return
	var sender := _sender_id()
	if sender <= 1:
		return
	if not _peer_slots.has(sender):
		# A party carried in from the open world was already connected when
		# this scene loaded, so `peer_connected` never fired for it.
		_seat_peer(sender,_safe_name(player_name))
	if _peer_slots.has(sender):
		var slot := int(_peer_slots[sender])
		actors[slot].display_name = _safe_name(player_name)
		_apply_loadout(slot,loadout)
		_broadcast_names()

@rpc("authority","call_remote","reliable")
func _accept(slot: int) -> void:
	if network_role != "client" or slot < 1 or slot > 3:
		return
	local_slot = slot
	_carry_client = false
	_next_swing_side = 0
	var join_point := _join_spawn(slot)
	_camera_yaw = atan2(join_point.x,join_point.z)
	for actor in actors:
		actor.authoritative = false
		actor.is_local = actor.slot == slot
		actor.predicting = actor.slot == slot
		actor.combat.damage_enabled = false
		actor.combat.target_mask = 2
		if actor.slot != slot:
			actor.visible = false
	actors[slot].visible = true
	actors[slot].interp_delay = 0.05
	_clock.configure(60.0,actors[(slot+1)%4].interp_delay)
	hud.configure(_endpoint)
	_bind_ui_rig()
	_set_cursor_free(false)
	print("DELVE_CLIENT_READY slot=%d" % slot)

func _physics_process(delta: float) -> void:
	if network_role == "offline":
		return
	if network_role == "client" and local_slot < 0:
		_join_elapsed += delta
		if _carry_client:
			_register_retry -= delta
			if _register_retry <= 0.0:
				_register_retry = REGISTER_RETRY
				_register.rpc_id(1,_player_name,_local_loadout())
		if _join_elapsed > 6.0:
			_connection_ended("Connection timed out. The host may be offline, full, or blocked by a firewall.")
		return
	_collect_loot(delta)
	_send_elapsed += delta
	if local_slot >= 0:
		var x := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		var z := float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))
		var motion := Vector2(x,z).limit_length()
		if _cursor_free:
			motion = Vector2.ZERO
		var right := Vector2(cos(_camera_yaw),-sin(_camera_yaw))
		var back := Vector2(sin(_camera_yaw),cos(_camera_yaw))
		var direction := right*motion.x + back*motion.y
		var running := Input.is_physical_key_pressed(KEY_SHIFT)
		var aim := _crosshair_aim()
		var aim_origin: Variant = _aim_origin if _aim_origin_valid else null
		if network_role == "host":
			_set_movement(local_slot,direction,running,aim,-1,aim_origin)
		elif network_role == "client":
			# Prediction: this peer integrates the frame it is about to send.
			_clock.advance(delta)
			var local = actors[local_slot]
			var view := _view_tick()
			local.update_input(direction,running,view)
			local.predicted_step(delta,actors)
			_move_input.rpc_id(1,direction,running,aim,_snapshot_ticks[local_slot],aim_origin,
				local.latest_prediction_seq(),view,local.input_history())
	if network_role == "host":
		server_tick += 1
		for actor in actors:
			if actor.peer_id > 0:
				actor.combat.lag_tick = server_tick
				actor.step(delta,actors,server_tick)
		if phase == "WAVE":
			var live := _live_devils()
			for devil in devils.duplicate():
				if is_instance_valid(devil) and devil.alive:
					devil.step(delta,actors,live)
		_advance_host_state(delta)
		_check_hole_descent()
		_check_party_wipe()
		_lag.record(server_tick,_lag_bodies())
		if _send_elapsed >= SNAPSHOT_INTERVAL:
			for actor in actors:
				if actor.peer_id > 0:
					_receive_snapshot.rpc(server_tick,actor.slot,actor.snapshot())
					_snapshot_ticks[actor.slot] = server_tick
			var states: Array = []
			var clone_states: Array = []
			for devil in devils:
				if not is_instance_valid(devil):
					continue
				var clone_kind = devil.get("kind")
				if clone_kind != null and int(clone_kind) == RangerClone.KIND:
					clone_states.append(devil.snapshot())
				else:
					states.append(devil.snapshot())
			if not states.is_empty():
				# A full wave encodes to several kilobytes; split it into
				# datagrams that stay inside the clamped payload.
				for batch in NetLimits.batches(states,[server_tick]):
					_devil_snapshots.rpc(server_tick,batch)
			if not clone_states.is_empty():
				for batch in NetLimits.batches(clone_states,[server_tick]):
					_clone_snapshots.rpc(server_tick,batch)
		_run_send_elapsed += delta
		if _run_send_elapsed >= RUN_STATE_INTERVAL:
			_run_send_elapsed = fmod(_run_send_elapsed,RUN_STATE_INTERVAL)
			_sync_run_state()
	if _send_elapsed >= SNAPSHOT_INTERVAL:
		_send_elapsed = fmod(_send_elapsed,SNAPSHOT_INTERVAL)

func _set_movement(slot: int, direction: Vector2, running: bool, aim: Variant = null, aim_tick: int = -1, aim_origin: Variant = null, seq: int = -1, view: int = -1, history: Array = []) -> void:
	if slot < 0 or slot >= actors.size():
		return
	if not direction.is_finite():
		return
	if aim != null and not _set_aim(slot,aim,aim_tick,aim_origin):
		return
	actors[slot].accept_network_input(direction,running,seq,view,history)

func _set_aim(slot: int, point: Vector3, aim_tick: int = -1, aim_origin: Variant = null) -> bool:
	if not point.is_finite() or point.length_squared() > 1000000.0:
		return false
	var actor = actors[slot]
	if actor.peer_id > 1:
		if aim_tick < 0 or aim_tick > _snapshot_ticks[slot]:
			return false
		# Reliable draw/release may arrive after a newer movement aim. Honor
		# the action without rewinding its aim or exposure acknowledgement.
		if aim_tick < actor.aim_snapshot_tick:
			return true
		actor.aim_snapshot_tick = aim_tick
	actor.update_cover_aim_readiness()
	actor.combat.set_aim(point)
	if typeof(aim_origin) == TYPE_VECTOR3:
		var origin: Vector3 = aim_origin
		var ray: Vector3 = point-origin
		if origin.is_finite() and origin.distance_squared_to(actor.global_position) <= 144.0 \
				and ray.is_finite() and ray.length_squared() > 0.01:
			actor.combat.set_camera_ray(origin,ray)
		else:
			actor.combat.clear_camera_ray()
	else:
		actor.combat.clear_camera_ray()
	if actor.combat.blocking:
		var facing: Vector3 = point - actor.global_position
		facing.y = 0.0
		if facing.length_squared() > 0.000001:
			actor.combat.face_block(facing)
	return true

@rpc("any_peer","call_remote","unreliable_ordered")
func _move_input(direction: Vector2, running: bool, aim: Variant, aim_tick: Variant, aim_origin: Variant = null, seq: Variant = -1, view: Variant = -1, history: Array = []) -> void:
	if network_role != "host":
		return
	var sender := _sender_id()
	if not _peer_slots.has(sender):
		return
	var aim_point: Variant = aim if typeof(aim) == TYPE_VECTOR3 and typeof(aim_tick) == TYPE_INT else null
	_set_movement(int(_peer_slots[sender]),direction,running,aim_point,
		int(aim_tick) if typeof(aim_tick) == TYPE_INT else -1,aim_origin,
		int(seq) if typeof(seq) == TYPE_INT else -1,int(view) if typeof(view) == TYPE_INT else -1,
		history if typeof(history) == TYPE_ARRAY else [])

@rpc("authority","call_remote","unreliable")
func _receive_snapshot(tick: int, slot: int, state: Dictionary) -> void:
	if network_role != "client" or slot < 0 or slot >= actors.size() or tick <= _snapshot_ticks[slot]:
		return
	_snapshot_ticks[slot] = tick
	last_snapshot_tick = maxi(last_snapshot_tick,tick)
	if slot == local_slot:
		_clock.ingest(tick,Time.get_ticks_msec()/1000.0)
	var previous_ability := str(actors[slot].ability.active_id)
	actors[slot].apply_snapshot(state,tick,actors)
	var current_ability := str(actors[slot].ability.active_id)
	if actors[slot].ability.active and current_ability != previous_ability:
		var definition := AbilityRules.by_id(current_ability)
		var sound := str(definition.get("sound",""))
		if not sound.is_empty():
			audio.play_sound(sound)

func send_action(action: String, value: Variant = null) -> void:
	if local_slot < 0:
		return
	if action == "interact":
		if network_role == "host":
			_host_interact(local_slot)
		elif network_role == "client":
			_action_input.rpc_id(1,action,null,_snapshot_ticks[local_slot],null)
		return
	if action in ["bow","sword","weapon","armor","shield","loadout"]:
		_cancel_draw_input()
	if action in ["draw","throw"] and not _peek_held and actors[local_slot].rig.phase == "READY":
		_capture_peek_context()
	if action in ["draw","release","throw","throw_release"]:
		_send_peek_input()
	var aim_origin: Variant = _aim_origin if _aim_origin_valid and action in ["draw","release","throw","throw_release","melee"] else null
	if network_role == "host":
		_apply_action(local_slot,action,value,-1,aim_origin)
	elif network_role == "client":
		# Locomotion intents start on this frame; combat and skills stay
		# authoritative so a client never guesses its own hit.
		actors[local_slot].predict_action(action,value)
		_action_input.rpc_id(1,action,value,_snapshot_ticks[local_slot],aim_origin)

@rpc("any_peer","call_remote","reliable")
func _action_input(action: String, value: Variant, aim_tick: Variant, aim_origin: Variant = null) -> void:
	if network_role != "host":
		return
	var sender := _sender_id()
	if not _peer_slots.has(sender):
		return
	var slot := int(_peer_slots[sender])
	if action == "interact":
		# Interaction is a world-position check; it needs no aim rewind.
		_apply_action(slot,action,null)
		return
	if action == "loadout":
		# Kit changes are seat state, not aim; no snapshot rewind needed.
		if typeof(value) == TYPE_DICTIONARY:
			_apply_loadout(slot,value)
		return
	if typeof(aim_tick) != TYPE_INT:
		return
	if aim_tick < 0 or aim_tick > _snapshot_ticks[slot]:
		return
	_apply_action(slot,action,value,aim_tick,aim_origin)

func _apply_action(slot: int, action: String, value: Variant, aim_tick: int = -1, aim_origin: Variant = null) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var actor = actors[slot]
	if action == "loadout":
		# Same validated seat loader as the join handshake; unknown fields die here.
		if typeof(value) == TYPE_DICTIONARY:
			_apply_loadout(slot,value)
		return
	if not actor.alive:
		return
	# Every damage-capable intent carries the tick its owner was drawing.
	_arm_lag(actor)
	match action:
		"draw":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.begin_draw()
		"melee":
			if typeof(value) != TYPE_DICTIONARY:
				return
			var aim = value.get("aim")
			var hand := str(value.get("hand","right"))
			var variant := str(value.get("variant","overhead"))
			if typeof(aim) != TYPE_VECTOR3 or hand not in ["left","right"] \
					or variant not in ["overhead","diagonal_left","diagonal_right","stab"]:
				return
			if _set_aim(slot,aim,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				if actor.combat.begin_melee(hand,variant) and slot == local_slot and actor.rig.weapon != "dual":
					if variant == "diagonal_right":
						_next_swing_side = -1
					elif variant == "diagonal_left":
						_next_swing_side = 1
		"step":
			if typeof(value) != TYPE_VECTOR3:
				return
			var direction: Vector3 = value
			if not direction.is_finite() or absf(direction.y) > 0.01:
				return
			var flat := Vector3(direction.x,0,direction.z)
			if absf(flat.length()-1.0) > 0.1:
				return
			actor.try_step(flat)
		"release":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.release_draw()
		"throw":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.begin_throw()
		"throw_release":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.release_throw()
		"stop": actor.combat.stop()
		"jump":
			if typeof(value) == TYPE_BOOL:
				actor.press_jump(value)
		"cover":
			if typeof(value) == TYPE_VECTOR3 and value.is_finite() and value.length_squared() > 0.01 and value.length_squared() <= 1000000.0:
				actor.toggle_cover(value.normalized())
		"crouch":
			if typeof(value) == TYPE_BOOL:
				actor.set_crouch(value)
		"block":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("pressed")) != TYPE_BOOL or typeof(value.get("forward")) != TYPE_VECTOR3:
				return
			var forward: Vector3 = value.forward
			if not forward.is_finite() or (value.pressed and forward.length_squared() < 0.25):
				return
			actor.set_block(value.pressed,Vector3(forward.x,0,forward.z))
		"peek":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("pressed")) != TYPE_BOOL or typeof(value.get("right")) != TYPE_VECTOR3 or typeof(value.get("side")) != TYPE_INT:
				return
			var right: Vector3 = value.right
			if not right.is_finite() or absf(right.y) > 0.01 or absf(right.length_squared()-1.0) > 0.01 or value.side not in [-1,1]:
				return
			actor.peek_requested = value.pressed
			actor.peek_view_right = Vector3(right.x,0,right.z).normalized()
			actor.peek_shoulder = value.side
			actor.update_combat_cover_side()
		"bow":
			if typeof(value) == TYPE_INT and value >= 0 and value < 3:
				actor.rig.set_bow(value)
		"sword":
			if typeof(value) == TYPE_INT and value >= 0 and value < 3:
				actor.rig.set_sword(value)
		"weapon":
			if typeof(value) == TYPE_STRING and value in ["bow","sword","dagger","dual"]:
				var requested := str(value)
				if requested == "dual":
					if actor.rig.weapon == "dual":
						requested = "sword"
					elif actor.rig.sword_index == 2:
						return
				actor.combat.stop()
				actor.rig.set_weapon(requested)
		"shield":
			if typeof(value) == TYPE_BOOL:
				actor.combat.stop()
				actor.rig.set_shield(value)
		"consume":
			if typeof(value) == TYPE_STRING and value in ["bandage","potion"]:
				actor.try_consume(value)
		"ability":
			if typeof(value) != TYPE_INT or int(value) < 0 or int(value) >= AbilityRules.SLOT_COUNT:
				return
			var seat_definition: Dictionary = actor.ability.definition(int(value))
			if not actor.ability.active and actor.alive and not seat_definition.is_empty():
				# A backstab needs a body under the fighter's aim: refuse before
				# the runner spends stamina or starts its clock.
				var refusal: String = _prepare_backstab(actor, seat_definition)
				if not refusal.is_empty():
					if int(slot) == local_slot:
						hud.set_status(refusal,1.6)
					return
			var outcome: Dictionary = actor.try_ability(int(value))
			if bool(outcome.get("ok",false)):
				var definition: Dictionary = outcome.get("definition",{})
				var sound := str(definition.get("sound",""))
				if not sound.is_empty():
					audio.play_sound(sound)
		"armor":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("slot")) != TYPE_STRING or typeof(value.get("set")) != TYPE_INT:
				return
			var armor_slot := str(value.slot)
			var armor_set := int(value.set)
			if armor_slot in ArmorData.SLOTS and armor_set >= 0 and armor_set < ArmorData.SET_IDS.size():
				actor.rig.set_armor_piece(armor_slot,armor_set)
		"interact":
			_host_interact(slot)

func _on_fired(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	if network_role != "host":
		return
	var damage := Combat.damage_for(actors[slot].rig.bow_index,charge,
		actors[slot].rig.ranged_scale())
	var visual_origin: Vector3 = actors[slot].rig.last_arrow_visual_origin
	_spawn_arrow(slot,origin,direction,speed,damage,true,visual_origin)
	_arrow_event.rpc(slot,origin,direction,speed,visual_origin)
	shots_fired += 1

func _spawn_arrow(slot: int, origin: Vector3, direction: Vector3, speed: float, damage: float, authoritative: bool, visual_origin: Vector3 = Vector3.INF, pierce_count: int = 0) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var arrow := Arrow.new()
	arrow.source_id = slot
	# Layer 8 is the shield: an enemy clone or a party member's raised shield
	# takes the shaft before the body behind it.
	arrow.hit_mask = 1 | 2 | 8
	arrow.authoritative_damage = authoritative
	if authoritative:
		arrow.lag_comp = _lag
		arrow.lag_ticks = _shooter_lag(slot)
	add_child(arrow)
	var excluded: Array[RID] = [actors[slot].get_rid()]
	if is_instance_valid(actors[slot].rig.active_shield):
		excluded.append(actors[slot].rig.active_shield.get_rid())
	arrow.launch(origin,direction,speed,damage,excluded,visual_origin,pierce_count)
	for index in range(projectiles.size()-1,-1,-1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(arrow)
	if projectiles.size() > MAX_SHOTS:
		var oldest = projectiles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	if slot == local_slot:
		audio.play_sound("release")

## The bodies a client's action may hit: the party and every live devil.
func _lag_bodies() -> Array:
	var bodies: Array = []
	for actor in actors:
		bodies.append(actor)
	for devil in devils:
		if is_instance_valid(devil):
			bodies.append(devil)
	return bodies


## The server tick this peer is currently drawing; its aim and swings are judged
## against that world, not the present one.
func _view_tick() -> int:
	if _clock.newest_tick() >= 0:
		return _clock.render_tick()
	return maxi(0,_snapshot_ticks[local_slot])


## Arms one fighter's damage window with the rewind its owner needs.
func _arm_lag(actor) -> void:
	actor.combat.lag_tick = server_tick
	actor.combat.lag_ticks = int(actor.lag_ticks(server_tick,MAX_LAG_TICKS)) if int(actor.peer_id) > 1 else 0


## How many ticks behind the host the shooter was drawing when it released.
func _shooter_lag(slot: int) -> int:
	if slot < 0 or slot >= actors.size():
		return 0
	var actor = actors[slot]
	if int(actor.peer_id) <= 1:
		return 0
	return int(actor.lag_ticks(server_tick,MAX_LAG_TICKS))


func _ability_authority(actor) -> bool:
	return network_role != "client" and actor != null and is_instance_valid(actor) \
		and bool(actor.authoritative)


func _on_ability_cue(id: String, cue: String, index: int, actor) -> void:
	if not is_instance_valid(actor):
		return
	var runner = actor.ability
	if not runner.active or str(runner.active_id) != id:
		return
	var definition: Dictionary = runner.active_definition
	if definition.is_empty():
		return
	var effect: Dictionary = definition.get("effect", {})
	var authoritative := _ability_authority(actor)
	var damage: float = AbilityRules.damage_for(definition, actor.rig)
	match str(effect.get("kind", "")):
		"barrage", "volley", "piercing_shot":
			_delve_ability_shots(actor, definition, index, damage, authoritative)
		"projectile":
			_delve_ability_spell(actor, definition, damage, authoritative)
		"backstab":
			_delve_ability_backstab(actor, cue, damage, authoritative)
		"melee_arc", "melee_ring":
			_delve_ability_melee(actor, definition, cue, index, damage, authoritative)


func _delve_ability_shots(actor, definition: Dictionary, index: int,
		damage: float, authoritative: bool) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var kind := str(effect.get("kind", ""))
	var rig = actor.rig
	var aim: Vector3 = actor.combat.aim_point
	# The cue lands before the rig's own pose step, so aim and resample the bow
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
		_spawn_arrow(int(actor.slot), origin, direction, speed, damage, authoritative, origin, pierce)


func _delve_ability_spell(actor, definition: Dictionary, damage: float,
		authoritative: bool) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = actor.rig
	var origin: Vector3 = rig.cast_origin()
	var aim: Vector3 = actor.combat.aim_point
	var direction := aim - origin
	if direction.length_squared() < 0.0001:
		direction = -rig.global_basis.z
	var spell := SpellProjectile.new()
	spell.kind = str(effect.get("projectile", "fireball"))
	spell.hit_mask = 1 | 2 | 8
	add_child(spell)
	var excluded: Array[RID] = [actor.get_rid()]
	if is_instance_valid(rig.active_shield):
		excluded.append(rig.active_shield.get_rid())
	spell.launch(origin, direction, float(effect.get("speed", 22.0)), damage,
		excluded, spell.hit_mask, authoritative, rig.global_position,
		float(effect.get("radius", 0.0)), int(effect.get("pierce", 0)))
	spell.source_rig = rig
	spell.set_meta("stagger", float(effect.get("stagger", 0.0)))
	if authoritative:
		spell.detonated.connect(_on_ability_spell_detonated.bind(spell, actor.combat))


func _on_ability_spell_detonated(centre: Vector3, _direction: Vector3, spell, combat_ref) -> void:
	if not is_instance_valid(spell) or not is_instance_valid(combat_ref):
		return
	if spell.blast_radius <= 0.0:
		return
	combat_ref.ability_blast(centre, spell.blast_radius, spell.damage,
		float(spell.get_meta("stagger", 0.0)))


func _delve_ability_melee(actor, definition: Dictionary, cue: String, index: int,
		damage: float, authoritative: bool) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = actor.rig
	var id := str(definition.get("id", ""))
	var radius := float(effect.get("radius", 1.7))
	var arc := float(effect.get("arc_degrees", 360.0))
	var ring := str(effect.get("kind", "")) == "melee_ring" or arc >= 359.0
	var forward: Vector3 = actor.combat.aim_point - rig.global_position
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
			victims = actor.ability.active_victims
		actor.combat.ability_strike(radius, arc, damage,
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


## A backstab needs a live body under the fighter's aim. The resolved body
## rides on the seat so the blink and stab cues agree with the preflight.
func _prepare_backstab(actor, definition: Dictionary) -> String:
	if str(definition.get("effect", {}).get("kind", "")) != "backstab":
		return ""
	var target: Node3D = _backstab_target(actor)
	if target == null:
		actor.remove_meta("backstab_target")
		return "No backstab target."
	actor.set_meta("backstab_target",target)
	return ""


func _backstab_target(actor) -> Node3D:
	var exclude: Array[RID] = []
	exclude.append(actor.get_rid())
	return BackstabAbility.find_target(get_world_3d().direct_space_state,
		actor.global_position,actor.combat.aim_point,BACKSTAB_MASK,BACKSTAB_RANGE,exclude)


## The blink cue smokes the old spot and, on the authority only, teleports
## behind the preflight target; the stab cue spends the dagger damage on the
## body the caster is now behind.
func _delve_ability_backstab(actor, cue: String, damage: float, authoritative: bool) -> void:
	var rig = actor.rig
	var target: Node3D = null
	if actor.has_meta("backstab_target"):
		var resolved = actor.get_meta("backstab_target")
		if is_instance_valid(resolved) and resolved is Node3D:
			target = resolved
	var forward: Vector3 = actor.combat.aim_point - rig.global_position
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
		BackstabAbility.blink(actor, spot.position, float(spot.yaw))
		AbilityFx.smoke_puff(self, rig.global_position, 1.0, true)
		return
	if cue != "stab":
		return
	if target == null:
		target = _backstab_target(actor)
	if target != null and authoritative and target.get("alive") != false:
		BackstabAbility.strike(actor, target, damage, int(actor.slot))
	if target != null:
		AbilityFx.backstab_flash(self, target.global_position - forward * 0.35 + Vector3.UP * 1.15, forward)


@rpc("authority","call_remote","reliable")
func _arrow_event(slot: int, origin: Vector3, direction: Vector3, speed: float, visual_origin: Variant = null) -> void:
	if network_role == "client" and slot >= 0 and slot < actors.size():
		var start: Vector3 = visual_origin if typeof(visual_origin) == TYPE_VECTOR3 else Vector3.INF
		_spawn_arrow(slot,origin,direction,speed,0.0,false,start)
		shots_fired += 1

func _on_thrown_weapon(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float, weapon_name: String, weapon_index: int) -> void:
	if network_role != "host":
		return
	var damage := Combat.throw_damage(weapon_name,weapon_index,charge,
		actors[slot].rig.throw_scale())
	_spawn_thrown(slot,origin,direction,speed,weapon_name,weapon_index,damage,true)
	_throw_event.rpc(slot,origin,direction,speed,weapon_name,weapon_index)
	throws_fired += 1

func _spawn_thrown(slot: int, origin: Vector3, direction: Vector3, speed: float, weapon_name: String, weapon_index: int, damage: float, authoritative: bool) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var thrown := Thrown.new()
	thrown.source_id = slot
	thrown.weapon = weapon_name
	thrown.weapon_index = weapon_index
	thrown.blade_length = float(Archer.DAGGER_DATA.length) if weapon_name == "dagger" else float(Archer.SWORD_DATA[clampi(weapon_index,0,2)].length)
	thrown.hit_mask = 1 | 2
	thrown.authoritative_damage = authoritative
	add_child(thrown)
	var excluded: Array[RID] = [actors[slot].get_rid()]
	thrown.launch(origin,direction,speed,damage,excluded)
	for index in range(projectiles.size()-1,-1,-1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(thrown)
	if projectiles.size() > MAX_SHOTS:
		var oldest = projectiles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	if slot == local_slot:
		audio.play_sound("release")

@rpc("authority","call_remote","reliable")
func _throw_event(slot: int, origin: Vector3, direction: Vector3, speed: float, weapon_name: String, weapon_index: int) -> void:
	if network_role == "client" and slot >= 0 and slot < actors.size():
		_spawn_thrown(slot,origin,direction,speed,weapon_name,weapon_index,0.0,false)

func _on_actor_fell(_slot: int, _source_id: int) -> void:
	if network_role != "host":
		return
	_check_party_wipe()

func _on_devil_died(devil) -> void:
	if network_role != "host":
		return
	var killer := -1
	if is_instance_valid(devil) and devil.get("last_hitter") != null:
		killer = int(devil.last_hitter)
	if killer >= 0 and killer < actors.size():
		actors[killer].apply_kill_refill()
	_drop_devil_weapon(devil)
	_check_depth_cleared()

## The authoritative host spawns the local pickup once and mirrors it to every
## client, which keeps each peer's own PlayerState pickup local and authoritative.
func _drop_devil_weapon(devil) -> void:
	if not is_instance_valid(devil) or not devil.has_method("held_weapon_id"):
		return
	var item_id := str(devil.held_weapon_id())
	if item_id.is_empty() or not State.ITEMS.has(item_id):
		return
	if not LootRules.drops():
		return
	var at := _drop_floor(devil.global_position)
	_spawn_weapon_pickup(item_id,at)
	_weapon_drop_event.rpc(item_id,at)

@rpc("authority","call_remote","reliable")
func _weapon_drop_event(item_id: String, at: Vector3) -> void:
	if network_role != "client":
		return
	_spawn_weapon_pickup(item_id,at)

func _spawn_weapon_pickup(item_id: String, at: Vector3) -> void:
	if not State.ITEMS.has(item_id):
		return
	var pickup := LootPickup.new()
	pickup.name = "DevilDrop_" + item_id
	pickup.setup(item_id,_field_display_name(item_id))
	pickup.position = at
	add_child(pickup)
	loot_pickups.append({"node":pickup, "item_id":item_id, "armed":true})

func _on_devil_struck(_target, _amount, position: Vector3, outcome) -> void:
	if network_role != "host":
		return
	var kind := "hit"
	if typeof(outcome) == TYPE_INT:
		var code := int(outcome)
		if code == Combat.DEFENSE_PARRY:
			kind = "parry"
		elif code == Combat.DEFENSE_BLOCK or code == Combat.DEFENSE_WEAK_BLOCK:
			kind = "block"
	elif typeof(outcome) == TYPE_STRING:
		var text := str(outcome)
		if text in ["parry","block","hit"]:
			kind = text
	elif typeof(outcome) == TYPE_BOOL and bool(outcome):
		kind = "parry"
	Combat.spawn_impact(self,position,kind)
	audio.play_sound("clang" if kind == "parry" else "block" if kind == "block" else "hit")
	_impact_event.rpc(position,kind)

@rpc("authority","call_remote","unreliable")
func _impact_event(position: Vector3, kind: String) -> void:
	if network_role != "client":
		return
	Combat.spawn_impact(self,position,kind)
	audio.play_sound("clang" if kind == "parry" else "block" if kind == "block" else "hit")

func _process(delta: float) -> void:
	_elapsed += delta
	if _exit_after > 0.0 and _elapsed >= _exit_after:
		_exit_after = 0.0
		print("DELVE_EXIT depth=%d phase=%s chest_ready=%s chest_open=%s rope_lowered=%s hole_open=%s" % [depth,phase,chest_ready,chest_open,world.is_rope_lowered(),world.is_hole_open()])
		get_tree().quit(0)
	if network_role == "host":
		_process_hooks(delta)
	if local_slot < 0:
		hud.reticle_visible = false
		return
	var actor = actors[local_slot]
	if not actor.alive and (_peek_held or _mouse_drawing or _throw_held):
		_peek_held = false
		_cancel_draw_input()
	_shoulder_camera.update(delta)
	_update_game_camera()
	var state: Dictionary = _run_state_dict() if network_role == "host" else _remote_state
	if state.is_empty():
		state = _run_state_dict()
	hud.update_run(state)
	hud.update_local(_local_state(actor))
	hud.set_prompt(_prompt_text())
	hud.reticle_visible = actor.alive and not _cursor_free
	hud.reticle = get_viewport().get_visible_rect().size * 0.5

func _process_hooks(delta: float) -> void:
	_mode_elapsed += delta
	if _auto_start and not _auto_fired and phase == "ALTAR" and _mode_elapsed >= AUTO_BEGIN_DELAY:
		_auto_fired = true
		begin_wave()
	if _kill_wave_hook and not _kill_fired and phase == "WAVE" and _wave_elapsed >= HOOK_KILL_DELAY:
		_kill_fired = true
		for devil in devils.duplicate():
			if is_instance_valid(devil) and devil.alive:
				devil.take_damage(99999.0,-1)

func _local_state(actor) -> Dictionary:
	return {
		"slot":actor.slot, "health":actor.health, "stamina":actor.stamina, "alive":actor.alive,
		"weapon":actor.rig.weapon, "bow":actor.rig.bow_index, "sword":actor.rig.sword_index,
		"armor":actor.rig.armor_bits(), "phase":actor.rig.phase, "draw":actor.rig.draw_amount,
		"shield":actor.rig.shield_equipped, "blocking":actor.combat.blocking,
		"movement":actor.combat.movement_mode, "attack_progress":actor.combat.attack_progress,
		"attack_interval":actor.combat.get_attack_interval(),
		"parry":actor.authoritative and actor.combat.blocking and not actor.rig.shield_equipped and actor.combat.block_time <= Combat.PARRY_WINDOW,
		"left":actor.rig.melee_progress_for("left"), "right":actor.rig.melee_progress_for("right"),
		"downed":not actor.alive, "sealed":bool(world.sealed), "run_phase":phase,
		"ability":actor.ability.hud_state(0), "ability_off":actor.ability.hud_state(1),
		"ability_trinket":actor.ability.hud_state(2),
		"max_health":actor.max_health, "max_stamina":actor.max_stamina,
	}

func _prompt_text() -> String:
	if local_slot < 0 or local_slot >= actors.size():
		return ""
	var actor = actors[local_slot]
	var pos: Vector3 = actor.global_position
	match phase:
		"ALTAR":
			if world.has_altar() and pos.distance_to(world.altar_position) <= INTERACT_RANGE:
				return "G  TOUCH THE ALTAR"
			if world.has_altar():
				return "Walk to the altar to begin depth %d" % depth
			return ""
		"RITUAL":
			return "The pentagram wakes - %d devils are coming" % wave_total
		"DROP":
			return "The pit is swallowing the party"
		"WAVE":
			var remaining := _remaining_enemies()
			if network_role == "client":
				remaining = int(_remote_state.get("remaining",remaining))
			return "Sealed in - %d cinder devils remain" % remaining
		"CLEARED":
			if chest_ready and not chest_open and is_instance_valid(chest) and pos.distance_to(world.chest_position) <= CHEST_RANGE:
				return "G  OPEN THE CACHE"
			if rope_lowered and pos.distance_to(world.rope_position) <= INTERACT_RANGE:
				return "G  ASCEND TO THE SURFACE"
			if hole_open and pos.distance_to(world.hole_position) <= INTERACT_RANGE:
				return "G  DESCEND TO DEPTH %d" % (depth + 1)
			return "The depth is broken - take the rope or the hole."
		_:
			return ""

func _update_game_camera() -> void:
	var actor = actors[local_slot]
	var height: float = actor.cover.camera_height()
	var focus: Vector3 = actor.position + Vector3(0,height,0)
	var back := Vector3(sin(_camera_yaw)*cos(_camera_pitch),sin(_camera_pitch),cos(_camera_yaw)*cos(_camera_pitch))
	camera.position = _shoulder_camera.resolve(get_world_3d().direct_space_state,focus,back,_camera_distance)
	camera.look_at(camera.position-back)

func _set_cursor_free(value: bool) -> void:
	_cursor_free = value
	if value:
		_cancel_draw_input()
		_peek_held = false
		_send_peek_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _ui_open() -> bool:
	return _world_ui != null and _world_ui.is_open()

func _on_ui_opened() -> void:
	# A menu opens with the pointer free and any held draw or throw cancelled.
	_set_cursor_free(true)

func _on_ui_closed() -> void:
	# Closing must not recapture the pointer in the lobby, a dead run or after
	# the connection dropped; the scene owns that decision.
	if network_role == "offline" or local_slot < 0 or phase == "GAME_OVER":
		return
	_set_cursor_free(false)

func _bind_ui_rig() -> void:
	if _world_ui == null:
		return
	var rig: Variant = null
	if local_slot >= 0 and local_slot < actors.size():
		rig = actors[local_slot].rig
	_world_ui.rebind(rig)

func _on_ui_loadout_changed() -> void:
	if local_slot < 0 or local_slot >= actors.size():
		return
	_bind_ui_rig()
	_apply_loadout(local_slot,_local_loadout())
	hud.update_local(_local_state(actors[local_slot]))
	if network_role == "client":
		# The host rebuilds the seat from the same validated catalog ids and
		# its snapshots stay the presentation authority for everyone else.
		send_action("loadout",_local_loadout())

## TAB toggles the persistent hand pair; the host rebuilds the seat from the
## same loadout action used by the paperdoll.
func _quick_swap() -> void:
	if _ui_open():
		return
	var node: Variant = get_node_or_null("/root/PlayerState")
	if node == null:
		return
	var result: Dictionary = node.quick_swap()
	if not bool(result.get("ok", false)):
		hud.set_status(str(result.get("message", "No quick swap set.")))
		return
	_cancel_draw_input()
	_on_ui_loadout_changed()
	audio.play_sound("equip")
	hud.set_status(str(result.get("message", "Swapped weapons.")),1.5)
func _drop_world_item(item_id: String) -> void:
	if _player_state == null or local_slot < 0 or local_slot >= actors.size():
		return
	var id := str(item_id)
	if id.is_empty() or not State.ITEMS.has(id):
		return
	var facing := Vector3(-sin(_camera_yaw),0.0,-cos(_camera_yaw))
	var pickup := LootPickup.new()
	pickup.name = "FieldDrop_" + id
	pickup.setup(id,_field_display_name(id))
	pickup.position = _drop_floor(actors[local_slot].global_position + facing*0.8)
	add_child(pickup)
	# A dropped piece arms only after the dropper steps clear, so it cannot be
	# swallowed again from the same spot.
	loot_pickups.append({"node":pickup, "item_id":id, "armed":false})

func _collect_loot(delta: float) -> void:
	_loot_message_cooldown = maxf(0.0,_loot_message_cooldown - delta)
	if _player_state == null or local_slot < 0 or local_slot >= actors.size():
		return
	var actor = actors[local_slot]
	if not actor.alive:
		return
	for index in range(loot_pickups.size()-1,-1,-1):
		var entry: Dictionary = loot_pickups[index]
		var pickup = entry.get("node")
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			loot_pickups.remove_at(index)
			continue
		var offset: Vector3 = pickup.global_position - actor.global_position
		var in_reach: bool = Vector2(offset.x,offset.z).length() <= PICKUP_RADIUS and absf(offset.y) <= 2.4
		if not in_reach:
			if not bool(entry.get("armed",true)):
				entry["armed"] = true
			continue
		if not bool(entry.get("armed",true)):
			continue
		var result: Dictionary = _player_state.try_pickup(str(entry.get("item_id","")))
		if bool(result.get("ok",false)):
			var picked := str(pickup.get("display_name"))
			loot_pickups.remove_at(index)
			pickup.queue_free()
			hud.set_status(str(result.get("message","Picked up %s." % picked)),2.5)
			_refresh_world_ui()
		elif _loot_message_cooldown <= 0.0:
			_loot_message_cooldown = DROP_FULL_INTERVAL
			hud.set_status(str(result.get("message","Backpack full.")),2.5)

func _field_display_name(item_id: String) -> String:
	if _player_state != null and _player_state.has_method("item_name"):
		var named := str(_player_state.item_name(item_id))
		if not named.is_empty() and named != item_id:
			return named
	return item_id.capitalize()

func _drop_floor(at: Vector3) -> Vector3:
	_drop_query.from = at + Vector3(0,2.0,0)
	_drop_query.to = at - Vector3(0,3.0,0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_drop_query)
	return (hit.position + Vector3(0,0.05,0)) if not hit.is_empty() else at

func _refresh_world_ui() -> void:
	if _world_ui != null:
		_world_ui.refresh()

func _crosshair_aim() -> Vector3:
	_update_game_camera()
	var center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	_aim_origin = ray_origin
	_aim_origin_valid = true
	# Match the frontier: shoulder and bow poses must not move the start past a target.
	var actor = actors[local_slot]
	var aim_anchor: Vector3 = actor.global_position + Vector3.UP*actor.cover.camera_height()
	var actor_depth := maxf(0.0,(aim_anchor-ray_origin).dot(ray_direction))
	_query.from = ray_origin + ray_direction*actor_depth
	_query.to = ray_origin + ray_direction*120.0
	# Skip only the cover this delver is posted against, on host and replica.
	var excluded: Array[RID] = [actor.get_rid()]
	var cover_rid: RID = actor.cover.attached_surface()
	if cover_rid.is_valid():
		excluded.append(cover_rid)
	_query.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	return hit.position if not hit.is_empty() else _query.to

func _input(event: InputEvent) -> void:
	if local_slot < 0:
		return
	if _ui_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_peek_held = false
		if actors[local_slot].rig.weapon != "dual":
			send_action("block",{"pressed":false,"forward":Vector3.ZERO})
		_send_peek_input()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _mouse_drawing:
			_mouse_drawing = false
			send_action("release",_crosshair_aim())
	if event is InputEventKey and event.keycode == KEY_T and not event.pressed:
		if _throw_held:
			_throw_held = false
			send_action("throw_release",_crosshair_aim())

func _cancel_draw_input() -> void:
	_mouse_drawing = false
	_throw_held = false
	send_action("stop")

func _capture_peek_context() -> void:
	_peek_right = Vector3(cos(_camera_yaw),0,-sin(_camera_yaw))

func _send_peek_input() -> void:
	send_action("peek",{"pressed":_peek_held,"right":_peek_right,"side":_shoulder_camera.side})

func _diagonal_variant() -> String:
	var side := _next_swing_side
	if side == 0:
		side = 1 if _shoulder_camera.side > 0 else -1
	return "diagonal_right" if side > 0 else "diagonal_left"

func _send_melee(hand: String, variant: String = "") -> void:
	if variant.is_empty():
		variant = _diagonal_variant()
	var aim := _crosshair_aim()
	send_action("melee",{"aim":aim,"hand":hand,"variant":variant})
	if network_role == "client" and actors[local_slot].rig.weapon != "dual":
		if variant == "diagonal_right":
			_next_swing_side = -1
		elif variant == "diagonal_left":
			_next_swing_side = 1

func _send_step(side: int) -> void:
	if local_slot < 0 or _cursor_free or side == 0:
		return
	var right := Vector3(cos(_camera_yaw),0,-sin(_camera_yaw))
	send_action("step",right*signf(float(side)))

func _unhandled_input(event: InputEvent) -> void:
	# F8 diagnostics are not delve input: they work while joining too.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		if is_instance_valid(_perf_overlay):
			_perf_overlay.toggle()
		return
	if local_slot < 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _ui_open():
			# The inventory/equipment overlay owns the keyboard while it is up.
			match event.keycode:
				KEY_ESCAPE:
					_world_ui.close()
				KEY_I:
					if _world_ui.active_view() == "inventory":
						_world_ui.close()
					else:
						_world_ui.open_inventory()
				KEY_P:
					if _world_ui.active_view() == "equipment":
						_world_ui.close()
					else:
						_world_ui.open_equipment()
			return
		match event.keycode:
			KEY_1:
				if event.shift_pressed:
					send_action("ability",0)
				else:
					send_action("weapon","bow")
			KEY_2:
				if event.shift_pressed:
					send_action("ability",1)
				else:
					send_action("weapon","sword")
			KEY_3:
				if event.shift_pressed:
					send_action("ability",2)
				else:
					send_action("weapon","dagger")
			KEY_4: send_action("shield",not actors[local_slot].rig.shield_equipped)
			KEY_5: send_action("weapon","dual")
			KEY_6: send_action("consume","bandage")
			KEY_7: send_action("consume","potion")
			KEY_TAB: _quick_swap()
			KEY_C:
				if not _cursor_free:
					send_action("crouch",not actors[local_slot].cover.crouch_requested)
			KEY_SPACE:
				if not _cursor_free:
					_peek_held = false
					_send_peek_input()
					send_action("jump",event.shift_pressed)
			KEY_F:
				if not _cursor_free:
					_cancel_draw_input()
					_peek_held = false
					_capture_peek_context()
					_send_peek_input()
					send_action("cover",Vector3(-sin(_camera_yaw),0,-cos(_camera_yaw)))
			KEY_X:
				_shoulder_camera.swap()
				_next_swing_side = _shoulder_camera.side
				_capture_peek_context()
				_send_peek_input()
			KEY_Q: _send_step(-1)
			KEY_E: _send_step(1)
			KEY_G:
				if not _cursor_free:
					send_action("interact")
			KEY_ESCAPE:
				_set_cursor_free(not _cursor_free)
			KEY_I:
				if _world_ui != null:
					_world_ui.open_inventory()
				else:
					_set_cursor_free(not _cursor_free)
			KEY_P:
				if _world_ui != null:
					_world_ui.open_equipment()
				else:
					_set_cursor_free(not _cursor_free)
			KEY_T:
				_set_cursor_free(false)
				_throw_held = true
				send_action("throw",_crosshair_aim())
	if _ui_open():
		return
	if event is InputEventMouseButton and event.pressed:
		var weapon: String = actors[local_slot].rig.weapon
		if event.button_index == MOUSE_BUTTON_LEFT:
			_set_cursor_free(false)
			if weapon == "bow":
				_mouse_drawing = true
				send_action("draw",_crosshair_aim())
			elif weapon == "dual":
				_send_melee("left","diagonal_left")
			elif weapon in ["sword","dagger"]:
				_send_melee("right")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_cursor_free(false)
			if weapon == "dual":
				_send_melee("right","diagonal_right")
			else:
				_peek_held = true
				_capture_peek_context()
				_send_peek_input()
				send_action("block",{"pressed":true,"forward":Vector3(-sin(_camera_yaw),0,-cos(_camera_yaw))})
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _cursor_free:
				return
			if event.ctrl_pressed:
				_camera_distance = maxf(3,_camera_distance-0.5)
			elif weapon in ["sword","dagger","dual"]:
				_send_melee("right","stab")
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _cursor_free:
				return
			if event.ctrl_pressed:
				_camera_distance = minf(17,_camera_distance+0.5)
			elif weapon in ["sword","dagger","dual"]:
				_send_melee("right","overhead")
	if event is InputEventMouseMotion and not _cursor_free:
		_camera_yaw -= event.relative.x*0.004
		_camera_pitch = clampf(_camera_pitch+event.relative.y*0.004,-0.7,0.7)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and local_slot >= 0:
		_set_cursor_free(true)

func _exit_tree() -> void:
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# --------------------------------------------------------------------------
# Run flow
# --------------------------------------------------------------------------

func begin_wave() -> void:
	if network_role != "host" or phase != "ALTAR":
		return
	if not world.has_altar():
		return
	_begin_ritual()

## The sanctuary altar wakes the pentagram: the room seals, the demonic ritual
## plays, and the whole wave is planned up front so every peer agrees on what
## is coming before the first imp surfaces.
func _begin_ritual() -> void:
	if network_role != "host":
		return
	world.set_sealed(true)
	_wave_elapsed = 0.0
	_wave_clock = 0.0
	_ritual_elapsed = 0.0
	_ritual_progress = 0.0
	_drop_elapsed = 0.0
	_kill_fired = false
	wave_number = _waves_started + 1
	_build_wave_plan()
	_set_phase("RITUAL")
	hud.show_banner("WAVE %d" % wave_number,2.0)
	print("DELVE_RITUAL_START room=%s total=%d" % [str(world.room_kind),wave_total])
	_sync_run_state()

func descend_next_depth() -> void:
	if network_role != "host" or phase != "CLEARED":
		return
	depth += 1
	var kind := _room_kind(depth)
	var room_cycle := _room_cycle(depth)
	_clear_devils()
	_remove_chest()
	chest_ready = false
	chest_open = false
	rope_lowered = false
	hole_open = false
	_clear_timer = 0.0
	_wave_elapsed = 0.0
	_wave_clock = 0.0
	_ritual_elapsed = 0.0
	_ritual_progress = 0.0
	_drop_elapsed = 0.0
	_wave_plan.clear()
	_wave_cursor = 0
	wave_total = 0
	_kill_fired = false
	_auto_fired = false
	_mode_elapsed = 0.0
	# The world rebuilds both rooms on the same footprint, keeps the altar,
	# rope and hole coordinates, swaps the palette for the new cycle and
	# resets the sealed barriers, rope, hole and beacons.
	world.apply_room(kind,room_cycle)
	_drop_party()
	hud.show_banner("DEPTH %d" % depth,2.5)
	if world.has_altar():
		_set_phase("ALTAR")
	else:
		# The ossuary has no altar: the summoning resumes as soon as the party
		# has landed on the floor of the pit.
		_set_phase("DROP")
		print("DELVE_DROP room=%s" % kind)
	print("DELVE_DEPTH_DESCEND depth=%d room=%s cycle=%d" % [depth,kind,room_cycle])
	_sync_run_state()

func _room_kind(value: int) -> String:
	return World.ROOM_SANCTUARY if value % 2 == 1 else World.ROOM_OSSUARY

func _room_cycle(value: int) -> int:
	return (value + 1) / 2

func ascend_to_surface() -> void:
	if network_role != "host":
		return
	if phase != "CLEARED":
		return
	_ascend_event.rpc()
	print("DELVE_RETURN_SURFACE")
	# Give ENet a couple of polls to flush the reliable departure before this
	# controller closes its peer on the way out.
	get_tree().create_timer(0.25).timeout.connect(_change_scene_to_surface,CONNECT_ONE_SHOT)

@rpc("authority","call_remote","reliable")
func _ascend_event() -> void:
	print("DELVE_RETURN_SURFACE")
	_change_scene_to_surface()

func _change_scene_to_surface() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func open_chest() -> void:
	if network_role != "host" or phase != "CLEARED":
		return
	if not chest_ready or chest_open:
		return
	if not is_instance_valid(chest):
		_spawn_chest()
	if not is_instance_valid(chest):
		return
	chest.open(false)
	_on_chest_opened()

func reach_phase() -> Dictionary:
	var state := _run_state_dict()
	state["local_slot"] = local_slot
	state["humans"] = get_human_count()
	state["devils_alive"] = _live_devil_count()
	return state

func _start_wave() -> void:
	_ritual_progress = 1.0
	_wave_clock = 0.0
	_wave_elapsed = 0.0
	_kill_fired = false
	_waves_started += 1
	_set_phase("WAVE")
	print("DELVE_DEPTH_START depth=%d mobs=%d" % [depth,wave_total])
	print("DELVE_WAVE_START room=%s wave=%d total=%d" % [str(world.room_kind),wave_number,wave_total])
	_sync_run_state()

## Public HUD/test surface: copies of the planned entries, in spawn order.
func wave_plan() -> Array:
	var plan: Array = []
	for entry in _wave_plan:
		plan.append({
			"role":str(entry.get("role",Devil.ROLE_DEVIL)),
			"weapon":str(entry.get("weapon","claw")),
			"at":float(entry.get("at",0.0)),
			"position":Vector3(entry.get("position",Vector3.ZERO))
		})
	return plan

func _wave_duration(kind: String) -> float:
	return WAVE2_SECONDS if kind == World.ROOM_OSSUARY else WAVE1_SECONDS

## The wave budget: ten enemies on the run's first wave, five more each wave.
## The room kind picks the window length and the composition, never the count.
func _wave_total_for() -> int:
	return WAVE_FIRST_ENEMIES + WAVE_STEP * maxi(0,wave_number - 1)

## One budget, one composition: the five court devils and the crimson clones are
## set pieces drawn from the wave total, and the plain ladder fills the rest, so
## `wave_total` is the number of bodies the room fields. Cycle one's ladder is
## deliberately plain - imps and cinder devils in the old 16:10 ratio - and the
## deeper cycles trade imps for bonefiends and brutes in the ossuary, devils in
## the sanctuary. The list comes back ordered easy to hard: see `_easy_first`.
func _wave_roles(kind: String, total: int) -> Array:
	var extras: Array = []
	for role in Devil.SPECIES_ROLES:
		extras.append(str(role))
	for index in _clone_count():
		extras.append(Devil.ROLE_RANGER)
	var ladder := maxi(1,total - extras.size())
	var roles: Array = []
	if int(world.cycle) <= 1:
		var imps := clampi(int(round(float(ladder) * CYCLE_ONE_IMP_SHARE)),1,ladder)
		for index in imps:
			roles.append(Devil.ROLE_IMP)
		for index in ladder - imps:
			roles.append(Devil.ROLE_DEVIL)
	elif kind == World.ROOM_OSSUARY:
		var heavy := mini(maxi(2,int(round(float(ladder) * 0.2))),ladder)
		var brutes := mini(maxi(2,int(round(float(ladder) * 0.3))),ladder - heavy)
		for index in heavy:
			roles.append(Devil.ROLE_IMP)
		for index in ladder - heavy - brutes:
			roles.append(Devil.ROLE_BONEFIEND)
		for index in brutes:
			roles.append(Devil.ROLE_BRUTE)
	else:
		var devils := mini(maxi(2,ladder / 4),ladder)
		for index in ladder - devils:
			roles.append(Devil.ROLE_IMP)
		for index in devils:
			roles.append(Devil.ROLE_DEVIL)
	roles.append_array(extras)
	return _easy_first(roles)

## How many crimson clones join this wave: none before `CLONE_FIRST_WAVE`, one on
## that wave, then one more per wave up to `CLONE_MAX`.
func _clone_count() -> int:
	return clampi(wave_number - CLONE_FIRST_WAVE + 1,0,CLONE_MAX)

## Sorts a wave's roles from the lightest body to the heaviest, so the ritual's
## opening seconds are imps and the court devils and clones arrive as the room
## closes. Ties keep their composition order, which keeps the schedule stable.
func _easy_first(roles: Array) -> Array:
	var ranked: Array = []
	for index in roles.size():
		var role := str(roles[index])
		ranked.append({
			"role": role,
			"tier": int(Devil.ROLE_DIFFICULTY.get(role,Devil.ROLE_DIFFICULTY.size())),
			"index": index
		})
	ranked.sort_custom(_compare_difficulty)
	var ordered: Array = []
	for entry in ranked:
		ordered.append(str(entry.get("role",Devil.ROLE_DEVIL)))
	return ordered

## Stable by construction: the composition index breaks every tier tie.
func _compare_difficulty(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("tier",0)) != int(b.get("tier",0)):
		return int(a.get("tier",0)) < int(b.get("tier",0))
	return int(a.get("index",0)) < int(b.get("index",0))

func _wave_weapon(role: String, role_index: int) -> String:
	if role == Devil.ROLE_RANGER or Devil.SPECIES_ROLES.has(role):
		# Both pick their own kit; the clone rolls a random paperdoll.
		return "claw"
	if role == Devil.ROLE_IMP:
		return "claw" if role_index % 2 == 0 else "dagger"
	if role == Devil.ROLE_DEVIL:
		return "dagger" if role_index % 2 == 0 else "sword"
	return "sword"

## Late-weighted schedule over an easy-first ladder:
## `at = duration * (i / (total - 1)) ^ SPAWN_CURVE`, with the roles already
## sorted light to heavy, so the room opens on imps and the heavies close it.
func _build_wave_plan() -> void:
	_wave_plan.clear()
	_wave_cursor = 0
	_wave_clock = 0.0
	var kind := str(world.room_kind)
	var budget := _wave_total_for()
	var roles := _wave_roles(kind,budget)
	var total := roles.size()
	wave_total = total
	var duration := _wave_duration(kind)
	var picked: Array = []
	var role_counts: Dictionary = {}
	for index in roles.size():
		var role := str(roles[index])
		var role_index := int(role_counts.get(role,0))
		role_counts[role] = role_index + 1
		var progress := float(index) / float(maxi(total - 1,1))
		var point := _wave_spawn_point(index,picked)
		picked.append(point)
		_wave_plan.append({
			"role":role,
			"weapon":_wave_weapon(role,role_index),
			"at":duration * pow(progress,SPAWN_CURVE),
			"position":point,
			"facing":_face_nearest_ranger(point)
		})

## Deterministic random floor point for one wave entry. The seed mixes the run
## seed, the depth and the entry index, so a replayed run and every peer agree.
## Candidates that crowd a standing ranger or a sibling spawn are rejected; if
## the floor is that saturated the roomiest candidate still wins, so the wave
## always surfaces instead of stalling.
func _wave_spawn_point(index: int, picked: Array) -> Vector3:
	var candidates: Array = world.spawn_points
	if candidates.is_empty():
		return world.altar_position
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(run_seed) + depth * 7919 + index * 104729
	var start := rng.randi_range(0,candidates.size() - 1)
	var roomiest: Vector3 = candidates[start]
	var best := -1.0
	for offset in candidates.size():
		var point: Vector3 = candidates[(start + offset) % candidates.size()]
		var clearance := _spawn_clearance(point,picked)
		if clearance >= 0.0:
			return point
		if clearance > best:
			best = clearance
			roomiest = point
	return roomiest

## Negative when a candidate is too close to a standing ranger or to a spawn
## already claimed by this wave; otherwise its nearest-neighbour distance.
func _spawn_clearance(point: Vector3, picked: Array) -> float:
	var clearance := 1.0e9
	for actor in actors:
		if actor.peer_id <= 0 or not actor.alive:
			continue
		var gap := _flat_distance(point,actor.global_position)
		if gap < SPAWN_PLAYER_CLEARANCE:
			return -1.0
		clearance = minf(clearance,gap)
	for other in picked:
		var gap := _flat_distance(point,other)
		if gap < SPAWN_MUTUAL_CLEARANCE:
			return -1.0
		clearance = minf(clearance,gap)
	return clearance

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x,a.z - b.z).length()

func _face_nearest_ranger(point: Vector3) -> Vector3:
	var nearest: Variant = null
	var best := 1.0e9
	for actor in actors:
		if actor.peer_id <= 0 or not actor.alive:
			continue
		var gap := _flat_distance(point,actor.global_position)
		if gap < best:
			best = gap
			nearest = actor
	if nearest == null:
		return Vector3.FORWARD
	var facing: Vector3 = nearest.global_position - point
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return Vector3.FORWARD
	return facing.normalized()

func _advance_host_state(delta: float) -> void:
	match phase:
		"RITUAL":
			_ritual_elapsed += delta
			_ritual_progress = clampf(_ritual_elapsed / RITUAL_SECONDS,0.0,1.0)
			world.set_ritual(true,_ritual_progress)
			if _ritual_elapsed >= RITUAL_SECONDS:
				_start_wave()
		"DROP":
			# The ossuary summoning starts once every survivor is on the floor.
			_drop_elapsed += delta
			if _drop_elapsed >= DROP_GRACE and _party_landed():
				_begin_ritual()
		"WAVE":
			_wave_elapsed += delta
			_wave_clock += delta * spawn_time_scale
			# A body costs about a millisecond to enter the tree, so the wave
			# budget drains over frames instead of landing in one: the entries
			# due now that do not fit wait for the next frame.
			var budget := SPAWN_PER_FRAME
			while budget > 0 and _wave_cursor < _wave_plan.size():
				var entry: Dictionary = _wave_plan[_wave_cursor]
				if float(entry.get("at",0.0)) > _wave_clock:
					break
				_spawn_devil(entry)
				_wave_cursor += 1
				budget -= 1
		"CLEARED":
			if chest_ready:
				return
			_clear_timer = maxf(0.0,_clear_timer-delta)
			if _clear_timer <= 0.0:
				_clear_timer = 0.0
				chest_ready = true
				_spawn_chest()
				rope_lowered = true
				hole_open = true
				world.set_rope_lowered(true)
				world.set_hole_open(true)
				_refresh_beacons()
				hud.set_status("The cache is ready. Climb the rope or drop through the floor.",3.0)
				print("DELVE_CACHE_READY depth=%d" % depth)
				_sync_run_state()
		_:
			pass

func _party_landed() -> bool:
	for actor in actors:
		if actor.peer_id <= 0 or not actor.alive:
			continue
		if actor.global_position.y >= DROP_LAND_Y:
			return false
	return true

func _spawn_devil(entry: Dictionary) -> void:
	var role := str(entry.get("role",Devil.ROLE_DEVIL))
	var weapon := str(entry.get("weapon","claw"))
	var point: Vector3 = entry.get("position",world.altar_position)
	var facing: Vector3 = entry.get("facing",Vector3.ZERO)
	if role == Devil.ROLE_RANGER:
		var clone := RangerClone.new()
		clone.name = "RangerClone%d" % _next_devil_id
		clone.bounds = Devil.LIMIT
		add_child(clone)
		clone.configure(_next_devil_id,depth,true,"direct")
		clone.spawn_at(point,facing)
		clone.died.connect(_on_devil_died)
		clone.struck.connect(_on_devil_struck)
		clone.arrow_fired.connect(_on_clone_arrow)
		devils.append(clone)
		_next_devil_id += 1
		return
	var devil = Devil.new()
	devil.name = "Devil%d" % _next_devil_id
	add_child(devil)
	devil.configure(_next_devil_id,weapon,depth,role)
	devil.authoritative = true
	devil.spawn_at(point,facing)
	devil.died.connect(_on_devil_died)
	devil.struck.connect(_on_devil_struck)
	devils.append(devil)
	_next_devil_id += 1

func _depth_cleared() -> void:
	if phase != "WAVE":
		return
	_set_phase("CLEARED")
	world.set_sealed(false)
	_clear_timer = CLEAR_DELAY
	print("DELVE_DEPTH_CLEAR depth=%d" % depth)
	hud.show_banner("DEPTH %d CLEARED" % depth,2.0)
	_sync_run_state()

func _check_depth_cleared() -> void:
	if phase != "WAVE":
		return
	if _wave_cursor < _wave_plan.size():
		return
	for devil in devils:
		if is_instance_valid(devil) and devil.alive:
			return
	_depth_cleared()

func _check_hole_descent() -> void:
	if phase != "CLEARED" or not hole_open:
		return
	for actor in actors:
		if actor.peer_id <= 0 or not actor.alive:
			continue
		if world.is_in_hole(actor.global_position):
			descend_next_depth()
			return

func _remaining_enemies() -> int:
	if phase != "WAVE":
		return 0
	return maxi(0,_wave_plan.size() - _wave_cursor) + _live_devil_count()

func _live_devil_count() -> int:
	var count := 0
	for devil in devils:
		if is_instance_valid(devil) and devil.alive:
			count += 1
	return count

func _live_devils() -> Array:
	var live: Array = []
	for devil in devils:
		if is_instance_valid(devil) and devil.alive:
			live.append(devil)
	return live

func _clear_devils() -> void:
	for devil in devils:
		if is_instance_valid(devil):
			devil.queue_free()
	devils.clear()
	if network_role == "host":
		_devils_reset.rpc()

@rpc("authority","call_remote","reliable")
func _devils_reset() -> void:
	if network_role != "client":
		return
	_on_devils_reset_local()

func _on_devils_reset_local() -> void:
	for key in _devil_nodes.keys():
		var node = _devil_nodes[key]
		if is_instance_valid(node):
			node.queue_free()
	_devil_nodes.clear()
	_devil_dead_ids.clear()
	_last_devil_tick = -1

@rpc("authority","call_remote","unreliable")
func _clone_snapshots(tick: int, states: Array) -> void:
	if network_role != "client" or tick < _last_clone_tick:
		return
	_last_clone_tick = tick
	for state in states:
		if typeof(state) != TYPE_DICTIONARY:
			continue
		var id := int(state.get("id",0))
		var state_alive := bool(state.get("alive",true))
		if not state_alive:
			_devil_dead_ids[id] = true
		var node = _devil_nodes.get(id)
		if node == null or not is_instance_valid(node):
			if not state_alive:
				continue
			var created := RangerClone.new()
			created.name = "RangerClone%d" % id
			add_child(created)
			created.configure(id,int(state.get("depth",depth)),false,"direct")
			created.apply_snapshot(state,tick)
			_devil_nodes[id] = created
			continue
		node.apply_snapshot(state,tick)


func _on_clone_arrow(origin: Vector3, direction: Vector3, speed: float, _damage: float) -> void:
	if network_role != "host":
		return
	_clone_arrow_event.rpc(origin,direction,speed)


@rpc("authority","call_remote","reliable")
func _clone_arrow_event(origin: Vector3, direction: Vector3, speed: float) -> void:
	if network_role != "client":
		return
	var arrow := Arrow.new()
	arrow.hit_mask = 1 | 4 | 8
	arrow.authoritative_damage = false
	add_child(arrow)
	arrow.launch(origin,direction,speed,0.0,[])


@rpc("authority","call_remote","unreliable")
func _devil_snapshots(tick: int, states: Array) -> void:
	# One wave now arrives as several datagrams with the same tick, so only an
	# older tick is stale; applying a batch twice is idempotent.
	if network_role != "client" or tick < _last_devil_tick:
		return
	_last_devil_tick = tick
	for state in states:
		if typeof(state) != TYPE_DICTIONARY:
			continue
		var id := int(state.get("id",0))
		var state_alive := bool(state.get("alive",true))
		if not state_alive:
			_devil_dead_ids[id] = true
		var node = _devil_nodes.get(id)
		if node == null or not is_instance_valid(node):
			# The corpse already finished; never respawn a replica just to die.
			if not state_alive:
				continue
			var created = Devil.new()
			add_child(created)
			created.configure(id,str(state.get("weapon","claw")),int(state.get("depth",depth)),
				str(state.get("role",Devil.ROLE_DEVIL)))
			created.authoritative = false
			_devil_nodes[id] = created
			node = created
		node.apply_snapshot(state,tick)

func _spawn_chest() -> void:
	if is_instance_valid(chest):
		return
	chest = Chest.new()
	add_child(chest)
	chest.position = world.chest_position
	if not chest.opened.is_connected(_on_chest_opened):
		chest.opened.connect(_on_chest_opened)
	chest.set_depth(depth)

func _remove_chest() -> void:
	if is_instance_valid(chest):
		chest.queue_free()
	chest = null

func _on_chest_opened() -> void:
	if network_role != "host" or chest_open:
		return
	chest_open = true
	_chest_event.rpc()
	var gold := 40 + 30 * depth
	# The cache still pays its gold; the item is the tenth-of-the-old-rate roll.
	var item_id := _reward_item() if LootRules.drops() else ""
	_grant_reward(depth,gold,item_id)
	_reward_event.rpc(depth,gold,item_id)
	print("DELVE_CHEST_OPEN depth=%d gold=%d item=%s" % [depth,gold,item_id])
	_sync_run_state()

@rpc("authority","call_remote","reliable")
func _reward_event(depth_value: int, gold: int, item_id: String) -> void:
	_grant_reward(depth_value,gold,item_id)

## Every peer grants to its own PlayerState. The host calls this once locally
## and the authority RPC covers the clients, so credits land exactly once.
func _grant_reward(depth_value: int, gold: int, item_id: String) -> void:
	hud.show_banner("+%d GOLD" % gold,2.5)
	if _player_state == null:
		hud.set_status("DEPTH %d CACHE: %d gold" % [depth_value,gold],4.0)
		return
	_player_state.add_credits(gold)
	var gained := ""
	if not item_id.is_empty():
		var result: Dictionary = _player_state.try_pickup(item_id)
		gained = _field_display_name(item_id) if bool(result.get("ok",false)) else "backpack full"
	var message := "+%d gold" % gold
	if not gained.is_empty():
		message += "  /  " + gained
	hud.set_status("DEPTH %d CACHE: %s" % [depth_value,message],4.5)

## Deterministic per (seed, depth): the table climbs in tiers, the index is the
## same on every peer because the host broadcasts the chosen id anyway.
func _reward_item() -> String:
	var table: Array = LOOT_TIERS[mini((depth - 1) / 5,LOOT_TIERS.size() - 1)]
	var index := (absi(run_seed) + depth * 7) % table.size()
	return str(table[index])

@rpc("authority","call_remote","reliable")
func _chest_event() -> void:
	if network_role != "client":
		return
	chest_open = true
	if not is_instance_valid(chest) and chest_ready:
		_spawn_chest()
	if is_instance_valid(chest) and not chest.is_opened():
		chest.open(false)

func _sync_client_chest() -> void:
	if network_role != "client":
		return
	if chest_ready:
		if not is_instance_valid(chest):
			_spawn_chest()
		if chest_open and is_instance_valid(chest) and not chest.is_opened():
			chest.open(false)
	elif is_instance_valid(chest):
		_remove_chest()

@rpc("authority","call_remote","reliable")
func _run_state(state: Dictionary) -> void:
	if network_role != "client":
		return
	_apply_run_state(state)

func _apply_run_state(state: Dictionary) -> void:
	var previous_phase := phase
	var previous_depth := depth
	var room := str(state.get("room",str(world.room_kind)))
	if room != World.ROOM_SANCTUARY and room != World.ROOM_OSSUARY:
		room = str(world.room_kind)
	var room_cycle := maxi(1,int(state.get("cycle",int(world.cycle))))
	if room != str(world.room_kind) or room_cycle != int(world.cycle):
		# Both rooms share one footprint; the rebuild also drops the sealed
		# barriers, the rope, the hole and the beacons, so reapply them below.
		world.apply_room(room,room_cycle)
	phase = str(state.get("phase",phase))
	depth = maxi(1,int(state.get("depth",depth)))
	wave_total = maxi(0,int(state.get("wave_total",wave_total)))
	wave_number = maxi(1,int(state.get("wave_number",wave_number)))
	_ritual_progress = clampf(float(state.get("ritual",_ritual_progress)),0.0,1.0)
	chest_ready = bool(state.get("chest_ready",chest_ready))
	chest_open = bool(state.get("chest_open",chest_open))
	rope_lowered = bool(state.get("rope_lowered",rope_lowered))
	hole_open = bool(state.get("hole_open",hole_open))
	_clear_timer = float(state.get("timer",0.0))
	_remote_state = state.duplicate(true)
	# The host's slot index is not this client's; the party panel marks the
	# local row from this field, so keep it local.
	_remote_state["local_slot"] = local_slot
	if state.has("endpoint"):
		_endpoint = str(state.get("endpoint",_endpoint))
	world.set_sealed(bool(state.get("sealed",false)))
	world.set_rope_lowered(rope_lowered)
	world.set_hole_open(hole_open)
	_apply_world_ritual(bool(state.get("pentagram",_pentagram_lit())),_ritual_progress_value())
	_refresh_beacons()
	var party: Variant = state.get("party",[])
	var active_slots: Dictionary = {}
	if party is Array:
		for row in party:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var slot := int(row.get("slot",-1))
			if slot < 0 or slot >= actors.size():
				continue
			active_slots[slot] = true
			var actor = actors[slot]
			actor.display_name = str(row.get("name",actor.display_name))
			if actor.slot != local_slot:
				actor.visible = true
	for actor in actors:
		if not active_slots.has(actor.slot) and actor.slot != local_slot:
			actor.visible = false
			actor.alive = false
			actor.collision_layer = 0
			actor.collision_mask = 0
	_sync_client_chest()
	if phase == "GAME_OVER":
		if _ui_open():
			_world_ui.close()
		_set_cursor_free(true)
	if phase != previous_phase:
		match phase:
			"ALTAR", "DROP":
				hud.show_banner("DEPTH %d" % depth,2.0)
			"RITUAL":
				hud.show_banner("WAVE %d" % wave_number,2.0)
			"CLEARED":
				hud.show_banner("DEPTH %d CLEARED" % depth,2.0)
			"GAME_OVER":
				hud.show_game_over("The delve has claimed the party.")
	elif depth != previous_depth:
		hud.show_banner("DEPTH %d" % depth,2.0)

func _run_state_dict() -> Dictionary:
	var party: Array = []
	for actor in actors:
		if actor.peer_id <= 0:
			continue
		party.append({"slot":actor.slot, "name":actor.display_name, "health":actor.health, "max_health":actor.max_health,
			"alive":actor.alive, "peer":actor.peer_id, "downed":not actor.alive})
	return {
		"phase":phase, "depth":depth,
		"room":str(world.room_kind), "cycle":int(world.cycle),
		"ritual":_ritual_progress_value(), "pentagram":_pentagram_lit(),
		"wave_total":wave_total, "wave_number":wave_number,
		"remaining":_remaining_enemies(),
		"timer":maxf(0.0,_clear_timer) if phase == "CLEARED" else 0.0,
		"sealed":bool(world.sealed), "chest_ready":chest_ready, "chest_open":chest_open,
		"rope_lowered":bool(world.is_rope_lowered()), "hole_open":bool(world.is_hole_open()),
		"party":party, "role":network_role, "endpoint":_endpoint, "local_slot":local_slot,
	}

func _sync_run_state() -> void:
	if network_role != "host":
		return
	_run_state.rpc(_run_state_dict())

func _set_phase(value: String) -> void:
	phase = value
	print("DELVE_PHASE phase=%s depth=%d" % [phase,depth])
	_apply_world_ritual(_pentagram_lit(),_ritual_progress_value())
	_refresh_beacons()
	if phase == "GAME_OVER":
		if _ui_open():
			_world_ui.close()
		_set_cursor_free(true)
		hud.show_game_over("The delve has claimed the party.")

## The pentagram burns through the ritual and the wave it summons, then rests.
func _pentagram_lit() -> bool:
	return phase == "RITUAL" or phase == "WAVE"

func _ritual_progress_value() -> float:
	if phase == "RITUAL":
		return clampf(_ritual_progress,0.0,1.0)
	if phase == "WAVE":
		return 1.0
	return 0.0

func _apply_world_ritual(pentagram_active: bool, progress: float) -> void:
	if pentagram_active:
		world.set_pentagram(true,1.0)
		world.set_ritual(true,clampf(progress,0.0,1.0))
	else:
		world.set_pentagram(false)
		world.set_ritual(false,0.0)

## Beacons mark only what the party can actually act on right now.
func _refresh_beacons() -> void:
	var altar: bool = phase == "ALTAR" and bool(world.has_altar())
	var rope := phase == "CLEARED" and bool(world.is_rope_lowered())
	var hole := phase == "CLEARED" and bool(world.is_hole_open())
	world.set_beacons(altar,rope,hole)

func _check_party_wipe() -> void:
	if network_role != "host":
		return
	if phase != "RITUAL" and phase != "DROP" and phase != "WAVE" and phase != "CLEARED":
		return
	var active := 0
	var standing := 0
	for actor in actors:
		if actor.peer_id <= 0:
			continue
		active += 1
		if actor.alive:
			standing += 1
	if active > 0 and standing == 0:
		_game_over()

func _game_over() -> void:
	if phase == "GAME_OVER":
		return
	_set_phase("GAME_OVER")
	for actor in actors:
		actor.combat.stop()
	print("DELVE_GAME_OVER depth=%d" % depth)
	_sync_run_state()

func _drop_party() -> void:
	var index := 0
	for actor in actors:
		if actor.peer_id <= 0:
			continue
		var angle := TAU * float(index) / 4.0
		var point: Vector3 = world.drop_center + Vector3(cos(angle)*2.4,0.0,sin(angle)*2.4)
		actor.respawn_at(point)
		actor.combat.damage_enabled = true
		index += 1

func _host_interact(slot: int) -> void:
	if network_role != "host" or slot < 0 or slot >= actors.size():
		return
	var actor = actors[slot]
	if not actor.alive:
		return
	var pos: Vector3 = actor.global_position
	match phase:
		"ALTAR":
			if world.has_altar() and pos.distance_to(world.altar_position) <= INTERACT_RANGE:
				begin_wave()
		"CLEARED":
			if chest_ready and not chest_open and is_instance_valid(chest) \
					and pos.distance_to(world.chest_position) <= CHEST_RANGE:
				open_chest()
				return
			# The rope is the way out; the open floor is the way deeper. Either
			# survivor may lead, so a downed host does not strand the party.
			if rope_lowered and pos.distance_to(world.rope_position) <= INTERACT_RANGE:
				ascend_to_surface()
				return
			if hole_open and pos.distance_to(world.hole_position) <= INTERACT_RANGE:
				descend_next_depth()
		_:
			pass
