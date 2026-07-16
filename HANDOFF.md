# Development handoff

## Current status

The repository contains a functioning but simplified Godot strategy prototype.
The product design was subsequently expanded into a full set of specifications.
No migration from the prototype architecture to the specified architecture has
started yet.

The latest specification milestone is complete:

- High-level game specification
- Real-time battle specification
- Turn-based strategy specification
- Unit and weapon numeric specification
- Event and narrative specification
- Save, difficulty, AI, input, and UI specification
- Godot-oriented data definition document

The next milestone is the data-foundation implementation described in
`DATA_DEFINITION.md`.

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
| One generic `resources` currency | Separate funds and materials |
| `UnitStack` stores unit-type counts | Individual `UnitInstanceState` records |
| No five-unit squad slots | `SquadState` with 3 front and 2 rear slots |
| Unit type has attack/defense only | Unit, weapon, aptitude, resistance, and support Resources |
| Faction-wide integer tech tier | Generated five-tier technology-node graph |
| Parallel per-unit production timers | Facility production-power queues |
| Ratio-based instant combat | Free-movement RTS plus 30-second combat rounds |
| One combined turn loop | Fixed faction turns with strategy and combat phases |
| Region has one resource yield | Region funds/materials income plus fixed facilities |

Relevant prototype files:

- `resources/unit_type.gd`
- `resources/faction_def.gd`
- `resources/region_def.gd`
- `resources/tech_def.gd`
- `resources/campaign_config.gd`
- `scripts/units/unit_stack.gd`
- `scripts/combat/combat_resolver.gd`
- `autoload/game_state.gd`
- `autoload/turn_manager.gd`

## Recommended next task

Implement the first data-foundation slice without removing the prototype:

1. Create shared enums/constants.
2. Create new Resource definitions for `WeaponDef`, expanded `UnitDef`,
   `PilotDef`, `PilotSkillDef`, and `SupportSkillDef`.
3. Create a typed master-data registry that loads each Resource directory.
4. Create a development-build validator for duplicate IDs, missing references,
   numeric ranges, and invalid enum combinations.
5. Add a minimal dataset containing:
   - three unit definitions,
   - three weapons,
   - one support skill,
   - two named pilots,
   - the generic-pilot fallback behavior.
6. Verify that the project starts and the validator reports no errors.

Do not migrate `TurnManager`, production, or combat in the same change unless
the user explicitly broadens the task. Keeping the first slice isolated makes
the data model reviewable before runtime state depends on it.

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

