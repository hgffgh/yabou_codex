class_name SaveLoadPanel
extends CanvasLayer
## Manual save/load slot picker. DATA_DEFINITION.md section 26.2: saving is
## only ever possible during the player's own strategy phase
## (TurnManager.can_save_now() enforces this); loading has no such
## restriction. Same overlay pattern as DevelopmentPanel — own CanvasLayer,
## dim background, centered card.

signal closed

const SLOT_COUNT := 10

var _status_label: Label
var _slot_rows: VBoxContainer
var _autosave_rows: VBoxContainer

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

	var card := UITheme.make_card(Vector2(560, 640))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(512, 600)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "セーブ / ロード"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(512, 320)
	vbox.add_child(scroll)
	_slot_rows = VBoxContainer.new()
	_slot_rows.add_theme_constant_override("separation", 6)
	_slot_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slot_rows)

	## SYSTEM_DETAIL_SPECIFICATION.md section 2.2: "手動・オートを別一覧で
	## 表示する". Autosaves are load-only from this panel -- they're only
	## ever written automatically by TurnManager._autosave.
	var autosave_title := Label.new()
	autosave_title.text = "オートセーブ"
	autosave_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(autosave_title)
	_autosave_rows = VBoxContainer.new()
	_autosave_rows.add_theme_constant_override("separation", 6)
	_autosave_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_autosave_rows)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)

	_refresh()

func _refresh() -> void:
	for child in _slot_rows.get_children():
		child.queue_free()
	var slots_by_number := {}
	for entry: Dictionary in TurnManager.list_save_slots():
		slots_by_number[int(entry.slot)] = entry

	var can_save := TurnManager.can_save_now()
	for slot in range(SLOT_COUNT):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var label := Label.new()
		label.custom_minimum_size = Vector2(320, 0)
		if slots_by_number.has(slot):
			var entry: Dictionary = slots_by_number[slot]
			var fdef: FactionDef = GameState.faction_defs.get(entry.player_faction_id)
			var faction_name := fdef.display_name if fdef != null else String(entry.player_faction_id)
			var datetime := Time.get_datetime_string_from_unix_time(int(entry.saved_at_unix), true)
			label.text = "スロット%d: ターン%d / %s / %s" % [slot, int(entry.turn_number), faction_name, datetime]
		else:
			label.text = "スロット%d: (空)" % slot
		row.add_child(label)

		var save_button := Button.new()
		save_button.text = "セーブ"
		save_button.custom_minimum_size = Vector2(80, 36)
		save_button.disabled = not can_save
		save_button.pressed.connect(_on_save_pressed.bind(slot))
		row.add_child(save_button)

		var load_button := Button.new()
		load_button.text = "ロード"
		load_button.custom_minimum_size = Vector2(80, 36)
		load_button.disabled = not slots_by_number.has(slot)
		load_button.pressed.connect(_on_load_pressed.bind(slot))
		row.add_child(load_button)

		_slot_rows.add_child(row)

	for child in _autosave_rows.get_children():
		child.queue_free()
	var autosaves_by_number := {}
	for entry: Dictionary in TurnManager.list_save_slots(true):
		autosaves_by_number[int(entry.slot)] = entry
	for slot in range(TurnManager.AUTOSAVE_SLOT_COUNT):
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 10)
		arow.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var alabel := Label.new()
		alabel.custom_minimum_size = Vector2(400, 0)
		if autosaves_by_number.has(slot):
			var entry: Dictionary = autosaves_by_number[slot]
			var fdef: FactionDef = GameState.faction_defs.get(entry.player_faction_id)
			var faction_name := fdef.display_name if fdef != null else String(entry.player_faction_id)
			var datetime := Time.get_datetime_string_from_unix_time(int(entry.saved_at_unix), true)
			alabel.text = "オート%d: ターン%d / %s / %s" % [slot, int(entry.turn_number), faction_name, datetime]
		else:
			alabel.text = "オート%d: (空)" % slot
		arow.add_child(alabel)

		var aload_button := Button.new()
		aload_button.text = "ロード"
		aload_button.custom_minimum_size = Vector2(80, 36)
		aload_button.disabled = not autosaves_by_number.has(slot)
		aload_button.pressed.connect(_on_load_pressed.bind(slot, true))
		arow.add_child(aload_button)

		_autosave_rows.add_child(arow)

	if not can_save:
		_status_label.text = "セーブは自勢力の命令フェイズ中のみ可能です。ロードはいつでも可能です。"
	else:
		_status_label.text = ""

## _refresh() itself sets _status_label to the phase-gating hint or "", so
## the result message below must be applied *after* it -- setting it first
## would just get immediately clobbered.
func _on_save_pressed(slot: int) -> void:
	var errors: PackedStringArray = TurnManager.save_game(slot)
	_refresh()
	_status_label.text = "セーブしました: スロット%d" % slot if errors.is_empty() else "セーブ失敗: %s" % errors[0]

func _on_load_pressed(slot: int, auto: bool = false) -> void:
	var errors: PackedStringArray = TurnManager.load_game(slot, auto)
	if errors.is_empty():
		closed.emit()
		queue_free()
	else:
		_status_label.text = "ロード失敗: %s" % errors[0]

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
