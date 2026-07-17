extends SceneTree

var failures := PackedStringArray()
var registry := MasterDataRegistry.new()

func _initialize() -> void:
	registry.load_all()
	var first := _create_battle(2468)
	var second := _create_battle(2468)
	_check(first != null and second != null, "battle setup failed")
	if first != null and second != null:
		first.time_scale = 0.0
		first.advance_time(20.0)
		_check((first.unit_states_by_id[&"unit_00000001"] as BattleUnitState).action_gauge == 0.0, "pause advanced combat gauge")
		first.time_scale = 1.0
		first.advance_time(7.0)
		_check(first.combat_events.is_empty(), "unit attacked before gauge reached 100")
		first.advance_time(0.5)
		second.advance_time(7.5)
		var first_attacker := first.unit_states_by_id[&"unit_00000001"] as BattleUnitState
		var second_attacker := second.unit_states_by_id[&"unit_00000001"] as BattleUnitState
		_check(not first.combat_events.is_empty(), "ready unit did not fire in range (gauge %.2f)" % first_attacker.action_gauge)
		_check(first_attacker.current_en == first_attacker.initial_en - 20, "weapon EN cost was not consumed exactly once (%d/%d)" % [first_attacker.current_en, first_attacker.initial_en])
		_check(first_attacker.action_gauge == 0.0 and first_attacker.post_action_delay_sec == 1.0, "action reset or post-action delay is incorrect (%.2f/%.2f)" % [first_attacker.action_gauge, first_attacker.post_action_delay_sec])
		_check(first.rng_state == second.rng_state, "same seed did not preserve deterministic RNG state")
		_check(first_attacker.current_hp == second_attacker.current_hp, "same seed produced different combat damage")
	var large_step := _create_battle(97531)
	var small_steps := _create_battle(97531)
	if large_step != null and small_steps != null:
		large_step.advance_time(30.0)
		for _index in range(300): small_steps.advance_time(0.1)
		_check(_combat_snapshot(large_step) == _combat_snapshot(small_steps), "combat result changed with delta subdivision")
	if failures.is_empty():
		print("battle_combat_system_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures: push_error("battle_combat_system_test: %s" % failure)
		quit(1)

func _create_battle(seed: int) -> BattleRuntimeState:
	var campaign := CampaignRuntimeState.new()
	var regions := {&"nova_capital": true, &"crimson_border": true}
	var attacker: Dictionary = campaign.rollout_unit(&"nova_scout", &"nova_republic", &"nova_capital", registry, regions)
	var defender: Dictionary = campaign.rollout_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border", registry, regions)
	attacker.squad.move_origin_region_id = &"nova_capital"
	attacker.squad.region_id = &"crimson_border"
	var pending := {"type": "squad_battle_pending", "region_id": &"crimson_border", "attacker_id": &"nova_republic", "defender_id": &"crimson_empire", "attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id]}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(pending, campaign, &"combat_test", seed, Vector3(0, 0, 0), Vector3(50, 0, 0))
	if not created.errors.is_empty():
		failures.append("factory errors: %s" % created.errors)
		return null
	var battle := created.state as BattleRuntimeState
	battle.unit_defs = registry.units
	battle.weapon_defs = registry.weapons
	return battle

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _combat_snapshot(battle: BattleRuntimeState) -> Dictionary:
	var units := {}
	for unit_id: StringName in battle.unit_states_by_id:
		var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		units[unit_id] = [unit.current_hp, unit.current_en, unit.destroyed_this_battle]
	return {"units": units, "rng_state": battle.rng_state, "reason": battle.result.reason if battle.result != null else &""}
