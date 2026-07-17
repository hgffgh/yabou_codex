class_name PilotAssignmentPanel
extends CanvasLayer
## STRATEGY_DETAIL_SPECIFICATION.md section 5 pilot roster / DATA_DEFINITION.md
## PilotState: player-facing UI for CampaignRuntimeState.assign_pilot_to_unit
## and unassign_pilot, which previously existed only as tested backend logic
## invoked by GameState's transitional deterministic seeding. Own
## CanvasLayer, dim background, centered card, matching the other panels'
## shared style.

signal closed

var _faction_id: StringName
var _status_label: Label
var _rows: VBoxContainer

func setup(faction_id: StringName) -> void:
	_faction_id = faction_id
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

	var card := UITheme.make_card(Vector2(700, 560))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(652, 520)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "パイロット編成"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(652, 420)
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)

	_refresh()

func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()

	var can_act := TurnManager.current_phase == TurnManager.Phase.ORDERS \
		and TurnManager.active_faction_id == _faction_id and not TurnManager.is_resolving_turn
	_status_label.text = "" if can_act else "編成変更は自勢力の命令フェイズ中のみ可能です。"

	var pilot_ids := GameState.campaign_runtime.pilots_by_id.keys()
	pilot_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for pilot_id: StringName in pilot_ids:
		var pilot: PilotState = GameState.campaign_runtime.get_pilot(pilot_id)
		if pilot == null or pilot.owner_faction_id != _faction_id:
			continue
		_rows.add_child(_build_pilot_row(pilot, can_act))

func _build_pilot_row(pilot: PilotState, can_act: bool) -> Control:
	var pilot_def: PilotDef = GameState.master_data.pilots.get(pilot.pilot_id)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)

	var next_req := GameConstants.pilot_exp_to_next_level(pilot.level)
	var exp_text := "EXP %d/%d" % [pilot.current_exp, next_req] if next_req > 0 else "EXP上限"
	var injury_text := " / 負傷中(残り%dターン)" % pilot.injury_turns_remaining if pilot.is_injured() else ""
	var header := Label.new()
	header.text = "%s ── Lv%d (%s)%s / %s" % [
		tr(String(pilot_def.display_name_key)) if pilot_def != null else String(pilot.pilot_id),
		pilot.level, exp_text, injury_text, _assignment_text(pilot),
	]
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	section.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(360, 36)
	var eligible := _eligible_units(pilot)
	var selected_index := -1
	for i in range(eligible.size()):
		var entry: Dictionary = eligible[i]
		picker.add_item(entry.label)
		picker.set_item_metadata(i, entry.unit_id)
		if entry.unit_id == pilot.assigned_unit_instance_id:
			selected_index = i
	if picker.item_count == 0:
		picker.add_item("(搭乗可能な機体がありません)")
		picker.disabled = true
	elif selected_index >= 0:
		picker.selected = selected_index
	row.add_child(picker)

	var assign_button := Button.new()
	assign_button.text = "搭乗"
	assign_button.custom_minimum_size = Vector2(70, 36)
	assign_button.disabled = not can_act or pilot.is_injured() or picker.item_count == 0 or picker.disabled
	assign_button.pressed.connect(_on_assign_pressed.bind(pilot.pilot_id, picker))
	row.add_child(assign_button)

	var unassign_button := Button.new()
	unassign_button.text = "解除"
	unassign_button.custom_minimum_size = Vector2(70, 36)
	unassign_button.disabled = not can_act or not pilot.is_assigned()
	unassign_button.pressed.connect(_on_unassign_pressed.bind(pilot.pilot_id))
	row.add_child(unassign_button)

	section.add_child(row)
	section.add_child(HSeparator.new())
	return section

func _assignment_text(pilot: PilotState) -> String:
	if not pilot.is_assigned():
		return "未搭乗"
	var unit: UnitInstanceState = GameState.campaign_runtime.get_unit(pilot.assigned_unit_instance_id)
	if unit == null:
		return "未搭乗"
	return "搭乗中: %s [%s]" % [_unit_label(unit), _unit_location_text(unit)]

## Active units the player owns, regardless of current occupant -- selecting
## an already-piloted unit is a valid, informed choice (assign_pilot_to_unit
## silently displaces whoever's currently aboard), so each entry's label
## names the current occupant rather than hiding occupied units.
func _eligible_units(pilot: PilotState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var unit_ids := GameState.campaign_runtime.units_by_id.keys()
	unit_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for unit_id: StringName in unit_ids:
		var unit: UnitInstanceState = GameState.campaign_runtime.get_unit(unit_id)
		if unit == null or unit.owner_faction_id != _faction_id or unit.condition != GameEnums.UnitCondition.ACTIVE:
			continue
		var occupant := "未搭乗"
		if unit.pilot_id == pilot.pilot_id:
			occupant = "現在搭乗中"
		elif not unit.pilot_id.is_empty():
			var other_def: PilotDef = GameState.master_data.pilots.get(unit.pilot_id)
			occupant = tr(String(other_def.display_name_key)) if other_def != null else String(unit.pilot_id)
		result.append({
			"unit_id": unit_id,
			"label": "%s [%s] 搭乗:%s" % [_unit_label(unit), _unit_location_text(unit), occupant],
		})
	return result

func _unit_label(unit: UnitInstanceState) -> String:
	var unit_def: UnitDef = GameState.master_data.units.get(unit.unit_def_id)
	return tr(String(unit_def.display_name_key)) if unit_def != null else String(unit.unit_def_id)

func _unit_location_text(unit: UnitInstanceState) -> String:
	var squad: SquadState = GameState.campaign_runtime.get_squad(unit.squad_id)
	if squad == null:
		return "未編成"
	var region_def: RegionDef = GameState.region_defs.get(squad.region_id)
	return region_def.display_name if region_def != null else String(squad.region_id)

## _refresh() itself sets _status_label to either "" or the phase-gating
## hint, so the action-result message below must be applied *after* it --
## setting it first would just get immediately clobbered.
func _on_assign_pressed(pilot_id: StringName, picker: OptionButton) -> void:
	if picker.item_count == 0 or picker.disabled or picker.selected < 0:
		return
	var unit_id := StringName(picker.get_item_metadata(picker.selected))
	var errors := GameState.campaign_runtime.assign_pilot_to_unit(pilot_id, unit_id)
	_refresh()
	_status_label.text = "搭乗に失敗しました: %s" % errors[0] if not errors.is_empty() else "搭乗しました。"

func _on_unassign_pressed(pilot_id: StringName) -> void:
	var errors := GameState.campaign_runtime.unassign_pilot(pilot_id)
	_refresh()
	_status_label.text = "解除に失敗しました: %s" % errors[0] if not errors.is_empty() else "解除しました。"

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
