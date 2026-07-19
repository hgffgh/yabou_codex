class_name HudIcon
extends Control
## Procedural vector glyph, no texture. Generalizes the one existing
## convention in the codebase -- RegionNodeView._draw_terrain_accent()'s
## "square = shipyard, triangle = border zone" outline shapes drawn straight
## in _draw() -- into a small reusable set usable anywhere a stat/status
## needs an icon (resource ribbon, region panel, pilot skill chips) without
## a single new art asset. `glyph` selects the shape; `glyph_color` tints it
## (callers pass UITheme.COLOR_GOLD, a faction color, etc.).

@export var glyph: StringName = &"square"
@export var glyph_color: Color = Color.WHITE
@export var line_width: float = 1.6

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(16, 16)

func set_glyph(new_glyph: StringName, color: Color) -> void:
	glyph = new_glyph
	glyph_color = color
	queue_redraw()

func _draw() -> void:
	var s := size
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.5 - line_width
	match glyph:
		&"square":
			var half := r * 0.72
			draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), glyph_color, false, line_width)
		&"triangle":
			var pts := PackedVector2Array([
				c + Vector2(0, -r),
				c + Vector2(r * 0.87, r * 0.6),
				c + Vector2(-r * 0.87, r * 0.6),
			])
			draw_polyline(pts + PackedVector2Array([pts[0]]), glyph_color, line_width)
		&"hex":
			var hex_pts := _hex_points(c, r)
			draw_polyline(hex_pts + PackedVector2Array([hex_pts[0]]), glyph_color, line_width)
		&"diamond":
			var pts := PackedVector2Array([
				c + Vector2(0, -r),
				c + Vector2(r, 0),
				c + Vector2(0, r),
				c + Vector2(-r, 0),
			])
			draw_colored_polygon(pts, glyph_color)
		&"chevron":
			# An open "^" stroke, not a filled ribbon: a closed chevron
			# ribbon's inner/outer edges cross each other (a self-
			# intersecting "bowtie" polygon), which Godot's polygon
			# triangulator can't fill -- an open polyline sidesteps that
			# entirely and still reads clearly as a chevron at icon size.
			var w := r * 0.85
			var h := r * 0.55
			var pts := PackedVector2Array([
				c + Vector2(-w, h),
				c + Vector2(0, -h),
				c + Vector2(w, h),
			])
			draw_polyline(pts, glyph_color, line_width * 1.8)
		_:
			pass

## Flat-top hexagon vertices, matching FactionCrest's own hex silhouette so
## the "陣営紋章" icon-strip glyph reads as a small preview of the crest.
static func _hex_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var angle := PI / 6.0 + i * PI / 3.0
		pts.append(c + Vector2(cos(angle), sin(angle)) * r)
	return pts
