class_name UnitDef
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
@export var faction_origin_id: StringName
@export var size: GameEnums.UnitSize = GameEnums.UnitSize.STANDARD
@export var role: GameEnums.UnitRole = GameEnums.UnitRole.ATTACK
@export var icon: Texture2D
@export var model_scene: PackedScene
@export var vignette_sprite: Texture2D
@export var max_hp: int = 1500
@export var max_en: int = 300
@export var firepower: int = 100
@export var armor: int = 100
@export var speed: int = 100
@export var evasion: int = 10
@export var ground_aptitude: GameEnums.EnvironmentAptitude = GameEnums.EnvironmentAptitude.STANDARD
@export var space_aptitude: GameEnums.EnvironmentAptitude = GameEnums.EnvironmentAptitude.STANDARD
@export var moon_aptitude: GameEnums.EnvironmentAptitude = GameEnums.EnvironmentAptitude.STANDARD
@export var ballistic_damage_multiplier: float = 1.0
@export var beam_damage_multiplier: float = 1.0
@export var melee_damage_multiplier: float = 1.0
@export var weapon_ids: Array[StringName] = []
@export var support_skill_ids: Array[StringName] = []
@export var sensor_range_m: float = GameConstants.NORMAL_SENSOR_RANGE_M
@export var sensor_ignores_obstacles: bool = false
@export var capture_allowed: bool = true
@export var power_adjustment: float = 1.0
@export var tech_id: StringName
