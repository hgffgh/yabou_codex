class_name BattleVignette
extends CanvasLayer
## Short, skippable presentation of a CombatResolver result that already
## happened. Two faction icons slide together and flash on impact, then the
## HP bars animate to their precomputed end state — none of this decides
## anything, it only shows what CombatResolver already computed.

signal dismissed

const OUTCOME_TEXT := {
	0: "完全勝利",  # CombatResolver.Outcome.FULL_VICTORY
	1: "辛勝",      # MARGINAL_VICTORY
	2: "膠着",      # STALEMATE
	3: "敗北",      # DEFEAT
}
const OUTCOME_COLOR := {
	0: Color(0.55, 0.85, 0.55),
	1: Color(0.78, 0.85, 0.55),
	2: Color(0.80, 0.78, 0.55),
	3: Color(0.90, 0.45, 0.45),
}

var _attacker_bar: ProgressBar
var _defender_bar: ProgressBar
var _attacker_icon: Control
var _defender_icon: Control
var _attacker_rest_pos: Vector2
var _defender_rest_pos: Vector2
var _flash: ColorRect
var _outcome_label: Label
var _skip_button: Button
var _active_tween: Tween
var _entry: Dictionary

func setup(entry: Dictionary) -> void:
	_entry = entry
	layer = 10  # above the map's own CanvasLayer (default layer 1)

	var root := Control.new()
	root.theme = UITheme.get_theme()
	add_child(root)
	UIUtils.fill_parent(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	root.add_child(dim)
	UIUtils.fill_parent(dim)

	var center := CenterContainer.new()
	root.add_child(center)
	UIUtils.fill_parent(center)

	var card := UITheme.make_card(Vector2(560, 340))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.position = Vector2(28, 22)
	vbox.size = Vector2(504, 296)
	card.add_child(vbox)

	var region_name: String = GameState.region_defs[entry["region_id"]].display_name
	var title := Label.new()
	title.text = "%s で交戦" % region_name
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var attacker_fdef: FactionDef = GameState.faction_defs[entry["attacker_id"]]
	var defender_fdef: FactionDef = GameState.faction_defs[entry["defender_id"]]

	var clash_area := Control.new()
	clash_area.custom_minimum_size = Vector2(0, 56)
	vbox.add_child(clash_area)

	_attacker_icon = _make_icon(attacker_fdef, entry.get("attacker_units", {}))
	_defender_icon = _make_icon(defender_fdef, entry.get("defender_units", {}))
	_attacker_rest_pos = Vector2(0, 4)
	_defender_rest_pos = Vector2(456, 4)
	_attacker_icon.position = _attacker_rest_pos
	_defender_icon.position = _defender_rest_pos
	clash_area.add_child(_attacker_icon)
	clash_area.add_child(_defender_icon)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.size = Vector2(48, 48)
	_flash.position = Vector2(228, 4)
	clash_area.add_child(_flash)

	_attacker_bar = _build_side_row(vbox, "攻撃: " + attacker_fdef.display_name, attacker_fdef.color)
	_defender_bar = _build_side_row(vbox, "防御: " + defender_fdef.display_name, defender_fdef.color)

	_outcome_label = Label.new()
	_outcome_label.add_theme_font_size_override("font_size", 20)
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_label.text = " "
	vbox.add_child(_outcome_label)

	var button_center := CenterContainer.new()
	vbox.add_child(button_center)
	_skip_button = Button.new()
	_skip_button.text = "続ける"
	_skip_button.custom_minimum_size = Vector2(160, 40)
	_skip_button.pressed.connect(_on_skip_pressed)
	button_center.add_child(_skip_button)

	_play_clash()

## The faction-colored circle is the "team" identity; what's drawn inside
## it is the actual unit type(s) fighting (up to 2, by count), not just the
## faction emblem — the player asked to see which units are in the fight,
## not just who owns them. Falls back to the emblem if a stack somehow has
## no composition data.
func _make_icon(fdef: FactionDef, units: Dictionary) -> Control:
	var wrapper := Control.new()
	wrapper.size = Vector2(48, 48)

	var bg := Panel.new()
	bg.size = Vector2(48, 48)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fdef.color.darkened(0.35)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(24)
	bg.add_theme_stylebox_override("panel", sb)
	wrapper.add_child(bg)

	var unit_ids := _dominant_unit_ids(units, 2)
	if unit_ids.is_empty():
		if fdef.emblem:
			_add_icon_texture(wrapper, fdef.emblem, Vector2(6, 6), Vector2(36, 36))
	elif unit_ids.size() == 1:
		var udef: UnitType = GameState.unit_defs[unit_ids[0]]
		if udef.icon:
			_add_icon_texture(wrapper, udef.icon, Vector2(6, 6), Vector2(36, 36))
	else:
		for i in range(unit_ids.size()):
			var udef: UnitType = GameState.unit_defs[unit_ids[i]]
			if udef.icon:
				_add_icon_texture(wrapper, udef.icon, Vector2(4.0 + i * 22.0, 12), Vector2(20, 20))

	return wrapper

func _dominant_unit_ids(units: Dictionary, max_count: int) -> Array:
	var ids := units.keys()
	ids.sort_custom(func(a, b): return units[a] > units[b])
	if ids.size() > max_count:
		ids = ids.slice(0, max_count)
	return ids

func _add_icon_texture(parent: Control, texture: Texture2D, pos: Vector2, size: Vector2) -> void:
	var rect := TextureRect.new()
	rect.texture = texture
	# Without this, TextureRect uses the texture's native size (our SVGs
	# are 128x128) as its minimum size and ignores .size entirely.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.position = pos
	rect.size = size
	parent.add_child(rect)

func _build_side_row(parent: VBoxContainer, label_text: String, color: Color) -> ProgressBar:
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	parent.add_child(bar)
	return bar

func _play_clash() -> void:
	var attacker_target := Vector2(204, 4)
	var defender_target := Vector2(252, 4)

	_active_tween = create_tween()
	_active_tween.tween_property(_attacker_icon, "position", attacker_target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.parallel().tween_property(_defender_icon, "position", defender_target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.tween_callback(_flash_impact)
	_active_tween.tween_interval(0.1)
	_active_tween.tween_property(_attacker_icon, "position", _attacker_rest_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.parallel().tween_property(_defender_icon, "position", _defender_rest_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_callback(_play_bars)

func _flash_impact() -> void:
	_flash.color = Color(1, 1, 1, 0.9)
	var flash_tween := create_tween()
	flash_tween.tween_property(_flash, "color:a", 0.0, 0.3)

func _play_bars() -> void:
	var attacker_before: int = max(_entry["attacker_before"], 1)
	var defender_before: int = max(_entry["defender_before"], 1)
	var attacker_fraction: float = float(_entry["attacker_after"]) / float(attacker_before)
	var defender_fraction: float = float(_entry["defender_after"]) / float(defender_before)

	_active_tween = create_tween()
	_active_tween.tween_property(_attacker_bar, "value", attacker_fraction, 1.0)
	_active_tween.parallel().tween_property(_defender_bar, "value", defender_fraction, 1.0)
	_active_tween.tween_callback(_show_outcome)

func _show_outcome() -> void:
	var outcome: int = _entry["outcome"]
	var text: String = OUTCOME_TEXT.get(outcome, "?")
	if _entry["captured"]:
		var attacker_fdef: FactionDef = GameState.faction_defs[_entry["attacker_id"]]
		text += "  ｜  %s が占領" % attacker_fdef.display_name
	_outcome_label.text = text
	_outcome_label.add_theme_color_override("font_color", OUTCOME_COLOR.get(outcome, UITheme.COLOR_TEXT))

func _snap_to_end_state() -> void:
	_attacker_icon.position = _attacker_rest_pos
	_defender_icon.position = _defender_rest_pos
	_flash.color = Color(1, 1, 1, 0.0)
	_attacker_bar.value = float(_entry["attacker_after"]) / float(max(_entry["attacker_before"], 1))
	_defender_bar.value = float(_entry["defender_after"]) / float(max(_entry["defender_before"], 1))

func _on_skip_pressed() -> void:
	if _active_tween and _active_tween.is_running():
		_active_tween.kill()
		_snap_to_end_state()
		_show_outcome()
		return
	dismissed.emit()
	queue_free()
