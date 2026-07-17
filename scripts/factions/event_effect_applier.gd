class_name EventEffectApplier
extends RefCounted
## Applies one EventEffectDef to a faction. EVENT_DETAIL_SPECIFICATION.md
## section 5 lists effect categories in prose; GameEnums.EventEffectType
## enumerates them and this maps each to a concrete payload shape (schema
## chosen here, same as EventConditionEvaluator's condition types, since
## DATA_DEFINITION.md leaves the exact data format undecided):
##
##   FUNDS               {"amount": int}            faction.funds delta, floored at 0
##   MATERIALS           {"amount": int}             faction.materials delta, floored at 0
##   TECH_CANDIDATE       {"tech_id": StringName}     grants a new gifted-style
##                        research candidate node (same dedup-by-tech_id and
##                        "gifted" prerequisite rule as Diplomacy.gift_tech)
##   RESEARCH_MODIFIER   {"turns_delta": int}         adjusts current_research's
##                        remaining turns (min 1); no-op if nothing is being
##                        researched
##   PILOT_JOIN           {"pilot_id": StringName}    registers a roster pilot
##                        that hasn't joined yet (PilotDef.initial_level, no
##                        unit assignment)
##   PILOT_LEAVE          {"pilot_id": StringName}    unassigns and marks
##                        PilotState.available = false (stays on record, just
##                        can no longer be assigned -- see PilotState's
##                        "available" field)
##   PILOT_INJURE         {"pilot_id": StringName}    forces the standard
##                        3-turn injury via GameState's own helper
##   UNIT_GAIN            {"unit_def_id": StringName, "region_id": StringName
##                        (optional, defaults to the faction's capital)}
##   UNIT_LOSE            {"unit_def_id": StringName (optional filter)}
##                        removes one matching owned unit, preferring an
##                        unassigned one
##   RELATION             {"other_faction_id": StringName, "delta": int}
##   TREATY               {"other_faction_id": StringName, "treaty_type":
##                        StringName ("none"/"ceasefire"/"non_aggression"),
##                        "duration": int (optional)}
##   ENEMY_REINFORCEMENT {"target_faction_id": StringName, "unit_def_id":
##                        StringName, "region_id": StringName}
##   EVENT_FLAG           {"flag": StringName, "value": bool (optional, true)}
##
## `game_state` is passed explicitly for the same reason as Diplomacy's
## functions -- see that class's doc comment.

static func apply(game_state: Node, faction_id: StringName, effect: EventEffectDef) -> void:
	if effect == null:
		return
	var faction: Faction = game_state.get_faction(faction_id)
	if faction == null:
		return
	var payload := effect.payload
	match effect.effect_type:
		GameEnums.EventEffectType.FUNDS:
			faction.funds = maxi(0, faction.funds + int(payload.get("amount", 0)))
		GameEnums.EventEffectType.MATERIALS:
			faction.materials = maxi(0, faction.materials + int(payload.get("amount", 0)))
		GameEnums.EventEffectType.TECH_CANDIDATE:
			_grant_tech_candidate(game_state, faction, StringName(payload.get("tech_id", "")))
		GameEnums.EventEffectType.RESEARCH_MODIFIER:
			if faction.current_research != null:
				faction.current_research.turns_remaining = maxi(1, faction.current_research.turns_remaining + int(payload.get("turns_delta", 0)))
		GameEnums.EventEffectType.PILOT_JOIN:
			_pilot_join(game_state, faction_id, StringName(payload.get("pilot_id", "")))
		GameEnums.EventEffectType.PILOT_LEAVE:
			_pilot_leave(game_state, StringName(payload.get("pilot_id", "")))
		GameEnums.EventEffectType.PILOT_INJURE:
			_pilot_injure(game_state, StringName(payload.get("pilot_id", "")))
		GameEnums.EventEffectType.UNIT_GAIN:
			_unit_gain(game_state, faction_id, StringName(payload.get("unit_def_id", "")), StringName(payload.get("region_id", "")))
		GameEnums.EventEffectType.UNIT_LOSE:
			_unit_lose(game_state, faction_id, StringName(payload.get("unit_def_id", "")))
		GameEnums.EventEffectType.RELATION:
			_relation(game_state, faction_id, StringName(payload.get("other_faction_id", "")), int(payload.get("delta", 0)))
		GameEnums.EventEffectType.TREATY:
			_treaty(game_state, faction_id, StringName(payload.get("other_faction_id", "")), StringName(payload.get("treaty_type", "none")), int(payload.get("duration", 0)))
		GameEnums.EventEffectType.ENEMY_REINFORCEMENT:
			_unit_gain(game_state, StringName(payload.get("target_faction_id", "")), StringName(payload.get("unit_def_id", "")), StringName(payload.get("region_id", "")))
		GameEnums.EventEffectType.EVENT_FLAG:
			faction.event_flags[StringName(payload.get("flag", ""))] = bool(payload.get("value", true))


static func _grant_tech_candidate(game_state: Node, faction: Faction, tech_id: StringName) -> void:
	if tech_id.is_empty():
		return
	for existing_id: StringName in faction.generated_tech_nodes:
		if (faction.generated_tech_nodes[existing_id] as GeneratedTechNodeState).tech_id == tech_id:
			return
	var tech_def := game_state.master_data.techs.get(tech_id) as TechDef
	if tech_def == null:
		return
	var node := GeneratedTechNodeState.new()
	node.node_id = StringName("event_%s_%s" % [faction.def.id, tech_id])
	node.tech_id = tech_id
	node.tier = tech_def.tier
	node.gifted = true
	faction.generated_tech_nodes[node.node_id] = node


## Unlike GameState._apply_pilot_injury (called right after the pilot's unit
## was already destroyed/removed, so the unit side of the link doesn't
## matter), an event-injured pilot's unit is still alive and active -- use
## unassign_pilot so the unit's pilot_id/squad-leader bookkeeping stays
## consistent too, then apply the standard 3-turn injury countdown.
static func _pilot_injure(game_state: Node, pilot_id: StringName) -> void:
	if pilot_id.is_empty():
		return
	var pilot: PilotState = game_state.campaign_runtime.get_pilot(pilot_id)
	if pilot == null:
		return
	game_state.campaign_runtime.unassign_pilot(pilot_id)
	pilot.injury_turns_remaining = GameConstants.PILOT_INJURY_TURNS


static func _pilot_join(game_state: Node, faction_id: StringName, pilot_id: StringName) -> void:
	if pilot_id.is_empty() or game_state.campaign_runtime.get_pilot(pilot_id) != null:
		return
	var pilot_def := game_state.master_data.pilots.get(pilot_id) as PilotDef
	if pilot_def == null:
		return
	var pilot := PilotState.new()
	pilot.pilot_id = pilot_id
	pilot.owner_faction_id = faction_id
	pilot.level = clampi(pilot_def.initial_level, 1, GameConstants.PILOT_LEVEL_CAP)
	pilot.available = true
	pilot.joined = true
	game_state.campaign_runtime.register_pilot(pilot)


static func _pilot_leave(game_state: Node, pilot_id: StringName) -> void:
	var pilot: PilotState = game_state.campaign_runtime.get_pilot(pilot_id)
	if pilot == null:
		return
	game_state.campaign_runtime.unassign_pilot(pilot_id)
	pilot.available = false
	pilot.joined = false


static func _unit_gain(game_state: Node, faction_id: StringName, unit_def_id: StringName, region_id: StringName) -> void:
	if unit_def_id.is_empty() or not game_state.master_data.units.has(unit_def_id):
		return
	var target_region_id := region_id
	if target_region_id.is_empty():
		var faction_def := game_state.faction_defs.get(faction_id) as FactionDef
		if faction_def == null:
			return
		target_region_id = faction_def.starting_region_id
	game_state.rollout_new_unit(unit_def_id, faction_id, target_region_id)


static func _unit_lose(game_state: Node, faction_id: StringName, unit_def_id: StringName) -> void:
	var candidate_id := &""
	var candidate_assigned := true
	var unit_ids: Array = game_state.campaign_runtime.units_by_id.keys()
	unit_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for instance_id: StringName in unit_ids:
		var unit: UnitInstanceState = game_state.campaign_runtime.get_unit(instance_id)
		if unit == null or unit.owner_faction_id != faction_id:
			continue
		if not unit_def_id.is_empty() and unit.unit_def_id != unit_def_id:
			continue
		var assigned := not unit.squad_id.is_empty()
		if candidate_id.is_empty() or (candidate_assigned and not assigned):
			candidate_id = instance_id
			candidate_assigned = assigned
			if not assigned:
				break
	if candidate_id.is_empty():
		return
	game_state.campaign_runtime.remove_unit_from_squad(candidate_id)
	game_state.campaign_runtime.units_by_id.erase(candidate_id)


static func _relation(game_state: Node, faction_id: StringName, other_faction_id: StringName, delta: int) -> void:
	if other_faction_id.is_empty() or faction_id == other_faction_id:
		return
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(faction_id, other_faction_id)
	relation.friendship = clampi(relation.friendship + delta, GameConstants.FRIENDSHIP_MIN, GameConstants.FRIENDSHIP_MAX)


static func _treaty(game_state: Node, faction_id: StringName, other_faction_id: StringName, treaty_name: StringName, duration: int) -> void:
	if other_faction_id.is_empty() or faction_id == other_faction_id:
		return
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(faction_id, other_faction_id)
	if treaty_name == &"ceasefire":
		relation.treaty_type = GameEnums.TreatyType.CEASEFIRE
		relation.treaty_turns_remaining = maxi(1, duration)
	elif treaty_name == &"non_aggression":
		relation.treaty_type = GameEnums.TreatyType.NON_AGGRESSION
		relation.treaty_turns_remaining = maxi(1, duration)
	else:
		relation.treaty_type = GameEnums.TreatyType.NONE
		relation.treaty_turns_remaining = 0
