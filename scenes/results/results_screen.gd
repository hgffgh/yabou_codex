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
	theme = UITheme.get_theme()
	UIUtils.fill_parent(self)

	var bg := ColorRect.new()
	bg.color = UITheme.COLOR_BG
	add_child(bg)
	UIUtils.fill_parent(bg)

	var center := CenterContainer.new()
	add_child(center)
	UIUtils.fill_parent(center)

	var card_width := 560.0
	var standings := _build_standings()
	var unlocked_ids: Array[StringName] = GameState.last_unlocked_achievement_ids
	var card_height := 220.0 + standings.size() * 44.0 + (0.0 if unlocked_ids.is_empty() else 48.0 + unlocked_ids.size() * 28.0)

	var card := UITheme.make_card(Vector2(card_width, card_height))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.position = Vector2(28, 24)
	vbox.size = Vector2(card_width - 56, card_height - 48)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "ゲーム終了"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var reason_label := Label.new()
	var reason_text: String = REASON_TEXT.get(GameState.last_game_over_reason, GameState.last_game_over_reason)
	reason_label.text = "%s（ターン %d / %d）" % [reason_text, GameState.turn_number, GameState.campaign_config.turn_cap]
	reason_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(reason_label)

	vbox.add_child(HSeparator.new())

	if standings.is_empty():
		var none_label := Label.new()
		none_label.text = "生存している勢力はありません。"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(none_label)
	else:
		for i in range(standings.size()):
			vbox.add_child(_build_row(standings[i], i + 1))

	if not unlocked_ids.is_empty():
		vbox.add_child(HSeparator.new())
		var achievements_title := Label.new()
		achievements_title.text = "実績解除"
		achievements_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(achievements_title)
		for id: StringName in unlocked_ids:
			var def: AchievementDef = GameState.master_data.achievements.get(id)
			var achievement_label := Label.new()
			achievement_label.text = "・" + (tr(String(def.display_name_key)) if def != null else String(id))
			achievement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			achievement_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
			vbox.add_child(achievement_label)

	vbox.add_child(HSeparator.new())

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)

	var play_again := Button.new()
	play_again.text = "もう一度プレイ"
	play_again.custom_minimum_size = Vector2(200, 46)
	play_again.pressed.connect(func(): SceneRouter.goto_faction_setup())
	UITheme.style_primary_button(play_again)
	button_row.add_child(play_again)

	var main_menu_button := Button.new()
	main_menu_button.text = "メインメニュー"
	main_menu_button.custom_minimum_size = Vector2(200, 46)
	main_menu_button.pressed.connect(func(): SceneRouter.goto_main_menu())
	main_menu_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CANCEL))
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

func _build_row(entry: Dictionary, rank: int) -> Control:
	var fdef: FactionDef = GameState.faction_defs[entry["faction_id"]]
	var is_player: bool = entry["faction_id"] == GameState.player_faction_id

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(0, 36)

	if is_player:
		var highlight := Panel.new()
		highlight.add_theme_stylebox_override("panel", UITheme.accent_style(fdef.color, 6))
		wrapper.add_child(highlight)
		UIUtils.fill_parent(highlight)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	wrapper.add_child(row)
	UIUtils.fill_parent(row)

	var rank_label := Label.new()
	rank_label.text = "%d位" % rank
	rank_label.custom_minimum_size = Vector2(46, 0)
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(rank_label)

	var swatch_center := CenterContainer.new()
	swatch_center.custom_minimum_size = Vector2(28, 0)
	if fdef.emblem:
		var emblem := TextureRect.new()
		emblem.custom_minimum_size = Vector2(24, 24)
		emblem.texture = fdef.emblem
		# Without this, TextureRect's own minimum size (from the 128x128
		# source SVG) wins over custom_minimum_size and blows up the row.
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		swatch_center.add_child(emblem)
	else:
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.add_theme_stylebox_override("panel", UITheme.accent_style(fdef.color, 4))
		swatch_center.add_child(swatch)
	row.add_child(swatch_center)

	var name_label := Label.new()
	name_label.text = fdef.display_name + ("（あなた）" if is_player else "")
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(280, 0)
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.text = "スコア %d" % int(entry["score"])
	score_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(score_label)

	return wrapper
