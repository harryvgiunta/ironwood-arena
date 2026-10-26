extends Node3D

## Presentation-only controller for the imported Briar wolf. Gameplay owns the
## root motion, state timer, damage and death lifecycle; this node samples the
## authored clips and hands the dead skeleton to the shared corpse ragdoll.

const Hitbox = preload("res://scripts/hitbox.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const WOLF_SCENE := preload("res://assets/characters/ironwood_wolf.glb")
const IDLE_CLIP := "Wolf_Idle_Loop"
const TROT_CLIP := "Wolf_Trot_Loop"
const ATTACK_CLIP := "Wolf_Attack"
const DEATH_CLIP := "Wolf_Death"
const TROT_DURATION := 0.6
const TROT_STRIDE := 1.15
const ATTACK_IMPACT := 0.65
const ATTACK_RECOVERY := 0.85
const DEATH_DURATION := 0.45
const MOVE_THRESHOLD := 0.18

var _player: AnimationPlayer
## Frames per animation step; see `set_anim_stride`.
var _anim_stride := 1
var _anim_phase := 0
var _skeleton: Skeleton3D
var _head_bone := -1
var _clip := ""
var _speed := 0.0
var _combat_state := ""
var _combat_time := 0.0
var _attack_playing := false
var _dead := false
var _death_time := 0.0
var _death_held := false


func _ready() -> void:
	var scene := WOLF_SCENE.instantiate()
	add_child(scene)
	_player = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = scene.find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null or _skeleton == null:
		push_error("Wolf visual is missing its AnimationPlayer or Skeleton3D")
		return
	_head_bone = _skeleton.find_bone("head")
	for name in [IDLE_CLIP, TROT_CLIP, ATTACK_CLIP, DEATH_CLIP]:
		if not _player.has_animation(name):
			push_error("Wolf visual is missing clip: " + name)
			return
	_player.get_animation(IDLE_CLIP).loop_mode = Animation.LOOP_LINEAR
	_player.get_animation(TROT_CLIP).loop_mode = Animation.LOOP_LINEAR
	_player.get_animation(ATTACK_CLIP).loop_mode = Animation.LOOP_NONE
	_player.get_animation(DEATH_CLIP).loop_mode = Animation.LOOP_NONE
	_clip = IDLE_CLIP
	_player.speed_scale = 1.0
	_player.play(IDLE_CLIP)


func set_motion(speed: float) -> void:
	_speed = speed


func set_combat(state: String, time: float) -> void:
	_combat_state = state
	_combat_time = time
	if _dead:
		return
	if state in ["WINDUP", "RECOVER"] and not _attack_playing:
		_attack_playing = true
		_clip = ATTACK_CLIP
		_player.speed_scale = 1.0
		_player.play(ATTACK_CLIP, 0.08)


func die(direction: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	_dead = true
	_attack_playing = false
	_death_time = 0.0
	# The authored death clip is replaced by the corpse ragdoll: the pinned
	# animation pose is captured at the lethal frame, then the skeleton goes
	# limp. The clip name stays for the presentation contract and tests.
	_death_held = true
	_clip = DEATH_CLIP
	if _player:
		_player.pause()
	CorpsePhysics.start_limp(self, direction)


func head_hitbox_center() -> Vector3:
	if _skeleton == null or _head_bone < 0:
		return global_position
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone).origin

func head_hit_profile() -> Vector2:
	return Vector2(Hitbox.WOLF_HEAD_RADIUS,Hitbox.WOLF_HEAD_HALF_HEIGHT)

func get_clip_name() -> String:
	return _clip


func is_dead() -> bool:
	return _dead


func _process(delta: float) -> void:
	if _anim_stride > 1:
		_anim_phase += 1
		if _anim_phase % _anim_stride != 0:
			return
		delta *= float(_anim_stride)
	Perf.begin("mob.anim")
	_sample(delta)
	Perf.end()


func _sample(delta: float) -> void:
	if _player == null:
		return
	if _dead:
		_advance_death(delta)
		return
	if _attack_playing:
		# The gameplay timer is authoritative. Seek to its mapped position so a
		# long physics frame cannot desynchronise the bite from the damage check.
		if _combat_state == "WINDUP":
			_player.seek(clampf(_combat_time, 0.0, ATTACK_IMPACT), true)
			return
		if _combat_state == "RECOVER":
			_player.seek(ATTACK_IMPACT + clampf(_combat_time, 0.0, ATTACK_RECOVERY), true)
			return
		_attack_playing = false
		_select_locomotion()
		return
	_select_locomotion()


func _select_locomotion() -> void:
	if _speed > MOVE_THRESHOLD:
		if _clip != TROT_CLIP:
			_clip = TROT_CLIP
			_player.speed_scale = 1.0
			_player.play(TROT_CLIP, 0.18)
		_player.speed_scale = clampf(_speed / (TROT_STRIDE / TROT_DURATION), 0.35, 2.6)
	else:
		if _clip != IDLE_CLIP:
			_clip = IDLE_CLIP
			_player.speed_scale = 1.0
			_player.play(IDLE_CLIP, 0.20)
		else:
			_player.speed_scale = 1.0


func _advance_death(delta: float) -> void:
	if _death_held:
		return
	_death_time += delta
	if _death_time >= DEATH_DURATION:
		_death_held = true
		_player.seek(DEATH_DURATION, true)
		_player.pause()


## Stops the clip writing bone tracks. The last pose stays on the rig, which is
## what a body outside the camera shows: see `MobLod.in_view`.
func set_frozen(frozen: bool) -> void:
	set_process(not frozen)


func set_anim_stride(stride: int) -> void:
	_anim_stride = maxi(1, stride)
