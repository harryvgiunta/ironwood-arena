extends Node3D

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const World = preload("res://scripts/arena_world.gd")
const Hud = preload("res://scripts/arena_hud.gd")
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
const SeatLoadout = preload("res://scripts/seat_loadout.gd")
const FieldInventoryScript = preload("res://scripts/world_ui.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const LagCompensation = preload("res://scripts/lag_compensation.gd")
const PerfOverlay = preload("res://scripts/perf_overlay.gd")
## A backstab picks its body from the layer the fighters spar on.
const BACKSTAB_MASK := 4
const BACKSTAB_RANGE := 8.0
## The longest rewind the host will ever perform for one client action.
const MAX_LAG_TICKS := 30
const SNAPSHOT_INTERVAL := 0.05
var actors: Array = []
var local_slot := -1
var network_role := "offline"
var server_tick := 0
var last_snapshot_tick := -1
var projectiles: Array[Node3D] = []
var shots_fired := 0
var throws_fired := 0
var world
var hud
var audio
var camera: Camera3D
## F8 frame diagnostics (see `perf_overlay.gd`).
var _perf_overlay
var _peer_slots: Dictionary = {}
# Per actor: newest snapshot sent by the host or applied by this client.
var _snapshot_ticks := PackedInt32Array([-1,-1,-1,-1])
## The server tick this client draws the world at, learned from arrivals.
var _clock = NetReplication.NetClock.new()
## One second of hitbox poses so a client's swing resolves against its view.
var _lag = LagCompensation.new()
var _player_name := "Ranger"
var _endpoint := ""
var _join_elapsed := 0.0
var _send_elapsed := 0.0
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
var _world_ui

func _ready() -> void:
	name = "Arena"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world = World.new()
	add_child(world)
	for index in 4:
		var actor := Actor.new()
		actor.slot = index
		actor.name = "Fighter%d" % index
		add_child(actor)
		actor.configure(0,true,"Bot %d" % (index+1),world.spawn_points[index])
		actor.bounds = World.LIMIT-0.3
		actor.interp_delay = 0.12
		actor.combat.lag_rewind = _lag
		actor.fired.connect(_on_fired)
		actor.thrown_weapon.connect(_on_thrown_weapon)
		actor.killed.connect(_on_killed)
		actor.combat.clash.connect(_on_clash)
		actor.combat.defense_resolved.connect(_on_defense_resolved)
		actor.ability.cue.connect(_on_ability_cue.bind(actor))
		actor.visible = false
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
	hud.host_requested.connect(host_game)
	hud.join_requested.connect(join_game)
	hud.leave_requested.connect(leave_game)
	hud.town_requested.connect(_hub)
	hud.bow_selected.connect(func(index: int): send_action("bow",index))
	hud.armor_selected.connect(func(slot: String, set_index: int): send_action("armor",{"slot":slot,"set":set_index}))
	hud.sword_selected.connect(func(index: int): send_action("sword",index))
	hud.weapon_selected.connect(func(value: String): send_action("weapon",value))
	hud.shield_selected.connect(func(active: bool): send_action("shield",active))
	hud.consumable_selected.connect(func(kind: String): send_action("consume",kind))
	var player_state := get_node_or_null("/root/PlayerState")
	if player_state != null:
		_world_ui = FieldInventoryScript.new()
		_world_ui.name = "WorldUI"
		_world_ui.layer = layer.layer + 1
		add_child(_world_ui)
		_world_ui.opened.connect(_on_ui_opened)
		_world_ui.closed.connect(_on_ui_closed)
		_world_ui.loadout_changed.connect(_on_ui_loadout_changed)
		# No world-drop handler: arena drops fall back to the persistent floor list.
		_world_ui.configure(player_state,get_node_or_null("/root/Session"),null,Callable(),true)
	audio = Audio.new()
	add_child(audio)
	_query.collision_mask = 1 | 4
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _connection_ended("Could not join. Check address, UDP port and host capacity (four players)."))
	multiplayer.server_disconnected.connect(func(): _connection_ended("The host disconnected. Host a new match or join another game."))
	call_deferred("_read_arguments")

func _read_arguments() -> void:
	var pending: Dictionary = {}
	var session_node := get_node_or_null("/root/Session")
	if session_node != null:
		pending = session_node.take()
	var args := OS.get_cmdline_user_args()
	var port := 7777
	var player_name := "Ranger"
	var address := ""
	for index in args.size():
		if args[index] == "--arena-port" and index+1 < args.size():
			port = args[index+1].to_int()
		elif args[index] == "--arena-name" and index+1 < args.size():
			player_name = args[index+1]
		elif args[index] == "--arena-join" and index+1 < args.size():
			address = args[index+1]
	# Explicit command-line intent stays authoritative; the hub request fills the gap.
	if args.has("--arena-host"):
		host_game(port,player_name)
	elif not address.is_empty():
		join_game(address,port,player_name)
	elif str(pending.get("mode","")) == "skirmish":
		host_game(int(pending.port),str(pending.name),true)
	elif str(pending.get("mode","")) == "host":
		host_game(int(pending.port),str(pending.name))
	elif str(pending.get("mode","")) == "client":
		join_game(str(pending.address),int(pending.port),str(pending.name))

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
		# A local practice match must not lose to an existing host on the default port.
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
	network_role = "host"
	local_slot = 0
	_camera_yaw = atan2(world.spawn_points[0].x,world.spawn_points[0].z)
	_peer_slots[1] = 0
	_player_name = _safe_name(player_name)
	_remember_network(_player_name,"",port)
	for actor in actors:
		actor.authoritative = true
		actor.visible = true
		actor.is_local = actor.slot == 0
		actor.configure(1 if actor.slot == 0 else 0,actor.slot != 0,_player_name if actor.slot == 0 else "Bot %d" % actor.slot,world.spawn_points[actor.slot])
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
			addresses.append(address)
	_endpoint = "UDP %d / LAN %s / same PC 127.0.0.1" % [port,", ".join(addresses)]
	hud.show_match(_player_name,_endpoint)
	_set_cursor_free(false)
	_apply_loadout(0,_local_loadout())
	_bind_ui_rig()
	print("ARENA_HOST_READY port=",port)

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
	_join_elapsed = 0
	hud.set_status("Connecting to " + _endpoint + "...")

func leave_game() -> void:
	network_role = "offline"
	if _world_ui != null:
		if _world_ui.is_open():
			_world_ui.close()
		_world_ui.rebind(null)
	local_slot = -1
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer_slots.clear()
	last_snapshot_tick = -1
	_snapshot_ticks.fill(-1)
	server_tick = 0
	_send_elapsed = 0
	shots_fired = 0
	throws_fired = 0
	_mouse_drawing = false
	_throw_held = false
	_peek_held = false
	_next_swing_side = 0
	_peek_right = Vector3.RIGHT
	_cursor_free = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	projectiles.clear()
	for actor in actors:
		actor.combat.stop()
		actor.reset_stance()
		actor.authoritative = false
		actor.is_local = false
		actor.predicting = false
		actor.combat.damage_enabled = false
		actor.visible = false
		actor.collision_layer = 0
		actor.collision_mask = 0
	hud.show_lobby()

func _connection_ended(message: String) -> void:
	leave_game()
	hud.set_status(message)
	print("ARENA_CONNECTION_ENDED ",message)

func _hub() -> void:
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
		cache.remember(player_name,address,port,"arena")

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

func _apply_loadout(slot: int, loadout: Dictionary) -> void:
	if slot < 0 or slot >= actors.size():
		return
	SeatLoadout.apply(actors[slot].rig,loadout)

func get_human_count() -> int:
	var count := 0
	for actor in actors:
		if not actor.is_bot:
			count += 1
	return count if network_role != "offline" else 0

func _peer_connected(peer_id: int) -> void:
	if network_role != "host":
		return
	multiplayer.multiplayer_peer.get_peer(peer_id).set_timeout(32,2000,5000)
	for actor in actors:
		if actor.is_bot:
			_clear_slot_arrows(actor.slot)
			actor.configure(peer_id,false,"Joining ranger",world.spawn_points[actor.slot])
			_peer_slots[peer_id] = actor.slot
			_accept.rpc_id(peer_id,actor.slot)
			_broadcast_names()
			print("ARENA_PEER_JOINED slot=",actor.slot," humans=",get_human_count())
			return
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)

func _peer_disconnected(peer_id: int) -> void:
	if network_role != "host" or not _peer_slots.has(peer_id):
		return
	var slot: int = _peer_slots[peer_id]
	_peer_slots.erase(peer_id)
	_clear_slot_arrows(slot)
	actors[slot].configure(0,true,"Bot %d" % slot,world.spawn_points[slot])
	_broadcast_names()
	print("ARENA_BOT_RESTORED slot=",slot," humans=",get_human_count())

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

func _connected() -> void:
	multiplayer.multiplayer_peer.get_peer(1).set_timeout(32,2000,5000)
	_register.rpc_id(1,_player_name,_local_loadout())

@rpc("any_peer","call_remote","reliable")
func _register(player_name: String, loadout: Dictionary) -> void:
	if network_role != "host":
		return
	var sender := _sender_id()
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
	_next_swing_side = 0
	_camera_yaw = atan2(world.spawn_points[slot].x,world.spawn_points[slot].z)
	for actor in actors:
		actor.authoritative = false
		actor.visible = true
		actor.is_local = actor.slot == slot
		actor.predicting = actor.slot == slot
	actors[slot].interp_delay = 0.05
	actors[slot].revive()
	# The view clock names the tick this peer draws remote fighters at, which is
	# what its aim and swings are rewound to.
	_clock.configure(60.0,actors[(slot+1)%4].interp_delay)
	hud.show_match(_player_name,_endpoint)
	_bind_ui_rig()
	_set_cursor_free(false)
	print("ARENA_CLIENT_READY slot=",slot)

## Fighter names are static for a match, so they ride one reliable roster
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

func _physics_process(delta: float) -> void:
	if network_role == "offline":
		return
	if network_role == "client" and local_slot < 0:
		_join_elapsed += delta
		if _join_elapsed > 6.0:
			_connection_ended("Connection timed out. The host may be offline, full, or blocked by a firewall.")
		return
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
			# Prediction: this peer integrates the frame it is about to send, so
			# the fighter moves on the key, not a round trip later. The authority
			# receives every frame and acknowledges the newest one it consumed.
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
			actor.combat.lag_tick = server_tick
			actor.step(delta,actors,server_tick)
		_lag.record(server_tick,actors)
		if _send_elapsed >= SNAPSHOT_INTERVAL:
			# One fighter per datagram stays below ENet's MTU without fragmentation.
			for actor in actors:
				_receive_snapshot.rpc(server_tick,actor.slot,actor.snapshot())
				_snapshot_ticks[actor.slot] = server_tick
			_send_elapsed = fmod(_send_elapsed,SNAPSHOT_INTERVAL)

func _set_movement(slot: int, direction: Vector2, running: bool, aim: Variant = null, aim_tick: int = -1, aim_origin: Variant = null, seq: int = -1, view: int = -1, history: Array = []) -> void:
	if not direction.is_finite():
		return
	# Movement is never dropped because a frame carried no aim; only an aim
	# sample that fails validation leaves the previous point in place.
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
	actors[slot].combat.set_aim(point)
	if typeof(aim_origin) == TYPE_VECTOR3:
		var origin: Vector3 = aim_origin
		var ray: Vector3 = point-origin
		if origin.is_finite() and origin.distance_squared_to(actor.global_position) <= 144.0 \
				and ray.is_finite() and ray.length_squared() > 0.01:
			actors[slot].combat.set_camera_ray(origin,ray)
		else:
			actors[slot].combat.clear_camera_ray()
	else:
		actors[slot].combat.clear_camera_ray()
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
	if network_role != "client" or slot < 0 or slot >= 4 or tick <= _snapshot_ticks[slot]:
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

## The server tick this peer is currently drawing, which is what its aim and
## its swings must be judged against. Falls back to the newest acknowledgement
## before the first remote sample arrives.
func _view_tick() -> int:
	if _clock.newest_tick() >= 0:
		return _clock.render_tick()
	return maxi(0,_snapshot_ticks[local_slot])


## Arms one fighter's damage window with the rewind its owner needs: how far
## behind the host that peer was drawing when it pressed the button.
func _arm_lag(actor) -> void:
	actor.combat.lag_tick = server_tick
	actor.combat.lag_ticks = int(actor.lag_ticks(server_tick,MAX_LAG_TICKS)) if int(actor.peer_id) > 1 else 0


func send_action(action: String, value: Variant = null) -> void:
	if local_slot < 0:
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
		# Locomotion intents start on this frame; combat and kits stay
		# authoritative so a client can never guess its own parry or damage.
		actors[local_slot].predict_action(action,value)
		_action_input.rpc_id(1,action,value,_snapshot_ticks[local_slot],aim_origin)

@rpc("any_peer","call_remote","reliable")
func _action_input(action: String, value: Variant, aim_tick: Variant, aim_origin: Variant = null) -> void:
	if network_role != "host" or typeof(aim_tick) != TYPE_INT:
		return
	var sender := _sender_id()
	if _peer_slots.has(sender):
		var slot := int(_peer_slots[sender])
		if action == "loadout":
			# Kit changes are seat state, not aim; no snapshot rewind needed.
			if typeof(value) == TYPE_DICTIONARY:
				_apply_loadout(slot,value)
			return
		if aim_tick < 0 or aim_tick > _snapshot_ticks[slot]:
			return
		_apply_action(slot,action,value,aim_tick,aim_origin)

func _apply_action(slot: int, action: String, value: Variant, aim_tick: int = -1, aim_origin: Variant = null) -> void:
	var actor = actors[slot]
	if action == "loadout":
		# Same validated seat loader as the join handshake; unknown fields die here.
		if typeof(value) == TYPE_DICTIONARY:
			_apply_loadout(slot,value)
		return
	if not actor.alive:
		return
	# Every damage-capable intent carries the tick its owner was drawing, so the
	# host can rewind the targets the client actually saw.
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
						hud.flash_status(refusal,1.6)
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
	var arrow := Arrow.new()
	arrow.source_id = slot
	if authoritative:
		# A projectile resolves its impact long after launch, so it carries the
		# shooter's view lag instead of a fixed rewind tick.
		arrow.lag_comp = _lag
		arrow.lag_ticks = _shooter_lag(slot)
	arrow.hit_mask = 1 | 4 | 8
	arrow.authoritative_damage = authoritative
	add_child(arrow)
	var excluded: Array[RID] = [actors[slot].get_rid()]
	if is_instance_valid(actors[slot].rig.active_shield):
		excluded.append(actors[slot].rig.active_shield.get_rid())
	arrow.launch(origin,direction,speed,damage,excluded,visual_origin,pierce_count)
	for index in range(projectiles.size()-1,-1,-1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(arrow)
	if projectiles.size() > 128:
		projectiles.pop_front().queue_free()
	if slot == local_slot:
		audio.play_sound("release")

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
			_arena_ability_shots(actor, definition, index, damage, authoritative)
		"projectile":
			_arena_ability_spell(actor, definition, damage, authoritative)
		"backstab":
			_arena_ability_backstab(actor, cue, damage, authoritative)
		"melee_arc", "melee_ring":
			_arena_ability_melee(actor, definition, cue, index, damage, authoritative)


func _arena_ability_shots(actor, definition: Dictionary, index: int,
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


func _arena_ability_spell(actor, definition: Dictionary, damage: float,
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
	spell.hit_mask = 1 | 4 | 8
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


func _arena_ability_melee(actor, definition: Dictionary, cue: String, index: int,
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
func _arena_ability_backstab(actor, cue: String, damage: float, authoritative: bool) -> void:
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
	if network_role == "client" and slot >= 0 and slot < 4:
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
	var thrown := Thrown.new()
	thrown.source_id = slot
	thrown.weapon = weapon_name
	thrown.weapon_index = weapon_index
	thrown.blade_length = float(Archer.DAGGER_DATA.length) if weapon_name == "dagger" else float(Archer.SWORD_DATA[clampi(weapon_index,0,2)].length)
	thrown.hit_mask = 1 | 4
	thrown.authoritative_damage = authoritative
	add_child(thrown)
	var excluded: Array[RID] = [actors[slot].get_rid()]
	thrown.launch(origin,direction,speed,damage,excluded)
	for index in range(projectiles.size()-1,-1,-1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(thrown)
	if projectiles.size() > 128:
		projectiles.pop_front().queue_free()
	if slot == local_slot:
		audio.play_sound("release")

@rpc("authority","call_remote","reliable")
func _throw_event(slot: int, origin: Vector3, direction: Vector3, speed: float, weapon_name: String, weapon_index: int) -> void:
	if network_role == "client" and slot >= 0 and slot < 4:
		_spawn_thrown(slot,origin,direction,speed,weapon_name,weapon_index,0.0,false)

func _on_clash(position: Vector3) -> void:
	if network_role != "host":
		return
	Combat.spawn_impact(self,position,"clash")
	audio.play_sound("clang")
	_clash_event.rpc(position)

func _on_defense_resolved(defender_slot: int, position: Vector3, parried: bool) -> void:
	if network_role != "host":
		return
	Combat.spawn_impact(self,position,"parry" if parried else "block")
	audio.play_sound("parry" if parried else "block")
	_defense_event.rpc(defender_slot,position,parried)

@rpc("authority","call_remote","reliable")
func _defense_event(_defender_slot: int, position: Vector3, parried: bool) -> void:
	if network_role != "client":
		return
	Combat.spawn_impact(self,position,"parry" if parried else "block")
	audio.play_sound("parry" if parried else "block")

@rpc("authority","call_remote","unreliable")
func _clash_event(position: Vector3) -> void:
	if network_role != "client":
		return
	Combat.spawn_impact(self,position,"clash")
	audio.play_sound("clang")

func _on_killed(slot: int, source: int) -> void:
	if network_role == "host" and source >= 0 and source < 4 and source != slot:
		actors[source].kills += 1
		actors[source].apply_kill_refill()
		print("ARENA_KILL source=",source," victim=",slot)

func _process(delta: float) -> void:
	if local_slot < 0:
		return
	var actor = actors[local_slot]
	if not actor.alive and (_peek_held or _mouse_drawing or _throw_held):
		_peek_held = false
		_cancel_draw_input()
	_shoulder_camera.update(delta)
	_update_game_camera()
	var rows: Array[Dictionary] = []
	for fighter in actors:
		rows.append({"slot":fighter.slot,"name":fighter.display_name,"bot":fighter.is_bot,"health":fighter.health,"kills":fighter.kills,"deaths":fighter.deaths})
	hud.update_match({"players":rows,"local_slot":local_slot,"health":actor.health,"movement":actor.combat.movement_mode,
		"attack_interval":actor.combat.get_attack_interval(),"attack_progress":actor.combat.attack_progress,
		"phase":actor.rig.phase,"phase_time":actor.rig._phase_time,"draw":actor.rig.draw_amount,"bow":actor.rig.bow_index,"armor":actor.rig.armor_bits(),"sword":actor.rig.sword_index,"weapon":actor.rig.weapon,"respawn":actor.respawn,
		"shield":actor.rig.shield_equipped,
		"left_melee":actor.rig.melee_progress_for("left"),"right_melee":actor.rig.melee_progress_for("right"),
		"blocking":actor.combat.blocking,"parry":actor.authoritative and actor.combat.blocking and not actor.rig.shield_equipped and actor.combat.block_time <= Combat.PARRY_WINDOW,
		"attack_parry":actor.rig.weapon == "dual" and actor.rig.in_strike_window(),
		"ability":actor.ability.hud_state(0),"ability_off":actor.ability.hud_state(1),
		"ability_trinket":actor.ability.hud_state(2),
		"max_health":actor.max_health})
	hud.update_cover(actor.cover.active,actor.cover.low,actor.cover.peeking,_shoulder_camera.side,actor.cover.crouched,actor.rig.slide_progress >= 0.0)
	hud.reticle_visible = actor.alive and not _cursor_free
	hud.reticle = get_viewport().get_visible_rect().size * 0.5

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
	_cancel_draw_input()
	_peek_held = false
	_send_peek_input()
	_set_cursor_free(true)

func _on_ui_closed() -> void:
	# Closing must not recapture the pointer in the lobby or after a disconnect.
	if network_role == "offline" or local_slot < 0:
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
		hud.flash_status(str(result.get("message", "No quick swap set.")))
		return
	_cancel_draw_input()
	_on_ui_loadout_changed()
	audio.play_sound("equip")
	hud.flash_status(str(result.get("message", "Swapped weapons.")),1.5)

func _crosshair_aim() -> Vector3:
	_update_game_camera()
	var center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	_aim_origin = ray_origin
	_aim_origin_valid = true
	# Match frontier: shoulder and bow poses must not move the start past a target.
	var actor = actors[local_slot]
	var aim_anchor: Vector3 = actor.global_position + Vector3.UP*actor.cover.camera_height()
	var actor_depth := maxf(0.0,(aim_anchor-ray_origin).dot(ray_direction))
	_query.from = ray_origin + ray_direction*actor_depth
	_query.to = ray_origin + ray_direction*120.0
	# Skip only the cover this fighter is posted against, on host and replica.
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
	# F8 diagnostics are not match input: they work in the lobby too.
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
			KEY_TAB: _quick_swap()
			KEY_6: send_action("consume","bandage")
			KEY_7: send_action("consume","potion")
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
	multiplayer.multiplayer_peer.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
