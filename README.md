# ORBITAL DOMINION (working title)

A Godot 4.7 prototype for a single-player PC strategy game combining a
turn-based Earth-sphere campaign with squad-based real-time battles.

The current codebase is an early strategy prototype. The intended product rules
and target architecture are documented in the specification files at the
repository root.

## Requirements

- Godot 4.7
- Git or GitHub Desktop
- A desktop environment capable of the Godot GL Compatibility renderer

Character voices are not part of the current design. GodotSteam is included,
but Steam initialization is disabled by default in `project.godot`.

## Getting started

### GitHub Desktop

1. Sign in to GitHub Desktop.
2. Clone `hgffgh/yabou_codex`.
3. Open Godot 4.7.
4. Import the cloned `project.godot`.
5. Run the project.

### Command line

```bash
git clone https://github.com/hgffgh/yabou_codex.git
cd yabou_codex
```

Then import `project.godot` in Godot 4.7.

Godot regenerates `.godot/` and imported-resource caches locally. These files
are intentionally not stored in Git.

## Project entry points

- Main scene: `scenes/main_menu/main_menu.tscn`
- Global game state: `autoload/game_state.gd`
- Turn flow: `autoload/turn_manager.gd`
- Static data: `data/`
- Resource classes: `resources/`

## Documentation

| Document | Purpose |
| --- | --- |
| `AGENTS.md` | Instructions for coding agents working in this repository |
| `HANDOFF.md` | Current progress, architecture gap, and next task |
| `GAME_SPECIFICATION.md` | High-level game design |
| `DATA_DEFINITION.md` | Target data model and migration plan |
| `COMBAT_DETAIL_SPECIFICATION.md` | Real-time battle rules |
| `STRATEGY_DETAIL_SPECIFICATION.md` | Campaign, economy, production, research, and diplomacy |
| `UNIT_DETAIL_SPECIFICATION.md` | Unit and weapon numeric ranges |
| `EVENT_DETAIL_SPECIFICATION.md` | Narrative and event system |
| `SYSTEM_DETAIL_SPECIFICATION.md` | Save, difficulty, AI, input, UI, and achievements |

New contributors and agents should read `HANDOFF.md` before making gameplay or
architecture changes.

## Cross-device workflow

Before switching devices:

```bash
git status
git add <changed-files>
git commit -m "Describe the change"
git push
```

On the other device:

```bash
git pull --ff-only
```

Do not commit `.godot/`, `.import/`, `.DS_Store`, `steam_appid.txt`, or local
export configuration files.

## Current next step

Implement the new data foundation described in `DATA_DEFINITION.md`:

1. shared enums and constants,
2. new Resource definitions,
3. a typed master-data registry,
4. startup data validation,
5. a minimal test dataset.

See `HANDOFF.md` for the exact scope and constraints.

