class_name FactionCrest
extends Control
## A faction's identity badge: a hexagon outline in FactionDef.color with
## the faction's existing emblem (assets/ui/emblems/*.svg, already
## referenced by every FactionDef -- no new art) centered inside a dark
## backing. Replaces the ad hoc square emblem badges strategic_map.gd and
## diplomacy_panel.gd would otherwise each build separately, matching the
## design reference's hexagonal crest without hand-drawing a per-faction
## glyph -- the real emblem art already does that job.

var _color: Color = Color.WHITE
var _emblem: TextureRect

func setup(fdef: FactionDef, crest_size: float = 44.0) -> void:
	_color = fdef.color if fdef != null else Color.WHITE
	custom_minimum_size = Vector2(crest_size, crest_size)
	size = Vector2(crest_size, crest_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _emblem == null and fdef != null and fdef.emblem != null:
		_emblem = TextureRect.new()
		_emblem.texture = fdef.emblem
		_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_emblem)
	if _emblem != null:
		var inner := crest_size * 0.56
		_emblem.position = (Vector2(crest_size, crest_size) - Vector2(inner, inner)) * 0.5
		_emblem.size = Vector2(inner, inner)

	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var pts := HudIcon._hex_points(c, r)
	var closed := pts + PackedVector2Array([pts[0]])
	draw_colored_polygon(pts, Color(0.02, 0.05, 0.09, 0.85))
	draw_polyline(closed, _color, 2.0)
