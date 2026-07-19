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
var _region_defense_label: Label
var _region_supply_label: Label
var _region_garrison_label: Label
var _production_option: OptionButton
var _produce_button: Button
var _production_queue_box: VBoxContainer
var _squad_option: OptionButton
var _move_option: OptionButton
var _move_button: Button
var _formation_button: Button
var _log_label: Label
var _development_button: Button
var _end_turn_button: Button
var _funds_label: Label
var _materials_label: Label
var _research_label: Label
var _last_funds: int = -1
var _last_materials: int = -1
var _last_research: int = -1
var _turn_progress_row: Control
var _turn_progress_bar: ProgressBar
var _turn_progress_label: Label
var _message_bar_label: Label
const DEFAULT_MESSAGE := "参謀：司令官、コマンドを選択してください。"

var _zoom_level: float = 1.0
var _dragging: bool = false
var _drag_start_mouse: Vector2
var _drag_start_cam: Vector2

const MAX_PLAYER_QUEUE_LENGTH := 5  # keep in sync with AiController.MAX_QUEUE_LENGTH's intent

func _ready() -> void:
	_build_background()
	_build_starfield()
	_build_camera()
	_build_regions_and_lines()
	_fit_camera_to_map()
	_build_ui_overlay()

	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.active_faction_changed.connect(_on_active_faction_changed)
	TurnManager.turn_events_ready.connect(_on_turn_events_ready)
	TurnManager.squad_battles_detected.connect(_on_squad_battles_detected)
	TurnManager.battle_runtime_ready.connect(_on_battle_runtime_ready)
	GameState.turn_advanced.connect(_on_turn_advanced)
	GameState.region_ownership_changed.connect(_on_region_ownership_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.supply_network_changed.connect(_on_supply_network_changed)

	_update_turn_ui()
	_update_info_panel()

# ---------------- Background ----------------

## Godot's own viewport clear color (a flat mid-gray) was the actual
## backdrop behind the starfield/map the whole time -- the starfield only
## ever drew points on top of it, never filled anything itself, so the map
## area never picked up any of the "司令デッキ" palette at all no matter how
## the panel theme changed. A dedicated low-layer CanvasLayer with a radial
## gradient fixes that at the source, screen-space so it never has to track
## the camera's own pan/zoom.
func _build_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.11, 0.20, 0.32, 1.0))
	gradient.set_color(1, UITheme.COLOR_BG)

	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	gradient_texture.fill_from = Vector2(0.2, 0.05)
	gradient_texture.fill_to = Vector2(1.0, 0.95)
	gradient_texture.width = 512
	gradient_texture.height = 512

	var bg_rect := TextureRect.new()
	bg_rect.texture = gradient_texture
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg_rect)
	UIUtils.fill_parent(bg_rect)

## A faint coordinate grid only (echoing the sensor-grid look of the design
## reference's own `.hud-frame::after`) -- no star points. An earlier pass
## added bright white dots (up to 85% opacity) here to read as "space", but
## the design reference's own background is only ever the two gradients
## plus this grid, nothing scattered on top of it; the dots were the single
## biggest reason the actual screen read as noticeably busier/less clean
## than the reference once compared side by side.
func _build_starfield() -> void:
	var stars := Node2D.new()
	stars.z_index = -20
	add_child(stars)

	var grid_color := Color(UITheme.COLOR_BORDER.r, UITheme.COLOR_BORDER.g, UITheme.COLOR_BORDER.b, 0.08)
	stars.draw.connect(func():
		for x in range(-1400, 1401, 100):
			stars.draw_line(Vector2(x, -1000), Vector2(x, 1000), grid_color, 1.0)
		for y in range(-1000, 1001, 100):
			stars.draw_line(Vector2(-1400, y), Vector2(1400, y), grid_color, 1.0)
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

	# Reserve space for all four permanent HUD elements (message bar,
	# command rail, region side panel, resource ribbon) so the fitted map
	# doesn't just avoid clipping at the raw viewport edges, but also avoids
	# rendering key regions (e.g. a faction's capital) underneath any of
	# them. Left/top/bottom track _build_ui_overlay's own message bar
	# height / rail width / ribbon height plus its margins; right is the
	# region side panel's.
	var reserved_top := 80.0
	var reserved_left := 232.0
	var reserved_right := 360.0
	var reserved_bottom := 130.0
	var viewport_size := get_viewport_rect().size
	var safe_size := Vector2(viewport_size.x - reserved_left - reserved_right, viewport_size.y - reserved_top - reserved_bottom)
	var target_zoom: float = clamp(min(safe_size.x / map_size.x, safe_size.y / map_size.y), MIN_ZOOM, 1.0)

	_zoom_level = target_zoom
	_camera.zoom = Vector2(target_zoom, target_zoom)

	# Shift the camera so the map centers within that safe rectangle rather
	# than the full screen — the camera always projects its .position to
	# screen center, so we offset away from map_center by half the
	# difference between each pair of opposing reserved strips.
	var screen_center_to_safe_center := Vector2((reserved_left - reserved_right) / 2.0, (reserved_top - reserved_bottom) / 2.0)
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
		_region_views[region_id].update_squad_badge()

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

	var viewport_size := get_viewport_rect().size
	var player_fdef: FactionDef = GameState.faction_defs[GameState.player_faction_id]

	const RIBBON_HEIGHT := 92.0
	const MESSAGE_BAR_HEIGHT := 44.0
	const RAIL_WIDTH := 192.0
	const FLYOUT_WIDTH := 190.0
	# 420 comfortably fits the production/fleet-dispatch OptionButtons' own
	# item text (unit name plus cost) -- see the fuller note further down
	# where the region panel itself is built. Computed early because the
	# message bar's own content needs to know where the region panel starts
	# so it doesn't run its own content underneath it.
	var panel_width := 420.0
	var side_panel_pos := Vector2(viewport_size.x - panel_width - 20, 20)

	# One continuous "command deck" shell, not four separately-boxed cards:
	# the design reference's own message bar / rail / map / ribbon share a
	# single gradient background and are divided only by hairline rules
	# (msgbar's border-bottom, cmd-list's border-right, resource-ribbon's
	# border-top) -- none of them has its own filled background. So this
	# shell is one transparent Panel (its border is the frame's own outer
	# edge, plus a gold top accent) sitting over the starfield/gradient
	# built in _build_background()/_build_starfield(), with separate
	# hairline ColorRects marking just those three internal seams. The
	# actual map can't be boxed in the same way the reference's placeholder
	# "戦略マップ表示領域" is without hiding the real, pannable map, so the
	# open middle area is left exactly that: open, showing the map through.
	var shell_pos := Vector2(20, 20)
	var shell_size := Vector2(viewport_size.x - 40, viewport_size.y - 40)
	var shell := Panel.new()
	shell.position = shell_pos
	shell.size = shell_size
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shell_style := StyleBoxFlat.new()
	shell_style.bg_color = Color(0, 0, 0, 0)
	shell_style.border_color = UITheme.COLOR_BORDER
	shell_style.set_border_width_all(1)
	shell.add_theme_stylebox_override("panel", shell_style)
	root.add_child(shell)

	var shell_top_accent := ColorRect.new()
	shell_top_accent.position = shell_pos
	shell_top_accent.size = Vector2(shell_size.x, 3)
	shell_top_accent.color = UITheme.COLOR_GOLD
	shell_top_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shell_top_accent)

	var content_top := shell_pos.y + MESSAGE_BAR_HEIGHT
	var ribbon_top := shell_pos.y + shell_size.y - RIBBON_HEIGHT
	var rail_right := shell_pos.x + RAIL_WIDTH

	for seam in [
		[Vector2(shell_pos.x, content_top), Vector2(shell_size.x, 1)],
		[Vector2(rail_right, content_top), Vector2(1, ribbon_top - content_top)],
		[Vector2(shell_pos.x, ribbon_top), Vector2(shell_size.x, 1)],
	]:
		var divider := ColorRect.new()
		divider.position = seam[0]
		divider.size = seam[1]
		divider.color = UITheme.COLOR_BORDER
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(divider)

	# The design reference's own msgbar has nothing in it but this one line
	# of advisor text -- no badge, no icons. Player identity moved to the
	# ribbon (see ribbon_right_row below), which already carries
	# game-specific content the reference's static mock never had to.
	var message_row := HBoxContainer.new()
	message_row.position = Vector2(shell_pos.x + 16, shell_pos.y)
	message_row.size = Vector2(side_panel_pos.x - message_row.position.x - 20, MESSAGE_BAR_HEIGHT)
	root.add_child(message_row)

	_message_bar_label = Label.new()
	_message_bar_label.text = DEFAULT_MESSAGE
	_message_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_bar_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	message_row.add_child(_message_bar_label)

	# Left command rail: category rows stacked vertically, full height (down
	# to the ribbon) so its right edge (the divider drawn above) reads as
	# one continuous line between "commands" and "map" -- matches the
	# design reference's list column stretching the full height of its
	# shell. 行動終了 deliberately does NOT live here: it's the one action
	# pressed every single turn, so it stays a dedicated primary button in
	# the ribbon instead of being buried in a list alongside everything else.
	var rail_box := VBoxContainer.new()
	rail_box.add_theme_constant_override("separation", 0)
	rail_box.position = Vector2(shell_pos.x + 16, content_top + 4)
	root.add_child(rail_box)

	var info_rail_button := _build_rail_row("情報", RAIL_WIDTH - 32)
	rail_box.add_child(info_rail_button)
	var military_rail_button := _build_rail_row("軍事", RAIL_WIDTH - 32)
	rail_box.add_child(military_rail_button)
	var production_rail_button := _build_rail_row("生産", RAIL_WIDTH - 32)
	rail_box.add_child(production_rail_button)
	_development_button = _build_rail_row("開発", RAIL_WIDTH - 32)
	rail_box.add_child(_development_button)
	var diplomacy_rail_button := _build_rail_row("外交", RAIL_WIDTH - 32)
	rail_box.add_child(diplomacy_rail_button)
	var system_rail_button := _build_rail_row("システム", RAIL_WIDTH - 32)
	rail_box.add_child(system_rail_button)

	# 軍事 and システム open a flyout instead of acting immediately -- 軍事's
	# "action" is really three different existing controls (move order,
	# formation, pilot assignment), and システム bundles two unrelated ones
	# (save/load, return to menu). Both are just another rail-like column
	# beside the first (matching the reference's own "with-flyout" 3-column
	# layout: rail | flyout | map) with a single right-hand divider, not a
	# separately boxed floating card -- there's nothing to layer in front of
	# since it has no fill of its own.
	var military_flyout := _build_flyout(rail_right, content_top, ribbon_top - content_top, FLYOUT_WIDTH)
	var move_flyout_button := _build_flyout_row(military_flyout, "移動命令", FLYOUT_WIDTH)
	UITheme.style_primary_button(move_flyout_button)
	var formation_flyout_button := _build_flyout_row(military_flyout, "部隊編成…", FLYOUT_WIDTH)
	var pilot_flyout_button := _build_flyout_row(military_flyout, "パイロット編成", FLYOUT_WIDTH)
	root.add_child(military_flyout)

	var system_flyout := _build_flyout(rail_right, content_top, ribbon_top - content_top, FLYOUT_WIDTH)
	var save_load_flyout_button := _build_flyout_row(system_flyout, "セーブ/ロード", FLYOUT_WIDTH)
	var menu_flyout_button := _build_flyout_row(system_flyout, "メインメニューへ戻る", FLYOUT_WIDTH)
	root.add_child(system_flyout)

	var flyout_entries: Array[Dictionary] = [
		{"flyout": military_flyout, "button": military_rail_button, "message": "軍事：どの行動を行いますか。"},
		{"flyout": system_flyout, "button": system_rail_button, "message": "システム：セーブ・ロード、またはメインメニューへ。"},
	]
	var close_all_flyouts := func():
		for entry: Dictionary in flyout_entries:
			(entry.flyout as Control).visible = false
			_set_rail_active(entry.button as Button, false)
		_message_bar_label.text = DEFAULT_MESSAGE
	var toggle_flyout := func(index: int):
		var entry := flyout_entries[index]
		var opening: bool = not (entry.flyout as Control).visible
		close_all_flyouts.call()
		if opening:
			(entry.flyout as Control).visible = true
			_set_rail_active(entry.button as Button, true)
			_message_bar_label.text = entry.message

	move_flyout_button.pressed.connect(func(): close_all_flyouts.call(); _on_move_pressed())
	formation_flyout_button.pressed.connect(func(): close_all_flyouts.call(); _on_formation_pressed())
	pilot_flyout_button.pressed.connect(func(): close_all_flyouts.call(); _on_pilot_assignment_pressed())
	save_load_flyout_button.pressed.connect(func(): close_all_flyouts.call(); _on_save_load_pressed())
	menu_flyout_button.pressed.connect(func(): close_all_flyouts.call(); SceneRouter.goto_main_menu())

	military_rail_button.pressed.connect(func(): toggle_flyout.call(0))
	system_rail_button.pressed.connect(func(): toggle_flyout.call(1))
	info_rail_button.pressed.connect(func(): close_all_flyouts.call(); _on_encyclopedia_pressed())
	_development_button.pressed.connect(func(): close_all_flyouts.call(); _on_development_pressed())
	diplomacy_rail_button.pressed.connect(func(): close_all_flyouts.call(); _on_diplomacy_pressed())
	# "生産は各拠点で行うように": a real standalone panel listing every
	# production-capable region the player owns, replacing the old hint
	# message that just pointed the player back at the region side panel --
	# see ProductionPanel's own doc comment for the full reasoning.
	production_rail_button.pressed.connect(func(): close_all_flyouts.call(); _on_production_pressed())

	# Resource ribbon along the bottom edge -- matches the design
	# reference's footer ribbon (funds/materials/turn). Fixed height (not
	# shrink-wrapped like the old single-row top bar was) so it never needs
	# to re-measure itself as values change. No fill of its own -- the
	# divider drawn above (at ribbon_top) is its only border, same as the
	# reference's resource-ribbon.
	var ribbon_content := HBoxContainer.new()
	ribbon_content.position = Vector2(shell_pos.x + 20, ribbon_top + 12)
	ribbon_content.size = Vector2(shell_size.x - 40, RIBBON_HEIGHT - 24)
	ribbon_content.add_theme_constant_override("separation", 40)
	root.add_child(ribbon_content)

	_funds_label = _build_stat_widget(ribbon_content, "資金", "FUNDS", &"square")
	_funds_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_materials_label = _build_stat_widget(ribbon_content, "物資", "MATERIALS", &"diamond")
	_materials_label.add_theme_color_override("font_color", player_fdef.color)
	_research_label = _build_stat_widget(ribbon_content, "研究資源", "RESEARCH", &"chevron")

	var ribbon_spacer := Control.new()
	ribbon_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon_content.add_child(ribbon_spacer)

	var ribbon_right := VBoxContainer.new()
	ribbon_right.add_theme_constant_override("separation", 6)
	ribbon_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ribbon_content.add_child(ribbon_right)

	var ribbon_right_row := HBoxContainer.new()
	ribbon_right_row.add_theme_constant_override("separation", 16)
	ribbon_right.add_child(ribbon_right_row)

	# Persistent "which one is me" indicator — the map's gold ownership ring
	# and the region panel's own faction-colored accent both answer this
	# per-region, but this answers it without having to look at either.
	# Lives here (not the message bar, which the design reference keeps to
	# just its one line of advisor text) since the ribbon already carries
	# game-specific content the reference's static mock never needed.
	var player_badge := HBoxContainer.new()
	player_badge.add_theme_constant_override("separation", 6)
	ribbon_right_row.add_child(player_badge)
	if player_fdef.emblem:
		var crest := FactionCrest.new()
		crest.setup(player_fdef, 28.0)
		player_badge.add_child(crest)
	var player_name_label := Label.new()
	player_name_label.text = player_fdef.display_name
	player_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_display_label(player_name_label, 15)
	player_name_label.add_theme_color_override("font_color", player_fdef.color)
	player_badge.add_child(player_name_label)

	_phase_label = Label.new()
	_phase_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon_right_row.add_child(_phase_label)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 18)
	_turn_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon_right_row.add_child(_turn_label)

	_end_turn_button = Button.new()
	_end_turn_button.text = "行動終了"
	_end_turn_button.custom_minimum_size = Vector2(120, 40)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	ribbon_right_row.add_child(_end_turn_button)
	# The one action every player presses every single turn gets the one
	# gold "primary" treatment — every other rail row stays neutral.
	UITheme.style_primary_button(_end_turn_button)

	## The player has no way to tell how far along AI-vs-AI turn resolution
	## is once they hit 行動終了 -- the button just says "AI行動中" with no
	## sense of progress or remaining time. A second row, hidden during the
	## player's own ORDERS phase, shows which AI faction is currently acting
	## out of how many via TurnManager.active_faction_index/
	## faction_turn_order (both already updated every time active_faction_changed
	## fires, which _update_turn_ui already listens to). The ribbon's fixed
	## height already has room for this without needing to resize anything.
	_turn_progress_row = HBoxContainer.new()
	_turn_progress_row.add_theme_constant_override("separation", 10)
	ribbon_right.add_child(_turn_progress_row)

	_turn_progress_label = Label.new()
	_turn_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_progress_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_turn_progress_row.add_child(_turn_progress_label)

	_turn_progress_bar = ProgressBar.new()
	_turn_progress_bar.custom_minimum_size = Vector2(260, 18)
	_turn_progress_bar.show_percentage = false
	_turn_progress_row.add_child(_turn_progress_bar)

	_turn_progress_row.visible = false

	# 320 clipped the production/fleet-dispatch OptionButtons' own item text
	# (unit name plus cost, e.g. "unit.nova_scout.name（資金300・物資200）")
	# — OptionButton doesn't wrap or ellipsize, it just cuts off past its
	# width. panel_width (420, set near the top of this function) comfortably
	# fits that content with the current dataset's longest labels; the map
	# area to its left has ample room to spare.
	var panel_height := 500.0
	# NOT the command shell's fully transparent glass treatment (bg alpha 0)
	# -- confirmed live that a fully transparent side_panel lets the live
	# 2D strategic map underneath (region nodes/labels near this panel's
	# left edge, e.g. a capital or shipyard node the camera happens to have
	# positioned close by) bleed straight through and visually overlap this
	# panel's own text, which the command shell's *open middle map area*
	# never has to worry about since nothing else is drawn on top of it
	# there. UITheme.COLOR_PANEL (already near-opaque, alpha 0.97) keeps
	# the same dark-glass read while actually blocking the map behind it.
	var side_panel := Panel.new()
	side_panel.position = side_panel_pos
	side_panel.size = Vector2(panel_width, panel_height)
	side_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side_panel_style := StyleBoxFlat.new()
	side_panel_style.bg_color = UITheme.COLOR_PANEL
	side_panel_style.border_color = UITheme.COLOR_BORDER
	side_panel_style.set_border_width_all(1)
	side_panel.add_theme_stylebox_override("panel", side_panel_style)
	root.add_child(side_panel)

	var side_panel_accent := ColorRect.new()
	side_panel_accent.position = side_panel_pos
	side_panel_accent.size = Vector2(panel_width, 3)
	side_panel_accent.color = player_fdef.color
	side_panel_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(side_panel_accent)

	var info_panel := VBoxContainer.new()
	info_panel.add_theme_constant_override("separation", 10)
	info_panel.position = Vector2(18, 18)
	info_panel.size = Vector2(panel_width - 36, panel_height - 36)
	side_panel.add_child(info_panel)

	_region_name_label = Label.new()
	UITheme.style_display_label(_region_name_label, 20)
	info_panel.add_child(_region_name_label)

	info_panel.add_child(HSeparator.new())
	_region_owner_label = _build_info_row(info_panel, "所有")
	info_panel.add_child(HSeparator.new())
	_region_yield_label = _build_info_row(info_panel, "資源産出")
	info_panel.add_child(HSeparator.new())
	_region_defense_label = _build_info_row(info_panel, "防御補正")
	info_panel.add_child(HSeparator.new())
	_region_supply_label = _build_info_row(info_panel, "補給")
	info_panel.add_child(HSeparator.new())
	_region_garrison_label = _build_info_row(info_panel, "駐留戦力")

	info_panel.add_child(HSeparator.new())

	info_panel.add_child(_build_section_header("PRODUCE 生産"))

	_production_option = OptionButton.new()
	# clip_text as a permanent safety net on top of the 420 panel_width:
	# guessing an exact pixel width for arbitrarily long untranslated *_key
	# item text (see the panel_width note above) is inherently fragile --
	# this guarantees a future, even-longer label always ellipsizes instead
	# of ever overflowing again, on this and every OptionButton below.
	# fit_to_longest_item defaults to true and OVERRIDES clip_text for the
	# purpose of OptionButton's own reported minimum size -- confirmed live
	# (windowed build) that clip_text alone still let this button report a
	# 576px minimum width (the locked nova_vanguard item's full "──未解禁"
	# suffixed label) and physically render that wide, spilling out past
	# the 384px-wide row and the panel's own right edge. Must be disabled
	# on every OptionButton in this panel for clip_text to actually cap the
	# rendered width instead of merely being ignored.
	_production_option.clip_text = true
	_production_option.fit_to_longest_item = false
	info_panel.add_child(_production_option)

	_produce_button = Button.new()
	_produce_button.text = "生産を予約"
	_produce_button.pressed.connect(_on_produce_pressed)
	info_panel.add_child(_produce_button)

	# One row per queued job, not just the head's progress bar -- an
	# empty-fill bar for a waiting job still tells the player "yes, this is
	# queued and will get its turn" instead of only ever showing the one
	# closest to completion (matches the design reference's queue-item list).
	_production_queue_box = VBoxContainer.new()
	_production_queue_box.add_theme_constant_override("separation", 8)
	info_panel.add_child(_production_queue_box)

	info_panel.add_child(HSeparator.new())

	info_panel.add_child(_build_section_header("DISPATCH 艦隊派遣"))

	_squad_option = OptionButton.new()
	_squad_option.clip_text = true
	_squad_option.fit_to_longest_item = false
	_squad_option.item_selected.connect(func(_index: int): _update_info_panel())
	info_panel.add_child(_squad_option)

	_move_option = OptionButton.new()
	_move_option.clip_text = true
	_move_option.fit_to_longest_item = false
	info_panel.add_child(_move_option)

	_move_button = Button.new()
	_move_button.text = "移動命令"
	_move_button.pressed.connect(_on_move_pressed)
	info_panel.add_child(_move_button)

	_formation_button = Button.new()
	_formation_button.text = "部隊編成…"
	_formation_button.pressed.connect(_on_formation_pressed)
	info_panel.add_child(_formation_button)

	info_panel.add_child(HSeparator.new())
	_log_label = Label.new()
	_log_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_log_label.custom_minimum_size = Vector2(panel_width - 40, 0)
	info_panel.add_child(_log_label)

## A small caption-over-value readout (e.g. "FUNDS 資金" over "3,420")
## instead of folding every resource into one long concatenated Label —
## each stat gets its own spot in the ribbon so a single number changing
## doesn't require rereading the whole row to find it. `en_caption` is
## optional so this stays usable for JP-only captions elsewhere.
func _build_stat_widget(parent: Control, jp_caption: String, en_caption: String = "", glyph: StringName = &"") -> Label:
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	parent.add_child(outer)
	if glyph != &"":
		var icon := HudIcon.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.glyph = glyph
		icon.glyph_color = UITheme.COLOR_TEXT_DIM
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		outer.add_child(icon)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	outer.add_child(box)
	var caption_label := Label.new()
	caption_label.text = UITheme.bracket("%s %s" % [en_caption, jp_caption] if not en_caption.is_empty() else jp_caption)
	UITheme.style_mono_label(caption_label, 10)
	caption_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	box.add_child(caption_label)
	var value_label := Label.new()
	UITheme.style_mono_label(value_label, 20)
	box.add_child(value_label)
	return value_label

## One row of the left command rail (or a flyout): plain text with a
## hairline rule underneath, no button-shaped box -- matches the design
## reference's minimal list style instead of every other panel's bordered
## button look. Hovering any row always previews gold; _set_rail_active
## controls the persistent gold state for the (currently two) categories
## that open a flyout instead of acting immediately.
func _build_rail_row(text: String, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 40)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0, 0, 0, 0)
	hover.border_color = UITheme.COLOR_GOLD
	hover.border_width_bottom = 1
	hover.content_margin_left = 14
	hover.content_margin_top = 9
	hover.content_margin_bottom = 9
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT)
	_set_rail_active(button, false)
	return button

## Toggles a rail/flyout row between its plain (dim text, hairline bottom
## rule) and active (gold text, gold left tick) look.
func _set_rail_active(button: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = UITheme.COLOR_GOLD if active else UITheme.COLOR_BORDER
	sb.border_width_bottom = 1
	sb.border_width_left = 2 if active else 0
	sb.content_margin_left = 12 if active else 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("pressed", sb)
	button.add_theme_color_override("font_color", UITheme.COLOR_GOLD if active else UITheme.COLOR_TEXT_DIM)

## Builds a flyout column beside the rail -- fixed-size and fill-less, with
## only a right-hand hairline divider, matching the design reference's own
## "with-flyout" 3-column layout (rail | flyout | map) rather than a boxed
## floating card. Full height like the rail (see _build_ui_overlay) so its
## divider reads as one continuous line, empty space below its rows and all.
func _build_flyout(x: float, y: float, height: float, width: float) -> Control:
	var flyout := Control.new()
	flyout.position = Vector2(x + 1, y)
	flyout.size = Vector2(width, height)
	flyout.visible = false
	flyout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var divider := ColorRect.new()
	divider.position = Vector2(width - 1, 0)
	divider.size = Vector2(1, height)
	divider.color = UITheme.COLOR_BORDER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyout.add_child(divider)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 0)
	box.position = Vector2(16, 4)
	flyout.add_child(box)
	return flyout

func _build_flyout_row(flyout: Control, text: String, width: float) -> Button:
	var box := flyout.get_node("Box") as VBoxContainer
	var button := _build_rail_row(text, width - 32)
	box.add_child(button)
	return button

## A caption-left / value-right row for the region side panel (e.g. "所有"
## ｜ "ノヴァ共和国（自国）") — replaces the old single Label per fact that
## concatenated the caption and value into one sentence, which read as prose
## instead of a scannable readout.
##
## Right-alignment is done with an expanding spacer between the two labels,
## NOT via `value_label.size_flags_horizontal = SIZE_EXPAND_FILL` +
## `horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT` on the value Label
## itself -- confirmed live (actual windowed build, not just a headless
## smoke test) that combination silently renders no text at all in this
## container structure, even though the Label's `.text` is set correctly
## and no error is thrown. Root cause not fully isolated (removing either
## the expand flag or the right alignment alone made it render again), but
## the spacer pattern below sidesteps it entirely: the value Label stays at
## its own natural (shrink) width and default left-internal alignment, and
## the spacer absorbs 100% of the slack, which visually right-aligns the
## value against the row's right edge without ever combining those two
## properties on the same Label.
## A caption-left / value-right row for the region side panel (e.g. "所有"
## ｜ "ノヴァ共和国（自国）") — replaces the old single Label per fact that
## concatenated the caption and value into one sentence, which read as prose
## instead of a scannable readout.
##
## The value Label deliberately uses plain absolute `.position`/`.size` with
## every anchor left at its 0/0/0/0 default, NOT `anchor_left`/`anchor_right`
## = 1.0 (the idiomatic "dock to the right edge" approach) and NOT an
## HBoxContainer + SIZE_EXPAND-flagged child (the idiomatic Container-based
## equivalent). Confirmed live -- windowed build, cross-checked against a
## deferred `get_viewport().get_texture().get_image()` capture so it isn't
## an external screenshot-tool artifact -- that at this nesting depth
## (CanvasLayer > Control > Panel > VBoxContainer > row) both of those
## idiomatic approaches (and every variant tried: SIZE_EXPAND_FILL +
## horizontal_alignment = RIGHT, SIZE_EXPAND | SIZE_SHRINK_END, a separate
## expanding spacer Control, right-docking anchors with negative offsets)
## render the value Label as fully invisible in this Godot version, even
## though every introspectable property on it (`.text`, `.size`,
## `.global_position`, `.visible`, `.modulate`, resolved theme font/color)
## reports entirely correct, on-screen, opaque values -- isolating it down
## to specifically `anchor_left`/`anchor_right` (Container expand flags
## appear to hit the same underlying path internally). Plain top-left
## position/size, matching caption_label's own already-working style and
## computed from the row's known fixed width instead of resolved via
## anchors, sidesteps it entirely.
func _build_info_row(parent: Control, caption: String) -> Label:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, 23)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var caption_label := Label.new()
	caption_label.text = UITheme.bracket(caption)
	UITheme.style_mono_label(caption_label, 11)
	caption_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	caption_label.position = Vector2(0, 3)
	caption_label.size = Vector2(104, 17)
	row.add_child(caption_label)

	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Plain absolute position/size, matching caption_label's own (working)
	# style exactly -- no anchors, no size_flags. 384 is the same fixed row
	# width (panel_width 420 - the info_panel margins 36) every row in this
	# panel already has -- see _build_ui_overlay()'s panel_width comment.
	value_label.position = Vector2(384.0 - 260.0, 0.0)
	value_label.size = Vector2(260.0, 23.0)
	row.add_child(value_label)
	return value_label

## A bracket-wrapped bilingual section label (e.g. "[ PRODUCE 生産 ]") for a
## sub-block within the side panel -- same mono/dim treatment as
## _build_info_row's captions and the production queue's own "QUEUE 生産
## キュー" header, so every label in this panel reads as one labeled-readout
## system instead of the old plain "生産:" / "艦隊派遣先:" prose-colon style.
func _build_section_header(text: String) -> Label:
	var label := Label.new()
	label.text = UITheme.bracket(text)
	UITheme.style_mono_label(label, 10)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	return label

func _update_info_panel() -> void:
	if _selected_region_id == &"":
		_region_name_label.text = "領域が選択されていません"
		_region_owner_label.text = ""
		_region_yield_label.text = ""
		_region_defense_label.text = ""
		_region_supply_label.text = ""
		_region_garrison_label.text = ""
		_production_option.disabled = true
		_produce_button.disabled = true
		for child in _production_queue_box.get_children():
			child.queue_free()
		_squad_option.disabled = true
		_move_option.disabled = true
		_move_button.disabled = true
		_formation_button.disabled = true
		return

	var region: Region = GameState.regions[_selected_region_id]
	_region_name_label.text = region.def.display_name
	var owner_name := "未占領"
	if region.owner_faction_id != &"":
		owner_name = GameState.faction_defs[region.owner_faction_id].display_name
	_region_owner_label.text = owner_name
	_region_owner_label.add_theme_color_override("font_color", _color_for_owner(region.owner_faction_id))
	_region_yield_label.text = "%d / ターン" % region.def.resource_yield
	_region_defense_label.text = "+%d" % region.def.defense_terrain_bonus
	if region.owner_faction_id == GameState.player_faction_id:
		var supplied := GameState.is_region_supplied(region.def.id, GameState.player_faction_id)
		_region_supply_label.text = "接続" if supplied else "遮断"
		_region_supply_label.add_theme_color_override("font_color", UITheme.COLOR_GOOD if supplied else UITheme.COLOR_DANGER)
	elif region.owner_faction_id.is_empty():
		_region_supply_label.text = "対象外"
		_region_supply_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	else:
		_region_supply_label.text = "不明"
		_region_supply_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_region_garrison_label.text = _garrison_text(region)

	var is_player_owned := region.owner_faction_id == GameState.player_faction_id
	var orders_open := TurnManager.current_phase == TurnManager.Phase.ORDERS and TurnManager.active_faction_id == GameState.player_faction_id and not TurnManager.is_resolving_turn

	var player_faction: Faction = GameState.get_faction(GameState.player_faction_id)
	_production_option.clear()
	var has_unlocked_option := false
	for uid in GameState.master_data.units:
		var udef: UnitDef = GameState.master_data.units[uid]
		if udef.faction_origin_id != player_faction.def.id:
			continue
		var unlocked := TechUnlock.is_unit_unlocked(player_faction, uid, GameState.master_data)
		var label := "%s（資金%d・物資%d）%s" % [
			tr(String(udef.display_name_key)),
			GameConstants.UNIT_PRODUCTION_FUNDS[udef.size],
			GameConstants.UNIT_PRODUCTION_MATERIALS[udef.size],
			"" if unlocked else "── 未解禁",
		]
		if udef.icon:
			_production_option.add_icon_item(udef.icon, label)
		else:
			_production_option.add_item(label)
		_production_option.set_item_metadata(_production_option.item_count - 1, uid)
		if unlocked:
			has_unlocked_option = true
		else:
			_production_option.set_item_disabled(_production_option.item_count - 1, true)
	var facility_ids := GameState.production_facility_ids_for_region(region.def.id)
	var queue_size := 0
	if not facility_ids.is_empty():
		var production_queue := GameState.campaign_runtime.production_queues_by_facility_id.get(facility_ids[0]) as ProductionQueueState
		queue_size = production_queue.job_ids.size() if production_queue != null else 0
	var queue_full := queue_size >= MAX_PLAYER_QUEUE_LENGTH
	var can_produce := is_player_owned and orders_open and not queue_full and not facility_ids.is_empty() and has_unlocked_option
	_production_option.disabled = not can_produce
	_produce_button.disabled = not can_produce
	_rebuild_production_queue(region, facility_ids)

	_move_option.clear()
	for neighbor_id in region.def.neighbor_ids:
		var ndef: RegionDef = GameState.region_defs[neighbor_id]
		_move_option.add_item(ndef.display_name)
		_move_option.set_item_metadata(_move_option.item_count - 1, neighbor_id)
	_squad_option.clear()
	for squad: SquadState in GameState.campaign_runtime.get_squads_in_region(region.def.id, GameState.player_faction_id):
		var status := " [移動済]" if squad.movement_used else ""
		_squad_option.add_item("%s (%d機)%s" % [squad.display_name, squad.unit_instance_ids.size(), status])
		_squad_option.set_item_metadata(_squad_option.item_count - 1, squad.squad_id)
	# Auto-select the first squad instead of leaving `selected == -1` until
	# the player manually opens the dropdown -- previously 移動命令/部隊編成
	# stayed disabled with no explanation the instant a region with a real
	# squad was selected, since selected_squad below fell through to null.
	if _squad_option.item_count > 0:
		_squad_option.select(0)
	var selected_squad := GameState.campaign_runtime.get_squad(_squad_option.get_item_metadata(_squad_option.selected)) if _squad_option.selected >= 0 else null
	var can_move: bool = is_player_owned and orders_open and selected_squad != null and not selected_squad.movement_used and _move_option.item_count > 0
	_squad_option.disabled = not is_player_owned or not orders_open or _squad_option.item_count == 0
	_move_option.disabled = not can_move
	_move_button.disabled = not can_move
	_formation_button.disabled = not is_player_owned or not orders_open or selected_squad == null

func _on_produce_pressed() -> void:
	if _selected_region_id == &"" or _production_option.selected < 0:
		return
	var region: Region = GameState.regions[_selected_region_id]
	var facility_ids := GameState.production_facility_ids_for_region(region.def.id)
	if facility_ids.is_empty():
		_append_log("この地域には生産施設がありません。")
		return
	var unit_id: StringName = _production_option.get_item_metadata(_production_option.selected)
	var result := GameState.queue_production(GameState.player_faction_id, facility_ids[0], unit_id)
	if not result.errors.is_empty():
		_append_log("生産登録に失敗しました: %s" % result.errors[0])
		return
	var unit_def := GameState.master_data.units[unit_id] as UnitDef
	_append_log("%s で %s の生産を登録しました。" % [region.def.display_name, tr(String(unit_def.display_name_key))])
	_update_info_panel()
	_update_turn_ui()

## "3個小隊・12機" — same known/unconfirmed split RegionNodeView.update_squad_badge()
## already applies to the map's own badge (COMBAT_DETAIL_SPECIFICATION.md
## section 24: an unconfirmed hostile squad's composition must not be
## revealed), so the panel and the map badge never disagree about what the
## player is allowed to know for the same region.
func _garrison_text(region: Region) -> String:
	var squad_count := 0
	var unit_count := 0
	var has_unknown := false
	for squad: SquadState in GameState.campaign_runtime.get_squads_in_region(region.def.id):
		if squad.unit_instance_ids.is_empty():
			continue
		var known := squad.owner_faction_id == GameState.player_faction_id \
			or GameState.campaign_runtime.is_squad_confirmed(GameState.player_faction_id, squad.squad_id)
		if not known:
			has_unknown = true
			continue
		squad_count += 1
		unit_count += squad.unit_instance_ids.size()
	if squad_count == 0:
		return "未確認部隊あり" if has_unknown else "駐留なし"
	var text := "%d個小隊・%d機" % [squad_count, unit_count]
	return text + "＋未確認あり" if has_unknown else text

## Rebuilds one row per queued production job (not just the head's progress)
## so a waiting job still visibly holds its place in line instead of only
## the closest-to-completion job ever showing anything.
func _rebuild_production_queue(region: Region, facility_ids: Array) -> void:
	for child in _production_queue_box.get_children():
		child.queue_free()
	if facility_ids.is_empty():
		_production_queue_box.add_child(_queue_status_label("生産施設: なし"))
		return
	var queue := GameState.campaign_runtime.production_queues_by_facility_id.get(facility_ids[0]) as ProductionQueueState
	if queue == null or queue.job_ids.is_empty():
		_production_queue_box.add_child(_queue_status_label("生産キュー: なし"))
		return
	_production_queue_box.add_child(_build_section_header("QUEUE 生産キュー"))
	for i in range(queue.job_ids.size()):
		var job := GameState.campaign_runtime.production_jobs_by_id[queue.job_ids[i]] as ProductionJobState
		var unit_def := GameState.master_data.units[job.unit_def_id] as UnitDef
		_production_queue_box.add_child(_build_queue_row(unit_def, job, i == 0))

func _queue_status_label(text: String) -> Label:
	var label := Label.new()
	label.text = UITheme.bracket(text)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	return label

## One queue entry: name/fraction on top, a thin progress track below. Only
## the head-of-queue job (is_head) actually accrues production power in this
## facility's FIFO model, so every other row's track stays visibly empty
## rather than implying it's silently progressing in parallel.
func _build_queue_row(unit_def: UnitDef, job: ProductionJobState, is_head: bool) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	row.add_child(top)
	var name_label := Label.new()
	name_label.text = tr(String(unit_def.display_name_key))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not is_head:
		name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	top.add_child(name_label)
	var frac_label := Label.new()
	frac_label.text = "%d/%d" % [job.production_accumulated, job.production_required]
	UITheme.style_mono_label(frac_label, 12)
	frac_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	top.add_child(frac_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.max_value = float(job.production_required)
	bar.value = float(job.production_accumulated) if is_head else 0.0
	row.add_child(bar)
	return row

func _on_move_pressed() -> void:
	if _selected_region_id == &"" or _squad_option.selected < 0:
		return
	var region: Region = GameState.regions[_selected_region_id]
	var idx := _move_option.selected
	if idx < 0:
		return
	var dest_id: StringName = _move_option.get_item_metadata(idx)
	var squad_id: StringName = _squad_option.get_item_metadata(_squad_option.selected)
	var errors := GameState.plan_squad_movement(squad_id, dest_id, GameState.player_faction_id)
	if not errors.is_empty():
		_append_log("移動命令に失敗しました: %s" % errors[0])
		return
	_update_info_panel()
	_append_log("%s の艦隊に %s への移動を命令しました。" % [region.def.display_name, GameState.region_defs[dest_id].display_name])


func _on_formation_pressed() -> void:
	if _squad_option.selected < 0:
		return
	var squad_id: StringName = _squad_option.get_item_metadata(_squad_option.selected)
	_open_formation_dialog(squad_id)


const FORMATION_CARD_WIDTH := 760.0

## Rebuilt as the same CanvasLayer/dim/CenterContainer/card modal every other
## panel in this game uses (DiplomacyPanel, PilotAssignmentPanel, etc.)
## instead of a bare native Window -- a separate OS-level popup with its own
## title bar was the one screen in the whole "軍事" (military) command group
## that never got the Command Deck redesign pass at all, standing out as
## visibly unstyled next to everything else. Each slot also gained an HP/EN
## mini-gauge pair (previously no visual meter existed here at all, only
## the unit's name) -- built with plain absolute position/size, never
## SIZE_EXPAND_FILL + horizontal_alignment = RIGHT or anchors; see
## StrategicMap._build_info_row's long comment for why that combination
## renders fully invisible at this nesting depth in this Godot version.
func _open_formation_dialog(squad_id: StringName) -> void:
	var squad := GameState.campaign_runtime.get_squad(squad_id)
	if squad == null:
		return

	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var root := Control.new()
	root.theme = UITheme.get_theme()
	layer.add_child(root)
	UIUtils.fill_parent(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	UIUtils.fill_parent(dim)

	var center := CenterContainer.new()
	root.add_child(center)
	UIUtils.fill_parent(center)

	var card := UITheme.make_card(Vector2(FORMATION_CARD_WIDTH, 560))
	center.add_child(card)
	var close_dialog := func(): layer.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(FORMATION_CARD_WIDTH - 48.0, 520)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "部隊編成 - %s" % squad.display_name
	UITheme.style_display_label(title, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var help := Label.new()
	help.text = "スロット変更、選択機の分割、同一地域の部隊統合ができます。"
	help.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(help)

	var split_checks: Array[CheckButton] = []
	for slot_index in range(GameConstants.MAX_UNITS_PER_SQUAD):
		vbox.add_child(_build_formation_slot_row(squad_id, squad, slot_index, split_checks, close_dialog))

	var split_button := Button.new()
	split_button.text = "選択した機体を新部隊へ分割"
	split_button.custom_minimum_size = Vector2(0, 40)
	split_button.pressed.connect(func():
		var selected_units: Array[StringName] = []
		for check in split_checks:
			if check.button_pressed: selected_units.append(StringName(check.get_meta("unit_id")))
		var result := GameState.campaign_runtime.split_squad(squad_id, selected_units, "%s 分遣隊" % squad.display_name)
		if not result.errors.is_empty(): _append_log("部隊分割に失敗しました: %s" % result.errors[0])
		close_dialog.call()
		_update_info_panel()
	)
	vbox.add_child(split_button)

	var merge_row := HBoxContainer.new()
	merge_row.add_theme_constant_override("separation", 8)
	vbox.add_child(merge_row)
	var merge_option := OptionButton.new()
	merge_option.custom_minimum_size = Vector2(FORMATION_CARD_WIDTH - 48.0 - 150.0, 36)
	merge_option.clip_text = true
	merge_option.fit_to_longest_item = false
	for other: SquadState in GameState.campaign_runtime.get_squads_in_region(squad.region_id, squad.owner_faction_id):
		if other.squad_id != squad_id:
			merge_option.add_item("%s (%d機)" % [other.display_name, other.unit_instance_ids.size()])
			merge_option.set_item_metadata(merge_option.item_count - 1, other.squad_id)
	merge_row.add_child(merge_option)
	var merge_button := Button.new()
	merge_button.text = "選択部隊を統合"
	merge_button.custom_minimum_size = Vector2(140, 36)
	merge_button.disabled = merge_option.item_count == 0
	merge_button.pressed.connect(func():
		var source_id: StringName = merge_option.get_item_metadata(merge_option.selected)
		var errors := GameState.campaign_runtime.merge_squads(squad_id, source_id)
		if not errors.is_empty(): _append_log("部隊統合に失敗しました: %s" % errors[0])
		close_dialog.call()
		_update_info_panel()
	)
	merge_row.add_child(merge_button)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(close_dialog)
	vbox.add_child(close_button)

## One slot's full row: SLOT tag + unit name + HP/EN mini-gauges on top, then
## the 分割/スロット変更/EN補給/修理開始 controls below -- split into its own
## function since _open_formation_dialog was already long before this and
## the gauges need several more lines each.
func _build_formation_slot_row(squad_id: StringName, squad: SquadState, slot_index: int, split_checks: Array[CheckButton], close_dialog: Callable) -> Panel:
	var unit_id := squad.get_unit_at_slot(slot_index)
	var row_height := 90.0 if not unit_id.is_empty() else 44.0
	var card := Panel.new()
	card.custom_minimum_size = Vector2(0, row_height)
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_RAISED
	style.border_color = UITheme.COLOR_BORDER
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)

	var row_width := FORMATION_CARD_WIDTH - 48.0

	var slot_label := Label.new()
	slot_label.position = Vector2(12, 10)
	slot_label.size = Vector2(70, 20)
	UITheme.style_mono_label(slot_label, 11)
	slot_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	slot_label.text = UITheme.bracket("SLOT %d" % slot_index)
	card.add_child(slot_label)

	if unit_id.is_empty():
		var empty_label := Label.new()
		empty_label.position = Vector2(90, 10)
		empty_label.size = Vector2(row_width - 100.0, 20)
		empty_label.text = "空き"
		empty_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		card.add_child(empty_label)
		var check := CheckButton.new()
		check.disabled = true
		check.set_meta("unit_id", unit_id)
		check.position = Vector2(row_width - 60.0, 4)
		card.add_child(check)
		split_checks.append(check)
		return card

	var unit := GameState.campaign_runtime.get_unit(unit_id)
	var unit_def := GameState.master_data.units.get(unit.unit_def_id) as UnitDef

	var name_label := Label.new()
	name_label.position = Vector2(90, 8)
	name_label.size = Vector2(row_width - 100.0, 20)
	UITheme.style_display_label(name_label, 14)
	name_label.text = tr(String(unit_def.display_name_key))
	card.add_child(name_label)

	var check := CheckButton.new()
	check.text = "分割"
	check.set_meta("unit_id", unit_id)
	check.position = Vector2(row_width - 66.0, 6)
	card.add_child(check)
	split_checks.append(check)

	# HP/EN mini-gauges -- see this function's own doc comment: the only
	# visual condition readout in this dialog used to be the unit's name
	# alone, with no indication of damage or EN state at all.
	var gauge_width := (row_width - 90.0 - 12.0) / 2.0
	_build_formation_gauge(card, 90.0, 34.0, gauge_width, "HP", unit.current_hp, unit_def.max_hp, UITheme.COLOR_GOOD if unit.current_hp > unit_def.max_hp * 0.3 else UITheme.COLOR_DANGER)
	_build_formation_gauge(card, 90.0 + gauge_width + 12.0, 34.0, gauge_width, "EN", unit.current_en, unit_def.max_en, UITheme.COLOR_GOLD)

	var controls := HBoxContainer.new()
	controls.position = Vector2(90.0, 58.0)
	controls.size = Vector2(row_width - 100.0, 28)
	controls.add_theme_constant_override("separation", 8)
	card.add_child(controls)

	var slot_option := OptionButton.new()
	slot_option.custom_minimum_size = Vector2(110, 28)
	for candidate in range(GameConstants.MAX_UNITS_PER_SQUAD):
		slot_option.add_item("Slot %d" % candidate)
		slot_option.set_item_disabled(candidate, candidate != slot_index and not squad.get_unit_at_slot(candidate).is_empty())
	slot_option.select(slot_index)
	slot_option.item_selected.connect(func(new_slot: int):
		var errors := GameState.campaign_runtime.move_unit_to_slot(squad_id, unit_id, new_slot)
		close_dialog.call()
		if not errors.is_empty(): _append_log("スロット変更に失敗しました: %s" % errors[0])
		_update_info_panel()
	)
	controls.add_child(slot_option)

	var en_button := Button.new()
	en_button.text = "EN補給"
	en_button.custom_minimum_size = Vector2(80, 28)
	en_button.pressed.connect(func():
		var errors := GameState.resupply_unit_en(unit_id, GameState.player_faction_id)
		if not errors.is_empty(): _append_log("EN補給に失敗しました: %s" % errors[0])
		else: _append_log("ENを最大まで補給しました。")
	)
	controls.add_child(en_button)

	var repair_button := Button.new()
	repair_button.text = "修理開始"
	repair_button.custom_minimum_size = Vector2(80, 28)
	repair_button.pressed.connect(func():
		var result := GameState.start_unit_repair(unit_id, GameState.player_faction_id)
		if not result.errors.is_empty(): _append_log("修理開始に失敗しました: %s" % result.errors[0])
		else: _append_log("修理を開始しました（%dターン）。" % result.turns)
		close_dialog.call()
		_update_info_panel()
	)
	controls.add_child(repair_button)

	return card

## A labeled mini-gauge at an explicit absolute position -- plain
## position/size Labels only, matching every other gauge built this
## session (see _open_formation_dialog's doc comment for why).
func _build_formation_gauge(card: Panel, x: float, y: float, width: float, caption: String, value: int, max_value: int, color: Color) -> void:
	var caption_label := Label.new()
	caption_label.position = Vector2(x, y)
	caption_label.size = Vector2(26, 16)
	UITheme.style_mono_label(caption_label, 10)
	caption_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	caption_label.text = caption
	card.add_child(caption_label)

	var value_label := Label.new()
	value_label.position = Vector2(x + width - 60.0, y)
	value_label.size = Vector2(60, 16)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.style_mono_label(value_label, 10)
	value_label.text = "%d/%d" % [value, max_value]
	card.add_child(value_label)

	var track := ProgressBar.new()
	track.position = Vector2(x + 28.0, y + 2.0)
	track.size = Vector2(width - 28.0 - 62.0, 6)
	track.show_percentage = false
	track.max_value = maxf(1.0, max_value)
	track.value = clampf(value, 0.0, max_value)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	track.add_theme_stylebox_override("fill", fill_style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UITheme.COLOR_PANEL
	track.add_theme_stylebox_override("background", bg_style)
	card.add_child(track)

func _on_end_turn_pressed() -> void:
	if GameState.is_game_over or TurnManager.is_resolving_turn or TurnManager.active_faction_id != GameState.player_faction_id:
		return
	TurnManager.commit_turn()

func _on_development_pressed() -> void:
	if GameState.is_game_over or TurnManager.is_resolving_turn or TurnManager.active_faction_id != GameState.player_faction_id or TurnManager.current_phase != TurnManager.Phase.ORDERS:
		return
	var panel := DevelopmentPanel.new()
	add_child(panel)
	panel.setup(GameState.player_faction_id)

func _on_save_load_pressed() -> void:
	var panel := SaveLoadPanel.new()
	add_child(panel)
	panel.setup()

func _on_encyclopedia_pressed() -> void:
	var panel := EncyclopediaPanel.new()
	add_child(panel)
	panel.setup()

func _on_diplomacy_pressed() -> void:
	var panel := DiplomacyPanel.new()
	add_child(panel)
	panel.setup(GameState.player_faction_id)

func _on_production_pressed() -> void:
	var panel := ProductionPanel.new()
	add_child(panel)
	panel.setup()

func _on_pilot_assignment_pressed() -> void:
	var panel := PilotAssignmentPanel.new()
	add_child(panel)
	panel.setup(GameState.player_faction_id)

func _on_turn_events_ready(summary: String) -> void:
	if not summary.is_empty():
		_append_log(summary)

func _on_squad_battles_detected(battles: Array[Dictionary]) -> void:
	var names: Array[String] = []
	for battle: Dictionary in battles:
		var region_def := GameState.region_defs.get(battle.region_id) as RegionDef
		names.append(region_def.display_name if region_def != null else String(battle.region_id))
	_append_log("戦闘待機地域: %s（RTS戦闘実装後に解決）" % ", ".join(names))

func _on_battle_runtime_ready(battle: BattleRuntimeState) -> void:
	var view := BattlePrototypeView.new()
	view.setup(battle)
	add_child(view)

func _on_phase_changed(_phase) -> void:
	_update_turn_ui()
	_update_info_panel()
	_flash_label(_phase_label)
	_maybe_open_event_panel()

## EVENT_DETAIL_SPECIFICATION.md section 8: pending events play "戦略フェイズ
## 前", i.e. before the player can act in Phase.ORDERS. TurnManager already
## populated GameState.get_faction(player_faction_id).pending_event_ids by
## the time this phase_changed(ORDERS) fires; the panel is a modal overlay
## (mouse_filter STOP, layer above everything else) so it blocks the player
## from reaching any other button until every queued event is resolved,
## which is enough to satisfy "before the strategy phase" without needing
## TurnManager itself to await UI input mid-turn-advance.
func _maybe_open_event_panel() -> void:
	if TurnManager.current_phase != TurnManager.Phase.ORDERS or TurnManager.active_faction_id != GameState.player_faction_id:
		return
	var faction := GameState.get_faction(GameState.player_faction_id)
	if faction == null or faction.pending_event_ids.is_empty():
		return
	for child in get_children():
		if child is EventPanel:
			return
	var panel := EventPanel.new()
	add_child(panel)
	panel.setup(GameState.player_faction_id)

func _on_active_faction_changed(_faction_id: StringName, _index: int) -> void:
	_update_turn_ui()
	_update_info_panel()
	_refresh_all_region_colors()
	_refresh_all_region_badges()

func _on_supply_network_changed(_faction_id: StringName) -> void:
	_update_info_panel()

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
	var active_name := "---"
	var active_def := GameState.faction_defs.get(TurnManager.active_faction_id) as FactionDef
	if active_def != null:
		active_name = active_def.display_name
	_phase_label.text = "%s ・ %s" % [active_name, phase_names[TurnManager.current_phase]]
	var faction: Faction = GameState.get_faction(GameState.player_faction_id)
	if faction:
		# Count up from the previously displayed value instead of silently
		# replacing the text -- a resource change (weekly income, a gift, a
		# purchase) reads as an event, not just a number that jumped. -1 is
		# the "first paint" sentinel: the very first call has no prior value
		# to animate from, so it sets the text directly with no flash.
		if _last_funds < 0:
			_funds_label.text = str(faction.funds)
		else:
			UITheme.animate_value(self, _funds_label, _last_funds, faction.funds)
		_last_funds = faction.funds
		if _last_materials < 0:
			_materials_label.text = str(faction.materials)
		else:
			UITheme.animate_value(self, _materials_label, _last_materials, faction.materials)
		_last_materials = faction.materials
		if _last_research < 0:
			_research_label.text = str(faction.resources)
		else:
			UITheme.animate_value(self, _research_label, _last_research, faction.resources)
		_last_research = faction.resources
	var player_orders := TurnManager.active_faction_id == GameState.player_faction_id and TurnManager.current_phase == TurnManager.Phase.ORDERS and not TurnManager.is_resolving_turn
	_development_button.disabled = not player_orders
	_end_turn_button.disabled = not player_orders
	_end_turn_button.text = "行動終了" if player_orders else "AI行動中"
	_update_turn_progress(active_name)
	_refresh_all_region_badges()

## faction_turn_order[0] is always the player (_build_faction_turn_order),
## so AI factions occupy indices 1..size-1: active_faction_index doubles as
## "how many AI factions have started their turn so far" whenever an AI
## faction is active. The ribbon has a fixed size (see RIBBON_HEIGHT in
## _build_ui_overlay), so this row showing/hiding never needs to trigger a
## resize the way the old shrink-wrapped top bar card did.
func _update_turn_progress(active_name: String) -> void:
	var ai_total := TurnManager.faction_turn_order.size() - 1
	var showing := TurnManager.is_resolving_turn and TurnManager.active_faction_id != GameState.player_faction_id and ai_total > 0
	_turn_progress_row.visible = showing
	if not showing:
		return
	var ai_index := clampi(TurnManager.active_faction_index, 1, ai_total)
	_turn_progress_bar.max_value = float(ai_total)
	_turn_progress_bar.value = float(ai_index)
	_turn_progress_label.text = "AI行動中: %s (%d / %d)" % [active_name, ai_index, ai_total]

func _append_log(text: String) -> void:
	_log_label.text = text

func _on_game_over(_reason: String, _standings: Array) -> void:
	SceneRouter.goto_results()
