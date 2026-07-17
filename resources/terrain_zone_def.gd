class_name TerrainZoneDef
extends Resource
## COMBAT_DETAIL_SPECIFICATION.md section 29 / DATA_DEFINITION.md section
## 19.2. A zone is a simple circle (center + radius) rather than the spec's
## area_node_path-driven Area3D shape: there is no battle-map scene geometry
## to attach a real Area3D to, and BattleControlPointDef already proves plain
## distance checks are how "a region of the battlefield" works in this
## codebase (capture/sensor radius, no physics queries). `position` follows
## BattleControlPointDef's own convention -- real ground-plane x/z, matching
## the 3D scene and how BattleSquadState.world_position maps its y component
## to world Z (see BattleRuntimeFactory._build_side's spawn placement and
## BattlePrototypeView._build_squad_visuals).

@export var id: StringName
@export var effect: GameEnums.TerrainEffect = GameEnums.TerrainEffect.NORMAL
@export var position: Vector3 = Vector3.ZERO
@export var radius_m: float = 100.0
## COMBAT_DETAIL_SPECIFICATION.md 29.1: difficult terrain multiplies move
## speed by 0.8; every other effect leaves it at 1.0.
@export var move_multiplier: float = 1.0
## 29.2: cover adds 15 to the defender's evasion bonus against non-melee
## attacks; every other effect leaves it at 0.
@export var evasion_add: int = 0
## 29.3: hazardous terrain drains this fraction of a unit's max HP per
## second; every other effect leaves it at 0.
@export var hazard_hp_pct_per_sec: float = 0.0
## Large-obstacle sensor line-of-sight blocking (DATA_DEFINITION.md 19.2);
## independent of `effect` so any zone type could in principle also block
## sensors, though in practice only IMPASSABLE zones are expected to set it.
@export var blocks_sensor_los: bool = false
