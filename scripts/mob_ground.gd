extends RefCounted
## Locomotion for wilderness mobs, without a physics body step.
##
## A `CharacterBody3D` step (`move_and_slide`) costs about 90 µs on this world:
## the body sweeps and resolves against the terrain, every neighbouring body and
## every prop, then re-tests the floor, up to `max_slides` times. One ranger can
## afford that; a hundred mobs cannot, and the measurement says a hundred mobs
## at that price is most of the frame.
##
## So mobs walk on the world's own surface instead. The terrain is an analytic
## height field already (`RangeWorld.terrain_height`), and the props are marked
## in a square-metre navigation grid at build time (`RangeWorld.is_blocked`), so
## a body's next step is a few array reads: about 1.6 µs, fifty times cheaper.
## The mob keeps its `CollisionShape3D` on the hit layer, so blades, arrows,
## spells and the ranger's own capsule still see it; it simply never asks the
## physics server to move it.
##
## The trade is fidelity, deliberately: a mob no longer slides along a wall at a
## grazing angle or steps up a kerb — it stops and tries the other axis — and it
## cannot be pushed by a body heavier than itself. Separation is handled by the
## mob's own neighbour pass, which is cheaper and more legible than the solver's.

## Metres of ground the feet still reach across in one step, so walking off a
## kerb follows the surface instead of starting a fall.
const SNAP := 0.45
## Falling speed once the ground drops away.
const GRAVITY := 18.0

var velocity := Vector3.ZERO
var grounded := true
## The world, for `terrain_height` and `is_blocked`.
var terrain: Node3D
## Body radius used against the navigation grid.
var radius := 0.34
## Ground height under the body after the last step.
var ground := 0.0
## Real displacement this step, per second: what the animation sampler wants.
var actual := Vector3.ZERO

var _from := Vector3.ZERO
var _next := Vector3.ZERO
## Ground query used only where there is no analytic terrain: a bare test
## scene, a probe. Never taken in the frontier.
var _ray := PhysicsRayQueryParameters3D.new()


## Moves `owner` one step towards `desired` (its wanted velocity), with
## `control` the metres per second squared of steering it has.
func step(owner: Node3D, delta: float, desired: Vector3, control: float) -> void:
	velocity.x = move_toward(velocity.x, desired.x, control * delta)
	velocity.z = move_toward(velocity.z, desired.z, control * delta)
	_from = owner.global_position
	_next = _from + velocity * delta
	# A body that is already inside a marked cell is let out rather than walled
	# in: only entering is refused, so nothing can be trapped by its own spawn
	# or by a push.
	if terrain != null and not terrain.is_blocked(_from.x, _from.z, radius) \
			and terrain.is_blocked(_next.x, _next.z, radius):
		if not terrain.is_blocked(_next.x, _from.z, radius):
			_next.z = _from.z
			velocity.z = 0.0
		elif not terrain.is_blocked(_from.x, _next.z, radius):
			_next.x = _from.x
			velocity.x = 0.0
		else:
			_next.x = _from.x
			_next.z = _from.z
			velocity.x = 0.0
			velocity.z = 0.0
	var limit := 143.0
	_next.x = clampf(_next.x, -limit, limit)
	_next.z = clampf(_next.z, -limit, limit)
	ground = terrain.terrain_height(_next.x, _next.z) if terrain != null else _sample(owner)
	if _next.y <= ground:
		_next.y = ground
		velocity.y = 0.0
		grounded = true
	elif _next.y - ground <= SNAP and velocity.y <= 0.0:
		# Walking downhill: follow the surface rather than lift off it.
		_next.y = ground
		velocity.y = 0.0
		grounded = true
	else:
		grounded = false
		velocity.y -= GRAVITY * delta
	actual = (_next - _from) / maxf(delta, 0.0001)
	# A body that did not move keeps its transform: writing the same position
	# back dirties the node and its physics body for nothing, and most of a
	# frontier's mobs are standing still.
	if _next.x != _from.x or _next.y != _from.y or _next.z != _from.z:
		owner.global_position = _next


## Puts the body on the ground at its current heading without moving it.
func settle(owner: Node3D) -> void:
	_from = owner.global_position
	ground = terrain.terrain_height(_from.x, _from.z) if terrain != null else _sample(owner)
	_from.y = ground
	owner.global_position = _from
	velocity.y = 0.0
	grounded = true


## Airborne launch: the leap and jump paths own their vertical speed.
func launch(up_speed: float) -> void:
	velocity.y = up_speed
	grounded = false


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length_squared() > 0.0025


## Floor height from the physics world, for scenes that have no analytic
## terrain: a downward ray from just above the body's feet.
func _sample(owner: Node3D) -> float:
	var space := owner.get_world_3d()
	if space == null:
		return _next.y
	var at := owner.global_position
	_ray.from = at + Vector3(0.0, 1.0, 0.0)
	_ray.to = at + Vector3(0.0, -1.6, 0.0)
	_ray.collision_mask = 1
	_ray.exclude = [owner.get_rid()] if owner is CollisionObject3D else []
	var hit := space.direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return at.y - 3.2
	return float((hit.position as Vector3).y)


## Moves a body that already owns its full velocity vector (`CharacterBody3D`'s
## `velocity`, gravity included): same ground clamp and navigation test as
## `step`, but the caller's vector is what travels. Used by the legacy mob AI,
## whose dodge, slide and leap states write velocity directly.
func drive(owner: CharacterBody3D, delta: float) -> void:
	velocity = owner.velocity
	_from = owner.global_position
	_next = _from + velocity * delta
	if terrain != null and not terrain.is_blocked(_from.x, _from.z, radius) \
			and terrain.is_blocked(_next.x, _next.z, radius):
		if not terrain.is_blocked(_next.x, _from.z, radius):
			_next.z = _from.z
			velocity.z = 0.0
		elif not terrain.is_blocked(_from.x, _next.z, radius):
			_next.x = _from.x
			velocity.x = 0.0
		else:
			_next.x = _from.x
			_next.z = _from.z
			velocity.x = 0.0
			velocity.z = 0.0
	var limit := 143.0
	_next.x = clampf(_next.x, -limit, limit)
	_next.z = clampf(_next.z, -limit, limit)
	ground = terrain.terrain_height(_next.x, _next.z) if terrain != null else _sample(owner)
	if _next.y <= ground:
		_next.y = ground
		velocity.y = 0.0
		grounded = true
	elif _next.y - ground <= SNAP and velocity.y <= 0.0:
		_next.y = ground
		velocity.y = 0.0
		grounded = true
	else:
		grounded = false
	actual = (_next - _from) / maxf(delta, 0.0001)
	owner.velocity = velocity
	if _next.x != _from.x or _next.y != _from.y or _next.z != _from.z:
		owner.global_position = _next
