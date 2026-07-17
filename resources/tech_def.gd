class_name TechDef
extends Resource
## DATA_DEFINITION.md section 15. Cost/duration are not per-tech -- they
## come from CampaignConfig.research_costs/research_turns, indexed by tier.

@export var id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
@export var origin_faction_id: StringName
@export_range(1, 5, 1) var tier: int = 1
@export var category: StringName = &"unit"
## Schema-only for now: nothing gates production/support-skill availability
## on research yet (production only checks UnitDef.faction_origin_id).
@export var unlocks_unit_ids: Array[StringName] = []
@export var unlocks_skill_ids: Array[StringName] = []
@export var candidate_tags: Array[StringName] = []
## Always placed in its origin faction's generated tree; never eligible for
## another faction's random draw.
@export var mandatory_base_tech: bool = false
@export var giftable: bool = true
## Schema-only: no capture-analysis system exists yet.
@export var capture_unlockable: bool = false
## Schema-only: no encyclopedia/cross-campaign candidate-pool system exists
## yet -- TechTreeGenerator currently draws from every non-mandatory TechDef
## unconditionally. See HANDOFF.md for the scope tradeoff.
@export var encyclopedia_unlockable: bool = true
