class_name Faction
extends RefCounted
## Runtime state for one faction, wrapping its static FactionDef content.

var def: FactionDef
var resources: int
var funds: int
var materials: int
var is_ai_controlled: bool
var eliminated: bool = false

## Global "development level" — a faction-wide command (not per-region),
## matching the original series' overall-menu research command. Legacy
## placeholder from the prototype tech system; superseded by the generated
## tech-node tree in DATA_DEFINITION.md once that migration lands.
var tech_tier: int = 0
var research_in_progress: bool = false
var research_turns_remaining: int = 0

func _init(faction_def: FactionDef) -> void:
	def = faction_def
	resources = faction_def.starting_resources
	funds = faction_def.starting_funds
	materials = faction_def.starting_materials
	is_ai_controlled = faction_def.is_ai_controlled
