extends RefCounted
## The mob replication record: fifteen floats per body.
##
## The frontier host sends every mob inside the relevance radius fifteen times
## a second. A mob used to travel as a nine-key dictionary — 244 encoded bytes
## each — so a hundred and thirty bodies in view was 32 KB per send, half a
## megabyte a second of upstream. That is past what a residential connection
## carries, and once the host's queue backs up ENet starts dropping the
## snapshots that own the smoothness, which is what a client feels as jitter.
## The same body packs into fifteen floats: 72 bytes, a third of the traffic,
## one allocation instead of a dictionary and nine values, and it is cheap to
## size without encoding it.
##
## Layout, by slot:
##   0      mob index in the host's enemy table
##   1..3   world position
##   4..6   velocity, for dead reckoning a starved replica
##   7      yaw
##   8      state clock, seconds in the current action
##   9      health
##   10     state code, alive flag and grounded flag in one number
##   11..14 family extra: the cinder devil's dodge/slide pose, else zero
##
## The state vocabulary is shared by the devils, the wolves, the cinder devil,
## the forest mobs and the ranger clones, so one table covers every family.

const WIDTH := 15

const AT_INDEX := 0
const AT_POSITION := 1
const AT_VELOCITY := 4
const AT_YAW := 7
const AT_STATE_TIME := 8
const AT_HEALTH := 9
const AT_FLAGS := 10
const AT_EXTRA := 11

## Every state name any mob family can report, in one place.
const STATES := [
	"IDLE", "RETURN", "CIRCLE", "WINDUP", "STRIKE", "RECOVER", "STAGGER",
	"DEAD", "CHASE", "DIVE", "LEAP", "SHOOT", "SLIDE", "STEP", "EMERGE",
	"DRAWING", "HOLDING",
]
const FLAG_ALIVE := 2
const FLAG_GROUNDED := 1
## The state occupies the high part of the flags slot.
const STATE_SCALE := 4


static func state_code(state_name: String) -> int:
	var index := STATES.find(state_name)
	return index if index >= 0 else 0


static func state_name(code: int) -> String:
	if code < 0 or code >= STATES.size():
		return "IDLE"
	return str(STATES[code])


static func pack(index: int, position: Vector3, velocity: Vector3, yaw: float,
		state_time: float, health: float, grounded: bool, alive: bool,
		state: String, extra := Vector4.ZERO) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(WIDTH)
	out[AT_INDEX] = float(index)
	out[AT_POSITION] = position.x
	out[AT_POSITION + 1] = position.y
	out[AT_POSITION + 2] = position.z
	out[AT_VELOCITY] = velocity.x
	out[AT_VELOCITY + 1] = velocity.y
	out[AT_VELOCITY + 2] = velocity.z
	out[AT_YAW] = yaw
	out[AT_STATE_TIME] = state_time
	out[AT_HEALTH] = health
	out[AT_FLAGS] = float(state_code(state)
		* STATE_SCALE
		+ (FLAG_ALIVE if alive else 0)
		+ (FLAG_GROUNDED if grounded else 0))
	out[AT_EXTRA] = extra.x
	out[AT_EXTRA + 1] = extra.y
	out[AT_EXTRA + 2] = extra.z
	out[AT_EXTRA + 3] = extra.w
	return out


static func position_of(record: PackedFloat32Array) -> Vector3:
	return Vector3(record[AT_POSITION], record[AT_POSITION + 1], record[AT_POSITION + 2])


static func velocity_of(record: PackedFloat32Array) -> Vector3:
	return Vector3(record[AT_VELOCITY], record[AT_VELOCITY + 1], record[AT_VELOCITY + 2])


static func extra_of(record: PackedFloat32Array) -> Vector4:
	return Vector4(record[AT_EXTRA], record[AT_EXTRA + 1], record[AT_EXTRA + 2], record[AT_EXTRA + 3])


static func state_of(record: PackedFloat32Array) -> String:
	return state_name(int(record[AT_FLAGS]) / STATE_SCALE)


static func alive_of(record: PackedFloat32Array) -> bool:
	return (int(record[AT_FLAGS]) & FLAG_ALIVE) != 0


static func grounded_of(record: PackedFloat32Array) -> bool:
	return (int(record[AT_FLAGS]) & FLAG_GROUNDED) != 0
