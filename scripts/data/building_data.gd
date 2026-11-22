class_name BuildingData
extends Resource

@export var building_id: StringName = &""
@export var display_name: String = "Building"
@export var scene: PackedScene
@export var biomass_cost: int = 0
@export var silica_cost: int = 0
@export var compute_cost: int = 0
@export var build_time: float = 4.0
@export var footprint_size: Vector2 = Vector2(72.0, 72.0)
@export var max_hp: float = 500.0
@export var bandwidth_provided: int = 0
@export var is_dropoff: bool = false
@export var accepted_resources: Array[StringName] = []
@export var requires_vent: bool = false
@export var max_staff_slots: int = 0


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


func get_footprint_radius() -> float:
	return maxf(footprint_size.x, footprint_size.y) * 0.5
