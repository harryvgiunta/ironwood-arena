extends RefCounted
## Neighbour lookup for wilderness mobs, rebuilt once per physics frame.
##
## Every mob's spacing pass used to scan the whole `wild_mobs` group: with a
## hundred and seventy-five bodies that is thirty thousand distance tests and a
## fresh array per mob per frame, and it measured at four milliseconds — the
## second largest cost in the frontier after the physics steps. The same pass
## against a square-metre bucket grid reads the nine cells around the body
## instead, so a mob only looks at bodies that could possibly touch it.
##
## The grid is called by the mobs themselves (`gather`/`next_body`) rather than
## driving them, because a mob's push has to land inside its own movement step:
## one pass per frame, one cursor.

## Bucket size. A mob is 0.2–0.4 m across and separation reaches 1.35 m, so a
## four-metre bucket gives every candidate within reach of the nine-cell ring.
const CELL := 4.0
const ORIGIN := -160.0
const SIDE := 80

## Group every wilderness mob joins; the grid reads it once per frame.
const GROUP := "wild_mobs"

static var _head := PackedInt32Array()
static var _next := PackedInt32Array()
static var _bodies: Array = []
static var _frame := -1
static var _cursor := -1
static var _cx := 0
static var _cz := 0
static var _ring_x := -1
static var _ring_z := -1


## Rebuilds the grid if this frame has not been served yet.
static func refresh(tree: SceneTree) -> void:
	var now := Engine.get_physics_frames()
	if now == _frame:
		return
	_frame = now
	_bodies = tree.get_nodes_in_group(GROUP)
	if _head.size() != SIDE * SIDE:
		_head.resize(SIDE * SIDE)
		_head.fill(-1)
	else:
		_head.fill(-1)
	if _next.size() < _bodies.size():
		_next.resize(_bodies.size() + 64)
	for index in _bodies.size():
		var body := _bodies[index] as Node3D
		if body == null or not body.is_inside_tree():
			_next[index] = -1
			continue
		var at := body.global_position
		var cell := _cell_of(at.x, at.z)
		_next[index] = _head[cell]
		_head[cell] = index


static func _cell_of(x: float, z: float) -> int:
	var ix := clampi(int((x - ORIGIN) / CELL), 0, SIDE - 1)
	var iz := clampi(int((z - ORIGIN) / CELL), 0, SIDE - 1)
	return iz * SIDE + ix


## Starts a walk over the bodies near this point. `next_body()` returns them
## one at a time and null at the end; a mob must finish its walk before any
## other mob starts one.
static func gather(x: float, z: float) -> void:
	_cx = clampi(int((x - ORIGIN) / CELL), 0, SIDE - 1)
	_cz = clampi(int((z - ORIGIN) / CELL), 0, SIDE - 1)
	_ring_x = -1
	_ring_z = -1
	_cursor = -1


static func next_body() -> Node3D:
	while true:
		if _cursor >= 0:
			var current := _cursor
			_cursor = _next[current] if current < _next.size() else -1
			var body := _bodies[current] as Node3D if current < _bodies.size() else null
			if body != null and is_instance_valid(body):
				return body
			continue
		# Move to the next bucket of the nine-cell ring.
		_ring_x += 1
		if _ring_x > 1:
			_ring_x = -1
			_ring_z += 1
			if _ring_z > 1:
				return null
		var ix := clampi(_cx + _ring_x, 0, SIDE - 1)
		var iz := clampi(_cz + _ring_z, 0, SIDE - 1)
		_cursor = _head[iz * SIDE + ix]
	return null


## How many bodies the last `refresh` indexed. Benchmarks and tests read it;
## gameplay never needs it.
static func size() -> int:
	return _bodies.size()
