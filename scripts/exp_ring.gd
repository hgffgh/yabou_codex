class_name ExpRing
extends Control
## Radial EXP gauge replacing pilot_assignment_panel.gd's linear ProgressBar
## + separate "EXP N/M" label: a donut track (drawn the same way
## RegionNodeView draws its player-ownership ring, generalized to an
## arbitrary fraction) with the pilot's level centered inside, so "how close
## to leveling up" and "what level now" read from one glyph instead of two
## widgets. `ring_color` lets the caller recolor it per pilot state (nova
## blue when ready, COLOR_DANGER while injured).

var _progress: float = 0.0
var _ring_color: Color = Color.WHITE
var _level_label: Label
const _TRACK_COLOR := Color(1, 1, 1, 0.09)

func setup(level: int, progress: float, ring_color: Color) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	_ring_color = ring_color
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(64, 64)
		size = custom_minimum_size

	if _level_label == null:
		_level_label = Label.new()
		_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_level_label)
		UIUtils.fill_parent(_level_label)
	UITheme.style_mono_label(_level_label, int(size.y * 0.3))
	_level_label.text = "Lv%d" % level
	_level_label.add_theme_color_override("font_color", ring_color)

	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var width := maxf(4.0, r * 0.22)
	draw_arc(c, r, 0.0, TAU, 48, _TRACK_COLOR, width, true)
	if _progress > 0.0:
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + _progress * TAU, 48, _ring_color, width, true)
