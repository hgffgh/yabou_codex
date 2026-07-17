extends SceneTree

var failures := PackedStringArray()
var registry := MasterDataRegistry.new()
var regions := {&"nova_capital": true, &"crimson_border": true}

func _initialize() -> void:
	registry.load_all()
	var campaign := CampaignRuntimeState.new()
	var attacker: Dictionary = campaign.rollout_unit(&"nova_scout", &"nova_republic", &"nova_capital", registry, regions)
	var defender: Dictionary = campaign.rollout_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border", registry, regions)
	attacker.squad.move_origin_region_id = &"nova_capital"
	attacker.squad.region_id = &"crimson_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id],
		"defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(pending, campaign, &"battle_00000001", 12345, Vector3(-400, 0, 0), Vector3(400, 0, 0))
	_check(created.errors.is_empty(), "valid battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	_check(battle != null and battle.rng_state == 12345, "battle scalar state was not initialized")
	if battle != null:
		var battle_attacker := battle.unit_states_by_id[attacker.unit.instance_id] as BattleUnitState
		_check(battle_attacker.current_hp == attacker.unit.current_hp and battle_attacker.slot_index == 0, "unit snapshot did not preserve HP and slot")
		battle_attacker.current_hp = 1
		_check(attacker.unit.current_hp != 1, "battle HP mutation leaked into campaign state")
		var battle_squad := battle.squad_states_by_id[attacker.squad.squad_id] as BattleSquadState
		_check(battle_squad.world_position == Vector3(-400, 0, 0) and battle_squad.retreat_region_id == &"nova_capital", "attacker spawn or retreat origin was incorrect")
		_check(battle.request_retreat(attacker.squad.squad_id), "retreat request failed")
		battle.advance_time(9.9)
		_check(battle.result == null, "retreat completed before ten seconds")
		battle.advance_time(0.1)
		_check(battle.result != null and battle.result.reason == &"retreat" and battle.result.winner_faction_id == &"crimson_empire", "retreat did not finalize defender victory")
	var invalid := pending.duplicate(true)
	invalid.attacker_squad_ids = [&"missing_squad"]
	var failed: Dictionary = BattleRuntimeFactory.new().create_from_pending(invalid, campaign, &"battle_bad", 1, Vector3.ZERO, Vector3.ONE)
	_check(failed.state == null and not failed.errors.is_empty(), "invalid squad reference created a partial battle")
	if failures.is_empty():
		print("battle_runtime_state_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures: push_error("battle_runtime_state_test: %s" % failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
