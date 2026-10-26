extends RefCounted
## Aggression and sight for every wilderness mob.
##
## One rule set for the profile state machines (devils, forest mobs) and the
## legacy wolf/sentinel/cinder devil AI:
##
##   - A mob is aggressive only while it has seen a ranger recently. Sight is
##     a forward cone, capped by the profile's range, and blocked by terrain,
##     props and tree trunks. A mob's back is blind, so a ranger can walk up
##     behind it and strike unseen.
##   - Losing the line of sight never drops aggression. The mob keeps hunting
##     the last place it saw its quarry for `MEMORY_SECONDS` (15 s, the
##     required floor) and only then walks home.
##   - A landed blow always gives a mob the fight: `notice()` on any damage
##     path, plus `alert_pack()` so the neighbours that heard the cry join.
##
## Every mob joins `GROUP`; that is the only thing alerting needs. Senses are
## host-side gameplay state: replicas replay a snapshot and never run this.

## Ranges shared by every mob family.
const GROUP := "wild_mobs"
## Seconds of pursuit from the last sighting. The requirement is "at least 15
## seconds", so this is the floor and never an instant reset.
const MEMORY_SECONDS := 15.0
## The full cone is twice this: 140 degrees of view, 220 degrees of blind spot.
const HALF_FOV_DEGREES := 70.0
## A struck mob's cry reaches this far, so a pack answers as one.
const SHOUT_RADIUS := 12.0
## The town's safe ring. Mobs never hunt a ranger standing inside it.
const SAFE_RING := 19.0
## Eye height as a fraction of the mob's authored height.
const EYE_HEIGHT_FRACTION := 0.85
## The two body samples a mob must clear to see a ranger.
const CHEST_HEIGHT := 1.25
const HEAD_HEIGHT := 1.65
## Terrain, props and tree trunks block sight. Rangers and other bodies are on
## their own layers and never hide one another.
const SIGHT_MASK := 1
## Standing this close to the last sighting means it arrived.
const ARRIVE_DISTANCE := 1.6

## The ranger this mob is currently hunting (null before anything is seen).
var target: CharacterBody3D
## Where it last saw, heard or was struck by its quarry.
var last_seen := Vector3.ZERO
## Seconds of pursuit left after the last sighting.
var memory := 0.0
## True only on frames with a clear, in-cone view.
var seen := false

var _query := PhysicsRayQueryParameters3D.new()


func _init() -> void:
	_query.collision_mask = SIGHT_MASK


func aggressive() -> bool:
	return memory > 0.0


## Where the mob should head: the live body only while it can actually see it,
## otherwise the place it last saw one. Steering never follows a target through
## a wall.
func focus() -> Vector3:
	if seen and is_instance_valid(target):
		return target.global_position
	return last_seen


## One AI tick. Refreshes the pursuit timer, looks for the nearest visible
## candidate and returns whether the mob is aggressive. `safe_center` is the
## town's ring: a ranger inside it is never a candidate. That rule used to be a
## `Callable` the mobs passed in, which cost a dynamic dispatch per candidate
## per tick -- more than the sight ray itself, since the rule is the same for
## every family and a sight ray here is under two microseconds.
func step(owner: Node3D, candidates: Array, delta: float, sight_range: float,
		eye_height: float, safe_center: Vector3) -> bool:
	memory = maxf(0.0, memory - delta)
	seen = false
	if not is_instance_valid(owner) or sight_range <= 0.0:
		clear()
		return false
	var best: CharacterBody3D = null
	var best_distance := INF
	# Keep the remembered target if it is still in view, then let any nearer
	# visible body take over.
	if is_instance_valid(target) and _hostile(target, safe_center) \
			and can_see(owner, target, sight_range, eye_height):
		best = target
		best_distance = owner.global_position.distance_squared_to(target.global_position)
	for candidate in candidates:
		if candidate == best or not _hostile(candidate, safe_center):
			continue
		if not can_see(owner, candidate, sight_range, eye_height):
			continue
		var distance: float = owner.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	if best != null:
		target = best
		last_seen = best.global_position
		memory = MEMORY_SECONDS
		seen = true
		return true
	if not is_instance_valid(target) or not _hostile(target, safe_center):
		clear()
		return false
	return memory > 0.0


## A blow landed. The mob turns on whoever delivered it even if that ranger is
## behind a tree or out of the cone: being hit is not something you can miss.
func notice(attacker: Node3D, at: Vector3) -> void:
	if attacker is CharacterBody3D:
		target = attacker
		last_seen = attacker.global_position
	else:
		last_seen = at
	memory = MEMORY_SECONDS
	seen = false


func clear() -> void:
	target = null
	last_seen = Vector3.ZERO
	memory = 0.0
	seen = false


## Cone, range and line of sight, in that order: the cheap rejections first.
func can_see(owner: Node3D, candidate: Node3D, sight_range: float,
		eye_height: float) -> bool:
	if not is_instance_valid(owner) or not is_instance_valid(candidate):
		return false
	var offset := candidate.global_position - owner.global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > sight_range:
		return false
	if distance > 0.35:
		var forward := -owner.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001 \
				and forward.normalized().dot(offset / distance) < _fov_cosine():
			return false
	var from := owner.global_position + Vector3(0.0, eye_height, 0.0)
	if _clear(owner, from, candidate.global_position + Vector3(0.0, CHEST_HEIGHT, 0.0)):
		return true
	return _clear(owner, from, candidate.global_position + Vector3(0.0, HEAD_HEIGHT, 0.0))


func _clear(owner: Node3D, from: Vector3, to: Vector3) -> bool:
	_query.from = from
	_query.to = to
	return owner.get_world_3d().direct_space_state.intersect_ray(_query).is_empty()


## The one hostility rule for every family: alive, and outside the town ring.
static func _hostile(candidate: Object, safe_center: Vector3) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.get("alive") == false:
		return false
	return not in_safe_ring(safe_center, candidate.global_position)


static func _fov_cosine() -> float:
	return cos(deg_to_rad(HALF_FOV_DEGREES))


## The alarm. Every mob within `radius` of `struck` hears it and takes up the
## hunt at `at`, so shooting one beast of a pack brings the rest.
static func alert_pack(struck: Node3D, attacker: Node3D, at: Vector3,
		radius: float = SHOUT_RADIUS) -> int:
	if not is_instance_valid(struck) or not struck.is_inside_tree():
		return 0
	var alerted := 0
	for other in struck.get_tree().get_nodes_in_group(GROUP):
		if other == struck or not is_instance_valid(other):
			continue
		if other.get("alive") == false:
			continue
		if other.global_position.distance_to(struck.global_position) > radius:
			continue
		if not other.has_method("hear_alert"):
			continue
		other.hear_alert(attacker, at)
		alerted += 1
	return alerted


## True for a ranger the mob is allowed to hunt: alive and outside the town's
## safe ring. Both mob families use this for sight, alerts and responses.
static func in_safe_ring(safe_center: Vector3, point: Vector3) -> bool:
	return Vector2(point.x - safe_center.x, point.z - safe_center.z).length() < SAFE_RING
