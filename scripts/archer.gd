extends Node3D
## Imported humanoid animation, with skeletal aim/terrain corrections and real blade samples.

signal arrow_released(origin: Vector3, direction: Vector3, speed: float, charge: float)
signal weapon_thrown(origin: Vector3, direction: Vector3, speed: float, charge: float, weapon: String, weapon_index: int)
signal loadout_changed()
signal melee_started(hand: String)
signal melee_sweep(hand: String, previous_base: Vector3, previous_tip: Vector3, current_base: Vector3, current_tip: Vector3, radius: float)

const Geo = preload("res://scripts/geo.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const Bow = preload("res://scripts/bow.gd")
const Sword = preload("res://scripts/sword.gd")
const Dagger = preload("res://scripts/dagger.gd")
const Shield = preload("res://scripts/shield.gd")
const Staff = preload("res://scripts/staff.gd")
const FocusItem = preload("res://scripts/focus_item.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const TrinketStats = preload("res://scripts/trinket_stats.gd")
const EnergyShield = preload("res://scripts/energy_shield.gd")
const CHARACTER = preload("res://assets/characters/ironwood_ranger.glb")
const BOW_DATA = [
	{"name":"Shortbow", "subtitle":"Quick ashwood scout bow", "draw_seconds":1.0, "speed":66.0, "length":1.0},
	{"name":"Recurve", "subtitle":"Balanced horn-and-yew recurve", "draw_seconds":2.0, "speed":84.0, "length":1.4},
	{"name":"Longbow", "subtitle":"Heavy heartwood war bow", "draw_seconds":3.0, "speed":102.0, "length":1.8},
]
const SWORD_DATA = [
	{"name":"Shortsword", "seconds":1.0, "length":0.80, "reach":1.8, "damage":30.0, "throw_speed":26.0},
	{"name":"Arming sword", "seconds":2.0, "length":1.05, "reach":2.1, "damage":38.0, "throw_speed":28.0},
	{"name":"Greatsword", "seconds":3.0, "length":1.40, "reach":2.5, "damage":50.0, "throw_speed":24.0},
]
const DAGGER_DATA = {"name":"Dagger", "seconds":0.5, "length":0.34, "reach":1.2, "damage":14.0, "throw_speed":30.0}
const CONSUMABLE_DATA = {
	"bandage": {"name":"Bandage", "seconds":3.0, "heal":35.0, "heal_seconds":3.0, "clip":"Bandage_Wrap", "phase":"BANDAGE"},
	"potion": {"name":"Healing potion", "seconds":0.5, "heal":50.0, "heal_seconds":0.0, "clip":"Potion_Drink", "phase":"DRINK"},
}
## Two-handed staves reuse the greatsword combat profile; only the visible
## shaft endpoints differ, so blade sweeps follow the real staff length.
const STAFF_DATA = [
	{"name":"Ember staff", "length":1.75},
	{"name":"Bone staff", "length":1.60},
]
## A shield skill presents the disc ahead of the body. These are the minimum
## plane distances in front of the chest and head bones: the skinned chest
## reaches 0.29 m from the spine and every helmet 0.28 m from the head bone, so
## the disc sits just ahead of both and a clip that draws the hand back cannot
## carry the boss through the torso or the helmet.
const ABILITY_SHIELD_CHEST_CLEAR := 0.34
const ABILITY_SHIELD_HEAD_CLEAR := 0.34
const ABILITY_SHIELD_LEG_CLEAR := 0.60
## Every standard cut starts with a real backswing: the hands cock up behind
## the striking shoulder while the chest winds away from the target, then the
## hilt crosses the centre line and the tip whips through the sector past it.
const DIAGONAL_SECONDS = [0.60,0.78,1.02]
## The swing runs on one clock for every weapon: the body loads through 30% of
## the clip, the hips and chest snap the strike through 30-45%, the blade
## overshoots and is cushioned through 45-65%, and the last third eases back
## into the carry.
const SWING_LOAD_END := 0.30
const SWING_FOLLOW_END := 0.65
const SWING_SETTLE_END := 0.75
## The kinetic chain, as clip fractions of the shared strike arc. The pelvis
## turns first, the chest follows it, the clavicle drags the shoulder behind
## the chest, and the hand and blade tip trail everything.
const SWING_CHAIN_PELVIS := 0.034
const SWING_CHAIN_CHEST := 0.022
const SWING_CHAIN_CLAVICLE := 0.011
const SWING_CHAIN_BLADE := -0.014
## One diagonal cut, tuned per blade size. `yaw`/`rad` place the hilt in polar
## form around the body centre, `fwd`/`up` drive it in the swing frame,
## `blade_load`/`blade_cross` aim the blade at the chamber and follow-through
## and `tip_load`/`tip_down` pitch it. The drive carries the hilt across the
## centre line while the tip whips through the sector ahead of it.
const DIAGONAL_BLADE = [
	{"yaw_load":1.78, "yaw_cross":0.80, "rad_load":0.24, "rad_cross":0.38,
		"fwd_load":0.02, "fwd_cross":0.34, "up_load":0.24, "up_cross":-0.30,
		"blade_load":1.74, "blade_cross":1.60, "tip_load":0.58, "tip_down":-0.20,
		"pelvis_load":0.42, "pelvis_cross":0.28, "chest_load":0.84, "chest_cross":0.38,
		"lean_load":0.16, "lean_cross":0.30, "clavicle":0.16},
	{"yaw_load":1.86, "yaw_cross":0.86, "rad_load":0.26, "rad_cross":0.40,
		"fwd_load":0.00, "fwd_cross":0.38, "up_load":0.26, "up_cross":-0.32,
		"blade_load":1.90, "blade_cross":1.70, "tip_load":0.62, "tip_down":-0.22,
		"pelvis_load":0.48, "pelvis_cross":0.32, "chest_load":0.92, "chest_cross":0.44,
		"lean_load":0.16, "lean_cross":0.32, "clavicle":0.18},
	{"yaw_load":1.94, "yaw_cross":0.94, "rad_load":0.32, "rad_cross":0.44,
		"fwd_load":0.12, "fwd_cross":0.44, "up_load":0.40, "up_cross":-0.36,
		"blade_load":2.02, "blade_cross":1.80, "tip_load":0.66, "tip_down":-0.24,
		"pelvis_load":0.54, "pelvis_cross":0.36, "chest_load":0.98, "chest_cross":0.48,
		"lean_load":0.15, "lean_cross":0.34, "clavicle":0.20},
]
## A staff is held around its middle, so its swing is not a sword hilt orbit:
## both hands stay near the shaft centre and drive forward as a piston while
## the shaft wheelbarrows through the sector. The leading end travels farther
## than the hands, the rear end counterweights up and back, and the shaft ends
## the strike pointing forward-left rather than folded flat across the belly.
const DIAGONAL_STAFF = {
	"yaw_load":1.02, "yaw_cross":0.55, "rad_load":0.26, "rad_cross":0.32,
	"fwd_load":0.16, "fwd_cross":0.54, "up_load":0.22, "up_cross":-0.26,
	"blade_load":2.02, "blade_cross":0.80, "tip_load":0.62, "tip_down":-0.42,
	"pelvis_load":0.58, "pelvis_cross":0.40, "chest_load":1.00, "chest_cross":0.52,
	"lean_load":0.15, "lean_cross":0.34, "clavicle":0.22,
}
const STAFF_GRIP_DEPTH := 0.32
const STAFF_REACH = [1.60,1.50]
const MELEE_VARIANTS = ["overhead","diagonal_left","diagonal_right","stab"]
const RAISE_SECONDS := 0.30
const RELEASE_SECONDS := 0.28
const RECOVER_SECONDS := 0.95
const MAX_ELEVATION := deg_to_rad(25.0)
const STANCE_YAW := deg_to_rad(-80.0)
const MELEE_SAMPLE_SECONDS := 1.0 / 120.0
const BLEND_SECONDS := 0.12
static var _profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/ironwood_ranger.json"))

var bow_index := 1
var sword_index := 1
## Model family for the held blades: "" is forged steel, "makeshift" is the
## salvage cleaver/shiv the Unholy Forest set is themed on.
var sword_skin := ""
var dagger_skin := ""
var armor_pieces := {"head":0, "chest":0, "hands":0, "legs":0, "feet":0}
var weapon := "bow"
## The paperdoll main-hand category. Empty hands cannot be dual-wielded; a bow
## or dagger may still hand the session back to the selected one-handed sword.
var main_hand_kind := "sword"
var phase := "READY"
var draw_amount := 0.0
var charge_frozen := false
var bow_hand: Node3D
var string_hand: Node3D
var active_bow: Bow
var active_sword: Node3D
var active_dagger: Node3D
var active_shield
var shield_equipped := false
var shield_variant := 1
var consumable_kind := ""
var _bandage_prop: Node3D
var _potion_prop: Node3D
var active_staff: Node3D
var active_off_weapon: Node3D
var active_focus: Node3D
var staff_index := 0
var staff_active := false
## The off hand defaults to the dagger so the established dual-wield mode keeps
## its visible left-hand weapon until a loadout replaces it.
var off_weapon_kind := "dagger"
var off_weapon_index := 0
var off_weapon_active := true
var focus_kind := ""
var focus_index := 0
var focus_active := false
## Worn trinket kit ({neck, ring1, ring2, off}) and its summed modifiers.
## Presentation never reads these; the damage/timing getters below do.
var trinkets := {"neck":"", "ring1":"", "ring2":"", "off":""}
var trinket_stats := {}
var _ward: EnergyShield
var skeleton: Skeleton3D
var _phase_time := 0.0
var _roll_progress := -1.0
var slide_progress := -1.0
var _slide_direction := Vector3.FORWARD
var _slide_weight := 0.0
var _velocity := Vector3.ZERO
var _grounded := true
var _cover_active := false
var _blocking := false
var _block_forward := Vector3.FORWARD
var _cover_normal := Vector3.ZERO
var _cover_lean := Vector3.ZERO
var _crouch_amount := 0.0
var _ground_sampler := Callable()
var _aim_point := Vector3(0,1.5,-20)
var _motion_time := 0.0
var _locomotion_phase := 0.0
var _air_time := 0.0
var _landing_weight := 0.0
var _release_draw := 0.0
var _release_charge := 0.0
var _release_raise := 0.0
var _release_grip := Vector3.ZERO
var _release_contact := Vector3.ZERO
var _release_bow_rotation := Quaternion.IDENTITY
var last_arrow_visual_origin := Vector3.ZERO
var _model: Node3D
var _player: AnimationPlayer
var _bows: Array[Bow] = []
var _swords: Array[Node3D] = []
var _off_swords: Array[Node3D] = []
var _staffs: Array[Node3D] = []
var _focus_items: Dictionary = {}
var _armor_meshes: Dictionary = {}
var _chest: Node3D
var _quiver: Node3D
var _chest_rest_basis := Basis.IDENTITY
var _bones: Dictionary = {}
var _arms: Array[PackedInt32Array] = []
var _legs: Array[PackedInt32Array] = []
var _leg_lengths := Vector2.ZERO
var _leg_bones := PackedInt32Array()
var _lower_pose: Array[Transform3D] = []
var _blend_pose: Array[Transform3D] = []
var _authored_pose: Array[Transform3D] = []
var _crouch_pose: Array[Transform3D] = []
var _slide_crouch_pose: Array[Transform3D] = []
var _crouch_lowering := 0.0
var _cover_bones := PackedInt32Array()
var _cover_neutral: Array[Transform3D] = []
var _cover_turns: Array[Basis] = []
var _cover_shift := Vector3.ZERO
var _guard_bones := PackedInt32Array()
var _guard_pose: Array[Transform3D] = []
var _display_clip := ""
var _display_lower_clip := ""
var _display_weapon := ""
var _display_drawing := false
var _display_diagonal := 0
var _blend_time := BLEND_SECONDS
var _palm_left := Vector3.ZERO
var _palm_right := Vector3.ZERO
var _jaw_bone := -1
var _jaw_offset := Vector3.ZERO
var _bow_grip_basis := Basis.IDENTITY
var _string_grip_basis := Basis.IDENTITY
var _sword_grip := Transform3D.IDENTITY
var _sword_grip_left := Transform3D.IDENTITY
var _melee_hand := "right"
var _right_variant := "overhead"
var _left_variant := "overhead"
var _left_melee_time := -1.0
var _right_melee_time := -1.0
var _left_melee_duration := float(DAGGER_DATA.seconds)
var _right_melee_duration := 1.0
var _swing_start_hand: Array[Transform3D] = [Transform3D.IDENTITY,Transform3D.IDENTITY]
var _swing_start_valid: Array[bool] = [false,false]
## A diagonal pivots over the stance it starts in. The authored overhead's
## lunge would otherwise step the feet 0.3 m forward and slide the hips out of
## the actor's circle, so both ankles and the neutral hip offset are pinned for
## the whole swing and the legs re-solved onto them.
var _swing_stance: Array[Transform3D] = [Transform3D.IDENTITY,Transform3D.IDENTITY]
var _swing_stance_offset := Vector3.ZERO
var _swing_stance_valid := false
var _step_progress := -1.0
var _step_direction := Vector3.RIGHT
var _step_facing_hold := 0.0
var _hit_react := 0.0
var ability_id := ""
var ability_clip := ""
var ability_duration := 1.0
var ability_slot := -1
var ability_index := -1
var ability_lean := 0.0
var ability_spin := 0.0
var ability_draw_curve: Array = []
## Move-enabled abilities keep their authored upper body while the legs layer
## the normal locomotion cycle under them. `ability_travel` marks the committed
## lunge/charge window whose authored full-body travel must survive unchanged.
var ability_move := false
var ability_travel := 0.0
var _neutral_right_arm: Dictionary = {}
var _offhand_offset := Vector3(0.03,-0.23,0.28)
var _offhand_weapon_basis := Basis.IDENTITY
var _offhand_pole := Vector3(0.40,-0.20,0.50)
var _foot_height := Vector2.ZERO
var _foot_up: Array[Vector3] = []
var _built := false

func _ready() -> void:
	name = "Archer"
	_model = CHARACTER.instantiate()
	add_child(_model)
	_model.basis = Basis(Vector3.UP,PI)
	skeleton = _find_node_of_type(_model, "Skeleton3D") as Skeleton3D
	_player = _find_node_of_type(_model, "AnimationPlayer") as AnimationPlayer
	assert(skeleton != null and _player != null, "The ranger asset must contain its rig and authored animation library")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for index in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(index)] = index
		_blend_pose.append(Transform3D.IDENTITY)
		_authored_pose.append(skeleton.get_bone_pose(index))
		_crouch_pose.append(Transform3D.IDENTITY)
	for side in ["l", "r"]:
		_arms.append(PackedInt32Array([_bones["upperarm_"+side],_bones["lowerarm_"+side],_bones["hand_"+side]]))
		_legs.append(PackedInt32Array([_bones["thigh_"+side],_bones["calf_"+side],_bones["foot_"+side]]))
		for prefix in ["thigh_", "calf_", "foot_", "ball_", "ball_leaf_"]:
			_leg_bones.append(_bones[prefix+side])
	_leg_bones.append(_bones.pelvis)
	_lower_pose.resize(_leg_bones.size())
	for bone_name in ["pelvis","spine_01","spine_02","spine_03","neck_01","Head"]:
		_cover_bones.append(_bones[bone_name])
	_sample_clip(str(_profile.clips.cover_top.name),0.0)
	for bone in _cover_bones:
		_cover_neutral.append(skeleton.get_bone_global_pose(bone))
		_cover_turns.append(Basis.IDENTITY)
	var standing_pelvis := skeleton.get_bone_global_pose(_bones.pelvis).origin.y
	_sample_clip(str(_profile.clips.crouch_idle.name),0.0)
	_crouch_lowering = 0.58-(standing_pelvis-skeleton.get_bone_global_pose(_bones.pelvis).origin.y)
	for bone in skeleton.get_bone_count():
		_slide_crouch_pose.append(skeleton.get_bone_pose(bone))
	_palm_left = _vector(_profile.palms.left)
	_palm_right = _vector(_profile.palms.right)
	_jaw_bone = int(_bones[_profile.bow_anchor.bone])
	_jaw_offset = _vector(_profile.bow_anchor.position)
	var rotation: Array = _profile.sword_grip.rotation
	_sword_grip = Transform3D(Basis(Quaternion(rotation[0],rotation[1],rotation[2],rotation[3]).normalized()),_vector(_profile.sword_grip.position))
	_sword_grip_left = _mirror_transform(_sword_grip)
	_offhand_weapon_basis = Basis.looking_at(Vector3(0.0,-0.25,1.0).normalized(),Vector3.UP)
	for side in 2:
		var rest := skeleton.global_transform * skeleton.get_bone_global_rest(_legs[side][2])
		_foot_height[side] = rest.origin.y - global_position.y
		var thigh := skeleton.get_bone_global_rest(_legs[side][0]).origin
		var calf := skeleton.get_bone_global_rest(_legs[side][1]).origin
		_leg_lengths[side] = thigh.distance_to(calf)+calf.distance_to(skeleton.get_bone_global_rest(_legs[side][2]).origin)
		_foot_up.append(rest.basis.inverse() * Vector3.UP)
	for bone in skeleton.get_bone_count():
		var ancestor := bone
		while ancestor >= 0:
			if ancestor == int(_bones.clavicle_l) or ancestor == int(_bones.clavicle_r):
				_guard_bones.append(bone)
				_guard_pose.append(Transform3D.IDENTITY)
				break
			ancestor = skeleton.get_bone_parent(ancestor)
	_sample_clip("Sword_Idle_OneHand",0.0)
	for bone_name in ["clavicle_r","upperarm_r","lowerarm_r","hand_r"]:
		_neutral_right_arm[int(_bones[bone_name])] = skeleton.get_bone_pose(int(_bones[bone_name]))
	var carry_basis := global_basis * Basis(Vector3.RIGHT,-0.45)
	_bow_grip_basis = _bone_world(_arms[0][2]).basis.inverse() * carry_basis
	_string_grip_basis = _bone_world(_arms[1][2]).basis.inverse() * global_basis
	bow_hand = Node3D.new()
	bow_hand.name = "BowGrip"
	add_child(bow_hand)
	string_hand = Node3D.new()
	string_hand.name = "StringGrip"
	add_child(string_hand)
	for index in 3:
		var bow := Bow.new()
		bow.bow_kind = index
		bow.bow_length = float(BOW_DATA[index].length)
		add_child(bow)
		_bows.append(bow)
		var sword := Sword.new()
		sword.sword_kind = index
		sword.blade_length = float(SWORD_DATA[index].length)
		add_child(sword)
		_swords.append(sword)
	var dagger := Dagger.new()
	dagger.blade_length = float(DAGGER_DATA.length)
	add_child(dagger)
	dagger.visible = false
	var shield := Shield.new()
	shield.name = "Shield"
	add_child(shield)
	active_shield = shield
	active_bow = _bows[bow_index]
	active_sword = _swords[sword_index]
	active_dagger = dagger
	_build_weapon_visuals()
	active_off_weapon = active_dagger
	active_staff = _staffs[0]
	if off_weapon_active and off_weapon_kind != "dagger":
		active_off_weapon = _off_weapon_mesh()
	if staff_active:
		active_staff = _staffs[staff_index]
	if focus_active:
		active_focus = _focus_items.get(focus_kind,null)
	_build_equipment()
	_build_consumable_props()
	_built = true
	set_bow(bow_index)
	set_sword(sword_index)
	_apply_armor_visibility()
	_update_pose(0.0)

## Death hand-off for a corpse ragdoll: the skeleton goes fully limp, so the
## Archer's separately transformed props (bows, swords, shield, quiver,
## consumables) and bone-riding blood attachments can no longer follow it.
## Hide them and stop the physics-clock animation before the skin is simulated.
func enter_corpse_pose() -> void:
	set_physics_process(false)
	for child in get_children():
		if child == _model:
			continue
		if child is Node3D:
			(child as Node3D).visible = false
	if skeleton != null:
		for child in skeleton.get_children():
			if child is BoneAttachment3D:
				(child as BoneAttachment3D).visible = false


func _find_node_of_type(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for child in root.get_children():
		var found := _find_node_of_type(child,type_name)
		if found != null:
			return found
	return null

func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

func _mirror_transform(value: Transform3D) -> Transform3D:
	# The imported skeleton's left side is the exact X mirror of its right side.
	var mirror := Basis(Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,0,1))
	return Transform3D(mirror*value.basis*mirror,mirror*value.origin)

func _build_equipment() -> void:
	_chest = Node3D.new()
	add_child(_chest)
	_chest_rest_basis = (global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(_bones.spine_03)).basis
	var leather := Geo.material(Color("543d2c"))
	var trim := Geo.material(Color("be9454"),0.5,0.45)
	_quiver = Node3D.new()
	_quiver.position = Vector3(0.13,0.05,0.19)
	_quiver.rotation.z = -0.18
	_chest.add_child(_quiver)
	Geo.cylinder(_quiver,0.075,0.09,0.46,Vector3.ZERO,leather,12)
	Geo.cylinder(_quiver,0.094,0.094,0.04,Vector3(0,0.23,0),trim,12)
	for index in 5:
		var x := cos(index*2.4)*0.04
		var z := sin(index*2.4)*0.04
		Geo.beam(_quiver,Vector3(x,0.18,z),Vector3(x,0.47,z),0.004,trim,6)
		Geo.box(_quiver,Vector3(0.035,0.07,0.004),Vector3(x,0.43,z),trim)
	_build_armor_meshes()
	_attach_makeshift_armor()


## The salvage starter set ships as its own skinned GLB bound to a copy of this
## rig's skeleton, so adding a set never means rebuilding the hero asset. Each
## piece names the slot it covers; the runtime repoints its skin at the live
## skeleton and registers it exactly like the sets inside the ranger GLB.
const MAKESHIFT_ARMOR_SCENE := "res://assets/characters/armor/ironwood_makeshift.glb"
const MAKESHIFT_ARMOR_PIECES := {
	"head":"Armor_Makeshift_Head", "chest":"Armor_Makeshift_Chest",
	"hands":"Armor_Makeshift_Hands", "legs":"Armor_Makeshift_Legs",
	"feet":"Armor_Makeshift_Feet",
}


func _attach_makeshift_armor() -> void:
	var set_index := ArmorData.SET_IDS.find("makeshift")
	if set_index < 0:
		return
	if not ResourceLoader.exists(MAKESHIFT_ARMOR_SCENE):
		push_error("Missing Makeshift armour asset: " + MAKESHIFT_ARMOR_SCENE)
		return
	var packed := load(MAKESHIFT_ARMOR_SCENE) as PackedScene
	if packed == null:
		push_error("Makeshift armour asset is not a scene: " + MAKESHIFT_ARMOR_SCENE)
		return
	var instance := packed.instantiate() as Node3D
	_model.add_child(instance)
	# The imported pieces hang off their own skeleton node; leave that hierarchy
	# alone (a hidden parent hides the pieces) and only repoint each skin.
	for slot: String in MAKESHIFT_ARMOR_PIECES:
		var piece_name := str(MAKESHIFT_ARMOR_PIECES[slot])
		var piece := instance.find_child(piece_name, true, false) as MeshInstance3D
		if piece == null:
			push_error("Makeshift armour piece is missing: " + piece_name)
			continue
		piece.skeleton = piece.get_path_to(skeleton)
		piece.visible = false
		if _armor_meshes.has(slot):
			_armor_meshes[slot][set_index].append(piece)

func _build_consumable_props() -> void:
	var cloth := Geo.material(Color("ddd6c2"))
	var cloth_edge := Geo.material(Color("b7ad92"))
	_bandage_prop = Node3D.new()
	_bandage_prop.name = "BandageRoll"
	_bandage_prop.visible = false
	add_child(_bandage_prop)
	Geo.cylinder(_bandage_prop,0.036,0.036,0.105,Vector3.ZERO,cloth,12)
	Geo.cylinder(_bandage_prop,0.038,0.038,0.012,Vector3(0,0.049,0),cloth_edge,12)
	Geo.box(_bandage_prop,Vector3(0.085,0.003,0.19),Vector3(0,-0.018,0.09),cloth)
	Geo.sphere(_bandage_prop,0.038,Vector3(0,-0.052,0),cloth,Vector3(1.0,0.6,1.0))
	var glass := Geo.material(Color(0.42,0.68,0.64,0.75),0.2,0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var liquid := Geo.material(Color("b73f45"),0.1,0.45)
	var cork := Geo.material(Color("a8814f"))
	_potion_prop = Node3D.new()
	_potion_prop.name = "HealingPotion"
	_potion_prop.visible = false
	add_child(_potion_prop)
	Geo.cylinder(_potion_prop,0.033,0.033,0.085,Vector3(0,0.042,0),liquid,12)
	Geo.cylinder(_potion_prop,0.036,0.030,0.125,Vector3(0,0.062,0),glass,12)
	Geo.cylinder(_potion_prop,0.017,0.017,0.045,Vector3(0,0.145,0),glass,10)
	Geo.cylinder(_potion_prop,0.020,0.020,0.022,Vector3(0,0.176,0),cork,10)
	Geo.sphere(_potion_prop,0.018,Vector3(0,0.09,0),liquid)
	_update_consumable_props()

func begin_consumable(kind: String) -> bool:
	if not CONSUMABLE_DATA.has(kind):
		return false
	if phase != "READY" or _roll_progress >= 0.0 or is_melee():
		return false
	consumable_kind = kind
	phase = str(CONSUMABLE_DATA[kind].phase)
	_phase_time = 0.0
	draw_amount = 0.0
	charge_frozen = false
	_blocking = false
	_update_pose(0.0)
	return true

func end_consumable() -> void:
	if phase not in ["BANDAGE","DRINK"]:
		return
	phase = "READY"
	_phase_time = 0.0
	consumable_kind = ""
	_update_pose(0.0)

func cancel_consumable() -> void:
	if phase in ["BANDAGE","DRINK"]:
		end_consumable()

func is_consuming() -> bool:
	return phase in ["BANDAGE","DRINK"]

func begin_ability(definition: Dictionary, direction: Vector3) -> void:
	if not _built or definition.is_empty():
		return
	var clip := str(definition.get("animation", "Sprint_Loop"))
	ability_slot = int(definition.get("slot", 0))
	ability_index = AbilityRules.index_of(str(definition.get("id", "")))
	ability_id = str(definition.get("id", ""))
	ability_clip = clip if _player.has_animation(clip) else "Sprint_Loop"
	ability_duration = maxf(float(definition.get("duration", 1.0)),0.01)
	ability_lean = float(definition.get("lean",0.0))
	ability_spin = float(definition.get("spin",0.0))
	ability_draw_curve = definition.get("bow_draw", [])
	ability_move = bool(definition.get("move",false))
	ability_travel = maxf(float(definition.get("travel_seconds",0.0)),0.0)
	phase = "ABILITY"
	_phase_time = 0.0
	draw_amount = 0.0
	charge_frozen = false
	_blocking = false
	_clear_melee()
	consumable_kind = ""
	var planar := Vector3(direction.x,0.0,direction.z)
	# A blade skill or dash is performed standing, and the controller has already
	# stood the capsule up. Drop the leftover crouch blend so the authored clip
	# owns every bone from the first frame instead of being covered by the crouch
	# pose.
	if AbilityRules.needs_standing(definition):
		_crouch_amount = 0.0
		_slide_weight = 0.0
	if not ability_draw_curve.is_empty() or AbilityRules.follows_aim(definition):
		# Aim-directed skills are performed down the crosshair, not down the
		# heading that was carried into the keypress: turn onto the aim before
		# the first frame so the dash and its blade trail leave along it.
		var offset := _aim_point-global_position
		if Vector2(offset.x,offset.z).length_squared() > 0.0001:
			planar = Vector3(offset.x,0.0,offset.z)
	if planar.length_squared() > 0.000001:
		global_basis = Basis(Vector3.UP,atan2(-planar.x,-planar.z))
	_update_pose(0.0)

func is_ability() -> bool:
	return phase == "ABILITY"

## Move-enabled skills may keep walking under their authored upper body.
func ability_allows_movement() -> bool:
	return phase == "ABILITY" and ability_move

func ability_progress() -> float:
	return clampf(_phase_time/maxf(ability_duration,0.01),0.0,1.0)

## A release cue fires from the owning scene before this rig's own pose step,
## so a shot would read the previous frame's hand origin. Solve the pose on
## demand after the aim moved, keeping the shaft on the live crosshair.
func refresh_bow_pose() -> void:
	if not _built:
		return
	_update_pose(0.0)

func cancel_ability() -> void:
	if phase != "ABILITY":
		return
	_reset_ability_state()
	_update_pose(0.0)

func _reset_ability_state() -> void:
	phase = "READY"
	_phase_time = 0.0
	ability_id = ""
	ability_clip = ""
	ability_duration = 1.0
	ability_slot = -1
	ability_index = -1
	ability_lean = 0.0
	ability_spin = 0.0
	ability_draw_curve = []
	ability_move = false
	ability_travel = 0.0

func _update_consumable_props() -> void:
	if _bandage_prop == null or _potion_prop == null:
		return
	var consuming := is_consuming()
	_bandage_prop.visible = consuming and consumable_kind == "bandage"
	_potion_prop.visible = consuming and consumable_kind == "potion"
	if not consuming:
		return
	var socket := _bone_world(_arms[1][2]) * _sword_grip
	var prop := _bandage_prop if consumable_kind == "bandage" else _potion_prop
	prop.global_transform = Transform3D(socket.basis * Basis(Vector3.RIGHT,PI*0.5),socket.origin)

func _build_weapon_visuals() -> void:
	# Off-hand 1H swords are separate meshes from the main-hand set so both
	# hands can show the same sword size at once.
	for index in 2:
		var off := Sword.new()
		off.sword_kind = index
		off.blade_length = float(SWORD_DATA[index].length)
		add_child(off)
		off.visible = false
		_off_swords.append(off)
	for index in STAFF_DATA.size():
		var staff := Staff.new()
		staff.staff_kind = index
		staff.blade_length = float(STAFF_DATA[index].length)
		add_child(staff)
		staff.visible = false
		_staffs.append(staff)
	for kind in ["tome", "skull", "skull_life", "skull_death"]:
		var focus := FocusItem.new()
		focus.focus_kind = kind
		add_child(focus)
		focus.visible = false
		_focus_items[kind] = focus

func set_bow(index: int) -> void:
	cancel_consumable()
	bow_index = clampi(index,0,2)
	if not _built:
		return
	active_bow = _bows[bow_index]
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_sword(index: int) -> void:
	cancel_consumable()
	if is_melee():
		_clear_melee()
		phase = "READY"
		_phase_time = 0.0
	# Selecting a sword is the session hand-off away from a staff. The persistent
	# loadout re-activates the staff after this call.
	staff_active = false
	sword_index = clampi(index,0,2)
	if weapon == "dual" and sword_index == 2:
		# The greatsword needs both hands; fall back to the one-handed sword mode.
		weapon = "sword"
	if shield_equipped and not can_equip_shield():
		shield_equipped = false
		_blocking = false
	if not _built:
		return
	active_sword = _swords[sword_index]
	_set_blade_skin(active_sword, sword_skin if sword_index == 0 else "")
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

## Swap the held blade's model family without changing its combat profile: the
## salvage cleaver and shiv are class-equivalent to the iron pieces.
func set_blade_skins(sword_family: String, dagger_family: String) -> void:
	sword_skin = sword_family
	dagger_skin = dagger_family
	if not _built:
		return
	for index in _swords.size():
		_set_blade_skin(_swords[index], sword_skin if index == 0 else "")
	_set_blade_skin(active_dagger, dagger_skin)


## The blade scripts own set_skin(); the rig only holds Node3D references, so
## this is a dynamic call rather than a typed one.
func _set_blade_skin(node: Node3D, family: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.call("set_skin", family)

func set_weapon(value: String) -> bool:
	cancel_consumable()
	if value not in ["bow","sword","dagger","dual","none"]:
		return false
	if value != "dual":
		main_hand_kind = value
	if value == "dual" and shield_equipped and off_weapon_active:
		# A raised shield is stowed when a legal off-hand weapon enters dual.
		shield_equipped = false
		_blocking = false
	if value == "dual" and not _dual_ready():
		return false
	if value == weapon:
		# Pressing the sword key while a staff supplies this same "sword" mode
		# must still hand the session back to the actual sword.
		if value == "sword" and staff_active:
			staff_active = false
			_sync_weapon_visibility()
			_update_pose(0.0)
		return true
	_clear_melee()
	if phase not in ["RELEASE","RECOVER","T_RELEASE","T_RECOVER"]:
		phase = "READY"
		_phase_time = 0.0
		draw_amount = 0.0
	_melee_hand = "right"
	_blocking = false
	weapon = value
	if shield_equipped and not can_equip_shield():
		shield_equipped = false
	set_bow(bow_index)
	set_sword(sword_index)
	_sync_weapon_visibility()
	return true

func apply_loadout(loadout: Dictionary) -> void:
	# Session hand-off from PlayerState.loadout(): armor, main mode, off item
	# and the matching pose. Pure presentation; every setter keeps its own
	# legality checks, so a malformed dict degrades instead of crashing.
	var mode := str(loadout.get("weapon",""))
	var main_id := str(loadout.get("main",""))
	var off_id := str(loadout.get("off",""))
	apply_trinkets(loadout.get("trinkets",{}))
	set_blade_skins("makeshift" if main_id == "sword_makeshift" else "",
		"makeshift" if main_id == "dagger_makeshift" or off_id == "dagger_makeshift" else "")
	var staff_value := int(loadout.get("staff",-1))
	var bow_value := int(loadout.get("bow",0))
	var sword_value := int(loadout.get("sword",0))
	var shield_on := bool(loadout.get("shield",false))
	set_armor_pieces(loadout.get("armor",{}))
	set_staff(0,false)
	set_off_focus("",0,false)
	set_off_weapon("",0,false)
	set_shield(false)
	set_bow(bow_value)
	set_sword(sword_value)
	var focus: Dictionary = loadout.get("focus",{})
	if focus.has("kind"):
		set_off_focus(str(focus.get("kind","")),int(focus.get("index",0)),true)
	var off_weapon: Dictionary = loadout.get("off_weapon",{})
	if off_weapon.has("kind"):
		set_off_weapon(str(off_weapon.get("kind","")),int(off_weapon.get("index",0)),true)
	if shield_on:
		set_shield_variant(_shield_variant_for(off_id))
	var dual_ready := sword_value <= 1 and staff_value < 0 and not focus_active \
		and off_weapon_active and off_weapon_kind in ["dagger","sword"]
	match mode:
		"bow":
			set_weapon("bow")
			set_sword(0)
		"dagger":
			set_weapon("dagger")
			set_sword(0)
		"sword":
			set_weapon("sword")
			if dual_ready:
				set_weapon("dual")
		"dual":
			set_weapon("sword")
			set_weapon("dual")
		_:
			set_weapon("none")
	if shield_on:
		set_shield(true)
	# Activate the staff after the mode selection: set_sword() intentionally
	# stows a staff, and a fresh loadout must be able to replace that session
	# hand-off with the paperdoll's main-hand staff.
	if staff_value >= 0:
		set_staff(staff_value,true)
	_update_pose(0.0)
	_sync_weapon_visibility()

func set_staff(index: int, active: bool) -> void:
	staff_index = clampi(index,0,STAFF_DATA.size()-1)
	staff_active = active
	active_staff = _staffs[staff_index] if not _staffs.is_empty() else null
	if not _built:
		return
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_off_weapon(kind: String, index: int, active: bool) -> void:
	off_weapon_kind = kind if kind in ["dagger","sword"] else ""
	off_weapon_index = clampi(index,0,1)
	off_weapon_active = active and not off_weapon_kind.is_empty()
	active_off_weapon = _off_weapon_mesh()
	if weapon == "dual" and not _dual_ready():
		_clear_melee()
		weapon = "sword"
		_sync_primary_hand()
	if not _built:
		return
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_off_focus(kind: String, index: int, active: bool) -> void:
	focus_kind = kind if kind in ["tome","skull","skull_life","skull_death"] else ""
	focus_index = clampi(index,0,3)
	focus_active = active and not focus_kind.is_empty()
	active_focus = _focus_items.get(focus_kind,null) if focus_active else null
	if focus_active and weapon == "dual":
		_clear_melee()
		weapon = "sword"
		_sync_primary_hand()
	if not _built:
		return
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_shield_variant(index: int) -> void:
	shield_variant = clampi(index,0,2)
	if active_shield != null and active_shield.has_method("set_variant"):
		active_shield.set_variant(shield_variant)
	if not _built:
		return
	_update_pose(0.0)

func _shield_variant_for(item_id: String) -> int:
	match item_id:
		"shield_buckler":
			return 0
		"shield_tower":
			return 2
	return 1

func _off_weapon_mesh() -> Node3D:
	if not off_weapon_active:
		return null
	if off_weapon_kind == "sword":
		return _off_swords[off_weapon_index] if _off_swords.size() > off_weapon_index else null
	if off_weapon_kind == "dagger":
		return active_dagger
	return null

func _dual_ready() -> bool:
	return main_hand_kind != "none" and sword_index <= 1 and staff_active == false \
		and not focus_active and not shield_equipped \
		and off_weapon_active and off_weapon_kind in ["dagger","sword"]

func _staff_shown() -> bool:
	return staff_active and weapon == "sword"

func _off_profile() -> Dictionary:
	if off_weapon_kind == "sword":
		return SWORD_DATA[off_weapon_index]
	return DAGGER_DATA

func _left_blade_node() -> Node3D:
	if active_off_weapon != null:
		return active_off_weapon
	return active_dagger

func _focus_supported() -> bool:
	# A held focus is a two-slot loadout: one-handed main, nothing blocking or
	# dual-wielded, and no action pose that owns the left arm.
	if weapon not in ["sword","dagger"] or sword_index > 1:
		return false
	if shield_equipped or staff_active or _roll_progress >= 0.0:
		return false
	return phase not in ["DRAWING","HOLDING","RELEASE","RECOVER"]

func _sync_weapon_visibility() -> void:
	# A thrown weapon leaves the hand for its release frame, then the endless
	# supply restores the same equipped weapon as the recovery begins.
	var hidden := phase == "T_RELEASE"
	var consuming := is_consuming()
	var staff_shown := _staff_shown()
	var left_shown := weapon == "dual" and off_weapon_active and off_weapon_kind in ["dagger","sword"]
	for i in _swords.size():
		_swords[i].visible = weapon in ["sword","dual"] and i == sword_index and not hidden and not staff_shown and not consuming
	for i in _bows.size():
		_bows[i].visible = weapon == "bow" and i == bow_index and not consuming
	for i in _staffs.size():
		_staffs[i].visible = staff_shown and i == staff_index and not hidden and not consuming
	if active_dagger != null:
		active_dagger.visible = ((weapon == "dagger" and not hidden) \
			or (left_shown and off_weapon_kind == "dagger")) and not consuming
	for i in _off_swords.size():
		_off_swords[i].visible = left_shown and off_weapon_kind == "sword" and i == off_weapon_index and not consuming
	var focus_shown := focus_active and _focus_supported() and not consuming
	for key: String in _focus_items:
		_focus_items[key].visible = focus_shown and key == focus_kind
	if active_shield != null:
		active_shield.set_active(shield_equipped and not consuming and is_visible_in_tree())

## Hand-above weapon node used for blood coating. Only the weapon actually
## drawn in that hand is stained, so a stowed sword keeps its clean steel.
func blood_weapon_anchor(hand: String = "") -> Node3D:
	if staff_active and is_instance_valid(active_staff) and active_staff.visible:
		return active_staff
	if weapon == "dual" and hand == "left":
		return active_off_weapon if is_instance_valid(active_off_weapon) \
			and active_off_weapon.visible else null
	if weapon == "dagger":
		return active_dagger if is_instance_valid(active_dagger) \
			and active_dagger.visible else null
	if weapon in ["sword","dual"]:
		return active_sword if is_instance_valid(active_sword) \
			and active_sword.visible else null
	return null

func _build_armor_meshes() -> void:
	# The imported leather outfit is split across the same five slots as the
	# generated shells.  Arrows/head/face/hair stay outside every group.
	var source_slots := {
		"Male_Ranger_Head_Hood": "head",
		"Male_Ranger_Body": "chest",
		"Male_Ranger_Body_Belt_1": "chest",
		"Male_Ranger_Body_Belt_2": "chest",
		"Male_Ranger_Acc_Pauldron": "chest",
		"Male_Ranger_Arms": "chest",
		"Male_Ranger_Arms_Bracer": "hands",
		"Male_Ranger_Legs": "legs",
		"Male_Ranger_Feet_Boots": "feet",
	}
	for slot in ArmorData.SLOTS:
		_armor_meshes[slot] = {}
		for set_index in ArmorData.SET_IDS.size():
			_armor_meshes[slot][set_index] = []
	for node in _model.find_children("*","MeshInstance3D",true,false):
		var mesh_name := str(node.name)
		var slot := str(source_slots.get(mesh_name,""))
		var set_index := 0 if not slot.is_empty() else -1
		if mesh_name.begins_with("Armor_"):
			var parts := mesh_name.split("_")
			if parts.size() >= 3:
				set_index = ArmorData.SET_IDS.find(parts[1].to_lower())
				slot = parts[2].to_lower()
		if set_index >= 0 and _armor_meshes.has(slot):
			_armor_meshes[slot][set_index].append(node)
	var generated: Dictionary = _profile.get("armor",{}).get("generated",{})
	for set_name: String in generated:
		var set_index := ArmorData.SET_IDS.find(set_name)
		if set_index < 0:
			continue
		for slot: String in generated[set_name]:
			if not _armor_meshes.has(slot):
				continue
			for mesh_name: String in generated[set_name][slot]:
				var node := _model.find_child(mesh_name,true,false)
				if node is MeshInstance3D and not _armor_meshes[slot][set_index].has(node):
					_armor_meshes[slot][set_index].append(node)

func _apply_armor_visibility() -> void:
	for slot in ArmorData.SLOTS:
		var active := int(armor_pieces.get(slot,0))
		for set_index: int in _armor_meshes.get(slot,{}):
			for node: Node3D in _armor_meshes[slot][set_index]:
				node.visible = set_index == active

func set_armor_piece(slot: String, set_index: int) -> void:
	cancel_consumable()
	if slot not in ArmorData.SLOTS:
		return
	armor_pieces[slot] = clampi(set_index,0,ArmorData.SET_IDS.size()-1)
	if _built:
		_apply_armor_visibility()
	loadout_changed.emit()

func set_armor_pieces(pieces: Dictionary) -> void:
	cancel_consumable()
	for slot in ArmorData.SLOTS:
		armor_pieces[slot] = clampi(int(pieces.get(slot,0)),0,ArmorData.SET_IDS.size()-1)
	if _built:
		_apply_armor_visibility()
	loadout_changed.emit()

func set_armor(index: int) -> void:
	cancel_consumable()
	# Convenience for tests and whole-set loadouts: every slot uses one set.
	var value := clampi(index,0,ArmorData.SET_IDS.size()-1)
	for slot in ArmorData.SLOTS:
		armor_pieces[slot] = value
	if _built:
		_apply_armor_visibility()
	loadout_changed.emit()

func set_armor_bits(bits: int) -> void:
	set_armor_pieces(ArmorData.unpack(bits & ArmorData.PIECE_MASK))

func armor_bits() -> int:
	return ArmorData.pack(armor_pieces)

func armor_piece(slot: String) -> int:
	return int(armor_pieces.get(slot,0))

func armor_reduction() -> float:
	return ArmorData.reduction(armor_pieces)

func can_equip_shield() -> bool:
	# Any one-handed sword or the dagger can carry the shield; the 2H
	# greatsword, staff, bow and dual wield still cannot.
	return weapon == "dagger" or (weapon == "sword" and sword_index <= 1)

func set_shield(active: bool) -> bool:
	cancel_consumable()
	var allowed := active and can_equip_shield()
	if shield_equipped == allowed:
		return shield_equipped
	shield_equipped = allowed
	if not allowed:
		_blocking = false
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()
	return shield_equipped

func is_melee() -> bool:
	return has_melee("left") or has_melee("right")

func has_melee(hand: String) -> bool:
	return (_left_melee_time >= 0.0) if hand == "left" else (_right_melee_time >= 0.0)

func melee_progress_for(hand: String) -> float:
	var time := _left_melee_time if hand == "left" else _right_melee_time
	if time < 0.0:
		return 1.0
	var duration := _left_melee_duration if hand == "left" else _right_melee_duration
	return clampf(time/maxf(duration,0.001),0.0,1.0)

func _right_phase() -> String:
	match _right_variant:
		"diagonal_left":
			return "MELEE_DL"
		"diagonal_right":
			return "MELEE_DR"
		"stab":
			return "MELEE_ST"
	return "MELEE"

func _sync_primary_hand() -> void:
	if _right_melee_time >= 0.0:
		phase = _right_phase()
		_melee_hand = "right"
		_phase_time = _right_melee_time
	elif _left_melee_time >= 0.0:
		phase = "MELEE_L"
		_melee_hand = "left"
		_phase_time = _left_melee_time
	else:
		phase = "READY"
		_melee_hand = "right"
		_phase_time = 0.0

func _duration_for(hand: String, variant: String) -> float:
	var dagger := off_weapon_kind != "sword" if hand == "left" else weapon == "dagger"
	var size := off_weapon_index if hand == "left" else sword_index
	var base := float(SWORD_DATA[size].seconds)
	if variant in ["diagonal_left","diagonal_right"]:
		base = 0.42 if dagger else float(DIAGONAL_SECONDS[size])
	elif variant == "stab" or dagger:
		base = float(DAGGER_DATA.seconds)
	return base/maxf(attack_rate(),0.01)

func _valid_variant(variant: String) -> bool:
	return variant in MELEE_VARIANTS

func melee_variant(hand: String) -> String:
	return _left_variant if hand == "left" else _right_variant

func is_diagonal_swing(hand: String) -> bool:
	return has_melee(hand) and melee_variant(hand) in ["diagonal_left","diagonal_right"]

## Fraction of the strike arc the blade has travelled. The load holds it at
## zero, the release is front-loaded (about three quarters of the arc inside
## its own 15% slice) and the follow-through decelerates into the overshoot.
func _swing_drive(progress: float) -> float:
	var p := (progress-SWING_LOAD_END)/(SWING_FOLLOW_END-SWING_LOAD_END)
	if p <= 0.0:
		return 0.0
	if p >= 1.0:
		return 1.0
	# A whip, not a hinge: the arc is front-loaded so the stroke clears most of
	# its travel inside the release slice, while the blended smoothstep keeps
	# the peak speed near the centre line and the acceleration ramped.
	var whip := 1.0-pow(1.0-p,2.6)
	return (whip*0.62+smoothstep(0.0,1.0,p)*0.38)*smoothstep(0.0,0.10,p)

## A joint that leads the blade by `lead` clip fractions; a negative lead trails.
func _swing_chain(progress: float, lead: float) -> float:
	return _swing_drive(progress-lead)

func melee_cut_progress(hand: String) -> float:
	var time := _left_melee_time if hand == "left" else _right_melee_time
	return clampf(time/maxf(melee_seconds(hand),0.001),0.0,1.0)

func melee_cut_curve(hand: String) -> float:
	return _swing_chain(melee_cut_progress(hand),SWING_CHAIN_BLADE)

func melee_half_angle(hand: String) -> float:
	var dagger := off_weapon_kind != "sword" if hand == "left" else weapon == "dagger"
	var size := off_weapon_index if hand == "left" else sword_index
	return deg_to_rad(75.0 if dagger else 80.0+5.0*size)

func can_begin_melee(hand: String) -> bool:
	if _roll_progress >= 0.0 or is_consuming():
		return false
	if hand == "left":
		if weapon != "dual" or _left_melee_time >= 0.0:
			return false
		return phase == "READY" or (phase.begins_with("MELEE") and phase != "MELEE_L")
	if weapon not in ["sword","dagger","dual"] or _right_melee_time >= 0.0:
		return false
	return phase == "READY" or phase == "MELEE_L"

func begin_melee(hand: String = "right", variant: String = "overhead") -> bool:
	var key := "left" if hand == "left" else "right"
	if not can_begin_melee(key):
		return false
	# A second hand joining an overlapping dual cut keeps the stance it inherited.
	if not is_melee():
		_swing_stance_valid = false
	var requested := variant if _valid_variant(variant) else "overhead"
	if key == "left":
		_left_variant = requested
		_left_melee_duration = _duration_for(key,requested)
		_left_melee_time = 0.0
	else:
		_right_variant = requested
		_right_melee_duration = _duration_for(key,requested)
		_right_melee_time = 0.0
	_swing_start_valid[0 if key == "left" else 1] = false
	_sync_primary_hand()
	melee_started.emit(key)
	_update_pose(0.0)
	return true

func abort_melee(hand: String) -> void:
	if hand == "left":
		_left_melee_time = -1.0
	else:
		_right_melee_time = -1.0
	_sync_primary_hand()
	_update_pose(0.0)

func _clear_melee() -> void:
	_left_melee_time = -1.0
	_right_melee_time = -1.0
	_swing_start_valid.fill(false)
	_swing_stance_valid = false

func melee_seconds(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return _left_melee_duration if _left_melee_time >= 0.0 else float(_off_profile().seconds)
	if _right_melee_time >= 0.0:
		return _right_melee_duration
	if weapon == "dagger":
		return float(DAGGER_DATA.seconds)
	return float(SWORD_DATA[sword_index].seconds)

func melee_damage(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	var base := float(SWORD_DATA[sword_index].damage)
	if key == "left":
		base = float(_off_profile().damage)
	elif weapon == "dagger":
		base = float(DAGGER_DATA.damage)
	return base*melee_scale()

## Trinket modifiers read by the controllers, `Combat` and the ability cues.
func apply_trinkets(kit: Dictionary) -> void:
	trinkets = TrinketStats.kit(kit)
	trinket_stats = TrinketStats.sum(trinkets)

func melee_scale() -> float:
	return TrinketStats.damage_scale(trinket_stats,"melee_damage")

func ranged_scale() -> float:
	return TrinketStats.damage_scale(trinket_stats,"ranged_damage")

func throw_scale() -> float:
	return TrinketStats.damage_scale(trinket_stats,"throw_damage")

## Rate multiplier: a 1.0 s draw becomes `1.0 / attack_rate()` seconds.
func attack_rate() -> float:
	return TrinketStats.attack_rate(trinket_stats)

func move_scale() -> float:
	return TrinketStats.move_scale(trinket_stats)

func damage_reduction() -> float:
	return TrinketStats.damage_reduction(armor_reduction(),trinket_stats)

## The yellow ward bubble. Presentation only: the absorbing share lives on the
## actor that owns the health.
func set_ward(active: bool) -> void:
	if active and not is_instance_valid(_ward):
		_ward = EnergyShield.new()
		add_child(_ward)
	if is_instance_valid(_ward):
		_ward.visible = active

func melee_reach(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return float(_off_profile().reach)
	if weapon == "dagger":
		return float(DAGGER_DATA.reach)
	if _staff_shown():
		return float(STAFF_REACH[staff_index])
	return float(SWORD_DATA[sword_index].reach)

func melee_radius(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return (0.035 + 0.011 * off_weapon_index) if off_weapon_kind == "sword" else 0.022
	if weapon == "dagger":
		return 0.022
	return 0.035 + 0.011 * sword_index

func begin_draw() -> void:
	if weapon != "bow" or phase != "READY" or _roll_progress >= 0.0:
		return
	draw_amount = 0.0
	charge_frozen = false
	phase = "DRAWING"
	_phase_time = 0.0
	_update_pose(0.0)

func begin_throw() -> bool:
	if staff_active or weapon not in ["sword","dagger","dual"] or phase != "READY" or _roll_progress >= 0.0:
		return false
	draw_amount = 0.0
	charge_frozen = false
	phase = "T_DRAW"
	_phase_time = 0.0
	_update_pose(0.0)
	return true

func charge_seconds() -> float:
	var base := float(SWORD_DATA[sword_index].seconds)
	if weapon == "bow":
		base = float(BOW_DATA[bow_index].draw_seconds)
	elif weapon == "dagger":
		base = float(DAGGER_DATA.seconds)
	return base/maxf(attack_rate(),0.01)

func throw_weapon_name() -> String:
	return "dagger" if weapon == "dagger" else "sword"

func throw_speed() -> float:
	return float(DAGGER_DATA.throw_speed) if weapon == "dagger" else float(SWORD_DATA[sword_index].throw_speed)

func get_throw_origin() -> Vector3:
	if weapon == "dagger":
		return active_dagger.global_position
	if _staff_shown():
		return active_staff.global_position
	return active_sword.global_position

func cast_origin() -> Vector3:
	# The staff mesh runs down its local -Z from the grip; the live ember/bone
	# head sits near the far end. Spells leave from there instead of the wrist.
	if _staff_shown() and active_staff != null:
		# The staff mesh runs from local z=-0.09 down its blade length; the
		# socket already carries the middle-grip offset, so the live head is
		# only ~0.7 m in front of the hand.
		var head := -0.09-float(active_staff.blade_length)
		return active_staff.to_global(Vector3(0.0, 0.0, head))
	if weapon == "bow" and active_bow != null:
		return active_bow.get_arrow_origin()
	return get_throw_origin()

func get_recovery_progress() -> float:
	var duration := RELEASE_SECONDS + RECOVER_SECONDS
	if phase in ["RELEASE","T_RELEASE"]:
		return clampf(_phase_time/duration,0,1)
	if phase in ["RECOVER","T_RECOVER"]:
		return clampf((RELEASE_SECONDS+_phase_time)/duration,0,1)
	return 1.0

func release_string(override_origin: Vector3 = Vector3.INF, override_direction: Vector3 = Vector3.ZERO) -> void:
	if phase not in ["DRAWING","HOLDING"]:
		return
	charge_frozen = false
	_release_charge = clampf(draw_amount,0,1)
	_release_draw = draw_amount
	_release_raise = _archery_weight()
	_release_grip = to_local(active_bow.global_position)
	_release_contact = to_local(string_hand.global_position)
	_release_bow_rotation = (global_basis.inverse()*active_bow.global_basis).get_rotation_quaternion()
	var visual_origin := get_arrow_origin()
	var origin := visual_origin
	var direction := (_aim_point-origin).normalized()
	if override_origin.is_finite() and override_direction.length_squared() > 0.5:
		origin = override_origin
		direction = override_direction.normalized()
	elif direction.length_squared() < 0.0001:
		direction = active_bow.get_arrow_direction()
	# The rendered arrow leaves from the bow; the physics arrow leaves along the
	# validated crosshair ray. Arrow blends one to the other over a few frames.
	last_arrow_visual_origin = visual_origin
	phase = "RELEASE"
	_phase_time = 0.0
	active_bow.set_arrow_visible(false)
	arrow_released.emit(origin,direction,float(BOW_DATA[bow_index].speed)*lerpf(0.45,1.0,_release_charge),_release_charge)
	_update_pose(0.0)

func release_throw() -> void:
	if phase not in ["T_DRAW","T_HOLD"] or weapon not in ["sword","dagger","dual"]:
		return
	charge_frozen = false
	_release_charge = clampf(draw_amount,0,1)
	_release_draw = draw_amount
	var origin := get_throw_origin()
	var direction := (_aim_point-origin).normalized()
	if direction.length_squared() < 0.0001:
		direction = -global_basis.z
	phase = "T_RELEASE"
	_phase_time = 0.0
	# Endless supply: the equipped weapon is never consumed, only a flying copy
	# leaves the hand. Damage scales with charge exactly like a bow draw.
	var thrown_name := throw_weapon_name()
	weapon_thrown.emit(origin,direction,throw_speed()*lerpf(0.45,1.0,_release_charge),_release_charge,thrown_name,sword_index if thrown_name == "sword" else 0)
	_update_pose(0.0)

func cancel_draw() -> void:
	charge_frozen = false
	cancel_consumable()
	if phase not in ["DRAWING","HOLDING","T_DRAW","T_HOLD"] and not phase.begins_with("MELEE"):
		return
	_clear_melee()
	phase = "READY"
	draw_amount = 0.0
	_phase_time = 0.0
	_update_pose(0.0)

func aim_at(world_point: Vector3) -> void:
	_aim_point = world_point
	if _built and phase != "READY":
		_update_pose(0.0)

func set_roll(progress: float, direction: Vector3) -> void:
	# See `set_step`: an unchanged "not rolling" must not rebuild the pose.
	if progress < 0.0 and _roll_progress < 0.0:
		return
	_roll_progress = progress
	if progress >= 0.0:
		global_basis = Basis(Vector3.UP,atan2(-direction.x,-direction.z))
	_update_pose(0.0)

func set_hit_react(seconds: float) -> void:
	if seconds <= 0.0:
		_hit_react = 0.0
	else:
		_hit_react = maxf(_hit_react,seconds)
		cancel_consumable()
	_update_pose(0.0)

func set_step(progress: float, direction: Vector3) -> void:
	# The tick reports "not stepping" every frame. Rebuilding the pose for an
	# unchanged state was a tenth of a millisecond a frame; the animation clock
	# already refreshes the pose, so only a real change needs to force one.
	if progress < 0.0 and _step_progress < 0.0:
		return
	_step_progress = clampf(progress,0.0,1.0) if progress >= 0.0 else -1.0
	if _step_progress >= 0.0:
		var planar := Vector3(direction.x,0.0,direction.z)
		if not planar.is_zero_approx():
			_step_direction = planar.normalized()
		# The step's own momentum is still decaying on the next few ticks.
		# Keep the facing latched so the exit does not snap the root into the
		# step direction and undo the whole side-step silhouette.
		_step_facing_hold = 0.20
	_update_pose(0.0)

func set_slide(progress: float, direction: Vector3) -> void:
	slide_progress = clampf(progress,0.0,1.0) if progress >= 0.0 else -1.0
	if slide_progress >= 0.0:
		var planar := Vector3(direction.x,0.0,direction.z)
		if not planar.is_zero_approx():
			_slide_direction = planar.normalized()
		if phase == "READY" and _roll_progress < 0.0:
			global_basis = Basis(Vector3.UP,atan2(-_slide_direction.x,-_slide_direction.z))
	elif _crouch_amount <= 0.0 or _cover_active:
		_slide_weight = 0.0

func set_cover(active: bool, outward: Vector3, crouch_amount: float, peeking: bool, lean: Vector3) -> void:
	_cover_active = active
	_cover_normal = outward
	_cover_lean = lean if active else Vector3.ZERO
	_crouch_amount = clampf(crouch_amount,0.0,1.0)
	if active and (phase == "READY" or not peeking):
		global_basis = Basis(Vector3.UP,atan2(-outward.x,-outward.z))

func set_blocking(active: bool, forward: Vector3 = Vector3.ZERO) -> void:
	_blocking = active and weapon in ["sword","dagger"]
	if _blocking:
		face_block(forward)
	_update_pose(0.0)

func face_block(forward: Vector3) -> void:
	if not _blocking:
		return
	var planar := Vector3(forward.x,0.0,forward.z)
	if planar.length_squared() > 0.000001:
		_block_forward = planar.normalized()
		global_basis = Basis(Vector3.UP,atan2(-planar.x,-planar.z))

func is_blocking() -> bool:
	return _blocking

func in_strike_window(hand: String = "") -> bool:
	if hand in ["left","right"]:
		var time := _left_melee_time if hand == "left" else _right_melee_time
		if time < 0.0:
			return false
		if hand == "left" and weapon != "dual":
			return false
		if hand == "right" and weapon not in ["sword","dagger","dual"]:
			return false
		var window := _melee_window(hand)
		return time >= window.x-0.000001 and time <= window.y+0.000001
	return (has_melee("left") and in_strike_window("left")) \
		or (has_melee("right") and in_strike_window("right"))

func set_locomotion(world_velocity: Vector3, grounded: bool) -> void:
	if grounded and not _grounded and _velocity.y < -1.0:
		_landing_weight = 1.0
	if not grounded and _grounded:
		_air_time = 0.0
	_velocity = world_velocity
	_grounded = grounded
	if not _cover_active and not _blocking and not is_consuming() and phase == "READY" and _roll_progress < 0.0 and slide_progress < 0.0 and _step_progress < 0.0 and _step_facing_hold <= 0.0 and Vector2(world_velocity.x,world_velocity.z).length_squared() > 0.01:
		# A quick step keeps the original facing; its travel is applied by the
		# hips and shoulders below instead of snapping the whole body sideways.
		global_basis = Basis(Vector3.UP,atan2(-world_velocity.x,-world_velocity.z))

func set_ground_sampler(sampler: Callable) -> void:
	_ground_sampler = sampler

## Wire order of the replicated animation state. The snapshot carries the
## values positionally: eighteen key strings cost more than the fields they
## name, and one fighter datagram must stay inside the clamped payload.
const ANIMATION_KEYS := ["phase","draw","charge_frozen","time","aim",
	"release_draw","release_charge","release_raise","release_grip","release_contact",
	"release_rotation","yaw","roll","slide","motion_time","locomotion_phase",
	"air_time","landing"]
## Position of "roll" in ANIMATION_KEYS, read per replica without a search.
const ANIM_ROLL := 12

func pack_animation_state(state: Dictionary) -> Array:
	var packed: Array = []
	packed.resize(ANIMATION_KEYS.size())
	for index in ANIMATION_KEYS.size():
		packed[index] = state.get(ANIMATION_KEYS[index])
	return packed

static func unpack_animation_state(packed: Array) -> Dictionary:
	var state := {}
	for index in mini(ANIMATION_KEYS.size(),packed.size()):
		state[ANIMATION_KEYS[index]] = packed[index]
	return state

## The roll clock of a wire state or a local dictionary.
static func animation_roll(state: Variant) -> float:
	if typeof(state) == TYPE_ARRAY:
		var packed: Array = state
		return float(packed[ANIM_ROLL]) if packed.size() > ANIM_ROLL else -1.0
	if typeof(state) == TYPE_DICTIONARY:
		return float((state as Dictionary).get("roll",-1.0))
	return -1.0

func get_animation_state() -> Dictionary:
	# Roll facing already travels in yaw; compact slide state also fits maximum-length names.
	# Guard rides in the presentation phase instead of another payload field:
	# gameplay still sees READY, while replicas show the sword guard pose.
	# The idle draw scalar packs left variant (2 bits) and elapsed milliseconds.
	# Zero elapsed code means inactive; right phase/time remains full precision.
	var melee_secondary := draw_amount
	if is_melee():
		var variant_code := MELEE_VARIANTS.find(_left_variant)
		var elapsed_code := int(round(_left_melee_time*1000.0))+1 if _left_melee_time >= 0.0 else 0
		melee_secondary = float((elapsed_code << 2) | variant_code)
	elif is_ability():
		# Slot (1..2, low two bits) and the ability's table index (high bits)
		# ride in the existing draw scalar; time carries the elapsed clock, so
		# item-granted clips replicate without another snapshot key.
		melee_secondary = float(((maxi(ability_index,0)+1) << 2) | (ability_slot+1))
	var presentation := "GUARD" if _blocking else phase
	var presentation_time := _phase_time
	if _hit_react > 0.0001 and phase == "READY" and not _blocking:
		# STAGGER rides in the existing phase string; time carries the remaining
		# reaction, so the flinch costs no extra snapshot key. An attack that is
		# already active owns the pose instead.
		presentation = "STAGGER"
		presentation_time = _hit_react
	elif _step_progress >= 0.0 and phase == "READY" and not _blocking:
		# The quick step also rides in the phase string. Time carries its
		# progress, so replicas get the shoulder turn with no extra payload key.
		presentation = "STEP"
		presentation_time = _step_progress
	return {"phase":presentation,"draw":melee_secondary,"charge_frozen":charge_frozen,"time":presentation_time,"aim":_aim_point,
		"release_draw":_release_draw,"release_charge":_release_charge,"release_raise":_release_raise,
		"release_grip":_release_grip,"release_contact":_release_contact,"release_rotation":_release_bow_rotation,
		"yaw":global_rotation.y,"roll":_roll_progress,
		"slide":Vector4(slide_progress,_slide_direction.x,_slide_direction.z,_slide_weight),
		"motion_time":_motion_time,"locomotion_phase":_locomotion_phase,"air_time":_air_time,"landing":_landing_weight}

func apply_animation_state(state: Variant) -> void:
	# The wire carries the packed values; local callers and tests hand in the
	# dictionary get_animation_state() builds.
	if typeof(state) == TYPE_ARRAY:
		state = unpack_animation_state(state)
	var replicated_phase := str(state.phase)
	var guard_phase := replicated_phase == "GUARD"
	var step_phase := replicated_phase == "STEP"
	var consume_phase := replicated_phase in ["BANDAGE","DRINK"]
	_blocking = guard_phase and weapon in ["sword","dagger"]
	if replicated_phase.begins_with("MELEE"):
		var packed := int(state.draw)
		var incoming_left: String = MELEE_VARIANTS[packed & 3]
		if incoming_left != _left_variant:
			_swing_start_valid[0] = false
			_swing_stance_valid = false
		_left_variant = incoming_left
		_left_melee_duration = _duration_for("left",_left_variant)
		var elapsed_code := packed >> 2
		if _left_melee_time < 0.0 or (elapsed_code > 0 and float(elapsed_code-1)/1000.0 < _left_melee_time-0.02):
			_swing_start_valid[0] = false
			_swing_stance_valid = false
		if replicated_phase == "MELEE_L":
			_left_melee_time = float(state.time)
			_right_melee_time = -1.0
		else:
			var incoming_variant := "overhead"
			if replicated_phase == "MELEE_DL":
				incoming_variant = "diagonal_left"
			elif replicated_phase == "MELEE_DR":
				incoming_variant = "diagonal_right"
			elif replicated_phase == "MELEE_ST":
				incoming_variant = "stab"
			if _right_melee_time < 0.0 or incoming_variant != _right_variant or float(state.time) < _right_melee_time-0.02:
				_swing_start_valid[1] = false
				_swing_stance_valid = false
			_right_variant = incoming_variant
			_right_melee_duration = _duration_for("right",_right_variant)
			_right_melee_time = float(state.time)
			_left_melee_time = float(elapsed_code-1)/1000.0 if elapsed_code > 0 else -1.0
		_sync_primary_hand()
		draw_amount = 0.0
		_hit_react = 0.0
	elif replicated_phase == "ABILITY":
		var packed := int(round(float(state.draw)))
		var incoming_slot := maxi((packed & 3)-1,0)
		var incoming_index := (packed >> 2)-1
		var definition := AbilityRules.by_index(incoming_index)
		ability_slot = incoming_slot
		ability_index = incoming_index
		ability_id = str(definition.get("id",""))
		ability_clip = str(definition.get("animation","Sprint_Loop"))
		ability_duration = maxf(float(definition.get("duration",1.0)),0.01)
		ability_lean = float(definition.get("lean",0.0))
		ability_spin = float(definition.get("spin",0.0))
		ability_draw_curve = definition.get("bow_draw", [])
		ability_move = bool(definition.get("move",false))
		ability_travel = maxf(float(definition.get("travel_seconds",0.0)),0.0)
		phase = "ABILITY"
		_phase_time = float(state.time)
		draw_amount = 0.0
		consumable_kind = ""
		_hit_react = 0.0
		_clear_melee()
	elif replicated_phase == "STAGGER":
		_left_melee_time = -1.0
		_right_melee_time = -1.0
		phase = "READY"
		_melee_hand = "right"
		_phase_time = 0.0
		draw_amount = 0.0
		_hit_react = maxf(float(state.time),0.0)
	else:
		_left_melee_time = -1.0
		_right_melee_time = -1.0
		_swing_stance_valid = false
		phase = "READY" if guard_phase or step_phase else replicated_phase
		_melee_hand = "right"
		_phase_time = 0.0 if guard_phase or step_phase else float(state.time)
		draw_amount = float(state.draw)
		_hit_react = 0.0
		consumable_kind = ("bandage" if replicated_phase == "BANDAGE" else "potion") if consume_phase else ""
	charge_frozen = bool(state.charge_frozen)
	_aim_point = state.aim
	_release_draw = float(state.release_draw)
	_release_charge = float(state.release_charge)
	_release_raise = float(state.release_raise)
	_release_grip = state.release_grip
	_release_contact = state.release_contact
	_release_bow_rotation = state.release_rotation
	global_basis = Basis(Vector3.UP,float(state.yaw))
	if _blocking:
		_block_forward = -global_basis.z
	if step_phase:
		_step_progress = clampf(float(state.time),0.0,1.0)
		# Replicas have no separate step payload; the snapshot velocity is the
		# same world travel the owner collided into.
		var travel := Vector3(_velocity.x,0.0,_velocity.z)
		_step_direction = travel.normalized() if travel.length_squared() > 0.0625 else global_basis.x
	else:
		_step_progress = -1.0
	_roll_progress = float(state.roll)
	var slide: Vector4 = state.slide
	slide_progress = slide.x
	_slide_direction = Vector3(slide.y,0.0,slide.z)
	_slide_weight = slide.w
	_motion_time = float(state.motion_time)
	_locomotion_phase = float(state.locomotion_phase)
	_air_time = float(state.air_time)
	_landing_weight = float(state.landing)
	# The owning actor applies its single authoritative cover snapshot via set_cover first.
	_update_pose(0.0)

func get_arrow_origin() -> Vector3:
	return active_bow.get_arrow_origin()

func get_stance_forward() -> Vector3:
	var pose := _bone_world(_bones.spine_03)
	return (pose.basis * skeleton.get_bone_global_rest(_bones.spine_03).basis.inverse()).z.normalized()

func head_hitbox_center() -> Vector3:
	if not _built:
		return global_position + Vector3(0, Hitbox.HUMAN_HEAD_OFFSET + 1.6, 0)
	return _bone_world(_bones.Head) * Vector3(0, Hitbox.HUMAN_HEAD_OFFSET, 0)

func head_hit_profile() -> Vector2:
	return Vector2(Hitbox.HUMAN_HEAD_RADIUS, Hitbox.HUMAN_HEAD_HALF_HEIGHT)

func get_joint_positions() -> Dictionary:
	var result: Dictionary = {}
	for side in 2:
		var prefix := "left" if side == 0 else "right"
		result[prefix+"_shoulder"] = _bone_world(_arms[side][0]).origin
		result[prefix+"_elbow"] = _bone_world(_arms[side][1]).origin
		result[prefix+"_wrist"] = _bone_world(_arms[side][2]).origin
		result[prefix+"_hip"] = _bone_world(_legs[side][0]).origin
		result[prefix+"_knee"] = _bone_world(_legs[side][1]).origin
		var foot := _bone_world(_legs[side][2])
		result[prefix+"_ankle"] = foot.origin
		result[prefix+"_foot"] = foot.origin - foot.basis*_foot_up[side]*_foot_height[side]
	result["anchor"] = _jaw_anchor()
	return result

func get_blade_base(hand: String = "") -> Vector3:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return _left_blade_node().to_global(Vector3(0,0,-0.09))
	if weapon == "dagger":
		return active_dagger.to_global(Vector3(0,0,-0.09))
	if _staff_shown():
		return active_staff.to_global(Vector3(0,0,-0.09))
	return active_sword.to_global(Vector3(0,0,-0.09))

func get_blade_tip(hand: String = "") -> Vector3:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return _left_blade_node().to_global(Vector3(0,0,-float(_off_profile().length)-0.09))
	if weapon == "dagger":
		return active_dagger.to_global(Vector3(0,0,-float(DAGGER_DATA.length)-0.09))
	if _staff_shown():
		return active_staff.to_global(Vector3(0,0,-float(STAFF_DATA[staff_index].length)-0.09))
	return active_sword.to_global(Vector3(0,0,-float(SWORD_DATA[sword_index].length)-0.09))

func _physics_process(delta: float) -> void:
	Perf.begin("rig")
	advance_animation(delta)
	Perf.end()

func advance_animation(delta: float) -> void:
	if not _built:
		return
	_hit_react = maxf(0.0,_hit_react-delta)
	if not is_melee():
		_advance_step(delta)
		return
	# Each hand owns its elapsed time. Both weapons can damage in the same
	# frame; the right sword animation is the body clip whenever it is active.
	# Chronological substeps prevent a long frame from skipping either downswing.
	var remaining := maxf(delta,0.0)
	while remaining > 0.000001 and is_melee():
		var step := minf(remaining,MELEE_SAMPLE_SECONDS)
		var previous_left := _left_melee_time
		var previous_right := _right_melee_time
		var previous_left_base := Vector3.ZERO
		var previous_left_tip := Vector3.ZERO
		var previous_right_base := Vector3.ZERO
		var previous_right_tip := Vector3.ZERO
		if previous_left >= 0.0:
			previous_left_base = get_blade_base("left")
			previous_left_tip = get_blade_tip("left")
		if previous_right >= 0.0:
			previous_right_base = get_blade_base("right")
			previous_right_tip = get_blade_tip("right")
		_advance_melee_step(step)
		if _roll_progress < 0.0:
			if previous_left >= 0.0 and _left_melee_time >= 0.0:
				var window_left := _melee_window("left")
				if _left_melee_time >= window_left.x and previous_left <= window_left.y:
					melee_sweep.emit("left",previous_left_base,previous_left_tip,
						get_blade_base("left"),get_blade_tip("left"),melee_radius("left"))
			if previous_right >= 0.0 and _right_melee_time >= 0.0:
				var window_right := _melee_window("right")
				if _right_melee_time >= window_right.x and previous_right <= window_right.y:
					melee_sweep.emit("right",previous_right_base,previous_right_tip,
						get_blade_base("right"),get_blade_tip("right"),melee_radius("right"))
		if _left_melee_time >= _left_melee_duration-0.000001:
			_left_melee_time = -1.0
		if _right_melee_time >= _right_melee_duration-0.000001:
			_right_melee_time = -1.0
		_sync_primary_hand()
		remaining -= step
	if remaining > 0.000001:
		_advance_step(remaining)

func _advance_melee_step(delta: float) -> void:
	_advance_motion(delta)
	if _left_melee_time >= 0.0:
		_left_melee_time += delta
	if _right_melee_time >= 0.0:
		_right_melee_time += delta
	_sync_primary_hand()
	_update_pose(delta)

func _advance_motion(delta: float) -> void:
	_motion_time += delta
	var slide_target := 1.0 if slide_progress >= 0.0 else 0.0
	_slide_weight = move_toward(_slide_weight,slide_target,delta/BLEND_SECONDS) if _grounded and _roll_progress < 0.0 and not _cover_active else 0.0
	if _grounded and slide_progress < 0.0:
		var speed := Vector2(_velocity.x,_velocity.z).length()
		var clip := _locomotion_clip(speed)
		var reference_speed := 8.5 if clip == "Sprint_Loop" else (5.5 if clip == "Jog_Fwd_Loop" else 2.4)
		var stride := reference_speed*float(_profile.animations[clip])
		stride = lerpf(stride,float(_profile.clips.crouch_forward.stride),_crouch_amount)
		_locomotion_phase = fposmod(_locomotion_phase+delta*speed/stride,1.0)
	_air_time += delta if not _grounded else 0.0
	_landing_weight = move_toward(_landing_weight,0.0,delta*4.0)

func _advance_step(delta: float) -> void:
	_phase_time += delta
	_advance_motion(delta)
	match phase:
		"DRAWING":
			if not charge_frozen:
				draw_amount = minf(1.0,draw_amount+delta/maxf(charge_seconds(),0.001))
			if draw_amount >= 1.0-0.000001:
				draw_amount = 1.0
				phase = "HOLDING"
				_phase_time = 0.0
		"T_DRAW":
			if not charge_frozen:
				draw_amount = minf(1.0,draw_amount+delta/charge_seconds())
			if draw_amount >= 1.0-0.000001:
				draw_amount = 1.0
				phase = "T_HOLD"
				_phase_time = 0.0
		"RELEASE":
			draw_amount = _release_draw*(1.0-smoothstep(0.0,0.075,_phase_time))
			if _phase_time >= RELEASE_SECONDS:
				draw_amount = 0.0
				phase = "RECOVER"
				_phase_time -= RELEASE_SECONDS
		"T_RELEASE":
			draw_amount = _release_draw*(1.0-smoothstep(0.0,0.075,_phase_time))
			if _phase_time >= RELEASE_SECONDS:
				draw_amount = 0.0
				phase = "T_RECOVER"
				_phase_time -= RELEASE_SECONDS
		"BANDAGE","DRINK":
			var consume_length := float(CONSUMABLE_DATA.get(consumable_kind, {}).get("seconds", 0.0))
			_phase_time = minf(_phase_time, consume_length)
		"ABILITY":
			_phase_time = minf(_phase_time, ability_duration)
	if phase == "ABILITY" and _phase_time >= ability_duration-0.000001:
		_reset_ability_state()
	if phase in ["RECOVER","T_RECOVER"] and _phase_time >= RECOVER_SECONDS-0.000001:
		phase = "READY"
		_phase_time = 0.0
	_update_pose(delta)

func _melee_clip_for(hand: String, variant: String) -> Dictionary:
	var key := "left" if hand == "left" else "right"
	if variant in ["diagonal_left","diagonal_right"]:
		# Reuse the grounded load, drive and recovery of the authored heavy
		# overhead, not the one-hand finisher's airborne leg kick.
		return _profile.clips.overhead
	if key == "left" or weapon == "dagger" or variant == "stab":
		return _profile.clips.stab
	return _profile.clips.overhead if sword_index == 2 else _profile.clips.overhead_one_hand

func _melee_clip() -> Dictionary:
	return _melee_clip_for(_melee_hand,melee_variant(_melee_hand))

func _melee_window(hand: String = "") -> Vector2:
	var key := hand if hand in ["left","right"] else _melee_hand
	if is_diagonal_swing(key):
		return Vector2(SWING_LOAD_END,SWING_FOLLOW_END)*melee_seconds(key)
	if key == "left" or weapon == "dagger" or (key == "right" and _right_variant == "stab"):
		var clip: Dictionary = _profile.clips.stab
		var scale := 1.0
		if key == "left":
			# The authored stab is 0.5 s; an off-hand sword keeps the same
			# proportion of its longer swing instead of hitting too early.
			scale = _left_melee_duration / maxf(float(clip.duration),0.0001)
		return Vector2(float(clip.strike_start),float(clip.strike_end)) * scale
	var duration := _right_melee_duration if _right_melee_time >= 0.0 else float(SWORD_DATA[sword_index].seconds)
	var cut_seconds := 0.22+0.04*sword_index
	var windup := (duration-cut_seconds)*0.55
	return Vector2(windup,windup+cut_seconds)

func _melee_clip_time() -> float:
	var clip := _melee_clip()
	var window := _melee_window()
	var duration := melee_seconds()
	if _phase_time < window.x:
		return lerpf(0.0,float(clip.strike_start),clampf(_phase_time/window.x,0,1))
	if _phase_time < window.y:
		return lerpf(float(clip.strike_start),float(clip.strike_end),(_phase_time-window.x)/(window.y-window.x))
	return lerpf(float(clip.strike_end),float(clip.duration),clampf((_phase_time-window.y)/(duration-window.y),0,1))

func _throw_clip_time() -> float:
	# Charge winds through the authored chamber; release snaps through the
	# authored strike, then the follow-through doubles as the resupply recovery.
	var clip := _melee_clip_for("right","overhead")
	var strike_start := float(clip.strike_start)
	var strike_end := float(clip.strike_end)
	match phase:
		"T_DRAW":
			return lerpf(0.0,strike_start,clampf(_phase_time/charge_seconds(),0,1))
		"T_HOLD":
			return strike_start
		"T_RELEASE":
			return lerpf(strike_start,strike_end,smoothstep(0.0,RELEASE_SECONDS,_phase_time))
	return lerpf(strike_end,float(clip.duration),smoothstep(0.0,RECOVER_SECONDS,_phase_time))

func _archery_weight() -> float:
	if phase == "ABILITY":
		if ability_draw_curve.is_empty():
			return 0.0
		var progress := ability_progress()
		return smoothstep(0.0,0.10,progress)*(1.0-smoothstep(0.86,0.99,progress))
	if phase == "DRAWING":
		return smoothstep(0.0,RAISE_SECONDS,_phase_time)
	if phase == "HOLDING":
		return 1.0
	if phase == "RELEASE":
		return _release_raise
	if phase == "RECOVER":
		return _release_raise*(1.0-smoothstep(0.18,0.72,_phase_time))
	return 0.0

func _sample_clip(clip: String, time: float) -> void:
	skeleton.reset_bone_poses()
	if _player.current_animation != clip:
		_player.play(clip,0.0)
	_player.seek(clampf(time,0.0,_player.get_animation(clip).length),true)

func _locomotion_clip(speed: float) -> String:
	if speed > 7.0:
		return "Sprint_Loop"
	if speed > 3.0:
		return "Jog_Fwd_Loop"
	return "Walk_Loop"

func _locomotion_clip_time(clip: String) -> float:
	return _locomotion_phase*_player.get_animation(clip).length

## Balanced regardless of the body's early returns, so the profiler cannot be
## thrown out of step by a pose that bails.
func _update_pose(delta: float) -> void:
	Perf.begin("rig.pose")
	_update_pose_body(delta)
	Perf.end()


func _update_pose_body(delta: float) -> void:
	if not _built:
		return
	_step_facing_hold = maxf(0.0,_step_facing_hold-delta)
	var speed := Vector2(_velocity.x,_velocity.z).length()
	var sliding := _grounded and _roll_progress < 0.0 and not _cover_active and (slide_progress >= 0.0 or _slide_weight > 0.0)
	var stepping := _grounded and _step_progress >= 0.0 and _roll_progress < 0.0 and not sliding
	# The quick step owns its own planted lunge; the forward locomotion cycle
	# would read as a sprint in the step direction instead of a side step.
	var ability := phase == "ABILITY"
	# Bow skills decode their draw strength from data; both arms are then solved
	# by the shared archery pose, so the bow aims and releases on cue.
	var bow_ability := ability and weapon == "bow" and not ability_draw_curve.is_empty()
	if bow_ability:
		draw_amount = _sample_ability_draw()
	# A move-enabled skill keeps playing its authored upper body while the legs
	# layer the normal locomotion cycle. The committed travel window of a lunge
	# or shield charge is exempt: its authored full-body clip owns the pose.
	var moving_ability := ability and ability_move and (ability_travel <= 0.0 or _phase_time >= ability_travel)
	var moving := _grounded and speed > 0.1 and _roll_progress < 0.0 and not sliding and not stepping
	var consuming := is_consuming()
	var drawing := weapon == "bow" and phase in ["DRAWING","HOLDING","RELEASE","RECOVER"]
	var aim_bow := drawing or bow_ability
	var throwing := phase in ["T_DRAW","T_HOLD","T_RELEASE","T_RECOVER"]
	var coupled_carry := weapon == "sword" and (sword_index == 2 or _staff_shown()) and not is_melee() and not throwing and not consuming
	var guarding := (coupled_carry or _blocking) and _grounded and _roll_progress < 0.0
	var arm_overlay := coupled_carry and not guarding
	var action := is_melee() or drawing or throwing or guarding or _cover_active or consuming or moving_ability
	var layer_lower_body := action and (moving or (guarding and _landing_weight > 0.0))
	var diagonal_body := is_diagonal_swing(_melee_hand)
	var diagonal_id := 0
	if diagonal_body:
		diagonal_id = (1 if _melee_hand == "right" else 3)+(1 if melee_variant(_melee_hand) == "diagonal_left" else 0)
	var lower_clip := (_locomotion_clip(speed) if moving else "Jump_Land") if layer_lower_body else ""
	var archery := _archery_weight() if aim_bow else 0.0
	if _roll_progress < 0.0 and not consuming and not ability and (phase != "READY" or _cover_active):
		var offset := _aim_point-global_position
		if Vector2(offset.x,offset.z).length_squared() > 0.0001:
			var yaw := atan2(-offset.x,-offset.z)
			if _cover_active:
				var tucked_yaw := atan2(-_cover_normal.x,-_cover_normal.z)
				yaw = lerp_angle(tucked_yaw,yaw,smoothstep(0.0,1.0,_cover_lean.length()))
			global_basis = Basis(Vector3.UP,yaw)
	# Bow skills ride the crosshair: the body turns onto the aim on every pose
	# solve, so each release cue leaves from the stance the player is looking
	# through instead of the heading the skill began with.
	if bow_ability and _roll_progress < 0.0:
		var aim_offset := _aim_point-global_position
		if Vector2(aim_offset.x,aim_offset.z).length_squared() > 0.0001:
			global_basis = Basis(Vector3.UP,atan2(-aim_offset.x,-aim_offset.z))
	# These nodes are rotation-only. Repeated Euler setters preserve extracted
	# scale and accumulate float drift until weapon/foot slerps cease to be rotations.
	_model.basis = Basis(Vector3.UP,PI+STANCE_YAW*archery+_ability_spin_yaw())
	_model.position = Vector3.ZERO
	var clip := ("Sword_Idle_OneHand" if weapon in ["sword","dagger"] or weapon == "dual" else "Idle_Loop")
	if weapon == "sword" and (sword_index == 2 or _staff_shown()):
		clip = "Sword_Idle"
	var time := fposmod(_motion_time,_player.get_animation(clip).length)
	if _roll_progress >= 0.0:
		clip = "Roll"
		time = clampf(_roll_progress,0,1)*_player.get_animation(clip).length
	elif is_melee():
		clip = str(_melee_clip().name)
		time = _melee_clip_time()
	elif throwing:
		clip = str(_melee_clip_for("right","overhead").name)
		time = _throw_clip_time()
	elif consuming:
		clip = str(CONSUMABLE_DATA.get(consumable_kind, {}).get("clip","Idle_Loop"))
		time = clampf(_phase_time,0.0,_player.get_animation(clip).length)
	elif ability:
		clip = ability_clip if _player.has_animation(ability_clip) else "Sprint_Loop"
		time = ability_progress()*_player.get_animation(clip).length
	elif drawing:
		time = 0.0
	elif guarding:
		clip = "Sword_Block_Loop" if weapon == "sword" and (sword_index == 2 or _staff_shown()) else "Sword_Block_Loop_OneHand"
		time = fposmod(_motion_time,_player.get_animation(clip).length)
	elif not _grounded:
		clip = "Jump_Start" if _air_time < 0.15 else "Jump_Loop"
		time = _air_time/0.15*_player.get_animation(clip).length if _air_time < 0.15 else fposmod(_air_time,_player.get_animation(clip).length)
	elif _landing_weight > 0.0 and not moving and not sliding:
		clip = "Jump_Land"
		time = (1.0-_landing_weight)*_player.get_animation(clip).length
	elif moving:
		clip = _locomotion_clip(speed)
		time = _locomotion_clip_time(clip)
	if clip != _display_clip or lower_clip != _display_lower_clip or weapon != _display_weapon or drawing != _display_drawing or diagonal_id != _display_diagonal:
		for bone in skeleton.get_bone_count():
			_blend_pose[bone] = _authored_pose[bone]
		_blend_time = 0.0
		_display_clip = clip
		_display_lower_clip = lower_clip
		_display_weapon = weapon
		_display_drawing = drawing
		_display_diagonal = diagonal_id
	# A blade skill or dash is performed standing. A replicated crouch that has
	# not finished clearing yet must not cover its authored clip.
	if _crouch_amount > 0.0 and _ability_needs_standing():
		_crouch_amount = 0.0
	var crouching := _crouch_amount > 0.0 and _roll_progress < 0.0
	var leaning := _cover_active and not _cover_lean.is_zero_approx() and _roll_progress < 0.0
	if leaning:
		_sample_cover_lean()
	if crouching:
		var crouch_moving := moving or (sliding and slide_progress < 0.0 and speed > 0.1)
		var crouch_clip := str(_profile.clips.crouch_forward.name if crouch_moving else _profile.clips.crouch_idle.name)
		var crouch_time := _locomotion_clip_time(crouch_clip) if crouch_moving else fposmod(_motion_time,_player.get_animation(crouch_clip).length)
		_sample_clip(crouch_clip,crouch_time)
		var slide_blend := smoothstep(0.0,1.0,_slide_weight)
		for bone in skeleton.get_bone_count():
			var pose := skeleton.get_bone_pose(bone)
			_crouch_pose[bone] = pose.interpolate_with(_slide_crouch_pose[bone],slide_blend) if sliding else pose
	if arm_overlay or diagonal_body:
		var carry_clip := "Sword_Idle"
		if diagonal_body:
			carry_clip = "Sword_Block_Loop" if weapon == "sword" and (sword_index == 2 or _staff_shown()) else "Sword_Idle_OneHand"
		_sample_clip(carry_clip,fposmod(_motion_time,_player.get_animation(carry_clip).length))
		for index in _guard_bones.size():
			_guard_pose[index] = skeleton.get_bone_pose(_guard_bones[index])
	if layer_lower_body:
		var lower_time := _locomotion_clip_time(lower_clip) if moving else (1.0-_landing_weight)*_player.get_animation(lower_clip).length
		_sample_clip(lower_clip,lower_time)
		for index in _leg_bones.size():
			_lower_pose[index] = skeleton.get_bone_pose(_leg_bones[index])
	_sample_clip(clip,time)
	if diagonal_body:
		# Mirror the authored plant/drive with the cut's starting side. Arms
		# retain their own carry before the diagonal socket solves take over.
		if melee_variant(_melee_hand) == "diagonal_left":
			for index in 5:
				var left_pose := skeleton.get_bone_pose(_leg_bones[index])
				var right_pose := skeleton.get_bone_pose(_leg_bones[index+5])
				skeleton.set_bone_pose(_leg_bones[index],_mirror_transform(right_pose))
				skeleton.set_bone_pose(_leg_bones[index+5],_mirror_transform(left_pose))
			for bone in _cover_bones:
				skeleton.set_bone_pose(bone,_mirror_transform(skeleton.get_bone_pose(bone)))
		for index in _guard_bones.size():
			skeleton.set_bone_pose(_guard_bones[index],_guard_pose[index])
	if layer_lower_body:
		for index in _leg_bones.size():
			skeleton.set_bone_pose(_leg_bones[index],_lower_pose[index])
	_blend_time = minf(BLEND_SECONDS,_blend_time+delta)
	if _blend_time < BLEND_SECONDS and _roll_progress < 0.0:
		var weight := smoothstep(0.0,BLEND_SECONDS,_blend_time)
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose(bone,_blend_pose[bone].interpolate_with(skeleton.get_bone_pose(bone),weight))
	# Blend authored motion only. Feeding already crouched/IK-corrected bones
	# back into the next transition applies their offsets again on every switch.
	for bone in skeleton.get_bone_count():
		_authored_pose[bone] = skeleton.get_bone_pose(bone)
	if arm_overlay:
		for index in _guard_bones.size():
			skeleton.set_bone_pose(_guard_bones[index],_guard_pose[index])
	if crouching:
		_apply_cover_crouch(drawing or is_melee() or throwing or coupled_carry or _blocking or weapon == "dual" or consuming)
	if moving and action:
		var spine_pose := _bone_world(_bones.spine_01)
		var pelvis := _bone_world(_bones.pelvis)
		var travel := atan2(-_velocity.x,-_velocity.z)-global_rotation.y-STANCE_YAW*archery
		pelvis.basis = Basis(Vector3.UP,travel)*pelvis.basis
		_set_bone_world(_bones.pelvis,pelvis)
		var corrected_spine := _bone_world(_bones.spine_01)
		corrected_spine.basis = spine_pose.basis
		_set_bone_world(_bones.spine_01,corrected_spine)
	if leaning:
		_apply_cover_lean()
	_apply_melee_swing_path()
	_apply_hit_react_pose()
	if ability:
		_apply_ability_pose()
	if _grounded and _roll_progress < 0.0:
		if aim_bow and not moving:
			_plant_archery_feet(archery*(1.0-_slide_weight) if sliding else archery)
		if sliding:
			_apply_slide_pose(drawing or is_melee() or throwing or coupled_carry or _blocking or weapon == "dual" or consuming)
		if _step_progress >= 0.0 and not is_melee() and not throwing:
			_apply_step_pose()
		_place_feet()
	if aim_bow:
		var head := _bone_world(_bones.Head)
		head.basis = Basis(Vector3.UP,-STANCE_YAW*archery)*head.basis
		_set_bone_world(_bones.Head,head)
	if weapon == "dual" and not consuming:
		_pose_dual_arms()
		if _right_melee_time >= 0.0 and _right_variant == "stab":
			_aim_sword_thrust()
	elif weapon == "dagger" and _right_melee_time >= 0.0 and not is_diagonal_swing("right"):
		_aim_dagger_stab()
	elif weapon == "sword" and _right_melee_time >= 0.0 and _right_variant == "stab":
		_aim_sword_thrust()
	for hand in ["left","right"]:
		if is_diagonal_swing(hand):
			_apply_diagonal_arm_path(hand)
	_update_shield_pose()
	if weapon == "bow":
		_update_bow_pose(aim_bow)
	elif weapon != "none":
		_update_hand_contacts()
		var right_hand := _bone_world(_arms[1][2])
		if weapon == "dagger":
			active_dagger.global_transform = right_hand * _sword_grip
		elif weapon == "dual":
			active_sword.global_transform = right_hand * _sword_grip
			if active_off_weapon != null:
				active_off_weapon.global_transform = _bone_world(_arms[0][2]) * _sword_grip_left
		elif _staff_shown():
			# A staff is gripped around its middle: the right hand sits just
			# below the shaft centre and the support hand above it.
			active_staff.global_transform = _weapon_socket(right_hand)
		else:
			active_sword.global_transform = right_hand * _sword_grip
		if active_focus != null:
			active_focus.global_transform = _bone_world(_arms[0][2]) * _sword_grip_left
	var chest_pose := global_transform.affine_inverse()*_bone_world(_bones.spine_03)
	_chest.transform = Transform3D(chest_pose.basis*_chest_rest_basis.inverse(),chest_pose.origin)
	_update_consumable_props()
	_sync_weapon_visibility()

func _pose_dual_arms() -> void:
	# Precision strikes extend the left hand along the crosshair. Diagonal
	# paths take over that arm after this neutral offhand solve. An inactive
	# right hand keeps its neutral local pose instead of copying a left stab.
	# Keep the authored tucked roll arms intact.
	if _roll_progress >= 0.0:
		return
	var left_before: Array[Transform3D] = []
	for bone in _arms[0]:
		left_before.append(skeleton.get_bone_pose(bone))
	var left_melee := _left_melee_time >= 0.0
	var right_melee := _right_melee_time >= 0.0
	var restore_right := left_melee and not right_melee
	var right_bones: Array[int] = []
	var right_before: Array[Transform3D] = []
	if restore_right:
		right_bones.append(int(_bones.clavicle_r))
		for bone in _arms[1]:
			right_bones.append(bone)
		for bone in right_bones:
			right_before.append(skeleton.get_bone_pose(bone))
	if left_melee and not is_diagonal_swing("left"):
		var shoulder_l := _bone_world(_arms[0][0]).origin
		var shoulder_skel := skeleton.get_bone_global_pose(_arms[0][0])
		var guard := skeleton.global_transform*(shoulder_skel.origin+_offhand_offset)
		var offset := _aim_point-shoulder_l
		var direction := -global_basis.z
		if offset.length_squared() > 0.1225:
			direction = offset.normalized()
		var up := Vector3.UP
		if absf(direction.dot(up)) > 0.98:
			up = global_basis.x
		var aim_basis := Basis.looking_at(direction,up)
		var elbow := _bone_world(_arms[0][1]).origin
		var arm_reach := shoulder_l.distance_to(elbow)+elbow.distance_to(_bone_world(_arms[0][2]).origin)
		var aim_along := 0.35
		if offset.length_squared() > 0.1225:
			aim_along = maxf(0.10,offset.length()-float(_off_profile().length)-0.09)
		var extended := shoulder_l+direction*minf(aim_along,arm_reach-0.01)
		var window := _melee_window("left")
		var extend := smoothstep(window.x-0.06,window.x,_left_melee_time)
		var retract := smoothstep(window.y+0.06,maxf(window.y+0.08,_left_melee_duration-0.04),_left_melee_time)
		var strike := extend*(1.0-retract)
		var target := guard.lerp(extended,strike)
		_solve_limb(_arms[0],target,aim_basis*_sword_grip_left.basis.inverse(),skeleton.global_basis*_offhand_pole)
		if restore_right:
			for bone: int in _neutral_right_arm:
				skeleton.set_bone_pose(bone,_neutral_right_arm[bone])
	else:
		var shoulder := skeleton.get_bone_global_pose(_arms[0][0])
		var target_skel := shoulder.origin+_offhand_offset
		_solve_limb(_arms[0],skeleton.global_transform*target_skel,
			skeleton.global_basis*_offhand_weapon_basis*_sword_grip_left.basis.inverse(),
			skeleton.global_basis*_offhand_pole)
		if restore_right:
			for bone: int in _neutral_right_arm:
				skeleton.set_bone_pose(bone,_neutral_right_arm[bone])
	if _blend_time < BLEND_SECONDS and _roll_progress < 0.0:
		var weight := smoothstep(0.0,BLEND_SECONDS,_blend_time)
		for index in _arms[0].size():
			var bone := _arms[0][index]
			skeleton.set_bone_pose(bone,left_before[index].interpolate_with(skeleton.get_bone_pose(bone),weight))
		if restore_right:
			for index in right_bones.size():
				var bone := right_bones[index]
				skeleton.set_bone_pose(bone,right_before[index].interpolate_with(skeleton.get_bone_pose(bone),weight))
	# Feed the visible arm pose into the next clip transition instead of the
	# unsolved authored arm, which would pop when the strike ends.
	for bone in _arms[0]:
		_authored_pose[bone] = skeleton.get_bone_pose(bone)
	if restore_right:
		for bone in right_bones:
			_authored_pose[bone] = skeleton.get_bone_pose(bone)

func _apply_cover_crouch(lower_only: bool) -> void:
	# Authored crouch steps replace standing strides; aim and sword grips keep their upper-body pose.
	if lower_only:
		for bone in _leg_bones:
			skeleton.set_bone_pose(bone,skeleton.get_bone_pose(bone).interpolate_with(_crouch_pose[bone],_crouch_amount))
	else:
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose(bone,skeleton.get_bone_pose(bone).interpolate_with(_crouch_pose[bone],_crouch_amount))
	var left := _bone_world(_legs[0][2])
	var right := _bone_world(_legs[1][2])
	var pelvis := _bone_world(_bones.pelvis)
	pelvis.origin.y -= _crouch_lowering*_crouch_amount
	_set_bone_world(_bones.pelvis,pelvis)
	_solve_limb(_legs[0],left.origin,left.basis)
	_solve_limb(_legs[1],right.origin,right.basis)

func _apply_slide_pose(lower_only: bool) -> void:
	# Slide offsets are measured against the imported leg chains. Only fixed-length
	# limb rotations follow the targets; physical crouch remains owned by CoverMovement.
	var weight := smoothstep(0.0,1.0,_slide_weight)*_crouch_amount
	if weight <= 0.0:
		return
	var stance := Basis(Vector3.UP,atan2(-_slide_direction.x,-_slide_direction.z))
	var spine := _bone_world(_bones.spine_01)
	var pelvis := _bone_world(_bones.pelvis)
	var travel := atan2(-_slide_direction.x,-_slide_direction.z)-global_rotation.y-STANCE_YAW*_archery_weight()
	pelvis.basis = Basis(Vector3.UP,wrapf(travel,-PI,PI)*weight)*pelvis.basis
	var leg_length := (_leg_lengths.x+_leg_lengths.y)*0.5
	pelvis.origin += (stance.z*0.08-Vector3.UP*0.08)*leg_length*weight
	_set_bone_world(_bones.pelvis,pelvis)
	var corrected_spine := _bone_world(_bones.spine_01)
	# Keep action/guard orientation and both grips intact; ready stance leans back
	# slightly over the tucked trailing knee instead of pitching the whole mesh.
	corrected_spine.basis = spine.basis if lower_only else Basis(stance.x,0.16*weight)*spine.basis
	_set_bone_world(_bones.spine_01,corrected_spine)
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var foot := _bone_world(_legs[side][2])
		var reach := 0.70 if side == 0 else -0.22
		var target := global_position+stance*Vector3(sign_x*0.19*_leg_lengths[side],_foot_height[side],-reach*_leg_lengths[side])
		var rest_basis := stance*Basis(Vector3.UP,PI)*skeleton.get_bone_global_rest(_legs[side][2]).basis
		if side == 0:
			rest_basis = Basis(stance.x,0.14)*rest_basis
		var pole := stance*Vector3(sign_x*0.18,0.25,-1.0)
		_solve_limb(_legs[side],foot.origin.lerp(target,weight),foot.basis.slerp(rest_basis,weight),pole)

func _diagonal_swing_timeline(hand: String) -> Dictionary:
	var duration := melee_seconds(hand)
	var time := _left_melee_time if hand == "left" else _right_melee_time
	var progress := clampf(time/maxf(duration,0.001),0.0,1.0)
	var side := 1.0 if melee_variant(hand) == "diagonal_right" else -1.0
	var size := off_weapon_index if hand == "left" else sword_index
	var dagger := off_weapon_kind != "sword" if hand == "left" else weapon == "dagger"
	var staff := _staff_shown()
	var spec: Dictionary = DIAGONAL_STAFF if staff else DIAGONAL_BLADE[0 if dagger else size]
	# Every joint runs the same strike curve on its own clock offset, so the
	# coil unwinds from the ground up and the blade arrives last.
	var load := smoothstep(0.0,SWING_LOAD_END*0.92,progress)
	var pelvis := _swing_chain(progress,SWING_CHAIN_PELVIS)
	var chest := _swing_chain(progress,SWING_CHAIN_CHEST)
	var clavicle := _swing_chain(progress,SWING_CHAIN_CLAVICLE)
	var drive := _swing_drive(progress)
	var blade_drive := _swing_chain(progress,SWING_CHAIN_BLADE)
	var recover := smoothstep(SWING_SETTLE_END,1.0,progress)
	# Momentum is absorbed at the end of the arc: the blade rebounds a few
	# degrees and settles instead of stopping dead at the centre line.
	var cushion := 0.0
	if progress > SWING_FOLLOW_END and progress < SWING_SETTLE_END:
		cushion = sin((progress-SWING_FOLLOW_END)/(SWING_SETTLE_END-SWING_FOLLOW_END)*PI)
	var cross_body := (side < 0.0) == (hand == "right")
	var fwd_load := float(spec.fwd_load)+0.12*cushion
	var up_load := float(spec.up_load)
	var blade_load := float(spec.blade_load)
	if cross_body:
		# A backhand chamber crosses the chest, so it is pulled back and cocked
		# harder: the blade passes over the far shoulder instead of through the
		# face, and the shoulder girdle's own turn does not drag it forward.
		fwd_load -= 0.10
		up_load += 0.04
		blade_load += 0.22
	var hand_yaw := side*lerpf(lerpf(0.25,float(spec.yaw_load),load),-float(spec.yaw_cross),drive)
	# The blade holds the cocked aim through the load: how the weapon travels
	# there is the arm path's business, so the tip never sweeps forward first.
	var blade_yaw := side*lerpf(blade_load,-(float(spec.blade_cross)+0.10*cushion),blade_drive)
	# The chest finishes the strike turned past the target with the leading
	# shoulder forward; the hips are already through by then.
	var pelvis_yaw := -side*lerpf(float(spec.pelvis_load)*load,-float(spec.pelvis_cross),pelvis)
	var chest_yaw := -side*lerpf(float(spec.chest_load)*load,-float(spec.chest_cross),chest)
	var chest_pitch := lerpf(float(spec.lean_load),float(spec.lean_cross),chest)-0.05*cushion
	return {
		"load":load, "drive":drive, "cut":blade_drive, "release":recover,
		"pelvis":pelvis_yaw, "chest":chest_yaw, "chest_pitch":chest_pitch,
		"clavicle":float(spec.clavicle),
		"head_yaw":-chest_yaw*0.62, "head_pitch":chest_pitch*0.72,
		"yaw":hand_yaw,
		"radius":lerpf(float(spec.rad_load),float(spec.rad_cross),drive),
		"fwd":lerpf(fwd_load,float(spec.fwd_cross),drive),
		"up":lerpf(up_load,float(spec.up_cross),drive)+0.05*cushion,
		"side":side, "cross_body":cross_body, "blade_yaw":blade_yaw,
		"blade_pitch":lerpf(float(spec.tip_load),float(spec.tip_down),blade_drive)+0.12*cushion,
	}

func _apply_melee_swing_path() -> void:
	# A right-hand authored precision stroke owns the body during overlap;
	# the left diagonal still solves its own independent hand trajectory.
	if has_melee("right") and not is_diagonal_swing("right"):
		return
	var hand := "right" if is_diagonal_swing("right") else "left"
	if not is_diagonal_swing(hand):
		return
	var swing := _diagonal_swing_timeline(hand)
	var fade := 1.0-float(swing.release)
	var pelvis_yaw := float(swing.pelvis)*fade
	var chest_yaw := float(swing.chest)*fade
	var pitch := float(swing.chest_pitch)*fade
	if absf(pelvis_yaw)+absf(chest_yaw)+absf(pitch) <= 0.0001:
		return
	# The hips lead, the chest follows, the shoulder drags behind the chest.
	# A planted, stationary actor can rotate the pelvis and re-solve the feet.
	# While locomotion, crouch or a slide owns the lower body, lock the pelvis
	# and move the whole coil into the spine and clavicle.
	var stationary := _grounded and _velocity.length_squared() < 0.01 \
		and _crouch_amount < 0.01 and _slide_weight < 0.01
	var spine_yaw := chest_yaw
	if stationary:
		if not _swing_stance_valid:
			for side in 2:
				_swing_stance[side] = _bone_world(_legs[side][2])
			var stance_centre := (_swing_stance[0].origin+_swing_stance[1].origin)*0.5
			_swing_stance_offset = _bone_world(_bones.pelvis).origin-stance_centre
			_swing_stance_offset.y = 0.0
			_swing_stance_valid = true
		var pelvis := _bone_world(_bones.pelvis)
		pelvis.basis = Basis(Vector3.UP,pelvis_yaw)*pelvis.basis
		# The hips pivot over the stance instead of travelling: a small weight
		# shift is allowed, a lunge or a slide back out of the circle is not.
		var anchor := (_swing_stance[0].origin+_swing_stance[1].origin)*0.5+_swing_stance_offset
		var shift := pelvis.origin-anchor
		shift.y = 0.0
		# Keep the clip's hip height; only the horizontal travel is clamped.
		# The clamp and the planted feet are handed back to the authored carry
		# through the recovery so neither snaps home in a single frame.
		var handoff := float(swing.release)
		var stance_hip := Vector3(anchor.x,pelvis.origin.y,anchor.z)+shift.limit_length(0.08)
		pelvis.origin = pelvis.origin.lerp(stance_hip,1.0-handoff)
		_set_bone_world(_bones.pelvis,pelvis)
		var stance_pole := global_basis*Vector3(0.0,0.2,-1.0)
		for side in 2:
			var clip_foot := _bone_world(_legs[side][2])
			var ankle := _swing_stance[side].origin.lerp(clip_foot.origin,handoff)
			var ankle_basis := _swing_stance[side].basis.slerp(clip_foot.basis,handoff)
			_solve_limb(_legs[side],ankle,ankle_basis,stance_pole)
	else:
		spine_yaw += pelvis_yaw
	# The authored chop supplies the plant, the hip drop and the knee drive,
	# but the torso belongs to the swing. Rebuild it in the character frame so
	# the chest extends over the trailing hip on the load and crunches through
	# the strike, instead of inheriting the overhead's forward hunch.
	var up := Vector3.UP
	var sideways := global_basis.x
	var rest := skeleton.global_transform
	for share in [[_bones.spine_01,0.34],[_bones.spine_02,0.68],[_bones.spine_03,1.0]]:
		var pose := _bone_world(int(share[0]))
		var rest_basis := (rest*skeleton.get_bone_global_rest(int(share[0]))).basis
		# Positive pitch leans the chest forward, i.e. a negative turn about the
		# character's own right axis.
		pose.basis = Basis(up,spine_yaw*float(share[1])) \
			* Basis(sideways,-pitch*float(share[1])) * rest_basis
		_set_bone_world(int(share[0]),pose)
	# The striking clavicle carries the shoulder farther into the swing without
	# moving the whole chest. It is re-solved with the arm afterwards.
	var clavicle_bone: int = _bones.clavicle_l if hand == "left" else _bones.clavicle_r
	var clavicle := _bone_world(clavicle_bone)
	clavicle.basis = Basis(up,spine_yaw*float(swing.clavicle)*0.35)*clavicle.basis
	_set_bone_world(clavicle_bone,clavicle)
	# The gaze stays on the target: the head gives back most of the chest yaw
	# and of the strike's pitch, so the wind-up reads as a coil without the
	# character staring at the ground through the cut.
	var head := _bone_world(_bones.Head)
	head.basis = Basis(up,float(swing.head_yaw)*fade) \
		* Basis(sideways,-float(swing.head_pitch)*fade) * head.basis
	_set_bone_world(_bones.Head,head)

func _apply_diagonal_arm_path(hand_key: String) -> void:
	var swing := _diagonal_swing_timeline(hand_key)
	var arm := 0 if hand_key == "left" else 1
	var hand_side := -1.0 if arm == 0 else 1.0
	var grip := _sword_grip_left if arm == 0 else _sword_grip
	var staff := _staff_shown()
	var two_hand: bool = hand_key == "right" and weapon == "sword" and (sword_index == 2 or staff)
	# Transition waypoints follow the shoulder line rather than the spine base,
	# including crouched and elevated actors.
	var pivot := (_bone_world(_arms[0][0]).origin+_bone_world(_arms[1][0]).origin)*0.5
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return
	forward = forward.normalized()
	var offset := _aim_point-global_position
	offset.y = 0.0
	if offset.length_squared() > 0.04:
		forward = offset.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var yaw := float(swing.yaw)
	# A one-handed wrist works in front of its own shoulder. A shared hilt
	# works between both shoulders: centering it on the sword arm forces the
	# support forearm across the chest even when both wrists are reachable.
	var shoulder := _bone_world(_arms[arm][0]).origin
	var hand_centre := pivot if two_hand else shoulder
	# The hilt orbits the shoulder (one hand) or the shoulder line (two hands)
	# while its own piston drives it forward and its height comes from the
	# strike arc, so the hand leads the torso instead of sliding around the
	# belly. Heights are actor-relative, never clamped against the floor.
	var radial := forward*cos(yaw)+right*sin(yaw)
	var target := hand_centre+radial*float(swing.radius)
	target += forward*float(swing.fwd)+Vector3.UP*float(swing.up)
	# A shared hilt lives between the shoulders: pulled behind the chest it
	# buries the hands in the torso, so it keeps a working clearance in front.
	if two_hand:
		var ahead := (target-pivot).dot(forward)
		if ahead < 0.30:
			target += forward*(0.30-ahead)
	var elbow := _bone_world(_arms[arm][1]).origin
	var wrist_origin := _bone_world(_arms[arm][2]).origin
	var arm_reach := shoulder.distance_to(elbow)+elbow.distance_to(wrist_origin)
	var reach := target-shoulder
	if reach.length() > arm_reach*0.90:
		target = shoulder+reach.normalized()*arm_reach*0.90
	# The blade axis is radial from the body, so the whole 1.4 m greatsword
	# sweeps around the swing centre rather than translating forward. The tip
	# leads the hilt: it is already inside the sector while the hands still
	# finish their coil, and it passes the centre line before they do.
	var blade_azimuth := float(swing.blade_yaw)
	var blade_dir := forward*cos(blade_azimuth)+right*sin(blade_azimuth)
	blade_dir = (blade_dir*cos(float(swing.blade_pitch))+Vector3.UP*sin(float(swing.blade_pitch))).normalized()
	var hand := _bone_world(_arms[arm][2])
	var upper_pose := skeleton.get_bone_pose(_arms[arm][0])
	var lower_pose := skeleton.get_bone_pose(_arms[arm][1])
	var hand_pose := skeleton.get_bone_pose(_arms[arm][2])
	# The resting carry is held in root space, not chest space: the authored
	# wind-up twists the chest, and a chest-relative carry would be dragged
	# behind the back where the sword arm cannot follow it.
	var root_xf := Transform3D(global_basis,global_position)
	if not _swing_start_valid[arm]:
		_swing_start_hand[arm] = root_xf.affine_inverse()*hand
		_swing_start_valid[arm] = true
	var start := root_xf*_swing_start_hand[arm]
	var raise := float(swing.load)
	var release := float(swing.release)
	# The hand leaves the carry along an arc that bows out in front of the
	# chest, not a straight line through it: a linear blend to a cross-body
	# wind-up passed the wrist through the shoulder and the elbow flipped
	# halfway there. The control point sits in the swing frame, so the path
	# stays in front of the body while the torso winds under it.
	var via := pivot+right*(0.34*hand_side)+forward*0.20+Vector3.UP*-0.22
	# Leave the carry outward before turning into the swing plane. A hand can
	# rest anywhere around the body after the previous action; a direct arc
	# toward the swing centre would drag the forearm through the ribs.
	var start_out := start.origin-pivot
	start_out.y = 0.0
	if start_out.length_squared() < 0.0001:
		start_out = right*hand_side
	var leave := start.origin+start_out.normalized()*0.26+Vector3.UP*0.16-forward*0.04
	# The windup bows outward and up toward the cocked pose. Reusing the low
	# forward recovery control would push the hands away from the body before
	# the cut and erase the backswing.
	var load_via := pivot+right*(0.30*hand_side)-forward*0.08+Vector3.UP*0.16
	var hand_path := target
	if raise < 1.0:
		hand_path = _hand_arc(start.origin,leave,load_via,hand_path,raise)
	var start_sword := start.basis*grip.basis
	var target_sword := Basis.looking_at(blade_dir,Vector3.UP)
	# The cut owns the blade directly. During the load the weapon leaves the
	# carry where it already is and pulls out and back around the striking
	# shoulder, so the tip never travels forward across the body first.
	var cut_sword := target_sword
	if raise < 0.999:
		var start_dir: Vector3 = -start_sword.z
		var start_up: Vector3 = start_sword.y
		var strike_side := float(swing.side)
		var loaded := start_dir
		if two_hand or bool(swing.cross_body):
			# A shared grip cannot pull its blade low across the body, and a
			# backhand chamber has to cross it: both lift the weapon up and
			# over the shoulder instead of sweeping it out in front.
			var lift := start_dir.slerp(blade_dir,0.5)
			lift = (lift-forward*0.30+Vector3.UP*0.22).normalized()
			loaded = start_dir.slerp(lift,smoothstep(0.0,0.55,raise))
			loaded = loaded.slerp(blade_dir,smoothstep(0.30,1.0,raise)).normalized()
		else:
			var outward := (right*(0.55*strike_side)-forward*0.55+Vector3.UP*0.62).normalized()
			loaded = start_dir.slerp(outward,smoothstep(0.0,0.5,raise))
			loaded = loaded.slerp(blade_dir,smoothstep(0.34,1.0,raise)).normalized()
		var load_up := start_up.slerp(Vector3.UP,smoothstep(0.0,0.85,raise)).normalized()
		if absf(load_up.dot(loaded)) > 0.96:
			load_up = right*strike_side
		cut_sword = Basis.looking_at(loaded,load_up)
	# The hand comes up to the carry before the blade turns back into it, so the
	# tip does not drag through the floor while the low follow-through rotates
	# up toward the resting carry.
	var turned := smoothstep(0.30,1.0,release)
	# The cut recovers to a front guard rather than dragging the hand back to
	# the hip: a low hand beside a lunging body folds the forearm through the
	# belly. The carry is the opening pose only.
	var guard_height := shoulder.y-0.32
	var guard := pivot+forward*0.34+right*(0.12*hand_side)+Vector3.UP*((guard_height-pivot.y)*0.6)
	if release > 0.0:
		hand_path = _bezier(hand_path,via,guard,release)
	# Ease out of the authored arm over the same window the rig blends clips.
	# That arm pose is valid for its body; taking the arm over in one frame
	# while the torso is still blending would fold the forearm into the ribs.
	var time := _left_melee_time if arm == 0 else _right_melee_time
	var engage := smoothstep(0.0,minf(BLEND_SECONDS,_melee_window(hand_key).x),time)
	var hand_position := hand_path
	var sword_basis := cut_sword if turned <= 0.0001 else _blend_basis(cut_sword,start_sword,turned)
	if engage < 0.999:
		sword_basis = _blend_basis(hand.basis*grip.basis,sword_basis,engage)
	var hand_basis := sword_basis*grip.basis.inverse()
	# Use one exterior bend plane throughout the cut. Interpolating pole
	# directions by wrist distance could cross the arm axis and flip the elbow.
	var pole := right*(1.4*hand_side)+forward*0.9-Vector3.UP*0.25
	_solve_limb(_arms[arm],hand_position,hand_basis,pole)
	# Restore the complete arm, not just its wrist target, so the outgoing
	# solved elbow blends back with the authored body instead of popping
	# when the attack returns to its carry.
	var solve_weight := engage*(1.0-release)
	if solve_weight < 0.999999:
		skeleton.set_bone_pose(_arms[arm][0],upper_pose.interpolate_with(skeleton.get_bone_pose(_arms[arm][0]),solve_weight))
		skeleton.set_bone_pose(_arms[arm][1],lower_pose.interpolate_with(skeleton.get_bone_pose(_arms[arm][1]),solve_weight))
		skeleton.set_bone_pose(_arms[arm][2],hand_pose.interpolate_with(skeleton.get_bone_pose(_arms[arm][2]),solve_weight))
	if two_hand:
		# A hilt is one rigid constraint shared by both arms. Solve its position
		# inside both wrist-reach spheres instead of clamping the support wrist
		# away from the handle when the primary hand takes it out of reach.
		var sword_hand := _bone_world(_arms[1][2])
		# The support depth is measured from the right hand along the weapon's
		# own +Z. The staff's visual node is offset along that shaft, so the
		# grip point must stay in hand space rather than node-space.
		var handle := sword_hand*_sword_grip
		var left := _bone_world(_arms[0][2])
		# When switching from a one-handed carry, the blade initially remains
		# beside the right hip while the authored guard blends in. Do not pull
		# the left arm through the torso to grasp that still-rearward hilt.
		# Acquire it after the outward lift, completing before the active cut.
		var load_end := _melee_window(hand_key).x
		# Close the support grip through the first part of the load. Waiting
		# until the top leaves the authored cross-chest arm in place while the
		# chest has already coiled, which drives the forearm through the ribs.
		var support_attach := smoothstep(load_end*0.35,load_end,time)
		var support_shoulder := _bone_world(_arms[0][0]).origin
		var support_elbow := _bone_world(_arms[0][1]).origin
		var support_length := support_shoulder.distance_to(support_elbow)+support_elbow.distance_to(left.origin)
		var support_target: Basis = handle.basis*_sword_grip_left.basis.inverse()
		var support_basis := _blend_basis(left.basis,support_target,solve_weight)
		var carry_depth := clampf((handle.affine_inverse()*(left*_palm_left)).z,0.06,0.29)
		# A staff's hands stay spaced around its middle. A sword's support hand
		# slides toward the pommel and only widens as the cut drives out.
		var grip_depth: float
		if staff:
			grip_depth = STAFF_GRIP_DEPTH
		else:
			grip_depth = lerpf(carry_depth,
				lerpf(0.05,0.20,smoothstep(0.0,0.55,float(swing.cut))),solve_weight)
		var support_offset := handle*Vector3(0,0,grip_depth)-sword_hand.origin-support_basis*_palm_left
		var reach_weight := lerpf(0.998,0.90,solve_weight)
		# Bone-pose recovery may pull the primary wrist back before the torso
		# has unwound. Keep the shared hilt ahead of the chest while solving,
		# then hand its depth back to the authored carry with the same blend.
		var carry_handoff := 1.0-smoothstep(0.65,1.0,release)
		# A cocked hilt may sit close to the chest line, but never inside it.
		# Restore the 0.40 m front clearance as soon as the cut drives out.
		var clearance_floor := lerpf(0.28 if staff else 0.36,0.46,
			smoothstep(0.0,0.30,float(swing.cut)))
		var front_clearance := lerpf((hand.origin-pivot).dot(forward),clearance_floor,engage*carry_handoff)
		var hilt_target := sword_hand.origin+forward*maxf(0.0,front_clearance-(sword_hand.origin-pivot).dot(forward))
		var coupled := _two_hand_wrist_target(hilt_target,shoulder,arm_reach*reach_weight,
			support_shoulder-support_offset,support_length*reach_weight,forward)
		coupled = sword_hand.origin.lerp(coupled,support_attach)
		if coupled.distance_squared_to(sword_hand.origin) > 0.00000001:
			var right_pole := _bone_world(_arms[1][1]).origin-shoulder
			_solve_limb(_arms[1],coupled,sword_hand.basis,right_pole)
			sword_hand = _bone_world(_arms[1][2])
			handle = sword_hand*_sword_grip
		var authored_support_pole := (support_elbow-support_shoulder).normalized()
		var exterior_pole := (-right*2.0+forward*1.1-Vector3.UP*0.30).normalized()
		# Keep the exterior bend until the hilt has returned to the front guard;
		# restoring the carry elbow earlier cuts across the still-turned ribs.
		# Drive the support elbow outward from the start of the acquisition.
		# Waiting for full attachment leaves the authored down/in bend in place
		# while the wrist is already crossing the chest.
		var elbow_weight := engage*smoothstep(0.0,load_end*0.82,time)*carry_handoff
		var support_pole := authored_support_pole.lerp(exterior_pole,elbow_weight)
		var wrist_target := handle*Vector3(0,0,grip_depth)-support_basis*_palm_left
		if support_attach < 1.0:
			# Approach around the front-left of the ribs, then cross onto the
			# hilt. Blending solved bone rotations followed a different wrist
			# path and straightened the forearm through the chest mid-catch.
			var approach := support_shoulder-right*0.12+forward*0.34-Vector3.UP*0.10
			wrist_target = _bezier(left.origin,approach,wrist_target,support_attach)
			# Preserve bend room while the two hands are not yet coupled. At
			# acquisition's end the shared reach solver supplies this same limit.
			var acquire_reach := lerpf(support_shoulder.distance_to(left.origin),support_length*reach_weight,support_attach)
			wrist_target = support_shoulder+(wrist_target-support_shoulder).limit_length(acquire_reach)
			support_basis = _blend_basis(left.basis,support_basis,support_attach)
		_solve_limb(_arms[0],wrist_target,support_basis,support_pole)
	elif hand_key == "right" and weapon != "dual" and not shield_equipped and not focus_active:
		# A free off hand reaches forward as a counterbalance during the coil
		# and returns with the recovery; shield and focus hands keep their guard.
		_pose_counterbalance_arm(float(swing.load)*(1.0-float(swing.drive)),forward,right)

func _pose_counterbalance_arm(weight: float, forward: Vector3, right: Vector3) -> void:
	if weight <= 0.0001:
		return
	var shoulder := _bone_world(_arms[0][0]).origin
	var hand := _bone_world(_arms[0][2])
	var upper_pose := skeleton.get_bone_pose(_arms[0][0])
	var lower_pose := skeleton.get_bone_pose(_arms[0][1])
	var hand_pose := skeleton.get_bone_pose(_arms[0][2])
	var elbow := _bone_world(_arms[0][1]).origin
	var arm_reach := shoulder.distance_to(elbow)+elbow.distance_to(hand.origin)
	var target := shoulder+forward*0.42-right*0.14+Vector3.UP*0.04
	var offset := target-shoulder
	if offset.length() > arm_reach*0.90:
		target = shoulder+offset.normalized()*arm_reach*0.90
	var pole := (-right*1.2+forward*0.2-Vector3.UP*0.5).normalized()
	_solve_limb(_arms[0],target,hand.basis,pole)
	if weight < 0.999999:
		skeleton.set_bone_pose(_arms[0][0],upper_pose.interpolate_with(skeleton.get_bone_pose(_arms[0][0]),weight))
		skeleton.set_bone_pose(_arms[0][1],lower_pose.interpolate_with(skeleton.get_bone_pose(_arms[0][1]),weight))
		skeleton.set_bone_pose(_arms[0][2],hand_pose.interpolate_with(skeleton.get_bone_pose(_arms[0][2]),weight))

func _two_hand_wrist_target(target: Vector3, primary: Vector3, primary_radius: float,
		support: Vector3, support_radius: float, forward: Vector3) -> Vector3:
	# Closest point in the intersection of the two reachable balls. If either
	# sphere projection lies in the other ball, it is already the solution.
	var projected := primary+(target-primary).limit_length(primary_radius)
	if projected.distance_squared_to(support) <= support_radius*support_radius:
		return projected
	projected = support+(target-support).limit_length(support_radius)
	if projected.distance_squared_to(primary) <= primary_radius*primary_radius:
		return projected
	# Otherwise both constraints bind, so project onto their intersection
	# circle. Neither arm needs scaling, and the support palm stays on the hilt.
	var between := support-primary
	var distance := between.length()
	if distance < 0.000001:
		return primary+(target-primary).limit_length(minf(primary_radius,support_radius))
	var axis := between/distance
	var along := (primary_radius*primary_radius-support_radius*support_radius+distance*distance)/(2.0*distance)
	var centre := primary+axis*along
	var radial := target-centre
	radial -= axis*radial.dot(axis)
	if radial.length_squared() < 0.000001:
		radial = forward-axis*forward.dot(axis)
	var radius := sqrt(maxf(0.0,primary_radius*primary_radius-along*along))
	return centre+radial.normalized()*radius

func _ability_bow() -> bool:
	return phase == "ABILITY" and weapon == "bow" and not ability_draw_curve.is_empty()

func _ability_needs_standing() -> bool:
	return phase == "ABILITY" and AbilityRules.needs_standing(AbilityRules.by_id(ability_id))

func _sample_ability_draw() -> float:
	if ability_draw_curve.is_empty():
		return 0.0
	var progress := ability_progress()
	var first: Array = ability_draw_curve[0]
	if progress <= float(first[0]):
		return clampf(float(first[1]),0.0,1.0)
	for index in range(1,ability_draw_curve.size()):
		var previous: Array = ability_draw_curve[index-1]
		var current: Array = ability_draw_curve[index]
		if progress <= float(current[0]):
			var span := maxf(float(current[0])-float(previous[0]),0.000001)
			# A release key is nearly instantaneous; a smoothstep here would
			# smear the snap, so keep the interpolation linear.
			return clampf(lerpf(float(previous[1]),float(current[1]),(progress-float(previous[0]))/span),0.0,1.0)
	var last: Array = ability_draw_curve[ability_draw_curve.size()-1]
	return clampf(float(last[1]),0.0,1.0)

func _ability_spin_yaw() -> float:
	# The spin is presentation-only and derived from the phase clock, so a
	# replica reproduces the same turn without extra network state. The clip
	# carries the stance and the blade extension; the model turns underneath it.
	if phase != "ABILITY" or ability_spin == 0.0:
		return 0.0
	var progress := ability_progress()
	var turn := smoothstep(0.10,0.86,progress)
	return TAU*ability_spin*turn

func _apply_ability_pose() -> void:
	# The authored sprint carries the legs; this overlay drops the chest and
	# hips over the lead foot and lifts the gaze so the charge reads as weight
	# moving forward instead of a normal sprint.
	var progress := ability_progress()
	var weight := smoothstep(0.0,0.16,progress)*(1.0-smoothstep(0.78,1.0,progress))
	if weight <= 0.0001 or ability_lean <= 0.0001:
		return
	var spine := _bone_world(_bones.spine_01)
	spine.basis = Basis(global_basis.x,-ability_lean*weight)*spine.basis
	_set_bone_world(_bones.spine_01,spine)
	var chest := _bone_world(_bones.spine_03)
	chest.basis = Basis(global_basis.x,-ability_lean*0.5*weight)*chest.basis
	_set_bone_world(_bones.spine_03,chest)
	var head := _bone_world(_bones.Head)
	head.basis = Basis(global_basis.x,ability_lean*1.1*weight)*head.basis
	_set_bone_world(_bones.Head,head)
	var pelvis := _bone_world(_bones.pelvis)
	pelvis.origin -= global_basis.z*ability_lean*0.22*weight
	_set_bone_world(_bones.pelvis,pelvis)

func _apply_hit_react_pose() -> void:
	if _hit_react <= 0.0001 or _roll_progress >= 0.0 or phase != "READY" or _blocking:
		return
	var weight := clampf(_hit_react/0.42,0.0,1.0)
	var spine := _bone_world(_bones.spine_01)
	spine.basis = Basis(global_basis.x,0.22*weight)*spine.basis
	_set_bone_world(_bones.spine_01,spine)
	var head := _bone_world(_bones.Head)
	head.basis = Basis(global_basis.x,0.14*weight)*head.basis
	_set_bone_world(_bones.Head,head)
	var pelvis := _bone_world(_bones.pelvis)
	pelvis.origin += global_basis.z*0.035*weight
	_set_bone_world(_bones.pelvis,pelvis)

func _apply_step_pose() -> void:
	# A planted lateral lunge. The root keeps its facing while the hips open
	# toward the travel, the chest turns further and the head stays on target.
	# That is the side step; snapping the whole body to the velocity read as a
	# one-beat sideways sprint instead.
	var weight := sin(clampf(_step_progress,0.0,1.0)*PI)
	if weight <= 0.0:
		return
	var travel := Vector3(_step_direction.x,0.0,_step_direction.z)
	if travel.length_squared() < 0.0001:
		return
	travel = travel.normalized()
	var face := -global_basis.z
	var turn := clampf(atan2(face.cross(travel).y,face.dot(travel)),-PI*0.5,PI*0.5)
	var side := signf(turn)
	var pelvis := _bone_world(_bones.pelvis)
	pelvis.basis = Basis(Vector3.UP,turn*0.30*weight) \
		* Basis(face,-side*0.12*weight) \
		* Basis(global_basis.x,-0.16*weight) * pelvis.basis
	pelvis.origin += travel*(0.10*weight) - Vector3.UP*0.05*weight
	_set_bone_world(_bones.pelvis,pelvis)
	var spine := _bone_world(_bones.spine_01)
	spine.basis = Basis(Vector3.UP,turn*0.22*weight) \
		* Basis(face,side*0.05*weight) \
		* Basis(global_basis.x,-0.06*weight) * spine.basis
	_set_bone_world(_bones.spine_01,spine)
	var chest := _bone_world(_bones.spine_02)
	chest.basis = Basis(Vector3.UP,turn*0.08*weight)*chest.basis
	_set_bone_world(_bones.spine_02,chest)
	var head := _bone_world(_bones.Head)
	head.basis = Basis(Vector3.UP,-turn*0.42*weight)*head.basis
	_set_bone_world(_bones.Head,head)

func _sample_cover_lean() -> void:
	var clip: Dictionary = _profile.clips.cover_top
	if _cover_lean.y <= 0.0:
		clip = _profile.clips.cover_left if _cover_lean.dot(_cover_normal.cross(Vector3.UP)) > 0.0 else _profile.clips.cover_right
	_sample_clip(str(clip.name),clampf(_cover_lean.length(),0.0,1.0)*float(clip.duration))
	var parent_turn := Basis.IDENTITY
	for index in _cover_bones.size():
		var pose := skeleton.get_bone_global_pose(_cover_bones[index])
		var turn := pose.basis*_cover_neutral[index].basis.inverse()
		_cover_turns[index] = turn*parent_turn.inverse()
		parent_turn = turn
	_cover_shift = skeleton.get_bone_global_pose(_bones.pelvis).origin-_cover_neutral[0].origin

func _apply_cover_lean() -> void:
	# Keep the authored lean in the cover frame, even when an attack turns toward the crosshair.
	var cover_basis := Basis(Vector3.UP,atan2(-_cover_normal.x,-_cover_normal.z))
	var inverse := cover_basis.inverse()
	var left := _bone_world(_legs[0][2])
	var right := _bone_world(_legs[1][2])
	for index in _cover_bones.size():
		var bone := _cover_bones[index]
		var pose := _bone_world(bone)
		pose.basis = cover_basis*_cover_turns[index]*inverse*pose.basis
		if index == 0:
			pose.origin += cover_basis*_cover_shift
		_set_bone_world(bone,pose)
	_solve_limb(_legs[0],left.origin,left.basis)
	_solve_limb(_legs[1],right.origin,right.basis)

func _update_hand_contacts() -> void:
	var left := _bone_world(_arms[0][2])
	var right := _bone_world(_arms[1][2])
	bow_hand.global_transform = Transform3D(left.basis,left*_palm_left)
	string_hand.global_transform = Transform3D(right.basis,right*_palm_right)

func _aim_sword_thrust() -> void:
	var shoulder := _bone_world(_arms[1][0]).origin
	var hand := _bone_world(_arms[1][2])
	var offset := _aim_point-shoulder
	if Vector2(offset.x,offset.z).length() < 0.35 or offset.length_squared() < 0.0001:
		return
	var direction := offset.normalized()
	var along := (hand.origin-shoulder).dot(direction)
	var elbow := _bone_world(_arms[1][1]).origin
	var arm_reach := shoulder.distance_to(elbow)+elbow.distance_to(hand.origin)
	var blade_length := float(STAFF_DATA[staff_index].length) if _staff_shown() else float(SWORD_DATA[sword_index].length)
	var aim_along := offset.length()-blade_length-0.09
	var window := _melee_window("right")
	var thrust := smoothstep(window.x*0.6,window.y,_right_melee_time)
	along = lerpf(along,clampf(aim_along,along,arm_reach-0.01),thrust)
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = global_basis.x
	var aim_basis := Basis.looking_at(direction,up)
	_solve_limb(_arms[1],shoulder+direction*along,aim_basis*_sword_grip.basis.inverse())

func _aim_dagger_stab() -> void:
	var shoulder := _bone_world(_arms[1][0]).origin
	var hand := _bone_world(_arms[1][2])
	var offset := _aim_point-shoulder
	# Ignore a placeholder/self aim (the arena's initial aim is the actor's own
	# chest); the authored thrust remains for those.
	if Vector2(offset.x,offset.z).length() < 0.35 or offset.length_squared() < 0.0001:
		return
	var direction := offset.normalized()
	# Keep the authored chamber/extension travel, but put the hand on the aim
	# line: the signed distance along the aim is the authored hand's own.
	var along := (hand.origin-shoulder).dot(direction)
	# During the strike the arm extends toward the aim point. The hand cannot
	# pass the arm's length or the point itself (the blade's reach is 0.43).
	var elbow := _bone_world(_arms[1][1]).origin
	var arm_reach := shoulder.distance_to(elbow)+elbow.distance_to(hand.origin)
	var aim_along := offset.length()-float(DAGGER_DATA.length)-0.09
	var window := _melee_window()
	var thrust := smoothstep(window.x*0.6,window.y,_phase_time)
	along = lerpf(along,clampf(aim_along,along,arm_reach-0.01),thrust)
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = global_basis.x
	var aim_basis := Basis.looking_at(direction,up)
	# The socket carries its own grip rotation; cancel it so the blade axis
	# itself points at the aim rather than the hand bone.
	_solve_limb(_arms[1],shoulder+direction*along,aim_basis*_sword_grip.basis.inverse())

func _update_shield_pose() -> void:
	if active_shield == null:
		return
	if not shield_equipped:
		active_shield.set_active(false)
		return
	active_shield.set_active(true)
	var shield_radius := 0.36
	if active_shield.has_method("radius"):
		shield_radius = float(active_shield.radius())
	var size_delta := shield_radius-0.36
	# A shield skill presents the boss toward the target. The carried pose
	# hangs it flat against the outside of the forearm, which would read as an
	# edge-first shove if the authored arm came up in front.
	if phase == "ABILITY" and ability_slot == 1:
		var forward := _aim_point-global_position
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = -global_basis.z
			forward.y = 0.0
		forward = forward.normalized()
		var hand := _bone_world(_arms[0][2])
		var basis := Basis.looking_at(forward,Vector3.UP)
		var center := hand.origin+forward*(0.10+size_delta*0.4)+Vector3.UP*0.03
		# The shove is driven from the body, not from the wrist: a clip that
		# draws the hand back to the chest would carry the disc through the
		# torso and the helmet. Push the disc out until its plane clears the
		# chest and head, and solve the arm onto the pushed wrist.
		var chest := _bone_world(_bones.spine_03).origin
		var head := _bone_world(_bones.Head).origin
		var needed := maxf((chest-global_position).dot(forward)+ABILITY_SHIELD_CHEST_CLEAR,
			(head-global_position).dot(forward)+ABILITY_SHIELD_HEAD_CLEAR)
		# A low shield (the ground slam) passes the legs, not the head, so the
		# bones that actually share its height set the clearing distance.
		var gated := shield_radius*0.8+0.15
		for side in 2:
			for joint in 2:
				var leg := _bone_world(_legs[side][joint]).origin
				if absf(center.y-leg.y) > gated:
					continue
				needed = maxf(needed,(leg-global_position).dot(forward)+ABILITY_SHIELD_LEG_CLEAR)
		var ahead := (center-global_position).dot(forward)
		if ahead < needed:
			center += forward*(needed-ahead)
			var shoulder := _bone_world(_arms[0][0]).origin
			var elbow := _bone_world(_arms[0][1]).origin
			var pole := elbow-(shoulder+hand.origin)*0.5
			_solve_limb(_arms[0],center-forward*0.12-Vector3.UP*0.03,basis,pole)
		active_shield.global_transform = Transform3D(basis,center)
		return
	if _blocking:
		var forward := _block_forward
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = -global_basis.z
		forward = forward.normalized()
		var right := global_basis.x
		var chest := _bone_world(_bones.spine_03).origin
		# Keep the shield clear of the weapon hand behind it: the one-handed
		# guard bracer reaches almost to the face, so a close carry clips it.
		# Crouching brings that hand further forward relative to the chest.
		var reach := 0.58+size_delta+0.06*_crouch_amount
		var center := chest+forward*reach+Vector3.UP*0.02-right*0.08
		var basis := Basis.looking_at(forward,Vector3.UP)
		active_shield.global_transform = Transform3D(basis,center)
		var hand := center-forward*0.12-Vector3.UP*0.03
		_solve_limb(_arms[0],hand,basis,-right*0.55-forward*0.15+Vector3.UP*0.1)
	else:
		# A carried shield hangs flat against the outside of the left forearm
		# with its boss facing out. Centering it on the wrist with the face
		# forward slices the forearm and, when crouched, the torso and legs.
		var hand := _bone_world(_arms[0][2])
		var outward := -global_basis.x
		var basis := Basis.looking_at(outward,Vector3.UP)
		var carry := 0.18+size_delta*0.5
		var center := hand.origin+outward*carry+Vector3.UP*0.02
		active_shield.global_transform = Transform3D(basis,center)

func _update_bow_pose(drawing: bool) -> void:
	var left := _bone_world(_arms[0][2])
	var right := _bone_world(_arms[1][2])
	var carry_grip: Vector3 = left*_palm_left
	var carry_contact: Vector3 = right*_palm_right
	var bow_basis := left.basis*_bow_grip_basis
	var grip := carry_grip
	var contact := carry_contact
	var right_basis := right.basis
	if drawing:
		var shoulder := _bone_world(_arms[1][0]).origin
		var body_right := shoulder-_bone_world(_arms[0][0]).origin
		body_right.y = 0.0
		body_right = body_right.normalized()
		var body_forward := Vector3.UP.cross(body_right).normalized()
		var chest := _bone_world(_bones.spine_03).origin
		var shoulder_gate := shoulder+body_right*0.16+Vector3.UP*0.28-body_forward*0.03
		var front_gate := shoulder+body_forward*0.32+body_right*0.12+Vector3.UP*0.10
		var anchor := _jaw_anchor()
		var offset := _aim_point-anchor
		var elevation := clampf(atan2(offset.y,maxf(Vector2(offset.x,offset.z).length(),0.001)),-MAX_ELEVATION,MAX_ELEVATION)
		var aim_yaw := atan2(-offset.x,-offset.z)
		if _cover_active:
			aim_yaw = lerp_angle(atan2(-_cover_normal.x,-_cover_normal.z),aim_yaw,smoothstep(0.0,1.0,_cover_lean.length()))
		var aim_basis := Basis(Vector3.UP,aim_yaw)*Basis(Vector3.RIGHT,elevation)
		var weight := _archery_weight()
		# Push the bow out while pulling the string back; a fully extended bow
		# at zero tension puts its brace point beyond the drawing arm's reach.
		var grip_distance := lerpf(Bow.BRACE_DISTANCE+0.12,Bow.DRAW_DISTANCE,draw_amount)
		grip = carry_grip.lerp(anchor-aim_basis.z*grip_distance,weight)
		bow_basis = bow_basis.slerp(aim_basis,weight)
		if phase == "RELEASE":
			grip = to_global(_release_grip)
			bow_basis = global_basis*Basis(_release_bow_rotation)
		elif phase == "RECOVER":
			# Load in front of the centreline, within both arms' reach. A far-left
			# target straightens the right elbow and drives its forearm through the chest.
			var nocking_grip := chest+body_right*0.04+body_forward*0.46-Vector3.UP*0.05
			var nocking_basis := Basis.looking_at(body_forward,Vector3.UP)
			var lower := smoothstep(0.18,0.40,_phase_time)
			var relax := smoothstep(0.72,RECOVER_SECONDS,_phase_time)
			grip = to_global(_release_grip).lerp(nocking_grip,lower).lerp(carry_grip,relax)
			bow_basis = (global_basis*Basis(_release_bow_rotation)).slerp(nocking_basis,lower).slerp(bow_basis,relax)
		var left_basis := bow_basis*_bow_grip_basis.inverse()
		_solve_limb(_arms[0],grip-left_basis*_palm_left,left_basis,-body_right*0.60+body_forward*0.40-Vector3.UP*0.20)
		left = _bone_world(_arms[0][2])
		active_bow.global_transform = Transform3D(bow_basis,left*_palm_left)
		active_bow.set_draw(draw_amount)
		right_basis = bow_basis*_string_grip_basis.inverse()
		contact = active_bow.get_nock_position()
		var draw_reach := 1.0
		if phase == "DRAWING":
			draw_reach = smoothstep(0.03,RAISE_SECONDS,_phase_time)
			var hip_gate := chest+body_forward*0.35+body_right*0.28-Vector3.UP*0.20
			contact = _hand_arc(carry_contact,hip_gate,front_gate,contact,draw_reach)
			right_basis = right.basis.slerp(right_basis,draw_reach)
		elif phase in ["RELEASE","RECOVER"]:
			var follow := smoothstep(0.0,RELEASE_SECONDS,_phase_time) if phase == "RELEASE" else 1.0
			contact = to_global(_release_contact)+global_basis*Basis(_release_bow_rotation).z*(0.12*follow*_release_raise*_release_charge)
			if phase == "RECOVER":
				var quiver_top := _quiver.to_global(Vector3(0,0.29,0))
				if _phase_time < 0.40:
					contact = _hand_arc(contact,shoulder_gate,shoulder_gate,quiver_top,smoothstep(0.03,0.40,_phase_time))
				elif _phase_time < 0.68:
					contact = _hand_arc(quiver_top,shoulder_gate,front_gate,active_bow.get_nock_position(),smoothstep(0.40,0.68,_phase_time))
				else:
					var relax := smoothstep(0.72,RECOVER_SECONDS,_phase_time)
					var hip_gate := chest+body_forward*0.35+body_right*0.28-Vector3.UP*0.20
					contact = _hand_arc(active_bow.get_nock_position(),hip_gate,hip_gate,carry_contact,relax)
					right_basis = right_basis.slerp(right.basis,relax)
		var elbow_pole := body_right*0.65+body_forward*0.40+Vector3.UP*0.12
		if phase == "DRAWING":
			elbow_pole = (_bone_world(_arms[1][1]).origin-shoulder).lerp(elbow_pole,draw_reach)
		_solve_limb(_arms[1],contact-right_basis*_palm_right,right_basis,elbow_pole)
	else:
		active_bow.global_transform = Transform3D(bow_basis,grip)
		active_bow.set_draw(0.0)
	active_bow.set_arrow_visible(_roll_progress < 0.0 and (phase in ["READY","DRAWING","HOLDING"] \
		or (phase == "RECOVER" and _phase_time >= 0.68) \
		or (phase == "ABILITY" and not ability_draw_curve.is_empty() and draw_amount > 0.03)))
	_update_hand_contacts()

func _jaw_anchor() -> Vector3:
	return _bone_world(_jaw_bone)*_jaw_offset

func _hand_arc(start: Vector3, control_a: Vector3, control_b: Vector3, finish: Vector3, t: float) -> Vector3:
	var u := 1.0-t
	return start*(u*u*u)+control_a*(3.0*u*u*t)+control_b*(3.0*u*t*t)+finish*(t*t*t)

func _staff_mesh_offset() -> float:
	# Shift the shaft so the grip origin sits just below its midpoint; the
	# support hand then grips STAFF_GRIP_DEPTH above it, around the centre.
	var middle := float(STAFF_DATA[staff_index].length)*0.5+0.25
	if not _staff_shown() or not is_melee():
		return middle
	var variant := melee_variant("right")
	if variant not in ["overhead","stab"]:
		return middle
	# The authored overhead and thrust finish with the sword hand low or
	# ahead of the chest. A centred shaft would put its lower half through
	# the floor or the head, so the staff slides to an end grip for those two
	# precision attacks and returns to the middle on recovery.
	var duration := melee_seconds("right")
	var time := maxf(_right_melee_time,0.0)
	var slide := smoothstep(0.0,minf(0.40,duration*0.38),time)
	var restore := smoothstep(duration*0.78,duration,time)
	return lerpf(middle,0.0,slide*(1.0-restore))

func _weapon_socket(hand_xf: Transform3D) -> Transform3D:
	if _staff_shown():
		return hand_xf*_sword_grip*Transform3D(Basis(),Vector3(0,0,_staff_mesh_offset()))
	return hand_xf*_sword_grip

func _bone_world(index: int) -> Transform3D:
	return skeleton.global_transform*skeleton.get_bone_global_pose(index)

func _set_bone_world(index: int, pose: Transform3D) -> void:
	skeleton.set_bone_global_pose(index,skeleton.global_transform.affine_inverse()*pose)

func _bezier(start: Vector3, control: Vector3, finish: Vector3, weight: float) -> Vector3:
	var inverse := 1.0-weight
	return start*(inverse*inverse)+control*(2.0*inverse*weight)+finish*(weight*weight)

func _arc(from: Vector3, to: Vector3) -> Quaternion:
	# A 180-degree vector pair has no unique rotation axis, and Godot's from/to
	# quaternion then flips axis between frames. Nudge the target just off the
	# antipode toward a stable side so the arc stays continuous.
	if from.dot(to) < -0.9995:
		var side := from.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = from.cross(Vector3.RIGHT)
		to = (to+side.normalized()*0.02).normalized()
	return Quaternion(from,to)

func _blend_basis(from: Basis, to: Basis, weight: float) -> Basis:
	# Interpolate orientation as two independent vector arcs instead of slerping
	# whole bases. A basis slerp between a changing authored hand pose and the
	# cut target flips its rotation axis when the pair approaches 180 degrees,
	# which snapped the sword through the body mid-swing. Direction and up are
	# stable vectors here, and the result reconstructs `from` exactly at 0.
	var dir := (Basis(Quaternion.IDENTITY.slerp(_arc(-from.z,-to.z),weight))*(-from.z)).normalized()
	var up := (Basis(Quaternion.IDENTITY.slerp(_arc(from.y,to.y),weight))*from.y).normalized()
	if absf(dir.dot(up)) > 0.985:
		up = to.y if absf(dir.dot(to.y)) < 0.985 else Vector3.UP
	return Basis.looking_at(dir,up)

func _solve_limb(chain: PackedInt32Array, target: Vector3, endpoint_basis: Basis, pole: Vector3 = Vector3.ZERO) -> void:
	var upper := _bone_world(chain[0])
	var lower := _bone_world(chain[1])
	var end := _bone_world(chain[2])
	var upper_length := upper.origin.distance_to(lower.origin)
	var lower_length := lower.origin.distance_to(end.origin)
	var offset := target-upper.origin
	var axis := offset.normalized() if offset.length_squared() > 0.000001 else Vector3.DOWN
	var distance := clampf(offset.length(),absf(upper_length-lower_length)+0.001,upper_length+lower_length-0.001)
	var bend := lower.origin-upper.origin if pole.is_zero_approx() else pole
	bend -= axis*bend.dot(axis)
	if bend.length_squared() < 0.000001:
		bend = upper.basis.z-axis*upper.basis.z.dot(axis)
	bend = bend.normalized()
	var along := (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2.0*distance)
	var elbow := upper.origin+axis*along+bend*sqrt(maxf(0.0,upper_length*upper_length-along*along))
	var wrist := upper.origin+axis*distance
	# Rotate the authored bone frames; never invent a replacement twist basis or scale a bone.
	var upper_turn := Basis(Quaternion((lower.origin-upper.origin).normalized(),(elbow-upper.origin).normalized()))
	var lower_turn := Basis(Quaternion((end.origin-lower.origin).normalized(),(wrist-elbow).normalized()))
	_set_bone_world(chain[0],Transform3D(upper_turn*upper.basis,upper.origin))
	_set_bone_world(chain[1],Transform3D(lower_turn*lower.basis,elbow))
	_set_bone_world(chain[2],Transform3D(endpoint_basis,wrist))

func _plant_archery_feet(weight: float) -> void:
	var stance := global_basis*Basis(Vector3.UP,STANCE_YAW*weight)
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var foot := _bone_world(_legs[side][2])
		var planted := global_position+stance*Vector3(sign_x*0.18,_foot_height[side],0.0)
		var basis := skeleton.global_basis*skeleton.get_bone_global_rest(_legs[side][2]).basis
		_solve_limb(_legs[side],foot.origin.lerp(planted,weight),foot.basis.slerp(basis,weight),stance*Vector3(sign_x*0.08,0,-1))

func _step_foot_offset(side: int) -> Vector3:
	# Widen the stance toward the step: the leading foot reaches out and lifts,
	# the trailing foot braces. The pelvis shift is deliberately smaller than
	# the lead reach so the silhouette stays a step, not a slide.
	if _step_progress < 0.0:
		return Vector3.ZERO
	var travel := Vector3(_step_direction.x,0.0,_step_direction.z)
	if travel.length_squared() < 0.0001:
		return Vector3.ZERO
	travel = travel.normalized()
	var local := travel.dot(global_basis.x)
	if absf(local) < 0.1:
		return Vector3.ZERO
	var weight := sin(clampf(_step_progress,0.0,1.0)*PI)
	var lead := 0 if local < 0.0 else 1
	if side == lead:
		return travel*(0.26*weight)+Vector3.UP*(0.075*weight)
	return travel*(-0.07*weight)

func _place_feet() -> void:
	if not _ground_sampler.is_valid():
		return
	var offset_l := _step_foot_offset(0)
	var offset_r := _step_foot_offset(1)
	var left := _bone_world(_legs[0][2])
	var right := _bone_world(_legs[1][2])
	var left_floor := left.origin+Vector3(offset_l.x,0.0,offset_l.z)
	var right_floor := right.origin+Vector3(offset_r.x,0.0,offset_r.z)
	var floors := Vector2(float(_ground_sampler.call(left_floor)),float(_ground_sampler.call(right_floor)))
	var base_floor := minf(floors.x,floors.y)
	_model.position.y = clampf(base_floor-global_position.y,-0.4,0.4)
	for side in 2:
		var foot := _bone_world(_legs[side][2])
		var offset := offset_l if side == 0 else offset_r
		var ankle := foot.origin+offset+Vector3.UP*(floors[side]-base_floor)
		var toe := foot.origin-global_basis.z*0.15
		var edge := foot.origin+global_basis.x*0.08
		var forward := -global_basis.z*0.15+Vector3.UP*(float(_ground_sampler.call(toe))-floors[side])
		var across := global_basis.x*0.08+Vector3.UP*(float(_ground_sampler.call(edge))-floors[side])
		var normal := across.cross(forward).normalized()
		# Terrain adds slope; do not erase authored heel lift or toe push-off.
		var basis := Basis(Quaternion(Vector3.UP,normal))*foot.basis
		_solve_limb(_legs[side],ankle,basis)
