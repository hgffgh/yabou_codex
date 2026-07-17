class_name RegionNodeView
extends Node2D
## One clickable region marker on the strategic map. Built entirely in code
## (circle via _draw(), click detection via a child Area2D) so no separate
## per-region .tscn is needed — StrategicMap instances one of these per
## RegionDef in the loaded campaign.

signal region_clicked(region_id: StringName)

const RADIUS := 28.0
const BADGE_RADIUS := 16.0
const BADGE_OFFSET := Vector2(22, 22)
const PLAYER_RING_COLOR := Color(1.0, 0.85, 0.25, 0.95)

var region_id: StringName
var region_ref: Region
var fill_color: Color = Color.GRAY
var is_selected: bool = false
var is_hovered: bool = false
var is_player_owned: bool = false

var _badge_icon: TextureRect
var _badge_count_label: Label

func setup(id: StringName, region: Region, color: Color) -> void:
	region_id = id
	region_ref = region
	fill_color = color
	position = region.def.map_position

	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	area.add_child(shape)
	area.input_pickable = true
	area.input_event.connect(_on_area_input_event)
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)
	add_child(area)

	var label := Label.new()
	label.text = region.def.display_name
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.position = Vector2(-RADIUS - 20, RADIUS + 4)
	label.custom_minimum_size = Vector2(RADIUS * 2 + 40, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)

	_badge_icon = TextureRect.new()
	_badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_icon.size = Vector2(BADGE_RADIUS * 1.3, BADGE_RADIUS * 1.3)
	_badge_icon.position = BADGE_OFFSET - _badge_icon.size / 2.0
	_badge_icon.visible = false
	add_child(_badge_icon)

	_badge_count_label = Label.new()
	_badge_count_label.add_theme_font_size_override("font_size", 10)
	_badge_count_label.add_theme_color_override("font_color", Color.WHITE)
	_badge_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_count_label.position = BADGE_OFFSET + Vector2(2, BADGE_RADIUS - 6)
	_badge_count_label.size = Vector2(24, 14)
	_badge_count_label.visible = false
	add_child(_badge_count_label)

	update_squad_badge()
	queue_redraw()

func set_owner_color(color: Color) -> void:
	fill_color = color
	queue_redraw()

## Gold ring around the marker, independent of faction color — the fastest
## way to answer "which ones are mine?" at a glance across the whole map,
## rather than having to remember/match your faction's specific hue.
func set_player_owned(owned: bool) -> void:
	is_player_owned = owned
	queue_redraw()

func set_selected(selected: bool) -> void:
	is_selected = selected
	queue_redraw()

## Badge showing the dominant unit type stationed here (by count) plus a
## total count, so the player can see WHAT is garrisoned where, not just
## THAT something is — a plain number badge didn't answer "which unit?"
## COMBAT_DETAIL_SPECIFICATION.md section 24: an unconfirmed hostile squad
## must not reveal its composition, so it is excluded from the known-count
## tally and instead flips the badge to a "?" placeholder — showing exact
## numbers alongside an unknown presence would misleadingly imply the
## total is fully known.
func update_squad_badge() -> void:
	var total := 0
	var dominant_id: StringName = &""
	var counts_by_unit_def_id: Dictionary = {}
	var has_unknown_contact := false
	for squad: SquadState in GameState.campaign_runtime.get_squads_in_region(region_id):
		var known := squad.owner_faction_id == GameState.player_faction_id or GameState.campaign_runtime.is_squad_confirmed(GameState.player_faction_id, squad.squad_id)
		if not known:
			if not squad.unit_instance_ids.is_empty():
				has_unknown_contact = true
			continue
		for unit_instance_id: StringName in squad.unit_instance_ids:
			var unit := GameState.campaign_runtime.get_unit(unit_instance_id) as UnitInstanceState
			if unit == null:
				continue
			total += 1
			counts_by_unit_def_id[unit.unit_def_id] = int(counts_by_unit_def_id.get(unit.unit_def_id, 0)) + 1

	var dominant_count := -1
	var sorted_unit_def_ids := counts_by_unit_def_id.keys()
	sorted_unit_def_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for unit_def_id: StringName in sorted_unit_def_ids:
		var count: int = counts_by_unit_def_id[unit_def_id]
		if count > dominant_count:
			dominant_count = count
			dominant_id = unit_def_id

	if has_unknown_contact:
		_badge_icon.visible = false
		_badge_count_label.visible = true
		_badge_count_label.text = "?"
	elif total <= 0:
		_badge_icon.visible = false
		_badge_count_label.visible = false
	else:
		_badge_count_label.visible = true
		_badge_count_label.text = str(total) if total < 100 else "99+"
		var udef := GameState.master_data.units.get(dominant_id) as UnitDef
		if udef and udef.icon:
			_badge_icon.texture = udef.icon
			_badge_icon.visible = true
		else:
			_badge_icon.visible = false
	queue_redraw()

## Compatibility entry point: this renders new SquadState data only.
func update_unit_badge() -> void:
	update_squad_badge()

func _on_mouse_entered() -> void:
	is_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	is_hovered = false
	queue_redraw()

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		region_clicked.emit(region_id)

func _draw() -> void:
	if is_selected:
		draw_circle(Vector2.ZERO, RADIUS + 8.0, Color(1, 1, 1, 0.12))

	if is_player_owned:
		draw_arc(Vector2.ZERO, RADIUS + 6.0, 0, TAU, 40, PLAYER_RING_COLOR, 3.0)

	var draw_color := fill_color.lightened(0.15) if is_hovered else fill_color
	draw_circle(Vector2.ZERO, RADIUS, draw_color)

	var outline_color := Color.WHITE if is_selected else Color(0, 0, 0, 0.6)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, outline_color, 4.0 if is_selected else 2.0)

	if region_ref.def.is_capital_slot:
		draw_circle(Vector2.ZERO, RADIUS * 0.35, Color.WHITE)
	else:
		_draw_terrain_accent()

	if _badge_count_label and _badge_count_label.visible:
		draw_circle(BADGE_OFFSET, BADGE_RADIUS, Color(0.1, 0.1, 0.13, 0.95))
		draw_arc(BADGE_OFFSET, BADGE_RADIUS, 0, TAU, 20, Color.WHITE, 1.5)
		# Small dark pill behind the count so it stays legible over the icon.
		var count_pos := BADGE_OFFSET + Vector2(2, BADGE_RADIUS - 6) + Vector2(12, 7)
		draw_circle(count_pos, 8.0, Color(0.05, 0.05, 0.07, 0.9))

## A small top-left glyph hinting at the region's terrain_type, so the map
## isn't just uniform circles — capitals already stand out via their
## white core dot, so this only draws for non-capital terrain.
func _draw_terrain_accent() -> void:
	var terrain: StringName = region_ref.def.terrain_type
	var accent_pos := Vector2(-18, -18)
	var accent_color := Color(1, 1, 1, 0.55)
	match terrain:
		"shipyard_belt":
			# small square outline — production/industry
			draw_rect(Rect2(accent_pos - Vector2(5, 5), Vector2(10, 10)), accent_color, false, 1.6)
		"border_zone":
			# small triangle — front line / lookout
			var pts := PackedVector2Array([
				accent_pos + Vector2(0, -6),
				accent_pos + Vector2(6, 5),
				accent_pos + Vector2(-6, 5),
			])
			draw_polyline(pts + PackedVector2Array([pts[0]]), accent_color, 1.6)
		_:
			pass
