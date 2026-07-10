extends Control
## Shown once TurnManager ends the game (see GameState.last_game_over_*).
## "Play Again" returns to FactionSetup rather than restarting in place —
## re-picking a faction is cheap and the campaign is short by design.

const REASON_TEXT := {
	"turn_cap": "ターン上限に到達",
	"region_threshold": "領域制圧により決着",
	"capital_capture": "首都陥落により決着",
	"player_eliminated": "あなたの本拠地が陥落しました",
}

func _ready() -> void:
	UIUtils.fill_parent(self)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.14)
	add_child(bg)
	UIUtils.fill_parent(bg)

	var center := CenterContainer.new()
	add_child(center)
	UIUtils.fill_parent(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "ゲーム終了"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var reason_label := Label.new()
	var reason_text: String = REASON_TEXT.get(GameState.last_game_over_reason, GameState.last_game_over_reason)
	reason_label.text = "%s（ターン %d / %d）" % [reason_text, GameState.turn_number, GameState.campaign_config.turn_cap]
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(reason_label)

	vbox.add_child(HSeparator.new())

	var standings := _build_standings()
	if standings.is_empty():
		var none_label := Label.new()
		none_label.text = "生存している勢力はありません。"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(none_label)
	else:
		for i in range(standings.size()):
			vbox.add_child(_build_row(standings[i], i + 1))

	vbox.add_child(HSeparator.new())

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)

	var play_again := Button.new()
	play_again.text = "もう一度プレイ"
	play_again.custom_minimum_size = Vector2(200, 44)
	play_again.pressed.connect(func(): SceneRouter.goto_faction_setup())
	button_row.add_child(play_again)

	var main_menu_button := Button.new()
	main_menu_button.text = "メインメニュー"
	main_menu_button.custom_minimum_size = Vector2(200, 44)
	main_menu_button.pressed.connect(func(): SceneRouter.goto_main_menu())
	button_row.add_child(main_menu_button)

## The turn-cap path already carries real scores; single-winner paths
## (elimination/region-threshold) pass a -1 sentinel, so recompute a full,
## sorted board from whoever's still alive at the moment the game ended.
func _build_standings() -> Array:
	var stored: Array = GameState.last_game_over_standings
	if not stored.is_empty() and int(stored[0].get("score", -1)) >= 0:
		return stored
	var result: Array = []
	for fid in GameState.alive_faction_ids():
		var faction: Faction = GameState.get_faction(fid)
		result.append({
			"faction_id": fid,
			"score": GameState.region_count_for(fid) * 10 + faction.resources,
		})
	result.sort_custom(func(a, b): return a["score"] > b["score"])
	return result

func _build_row(entry: Dictionary, rank: int) -> HBoxContainer:
	var fdef: FactionDef = GameState.faction_defs[entry["faction_id"]]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var rank_label := Label.new()
	rank_label.text = "%d位" % rank
	rank_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = fdef.display_name
	if entry["faction_id"] == GameState.player_faction_id:
		name_label.text += "（あなた）"
	name_label.add_theme_color_override("font_color", fdef.color)
	name_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.text = "スコア %d" % int(entry["score"])
	row.add_child(score_label)

	return row
