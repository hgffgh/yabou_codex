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

	var card := UITheme.make_card(Vector2(560, 520))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(512, 480)
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
	scroll.custom_minimum_size = Vector2(512, 380)
	vbox.add_child(scroll)
	_slot_rows = VBoxContainer.new()
	_slot_rows.add_theme_constant_override("separation", 6)
	_slot_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slot_rows)

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

	if not can_save:
		_status_label.text = "セーブは自勢力の命令フェイズ中のみ可能です。ロードはいつでも可能です。"
	else:
		_status_label.text = ""

func _on_save_pressed(slot: int) -> void:
	var errors: PackedStringArray = TurnManager.save_game(slot)
	_status_label.text = "セーブしました: スロット%d" % slot if errors.is_empty() else "セーブ失敗: %s" % errors[0]
	_refresh()

func _on_load_pressed(slot: int) -> void:
	var errors: PackedStringArray = TurnManager.load_game(slot)
	if errors.is_empty():
		closed.emit()
		queue_free()
	else:
		_status_label.text = "ロード失敗: %s" % errors[0]

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
