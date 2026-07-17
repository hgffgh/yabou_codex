class_name CampaignRuntimeState
extends RefCounted

## Owns the mutable unit/squad graph and deterministic, RNG-independent IDs.

const UNIT_ID_PREFIX := "unit_"
const SQUAD_ID_PREFIX := "squad_"
const PRODUCTION_JOB_ID_PREFIX := "production_job_"

var units_by_id: Dictionary = {}
var squads_by_id: Dictionary = {}
var pilots_by_id: Dictionary = {}
var production_jobs_by_id: Dictionary = {}
var production_queues_by_facility_id: Dictionary = {}
var next_unit_serial: int = 1
var next_squad_serial: int = 1
var next_production_job_serial: int = 1


func reset() -> void:
	units_by_id.clear()
	squads_by_id.clear()
	pilots_by_id.clear()
	production_jobs_by_id.clear()
	production_queues_by_facility_id.clear()
	next_unit_serial = 1
	next_squad_serial = 1
	next_production_job_serial = 1


func queue_production(
	facility_instance_id: StringName,
	unit_def_id: StringName,
	funds_paid: int,
	materials_paid: int,
	registered_turn: int,
	production_required: int,
) -> Dictionary:
	var errors := PackedStringArray()
	if facility_instance_id.is_empty():
		errors.append("production: facility_instance_id must not be empty")
	if unit_def_id.is_empty():
		errors.append("production: unit_def_id must not be empty")
	if funds_paid < 0:
		errors.append("production: funds_paid must not be negative")
	if materials_paid < 0:
		errors.append("production: materials_paid must not be negative")
	if registered_turn < 0:
		errors.append("production: registered_turn must not be negative")
	if production_required < 1:
		errors.append("production: production_required must be positive")
	if not errors.is_empty():
		errors.sort()
		return {"job": null, "errors": errors}

	var job := ProductionJobState.new()
	job.job_id = _allocate_production_job_id()
	job.unit_def_id = unit_def_id
	job.production_required = production_required
	job.funds_paid = funds_paid
	job.materials_paid = materials_paid
	job.registered_turn = registered_turn
	production_jobs_by_id[job.job_id] = job
	var queue := production_queues_by_facility_id.get(facility_instance_id) as ProductionQueueState
	if queue == null:
		queue = ProductionQueueState.new()
		queue.facility_instance_id = facility_instance_id
		production_queues_by_facility_id[facility_instance_id] = queue
	queue.job_ids.append(job.job_id)
	return {"job": job, "errors": PackedStringArray()}


func advance_production(facility_instance_id: StringName, production_power: int) -> Array[ProductionJobState]:
	var completed: Array[ProductionJobState] = []
	if production_power <= 0:
		return completed
	var queue := production_queues_by_facility_id.get(facility_instance_id) as ProductionQueueState
	if queue == null:
		return completed
	var remaining_power := production_power
	while remaining_power > 0 and not queue.job_ids.is_empty():
		var job_id := queue.job_ids[0]
		var job := production_jobs_by_id.get(job_id) as ProductionJobState
		if job == null:
			queue.job_ids.pop_front()
			continue
		var needed := job.production_required - job.production_accumulated
		var applied := mini(remaining_power, needed)
		job.production_accumulated += applied
		remaining_power -= applied
		if job.production_accumulated >= job.production_required:
			queue.job_ids.pop_front()
			production_jobs_by_id.erase(job_id)
			completed.append(job)
	return completed


func clear_production_facility(facility_instance_id: StringName) -> Array[ProductionJobState]:
	var removed: Array[ProductionJobState] = []
	var queue := production_queues_by_facility_id.get(facility_instance_id) as ProductionQueueState
	if queue == null:
		return removed
	for job_id: StringName in queue.job_ids:
		var job := production_jobs_by_id.get(job_id) as ProductionJobState
		if job != null:
			removed.append(job)
		production_jobs_by_id.erase(job_id)
	production_queues_by_facility_id.erase(facility_instance_id)
	return removed


func get_unit(instance_id: StringName) -> UnitInstanceState:
	return units_by_id.get(instance_id) as UnitInstanceState


func get_squad(squad_id: StringName) -> SquadState:
	return squads_by_id.get(squad_id) as SquadState


func register_unit(unit: UnitInstanceState) -> bool:
	if unit == null or unit.instance_id.is_empty() or units_by_id.has(unit.instance_id):
		return false
	if not unit.squad_id.is_empty() or unit.slot_index != -1:
		return false
	units_by_id[unit.instance_id] = unit
	return true


func register_squad(squad: SquadState) -> bool:
	if squad == null or squad.squad_id.is_empty() or squads_by_id.has(squad.squad_id):
		return false
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			return false
		var slot_index := squad.get_slot_index(unit_id)
		if unit.squad_id != squad.squad_id or unit.slot_index != slot_index:
			return false
	squads_by_id[squad.squad_id] = squad
	return true


func get_pilot(pilot_id: StringName) -> PilotState:
	return pilots_by_id.get(pilot_id) as PilotState


func register_pilot(pilot: PilotState) -> bool:
	if pilot == null or pilot.pilot_id.is_empty() or pilots_by_id.has(pilot.pilot_id):
		return false
	pilots_by_id[pilot.pilot_id] = pilot
	return true


## Assigns a named pilot to a unit, per STRATEGY_DETAIL_SPECIFICATION.md
## section 5: placing a named pilot silently displaces whatever generic or
## named pilot currently crews that unit (and, if this pilot was already
## flying a different unit, that unit reverts to a generic pilot). Injured
## pilots cannot be assigned. Region/area continuity for a pilot switching
## machines is not enforced — PilotState does not track a location
## independent of its assigned unit.
func assign_pilot_to_unit(pilot_id: StringName, unit_instance_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var pilot := get_pilot(pilot_id)
	var unit := get_unit(unit_instance_id)
	if pilot == null:
		errors.append("pilot assignment: pilot_id '%s' does not resolve" % pilot_id)
	if unit == null:
		errors.append("pilot assignment: unit_instance_id '%s' does not resolve" % unit_instance_id)
	if not errors.is_empty():
		return errors
	if pilot.is_injured():
		errors.append("pilot assignment: pilot is injured")
	if unit.owner_faction_id != pilot.owner_faction_id:
		errors.append("pilot assignment: unit is not owned by the pilot's faction")
	elif unit.condition != GameEnums.UnitCondition.ACTIVE:
		errors.append("pilot assignment: unit is not active")
	if not errors.is_empty():
		return errors
	if pilot.assigned_unit_instance_id == unit_instance_id:
		return errors
	if not pilot.assigned_unit_instance_id.is_empty():
		var previous := get_unit(pilot.assigned_unit_instance_id)
		if previous != null:
			previous.pilot_id = &""
			_repair_squad_leader_for_unit(previous)
	if not unit.pilot_id.is_empty():
		var displaced := get_pilot(unit.pilot_id)
		if displaced != null:
			displaced.assigned_unit_instance_id = &""
	unit.pilot_id = pilot_id
	pilot.assigned_unit_instance_id = unit_instance_id
	_repair_squad_leader_for_unit(unit)
	return errors


## Reverts a named pilot's unit to a generic pilot. The pilot itself stays
## on its faction's roster, available for reassignment.
func unassign_pilot(pilot_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var pilot := get_pilot(pilot_id)
	if pilot == null:
		errors.append("pilot assignment: pilot_id '%s' does not resolve" % pilot_id)
		return errors
	if pilot.assigned_unit_instance_id.is_empty():
		return errors
	var unit := get_unit(pilot.assigned_unit_instance_id)
	if unit != null and unit.pilot_id == pilot_id:
		unit.pilot_id = &""
		_repair_squad_leader_for_unit(unit)
	pilot.assigned_unit_instance_id = &""
	return errors


func _repair_squad_leader_for_unit(unit: UnitInstanceState) -> void:
	if unit == null or unit.squad_id.is_empty():
		return
	var squad := get_squad(unit.squad_id)
	if squad != null:
		_repair_squad_leader(squad)


func remove_unassigned_unit(instance_id: StringName) -> bool:
	var unit := get_unit(instance_id)
	if unit == null or not unit.squad_id.is_empty() or unit.slot_index != -1:
		return false
	return units_by_id.erase(instance_id)


func disband_squad(squad_id: StringName) -> bool:
	var squad := get_squad(squad_id)
	if squad == null:
		return false
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := get_unit(unit_id)
		if unit != null and unit.squad_id == squad_id:
			unit.squad_id = &""
			unit.slot_index = -1
	return squads_by_id.erase(squad_id)


## Detaches a unit from its squad (if any), deleting the squad when it would
## otherwise be left with zero units, and keeping the squad's leader_pilot_id
## consistent. Used for destroyed-unit cleanup after a battle: recovered
## units stay in the campaign as unassigned DESTROYED_RECOVERED records,
## and captured/lost units are reassigned or erased by the caller.
func remove_unit_from_squad(unit_instance_id: StringName) -> void:
	var unit := get_unit(unit_instance_id)
	if unit == null or unit.squad_id.is_empty():
		return
	var squad := get_squad(unit.squad_id)
	unit.squad_id = &""
	unit.slot_index = -1
	if squad == null:
		return
	squad.remove_unit(unit_instance_id)
	if squad.unit_instance_ids.is_empty():
		squads_by_id.erase(squad.squad_id)
	else:
		_repair_squad_leader(squad)


## Reassigns a destroyed-and-salvaged unit to a new owner as a fresh
## one-unit squad (the captured frame's original pilot is assumed to have
## ejected/been recovered by their own side, so it reverts to a generic
## pilot). Mirrors rollout_unit's paired-commit shape but reuses the
## existing unit record instead of allocating a new one.
func capture_unit(
	unit_instance_id: StringName,
	new_owner_faction_id: StringName,
	region_id: StringName,
	registry: MasterDataRegistry,
	valid_region_ids: Dictionary,
) -> Dictionary:
	var errors := PackedStringArray()
	var unit := get_unit(unit_instance_id)
	if unit == null:
		errors.append("capture: unit_instance_id '%s' does not resolve" % unit_instance_id)
	if new_owner_faction_id.is_empty() or not registry.factions.has(new_owner_faction_id):
		errors.append("capture: new_owner_faction_id '%s' does not resolve" % new_owner_faction_id)
	if region_id.is_empty() or not valid_region_ids.has(region_id):
		errors.append("capture: region_id '%s' does not resolve" % region_id)
	if not errors.is_empty():
		errors.sort()
		return {"squad": null, "errors": errors}

	remove_unit_from_squad(unit_instance_id)
	unit.owner_faction_id = new_owner_faction_id
	unit.pilot_id = &""
	unit.captured = true
	unit.condition = GameEnums.UnitCondition.ACTIVE
	unit.current_hp = 1
	unit.current_en = 0
	unit.repair_turns_remaining = 0
	unit.movement_used = false

	var squad := SquadState.new()
	squad.squad_id = _allocate_squad_id()
	squad.display_name = "Squad %08d" % (next_squad_serial - 1)
	squad.owner_faction_id = new_owner_faction_id
	squad.region_id = region_id
	if not squad.assign_unit(unit_instance_id, 0):
		errors.append("capture: failed to assign front slot 0")
		errors.sort()
		return {"squad": null, "errors": errors}
	unit.squad_id = squad.squad_id
	unit.slot_index = 0
	squads_by_id[squad.squad_id] = squad
	return {"squad": squad, "errors": PackedStringArray()}


func get_squads_in_region(region_id: StringName, owner_faction_id: StringName = &"") -> Array[SquadState]:
	var result: Array[SquadState] = []
	for key: Variant in _sorted_keys(squads_by_id):
		var squad := squads_by_id[key] as SquadState
		if squad != null and squad.region_id == region_id and (owner_faction_id.is_empty() or squad.owner_faction_id == owner_faction_id):
			result.append(squad)
	return result


func plan_squad_movement(
	squad_id: StringName,
	destination_region_id: StringName,
	acting_faction_id: StringName,
	adjacent_region_ids: Array[StringName],
) -> PackedStringArray:
	var errors := PackedStringArray()
	var squad := get_squad(squad_id)
	if squad == null:
		errors.append("movement: squad_id '%s' does not resolve" % squad_id)
		return errors
	if squad.owner_faction_id != acting_faction_id:
		errors.append("movement: squad is not owned by the acting faction")
	if squad.movement_used or not squad.planned_destination_region_id.is_empty():
		errors.append("movement: squad has already moved this turn")
	if destination_region_id.is_empty() or not adjacent_region_ids.has(destination_region_id):
		errors.append("movement: destination must be adjacent to the squad region")
	if squad.unit_instance_ids.is_empty():
		errors.append("movement: squad must contain at least one unit")
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := get_unit(unit_id)
		if unit == null or unit.squad_id != squad_id or unit.owner_faction_id != squad.owner_faction_id:
			errors.append("movement: squad unit graph is inconsistent")
			break
		if unit.movement_used or unit.condition != GameEnums.UnitCondition.ACTIVE or unit.repair_turns_remaining > 0:
			errors.append("movement: every unit must be active and unused")
			break
	if not errors.is_empty():
		errors.sort()
		return errors
	squad.move_origin_region_id = squad.region_id
	squad.planned_destination_region_id = destination_region_id
	squad.movement_used = true
	for unit_id: StringName in squad.unit_instance_ids:
		get_unit(unit_id).movement_used = true
	return errors


func execute_planned_squad_movements(owner_faction_id: StringName = &"") -> Array[StringName]:
	var moved: Array[StringName] = []
	for key: Variant in _sorted_keys(squads_by_id):
		var squad := squads_by_id[key] as SquadState
		if squad != null and (owner_faction_id.is_empty() or squad.owner_faction_id == owner_faction_id) and not squad.planned_destination_region_id.is_empty():
			squad.region_id = squad.planned_destination_region_id
			squad.planned_destination_region_id = &""
			moved.append(squad.squad_id)
	return moved


func reset_movement_for_faction(owner_faction_id: StringName) -> void:
	for squad: SquadState in squads_by_id.values():
		if squad == null or squad.owner_faction_id != owner_faction_id:
			continue
		squad.movement_used = false
		squad.move_origin_region_id = &""
		squad.planned_destination_region_id = &""
		for unit_id: StringName in squad.unit_instance_ids:
			var unit := get_unit(unit_id)
			if unit != null:
				unit.movement_used = false


func split_squad(source_squad_id: StringName, unit_ids: Array[StringName], display_name: String = "") -> Dictionary:
	var errors := PackedStringArray()
	var source := get_squad(source_squad_id)
	if source == null:
		errors.append("split: source squad does not resolve")
	elif unit_ids.is_empty() or unit_ids.size() >= source.unit_instance_ids.size():
		errors.append("split: select at least one but not every unit")
	else:
		var seen := {}
		for unit_id: StringName in unit_ids:
			if seen.has(unit_id) or not source.contains_unit(unit_id):
				errors.append("split: selected unit is duplicate or not in source squad")
				break
			var unit := get_unit(unit_id)
			if unit == null or unit.squad_id != source_squad_id or unit.slot_index != source.get_slot_index(unit_id):
				errors.append("split: selected unit graph is inconsistent")
				break
			seen[unit_id] = true
	if not errors.is_empty():
		return {"squad": null, "errors": errors}
	var new_squad := SquadState.new()
	new_squad.squad_id = _allocate_squad_id()
	new_squad.display_name = display_name if not display_name.is_empty() else "Squad %08d" % (next_squad_serial - 1)
	new_squad.owner_faction_id = source.owner_faction_id
	new_squad.region_id = source.region_id
	new_squad.movement_used = source.movement_used
	new_squad.move_origin_region_id = source.move_origin_region_id
	new_squad.planned_destination_region_id = source.planned_destination_region_id
	var moved_leader := false
	for unit_id: StringName in unit_ids:
		source.remove_unit(unit_id)
		var target_slot := new_squad.unit_instance_ids.size()
		new_squad.assign_unit(unit_id, target_slot)
		var unit := get_unit(unit_id)
		unit.squad_id = new_squad.squad_id
		unit.slot_index = target_slot
		new_squad.movement_used = new_squad.movement_used or unit.movement_used
		moved_leader = moved_leader or (not source.leader_pilot_id.is_empty() and unit.pilot_id == source.leader_pilot_id)
	if moved_leader:
		new_squad.leader_pilot_id = source.leader_pilot_id
		source.leader_pilot_id = &""
	_normalize_movement([source, new_squad])
	_repair_squad_leader(source)
	_repair_squad_leader(new_squad)
	new_squad.intel_revision = 1
	squads_by_id[new_squad.squad_id] = new_squad
	return {"squad": new_squad, "errors": PackedStringArray()}


func move_unit_to_slot(squad_id: StringName, unit_id: StringName, target_slot_index: int) -> PackedStringArray:
	var errors := PackedStringArray()
	var squad := get_squad(squad_id)
	var unit := get_unit(unit_id)
	if squad == null or unit == null or unit.squad_id != squad_id or not squad.contains_unit(unit_id):
		errors.append("formation: unit does not belong to squad")
	elif target_slot_index < 0 or target_slot_index >= GameConstants.MAX_UNITS_PER_SQUAD:
		errors.append("formation: target slot is outside the squad")
	elif not squad.get_unit_at_slot(target_slot_index).is_empty():
		errors.append("formation: target slot is occupied")
	elif not squad.assign_unit(unit_id, target_slot_index):
		errors.append("formation: slot assignment failed")
	else:
		unit.slot_index = target_slot_index
	return errors


func merge_squads(target_squad_id: StringName, source_squad_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var target := get_squad(target_squad_id)
	var source := get_squad(source_squad_id)
	if target == null or source == null or target == source:
		errors.append("merge: distinct target and source squads must resolve")
	elif target.owner_faction_id != source.owner_faction_id or target.region_id != source.region_id:
		errors.append("merge: squads must share owner and region")
	elif target.unit_instance_ids.size() + source.unit_instance_ids.size() > GameConstants.MAX_UNITS_PER_SQUAD:
		errors.append("merge: combined squad exceeds the slot limit")
	elif target.planned_destination_region_id != source.planned_destination_region_id or target.move_origin_region_id != source.move_origin_region_id:
		errors.append("merge: squads must have matching movement plans")
	else:
		for unit_id: StringName in source.unit_instance_ids:
			var unit := get_unit(unit_id)
			if unit == null or unit.squad_id != source_squad_id or unit.slot_index != source.get_slot_index(unit_id):
				errors.append("merge: source unit graph is inconsistent")
				break
	if not errors.is_empty():
		return errors
	var free_slots: Array[int] = []
	for slot_index in range(GameConstants.MAX_UNITS_PER_SQUAD):
		if target.get_unit_at_slot(slot_index).is_empty():
			free_slots.append(slot_index)
	var source_units := source.unit_instance_ids.duplicate()
	for unit_id: StringName in source_units:
		var target_slot: int = free_slots.pop_front()
		if not target.assign_unit(unit_id, target_slot):
			return PackedStringArray(["merge: failed to assign a prevalidated slot"])
		var unit := get_unit(unit_id)
		unit.squad_id = target.squad_id
		unit.slot_index = target_slot
	target.movement_used = target.movement_used or source.movement_used
	if target.move_origin_region_id.is_empty():
		target.move_origin_region_id = source.move_origin_region_id
	if target.planned_destination_region_id.is_empty():
		target.planned_destination_region_id = source.planned_destination_region_id
	if target.leader_pilot_id.is_empty() and not source.leader_pilot_id.is_empty():
		target.leader_pilot_id = source.leader_pilot_id
	_normalize_movement([target, source])
	_repair_squad_leader(target)
	target.intel_revision += 1
	squads_by_id.erase(source_squad_id)
	return errors


func validate(
	registry: MasterDataRegistry,
	valid_region_ids: Dictionary,
	max_hp_by_instance: Dictionary = {},
) -> PackedStringArray:
	var errors := RuntimeStateValidator.new().validate(
		units_by_id, squads_by_id, registry, valid_region_ids, max_hp_by_instance
	)
	if next_unit_serial < 1:
		errors.append("campaign: next_unit_serial must be at least 1")
	if next_squad_serial < 1:
		errors.append("campaign: next_squad_serial must be at least 1")
	if next_unit_serial <= _maximum_serial(units_by_id, UNIT_ID_PREFIX):
		errors.append("campaign: next_unit_serial must exceed existing generated unit IDs")
	if next_squad_serial <= _maximum_serial(squads_by_id, SQUAD_ID_PREFIX):
		errors.append("campaign: next_squad_serial must exceed existing generated squad IDs")
	if next_production_job_serial < 1:
		errors.append("campaign: next_production_job_serial must be at least 1")
	if next_production_job_serial <= _maximum_serial(production_jobs_by_id, PRODUCTION_JOB_ID_PREFIX):
		errors.append("campaign: next_production_job_serial must exceed existing generated production job IDs")
	for pilot_key: Variant in pilots_by_id:
		var pilot := pilots_by_id[pilot_key] as PilotState
		if pilot == null or pilot.pilot_id != pilot_key or StringName(pilot_key).is_empty():
			errors.append("campaign.pilot_states: invalid pilot '%s'" % pilot_key)
			continue
		if pilot.owner_faction_id.is_empty() or not registry.factions.has(pilot.owner_faction_id):
			errors.append("campaign.pilot_states[%s]: owner_faction_id does not resolve" % pilot_key)
		if not registry.pilots.has(pilot.pilot_id):
			errors.append("campaign.pilot_states[%s]: pilot_id does not resolve to a PilotDef" % pilot_key)
		if pilot.level < 1 or pilot.level > GameConstants.PILOT_LEVEL_CAP:
			errors.append("campaign.pilot_states[%s]: level must be in 1..%d" % [pilot_key, GameConstants.PILOT_LEVEL_CAP])
		if pilot.current_exp < 0:
			errors.append("campaign.pilot_states[%s]: current_exp must not be negative" % pilot_key)
		if pilot.injury_turns_remaining < 0:
			errors.append("campaign.pilot_states[%s]: injury_turns_remaining must not be negative" % pilot_key)
		if not pilot.assigned_unit_instance_id.is_empty():
			var assigned_unit := units_by_id.get(pilot.assigned_unit_instance_id) as UnitInstanceState
			if assigned_unit == null or assigned_unit.pilot_id != pilot.pilot_id:
				errors.append("campaign.pilot_states[%s]: assigned_unit_instance_id back-reference is inconsistent" % pilot_key)
	for unit_key: Variant in units_by_id:
		var pilot_owner := units_by_id[unit_key] as UnitInstanceState
		if pilot_owner == null or pilot_owner.pilot_id.is_empty():
			continue
		var owning_pilot := pilots_by_id.get(pilot_owner.pilot_id) as PilotState
		if owning_pilot == null or owning_pilot.assigned_unit_instance_id != pilot_owner.instance_id:
			errors.append("units[%s]: pilot_id '%s' does not resolve to a matching PilotState" % [unit_key, pilot_owner.pilot_id])
	var queued_jobs := {}
	for facility_key: Variant in production_queues_by_facility_id:
		var queue := production_queues_by_facility_id[facility_key] as ProductionQueueState
		if queue == null or queue.facility_instance_id != facility_key or StringName(facility_key).is_empty():
			errors.append("campaign.production_queues: invalid facility queue '%s'" % facility_key)
			continue
		for job_id: StringName in queue.job_ids:
			if not production_jobs_by_id.has(job_id):
				errors.append("campaign.production_queues: job_id '%s' does not resolve" % job_id)
			elif queued_jobs.has(job_id):
				errors.append("campaign.production_queues: job_id '%s' is queued more than once" % job_id)
			else:
				queued_jobs[job_id] = true
	for job_key: Variant in production_jobs_by_id:
		var job := production_jobs_by_id[job_key] as ProductionJobState
		if job == null or job.job_id != job_key or StringName(job_key).is_empty():
			errors.append("campaign.production_jobs: invalid job '%s'" % job_key)
			continue
		if job.unit_def_id.is_empty() or not registry.units.has(job.unit_def_id):
			errors.append("campaign.production_jobs[%s]: unit_def_id does not resolve" % job_key)
		if job.production_required < 1 or job.production_accumulated < 0 or job.production_accumulated >= job.production_required:
			errors.append("campaign.production_jobs[%s]: invalid production progress" % job_key)
		if job.funds_paid < 0 or job.materials_paid < 0 or job.registered_turn < 0:
			errors.append("campaign.production_jobs[%s]: paid costs and turn must not be negative" % job_key)
		if not queued_jobs.has(job_key):
			errors.append("campaign.production_jobs[%s]: job is not queued" % job_key)
	errors.sort()
	return errors


func rollout_unit(
	unit_def_id: StringName,
	owner_faction_id: StringName,
	region_id: StringName,
	registry: MasterDataRegistry,
	valid_region_ids: Dictionary,
	display_name: String = "",
) -> Dictionary:
	var errors := PackedStringArray()
	var unit_def := registry.units.get(unit_def_id) as UnitDef
	if unit_def == null:
		errors.append("rollout: unit_def_id '%s' does not resolve" % unit_def_id)
	if owner_faction_id.is_empty() or not registry.factions.has(owner_faction_id):
		errors.append("rollout: owner_faction_id '%s' does not resolve" % owner_faction_id)
	if region_id.is_empty() or not valid_region_ids.has(region_id):
		errors.append("rollout: region_id '%s' does not resolve" % region_id)
	if unit_def != null and (unit_def.max_hp < 1 or unit_def.max_en < 1):
		errors.append("rollout: unit definition requires positive max_hp and max_en")
	if not errors.is_empty():
		errors.sort()
		return {"unit": null, "squad": null, "errors": errors}

	var instance_id := _allocate_unit_id()
	var squad_id := _allocate_squad_id()
	var unit := UnitInstanceState.new()
	unit.instance_id = instance_id
	unit.unit_def_id = unit_def_id
	unit.owner_faction_id = owner_faction_id
	unit.origin_faction_id = owner_faction_id
	unit.current_hp = unit_def.max_hp
	unit.current_en = unit_def.max_en
	unit.pilot_id = &""
	unit.squad_id = squad_id
	unit.slot_index = 0

	var squad := SquadState.new()
	squad.squad_id = squad_id
	squad.display_name = display_name if not display_name.is_empty() else "Squad %08d" % (next_squad_serial - 1)
	squad.owner_faction_id = owner_faction_id
	squad.region_id = region_id
	if not squad.assign_unit(instance_id, 0):
		return {"unit": null, "squad": null, "errors": PackedStringArray(["rollout: failed to assign front slot 0"])}
	squad.intel_revision = 0

	# All fallible preconditions precede this paired commit.
	units_by_id[instance_id] = unit
	squads_by_id[squad_id] = squad
	return {"unit": unit, "squad": squad, "errors": PackedStringArray()}


func to_dict() -> Dictionary:
	var unit_states: Array[Dictionary] = []
	for key: Variant in _sorted_keys(units_by_id):
		var unit := units_by_id[key] as UnitInstanceState
		if unit != null:
			unit_states.append(unit.to_dict())
	var squad_states: Array[Dictionary] = []
	for key: Variant in _sorted_keys(squads_by_id):
		var squad := squads_by_id[key] as SquadState
		if squad != null:
			squad_states.append(squad.to_dict())
	var pilot_states: Array[Dictionary] = []
	for key: Variant in _sorted_keys(pilots_by_id):
		var pilot := pilots_by_id[key] as PilotState
		if pilot != null:
			pilot_states.append(pilot.to_dict())
	var production_jobs: Array[Dictionary] = []
	for key: Variant in _sorted_keys(production_jobs_by_id):
		var job := production_jobs_by_id[key] as ProductionJobState
		if job != null:
			production_jobs.append(job.to_dict())
	var production_queues: Array[Dictionary] = []
	for key: Variant in _sorted_keys(production_queues_by_facility_id):
		var queue := production_queues_by_facility_id[key] as ProductionQueueState
		if queue != null:
			production_queues.append(queue.to_dict())
	return {
		"next_unit_serial": next_unit_serial,
		"next_squad_serial": next_squad_serial,
		"next_production_job_serial": next_production_job_serial,
		"unit_states": unit_states,
		"squad_states": squad_states,
		"pilot_states": pilot_states,
		"production_jobs": production_jobs,
		"production_queues": production_queues,
	}


static func from_dict(data: Dictionary) -> Dictionary:
	var state := CampaignRuntimeState.new()
	var errors := PackedStringArray()
	var unit_values: Variant = data.get("unit_states", [])
	if unit_values is Array:
		for value: Variant in unit_values:
			if not value is Dictionary:
				errors.append("campaign.unit_states: entry must be a Dictionary")
				continue
			var unit := UnitInstanceState.from_dict(value)
			if unit.instance_id.is_empty():
				errors.append("campaign.unit_states: instance_id must not be empty")
			elif state.units_by_id.has(unit.instance_id):
				errors.append("campaign.unit_states: duplicate instance_id '%s'" % unit.instance_id)
			else:
				state.units_by_id[unit.instance_id] = unit
	else:
		errors.append("campaign.unit_states must be an Array")

	var squad_values: Variant = data.get("squad_states", [])
	if squad_values is Array:
		for value: Variant in squad_values:
			if not value is Dictionary:
				errors.append("campaign.squad_states: entry must be a Dictionary")
				continue
			var squad := SquadState.from_dict(value)
			if squad.squad_id.is_empty():
				errors.append("campaign.squad_states: squad_id must not be empty")
			elif state.squads_by_id.has(squad.squad_id):
				errors.append("campaign.squad_states: duplicate squad_id '%s'" % squad.squad_id)
			else:
				state.squads_by_id[squad.squad_id] = squad
	else:
		errors.append("campaign.squad_states must be an Array")

	var pilot_values: Variant = data.get("pilot_states", [])
	if pilot_values is Array:
		for value: Variant in pilot_values:
			if not value is Dictionary:
				errors.append("campaign.pilot_states: entry must be a Dictionary")
				continue
			var pilot := PilotState.from_dict(value)
			if pilot.pilot_id.is_empty():
				errors.append("campaign.pilot_states: pilot_id must not be empty")
			elif state.pilots_by_id.has(pilot.pilot_id):
				errors.append("campaign.pilot_states: duplicate pilot_id '%s'" % pilot.pilot_id)
			else:
				state.pilots_by_id[pilot.pilot_id] = pilot
	else:
		errors.append("campaign.pilot_states must be an Array")

	var job_values: Variant = data.get("production_jobs", [])
	if job_values is Array:
		for value: Variant in job_values:
			if not value is Dictionary:
				errors.append("campaign.production_jobs: entry must be a Dictionary")
				continue
			var job := ProductionJobState.from_dict(value)
			if job.job_id.is_empty() or state.production_jobs_by_id.has(job.job_id):
				errors.append("campaign.production_jobs: empty or duplicate job_id '%s'" % job.job_id)
			else:
				state.production_jobs_by_id[job.job_id] = job
	else:
		errors.append("campaign.production_jobs must be an Array")

	var queue_values: Variant = data.get("production_queues", [])
	if queue_values is Array:
		for value: Variant in queue_values:
			if not value is Dictionary:
				errors.append("campaign.production_queues: entry must be a Dictionary")
				continue
			var queue := ProductionQueueState.from_dict(value)
			if queue.facility_instance_id.is_empty() or state.production_queues_by_facility_id.has(queue.facility_instance_id):
				errors.append("campaign.production_queues: empty or duplicate facility_instance_id '%s'" % queue.facility_instance_id)
			else:
				state.production_queues_by_facility_id[queue.facility_instance_id] = queue
	else:
		errors.append("campaign.production_queues must be an Array")

	state.next_unit_serial = maxi(int(data.get("next_unit_serial", 1)), state._maximum_serial(state.units_by_id, UNIT_ID_PREFIX) + 1)
	state.next_squad_serial = maxi(int(data.get("next_squad_serial", 1)), state._maximum_serial(state.squads_by_id, SQUAD_ID_PREFIX) + 1)
	state.next_production_job_serial = maxi(int(data.get("next_production_job_serial", 1)), state._maximum_serial(state.production_jobs_by_id, PRODUCTION_JOB_ID_PREFIX) + 1)
	state.next_unit_serial = maxi(1, state.next_unit_serial)
	state.next_squad_serial = maxi(1, state.next_squad_serial)
	state.next_production_job_serial = maxi(1, state.next_production_job_serial)
	errors.sort()
	return {"state": state, "errors": errors}


func _allocate_unit_id() -> StringName:
	while true:
		var result := StringName("%s%08d" % [UNIT_ID_PREFIX, next_unit_serial])
		next_unit_serial += 1
		if not units_by_id.has(result):
			return result
	return &""


func _allocate_squad_id() -> StringName:
	while true:
		var result := StringName("%s%08d" % [SQUAD_ID_PREFIX, next_squad_serial])
		next_squad_serial += 1
		if not squads_by_id.has(result):
			return result
	return &""


func _allocate_production_job_id() -> StringName:
	while true:
		var result := StringName("%s%08d" % [PRODUCTION_JOB_ID_PREFIX, next_production_job_serial])
		next_production_job_serial += 1
		if not production_jobs_by_id.has(result):
			return result
	return &""


func _maximum_serial(values: Dictionary, prefix: String) -> int:
	var maximum := 0
	for key: Variant in values:
		var text := String(key)
		if not text.begins_with(prefix):
			continue
		var suffix := text.substr(prefix.length())
		if suffix.is_valid_int():
			maximum = maxi(maximum, int(suffix))
	return maximum


func _sorted_keys(values: Dictionary) -> Array:
	var keys := values.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	return keys


func _normalize_movement(target_squads: Array) -> void:
	var used := false
	for squad: SquadState in target_squads:
		used = used or squad.movement_used
		for unit_id: StringName in squad.unit_instance_ids:
			var unit := get_unit(unit_id)
			used = used or (unit != null and unit.movement_used)
	for squad: SquadState in target_squads:
		squad.movement_used = used
		for unit_id: StringName in squad.unit_instance_ids:
			var unit := get_unit(unit_id)
			if unit != null:
				unit.movement_used = used


func _repair_squad_leader(squad: SquadState) -> void:
	if squad == null or squad.unit_instance_ids.is_empty():
		return
	var first_named_pilot: StringName = &""
	for unit_id: StringName in squad.slot_unit_ids:
		if unit_id.is_empty():
			continue
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		if unit.pilot_id == squad.leader_pilot_id and not squad.leader_pilot_id.is_empty():
			return
		if unit.pilot_id.is_empty():
			squad.leader_pilot_id = &""
			return
		if first_named_pilot.is_empty():
			first_named_pilot = unit.pilot_id
	squad.leader_pilot_id = first_named_pilot
