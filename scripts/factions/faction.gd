class_name Faction
extends RefCounted
## Runtime state for one faction, wrapping its static FactionDef content.

var def: FactionDef
var resources: int
var relations: Dictionary = {}  # other faction_id -> int (-100..100)
var is_ai_controlled: bool
var eliminated: bool = false

func _init(faction_def: FactionDef) -> void:
	def = faction_def
	resources = faction_def.starting_resources
	relations = faction_def.starting_relations.duplicate()
	is_ai_controlled = faction_def.is_ai_controlled
