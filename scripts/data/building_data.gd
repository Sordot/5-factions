class_name BuildingData
extends Resource

@export var building_id: StringName = &""
@export var display_name: String = "Building"
@export var scene: PackedScene = null
@export_file("*.tscn") var scene_path: String = ""
@export var biomass_cost: int = 0
@export var silica_cost: int = 0
@export var compute_cost: int = 0
@export var build_time: float = 4.0
@export var footprint_size: Vector2 = Vector2(72.0, 72.0)
@export var max_hp: float = 500.0
@export var vision_range: float = 420.0
@export var bandwidth_provided: int = 0
@export var is_dropoff: bool = false
@export var accepted_resources: Array[StringName] = []
@export var requires_vent: bool = false
@export var max_staff_slots: int = 0
@export var trainable_units: Array[UnitData] = []
@export var trainable_unit_paths: PackedStringArray = PackedStringArray()
@export var researchable_upgrades: Array[UpgradeData] = []
@export var can_set_rally: bool = true
@export var batch_production_count: int = 1
@export var base_batch_cost_multiplier: float = 1.0
@export var required_building_id: StringName = &""


func resolve_scene() -> PackedScene:
	if scene != null:
		return scene
	if not scene_path.is_empty():
		return load(scene_path) as PackedScene
	return null


func resolve_trainable_units() -> Array[UnitData]:
	var out: Array[UnitData] = []
	for u: UnitData in trainable_units:
		if u != null:
			out.append(u)
	for path: String in trainable_unit_paths:
		if not path.is_empty():
			var loaded: UnitData = load(path) as UnitData
			if loaded != null:
				out.append(loaded)
	return out


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
