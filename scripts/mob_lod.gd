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

## The approach threshold at which a rig that was released at `RELEASE_RANGE`
## is rebuilt. It is deliberately not where animation stops: a body that walked
## out from the player keeps its rig, drawing and animating, all the way to
## `RELEASE_RANGE`. Hiding it at this line put a visible pop into the mid
## distance in both directions. The gap between the two numbers is hysteresis:
## a body pacing the boundary must not build and free a rig every second.
const REBUILD_RANGE := 45.0
## Frames per animation step for a presented body. Thirty hertz is the
## standard trade for character animation: the sampler is skipped on the frames
## between, so the clip advances the same time over a longer gap and the
## skeleton is only touched when it actually moves. Measured at 5% of a
## frontier frame over sixty-hertz rigs.
const ANIMATE_STRIDE := 2
## Past this a body's presentation subtree is released outright -- four
## hundredths of a millisecond each, but a body that far away is not read -- and
## rebuilt when it comes back inside `REBUILD_RANGE`.
const RELEASE_RANGE := 58.0
## Radius of the sphere that decides whether a body is on screen. It covers the
## tallest devil plus the reach of a swung weapon, so a body straddling the
## screen edge is never called offscreen while a sliver of it still draws. The
## test that came before sampled two points on the body and could hide a body
## whose torso was in view.
const VIEW_RADIUS := 2.0
## Height above a body's root at which that sphere is centred.
const VIEW_CENTRE_HEIGHT := 1.0
## Metres to the nearest ranger at which each stride takes over.
const NEAR := 22.0
const MID := 55.0
## Physics ticks between decisions, per tier: 30 Hz in a fight, 15 Hz close by,
## 5 Hz in the middle distance, 2 Hz beyond. Movement is *not* tied to
## this: a body integrates its last decided velocity every frame, so a coarse
## think rate costs nothing visible.
const STRIDE_ATTACK := 2
const STRIDE_NEAR := 4
const STRIDE_MID := 12
const STRIDE_FAR := 48


## `ready` is the mob's own readiness to swing: a body whose cooldown is up, or
## which is already winding up, striking or recovering, thinks at thirty hertz
## whatever the range, because that is the part of a fight a player reads. The
## rest of a pack — orbiting, waiting out a cooldown, walking home — does not.
static func stride_for(distance: float, ready := false) -> int:
	if ready:
		return STRIDE_ATTACK
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


## True while a body is close enough to own, draw and animate a rig at all.
static func should_present(distance: float) -> bool:
	return distance <= RELEASE_RANGE


## True when a body's bounding sphere still touches the viewer's frustum.
##
## `planes` is one `Camera3D.get_frustum()`, computed once for the whole scene
## and shared by every body. Its normals point *out* of the view volume, so a
## point is outside a plane when its signed distance is positive; adding the
## body's radius makes the test conservative -- a body is only offscreen when
## the whole sphere is, which is the only state in which hiding it is free.
static func in_view(planes: Array[Plane], centre: Vector3, radius: float = VIEW_RADIUS) -> bool:
	for plane in planes:
		if plane.distance_to(centre) > radius:
			return false
	return true


static func due(frame: int, phase_offset: int, stride: int) -> bool:
	return stride <= 1 or (frame + phase_offset) % stride == 0
