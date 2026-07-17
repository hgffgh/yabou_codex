class_name EncyclopediaPanel
extends CanvasLayer
## DATA_DEFINITION.md section 24: browses ProfileState.encyclopedia_unit_ids/
## encyclopedia_weapon_ids/encyclopedia_pilot_ids, grown by GameState.
## register_encyclopedia_for_squad. Every UnitDef/WeaponDef/PilotDef in the
## master data is listed; an unregistered entry shows as "未確認" with its
## details hidden. Read-only (no actions), so it's simpler than the other
## overlay panels: no _status_label, no can_act gating.

signal closed

func setup() -> void:
	layer = 9

	var root := Control.new()
	root.theme = UITheme.get_theme()
	add_child(root)
	UIUtils.fill_parent(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	UIUtils.fill_parent(dim)

	var center := CenterContainer.new()
	root.add_child(center)
	UIUtils.fill_parent(center)

	var card := UITheme.make_card(Vector2(640, 640))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(592, 600)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "図鑑"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var summary := Label.new()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.text = "機体 %d/%d ・ 武器 %d/%d ・ パイロット %d/%d" % [
		GameState.profile.encyclopedia_unit_ids.size(), GameState.master_data.units.size(),
		GameState.profile.encyclopedia_weapon_ids.size(), GameState.master_data.weapons.size(),
		GameState.profile.encyclopedia_pilot_ids.size(), GameState.master_data.pilots.size(),
	]
	vbox.add_child(summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(592, 500)
	vbox.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	rows.add_child(_section_header("機体"))
	for id: StringName in _sorted_keys(GameState.master_data.units):
		rows.add_child(_build_unit_row(id))
	rows.add_child(_section_header("武器"))
	for id: StringName in _sorted_keys(GameState.master_data.weapons):
		rows.add_child(_build_weapon_row(id))
	rows.add_child(_section_header("パイロット"))
	for id: StringName in _sorted_keys(GameState.master_data.pilots):
		rows.add_child(_build_pilot_row(id))

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)

func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label

func _build_unit_row(id: StringName) -> Label:
	var label := Label.new()
	if not GameState.profile.encyclopedia_unit_ids.has(id):
		label.text = "？？？ (未確認)"
		return label
	var def: UnitDef = GameState.master_data.units[id]
	var fdef: FactionDef = GameState.faction_defs.get(def.faction_origin_id)
	label.text = "%s ── %s ／ HP%d EN%d 火力%d 装甲%d" % [
		tr(String(def.display_name_key)), fdef.display_name if fdef != null else String(def.faction_origin_id),
		def.max_hp, def.max_en, def.firepower, def.armor,
	]
	return label

func _build_weapon_row(id: StringName) -> Label:
	var label := Label.new()
	if not GameState.profile.encyclopedia_weapon_ids.has(id):
		label.text = "？？？ (未確認)"
		return label
	var def: WeaponDef = GameState.master_data.weapons[id]
	label.text = "%s ── 威力%d 命中%d%% 射程%d-%dm" % [
		tr(String(def.display_name_key)), def.total_power, def.base_accuracy_pct, int(def.min_range_m), int(def.max_range_m),
	]
	return label

func _build_pilot_row(id: StringName) -> Label:
	var label := Label.new()
	if not GameState.profile.encyclopedia_pilot_ids.has(id):
		label.text = "？？？ (未確認)"
		return label
	var def: PilotDef = GameState.master_data.pilots[id]
	var fdef: FactionDef = GameState.faction_defs.get(def.faction_id)
	label.text = "%s ── %s ／ 初期レベル%d" % [
		tr(String(def.display_name_key)), fdef.display_name if fdef != null else String(def.faction_id), def.initial_level,
	]
	return label

func _sorted_keys(entries: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: Variant in entries:
		ids.append(StringName(id))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
