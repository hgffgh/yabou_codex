extends SceneTree
## DATA_DEFINITION.md section 9.1.1's model_scene pipeline: nova_scout is the
## first unit with a real (Blender-generated, see tools/gen_unit_model.py)
## model_scene instead of scenes/units/placeholder_unit_model.tscn.
## BattlePrototypeView._instantiate_model must tell the two apart (an empty
## Node3D placeholder yields no visible model, falling back to the old
## Sprite3D billboard) and _tint_model_materials must apply a distinct
## faction tint per MeshInstance3D without mutating the shared source scene.

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("unit_model_pipeline_test: GameState is unavailable")
		quit(1)
		return

	_test_nova_scout_model_has_expected_rig_and_clips()
	_test_instantiate_model_distinguishes_real_model_from_placeholder()
	_test_tint_model_materials_applies_distinct_faction_colors()
	_finish()


func _test_nova_scout_model_has_expected_rig_and_clips() -> void:
	var unit_def: UnitDef = game_state.master_data.units.get(&"nova_scout")
	_check(unit_def != null, "setup: nova_scout should exist in master data")
	if unit_def == null:
		return
	_check(unit_def.model_scene != null, "nova_scout.model_scene should be set")
	if unit_def.model_scene == null:
		return
	var instance := unit_def.model_scene.instantiate()
	_check(instance.get_child_count() > 0, "nova_scout's model should not be the empty placeholder")
	var anim_player := _find_animation_player(instance)
	_check(anim_player != null, "nova_scout's model should contain an AnimationPlayer")
	if anim_player != null:
		for clip_name in [&"idle", &"move", &"attack", &"hit", &"destroyed"]:
			_check(anim_player.has_animation(clip_name), "nova_scout's model should have a %s clip" % clip_name)
	_check(_count_mesh_instances(instance) > 0, "nova_scout's model should contain at least one MeshInstance3D")
	instance.queue_free()


func _test_instantiate_model_distinguishes_real_model_from_placeholder() -> void:
	var view := BattlePrototypeView.new()
	var nova_scout_def: UnitDef = game_state.master_data.units.get(&"nova_scout")
	var placeholder_def: UnitDef = game_state.master_data.units.get(&"crimson_bastion")
	_check(nova_scout_def != null and placeholder_def != null, "setup: both reference units should exist")
	if nova_scout_def == null or placeholder_def == null:
		return
	var real_instance: Node3D = view.call("_instantiate_model", nova_scout_def)
	_check(real_instance != null, "_instantiate_model should return a node for nova_scout's real model")
	if real_instance != null:
		real_instance.queue_free()
	var placeholder_instance: Node3D = view.call("_instantiate_model", placeholder_def)
	_check(placeholder_instance == null, "_instantiate_model should fall back to null for a still-empty placeholder model_scene, so callers use the Sprite3D billboard instead")
	view.queue_free()


func _test_tint_model_materials_applies_distinct_faction_colors() -> void:
	var view := BattlePrototypeView.new()
	var unit_def: UnitDef = game_state.master_data.units.get(&"nova_scout")
	if unit_def == null:
		return
	var player_instance: Node3D = view.call("_instantiate_model", unit_def)
	var enemy_instance: Node3D = view.call("_instantiate_model", unit_def)
	view.call("_tint_model_materials", player_instance, Color(0.55, 0.85, 1.0))
	view.call("_tint_model_materials", enemy_instance, Color(1.0, 0.55, 0.55))
	var player_material := _find_mesh_material(player_instance)
	var enemy_material := _find_mesh_material(enemy_instance)
	_check(player_material != null and enemy_material != null, "both instances should end up with an overridden material")
	if player_material != null and enemy_material != null:
		_check(not player_material.albedo_color.is_equal_approx(enemy_material.albedo_color), "player and enemy tints should produce different albedo colors")
	player_instance.queue_free()
	enemy_instance.queue_free()
	view.queue_free()


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _count_mesh_instances(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count


func _find_mesh_material(node: Node) -> StandardMaterial3D:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).material_override as StandardMaterial3D
	for child in node.get_children():
		var found := _find_mesh_material(child)
		if found != null:
			return found
	return null


func _finish() -> void:
	if failures.is_empty():
		print("unit_model_pipeline_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("unit_model_pipeline_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
