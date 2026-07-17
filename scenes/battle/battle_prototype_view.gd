class_name BattlePrototypeView
extends CanvasLayer

const ARENA_SIZE := Vector2(1200.0, 900.0)
const FORMATION_OFFSETS := [
	Vector3(-42, 0, -25), Vector3(0, 0, -38), Vector3(42, 0, -25),
	Vector3(-25, 0, 35), Vector3(25, 0, 35),
]

var battle: BattleRuntimeState
var selected_squad_id: StringName = &""
var arena: SubViewportContainer
var battle_viewport: SubViewport
var world_root: Node3D
var camera: Camera3D
var status_label: Label
var squad_visuals: Dictionary = {}
var selection_markers: Dictionary = {}
var control_point_labels: Dictionary = {}
var control_point_materials: Dictionary = {}
var unit_visuals: Dictionary = {}
var hp_bar_fills: Dictionary = {}
var en_bar_fills: Dictionary = {}
var transient_effects: Array[Dictionary] = []
var processed_combat_event_count := 0
var prebattle_panel: PanelContainer
var prebattle_summary: Label
var policy_selector: OptionButton
var result_panel: PanelContainer
var result_summary: Label
var battle_started := false
var game_state: Node
var turn_manager: Node

func setup(value: BattleRuntimeState) -> void:
	battle = value

func _ready() -> void:
	layer = 100
	game_state = get_node("/root/GameState")
	turn_manager = get_node("/root/TurnManager")
	battle.require_round_confirmation = true
	_build_hud()
	_build_3d_world()
	_build_squad_visuals()
	_sync_control_point_visuals()
	_show_prebattle()

func _build_hud() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.012, 0.02, 0.045, 1.0)
	add_child(backdrop)
	UIUtils.fill_parent(backdrop)
	var title := Label.new()
	title.text = "ORBITAL DOMINION / 2.5D BATTLE  —  %s" % game_state.region_defs[battle.region_id].display_name
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 23)
	backdrop.add_child(title)
	status_label = Label.new()
	status_label.position = Vector2(24, 50)
	backdrop.add_child(status_label)
	arena = SubViewportContainer.new()
	arena.position = Vector2(28, 86)
	arena.size = Vector2(1230, 780)
	arena.stretch = true
	arena.mouse_filter = Control.MOUSE_FILTER_STOP
	arena.gui_input.connect(_on_arena_input)
	backdrop.add_child(arena)
	var controls := VBoxContainer.new()
	controls.position = Vector2(1280, 100)
	controls.size = Vector2(290, 620)
	backdrop.add_child(controls)
	var help := Label.new()
	help.text = "ロボット部隊を左クリックで選択\n地面を右クリックして移動\n\n青: プレイヤー　赤: 敵\n前列3機 / 後列2機\n\n攻撃・拠点制圧は次段階です。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	controls.add_child(help)
	for scale_value in [0.0, 1.0, 2.0, 4.0]:
		var button := Button.new()
		button.text = "一時停止" if scale_value == 0.0 else "戦場速度 x%d" % int(scale_value)
		button.pressed.connect(func(): battle.time_scale = scale_value)
		controls.add_child(button)
	var retreat := Button.new()
	retreat.text = "侵攻部隊を撤退"
	retreat.pressed.connect(_request_attacker_retreat)
	controls.add_child(retreat)
	_build_prebattle_panel(backdrop)
	_build_result_panel(backdrop)

func _build_prebattle_panel(parent: Control) -> void:
	prebattle_panel = PanelContainer.new()
	prebattle_panel.position = Vector2(380, 190)
	prebattle_panel.size = Vector2(800, 470)
	prebattle_panel.visible = false
	parent.add_child(prebattle_panel)
	var content := VBoxContainer.new()
	prebattle_panel.add_child(content)
	var heading := Label.new()
	heading.text = "CONTACT / 戦闘前確認"
	heading.add_theme_font_size_override("font_size", 26)
	content.add_child(heading)
	prebattle_summary = Label.new()
	prebattle_summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	prebattle_summary.custom_minimum_size = Vector2(740, 290)
	content.add_child(prebattle_summary)
	policy_selector = OptionButton.new()
	for label_text in ["バランス", "攻撃重視", "防御重視", "支援優先", "撤退優先"]: policy_selector.add_item(label_text)
	content.add_child(policy_selector)
	var start_button := Button.new()
	start_button.text = "30秒ラウンド開始"
	start_button.pressed.connect(_confirm_round)
	content.add_child(start_button)

func _build_result_panel(parent: Control) -> void:
	result_panel = PanelContainer.new()
	result_panel.position = Vector2(430, 210)
	result_panel.size = Vector2(700, 390)
	result_panel.visible = false
	parent.add_child(result_panel)
	var content := VBoxContainer.new()
	result_panel.add_child(content)
	var heading := Label.new()
	heading.text = "BATTLE RESULT / 戦闘結果"
	heading.add_theme_font_size_override("font_size", 28)
	content.add_child(heading)
	result_summary = Label.new()
	result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	result_summary.custom_minimum_size = Vector2(640, 250)
	content.add_child(result_summary)
	var close_button := Button.new()
	close_button.text = "戦略画面へ戻る"
	close_button.pressed.connect(_complete_result)
	content.add_child(close_button)

func _build_3d_world() -> void:
	battle_viewport = SubViewport.new()
	battle_viewport.size = Vector2i(1230, 780)
	battle_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	battle_viewport.msaa_3d = Viewport.MSAA_2X
	battle_viewport.world_3d = World3D.new()
	arena.add_child(battle_viewport)
	world_root = Node3D.new()
	battle_viewport.add_child(world_root)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.015, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.34, 0.48)
	env.ambient_light_energy = 0.85
	environment.environment = env
	world_root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	world_root.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = ARENA_SIZE
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.035, 0.065, 0.11)
	ground_material.metallic = 0.25
	ground_material.roughness = 0.75
	ground.material_override = ground_material
	world_root.add_child(ground)
	_add_grid_lines()
	for point_id: StringName in battle.control_point_defs_by_id:
		var point_def := battle.control_point_defs_by_id[point_id] as BattleControlPointDef
		var color := Color(0.75, 0.8, 0.9)
		var label_text := "RELAY"
		if point_id == battle.attacker_hq_id: color = Color(0.15, 0.55, 1.0); label_text = "ATTACKER HQ"
		elif point_id == battle.defender_hq_id: color = Color(1.0, 0.2, 0.25); label_text = "DEFENDER HQ"
		_add_control_point(point_id, point_def.position + Vector3(0, 3, 0), color, label_text)
	camera = Camera3D.new()
	camera.position = Vector3(0, 760, 720)
	camera.fov = 52.0
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	world_root.add_child(camera)
	camera.current = true

func _add_grid_lines() -> void:
	for x in range(-600, 601, 100):
		_add_line(Vector3(x, 0.4, -450), Vector3(x, 0.4, 450), Color(0.15, 0.35, 0.55, 0.28))
	for z in range(-450, 451, 100):
		_add_line(Vector3(-600, 0.4, z), Vector3(600, 0.4, z), Color(0.15, 0.35, 0.55, 0.28))

func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	world_root.add_child(instance)

func _add_control_point(point_id: StringName, position: Vector3, color: Color, label_text: String) -> void:
	var marker := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 34.0
	cylinder.bottom_radius = 34.0
	cylinder.height = 6.0
	marker.mesh = cylinder
	marker.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.7)
	material.emission_enabled = true
	material.emission = color * 0.45
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = material
	control_point_materials[point_id] = material
	world_root.add_child(marker)
	var label := Label3D.new()
	label.text = label_text
	label.position = position + Vector3(0, 18, 0)
	label.font_size = 28
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	world_root.add_child(label)
	control_point_labels[point_id] = label

func _build_squad_visuals() -> void:
	for squad: BattleSquadState in battle.squad_states_by_id.values():
		var root_node := Node3D.new()
		root_node.name = String(squad.squad_id)
		root_node.position = Vector3(squad.world_position.x, 0.0, squad.world_position.y)
		world_root.add_child(root_node)
		squad_visuals[squad.squad_id] = root_node
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 52.0
		ring_mesh.outer_radius = 57.0
		ring.mesh = ring_mesh
		ring.position.y = 1.5
		ring.visible = false
		var ring_material := StandardMaterial3D.new()
		ring_material.albedo_color = Color.GOLD
		ring_material.emission_enabled = true
		ring_material.emission = Color.GOLD
		ring.material_override = ring_material
		root_node.add_child(ring)
		selection_markers[squad.squad_id] = ring
		for unit_id: StringName in squad.unit_instance_ids:
			var battle_unit := battle.unit_states_by_id[unit_id] as BattleUnitState
			var campaign_unit: UnitInstanceState = game_state.campaign_runtime.get_unit(unit_id)
			var unit_def := game_state.master_data.units.get(campaign_unit.unit_def_id) as UnitDef
			var unit_root := Node3D.new()
			unit_root.position = FORMATION_OFFSETS[battle_unit.slot_index]
			root_node.add_child(unit_root)
			unit_visuals[unit_id] = unit_root
			var sprite := Sprite3D.new()
			sprite.texture = unit_def.vignette_sprite if unit_def.vignette_sprite != null else unit_def.icon
			sprite.pixel_size = 0.24
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.no_depth_test = false
			sprite.position = Vector3(0, 42, 0)
			var size_scale := [0.8, 1.0, 1.35][unit_def.size] as float
			sprite.scale = Vector3.ONE * size_scale
			sprite.modulate = Color(0.55, 0.85, 1.0) if squad.faction_id == game_state.player_faction_id else Color(1.0, 0.55, 0.55)
			unit_root.add_child(sprite)
			_add_unit_status_bars(unit_root, unit_id)

func _add_unit_status_bars(unit_root: Node3D, unit_id: StringName) -> void:
	var background := _make_status_bar(Color(0.02, 0.03, 0.04, 0.9), 58.0, 10.0)
	background.position = Vector3(0, 82, 0)
	unit_root.add_child(background)
	var hp_fill := _make_status_bar(Color(0.15, 0.95, 0.35), 54.0, 4.0)
	hp_fill.position = Vector3(0, 84, 0.2)
	unit_root.add_child(hp_fill)
	hp_bar_fills[unit_id] = hp_fill
	var en_fill := _make_status_bar(Color(0.15, 0.65, 1.0), 54.0, 3.0)
	en_fill.position = Vector3(0, 78, 0.2)
	unit_root.add_child(en_fill)
	en_bar_fills[unit_id] = en_fill

func _make_status_bar(color: Color, width: float, height: float) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	bar.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	bar.material_override = material
	return bar

func _process(delta: float) -> void:
	if battle == null:
		return
	_advance_transient_effects(delta)
	if battle.result != null:
		_show_battle_result()
		return
	if not battle_started:
		return
	var scaled_delta := delta * battle.time_scale
	for squad: BattleSquadState in battle.squad_states_by_id.values():
		var offset := squad.destination - squad.world_position
		if offset.length() > 1.0 and not squad.retreat_requested and battle.engagements_by_squad_id.is_empty() and squad.reengage_wait_sec <= 0.0:
			squad.world_position += offset.normalized() * minf(offset.length(), _squad_speed(squad) * scaled_delta)
		squad.world_position.x = clampf(squad.world_position.x, -580.0, 580.0)
		squad.world_position.y = clampf(squad.world_position.y, -430.0, 430.0)
		var visual := squad_visuals.get(squad.squad_id) as Node3D
		if visual != null: visual.position = Vector3(squad.world_position.x, 0, squad.world_position.y)
	battle.advance_time(delta)
	_sync_combat_events()
	_sync_unit_status()
	_sync_control_point_visuals()
	status_label.text = "経過 %.1f / 300秒  x%.0f  選択: %s" % [battle.elapsed_world_sec, battle.time_scale, selected_squad_id]
	if battle.has_unconfirmed_engagement(): _show_prebattle()
	if battle.result != null:
		_show_battle_result()

func _show_prebattle() -> void:
	prebattle_panel.visible = true
	var lines: PackedStringArray = ["敵味方の編成と現在状態", ""]
	var player_power := 0.0
	var enemy_power := 0.0
	for squad: BattleSquadState in battle.squad_states_by_id.values():
		var side := "PLAYER" if squad.faction_id == game_state.player_faction_id else "ENEMY"
		var power := BattlePowerEstimator.squad_power(battle, squad)
		if squad.faction_id == game_state.player_faction_id: player_power += power
		else: enemy_power += power
		lines.append("%s  %s  方針:%d" % [side, squad.squad_id, squad.policy])
		for unit_id: StringName in squad.unit_instance_ids:
			var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
			lines.append("  SLOT %d  HP %d/%d  EN %d/%d" % [unit.slot_index + 1, unit.current_hp, unit.max_hp, unit.current_en, unit.max_en])
	lines.append("\n概略戦力: %s" % BattlePowerEstimator.rating(player_power, enemy_power))
	lines.append("命中率・ダメージ幅・乱数結果は非表示です。")
	prebattle_summary.text = "\n".join(lines)

func _confirm_battle_start() -> void:
	for engagement: BattleEngagementState in battle.engagements_by_squad_id.values():
		for squad_id: StringName in [engagement.first_squad_id, engagement.second_squad_id]:
			var squad := battle.squad_states_by_id[squad_id] as BattleSquadState
			if squad.faction_id == game_state.player_faction_id: squad.policy = policy_selector.selected
	battle.confirm_engagements()
	battle_started = true
	prebattle_panel.visible = false

func _confirm_round() -> void:
	_confirm_battle_start()

func _show_battle_result() -> void:
	if result_panel.visible or battle.result == null: return
	prebattle_panel.visible = false
	result_panel.visible = true
	var result := battle.result
	result_summary.text = "勝者: %s\n敗者: %s\n決着: %s\n戦闘時間: %.1f秒\n撃破: %s\n\n結果のやり直しはできません。" % [result.winner_faction_id, result.loser_faction_id, result.reason, result.elapsed_world_sec, ", ".join(result.destroyed_unit_ids)]

func _confirm_battle_result() -> void:
	_complete_result()

func _complete_result() -> void:
	var errors: PackedStringArray = turn_manager.complete_battle_runtime(battle)
	if errors.is_empty(): queue_free()
	else: result_summary.text += "\n結果反映エラー: %s" % errors[0]

func _sync_unit_status() -> void:
	for unit_id: StringName in unit_visuals:
		var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		var hp_ratio := clampf(float(unit.current_hp) / float(maxi(1, unit.max_hp)), 0.0, 1.0)
		var en_ratio := clampf(float(unit.current_en) / float(maxi(1, unit.max_en)), 0.0, 1.0)
		_set_bar_ratio(hp_bar_fills[unit_id] as MeshInstance3D, hp_ratio)
		_set_bar_ratio(en_bar_fills[unit_id] as MeshInstance3D, en_ratio)
		(unit_visuals[unit_id] as Node3D).visible = unit.current_hp > 0

func _sync_control_point_visuals() -> void:
	for point_id: StringName in control_point_labels:
		var point := battle.control_point_states[point_id] as BattleControlPointState
		var label := control_point_labels[point_id] as Label3D
		var base_text := "ATTACKER HQ" if point_id == battle.attacker_hq_id else ("DEFENDER HQ" if point_id == battle.defender_hq_id else "RELAY")
		var owner_color := _faction_color(point.owner_faction_id)
		var display_color := owner_color
		if not point.capturing_faction_id.is_empty():
			display_color = owner_color.lerp(_faction_color(point.capturing_faction_id), point.capture_progress / 100.0)
		label.text = "%s / %s" % [base_text, String(point.owner_faction_id) if not point.owner_faction_id.is_empty() else "NEUTRAL"]
		if not point.capturing_faction_id.is_empty(): label.text += " -> %s %.0f%%" % [point.capturing_faction_id, point.capture_progress]
		label.modulate = display_color
		var material := control_point_materials[point_id] as StandardMaterial3D
		material.albedo_color = Color(display_color, 0.7)
		material.emission = display_color * 0.45

func _faction_color(faction_id: StringName) -> Color:
	if faction_id.is_empty(): return Color(0.55, 0.58, 0.64)
	var faction := game_state.master_data.factions.get(faction_id) as FactionDef
	return faction.color if faction != null else Color.WHITE

func _set_bar_ratio(bar: MeshInstance3D, ratio: float) -> void:
	bar.visible = ratio > 0.0
	bar.scale.x = maxf(0.001, ratio)
	bar.position.x = -27.0 * (1.0 - ratio)

func _sync_combat_events() -> void:
	for event: Dictionary in battle.combat_events:
		if event.get("type") != &"shot": continue
		var source := unit_visuals.get(StringName(event.source_unit_id)) as Node3D
		var target := unit_visuals.get(StringName(event.target_unit_id)) as Node3D
		if source == null or target == null: continue
		var weapon := battle.weapon_defs.get(StringName(event.weapon_id)) as WeaponDef
		var color := Color(0.25, 0.75, 1.0) if weapon != null and weapon.damage_attribute == GameEnums.DamageAttribute.BEAM else Color(1.0, 0.72, 0.2)
		_add_shot_line(source.global_position + Vector3(0, 46, 0), target.global_position + Vector3(0, 42, 0), color, bool(event.hit))
		_add_damage_label(target.global_position + Vector3(0, 92, 0), event)
		processed_combat_event_count += 1

func _add_shot_line(from: Vector3, to: Vector3, color: Color, hit: bool) -> void:
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES)
	line.surface_set_color(color if hit else Color(color, 0.35))
	line.surface_add_vertex(from)
	line.surface_add_vertex(to)
	line.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = line
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	world_root.add_child(instance)
	transient_effects.append({"node": instance, "remaining": 0.16})

func _add_damage_label(position: Vector3, event: Dictionary) -> void:
	var label := Label3D.new()
	label.text = ("CRITICAL %d" % int(event.damage)) if bool(event.critical) else (str(event.damage) if bool(event.hit) else "MISS")
	label.position = position
	label.font_size = 34
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.35, 0.2) if bool(event.critical) else Color.WHITE
	world_root.add_child(label)
	transient_effects.append({"node": label, "remaining": 0.55})

func _advance_transient_effects(delta: float) -> void:
	for index in range(transient_effects.size() - 1, -1, -1):
		var effect: Dictionary = transient_effects[index]
		effect.remaining = float(effect.remaining) - delta
		if float(effect.remaining) <= 0.0:
			(effect.node as Node).queue_free()
			transient_effects.remove_at(index)
		else:
			transient_effects[index] = effect

func _squad_speed(squad: BattleSquadState) -> float:
	var slowest: float = INF
	for unit_id: StringName in squad.unit_instance_ids:
		var battle_unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		if battle_unit.current_hp <= 0: continue
		var campaign_unit: UnitInstanceState = game_state.campaign_runtime.get_unit(unit_id)
		var unit_def := game_state.master_data.units.get(campaign_unit.unit_def_id) as UnitDef
		slowest = minf(slowest, float(unit_def.speed) / 10.0)
	return slowest if slowest < INF else 0.0

func _on_arena_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or camera == null:
		return
	var world: Variant = _ray_to_ground(event.position)
	if world == null:
		return
	var target := world as Vector3
	if event.button_index == MOUSE_BUTTON_LEFT:
		selected_squad_id = _nearest_player_squad(Vector2(target.x, target.z))
		for squad_id: StringName in selection_markers:
			(selection_markers[squad_id] as MeshInstance3D).visible = squad_id == selected_squad_id
	elif event.button_index == MOUSE_BUTTON_RIGHT and not selected_squad_id.is_empty():
		var squad := battle.squad_states_by_id.get(selected_squad_id) as BattleSquadState
		if squad != null and battle.engagements_by_squad_id.is_empty() and squad.reengage_wait_sec <= 0.0 and not squad.retreat_requested:
			squad.destination = Vector3(target.x, target.z, 0.0)

func _ray_to_ground(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001: return null
	var distance := -origin.y / direction.y
	return origin + direction * distance if distance >= 0.0 else null

func _nearest_player_squad(world: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_distance := 85.0
	for squad: BattleSquadState in battle.squad_states_by_id.values():
		if squad.faction_id != game_state.player_faction_id: continue
		var distance := Vector2(squad.world_position.x, squad.world_position.y).distance_to(world)
		if distance < best_distance:
			best_distance = distance
			best_id = squad.squad_id
	return best_id

func _request_attacker_retreat() -> void:
	for squad_id: StringName in battle.attacker_squad_ids:
		battle.request_retreat(squad_id)
	battle.time_scale = 4.0
