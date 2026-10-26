extends Control

signal bow_selected(index: int)
signal armor_selected(slot: String, set_index: int)
signal sword_selected(index: int)
signal weapon_selected(value: String)
signal shield_selected(active: bool)
signal consumable_selected(kind: String)
signal view_toggled
signal camp_requested
signal map_toggled
signal inventory_requested
signal equipment_requested
signal cursor_requested(free: bool)

const AbilitySlot = preload("res://scripts/ability_slot.gd")
const Stamina = preload("res://scripts/stamina.gd")
const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const CROSSHAIR_AXES = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
var map_open := false
var reticle := Vector2.ZERO
var reticle_visible := false
var _weapon := "bow"
var _shield_equipped := false
var _armor_pieces: Dictionary = {}
var _region: Label
var _session: Label
var _quest: Label
var _health_label: Label
var _gold_label: Label
var _backpack_label: Label
var _phase: Label
var _loadout: Label
var _cover_status: Label
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _stamina_label: Label
var _charge_bar: ProgressBar
var _ability_slot
var _off_ability_slot
var _trinket_ability_slot
var _interaction_panel: Panel
var _interaction: Label
var _feedback: Label
var _feedback_time := 0.0
var _damage_flash := 0.0
var _map_button: Button
var _player_position := Vector3.ZERO
var _player_yaw := 0.0
var _activated: Dictionary = {}
var _landmarks: Array[Dictionary] = []
var _paths: Array[PackedVector3Array] = []
var _interactables: Array[Dictionary] = []
var _world_limit := 145.0
var _map_style: StyleBoxFlat
## Worn-trinket maxima. The bars and the labels share them so a +25 health ring
## reads as 125/125 rather than an over-full bar.
var _max_health := 100.0
var _max_stamina := Stamina.MAX

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_style = _style(Color(0.045, 0.095, 0.12, 0.96), Color("58716b"), 10)
	var ui_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", CREAM)
	ui_theme.set_color("font_color", "Button", CREAM)
	ui_theme.set_color("font_hover_color", "Button", Color.WHITE)
	ui_theme.set_color("font_pressed_color", "Button", Color("13282f"))
	ui_theme.set_stylebox("normal", "Button", _style(Color("243a40"), Color("456068"), 6))
	ui_theme.set_stylebox("hover", "Button", _style(Color("34545b"), GOLD, 6))
	ui_theme.set_stylebox("pressed", "Button", _style(GOLD, GOLD, 6))
	theme = ui_theme
	var title := _panel(self, Vector2(24, 22), Vector2(300, 88))
	_label(title, "IRONWOOD  " + str(ProjectSettings.get_setting("application/config/version")), Vector2(17, 11), 25, CREAM)
	_region = _label(title, "The frontier", Vector2(18, 49), 16, GOLD)
	_session = _label(title, "", Vector2(18, 70), 10, MUTED)
	var quest_panel := _panel(self, Vector2(-340, 22), Vector2(316, 154))
	quest_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	_label(quest_panel, "WORLD QUEST  /  THE LOST WAYSTONES", Vector2(16, 13), 11, GOLD)
	_quest = _label(quest_panel, "Restore the frontier   0 / 3", Vector2(16, 39), 20, CREAM)
	_label(quest_panel, "Follow the trails to the forest, ruins and ridge.\nDefeat the guards. Press E at each waystone.\nThe village campfire restores your health.", Vector2(16, 78), 12, MUTED)
	_feedback = _label(self, "", Vector2(-360, 111), 17, GOLD)
	_feedback.set_anchors_preset(Control.PRESET_CENTER_TOP, true)
	_feedback.size.x = 720
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_color_override("font_shadow_color", Color("10242b"))
	_feedback.add_theme_constant_override("shadow_outline_size", 4)
	_feedback.add_theme_constant_override("shadow_offset_y", 2)
	var vitals := _panel(self, Vector2(24, -154), Vector2(300, 122))
	vitals.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	_health_label = _label(vitals, "HEALTH  100 / 100", Vector2(16, 12), 13, CREAM)
	_health_bar = _bar(vitals, Vector2(16, 37), Vector2(268, 11), Color("72b58b"))
	_health_bar.max_value = _max_health
	_stamina_bar = _bar(vitals, Vector2(16, 58), Vector2(268, 5), GOLD)
	_stamina_bar.max_value = _max_stamina
	_stamina_label = _label(vitals, "STAMINA  %d / %d" % [int(Stamina.MAX),int(Stamina.MAX)], Vector2(16, 70), 10, MUTED)
	_gold_label = _label(vitals, "0 GOLD  /  0 FOES", Vector2(16, 91), 13, GOLD)
	_ability_slot = AbilitySlot.new()
	_ability_slot.position = Vector2(332, -154)
	_ability_slot.configure(0)
	_ability_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	add_child(_ability_slot)
	_off_ability_slot = AbilitySlot.new()
	_off_ability_slot.position = Vector2(436, -154)
	_off_ability_slot.configure(1)
	_off_ability_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	add_child(_off_ability_slot)
	_trinket_ability_slot = AbilitySlot.new()
	_trinket_ability_slot.position = Vector2(540, -154)
	_trinket_ability_slot.configure(2)
	_trinket_ability_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	add_child(_trinket_ability_slot)
	var backpack := _panel(self, Vector2(-216, -243), Vector2(192, 30))
	backpack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	backpack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backpack_label = _label(backpack, "BACKPACK  0 / 15", Vector2(12, 6), 12, TEAL)
	var charge := _panel(self, Vector2(648, -133), Vector2(412, 101))
	charge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	_phase = _label(charge, "", Vector2(17, 12), 13, CREAM)
	_charge_bar = _bar(charge, Vector2(17, 41), Vector2(378, 8), GOLD)
	_loadout = _label(charge, "", Vector2(17, 63), 13, MUTED)
	var cover_panel := _panel(self, Vector2(24, -289), Vector2(620, 116))
	cover_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	_cover_status = _label(cover_panel, "OPEN / RIGHT SHOULDER", Vector2(15, 10), 12, MUTED)
	_label(cover_panel, "F  Cover / exit   C  Crouch   SPACE  Jump   Q / E  Step left / right   G  Interact\nSHIFT  Sprint / fast cover   Sprint + C  Slide\nLMB  Diagonal cut / draw   WHEEL UP  Stab   WHEEL DOWN  Overhead\nRMB  Guard / peek (dual: right cut)   HOLD T  Throw   X  Lookout", Vector2(15, 35), 11, CREAM)
	_interaction_panel = _panel(self, Vector2(-310, -190), Vector2(620, 39))
	_interaction_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	_interaction = _label(_interaction_panel, "", Vector2(15, 9), 14, GOLD)
	_interaction_panel.visible = false
	var equipment_button := _button(self, "I   INVENTORY", Vector2(-216, -163), Vector2(192, 35))
	equipment_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	equipment_button.pressed.connect(func(): inventory_requested.emit())
	var kit_button := _button(self, "P   EQUIPMENT", Vector2(-216, -207), Vector2(192, 35))
	kit_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	kit_button.pressed.connect(func(): equipment_requested.emit())
	_map_button = _button(self, "M   WORLD MAP", Vector2(-216, -119), Vector2(192, 35))
	_map_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	_map_button.pressed.connect(func(): map_toggled.emit())
	var camp_button := _button(self, "R   RETURN TO TOWN", Vector2(-216, -75), Vector2(192, 35))
	camp_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	camp_button.pressed.connect(func(): camp_requested.emit())
	var hints := _label(self, "MOUSE  Aim   LMB  Draw / diagonal cut   WHEEL UP  Stab   WHEEL DOWN  Overhead   Q / E  Step   HOLD T  Throw   1-5  Gear   TAB  Swap   6 / 7  Consumables   SHIFT + SPACE  Roll   SHIFT + 1 / 2 / 3  Skills   G  Interact   I  Inventory   P  Equipment   F8  Performance", Vector2(-600, -23), 11, CREAM)
	hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	hints.add_theme_color_override("font_shadow_color", Color("10242b"))
	hints.add_theme_constant_override("shadow_outline_size", 3)

func set_limits(max_health: float, max_stamina: float) -> void:
	_max_health = maxf(1.0,max_health)
	_max_stamina = maxf(1.0,max_stamina)
	if _health_bar != null:
		_health_bar.max_value = _max_health
	if _stamina_bar != null:
		_stamina_bar.max_value = _max_stamina

func configure_map(landmarks: Array[Dictionary], paths: Array[PackedVector3Array], interactables: Array[Dictionary], limit: float) -> void:
	_landmarks = landmarks
	_paths = paths
	_interactables = interactables
	_world_limit = limit

func update_status(health: float, stamina: float, gold: int, kills: int, phase_name: String, draw_amount: float, region: String, interval: float, progress: float, movement: String, blocking: bool = false, parry_ready: bool = false, left_melee: float = 1.0, right_melee: float = 1.0, consume_kind: String = "", consume_time: float = 0.0, ability_state: Dictionary = {}, off_ability_state: Dictionary = {}, trinket_ability_state: Dictionary = {}) -> void:
	_region.text = region
	_health_label.text = "HEALTH  %d / %d" % [int(health),int(round(_max_health))]
	_health_bar.value = health
	_stamina_bar.value = stamina
	_stamina_label.text = "STAMINA  %d / %d" % [int(stamina),int(round(_max_stamina))]
	_ability_slot.update_state(ability_state)
	if is_instance_valid(_off_ability_slot):
		_off_ability_slot.update_state(off_ability_state)
	if is_instance_valid(_trinket_ability_slot):
		_trinket_ability_slot.update_state(trinket_ability_state)
	_gold_label.text = "%d GOLD  /  %d FOES" % [gold, kills]
	_charge_bar.value = draw_amount * 100.0 if phase_name in ["DRAWING", "HOLDING", "T_DRAW", "T_HOLD"] else progress * 100.0
	if phase_name == "ABILITY":
		var charge_ratio := 0.0
		var active_state := ability_state
		if active_state.is_empty() or not bool(active_state.get("active", false)):
			active_state = off_ability_state
		if active_state.is_empty() or not bool(active_state.get("active", false)):
			active_state = trinket_ability_state
		if not active_state.is_empty():
			charge_ratio = clampf(float(active_state.get("elapsed",0.0))/maxf(float(active_state.get("duration",1.0)),0.001),0.0,1.0)
		_charge_bar.value = charge_ratio * 100.0
		_phase.text = "%s  %d%%  /  %s" % [str(active_state.get("name", "SKILL")), int(charge_ratio * 100.0), str(active_state.get("key", ""))]
	elif phase_name == "BANDAGE" or consume_kind == "bandage":
		_charge_bar.value = clampf(consume_time/3.0,0.0,1.0)*100.0
		_phase.text = "WRAPPING BANDAGE  %d%%  /  STAND STILL" % int(clampf(consume_time/3.0,0.0,1.0)*100.0)
	elif phase_name == "DRINK" or consume_kind == "potion":
		_charge_bar.value = clampf(consume_time/0.5,0.0,1.0)*100.0
		_phase.text = "DRINKING POTION  %d%%" % int(clampf(consume_time/0.5,0.0,1.0)*100.0)
	elif _weapon == "dual" and (left_melee < 0.999999 or right_melee < 0.999999):
		_phase.text = "DUAL  /  LEFT %s  /  RIGHT %s" % [_melee_pct(left_melee),_melee_pct(right_melee)]
	elif phase_name in ["DRAWING", "HOLDING"]:
		_phase.text = "DRAW %.0f%%  /  DAMAGE x%.2f  /  RELEASE TO SHOOT" % [draw_amount * 100, draw_amount]
	elif phase_name in ["T_DRAW", "T_HOLD"]:
		_phase.text = "THROW %.0f%%  /  DAMAGE x%.2f  /  RELEASE TO THROW" % [draw_amount * 100, draw_amount]
	elif phase_name.begins_with("MELEE"):
		if _weapon == "dual":
			_phase.text = ("LEFT DIAGONAL CUT / %.2f s" if phase_name == "MELEE_L" else "RIGHT ATTACK / %.2f s") % interval
		elif phase_name == "MELEE_ST":
			_phase.text = "FORWARD STAB / %.2f s SWING" % interval
		elif phase_name == "MELEE_DL":
			_phase.text = "LEFT DIAGONAL CUT / %.2f s" % interval
		elif phase_name == "MELEE_DR":
			_phase.text = "RIGHT DIAGONAL CUT / %.2f s" % interval
		else:
			_phase.text = "OVERHEAD CHOP / %.1f s SWING" % interval
	elif blocking:
		if _shield_equipped:
			_phase.text = "SHIELD UP / FRONT ARROWS STOP"
		elif _weapon == "dagger":
			_phase.text = "WEAK GUARD / DAGGER ONLY SOFTENS THE HIT"
		else:
			_phase.text = "PARRY WINDOW / COUNTER NOW" if parry_ready else "GUARDING / EACH HIT COSTS STAMINA"
	elif phase_name in ["RELEASE", "RECOVER"]:
		_phase.text = "NOCKING NEXT ARROW / %.1f s" % [(1.0 - progress) * interval]
	elif phase_name in ["T_RELEASE", "T_RECOVER"]:
		_phase.text = "THROW RECOVERY %.1f s  /  %s" % [(1.0 - progress) * interval, movement]
	elif progress < 0.999999:
		_phase.text = "RECOVERY %.1f s  /  %s" % [(1.0 - progress) * interval, movement]
	else:
		if _weapon == "dual":
			_phase.text = "DUAL WIELD / LMB LEFT CUT / RMB RIGHT CUT / NO GUARD"
		elif _weapon == "bow":
			_phase.text = "READY / HOLD LMB TO DRAW / RELEASE TO SHOOT"
		elif _weapon == "none":
			_phase.text = "UNARMED / PRESS P TO EQUIP A WEAPON"
		else:
			_phase.text = "READY / LMB DIAGONAL BY SHOULDER / WHEEL UP STAB / WHEEL DOWN OVERHEAD"

func _melee_pct(value: float) -> String:
	return "READY" if value >= 0.999999 else "%d%%" % int(value*100.0)

func update_cover(active: bool, low: bool, peeking: bool, side: int, crouched: bool, sliding: bool) -> void:
	var stance := "SLIDING" if sliding else "CROUCHED" if crouched else "OPEN"
	if active:
		if peeking:
			stance = "TOP LOOKOUT" if low else "LEFT LOOKOUT" if side < 0 else "RIGHT LOOKOUT"
		else:
			stance = ("LOW COVER" if low else "TALL COVER") + (" / CROUCHED" if crouched else " / TUCKED")
	_cover_status.text = stance if active and peeking else stance + (" / LEFT SHOULDER" if side < 0 else " / RIGHT SHOULDER")
	_cover_status.add_theme_color_override("font_color", TEAL if active and peeking else GOLD if active else MUTED)

func update_loadout(_bow: int, armor_pieces: Dictionary, data: Dictionary, armor_summary: String, _sword: int, weapon: String, sword_data: Dictionary, dagger_data: Dictionary = {}, shield: bool = false) -> void:
	_shield_equipped = shield
	_armor_pieces = armor_pieces.duplicate()
	_weapon = weapon
	if weapon == "none":
		_loadout.text = "UNARMED / %s" % armor_summary
	else:
		var weapon_name := String(data.name) if weapon == "bow" else String(dagger_data.name) if weapon == "dagger" else String(sword_data.name)
		if weapon == "dual":
			weapon_name = "%s + OFF HAND" % String(sword_data.name)
		_loadout.text = "%s / %s / %s" % [weapon.to_upper(),weapon_name,armor_summary]

func set_backpack(count: int, capacity: int) -> void:
	if _backpack_label == null:
		return
	_backpack_label.text = "BACKPACK  %d / %d" % [count, capacity]
	_backpack_label.add_theme_color_override("font_color", GOLD if count >= capacity else TEAL)

func update_world_position(position_at: Vector3, yaw: float, activated: Dictionary) -> void:
	_player_position = position_at
	_player_yaw = yaw
	_activated = activated
	_quest.text = "Frontier restored  3 / 3" if activated.size() == 3 else "Restore the frontier   %d / 3" % activated.size()

func set_interaction(text: String) -> void:
	_interaction_panel.visible = not text.is_empty()
	_interaction.text = text

func set_session(text: String) -> void:
	if _session != null:
		_session.text = text

func set_inspecting(_value: bool) -> void:
	pass

func toggle_map() -> void:
	map_open = not map_open
	_map_button.text = "M   CLOSE MAP" if map_open else "M   WORLD MAP"
	cursor_requested.emit(map_open)

func close_panels() -> void:
	map_open = false
	_map_button.text = "M   WORLD MAP"
	cursor_requested.emit(false)

func show_feedback(message: String, seconds: float = 3.0) -> void:
	_feedback.text = message
	_feedback_time = seconds
	_feedback.modulate.a = 1.0

func flash_damage() -> void:
	_damage_flash = 0.35

func _process(delta: float) -> void:
	_feedback_time = maxf(0.0, _feedback_time - delta)
	_feedback.modulate.a = minf(_feedback_time * 2.0, 1.0)
	_damage_flash = maxf(0.0, _damage_flash - delta)
	queue_redraw()

func _draw() -> void:
	if _damage_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.07, 0.03, _damage_flash * 0.4), false, 14.0)
	if map_open:
		var map_rect := Rect2(Vector2(size.x * 0.5 - 310, 135), Vector2(620, 620))
		_draw_map(map_rect, true)
	else:
		_draw_map(Rect2(Vector2(size.x - 216, 196), Vector2(192, 192)), false)
	if reticle_visible and not map_open:
		for axis in CROSSHAIR_AXES:
			draw_line(reticle+axis*5,reticle+axis*13,Color(0.04,0.09,0.10,0.85),3.5,true)
			draw_line(reticle+axis*5,reticle+axis*13,Color.WHITE,1.25,true)
		draw_circle(reticle,1.5,Color.WHITE)

func _map_point(point: Vector3, rect: Rect2) -> Vector2:
	var normalized := Vector2(point.x, point.z) / (_world_limit * 2.0) + Vector2.ONE * 0.5
	return rect.position + Vector2.ONE * 14 + normalized * (rect.size - Vector2.ONE * 28)

func _draw_map(rect: Rect2, expanded: bool) -> void:
	draw_style_box(_map_style, rect)
	var font := get_theme_default_font()
	for path in _paths:
		for index in range(path.size() - 1):
			draw_line(_map_point(path[index], rect), _map_point(path[index + 1], rect), Color("8f8970"), 3.0 if expanded else 1.4, true)
	for landmark: Dictionary in _landmarks:
		var point := _map_point(landmark.position, rect)
		draw_circle(point, 3.0, MUTED)
		if expanded:
			draw_string(font, point + Vector2(8, -7), landmark.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CREAM)
	for item: Dictionary in _interactables:
		var point := _map_point(item.position, rect)
		var color := TEAL if _activated.has(item.id) else GOLD
		if item.kind == "delve":
			color = Color("e08a4f")
		elif item.kind == "stash":
			color = Color("b7c46f")
		elif item.kind == "portal":
			color = Color("b28be0")
		elif item.kind == "vendor":
			color = Color("e9bf76")
		if item.kind == "camp":
			draw_rect(Rect2(point - Vector2.ONE * 4, Vector2.ONE * 8), Color("d69b74"))
		else:
			draw_circle(point, 5.0 if expanded else 3.5, color)
			draw_arc(point, 8.0 if expanded else 6.0, 0, TAU, 20, color, 1.0, true)
	var player_point := _map_point(_player_position, rect)
	var direction := Vector2(-sin(_player_yaw), -cos(_player_yaw))
	var right := Vector2(-direction.y, direction.x)
	var triangle := PackedVector2Array([player_point + direction * 8, player_point - direction * 5 + right * 5, player_point - direction * 5 - right * 5])
	draw_colored_polygon(triangle, CREAM)
	draw_string(font, rect.position + Vector2(12, 20), "IRONWOOD FRONTIER  /  M TO CLOSE" if expanded else "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
	if expanded:
		draw_string(font, rect.position + Vector2(18, rect.size.y - 14), "Gold: waystone / keeper   /   Teal: restored   /   Purple: arena portal   /   Square: campfire", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)

func _panel(parent: Node, position_at: Vector2, dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = position_at
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _style(Color(0.045, 0.095, 0.12, 0.92), Color("3c5358"), 9))
	parent.add_child(panel)
	return panel

func _label(parent: Node, text: String, position_at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, position_at: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position_at
	button.custom_minimum_size = dimensions
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func _bar(parent: Node, position_at: Vector2, dimensions: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = position_at
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_font_size_override("font_size", 1)
	bar.add_theme_stylebox_override("background", _style(Color("30464b"), Color.TRANSPARENT, 3))
	bar.add_theme_stylebox_override("fill", _style(color, Color.TRANSPARENT, 3))
	parent.add_child(bar)
	bar.size = dimensions
	return bar

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style
