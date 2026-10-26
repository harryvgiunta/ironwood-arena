extends RefCounted
## One frame-accurate profiler for the frontier, the arena and the delve.
##
## Godot's editor profiler measures whole script functions but needs the editor
## running, cannot be scripted headless, and reports per-call samples rather
## than the aggregate this project needs: "which line costs the most across one
## hundred simultaneous mobs in a single second". So the hot entry points call
## `begin(name)`/`end()` and every call of that name folds into one bucket.
##
## Cost when disabled is a single static-var read per call. When enabled each
## pair is two `Time.get_ticks_usec()` reads, a dictionary lookup and a stack
## push/pop; the instrumented scopes are frame entry points, not per-vertex
## loops, so the overhead stays under a percent of the frame.
##
## Scopes nest. A scope reports both `total` (inclusive of children) and `self`
## (its own body), so a wrapped `_physics_process` can be split into the steps
## that actually cost time without touching the engine.

## One row per scope name, index-stable for the lifetime of the process.
static var _index: Dictionary = {}
static var _names := PackedStringArray()
static var _total := PackedInt64Array()
static var _own := PackedInt64Array()
static var _calls := PackedInt32Array()
static var _peak := PackedInt64Array()

## The open scope stack. Parallel arrays rather than an Array of Arrays so a
## begin/end pair allocates nothing.
static var _open_name := PackedInt64Array()
static var _open_start := PackedInt64Array()
static var _open_child := PackedInt64Array()
static var _depth := 0

## Master switch. `Perf` (autoload-free) is enabled by the harness or by the
## `IRONWOOD_PERF` environment variable, never by normal play.
static var enabled := false
## Whether the scopes themselves run. Kept separate from `enabled` so a
## benchmark can measure the game with the frame clock still running: a
## begin/end pair per mob per frame is not free, and publishing a number that
## includes the profiler's own cost would be dishonest.
static var scopes := true
## Frames the samples cover; the report divides by this to get a per-frame cost.
static var frames := 0
## Wall time of every measured frame, keyed `frame:<label>`.
static var frame_us := 0
## Every measured frame's wall time. The average is dragged around by the
## spikes a scene change or a spawn causes; the median is what a player sits
## at, and it is what the published numbers quote.
static var frame_samples := PackedInt64Array()
static var frame_peak_us := 0
static var _last_tick := 0
## Frames that began while a scope from the previous frame was still open. A
## non-zero count means a `begin` is missing its `end`, which silently nests
## everything after it; the report shouts about it rather than quietly
## attributing time to the wrong parent.
static var imbalanced := 0


static func reset() -> void:
	_index.clear()
	_names = PackedStringArray()
	_total = PackedInt64Array()
	_own = PackedInt64Array()
	_calls = PackedInt32Array()
	_peak = PackedInt64Array()
	_open_name = PackedInt64Array()
	_open_start = PackedInt64Array()
	_open_child = PackedInt64Array()
	_depth = 0
	frames = 0
	imbalanced = 0
	frame_samples = PackedInt64Array()
	frame_us = 0
	frame_peak_us = 0
	_last_tick = 0


static func _slot(name: String) -> int:
	var found: int = _index.get(name, -1)
	if found >= 0:
		return found
	var next := _names.size()
	_index[name] = next
	_names.append(name)
	_total.append(0)
	_own.append(0)
	_calls.append(0)
	_peak.append(0)
	return next


static func begin(name: String) -> void:
	if not enabled or not scopes:
		return
	if _depth >= _open_name.size():
		_open_name.resize(_depth + 16)
		_open_start.resize(_depth + 16)
		_open_child.resize(_depth + 16)
	_open_name[_depth] = _slot(name)
	_open_start[_depth] = Time.get_ticks_usec()
	_open_child[_depth] = 0
	_depth += 1


static func end() -> void:
	if not enabled or not scopes or _depth <= 0:
		return
	_depth -= 1
	var spent := Time.get_ticks_usec() - _open_start[_depth]
	var name_index := _open_name[_depth]
	var children := _open_child[_depth]
	_total[name_index] += spent
	_own[name_index] += spent - children
	_calls[name_index] += 1
	if spent > _peak[name_index]:
		_peak[name_index] = spent
	if _depth > 0:
		_open_child[_depth - 1] += spent


## Wraps a whole measured frame so the report has a denominator and can name
## the frame rate the numbers were taken at. The harness calls it once per
## physics tick; the gap between calls is the frame's real cost on this
## machine, engine work included.
static func tick() -> void:
	if not enabled:
		return
	if _depth != 0:
		imbalanced += 1
		_depth = 0
	var now := Time.get_ticks_usec()
	if _last_tick > 0:
		var spent := now - _last_tick
		frames += 1
		frame_us += spent
		if frame_samples.size() < 8192:
			frame_samples.append(spent)
		if spent > frame_peak_us:
			frame_peak_us = spent
	_last_tick = now


## Just the named scopes, with their mean cost. Used by the spawn benchmark,
## which cares about one frame's inside rather than the whole window.
static func summary(prefix: String) -> String:
	var lines := PackedStringArray()
	for slot in _names.size():
		if not _names[slot].begins_with(prefix) or _calls[slot] == 0:
			continue
		lines.append("%-22s total=%8.2fms calls=%5d avg=%7.1fµs peak=%6dµs" % [
			_names[slot],
			float(_total[slot]) / 1000.0,
			_calls[slot],
			float(_total[slot]) / float(_calls[slot]),
			_peak[slot]])
	return "\n".join(lines)


## Column-aligned table, heaviest first. `budget_us` is the frame time the
## percentages are taken against; pass 0 to use the measured frame average.
static func report(title: String, budget_us: int = 0) -> String:
	var count := _names.size()
	var order := range(count)
	order.sort_custom(func(a: int, b: int) -> bool: return _total[a] > _total[b])
	var scale := frames if frames > 0 else 1
	var denominator := budget_us if budget_us > 0 else (frame_us / scale)
	if denominator <= 0:
		denominator = 1
	var lines := PackedStringArray()
	lines.append("")
	lines.append("=== %s ===" % title)
	lines.append("frames=%d  median frame=%.2f ms  avg frame=%.2f ms  worst frame=%.2f ms  imbalanced=%d" % [
		frames, _median_ms(), float(frame_us) / float(scale) / 1000.0,
		float(frame_peak_us) / 1000.0, imbalanced])
	if count == 0:
		lines.append("(no scopes: frame clock only)")
		lines.append("")
		return "\n".join(lines)
	lines.append("%-26s %10s %9s %8s %10s %9s %8s" % [
		"scope", "total ms", "ms/frame", "share", "calls", "calls/fr", "peak µs"])
	lines.append("-".repeat(88))
	for slot in order:
		var total := _total[slot]
		if total <= 0:
			continue
		lines.append("%-26s %10.2f %9.3f %7.1f%% %10d %9.1f %8d" % [
			_names[slot],
			float(total) / 1000.0,
			float(total) / float(scale) / 1000.0,
			100.0 * float(total) / float(denominator * scale),
			_calls[slot],
			float(_calls[slot]) / float(scale),
			_peak[slot]])
	lines.append("")
	return "\n".join(lines)


## Machine-readable rows for diffing two runs.
static func rows() -> Array:
	var out: Array = []
	for slot in _names.size():
		if _total[slot] <= 0:
			continue
		out.append({
			"scope": _names[slot],
			"total_us": _total[slot],
			"own_us": _own[slot],
			"calls": _calls[slot],
			"peak_us": _peak[slot],
		})
	return out


static func _median_ms() -> float:
	if frame_samples.is_empty():
		return 0.0
	var sorted := frame_samples.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2]) / 1000.0
