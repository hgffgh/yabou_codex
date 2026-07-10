extends Node
## Single source of truth for factions/regions/turn state at runtime.
## Static content (Region/Faction/UnitType defs) is loaded once at boot by
## scanning res://data/; runtime state is rebuilt on start_new_game().

signal turn_advanced(turn_number: int)
signal region_ownership_changed(region_id: StringName, old_owner: StringName, new_owner: StringName)
signal faction_eliminated(faction_id: StringName)
signal game_over(reason: String, standings: Array)

var region_defs: Dictionary = {}   # StringName -> RegionDef
var faction_defs: Dictionary = {}  # StringName -> FactionDef
var unit_defs: Dictionary = {}     # StringName -> UnitType
var campaign_config: CampaignConfig

var turn_number: int = 1
var factions: Dictionary = {}  # StringName -> Faction
var regions: Dictionary = {}   # StringName -> Region
var player_faction_id: StringName = &""
var is_game_over: bool = false
var last_game_over_reason: String = ""
var last_game_over_standings: Array = []

func _ready() -> void:
	_load_static_data()

func _load_static_data() -> void:
	region_defs = _load_resources_in_dir("res://data/regions/")
	faction_defs = _load_resources_in_dir("res://data/factions/")
	unit_defs = _load_resources_in_dir("res://data/units/")
	campaign_config = load("res://data/campaign_config.tres")

func _load_resources_in_dir(path: String) -> Dictionary:
	var result := {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("GameState: cannot open directory %s" % path)
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: Resource = load(path + file_name)
			if res != null and "id" in res:
				result[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	return result

func start_new_game(chosen_player_faction_id: StringName) -> void:
	turn_number = 1
	is_game_over = false
	player_faction_id = chosen_player_faction_id
	factions.clear()
	regions.clear()

	for id in faction_defs:
		var f := Faction.new(faction_defs[id])
		f.is_ai_controlled = id != chosen_player_faction_id
		factions[id] = f

	for id in region_defs:
		regions[id] = Region.new(region_defs[id])

	turn_advanced.emit(turn_number)

func advance_turn() -> void:
	turn_number += 1
	turn_advanced.emit(turn_number)

func get_region(id: StringName) -> Region:
	return regions.get(id)

func get_faction(id: StringName) -> Faction:
	return factions.get(id)

func set_region_owner(region_id: StringName, new_owner_id: StringName) -> void:
	var region: Region = regions[region_id]
	var old_owner := region.owner_faction_id
	if old_owner == new_owner_id:
		return
	region.owner_faction_id = new_owner_id
	region_ownership_changed.emit(region_id, old_owner, new_owner_id)
	_check_capital_loss(region_id, old_owner)

## A faction is eliminated the moment it no longer holds its own designated
## capital region — losing someone else's captured capital doesn't count.
func _check_capital_loss(region_id: StringName, old_owner: StringName) -> void:
	if old_owner == &"":
		return
	var faction: Faction = factions.get(old_owner)
	if faction == null or faction.eliminated:
		return
	if faction.def.starting_region_id == region_id:
		faction.eliminated = true
		faction_eliminated.emit(old_owner)

func region_count_for(faction_id: StringName) -> int:
	var count := 0
	for region in regions.values():
		if region.owner_faction_id == faction_id:
			count += 1
	return count

func alive_faction_ids() -> Array:
	var ids := []
	for fid in factions:
		if not factions[fid].eliminated:
			ids.append(fid)
	return ids
