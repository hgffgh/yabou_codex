class_name UITheme
extends RefCounted
## Single shared Theme so every screen's buttons/panels/bars look like one
## system instead of ad-hoc per-screen styling. Built once in code (not a
## hand-authored .tres — see UIUtils for why we avoid hand-authoring Godot
## resource internals where a script can do it more reliably) and cached.

const COLOR_BG := Color(0.07, 0.08, 0.11, 1.0)
const COLOR_PANEL := Color(0.10, 0.11, 0.15, 0.97)
const COLOR_PANEL_RAISED := Color(0.15, 0.16, 0.21, 1.0)
const COLOR_BORDER := Color(0.28, 0.31, 0.40, 1.0)
const COLOR_ACCENT := Color(0.42, 0.60, 0.95, 1.0)
const COLOR_TEXT := Color(0.93, 0.94, 0.97, 1.0)
const COLOR_TEXT_DIM := Color(0.62, 0.65, 0.73, 1.0)

static var _cached: Theme

static func get_theme() -> Theme:
	if _cached == null:
		_cached = _build()
	return _cached

static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15

	# Noto Sans JP (SIL OFL 1.1, no attribution required) — placeholder
	# typeface until real art direction lands; Godot's built-in editor font
	# has patchy CJK coverage, this one's a proper Japanese Sans face.
	var font_path := "res://assets/fonts/NotoSansJP-Variable.ttf"
	if ResourceLoader.exists(font_path):
		theme.default_font = load(font_path)

	var btn_normal := _style(COLOR_PANEL_RAISED, COLOR_BORDER, 8)
	var btn_hover := _style(COLOR_PANEL_RAISED.lightened(0.1), COLOR_ACCENT, 8)
	var btn_pressed := _style(COLOR_PANEL_RAISED.darkened(0.15), COLOR_ACCENT, 8)
	var btn_disabled := _style(COLOR_PANEL_RAISED.darkened(0.25), COLOR_BORDER.darkened(0.3), 8)

	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, btn_normal)
		theme.set_stylebox("hover", type_name, btn_hover)
		theme.set_stylebox("pressed", type_name, btn_pressed)
		theme.set_stylebox("disabled", type_name, btn_disabled)
		theme.set_color("font_color", type_name, COLOR_TEXT)
		theme.set_color("font_hover_color", type_name, COLOR_TEXT)
		theme.set_color("font_pressed_color", type_name, COLOR_TEXT)
		theme.set_color("font_disabled_color", type_name, COLOR_TEXT_DIM)
		# Our source icons are 128x128 SVGs — without this every dropdown/
		# button icon would render at full size instead of a small glyph.
		theme.set_constant("icon_max_width", type_name, 20)

	var panel_style := _style(COLOR_PANEL, COLOR_BORDER, 12)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	var bar_bg := _style(COLOR_PANEL_RAISED, COLOR_BORDER, 5)
	var bar_fill := _style(COLOR_ACCENT, COLOR_ACCENT, 5)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

	theme.set_color("font_color", "Label", COLOR_TEXT)
	theme.set_color("font_color", "CheckBox", COLOR_TEXT)

	return theme

static func _style(bg: Color, border: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Convenience: a rounded card background sized/positioned by the caller.
## Panel (not PanelContainer) never auto-resizes to its children, so this
## is safe to use anywhere a fixed-size backdrop is needed.
static func make_card(size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.theme = get_theme()
	panel.size = size
	return panel

## A card-ish style tinted by an arbitrary accent color (faction color,
## outcome color, etc.) — used to call out a selected/highlighted element
## without baking every faction's color into the shared theme itself.
static func accent_style(color: Color, radius: int = 8) -> StyleBoxFlat:
	return _style(color.darkened(0.75), color, radius, 2)
