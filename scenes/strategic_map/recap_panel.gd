class_name RecapPanel
extends CanvasLayer
## EVENT_DETAIL_SPECIFICATION.md sections 6/9's 回想 screen, the one piece
## the event-system milestone deliberately left unbuilt (see EventPanel's own
## doc comment and HANDOFF.md): browses ProfileState.viewed_event_ids (every
## MAIN event ever resolved across campaigns, plus any once_per_profile SUB
## event) and this campaign's own CampaignRuntimeState.campaign_event_history
## (every SUB event resolved this campaign, in resolution order, cleared on
## a new campaign). Read-only, matching EncyclopediaPanel -- no
## _status_label, no can_act gating. The chosen option for a choice-bearing
## event only shows when it was resolved *this* campaign -- Faction.event_flags
## resets each new campaign, so a recap entry left over from an earlier
## playthrough has nothing to look up.

signal closed

func setup(faction_id: StringName) -> void:
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

	var card := UITheme.make_card(Vector2(640, 620))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(24, 20)
	vbox.size = Vector2(592, 580)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "回想"
	UITheme.style_display_label(title, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var faction := GameState.get_faction(faction_id)

	vbox.add_child(_section_header("主要イベント"))
	var main_scroll := ScrollContainer.new()
	main_scroll.custom_minimum_size = Vector2(592, 220)
	vbox.add_child(main_scroll)
	var main_rows := VBoxContainer.new()
	main_rows.add_theme_constant_override("separation", 8)
	main_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.add_child(main_rows)
	var main_ids := GameState.profile.viewed_event_ids.duplicate()
	main_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	if main_ids.is_empty():
		main_rows.add_child(_empty_label("まだ主要イベントは発生していません。"))
	else:
		for event_id: StringName in main_ids:
			main_rows.add_child(_build_recap_row(event_id, faction))

	vbox.add_child(_section_header("今回の履歴（補助イベント）"))
	var sub_scroll := ScrollContainer.new()
	sub_scroll.custom_minimum_size = Vector2(592, 220)
	vbox.add_child(sub_scroll)
	var sub_rows := VBoxContainer.new()
	sub_rows.add_theme_constant_override("separation", 8)
	sub_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_scroll.add_child(sub_rows)
	var sub_ids: Array[StringName] = GameState.campaign_runtime.campaign_event_history
	if sub_ids.is_empty():
		sub_rows.add_child(_empty_label("今回のキャンペーンではまだ補助イベントが発生していません。"))
	else:
		for event_id: StringName in sub_ids:
			sub_rows.add_child(_build_recap_row(event_id, faction))

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(_on_close_pressed)
	close_button.pressed.connect(AudioManager.play_sfx.bind(AudioManager.SFX_CANCEL))
	vbox.add_child(close_button)

func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = UITheme.bracket(text)
	UITheme.style_display_label(label, 15)
	label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	return label

func _empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## One row: a 主要/補助 badge plus the event's title in its origin faction's
## color, and (only when resolvable) a dim second line naming the choice
## actually made.
func _build_recap_row(event_id: StringName, faction: Faction) -> Control:
	var def := GameState.master_data.events.get(event_id) as EventDef
	var fdef: FactionDef = GameState.faction_defs.get(def.faction_id) if def != null else null
	var faction_color := fdef.color if fdef != null else UITheme.COLOR_TEXT
	var is_main := def != null and def.importance == GameEnums.EventImportance.MAIN

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	wrapper.add_child(head_row)

	var badge := Label.new()
	badge.text = UITheme.bracket("主要" if is_main else "補助")
	UITheme.style_mono_label(badge, 10)
	badge.add_theme_color_override("font_color", UITheme.COLOR_GOLD if is_main else UITheme.COLOR_TEXT_DIM)
	badge.custom_minimum_size = Vector2(44, 0)
	head_row.add_child(badge)

	var title_label := Label.new()
	title_label.text = tr(String(def.title_key)) if def != null else String(event_id)
	title_label.add_theme_color_override("font_color", faction_color)
	head_row.add_child(title_label)

	if def != null and faction != null:
		var choice_id := StringName(faction.event_flags.get(StringName("choice:%s" % event_id), ""))
		if not choice_id.is_empty():
			for choice_value: Variant in def.choice_entries:
				var choice := choice_value as Dictionary
				if StringName(choice.get("id", "")) == choice_id:
					var choice_label := Label.new()
					choice_label.text = "選択：%s" % tr(String(choice.get("label_key", "")))
					choice_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
					wrapper.add_child(choice_label)
					break

	return wrapper

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
