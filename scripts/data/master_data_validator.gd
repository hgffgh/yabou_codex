class_name MasterDataValidator
extends RefCounted

const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const DAMAGE_MULTIPLIERS: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5]
const PILOT_UNLOCK_LEVELS: Array[int] = [1, 10, 20, 30, 40]
const PILOT_CONDITIONS: Array[StringName] = [&"always", &"hp_pct", &"en_pct", &"environment"]
const PILOT_MODIFIERS: Array[StringName] = [
	&"firepower", &"accuracy", &"evasion", &"armor", &"critical",
]
const EVENT_CONDITION_TYPES: Array[StringName] = [
	&"turn_at_least", &"turn_at_most", &"region_owned", &"region_not_owned",
	&"squad_near_region", &"tech_researched", &"pilot_assigned", &"pilots_share_squad",
	&"pilot_injured", &"relation_band_at_least", &"treaty_active",
	&"capture_count_at_least", &"region_count_at_least", &"military_power_at_least",
	&"event_flag_set", &"event_choice_selected",
]

var _errors: PackedStringArray = []
var _id_regex := RegEx.new()


func validate(registry: MasterDataRegistry) -> PackedStringArray:
	_errors = registry.load_errors.duplicate()
	_id_regex.compile(ID_PATTERN)
	for category: StringName in [
		&"units", &"weapons", &"support_skills", &"pilots", &"pilot_skills",
		&"factions", &"techs", &"facility_defs", &"facility_instances",
		&"battle_maps", &"battle_control_points", &"terrain_zones", &"difficulties", &"achievements",
		&"event_effects", &"events", &"ai_profiles",
	]:
		_validate_ids(category, registry.get_category(category))
	_validate_global_id_uniqueness(registry)
	_validate_weapons(registry)
	_validate_support_skills(registry)
	_validate_units(registry)
	_validate_pilot_skills(registry)
	_validate_pilots(registry)
	_validate_facility_defs(registry)
	_validate_facility_instances(registry)
	_validate_battle_control_points(registry)
	_validate_terrain_zones(registry)
	_validate_battle_maps(registry)
	_validate_difficulties(registry)
	_validate_achievements(registry)
	_validate_techs(registry)
	_validate_event_effects(registry)
	_validate_events(registry)
	_validate_ai_profiles(registry)
	_errors.sort()
	return _errors.duplicate()


func _validate_global_id_uniqueness(registry: MasterDataRegistry) -> void:
	var category_by_id: Dictionary = {}
	for category: StringName in [
		&"units", &"weapons", &"support_skills", &"pilots", &"pilot_skills",
		&"factions", &"techs", &"facility_defs", &"facility_instances",
		&"battle_maps", &"battle_control_points", &"terrain_zones", &"difficulties", &"achievements",
		&"event_effects", &"events", &"ai_profiles",
	]:
		for id_value: Variant in registry.get_category(category):
			var id := StringName(id_value)
			if category_by_id.has(id):
				_error(category, id, "id is also used in %s" % category_by_id[id])
			else:
				category_by_id[id] = category


func _validate_ids(category: StringName, entries: Dictionary) -> void:
	for id_value: Variant in entries.keys():
		var id := StringName(id_value)
		if id == &"":
			_error(category, id, "id must not be empty")
		elif _id_regex.search(String(id)) == null:
			_error(category, id, "id must be lowercase snake_case")


func _validate_weapons(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.weapons):
		var item: Resource = registry.weapons[id]
		_require_key(item, &"display_name_key", &"weapons", id)
		_range_int(item, &"weapon_class", 0, 3, &"weapons", id)
		_range_int(item, &"damage_attribute", 0, 2, &"weapons", id)
		_range_int(item, &"action_type", 0, 0, &"weapons", id)
		_min_int(item, &"total_power", 1, &"weapons", id)
		_range_int(item, &"hit_count", 1, 10, &"weapons", id)
		_min_int(item, &"penetration", 0, &"weapons", id)
		_range_int(item, &"base_accuracy_pct", 0, 100, &"weapons", id)
		_range_int(item, &"base_critical_pct", 0, 100, &"weapons", id)
		_min_int(item, &"en_cost", 0, &"weapons", id)
		_min_float(item, &"post_action_delay_sec", 0.0, &"weapons", id)
		_min_float(item, &"min_range_m", 0.0, &"weapons", id)
		_min_float(item, &"max_range_m", 0.0, &"weapons", id)
		if float(item.get("min_range_m")) > float(item.get("max_range_m")):
			_error(&"weapons", id, "min_range_m must not exceed max_range_m")
		_range_int(item, &"target_rule", 0, 7, &"weapons", id)
		_range_int(item, &"target_pattern", 0, 7, &"weapons", id)
		if not bool(item.get("can_target_front")) and not bool(item.get("can_target_rear")):
			_error(&"weapons", id, "weapon must target at least one row")
		if int(item.get("damage_attribute")) == 2 and not bool(item.get("ignores_cover")):
			_error(&"weapons", id, "melee weapons must ignore cover")


func _validate_support_skills(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.support_skills):
		var item: Resource = registry.support_skills[id]
		_require_key(item, &"display_name_key", &"support_skills", id)
		var action := int(item.get("action_type"))
		if action != 1 and action != 2:
			_error(&"support_skills", id, "action_type must be REPAIR or EN_TRANSFER")
		var trigger := StringName(item.get("trigger_resource"))
		if trigger != &"hp_pct" and trigger != &"en_pct":
			_error(&"support_skills", id, "trigger_resource must be hp_pct or en_pct")
		_range_float(item, &"trigger_threshold_pct", 0.0, 1.0, &"support_skills", id)
		_range_int(item, &"target_rule", 0, 9, &"support_skills", id)
		var pattern := int(item.get("target_pattern"))
		if pattern != 0 and pattern != 7:
			_error(&"support_skills", id, "target_pattern must be SINGLE or ALL_ALLIES")
		_min_int(item, &"fixed_repair", 0, &"support_skills", id)
		_range_float(item, &"max_hp_repair_pct", 0.0, 1.0, &"support_skills", id)
		_min_int(item, &"transfer_en", 0, &"support_skills", id)
		_min_int(item, &"en_cost", 0, &"support_skills", id)
		_min_float(item, &"post_action_delay_sec", 0.0, &"support_skills", id)
		if action == 1 and int(item.get("fixed_repair")) == 0 and float(item.get("max_hp_repair_pct")) == 0.0:
			_error(&"support_skills", id, "repair skill must repair a positive amount")
		if action == 2:
			var transfer := int(item.get("transfer_en"))
			if transfer <= 0 or int(item.get("en_cost")) != transfer:
				_error(&"support_skills", id, "EN transfer must be positive and equal en_cost")


func _validate_units(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.units):
		var item: Resource = registry.units[id]
		_require_key(item, &"display_name_key", &"units", id)
		_require_key(item, &"description_key", &"units", id)
		_require_resource(item, &"icon", &"units", id)
		_require_resource(item, &"model_scene", &"units", id)
		_reference(item, &"faction_origin_id", &"factions", registry.factions, &"units", id)
		_reference(item, &"tech_id", &"techs", registry.techs, &"units", id)
		_references(item, &"weapon_ids", &"weapons", registry.weapons, &"units", id, true)
		_references(item, &"support_skill_ids", &"support_skills", registry.support_skills, &"units", id)
		_range_int(item, &"size", 0, 2, &"units", id)
		_range_int(item, &"role", 0, 4, &"units", id)
		for field: StringName in [&"ground_aptitude", &"space_aptitude", &"moon_aptitude"]:
			_range_int(item, field, 0, 2, &"units", id)
		for field: StringName in [&"max_hp", &"max_en", &"firepower", &"speed", &"sensor_range_m"]:
			_min_float(item, field, 1.0, &"units", id)
		_min_int(item, &"armor", 0, &"units", id)
		_min_int(item, &"evasion", 0, &"units", id)
		for field: StringName in [&"ballistic_damage_multiplier", &"beam_damage_multiplier", &"melee_damage_multiplier"]:
			if not DAMAGE_MULTIPLIERS.has(float(item.get(String(field)))):
				_error(&"units", id, "%s has unsupported value" % field)
		_min_float(item, &"power_adjustment", 0.000001, &"units", id)


func _validate_techs(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.techs):
		var item: Resource = registry.techs[id]
		_require_key(item, &"display_name_key", &"techs", id)
		_require_key(item, &"description_key", &"techs", id)
		_reference(item, &"origin_faction_id", &"factions", registry.factions, &"techs", id)
		_range_int(item, &"tier", 1, 5, &"techs", id)
		_require_key(item, &"category", &"techs", id)


func _validate_pilot_skills(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.pilot_skills):
		var item: Resource = registry.pilot_skills[id]
		_require_key(item, &"display_name_key", &"pilot_skills", id)
		_require_key(item, &"description_key", &"pilot_skills", id)
		if not PILOT_UNLOCK_LEVELS.has(int(item.get("unlock_level"))):
			_error(&"pilot_skills", id, "unlock_level must be 1, 10, 20, 30, or 40")
		if not PILOT_CONDITIONS.has(StringName(item.get("condition_type"))):
			_error(&"pilot_skills", id, "unsupported condition_type")
		var modifiers: Dictionary = item.get("modifiers")
		for key: Variant in modifiers:
			if not PILOT_MODIFIERS.has(StringName(key)):
				_error(&"pilot_skills", id, "unsupported modifier '%s'" % key)
			if not modifiers[key] is int and not modifiers[key] is float:
				_error(&"pilot_skills", id, "modifier '%s' must be numeric" % key)
		var action_skill_id := StringName(item.get("action_skill_id"))
		if action_skill_id != &"" and not registry.support_skills.has(action_skill_id):
			_error(&"pilot_skills", id, "action_skill_id '%s' does not resolve" % action_skill_id)


func _validate_pilots(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.pilots):
		var item: Resource = registry.pilots[id]
		_require_key(item, &"display_name_key", &"pilots", id)
		_require_key(item, &"description_key", &"pilots", id)
		_require_resource(item, &"portrait", &"pilots", id)
		_reference(item, &"faction_id", &"factions", registry.factions, &"pilots", id)
		_range_int(item, &"initial_level", 1, 50, &"pilots", id)
		for field: StringName in [&"initial_shooting", &"initial_melee", &"initial_defense", &"initial_reaction", &"initial_command"]:
			_range_int(item, field, 0, 200, &"pilots", id)
		for field: StringName in [&"growth_shooting", &"growth_melee", &"growth_defense", &"growth_reaction", &"growth_command"]:
			_range_int(item, field, 0, 3, &"pilots", id)
		var skills: Array = item.get("skill_ids")
		if skills.size() > 5:
			_error(&"pilots", id, "skill_ids must contain at most five entries")
		_references(item, &"skill_ids", &"pilot_skills", registry.pilot_skills, &"pilots", id)
		for field: StringName in [&"preferred_unit_ids", &"poor_unit_ids", &"exclusive_unit_ids"]:
			_references(item, field, &"units", registry.units, &"pilots", id)


func _validate_facility_defs(registry: MasterDataRegistry) -> void:
	var expected_values: Dictionary = {
		GameEnums.FacilityType.ECONOMY: [300, 0, 0, 0.0],
		GameEnums.FacilityType.LARGE_ECONOMY: [600, 0, 0, 0.0],
		GameEnums.FacilityType.RESOURCE: [0, 200, 0, 0.0],
		GameEnums.FacilityType.LARGE_RESOURCE: [0, 400, 0, 0.0],
		GameEnums.FacilityType.RESEARCH: [0, 0, 0, 0.05],
		GameEnums.FacilityType.PRODUCTION: [0, 0, 100, 0.0],
		GameEnums.FacilityType.LARGE_PRODUCTION: [0, 0, 200, 0.0],
	}
	for id: StringName in _sorted_ids(registry.facility_defs):
		var item: Resource = registry.facility_defs[id]
		_require_key(item, &"display_name_key", &"facility_defs", id)
		_range_int(item, &"facility_type", 0, 6, &"facility_defs", id)
		var facility_type := int(item.get("facility_type"))
		if not expected_values.has(facility_type):
			continue
		var expected: Array = expected_values[facility_type]
		if int(item.get("funds_income")) != int(expected[0]):
			_error(&"facility_defs", id, "funds_income contradicts facility_type")
		if int(item.get("materials_income")) != int(expected[1]):
			_error(&"facility_defs", id, "materials_income contradicts facility_type")
		if int(item.get("production_power")) != int(expected[2]):
			_error(&"facility_defs", id, "production_power contradicts facility_type")
		if not is_equal_approx(float(item.get("research_discount_pct")), float(expected[3])):
			_error(&"facility_defs", id, "research_discount_pct contradicts facility_type")


func _validate_facility_instances(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.facility_instances):
		var item: Resource = registry.facility_instances[id]
		_reference(
			item, &"facility_def_id", &"facility_defs", registry.facility_defs,
			&"facility_instances", id
		)
		_require_key(item, &"region_id", &"facility_instances", id)

func _validate_battle_control_points(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.battle_control_points):
		var item: Resource = registry.battle_control_points[id]
		_min_float(item, &"capture_radius_m", 0.000001, &"battle_control_points", id)
		_min_float(item, &"sensor_radius_m", 0.000001, &"battle_control_points", id)
		_range_float(item, &"hp_recovery_pct_per_sec", 0.0, 1.0, &"battle_control_points", id)
		_range_float(item, &"en_recovery_pct_per_sec", 0.0, 1.0, &"battle_control_points", id)

func _validate_terrain_zones(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.terrain_zones):
		var item: Resource = registry.terrain_zones[id]
		_range_int(item, &"effect", 0, 4, &"terrain_zones", id)
		_min_float(item, &"radius_m", 0.000001, &"terrain_zones", id)
		_range_float(item, &"move_multiplier", 0.0, 2.0, &"terrain_zones", id)
		_range_int(item, &"evasion_add", 0, 100, &"terrain_zones", id)
		_range_float(item, &"hazard_hp_pct_per_sec", 0.0, 1.0, &"terrain_zones", id)

func _validate_battle_maps(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.battle_maps):
		var item: Resource = registry.battle_maps[id]
		_require_resource(item, &"scene", &"battle_maps", id)
		_range_int(item, &"environment", 0, 2, &"battle_maps", id)
		var world_size: Vector2 = item.get("world_size_m")
		if world_size.x <= 0.0 or world_size.y <= 0.0: _error(&"battle_maps", id, "world_size_m axes must be positive")
		_reference(item, &"attacker_hq_id", &"battle_control_points", registry.battle_control_points, &"battle_maps", id)
		_reference(item, &"defender_hq_id", &"battle_control_points", registry.battle_control_points, &"battle_maps", id)
		_references(item, &"control_point_ids", &"battle_control_points", registry.battle_control_points, &"battle_maps", id)
		_references(item, &"terrain_zone_ids", &"terrain_zones", registry.terrain_zones, &"battle_maps", id)
		if item.get("attacker_hq_id") == item.get("defender_hq_id"): _error(&"battle_maps", id, "headquarters IDs must differ")
		if NodePath(item.get("navigation_region_path")).is_empty(): _error(&"battle_maps", id, "navigation_region_path must not be empty")


func _validate_difficulties(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.difficulties):
		var item: Resource = registry.difficulties[id]
		_min_float(item, &"enemy_income_multiplier", 0.000001, &"difficulties", id)
		_min_float(item, &"enemy_hp_multiplier", 0.000001, &"difficulties", id)
		_min_float(item, &"enemy_firepower_multiplier", 0.000001, &"difficulties", id)
		_range_int(item, &"enemy_accuracy_add", -50, 50, &"difficulties", id)
		_range_int(item, &"enemy_evasion_add", -50, 50, &"difficulties", id)
		_require_key(item, &"ai_profile_id", &"difficulties", id)


func _validate_achievements(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.achievements):
		var item: Resource = registry.achievements[id]
		_require_key(item, &"condition_type", &"achievements", id)
		_range_float(item, &"exp_bonus_pct", 0.0, 0.5, &"achievements", id)


func _validate_ai_profiles(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.ai_profiles):
		var item: Resource = registry.ai_profiles[id]
		_min_float(item, &"aggression_multiplier", 0.000001, &"ai_profiles", id)
		_min_int(item, &"production_queue_length", 1, &"ai_profiles", id)
		_min_int(item, &"research_reserve", 0, &"ai_profiles", id)


func _validate_event_effects(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.event_effects):
		var item: Resource = registry.event_effects[id]
		_range_int(item, &"effect_type", 0, 12, &"event_effects", id)


func _validate_events(registry: MasterDataRegistry) -> void:
	for id: StringName in _sorted_ids(registry.events):
		var item: Resource = registry.events[id]
		_require_key(item, &"title_key", &"events", id)
		_reference(item, &"faction_id", &"factions", registry.factions, &"events", id)
		_range_int(item, &"importance", 0, 1, &"events", id)
		_validate_condition_tree(item.get("condition_tree"), &"events", id)
		var seen_choice_ids: Dictionary = {}
		for choice_value: Variant in item.get("choice_entries") as Array:
			if not choice_value is Dictionary:
				_error(&"events", id, "choice_entries entry must be a Dictionary")
				continue
			var choice := choice_value as Dictionary
			var choice_id := StringName(choice.get("id", ""))
			if choice_id == &"":
				_error(&"events", id, "choice_entries entry must have a non-empty id")
			elif seen_choice_ids.has(choice_id):
				_error(&"events", id, "choice_entries contains duplicate choice id '%s'" % choice_id)
			seen_choice_ids[choice_id] = true
			if StringName(choice.get("label_key", "")) == &"":
				_error(&"events", id, "choice_entries entry '%s' must have a label_key" % choice_id)
			for effect_value: Variant in choice.get("effect_ids", []) as Array:
				if not registry.event_effects.has(StringName(effect_value)):
					_error(&"events", id, "choice '%s' effect_id '%s' does not resolve in event_effects" % [choice_id, effect_value])
		for effect_value: Variant in item.get("default_effect_ids") as Array:
			if not registry.event_effects.has(StringName(effect_value)):
				_error(&"events", id, "default_effect_ids '%s' does not resolve in event_effects" % effect_value)
		for followup_value: Variant in item.get("followup_event_ids") as Array:
			if not registry.events.has(StringName(followup_value)):
				_error(&"events", id, "followup_event_ids '%s' does not resolve in events" % followup_value)
		for dialogue_value: Variant in item.get("dialogue_entries") as Array:
			if not dialogue_value is Dictionary or StringName((dialogue_value as Dictionary).get("body_key", "")) == &"":
				_error(&"events", id, "dialogue_entries entry must be a Dictionary with a non-empty body_key")
		if (item.get("dialogue_entries") as Array).is_empty() and (item.get("choice_entries") as Array).is_empty() and (item.get("default_effect_ids") as Array).is_empty():
			_error(&"events", id, "event has no dialogue, choices, or default effects -- it would do nothing")


func _validate_condition_tree(tree: Variant, category: StringName, id: StringName) -> void:
	if not tree is Dictionary:
		_error(category, id, "condition_tree must be a Dictionary")
		return
	var node := tree as Dictionary
	if node.is_empty():
		return
	if node.has("all") or node.has("any"):
		var children: Variant = node.get("all", node.get("any"))
		if not children is Array or (children as Array).is_empty():
			_error(category, id, "condition_tree all/any must be a non-empty Array")
			return
		for child: Variant in children as Array:
			_validate_condition_tree(child, category, id)
		return
	if node.has("not"):
		_validate_condition_tree(node["not"], category, id)
		return
	if not EVENT_CONDITION_TYPES.has(StringName(node.get("type", ""))):
		_error(category, id, "condition_tree has unsupported type '%s'" % node.get("type", ""))


func _reference(item: Resource, field: StringName, target_name: StringName, target: Dictionary, category: StringName, id: StringName) -> void:
	var reference := StringName(item.get(String(field)))
	if reference == &"":
		_error(category, id, "%s must not be empty" % field)
	elif not target.has(reference):
		_error(category, id, "%s '%s' does not resolve in %s" % [field, reference, target_name])


func _references(item: Resource, field: StringName, target_name: StringName, target: Dictionary, category: StringName, id: StringName, require_non_empty: bool = false) -> void:
	var references: Array = item.get(String(field))
	if require_non_empty and references.is_empty():
		_error(category, id, "%s must not be empty" % field)
	var seen: Dictionary = {}
	for value: Variant in references:
		var reference := StringName(value)
		if reference == &"" or not target.has(reference):
			_error(category, id, "%s '%s' does not resolve in %s" % [field, reference, target_name])
		if seen.has(reference):
			_error(category, id, "%s contains duplicate '%s'" % [field, reference])
		seen[reference] = true


func _require_key(item: Resource, field: StringName, category: StringName, id: StringName) -> void:
	if StringName(item.get(String(field))) == &"":
		_error(category, id, "%s must not be empty" % field)


func _require_resource(item: Resource, field: StringName, category: StringName, id: StringName) -> void:
	if item.get(String(field)) == null:
		_error(category, id, "%s must be assigned" % field)


func _range_int(item: Resource, field: StringName, minimum: int, maximum: int, category: StringName, id: StringName) -> void:
	var value := int(item.get(String(field)))
	if value < minimum or value > maximum:
		_error(category, id, "%s must be in %d..%d" % [field, minimum, maximum])


func _min_int(item: Resource, field: StringName, minimum: int, category: StringName, id: StringName) -> void:
	if int(item.get(String(field))) < minimum:
		_error(category, id, "%s must be at least %d" % [field, minimum])


func _range_float(item: Resource, field: StringName, minimum: float, maximum: float, category: StringName, id: StringName) -> void:
	var value := float(item.get(String(field)))
	if value < minimum or value > maximum:
		_error(category, id, "%s must be in %s..%s" % [field, minimum, maximum])


func _min_float(item: Resource, field: StringName, minimum: float, category: StringName, id: StringName) -> void:
	if float(item.get(String(field))) < minimum:
		_error(category, id, "%s must be at least %s" % [field, minimum])


func _sorted_ids(entries: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: Variant in entries:
		ids.append(StringName(id))
	ids.sort()
	return ids


func _error(category: StringName, id: StringName, message: String) -> void:
	_errors.append("%s[%s]: %s" % [category, id, message])
