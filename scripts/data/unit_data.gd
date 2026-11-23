class_name UnitData
extends Resource

@export var unit_type_id: StringName = &"clone_trooper"
@export var display_name: String = "Clone Trooper"
@export var max_hp: float = 100.0
@export var move_speed: float = 260.0
@export var acceleration: float = 1800.0
@export var turn_speed: float = 14.0
@export var selection_radius: float = 20.0
@export var collision_radius: float = 16.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 180.0
@export var min_attack_range: float = 0.0
@export var aoe_attack_radius: float = 0.0
@export var line_pierce_width: float = 0.0
@export var aggro_range: float = 280.0
@export var vision_range: float = 360.0
@export var attack_cooldown: float = 0.7
@export var is_armored: bool = false
@export var bonus_vs_armored: float = 0.0
@export var damage_reduction: float = 0.0
@export var ignore_friendly_unit_collision: bool = false
@export var heal_aura_rate: float = 0.0
@export var heal_aura_radius: float = 0.0
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
@export var biomass_cost: int = 50
@export var silica_cost: int = 0
@export var compute_cost: int = 0
@export var build_time: float = 3.0
@export var train_time: float = 4.0
@export_file("*.tscn") var unit_scene_path: String = ""
@export var unit_scene: PackedScene = null


func resolve_unit_scene() -> PackedScene:
	if unit_scene != null:
		return unit_scene
	if not unit_scene_path.is_empty():
		return load(unit_scene_path) as PackedScene
	return null


func get_cost_dict() -> Dictionary:
	return get_scaled_cost_dict(1.0)


func get_scaled_cost_dict(multiplier: float) -> Dictionary:
	var costs: Dictionary = {}
	var mult: float = maxf(0.0, multiplier)
	if biomass_cost > 0:
		costs[EconomyManager.RESOURCE_BIOMASS] = int(floor(float(biomass_cost) * mult + 0.5))
	if silica_cost > 0:
		costs[EconomyManager.RESOURCE_SILICA] = int(floor(float(silica_cost) * mult + 0.5))
	if compute_cost > 0:
		costs[EconomyManager.RESOURCE_COMPUTE] = int(floor(float(compute_cost) * mult + 0.5))
	return costs


func get_cost_label() -> String:
	return get_scaled_cost_label(1.0)


func get_scaled_cost_label(multiplier: float) -> String:
	var costs: Dictionary = get_scaled_cost_dict(multiplier)
	var parts: PackedStringArray = PackedStringArray()
	var b: int = int(costs.get(EconomyManager.RESOURCE_BIOMASS, 0))
	var s: int = int(costs.get(EconomyManager.RESOURCE_SILICA, 0))
	var c: int = int(costs.get(EconomyManager.RESOURCE_COMPUTE, 0))
	if b > 0:
		parts.append("%dB" % b)
	if s > 0:
		parts.append("%dS" % s)
	if c > 0:
		parts.append("%dC" % c)
	return " / ".join(parts) if not parts.is_empty() else "Free"
