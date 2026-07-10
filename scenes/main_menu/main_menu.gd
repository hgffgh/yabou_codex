extends Control
## Root scene. UI is built in code rather than hand-authored in the .tscn —
## keeps the scene file trivial and avoids drift between layout and logic.

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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "フロンティア協約"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "四勢力による宙域制圧。オリジナル設定・短時間プレイ。"
	subtitle.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var steam_label := Label.new()
	steam_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	steam_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	steam_label.text = "Steam: 接続済み" if SteamManager.is_steam_available else "Steam: オフライン（開発モード）"
	vbox.add_child(steam_label)

	vbox.add_child(_spacer(12))

	var start_button := Button.new()
	start_button.text = "キャンペーン開始"
	start_button.custom_minimum_size = Vector2(240, 48)
	start_button.pressed.connect(func(): SceneRouter.goto_faction_setup())
	vbox.add_child(start_button)

	var quit_button := Button.new()
	quit_button.text = "終了"
	quit_button.custom_minimum_size = Vector2(240, 48)
	quit_button.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_button)

func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
