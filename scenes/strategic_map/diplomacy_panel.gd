class_name DiplomacyPanel
extends CanvasLayer
## STRATEGY_DETAIL_SPECIFICATION.md section 11: treaty proposals, resource/
## tech gifting, intel purchase, and captured-unit ransom for the player
## faction. Own CanvasLayer, dim background, centered card, matching
## DevelopmentPanel/SaveLoadPanel's shared style.
## Intel purchase's third-party picker is architecturally complete but
## practically inert on the current two-faction dataset (STRATEGY_DETAIL_
## SPECIFICATION.md section 11.7 needs a third living faction to have
## anything to buy) -- it'll populate and work the moment a third faction
## exists.

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
var _ransom_rows: VBoxContainer

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

	var card := UITheme.make_card(Vector2(640, 700))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(592, 660)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "外交"
	UITheme.style_display_label(title, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(592, 360)
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	## STRATEGY_DETAIL_SPECIFICATION.md section 11.8: ransom back any of this
	## faction's own-origin units currently captured by someone else. A
	## separate section (not per-other-faction) since ransom_captured_unit
	## derives the captor automatically from the unit itself.
	var ransom_title := Label.new()
	ransom_title.text = "鹵獲機ランサム"
	ransom_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ransom_title)
	var ransom_scroll := ScrollContainer.new()
	ransom_scroll.custom_minimum_size = Vector2(592, 110)
	vbox.add_child(ransom_scroll)
	_ransom_rows = VBoxContainer.new()
	_ransom_rows.add_theme_constant_override("separation", 4)
	_ransom_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ransom_scroll.add_child(_ransom_rows)

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

	for child in _ransom_rows.get_children():
		child.queue_free()
	var captured_ids: Array[StringName] = []
	for instance_id: StringName in GameState.campaign_runtime.units_by_id.keys():
		var unit := GameState.campaign_runtime.get_unit(instance_id)
		if unit != null and unit.captured and unit.origin_faction_id == _faction_id:
			captured_ids.append(instance_id)
	captured_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	if captured_ids.is_empty():
		var none_label := Label.new()
		none_label.text = "現在鹵獲されている自軍機はありません。"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ransom_rows.add_child(none_label)
	else:
		for instance_id: StringName in captured_ids:
			_ransom_rows.add_child(_build_ransom_row(instance_id, can_act))

func _build_faction_section(other_id: StringName, can_act: bool) -> Control:
	var fdef: FactionDef = GameState.faction_defs.get(other_id)
	var player_fdef: FactionDef = GameState.faction_defs.get(_faction_id)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)

	var relation := GameState.campaign_runtime.get_relation_state(_faction_id, other_id)
	var band: int = relation.relation_band()
	var band_color := UITheme.COLOR_TEXT_DIM
	if band == GameEnums.RelationBand.FRIENDLY or band == GameEnums.RelationBand.CLOSE:
		band_color = UITheme.COLOR_GOOD
	elif band == GameEnums.RelationBand.HOSTILE or band == GameEnums.RelationBand.NEMESIS:
		band_color = UITheme.COLOR_DANGER

	# A faction crest either side of a center-out relationship gauge, in
	# place of the old plain name label -- which side the gauge's fill grows
	# toward reads at a glance, replacing the old left-aligned (-100..100)
	# ProgressBar that could only ever grow rightward regardless of sign.
	var heads_row := HBoxContainer.new()
	heads_row.add_theme_constant_override("separation", 10)
	section.add_child(heads_row)

	var self_side := HBoxContainer.new()
	self_side.add_theme_constant_override("separation", 8)
	heads_row.add_child(self_side)
	if player_fdef != null and player_fdef.emblem:
		var self_crest := FactionCrest.new()
		self_crest.setup(player_fdef, 34.0)
		self_side.add_child(self_crest)
	var self_name_label := Label.new()
	self_name_label.text = player_fdef.display_name if player_fdef != null else String(_faction_id)
	UITheme.style_display_label(self_name_label, 13)
	self_name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	self_side.add_child(self_name_label)

	var gauge := RelationGauge.new()
	gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauge.set_value(relation.friendship, band_color)
	heads_row.add_child(gauge)

	var other_side := HBoxContainer.new()
	other_side.add_theme_constant_override("separation", 8)
	heads_row.add_child(other_side)
	var name_label := Label.new()
	name_label.text = fdef.display_name if fdef != null else String(other_id)
	name_label.add_theme_color_override("font_color", fdef.color if fdef != null else UITheme.COLOR_TEXT)
	UITheme.style_display_label(name_label, 13)
	other_side.add_child(name_label)
	if fdef != null and fdef.emblem:
		var other_crest := FactionCrest.new()
		other_crest.setup(fdef, 34.0)
		other_side.add_child(other_crest)

	# Friendship value/band and treaty status each get their own line below
	# the heads row instead of sharing one sentence.
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	section.add_child(status_row)
	var friendship_label := Label.new()
	friendship_label.text = "友好度 %+d（%s）" % [relation.friendship, BAND_LABELS.get(band, "?")]
	friendship_label.add_theme_color_override("font_color", band_color)
	status_row.add_child(friendship_label)
	var treaty_spacer := Control.new()
	treaty_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(treaty_spacer)
	var treaty_label := Label.new()
	treaty_label.text = UITheme.bracket(_treaty_status_text(relation))
	UITheme.style_mono_label(treaty_label, 11)
	treaty_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD if relation.treaty_type != GameEnums.TreatyType.NONE else UITheme.COLOR_TEXT_DIM)
	status_row.add_child(treaty_label)

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
	UITheme.style_danger_button(break_button)
	actions_row.add_child(break_button)

	var gift_funds_button := Button.new()
	gift_funds_button.text = "資金贈与(%d)" % GameConstants.MIN_GIFT_FUNDS
	gift_funds_button.custom_minimum_size = Vector2(110, 36)
	var faction := GameState.get_faction(_faction_id)
	gift_funds_button.disabled = not can_act or relation.gift_cooldown_turns > 0 or faction.funds < GameConstants.MIN_GIFT_FUNDS
	gift_funds_button.pressed.connect(_on_gift_pressed.bind(other_id, GameConstants.MIN_GIFT_FUNDS, 0))
	gift_funds_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	actions_row.add_child(gift_funds_button)

	var gift_materials_button := Button.new()
	gift_materials_button.text = "物資贈与(%d)" % GameConstants.MIN_GIFT_MATERIALS
	gift_materials_button.custom_minimum_size = Vector2(110, 36)
	gift_materials_button.disabled = not can_act or relation.gift_cooldown_turns > 0 or faction.materials < GameConstants.MIN_GIFT_MATERIALS
	gift_materials_button.pressed.connect(_on_gift_pressed.bind(other_id, 0, GameConstants.MIN_GIFT_MATERIALS))
	gift_materials_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	actions_row.add_child(gift_materials_button)

	section.add_child(actions_row)

	var tech_row := HBoxContainer.new()
	tech_row.add_theme_constant_override("separation", 6)
	var other_faction := GameState.get_faction(other_id)
	var tech_picker := OptionButton.new()
	# 360 could clip this OptionButton's own item text ("Tier<N> " plus the
	# tech's name, which -- like every other untranslated *_key this session
	# found clipping -- renders as its full raw key, e.g.
	# "tech.fleet_logistics_network.name") -- widened for the same reason as
	# StrategicMap's production/fleet dropdowns and PilotAssignmentPanel's
	# unit picker.
	tech_picker.custom_minimum_size = Vector2(420, 36)
	tech_picker.clip_text = true
	# fit_to_longest_item defaults to true and overrides clip_text for this
	# button's own reported minimum size -- see StrategicMap._build_ui_overlay's
	# matching comment on _production_option for how this was found live.
	tech_picker.fit_to_longest_item = false
	for gift_node_id: StringName in _giftable_tech_nodes(faction, other_faction):
		var node := faction.generated_tech_nodes[gift_node_id] as GeneratedTechNodeState
		var tech_def: TechDef = GameState.master_data.techs.get(node.tech_id)
		tech_picker.add_item("Tier%d %s" % [node.tier, tr(String(tech_def.display_name_key)) if tech_def != null else String(node.tech_id)])
		tech_picker.set_item_metadata(tech_picker.item_count - 1, gift_node_id)
	if tech_picker.item_count == 0:
		tech_picker.add_item("(贈与可能な技術がありません)")
		tech_picker.disabled = true
	tech_row.add_child(tech_picker)

	var tech_gift_button := Button.new()
	tech_gift_button.text = "技術贈与"
	tech_gift_button.custom_minimum_size = Vector2(90, 36)
	tech_gift_button.disabled = not can_act or relation.gift_cooldown_turns > 0 or tech_picker.disabled
	tech_gift_button.pressed.connect(_on_tech_gift_pressed.bind(other_id, tech_picker))
	tech_gift_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	tech_row.add_child(tech_gift_button)

	section.add_child(tech_row)

	## STRATEGY_DETAIL_SPECIFICATION.md section 11.7: buys buyer_id's own
	## intel on every squad other_id (the "partner") has already confirmed
	## belonging to some third faction. Architecturally complete but
	## practically inert until a third living faction exists -- see this
	## class's own doc comment.
	var intel_row := HBoxContainer.new()
	intel_row.add_theme_constant_override("separation", 6)
	var third_party_picker := OptionButton.new()
	third_party_picker.custom_minimum_size = Vector2(200, 36)
	third_party_picker.clip_text = true
	third_party_picker.fit_to_longest_item = false
	var third_party_ids := GameState.factions.keys()
	third_party_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for third_id: StringName in third_party_ids:
		if third_id == _faction_id or third_id == other_id:
			continue
		var third_faction: Faction = GameState.get_faction(third_id)
		if third_faction == null or third_faction.eliminated:
			continue
		var third_fdef: FactionDef = GameState.faction_defs.get(third_id)
		third_party_picker.add_item(third_fdef.display_name if third_fdef != null else String(third_id))
		third_party_picker.set_item_metadata(third_party_picker.item_count - 1, third_id)
	if third_party_picker.item_count == 0:
		third_party_picker.add_item("(第三勢力なし)")
		third_party_picker.disabled = true
	intel_row.add_child(third_party_picker)

	var intel_button := Button.new()
	intel_button.text = "情報購入(%d)" % GameConstants.INTEL_PURCHASE_COST_FUNDS
	intel_button.custom_minimum_size = Vector2(140, 36)
	intel_button.disabled = not can_act or relation.intel_purchase_cooldown_turns > 0 \
		or third_party_picker.disabled or faction.funds < GameConstants.INTEL_PURCHASE_COST_FUNDS
	intel_button.pressed.connect(_on_intel_purchase_pressed.bind(other_id, third_party_picker))
	intel_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	intel_row.add_child(intel_button)
	section.add_child(intel_row)

	section.add_child(HSeparator.new())
	return section


## STRATEGY_DETAIL_SPECIFICATION.md section 11.8.
func _build_ransom_row(unit_instance_id: StringName, can_act: bool) -> Control:
	var unit := GameState.campaign_runtime.get_unit(unit_instance_id)
	var unit_def: UnitDef = GameState.master_data.units.get(unit.unit_def_id)
	var price := ceili(float(GameConstants.UNIT_PRODUCTION_FUNDS[unit_def.size]) * GameConstants.RANSOM_PRICE_PCT) if unit_def != null else 0
	var captor_fdef: FactionDef = GameState.faction_defs.get(unit.owner_faction_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.custom_minimum_size = Vector2(420, 0)
	var unit_name := tr(String(unit_def.display_name_key)) if unit_def != null else String(unit.unit_def_id)
	var captor_name := captor_fdef.display_name if captor_fdef != null else String(unit.owner_faction_id)
	label.text = "%s (捕獲: %s) ── 身代金 %d" % [unit_name, captor_name, price]
	row.add_child(label)

	var faction := GameState.get_faction(_faction_id)
	var button := Button.new()
	button.text = "身代金"
	button.custom_minimum_size = Vector2(90, 36)
	button.disabled = not can_act or faction == null or faction.funds < price
	button.pressed.connect(_on_ransom_pressed.bind(unit_instance_id))
	button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	row.add_child(button)

	return row

func _build_proposal_button(other_id: StringName, treaty: GameEnums.TreatyType, duration: int, can_act: bool) -> Button:
	var relation := GameState.campaign_runtime.get_relation_state(_faction_id, other_id)
	var label_prefix := "停戦" if treaty == GameEnums.TreatyType.CEASEFIRE else "不可侵"
	var rate := Diplomacy.compute_success_rate_pct(GameState, _faction_id, other_id, treaty, duration)
	var button := Button.new()
	button.text = "%s(%d週) %d%%" % [label_prefix, duration, rate]
	button.custom_minimum_size = Vector2(110, 36)
	button.disabled = not can_act or relation.treaty_type != GameEnums.TreatyType.NONE or relation.proposal_cooldown_turns > 0
	button.pressed.connect(_on_propose_pressed.bind(other_id, treaty, duration))
	button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
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

## Every researched, giftable node this faction has whose tech_id the other
## faction doesn't already hold anywhere in its own tree (STRATEGY_DETAIL_
## SPECIFICATION.md section 11.6: "同じ技術を同じ勢力へ複数回贈与できない").
func _giftable_tech_nodes(faction: Faction, other_faction: Faction) -> Array[StringName]:
	var result: Array[StringName] = []
	if faction == null or other_faction == null:
		return result
	var other_tech_ids := {}
	for other_node_id: Variant in other_faction.generated_tech_nodes:
		other_tech_ids[(other_faction.generated_tech_nodes[other_node_id] as GeneratedTechNodeState).tech_id] = true
	var node_ids := faction.generated_tech_nodes.keys()
	node_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for node_id: StringName in node_ids:
		var node := faction.generated_tech_nodes[node_id] as GeneratedTechNodeState
		if not node.researched or other_tech_ids.has(node.tech_id):
			continue
		var tech_def: TechDef = GameState.master_data.techs.get(node.tech_id)
		if tech_def != null and tech_def.giftable:
			result.append(node_id)
	return result

func _on_tech_gift_pressed(other_id: StringName, picker: OptionButton) -> void:
	if picker.item_count == 0 or picker.disabled or picker.selected < 0:
		return
	var giver_node_id := StringName(picker.get_item_metadata(picker.selected))
	var errors := Diplomacy.gift_tech(GameState, _faction_id, other_id, giver_node_id)
	_refresh()
	if not errors.is_empty():
		_status_label.text = "技術贈与に失敗しました: %s" % errors[0]
	else:
		_status_label.text = "技術を贈与しました。"

func _on_intel_purchase_pressed(partner_id: StringName, picker: OptionButton) -> void:
	if picker.item_count == 0 or picker.disabled or picker.selected < 0:
		return
	var third_party_id := StringName(picker.get_item_metadata(picker.selected))
	var result := Diplomacy.purchase_intel(GameState, _faction_id, partner_id, third_party_id)
	_refresh()
	var errors := result.errors as PackedStringArray
	if not errors.is_empty():
		_status_label.text = "情報購入に失敗しました: %s" % errors[0]
	else:
		_status_label.text = "情報を購入しました。(確認した部隊数: %d)" % (result.confirmed_squad_ids as Array).size()

func _on_ransom_pressed(unit_instance_id: StringName) -> void:
	var errors := Diplomacy.ransom_captured_unit(GameState, unit_instance_id)
	_refresh()
	if not errors.is_empty():
		_status_label.text = "身代金の支払いに失敗しました: %s" % errors[0]
	else:
		_status_label.text = "機体を取り戻しました。"

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
