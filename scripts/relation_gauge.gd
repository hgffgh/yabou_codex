class_name RelationGauge
extends Control
## Center-anchored friendship gauge replacing diplomacy_panel.gd's plain
## left-aligned ProgressBar(-100..100): a hairline track with a center tick,
## and a fill that grows right from the middle for a positive value or left
## for a negative one -- which faction the relationship leans toward reads
## from the fill's direction, not just a number.

var _value: float = 0.0
var _fill_color: Color = Color.WHITE
const _TRACK_COLOR := Color(1, 1, 1, 0.14)
const _TICK_COLOR := Color(1, 1, 1, 0.32)

func set_value(value: float, fill_color: Color) -> void:
	_value = clampf(value, -100.0, 100.0)
	_fill_color = fill_color
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(120, 12)
	queue_redraw()

func _draw() -> void:
	var track_y := size.y * 0.5
	draw_line(Vector2(0, track_y), Vector2(size.x, track_y), _TRACK_COLOR, 3.0)
	var mid_x := size.x * 0.5
	draw_line(Vector2(mid_x, 0), Vector2(mid_x, size.y), _TICK_COLOR, 1.0)
	var half_width := size.x * 0.5
	var extent := half_width * (absf(_value) / 100.0)
	if extent <= 0.0:
		return
	if _value >= 0.0:
		draw_line(Vector2(mid_x, track_y), Vector2(mid_x + extent, track_y), _fill_color, 4.0)
	else:
		draw_line(Vector2(mid_x - extent, track_y), Vector2(mid_x, track_y), _fill_color, 4.0)
