extends Control

var _selected_faction_id: StringName = &""
var _faction_buttons: Dictionary = {}
var _begin_button: Button
var _info_label: Label

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
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "勢力を選択"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var faction_row := HBoxContainer.new()
	faction_row.add_theme_constant_override("separation", 16)
	vbox.add_child(faction_row)

	var sorted_ids := GameState.faction_defs.keys()
	sorted_ids.sort()
	for fid in sorted_ids:
		var fdef: FactionDef = GameState.faction_defs[fid]
		var btn := Button.new()
		btn.text = fdef.display_name
		btn.custom_minimum_size = Vector2(200, 96)
		btn.toggle_mode = true
		btn.add_theme_color_override("font_color", fdef.color)
		btn.add_theme_color_override("font_hover_color", fdef.color)
		btn.add_theme_color_override("font_pressed_color", fdef.color)
		btn.add_theme_stylebox_override("pressed", UITheme.accent_style(fdef.color))
		if fdef.emblem:
			btn.icon = fdef.emblem
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.add_theme_constant_override("icon_max_width", 40)
		btn.pressed.connect(_on_faction_selected.bind(fid))
		faction_row.add_child(btn)
		_faction_buttons[fid] = btn

	_info_label = Label.new()
	_info_label.text = "キャンペーンで率いる勢力を選んでください。"
	_info_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_info_label)

	vbox.add_child(_spacer(8))

	_begin_button = Button.new()
	_begin_button.text = "キャンペーン開始"
	_begin_button.custom_minimum_size = Vector2(240, 46)
	_begin_button.disabled = true
	_begin_button.pressed.connect(_on_begin_pressed)
	vbox.add_child(_begin_button)

	var back_button := Button.new()
	back_button.text = "戻る"
	back_button.custom_minimum_size = Vector2(240, 40)
	back_button.pressed.connect(func(): SceneRouter.goto_main_menu())
	vbox.add_child(back_button)

func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

func _on_faction_selected(fid: StringName) -> void:
	_selected_faction_id = fid
	for other_id in _faction_buttons:
		_faction_buttons[other_id].button_pressed = other_id == fid
	var fdef: FactionDef = GameState.faction_defs[fid]
	var capital: RegionDef = GameState.region_defs[fdef.starting_region_id]
	_info_label.text = "%s を選択しました。首都: %s" % [fdef.display_name, capital.display_name]
	_begin_button.disabled = false

func _on_begin_pressed() -> void:
	if _selected_faction_id == &"":
		return
	TurnManager.start_new_game(_selected_faction_id)
	SceneRouter.goto_strategic_map()
