class_name BattleResultState
extends RefCounted

var winner_faction_id: StringName = &""
var loser_faction_id: StringName = &""
var reason: StringName = &""
var elapsed_world_sec: float = 0.0
var destroyed_unit_ids: Array[StringName] = []
var recovered_unit_ids: Array[StringName] = []
var captured_unit_ids: Array[StringName] = []
var lost_unit_ids: Array[StringName] = []
var injured_pilot_ids: Array[StringName] = []
var pilot_exp: Dictionary = {}

