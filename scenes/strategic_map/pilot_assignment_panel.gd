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
	UITheme.style_display_label(title, 24)
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
	close_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CANCEL))
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
	var progress := float(pilot.current_exp) / float(next_req) if next_req > 0 else 1.0
	var owner_fdef: FactionDef = GameState.faction_defs.get(pilot.owner_faction_id)
	var ring_color := UITheme.COLOR_DANGER if pilot.is_injured() \
		else (owner_fdef.color if owner_fdef != null else UITheme.COLOR_GOLD)

	# A radial EXP gauge (level centered inside) replaces the old separate
	# "Lv%d" label + linear ProgressBar + "EXP N/M" label -- how close to
	# leveling up and what level now read from one glyph. It also doubles as
	# the injury indicator: the ring itself turns COLOR_DANGER instead of
	# needing a second colored label to say the same thing.
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	section.add_child(top_row)

	var ring := ExpRing.new()
	ring.custom_minimum_size = Vector2(56, 56)
	ring.setup(pilot.level, progress, ring_color)
	top_row.add_child(ring)

	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 4)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(info_col)

	# A plain Control (not HBoxContainer) with plain absolute position/size on
	# both labels, NOT an HBoxContainer + SIZE_EXPAND_FILL-flagged
	# status_label -- see the matching, more detailed comment on
	# StrategicMap._build_info_row for how this was found: at this nesting
	# depth (CanvasLayer > ... > ScrollContainer > VBoxContainer rows), an
	# EXPAND-flagged Label renders fully invisible in this Godot version
	# despite every introspectable property on it reporting correct,
	# on-screen values, confirmed live against a deferred
	# get_viewport().get_texture().get_image() capture. 580 is info_col's
	# known fixed width (652 vbox - 56 ring - 16 separation, both constants
	# a few lines up).
	var name_row := Control.new()
	name_row.custom_minimum_size = Vector2(0, 24)
	info_col.add_child(name_row)
	var name_label := Label.new()
	name_label.text = tr(String(pilot_def.display_name_key)) if pilot_def != null else String(pilot.pilot_id)
	UITheme.style_display_label(name_label, 16)
	name_label.position = Vector2(0, 0)
	name_label.size = Vector2(330, 24)
	name_row.add_child(name_label)
	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_mono_label(status_label, 11)
	if pilot.is_injured():
		status_label.text = UITheme.bracket("負傷中・残り%dターン" % pilot.injury_turns_remaining)
		status_label.add_theme_color_override("font_color", UITheme.COLOR_DANGER)
	else:
		status_label.text = UITheme.bracket("出撃可能")
		status_label.add_theme_color_override("font_color", UITheme.COLOR_GOOD)
	status_label.position = Vector2(330, 0)
	status_label.size = Vector2(580.0 - 330.0, 24)
	name_row.add_child(status_label)

	var exp_label := Label.new()
	exp_label.text = "EXP %d/%d" % [pilot.current_exp, next_req] if next_req > 0 else "EXP上限"
	UITheme.style_mono_label(exp_label, 11)
	exp_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	info_col.add_child(exp_label)

	# Unlocked passive skills as chips -- STRATEGY_DETAIL_SPECIFICATION.md
	# section 5.6's skills were already readable by BattleCombatSystem but
	# never surfaced anywhere in the strategic UI before this. A skill not
	# yet reached by the pilot's current level still shows (so the player
	# can see what's coming) but stays dim instead of COLOR_GOOD.
	if pilot_def != null and not pilot_def.skill_ids.is_empty():
		var chip_row := HBoxContainer.new()
		chip_row.add_theme_constant_override("separation", 14)
		info_col.add_child(chip_row)
		for skill_id: StringName in pilot_def.skill_ids:
			var skill_def: PilotSkillDef = GameState.master_data.pilot_skills.get(skill_id)
			if skill_def == null:
				continue
			var chip := Label.new()
			chip.text = "%s（Lv%d）" % [tr(String(skill_def.display_name_key)), skill_def.unlock_level]
			UITheme.style_mono_label(chip, 10.5)
			chip.add_theme_color_override(
				"font_color",
				UITheme.COLOR_GOOD if pilot.level >= skill_def.unlock_level else UITheme.COLOR_TEXT_DIM
			)
			chip_row.add_child(chip)

	var assignment_label := Label.new()
	assignment_label.text = _assignment_text(pilot)
	assignment_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	assignment_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	section.add_child(assignment_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var picker := OptionButton.new()
	# 360 clipped this OptionButton's own item text (unit name, region, and
	# assignment status all concatenated) -- the row has ample room up to
	# ~500 (scroll width 652 minus the two 70px buttons and separation)
	# before crowding them, matching the same clipping issue and fix as
	# StrategicMap's production/fleet-dispatch dropdowns.
	picker.custom_minimum_size = Vector2(480, 36)
	picker.clip_text = true
	# fit_to_longest_item defaults to true and overrides clip_text for this
	# button's own reported minimum size -- see StrategicMap._build_ui_overlay's
	# matching, more detailed comment on _production_option for how this was
	# found (confirmed live, a windowed build screenshot showing an
	# OptionButton physically overflowing its row despite clip_text alone).
	picker.fit_to_longest_item = false
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
	assign_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	row.add_child(assign_button)

	var unassign_button := Button.new()
	unassign_button.text = "解除"
	unassign_button.custom_minimum_size = Vector2(70, 36)
	unassign_button.disabled = not can_act or not pilot.is_assigned()
	unassign_button.pressed.connect(_on_unassign_pressed.bind(pilot.pilot_id))
	unassign_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
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
