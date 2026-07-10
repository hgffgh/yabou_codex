class_name Diplomacy
extends RefCounted
## Lightweight relation-score model (-100..100 per faction pair). Feeds
## AiController's targeting (hostile relations lower the bar to attack,
## friendly ones raise it) rather than driving a full treaty/offer system —
## that's future scope beyond v1.

const ATTACK_PENALTY := -15.0
const DRIFT_PER_TURN := 1.0

static func relation(faction_id: StringName, other_id: StringName) -> float:
	if other_id == &"" or faction_id == other_id:
		return 0.0
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null:
		return 0.0
	return faction.relations.get(other_id, 0.0)

## Call once per turn after combat resolves: every battle sours relations
## between the two factions involved (symmetrically).
static func apply_combat_events(combat_log: Array) -> void:
	for entry in combat_log:
		if entry["type"] != "battle":
			continue
		_adjust_pair(entry["attacker_id"], entry["defender_id"], ATTACK_PENALTY)

## Call once per turn: relations drift back toward neutral (0) over time,
## so a single incident doesn't define a rivalry forever.
static func tick_drift() -> void:
	for faction_id in GameState.factions:
		var faction: Faction = GameState.factions[faction_id]
		for other_id in faction.relations.keys():
			var current: float = faction.relations[other_id]
			if current < 0.0:
				faction.relations[other_id] = min(current + DRIFT_PER_TURN, 0.0)
			elif current > 0.0:
				faction.relations[other_id] = max(current - DRIFT_PER_TURN, 0.0)

static func _adjust_pair(a: StringName, b: StringName, delta: float) -> void:
	_adjust_one(a, b, delta)
	_adjust_one(b, a, delta)

static func _adjust_one(faction_id: StringName, other_id: StringName, delta: float) -> void:
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null:
		return
	var current: float = faction.relations.get(other_id, 0.0)
	faction.relations[other_id] = clamp(current + delta, -100.0, 100.0)
