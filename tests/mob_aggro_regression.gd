extends SceneTree

## Aggression and sight for every wilderness mob.
##
## Owns the contract the feature was asked for: a mob only hunts what it can
## actually see (forward cone, capped range, scenery blocks it), a ranger can
## stand behind it safely, a landed blow makes it turn on its attacker and
## pulls the neighbours in, and losing sight never resets aggression before
## `MEMORY_SECONDS` (15 s) have passed.

const DevilMob = preload("res://scripts/devil_mob.gd")
const ForestMob = preload("res://scripts/forest_mob.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Arrow = preload("res://scripts/arrow.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const Backstab = preload("res://scripts/backstab_ability.gd")

## Far outside the town's safe ring: these mobs are free to hunt.
const SAFE_OFFSET := Vector3(1000.0, 0.0, 1000.0)

var failures := 0
var checks := 0
var world_root: Node3D


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	world_root = Node3D.new()
	world_root.name = "AggroTestWorld"
	root.add_child(world_root)
	_build_floor()
	var player := _player(Vector3(0.0, 0.0, 0.0))
	check(MobSenses.MEMORY_SECONDS >= 15.0,
		"pursuit memory honours the required 15 s floor (%.2f)" % MobSenses.MEMORY_SECONDS)
	await _check_blind_spot(player, "hell_goat")
	await _check_blind_spot(player, "ossuary_stalker")
	await _check_sight_range(player)
	await _check_blocked_sight(player)
	await _check_memory_floor(player)
	await _check_pursuit_after_lost_sight(player)
	await _check_pack_alarm(player)
	await _check_backstab_from_behind(player)
	await _check_legacy_wolf(player)
	await _check_safe_ring(player)
	print("MOB_AGGRO_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


# --- the requested behaviours ----------------------------------------------

## Behind a mob is blind; in front of it is not. The two mob families share
## the same rule, so both are driven here.
func _check_blind_spot(player: CharacterBody3D, mob_id: String) -> void:
	var mob = _spawn(mob_id, Vector3(0.0, 0.05, 0.0), player)
	# `_ready` faces the ranger, so put the ranger back behind the mob.
	mob.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, 3.0)
	await _frames(45)
	check(not bool(mob._senses.seen), mob_id + " does not see a ranger standing behind it")
	check(not bool(mob._senses.aggressive()), mob_id + " stays calm with a ranger behind it")
	check(str(mob.state) in ["IDLE", "RETURN"], mob_id + " stays home while it cannot see")
	check(is_equal_approx(mob.health, mob.max_health), mob_id + " never strikes an unseen ranger")
	# Step around into the cone: sight alone is enough to start the fight.
	player.global_position = Vector3(0.0, 0.0, -5.0)
	await _frames(20)
	check(bool(mob._senses.seen), mob_id + " sees the ranger in front of it")
	check(bool(mob._senses.aggressive()), mob_id + " turns aggressive on sight alone")
	check(str(mob.state) in ["CIRCLE", "WINDUP"], mob_id + " engages once it sees the ranger")
	_clear(mob)


## Sight is capped: just inside the profile range is a sighting, just outside
## is not, however clear the view.
func _check_sight_range(player: CharacterBody3D) -> void:
	var sight := float(DevilMob.PROFILES["hell_goat"]["sight"])
	var mob = _spawn("hell_goat", Vector3(0.0, 0.05, 0.0), player)
	mob.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, -(sight + 4.0))
	await _frames(20)
	check(not bool(mob._senses.seen), "a ranger beyond the sight range is not seen")
	check(not bool(mob._senses.aggressive()), "distance alone never builds aggression")
	player.global_position = Vector3(0.0, 0.0, -(sight - 3.0))
	await _frames(20)
	check(bool(mob._senses.seen), "a ranger inside the sight range is seen")
	_clear(mob)


## Terrain and props break the line of sight, not just distance or facing.
func _check_blocked_sight(player: CharacterBody3D) -> void:
	var mob = _spawn("hell_goat", Vector3(0.0, 0.05, 0.0), player)
	mob.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, -8.0)
	await _frames(10)
	check(bool(mob._senses.seen), "a clear line of sight sees the ranger")
	var wall := _wall(Vector3(0.0, 1.5, -4.0), Vector3(4.0, 3.0, 0.4))
	await _frames(10)
	check(not bool(mob._senses.seen), "a wall between them blocks the sighting")
	# The mob now hunts from memory instead of dropping the fight.
	check(bool(mob._senses.aggressive()), "blocked sight does not clear aggression")
	_clear(mob)
	_clear(wall)


## The countdown itself: the pursuit lasts the full memory, then stops. Driven
## on a frozen mob so the measurement is exact simulated seconds.
func _check_memory_floor(player: CharacterBody3D) -> void:
	var mob = _spawn("hell_goat", Vector3(0.0, 0.05, 0.0), player)
	mob.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, -6.0)
	await _frames(6)
	check(bool(mob._senses.aggressive()), "the ranger in the cone starts a pursuit")
	mob.set_physics_process(false)
	var hidden := [player]
	# The ranger leaves the cone entirely; only the memory is left.
	player.global_position = Vector3(0.0, 0.0, 60.0)
	for tick in 29:
		mob._senses.step(mob, hidden, 0.5, 30.0, 1.7, mob.safe_center)
	check(bool(mob._senses.aggressive()), "the pursuit survives 14.5 s without sight")
	mob._senses.step(mob, hidden, 0.5, 30.0, 1.7, mob.safe_center)
	check(not bool(mob._senses.aggressive()),
		"the pursuit ends after the 15 s memory, never earlier")
	_clear(mob)


## Losing the view mid-chase keeps the mob running at the last known spot for
## as long as the memory allows.
func _check_pursuit_after_lost_sight(player: CharacterBody3D) -> void:
	var mob = _spawn("hell_goat", Vector3(0.0, 0.05, 0.0), player)
	mob.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, -9.0)
	await _frames(12)
	check(bool(mob._senses.seen), "the chase starts from a clear sighting")
	var wall := _wall(Vector3(0.0, 1.5, -4.5), Vector3(5.0, 3.0, 0.4))
	await _frames(90)
	check(str(mob.state) != "RETURN", "a mob that lost sight keeps hunting instead of going home")
	check(bool(mob._senses.aggressive()), "aggression survives 1.5 s of blocked sight")
	check(mob.global_position.z < -1.0,
		"the mob runs at the last known position (z=%.2f)" % mob.global_position.z)
	_clear(mob)
	_clear(wall)


## A bow hit from behind: the struck mob turns on the archer and the neighbours
## within earshot come with it.
func _check_pack_alarm(player: CharacterBody3D) -> void:
	var struck = _spawn("hell_goat", Vector3(0.0, 0.05, 0.0), player)
	var neighbour = _spawn("hell_goat", Vector3(6.0, 0.05, 0.0), player)
	var distant = _spawn("hell_goat", Vector3(0.0, 0.05, 60.0), player)
	struck.rotation.y = 0.0
	neighbour.rotation.y = 0.0
	distant.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, 10.0)
	await _frames(20)
	check(not bool(struck._senses.aggressive()) and not bool(neighbour._senses.aggressive()),
		"the pack is calm before the shot")
	# A real arrow from the archer's hands, hitting the mob in the back.
	var origin := Vector3(0.0, 1.35, 10.0)
	var direction: Vector3 = struck.get_aim_position() - origin
	var arrow := Arrow.new()
	arrow.hit_mask = 1 | 2
	arrow.shooter = player
	arrow.source_id = 0
	world_root.add_child(arrow)
	arrow.launch(origin, direction.normalized(), 30.0, 8.0, [] as Array[RID], origin)
	var landed := false
	for frame in 90:
		await physics_frame
		if not is_instance_valid(arrow) or not bool(arrow.flying):
			landed = true
			break
	check(landed, "the arrow reaches the mob")
	check(struck.health < struck.max_health, "the arrow damages the mob")
	await _frames(10)
	check(bool(struck._senses.aggressive()), "a mob hit by an arrow turns aggressive")
	check(struck._senses.target == player, "a mob hit by an arrow targets its archer")
	check(bool(neighbour._senses.aggressive()), "the neighbour hears the cry and joins the hunt")
	check(neighbour._senses.target == player, "the alerted neighbour hunts the same archer")
	check(not bool(distant._senses.aggressive()),
		"a mob out of earshot is not pulled into the fight")
	_clear(struck)
	_clear(neighbour)
	_clear(distant)
	_clear(arrow)


## Sneaking: unseen from behind, the dagger lands for full effect; the wound
## then gives the mob the fight.
func _check_backstab_from_behind(player: CharacterBody3D) -> void:
	var mob = _spawn("hell_goat", Vector3(0.0, 0.05, 0.0), player)
	mob.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, 1.2)
	await _frames(20)
	check(not bool(mob._senses.seen), "a ranger behind the mob stays unseen while sneaking")
	check(str(mob.state) in ["IDLE", "RETURN"], "the mob does not react to the approach")
	var before: float = mob.health
	var applied: float = Backstab.strike(player, mob, 20.0, 0)
	check(is_equal_approx(applied, 20.0), "the unseen backstab lands its damage")
	check(is_equal_approx(mob.health, before - 20.0), "the dagger removes the health")
	check(str(mob.state) == "STAGGER", "the stab staggers the mob")
	await _frames(40)
	check(bool(mob._senses.aggressive()), "the stabbed mob turns on the ranger that stabbed it")
	check(mob._senses.target == player, "the stabbed mob locks onto its attacker")
	_clear(mob)


## The wolf and the cinder devil obey the same rule as the newer families.
func _check_legacy_wolf(player: CharacterBody3D) -> void:
	var wolf = Enemy.new()
	wolf.kind = 0
	wolf.player = player
	wolf.safe_center = SAFE_OFFSET
	wolf.position = Vector3(0.0, 0.05, 0.0)
	world_root.add_child(wolf)
	# A fresh mob watches the ranger that spawned it instead of staring down -Z:
	# a fixed frozen cone left whole packs blind to a ranger beside them.
	var forward: Vector3 = -wolf.global_basis.z
	var to_player: Vector3 = player.global_position - wolf.global_position
	forward.y = 0.0
	to_player.y = 0.0
	check(forward.normalized().dot(to_player.normalized()) > 0.95,
		"a fresh mob spawns facing the ranger")
	wolf.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, 3.0)
	await _frames(30)
	check(not bool(wolf._senses.seen), "the wolf does not see a ranger behind it")
	check(str(wolf.state) != "CHASE", "the wolf does not chase what it cannot see")
	player.global_position = Vector3(0.0, 0.0, -5.0)
	await _frames(20)
	check(wolf._senses.target == player, "the wolf acquires the ranger in front of it")
	check(str(wolf.state) in ["CHASE", "WINDUP"], "the wolf gives chase once it sees")
	_clear(wolf)


## Town peace: nothing inside the safe ring is hunted, however it was provoked.
func _check_safe_ring(player: CharacterBody3D) -> void:
	var mob = _spawn("hell_goat", Vector3(0.0, 0.05, 0.0), player)
	mob.safe_center = Vector3(0.0, 0.0, 0.0)
	mob.rotation.y = 0.0
	player.global_position = Vector3(0.0, 0.0, -5.0)
	await _frames(20)
	check(not bool(mob._senses.aggressive()), "a ranger inside the safe ring is never hunted")
	check(str(mob.state) in ["IDLE", "RETURN"], "the mob stays peaceful in town")
	_clear(mob)


# --- helpers ---------------------------------------------------------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	world_root.add_child(body)


func _player(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = at
	world_root.add_child(body)
	return body


func _wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = at
	world_root.add_child(body)
	return body


## Spawns a devil or forest mob (`ossuary_stalker` and friends) in the test world.
func _spawn(mob_id: String, at: Vector3, player: Node3D):
	var mob
	if ForestMob.FOREST_PROFILES.has(mob_id):
		mob = ForestMob.new()
	else:
		mob = DevilMob.new()
	mob.mob_id = mob_id
	mob.player = player
	mob.safe_center = SAFE_OFFSET
	mob.position = at
	world_root.add_child(mob)
	return mob


func _clear(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
