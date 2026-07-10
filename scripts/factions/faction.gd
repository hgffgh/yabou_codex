class_name Faction
extends RefCounted
## Runtime state for one faction, wrapping its static FactionDef content.

var def: FactionDef
var resources: int
var relations: Dictionary = {}  # other faction_id -> int (-100..100)
var is_ai_controlled: bool
var eliminated: bool = false

## Global "development level" — a faction-wide command (not per-region),
## matching the original series' overall-menu research command. Unlocks
## units whose UnitType.tech_tier_required <= tech_tier.
var tech_tier: int = 0
var research_in_progress: bool = false
var research_turns_remaining: int = 0

func _init(faction_def: FactionDef) -> void:
	def = faction_def
	resources = faction_def.starting_resources
	relations = faction_def.starting_relations.duplicate()
	is_ai_controlled = faction_def.is_ai_controlled
