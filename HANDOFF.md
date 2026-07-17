# Development handoff

## Current status

The repository contains a functioning but simplified Godot strategy prototype
alongside specification-driven master data and mutable campaign state.
Production now uses the new model; strategic movement and combat still use the
prototype stack path so that migration remains incremental.

The latest specification milestone is complete:

- High-level game specification
- Real-time battle specification
- Turn-based strategy specification
- Unit and weapon numeric specification
- Event and narrative specification
- Save, difficulty, AI, input, and UI specification
- Godot-oriented data definition document

The first data-foundation milestone is complete:

- Shared enums and constants
- `WeaponDef`, `UnitDef`, `PilotDef`, `PilotSkillDef`, and `SupportSkillDef`
- A deterministic, typed master-data registry
- Development-build startup validation
- A minimal cross-referenced unit, weapon, support, pilot, and technology dataset

The individual unit and squad runtime-state milestone is complete:

- `UnitInstanceState` with individual HP, EN, pilot, squad, slot, repair,
  movement, and capture state
- `SquadState` with three front and two rear slots
- ID-only dictionary serialization and JSON round-trip coverage
- Cross-state validation for master references, ownership, slots, leaders,
  named-pilot uniqueness, HP/EN, repair state, and regions
- Explicit `slot_index == -1` representation for unassigned units

The campaign runtime owner and rollout boundary are also complete:

- Deterministic `unit_%08d` and `squad_%08d` IDs independent of campaign RNG
- Saved monotonic counters that never reuse deleted IDs
- Stable ID-sorted serialization and JSON restoration
- Atomic rollout of a full-HP/full-EN generic-piloted unit in front slot 0
- `GameState.campaign_runtime` ownership and reset on new game

The production migration is complete:

- Separate funds and materials for production and regional income
- Typed facility definitions and fixed facility instances
- Facility-specific FIFO queues and deterministic production-job IDs
- Size-based prepaid funds, materials, and required production values
- Same-turn overflow into the next queued job with no cross-turn power storage
- Player and AI production selection using new `UnitDef` IDs
- Atomic completion rollout without persistent writes to legacy `UnitStack`
- Queue/progress loss without refunds when a facility region changes owner

The battle-result and combat-routing correctness pass is complete:

- Confirmed the legacy `UnitStack`/`CombatResolver`/`BattleVignette` prototype
  path was fully superseded and unreachable, then deleted it along with
  `Region.stacks`, `GameState.unit_defs`, and `res://data/legacy_units/`
- A region with two or more hostile defending factions now resolves as a
  sequence of pairwise battles (attacker vs. each defender in faction-ID
  order, re-deriving live squads between fights) instead of being detected
  every turn and silently skipped forever
- `GameState.apply_battle_result` now resolves every destroyed unit's fate:
  the winner's own losses become unassigned `DESTROYED_RECOVERED` records,
  a 10%-probability roll per capturable loser loss (via the battle's own
  deterministic RNG stream) captures it into a fresh one-unit squad for the
  winner (generic-piloted, 1 HP, placed in the battle region), and the
  remainder are fully removed from the campaign
- The "battle" combat-log entry is restored on `TurnManager` so
  `Diplomacy.apply_combat_events` actually applies its attack-relation
  penalty again, and the dead unreachable code block in
  `complete_battle_runtime` (`_strongest_faction`/`_auto_capture`/
  `_resolve_combat`) and the vignette-only signal wiring were removed

The pilot progression milestone is complete:

- `PilotState` (level, current EXP, injury countdown, unit assignment) is
  seeded at `PilotDef.initial_level` for every roster pilot at new-game time
  and auto-claims a still-generic-piloted unit for its faction, matching
  `_seed_initial_squads`' transitional loadout pattern
- `CampaignRuntimeState.assign_pilot_to_unit`/`unassign_pilot` implement the
  displacement rules from STRATEGY_DETAIL_SPECIFICATION.md section 5:
  placing a named pilot silently swaps out whichever pilot (generic or
  named) already crews both the source and destination unit; injured
  pilots cannot be (re)assigned
- Battle units now use each pilot's *current*, growth-adjusted stats
  (`initial_* + growth_* * (level - 1)`, capped at 200) instead of always
  their level-1 baseline
- EXP is earned exactly per section 5.3's table (round participation 50,
  enemy destroyed 50 split across every contributing attacker, support
  success 20 only when HP/EN actually increased, battle victory 50 or HQ
  capture 100 for every unit on the winning roster) and applied with
  `ceil()` and bracket-based leveling up to the level-50 cap once the
  battle resolves
- Any destroyed unit's named pilot is injured for three turns and
  unassigned regardless of which side won (COMBAT_DETAIL_SPECIFICATION.md
  section 18), decremented once per that faction's own turn via
  `GameState.advance_pilot_injuries_for_faction`
- Fixed two related capture bugs found while implementing this: the capture
  roll is now a genuine 10%-probability roll (it was a deterministic
  fractional-carry accumulator that always captured exactly 1-in-10) and
  `UnitDef.capture_allowed == false` units are now correctly always lost
  rather than being subject to a roll at all

The in-battle fog-of-war milestone (COMBAT_DETAIL_SPECIFICATION.md section
24) is complete, scoped to the battle overlay only -- see the explicit
deferrals below:

- `BattleSquadState` gains `intel_confirmed` (sticky for the rest of the
  battle), `currently_sensed` (recomputed every tick), `last_known_world_position`,
  and `revealed_until_world_sec`. `BattleRuntimeState._advance_intel_sensing`
  (called every `advance_time` tick) also finally wires up the
  long-declared-but-dead `BattleSquadState.sensor_range_m` field, recomputing
  it each tick as the max `UnitDef.sensor_range_m` among that squad's living
  units
- `intel_confirmed` (composition/HP/EN become visible) is set by either
  engaging in combat or coming within an enemy squad's sensor range;
  `currently_sensed` (whether the *live* position or the frozen
  last-known one is shown) is governed only by actual sensor coverage or
  an active reveal window -- combat contact alone does not grant continuous
  position tracking, which is what keeps the firing-disclosure rule below
  meaningful rather than redundant
- Firing a weapon while not `currently_sensed` opens a 5-battle-second
  reveal window (`BattleCombatSystem`), matching the spec's "attacking from
  outside sensor range discloses current position for 5 seconds" rule
- `BattlePrototypeView` hides an unconfirmed enemy squad's icon and HP/EN
  bars entirely, renders a confirmed-but-out-of-range squad frozen at its
  last known position, and the pre-battle confirmation panel now shows
  "未確認" instead of exact HP/EN for any enemy squad not yet confirmed

Explicitly deferred (kept out of this pass to avoid building unconsumed
scaffolding):

- No persistent, cross-battle `IntelRecordState` (DATA_DEFINITION.md
  section 21) -- confirmation is battle-scoped only and resets next battle.
- No strategic-map fog of war -- region badges still show full enemy
  composition unconditionally; the detail specs only fully specify fog
  rules for the battle view, not a strategic-map sensor model.
- No intel-purchase feature (STRATEGY_DETAIL_SPECIFICATION.md section 11.7)
  and no encyclopedia registration on first contact.
- The pre-battle power estimate still computes from each unit's real
  stats, not the category/faction/era averages the spec calls for when a
  squad is unconfirmed -- the existing five-band rating already hides exact
  numbers, which covers most of the intent.

The pilot skills milestone (STRATEGY_DETAIL_SPECIFICATION.md section 5.6) is
complete for passive combat modifiers:

- `BattleCombatSystem.pilot_skill_modifier(battle, unit, key)` sums a
  pilot's `modifiers[key]` across every skill in `PilotDef.skill_ids` that
  is currently unlocked (`BattleUnitState.pilot_level >= unlock_level`),
  passes its `leader_only` gate, and satisfies its `condition_type`
  (`always`, `hp_pct`/`en_pct` at-or-below `condition_value`, or
  `environment` matching the battle's own environment) -- exactly the
  `PILOT_CONDITIONS`/`PILOT_MODIFIERS` sets `master_data_validator.gd` was
  already validating against with no consumer. Applied to accuracy,
  evasion, firepower, armor, and critical rate in `_resolve_attack`.
- `BattleRuntimeState.environment` (new field, from `BattleMapDef.environment`)
  and `BattleUnitState.pilot_level` (snapshotted at battle creation from
  `PilotState.level`) back the `environment`/unlock-level checks.
- `res://data/pilot_skills/` was empty, so this pass also authored the
  first sample data: two skills each for `aria_nova` and `darius_crimson`
  (one Lv1 always-on, one Lv10 conditional/leader-only), covering all four
  condition types and all five modifier keys between the sample data and
  `pilot_skills_test.gd`'s synthetic-pilot cases.
- Deferred: `PilotSkillDef.action_skill_id` (granting an additional active
  support skill beyond `UnitDef.support_skill_ids`) is validated but not
  read anywhere -- none of the sample skills use it, and it is a distinct
  mechanic from the passive-modifier system implemented here.

The strategic-layer persistent intel milestone (DATA_DEFINITION.md section 21
/ COMBAT_DETAIL_SPECIFICATION.md section 24 / STRATEGY_DETAIL_SPECIFICATION.md
section 6) is complete, closing the "no persistent, cross-battle intel"
deferral from the in-battle fog-of-war milestone above:

- New `IntelRecordState` (trimmed to the strategic layer: observer, target
  squad, `IntelState`, the `target_revision` snapshot used for staleness,
  and `last_seen_turn`) lives in `CampaignRuntimeState.intel_records_by_key`,
  is saved/loaded/validated alongside pilots and units, and persists across
  turns and battles rather than resetting each fight like the battle-view
  fog state does.
- Two confirmation triggers: `GameState._confirm_battle_participant_intel`
  (both sides of a resolved battle confirm each other, called from
  `apply_battle_result`) and `GameState.refresh_intel_from_colocation`
  (a faction's own squad sharing a region with a hostile one counts as
  "sufficient sensor detection" at strategic, discrete-region granularity
  -- there is no continuous sensor-range model at this layer). The latter
  runs both at each faction's turn start and right after its movement
  phase, so a squad that just moved into contact is confirmed before that
  turn's combat phase resolves.
- `CampaignRuntimeState.is_squad_confirmed` treats a stored record as stale
  (and therefore unconfirmed again) once the target squad's `intel_revision`
  no longer matches what was recorded -- a composition change silently
  invalidates old intel rather than needing an explicit revert step.
- `RegionNodeView.update_squad_badge()` now excludes unconfirmed hostile
  squads from the composition/count it renders and shows a distinct "?"
  badge instead, rather than always revealing every squad's exact makeup
  on the strategic map regardless of faction.
- Still deferred: the intel-purchase feature (STRATEGY_DETAIL_SPECIFICATION.md
  section 11.7) and encyclopedia registration. The `IntelRecordState`/
  `confirm_squad_intel` machinery built here makes purchase straightforward
  to add later (call `confirm_squad_intel` for a third party's squads,
  gated by cost and a cooldown), but the UI hook and cooldown tracking
  aren't built yet.
- A `region_node_view.gd` UI-level test was attempted but dropped: directly
  instantiating `RegionNodeView` as the first thing a `--script` test entry
  point compiles hits a headless-only GDScript compile-order failure
  ("Identifier not found: GameState") that reproduces on *any* bare
  `GameState.` reference in that file, including lines that predate this
  change and already work fine through the normal autoload-boot path (e.g.
  `strategic_map_smoke_test.gd`, which builds real `RegionNodeView`
  instances through the full scene, passes). The badge-gating logic is
  covered by `strategic_intel_test.gd`'s `CampaignRuntimeState`-level
  checks and by code review instead.

The AI-vs-AI battle auto-resolution milestone is complete:

- `TurnManager._resolve_squad_battle` now branches on
  `_battle_involves_player` (attacker or defender faction id matches
  `GameState.player_faction_id`). Player-involved battles keep the
  existing `battle_runtime_ready` / `BattlePrototypeView` flow unchanged;
  a battle between two non-player factions is never emitted for the UI at
  all (`strategic_map.gd`'s `_on_battle_runtime_ready` would otherwise pop
  a view for *every* emitted battle unconditionally) and instead runs
  through `_auto_resolve_battle`.
- `_auto_resolve_battle` drives the same deterministic
  `BattleRuntimeState.advance_time`/`BattleCombatSystem` simulation the
  interactive view uses, synchronously, in whole-second steps up to the
  300-second world-time cap, then calls the existing
  `complete_battle_runtime` (so campaign application, the diplomacy log
  entry, and pending-battle bookkeeping all go through the identical path
  either way). Whole-second steps (rather than one call covering the full
  300 seconds) matter because a few things — the firing-disclosure reveal
  window in particular — read `elapsed_world_sec` mid-battle, and
  `advance_time` clamps that field to the cap *before* simulating, so one
  giant call would leave it pinned at 300 for the whole run instead of
  advancing incrementally.
- This also resolves the sequential multi-faction pairwise battles from
  the earlier combat-routing milestone the same way: each sub-battle
  independently checks player involvement, so a player fighting faction A
  while factions B and C also clash in the same region no longer forces
  the player to click through every unrelated fight.
- Every combat contact still resolves before the faction turn advances
  (no behavior change there) — what changed is *who* has to watch it
  happen.

The battle squad movement/AI milestone is complete, scoped to what's
tractable through code alone -- see the explicit deferrals below:

- Destination-seeking squad movement moved from `BattlePrototypeView._process`
  into `BattleRuntimeState._advance_squad_movement` (called from
  `advance_time`), with `_squad_speed` (unit speed / 10 m/s, slowest
  surviving unit) also relocated so it no longer needs a live `GameState`
  lookup. This was a real, previously-undiscovered gap in the AI
  auto-resolve milestone above: since movement only ever ran inside the
  interactive view's per-frame `_process`, an auto-resolved (headless)
  battle never moved a single squad, and could only ever produce a fight
  if a map's spawn points happened to already be in weapon range of each
  other.
- New `BattleRuntimeState._advance_ai_squad_orders` (also called from
  `advance_time`) closes "defending squads never move, retreat, or defend
  on their own": any squad whose faction isn't the new
  `player_faction_id` snapshot (set by `battle_runtime_factory.gd` from
  `GameState.player_faction_id` at creation, so the simulation itself
  never needs a live autoload dependency) picks its own destination every
  tick. OFFENSIVE/BALANCED squads press toward the nearest living enemy
  squad; DEFENSIVE/SUPPORT/RETREAT squads hold near their own HQ instead
  of charging out (they still fight normally if approached -- engagement
  triggers on weapon-range contact independent of this). RETREAT-policy
  squads also auto-`request_retreat()` once squad HP drops to 30% or
  below, per STRATEGY_DETAIL_SPECIFICATION.md's policy table, regardless
  of who controls the squad (policy selection is the trigger, not manual
  play).
- New `BattleSquadState.movement_ai_disabled` opt-out flag, for
  fixtures/tests that need a non-player squad to hold an exact manually-
  assigned position (`battle_capture_system_test.gd`'s HQ-capture-timing
  fixture needed this once its defender started rushing back to protect
  its own, here deliberately undefended, HQ -- correct new behavior, but
  incompatible with that test's old "frozen prop" assumption).
- Found and fixed a related bug while chasing a test regression from this
  change: several fixtures set a squad's `world_position` directly without
  also updating `destination`, which used to be harmless (movement never
  ran headless) but now caused the squad to visibly drift back toward its
  stale spawn-point destination once movement started running everywhere.
  `battle_capture_system_test.gd` now sets both together.
- Explicitly deferred: `TerrainZoneDef`/`TerrainEffect` (no resource class
  exists, and there is no scene geometry to attach zones to yet); true
  NavigationRegion3D pathfinding/obstacle avoidance (needs an editor-baked
  navmesh, not practical to add through text-based tools); and
  COMBAT_DETAIL_SPECIFICATION.md section 26's in-round approach/withdrawal
  mechanic, which operates on an abstract per-engagement distance
  explicitly decoupled from `world_position` ("ラウンド内の距離変化は
  戦場マップ上の実位置へ反映しない") and can shift which weapons stay in
  range mid-round -- a distinct, intricate mechanic from the pre-contact
  positioning implemented here, deserving its own pass.

The save/load milestone is complete for manual saves, scoped to what the
current (legacy, simplified) `CampaignConfig` and data model can actually
support -- see the explicit deferrals below:

- `GameState.to_save_dict()`/`apply_save_dict(data)` cover turn_number,
  player_faction_id, is_game_over, per-faction state (funds/materials/
  resources/eliminated/tech_tier/research progress/relations), per-region
  `owner_faction_id`, and `campaign_runtime` nested via its existing
  `to_dict()`/`from_dict()` (units/squads/pilots/production/intel all come
  along for free). `TurnManager.to_save_dict()`/`apply_save_dict(data)`
  cover `faction_turn_order`/`active_faction_index`; `current_phase`/
  `is_resolving_turn` are not saved at all, since a manual save is only
  ever possible during the player's own `Phase.ORDERS` in the first place
  (`TurnManager.can_save_now()`) -- that state is implied and restored
  directly rather than persisted.
- Both `apply_save_dict` methods validate everything into temporary
  structures first (including running `CampaignRuntimeState.validate()`
  against the currently-loaded master data) and only commit to live state
  if the whole save parses cleanly -- a bad or stale save file can never
  leave a half-applied campaign behind. `GameState`'s half is always
  applied before `TurnManager`'s, since the latter validates
  `faction_turn_order` entries against `GameState.factions`.
- `TurnManager.save_game(slot)`/`load_game(slot)`/`list_save_slots()`
  read/write JSON to `user://saves/slot_NN.json`. A `SaveLoadPanel`
  (matching `DevelopmentPanel`'s overlay style), reachable from a new
  "セーブ/ロード" button on the strategic map's top bar, lists ten fixed
  slots with turn/faction/timestamp and per-slot save/load actions, save
  disabled outside `Phase.ORDERS`.
- Explicitly deferred: autosave triggering and the manual/auto slot-count
  split (the full `CampaignConfig` schema's `manual_save_slots`/
  `autosave_slots` fields don't exist on the current simplified
  `resources/campaign_config.gd`, so this pass just supports ten
  fixed manual slots with no autosave tier); `difficulty_id` (no
  `DifficultyDef`/difficulty system exists at all yet); and `rng_state`
  (there is no persistent campaign-level RNG to save -- only each
  battle's own transient, battle-scoped RNG state, which is explicitly
  out of scope for a manual save since battles never save mid-fight).

## Source of truth

Read these documents in this order:

1. `GAME_SPECIFICATION.md`
2. `DATA_DEFINITION.md`
3. The subsystem detail specification relevant to the task

The specifications are newer than the current gameplay code. Existing code is
useful as a prototype and UI reference, but its simplified rules are not the
final design.

## Important confirmed decisions

- PC, single-player, original robot science-fiction setting.
- Three selectable factions fighting across Earth, the Moon, and colonies.
- One campaign week consists of the player faction, AI faction A, and AI
  faction B acting in a fixed order.
- Standard clear target is about 50 weeks; the hard deadline is 100 weeks.
- The strategic phase uses connected regions and one-region movement per squad.
- Battles occur in a separate combat phase after strategic movement is locked.
- A squad contains at most five units in three front and two rear slots.
- Units are individual runtime objects with HP, EN, pilot, and squad membership.
- Unassigned machines automatically use a generic pilot with all abilities 100.
- Named pilots have levels, fixed growth, five skills, and three-turn injuries.
- Battle maps use free movement, fog of war, headquarters capture, common
  auxiliary bases, and five-minute battle limits.
- Contact resolves through 30-second speed-gauge combat rounds.
- Weapons are fixed to unit types; players do not edit loadouts or priorities.
- The technology tree contains about 30 nodes over five tiers and is randomized
  per campaign using permanently unlocked candidates.
- Funds and materials are separate strategic resources.
- Difficulty changes AI, enemy economy, and enemy combat bonuses and is fixed at
  campaign start.
- Manual saves are available only during the strategic phase.

## Current implementation versus target design

| Current prototype | Required target |
| --- | --- |
| One generic `resources` currency | Production and research both use funds/materials; `Faction.resources` is now a fully unused legacy field |
| — (removed; `UnitStack`/`CombatResolver` deleted as unreachable) | Production, movement, and combat all use `UnitInstanceState`/`SquadState`/`BattleRuntimeState` |
| No five-unit squad slots | `SquadState` is implemented with 3 front and 2 rear slots and is fully wired into movement, production, and combat |
| Unit type has attack/defense only | New unit, weapon, aptitude, resistance, and support Resources now coexist with the prototype |
| — (implemented; see below) | Generated five-tier technology-node graph per faction, replacing the old flat `Faction.tech_tier` |
| Parallel per-unit production timers | Replaced by facility FIFO production-power queues |
| Ratio-based instant combat | Free-movement RTS plus 30-second combat rounds |
| One combined turn loop | Fixed faction turns with strategy and combat phases |
| Region has one resource yield | Region funds/materials income plus fixed facilities |

Relevant prototype files:

- `resources/faction_def.gd`
- `resources/region_def.gd`
- `resources/tech_def.gd`
- `resources/campaign_config.gd`
- `autoload/game_state.gd`
- `autoload/turn_manager.gd`

## Recommended next task

The legacy `UnitStack`/`CombatResolver`/`BattleVignette` prototype path is
gone, battle-result application (destroyed/recovered/captured/lost,
diplomacy penalties) is complete, named pilots now level up, earn EXP, get
injured, and apply passive skill modifiers per spec, the battle view respects
sensor-based fog of war with that confirmation also persisting at the
strategic layer, AI-vs-AI battles auto-resolve without blocking on the
player, non-player squads now move, press the attack, hold defensively, and
auto-retreat on their own inside a battle, manual save/load works end to
end, and diplomacy (STRATEGY_DETAIL_SPECIFICATION.md section 11) now has a
real runtime: `RelationState` (friendship, treaty type/countdown, and the
proposal/gift/intel-purchase cooldowns and violation penalty) replaces the
old `Faction.relations` float score, stored in
`CampaignRuntimeState.relation_states` keyed by an unordered faction-pair —
one instance per pair, not the per-`FactionState`-dict shape DATA_DEFINITION.md
section 6.2 sketches, since that would require manually keeping two
independent copies in sync on every update; this codebase already
centralizes all other campaign-wide collections (units, squads, pilots,
intel) the same way. `scripts/factions/diplomacy.gd` implements the full
11.3 success-rate formula (friendship, relative faction power via a new
`BattlePowerEstimator.faction_total_power`, treaty-length penalty, and a
gift-offer bonus sized against `GameState.estimate_faction_income`),
ceasefire/non-aggression proposals with a real deterministic roll
(`GameState.campaign_rng`, persisted across save/load), treaty
formation/expiry/notification, mutual invasion-blocking while a treaty is
active (`GameState.plan_squad_movement`), unilateral treaty-breaking with
its friendship and success-rate penalties, resource gifting, intel purchase
building on the existing `IntelRecordState` machinery, and captured-unit
ransom. A `DiplomacyPanel` (mirroring `SaveLoadPanel`'s style) exposes
proposals, treaty-breaking, and gifting from the strategic map; intel
purchase and ransom are backend-only for now (see the numbered list below).
Every `Diplomacy` function takes `game_state` as an explicit first
parameter instead of reading the `GameState` autoload by its bare
identifier — see the "Validation and setup" section's note on the headless
compile-order bug below, since a test exercising `Diplomacy` directly would
otherwise be the exact trigger case.

Terrain zones (COMBAT_DETAIL_SPECIFICATION.md section 29) are implemented:
a new `TerrainZoneDef` (`res://data/terrain_zones/`) models a zone as a
plain circle — `position` (real ground-plane x/z) plus `radius_m` — rather
than the spec's `area_node_path`-driven `Area3D` shape, since there is no
battle-map scene geometry to attach a real `Area3D` to and
`BattleControlPointDef` already proves plain distance checks are how "a
region of the battlefield" works in this codebase (capture/sensor radius,
no physics queries). `standard_battle_map.tres` now references four zones
(`standard_cover_ridge`, `standard_difficult_marsh`, `standard_hazard_field`,
`standard_impassable_wreckage`) exercising all four effects: difficult
terrain's 0.8x move-speed multiplier (`BattleRuntimeState._squad_speed`,
which while in there also finally wired up
`GameConstants.APTITUDE_MOVE_MULTIPLIERS` — declared from the start but
never read by anything before now), cover's +15 evasion bonus against
non-melee attacks (`BattleCombatSystem._cover_evasion_bonus`), hazardous
terrain's 1%-max-HP-per-second drain floored at 1 HP that skips both pause
and auto-resolved battles (`BattleRuntimeState._advance_terrain_hazard` /
`is_auto_resolving`), and impassable zones rejecting a destination order
placed inside one (`BattleRuntimeState.is_position_passable`, checked in
`BattlePrototypeView._on_arena_input`). `blocks_sensor_los` (DATA_DEFINITION.md
19.2) also blocks sensor detection along a line of sight that crosses such
a zone, via a segment-vs-circle test in `_advance_intel_sensing`. Zones get
a flat, unlit disc marker in the interactive battle view. Explicitly *not*
implemented: true `NavigationRegion3D`/`NavigationServer3D` pathfinding —
this battle simulation is a plain `RefCounted` advancing `Vector3`
positions directly with no scene tree or physics server involved at all
(deliberately, since auto-resolved battles run to completion with no
`Node3D` ever instantiated), so real engine navmesh pathfinding isn't just
hard to author through text tools, it's architecturally the wrong tool
here; a squad may still cross through an impassable zone while in transit
toward a valid destination, since only the destination itself is validated,
not the path to it.

`PilotSkillDef.action_skill_id` (DATA_DEFINITION.md section 13) is wired up:
`BattleCombatSystem._active_pilot_skills` now centralizes the unlock_level/
leader_only/condition_type gating that `pilot_skill_modifier` used to do
alone, and a new `pilot_action_skill_ids` reads the same gated skill list
for any granted `action_skill_id`s, which `_prepare_support` folds into a
unit's normal support-skill candidate pool (sorted by priority exactly like
`UnitDef.support_skill_ids`). `aria_last_stand` (unlocks at Lv10, active at
≤30% HP) now grants `field_repair`, demonstrated against `nova_scout`,
whose `UnitDef.support_skill_ids` is empty, so any repair capability
observed in the test can only have come from the pilot grant. A new
`PilotAssignmentPanel` (mirroring the other panels' style) exposes
`CampaignRuntimeState.assign_pilot_to_unit`/`unassign_pilot` — previously
tested backend logic invoked only by `GameState`'s transitional
deterministic seeding — from the strategic map: each of the player's
pilots gets a row showing level/EXP/injury status and current assignment,
an `OptionButton` listing every eligible active unit (labeled with its
current occupant, since assigning silently displaces whoever's aboard),
and 搭乗/解除 buttons. Fixed a real bug caught while smoke-testing it, also
present in `DiplomacyPanel` since it was copied from there: every panel's
action handlers set `_status_label.text` to a result message and *then*
called `_refresh()`, but `_refresh()` itself unconditionally overwrites
`_status_label.text` (to `""` or the phase-gating hint) as its first
step — so the result message never actually reached the player, silently
clobbered every time. Fixed in both panels by calling `_refresh()` first
and setting the result message after.

COMBAT_DETAIL_SPECIFICATION.md section 26's in-round abstract distance is
implemented: `BattleEngagementState.engagement_distance_m` is a per-
engagement value seeded from the real distance between the two squads'
`world_position` the instant weapon contact forms
(`BattleRuntimeState._start_available_engagements`), then shifted every
simulation tick by `_advance_engagement_distance` per both squads'
`BattlePolicy` — OFFENSIVE/BALANCED commit their squad's battlefield speed
(100%/50%) entirely to closing the distance, DEFENSIVE/SUPPORT/RETREAT
commit theirs (25%/50%/100%) entirely to opening it, matching the spec's
table exactly, clamped at a 0 minimum. `BattleCombatSystem._select_target`
now checks a weapon's range against this abstract distance via the new
`BattleRuntimeState.engagement_distance_m(squad_id)` instead of the real
`world_position` distance it used to read — the real position stays frozen
for the whole battle while any engagement exists (unchanged, pre-existing
behavior), so this is the only thing that actually changes: which weapons
stay usable can now shift mid-round independent of the battle map, exactly
as the spec intends, and the next round's initial distance is always
recomputed fresh from the real position once the current one ends. This
surfaced a real, spec-correct behavior change that broke an existing test's
assumption: `fog_of_war_test.gd`'s reveal-window case had both squads
default to BALANCED, which mutually closes distance fast enough that
crimson_bastion's slow action-gauge fill let the range collapse below its
siege_cannon's 60m minimum before it ever got to fire at all; fixed by
giving both squads DEFENSIVE for that test instead (mutual withdrawal, with
comfortable margin under the weapon's 300m max for the test's duration) —
not a bug, just this mechanic's first real interaction with an existing
fixture.

Difficulty (DATA_DEFINITION.md section 5) and environment-aptitude accuracy/
evasion (UNIT_DETAIL_SPECIFICATION.md section 6) are both implemented.
A new `DifficultyDef` (`res://data/difficulties/`: `easy`/`normal`/`hard`)
scales non-player factions only — `enemy_income_multiplier` in
`TurnManager._run_income_phase`, `enemy_hp_multiplier` applied once when
`BattleRuntimeFactory._build_side` snapshots a non-player unit's max/current
HP, and `enemy_firepower_multiplier`/`enemy_accuracy_add`/`enemy_evasion_add`
read live in `BattleCombatSystem._resolve_attack` via new accessors on
`BattleRuntimeState` (`hp_multiplier`/`firepower_multiplier`/`accuracy_add`/
`evasion_add`, all keyed off `is_enemy_faction`). `GameState.start_new_game`/
`TurnManager.start_new_game` both take an optional `difficulty_id` (default
`"normal"`, so none of the ~30 existing call sites needed touching),
falling back to Normal for an unresolved id; `difficulty_id` round-trips
through save/load and a picker was added to the faction-select screen.
`ai_profile_id` is schema-only — there's no AI behavior-profile system to
select between yet, just the single non-parameterized `AiController`.
Environment aptitude's accuracy/evasion bonuses (previously unwired, same
gap the terrain-zone milestone left for its move-speed counterpart) are now
read the same way: `BattleRuntimeState.environment_aptitude_accuracy_add`/
`environment_aptitude_evasion_add`, folded into the same accuracy formula
right alongside the difficulty additions.

The achievement/profile and autosave milestone (DATA_DEFINITION.md sections
9/9.1, SYSTEM_DETAIL_SPECIFICATION.md section 2.1) is complete, scoped down
to what the current data model actually needs — see the explicit deferrals
below:

- New `AchievementDef` (`res://data/achievements/`, 7 sample entries) and
  `ProfileState` (`res://scripts/state/profile_state.gd`), trimmed to just
  `achievement_ids`/`permanent_exp_bonus_pct` — `ProfileState`'s other
  DATA_DEFINITION.md fields (encyclopedia entries, unlocked tech candidates,
  viewed events, settings) all need systems that don't exist yet or are
  unrelated UI settings, so they were left out rather than stubbed.
  `GameState.profile` persists to `user://profile.json` (separate from any
  campaign save — it survives across campaigns, matching the spec), loaded
  once at `_ready()`.
- `GameState.evaluate_achievements()` runs `_achievement_condition_met`
  against every `AchievementDef` and is called from `TurnManager._end_game`
  whenever the new `GameState.did_player_win()` (uniform across the
  capital-capture/region-threshold/turn-cap game-over reasons) is true. Five
  `condition_type`s are supported: `faction_clear`, `difficulty_clear`,
  `turn_limit_clear`, `capture_count` (new `Faction.total_units_captured`),
  and `treaty_count` (derived by scanning `campaign_runtime.diplomacy_log`
  for the player's successful treaty proposals — no new counter needed).
  `ProfileState.recalculate_bonus` always recomputes the permanent EXP bonus
  from `achievement_ids` rather than trusting a stored value, and
  `GameState._apply_battle_pilot_exp` now reads it for the player's own
  pilots only (never AI pilots), replacing the old hardcoded `0.0`
  placeholder. `ResultsScreen` shows any achievements unlocked that game.
- Autosave: `TurnManager` now writes to one of 3 rotating
  `user://saves/autosave_NN.json` slots (oldest-or-empty replaced) at the
  start of each faction's turn and again right before combat resolution,
  matching SYSTEM_DETAIL_SPECIFICATION.md section 2.1's two triggers
  exactly. It's best-effort and bypasses `can_save_now()` — that gate exists
  specifically to stop player save-scumming during their own orders phase,
  not because other phases are unsafe to serialize. `save_game`/`load_game`/
  `list_save_slots`/`_read_save_summary` all gained an `auto: bool = false`
  parameter routing between the manual and autosave slot namespaces.
  `SaveLoadPanel` gained a load-only autosave section.
- Found and fixed a real test-isolation bug while building this: several
  `achievements_profile_test.gd` cases called `evaluate_achievements()`,
  which persists to the real `user://profile.json` — since that file
  survives across separate `--script` process invocations (unlike in-memory
  state), it leaked into a *later*, unrelated `pilot_progression_test.gd`
  run in the same full-suite sweep and inflated its EXP assertions. Fixed by
  snapshotting/restoring the real profile file around the whole test file's
  execution in `_initialize()`.
- Deferred: the full `CampaignConfig.manual_save_slots`/`autosave_slots`
  schema split from DATA_DEFINITION.md — the slot *count* (3) is hardcoded
  as `TurnManager.AUTOSAVE_SLOT_COUNT` rather than read from config, since
  `resources/campaign_config.gd` doesn't model that schema yet.

The real generated tech-node/research system (DATA_DEFINITION.md sections
15/15.1/15.2, STRATEGY_DETAIL_SPECIFICATION.md section 7) is complete,
replacing both the old flat `Faction.tech_tier` placeholder and the earlier
simplified `Diplomacy.gift_tech` in one pass (a half-migrated system would
leave two parallel and inconsistent tech representations, so this was done
as a single cutover across data/state/UI/AI rather than staged):

- `TechDef` was rewritten to match DATA_DEFINITION.md section 15 exactly
  (origin faction, tier, category, `mandatory_base_tech`, `giftable`, plus
  schema-only `unlocks_unit_ids`/`unlocks_skill_ids`/`capture_unlockable`/
  `encyclopedia_unlockable` for systems that don't gate on them yet). New
  `GeneratedTechNodeState` (node_id, tech_id, tier, prerequisites, gifted,
  researched) and `ResearchState` (node_id, funds_paid, turns_remaining)
  back `Faction.generated_tech_nodes`/`current_research`, replacing the
  removed `tech_tier`/`research_in_progress`/`research_turns_remaining`.
- New `TechTreeGenerator.generate_for_faction` builds each faction's 5-tier
  tree at `start_new_game` time, seeded from the same persisted
  `GameState.campaign_rng` diplomacy already uses: every faction's
  `mandatory_base_tech` techs are always placed at their tier, and the rest
  of each tier is filled by a deterministic Fisher-Yates draw (`Array.
  shuffle()` doesn't take a custom RNG) from the full non-mandatory tech
  pool, with 1-2 prerequisite links drawn from the tier below.
  `TARGET_NODES_PER_TIER = 3` (scaled down from the spec's "~6" to match the
  smaller sample dataset actually authored — 10 `TechDef`s total). Explicit
  scope tradeoff: DATA_DEFINITION.md's permanently-unlocked-candidate pool
  (a campaign-spanning set grown by an encyclopedia/capture-analysis system
  that doesn't exist yet) isn't modeled — every non-mandatory tech is always
  eligible for any faction's draw.
- `TurnManager.start_research(faction_id, node_id) -> PackedStringArray`
  (previously `start_research(faction_id) -> bool`) validates the node
  exists, is unresearched, and has its prerequisites met, then deducts cost
  from `faction.funds` — this also fixed a real currency bug: the old
  implementation deducted from the legacy `faction.resources` even though
  STRATEGY_DETAIL_SPECIFICATION.md section 7.3 specifies funds. A gifted
  node uses a different prerequisite rule than a naturally-drawn one (any
  researched node one tier down, not a specific `prerequisite_node_ids`
  link) via `_node_prerequisites_met`. `_research_discount_pct` (5% per
  owned RESEARCH-type facility, capped 25%) wires up the previously-dormant
  `FacilityDef.research_discount_pct` field — currently always 0% since no
  RESEARCH facility instance exists in the map data yet, but the formula
  itself is real and correct once one is added. `_advance_research` and the
  `research_completed(faction_id, tech_id)` signal (signature changed from
  `(faction_id, new_tier: int)`) were updated to match.
- `Diplomacy.gift_tech(game_state, giver_id, receiver_id, giver_node_id)`
  (gained a required 4th parameter) now implements the real spec behavior
  instead of the earlier tier-insta-complete stand-in: validates the
  giver's node is researched and `TechDef.giftable`, rejects a duplicate
  gift of a tech_id the receiver already holds anywhere in their tree, and
  creates a new `gifted = true` `GeneratedTechNodeState` on the receiver —
  sharing `gift_resources`' cooldown and friendship gain, same as before.
- `DevelopmentPanel` and `DiplomacyPanel`'s tech-gift button were rewritten
  for the node-based model: the former lists every tree node grouped by
  tier with researched/available/locked status and a start-research button;
  the latter's tech-gift button became an `OptionButton` populated with
  every giftable node the picker's own gift-eligibility check
  (`_giftable_tech_nodes`) allows. Both smoke-tested by loading their
  scripts dynamically via `load()` rather than the bare `DevelopmentPanel`/
  `DiplomacyPanel` class_name identifiers — see the compile-order bug note
  below, since referencing either class_name directly from a fresh
  `--script` entry hits it (both scripts bare-reference `TurnManager`
  internally).
- Sample data: 10 `TechDef`s across the 5 tiers (`data/techs/`), replacing
  the single obsolete `prototype_foundation.tres`, whose old schema
  (`display_name`/`cost`) no longer matched the rewritten `TechDef` and
  which every unit's `tech_id` pointed at — `nova_scout`/`nova_vanguard`/
  `crimson_bastion` were repointed to new faction-specific
  `mandatory_base_tech` entries (`nova_hull_foundation`/
  `crimson_hull_foundation`).

The event system (EVENT_DETAIL_SPECIFICATION.md / DATA_DEFINITION.md section
22) is complete, closing the last item on this document's own gap list — see
the "Validation and setup" section's note on scope for what's deliberately
still missing (art assets, VN-style playback controls, the recap screen):

- `EventDef` matches section 22's schema. `condition_tree` is a Dictionary,
  not code (`{"all"/"any"/"not": ...}` composing `{"type": "<condition_type>",
  ...}` leaves), evaluated by `EventConditionEvaluator.evaluate` — DATA_
  DEFINITION.md explicitly leaves this data format undecided, so the exact
  leaf-type set is a scope decision made here. All ten of section 3's trigger
  categories are covered by at least one concrete, state-backed condition
  type (`turn_at_least`/`turn_at_most`, `region_owned`/`region_not_owned`,
  `squad_near_region` — a BFS hop count over `RegionDef.neighbor_ids` from
  every region a faction has a squad in, `tech_researched`, `pilot_assigned`/
  `pilots_share_squad`, `pilot_injured`, `relation_band_at_least`/
  `treaty_active`, `capture_count_at_least`, `region_count_at_least`/
  `military_power_at_least` via the existing `BattlePowerEstimator`, and
  `event_flag_set`/`event_choice_selected`). Two categories are narrower than
  their spec prose: "固有パイロットの撃破" (pilot death) collapses into
  `pilot_injured` since this ruleset has no permanent pilot death — a
  destroyed unit's pilot is always just injured (STRATEGY_DETAIL_SPECIFICATION.md
  section 5.7) — and "解析" (encyclopedia analysis) isn't modeled since no
  encyclopedia system exists, so only the capture-count half of that category
  is covered.
- A parallel `EventEffectDef` (id + `GameEnums.EventEffectType` + payload
  Dictionary) plays the same role for "効果ID" that choice_entries/
  default_effect_ids reference — DATA_DEFINITION.md names the effect *type*
  enum but not a distinct resource for authoring one as data, so this adds
  the missing piece the same way `AchievementDef.condition_type`/
  `condition_payload` already does for achievements. `EventEffectApplier.
  apply(game_state, faction_id, effect)` implements all 13 `EventEffectType`
  values against real state: FUNDS/MATERIALS (floored at 0), TECH_CANDIDATE
  (grants a `gifted = true` research node, reusing the same dedup-by-tech_id
  and any-prior-tier-researched prerequisite rule `Diplomacy.gift_tech`
  established), RESEARCH_MODIFIER (adjusts `current_research.turns_remaining`,
  min 1), PILOT_JOIN/PILOT_LEAVE (the latter also finally reads
  `PilotState.available`, wiring up a field that had been set since the
  achievements milestone but never checked anywhere — `assign_pilot_to_unit`
  now rejects an unavailable pilot the same way it already rejected an
  injured one), PILOT_INJURE, UNIT_GAIN/UNIT_LOSE, RELATION, TREATY (directly
  sets a relation pair's treaty state, bypassing the normal proposal/roll
  flow — an event can just narratively grant or break one), and
  ENEMY_REINFORCEMENT (UNIT_GAIN targeting a different faction_id than the
  event's own).
- `Faction` gained `event_flags` (read by `event_flag_set`/written by the
  EVENT_FLAG effect and by choice resolution itself — see below),
  `pending_event_ids`, and `triggered_event_ids` (once_per_campaign/
  exclusive_group_id gating, locked in at *registration*, not resolution, so
  the same condition can't re-register a still-unresolved pending event next
  turn). `ProfileState` gained `viewed_event_ids` (once_per_profile gating
  across campaigns, and section 6's "回想" recap list — MAIN events always
  land here on resolution; a SUB event only does if it's explicitly
  `once_per_profile`). `CampaignRuntimeState` gained `campaign_event_history`
  (section 6's "履歴ログ": every resolved SUB event, this campaign only).
- `GameState.check_pending_events(faction_id)` evaluates every `EventDef`
  targeting that faction against `EventConditionEvaluator`, appending newly-
  satisfied ones to `pending_event_ids` and sorting the whole queue by
  importance (MAIN before SUB), then `priority`, then id — exactly section
  8's "主要イベント、補助イベント、イベントID昇順で処理する" plus section
  22's own `priority` field for same-type ordering.
  `GameState.resolve_event_choice(faction_id, event_id, choice_id)` applies
  the chosen effect_ids (or `default_effect_ids` for a choice-less event),
  records `event_flags["choice:<event_id>"] = choice_id` (backing
  `event_choice_selected`), and files the event into the recap list or
  history log per its importance. `TurnManager._begin_faction_turn` calls
  `check_pending_events` for every faction right before that faction's own
  `Phase.ORDERS` (section 8: "次の該当勢力ターン開始処理後、戦略フェイズ
  前に再生する"); an AI faction has no UI to show events to, so
  `GameState.auto_resolve_pending_events` immediately resolves its whole
  queue by deterministically picking each event's first `choice_entries`
  option (or its `default_effect_ids`) — a simple stand-in for real AI
  narrative decision-making, mirroring how every other `AiController`
  decision is instant and not player-visible.
- A new `EventPanel` (mirroring the other overlay panels' style) presents the
  player faction's queue one event at a time: a "次へ" button advances
  through `dialogue_entries`, then choice buttons appear (or a single
  acknowledge button for a choice-less event) and resolving one immediately
  loads the next queued event or closes. `StrategicMap._on_phase_changed`
  opens it automatically whenever `Phase.ORDERS` begins for the player
  faction with a non-empty `pending_event_ids` — the panel's own modal
  overlay (dim background, `MOUSE_FILTER_STOP`, a layer above every other
  panel) is what actually blocks the player from acting until every event
  resolves, rather than `TurnManager` awaiting UI input mid-turn-advance.
- Sample data: 8 events (`res://data/events/`, 2 MAIN + 2 SUB per faction)
  and 11 effects (`res://data/event_effects/`) — scaled down from the spec's
  "~8 main + ~15 sub per faction, ~69 total" the same way `TechTreeGenerator`
  scaled its per-tier node count, given how much smaller the actually-authored
  sample dataset is. One pair per faction demonstrates a MAIN event's binary
  aggressive/diplomatic choice gating a SUB event via `event_choice_selected`
  (`nova_main_001_first_contact` → `nova_sub_002_diplomacy_pays_off`, and the
  Crimson mirror), so the condition/effect/registration loop is exercised
  end-to-end by real data, not just synthetic test fixtures.
- Explicitly out of scope, matching every other panel in this codebase
  shipping plain-but-functional UI ahead of any final art: `scene_background`
  and dialogue-entry portraits (no character art or background images exist
  in this project yet), and section 7's VN-style playback controls (fast-
  forward, auto-play, a conversation log, read-only skip-ahead) — `EventPanel`
  is a plain sequential "次へ"-through-dialogue-then-choose flow with no skip
  affordance at all, which trivially satisfies section 7's one hard
  requirement ("選択肢到達時に早送り・スキップを停止する", never skipping
  past an unread choice) by not implementing skip in the first place. The
  回想 (recap) screen itself — a UI browsing `profile.viewed_event_ids` — also
  isn't built; the data it would read (`ProfileState.viewed_event_ids`) is
  in place and already covered by `event_system_test.gd`.

Strategic squad state now supports two-phase adjacent movement, per-unit and
per-squad `movement_used`, faction reset, split, and merge. The strategic map
issues player movement orders by squad ID, and the movement phase applies all
planned squad destinations. New games deterministically seed one squad for each
new `UnitDef` in its origin faction's starting region. This loadout is temporary
until `FactionDef.starting_unit_loadout` is added.

Faction turns now run in a fixed order with the selected player first, followed
by configured AI factions. Income, production, research progression, and
movement reset are scoped to the active faction. AI factions resolve one at a
time, and `turn_number` advances only after the full faction cycle. Combat
regions are processed in stable region-ID order. The current dataset has only
two factions, so this is a transitional subset of the specified three-faction
campaign.

The strategic map now renders badges solely from individual units in new
`SquadState` records, provides a five-slot formation dialog for slot movement,
split, and merge, and never combines those counts with legacy `UnitStack`
combat strength. AI factions also issue deterministic squad-ID movement orders;
the old AI stack order remains isolated only for prototype combat compatibility.

Supply connectivity is derived deterministically from each faction's original
capital through contiguous regions it currently owns. Ownership changes rebuild
the cache. Supplied units can replenish EN immediately for free and begin
prepaid repairs without a facility; repairs advance at that faction's next turn
start, pause while the region is disconnected, and resume after reconnection.
The formation dialog exposes EN replenishment and repair commands, while the
region panel shows the player's visible supply status. Supply loss does not
block normal strategic movement, matching the detailed specification.

The obsolete region-wide `pending_move_order` path and legacy AI stack movement
have been removed. At combat-phase start, new squad contacts are snapshotted in
stable region-ID order. Undefended hostile regions are captured through the
normal ownership boundary; defended regions produce ID-only pending battle
descriptors without projecting individual units into the old ratio resolver.
Until the minimum RTS runtime exists, those defended contacts are displayed as
battle-waiting regions and remain unresolved. This is an explicit specification
gap: the current prototype still advances the faction turn despite the pending
contact, while the target rules require every contact to end in victory or
retreat before the faction turn can finish.

The in-memory RTS state layer now exists: battle, squad, unit, control-point,
and result states plus a deterministic factory from pending descriptors.
Battle HP/EN are copied into temporary unit states so combat cannot mutate the
campaign before result application. Injected spawn points, stable squad/slot
ordering, retreat origins, ten-second retreat preparation, the 300-second cap,
and transient battle IDs/RNG seeds are represented. Battle spawn coordinates
now come from `BattleMapDef`; hashed battle seeds remain provisional until the
saved campaign RNG state is introduced.

A full-screen 2.5D battle prototype is attached as an overlay to the strategic
map. It uses a dedicated 3D world, perspective `Camera3D`, lit 1,200x900m ground
plane, grid, headquarters/relay markers, and billboard robot sprites for every
individual unit. Squads preserve the specified three-front/two-rear formation,
unit-size silhouettes, and use the slowest surviving unit's `speed / 10` for
movement. It supports player-squad selection, ray-to-ground right-click
destinations, pause and 1x/2x/4x time, and a provisional attacker-retreat
command. TurnManager awaits each battle in stable order, so faction progression
does not continue while the overlay is active. Retreat and timeout results copy
temporary HP/EN back through `GameState.apply_battle_result`, return attackers
to their recorded origins, reject double application, and then resume the
faction turn. The standard `BattleMapDef` now supplies validated spawn
transforms, world size, navigation-region path, two headquarters, and a central
relay. Living non-owner units capture an uncontested point at one point per
unit per second; empty, owner-defended, and contested points decay at two points
per second. Headquarters capture completes the battle and applies region
ownership through the normal result boundary. Either faction may capture an
opposing point, resolving contradictory attacker-only wording in favor of the
specification's explicit attacker-HQ and defender-HQ victory conditions.
The first automatic-fire layer is implemented independently of the view. Each
living unit gains action gauge at `10 * sqrt(speed / 100)` per world second,
selects the first fixed weapon whose EN and range requirements are met, spends
EN once, and observes its post-action delay. Front slots are targeted before
rear slots. Simultaneously ready attacks are fixed before their damage is
applied, allowing future mutual destruction without dictionary-order bias.
Per-hit accuracy, penetration/armor, five-percent minimum weapon damage,
attribute resistance, 90--110 percent variation, critical damage, and a saved
linear-congruential RNG state are active. HP zero marks the unit destroyed and
single-side annihilation finalizes the battle. Generic pilots use the
specification baseline of 100. Named-pilot shooting, melee, defense, reaction,
and command snapshots now affect accuracy, evasion, firepower, armor, and
critical chance. All eight target rules and the fixed single, row, column, and
all-target patterns are supported; random targeting consumes the saved battle
RNG deterministically. Defensive-policy units at or below 30 percent HP defend,
and unavailable weapons also select defense with the specified bonuses. Pilot
growth/skills, terrain, and cover remain gaps. Battle result recovery/loss rules
for destroyed units are also still pending.

Active support actions share the same gauge and simultaneous-action phase as
weapons. SUPPORT policy prefers a triggered skill; other policies attack first
and fall back to support when no weapon is usable. Repair uses its fixed value
plus target-max-HP percentage, spends full EN even when capped, and cannot
revive HP-zero units. EN transfer requires enough target capacity and moves the
same amount removed from its source, so squad total EN never grows. Attack
damage and destruction apply before committed support, while a supporter
destroyed in the same batch still completes its action. At round end, a dead
leader is replaced by the living pilot with highest command, then lowest slot;
generic pilots remain command 100 without runtime pilot records. Balanced
attack-versus-support ordering and ROLE/SELF target data remain schema gaps.

The battle overlay now starts in an explicit pre-battle confirmation state.
It lists both five-slot formations with current HP/EN, allows the player policy
to be selected, and shows only the five-band approximate power rating. Exact
accuracy, damage range, planned actions, targets, and RNG outcomes remain
hidden as required. Contact rounds can also require confirmation before their
internal clock advances. Finalized battles remain visible in a result panel
showing winner, loser, reason, elapsed time, and destroyed units; campaign
application occurs only when the player confirms returning to strategy, so the
result cannot be silently or doubly applied. Enemy details remain temporarily
fully visible until IntelState/FOW is connected.

Owned headquarters and relays now recover living friendly units within their
sensor radius at one percent max HP and two percent max EN per world second.
Per-unit fractional carry makes recovery independent of frame subdivision; HP
zero cannot recover and max values discard overflow. Overlapping points use the
highest single rate instead of stacking. A living non-owner unit inside that
point's capture radius blocks only that point, while pause and active automatic
rounds block recovery globally. Round participants remain in their existing
five-second re-engagement wait before recovering. Recovery uses squad-center
range as an explicit approximation until individual simulation positions are
introduced. The 2.5D markers now derive color from current owner faction data,
blend toward the capturing faction by progress, and immediately reflect owner
changes in both color and label.

Combat simulation now subdivides every update into deterministic 0.05-second
steps. A large update can therefore execute multiple actions instead of at
most one, and a 30-second update produces the same HP, EN, RNG state, and
result as 300 updates of 0.1 seconds. This fixed-step foundation is required
before adding formal contact-round boundaries and simultaneous round phases.

Weapon-range contact now creates deterministic, exclusive one-squad-versus-one-
squad engagements. Stable squad IDs break simultaneous contact ties, a locked
pair cannot be attacked by a third squad, and battlefield movement/input plus
control-point capture stop during an active round. A round ends before actions
at the exact 30.000-second boundary, clears surviving action gauges and weapon
delays, and assigns both squads a five-second re-engagement wait. Contact also
cancels queued destinations. The current interpretation always honors the
five-second wait for the same pair; this is provisional because detail sections
6 and 20 conflict on immediate forced re-contact while a wait remains.

The 2.5D view now consumes combat events without participating in combat
resolution. Every individual robot has billboard HP and EN bars that update
from transient battle state. Ballistic attacks draw a short amber firing line,
beam attacks use blue, and each hit produces a MISS, damage, or CRITICAL popup.
Destroyed robot visuals and their bars are hidden in place, preserving the
specified empty formation slot. These effects are disposable presentation;
skipping them cannot alter HP, EN, RNG, targeting, or battle results. Enemy HP
and EN are currently always visible, an explicit temporary gap until contact
intel visibility is connected.

The old `UnitType`/`UnitStack`/`CombatResolver`/`BattleVignette` prototype
classes and `res://data/legacy_units/` have been deleted; the typed registry
at `res://data/units/` is now the only unit-definition path.

### Validation and setup

- Debug builds load and validate all new master data during `GameState` startup.
- `res://data/pilot_skills/` is intentionally empty in the first dataset.
- Run runtime-state tests with `godot --headless --path . --script
  res://tests/runtime_state_test.gd` when Godot 4.7 is available.
- Run campaign owner and rollout tests with `godot --headless --path . --script
  res://tests/campaign_runtime_state_test.gd`.
- Run production state tests with `godot --headless --path . --script
  res://tests/production_system_test.gd` and the GameState boundary test with
  `res://tests/production_integration_test.gd`.
- Run `res://tests/strategic_map_smoke_test.gd` to construct a new-game
  strategic map and its production UI.
- Run `res://tests/strategic_squad_state_test.gd` for movement and split/merge
  graph invariants.
- Run `res://tests/ai_squad_movement_test.gd` for deterministic AI squad orders.
- Run `res://tests/faction_turn_flow_test.gd` for player-first fixed faction
  order, AI automatic resolution, and full-cycle week advancement.
- Run `res://tests/supply_system_test.gd` for supply connectivity, EN
  replenishment, and paused/resumed repairs.
- Run `res://tests/squad_combat_boundary_test.gd` for deterministic contact
  detection, undefended capture, and defended pending-battle descriptors.
- Run `res://tests/battle_runtime_state_test.gd` for deterministic transient
  battle creation, campaign isolation, and retreat timing.
- Run `res://tests/battle_view_smoke_test.gd` for battle HUD construction,
  paused movement/time behavior, per-unit HP/EN bars, shot feedback, and
  destroyed-unit visibility.
- Run `res://tests/battle_capture_system_test.gd` for battle-map integration,
  paused capture, headquarters victory, ownership application, and duplicate
  result rejection.
- Run `res://tests/battle_combat_system_test.gd` for paused gauges, fire timing,
  EN consumption, post-action delay, and deterministic combat RNG.
- Run `res://tests/battle_targeting_system_test.gd` for all target rules,
  deterministic random selection, row fallback, and fixed area patterns.
- Run `res://tests/battle_combat_round_test.gd` for the 30-second boundary,
  round-state cleanup, five-second wait, exclusive pairing, and pause freeze.
- Run `res://tests/battle_support_action_test.gd` for repair, EN transfer,
  conservation, target priority, and damage-before-support ordering.
- Run `res://tests/battle_leader_reselection_test.gd` for deterministic command
  and formation-slot leader replacement.
- Run `res://tests/battle_control_point_recovery_test.gd` for fractional HP/EN
  recovery, blocking, pause/round freeze, overlap, and owner switching.
- Run `res://tests/battle_result_application_test.gd` for destroyed-unit
  recovered/captured/lost outcomes, post-battle campaign validation, and the
  restored diplomacy attack-penalty log entry.
- Run `res://tests/multi_faction_conflict_test.gd` for `multi_faction_battle_pending`
  detection and the sequential pairwise resolution that replaced its
  permanent dead end (exercised with a synthetic third faction, since the
  current two-faction dataset can't otherwise produce the scenario).
- Run `res://tests/pilot_progression_test.gd` for pilot seeding at
  `initial_level`, assign/unassign displacement and injury gating,
  growth-adjusted battle stats, EXP awarding and level-up across the 250-EXP
  band, three-turn injury application/decrement, and the
  `capture_allowed == false` always-lost fix.
- Run `res://tests/fog_of_war_test.gd` for asymmetric sensor-range
  confirmation, sticky `intel_confirmed` versus non-sticky `currently_sensed`
  after leaving range, engagement-only confirmation not granting live
  position tracking, the firing-disclosure reveal window opening and
  expiring, and the battle view hiding/freezing unconfirmed and
  out-of-range enemy squads.
- Run `res://tests/pilot_skills_test.gd` for unlock-level gating, leader_only
  gating, all four `condition_type` values (`always`/`hp_pct`/`en_pct`/
  `environment`, the latter two via synthetic pilot/skill data registered
  and cleaned up locally), and a same-RNG-seed damage comparison proving a
  firepower skill actually changes `BattleCombatSystem._resolve_attack`'s
  output.
- Run `res://tests/strategic_intel_test.gd` for a squad's own-faction
  confirmation, colocation-based confirmation without combat, stickiness
  after the observing squad leaves, reverting to unconfirmed on a
  composition change, and both sides of a resolved battle confirming each
  other.
- Run `res://tests/ai_battle_auto_resolve_test.gd` for
  `_battle_involves_player` classification, a non-player battle finalizing
  synchronously through `_auto_resolve_battle` with no signal listener
  connected, and a full `commit_turn()` cycle completing when the active
  AI faction fights a synthetic third faction with no
  `battle_runtime_ready` handler present at all.
- Run `res://tests/battle_squad_movement_ai_test.gd` for headless (no view)
  squads actually closing distance under `advance_time` alone,
  OFFENSIVE/BALANCED squads targeting the nearest enemy, DEFENSIVE squads
  holding their own HQ, the player's own squad destination never being
  AI-overridden, RETREAT-policy auto-triggering at the 30% HP threshold,
  and the `movement_ai_disabled` opt-out.
- Run `res://tests/save_load_test.gd` for a full save/load round trip
  (funds, materials, region ownership, and campaign_runtime state survive
  a save, further mutation, and reload undoing that later mutation),
  save being refused outside `Phase.ORDERS`, `list_save_slots()` matching
  what's on disk, and loading a missing or corrupt slot failing cleanly
  instead of crashing. Uses slots 89-91 (cleaned up after the run) to
  avoid colliding with a real save on a developer's machine.
- Run `res://tests/diplomacy_test.gd` for initial friendship/band, combat
  events lowering friendship symmetrically, `tick_week`'s treaty countdown
  (including the one-turn-before-expiry log notice) and cooldown decrements,
  proposal validation (bad duration, cooldown, insufficient funds), a
  deterministic successful proposal (forced `campaign_rng` seed) forming the
  treaty, transferring the offer, and retreating a stranded squad home, a
  deterministic failed proposal costing nothing but setting the cooldown, an
  active treaty blocking `plan_squad_movement` into the partner's territory
  and that block lifting on expiry, unilateral treaty-breaking penalizing
  only the breaker's own future proposals, gift minimum/cooldown enforcement,
  intel purchase transferring only squads the partner already confirmed (via
  a synthetic third faction, same trick as `multi_faction_conflict_test.gd`),
  and captured-unit ransom. See also `campaign_runtime_state_test.gd`'s
  `_test_relation_state_round_trip` for `relation_states`/`diplomacy_log`
  surviving a JSON save/load round trip and `get_relation_state` resolving
  the same instance regardless of argument order.
- Run `res://tests/terrain_zone_test.gd` for `terrain_zone_at` lookup,
  difficult terrain's 0.8x speed multiplier, the newly-wired environment-
  aptitude speed multiplier, cover's evasion bonus ignoring melee attacks,
  hazard drain (floored at 1 HP, never destroying/finalizing the battle by
  itself, stopped by `is_auto_resolving` and by pause), impassable-position
  rejection, and sensor line-of-sight blocking by an obstacle directly on
  the line between two squads (versus the same distance with a clear line
  of sight). Uses the real `standard_battle_map.tres` zones rather than
  synthetic fixtures, so master-data loading/validation is covered too.
  When repositioning a squad and calling `advance_time` in a test, remember
  to also pin the *other* squad (`movement_ai_disabled = true` plus a
  matching `destination`) — otherwise a single large `advance_time` call
  lets an AI-controlled squad close an unrealistic distance and start a
  real fight in one step, as this test's hazard cases discovered the hard
  way (`_pin_defender_far_away`).
- `pilot_skills_test.gd` gained `_test_action_skill_id_grants_an_extra_
  support_skill`: proves `field_repair` is absent from `nova_scout` (its
  own `support_skill_ids` is empty), stays absent before Lv10 or above the
  30% HP threshold, appears via `pilot_action_skill_ids` once both are
  satisfied, and that `_prepare_support` actually selects it as a real
  combat action. When testing UI panels under `scenes/strategic_map/` by
  calling their handlers directly (bypassing button `disabled` gating),
  don't declare a variable with the panel's own type in a fresh `--script`
  entry (e.g. `var panel: PilotAssignmentPanel`) — that's the same headless
  compile-order bug as `diplomacy.gd` used to hit, since these files still
  bare-reference `GameState`/`TurnManager`. Use `child.get_script().
  get_global_name() == "PilotAssignmentPanel"` plus `Object.call()`/`get()`
  to reach it dynamically instead, as the ad hoc smoke checks for
  `SaveLoadPanel`/`DiplomacyPanel`/`PilotAssignmentPanel` all did.
- Run `res://tests/round_distance_test.gd` for `_round_distance_rate`
  matching the policy table exactly, a fresh engagement seeding
  `engagement_distance_m` from the real world distance, mutual OFFENSIVE
  closing it and mutual RETREAT opening it, the 0-minimum clamp, a weapon
  going unusable once the abstract distance drifts past its range even
  though `world_position` (checked directly) is untouched and still in
  range, `world_position` staying frozen for the whole battle while the
  abstract distance visibly drifts, and a new engagement after the old one
  ends recomputing its distance from the (moved) real position rather than
  inheriting the old engagement's drifted value. Calling
  `update_engagements(delta)` with a large `delta` to fast-forward through
  a squad's post-engagement `reengage_wait_sec` cooldown also advances any
  engagement that forms in that same call by the full `delta` — clear the
  cooldown fields directly instead of passing a large delta when a test
  wants to inspect a freshly-formed engagement's just-seeded distance
  before anything has had a chance to move it.
- Run `res://tests/combat_modifiers_test.gd` for the difficulty registry
  loading all 3 presets, `current_difficulty()` falling back to neutral for
  an unresolved `difficulty_id`, `start_new_game` validating it (accepting
  a real one, falling back to `"normal"` for a bad one), `difficulty_id`
  round-tripping through save/load, `enemy_hp_multiplier` scaling only the
  non-player unit in a real built battle, and the
  `hp_multiplier`/`firepower_multiplier`/`accuracy_add`/`evasion_add`/
  environment-aptitude accessors all returning the right values in
  isolation (no RNG-roll integration test — these compose into the
  accuracy/damage formula the same way `_cover_evasion_bonus` already did
  in `terrain_zone_test.gd`, and direct accessor tests were preferred there
  too over hunting for a specific seed).
- `diplomacy_test.gd`'s tech-gift coverage was rewritten for the node-based
  model: `_test_gift_tech_registers_a_new_gifted_node` (giver-must-have-
  researched gate, `giftable == false` rejection, a successful gift creates
  the right gifted node without touching the giver's own, shared cooldown/
  friendship gain with `gift_resources`, and duplicate-tech_id rejection)
  and `_test_gifted_node_uses_the_any_prior_tier_prerequisite_rule` (a
  gifted tier-1 node is always available; a gifted tier-2+ node needs *any*
  researched node one tier down, not a specific `prerequisite_node_ids`
  link). Both use hand-built `GeneratedTechNodeState` fixtures rather than
  `TechTreeGenerator`'s random output, to stay deterministic regardless of
  `campaign_rng`'s seed.
- Run `res://tests/achievements_profile_test.gd` for achievement unlocking
  across all 5 `condition_type`s, `ProfileState.recalculate_bonus` always
  recomputing from `achievement_ids` rather than trusting a stored value,
  the permanent EXP bonus applying only to the player's own pilots, a
  `user://profile.json` save/load round trip, and autosave slot rotation
  (oldest-or-empty replaced, `auto: bool` correctly separating the manual
  and autosave namespaces). Snapshots and restores the real profile file
  around its own execution — see the note above about why.
- Run `res://tests/tech_tree_test.gd` for `TechTreeGenerator.
  generate_for_faction` (mandatory techs always placed at their tier and
  never leak into another faction's tree, every generated node reachable,
  no duplicate tech_ids, determinism under a fixed RNG seed) and
  `TurnManager.start_research`/`_advance_research` (prerequisite gating,
  funds deducted via the correct `faction.funds` currency, rejecting a
  second concurrent research or insufficient funds, completion emitting
  `research_completed` and clearing `current_research`). A GDScript
  closure quirk surfaced while writing this: a lambda can read a captured
  outer local but an assignment to it inside the lambda does not write
  back to the outer scope — use a single-slot `Array` as a mutable box
  instead when a signal-connected lambda needs to report a result back to
  its caller.
- Run `res://tests/event_system_test.gd` for `EventConditionEvaluator`
  (nested all/any/not composition, and every leaf condition type: turn,
  region ownership, the `squad_near_region` BFS hop-cap, tech research,
  pilot assignment/injury, relation band/treaty state, capture count, region
  count, event flags, and past-choice results), `EventEffectApplier` (FUNDS
  floored at 0, RELATION deltas, EVENT_FLAG, TECH_CANDIDATE dedup-by-tech_id,
  and PILOT_LEAVE's new `PilotState.available` gate actually blocking
  `assign_pilot_to_unit`), `GameState.check_pending_events` (MAIN-before-SUB/
  priority/id sort order, re-checking not double-registering a still-pending
  once_per_campaign event), `resolve_event_choice` (effect application,
  `choice:<event_id>` flag recording, a resolved choice unlocking a
  `event_choice_selected`-gated follow-up event in the real sample data,
  MAIN events landing in `profile.viewed_event_ids`), `auto_resolve_pending_events`
  deterministically picking an AI faction's first choice, a save/load round
  trip of all the new per-faction/campaign/profile event fields, and — the
  one integration-level case that doesn't call GameState's event functions
  directly — a real `TurnManager.commit_turn()` cycle proving
  `_begin_faction_turn` actually registers the player's events and
  auto-resolves the AI faction's own. Same profile-file snapshot/restore
  wrapper as `achievements_profile_test.gd`, for the same reason
  (`resolve_event_choice` persists MAIN events to the real
  `user://profile.json`). Authoring the sample `EventDef`/`EventEffectDef`
  `.tres` data directly (not through the editor) needs nested typed-array
  literal syntax the rest of this project's data hadn't exercised yet:
  `Array[Dictionary]([{...}, {...}])`, with further `Array[StringName]([...])`
  literals nested inside those dictionaries for effect_ids — confirmed
  working, but easy to get an enum index wrong inside a payload Dictionary
  (`EventEffectType.EVENT_FLAG` is index 12, not 11 — GDScript won't catch a
  wrong plain `int` against an enum-typed export field the way it would
  catch a wrong type entirely) and have the effect silently no-op instead of
  erroring, since `EventEffectApplier.apply`'s `match` just falls through to
  a different case with a payload shape that doesn't match either.
- Any new script declaring `class_name` needs a one-time
  `godot --headless --path . --import` before it resolves as a global type
  in other scripts — otherwise headless runs fail with "Could not find type
  ... in the current scope" even though the class compiles fine on its own.
- A handful of files under `scenes/strategic_map/` fail to compile with
  "Identifier not found: GameState" if a `--script` test entry point makes
  them the first thing directly compiled/instantiated (a headless-only
  GDScript compile-order quirk; they work fine through the normal
  autoload-boot path, e.g. any test that goes through `GameState`/
  `TurnManager` first). If a new test hits this, prefer restructuring the
  test to reach the autoload first rather than fighting the target file's
  `GameState.` references — see `strategic_intel_test.gd`'s dropped
  `RegionNodeView` case for what was tried. `scripts/factions/diplomacy.gd`
  used to be on this list too; it now takes `game_state` as an explicit
  parameter on every function instead of referencing the `GameState`
  autoload by bare identifier, which sidesteps the bug entirely (see
  `diplomacy_test.gd` for a test that exercises it directly, something no
  earlier test attempted). Prefer that parameter-passing approach over the
  restructure-the-test workaround whenever the class under test is the one
  actually triggering the bug, rather than a bystander. For an ad hoc smoke
  check that must instantiate one of these files directly (not just call a
  static function on it), referencing its bare class_name at all — even
  only for `.new()`, never mind a typed variable declaration — is enough to
  trigger the bug, since GDScript eagerly resolves every identifier in a
  referenced class's body at the *referencing* script's own parse time, not
  at first execution. Load it dynamically instead:
  `load("res://path/to/script.gd").new()`, then interact through
  `Object.call()`/`.get()` rather than static typing — this is what the
  `DevelopmentPanel`/`DiplomacyPanel` tech-tree smoke check above did.
- Godot 4.7.1 is installed at
  `C:/Users/koyu9/local/godot/Godot_v4.7.1-stable_win64_console.exe` (not on
  PATH). All state/production tests, the strategic-map smoke test, and a
  three-frame main-scene smoke test pass.
- Headless runs warn that Steam has no app ID and continue without Steam; this
  is expected for local validation.
- Temporary balance data uses 3000 starting funds, 2000 starting materials,
  and one standard production facility (power 100) in each faction shipyard.
  These values and the full eight-region facility layout are not final balance.
- Newly produced squads can receive player and AI movement orders, and combat
  is fully routed through the new `SquadState`/`BattleRuntimeState` path for
  both player and AI squads — the legacy stack path no longer exists.

## Repository and synchronization

- Remote: `https://github.com/hgffgh/yabou_codex.git`
- Default branch: `main`
- Godot-generated `.godot/` and `.import/` directories are ignored.
- `steam_appid.txt` is ignored because it is local development data.
- The GodotSteam addon is committed and may contain platform-specific native
  libraries.

For another machine, clone the repository, install Godot 4.7, import
`project.godot`, and allow Godot to regenerate its local caches.

## Handoff maintenance

When completing a milestone, update:

- `Current status`
- `Current implementation versus target design`
- `Recommended next task`
- Any new validation or setup requirements

