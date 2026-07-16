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
var _production_queue_label: Label
var _move_option: OptionButton
var _move_button: Button
var _log_label: Label

var _zoom_level: float = 1.0
var _dragging: bool = false
var _drag_start_mouse: Vector2
var _drag_start_cam: Vector2

const MAX_PLAYER_QUEUE_LENGTH := 5  # keep in sync with AiController.MAX_QUEUE_LENGTH's intent

func _ready() -> void:
	_build_starfield()
	_build_camera()
	_build_regions_and_lines()
	_fit_camera_to_map()
	_build_ui_overlay()

	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.battle_ready_for_vignette.connect(_on_battle_ready_for_vignette)
	TurnManager.turn_events_ready.connect(_on_turn_events_ready)
	GameState.turn_advanced.connect(_on_turn_advanced)
	GameState.region_ownership_changed.connect(_on_region_ownership_changed)
	GameState.game_over.connect(_on_game_over)

	_update_turn_ui()
	_update_info_panel()

# ---------------- Background ----------------

## Deterministic starfield (fixed seed, generated once) so the flat gray
## map background reads as "space" instead of an empty void — cheap: a
## few hundred static points drawn via the `draw` signal, no per-frame
## recomputation.
func _build_starfield() -> void:
	var stars := Node2D.new()
	stars.z_index = -20
	add_child(stars)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260710
	var points: Array = []
	for i in range(260):
		var pos := Vector2(rng.randf_range(-1400, 1400), rng.randf_range(-1000, 1000))
		var brightness := rng.randf_range(0.18, 0.85)
		var size := rng.randf_range(1.0, 2.4)
		points.append([pos, brightness, size])

	stars.draw.connect(func():
		for p in points:
			stars.draw_circle(p[0], p[2], Color(1, 1, 1, p[1]))
	)

# ---------------- Camera ----------------

const MIN_ZOOM := 0.3
const MAX_ZOOM := 2.5

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.enabled = true
	add_child(_camera)

## Fits the whole region graph in view on load, regardless of window size —
## at a fixed zoom of 1.0 the map (roughly 1100x1100 world units) simply
## doesn't fit inside Godot's default 1152x648 window, clipping regions off
## the top/right edge and behind the HUD panels. Called after regions exist.
func _fit_camera_to_map() -> void:
	if GameState.regions.is_empty():
		return
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for region in GameState.regions.values():
		var pos: Vector2 = region.def.map_position
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)

	var margin := 100.0  # region radius + label text below it
	min_pos -= Vector2(margin, margin)
	max_pos += Vector2(margin, margin)
	var map_size: Vector2 = max_pos - min_pos
	var map_center: Vector2 = (min_pos + max_pos) / 2.0

	# Reserve space for the top bar and the side panel so the fitted map
	# doesn't just avoid clipping at the raw viewport edges, but also avoids
	# rendering key regions (e.g. the far faction's capital) underneath
	# either HUD panel.
	var reserved_top := 100.0
	var reserved_right := 360.0
	var viewport_size := get_viewport_rect().size
	var safe_size := Vector2(viewport_size.x - reserved_right, viewport_size.y - reserved_top)
	var target_zoom: float = clamp(min(safe_size.x / map_size.x, safe_size.y / map_size.y), MIN_ZOOM, 1.0)

	_zoom_level = target_zoom
	_camera.zoom = Vector2(target_zoom, target_zoom)

	# Shift the camera so the map centers within that safe area rather than
	# the full screen — the camera always projects its .position to screen
	# center, so we offset away from map_center by half the reserved strips.
	var screen_center_to_safe_center := Vector2(-reserved_right / 2.0, reserved_top / 2.0)
	_camera.position = map_center - screen_center_to_safe_center / target_zoom

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_level = clamp(_zoom_level * 0.9, MIN_ZOOM, MAX_ZOOM)
			_camera.zoom = Vector2(_zoom_level, _zoom_level)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_level = clamp(_zoom_level * 1.1, MIN_ZOOM, MAX_ZOOM)
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
		view.set_player_owned(region.owner_faction_id == GameState.player_faction_id)
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
		_region_views[region_id].set_player_owned(region.owner_faction_id == GameState.player_faction_id)

func _refresh_all_region_badges() -> void:
	for region_id in _region_views:
		_region_views[region_id].update_unit_badge()

func _on_region_ownership_changed(region_id: StringName, _old, _new) -> void:
	if _region_views.has(region_id):
		var owner_id: StringName = GameState.get_region(region_id).owner_faction_id
		_region_views[region_id].set_owner_color(_color_for_owner(owner_id))
		_region_views[region_id].set_player_owned(owner_id == GameState.player_faction_id)

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
	# look — see UITheme.make_card for why Panel specifically. The card is
	# sized AFTER top_bar's children exist (via get_combined_minimum_size),
	# not guessed up front — a guessed fixed width previously ran narrower
	# than the actual Japanese label + two buttons, so "メインメニュー"
	# rendered past the card's right edge at smaller window sizes.
	var top_bar_card := UITheme.make_card(Vector2.ZERO)
	top_bar_card.position = Vector2(20, 20)
	root.add_child(top_bar_card)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 20)
	top_bar_card.add_child(top_bar)

	# Persistent "which one is me" indicator — the map's gold ownership
	# ring answers this per-region, but this answers it at a glance without
	# having to scan the map at all.
	var player_fdef: FactionDef = GameState.faction_defs[GameState.player_faction_id]
	var player_badge := HBoxContainer.new()
	player_badge.add_theme_constant_override("separation", 8)
	top_bar.add_child(player_badge)

	if player_fdef.emblem:
		var player_emblem_bg := Panel.new()
		player_emblem_bg.custom_minimum_size = Vector2(28, 28)
		var emblem_sb := StyleBoxFlat.new()
		emblem_sb.bg_color = player_fdef.color.darkened(0.35)
		emblem_sb.border_color = RegionNodeView.PLAYER_RING_COLOR
		emblem_sb.set_border_width_all(2)
		emblem_sb.set_corner_radius_all(14)
		player_emblem_bg.add_theme_stylebox_override("panel", emblem_sb)
		player_badge.add_child(player_emblem_bg)

		var player_emblem := TextureRect.new()
		player_emblem.texture = player_fdef.emblem
		player_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		player_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		player_emblem.position = Vector2(3, 3)
		player_emblem.size = Vector2(22, 22)
		player_emblem_bg.add_child(player_emblem)

	var player_name_label := Label.new()
	player_name_label.text = "あなた: %s" % player_fdef.display_name
	player_name_label.add_theme_color_override("font_color", player_fdef.color)
	player_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player_badge.add_child(player_name_label)

	top_bar.add_child(VSeparator.new())

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 20)
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(_turn_label)

	_phase_label = Label.new()
	_phase_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(_phase_label)

	var development_button := Button.new()
	development_button.text = "開発"
	development_button.custom_minimum_size = Vector2(90, 40)
	development_button.pressed.connect(_on_development_pressed)
	top_bar.add_child(development_button)

	var end_turn_button := Button.new()
	end_turn_button.text = "ターン終了"
	end_turn_button.custom_minimum_size = Vector2(120, 40)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	top_bar.add_child(end_turn_button)

	var menu_button := Button.new()
	menu_button.text = "メインメニュー"
	menu_button.custom_minimum_size = Vector2(140, 40)
	menu_button.pressed.connect(func(): SceneRouter.goto_main_menu())
	top_bar.add_child(menu_button)

	var top_bar_margin := Vector2(16, 8)
	top_bar.position = top_bar_margin
	top_bar.size = top_bar.get_combined_minimum_size()
	top_bar_card.size = top_bar.size + top_bar_margin * 2

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

	_production_queue_label = Label.new()
	_production_queue_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_production_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_production_queue_label.custom_minimum_size = Vector2(280, 0)
	info_panel.add_child(_production_queue_label)

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
		_production_queue_label.text = ""
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

	var player_faction: Faction = GameState.get_faction(GameState.player_faction_id)
	_production_option.clear()
	for uid in GameState.unit_defs:
		var udef: UnitType = GameState.unit_defs[uid]
		if udef.tech_tier_required > player_faction.tech_tier:
			continue
		var label := "%s (%d・%dターン)" % [udef.display_name, udef.build_cost, udef.build_time_turns]
		if udef.icon:
			_production_option.add_icon_item(udef.icon, label)
		else:
			_production_option.add_item(label)
		_production_option.set_item_metadata(_production_option.item_count - 1, uid)
	var queue_full := region.pending_production.size() >= MAX_PLAYER_QUEUE_LENGTH
	var can_produce := is_player_owned and orders_open and not queue_full
	_production_option.disabled = not can_produce
	_produce_button.disabled = not can_produce
	_production_queue_label.text = _build_queue_text(region)

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
	if region.pending_production.size() >= MAX_PLAYER_QUEUE_LENGTH:
		_append_log("これ以上この領域には生産を予約できません（上限%d件）。" % MAX_PLAYER_QUEUE_LENGTH)
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

## Every queued job builds in parallel (see TurnManager._advance_production),
## so each gets its own "remaining turns" line rather than one number for
## a single active job plus a waiting list.
func _build_queue_text(region: Region) -> String:
	if region.pending_production.is_empty():
		return "生産キュー: なし"
	var lines: Array = []
	for job in region.pending_production:
		var udef: UnitType = GameState.unit_defs[job["unit_type_id"]]
		lines.append("%s（残り%dターン）" % [udef.display_name, job["turns_remaining"]])
	return "生産中:\n" + "\n".join(lines)

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

func _on_development_pressed() -> void:
	if GameState.is_game_over:
		return
	var panel := DevelopmentPanel.new()
	add_child(panel)
	panel.setup(GameState.player_faction_id)

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
	_flash_label(_phase_label)

## Brief color pulse so turn/phase changes register as an event instead
## of the label just silently changing text.
func _flash_label(label: Label) -> void:
	label.modulate = Color(1.6, 1.6, 1.6)
	var tween := create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, 0.35)

func _on_turn_advanced(_turn_number: int) -> void:
	_update_turn_ui()
	_refresh_all_region_colors()
	_flash_label(_turn_label)

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
