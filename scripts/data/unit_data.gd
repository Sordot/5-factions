class_name UnitData
extends Resource

@export var unit_type_id: StringName = &"clone_trooper"
@export var display_name: String = "Clone Trooper"
@export var short_display_name: String = ""
@export var max_hp: float = 100.0
@export var max_shield: float = 0.0
@export var shield_regen_rate: float = 0.0
@export var shield_regen_delay: float = 6.0
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
@export var attack_windup: float = -1.0 # < 0 uses role default (infantry 0.06s, heavy 0.11s, siege/beam 0.15s)
@export var is_armored: bool = false
@export var unit_tags: Array[StringName] = []
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
@export var salvage_silica: int = 0
@export var salvage_compute: int = 0
@export var build_time: float = 3.0
@export var train_time: float = 4.0
@export_file("*.tscn") var unit_scene_path: String = ""
@export var unit_scene: PackedScene = null

# Data-driven Weapon, VFX, Audio & UI Profile (Milestone 2.8)
@export var weapon_tracer_style: StringName = &"pulse" # &"pulse", &"rail", &"mortar", &"arc", &"bio", &"heavy"
@export var weapon_tracer_color: Color = Color(0.22, 0.74, 0.97, 1.0)
@export var weapon_tracer_width: float = 2.4
@export var weapon_sfx_id: StringName = &"weapon_rifle"
@export var audio_bark_class: StringName = &"swarm" # &"worker", &"swarm", &"counter", &"support", &"heavy"
@export var minimap_icon_shape: StringName = &"dot" # &"dot", &"worker", &"triangle_heavy"
@export var role_tags_display: String = ""
@export var can_fire_while_moving: bool = false
@export var splash_inner_radius_ratio: float = 0.35
@export var splash_edge_damage_ratio: float = 0.45

# Optional Deploy / Anchor Stance Overrides (Milestone 3.0a)
@export var can_deploy: bool = false
@export var deploy_duration: float = 1.2
@export var deployed_attack_damage: float = 0.0
@export var deployed_attack_range: float = 0.0
@export var deployed_min_attack_range: float = 0.0
@export var deployed_attack_cooldown: float = 0.0
@export var deployed_aoe_radius: float = 0.0
@export var deployed_damage_reduction_bonus: float = 0.0
@export var deployed_weapon_tracer_style: StringName = &""

# Optional Optical Tether Emitter (Milestone 3.9 — Harmonic Communion)
@export var tether_emit_radius: float = 0.0
@export var tether_max_links: int = 0
@export var tether_fire_rate_bonus: float = 0.0
@export var tether_range_bonus: float = 0.0
@export var tether_beam_ramp_bonus: float = 0.0

# Optional Escalating Continuous Beam & Refracting Split-Beam (Milestone 3.9)
@export var is_continuous_beam: bool = false
@export var beam_ramp_max_multiplier: float = 1.0
@export var beam_ramp_duration: float = 3.0
@export var beam_ramp_decay_delay: float = 0.45
@export var beam_ramp_decay_rate: float = 1.6
@export var refract_max_bounces: int = 0
@export var refract_radius: float = 0.0
@export var refract_damage_ratio: float = 0.50


func get_short_name() -> String:
	return short_display_name if not short_display_name.is_empty() else display_name


func has_tag(tag: StringName) -> bool:
	return tag != &"" and unit_tags.has(tag)


func is_worker_class() -> bool:
	return can_gather or can_staff_compute or has_tag(&"worker") or has_tag(&"harvester") or has_tag(&"engineer")


func is_combat_unit() -> bool:
	if is_worker_class() or has_tag(&"dummy"):
		return false
	return attack_damage > 0.0 or has_tag(&"support")


func is_heavy_unit() -> bool:
	return has_tag(&"heavy")


func is_synthetic_repairable() -> bool:
	return has_tag(&"synthetic") or has_tag(&"heavy") or has_tag(&"mechanical")


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
