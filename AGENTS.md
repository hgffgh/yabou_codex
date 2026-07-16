# AGENTS.md

## Project overview

This repository contains a Godot 4.7 prototype and the specifications for
`ORBITAL DOMINION` (working title), a single-player PC strategy game combining
a turn-based campaign with squad-based real-time battles.

The current Godot implementation predates the detailed specifications. Treat
the specification documents as the intended product design. Do not assume the
existing simplified runtime model is the final architecture.

## Required reading

Before changing gameplay code or data structures, read the relevant documents:

1. `HANDOFF.md` — current state, known gaps, and the next implementation task.
2. `GAME_SPECIFICATION.md` — high-level product rules.
3. `DATA_DEFINITION.md` — authoritative data architecture and migration order.
4. The detailed specification for the system being changed:
   - `COMBAT_DETAIL_SPECIFICATION.md`
   - `STRATEGY_DETAIL_SPECIFICATION.md`
   - `UNIT_DETAIL_SPECIFICATION.md`
   - `EVENT_DETAIL_SPECIFICATION.md`
   - `SYSTEM_DETAIL_SPECIFICATION.md`

If code and a specification disagree, report the mismatch before silently
changing the specification. Implement the specification unless the user asks
to revise it.

## Technical baseline

- Engine: Godot 4.7
- Language: GDScript
- Renderer: GL Compatibility
- Main scene: `res://scenes/main_menu/main_menu.tscn`
- Static game data: Godot Resources under `res://data/`
- Current global state: `autoload/game_state.gd`
- Current turn flow: `autoload/turn_manager.gd`

## Implementation rules

- Preserve stable master-data IDs. Use lowercase `snake_case` `StringName` IDs.
- Store references in save data by ID, not by Resource object reference.
- Keep immutable master data separate from mutable campaign state.
- New unit runtime logic must support individual HP, EN, pilot assignment, and
  membership in a maximum-five-unit squad.
- An empty pilot ID means an automatically supplied generic pilot. Do not create
  runtime records for generic pilots.
- Avoid extending `UnitStack` as the final solution. It stores counts by unit
  type and cannot represent the specified individual-unit state.
- Avoid extending the current ratio-based `CombatResolver` as the final RTS
  implementation. It is prototype code.
- Add validation for new Resource types and cross-resource IDs.
- Keep deterministic behavior reproducible from saved random state.
- Do not add persistent status effects; the design explicitly excludes them.
- Do not introduce online multiplayer, pilot permadeath, or player-editable
  weapon loadouts without a specification change.

## Change discipline

- Prefer small, reviewable migrations over a full rewrite.
- Keep the project runnable after each migration step.
- Preserve unrelated user changes in a dirty worktree.
- Update `HANDOFF.md` when a milestone is completed or the next task changes.
- Update the relevant specification when the user changes a confirmed rule.
- Add or update data validation whenever a new master-data field is introduced.
- Verify changed GDScript by opening/running the project or using the available
  Godot command-line checks when possible.

## Immediate implementation sequence

Unless the user selects another task, proceed in this order:

1. Add shared enums/constants and the master-data registry.
2. Add new Resource classes for units, weapons, pilots, skills, and campaign
   settings without deleting the old prototype classes.
3. Add a startup data validator.
4. Add `UnitInstanceState` and `SquadState`.
5. Create a small test dataset.
6. Migrate production and strategic movement from `UnitStack` to individual
   units and squads.
7. Implement the minimum RTS battle prototype only after the new data layer is
   stable.

## Completion checks

Before handing off a change:

- Confirm the project still starts.
- Confirm all master IDs are unique and referenced IDs resolve.
- Confirm no generated Godot cache files are committed.
- Run `git diff --check`.
- Summarize files changed, verification performed, and remaining specification
  gaps.

