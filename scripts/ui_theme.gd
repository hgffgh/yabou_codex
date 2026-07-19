class_name UITheme
extends RefCounted
## Single shared Theme so every screen's buttons/panels/bars look like one
## system instead of ad-hoc per-screen styling. Built once in code (not a
## hand-authored .tres — see UIUtils for why we avoid hand-authoring Godot
## resource internals where a script can do it more reliably) and cached.
##
## "Command Deck" palette: a deep navy void instead of near-black, hairline
## (low-alpha) borders instead of solid gray boxes, sharp corners instead of
## rounded ones, and exactly one warm accent (COLOR_GOLD) used everywhere
## something is interactive or belongs to the player — never several accent
## colors glowing on screen at once. Faction identity (Nova blue / Crimson
## red) stays with each FactionDef.color and is applied by the caller, not
## baked in here, so this file has one job: make every screen read as the
## same console.

const COLOR_BG := Color(0.039, 0.078, 0.125, 1.0)
const COLOR_PANEL := Color(0.063, 0.098, 0.145, 0.97)
const COLOR_PANEL_RAISED := Color(0.09, 0.135, 0.19, 1.0)
const COLOR_BORDER := Color(0.62, 0.82, 1.0, 0.22)
const COLOR_ACCENT := Color(1.0, 0.85, 0.25, 1.0)  # kept as the internal button/bar default; see COLOR_GOLD
const COLOR_TEXT := Color(0.89, 0.93, 0.97, 1.0)
const COLOR_TEXT_DIM := Color(0.78, 0.87, 0.95, 0.6)

## The one warm accent: "this is yours" / "this is actionable". Deliberately
## identical to RegionNodeView.PLAYER_RING_COLOR (kept as a separate literal
## rather than a cross-reference so this low-level theme file never depends
## on a specific scene script) — one gold, not two, whether the player is
## looking at the map ring or a button border.
const COLOR_GOLD := Color(1.0, 0.85, 0.25, 1.0)
const COLOR_GOOD := Color(0.42, 0.78, 0.6, 1.0)
const COLOR_DANGER := Color(0.85, 0.35, 0.35, 1.0)

const NOTO_SANS_JP_PATH := "res://assets/fonts/NotoSansJP-Variable.ttf"

static var _cached: Theme
static var _display_font: Font
static var _mono_font: Font

static func get_theme() -> Theme:
	if _cached == null:
		_cached = _build()
	return _cached

## Condensed display face for headings/nameplates (region names, pilot
## names, event titles, faction headers) -- everything the design reference
## calls out as "Display" role text. `SystemFont` walks this name list per
## platform: Bahnschrift is Windows' own bundled condensed grotesk (the
## reference's literal pick) and is not redistributable, so other platforms
## fall through to whatever condensed-ish system sans is present, and
## finally to the bundled Noto Sans JP so headings never silently render in
## the engine's default fallback face or lose CJK coverage.
static func get_display_font() -> Font:
	if _display_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Bahnschrift", "Yu Gothic UI", "Hiragino Sans", "Segoe UI Semibold", "Segoe UI"])
		sf.font_weight = 700
		sf.font_stretch = 75  # condensed
		if ResourceLoader.exists(NOTO_SANS_JP_PATH):
			sf.fallbacks = [load(NOTO_SANS_JP_PATH)]
		_display_font = sf
	return _display_font

## Tabular-numeral face for data readouts (FUNDS 3,420 / EXP 1,240/1,800) --
## the reference's "Data / Mono" role. Same fallback reasoning as
## get_display_font(): a system monospace name list, then Noto Sans JP so
## any CJK text that ends up in a mono-styled label still renders.
static func get_mono_font() -> Font:
	if _mono_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Cascadia Mono", "Cascadia Code", "Consolas", "SF Mono", "Courier New"])
		if ResourceLoader.exists(NOTO_SANS_JP_PATH):
			sf.fallbacks = [load(NOTO_SANS_JP_PATH)]
		_mono_font = sf
	return _mono_font

## Wraps caption text in the reference's "[ LABEL ]" bracket convention --
## used instead of a filled pill/box to mark a piece of data as a labeled
## readout rather than prose.
static func bracket(text: String) -> String:
	return "[ %s ]" % text

## Applies the condensed display face to one label at a given size -- the
## font alone (not a whole theme type override) since only specific
## "marquee" labels (names, titles) use it, not every Label on screen.
static func style_display_label(label: Label, size: int = 17) -> void:
	label.add_theme_font_override("font", get_display_font())
	label.add_theme_font_size_override("font_size", size)

## Applies the tabular-numeral mono face to one label -- for numeric/data
## readouts that should line up (funds, EXP fractions, percentages).
static func style_mono_label(label: Label, size: int = 15) -> void:
	label.add_theme_font_override("font", get_mono_font())
	label.add_theme_font_size_override("font_size", size)

static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15

	# Noto Sans JP (SIL OFL 1.1, no attribution required) — placeholder
	# typeface until real art direction lands; Godot's built-in editor font
	# has patchy CJK coverage, this one's a proper Japanese Sans face.
	var font_path := "res://assets/fonts/NotoSansJP-Variable.ttf"
	if ResourceLoader.exists(font_path):
		theme.default_font = load(font_path)

	# Buttons read as text with a hairline underline, not a filled box: the
	# underline is gold-bright on hover/press so "this is interactive"
	# always shows through the same one accent, and disabled just dims the
	# line rather than graying out a whole card.
	var btn_normal := _underline_style(COLOR_BORDER, 0.0)
	var btn_hover := _underline_style(COLOR_GOLD, 0.35)
	var btn_pressed := _underline_style(COLOR_GOLD, 0.55)
	var btn_disabled := _underline_style(COLOR_BORDER.darkened(0.3), 0.0)

	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, btn_normal)
		theme.set_stylebox("hover", type_name, btn_hover)
		theme.set_stylebox("pressed", type_name, btn_pressed)
		theme.set_stylebox("disabled", type_name, btn_disabled)
		theme.set_color("font_color", type_name, COLOR_TEXT_DIM)
		theme.set_color("font_hover_color", type_name, COLOR_TEXT)
		theme.set_color("font_pressed_color", type_name, COLOR_TEXT)
		theme.set_color("font_disabled_color", type_name, COLOR_TEXT_DIM.darkened(0.35))
		# Our source icons are 128x128 SVGs — without this every dropdown/
		# button icon would render at full size instead of a small glyph.
		theme.set_constant("icon_max_width", type_name, 20)

	var panel_style := _style(COLOR_PANEL, COLOR_BORDER, 0)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	var bar_bg := _style(COLOR_PANEL_RAISED, COLOR_BORDER, 0)
	var bar_fill := _style(COLOR_ACCENT, COLOR_ACCENT, 0)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

	# Every existing HSeparator/VSeparator across every panel (built with the
	# bare Godot default: a thick, fairly bright line) becomes a 1px hairline
	# for free through this one override — no need to touch each panel's own
	# `HSeparator.new()` call sites individually.
	var sep_h := StyleBoxLine.new()
	sep_h.color = COLOR_BORDER
	sep_h.thickness = 1
	theme.set_stylebox("separator", "HSeparator", sep_h)
	var sep_v := StyleBoxLine.new()
	sep_v.color = COLOR_BORDER
	sep_v.thickness = 1
	sep_v.vertical = true
	theme.set_stylebox("separator", "VSeparator", sep_v)

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

## A near-transparent box with a border on the bottom edge only — the
## restrained "text with a hairline rule" button look instead of a filled,
## rounded box. `fill_alpha` is the only thing that changes between the
## normal/hover/pressed variants: a faint wash on top of the same shape,
## never a different silhouette.
static func _underline_style(line_color: Color, fill_alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COLOR_PANEL_RAISED.r, COLOR_PANEL_RAISED.g, COLOR_PANEL_RAISED.b, fill_alpha)
	sb.border_color = line_color
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Convenience: a card background sized/positioned by the caller. Panel (not
## PanelContainer) never auto-resizes to its children, so this is safe to
## use anywhere a fixed-size backdrop is needed — including directly inside
## a CenterContainer, which is why custom_minimum_size is set here too: a
## bare Panel reports a (0,0) minimum size, so CenterContainer was silently
## shrinking the card to a point and only centering *that*, leaving its
## absolutely-positioned children (built by the caller) rendering
## off-center toward the bottom-right instead of the whole card being
## centered as a block.
static func make_card(size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.theme = get_theme()
	panel.custom_minimum_size = size
	panel.size = size
	return panel

## A card-ish style tinted by an arbitrary accent color (faction color,
## outcome color, etc.) — used to call out a selected/highlighted element
## without baking every faction's color into the shared theme itself.
static func accent_style(color: Color, radius: int = 0) -> StyleBoxFlat:
	return _style(color.darkened(0.75), color, radius, 2)

## Promotes a button to the one "primary action" look: always-gold border
## and text instead of only lighting up gold on hover. Meant for exactly one
## button per screen (turn end, confirm, etc.) — using it on more than one
## defeats the point of having a single accent mean "the important thing".
static func style_primary_button(button: Button) -> void:
	var normal := _underline_style(COLOR_GOLD, 0.12)
	var hover := _underline_style(COLOR_GOLD, 0.3)
	var pressed := _underline_style(COLOR_GOLD, 0.45)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", COLOR_GOLD)
	button.add_theme_color_override("font_hover_color", COLOR_GOLD)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)

## The destructive counterpart to style_primary_button(): always-red border
## and text for an irreversible/adversarial action (breaking a treaty,
## discarding a save). Same "one accent, always-on instead of only on
## hover" shape, just COLOR_DANGER instead of COLOR_GOLD.
static func style_danger_button(button: Button) -> void:
	var normal := _underline_style(COLOR_DANGER, 0.1)
	var hover := _underline_style(COLOR_DANGER, 0.28)
	var pressed := _underline_style(COLOR_DANGER, 0.4)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", COLOR_DANGER)
	button.add_theme_color_override("font_hover_color", COLOR_DANGER)
	button.add_theme_color_override("font_pressed_color", COLOR_DANGER)

## Steps a Label's displayed integer from from_value to to_value over ~0.45s
## instead of the text just silently changing, then settles from a bright
## flash back to white -- the "numbers are alive" requirement, extending
## _flash_label's existing "changes are events, not silent text swaps"
## pattern (see StrategicMap) to the value itself. `node` supplies the tree
## context create_tween() needs (UITheme is a bare RefCounted, not a Node).
## Safe to call every refresh: a no-op text set when the value hasn't moved.
static func animate_value(node: Node, label: Label, from_value: int, to_value: int, prefix: String = "", suffix: String = "") -> void:
	if from_value == to_value:
		label.text = "%s%d%s" % [prefix, to_value, suffix]
		return
	label.text = "%s%d%s" % [prefix, from_value, suffix]
	var tween := node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(
		func(v: float) -> void: label.text = "%s%d%s" % [prefix, int(round(v)), suffix],
		float(from_value), float(to_value), 0.45
	)
	var flash := COLOR_GOLD if to_value > from_value else COLOR_DANGER
	label.modulate = Color(flash.r * 1.5, flash.g * 1.5, flash.b * 1.5, 1.0)
	var flash_tween := node.create_tween()
	flash_tween.tween_property(label, "modulate", Color.WHITE, 0.5)
