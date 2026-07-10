extends Control
## Root scene. UI is built in code rather than hand-authored in the .tscn —
## keeps the scene file trivial and avoids drift between layout and logic.

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
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Frontier Concord"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Four-faction sector conquest. Original setting, short sessions."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var steam_label := Label.new()
	steam_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	steam_label.modulate = Color(1, 1, 1, 0.6)
	steam_label.text = "Steam: connected" if SteamManager.is_steam_available else "Steam: offline (dev mode)"
	vbox.add_child(steam_label)

	var start_button := Button.new()
	start_button.text = "Start Campaign"
	start_button.custom_minimum_size = Vector2(220, 44)
	start_button.pressed.connect(func(): SceneRouter.goto_faction_setup())
	vbox.add_child(start_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(220, 44)
	quit_button.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_button)
