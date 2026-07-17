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

## DATA_DEFINITION.md section 6.2 / EVENT_DETAIL_SPECIFICATION.md. Set by
## EventEffectDef.EVENT_FLAG and read by EventConditionEvaluator's
## event_flag_set condition; also where GameState.resolve_event_choice
## records "choice:<event_id>" -> chosen choice_id, backing the
## event_choice_selected condition (past-choice-result triggers).
var event_flags: Dictionary = {}
## Events whose condition became true and are waiting to be played (player
## faction) or auto-resolved (AI factions) before the next ORDERS phase --
## see TurnManager._begin_faction_turn/GameState.check_pending_events.
var pending_event_ids: Array[StringName] = []
## Every EventDef.id ever registered for this faction this campaign, gating
## once_per_campaign and exclusive_group_id (a second member of the same
## group can never register once any one member has).
var triggered_event_ids: Array[StringName] = []

func _init(faction_def: FactionDef) -> void:
	def = faction_def
	resources = faction_def.starting_resources
	funds = faction_def.starting_funds
	materials = faction_def.starting_materials
	is_ai_controlled = faction_def.is_ai_controlled
