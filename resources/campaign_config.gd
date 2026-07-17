class_name CampaignConfig
extends Resource

@export var turn_cap: int = 24
@export var victory_region_threshold_pct: float = 0.6
@export var faction_turn_order: Array[StringName] = []

## STRATEGY_DETAIL_SPECIFICATION.md section 7.3: index i (0-based) is Tier
## i+1's base funds cost / turn duration, before TurnManager applies each
## faction's research-facility discount.
@export var research_costs: Array[int] = [1000, 2000, 3000, 5000, 8000]
@export var research_turns: Array[int] = [1, 2, 3, 4, 5]
