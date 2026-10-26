extends Control
## F8: the frame a player is actually getting, split into the parts that make
## it. Off by default; nothing on this screen is measured until it is opened.
##
## The top block is the frame itself: measured frame time, fps, the worst frame
## and the 1% low in the recent window, the engine's process and physics
## clocks, draw calls/primitives/objects, scene and memory counts. Below it are
## the instrumented scopes (`Perf`), which is what turns "the frame is slow"
## into "this step is slow": the same table `docs/performance.md` quotes, at
## whatever the game is doing right now.
##
## The scopes are compiled into the hot entry points (`main`, mob AI, the rigs,
## the network pass) but cost one static-var read when disabled, so opening
## this is the only time normal play pays for them. Closing restores the switch
## the harness may have set.

const Perf = preload("res://scripts/perf_probe.gd")

## Seconds between text rebuilds. Faster than this and the numbers move too much
## to read; slower and a turn of the camera is not visible in them.
const REFRESH := 0.25
## Frame samples the fps/worst/1%-low figures are taken over.
const WINDOW := 180
## Scope rows shown, heaviest first.
const SCOPE_ROWS := 12

var _panel: Panel
var _label: Label
var _elapsed := 0.0
var _frame_ms := PackedFloat32Array()
var _context := PackedStringArray()
var _perf_was_enabled := false
var _perf_was_scoped := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Courier New"])
	_panel = Panel.new()
	_panel.position = Vector2(24.0, 122.0)
	_panel.size = Vector2(560.0, 440.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.06, 0.88)
	style.border_color = Color("3c5358")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_label = Label.new()
	_label.position = Vector2(12.0, 10.0)
	_label.size = Vector2(536.0, 420.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("d9e4e0"))
	_panel.add_child(_label)


func is_open() -> bool:
	return visible


func toggle() -> void:
	set_open(not visible)


func set_open(value: bool) -> void:
	if value == visible:
		return
	visible = value
	if value:
		_perf_was_enabled = Perf.enabled
		_perf_was_scoped = Perf.scopes
		Perf.enabled = true
		Perf.scopes = true
		Perf.reset()
		_frame_ms = PackedFloat32Array()
		_elapsed = REFRESH
		_label.text = "measuring..."
	else:
		Perf.enabled = _perf_was_enabled
		Perf.scopes = _perf_was_scoped


## Lines the owning scene contributes: what it knows that the engine does not.
## Kept out of the overlay so the frontier, the arena and the delve share one
## instrument; a scene that has nothing to add simply does not call this.
func set_context(lines: PackedStringArray) -> void:
	_context = lines


func _process(delta: float) -> void:
	if not visible:
		return
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > WINDOW:
		_frame_ms.remove_at(0)
	# The frame clock needs every frame; the table is rebuilt on the refresh.
	Perf.tick()
	_elapsed += delta
	if _elapsed < REFRESH:
		return
	_elapsed = 0.0
	_label.text = _compose()
	# Start a fresh scope window whose denominator is the frames just reported.
	Perf.reset()


func _compose() -> String:
	var count := _frame_ms.size()
	var average := 0.0
	var worst := 0.0
	for value in _frame_ms:
		average += value
		worst = maxf(worst, value)
	if count > 0:
		average /= float(count)
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var low := sorted[0] if not sorted.is_empty() else 0.0
	if not sorted.is_empty():
		low = sorted[mini(sorted.size() - 1, int(float(sorted.size()) * 0.99))]
	var lines := PackedStringArray()
	lines.append("IRONWOOD PERFORMANCE                          F8  HIDE")
	lines.append("frame    %6.2f ms    %5.1f fps    worst %6.2f ms    1%% low %5.1f fps" % [
		average, _fps(average), worst, _fps(low)])
	lines.append("process  %6.2f ms (pacing)   physics %6.2f ms    ticks %d Hz" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Engine.physics_ticks_per_second])
	lines.append("render   %5d draws    %.2f M prims    %d objects" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	lines.append("scene    %d nodes    %d orphans    %d resources" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))])
	lines.append("memory   %.1f MB static    %.1f MB video" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	for line in _context:
		lines.append(line)
	lines.append("--- scopes: ms/frame, share of the frame ---")
	var rows := Perf.rows()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["total_us"]) > int(b["total_us"]))
	var frames := maxi(Perf.frames, 1)
	var denominator := maxf(float(Perf.frame_us), 1.0)
	var shown := 0
	for row: Dictionary in rows:
		if shown >= SCOPE_ROWS:
			break
		shown += 1
		lines.append("  %-20s %7.3f   %5.1f%%" % [
			str(row["scope"]),
			float(row["total_us"]) / float(frames) / 1000.0,
			100.0 * float(row["total_us"]) / denominator])
	if shown == 0:
		lines.append("  (no scope samples)")
	if Perf.imbalanced > 0:
		lines.append("  WARNING: %d unbalanced begin/end pairs" % Perf.imbalanced)
	return "\n".join(lines)


func _fps(milliseconds: float) -> float:
	return 1000.0 / maxf(milliseconds, 0.0001)
