class_name BattleUnitState
extends RefCounted

var unit_instance_id: StringName = &""
var unit_def_id: StringName = &""
var pilot_id: StringName = &""
var squad_id: StringName = &""
var slot_index: int = -1
var initial_hp: int = 0
var initial_en: int = 0
var current_hp: int = 0
var current_en: int = 0
var max_hp: int = 0
var max_en: int = 0
var shooting: int = 100
var melee: int = 100
var defense: int = 100
var reaction: int = 100
var command: int = 100
var pilot_level: int = 1
var hp_recovery_fraction: float = 0.0
var en_recovery_fraction: float = 0.0
var action_gauge: float = 0.0
var post_action_delay_sec: float = 0.0
var defending: bool = false
var destroyed_this_battle: bool = false
var exp_earned: int = 0
