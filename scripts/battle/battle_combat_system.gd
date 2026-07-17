class_name BattleCombatSystem
extends RefCounted

const GAUGE_MAX := 100.0
const SIMULATION_STEP_SEC := 0.05

static func advance(battle: BattleRuntimeState, delta_sec: float) -> void:
	if delta_sec <= 0.0 or battle.unit_defs.is_empty() or battle.weapon_defs.is_empty():
		return
	battle.combat_events.clear()
	var remaining := delta_sec
	while remaining > 0.000001 and battle.result == null:
		var step := minf(SIMULATION_STEP_SEC, remaining)
		battle.update_engagements(step)
		_advance_step(battle, step)
		remaining -= step

static func _advance_step(battle: BattleRuntimeState, delta_sec: float) -> void:
	var ready: Array[StringName] = []
	var unit_ids: Array[StringName] = []
	for value: Variant in battle.unit_states_by_id.keys(): unit_ids.append(StringName(value))
	unit_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for unit_id: StringName in unit_ids:
		var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		if unit.current_hp <= 0: continue
		if not battle.is_squad_engaged(unit.squad_id): continue
		var engagement := battle.engagements_by_squad_id[unit.squad_id] as BattleEngagementState
		if not engagement.confirmed: continue
		if unit.post_action_delay_sec > 0.0:
			unit.post_action_delay_sec = maxf(0.0, unit.post_action_delay_sec - delta_sec)
			continue
		var unit_def := battle.unit_defs.get(unit.unit_def_id) as UnitDef
		if unit_def == null: continue
		unit.action_gauge = minf(GAUGE_MAX, unit.action_gauge + 10.0 * sqrt(float(unit_def.speed) / 100.0) * delta_sec)
		if unit.action_gauge >= GAUGE_MAX: ready.append(unit_id)
	var attacks: Array[Dictionary] = []
	var supports: Array[Dictionary] = []
	for attacker_id: StringName in ready:
		var attacker := battle.unit_states_by_id[attacker_id] as BattleUnitState
		var squad := battle.squad_states_by_id[attacker.squad_id] as BattleSquadState
		var support := _prepare_support(battle, attacker_id) if squad.policy == GameEnums.BattlePolicy.SUPPORT else {}
		var attack := _prepare_attack(battle, attacker_id) if support.is_empty() else {}
		if attack.is_empty() and support.is_empty(): support = _prepare_support(battle, attacker_id)
		attacker.action_gauge = 0.0
		if attack.is_empty() and support.is_empty():
			attacker.defending = true
		elif not attack.is_empty():
			attacker.defending = false
			attacker.current_en -= (attack.weapon as WeaponDef).en_cost
			attacker.post_action_delay_sec = (attack.weapon as WeaponDef).post_action_delay_sec
			# COMBAT_DETAIL_SPECIFICATION.md section 24: firing from outside
			# sensor range discloses the attacker's current position for 5
			# battle-seconds, ignoring obstacles.
			var attacking_squad := battle.squad_states_by_id[attacker.squad_id] as BattleSquadState
			if not attacking_squad.currently_sensed:
				attacking_squad.revealed_until_world_sec = battle.elapsed_world_sec + 5.0
			attacks.append(attack)
		else:
			attacker.defending = false
			var skill := support.skill as SupportSkillDef
			attacker.current_en -= _support_cost(skill)
			attacker.post_action_delay_sec = skill.post_action_delay_sec
			supports.append(support)
	var damage_by_target := {}
	var attackers_by_target: Dictionary = {}
	for attack: Dictionary in attacks:
		for target_id: StringName in attack.target_ids:
			var total_damage := _resolve_attack(battle, attack, target_id)
			damage_by_target[target_id] = int(damage_by_target.get(target_id, 0)) + total_damage
			if total_damage > 0:
				var contributors: Array = attackers_by_target.get(target_id, [])
				contributors.append(attack.attacker_id)
				attackers_by_target[target_id] = contributors
	for target_id: StringName in damage_by_target:
		var target := battle.unit_states_by_id[target_id] as BattleUnitState
		target.current_hp = maxi(0, target.current_hp - int(damage_by_target[target_id]))
		if target.current_hp == 0:
			target.destroyed_this_battle = true
			for attacker_id: Variant in attackers_by_target.get(target_id, []):
				var attacker_unit := battle.unit_states_by_id.get(attacker_id) as BattleUnitState
				if attacker_unit != null:
					attacker_unit.exp_earned += GameConstants.PILOT_EXP_ENEMY_DESTROYED
	for support: Dictionary in supports:
		_apply_support(battle, support)
	_finalize_annihilation(battle)

static func _prepare_support(battle: BattleRuntimeState, source_id: StringName) -> Dictionary:
	var source := battle.unit_states_by_id[source_id] as BattleUnitState
	var unit_def := battle.unit_defs.get(source.unit_def_id) as UnitDef
	if unit_def == null: return {}
	var skill_ids := unit_def.support_skill_ids.duplicate()
	skill_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var left := battle.support_skill_defs.get(a) as SupportSkillDef
		var right := battle.support_skill_defs.get(b) as SupportSkillDef
		if left != null and right != null and left.priority != right.priority: return left.priority < right.priority
		return String(a) < String(b))
	for skill_id: StringName in skill_ids:
		var skill := battle.support_skill_defs.get(skill_id) as SupportSkillDef
		if skill == null or source.current_en < _support_cost(skill): continue
		var target_id := _select_support_target(battle, source, skill)
		if not target_id.is_empty(): return {"source_id": source_id, "target_id": target_id, "skill": skill}
	return {}

static func _select_support_target(battle: BattleRuntimeState, source: BattleUnitState, skill: SupportSkillDef) -> StringName:
	var squad := battle.squad_states_by_id[source.squad_id] as BattleSquadState
	var candidates: Array[BattleUnitState] = []
	for unit_id: StringName in squad.unit_instance_ids:
		var target := battle.unit_states_by_id[unit_id] as BattleUnitState
		if target.current_hp <= 0 or (target.unit_instance_id == source.unit_instance_id and not skill.can_target_self): continue
		var ratio := float(target.current_hp) / float(maxi(1, target.max_hp)) if skill.action_type == GameEnums.ActionType.REPAIR else float(target.current_en) / float(maxi(1, target.max_en))
		if ratio > skill.trigger_threshold_pct: continue
		if skill.action_type == GameEnums.ActionType.REPAIR and target.current_hp >= target.max_hp: continue
		if skill.action_type == GameEnums.ActionType.EN_TRANSFER and target.max_en - target.current_en < skill.transfer_en: continue
		candidates.append(target)
	if candidates.is_empty(): return &""
	candidates.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		var a_value := _support_target_value(battle, a, skill.target_rule)
		var b_value := _support_target_value(battle, b, skill.target_rule)
		if a_value != b_value: return a_value < b_value
		return a.slot_index < b.slot_index)
	return candidates[0].unit_instance_id

static func _support_target_value(battle: BattleRuntimeState, unit: BattleUnitState, rule: int) -> float:
	match rule:
		GameEnums.SupportTargetRule.LOW_HP_RATIO: return float(unit.current_hp) / float(maxi(1, unit.max_hp))
		GameEnums.SupportTargetRule.HIGH_HP_LOSS: return -float(unit.max_hp - unit.current_hp)
		GameEnums.SupportTargetRule.LOW_EN_RATIO: return float(unit.current_en) / float(maxi(1, unit.max_en))
		GameEnums.SupportTargetRule.HIGH_EN_CONSUMPTION: return -float(unit.max_en - unit.current_en)
		GameEnums.SupportTargetRule.FRONT: return 0.0 if unit.slot_index <= 2 else 1.0
		GameEnums.SupportTargetRule.REAR: return 0.0 if unit.slot_index >= 3 else 1.0
		GameEnums.SupportTargetRule.LEADER:
			var squad := battle.squad_states_by_id[unit.squad_id] as BattleSquadState
			return 0.0 if squad.leader_unit_id == unit.unit_instance_id else 1.0
	return 0.0

static func _support_cost(skill: SupportSkillDef) -> int:
	return skill.en_cost

static func _apply_support(battle: BattleRuntimeState, action: Dictionary) -> void:
	var source := battle.unit_states_by_id[action.source_id] as BattleUnitState
	var target := battle.unit_states_by_id[action.target_id] as BattleUnitState
	var skill := action.skill as SupportSkillDef
	if target.current_hp <= 0: return
	var amount := 0
	if skill.action_type == GameEnums.ActionType.REPAIR:
		amount = mini(target.max_hp - target.current_hp, roundi(float(skill.fixed_repair) + float(target.max_hp) * skill.max_hp_repair_pct))
		target.current_hp += amount
	elif skill.action_type == GameEnums.ActionType.EN_TRANSFER:
		amount = mini(target.max_en - target.current_en, skill.transfer_en)
		target.current_en += amount
	else: return
	# STRATEGY_DETAIL_SPECIFICATION.md section 5.3: only an actual HP/EN
	# increase grants support-success EXP (a no-op repair/transfer earns none).
	if amount > 0:
		source.exp_earned += GameConstants.PILOT_EXP_SUPPORT_SUCCESS
	battle.combat_events.append({"type": &"support", "source_unit_id": source.unit_instance_id, "target_unit_id": target.unit_instance_id, "skill_id": skill.id, "amount": amount, "action_type": skill.action_type})

static func _prepare_attack(battle: BattleRuntimeState, attacker_id: StringName) -> Dictionary:
	var attacker := battle.unit_states_by_id[attacker_id] as BattleUnitState
	var attacker_squad := battle.squad_states_by_id[attacker.squad_id] as BattleSquadState
	var unit_def := battle.unit_defs.get(attacker.unit_def_id) as UnitDef
	if attacker_squad.policy == GameEnums.BattlePolicy.DEFENSIVE and attacker.current_hp * 100 <= attacker.max_hp * 30:
		return {}
	for weapon_id: StringName in unit_def.weapon_ids:
		var weapon := battle.weapon_defs.get(weapon_id) as WeaponDef
		if weapon == null or attacker.current_en < weapon.en_cost: continue
		var target_id := _select_target(battle, attacker_squad, weapon)
		if not target_id.is_empty():
			return {"attacker_id": attacker_id, "target_ids": _pattern_targets(battle, target_id, attacker_squad, weapon), "weapon_id": weapon_id, "weapon": weapon}
	return {}

static func _select_target(battle: BattleRuntimeState, attacker_squad: BattleSquadState, weapon: WeaponDef) -> StringName:
	var candidates: Array[BattleUnitState] = []
	var opponent_id := battle.engaged_opponent_id(attacker_squad.squad_id)
	for squad: BattleSquadState in battle.squad_states_by_id.values():
		if squad.squad_id != opponent_id: continue
		var distance := Vector2(attacker_squad.world_position.x, attacker_squad.world_position.y).distance_to(Vector2(squad.world_position.x, squad.world_position.y))
		if distance < weapon.min_range_m or distance > weapon.max_range_m: continue
		for unit_id: StringName in squad.unit_instance_ids:
			var target := battle.unit_states_by_id[unit_id] as BattleUnitState
			if target.current_hp <= 0: continue
			if target.slot_index <= 2 and weapon.can_target_front: candidates.append(target)
	if candidates.is_empty() and weapon.can_target_rear:
		for squad: BattleSquadState in battle.squad_states_by_id.values():
			if squad.squad_id != opponent_id: continue
			var distance := Vector2(attacker_squad.world_position.x, attacker_squad.world_position.y).distance_to(Vector2(squad.world_position.x, squad.world_position.y))
			if distance < weapon.min_range_m or distance > weapon.max_range_m: continue
			for unit_id: StringName in squad.unit_instance_ids:
				var target := battle.unit_states_by_id[unit_id] as BattleUnitState
				if target.current_hp > 0 and target.slot_index >= 3: candidates.append(target)
	if candidates.is_empty(): return &""
	if weapon.target_rule == GameEnums.TargetRule.RANDOM:
		return candidates[roll(battle, candidates.size())].unit_instance_id
	candidates.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool: return _target_before(battle, a, b, weapon.target_rule))
	return candidates[0].unit_instance_id

static func _target_before(battle: BattleRuntimeState, a: BattleUnitState, b: BattleUnitState, rule: int) -> bool:
	var a_def := battle.unit_defs[a.unit_def_id] as UnitDef
	var b_def := battle.unit_defs[b.unit_def_id] as UnitDef
	var a_value: float = 0.0
	var b_value: float = 0.0
	match rule:
		GameEnums.TargetRule.LOW_HP: a_value = a.current_hp; b_value = b.current_hp
		GameEnums.TargetRule.HIGH_HP: a_value = -a.current_hp; b_value = -b.current_hp
		GameEnums.TargetRule.LOW_ARMOR: a_value = a_def.armor; b_value = b_def.armor
		GameEnums.TargetRule.HIGH_ARMOR: a_value = -a_def.armor; b_value = -b_def.armor
		GameEnums.TargetRule.HIGH_SPEED: a_value = -a_def.speed; b_value = -b_def.speed
		GameEnums.TargetRule.SUPPORT:
			a_value = 0.0 if a_def.role == GameEnums.UnitRole.SUPPORT else 1.0
			b_value = 0.0 if b_def.role == GameEnums.UnitRole.SUPPORT else 1.0
	if a_value != b_value: return a_value < b_value
	if a.slot_index != b.slot_index: return a.slot_index < b.slot_index
	return String(a.unit_instance_id) < String(b.unit_instance_id)

static func _pattern_targets(battle: BattleRuntimeState, primary_id: StringName, attacker_squad: BattleSquadState, weapon: WeaponDef) -> Array[StringName]:
	var primary := battle.unit_states_by_id[primary_id] as BattleUnitState
	var target_squad := battle.squad_states_by_id[primary.squad_id] as BattleSquadState
	var source_squad := target_squad
	if weapon.target_pattern == GameEnums.TargetPattern.ALL_ALLIES: source_squad = attacker_squad
	var allowed_slots: Array[int] = []
	match weapon.target_pattern:
		GameEnums.TargetPattern.SINGLE: allowed_slots = [primary.slot_index]
		GameEnums.TargetPattern.FRONT_ROW: allowed_slots = [0, 1, 2]
		GameEnums.TargetPattern.REAR_ROW: allowed_slots = [3, 4]
		GameEnums.TargetPattern.LEFT_COLUMN: allowed_slots = [0, 3]
		GameEnums.TargetPattern.CENTER: allowed_slots = [1]
		GameEnums.TargetPattern.RIGHT_COLUMN: allowed_slots = [2, 4]
		GameEnums.TargetPattern.ALL_ENEMIES, GameEnums.TargetPattern.ALL_ALLIES: allowed_slots = [0, 1, 2, 3, 4]
	var result: Array[StringName] = []
	for unit_id: StringName in source_squad.unit_instance_ids:
		var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		if unit.current_hp > 0 and allowed_slots.has(unit.slot_index): result.append(unit_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return (battle.unit_states_by_id[a] as BattleUnitState).slot_index < (battle.unit_states_by_id[b] as BattleUnitState).slot_index)
	return result

static func _resolve_attack(battle: BattleRuntimeState, attack: Dictionary, target_id: StringName) -> int:
	var attacker := battle.unit_states_by_id[attack.attacker_id] as BattleUnitState
	var target := battle.unit_states_by_id[target_id] as BattleUnitState
	var attacker_def := battle.unit_defs[attacker.unit_def_id] as UnitDef
	var target_def := battle.unit_defs[target.unit_def_id] as UnitDef
	var weapon := attack.weapon as WeaponDef
	var total := 0
	for _hit in range(weapon.hit_count):
		var attacker_squad := battle.squad_states_by_id[attacker.squad_id] as BattleSquadState
		var target_squad := battle.squad_states_by_id[target.squad_id] as BattleSquadState
		var attack_skill := attacker.melee if weapon.damage_attribute == GameEnums.DamageAttribute.MELEE else attacker.shooting
		var attack_bonus := (float(attack_skill) - 100.0) * 0.2
		var reaction_bonus := (float(target.reaction) - 100.0) * 0.2
		var attack_command := (float(_active_leader_command(battle, attacker_squad)) - 100.0) * 0.1
		var defense_command := (float(_active_leader_command(battle, target_squad)) - 100.0) * 0.1
		var accuracy := clampi(roundi(float(weapon.base_accuracy_pct) + attack_bonus + attack_command - float(target_def.evasion) - reaction_bonus - defense_command - (10.0 if target.defending else 0.0) + pilot_skill_modifier(battle, attacker, &"accuracy") - pilot_skill_modifier(battle, target, &"evasion")), 5, 95)
		var hit := roll(battle, 100) < accuracy
		var damage := 0
		var critical := false
		if hit:
			var hit_power := float(weapon.total_power) / float(weapon.hit_count)
			var pilot_firepower := float(attack_skill - 100)
			var pilot_armor := float(roundi((float(target.defense) - 100.0) * 0.5))
			var effective_armor := maxf(0.0, float(target_def.armor) + pilot_armor + (20.0 if target.defending else 0.0) - float(weapon.penetration) + pilot_skill_modifier(battle, target, &"armor"))
			var base_damage := maxf(hit_power * 0.05, float(attacker_def.firepower) + pilot_firepower + hit_power - effective_armor + pilot_skill_modifier(battle, attacker, &"firepower"))
			base_damage *= _attribute_multiplier(target_def, weapon.damage_attribute)
			base_damage *= float(90 + roll(battle, 21)) / 100.0
			var critical_rate := clampi(weapon.base_critical_pct + floori(float(attacker.reaction - 100) / 10.0) + roundi(pilot_skill_modifier(battle, attacker, &"critical")), 0, 50)
			critical = roll(battle, 100) < critical_rate
			if critical: base_damage *= 1.5
			damage = roundi(base_damage)
			total += damage
		battle.combat_events.append({"type": &"shot", "source_unit_id": attacker.unit_instance_id, "target_unit_id": target.unit_instance_id, "weapon_id": weapon.id, "hit": hit, "critical": critical, "damage": damage})
	return total

static func _active_leader_command(battle: BattleRuntimeState, squad: BattleSquadState) -> int:
	if squad.leader_unit_id.is_empty(): return squad.leader_command
	var leader := battle.unit_states_by_id.get(squad.leader_unit_id) as BattleUnitState
	return squad.leader_command if leader != null and leader.current_hp > 0 else 100

static func _attribute_multiplier(unit_def: UnitDef, attribute: int) -> float:
	match attribute:
		GameEnums.DamageAttribute.BALLISTIC: return unit_def.ballistic_damage_multiplier
		GameEnums.DamageAttribute.BEAM: return unit_def.beam_damage_multiplier
		GameEnums.DamageAttribute.MELEE: return unit_def.melee_damage_multiplier
	return 1.0

## STRATEGY_DETAIL_SPECIFICATION.md section 5.6: sums every modifier of
## `key` (one of PILOT_MODIFIERS in master_data_validator.gd) across a
## pilot's currently-unlocked, condition-satisfied skills. Generic pilots
## (empty pilot_id) always contribute 0.
static func pilot_skill_modifier(battle: BattleRuntimeState, unit: BattleUnitState, key: StringName) -> float:
	if unit.pilot_id.is_empty():
		return 0.0
	var pilot_def := battle.pilot_defs.get(unit.pilot_id) as PilotDef
	if pilot_def == null:
		return 0.0
	var squad := battle.squad_states_by_id.get(unit.squad_id) as BattleSquadState
	var total := 0.0
	for skill_id: StringName in pilot_def.skill_ids:
		var skill := battle.pilot_skill_defs.get(skill_id) as PilotSkillDef
		if skill == null or unit.pilot_level < skill.unlock_level:
			continue
		if skill.leader_only and (squad == null or squad.leader_unit_id != unit.unit_instance_id):
			continue
		if not _pilot_skill_condition_met(battle, unit, skill):
			continue
		total += float(skill.modifiers.get(key, 0.0))
	return total

## PILOT_CONDITIONS in master_data_validator.gd: always, hp_pct, en_pct,
## environment. hp_pct/en_pct trigger at or below condition_value (a
## desperation-style threshold, matching the DEFENSIVE-policy 30% HP
## convention already used elsewhere in this file).
static func _pilot_skill_condition_met(battle: BattleRuntimeState, unit: BattleUnitState, skill: PilotSkillDef) -> bool:
	match skill.condition_type:
		&"always":
			return true
		&"hp_pct":
			return unit.max_hp > 0 and float(unit.current_hp) / float(unit.max_hp) <= skill.condition_value
		&"en_pct":
			return unit.max_en > 0 and float(unit.current_en) / float(unit.max_en) <= skill.condition_value
		&"environment":
			return int(skill.condition_value) == battle.environment
	return false

static func roll(battle: BattleRuntimeState, upper: int) -> int:
	battle.rng_state = int((battle.rng_state * 1664525 + 1013904223) & 0x7fffffff)
	return battle.rng_state % upper

static func _finalize_annihilation(battle: BattleRuntimeState) -> void:
	var attacker_alive := _side_alive(battle, battle.attacker_squad_ids)
	var defender_alive := _side_alive(battle, battle.defender_squad_ids)
	if attacker_alive == defender_alive: return
	if attacker_alive: battle.finalize(battle.attacker_faction_id, battle.defender_faction_id, &"annihilation")
	else: battle.finalize(battle.defender_faction_id, battle.attacker_faction_id, &"annihilation")

static func _side_alive(battle: BattleRuntimeState, squad_ids: Array[StringName]) -> bool:
	for squad_id: StringName in squad_ids:
		var squad := battle.squad_states_by_id[squad_id] as BattleSquadState
		for unit_id: StringName in squad.unit_instance_ids:
			if (battle.unit_states_by_id[unit_id] as BattleUnitState).current_hp > 0: return true
	return false
