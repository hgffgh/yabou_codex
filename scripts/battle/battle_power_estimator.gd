class_name BattlePowerEstimator
extends RefCounted

static func squad_power(battle: BattleRuntimeState, squad: BattleSquadState) -> float:
	var total := 0.0
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := battle.unit_states_by_id[unit_id] as BattleUnitState
		if unit.current_hp <= 0: continue
		var unit_def := battle.unit_defs.get(unit.unit_def_id) as UnitDef
		if unit_def == null: continue
		total += unit_def_base_power(unit_def, battle.weapon_defs, battle.support_skill_defs)
	return total


## STRATEGY_DETAIL_SPECIFICATION.md section 11.3's "機体基礎戦力": the same
## durability/attack/speed/support normalization squad_power uses in battle,
## but keyed off static UnitDef fields alone (no HP/current-state input), so
## it can also be summed across a faction's entire owned roster for the
## diplomacy proposal success-rate formula regardless of unit condition.
static func unit_def_base_power(unit_def: UnitDef, weapon_defs: Dictionary, support_skill_defs: Dictionary) -> float:
	var hp := _norm(unit_def.max_hp, 0.0, 6000.0)
	var armor := _norm(unit_def.armor, 0.0, 700.0)
	var evasion := _norm(unit_def.evasion, 0.0, 40.0)
	var durability := hp * 0.50 + armor * 0.30 + evasion * 0.20
	var weapon := weapon_defs.get(unit_def.weapon_ids[0]) as WeaponDef if not unit_def.weapon_ids.is_empty() else null
	var attack := _norm(unit_def.firepower, 0.0, 400.0) * 0.30
	if weapon != null: attack += _norm(weapon.total_power, 0.0, 1200.0) * 0.35 + float(weapon.base_accuracy_pct) * 0.20
	attack += _norm(unit_def.max_en, 0.0, 500.0) * 0.15
	var repair := 0.0
	var transfer := 0.0
	for skill_id: StringName in unit_def.support_skill_ids:
		var skill := support_skill_defs.get(skill_id) as SupportSkillDef
		if skill == null: continue
		repair = maxf(repair, float(skill.fixed_repair) + 3000.0 * skill.max_hp_repair_pct)
		transfer = maxf(transfer, float(skill.transfer_en))
	var support := _norm(repair, 0.0, 1000.0) * 0.40 + _norm(transfer, 0.0, 150.0) * 0.30 + _norm(unit_def.sensor_range_m, 0.0, 300.0) * 0.30
	var speed := _norm(unit_def.speed, 50.0, 200.0)
	return (durability * 0.30 + attack * 0.30 + speed * 0.20 + support * 0.20) * unit_def.power_adjustment


## STRATEGY_DETAIL_SPECIFICATION.md section 11.3: "勢力総戦力" sums every
## owned unit's base power, ignoring HP/EN/repair/destroyed-and-recovered
## state, pilots, territory, income, facilities, and tech count.
static func faction_total_power(
	faction_id: StringName, campaign_runtime: CampaignRuntimeState, master_data: MasterDataRegistry,
) -> float:
	var total := 0.0
	for unit: UnitInstanceState in campaign_runtime.units_by_id.values():
		if unit == null or unit.owner_faction_id != faction_id:
			continue
		var unit_def := master_data.units.get(unit.unit_def_id) as UnitDef
		if unit_def == null:
			continue
		total += unit_def_base_power(unit_def, master_data.weapons, master_data.support_skills)
	return total

static func rating(player_power: float, enemy_power: float) -> String:
	if enemy_power <= 0.0: return "圧倒的有利"
	var ratio := player_power / enemy_power
	if ratio >= 1.50: return "圧倒的有利"
	if ratio >= 1.15: return "有利"
	if ratio >= 0.87: return "互角"
	if ratio >= 0.67: return "不利"
	return "圧倒的不利"

static func _norm(value: float, minimum: float, maximum: float) -> float:
	return clampf((value - minimum) / (maximum - minimum) * 100.0, 0.0, 100.0)
