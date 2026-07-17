class_name RuntimeStateValidator
extends RefCounted

## Validates mutable unit and squad records as one campaign-state graph.

var _errors: PackedStringArray = []


func validate(
	units_by_id: Dictionary,
	squads_by_id: Dictionary,
	registry: MasterDataRegistry,
	valid_region_ids: Dictionary,
	max_hp_by_instance: Dictionary = {},
) -> PackedStringArray:
	_errors.clear()
	_validate_units(units_by_id, registry, max_hp_by_instance)
	_validate_squads(squads_by_id, units_by_id, registry, valid_region_ids)
	_validate_unit_squad_references(units_by_id, squads_by_id)
	_validate_named_pilot_uniqueness(units_by_id)
	_errors.sort()
	return _errors.duplicate()


func _validate_units(units: Dictionary, registry: MasterDataRegistry, hp_overrides: Dictionary) -> void:
	var seen_ids: Dictionary = {}
	for key: Variant in _sorted_keys(units):
		var unit: Variant = units[key]
		var label := "units[%s]" % key
		if not unit is UnitInstanceState:
			_error("%s: value must be UnitInstanceState" % label)
			continue
		var instance_id := StringName(unit.get("instance_id"))
		if instance_id == &"":
			_error("%s: instance_id must not be empty" % label)
		elif StringName(key) != instance_id:
			_error("%s: dictionary key does not match instance_id '%s'" % [label, instance_id])
		if seen_ids.has(instance_id):
			_error("%s: duplicate instance_id '%s'" % [label, instance_id])
		seen_ids[instance_id] = true

		var unit_def_id := StringName(unit.get("unit_def_id"))
		var unit_def: Variant = registry.units.get(unit_def_id)
		if unit_def_id == &"" or unit_def == null:
			_error("%s: unit_def_id '%s' does not resolve" % [label, unit_def_id])
		var owner_id := StringName(unit.get("owner_faction_id"))
		var origin_id := StringName(unit.get("origin_faction_id"))
		if owner_id == &"" or not registry.factions.has(owner_id):
			_error("%s: owner_faction_id '%s' does not resolve" % [label, owner_id])
		if origin_id == &"" or not registry.factions.has(origin_id):
			_error("%s: origin_faction_id '%s' does not resolve" % [label, origin_id])
		var pilot_id := StringName(unit.get("pilot_id"))
		if pilot_id != &"" and not registry.pilots.has(pilot_id):
			_error("%s: pilot_id '%s' does not resolve" % [label, pilot_id])

		var max_hp := int(unit_def.get("max_hp")) if unit_def != null else 0
		if hp_overrides.has(instance_id):
			max_hp = int(hp_overrides[instance_id])
		if max_hp < 0:
			_error("%s: maximum HP must not be negative" % label)
		var current_hp := int(unit.get("current_hp"))
		if current_hp < 0 or current_hp > max_hp:
			_error("%s: current_hp must be in 0..%d" % [label, max_hp])
		var max_en := int(unit_def.get("max_en")) if unit_def != null else 0
		var current_en := int(unit.get("current_en"))
		if current_en < 0 or current_en > max_en:
			_error("%s: current_en must be in 0..%d" % [label, max_en])

		var condition := int(unit.get("condition"))
		if condition < GameEnums.UnitCondition.ACTIVE or condition > GameEnums.UnitCondition.DESTROYED_RECOVERED:
			_error("%s: condition is outside UnitCondition" % label)
		var repair_turns := int(unit.get("repair_turns_remaining"))
		if condition == GameEnums.UnitCondition.REPAIRING:
			if repair_turns < 1:
				_error("%s: repairing unit requires repair_turns_remaining >= 1" % label)
		elif repair_turns != 0:
			_error("%s: non-repairing unit requires repair_turns_remaining == 0" % label)
		if condition == GameEnums.UnitCondition.DESTROYED_RECOVERED and current_hp != 0:
			_error("%s: destroyed recovered unit requires current_hp == 0" % label)

		var squad_id := StringName(unit.get("squad_id"))
		var slot_index := int(unit.get("slot_index"))
		if squad_id == &"":
			if slot_index != -1:
				_error("%s: unassigned unit requires slot_index == -1" % label)
		elif slot_index < 0 or slot_index >= GameConstants.MAX_UNITS_PER_SQUAD:
			_error("%s: assigned unit slot_index must be in 0..4" % label)


func _validate_squads(squads: Dictionary, units: Dictionary, registry: MasterDataRegistry, regions: Dictionary) -> void:
	var seen_ids: Dictionary = {}
	for key: Variant in _sorted_keys(squads):
		var squad: Variant = squads[key]
		var label := "squads[%s]" % key
		if not squad is SquadState:
			_error("%s: value must be SquadState" % label)
			continue
		var squad_id := StringName(squad.get("squad_id"))
		if squad_id == &"":
			_error("%s: squad_id must not be empty" % label)
		elif StringName(key) != squad_id:
			_error("%s: dictionary key does not match squad_id '%s'" % [label, squad_id])
		if seen_ids.has(squad_id):
			_error("%s: duplicate squad_id '%s'" % [label, squad_id])
		seen_ids[squad_id] = true

		var owner_id := StringName(squad.get("owner_faction_id"))
		if owner_id == &"" or not registry.factions.has(owner_id):
			_error("%s: owner_faction_id '%s' does not resolve" % [label, owner_id])
		var region_id := StringName(squad.get("region_id"))
		if region_id == &"" or not regions.has(region_id):
			_error("%s: region_id '%s' does not resolve" % [label, region_id])
		for field: String in ["move_origin_region_id", "planned_destination_region_id"]:
			var optional_region_id := StringName(squad.get(field))
			if optional_region_id != &"" and not regions.has(optional_region_id):
				_error("%s: %s '%s' does not resolve" % [label, field, optional_region_id])

		var unit_ids: Array = squad.get("unit_instance_ids")
		var slots: Array = squad.get("slot_unit_ids")
		if unit_ids.is_empty() or unit_ids.size() > GameConstants.MAX_UNITS_PER_SQUAD:
			_error("%s: unit_instance_ids must contain 1..5 units" % label)
		if slots.size() != GameConstants.MAX_UNITS_PER_SQUAD:
			_error("%s: slot_unit_ids must have exactly five entries" % label)
		var listed: Dictionary = {}
		for value: Variant in unit_ids:
			var unit_id := StringName(value)
			if unit_id == &"" or listed.has(unit_id):
				_error("%s: unit_instance_ids contains empty or duplicate id '%s'" % [label, unit_id])
			listed[unit_id] = true
		var slotted: Dictionary = {}
		for slot_index in range(slots.size()):
			var unit_id := StringName(slots[slot_index])
			if unit_id == &"":
				continue
			if slotted.has(unit_id):
				_error("%s: slot_unit_ids contains duplicate '%s'" % [label, unit_id])
			slotted[unit_id] = true
			if not listed.has(unit_id):
				_error("%s: slotted unit '%s' is absent from unit_instance_ids" % [label, unit_id])
			var unit: Variant = units.get(unit_id)
			if unit == null:
				_error("%s: unit '%s' does not resolve" % [label, unit_id])
			else:
				if StringName(unit.get("squad_id")) != squad_id or int(unit.get("slot_index")) != slot_index:
					_error("%s: unit '%s' squad/slot back-reference is inconsistent" % [label, unit_id])
				if StringName(unit.get("owner_faction_id")) != owner_id:
					_error("%s: unit '%s' owner differs from squad owner" % [label, unit_id])
		for unit_id: Variant in listed:
			if not slotted.has(unit_id):
				_error("%s: listed unit '%s' has no slot" % [label, unit_id])
			if not units.has(unit_id):
				_error("%s: listed unit '%s' does not resolve" % [label, unit_id])

		var leader_id := StringName(squad.get("leader_pilot_id"))
		if leader_id != &"":
			if not registry.pilots.has(leader_id):
				_error("%s: leader_pilot_id '%s' does not resolve" % [label, leader_id])
			var leader_found := false
			for unit_id: Variant in listed:
				var unit: Variant = units.get(unit_id)
				if unit != null and StringName(unit.get("pilot_id")) == leader_id:
					leader_found = true
			if not leader_found:
				_error("%s: named leader must pilot a unit in the squad" % label)
		else:
			var generic_leader_found := false
			for unit_id: Variant in listed:
				var unit: Variant = units.get(unit_id)
				if unit is UnitInstanceState and StringName(unit.get("pilot_id")) == &"":
					generic_leader_found = true
			if not generic_leader_found:
				_error("%s: generic leader requires a generic-piloted unit in the squad" % label)

		var policy := int(squad.get("battle_policy"))
		if policy < GameEnums.BattlePolicy.BALANCED or policy > GameEnums.BattlePolicy.RETREAT:
			_error("%s: battle_policy is outside BattlePolicy" % label)
		if int(squad.get("intel_revision")) < 0:
			_error("%s: intel_revision must not be negative" % label)


func _validate_unit_squad_references(units: Dictionary, squads: Dictionary) -> void:
	for key: Variant in _sorted_keys(units):
		var unit: Variant = units[key]
		if not unit is UnitInstanceState:
			continue
		var squad_id := StringName(unit.get("squad_id"))
		if squad_id != &"" and not squads.has(squad_id):
			_error("units[%s]: squad_id '%s' does not resolve" % [key, squad_id])


func _validate_named_pilot_uniqueness(units: Dictionary) -> void:
	var unit_by_pilot: Dictionary = {}
	for key: Variant in _sorted_keys(units):
		var unit: Variant = units[key]
		if not unit is UnitInstanceState:
			continue
		var pilot_id := StringName(unit.get("pilot_id"))
		if pilot_id == &"":
			continue
		if unit_by_pilot.has(pilot_id):
			_error("pilots[%s]: assigned to both '%s' and '%s'" % [pilot_id, unit_by_pilot[pilot_id], key])
		else:
			unit_by_pilot[pilot_id] = key


func _sorted_keys(values: Dictionary) -> Array:
	var keys := values.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	return keys


func _error(message: String) -> void:
	_errors.append(message)
