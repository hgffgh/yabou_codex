class_name FacilityDef
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var facility_type: GameEnums.FacilityType = GameEnums.FacilityType.ECONOMY
@export var funds_income: int = 0
@export var materials_income: int = 0
@export var production_power: int = 0
@export var research_discount_pct: float = 0.0
