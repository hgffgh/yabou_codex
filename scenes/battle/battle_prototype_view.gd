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
var unit_animation_players: Dictionary = {}
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
var audio_manager: Node
var _squad_status_rows: Dictionary = {}  # StringName -> Dictionary of row controls

func setup(value: BattleRuntimeState) -> void:
	battle = value

func _ready() -> void:
	layer = 100
	game_state = get_node("/root/GameState")
	turn_manager = get_node("/root/TurnManager")
	audio_manager = get_node("/root/AudioManager")
	battle.require_round_confirmation = true
	_build_hud()
	_build_3d_world()
	_build_squad_visuals()
	_sync_control_point_visuals()
	_show_prebattle()

func _build_hud() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UITheme.COLOR_BG
	backdrop.theme = UITheme.get_theme()
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
	# audio_manager (resolved via get_node in _ready()) and the raw &"confirm"
	# literal instead of AudioManager.SFX_CONFIRM -- same reason game_state/
	# turn_manager are resolved via get_node() rather than a bare identifier
	# in this file: a fresh --script test entry point that directly
	# instantiates BattlePrototypeView eagerly compiles this whole class
	# body, and ANY bare reference to the AudioManager autoload identifier
	# (even just to read a constant off it) isn't resolvable yet at that
	# point -- confirmed live, this is exactly what broke
	# battle_view_smoke_test.gd (see this project's own established note on
	# the headless compile-order bug elsewhere in this codebase).
	retreat.pressed.connect(audio_manager.play_sfx.bind(&"confirm"))
	controls.add_child(retreat)
	_build_squad_status_sliver(controls)
	_build_prebattle_panel(backdrop)
	_build_result_panel(backdrop)

## FIG.06 of the "司令デッキ化計画" design proposal: a compact tag + thin HP
## track per squad, or a fog tag for an unconfirmed enemy, replacing what
## used to be entirely absent from the flat HUD -- the only per-squad HP
## readout during a live battle was either the in-3D billboard bars over
## each robot (easy to lose behind the camera/other sprites) or the
## pre-battle confirmation panel (a one-time snapshot, not live). Built once
## per squad here; _sync_squad_status_sliver() (called from _process) keeps
## every row current, including flipping a still-unconfirmed enemy row over
## to its real HP track the instant BattleSquadState.intel_confirmed goes
## true mid-battle.
func _build_squad_status_sliver(parent: Control) -> void:
	parent.add_child(HSeparator.new())
	var header := Label.new()
	header.text = UITheme.bracket("SQUADS 部隊状況")
	UITheme.style_mono_label(header, 10)
	header.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	parent.add_child(header)
	var squad_ids := battle.squad_states_by_id.keys()
	squad_ids.sort()  # stable order, matching every other stable-ID iteration in this codebase
	for squad_id: StringName in squad_ids:
		var squad := battle.squad_states_by_id[squad_id] as BattleSquadState
		_squad_status_rows[squad_id] = _build_squad_status_row(parent, squad)

## One row: a fixed-width side/id tag, then either an HP track+percentage
## (own squad, or a confirmed enemy) or a fog tag (an unconfirmed enemy) --
## both built up front and toggled by _sync_squad_status_sliver() rather
## than rebuilt every frame, since the squad list itself never changes
## mid-battle.
func _build_squad_status_row(parent: Control, squad: BattleSquadState) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var tag := Label.new()
	UITheme.style_mono_label(tag, 11)
	tag.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	tag.custom_minimum_size = Vector2(96, 0)
	row.add_child(tag)

	# hp_group is a plain Control (not HBoxContainer), and hp_track/hp_value
	# inside it use plain absolute position/size instead of size_flags/
	# anchors -- see the matching, more detailed comment on
	# StrategicMap._build_info_row for why: an EXPAND-flagged sibling in the
	# same HBoxContainer as a Label renders that Label fully invisible in
	# this Godot version, confirmed live against a deferred
	# get_viewport().get_texture().get_image() capture. hp_group itself can
	# still take row's leftover width via SIZE_EXPAND_FILL (that part is
	# fine -- the bug is specific to Label rendering, not Control sizing/
	# positioning in general, and a plain Control has no text of its own to
	# fail to render); its children just can't rely on knowing that
	# resolved width, so 184 (row's own known width, 290 controls minus 96
	# tag minus 10 separation) is hardcoded the same way the region panel
	# fix hardcodes its own row width instead of querying it.
	var hp_group := Control.new()
	hp_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hp_group)
	var hp_track := ProgressBar.new()
	hp_track.show_percentage = false
	hp_track.position = Vector2(0, 4)
	hp_track.size = Vector2(184.0 - 48.0, 4)
	hp_group.add_child(hp_track)
	var hp_value := Label.new()
	UITheme.style_mono_label(hp_value, 11)
	hp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_value.position = Vector2(184.0 - 40.0, -6.0)
	hp_value.size = Vector2(40.0, 20.0)
	hp_group.add_child(hp_value)

	# Godot's StyleBoxFlat has no dashed-border option (the design
	# reference's fog tag uses `border: 1px dashed`) -- a solid hairline
	# border is the closest native equivalent, matching every other panel
	# border UITheme already builds as fill-less + hairline.
	var fog_wrap := PanelContainer.new()
	var fog_style := StyleBoxFlat.new()
	fog_style.bg_color = Color(0, 0, 0, 0)
	fog_style.border_color = UITheme.COLOR_BORDER
	fog_style.set_border_width_all(1)
	fog_style.content_margin_left = 10
	fog_style.content_margin_right = 10
	fog_style.content_margin_top = 3
	fog_style.content_margin_bottom = 3
	fog_wrap.add_theme_stylebox_override("panel", fog_style)
	fog_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fog_wrap)
	var fog_label := Label.new()
	fog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_mono_label(fog_label, 10.5)
	fog_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	fog_wrap.add_child(fog_label)

	return {
		"is_own": squad.faction_id == game_state.player_faction_id,
		"tag": tag, "hp_group": hp_group, "hp_track": hp_track, "hp_value": hp_value,
		"fog_wrap": fog_wrap, "fog_label": fog_label,
	}

## Re-evaluates every row's known/unconfirmed split and HP fraction each
## frame -- cheap (a handful of squads, a handful of units each) and avoids
## a second, separate signal path just to catch intel_confirmed flipping
## mid-battle when _process is already the single per-frame sync point for
## every other piece of battle HUD state.
func _sync_squad_status_sliver() -> void:
	for squad_id: StringName in _squad_status_rows:
		var squad := battle.squad_states_by_id.get(squad_id) as BattleSquadState
		if squad == null:
			continue
		var row: Dictionary = _squad_status_rows[squad_id]
		var is_own: bool = row.is_own
		var side_text := "自隊" if is_own else "敵"
		var known := is_own or squad.intel_confirmed
		(row.tag as Label).text = "%s・%s" % [side_text, squad.squad_id] if known else "%s・接触反応" % side_text

		(row.hp_group as Control).visible = known
		(row.fog_wrap as Control).visible = not known
		if known:
			var current_hp := 0
			var max_hp := 0
			for unit_id: StringName in squad.unit_instance_ids:
				var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
				current_hp += maxi(0, unit.current_hp)
				max_hp += unit.max_hp
			var ratio := float(current_hp) / float(maxi(1, max_hp))
			var hp_track := row.hp_track as ProgressBar
			hp_track.max_value = 1.0
			hp_track.value = ratio
			var fill_style := StyleBoxFlat.new()
			fill_style.bg_color = UITheme.COLOR_GOOD if ratio > 0.5 \
				else (UITheme.COLOR_GOLD if ratio > 0.2 else UITheme.COLOR_DANGER)
			hp_track.add_theme_stylebox_override("fill", fill_style)
			(row.hp_value as Label).text = "%d%%" % roundi(ratio * 100.0)
		else:
			var distance := battle.engagement_distance_m(squad_id)
			var fog_label := row.fog_label as Label
			fog_label.text = "未確認 — 交戦距離 %dm" % int(distance) if is_finite(distance) else "未確認"

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
	UITheme.style_primary_button(start_button)
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
	UITheme.style_primary_button(close_button)
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
	for zone_id: StringName in battle.terrain_zone_defs:
		_add_terrain_zone(battle.terrain_zone_defs[zone_id] as TerrainZoneDef)
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

## COMBAT_DETAIL_SPECIFICATION.md section 29: a flat, unlit disc sized to
## radius_m, colored per effect, purely visual (no collision/interaction --
## the actual gameplay effects live entirely in BattleRuntimeState/
## BattleCombatSystem).
const TERRAIN_ZONE_COLORS := {
	GameEnums.TerrainEffect.DIFFICULT: Color(0.55, 0.42, 0.18),
	GameEnums.TerrainEffect.COVER: Color(0.25, 0.65, 0.3),
	GameEnums.TerrainEffect.HAZARDOUS: Color(0.85, 0.25, 0.1),
	GameEnums.TerrainEffect.IMPASSABLE: Color(0.3, 0.3, 0.34),
}

func _add_terrain_zone(zone: TerrainZoneDef) -> void:
	if zone == null or not TERRAIN_ZONE_COLORS.has(zone.effect):
		return
	var color: Color = TERRAIN_ZONE_COLORS[zone.effect]
	var marker := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = zone.radius_m
	disc.bottom_radius = zone.radius_m
	disc.height = 0.6
	marker.mesh = disc
	marker.position = zone.position + Vector3(0, 0.3, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.35)
	material.emission_enabled = true
	material.emission = color * 0.3
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	world_root.add_child(marker)

func _build_squad_visuals() -> void:
	for squad: BattleSquadState in battle.squad_states_by_id.values():
		var root_node := Node3D.new()
		root_node.name = String(squad.squad_id)
		root_node.position = Vector3(squad.world_position.x, 0.0, squad.world_position.y)
		root_node.visible = squad.faction_id == game_state.player_faction_id
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
			var size_scale := [0.8, 1.0, 1.35][unit_def.size] as float
			var tint := Color(0.55, 0.85, 1.0) if squad.faction_id == game_state.player_faction_id else Color(1.0, 0.55, 0.55)
			var model_instance := _instantiate_model(unit_def)
			if model_instance != null:
				unit_root.add_child(model_instance)
				model_instance.scale = Vector3.ONE * size_scale
				_tint_model_materials(model_instance, tint)
				var anim_player := _find_animation_player(model_instance)
				unit_animation_players[unit_id] = anim_player
				if anim_player != null and anim_player.has_animation(&"idle"):
					anim_player.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
					anim_player.get_animation(&"move").loop_mode = Animation.LOOP_LINEAR
					anim_player.play(&"idle")
			else:
				var sprite := Sprite3D.new()
				sprite.texture = unit_def.vignette_sprite if unit_def.vignette_sprite != null else unit_def.icon
				sprite.pixel_size = 0.24
				sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sprite.no_depth_test = false
				sprite.position = Vector3(0, 42, 0)
				sprite.scale = Vector3.ONE * size_scale
				sprite.modulate = tint
				unit_root.add_child(sprite)
			_add_unit_status_bars(unit_root, unit_id)

## `UnitDef.model_scene` has been schema-required since the data-foundation
## milestone but was never wired up -- every unit's model_scene pointed at
## `scenes/units/placeholder_unit_model.tscn`, an empty Node3D with no
## children, deliberately so this exact "instantiate and check whether
## anything came back" fallback works without any per-unit flag. See
## DATA_DEFINITION.md section 9.1.1 for the model spec (glTF, coordinate/
## scale convention, five named AnimationPlayer clips) that a real
## model_scene needs to satisfy for this to render/animate correctly.
func _instantiate_model(unit_def: UnitDef) -> Node3D:
	if unit_def.model_scene == null:
		return null
	var instance := unit_def.model_scene.instantiate() as Node3D
	if instance == null or instance.get_child_count() == 0:
		if instance != null:
			instance.queue_free()
		return null
	return instance

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

## Real models must not bake a faction color into their texture (a captured
## unit's owner_faction_id can change), so every MeshInstance3D gets a fresh
## material tinted by multiplying the flat hull-grey the generator scripts
## export against by the same blue/red tint the old Sprite3D.modulate used.
func _tint_model_materials(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.72, 0.74, 0.78) * tint
		material.metallic = 0.5
		material.roughness = 0.45
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_tint_model_materials(child, tint)

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
	# Position movement itself now lives in BattleRuntimeState.advance_time
	# (so auto-resolved battles move too); this just mirrors the resulting
	# position onto each squad's visual every frame.
	for squad: BattleSquadState in battle.squad_states_by_id.values():
		_sync_intel_visibility(squad)
	battle.advance_time(delta)
	_sync_combat_events()
	_sync_unit_status()
	_sync_control_point_visuals()
	_sync_squad_status_sliver()
	status_label.text = "経過 %.1f / 300秒  x%.0f  選択: %s" % [battle.elapsed_world_sec, battle.time_scale, selected_squad_id]
	if battle.has_unconfirmed_engagement(): _show_prebattle()

## COMBAT_DETAIL_SPECIFICATION.md section 24: an unconfirmed enemy squad's
## icon is not shown at all. Once confirmed (sticky for the battle), it
## renders at its live position while currently sensed, and freezes at
## last_known_world_position (a stale "last confirmed" marker) once it
## leaves sensor range and the firing-disclosure window has elapsed.
func _sync_intel_visibility(squad: BattleSquadState) -> void:
	var visual := squad_visuals.get(squad.squad_id) as Node3D
	if visual == null:
		return
	var is_own_squad: bool = squad.faction_id == game_state.player_faction_id
	visual.visible = is_own_squad or squad.intel_confirmed
	if is_own_squad or squad.currently_sensed:
		visual.position = Vector3(squad.world_position.x, 0, squad.world_position.y)
	elif squad.intel_confirmed:
		visual.position = Vector3(squad.last_known_world_position.x, 0, squad.last_known_world_position.y)
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
		var unconfirmed_enemy: bool = squad.faction_id != game_state.player_faction_id and not squad.intel_confirmed
		lines.append("%s  %s  方針:%s" % [side, squad.squad_id if not unconfirmed_enemy else "未確認部隊", "?" if unconfirmed_enemy else str(squad.policy)])
		for unit_id: StringName in squad.unit_instance_ids:
			var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
			if unconfirmed_enemy:
				lines.append("  SLOT %d  未確認" % [unit.slot_index + 1])
			else:
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
		var destination := Vector3(target.x, target.z, 0.0)
		if squad != null and battle.engagements_by_squad_id.is_empty() and squad.reengage_wait_sec <= 0.0 \
				and not squad.retreat_requested and battle.is_position_passable(destination):
			squad.destination = destination

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
