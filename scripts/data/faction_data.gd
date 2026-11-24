class_name FactionData
extends Resource

@export var faction_id: StringName = &"genesis_v2"
@export var display_name: String = "GENESIS_V2 — The Vat-Born"
@export_multiline var tagline: String = "Bio-synthetic clone swarms backed by Compute-forged heavy walkers."
@export var is_playable: bool = true
@export var primary_color: Color = Color(0.20, 0.96, 0.86, 1.0)
@export var accent_color: Color = Color(0.28, 0.98, 0.62, 1.0)

@export var starting_hub_scene: PackedScene = null
@export var worker_scene: PackedScene = null
@export var harvester_scene: PackedScene = null
@export var engineer_scene: PackedScene = null

@export var building_roster: Array[BuildingData] = []
@export var unit_roster: Array[UnitData] = []
@export var upgrade_roster: Array[UpgradeData] = []

## Maps logical AI roles (&"hub", &"supply", &"barracks_t1", &"counter_foundry", &"heavy_t2", &"refinery", &"compute_hub")
## to building_type_id StringNames or BuildingData resource paths.
@export var ai_build_profile: Dictionary = {}


func get_building_by_id(type_id: StringName) -> BuildingData:
	for b: BuildingData in building_roster:
		if b != null and b.building_type_id == type_id:
			return b
	return null


func get_unit_by_id(type_id: StringName) -> UnitData:
	for u: UnitData in unit_roster:
		if u != null and u.unit_type_id == type_id:
			return u
	return null


func get_upgrade_by_id(upgrade_id: StringName) -> UpgradeData:
	for upg: UpgradeData in upgrade_roster:
		if upg != null and upg.upgrade_id == upgrade_id:
			return upg
	return null


func get_ai_building_for_role(role: StringName) -> BuildingData:
	if ai_build_profile.has(role):
		var val: Variant = ai_build_profile[role]
		if val is BuildingData:
			return val as BuildingData
		if val is StringName:
			return get_building_by_id(val as StringName)
		if val is String:
			var s: String = val as String
			if s.begins_with("res://"):
				return load(s) as BuildingData
			return get_building_by_id(StringName(s))
	return null
