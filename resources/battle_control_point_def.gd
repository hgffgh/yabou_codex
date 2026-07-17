class_name BattleControlPointDef
extends Resource

@export var id: StringName
@export var is_headquarters: bool = false
@export var position: Vector3 = Vector3.ZERO
@export var capture_radius_m: float = 70.0
@export var sensor_radius_m: float = 400.0
@export var hp_recovery_pct_per_sec: float = 0.01
@export var en_recovery_pct_per_sec: float = 0.02

