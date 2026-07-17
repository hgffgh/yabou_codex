extends SceneTree
## DifficultyDef (DATA_DEFINITION.md section 5) and environment-aptitude
## accuracy/evasion (UNIT_DETAIL_SPECIFICATION.md section 6).

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("combat_modifiers_test: required autoload is unavailable")
		quit(1)
		return

	_test_difficulty_registry_loads_three_presets()
	_test_current_difficulty_falls_back_to_neutral()
	_test_start_new_game_validates_difficulty_id()
	_test_save_load_round_trips_difficulty_id()
	_test_hp_multiplier_scales_only_non_player_units()
	_test_firepower_and_accuracy_evasion_scale_only_non_player_factions()
	_test_environment_aptitude_accuracy_and_evasion_additions()
	_finish()


func _test_difficulty_registry_loads_three_presets() -> void:
	_check(game_state.master_data_errors.is_empty(), "difficulty data failed master-data validation: %s" % game_state.master_data_errors)
	_check(game_state.master_data.difficulties.size() == 3, "expected exactly 3 difficulty presets in the standard dataset")
	var hard: DifficultyDef = game_state.master_data.difficulties.get(&"hard")
	_check(hard != null and is_equal_approx(hard.enemy_income_multiplier, 1.5) and hard.enemy_accuracy_add == 15,
		"hard.tres did not load the expected values")


func _test_current_difficulty_falls_back_to_neutral() -> void:
	var original: StringName = game_state.difficulty_id
	game_state.difficulty_id = &"does_not_exist"
	var fallback: DifficultyDef = game_state.current_difficulty()
	_check(is_equal_approx(fallback.enemy_income_multiplier, 1.0) and fallback.enemy_accuracy_add == 0,
		"current_difficulty() should fall back to neutral defaults for an unresolved difficulty_id")
	game_state.difficulty_id = original


func _test_start_new_game_validates_difficulty_id() -> void:
	turn_manager.start_new_game(&"nova_republic", &"hard")
	_check(game_state.difficulty_id == &"hard", "start_new_game should accept a valid difficulty_id")
	turn_manager.start_new_game(&"nova_republic", &"not_a_real_difficulty")
	_check(game_state.difficulty_id == &"normal", "start_new_game should fall back to normal for an unresolved difficulty_id")


func _test_save_load_round_trips_difficulty_id() -> void:
	const SLOT := 92
	turn_manager.start_new_game(&"nova_republic", &"hard")
	var save_errors: PackedStringArray = turn_manager.save_game(SLOT)
	_check(save_errors.is_empty(), "save failed: %s" % save_errors)
	game_state.difficulty_id = &"easy"
	var load_errors: PackedStringArray = turn_manager.load_game(SLOT)
	_check(load_errors.is_empty(), "load failed: %s" % load_errors)
	_check(game_state.difficulty_id == &"hard", "difficulty_id did not round-trip through save/load")
	var path := "user://saves/slot_%02d.json" % SLOT
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _test_hp_multiplier_scales_only_non_player_units() -> void:
	turn_manager.start_new_game(&"nova_republic", &"hard")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var battle_map := game_state.master_data.battle_maps[&"standard_battle_map"] as BattleMapDef
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"combat_modifiers_test", 1, Vector3(-400, 0, 0), Vector3(400, 0, 0), battle_map,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return
	_check(battle.difficulty != null and battle.difficulty.id == &"hard", "battle should have snapshotted the hard difficulty")

	var unit_def := battle.unit_defs[&"nova_scout"] as UnitDef
	var attacker_unit := battle.unit_states_by_id[attacker.unit.instance_id] as BattleUnitState
	var defender_unit := battle.unit_states_by_id[defender.unit.instance_id] as BattleUnitState
	_check(attacker_unit.max_hp == unit_def.max_hp,
		"the player's own unit must not be scaled by difficulty, got %d expected %d" % [attacker_unit.max_hp, unit_def.max_hp])
	var expected_enemy_hp := roundi(float(unit_def.max_hp) * 1.25)
	_check(defender_unit.max_hp == expected_enemy_hp,
		"the enemy unit's max_hp should scale by hard's 1.25x multiplier, got %d expected %d" % [defender_unit.max_hp, expected_enemy_hp])
	_check(defender_unit.current_hp == defender_unit.max_hp, "a freshly-rolled-out enemy unit should start at its (scaled) full HP")


func _test_firepower_and_accuracy_evasion_scale_only_non_player_factions() -> void:
	var battle := BattleRuntimeState.new()
	battle.player_faction_id = &"nova_republic"
	battle.difficulty = game_state.master_data.difficulties[&"hard"] as DifficultyDef

	_check(is_equal_approx(battle.firepower_multiplier(&"nova_republic"), 1.0), "the player faction must never be scaled by difficulty")
	_check(is_equal_approx(battle.firepower_multiplier(&"crimson_empire"), 1.25), "a non-player faction should get hard's firepower multiplier")
	_check(battle.accuracy_add(&"nova_republic") == 0, "the player faction must not get a difficulty accuracy bonus")
	_check(battle.accuracy_add(&"crimson_empire") == 15, "a non-player faction should get hard's accuracy_add")
	_check(battle.evasion_add(&"nova_republic") == 0, "the player faction must not get a difficulty evasion bonus")
	_check(battle.evasion_add(&"crimson_empire") == 15, "a non-player faction should get hard's evasion_add")
	_check(is_equal_approx(battle.hp_multiplier(&"nova_republic"), 1.0), "the player faction must not get a difficulty HP multiplier")
	_check(is_equal_approx(battle.hp_multiplier(&"crimson_empire"), 1.25), "a non-player faction should get hard's HP multiplier")


func _test_environment_aptitude_accuracy_and_evasion_additions() -> void:
	var battle := BattleRuntimeState.new()
	var unit_def := UnitDef.new()
	battle.environment = GameEnums.EnvironmentType.SPACE

	unit_def.space_aptitude = GameEnums.EnvironmentAptitude.PROFICIENT
	_check(battle.environment_aptitude_accuracy_add(unit_def) == 10 and battle.environment_aptitude_evasion_add(unit_def) == 10,
		"PROFICIENT aptitude should add +10 to both accuracy and evasion")

	unit_def.space_aptitude = GameEnums.EnvironmentAptitude.STANDARD
	_check(battle.environment_aptitude_accuracy_add(unit_def) == 0 and battle.environment_aptitude_evasion_add(unit_def) == 0,
		"STANDARD aptitude should add nothing")

	unit_def.space_aptitude = GameEnums.EnvironmentAptitude.POOR
	_check(battle.environment_aptitude_accuracy_add(unit_def) == -10 and battle.environment_aptitude_evasion_add(unit_def) == -10,
		"POOR aptitude should subtract 10 from both accuracy and evasion")

	battle.environment = GameEnums.EnvironmentType.GROUND
	unit_def.ground_aptitude = GameEnums.EnvironmentAptitude.PROFICIENT
	_check(battle.environment_aptitude_accuracy_add(unit_def) == 10,
		"the aptitude read must match the battle's own environment field (ground_aptitude here, not the still-POOR space_aptitude)")


func _finish() -> void:
	if failures.is_empty():
		print("combat_modifiers_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("combat_modifiers_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
