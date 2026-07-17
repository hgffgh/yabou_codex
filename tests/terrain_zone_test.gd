extends SceneTree
## COMBAT_DETAIL_SPECIFICATION.md section 29: terrain zones (difficult
## terrain, cover, hazard, impassable) plus the previously-unwired
## environment-aptitude move multiplier this milestone also connected.
## Exercises the real standard_battle_map.tres zones (standard_cover_ridge,
## standard_difficult_marsh, standard_hazard_field,
## standard_impassable_wreckage) rather than synthetic fixtures, so the
## data-loading/validation path is covered too.

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("terrain_zone_test: GameState autoload is unavailable")
		quit(1)
		return
	_check(game_state.master_data_errors.is_empty(), "terrain zone data failed master-data validation: %s" % game_state.master_data_errors)
	_check(game_state.master_data.terrain_zones.size() == 4, "expected exactly 4 terrain zones in the standard dataset")

	_test_terrain_zone_at_lookup()
	_test_difficult_terrain_slows_movement()
	_test_environment_aptitude_affects_speed()
	_test_cover_evasion_bonus_ignores_melee()
	_test_hazard_terrain_drains_hp_but_never_below_one()
	_test_hazard_stops_during_auto_resolve()
	_test_hazard_stops_while_paused()
	_test_impassable_zone_blocks_position()
	_test_sensor_los_blocked_by_obstacle()
	_finish()


func _test_terrain_zone_at_lookup() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var cover_zone := battle.terrain_zone_at(Vector3(-150, 100, 0))
	_check(cover_zone != null and cover_zone.id == &"standard_cover_ridge", "a position inside the cover zone's radius should resolve to it")
	var nowhere := battle.terrain_zone_at(Vector3(-150, 100 - 200, 0))
	_check(nowhere == null, "a position outside every zone's radius should resolve to null")


## nova_scout's speed / 10.0 with STANDARD aptitude (multiplier 1.0) inside
## standard_difficult_marsh (move_multiplier 0.8) should be exactly 0.8x
## the same unit's speed outside any zone.
func _test_difficult_terrain_slows_movement() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var squad := _only_squad(battle, battle.attacker_squad_ids)
	squad.world_position = Vector3(300, 300, 0)
	var speed_outside: float = battle._squad_speed(squad)
	squad.world_position = Vector3(150, -120, 0)
	var speed_inside: float = battle._squad_speed(squad)
	_check(speed_outside > 0.0, "setup: squad should have positive speed outside any zone")
	_check(is_equal_approx(speed_inside, speed_outside * 0.8),
		"difficult terrain should scale speed by 0.8x (outside=%.3f inside=%.3f)" % [speed_outside, speed_inside])


## GameConstants.APTITUDE_MOVE_MULTIPLIERS existed but was never read by
## anything before this milestone wired it into _squad_speed alongside the
## terrain multiplier it's meant to compose with.
func _test_environment_aptitude_affects_speed() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var squad := _only_squad(battle, battle.attacker_squad_ids)
	squad.world_position = Vector3(300, 300, 0)
	var unit_def := battle.unit_defs[&"nova_scout"] as UnitDef
	var original_aptitude := unit_def.space_aptitude
	battle.environment = GameEnums.EnvironmentType.SPACE

	unit_def.space_aptitude = GameEnums.EnvironmentAptitude.STANDARD
	var standard_speed: float = battle._squad_speed(squad)
	unit_def.space_aptitude = GameEnums.EnvironmentAptitude.POOR
	var poor_speed: float = battle._squad_speed(squad)
	unit_def.space_aptitude = original_aptitude

	_check(is_equal_approx(poor_speed, standard_speed * GameConstants.APTITUDE_MOVE_MULTIPLIERS[GameEnums.EnvironmentAptitude.POOR]),
		"POOR environment aptitude should scale battlefield move speed by its configured multiplier (standard=%.3f poor=%.3f)" % [standard_speed, poor_speed])


func _test_cover_evasion_bonus_ignores_melee() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var target_squad := _only_squad(battle, battle.attacker_squad_ids)
	target_squad.world_position = Vector3(-150, 100, 0)

	var ranged_weapon := WeaponDef.new()
	ranged_weapon.damage_attribute = GameEnums.DamageAttribute.BALLISTIC
	var melee_weapon := WeaponDef.new()
	melee_weapon.damage_attribute = GameEnums.DamageAttribute.MELEE

	_check(BattleCombatSystem._cover_evasion_bonus(battle, target_squad, ranged_weapon) == 15,
		"a squad standing in standard_cover_ridge should grant +15 evasion against a non-melee attack")
	_check(BattleCombatSystem._cover_evasion_bonus(battle, target_squad, melee_weapon) == 0,
		"melee attribute attacks must ignore cover entirely")

	target_squad.world_position = Vector3(300, 300, 0)
	_check(BattleCombatSystem._cover_evasion_bonus(battle, target_squad, ranged_weapon) == 0,
		"a squad outside any cover zone should get no evasion bonus")


func _test_hazard_terrain_drains_hp_but_never_below_one() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var squad := _only_squad(battle, battle.attacker_squad_ids)
	var unit := _first_unit(battle, battle.attacker_squad_ids)
	squad.world_position = Vector3(0, 200, 0)
	squad.destination = squad.world_position
	squad.movement_ai_disabled = true
	_pin_defender_far_away(battle)
	var hp_before := unit.current_hp

	for _tick in range(100):
		battle.advance_time(1.0)
		if battle.result != null:
			break

	_check(unit.current_hp < hp_before, "a unit standing in standard_hazard_field for a long time should have lost HP")
	_check(unit.current_hp >= 1, "terrain hazard damage must never bring a unit below 1 HP")
	_check(not unit.destroyed_this_battle, "terrain hazard damage alone must never mark a unit destroyed")
	_check(battle.result == null, "terrain hazard damage alone must never finalize the battle within 100 seconds")


func _test_hazard_stops_during_auto_resolve() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var squad := _only_squad(battle, battle.attacker_squad_ids)
	var unit := _first_unit(battle, battle.attacker_squad_ids)
	squad.world_position = Vector3(0, 200, 0)
	squad.destination = squad.world_position
	squad.movement_ai_disabled = true
	_pin_defender_far_away(battle)
	battle.is_auto_resolving = true
	var hp_before := unit.current_hp
	for _tick in range(60):
		battle.advance_time(1.0)
	_check(unit.current_hp == hp_before, "hazard damage must not apply while is_auto_resolving is true")


func _test_hazard_stops_while_paused() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var squad := _only_squad(battle, battle.attacker_squad_ids)
	var unit := _first_unit(battle, battle.attacker_squad_ids)
	squad.world_position = Vector3(0, 200, 0)
	squad.destination = squad.world_position
	squad.movement_ai_disabled = true
	_pin_defender_far_away(battle)
	battle.time_scale = 0.0
	var hp_before := unit.current_hp
	for _tick in range(60):
		battle.advance_time(1.0)
	_check(unit.current_hp == hp_before, "hazard damage must not apply while the battle is paused (time_scale 0)")


func _test_impassable_zone_blocks_position() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	_check(not battle.is_position_passable(Vector3(0, -250, 0)),
		"a position inside standard_impassable_wreckage must not be passable")
	_check(battle.is_position_passable(Vector3(300, 300, 0)),
		"a position outside every zone must be passable")


## standard_impassable_wreckage (real x=0,z=-250, radius 60) sits directly
## between (-50,-250) and (50,-250) -- 100m apart, well inside default
## sensor range -- so it should block detection there but not once one
## squad is repositioned off that line at the same distance.
func _test_sensor_los_blocked_by_obstacle() -> void:
	var battle := _build_battle()
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)

	attacker_squad.world_position = Vector3(-50, -250, 0)
	defender_squad.world_position = Vector3(50, -250, 0)
	battle._advance_intel_sensing()
	_check(not attacker_squad.currently_sensed and not defender_squad.currently_sensed,
		"an obstacle directly on the line between two squads should block sensor detection")

	attacker_squad.world_position = Vector3(-50, 50, 0)
	defender_squad.world_position = Vector3(50, 50, 0)
	attacker_squad.revealed_until_world_sec = 0.0
	defender_squad.revealed_until_world_sec = 0.0
	battle._advance_intel_sensing()
	_check(attacker_squad.currently_sensed and defender_squad.currently_sensed,
		"the same distance with a clear line of sight should sense normally")


func _build_battle() -> BattleRuntimeState:
	game_state.start_new_game(&"nova_republic")
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
		pending, game_state.campaign_runtime, &"terrain_zone_test", 1, Vector3(-400, 0, 0), Vector3(400, 0, 0), battle_map,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	_check((created.state as BattleRuntimeState).terrain_zone_defs.size() == 4, "battle should have inherited all 4 zones from standard_battle_map")
	return created.state as BattleRuntimeState


## Prevents the AI-controlled, un-repositioned defender squad from closing
## the distance and starting a real fight during a hazard test's advance_time
## loop, which would otherwise contaminate HP-loss assertions with genuine
## combat damage instead of the terrain-hazard tick under test.
func _pin_defender_far_away(battle: BattleRuntimeState) -> void:
	var defender := _only_squad(battle, battle.defender_squad_ids)
	defender.world_position = Vector3(400, -400, 0)
	defender.destination = defender.world_position
	defender.movement_ai_disabled = true


func _only_squad(battle: BattleRuntimeState, squad_ids: Array[StringName]) -> BattleSquadState:
	return battle.squad_states_by_id[squad_ids[0]] as BattleSquadState


func _first_unit(battle: BattleRuntimeState, squad_ids: Array[StringName]) -> BattleUnitState:
	var squad := battle.squad_states_by_id[squad_ids[0]] as BattleSquadState
	return battle.unit_states_by_id[squad.unit_instance_ids[0]] as BattleUnitState


func _finish() -> void:
	if failures.is_empty():
		print("terrain_zone_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("terrain_zone_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
