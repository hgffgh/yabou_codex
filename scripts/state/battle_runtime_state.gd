class_name BattleRuntimeState
extends RefCounted

const MAX_WORLD_SEC := 300.0
const RETREAT_PREPARE_SEC := 10.0

var battle_id: StringName = &""
var region_id: StringName = &""
var attacker_faction_id: StringName = &""
var defender_faction_id: StringName = &""
var elapsed_world_sec: float = 0.0
var time_scale: float = 1.0
var attacker_squad_ids: Array[StringName] = []
var defender_squad_ids: Array[StringName] = []
var squad_states_by_id: Dictionary = {}
var unit_states_by_id: Dictionary = {}
var control_point_states: Dictionary = {}
var control_point_defs_by_id: Dictionary = {}
var battle_map_id: StringName = &""
var attacker_hq_id: StringName = &""
var defender_hq_id: StringName = &""
var rng_state: int = 0
var unit_defs: Dictionary = {}
var weapon_defs: Dictionary = {}
var pilot_defs: Dictionary = {}
var support_skill_defs: Dictionary = {}
var combat_events: Array[Dictionary] = []
var engagements_by_squad_id: Dictionary = {}
var require_round_confirmation: bool = false
var result: BattleResultState
var applied_to_campaign: bool = false

func request_retreat(squad_id: StringName) -> bool:
	var squad := squad_states_by_id.get(squad_id) as BattleSquadState
	if squad == null or result != null:
		return false
	squad.retreat_requested = true
	squad.retreat_prepare_sec = 0.0
	return true

func advance_time(delta_sec: float) -> void:
	if result != null or delta_sec <= 0.0 or time_scale <= 0.0:
		return
	var applied := delta_sec * time_scale
	var had_engagement := not engagements_by_squad_id.is_empty()
	elapsed_world_sec = minf(MAX_WORLD_SEC, elapsed_world_sec + applied)
	for squad: BattleSquadState in squad_states_by_id.values():
		if squad.retreat_requested:
			squad.retreat_prepare_sec = minf(RETREAT_PREPARE_SEC, squad.retreat_prepare_sec + applied)
	BattleCombatSystem.advance(self, applied)
	if result != null:
		return
	_advance_capture(applied)
	if not had_engagement:
		_advance_control_point_recovery(applied)
	if result != null:
		return
	var all_attackers_ready := not attacker_squad_ids.is_empty()
	for squad_id: StringName in attacker_squad_ids:
		var attacker := squad_states_by_id[squad_id] as BattleSquadState
		all_attackers_ready = all_attackers_ready and attacker.retreat_requested and attacker.retreat_prepare_sec >= RETREAT_PREPARE_SEC
	if all_attackers_ready:
		finalize(defender_faction_id, attacker_faction_id, &"retreat")
		return
	if elapsed_world_sec >= MAX_WORLD_SEC:
		finalize(defender_faction_id, attacker_faction_id, &"timeout")

func is_squad_engaged(squad_id: StringName) -> bool:
	return engagements_by_squad_id.has(squad_id)

func engaged_opponent_id(squad_id: StringName) -> StringName:
	var engagement := engagements_by_squad_id.get(squad_id) as BattleEngagementState
	return engagement.opponent_of(squad_id) if engagement != null else &""

func has_unconfirmed_engagement() -> bool:
	for engagement: BattleEngagementState in engagements_by_squad_id.values():
		if not engagement.confirmed: return true
	return false

func confirm_engagements() -> void:
	for engagement: BattleEngagementState in engagements_by_squad_id.values():
		engagement.confirmed = true

func update_engagements(delta_sec: float) -> void:
	for squad: BattleSquadState in squad_states_by_id.values():
		if not is_squad_engaged(squad.squad_id):
			squad.reengage_wait_sec = maxf(0.0, squad.reengage_wait_sec - delta_sec)
			if squad.reengage_wait_sec < 0.000001: squad.reengage_wait_sec = 0.0
	_start_available_engagements()
	var unique: Array[BattleEngagementState] = []
	for engagement: BattleEngagementState in engagements_by_squad_id.values():
		if not unique.has(engagement): unique.append(engagement)
	for engagement: BattleEngagementState in unique:
		if not engagement.confirmed: continue
		engagement.elapsed_sec += delta_sec
		if engagement.elapsed_sec >= BattleEngagementState.ROUND_DURATION_SEC - 0.000001:
			_end_engagement(engagement)

func _start_available_engagements() -> void:
	var squad_ids: Array[StringName] = []
	for value: Variant in squad_states_by_id.keys(): squad_ids.append(StringName(value))
	squad_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for first_id: StringName in squad_ids:
		var first := squad_states_by_id[first_id] as BattleSquadState
		if is_squad_engaged(first_id) or first.reengage_wait_sec > 0.0 or not _squad_has_living_units(first): continue
		for second_id: StringName in squad_ids:
			var second := squad_states_by_id[second_id] as BattleSquadState
			if second.faction_id == first.faction_id or is_squad_engaged(second_id) or second.reengage_wait_sec > 0.0 or not _squad_has_living_units(second): continue
			if not _squads_in_weapon_contact(first, second): continue
			var engagement := BattleEngagementState.new()
			engagement.first_squad_id = first_id
			engagement.second_squad_id = second_id
			engagement.confirmed = not require_round_confirmation
			engagements_by_squad_id[first_id] = engagement
			engagements_by_squad_id[second_id] = engagement
			first.destination = first.world_position
			second.destination = second.world_position
			break

func _end_engagement(engagement: BattleEngagementState) -> void:
	for squad_id: StringName in [engagement.first_squad_id, engagement.second_squad_id]:
		var squad := squad_states_by_id.get(squad_id) as BattleSquadState
		if squad != null:
			_reselect_leader_if_needed(squad)
			squad.reengage_wait_sec = 5.0
			squad.last_battle_time_sec = elapsed_world_sec
			for unit_id: StringName in squad.unit_instance_ids:
				var unit := unit_states_by_id[unit_id] as BattleUnitState
				unit.action_gauge = 0.0
				unit.post_action_delay_sec = 0.0
		engagements_by_squad_id.erase(squad_id)

func _reselect_leader_if_needed(squad: BattleSquadState) -> void:
	var current := unit_states_by_id.get(squad.leader_unit_id) as BattleUnitState
	if current != null and current.current_hp > 0: return
	var candidates: Array[BattleUnitState] = []
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := unit_states_by_id[unit_id] as BattleUnitState
		if unit.current_hp > 0: candidates.append(unit)
	if candidates.is_empty():
		squad.leader_unit_id = &""
		squad.leader_command = 100
		return
	candidates.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		if a.command != b.command: return a.command > b.command
		return a.slot_index < b.slot_index)
	squad.leader_unit_id = candidates[0].unit_instance_id
	squad.leader_command = candidates[0].command

func _squads_in_weapon_contact(first: BattleSquadState, second: BattleSquadState) -> bool:
	var distance := Vector2(first.world_position.x, first.world_position.y).distance_to(Vector2(second.world_position.x, second.world_position.y))
	return distance <= maxf(_squad_max_usable_range(first), _squad_max_usable_range(second))

func _squad_max_usable_range(squad: BattleSquadState) -> float:
	var result := 0.0
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := unit_states_by_id[unit_id] as BattleUnitState
		if unit.current_hp <= 0: continue
		var unit_def := unit_defs.get(unit.unit_def_id) as UnitDef
		if unit_def == null: continue
		for weapon_id: StringName in unit_def.weapon_ids:
			var weapon := weapon_defs.get(weapon_id) as WeaponDef
			if weapon != null and unit.current_en >= weapon.en_cost: result = maxf(result, weapon.max_range_m)
	return result

func _squad_has_living_units(squad: BattleSquadState) -> bool:
	for unit_id: StringName in squad.unit_instance_ids:
		if (unit_states_by_id[unit_id] as BattleUnitState).current_hp > 0: return true
	return false

func _advance_capture(applied_sec: float) -> void:
	if not engagements_by_squad_id.is_empty():
		return
	for point_id: StringName in control_point_states:
		var point := control_point_states[point_id] as BattleControlPointState
		var point_def := control_point_defs_by_id.get(point_id) as BattleControlPointDef
		if point_def == null:
			continue
		var units_by_faction := {}
		for squad: BattleSquadState in squad_states_by_id.values():
			var squad_position := Vector2(squad.world_position.x, squad.world_position.y)
			var point_position := Vector2(point_def.position.x, point_def.position.z)
			if squad_position.distance_to(point_position) > point_def.capture_radius_m:
				continue
			var living := 0
			for unit_id: StringName in squad.unit_instance_ids:
				var unit := unit_states_by_id[unit_id] as BattleUnitState
				if unit.current_hp > 0:
					living += 1
			if living > 0:
				units_by_faction[squad.faction_id] = int(units_by_faction.get(squad.faction_id, 0)) + living
		var factions := units_by_faction.keys()
		if factions.size() == 1 and factions[0] != point.owner_faction_id:
			var capturing_id := StringName(factions[0])
			if point.capturing_faction_id != capturing_id:
				point.capturing_faction_id = capturing_id
				point.capture_progress = 0.0
			point.capture_progress = minf(100.0, point.capture_progress + float(units_by_faction[capturing_id]) * applied_sec)
			if point.capture_progress >= 100.0:
				point.owner_faction_id = capturing_id
				point.capture_progress = 0.0
				point.capturing_faction_id = &""
				if point_id == defender_hq_id and capturing_id == attacker_faction_id:
					finalize(attacker_faction_id, defender_faction_id, &"hq_capture")
				elif point_id == attacker_hq_id and capturing_id == defender_faction_id:
					finalize(defender_faction_id, attacker_faction_id, &"hq_capture")
		else:
			point.capture_progress = maxf(0.0, point.capture_progress - 2.0 * applied_sec)
			if point.capture_progress <= 0.0:
				point.capturing_faction_id = &""

func _advance_control_point_recovery(applied_sec: float) -> void:
	if not engagements_by_squad_id.is_empty(): return
	var hp_rate_by_unit := {}
	var en_rate_by_unit := {}
	for point_id: StringName in control_point_states:
		var point := control_point_states[point_id] as BattleControlPointState
		var point_def := control_point_defs_by_id.get(point_id) as BattleControlPointDef
		if point_def == null or point.owner_faction_id.is_empty(): continue
		var enemy_in_capture_range := false
		for squad: BattleSquadState in squad_states_by_id.values():
			if squad.faction_id == point.owner_faction_id or not _squad_has_living_units(squad): continue
			if Vector2(squad.world_position.x, squad.world_position.y).distance_to(Vector2(point_def.position.x, point_def.position.z)) <= point_def.capture_radius_m:
				enemy_in_capture_range = true
				break
		if enemy_in_capture_range: continue
		for squad: BattleSquadState in squad_states_by_id.values():
			if squad.faction_id != point.owner_faction_id or squad.reengage_wait_sec > 0.0: continue
			if Vector2(squad.world_position.x, squad.world_position.y).distance_to(Vector2(point_def.position.x, point_def.position.z)) > point_def.sensor_radius_m: continue
			for unit_id: StringName in squad.unit_instance_ids:
				var unit := unit_states_by_id[unit_id] as BattleUnitState
				if unit.current_hp <= 0: continue
				hp_rate_by_unit[unit_id] = maxf(float(hp_rate_by_unit.get(unit_id, 0.0)), point_def.hp_recovery_pct_per_sec)
				en_rate_by_unit[unit_id] = maxf(float(en_rate_by_unit.get(unit_id, 0.0)), point_def.en_recovery_pct_per_sec)
	for unit_id: StringName in hp_rate_by_unit:
		var unit := unit_states_by_id[unit_id] as BattleUnitState
		if unit.current_hp < unit.max_hp:
			unit.hp_recovery_fraction += float(unit.max_hp) * float(hp_rate_by_unit[unit_id]) * applied_sec
			var hp_gain := floori(unit.hp_recovery_fraction)
			unit.hp_recovery_fraction -= hp_gain
			unit.current_hp = mini(unit.max_hp, unit.current_hp + hp_gain)
			if unit.current_hp >= unit.max_hp: unit.hp_recovery_fraction = 0.0
		if unit.current_en < unit.max_en:
			unit.en_recovery_fraction += float(unit.max_en) * float(en_rate_by_unit[unit_id]) * applied_sec
			var en_gain := floori(unit.en_recovery_fraction)
			unit.en_recovery_fraction -= en_gain
			unit.current_en = mini(unit.max_en, unit.current_en + en_gain)
			if unit.current_en >= unit.max_en: unit.en_recovery_fraction = 0.0

func finalize(winner_id: StringName, loser_id: StringName, reason: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	if result != null:
		errors.append("battle: result is already finalized")
	elif not [attacker_faction_id, defender_faction_id].has(winner_id) or not [attacker_faction_id, defender_faction_id].has(loser_id) or winner_id == loser_id:
		errors.append("battle: winner and loser must be the opposing battle factions")
	elif not [&"hq_capture", &"annihilation", &"retreat", &"timeout"].has(reason):
		errors.append("battle: result reason is invalid")
	if not errors.is_empty():
		return errors
	result = BattleResultState.new()
	result.winner_faction_id = winner_id
	result.loser_faction_id = loser_id
	result.reason = reason
	result.elapsed_world_sec = elapsed_world_sec
	for unit_id: StringName in unit_states_by_id:
		var unit := unit_states_by_id[unit_id] as BattleUnitState
		if unit.destroyed_this_battle or unit.current_hp <= 0:
			result.destroyed_unit_ids.append(unit_id)
	result.destroyed_unit_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return errors
