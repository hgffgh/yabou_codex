class_name BattleRuntimeFactory
extends RefCounted

const SQUAD_SPACING := 100.0

func create_from_pending(
	pending: Dictionary,
	campaign: CampaignRuntimeState,
	battle_id: StringName,
	rng_state: int,
	attacker_spawn: Vector3,
	defender_spawn: Vector3,
	battle_map: BattleMapDef = null,
) -> Dictionary:
	var errors := PackedStringArray()
	if pending.get("type", "") != "squad_battle_pending": errors.append("battle factory: pending type is invalid")
	if battle_id.is_empty(): errors.append("battle factory: battle_id must not be empty")
	var state := BattleRuntimeState.new()
	state.battle_id = battle_id
	state.region_id = StringName(pending.get("region_id", ""))
	state.attacker_faction_id = StringName(pending.get("attacker_id", ""))
	state.defender_faction_id = StringName(pending.get("defender_id", ""))
	state.attacker_squad_ids = _sorted_ids(pending.get("attacker_squad_ids", []))
	state.defender_squad_ids = _sorted_ids(pending.get("defender_squad_ids", []))
	state.rng_state = rng_state
	var game_state: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if game_state != null:
		state.unit_defs = game_state.master_data.units
		state.weapon_defs = game_state.master_data.weapons
		state.pilot_defs = game_state.master_data.pilots
		state.support_skill_defs = game_state.master_data.support_skills
	if battle_map != null:
		state.battle_map_id = battle_map.id
		state.attacker_hq_id = battle_map.attacker_hq_id
		state.defender_hq_id = battle_map.defender_hq_id
		attacker_spawn = Vector3(battle_map.attacker_spawn_transform.origin.x, battle_map.attacker_spawn_transform.origin.z, 0.0)
		defender_spawn = Vector3(battle_map.defender_spawn_transform.origin.x, battle_map.defender_spawn_transform.origin.z, 0.0)
	if state.region_id.is_empty() or state.attacker_faction_id.is_empty() or state.defender_faction_id.is_empty(): errors.append("battle factory: region and factions must resolve")
	if state.attacker_faction_id == state.defender_faction_id: errors.append("battle factory: battle factions must differ")
	if state.attacker_squad_ids.is_empty() or state.defender_squad_ids.is_empty(): errors.append("battle factory: both sides need at least one squad")
	var seen := {}
	_validate_side(state.attacker_squad_ids, state.attacker_faction_id, state.region_id, true, campaign, seen, errors)
	_validate_side(state.defender_squad_ids, state.defender_faction_id, state.region_id, false, campaign, seen, errors)
	if not errors.is_empty():
		errors.sort()
		return {"state": null, "errors": errors}
	_build_side(state, state.attacker_squad_ids, campaign, attacker_spawn, true)
	_build_side(state, state.defender_squad_ids, campaign, defender_spawn, false)
	if battle_map != null:
		_build_control_points(state, battle_map)
	return {"state": state, "errors": errors}

func _build_control_points(state: BattleRuntimeState, battle_map: BattleMapDef) -> void:
	var point_ids: Array[StringName] = [battle_map.attacker_hq_id, battle_map.defender_hq_id]
	point_ids.append_array(battle_map.control_point_ids)
	for point_id: StringName in point_ids:
		var point_def := _registry_control_point(point_id)
		if point_def == null:
			continue
		var point := BattleControlPointState.new()
		point.control_point_id = point_id
		if point_id == battle_map.attacker_hq_id: point.owner_faction_id = state.attacker_faction_id
		elif point_id == battle_map.defender_hq_id: point.owner_faction_id = state.defender_faction_id
		state.control_point_states[point_id] = point
		state.control_point_defs_by_id[point_id] = point_def

func _registry_control_point(point_id: StringName) -> BattleControlPointDef:
	var game_state: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if game_state == null:
		return null
	return game_state.master_data.battle_control_points.get(point_id) as BattleControlPointDef

func _validate_side(ids: Array[StringName], faction_id: StringName, region_id: StringName, attacker: bool, campaign: CampaignRuntimeState, seen: Dictionary, errors: PackedStringArray) -> void:
	for squad_id: StringName in ids:
		if seen.has(squad_id): errors.append("battle factory: duplicate squad_id '%s'" % squad_id); continue
		seen[squad_id] = true
		var squad := campaign.get_squad(squad_id)
		if squad == null or squad.owner_faction_id != faction_id or squad.region_id != region_id:
			errors.append("battle factory: squad '%s' does not match faction and region" % squad_id); continue
		if attacker and squad.move_origin_region_id.is_empty(): errors.append("battle factory: attacker squad requires a retreat origin")
		for unit_id: StringName in squad.unit_instance_ids:
			var unit := campaign.get_unit(unit_id)
			if unit == null or unit.squad_id != squad_id or unit.slot_index != squad.get_slot_index(unit_id): errors.append("battle factory: unit graph is inconsistent")

func _build_side(state: BattleRuntimeState, ids: Array[StringName], campaign: CampaignRuntimeState, spawn: Vector3, attacker: bool) -> void:
	for index in range(ids.size()):
		var strategic := campaign.get_squad(ids[index])
		var battle_squad := BattleSquadState.new()
		battle_squad.squad_id = strategic.squad_id
		battle_squad.faction_id = strategic.owner_faction_id
		battle_squad.spawn_position = spawn + Vector3(0.0, float(index) * SQUAD_SPACING, 0.0)
		battle_squad.world_position = battle_squad.spawn_position
		battle_squad.destination = battle_squad.spawn_position
		battle_squad.retreat_region_id = strategic.move_origin_region_id if attacker else &""
		battle_squad.policy = strategic.battle_policy
		battle_squad.intel_revision = strategic.intel_revision
		battle_squad.leader_command = 100
		battle_squad.unit_instance_ids = strategic.unit_instance_ids.duplicate()
		state.squad_states_by_id[battle_squad.squad_id] = battle_squad
		for unit_id: StringName in strategic.unit_instance_ids:
			var strategic_unit := campaign.get_unit(unit_id)
			var battle_unit := BattleUnitState.new()
			battle_unit.unit_instance_id = unit_id
			battle_unit.unit_def_id = strategic_unit.unit_def_id
			battle_unit.pilot_id = strategic_unit.pilot_id
			battle_unit.squad_id = strategic.squad_id
			battle_unit.slot_index = strategic_unit.slot_index
			battle_unit.initial_hp = strategic_unit.current_hp
			battle_unit.initial_en = strategic_unit.current_en
			battle_unit.current_hp = strategic_unit.current_hp
			battle_unit.current_en = strategic_unit.current_en
			var unit_def := state.unit_defs.get(strategic_unit.unit_def_id) as UnitDef
			if unit_def != null:
				battle_unit.max_hp = unit_def.max_hp
				battle_unit.max_en = unit_def.max_en
			var pilot_def := state.pilot_defs.get(strategic_unit.pilot_id) as PilotDef
			if pilot_def != null:
				battle_unit.shooting = pilot_def.initial_shooting
				battle_unit.melee = pilot_def.initial_melee
				battle_unit.defense = pilot_def.initial_defense
				battle_unit.reaction = pilot_def.initial_reaction
				battle_unit.command = pilot_def.initial_command
			if strategic.leader_pilot_id == strategic_unit.pilot_id and not strategic_unit.pilot_id.is_empty():
				battle_squad.leader_unit_id = unit_id
				battle_squad.leader_command = battle_unit.command
			state.unit_states_by_id[unit_id] = battle_unit

func _sorted_ids(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for item: Variant in value: result.append(StringName(item))
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result
