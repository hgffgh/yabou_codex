class_name BattleVignette
extends CanvasLayer
## Short, skippable presentation of a CombatResolver result that already
## happened — the bars animate toward a precomputed end state, they never
## decide anything themselves. Built entirely in code, same pattern as the
## other screens (see UIUtils.fill_parent for why).

signal dismissed

const OUTCOME_TEXT := {
	0: "完全勝利",  # CombatResolver.Outcome.FULL_VICTORY
	1: "辛勝",      # MARGINAL_VICTORY
	2: "膠着",      # STALEMATE
	3: "敗北",      # DEFEAT
}

var _attacker_bar: ProgressBar
var _defender_bar: ProgressBar
var _outcome_label: Label
var _skip_button: Button
var _tween: Tween
var _entry: Dictionary

func setup(entry: Dictionary) -> void:
	_entry = entry
	layer = 10  # above the map's own CanvasLayer (default layer 1)

	var root := Control.new()
	add_child(root)
	UIUtils.fill_parent(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	root.add_child(dim)
	UIUtils.fill_parent(dim)

	var center := CenterContainer.new()
	root.add_child(center)
	UIUtils.fill_parent(center)

	var card := Control.new()
	card.custom_minimum_size = Vector2(560, 320)
	center.add_child(card)

	var card_bg := ColorRect.new()
	card_bg.color = Color(0.08, 0.08, 0.11, 0.98)
	card.add_child(card_bg)
	UIUtils.fill_parent(card_bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(512, 280)
	card.add_child(vbox)

	var region_name: String = GameState.region_defs[entry["region_id"]].display_name
	var title := Label.new()
	title.text = "%s で交戦" % region_name
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var attacker_fdef: FactionDef = GameState.faction_defs[entry["attacker_id"]]
	var defender_fdef: FactionDef = GameState.faction_defs[entry["defender_id"]]

	_attacker_bar = _build_side_row(vbox, "攻撃: " + attacker_fdef.display_name, attacker_fdef.color)
	_defender_bar = _build_side_row(vbox, "防御: " + defender_fdef.display_name, defender_fdef.color)

	_outcome_label = Label.new()
	_outcome_label.add_theme_font_size_override("font_size", 20)
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_label.text = " "
	vbox.add_child(_outcome_label)

	var button_center := CenterContainer.new()
	vbox.add_child(button_center)
	_skip_button = Button.new()
	_skip_button.text = "続ける"
	_skip_button.custom_minimum_size = Vector2(160, 40)
	_skip_button.pressed.connect(_on_skip_pressed)
	button_center.add_child(_skip_button)

	_play()

func _build_side_row(parent: VBoxContainer, label_text: String, color: Color) -> ProgressBar:
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 24)
	parent.add_child(bar)
	return bar

func _play() -> void:
	var attacker_before: int = max(_entry["attacker_before"], 1)
	var defender_before: int = max(_entry["defender_before"], 1)
	var attacker_fraction: float = float(_entry["attacker_after"]) / float(attacker_before)
	var defender_fraction: float = float(_entry["defender_after"]) / float(defender_before)

	_tween = create_tween()
	_tween.tween_property(_attacker_bar, "value", attacker_fraction, 1.2)
	_tween.parallel().tween_property(_defender_bar, "value", defender_fraction, 1.2)
	_tween.tween_callback(_show_outcome)

func _show_outcome() -> void:
	var outcome: int = _entry["outcome"]
	var text: String = OUTCOME_TEXT.get(outcome, "?")
	if _entry["captured"]:
		var attacker_fdef: FactionDef = GameState.faction_defs[_entry["attacker_id"]]
		text += "  ｜  %s が占領" % attacker_fdef.display_name
	_outcome_label.text = text

func _on_skip_pressed() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
		_attacker_bar.value = float(_entry["attacker_after"]) / float(max(_entry["attacker_before"], 1))
		_defender_bar.value = float(_entry["defender_after"]) / float(max(_entry["defender_before"], 1))
		_show_outcome()
		return
	dismissed.emit()
	queue_free()
