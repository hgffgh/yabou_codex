class_name EncyclopediaPanel
extends CanvasLayer
## DATA_DEFINITION.md section 24: browses ProfileState.encyclopedia_unit_ids/
## encyclopedia_weapon_ids/encyclopedia_pilot_ids, grown by GameState.
## register_encyclopedia_for_squad. Every UnitDef/WeaponDef/PilotDef in the
## master data is listed; an unregistered entry shows as "未確認" with its
## details hidden. Read-only (no actions), so it's simpler than the other
## overlay panels: no _status_label, no can_act gating.
##
## Cards with mini stat gauges instead of one concatenated-prose Label per
## entry ("わかりやすくゲージなどに変更してほしい" -- the flat text rows
## were hard to scan at a glance). Every gauge row uses plain absolute
## position/size for its caption/value Labels (never
## SIZE_EXPAND_FILL + horizontal_alignment = RIGHT, and never anchors) --
## see StrategicMap._build_info_row's long comment for why: confirmed live
## that combination renders fully invisible at this nesting depth in this
## Godot version. CARD_WIDTH is `rows`' own known fixed width (592, matching
## the scroll/vbox chain below), used the same way every other panel this
## session hardcodes a known container width instead of querying it.

signal closed

const CARD_WIDTH := 592.0
const CARD_MARGIN := 14.0
const COL_WIDTH := (CARD_WIDTH - CARD_MARGIN * 2.0 - 12.0) / 2.0

func setup() -> void:
	layer = 9

	var root := Control.new()
	root.theme = UITheme.get_theme()
	add_child(root)
	UIUtils.fill_parent(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	UIUtils.fill_parent(dim)

	var center := CenterContainer.new()
	root.add_child(center)
	UIUtils.fill_parent(center)

	var card := UITheme.make_card(Vector2(680, 680))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(632, 640)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "図鑑"
	UITheme.style_display_label(title, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var summary := Label.new()
	UITheme.style_mono_label(summary, 12)
	summary.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.text = UITheme.bracket("機体 %d/%d ・ 武器 %d/%d ・ パイロット %d/%d" % [
		GameState.profile.encyclopedia_unit_ids.size(), GameState.master_data.units.size(),
		GameState.profile.encyclopedia_weapon_ids.size(), GameState.master_data.weapons.size(),
		GameState.profile.encyclopedia_pilot_ids.size(), GameState.master_data.pilots.size(),
	])
	vbox.add_child(summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(632, 560)
	vbox.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	rows.add_child(_section_header("機体 UNITS"))
	for id: StringName in _sorted_keys(GameState.master_data.units):
		rows.add_child(_build_unit_card(id))
	rows.add_child(_section_header("武器 WEAPONS"))
	for id: StringName in _sorted_keys(GameState.master_data.weapons):
		rows.add_child(_build_weapon_card(id))
	rows.add_child(_section_header("パイロット PILOTS"))
	for id: StringName in _sorted_keys(GameState.master_data.pilots):
		rows.add_child(_build_pilot_card(id))

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)

func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = UITheme.bracket(text)
	UITheme.style_display_label(label, 15)
	label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	return label

## Card shell shared by all three entry kinds: a hairline-bordered Panel with
## a top accent strip, sized by an explicit custom_minimum_size.y (Panel
## isn't a Container, so nothing auto-fits it to its children the way a
## VBoxContainer would). Callers add their own header/gauge children at
## absolute positions inside it.
func _build_card(height: float, accent_color: Color) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(0, height)
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_RAISED
	style.border_color = UITheme.COLOR_BORDER
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)
	var accent := ColorRect.new()
	accent.position = Vector2(0, 0)
	accent.size = Vector2(CARD_WIDTH, 3)
	accent.color = accent_color
	card.add_child(accent)
	return card

## An icon-glyph + name header, common to every card kind. `subtitle` is a
## dim mono line under the name (faction, size/role, or level).
func _build_card_header(card: Panel, glyph: StringName, glyph_color: Color, name_text: String, subtitle: String, name_color: Color) -> void:
	var icon := HudIcon.new()
	icon.position = Vector2(CARD_MARGIN, 12.0)
	icon.size = Vector2(28, 28)
	icon.glyph = glyph
	icon.glyph_color = glyph_color
	card.add_child(icon)

	var name_label := Label.new()
	name_label.position = Vector2(CARD_MARGIN + 40.0, 8.0)
	name_label.size = Vector2(CARD_WIDTH - CARD_MARGIN * 2.0 - 40.0, 22)
	UITheme.style_display_label(name_label, 15)
	name_label.add_theme_color_override("font_color", name_color)
	name_label.text = name_text
	card.add_child(name_label)

	var subtitle_label := Label.new()
	subtitle_label.position = Vector2(CARD_MARGIN + 40.0, 28.0)
	subtitle_label.size = Vector2(CARD_WIDTH - CARD_MARGIN * 2.0 - 40.0, 16)
	UITheme.style_mono_label(subtitle_label, 10.5)
	subtitle_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	subtitle_label.text = subtitle
	card.add_child(subtitle_label)

## One labeled mini-gauge: caption on the left, a thin ProgressBar, and a
## right-aligned numeric readout -- all at explicit absolute positions (see
## this file's own top-of-file note on why, not size_flags/anchors).
func _build_gauge(card: Panel, x: float, y: float, width: float, caption: String, value: float, max_value: float, color: Color, value_text: String) -> void:
	var caption_label := Label.new()
	caption_label.position = Vector2(x, y)
	caption_label.size = Vector2(48, 16)
	UITheme.style_mono_label(caption_label, 10)
	caption_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	caption_label.text = caption
	card.add_child(caption_label)

	var value_label := Label.new()
	value_label.position = Vector2(x + width - 44.0, y)
	value_label.size = Vector2(44, 16)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.style_mono_label(value_label, 10)
	value_label.text = value_text
	card.add_child(value_label)

	var track := ProgressBar.new()
	track.position = Vector2(x + 50.0, y + 2.0)
	track.size = Vector2(width - 50.0 - 48.0, 6)
	track.show_percentage = false
	track.max_value = maxf(1.0, max_value)
	track.value = clampf(value, 0.0, max_value)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	track.add_theme_stylebox_override("fill", fill_style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UITheme.COLOR_PANEL
	track.add_theme_stylebox_override("background", bg_style)
	card.add_child(track)

func _unknown_card(label_text: String) -> Panel:
	var card := _build_card(56.0, UITheme.COLOR_BORDER)
	var label := Label.new()
	label.position = Vector2(CARD_MARGIN, 18.0)
	label.size = Vector2(CARD_WIDTH - CARD_MARGIN * 2.0, 20)
	label.text = label_text
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	card.add_child(label)
	return card

func _build_unit_card(id: StringName) -> Panel:
	if not GameState.profile.encyclopedia_unit_ids.has(id):
		return _unknown_card("？？？ (未確認)")
	var def: UnitDef = GameState.master_data.units[id]
	var fdef: FactionDef = GameState.faction_defs.get(def.faction_origin_id)
	var faction_color := fdef.color if fdef != null else UITheme.COLOR_TEXT
	var card := _build_card(102.0, faction_color)
	_build_card_header(
		card, &"hex", faction_color,
		tr(String(def.display_name_key)),
		fdef.display_name if fdef != null else String(def.faction_origin_id),
		faction_color,
	)
	var row_y := 56.0
	_build_gauge(card, CARD_MARGIN, row_y, COL_WIDTH, "HP", def.max_hp, 5000.0, UITheme.COLOR_GOOD, str(def.max_hp))
	_build_gauge(card, CARD_MARGIN + COL_WIDTH + 12.0, row_y, COL_WIDTH, "EN", def.max_en, 500.0, faction_color, str(def.max_en))
	_build_gauge(card, CARD_MARGIN, row_y + 22.0, COL_WIDTH, "火力", def.firepower, 400.0, UITheme.COLOR_GOLD, str(def.firepower))
	_build_gauge(card, CARD_MARGIN + COL_WIDTH + 12.0, row_y + 22.0, COL_WIDTH, "装甲", def.armor, 600.0, UITheme.COLOR_TEXT_DIM.lightened(0.3), str(def.armor))
	return card

func _build_weapon_card(id: StringName) -> Panel:
	if not GameState.profile.encyclopedia_weapon_ids.has(id):
		return _unknown_card("？？？ (未確認)")
	var def: WeaponDef = GameState.master_data.weapons[id]
	var card := _build_card(80.0, UITheme.COLOR_GOLD)
	_build_card_header(
		card, &"diamond", UITheme.COLOR_GOLD,
		tr(String(def.display_name_key)),
		"射程 %d〜%dm" % [int(def.min_range_m), int(def.max_range_m)],
		UITheme.COLOR_TEXT,
	)
	var row_y := 56.0
	_build_gauge(card, CARD_MARGIN, row_y, COL_WIDTH, "威力", def.total_power, 1000.0, UITheme.COLOR_DANGER, str(def.total_power))
	_build_gauge(card, CARD_MARGIN + COL_WIDTH + 12.0, row_y, COL_WIDTH, "命中", def.base_accuracy_pct, 100.0, UITheme.COLOR_GOOD, "%d%%" % def.base_accuracy_pct)
	return card

func _build_pilot_card(id: StringName) -> Panel:
	if not GameState.profile.encyclopedia_pilot_ids.has(id):
		return _unknown_card("？？？ (未確認)")
	var def: PilotDef = GameState.master_data.pilots[id]
	var fdef: FactionDef = GameState.faction_defs.get(def.faction_id)
	var faction_color := fdef.color if fdef != null else UITheme.COLOR_TEXT
	var card := _build_card(124.0, faction_color)
	_build_card_header(
		card, &"square", faction_color,
		tr(String(def.display_name_key)),
		"%s ／ 初期レベル%d" % [fdef.display_name if fdef != null else String(def.faction_id), def.initial_level],
		faction_color,
	)
	var row_y := 56.0
	_build_gauge(card, CARD_MARGIN, row_y, COL_WIDTH, "射撃", def.initial_shooting, 200.0, UITheme.COLOR_GOOD, str(def.initial_shooting))
	_build_gauge(card, CARD_MARGIN + COL_WIDTH + 12.0, row_y, COL_WIDTH, "格闘", def.initial_melee, 200.0, UITheme.COLOR_DANGER, str(def.initial_melee))
	_build_gauge(card, CARD_MARGIN, row_y + 22.0, COL_WIDTH, "防御", def.initial_defense, 200.0, faction_color, str(def.initial_defense))
	_build_gauge(card, CARD_MARGIN + COL_WIDTH + 12.0, row_y + 22.0, COL_WIDTH, "反応", def.initial_reaction, 200.0, UITheme.COLOR_GOLD, str(def.initial_reaction))
	_build_gauge(card, CARD_MARGIN, row_y + 44.0, COL_WIDTH, "指揮", def.initial_command, 200.0, UITheme.COLOR_TEXT_DIM.lightened(0.3), str(def.initial_command))
	return card

func _sorted_keys(entries: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: Variant in entries:
		ids.append(StringName(id))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
