class_name DevelopmentPanel
extends CanvasLayer
## The faction-wide "development" command (per the original series' overall
## command menu, not a per-region build item) — advances the player's
## tech_tier, unlocking higher-tier units everywhere. Own CanvasLayer, dim
## background, centered card.

signal closed

var _faction_id: StringName
var _status_label: Label
var _research_button: Button

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

	var card := UITheme.make_card(Vector2(420, 240))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(372, 200)
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

	_research_button = Button.new()
	_research_button.custom_minimum_size = Vector2(0, 44)
	_research_button.pressed.connect(_on_research_pressed)
	vbox.add_child(_research_button)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)

	TurnManager.research_completed.connect(_on_research_completed)

	_refresh()

func _refresh() -> void:
	var faction: Faction = GameState.get_faction(_faction_id)
	var config: CampaignConfig = GameState.campaign_config
	var max_tier: int = config.research_costs.size()

	var text := "現在の開発レベル: Tier %d / %d\n" % [faction.tech_tier, max_tier]
	var orders_open := TurnManager.current_phase == TurnManager.Phase.ORDERS
	if faction.tech_tier >= max_tier:
		text += "これ以上の開発はありません。"
		_research_button.disabled = true
		_research_button.text = "開発済み"
	elif faction.research_in_progress:
		text += "次のレベルまで残り%dターン" % faction.research_turns_remaining
		_research_button.disabled = true
		_research_button.text = "開発中…"
	else:
		var cost: int = config.research_costs[faction.tech_tier]
		var turns: int = config.research_turns[faction.tech_tier]
		text += "次のレベルへの開発: コスト%d・所要%dターン" % [cost, turns]
		_research_button.disabled = not orders_open or faction.resources < cost
		_research_button.text = "開発を開始"
	_status_label.text = text

func _on_research_pressed() -> void:
	if TurnManager.start_research(_faction_id):
		_refresh()

func _on_research_completed(faction_id: StringName, _new_tier: int) -> void:
	if faction_id == _faction_id:
		_refresh()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
