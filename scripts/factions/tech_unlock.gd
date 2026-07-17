class_name TechUnlock
extends RefCounted
## DATA_DEFINITION.md section 15's TechDef.unlocks_unit_ids/unlocks_skill_ids
## were schema-only until now -- declared but never read anywhere, so every
## unit was always producible regardless of what a faction had researched.
##
## A unit_def_id/skill_id not referenced by *any* TechDef's unlocks_unit_ids/
## unlocks_skill_ids is unrestricted (always available): these fields are an
## opt-in restriction a tech author adds to specific content, not a
## requirement to cover every unit/skill in the dataset. One that IS
## referenced by some tech requires the faction to have researched at least
## one tech listing it (STRATEGY_DETAIL_SPECIFICATION.md never specifies
## "exactly one" vs "any" gating tech for a given unlock, so "any" was
## chosen -- the same permissive rule TurnManager._node_prerequisites_met
## already uses for a gifted node's tier prerequisite).
##
## unlocks_skill_ids gating (which support skill a unit/pilot can actually
## use in battle) is not wired up by this class -- support_skill_ids/
## PilotSkillDef.action_skill_id are fixed per UnitDef/PilotDef with no
## player-facing loadout selection, so gating their live usability would
## need a researched-tech snapshot threaded through BattleRuntimeFactory/
## BattleCombatSystem's support-candidate gathering, a distinct and more
## invasive change from production gating. is_skill_unlocked exists for
## when that lands, but nothing calls it yet.

static func is_unit_unlocked(faction: Faction, unit_def_id: StringName, registry: MasterDataRegistry) -> bool:
	if not _is_restricted(unit_def_id, registry, true):
		return true
	return _has_researched_unlocking_tech(faction, unit_def_id, registry, true)


static func is_skill_unlocked(faction: Faction, skill_id: StringName, registry: MasterDataRegistry) -> bool:
	if not _is_restricted(skill_id, registry, false):
		return true
	return _has_researched_unlocking_tech(faction, skill_id, registry, false)


static func _is_restricted(id: StringName, registry: MasterDataRegistry, unit_mode: bool) -> bool:
	for tech_id: StringName in registry.techs:
		var def := registry.techs[tech_id] as TechDef
		var list := def.unlocks_unit_ids if unit_mode else def.unlocks_skill_ids
		if list.has(id):
			return true
	return false


static func _has_researched_unlocking_tech(faction: Faction, id: StringName, registry: MasterDataRegistry, unit_mode: bool) -> bool:
	for node_id: StringName in faction.generated_tech_nodes:
		var node := faction.generated_tech_nodes[node_id] as GeneratedTechNodeState
		if not node.researched:
			continue
		var def := registry.techs.get(node.tech_id) as TechDef
		if def == null:
			continue
		var list := def.unlocks_unit_ids if unit_mode else def.unlocks_skill_ids
		if list.has(id):
			return true
	return false
