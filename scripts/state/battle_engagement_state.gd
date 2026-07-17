class_name BattleEngagementState
extends RefCounted

const ROUND_DURATION_SEC := 30.0

var first_squad_id: StringName = &""
var second_squad_id: StringName = &""
var elapsed_sec: float = 0.0
var confirmed: bool = true

func contains(squad_id: StringName) -> bool:
	return squad_id == first_squad_id or squad_id == second_squad_id

func opponent_of(squad_id: StringName) -> StringName:
	if squad_id == first_squad_id: return second_squad_id
	if squad_id == second_squad_id: return first_squad_id
	return &""
