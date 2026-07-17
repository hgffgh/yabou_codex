class_name MasterDataRegistry
extends RefCounted

## Deterministic, type-checked index of immutable master data.

const SOURCES: Array[Dictionary] = [
	{"key": &"units", "path": "res://data/units/", "class": &"UnitDef"},
	{"key": &"weapons", "path": "res://data/weapons/", "class": &"WeaponDef"},
	{"key": &"support_skills", "path": "res://data/support_skills/", "class": &"SupportSkillDef"},
	{"key": &"pilots", "path": "res://data/pilots/", "class": &"PilotDef"},
	{"key": &"pilot_skills", "path": "res://data/pilot_skills/", "class": &"PilotSkillDef"},
	{"key": &"factions", "path": "res://data/factions/", "class": &"FactionDef"},
	{"key": &"techs", "path": "res://data/techs/", "class": &"TechDef"},
	{"key": &"facility_defs", "path": "res://data/facility_defs/", "class": &"FacilityDef"},
	{"key": &"facility_instances", "path": "res://data/facilities/", "class": &"FacilityInstanceDef"},
	{"key": &"battle_maps", "path": "res://data/battle_maps/", "class": &"BattleMapDef"},
	{"key": &"battle_control_points", "path": "res://data/battle_control_points/", "class": &"BattleControlPointDef"},
	{"key": &"terrain_zones", "path": "res://data/terrain_zones/", "class": &"TerrainZoneDef"},
]

var units: Dictionary = {}
var weapons: Dictionary = {}
var support_skills: Dictionary = {}
var pilots: Dictionary = {}
var pilot_skills: Dictionary = {}
var factions: Dictionary = {}
var techs: Dictionary = {}
var facility_defs: Dictionary = {}
var facility_instances: Dictionary = {}
var battle_maps: Dictionary = {}
var battle_control_points: Dictionary = {}
var terrain_zones: Dictionary = {}

var load_errors: PackedStringArray = []
var source_paths: Dictionary = {} # "category:id" -> resource path


func load_all() -> void:
	load_errors.clear()
	source_paths.clear()
	for source: Dictionary in SOURCES:
		var category: StringName = source["key"]
		var loaded := _load_directory(
			category,
			String(source["path"]),
			StringName(source["class"])
		)
		set(String(category), loaded)


func get_category(category: StringName) -> Dictionary:
	var value: Variant = get(String(category))
	return value if value is Dictionary else {}


func has_id(category: StringName, id: StringName) -> bool:
	return get_category(category).has(id)


func _load_directory(category: StringName, path: String, expected_class: StringName) -> Dictionary:
	var result: Dictionary = {}
	var first_path_by_id: Dictionary = {}
	var directory := DirAccess.open(path)
	if directory == null:
		load_errors.append("%s: cannot open directory %s" % [category, path])
		return result

	var file_names := PackedStringArray()
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	file_names.sort()

	for current_file_name: String in file_names:
		var resource_path := path.path_join(current_file_name)
		var resource := ResourceLoader.load(resource_path)
		if resource == null:
			load_errors.append("%s: failed to load %s" % [category, resource_path])
			continue
		var actual_class := _script_global_name(resource)
		if actual_class != expected_class:
			load_errors.append(
				"%s: %s has type %s; expected %s"
				% [category, resource_path, actual_class, expected_class]
			)
			continue
		var id_value: Variant = resource.get("id")
		if not id_value is StringName:
			load_errors.append("%s: %s has no StringName id" % [category, resource_path])
			continue
		var id: StringName = id_value
		if result.has(id):
			load_errors.append(
				"%s: duplicate id '%s' in %s and %s"
				% [category, id, first_path_by_id[id], resource_path]
			)
			continue
		result[id] = resource
		first_path_by_id[id] = resource_path
		source_paths["%s:%s" % [category, id]] = resource_path
	return result


func _script_global_name(resource: Resource) -> StringName:
	var script := resource.get_script() as Script
	if script == null:
		return &""
	return StringName(script.get_global_name())
