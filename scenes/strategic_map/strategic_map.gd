extends Node2D
## StrategicMap: M1 (static map, pan/zoom camera, region info panel) and
## M2 (turn-phase UI, per-region production/move orders) combined, since
## the order UI is what actually exercises the map interactively.

var _region_views: Dictionary = {}  # StringName -> RegionNodeView
var _selected_region_id: StringName = &""

var _camera: Camera2D
var _turn_label: Label
var _phase_label: Label
var _region_name_label: Label
var _region_owner_label: Label
var _region_yield_label: Label
var _production_option: OptionButton
var _produce_button: Button
var _move_option: OptionButton
var _move_button: Button
var _log_label: Label

var _zoom_level: float = 1.0
var _dragging: bool = false
var _drag_start_mouse: Vector2
var _drag_start_cam: Vector2

func _ready() -> void:
	_build_camera()
	_build_regions_and_lines()
	_build_ui_overlay()

	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.battle_ready_for_vignette.connect(_on_battle_ready_for_vignette)
	TurnManager.turn_events_ready.connect(_on_turn_events_ready)
	GameState.turn_advanced.connect(_on_turn_advanced)
	GameState.region_ownership_changed.connect(_on_region_ownership_changed)
	GameState.game_over.connect(_on_game_over)

	_update_turn_ui()
	_update_info_panel()

# ---------------- Camera ----------------

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.enabled = true
	add_child(_camera)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_level = clamp(_zoom_level * 0.9, 0.4, 2.5)
			_camera.zoom = Vector2(_zoom_level, _zoom_level)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_level = clamp(_zoom_level * 1.1, 0.4, 2.5)
			_camera.zoom = Vector2(_zoom_level, _zoom_level)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			_drag_start_mouse = get_viewport().get_mouse_position()
			_drag_start_cam = _camera.position
	elif event is InputEventMouseMotion and _dragging:
		var delta := get_viewport().get_mouse_position() - _drag_start_mouse
		_camera.position = _drag_start_cam - delta * _zoom_level

# ---------------- Map construction ----------------

func _build_regions_and_lines() -> void:
	var lines_node := Node2D.new()
	lines_node.z_index = -1
	add_child(lines_node)

	var drawn_pairs := {}
	for region_id in GameState.regions:
		var region: Region = GameState.regions[region_id]
		for neighbor_id in region.def.neighbor_ids:
			var pair_key := _pair_key(region_id, neighbor_id)
			if drawn_pairs.has(pair_key):
				continue
			drawn_pairs[pair_key] = true
			var neighbor: Region = GameState.get_region(neighbor_id)
			if neighbor == null:
				continue
			var line := Line2D.new()
			line.add_point(region.def.map_position)
			line.add_point(neighbor.def.map_position)
			line.width = 2.0
			line.default_color = Color(1, 1, 1, 0.25)
			lines_node.add_child(line)

	for region_id in GameState.regions:
		var region: Region = GameState.regions[region_id]
		var view := RegionNodeView.new()
		view.setup(region_id, region, _color_for_owner(region.owner_faction_id))
		view.region_clicked.connect(_on_region_clicked)
		add_child(view)
		_region_views[region_id] = view

func _pair_key(a: StringName, b: StringName) -> String:
	var arr := [String(a), String(b)]
	arr.sort()
	return arr[0] + "|" + arr[1]

func _color_for_owner(faction_id: StringName) -> Color:
	if faction_id == &"":
		return Color(0.5, 0.5, 0.5)
	var fdef: FactionDef = GameState.faction_defs.get(faction_id)
	return fdef.color if fdef else Color.GRAY

func _refresh_all_region_colors() -> void:
	for region_id in _region_views:
		var region: Region = GameState.regions[region_id]
		_region_views[region_id].set_owner_color(_color_for_owner(region.owner_faction_id))

func _refresh_all_region_badges() -> void:
	for region_id in _region_views:
		_region_views[region_id].update_unit_badge()

func _on_region_ownership_changed(region_id: StringName, _old, _new) -> void:
	if _region_views.has(region_id):
		_region_views[region_id].set_owner_color(_color_for_owner(GameState.get_region(region_id).owner_faction_id))

func _on_region_clicked(region_id: StringName) -> void:
	if _selected_region_id != &"" and _region_views.has(_selected_region_id):
		_region_views[_selected_region_id].set_selected(false)
	_selected_region_id = region_id
	_region_views[region_id].set_selected(true)
	_update_info_panel()

# ---------------- UI overlay ----------------

func _build_ui_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	UIUtils.fill_parent(root)

	# Panel (not PanelContainer/ColorRect) so nothing auto-resizes these to
	# fit their children and they still get the theme's rounded-corner card
	# look — see UITheme.make_card for why Panel specifically.
	var top_bar_card := UITheme.make_card(Vector2(560, 56))
	top_bar_card.position = Vector2(20, 20)
	root.add_child(top_bar_card)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 20)
	top_bar.position = Vector2(16, 8)
	top_bar.size = Vector2(528, 40)
	top_bar_card.add_child(top_bar)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 20)
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(_turn_label)

	_phase_label = Label.new()
	_phase_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(_phase_label)

	var end_turn_button := Button.new()
	end_turn_button.text = "ターン終了"
	end_turn_button.custom_minimum_size = Vector2(120, 40)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	top_bar.add_child(end_turn_button)

	var menu_button := Button.new()
	menu_button.text = "メインメニュー"
	menu_button.custom_minimum_size = Vector2(120, 40)
	menu_button.pressed.connect(func(): SceneRouter.goto_main_menu())
	top_bar.add_child(menu_button)

	var panel_width := 320.0
	var panel_height := 440.0
	var side_panel := UITheme.make_card(Vector2(panel_width, panel_height))
	side_panel.position = Vector2(get_viewport_rect().size.x - panel_width - 20, 20)
	root.add_child(side_panel)

	var info_panel := VBoxContainer.new()
	info_panel.add_theme_constant_override("separation", 10)
	info_panel.position = Vector2(18, 18)
	info_panel.size = Vector2(panel_width - 36, panel_height - 36)
	side_panel.add_child(info_panel)

	_region_name_label = Label.new()
	_region_name_label.add_theme_font_size_override("font_size", 20)
	info_panel.add_child(_region_name_label)

	_region_owner_label = Label.new()
	_region_owner_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	info_panel.add_child(_region_owner_label)

	_region_yield_label = Label.new()
	_region_yield_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	info_panel.add_child(_region_yield_label)

	info_panel.add_child(HSeparator.new())

	var produce_label := Label.new()
	produce_label.text = "生産:"
	produce_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	info_panel.add_child(produce_label)

	_production_option = OptionButton.new()
	info_panel.add_child(_production_option)

	_produce_button = Button.new()
	_produce_button.text = "生産を予約"
	_produce_button.pressed.connect(_on_produce_pressed)
	info_panel.add_child(_produce_button)

	info_panel.add_child(HSeparator.new())

	var move_label := Label.new()
	move_label.text = "艦隊派遣先:"
	move_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	info_panel.add_child(move_label)

	_move_option = OptionButton.new()
	info_panel.add_child(_move_option)

	_move_button = Button.new()
	_move_button.text = "移動命令"
	_move_button.pressed.connect(_on_move_pressed)
	info_panel.add_child(_move_button)

	info_panel.add_child(HSeparator.new())
	_log_label = Label.new()
	_log_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_log_label.custom_minimum_size = Vector2(280, 0)
	info_panel.add_child(_log_label)

func _update_info_panel() -> void:
	if _selected_region_id == &"":
		_region_name_label.text = "領域が選択されていません"
		_region_owner_label.text = ""
		_region_yield_label.text = ""
		_production_option.disabled = true
		_produce_button.disabled = true
		_move_option.disabled = true
		_move_button.disabled = true
		return

	var region: Region = GameState.regions[_selected_region_id]
	_region_name_label.text = region.def.display_name
	var owner_name := "未占領"
	if region.owner_faction_id != &"":
		owner_name = GameState.faction_defs[region.owner_faction_id].display_name
	_region_owner_label.text = "所有: %s" % owner_name
	_region_yield_label.text = "産出: %d/ターン  ｜  防御: +%d" % [region.def.resource_yield, region.def.defense_terrain_bonus]

	var is_player_owned := region.owner_faction_id == GameState.player_faction_id
	var orders_open := TurnManager.current_phase == TurnManager.Phase.ORDERS

	_production_option.clear()
	for uid in GameState.unit_defs:
		var udef: UnitType = GameState.unit_defs[uid]
		if udef.tech_tier_required > 0:
			continue
		_production_option.add_item("%s (%d)" % [udef.display_name, udef.build_cost])
		_production_option.set_item_metadata(_production_option.item_count - 1, uid)
	var can_produce := is_player_owned and orders_open and region.pending_production.is_empty()
	_production_option.disabled = not can_produce
	_produce_button.disabled = not can_produce

	_move_option.clear()
	for neighbor_id in region.def.neighbor_ids:
		var ndef: RegionDef = GameState.region_defs[neighbor_id]
		_move_option.add_item(ndef.display_name)
		_move_option.set_item_metadata(_move_option.item_count - 1, neighbor_id)
	var has_player_units: bool = region.stacks.has(GameState.player_faction_id) and not region.stacks[GameState.player_faction_id].is_empty()
	var can_move: bool = is_player_owned and orders_open and has_player_units
	_move_option.disabled = not can_move
	_move_button.disabled = not can_move

func _on_produce_pressed() -> void:
	if _selected_region_id == &"":
		return
	var region: Region = GameState.regions[_selected_region_id]
	if not region.pending_production.is_empty():
		_append_log("この領域は既に生産を予約しています。")
		return
	var idx := _production_option.selected
	if idx < 0:
		return
	var unit_id: StringName = _production_option.get_item_metadata(idx)
	var udef: UnitType = GameState.unit_defs[unit_id]
	var faction: Faction = GameState.get_faction(GameState.player_faction_id)
	if faction.resources < udef.build_cost:
		_append_log("%s を生産する資源が足りません。" % udef.display_name)
		return
	faction.resources -= udef.build_cost
	region.pending_production.append({"unit_type_id": unit_id, "turns_remaining": udef.build_time_turns})
	_append_log("%s で %s の生産を予約しました。" % [region.def.display_name, udef.display_name])
	_update_info_panel()
	_update_turn_ui()

func _on_move_pressed() -> void:
	if _selected_region_id == &"":
		return
	var region: Region = GameState.regions[_selected_region_id]
	var idx := _move_option.selected
	if idx < 0:
		return
	var dest_id: StringName = _move_option.get_item_metadata(idx)
	region.pending_move_order = dest_id
	_append_log("%s の艦隊に %s への移動を命令しました。" % [region.def.display_name, GameState.region_defs[dest_id].display_name])

func _on_end_turn_pressed() -> void:
	if GameState.is_game_over:
		return
	TurnManager.commit_turn()

func _on_battle_ready_for_vignette(entry: Dictionary) -> void:
	var vignette := BattleVignette.new()
	add_child(vignette)
	vignette.setup(entry)
	vignette.dismissed.connect(func(): TurnManager.vignette_dismissed.emit())

func _on_turn_events_ready(summary: String) -> void:
	if not summary.is_empty():
		_append_log(summary)

func _on_phase_changed(_phase) -> void:
	_update_turn_ui()
	_update_info_panel()

func _on_turn_advanced(_turn_number: int) -> void:
	_update_turn_ui()
	_refresh_all_region_colors()

func _update_turn_ui() -> void:
	_turn_label.text = "ターン %d / %d" % [GameState.turn_number, GameState.campaign_config.turn_cap]
	var phase_names := ["収入", "命令", "移動", "戦闘", "外交", "勝利判定"]
	var text := "フェーズ: %s" % phase_names[TurnManager.current_phase]
	var faction: Faction = GameState.get_faction(GameState.player_faction_id)
	if faction:
		text += "  ｜  資源: %d" % faction.resources
	_phase_label.text = text
	_refresh_all_region_badges()

func _append_log(text: String) -> void:
	_log_label.text = text

func _on_game_over(_reason: String, _standings: Array) -> void:
	SceneRouter.goto_results()
