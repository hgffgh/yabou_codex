class_name EventConditionEvaluator
extends RefCounted
## Evaluates an EventDef.condition_tree Dictionary against live campaign
## state for one faction. EVENT_DETAIL_SPECIFICATION.md section 3 lists ten
## trigger categories in prose; this maps each to one or more concrete,
## data-driven condition "type"s (chosen here, since DATA_DEFINITION.md
## explicitly leaves "イベントID・条件・排他グループのデータ形式" undecided):
##
##   1. 特定ターン                     -> turn_at_least / turn_at_most
##   2. エリアの制圧・喪失             -> region_owned / region_not_owned
##   3. 敵本拠地への接近               -> squad_near_region (BFS hop count
##                                        over RegionDef.neighbor_ids)
##   4. 技術・機体の研究               -> tech_researched
##   5. パイロット配置・同部隊編成     -> pilot_assigned / pilots_share_squad
##   6. 固有パイロットの撃破・負傷     -> pilot_injured (this ruleset has no
##                                        permanent pilot death -- a
##                                        destroyed unit's pilot is always
##                                        just injured, so "撃破" collapses
##                                        into the same condition)
##   7. 友好度・条約状態               -> relation_band_at_least / treaty_active
##   8. 鹵獲・解析                     -> capture_count_at_least ("解析"/
##                                        encyclopedia has no backing system
##                                        yet, so only the capture count half
##                                        is modeled)
##   9. 領地数・軍事力                 -> region_count_at_least /
##                                        military_power_at_least
##   10. 過去イベントの選択結果        -> event_choice_selected / event_flag_set
##
## `game_state` is passed explicitly rather than referenced by the bare
## GameState autoload identifier -- see Diplomacy's class doc comment for why.

static func evaluate(tree: Dictionary, game_state: Node, faction_id: StringName) -> bool:
	if tree.is_empty():
		return true
	if tree.has("all"):
		for child: Variant in tree["all"] as Array:
			if not evaluate(child as Dictionary, game_state, faction_id):
				return false
		return true
	if tree.has("any"):
		for child: Variant in tree["any"] as Array:
			if evaluate(child as Dictionary, game_state, faction_id):
				return true
		return false
	if tree.has("not"):
		return not evaluate(tree["not"] as Dictionary, game_state, faction_id)
	return _evaluate_leaf(StringName(tree.get("type", "")), tree, game_state, faction_id)


static func _evaluate_leaf(type: StringName, params: Dictionary, game_state: Node, faction_id: StringName) -> bool:
	match type:
		&"turn_at_least":
			return game_state.turn_number >= int(params.get("turn", 0))
		&"turn_at_most":
			return game_state.turn_number <= int(params.get("turn", 0))
		&"region_owned":
			var region: Region = game_state.get_region(StringName(params.get("region_id", "")))
			return region != null and region.owner_faction_id == faction_id
		&"region_not_owned":
			var region2: Region = game_state.get_region(StringName(params.get("region_id", "")))
			return region2 != null and region2.owner_faction_id != faction_id
		&"squad_near_region":
			return _squad_near_region(game_state, faction_id, StringName(params.get("target_region_id", "")), int(params.get("max_hops", 0)))
		&"tech_researched":
			return _tech_researched(game_state, faction_id, StringName(params.get("tech_id", "")))
		&"pilot_assigned":
			var pilot: PilotState = game_state.campaign_runtime.get_pilot(StringName(params.get("pilot_id", "")))
			return pilot != null and pilot.is_assigned()
		&"pilots_share_squad":
			return _pilots_share_squad(game_state, StringName(params.get("pilot_id_a", "")), StringName(params.get("pilot_id_b", "")))
		&"pilot_injured":
			var pilot2: PilotState = game_state.campaign_runtime.get_pilot(StringName(params.get("pilot_id", "")))
			return pilot2 != null and pilot2.is_injured()
		&"relation_band_at_least":
			return _relation_band_at_least(game_state, faction_id, StringName(params.get("other_faction_id", "")), StringName(params.get("band", "neutral")))
		&"treaty_active":
			return _treaty_active(game_state, faction_id, StringName(params.get("other_faction_id", "")), StringName(params.get("treaty_type", "")))
		&"capture_count_at_least":
			var faction: Faction = game_state.get_faction(faction_id)
			return faction != null and faction.total_units_captured >= int(params.get("count", 0))
		&"region_count_at_least":
			return game_state.region_count_for(faction_id) >= int(params.get("count", 0))
		&"military_power_at_least":
			return BattlePowerEstimator.faction_total_power(faction_id, game_state.campaign_runtime, game_state.master_data) >= float(params.get("count", 0))
		&"event_flag_set":
			var faction2: Faction = game_state.get_faction(faction_id)
			return faction2 != null and bool(faction2.event_flags.get(StringName(params.get("flag", "")), false))
		&"event_choice_selected":
			var faction3: Faction = game_state.get_faction(faction_id)
			if faction3 == null:
				return false
			var key := StringName("choice:%s" % StringName(params.get("event_id", "")))
			return StringName(faction3.event_flags.get(key, "")) == StringName(params.get("choice_id", ""))
	return false


static func _tech_researched(game_state: Node, faction_id: StringName, tech_id: StringName) -> bool:
	var faction: Faction = game_state.get_faction(faction_id)
	if faction == null:
		return false
	for node_id: StringName in faction.generated_tech_nodes:
		var node := faction.generated_tech_nodes[node_id] as GeneratedTechNodeState
		if node.tech_id == tech_id and node.researched:
			return true
	return false


static func _pilots_share_squad(game_state: Node, pilot_id_a: StringName, pilot_id_b: StringName) -> bool:
	var pilot_a: PilotState = game_state.campaign_runtime.get_pilot(pilot_id_a)
	var pilot_b: PilotState = game_state.campaign_runtime.get_pilot(pilot_id_b)
	if pilot_a == null or pilot_b == null or not pilot_a.is_assigned() or not pilot_b.is_assigned():
		return false
	var unit_a: UnitInstanceState = game_state.campaign_runtime.get_unit(pilot_a.assigned_unit_instance_id)
	var unit_b: UnitInstanceState = game_state.campaign_runtime.get_unit(pilot_b.assigned_unit_instance_id)
	return unit_a != null and unit_b != null and not unit_a.squad_id.is_empty() and unit_a.squad_id == unit_b.squad_id


static func _relation_band_at_least(game_state: Node, faction_id: StringName, other_faction_id: StringName, band_name: StringName) -> bool:
	var band := _band_from_name(band_name)
	if other_faction_id.is_empty() or faction_id == other_faction_id:
		return false
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(faction_id, other_faction_id)
	return int(relation.relation_band()) >= int(band)


static func _band_from_name(name: StringName) -> GameEnums.RelationBand:
	match name:
		&"nemesis": return GameEnums.RelationBand.NEMESIS
		&"hostile": return GameEnums.RelationBand.HOSTILE
		&"friendly": return GameEnums.RelationBand.FRIENDLY
		&"close": return GameEnums.RelationBand.CLOSE
		_: return GameEnums.RelationBand.NEUTRAL


static func _treaty_active(game_state: Node, faction_id: StringName, other_faction_id: StringName, treaty_name: StringName) -> bool:
	if other_faction_id.is_empty() or faction_id == other_faction_id:
		return false
	var current := Diplomacy.current_treaty_type(game_state, faction_id, other_faction_id)
	if treaty_name.is_empty() or treaty_name == &"any":
		return current != GameEnums.TreatyType.NONE
	var wanted := GameEnums.TreatyType.CEASEFIRE if treaty_name == &"ceasefire" else GameEnums.TreatyType.NON_AGGRESSION
	return current == wanted


## BFS over RegionDef.neighbor_ids from every region_id where faction_id
## currently has a squad, capped at max_hops, looking for target_region_id.
static func _squad_near_region(game_state: Node, faction_id: StringName, target_region_id: StringName, max_hops: int) -> bool:
	if target_region_id.is_empty():
		return false
	var occupied: Dictionary = {}
	for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if squad != null and squad.owner_faction_id == faction_id and not squad.unit_instance_ids.is_empty():
			occupied[squad.region_id] = true
	if occupied.is_empty():
		return false
	var visited: Dictionary = {}
	var frontier: Array = []
	for region_id: Variant in occupied:
		visited[region_id] = 0
		frontier.append(region_id)
	while not frontier.is_empty():
		var region_id: StringName = frontier.pop_front()
		var hops: int = visited[region_id]
		if region_id == target_region_id:
			return true
		if hops >= max_hops:
			continue
		var region_def := game_state.region_defs.get(region_id) as RegionDef
		if region_def == null:
			continue
		for neighbor_id: StringName in region_def.neighbor_ids:
			if not visited.has(neighbor_id):
				visited[neighbor_id] = hops + 1
				frontier.append(neighbor_id)
	return false
