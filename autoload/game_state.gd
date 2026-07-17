extends Node
## Single source of truth for factions/regions/turn state at runtime.
## Static content (Region/Faction defs) is loaded once at boot by scanning
## res://data/; runtime state is rebuilt on start_new_game().

signal turn_advanced(turn_number: int)
signal region_ownership_changed(region_id: StringName, old_owner: StringName, new_owner: StringName)
signal faction_eliminated(faction_id: StringName)
signal game_over(reason: String, standings: Array)
signal supply_network_changed(faction_id: StringName)

var region_defs: Dictionary = {}   # StringName -> RegionDef
var faction_defs: Dictionary = {}  # StringName -> FactionDef
var campaign_config: CampaignConfig
var master_data := MasterDataRegistry.new()
var master_data_errors: PackedStringArray = []
var campaign_runtime := CampaignRuntimeState.new()
var supplied_region_ids_by_faction: Dictionary = {}

var turn_number: int = 1
var factions: Dictionary = {}  # StringName -> Faction
var regions: Dictionary = {}   # StringName -> Region
var player_faction_id: StringName = &""
var is_game_over: bool = false
var last_game_over_reason: String = ""
var last_game_over_standings: Array = []

func _ready() -> void:
	_load_static_data()

func _load_static_data() -> void:
	master_data.load_all()
	if OS.is_debug_build():
		master_data_errors = MasterDataValidator.new().validate(master_data)
		if master_data_errors.is_empty():
			print("GameState: master-data validation succeeded")
		else:
			for validation_error: String in master_data_errors:
				push_error("GameState master data: %s" % validation_error)
	region_defs = _load_resources_in_dir("res://data/regions/")
	faction_defs = _load_resources_in_dir("res://data/factions/")
	campaign_config = load("res://data/campaign_config.tres")

func _load_resources_in_dir(path: String) -> Dictionary:
	var result := {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("GameState: cannot open directory %s" % path)
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: Resource = load(path + file_name)
			if res != null and "id" in res:
				result[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	return result

func start_new_game(chosen_player_faction_id: StringName) -> void:
	turn_number = 1
	is_game_over = false
	player_faction_id = chosen_player_faction_id
	campaign_runtime.reset()
	factions.clear()
	regions.clear()

	for id in faction_defs:
		var f := Faction.new(faction_defs[id])
		f.is_ai_controlled = id != chosen_player_faction_id
		factions[id] = f

	for id in region_defs:
		regions[id] = Region.new(region_defs[id])
	_seed_initial_squads()
	_seed_initial_pilots()
	recompute_all_supply_networks()

	turn_advanced.emit(turn_number)

func advance_turn() -> void:
	turn_number += 1
	turn_advanced.emit(turn_number)

func get_region(id: StringName) -> Region:
	return regions.get(id)

func get_faction(id: StringName) -> Faction:
	return factions.get(id)

func recompute_all_supply_networks() -> void:
	supplied_region_ids_by_faction.clear()
	for faction_id: StringName in factions.keys():
		recompute_supply_network(faction_id)

func recompute_supply_network(faction_id: StringName) -> Array[StringName]:
	var supplied: Array[StringName] = []
	var faction_def := faction_defs.get(faction_id) as FactionDef
	if faction_def == null:
		supplied_region_ids_by_faction[faction_id] = supplied
		return supplied
	var capital := get_region(faction_def.starting_region_id)
	if capital == null or capital.owner_faction_id != faction_id:
		supplied_region_ids_by_faction[faction_id] = supplied
		supply_network_changed.emit(faction_id)
		return supplied
	var frontier: Array[StringName] = [faction_def.starting_region_id]
	var visited := {faction_def.starting_region_id: true}
	while not frontier.is_empty():
		var region_id: StringName = frontier.pop_front()
		supplied.append(region_id)
		var region_def := region_defs[region_id] as RegionDef
		var neighbors := region_def.neighbor_ids.duplicate()
		neighbors.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for neighbor_id: StringName in neighbors:
			if visited.has(neighbor_id):
				continue
			visited[neighbor_id] = true
			var neighbor := get_region(neighbor_id)
			if neighbor != null and neighbor.owner_faction_id == faction_id:
				frontier.append(neighbor_id)
	supplied.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	supplied_region_ids_by_faction[faction_id] = supplied
	supply_network_changed.emit(faction_id)
	return supplied

func is_region_supplied(region_id: StringName, faction_id: StringName) -> bool:
	var supplied: Array = supplied_region_ids_by_faction.get(faction_id, [])
	return supplied.has(region_id)

func resupply_unit_en(instance_id: StringName, acting_faction_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var unit := campaign_runtime.get_unit(instance_id)
	var squad := campaign_runtime.get_squad(unit.squad_id) if unit != null else null
	var unit_def := master_data.units.get(unit.unit_def_id) as UnitDef if unit != null else null
	if unit == null or squad == null or unit_def == null:
		errors.append("resupply: unit, squad, or unit definition does not resolve")
	elif unit.owner_faction_id != acting_faction_id or squad.owner_faction_id != acting_faction_id:
		errors.append("resupply: unit is not owned by the acting faction")
	elif not is_region_supplied(squad.region_id, acting_faction_id):
		errors.append("resupply: squad region is not connected to supply")
	if not errors.is_empty():
		return errors
	unit.current_en = unit_def.max_en
	return errors

func detect_squad_conflicts(active_faction_id: StringName) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var region_ids := regions.keys()
	region_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for region_id: StringName in region_ids:
		var attacker_squad_ids: Array[StringName] = []
		var defenders_by_faction := {}
		for squad: SquadState in campaign_runtime.get_squads_in_region(region_id):
			if not _squad_can_enter_combat(squad):
				continue
			if squad.owner_faction_id == active_faction_id and not squad.move_origin_region_id.is_empty():
				attacker_squad_ids.append(squad.squad_id)
			elif squad.owner_faction_id != active_faction_id:
				if not defenders_by_faction.has(squad.owner_faction_id):
					defenders_by_faction[squad.owner_faction_id] = [] as Array[StringName]
				(defenders_by_faction[squad.owner_faction_id] as Array[StringName]).append(squad.squad_id)
		if attacker_squad_ids.is_empty():
			continue
		attacker_squad_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		var defender_faction_ids := defenders_by_faction.keys()
		defender_faction_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		if defender_faction_ids.is_empty():
			var region := get_region(region_id)
			if region.owner_faction_id != active_faction_id:
				set_region_owner(region_id, active_faction_id)
				results.append({"type": "auto_capture", "region_id": region_id, "faction_id": active_faction_id, "squad_ids": attacker_squad_ids})
			continue
		if defender_faction_ids.size() == 1:
			var defender_id: StringName = defender_faction_ids[0]
			results.append({
				"type": "squad_battle_pending", "region_id": region_id,
				"attacker_id": active_faction_id, "defender_id": defender_id,
				"attacker_squad_ids": attacker_squad_ids,
				"defender_squad_ids": defenders_by_faction[defender_id],
			})
		else:
			results.append({
				"type": "multi_faction_battle_pending", "region_id": region_id,
				"attacker_id": active_faction_id, "attacker_squad_ids": attacker_squad_ids,
				"defender_faction_ids": defender_faction_ids,
			})
	return results

func apply_battle_result(battle: BattleRuntimeState) -> PackedStringArray:
	var errors := PackedStringArray()
	if battle == null or battle.result == null:
		errors.append("battle result: battle has not been finalized")
	elif battle.applied_to_campaign:
		errors.append("battle result: result was already applied")
	elif not regions.has(battle.region_id):
		errors.append("battle result: region does not resolve")
	for unit_id: StringName in battle.unit_states_by_id:
		if campaign_runtime.get_unit(unit_id) == null:
			errors.append("battle result: campaign unit '%s' does not resolve" % unit_id)
	if not errors.is_empty():
		return errors
	for unit_id: StringName in battle.unit_states_by_id:
		var battle_unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		var unit := campaign_runtime.get_unit(unit_id)
		var unit_def := master_data.units.get(unit.unit_def_id) as UnitDef
		unit.current_hp = clampi(battle_unit.current_hp, 0, unit_def.max_hp)
		unit.current_en = clampi(battle_unit.current_en, 0, unit_def.max_en)
	_apply_battle_unit_outcomes(battle)
	for squad_id: StringName in battle.attacker_squad_ids + battle.defender_squad_ids:
		var squad := campaign_runtime.get_squad(squad_id)
		if squad == null:
			continue
		if squad.owner_faction_id == battle.result.loser_faction_id and battle.result.reason in [&"retreat", &"timeout"]:
			var battle_squad := battle.squad_states_by_id[squad_id] as BattleSquadState
			if not battle_squad.retreat_region_id.is_empty() and regions.has(battle_squad.retreat_region_id):
				squad.region_id = battle_squad.retreat_region_id
		squad.move_origin_region_id = &""
		squad.planned_destination_region_id = &""
	if battle.result.winner_faction_id == battle.attacker_faction_id and battle.result.reason in [&"hq_capture", &"annihilation"]:
		set_region_owner(battle.region_id, battle.attacker_faction_id)
	battle.applied_to_campaign = true
	return errors

## Applies each participating pilot's accumulated battle EXP (destroy,
## support-success, round-participation, and victory/HQ-capture credit),
## then resolves every destroyed unit's fate. COMBAT_DETAIL_SPECIFICATION.md
## section 18 / STRATEGY_DETAIL_SPECIFICATION.md section 5.7: any destroyed
## unit's named pilot is injured for three turns regardless of which side
## won. The winner's own losses are "recovered" (kept as an unassigned
## DESTROYED_RECOVERED record, salvage for a future rebuild feature); the
## loser's losses are mostly permanent, except for a probabilistic ~10%
## roll per capturable destroyed unit (COMBAT_DETAIL_SPECIFICATION.md
## section 18: a 10% capture roll per destroyed enemy unit),
## using the battle's own deterministic RNG stream so results stay
## reproducible from the same seed. Units with UnitDef.capture_allowed ==
## false are never eligible (section 18: 0% for non-capturable units).
func _apply_battle_unit_outcomes(battle: BattleRuntimeState) -> void:
	_apply_battle_pilot_exp(battle)
	var winner_id := battle.result.winner_faction_id
	for unit_id: StringName in battle.result.destroyed_unit_ids:
		var unit := campaign_runtime.get_unit(unit_id)
		if unit == null:
			continue
		var pilot_id := unit.pilot_id
		if unit.owner_faction_id == winner_id:
			campaign_runtime.remove_unit_from_squad(unit_id)
			unit.condition = GameEnums.UnitCondition.DESTROYED_RECOVERED
			unit.current_hp = 0
			unit.current_en = 0
			unit.pilot_id = &""
			battle.result.recovered_unit_ids.append(unit_id)
		else:
			var unit_def := master_data.units.get(unit.unit_def_id) as UnitDef
			var captured := false
			if unit_def != null and unit_def.capture_allowed:
				var capture_roll := BattleCombatSystem.roll(battle, 100)
				if capture_roll < int(round(GameConstants.CAPTURE_ENEMY_UNIT_PCT * 100.0)):
					var capture_result := campaign_runtime.capture_unit(unit_id, winner_id, battle.region_id, master_data, region_defs)
					if capture_result.errors.is_empty():
						battle.result.captured_unit_ids.append(unit_id)
						captured = true
					else:
						push_error("battle result: capture failed for '%s': %s" % [unit_id, capture_result.errors])
			if not captured:
				campaign_runtime.remove_unit_from_squad(unit_id)
				campaign_runtime.units_by_id.erase(unit_id)
				battle.result.lost_unit_ids.append(unit_id)
		_apply_pilot_injury(pilot_id, battle.result)

## STRATEGY_DETAIL_SPECIFICATION.md section 5.3: base EXP is summed on
## BattleUnitState.exp_earned throughout the battle; the permanent profile
## EXP bonus (achievements) is applied last with ceil(). No achievement/
## profile system exists yet, so that bonus is a documented 0.0 placeholder.
func _apply_battle_pilot_exp(battle: BattleRuntimeState) -> void:
	const PERMANENT_EXP_BONUS_PCT := 0.0
	for unit_id: StringName in battle.unit_states_by_id:
		var battle_unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		if battle_unit.pilot_id.is_empty() or battle_unit.exp_earned <= 0:
			continue
		var pilot := campaign_runtime.get_pilot(battle_unit.pilot_id)
		if pilot == null:
			continue
		var final_exp := ceili(float(battle_unit.exp_earned) * (1.0 + PERMANENT_EXP_BONUS_PCT))
		pilot.current_exp += final_exp
		battle.result.pilot_exp[battle_unit.pilot_id] = int(battle.result.pilot_exp.get(battle_unit.pilot_id, 0)) + final_exp
		while pilot.level < GameConstants.PILOT_LEVEL_CAP:
			var required := GameConstants.pilot_exp_to_next_level(pilot.level)
			if required <= 0 or pilot.current_exp < required:
				break
			pilot.current_exp -= required
			pilot.level += 1

func _apply_pilot_injury(pilot_id: StringName, result: BattleResultState) -> void:
	if pilot_id.is_empty():
		return
	var pilot := campaign_runtime.get_pilot(pilot_id)
	if pilot == null:
		return
	pilot.injury_turns_remaining = GameConstants.PILOT_INJURY_TURNS
	pilot.assigned_unit_instance_id = &""
	result.injured_pilot_ids.append(pilot_id)

## Live, combat-capable squad IDs a faction currently has sitting in a
## region, re-derived fresh from campaign_runtime. Used to resolve a
## multi_faction_battle_pending contact as a sequence of pairwise battles,
## where attrition from an earlier sub-battle must carry into the next.
func combat_capable_squad_ids_in_region(region_id: StringName, faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for squad: SquadState in campaign_runtime.get_squads_in_region(region_id, faction_id):
		if _squad_can_enter_combat(squad):
			result.append(squad.squad_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result

func _squad_can_enter_combat(squad: SquadState) -> bool:
	if squad == null or squad.unit_instance_ids.is_empty():
		return false
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := campaign_runtime.get_unit(unit_id)
		if unit != null and unit.current_hp > 0 and unit.condition == GameEnums.UnitCondition.ACTIVE and unit.repair_turns_remaining == 0:
			return true
	return false

func start_unit_repair(instance_id: StringName, acting_faction_id: StringName) -> Dictionary:
	var errors := PackedStringArray()
	var unit := campaign_runtime.get_unit(instance_id)
	var squad := campaign_runtime.get_squad(unit.squad_id) if unit != null else null
	var unit_def := master_data.units.get(unit.unit_def_id) as UnitDef if unit != null else null
	var faction := get_faction(acting_faction_id)
	if unit == null or squad == null or unit_def == null or faction == null:
		errors.append("repair: unit, squad, unit definition, or faction does not resolve")
	elif unit.owner_faction_id != acting_faction_id or squad.owner_faction_id != acting_faction_id:
		errors.append("repair: unit is not owned by the acting faction")
	elif not is_region_supplied(squad.region_id, acting_faction_id):
		errors.append("repair: squad region is not connected to supply")
	elif unit.condition == GameEnums.UnitCondition.REPAIRING:
		errors.append("repair: unit is already repairing")
	elif unit.current_hp >= unit_def.max_hp:
		errors.append("repair: unit has no damage")
	if not errors.is_empty():
		return {"errors": errors, "funds_cost": 0, "materials_cost": 0, "turns": 0}
	var damage_ratio := float(unit_def.max_hp - unit.current_hp) / float(unit_def.max_hp)
	var funds_cost := ceili(float(GameConstants.UNIT_PRODUCTION_FUNDS[unit_def.size]) * damage_ratio * 0.25)
	var materials_cost := ceili(float(GameConstants.UNIT_PRODUCTION_MATERIALS[unit_def.size]) * damage_ratio * 0.25)
	var base_turns := ceili(float(GameConstants.UNIT_PRODUCTION_POWER[unit_def.size]) / 100.0)
	var repair_turns := maxi(1, ceili(float(base_turns) * damage_ratio))
	if faction.funds < funds_cost:
		errors.append("repair: insufficient funds")
	if faction.materials < materials_cost:
		errors.append("repair: insufficient materials")
	if not errors.is_empty():
		return {"errors": errors, "funds_cost": funds_cost, "materials_cost": materials_cost, "turns": repair_turns}
	faction.funds -= funds_cost
	faction.materials -= materials_cost
	unit.condition = GameEnums.UnitCondition.REPAIRING
	unit.repair_turns_remaining = repair_turns
	return {"errors": errors, "funds_cost": funds_cost, "materials_cost": materials_cost, "turns": repair_turns}

func advance_repairs_for_faction(faction_id: StringName) -> Array[StringName]:
	var completed: Array[StringName] = []
	var unit_ids := campaign_runtime.units_by_id.keys()
	unit_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for instance_id: StringName in unit_ids:
		var unit := campaign_runtime.get_unit(instance_id)
		if unit == null or unit.owner_faction_id != faction_id or unit.condition != GameEnums.UnitCondition.REPAIRING:
			continue
		var squad := campaign_runtime.get_squad(unit.squad_id)
		if squad == null or not is_region_supplied(squad.region_id, faction_id):
			continue
		unit.repair_turns_remaining = maxi(0, unit.repair_turns_remaining - 1)
		if unit.repair_turns_remaining == 0:
			var unit_def := master_data.units.get(unit.unit_def_id) as UnitDef
			if unit_def == null:
				continue
			unit.current_hp = unit_def.max_hp
			unit.condition = GameEnums.UnitCondition.ACTIVE
			completed.append(instance_id)
	return completed

## STRATEGY_DETAIL_SPECIFICATION.md section 5.7: a destroyed named pilot
## cannot sortie for three of that faction's own turns.
func advance_pilot_injuries_for_faction(faction_id: StringName) -> Array[StringName]:
	var recovered: Array[StringName] = []
	var pilot_ids := campaign_runtime.pilots_by_id.keys()
	pilot_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for pilot_id: StringName in pilot_ids:
		var pilot := campaign_runtime.get_pilot(pilot_id)
		if pilot == null or pilot.owner_faction_id != faction_id or pilot.injury_turns_remaining <= 0:
			continue
		pilot.injury_turns_remaining -= 1
		if pilot.injury_turns_remaining == 0:
			recovered.append(pilot_id)
	return recovered

func rollout_new_unit(
	unit_def_id: StringName,
	owner_faction_id: StringName,
	region_id: StringName,
	display_name: String = "",
) -> Dictionary:
	return campaign_runtime.rollout_unit(
		unit_def_id,
		owner_faction_id,
		region_id,
		master_data,
		region_defs,
		display_name,
	)


func plan_squad_movement(squad_id: StringName, destination_region_id: StringName, acting_faction_id: StringName) -> PackedStringArray:
	var squad := campaign_runtime.get_squad(squad_id)
	if squad == null:
		return PackedStringArray(["movement: squad_id '%s' does not resolve" % squad_id])
	var region_def := region_defs.get(squad.region_id) as RegionDef
	if region_def == null:
		return PackedStringArray(["movement: source region does not resolve"])
	return campaign_runtime.plan_squad_movement(
		squad_id, destination_region_id, acting_faction_id, region_def.neighbor_ids
	)


func _seed_initial_squads() -> void:
	# Transitional deterministic loadout until FactionDef gains starting_unit_loadout.
	var unit_ids := master_data.units.keys()
	unit_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var faction_ids := faction_defs.keys()
	faction_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for faction_id: StringName in faction_ids:
		var faction_def := faction_defs[faction_id] as FactionDef
		if faction_def == null:
			continue
		for unit_id: StringName in unit_ids:
			var unit_def := master_data.units[unit_id] as UnitDef
			if unit_def != null and unit_def.faction_origin_id == faction_id:
				var result := rollout_new_unit(unit_id, faction_id, faction_def.starting_region_id, tr(String(unit_def.display_name_key)))
				if not result.errors.is_empty():
					push_error("Initial squad rollout failed: %s" % result.errors)

## Transitional deterministic assignment until formation UI exposes pilot
## roster management; mirrors _seed_initial_squads' temporary loadout. Each
## named pilot claims the first still-generic-piloted unit for their
## faction, at PilotDef.initial_level.
func _seed_initial_pilots() -> void:
	var pilot_ids := master_data.pilots.keys()
	pilot_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for pilot_id: StringName in pilot_ids:
		var pilot_def := master_data.pilots[pilot_id] as PilotDef
		if pilot_def == null:
			continue
		var pilot := PilotState.new()
		pilot.pilot_id = pilot_id
		pilot.owner_faction_id = pilot_def.faction_id
		pilot.level = clampi(pilot_def.initial_level, 1, GameConstants.PILOT_LEVEL_CAP)
		pilot.current_exp = 0
		pilot.injury_turns_remaining = 0
		pilot.available = true
		pilot.joined = true
		if not campaign_runtime.register_pilot(pilot):
			continue
		var unit_id := _first_generic_piloted_unit_for_faction(pilot_def.faction_id)
		if not unit_id.is_empty():
			var assign_errors := campaign_runtime.assign_pilot_to_unit(pilot_id, unit_id)
			if not assign_errors.is_empty():
				push_error("Initial pilot assignment failed for %s: %s" % [pilot_id, assign_errors])

func _first_generic_piloted_unit_for_faction(faction_id: StringName) -> StringName:
	var unit_ids := campaign_runtime.units_by_id.keys()
	unit_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for unit_id: StringName in unit_ids:
		var unit := campaign_runtime.get_unit(unit_id)
		if unit != null and unit.owner_faction_id == faction_id and unit.pilot_id.is_empty():
			return unit_id
	return &""

func production_facility_ids_for_region(region_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var region_def := region_defs.get(region_id) as RegionDef
	if region_def == null:
		return result
	for facility_id: StringName in region_def.facility_instance_ids:
		var instance := master_data.facility_instances.get(facility_id) as FacilityInstanceDef
		if instance == null or instance.region_id != region_id:
			continue
		var facility_def := master_data.facility_defs.get(instance.facility_def_id) as FacilityDef
		if facility_def != null and facility_def.facility_type in [GameEnums.FacilityType.PRODUCTION, GameEnums.FacilityType.LARGE_PRODUCTION]:
			result.append(facility_id)
	return result

func queue_production(faction_id: StringName, facility_id: StringName, unit_def_id: StringName) -> Dictionary:
	var errors := PackedStringArray()
	var faction := get_faction(faction_id)
	var instance := master_data.facility_instances.get(facility_id) as FacilityInstanceDef
	var unit_def := master_data.units.get(unit_def_id) as UnitDef
	var facility_def: FacilityDef = null
	var region := get_region(instance.region_id) if instance != null else null
	if faction == null:
		errors.append("production: faction_id '%s' does not resolve" % faction_id)
	if instance == null:
		errors.append("production: facility_instance_id '%s' does not resolve" % facility_id)
	else:
		facility_def = master_data.facility_defs.get(instance.facility_def_id) as FacilityDef
		if region == null or region.owner_faction_id != faction_id:
			errors.append("production: faction does not own the facility region")
	if facility_def == null or not facility_def.facility_type in [GameEnums.FacilityType.PRODUCTION, GameEnums.FacilityType.LARGE_PRODUCTION]:
		errors.append("production: facility is not a production facility")
	if unit_def == null:
		errors.append("production: unit_def_id '%s' does not resolve" % unit_def_id)
	if not errors.is_empty():
		return {"job": null, "errors": errors}
	var funds_cost: int = GameConstants.UNIT_PRODUCTION_FUNDS[unit_def.size]
	var materials_cost: int = GameConstants.UNIT_PRODUCTION_MATERIALS[unit_def.size]
	if faction.funds < funds_cost:
		errors.append("production: insufficient funds")
	if faction.materials < materials_cost:
		errors.append("production: insufficient materials")
	if not errors.is_empty():
		return {"job": null, "errors": errors}
	var queued := campaign_runtime.queue_production(
		facility_id, unit_def_id, funds_cost, materials_cost, turn_number,
		GameConstants.UNIT_PRODUCTION_POWER[unit_def.size]
	)
	if not queued.errors.is_empty():
		return queued
	faction.funds -= funds_cost
	faction.materials -= materials_cost
	return queued

func advance_region_production(region_id: StringName) -> Array[Dictionary]:
	var completed_rollouts: Array[Dictionary] = []
	var region := get_region(region_id)
	if region == null or region.owner_faction_id.is_empty():
		return completed_rollouts
	for facility_id: StringName in production_facility_ids_for_region(region_id):
		var instance := master_data.facility_instances[facility_id] as FacilityInstanceDef
		var facility_def := master_data.facility_defs[instance.facility_def_id] as FacilityDef
		for job: ProductionJobState in campaign_runtime.advance_production(facility_id, facility_def.production_power):
			var rollout := rollout_new_unit(job.unit_def_id, region.owner_faction_id, region_id)
			if rollout.errors.is_empty():
				completed_rollouts.append(rollout)
			else:
				push_error("Production rollout failed for %s: %s" % [job.job_id, rollout.errors])
	return completed_rollouts

func clear_region_production(region_id: StringName) -> void:
	for facility_id: StringName in production_facility_ids_for_region(region_id):
		campaign_runtime.clear_production_facility(facility_id)

func set_region_owner(region_id: StringName, new_owner_id: StringName) -> void:
	var region: Region = regions[region_id]
	var old_owner := region.owner_faction_id
	if old_owner == new_owner_id:
		return
	clear_region_production(region_id)
	region.owner_faction_id = new_owner_id
	recompute_all_supply_networks()
	region_ownership_changed.emit(region_id, old_owner, new_owner_id)
	_check_capital_loss(region_id, old_owner)

## A faction is eliminated the moment it no longer holds its own designated
## capital region — losing someone else's captured capital doesn't count.
func _check_capital_loss(region_id: StringName, old_owner: StringName) -> void:
	if old_owner == &"":
		return
	var faction: Faction = factions.get(old_owner)
	if faction == null or faction.eliminated:
		return
	if faction.def.starting_region_id == region_id:
		faction.eliminated = true
		faction_eliminated.emit(old_owner)

func region_count_for(faction_id: StringName) -> int:
	var count := 0
	for region in regions.values():
		if region.owner_faction_id == faction_id:
			count += 1
	return count

func alive_faction_ids() -> Array:
	var ids := []
	for fid in factions:
		if not factions[fid].eliminated:
			ids.append(fid)
	return ids
