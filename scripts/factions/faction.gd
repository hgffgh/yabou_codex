class_name Faction
extends RefCounted
## Runtime state for one faction, wrapping its static FactionDef content.

var def: FactionDef
var resources: int
var funds: int
var materials: int
var is_ai_controlled: bool
var eliminated: bool = false

## STRATEGY_DETAIL_SPECIFICATION.md section 7.2 / DATA_DEFINITION.md section
## 15.1: this faction's campaign-generated tech tree (TechTreeGenerator),
## keyed by node_id. Fixed once at campaign start; gift_tech can add extra
## gifted nodes to it afterward.
var generated_tech_nodes: Dictionary = {}
## Null when nothing is being researched. At most one at a time
## (DATA_DEFINITION.md section 15.2).
var current_research: ResearchState = null

## DATA_DEFINITION.md section 23's capture_ten_units-style achievement
## condition needs a running total across the whole campaign, not just a
## single battle's BattleResultState.captured_unit_ids.
var total_units_captured: int = 0

func _init(faction_def: FactionDef) -> void:
	def = faction_def
	resources = faction_def.starting_resources
	funds = faction_def.starting_funds
	materials = faction_def.starting_materials
	is_ai_controlled = faction_def.is_ai_controlled
