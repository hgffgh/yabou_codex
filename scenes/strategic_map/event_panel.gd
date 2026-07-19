class_name EventPanel
extends CanvasLayer
## EVENT_DETAIL_SPECIFICATION.md sections 6/7: presents the player faction's
## pending_event_ids one at a time (already priority-sorted by
## GameState.check_pending_events), advancing through dialogue_entries with
## a "次へ" button, then choice_entries buttons (or a single acknowledge
## button for a choice-less event). Same overlay style as the other panels.
## Deliberately out of scope, matching every other panel's plain-UI-first
## approach in this codebase (no art assets exist yet): scene_background,
## portraits, fast-forward/auto-play/skip, and the read-log/回想 screen --
## see HANDOFF.md.

signal closed

var _faction_id: StringName
var _current_event_id: StringName = &""
var _dialogue_index: int = 0

var _title_label: Label
var _speaker_label: Label
var _body_label: Label
var _next_button: Button
var _choice_box: VBoxContainer

func setup(faction_id: StringName) -> void:
	_faction_id = faction_id
	layer = 10  # above the other overlay panels -- an event blocks everything else

	var root := Control.new()
	root.theme = UITheme.get_theme()
	add_child(root)
	UIUtils.fill_parent(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	UIUtils.fill_parent(dim)

	var center := CenterContainer.new()
	root.add_child(center)
	UIUtils.fill_parent(center)

	var card := UITheme.make_card(Vector2(640, 420))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(592, 380)
	card.add_child(vbox)

	_title_label = Label.new()
	UITheme.style_display_label(_title_label, 22)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_title_label)

	# The speaking character's name gets its own gold nameplate line instead
	# of being folded into the body text with a blank line -- a voice should
	# be identifiable before you've read a word of what it says. Bracketed
	# mono text ("[ 戦務参謀 ]") matches every other panel's caption
	# convention instead of reading as an ordinary sentence.
	_speaker_label = Label.new()
	UITheme.style_mono_label(_speaker_label, 12)
	_speaker_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	vbox.add_child(_speaker_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body_label.custom_minimum_size = Vector2(592, 200)
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vbox.add_child(_body_label)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_choice_box)

	_next_button = Button.new()
	_next_button.text = "次へ"
	_next_button.custom_minimum_size = Vector2(0, 40)
	_next_button.pressed.connect(_on_next_pressed)
	_next_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	vbox.add_child(_next_button)

	_load_next_pending_event()

## Advances to the next queued event, or closes the panel once
## pending_event_ids is empty for this faction.
func _load_next_pending_event() -> void:
	var faction := GameState.get_faction(_faction_id)
	if faction == null or faction.pending_event_ids.is_empty():
		closed.emit()
		queue_free()
		return
	_current_event_id = faction.pending_event_ids[0]
	_dialogue_index = 0
	var def := GameState.master_data.events.get(_current_event_id) as EventDef
	_title_label.text = tr(String(def.title_key)) if def != null else String(_current_event_id)
	_choice_box.visible = false
	_next_button.visible = true
	_show_current_dialogue_entry(def)

func _show_current_dialogue_entry(def: EventDef) -> void:
	if def == null or _dialogue_index >= def.dialogue_entries.size():
		_show_choices(def)
		return
	var entry := def.dialogue_entries[_dialogue_index] as Dictionary
	var speaker_key := StringName(entry.get("speaker_key", ""))
	_speaker_label.visible = not speaker_key.is_empty()
	_speaker_label.text = UITheme.bracket(tr(String(speaker_key))) if not speaker_key.is_empty() else ""
	_body_label.text = tr(String(entry.get("body_key", "")))

func _on_next_pressed() -> void:
	var def := GameState.master_data.events.get(_current_event_id) as EventDef
	_dialogue_index += 1
	_show_current_dialogue_entry(def)

## EVENT_DETAIL_SPECIFICATION.md section 7: "選択肢到達時に早送り・スキップ
## を停止する" -- once choices are showing, _next_button (the only
## fast-forward-equivalent control this UI has) is hidden, so the player
## must make an explicit choice.
func _show_choices(def: EventDef) -> void:
	_next_button.visible = false
	_choice_box.visible = true
	for child in _choice_box.get_children():
		child.queue_free()
	if def == null or def.choice_entries.is_empty():
		var ack := Button.new()
		ack.text = "確認"
		ack.custom_minimum_size = Vector2(0, 40)
		ack.pressed.connect(_on_choice_pressed.bind(&""))
		UITheme.style_primary_button(ack)
		_choice_box.add_child(ack)
		return
	for choice_value: Variant in def.choice_entries:
		var choice := choice_value as Dictionary
		var choice_text := tr(String(choice.get("label_key", "")))
		var button := Button.new()
		button.text = "－  %s" % choice_text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		# A plain dash reads as inert list text; swapping it for a gold arrow
		# on hover is the only cue (besides the button's own underline) that
		# this line is the one about to be chosen -- mirrors the design
		# reference's "－" → "▸" hover swap.
		button.mouse_entered.connect(func() -> void:
			button.text = "▸  %s" % choice_text
			button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		)
		button.mouse_exited.connect(func() -> void:
			button.text = "－  %s" % choice_text
			button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		)
		button.pressed.connect(_on_choice_pressed.bind(StringName(choice.get("id", ""))))
		button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
		_choice_box.add_child(button)

func _on_choice_pressed(choice_id: StringName) -> void:
	GameState.resolve_event_choice(_faction_id, _current_event_id, choice_id)
	_load_next_pending_event()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
