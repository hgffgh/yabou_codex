class_name ProductionPanel
extends CanvasLayer
## "生産は各拠点で行うように" -- production was previously only reachable by
## first clicking a region on the map that happened to have a facility;
## the 生産 rail button itself just showed a hint message pointing the
## player back at the map instead of being a real action, unlike every
## other root command (軍事/開発/外交/システム all open a real panel). This
## is the panel the "司令デッキ化計画" design proposal's own roadmap
## recommended giving production ("艦隊運用と同格の頻出操作なのでルートに
## 独立させる") but which the redesign pass before this one deliberately
## deferred. One card per production-capable region the player owns, each
## with its own live queue and unit picker -- so managing every base's
## production no longer requires hunting for the right node on the map
## first. Own CanvasLayer, dim background, centered card, matching every
## other overlay panel's shared style.

signal closed

const MAX_QUEUE_LENGTH := 5  # keep in sync with StrategicMap.MAX_PLAYER_QUEUE_LENGTH's intent

var _rows: VBoxContainer
var _status_label: Label

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

	var card := UITheme.make_card(Vector2(680, 640))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(632, 600)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "生産"
	UITheme.style_display_label(title, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(632, 500)
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	close_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CANCEL))
	vbox.add_child(close_button)

	_refresh()

func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()

	var can_act := TurnManager.current_phase == TurnManager.Phase.ORDERS \
		and TurnManager.active_faction_id == GameState.player_faction_id and not TurnManager.is_resolving_turn
	_status_label.text = "" if can_act else "生産の予約は自勢力の命令フェイズ中のみ可能です。"

	var region_ids := GameState.regions.keys()
	region_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var found_any := false
	for region_id: Variant in region_ids:
		var region: Region = GameState.regions[region_id]
		if region.owner_faction_id != GameState.player_faction_id:
			continue
		var facility_ids := GameState.production_facility_ids_for_region(region.def.id)
		if facility_ids.is_empty():
			continue
		found_any = true
		_rows.add_child(_build_region_card(region, facility_ids[0], can_act))

	if not found_any:
		var empty_label := Label.new()
		empty_label.text = "生産施設を持つ自勢力の拠点がありません。"
		empty_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(empty_label)

## One region's production card: name header, live queue (one row per
## queued job, matching StrategicMap's region-panel queue display), and a
## unit picker + reserve button. PanelContainer (not a bare Panel) so its
## height auto-fits the queue's variable row count instead of needing a
## hand-computed custom_minimum_size.y the way the fixed-shape cards
## elsewhere in this session's other panels do.
func _build_region_card(region: Region, facility_id: StringName, can_act: bool) -> PanelContainer:
	var player_fdef: FactionDef = GameState.faction_defs[GameState.player_faction_id]
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_RAISED
	style.border_color = player_fdef.color
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)

	var header := Label.new()
	header.text = region.def.display_name
	UITheme.style_display_label(header, 16)
	content.add_child(header)

	var queue := GameState.campaign_runtime.production_queues_by_facility_id.get(facility_id) as ProductionQueueState
	var queue_size := queue.job_ids.size() if queue != null else 0
	if queue_size == 0:
		var empty_queue_label := Label.new()
		empty_queue_label.text = UITheme.bracket("生産キュー: なし")
		UITheme.style_mono_label(empty_queue_label, 10)
		empty_queue_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		content.add_child(empty_queue_label)
	else:
		var queue_header := Label.new()
		queue_header.text = UITheme.bracket("QUEUE 生産キュー")
		UITheme.style_mono_label(queue_header, 10)
		queue_header.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		content.add_child(queue_header)
		for i in range(queue.job_ids.size()):
			var job := GameState.campaign_runtime.production_jobs_by_id[queue.job_ids[i]] as ProductionJobState
			var unit_def := GameState.master_data.units[job.unit_def_id] as UnitDef
			content.add_child(_build_queue_row(unit_def, job, i == 0))

	content.add_child(HSeparator.new())

	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 8)
	content.add_child(picker_row)

	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(380, 36)
	picker.clip_text = true
	picker.fit_to_longest_item = false
	var player_faction: Faction = GameState.get_faction(GameState.player_faction_id)
	var has_unlocked_option := false
	for uid in GameState.master_data.units:
		var udef: UnitDef = GameState.master_data.units[uid]
		if udef.faction_origin_id != player_faction.def.id:
			continue
		var unlocked := TechUnlock.is_unit_unlocked(player_faction, uid, GameState.master_data)
		var label := "%s（資金%d・物資%d）%s" % [
			tr(String(udef.display_name_key)),
			GameConstants.UNIT_PRODUCTION_FUNDS[udef.size],
			GameConstants.UNIT_PRODUCTION_MATERIALS[udef.size],
			"" if unlocked else "── 未解禁",
		]
		if udef.icon:
			picker.add_icon_item(udef.icon, label)
		else:
			picker.add_item(label)
		picker.set_item_metadata(picker.item_count - 1, uid)
		if unlocked:
			has_unlocked_option = true
		else:
			picker.set_item_disabled(picker.item_count - 1, true)
	picker_row.add_child(picker)

	var queue_full := queue_size >= MAX_QUEUE_LENGTH
	var can_produce := can_act and not queue_full and has_unlocked_option
	picker.disabled = not can_produce

	var reserve_button := Button.new()
	reserve_button.text = "生産を予約"
	reserve_button.custom_minimum_size = Vector2(120, 36)
	reserve_button.disabled = not can_produce
	reserve_button.pressed.connect(func():
		if picker.selected < 0:
			return
		var unit_id: StringName = picker.get_item_metadata(picker.selected)
		var result := GameState.queue_production(GameState.player_faction_id, facility_id, unit_id)
		if not result.errors.is_empty():
			_status_label.text = "生産登録に失敗しました: %s" % result.errors[0]
		else:
			var unit_def := GameState.master_data.units[unit_id] as UnitDef
			_status_label.text = "%s で %s の生産を登録しました。" % [region.def.display_name, tr(String(unit_def.display_name_key))]
		_refresh()
	)
	reserve_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CONFIRM))
	picker_row.add_child(reserve_button)

	return card

## Matches StrategicMap._build_queue_row exactly (name/fraction on top, a
## thin progress track below, only the head-of-queue job's track actually
## filled) -- duplicated rather than shared since that one is private to
## StrategicMap and tightly coupled to its own _production_queue_box.
func _build_queue_row(unit_def: UnitDef, job: ProductionJobState, is_head: bool) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	row.add_child(top)
	var name_label := Label.new()
	name_label.text = tr(String(unit_def.display_name_key))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not is_head:
		name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	top.add_child(name_label)
	var frac_label := Label.new()
	frac_label.text = "%d/%d" % [job.production_accumulated, job.production_required]
	UITheme.style_mono_label(frac_label, 12)
	frac_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	top.add_child(frac_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.max_value = float(job.production_required)
	bar.value = float(job.production_accumulated) if is_head else 0.0
	row.add_child(bar)
	return row

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
