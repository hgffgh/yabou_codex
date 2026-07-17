class_name DiplomacyPanel
extends CanvasLayer
## STRATEGY_DETAIL_SPECIFICATION.md section 11: treaty proposals and resource
## gifting for the player faction. Intel purchase and captured-unit ransom
## are backend-only for now (see HANDOFF.md) -- intel purchase needs a third
## living faction to be meaningful, and ransom needs a captured-unit browser
## that doesn't exist yet. Own CanvasLayer, dim background, centered card,
## matching DevelopmentPanel/SaveLoadPanel's shared style.

signal closed

const BAND_LABELS := {
	GameEnums.RelationBand.NEMESIS: "宿敵",
	GameEnums.RelationBand.HOSTILE: "敵対",
	GameEnums.RelationBand.NEUTRAL: "中立",
	GameEnums.RelationBand.FRIENDLY: "友好",
	GameEnums.RelationBand.CLOSE: "親密",
}
const TREATY_LABELS := {
	GameEnums.TreatyType.NONE: "交戦中",
	GameEnums.TreatyType.CEASEFIRE: "停戦中",
	GameEnums.TreatyType.NON_AGGRESSION: "不可侵中",
}

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

	var card := UITheme.make_card(Vector2(640, 560))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(592, 520)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "外交"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(592, 420)
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
	_status_label.text = "" if can_act else "外交行動は自勢力の命令フェイズ中のみ可能です。"

	var other_ids := GameState.factions.keys()
	other_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for other_id: StringName in other_ids:
		if other_id == _faction_id:
			continue
		var other_faction: Faction = GameState.get_faction(other_id)
		if other_faction == null or other_faction.eliminated:
			continue
		_rows.add_child(_build_faction_section(other_id, can_act))

func _build_faction_section(other_id: StringName, can_act: bool) -> Control:
	var fdef: FactionDef = GameState.faction_defs.get(other_id)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)

	var relation := GameState.campaign_runtime.get_relation_state(_faction_id, other_id)
	var header := Label.new()
	header.text = "%s ── 友好度 %d (%s) / %s" % [
		fdef.display_name if fdef != null else String(other_id),
		relation.friendship, BAND_LABELS.get(relation.relation_band(), "?"),
		_treaty_status_text(relation),
	]
	section.add_child(header)

	var ceasefire_row := HBoxContainer.new()
	ceasefire_row.add_theme_constant_override("separation", 6)
	for duration: int in GameConstants.CEASEFIRE_DURATIONS:
		ceasefire_row.add_child(_build_proposal_button(other_id, GameEnums.TreatyType.CEASEFIRE, duration, can_act))
	section.add_child(ceasefire_row)

	var non_aggression_row := HBoxContainer.new()
	non_aggression_row.add_theme_constant_override("separation", 6)
	for duration: int in GameConstants.NON_AGGRESSION_DURATIONS:
		non_aggression_row.add_child(_build_proposal_button(other_id, GameEnums.TreatyType.NON_AGGRESSION, duration, can_act))
	section.add_child(non_aggression_row)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)

	var break_button := Button.new()
	break_button.text = "条約破棄"
	break_button.custom_minimum_size = Vector2(90, 36)
	break_button.disabled = not can_act or relation.treaty_type == GameEnums.TreatyType.NONE
	break_button.pressed.connect(_on_break_pressed.bind(other_id))
	actions_row.add_child(break_button)

	var gift_funds_button := Button.new()
	gift_funds_button.text = "資金贈与(%d)" % GameConstants.MIN_GIFT_FUNDS
	gift_funds_button.custom_minimum_size = Vector2(110, 36)
	var faction := GameState.get_faction(_faction_id)
	gift_funds_button.disabled = not can_act or relation.gift_cooldown_turns > 0 or faction.funds < GameConstants.MIN_GIFT_FUNDS
	gift_funds_button.pressed.connect(_on_gift_pressed.bind(other_id, GameConstants.MIN_GIFT_FUNDS, 0))
	actions_row.add_child(gift_funds_button)

	var gift_materials_button := Button.new()
	gift_materials_button.text = "物資贈与(%d)" % GameConstants.MIN_GIFT_MATERIALS
	gift_materials_button.custom_minimum_size = Vector2(110, 36)
	gift_materials_button.disabled = not can_act or relation.gift_cooldown_turns > 0 or faction.materials < GameConstants.MIN_GIFT_MATERIALS
	gift_materials_button.pressed.connect(_on_gift_pressed.bind(other_id, 0, GameConstants.MIN_GIFT_MATERIALS))
	actions_row.add_child(gift_materials_button)

	var other_faction := GameState.get_faction(other_id)
	var tech_gift_button := Button.new()
	tech_gift_button.text = "技術贈与"
	tech_gift_button.custom_minimum_size = Vector2(90, 36)
	var max_tier: int = GameState.campaign_config.research_costs.size()
	tech_gift_button.disabled = not can_act or relation.gift_cooldown_turns > 0 \
		or other_faction == null or other_faction.research_in_progress \
		or faction.tech_tier <= other_faction.tech_tier or other_faction.tech_tier >= max_tier
	tech_gift_button.pressed.connect(_on_tech_gift_pressed.bind(other_id))
	actions_row.add_child(tech_gift_button)

	section.add_child(actions_row)
	section.add_child(HSeparator.new())
	return section

func _build_proposal_button(other_id: StringName, treaty: GameEnums.TreatyType, duration: int, can_act: bool) -> Button:
	var relation := GameState.campaign_runtime.get_relation_state(_faction_id, other_id)
	var label_prefix := "停戦" if treaty == GameEnums.TreatyType.CEASEFIRE else "不可侵"
	var rate := Diplomacy.compute_success_rate_pct(GameState, _faction_id, other_id, treaty, duration)
	var button := Button.new()
	button.text = "%s(%d週) %d%%" % [label_prefix, duration, rate]
	button.custom_minimum_size = Vector2(110, 36)
	button.disabled = not can_act or relation.treaty_type != GameEnums.TreatyType.NONE or relation.proposal_cooldown_turns > 0
	button.pressed.connect(_on_propose_pressed.bind(other_id, treaty, duration))
	return button

func _treaty_status_text(relation: RelationState) -> String:
	var base_text: String = TREATY_LABELS.get(relation.treaty_type, "?")
	if relation.treaty_type != GameEnums.TreatyType.NONE:
		return "%s(残り%d週)" % [base_text, relation.treaty_turns_remaining]
	if relation.proposal_cooldown_turns > 0:
		return "%s / 提案不可(残り%d週)" % [base_text, relation.proposal_cooldown_turns]
	return base_text

## _refresh() itself sets _status_label to either "" or the phase-gating
## hint, so the action-result message below must be applied *after* it --
## setting it first would just get immediately clobbered.
func _on_propose_pressed(other_id: StringName, treaty: GameEnums.TreatyType, duration: int) -> void:
	var result := Diplomacy.propose_treaty(GameState, _faction_id, other_id, treaty, duration)
	_refresh()
	if not (result.errors as PackedStringArray).is_empty():
		_status_label.text = "提案に失敗しました: %s" % (result.errors as PackedStringArray)[0]
	elif result.success:
		_status_label.text = "条約が成立しました。(成功率%d%%)" % int(result.success_rate_pct)
	else:
		_status_label.text = "条約提案は拒否されました。(成功率%d%%)" % int(result.success_rate_pct)

func _on_break_pressed(other_id: StringName) -> void:
	var errors := Diplomacy.break_treaty(GameState, _faction_id, other_id)
	_refresh()
	if not errors.is_empty():
		_status_label.text = "条約破棄に失敗しました: %s" % errors[0]
	else:
		_status_label.text = "条約を破棄しました。"

func _on_gift_pressed(other_id: StringName, funds: int, materials: int) -> void:
	var errors := Diplomacy.gift_resources(GameState, _faction_id, other_id, funds, materials)
	_refresh()
	if not errors.is_empty():
		_status_label.text = "贈与に失敗しました: %s" % errors[0]
	else:
		_status_label.text = "贈与しました。"

func _on_tech_gift_pressed(other_id: StringName) -> void:
	var errors := Diplomacy.gift_tech(GameState, _faction_id, other_id)
	_refresh()
	if not errors.is_empty():
		_status_label.text = "技術贈与に失敗しました: %s" % errors[0]
	else:
		_status_label.text = "技術を贈与しました。"

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
