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
## Read by TechUnlock.is_unit_unlocked, which gates GameState.
## queue_production/AiController._best_affordable_unit -- a unit not listed
## by any tech here is unrestricted, matching UnitDef.faction_origin_id's
## own gating alone.
@export var unlocks_unit_ids: Array[StringName] = []
## Schema-only for now: TechUnlock.is_skill_unlocked exists but nothing
## calls it yet -- see that class's own doc comment for why gating a fixed,
## non-player-selected support skill's live battle usability is a distinct,
## more invasive change than production gating.
@export var unlocks_skill_ids: Array[StringName] = []
@export var candidate_tags: Array[StringName] = []
## Always placed in its origin faction's generated tree; never eligible for
## another faction's random draw.
@export var mandatory_base_tech: bool = false
@export var giftable: bool = true
## Schema-only: no capture-analysis system exists yet.
@export var capture_unlockable: bool = false
## Schema-only: ProfileState.unlocked_tech_candidate_ids (the real
## cross-campaign permanent pool TechTreeGenerator reads) only grows via
## researching a tech, not via completing the encyclopedia -- see
## TechTreeGenerator's own doc comment.
@export var encyclopedia_unlockable: bool = true
