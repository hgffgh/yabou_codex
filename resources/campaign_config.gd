class_name CampaignConfig
extends Resource

@export var turn_cap: int = 24
@export var victory_region_threshold_pct: float = 0.6

## Index i = cost/turns to research from tier i to tier i+1. Array length
## determines the max tech tier (2 entries = tiers 0,1,2 reachable).
@export var research_costs: Array[int] = [80, 150]
@export var research_turns: Array[int] = [3, 4]
