extends Node3D

## Presentation-only controller for the imported Cinder devil.
##
## The pack AI in `scripts/enemy.gd` owns root motion, damage, arrows and death
## timing. This node samples the authored GLB clips and maps the pack state
## machine onto them: idle/walk/run carry the orbit, the attack clip is seeked
## so its authored strike lands on the gameplay damage frame, the bow state
## drives a dedicated draw/release clip, and the step/slide/leap states layer
## their own lean and body offset on top of the locomotion clip.
##
## The seven clips are named `<Prefix>_<Clip>` and carry no `_Loop` suffix:
## Godot's glTF importer strips a trailing `_Loop`, so loop modes are applied
## here rather than inferred from the asset.

const Dagger = preload("res://scripts/dagger.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const Sword = preload("res://scripts/sword.gd")
const Bow = preload("res://scripts/bow.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")

const SCENE := "res://assets/characters/devils/ironwood_cinder_devil.glb"

## Mirrors assets/characters/devils/ironwood_cinder_devil.json. The regression
## compares these against the imported asset so a rebuild cannot silently
## change the contract the AI depends on.
const CLIPS := {
	"idle": "Cinder_Idle", "walk": "Cinder_Walk", "run": "Cinder_Run",
	"attack": "Cinder_Attack", "shoot": "Cinder_Shoot",
	"hit": "Cinder_Hit", "death": "Cinder_Death",
}
const IMPACT := 0.38          # attack damage frame in the authored clip
const ATTACK_LENGTH := 0.80
const RELEASE := 0.30         # arrow spawn frame in the draw clip
const SHOOT_LENGTH := 0.55
const HIT_LENGTH := 0.367
const WALK_SPEED := 1.30
const RUN_SPEED := 4.20
const RUN_THRESHOLD := 1.60
const MOVE_THRESHOLD := 0.22
const HEAD_RADIUS := 0.26
const HEAD_HALF := 0.16

## Gameplay clock of each pack state, used to seek the attack/draw clips.
const WINDUP_SECONDS := 0.30
const STRIKE_SECONDS := 0.16
const RECOVER_SECONDS := 0.30
const SHOOT_WINDUP := 0.30
const SHOOT_RECOVER := 0.22

var _instance: Node3D
## Frames per animation step; see `set_anim_stride`.
var _anim_stride := 1
var _anim_phase := 0
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone := -1
var _hand_r := -1
var _hand_l := -1
var _clip := ""
var _speed := 0.0
var _grounded := true
var _action := "CIRCLE"
var _action_time := 0.0
var _previous_action := ""
var _weapon := "claw"
var _melee: Node3D
var _bow: Node3D
var _melee_attachment: BoneAttachment3D
var _bow_attachment: BoneAttachment3D
var _dead := false
var _death_time := 0.0
var _death_held := false
var _lean := 0.0
var _drop := 0.0
var _slide_weight := 0.0
var _step_side := 0.0


func _ready() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("Missing Cinder devil scene: " + SCENE)
		return
	_instance = packed.instantiate()
	add_child(_instance)
	_player = _instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = _instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null or _skeleton == null:
		push_error("Cinder devil visual is missing its AnimationPlayer or Skeleton3D")
		return
	_head_bone = _skeleton.find_bone("head")
	_hand_r = _skeleton.find_bone("hand_r")
	_hand_l = _skeleton.find_bone("hand_l")
	for key in CLIPS:
		if not _player.has_animation(str(CLIPS[key])):
			push_error("Cinder devil visual is missing clip %s" % CLIPS[key])
			return
	for key in ["idle", "walk", "run"]:
		_player.get_animation(str(CLIPS[key])).loop_mode = Animation.LOOP_LINEAR
	for key in ["attack", "shoot", "hit", "death"]:
		_player.get_animation(str(CLIPS[key])).loop_mode = Animation.LOOP_NONE
	_clip = str(CLIPS.idle)
	_player.play(_clip, 0.0)
	_tune_materials()
	set_weapon(_weapon)


## The imported GLB carries the maps; the runtime only carries values glTF
## cannot express. The ember surfaces are what make the creature read at
## distance, so they get their own energy.
func _tune_materials() -> void:
	if _instance == null:
		return
	for mesh_instance in _instance.find_children("*", "MeshInstance3D", true, false):
		var node := mesh_instance as MeshInstance3D
		for surface in node.mesh.get_surface_count():
			var material := node.get_active_material(surface)
			if not (material is StandardMaterial3D):
				continue
			var tuned := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
			tuned.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var mat_name := tuned.resource_name.to_lower()
			if mat_name.contains("ember"):
				tuned.emission_energy_multiplier = 3.4
			elif mat_name.contains("char"):
				tuned.emission_energy_multiplier = 2.0
			node.set_surface_override_material(surface, tuned)


# ---------------------------------------------------------------------------
# Feed from the pack AI


func set_motion(velocity: Vector3, grounded: bool) -> void:
	_speed = Vector2(velocity.x, velocity.z).length()
	_grounded = grounded


func set_action(state: String, time: float) -> void:
	_previous_action = _action
	_action = state
	_action_time = time
	if _dead:
		return
	if state == "DEAD":
		die()


func set_step(progress: float, direction: Vector3) -> void:
	# A quick step leans the body onto the lead foot; the clip stays locomotion.
	# The weight is stored rather than written straight into the posture, so the
	# per-frame posture pass cannot overwrite it a moment later.
	var weight := 0.0 if progress < 0.0 else sin(clampf(progress, 0.0, 1.0) * PI)
	var side := 0.0
	if direction.length_squared() > 0.0001:
		var planar := Vector3(direction.x, 0.0, direction.z).normalized()
		side = planar.dot(global_basis.x)
	_step_side = side * weight


func set_slide(progress: float) -> void:
	# A slide is a crouch held for its whole duration, not a peak: a sine here
	# would stand the body back up as the slide finished.
	_slide_weight = 1.0 if progress >= 0.0 else 0.0


func set_weapon(role: String) -> void:
	_weapon = role if role in ["claw", "dagger", "sword", "bow"] else "claw"
	if _skeleton == null:
		return
	_release_weapon()
	match _weapon:
		"dagger":
			var dagger = Dagger.new()
			dagger.blade_length = 0.34
			_melee = dagger
			dagger.position = Vector3(0.0, 0.0, -0.04)
		"sword":
			var sword = Sword.new()
			sword.sword_kind = 0
			sword.blade_length = 0.68
			_melee = sword
			sword.position = Vector3(0.0, 0.0, -0.05)
		"bow":
			var bow = Bow.new()
			bow.bow_kind = 1
			bow.bow_length = 1.0
			bow.set_draw(0.0)
			bow.set_arrow_visible(false)
			_bow = bow
	if _melee != null:
		_melee_attachment = _attach(_melee, _hand_r)
	if _bow != null:
		_bow_attachment = _attach(_bow, _hand_l, Vector3(0.0, 0.0, 0.0))


func _attach(node: Node3D, bone: int, offset: Vector3 = Vector3.ZERO) -> BoneAttachment3D:
	if bone < 0:
		_instance.add_child(node)
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponBone_%d" % bone
	attachment.bone_idx = bone
	_skeleton.add_child(attachment)
	attachment.add_child(node)
	node.position += offset
	return attachment


func _release_weapon() -> void:
	for holder in [_melee, _bow]:
		if is_instance_valid(holder):
			holder.queue_free()
	_melee = null
	_bow = null
	for attachment in [_melee_attachment, _bow_attachment]:
		if is_instance_valid(attachment):
			attachment.queue_free()
	_melee_attachment = null
	_bow_attachment = null


func die(direction: Vector3 = Vector3.ZERO) -> void:
	if _dead or _player == null:
		return
	_dead = true
	_death_time = 0.0
	# The imported skeleton goes limp from the lethal pose; the weapon
	# attachments are hidden because a BoneAttachment3D cannot follow a
	# simulator-driven bone.
	_death_held = true
	_clip = str(CLIPS.death)
	_player.pause()
	if is_instance_valid(_melee_attachment):
		_melee_attachment.visible = false
	if is_instance_valid(_bow_attachment):
		_bow_attachment.visible = false
	CorpsePhysics.start_limp(self, direction)


func is_dead() -> bool:
	return _dead


func get_clip_name() -> String:
	return _clip


# ---------------------------------------------------------------------------
# Presentation probes read by enemy.gd, hitbox and the blood field


func head_hitbox_center() -> Vector3:
	if _skeleton == null or _head_bone < 0:
		return global_position + Vector3(0.0, 1.9, 0.0)
	var pose := _skeleton.get_bone_global_pose(_head_bone)
	# The skull bone runs up the cranium; the muzzle sits forward and below its
	# origin, which is where a head hit actually lands.
	var offset := Vector3(0.0, 0.04, -0.10)
	return _skeleton.global_transform * (pose.origin + pose.basis * offset)


func head_hit_profile() -> Vector2:
	return Vector2(HEAD_RADIUS, HEAD_HALF)


## The skinned body: the GLB root owns the Skeleton3D and the mesh, so blood
## stains ride the real bones instead of being measured off primitives.
func blood_anchor() -> Node3D:
	if is_instance_valid(_instance):
		return _instance
	return self


func weapon_anchor() -> Node3D:
	if is_instance_valid(_melee) and _melee.visible:
		return _melee
	return null


func strike_hand_position() -> Vector3:
	if _skeleton == null or _hand_r < 0:
		return global_position + Vector3(0.0, 1.2, 0.0)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_r).origin


func get_bow_origin() -> Vector3:
	if _skeleton != null and _hand_l >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_l).origin
	return global_position + Vector3(0.0, 1.4, 0.0)


# ---------------------------------------------------------------------------
# Sampling


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
	match _action:
		"WINDUP", "STRIKE", "RECOVER":
			_seek_attack()
			_apply_posture(delta)
		"SHOOT":
			_seek_shoot()
			_apply_posture(delta)
		"STAGGER":
			_play_once("hit")
			_apply_posture(delta)
		"LEAP":
			_seek_hold("run", 0.30)
			_apply_posture(delta)
		_:
			_select_locomotion()
			_apply_posture(delta)


## The attack clip is seeked from the AI clock, never restarted: WINDUP walks
## the authored windup, STRIKE places the strike frame across the damage beat
## and RECOVER walks the follow-through.
func _seek_attack() -> void:
	var t := IMPACT
	if _action == "WINDUP":
		t = IMPACT * clampf(_action_time / WINDUP_SECONDS, 0.0, 1.0)
	elif _action == "STRIKE":
		t = IMPACT + clampf(_action_time / STRIKE_SECONDS, 0.0, 1.0) * 0.09
	elif _action == "RECOVER":
		var post := maxf(0.05, ATTACK_LENGTH - IMPACT - 0.09)
		t = IMPACT + 0.09 + clampf(_action_time / RECOVER_SECONDS, 0.0, 1.0) * post
	_ensure_clip("attack")
	_player.speed_scale = 1.0
	_player.seek(clampf(t, 0.0, ATTACK_LENGTH), true)


func _seek_shoot() -> void:
	var t := RELEASE
	if _action_time < SHOOT_WINDUP:
		t = RELEASE * clampf(_action_time / SHOOT_WINDUP, 0.0, 1.0)
	else:
		var post := maxf(0.05, SHOOT_LENGTH - RELEASE)
		t = RELEASE + clampf((_action_time - SHOOT_WINDUP) / SHOOT_RECOVER, 0.0, 1.0) * post
	_ensure_clip("shoot")
	_player.speed_scale = 1.0
	_player.seek(clampf(t, 0.0, SHOOT_LENGTH), true)


## A one-shot clip that holds its last sampled frame (hit, and the airborne
## tuck). It restarts only when the clip changes, so a held state does not
## thrash the mixer.
func _play_once(key: String) -> void:
	var name := str(CLIPS[key])
	var length := _player.get_animation(name).length
	_ensure_clip(key)
	_player.speed_scale = 1.0
	_player.seek(clampf(_action_time, 0.0, length), true)


func _seek_hold(key: String, at: float) -> void:
	_ensure_clip(key)
	_player.speed_scale = 1.0
	_player.seek(clampf(at, 0.0, _player.get_animation(str(CLIPS[key])).length), true)


func _ensure_clip(key: String) -> void:
	var name := str(CLIPS[key])
	if _clip == name:
		return
	_clip = name
	_player.play(name, 0.06)


func _select_locomotion() -> void:
	if _speed <= MOVE_THRESHOLD:
		_ensure_clip("idle")
		_player.speed_scale = 1.0
		return
	if _speed >= RUN_THRESHOLD:
		_ensure_clip("run")
		_player.speed_scale = clampf(_speed / RUN_SPEED, 0.55, 1.85)
	else:
		_ensure_clip("walk")
		_player.speed_scale = clampf(_speed / WALK_SPEED, 0.55, 1.85)


## Slide crouch, step lean and the airborne tuck, applied to the imported root
## so the authored clips stay untouched.
func _apply_posture(delta: float) -> void:
	if _instance == null:
		return
	# The slide weight comes from set_slide and the state name alike: the pack AI
	# feeds both, and a replica that only receives one must still read correctly.
	var target_lean := 0.42 * _slide_weight
	var target_drop := -0.26 * _slide_weight
	if _action == "SLIDE":
		target_lean = 0.42
		target_drop = -0.26
	elif _action == "LEAP":
		target_lean = maxf(target_lean, 0.16)
		target_drop = maxf(target_drop, 0.10 if not _grounded else 0.0)
	elif _action == "DIVE":
		target_lean = maxf(target_lean, 0.20)
	elif _action == "STAGGER":
		target_lean = -0.12
	_lean = lerpf(_lean, target_lean, minf(1.0, delta * 9.0))
	_drop = lerpf(_drop, target_drop, minf(1.0, delta * 9.0))
	_instance.rotation = Vector3(_lean, 0.0, _step_side * 0.18)
	_instance.position = Vector3(_step_side * 0.06, _drop, 0.0)


func _advance_death(delta: float) -> void:
	if _death_held or _player == null:
		return
	_death_time += delta
	var length := _player.get_animation(str(CLIPS.death)).length
	if _death_time >= length:
		_death_held = true
		_player.seek(length, true)
		_player.pause()
	if _instance != null:
		_instance.rotation = _instance.rotation.lerp(Vector3(0.0, 0.0, 0.0), minf(1.0, delta * 6.0))


## Stops the clip writing bone tracks. The last pose stays on the rig, which is
## what a body outside the camera shows: see `MobLod.in_view`.
func set_frozen(frozen: bool) -> void:
	set_process(not frozen)


func set_anim_stride(stride: int) -> void:
	_anim_stride = maxi(1, stride)
