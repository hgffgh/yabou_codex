class_name RegionNodeView
extends Node2D
## One clickable region marker on the strategic map. Built entirely in code
## (circle via _draw(), click detection via a child Area2D) so no separate
## per-region .tscn is needed — StrategicMap instances one of these per
## RegionDef in the loaded campaign.

signal region_clicked(region_id: StringName)

const RADIUS := 28.0
const BADGE_RADIUS := 12.0
const BADGE_OFFSET := Vector2(20, 20)

var region_id: StringName
var region_ref: Region
var fill_color: Color = Color.GRAY
var is_selected: bool = false
var is_hovered: bool = false

var _badge_label: Label

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

	_badge_label = Label.new()
	_badge_label.add_theme_font_size_override("font_size", 11)
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.position = BADGE_OFFSET - Vector2(BADGE_RADIUS, BADGE_RADIUS)
	_badge_label.size = Vector2(BADGE_RADIUS * 2, BADGE_RADIUS * 2)
	_badge_label.visible = false
	add_child(_badge_label)

	update_unit_badge()
	queue_redraw()

func set_owner_color(color: Color) -> void:
	fill_color = color
	queue_redraw()

func set_selected(selected: bool) -> void:
	is_selected = selected
	queue_redraw()

## Small numeral badge showing total units stationed here, so the player
## can see where their (and the enemy's) forces are without clicking every
## region — this was the main usability gap the M5.5 pass targeted.
func update_unit_badge() -> void:
	var total := 0
	for stack in region_ref.stacks.values():
		total += stack.total_count()
	if total <= 0:
		_badge_label.visible = false
	else:
		_badge_label.visible = true
		_badge_label.text = str(total) if total < 100 else "99+"
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

	var draw_color := fill_color.lightened(0.15) if is_hovered else fill_color
	draw_circle(Vector2.ZERO, RADIUS, draw_color)

	var outline_color := Color.WHITE if is_selected else Color(0, 0, 0, 0.6)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, outline_color, 4.0 if is_selected else 2.0)

	if region_ref.def.is_capital_slot:
		draw_circle(Vector2.ZERO, RADIUS * 0.35, Color.WHITE)

	if _badge_label and _badge_label.visible:
		draw_circle(BADGE_OFFSET, BADGE_RADIUS, Color(0.1, 0.1, 0.13, 0.95))
		draw_arc(BADGE_OFFSET, BADGE_RADIUS, 0, TAU, 20, Color.WHITE, 1.5)
