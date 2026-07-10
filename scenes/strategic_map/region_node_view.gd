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

	update_unit_badge()
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
func update_unit_badge() -> void:
	var total := 0
	var dominant_id: StringName = &""
	var dominant_count := -1
	for stack in region_ref.stacks.values():
		for uid in stack.units:
			var count: int = stack.units[uid]
			total += count
			if count > dominant_count:
				dominant_count = count
				dominant_id = uid

	if total <= 0:
		_badge_icon.visible = false
		_badge_count_label.visible = false
	else:
		_badge_count_label.visible = true
		_badge_count_label.text = str(total) if total < 100 else "99+"
		var udef: UnitType = GameState.unit_defs.get(dominant_id)
		if udef and udef.icon:
			_badge_icon.texture = udef.icon
			_badge_icon.visible = true
		else:
			_badge_icon.visible = false
	queue_redraw()

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

	if _badge_icon and _badge_icon.visible:
		draw_circle(BADGE_OFFSET, BADGE_RADIUS, Color(0.1, 0.1, 0.13, 0.95))
		draw_arc(BADGE_OFFSET, BADGE_RADIUS, 0, TAU, 20, Color.WHITE, 1.5)
		# Small dark pill behind the count so it stays legible over the icon.
		var count_pos := BADGE_OFFSET + Vector2(2, BADGE_RADIUS - 6) + Vector2(12, 7)
		draw_circle(count_pos, 8.0, Color(0.05, 0.05, 0.07, 0.9))
