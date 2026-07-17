extends SceneTree

var failures := PackedStringArray()
var game_state: Node

func _initialize() -> void:
	await process_frame
	game_state = root.get_node("GameState")
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(pending, game_state.campaign_runtime, &"battle_view_test", 7, Vector3(-400, 0, 0), Vector3(400, 0, 0))
	var battle := created.state as BattleRuntimeState
	var view := BattlePrototypeView.new()
	view.setup(battle)
	root.add_child(view)
	await process_frame
	await process_frame
	_check(view.arena != null and view.status_label != null, "battle view did not construct its arena and HUD")
	_check(view.battle_viewport != null and view.world_root != null and view.camera != null and view.camera.current, "battle view did not construct an active 3D world and camera")
	_check(view.squad_visuals.size() == 2, "battle view did not create one 3D visual root per squad")
	_check(view.unit_visuals.size() == battle.unit_states_by_id.size(), "battle view did not create one robot visual per unit")
	_check(view.hp_bar_fills.size() == battle.unit_states_by_id.size() and view.en_bar_fills.size() == battle.unit_states_by_id.size(), "battle view did not create HP/EN bars per unit")
	_check(_has_property(view, &"prebattle_panel"), "battle view has no pre-battle confirmation panel")
	_check(_has_property(view, &"battle_started"), "battle view does not expose its confirmed-start state")
	var prebattle_elapsed := battle.elapsed_world_sec
	await process_frame
	await process_frame
	_check(battle.elapsed_world_sec == prebattle_elapsed, "battle time advanced before pre-battle confirmation")
	if view.has_method("_confirm_battle_start"):
		view.call("_confirm_battle_start")
		await process_frame
		_check(bool(view.get("battle_started")), "pre-battle confirmation did not start the battle")
		_check(battle.elapsed_world_sec > prebattle_elapsed, "battle time did not advance after pre-battle confirmation")
	else:
		_check(false, "battle view has no pre-battle confirmation action")
	var attacker_unit := battle.unit_states_by_id[attacker.unit.instance_id] as BattleUnitState
	attacker_unit.current_hp = attacker_unit.max_hp / 2
	attacker_unit.current_en = attacker_unit.max_en / 2
	view._sync_unit_status()
	_check(is_equal_approx((view.hp_bar_fills[attacker.unit.instance_id] as MeshInstance3D).scale.x, 0.5), "HP bar did not follow runtime HP")
	_check(is_equal_approx((view.en_bar_fills[attacker.unit.instance_id] as MeshInstance3D).scale.x, 0.5), "EN bar did not follow runtime EN")
	battle.combat_events = [{"type": &"shot", "source_unit_id": attacker.unit.instance_id, "target_unit_id": defender.unit.instance_id, "weapon_id": &"light_autocannon", "hit": true, "critical": false, "damage": 25}]
	view._sync_combat_events()
	_check(view.processed_combat_event_count == 1 and not view.transient_effects.is_empty(), "shot event did not create visual feedback")
	attacker_unit.current_hp = 0
	view._sync_unit_status()
	_check(not (view.unit_visuals[attacker.unit.instance_id] as Node3D).visible, "destroyed unit visual remained visible")
	var attacker_state := battle.squad_states_by_id[attacker.squad.squad_id] as BattleSquadState
	var before := attacker_state.world_position
	battle.time_scale = 0.0
	var elapsed_before := battle.elapsed_world_sec
	attacker_state.destination = Vector3.ZERO
	await process_frame
	_check(attacker_state.world_position == before and battle.elapsed_world_sec == elapsed_before, "paused battle advanced movement or time")
	var finalize_errors := battle.finalize(battle.attacker_faction_id, battle.defender_faction_id, &"annihilation")
	_check(finalize_errors.is_empty(), "smoke fixture could not finalize battle for result confirmation")
	if view.has_method("_show_battle_result"):
		view.call("_show_battle_result")
	else:
		view._process(0.0)
	_check(_has_property(view, &"result_panel") and view.get("result_panel") != null and (view.get("result_panel") as Control).visible, "battle result panel was not displayed")
	_check(not battle.applied_to_campaign, "battle result reached TurnManager before player confirmation")
	_check(not view.is_queued_for_deletion(), "battle view closed before result confirmation")
	if view.has_method("_confirm_battle_result"):
		view.call("_confirm_battle_result")
		_check(battle.applied_to_campaign, "confirmed result was not completed through TurnManager")
	else:
		_check(false, "battle view has no result confirmation action")
	if not view.is_queued_for_deletion(): view.queue_free()
	if failures.is_empty():
		print("battle_view_smoke_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures: push_error("battle_view_smoke_test: %s" % failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if property.get("name") == property_name:
			return true
	return false
