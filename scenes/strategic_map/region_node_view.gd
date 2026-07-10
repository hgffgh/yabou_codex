class_name RegionNodeView
extends Node2D
## One clickable region marker on the strategic map. Built entirely in code
## (circle via _draw(), click detection via a child Area2D) so no separate
## per-region .tscn is needed — StrategicMap instances one of these per
## RegionDef in the loaded campaign.

signal region_clicked(region_id: StringName)

const RADIUS := 28.0

var region_id: StringName
var region_ref: Region
var fill_color: Color = Color.GRAY
var is_selected: bool = false

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
	add_child(area)

	var label := Label.new()
	label.text = region.def.display_name
	label.add_theme_font_size_override("font_size", 12)
	label.position = Vector2(-RADIUS - 20, RADIUS + 4)
	label.custom_minimum_size = Vector2(RADIUS * 2 + 40, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	queue_redraw()

func set_owner_color(color: Color) -> void:
	fill_color = color
	queue_redraw()

func set_selected(selected: bool) -> void:
	is_selected = selected
	queue_redraw()

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		region_clicked.emit(region_id)

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, fill_color)
	var outline_color := Color.WHITE if is_selected else Color(0, 0, 0, 0.6)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, outline_color, 4.0 if is_selected else 2.0)
	if region_ref.def.is_capital_slot:
		draw_circle(Vector2.ZERO, RADIUS * 0.35, Color.WHITE)
