class_name BattleMapDef
extends Resource

@export var id: StringName
@export var scene: PackedScene
@export var environment: GameEnums.EnvironmentType = GameEnums.EnvironmentType.SPACE
@export var world_size_m: Vector2 = Vector2(1200, 900)
@export var attacker_spawn_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-400, 0, 0))
@export var defender_spawn_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(400, 0, 0))
@export var attacker_hq_id: StringName
@export var defender_hq_id: StringName
@export var control_point_ids: Array[StringName] = []
@export var terrain_zone_ids: Array[StringName] = []
@export var navigation_region_path: NodePath = NodePath("NavigationRegion3D")

