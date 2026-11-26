class_name BuildingData
extends Resource

@export var building_id: StringName = &""
@export var display_name: String = "Building"
@export var short_display_name: String = ""
@export var hud_accent_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var scene: PackedScene = null
@export_file("*.tscn") var scene_path: String = ""
@export var biomass_cost: int = 0
@export var silica_cost: int = 0
@export var compute_cost: int = 0
@export var build_time: float = 4.0
@export var footprint_size: Vector2 = Vector2(72.0, 72.0)
@export var max_hp: float = 500.0
@export var max_shield: float = 0.0
@export var shield_regen_rate: float = 0.0
@export var shield_regen_delay: float = 7.0
@export var damage_reduction: float = 0.0
@export var vision_range: float = 420.0
@export var bandwidth_provided: int = 0
@export var is_dropoff: bool = false
@export var accepted_resources: Array[StringName] = []
@export var accepted_dropoff_resources: Array[StringName] = []
@export var requires_vent: bool = false
@export var max_staff_slots: int = 0
@export var trainable_units: Array[UnitData] = []
@export var trainable_unit_paths: PackedStringArray = PackedStringArray()
@export var researchable_upgrades: Array[UpgradeData] = []
@export var can_set_rally: bool = true
@export var batch_production_count: int = 1
@export var base_batch_cost_multiplier: float = 1.0
@export var required_building_id: StringName = &""
@export var prerequisite_building_ids: Array[StringName] = []
@export var is_core_hub: bool = false
@export var is_command_hub: bool = false
@export var is_military_production: bool = false
@export var is_supply_provider: bool = false
@export var tech_tier: int = 0 # 0 = Core/Econ, 1 = Tier 1 Production/Counter, 2 = Tier 2 Heavy/Elite
@export var audio_select_class: StringName = &"utility" # &"hub", &"production", &"tech", &"defense", &"utility"
@export var tech_tree_summary: String = ""

# Optional static defense / turret weapon parameters (disabled by default)
@export var has_turret: bool = false
@export var turret_damage: float = 0.0
@export var turret_attack_interval: float = 1.0
@export var turret_attack_range: float = 260.0
@export var turret_min_range: float = 0.0
@export var turret_splash_radius: float = 0.0
@export var turret_bonus_vs_armored: float = 1.0
@export var turret_tracer_style: StringName = &"pulse"
@export var turret_turn_speed: float = 7.0

# Optional Command Hub Core Overclock Ability (Milestone 3.0a)
@export var can_overclock_buildings: bool = false
@export var overclock_speed_multiplier: float = 2.0
@export var overclock_duration: float = 15.0
@export var overclock_cooldown: float = 50.0

# Optional Passive Shield Regen Aura (Milestone 3.0b — e.g. Capacitor Pylon)
@export var shield_regen_aura_radius: float = 0.0
@export var shield_regen_delay_speedup: float = 0.0

# Optional Consecrated Power Lattice (Milestone 3.9)
@export var provides_power_grid: bool = false
@export var power_radius: float = 0.0
@export var requires_power_grid: bool = false

# Optional Optical Tether Emitter (Milestone 3.9 — Harmonic Communion)
@export var tether_emit_radius: float = 0.0
@export var tether_max_links: int = 0
@export var tether_fire_rate_bonus: float = 0.0
@export var tether_range_bonus: float = 0.0
@export var tether_beam_ramp_bonus: float = 0.0


func get_short_name() -> String:
	return short_display_name if not short_display_name.is_empty() else display_name


func is_hub() -> bool:
	return is_command_hub or is_core_hub


func get_dropoff_resources() -> Array[StringName]:
	if not accepted_dropoff_resources.is_empty():
		return accepted_dropoff_resources
	return accepted_resources


func get_prerequisite_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for pid: StringName in prerequisite_building_ids:
		if pid != &"" and not out.has(pid):
			out.append(pid)
	if required_building_id != &"" and not out.has(required_building_id):
		out.append(required_building_id)
	return out


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
