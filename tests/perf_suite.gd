extends SceneTree
## Perf suite for the frontier: what a frame costs, and where the time goes.
##
## Runs the real `main.tscn` headless under `--fixed-fps 60`, so every iteration
## simulates exactly one sixtieth of a second and the wall-clock cost of that
## iteration is the frame's real price on this machine. Costs are therefore
## comparable across runs, and the per-scope rows add up to the frame.
##
##   & $Godot --headless --path . --fixed-fps 60 \
##       --script res://tests/perf_suite.gd -- --mode=crowd --mobs=100
##
## Modes:
##   baseline  the shipped frontier, idle: the control.
##   spawn     `--mobs` devils added in one frame, then the frames that follow —
##             the "monsters spawn and the game stalls" symptom.
##   crowd     `--mobs` devils packed around an invulnerable ranger and fighting:
##             "sitting in a room with a hundred monsters".
##   net       the host replication path over that crowd: snapshot building,
##             datagram packing and the lag history.
##   all       baseline, spawn, crowd and net in one process.
##
## Every mode prints one report per measured window.

const Perf = preload("res://scripts/perf_probe.gd")
const DevilMob = preload("res://scripts/devil_mob.gd")
const NetLimits = preload("res://scripts/net_limits.gd")
const LagCompensation = preload("res://scripts/lag_compensation.gd")

const MOBS := ["hell_goat", "succubus", "spawn", "beast", "gargoyle"]
## The open northern frontier, well outside the town's safe ring so every mob
## in the crowd is free to hunt.
const CROWD_AT := Vector2(0.0, -78.0)
## The host's mob send cadence: `ENEMY_TICK` is four physics ticks.
const NET_STRIDE := 4

var main: Node
var world: Node3D
var mode := "crowd"
var mob_count := 100
var _explicit_mobs := false
## A/B switch: mobs that do not collide with each other, only with the world
## and the player. Used to price the crowd's broadphase.
var _isolated := false
## A/B switch: mobs that collide with nothing at all, to price the physics
## query itself against the per-body engine overhead.
var _ghost := false
## A/B switches for pricing what lives outside the script: the skinned rig and
## the collision shape.
var _no_visual := false
var _no_shape := false
## Upper bound on what the animated rigs cost: every `AnimationPlayer` in the
## scene stops writing tracks once the window opens.
var _freeze_all := false
## Turns the added bodies into inert replicas: they keep their collision shapes
## and rigs but run no AI, which prices what one hundred bodies cost on their
## own.
var _stub := false
## Render-side attribution: the shadow pass and the ground-cover batches are
## the two big primitive sources a graphics cut would target.
var _no_shadow := false
var _no_grass := false
## Shadow draw distance override: the sun's coverage is the single biggest
## lever on draw calls.
var _shadow_distance := 0.0
## Viewport anti-aliasing level, so its cost can be priced. -1 leaves the
## project setting alone.
var _msaa := -1
## Frees every frontier mob after boot: the world's own frame cost, which is
## the floor no mob optimisation can go below.
var _no_mobs := false
## Runs the frame clock without the scopes, which is what the published numbers
## should be: the profiler's own begin/end pairs cost something, and the
## per-mob ones are the largest single contributor.
var _no_scopes := false
## Keep only the `--keep` nearest frontier mobs and free the rest: the
## population curve, for deciding how many monsters a frame budget buys.
var _keep := -1
## Stops every mob's tick, leaving its node, body and rig: separates "the body
## exists" from "the body does anything". One `set_physics_process` per mob at
## boot — a per-frame version costs more than the tick it suppresses.
var _sleep_all := false
## Frees every mob's presentation subtree, leaving the body: prices the rigs a
## crowd carries whether or not the camera is looking at them.
var _no_rigs := false
## Comma-separated node-name prefixes to hide, for pricing world subsystems in
## the windowed build: `--hide=TreeLeaves_,Grass_`.
var _hide := ""
## Foliage still draws but stops writing to the shadow map.
var _leaf_shadows_off := false
## Runs the suite against a tree from before the optimisation work, whose mobs
## own their physics step and whose snapshots are dictionaries. The same file
## runs on both sides so the two numbers are directly comparable.
var _legacy := false
## Frame budget in milliseconds, applied to every measured window's median.
## The 60 Hz frame is 16.67; anything at or under this is a pass. `--budget=0`
## turns the gate off for pure exploration.
var _budget_ms := 16.6
var _failed := 0
var seconds := 6.0
var spawned: Array = []
var _steps: Array = []
var _step := 0
var _left := 0.0
var _waiting := false
var _ticks := 0
var _spawn_gaps := PackedInt64Array()
var _packed_sizes: Array = []
var _lag := LagCompensation.new()


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--mode="):
			mode = text.substr(7)
		elif text.begins_with("--mobs="):
			mob_count = maxi(0, text.substr(7).to_int())
			_explicit_mobs = true
		elif text.begins_with("--novisual="):
			_no_visual = text.substr(11).to_int() != 0
		elif text.begins_with("--noshadow="):
			_no_shadow = text.substr(11).to_int() != 0
		elif text.begins_with("--legacy="):
			_legacy = text.substr(9).to_int() != 0
		elif text.begins_with("--budget="):
			_budget_ms = maxf(0.0, text.substr(9).to_float())
		elif text.begins_with("--leafshadow="):
			_leaf_shadows_off = text.substr(13).to_int() == 0
		elif text.begins_with("--hide="):
			_hide = text.substr(7)
		elif text.begins_with("--norigs="):
			_no_rigs = text.substr(9).to_int() != 0
		elif text.begins_with("--sleepall="):
			_sleep_all = text.substr(11).to_int() != 0
		elif text.begins_with("--keep="):
			_keep = maxi(0, text.substr(7).to_int())
		elif text.begins_with("--noscopes="):
			_no_scopes = text.substr(11).to_int() != 0
		elif text.begins_with("--nomobs="):
			_no_mobs = text.substr(9).to_int() != 0
		elif text.begins_with("--msaa="):
			_msaa = text.substr(7).to_int()
		elif text.begins_with("--shadowdist="):
			_shadow_distance = text.substr(13).to_float()
		elif text.begins_with("--nograss="):
			_no_grass = text.substr(10).to_int() != 0
		elif text.begins_with("--stub="):
			_stub = text.substr(7).to_int() != 0
		elif text.begins_with("--freezeall="):
			_freeze_all = text.substr(12).to_int() != 0
		elif text.begins_with("--noshape="):
			_no_shape = text.substr(10).to_int() != 0
		elif text.begins_with("--ghost="):
			_ghost = text.substr(8).to_int() != 0
		elif text.begins_with("--isolated="):
			_isolated = text.substr(11).to_int() != 0
		elif text.begins_with("--seconds="):
			seconds = maxf(0.5, text.substr(10).to_float())
	# Each mode has its own default load: thirty is the spawn-symptom number,
	# a hundred is the room.
	if not _explicit_mobs:
		mob_count = 30 if mode == "spawn" else 100
	Perf.enabled = true
	Perf.scopes = not _no_scopes
	Perf.reset()
	# The suite measures CPU and GPU submission cost, so the frame must not be
	# capped by the display: a vsynced 60 Hz run would report the monitor's
	# refresh rate whatever the game costs.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	call_deferred("_boot")


func _boot() -> void:
	main = load("res://main.tscn").instantiate()
	main.name = "Ironwood"
	root.add_child(main)
	world = main.world
	for _index in 20:
		await physics_frame
	print("PERF boot mobs=%d nodes=%d" % [main.enemies.size(), _count(root)])
	_print_machine()
	# The world builds once, before the first measured window: its cost is a
	# load-time number, not a frame-time one.
	print(Perf.summary("world."))
	if not _hide.is_empty():
		var prefixes := _hide.split(",", false)
		var hidden := 0
		for node in root.find_children("*", "Node3D", true, false):
			var label := String(node.name)
			for prefix in prefixes:
				if label.begins_with(prefix):
					(node as Node3D).visible = false
					hidden += 1
					break
		print("PERF hidden nodes=%d prefixes=%s" % [hidden, _hide])
	if _no_rigs:
		for enemy in main.enemies:
			if not is_instance_valid(enemy):
				continue
			# A clone owns an Archer rig; freeing it breaks every caller.
			if enemy.has_method("configure") and enemy.get("bounds") != null:
				continue
			var body = enemy.get("_body")
			if is_instance_valid(body):
				body.free()
			enemy.set("_body", null)
			enemy.set("_visual", null)
			enemy.set("_wolf", null)
			enemy.set("_devil", null)
			enemy.set("_presenting", false)
	if _sleep_all:
		# One-time, not per frame: a per-frame `set()` on every mob costs more
		# than the tick it suppresses.
		for enemy in main.enemies:
			if is_instance_valid(enemy):
				enemy.set_physics_process(false)
	if _keep >= 0:
		var ordered := []
		for enemy in main.enemies:
			if is_instance_valid(enemy):
				ordered.append(enemy)
		ordered.sort_custom(func(a, b) -> bool:
			return a.global_position.distance_squared_to(main.player.global_position) \
				< b.global_position.distance_squared_to(main.player.global_position))
		for index in range(_keep, ordered.size()):
			var doomed = ordered[index]
			if main._enemies_by_index.has(doomed):
				main._enemies_by_index[main._enemies_by_index.find(doomed)] = null
			main.enemies.erase(doomed)
			doomed.free()
	if _no_mobs:
		for enemy in main.enemies:
			if is_instance_valid(enemy):
				enemy.free()
		main.enemies.clear()
		main._enemies_by_index.clear()
	_apply_render_cuts()
	_steps = _plan()
	if _steps.is_empty():
		quit(0)
		return
	_begin_step()


func _plan() -> Array:
	match mode:
		"baseline":
			return [{"label": "baseline", "setup": Callable(), "seconds": seconds}]
		"spawn":
			return [{"label": "spawn", "setup": Callable(self, "_setup_spawn"), "seconds": 3.0}]
		"crowd":
			return [{"label": "crowd", "setup": Callable(self, "_setup_crowd"), "seconds": seconds}]
		"net":
			return [{"label": "net", "setup": Callable(self, "_setup_net"), "seconds": seconds}]
		"all":
			return [
				{"label": "baseline", "setup": Callable(), "seconds": seconds},
				{"label": "spawn", "setup": Callable(self, "_setup_spawn"), "seconds": 3.0},
				{"label": "crowd", "setup": Callable(self, "_setup_crowd"), "seconds": seconds},
				{"label": "net", "setup": Callable(self, "_setup_net"), "seconds": seconds},
			]
	return []


func _begin_step() -> void:
	if _step >= _steps.size():
		# The gate: a run that leaves a window over budget fails, so this is a
		# regression check rather than only a report.
		if _failed > 0:
			print("PERF GATE FAIL windows=%d budget=%.2f ms" % [_failed, _budget_ms])
			quit(1)
			return
		print("PERF GATE PASS budget=%.2f ms" % _budget_ms)
		quit(0)
		return
	var step: Dictionary = _steps[_step]
	var setup: Callable = step.setup
	if setup.is_valid():
		var started := Time.get_ticks_usec()
		await setup.call()
		print("PERF setup %s: %.1f ms wall" % [
			str(step.label), float(Time.get_ticks_usec() - started) / 1000.0])
	Perf.reset()
	_packed_sizes.clear()
	if _freeze_all:
		for player in root.find_children("*", "AnimationPlayer", true, false):
			(player as AnimationPlayer).pause()
	_left = float(step.seconds)
	_ticks = 0
	_waiting = true
	print("PERF measure %s mobs=%d extra=%d" % [
		str(step.label), main.enemies.size(), spawned.size()])


var _last_frame_tick := 0


func _physics_process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if _last_frame_tick > 0 and now - _last_frame_tick > 40 and _waiting:
		print("PERF slow frame %d ms open=%s step=%s" % [
			now - _last_frame_tick, Perf.open_path(), str(_steps[_step].label)])
	_last_frame_tick = now
	Perf.tick()
	if not _waiting:
		return false
	_ticks += 1
	_keep_alive()
	if _ticks % NET_STRIDE == 0:
		_net_pass()
	_left -= 1.0 / 60.0
	if _left > 0.0:
		return false
	_finish_step()
	return false


func _finish_step() -> void:
	_waiting = false
	var step: Dictionary = _steps[_step]
	print(Perf.report("FRONTIER/%s mobs=%d nodes=%d" % [
		str(step.label), main.enemies.size(), _count(root)]))
	_print_render()
	if _budget_ms > 0.0:
		var median := Perf._median_ms()
		var ok := median <= _budget_ms
		if not ok:
			_failed += 1
		print("PERF budget %s: median %.2f ms of %.2f ms %s" % [
			str(step.label), median, _budget_ms, "PASS" if ok else "FAIL"])
	if str(step.label) == "spawn":
		_print_gaps("spawn")
	if str(step.label) == "net":
		_print_packing()
	_step += 1
	_begin_step()


# --- setup ------------------------------------------------------------------

## The spawn symptom: bodies instantiated and added in one frame.
func _setup_spawn() -> void:
	var count := mob_count if mode == "spawn" else 30
	Perf.reset()
	var started := Time.get_ticks_usec()
	for index in count:
		_add_mob(index, CROWD_AT, 7.0)
	var spent := Time.get_ticks_usec() - started
	print("PERF spawned %d devils in one frame: %.2f ms total, %.3f ms each" % [
		count, float(spent) / 1000.0, float(spent) / 1000.0 / float(maxi(1, count))])
	print(Perf.summary("spawn."))
	# The frames right after are the second half of the symptom: collision,
	# skeleton and animation setup all land on the next step.
	_spawn_gaps = PackedInt64Array()
	var previous := Time.get_ticks_usec()
	for _index in 40:
		await physics_frame
		var now := Time.get_ticks_usec()
		_spawn_gaps.append(now - previous)
		previous = now


## The hundred-mob room: every devil standing off the same ranger, reach
## apart, with the ranger held at full health so the fight never ends.
func _setup_crowd() -> void:
	_park_ranger()
	Perf.reset()
	var started := Time.get_ticks_usec()
	for index in mob_count:
		_add_mob(index, CROWD_AT, 3.0 + float(index % 7) * 1.9)
	print("PERF crowd spawn %d devils: %.2f ms total, %.3f ms each" % [
		mob_count, float(Time.get_ticks_usec() - started) / 1000.0,
		float(Time.get_ticks_usec() - started) / 1000.0 / float(maxi(1, mob_count))])
	print(Perf.summary("spawn."))
	for _index in 12:
		await physics_frame


func _setup_net() -> void:
	if spawned.size() < mob_count:
		_park_ranger()
		for index in mob_count:
			_add_mob(index, CROWD_AT, 3.0 + float(index % 7) * 1.9)
		for _index in 12:
			await physics_frame


func _park_ranger() -> void:
	var height: float = world.terrain_height(CROWD_AT.x, CROWD_AT.y)
	main.player.global_position = Vector3(CROWD_AT.x, height + 1.2, CROWD_AT.y)
	main.player.velocity = Vector3.ZERO
	main.max_health = 100000.0
	main.health = 100000.0


func _add_mob(index: int, centre: Vector2, radius: float) -> void:
	var mob := DevilMob.new()
	mob.mob_id = MOBS[index % MOBS.size()]
	var angle := float(index) * 2.399963
	var x: float = centre.x + cos(angle) * radius
	var z: float = centre.y + sin(angle) * radius
	mob.position = Vector3(x, world.terrain_height(x, z) + 0.12, z)
	mob.player = main.player
	if not _legacy:
		mob.terrain = world
	mob.safe_center = world.player_spawn
	main.add_child(mob)
	mob.defeated.connect(main._on_enemy_defeated)
	mob.attacked.connect(main._on_enemy_attack)
	if _stub:
		mob.replica = true
	if _no_shape:
		for child in mob.get_children():
			if child is CollisionShape3D:
				child.queue_free()
	if _no_visual:
		# Stop the engine side of the rig: the animation tracks, the skeleton
		# pose update and the skinned meshes, leaving the gameplay node intact.
		for player in mob.find_children("*", "AnimationPlayer", true, false):
			(player as AnimationPlayer).pause()
		for body in mob.get_children():
			if body is Node3D:
				(body as Node3D).visible = false
	if _ghost:
		mob.collision_layer = 0
		mob.collision_mask = 0
	elif _isolated:
		mob.collision_layer = 0
		mob.collision_mask = 1
	main.enemies.append(mob)
	if not _legacy:
		main._enemies_by_index.append(mob)
	spawned.append(mob)


func _keep_alive() -> void:
	main.health = main.max_health


# --- the host replication pass, isolated ------------------------------------

## What the host does for every enemy inside the relevance radius on each mob
## send tick: build the snapshot, encode it to size its datagram, and keep the
## one second of lag history. Run here rather than through `rpc()` so the
## measurement is CPU cost alone; the socket path has its own suite.
func _net_pass() -> void:
	Perf.begin("net.lag")
	_lag.record(main.server_tick, main._enemies_by_index)
	Perf.end()
	Perf.begin("net.build")
	var states: Array = []
	for index in main._enemies_by_index.size():
		var enemy = main._enemies_by_index[index]
		if not is_instance_valid(enemy) or not main._enemy_relevant(enemy):
			continue
		if _legacy:
			var state: Dictionary = enemy.snapshot()
			state["i"] = index
			states.append(state)
		else:
			states.append(enemy.snapshot(index))
	Perf.end()
	Perf.begin("net.pack")
	var batches: Array = NetLimits.batches(states, [main.server_tick])
	Perf.end()
	if _packed_sizes.size() < 64:
		_packed_sizes.append({
			"mobs": states.size(),
			"batches": batches.size(),
			"bytes": NetLimits.message_size([main.server_tick] + batches),
		})


# --- reporting --------------------------------------------------------------

func _print_gaps(label: String) -> void:
	if _spawn_gaps.is_empty():
		return
	var sorted := _spawn_gaps.duplicate()
	sorted.sort()
	var over := 0
	for gap in _spawn_gaps:
		if gap > 16667:
			over += 1
	print("PERF %s aftermath: median=%.2f ms worst=%.2f ms frames_over_16.6ms=%d of %d" % [
		label, float(sorted[sorted.size() / 2]) / 1000.0,
		float(sorted[-1]) / 1000.0, over, _spawn_gaps.size()])


func _print_packing() -> void:
	if _packed_sizes.is_empty():
		return
	var entry: Dictionary = _packed_sizes[-1]
	print("PERF net packing: mobs=%d datagrams=%d bytes=%d per_send upload=%d B/s tick=%d" % [
		int(entry.mobs), int(entry.batches), int(entry.bytes),
		int(entry.bytes) * int(round(1.0 / 0.0667)), main.server_tick])


## The render side: draw calls and primitives are what a frame costs before any
## script runs, and they only exist with a real device.
func _print_render() -> void:
	print("PERF render draw_calls=%d primitives=%d objects=%d fps=%.1f hud_nodes=%d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		Performance.get_monitor(Performance.TIME_FPS),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])


func _print_machine() -> void:
	print("PERF machine cpu=%s cores=%d physics_monitor=%.2fms process_monitor=%.2fms" % [
		OS.get_processor_name(), OS.get_processor_count(),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


## Applies the render-side cuts once, before measuring.
func _apply_render_cuts() -> void:
	if _no_shadow:
		for light in root.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).shadow_enabled = false
	if _leaf_shadows_off:
		var toned := 0
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			var label := String(node.name)
			if label.begins_with("TreeLeaves_") or label.begins_with("BackdropLeaves_"):
				(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				toned += 1
		print("PERF leaf shadows off nodes=%d" % toned)
	if _msaa >= 0:
		root.get_viewport().msaa_3d = _msaa
	if _shadow_distance > 0.0:
		for light in root.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).directional_shadow_max_distance = _shadow_distance
	if _no_grass:
		for node in root.find_children("*", "Node3D", true, false):
			var label := String(node.name).to_lower()
			if label.contains("grass") or label.contains("cover") or label.contains("fern"):
				(node as Node3D).visible = false
