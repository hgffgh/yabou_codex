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
| One generic `resources` currency | Production uses funds/materials; legacy research still uses `resources` |
| — (removed; `UnitStack`/`CombatResolver` deleted as unreachable) | Production, movement, and combat all use `UnitInstanceState`/`SquadState`/`BattleRuntimeState` |
| No five-unit squad slots | `SquadState` is implemented with 3 front and 2 rear slots and is fully wired into movement, production, and combat |
| Unit type has attack/defense only | New unit, weapon, aptitude, resistance, and support Resources now coexist with the prototype |
| Faction-wide integer tech tier | Generated five-tier technology-node graph |
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
diplomacy penalties) is complete, named pilots now level up, earn EXP, and
get injured per spec, and the battle view now respects sensor-based fog of
war. The remaining gaps, in rough order of value:

1. Pilot skills: `PilotSkillDef.modifiers`/`condition_type`/`leader_only`
   are validated at startup but never read during combat — learned skills
   have no effect. This was deliberately deferred from the pilot-progression
   pass because `res://data/pilot_skills/` is still empty (both current
   pilots have `skill_ids = []`), so there is no real data yet to validate a
   generic condition/modifier evaluator against. There is also no player
   formation UI for pilot assignment yet — `assign_pilot_to_unit`/
   `unassign_pilot` exist and are tested, but only `GameState`'s
   transitional deterministic seeding calls them today.
2. Persistent intel and strategic-map fog of war: fog of war only exists
   inside a single battle right now (see the fog-of-war milestone above for
   what's deliberately still missing — `IntelRecordState` persistence,
   strategic-map visibility, and the intel-purchase feature).
3. AI-vs-AI battle auto-resolution: every combat contact, including battles
   the player has no stake in, currently requires manually playing through
   the full RTS overlay, because `BattlePrototypeView` has no non-interactive
   fast-resolve path and `TurnManager` awaits every battle unconditionally.
   This will only get more disruptive as the faction count grows toward
   three.
4. Terrain zones and battle-map navigation: `TerrainZoneDef`/`TerrainEffect`
   have no resource class or loader yet, `BattleMapDef.navigation_region_path`
   is schema-only, squad movement is straight-line with no pathfinding, and
   defending squads never move, retreat, or defend on their own inside a
   battle (only player-issued squads reposition).
5. Save/load: per-object `to_dict()/from_dict()` round-tripping already
   exists and is tested for campaign/squad/unit/production/pilot state, but
   there is no top-level `CampaignSaveData` aggregator, no file I/O, and no
   save/load UI.
6. Diplomacy treaties and the event system remain schema-only —
   `TreatyType`/`RelationState`/`EventDef` have no runtime logic beyond the
   lightweight numeric relation score (`Faction.relations`,
   `scripts/factions/diplomacy.gd`) already driving AI attack targeting.
7. The permanent profile EXP bonus (achievements) is a hardcoded `0.0`
   placeholder in `GameState._apply_battle_pilot_exp` — there is no
   `ProfileState`/achievement system to source it from yet.

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
- Any new script declaring `class_name` needs a one-time
  `godot --headless --path . --import` before it resolves as a global type
  in other scripts — otherwise headless runs fail with "Could not find type
  ... in the current scope" even though the class compiles fine on its own.
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

