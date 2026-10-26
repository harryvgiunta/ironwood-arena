extends RefCounted
## How often a wilderness mob thinks.
##
## A mob's frame cost is nearly all per-tick: sight rays, the spacing walk, the
## state machine and the ground step. None of it needs sixty hertz. A devil
## walking at four metres per second covers six centimetres in a sixtieth of a
## second and twenty in a thirtieth, which no player can tell apart, while the
## frame it costs halves. So the mob families run their brains on a stride: the
## first person it catches every second frame, the middle distance every fourth,
## and the far frontier only often enough to notice a ranger arriving.
##
## The stride is chosen from the distance to the nearest ranger and applied by
## scaling delta, so a decimated tick integrates exactly the time it skipped:
## speeds, cooldowns and state timers stay in real time.
##
## Every tier is staggered by a per-mob phase, so a hundred mobs do not all
## think on the same frame and turn a smooth frame budget into a spike.

## Beyond this the rig stops animating altogether: the clip stops writing bone
## tracks and the body stops drawing. A walk cycle is not readable at that
## range through the trees, and the animation of every distant devil is roughly
## a third of a frontier frame.
const ANIMATE_RANGE := 45.0
## Inside this the rig animates every frame; between here and `ANIMATE_RANGE`
## it animates every other frame, which halves the bone work of every body that
## is not right in front of the player and reads identically at that distance.
const ANIMATE_NEAR := 12.0
## Metres to the nearest ranger at which each stride takes over.
const NEAR := 22.0
const MID := 55.0
## Physics ticks between ticks, per tier: 60 Hz, 30 Hz, 15 Hz, 5 Hz.
const STRIDE_NEAR := 2
const STRIDE_MID := 4
const STRIDE_FAR := 12


static func stride_for(distance: float) -> int:
	if distance < NEAR:
		return STRIDE_NEAR
	if distance < MID:
		return STRIDE_MID
	return STRIDE_FAR


## Per-mob offset so decimated ticks interleave instead of synchronising.
static func phase(at: Vector3, span: int) -> int:
	if span <= 1:
		return 0
	return int(absf(at.x * 7.0 + at.z * 13.0)) % span


## True when this mob should think on this physics frame.
## 1 for full rate, 2 for half rate; a body beyond `ANIMATE_RANGE` is frozen
## outright.
static func anim_stride(distance: float) -> int:
	return 1 if distance <= ANIMATE_NEAR else 2


static func should_animate(distance: float) -> bool:
	return distance <= ANIMATE_RANGE


static func due(frame: int, phase_offset: int, stride: int) -> bool:
	return stride <= 1 or (frame + phase_offset) % stride == 0
