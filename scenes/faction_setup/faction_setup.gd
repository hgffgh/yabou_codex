extends Control

var _selected_faction_id: StringName = &""
var _selected_difficulty_id: StringName = &"normal"
var _faction_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
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

	var difficulty_title := Label.new()
	difficulty_title.text = "難易度"
	difficulty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(difficulty_title)

	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 10)
	difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(difficulty_row)

	var difficulty_labels := {&"easy": "イージー", &"normal": "ノーマル", &"hard": "ハード"}
	var difficulty_ids := GameState.master_data.difficulties.keys()
	difficulty_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for did in difficulty_ids:
		var dbtn := Button.new()
		dbtn.text = difficulty_labels.get(did, String(did))
		dbtn.custom_minimum_size = Vector2(110, 44)
		dbtn.toggle_mode = true
		dbtn.button_pressed = did == _selected_difficulty_id
		dbtn.pressed.connect(_on_difficulty_selected.bind(did))
		difficulty_row.add_child(dbtn)
		_difficulty_buttons[did] = dbtn

	vbox.add_child(_spacer(8))

	_begin_button = Button.new()
	_begin_button.text = "キャンペーン開始"
	_begin_button.custom_minimum_size = Vector2(240, 46)
	_begin_button.disabled = true
	_begin_button.pressed.connect(_on_begin_pressed)
	UITheme.style_primary_button(_begin_button)
	vbox.add_child(_begin_button)

	var back_button := Button.new()
	back_button.text = "戻る"
	back_button.custom_minimum_size = Vector2(240, 40)
	back_button.pressed.connect(func(): SceneRouter.goto_main_menu())
	back_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CANCEL))
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

func _on_difficulty_selected(did: StringName) -> void:
	_selected_difficulty_id = did
	for other_id in _difficulty_buttons:
		_difficulty_buttons[other_id].button_pressed = other_id == did

func _on_begin_pressed() -> void:
	if _selected_faction_id == &"":
		return
	TurnManager.start_new_game(_selected_faction_id, _selected_difficulty_id)
	SceneRouter.goto_strategic_map()
