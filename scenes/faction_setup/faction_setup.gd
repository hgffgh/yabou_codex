extends Control

var _selected_faction_id: StringName = &""
var _faction_buttons: Dictionary = {}
var _begin_button: Button
var _info_label: Label

func _ready() -> void:
	UIUtils.fill_parent(self)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.14)
	add_child(bg)
	UIUtils.fill_parent(bg)

	var margin := MarginContainer.new()
	add_child(margin)
	UIUtils.fill_parent(margin)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 40)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Choose Your Faction"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var faction_row := HBoxContainer.new()
	faction_row.add_theme_constant_override("separation", 12)
	vbox.add_child(faction_row)

	var sorted_ids := GameState.faction_defs.keys()
	sorted_ids.sort()
	for fid in sorted_ids:
		var fdef: FactionDef = GameState.faction_defs[fid]
		var btn := Button.new()
		btn.text = fdef.display_name
		btn.custom_minimum_size = Vector2(180, 60)
		btn.toggle_mode = true
		btn.add_theme_color_override("font_color", fdef.color)
		btn.pressed.connect(_on_faction_selected.bind(fid))
		faction_row.add_child(btn)
		_faction_buttons[fid] = btn

	_info_label = Label.new()
	_info_label.text = "Select a faction to lead into the campaign."
	vbox.add_child(_info_label)

	_begin_button = Button.new()
	_begin_button.text = "Begin Campaign"
	_begin_button.custom_minimum_size = Vector2(220, 44)
	_begin_button.disabled = true
	_begin_button.pressed.connect(_on_begin_pressed)
	vbox.add_child(_begin_button)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(func(): SceneRouter.goto_main_menu())
	vbox.add_child(back_button)

func _on_faction_selected(fid: StringName) -> void:
	_selected_faction_id = fid
	for other_id in _faction_buttons:
		_faction_buttons[other_id].button_pressed = other_id == fid
	var fdef: FactionDef = GameState.faction_defs[fid]
	var capital: RegionDef = GameState.region_defs[fdef.starting_region_id]
	_info_label.text = "%s selected. Capital: %s" % [fdef.display_name, capital.display_name]
	_begin_button.disabled = false

func _on_begin_pressed() -> void:
	if _selected_faction_id == &"":
		return
	TurnManager.start_new_game(_selected_faction_id)
	SceneRouter.goto_strategic_map()
