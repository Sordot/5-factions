class_name UnitData
extends Resource

@export var unit_type_id: StringName = &"test_unit"
@export var display_name: String = "Test Unit"
@export var max_hp: float = 100.0
@export var move_speed: float = 260.0
@export var acceleration: float = 1800.0
@export var turn_speed: float = 14.0
@export var selection_radius: float = 20.0
@export var collision_radius: float = 16.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 180.0
@export var aggro_range: float = 280.0
@export var attack_cooldown: float = 0.7
@export var abilities: Array[AbilityData] = []
@export var bandwidth_cost: int = 1
@export var can_gather: bool = false
@export var gather_duration: float = 3.0
@export var carry_capacity: int = 10
@export var gather_range: float = 48.0
@export var dropoff_range: float = 64.0
@export var allowed_resource: StringName = &"biomass"
@export var auto_gather_on_spawn: bool = false
@export var can_staff_compute: bool = false
@export var biomass_cost: int = 0
@export var silica_cost: int = 0
@export var compute_cost: int = 0
@export var build_time: float = 3.0


func get_cost_dict() -> Dictionary:
	var costs: Dictionary = {}
	if biomass_cost > 0:
		costs[EconomyManager.RESOURCE_BIOMASS] = biomass_cost
	if silica_cost > 0:
		costs[EconomyManager.RESOURCE_SILICA] = silica_cost
	if compute_cost > 0:
		costs[EconomyManager.RESOURCE_COMPUTE] = compute_cost
	return costs


func get_cost_label() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if biomass_cost > 0:
		parts.append("%dB" % biomass_cost)
	if silica_cost > 0:
		parts.append("%dS" % silica_cost)
	if compute_cost > 0:
		parts.append("%dC" % compute_cost)
	return " / ".join(parts) if not parts.is_empty() else "Free"
