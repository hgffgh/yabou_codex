class_name BattleSquadState
extends RefCounted

var squad_id: StringName = &""
var faction_id: StringName = &""
var unit_instance_ids: Array[StringName] = []
var world_position: Vector3 = Vector3.ZERO
var destination: Vector3 = Vector3.ZERO
var spawn_position: Vector3 = Vector3.ZERO
var retreat_region_id: StringName = &""
var policy: GameEnums.BattlePolicy = GameEnums.BattlePolicy.BALANCED
var sensor_range_m: float = 0.0
var reengage_wait_sec: float = 0.0
var retreat_prepare_sec: float = 0.0
var retreat_requested: bool = false
var last_battle_time_sec: float = -1.0
var intel_revision: int = 0
var leader_unit_id: StringName = &""
var leader_command: int = 100
