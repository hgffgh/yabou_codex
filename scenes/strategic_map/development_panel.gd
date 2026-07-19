class_name DevelopmentPanel
extends CanvasLayer
## STRATEGY_DETAIL_SPECIFICATION.md section 7: shows this faction's whole
## campaign-generated tech tree (TechTreeGenerator) and lets the player
## start researching any node whose prerequisites are already met. Own
## CanvasLayer, dim background, centered card, matching the other panels.

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

	var card := UITheme.make_card(Vector2(640, 560))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(592, 520)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "開発"
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
	_rows.add_theme_constant_override("separation", 4)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)

	TurnManager.research_completed.connect(_on_research_completed)

	_refresh()

func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()

	var faction: Faction = GameState.get_faction(_faction_id)
	var can_act := TurnManager.current_phase == TurnManager.Phase.ORDERS \
		and TurnManager.active_faction_id == _faction_id and not TurnManager.is_resolving_turn

	var researched_count := 0
	for node_id: Variant in faction.generated_tech_nodes:
		if (faction.generated_tech_nodes[node_id] as GeneratedTechNodeState).researched:
			researched_count += 1
	var total_count: int = faction.generated_tech_nodes.size()

	var status_text := "研究済み %d / %d" % [researched_count, total_count]
	if faction.current_research != null:
		var researching_node := faction.generated_tech_nodes.get(faction.current_research.node_id) as GeneratedTechNodeState
		var tech_def: TechDef = GameState.master_data.techs.get(researching_node.tech_id) if researching_node != null else null
		var tech_name := tr(String(tech_def.display_name_key)) if tech_def != null else String(faction.current_research.node_id)
		status_text += "\n研究中: %s (残り%dターン)" % [tech_name, faction.current_research.turns_remaining]
	elif not can_act:
		status_text += "\n研究開始は自勢力の命令フェイズ中のみ可能です。"
	_status_label.text = status_text

	var node_ids := faction.generated_tech_nodes.keys()
	node_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var na := faction.generated_tech_nodes[a] as GeneratedTechNodeState
		var nb := faction.generated_tech_nodes[b] as GeneratedTechNodeState
		if na.tier != nb.tier: return na.tier < nb.tier
		return String(a) < String(b))

	for node_id: StringName in node_ids:
		_rows.add_child(_build_node_row(faction, node_id, can_act))

func _build_node_row(faction: Faction, node_id: StringName, can_act: bool) -> Control:
	var node := faction.generated_tech_nodes[node_id] as GeneratedTechNodeState
	var tech_def: TechDef = GameState.master_data.techs.get(node.tech_id)
	var tech_name := tr(String(tech_def.display_name_key)) if tech_def != null else String(node.tech_id)
	var gifted_tag := "（贈与）" if node.gifted else ""
	var prereq_met := TurnManager._node_prerequisites_met(faction, node)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.custom_minimum_size = Vector2(280, 0)
	label.text = "Tier%d %s%s" % [node.tier, tech_name, gifted_tag]
	row.add_child(label)

	# A colored status word instead of folding it into the name sentence:
	# green once researched, gold while it's a real available choice, dim
	# while blocked -- the three states read apart before the text does.
	var status_label := Label.new()
	status_label.custom_minimum_size = Vector2(150, 0)
	if node.researched:
		status_label.text = "研究済み"
		status_label.add_theme_color_override("font_color", UITheme.COLOR_GOOD)
	elif prereq_met:
		var config: CampaignConfig = GameState.campaign_config
		status_label.text = "コスト%d・%dターン" % [config.research_costs[node.tier - 1], config.research_turns[node.tier - 1]]
		status_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	else:
		status_label.text = "前提未達成"
		status_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	row.add_child(status_label)

	var button := Button.new()
	button.text = "研究開始"
	button.custom_minimum_size = Vector2(90, 36)
	button.disabled = not can_act or node.researched or faction.current_research != null or not prereq_met
	button.pressed.connect(_on_research_pressed.bind(node_id))
	row.add_child(button)

	return row

## _refresh() itself sets _status_label, so the result message below must be
## applied *after* it -- setting it first would just get immediately
## clobbered (see DiplomacyPanel/PilotAssignmentPanel for the same fix).
func _on_research_pressed(node_id: StringName) -> void:
	var errors := TurnManager.start_research(_faction_id, node_id)
	_refresh()
	if not errors.is_empty():
		_status_label.text = "研究開始に失敗しました: %s\n%s" % [errors[0], _status_label.text]

func _on_research_completed(faction_id: StringName, _tech_id: StringName) -> void:
	if faction_id == _faction_id:
		_refresh()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
