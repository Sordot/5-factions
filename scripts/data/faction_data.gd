class_name FactionData
extends Resource

## Single source of truth for a playable RTS faction:
## visual/audio identity, starting loadout, tech-tree rosters, AI profiles, and validation.

@export var faction_id: StringName = &"genesis_v2"
@export var display_name: String = "GENESIS_V2 — The Vat-Born"
@export var short_code: String = "GEN-V2"
@export_multiline var tagline: String = "Bio-synthetic clone swarms backed by Compute-forged heavy walkers."
@export var is_playable: bool = true
@export var primary_color: Color = Color(0.20, 0.96, 0.86, 1.0)
@export var accent_color: Color = Color(0.28, 0.98, 0.62, 1.0)
@export var hud_accent_color: Color = Color(0.20, 0.83, 0.60, 1.0)
@export var boot_banner_text: String = "// NEURAL LINK ONLINE — GENESIS_V2"
@export var audio_bark_pitch_bias: float = 1.0
@export var audio_timbre_profile: StringName = &"technozen_bio"

# Dossier & Radio Metadata (MainMenu & SkirmishAI)
@export var dossier_slot_number: int = 1
@export var dossier_subtitle: String = ""
@export_multiline var dossier_description: String = ""
@export var signature_badges: PackedStringArray = PackedStringArray()
@export var ai_transmissions: Dictionary = {}

# Starting Match Loadout
@export var starting_biomass: int = 200
@export var starting_silica: int = 50
@export var starting_compute: int = 0
@export var starting_worker_count: int = 3
@export var starting_hub_scene: PackedScene = null
@export var worker_scene: PackedScene = null
@export var harvester_scene: PackedScene = null
@export var engineer_scene: PackedScene = null
@export var extra_starting_units: Array[PackedScene] = []

# Tech-Tree & Roster Definitions
@export var building_roster: Array[BuildingData] = []
@export var unit_roster: Array[UnitData] = []
@export var upgrade_roster: Array[UpgradeData] = []

## Maps logical AI roles (&"hub", &"supply", &"barracks_t1", &"counter_foundry", &"heavy_t2", &"refinery", &"compute_hub")
## to building_id StringNames or BuildingData resource paths.
@export var ai_build_profile: Dictionary = {}
@export var ai_scout_unit_id: StringName = &"stinger"
@export var ai_salvage_unit_ids: Array[StringName] = [&"engineer", &"worker"]
@export var ai_counter_units: Dictionary = {}
@export var ai_playstyle_weights: Dictionary = {}

# Faction-specific resource saturation overrides (e.g., { &"silica": 1 })
@export var bonus_harvesters_by_resource: Dictionary = {}


func get_bonus_harvesters(res_type: StringName) -> int:
	if res_type == &"":
		return 0
	if bonus_harvesters_by_resource.has(res_type):
		return maxi(0, int(bonus_harvesters_by_resource[res_type]))
	var key_str: String = String(res_type)
	if bonus_harvesters_by_resource.has(key_str):
		return maxi(0, int(bonus_harvesters_by_resource[key_str]))
	return 0


func get_ai_transmission(category: StringName) -> String:
	if category == &"":
		return ""
	if ai_transmissions.has(category):
		return String(ai_transmissions[category])
	var key_str: String = String(category)
	if ai_transmissions.has(key_str):
		return String(ai_transmissions[key_str])
	return ""


func get_building_by_id(type_id: StringName) -> BuildingData:
	for b: BuildingData in building_roster:
		if b != null and b.building_id == type_id:
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


func get_unit_by_tag(tag: StringName) -> UnitData:
	for u: UnitData in unit_roster:
		if u != null and u.has_tag(tag):
			return u
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


func validate() -> Array[String]:
	var warnings: Array[String] = []
	var label: String = String(faction_id) if faction_id != &"" else display_name

	if faction_id == &"":
		warnings.append("[%s] faction_id is empty." % label)
	if starting_hub_scene == null:
		warnings.append("[%s] starting_hub_scene is null." % label)
	if worker_scene == null:
		warnings.append("[%s] worker_scene is null." % label)
	if building_roster.is_empty():
		warnings.append("[%s] building_roster is empty." % label)
	if unit_roster.is_empty():
		warnings.append("[%s] unit_roster is empty." % label)

	var b_ids: Dictionary = {}
	for b: BuildingData in building_roster:
		if b == null:
			warnings.append("[%s] null BuildingData entry in building_roster." % label)
			continue
		if b.building_id == &"":
			warnings.append("[%s] BuildingData '%s' has empty building_id." % [label, b.display_name])
		else:
			b_ids[b.building_id] = true
		if b.resolve_scene() == null:
			warnings.append("[%s] Building '%s' missing scene." % [label, String(b.building_id)])

	for b: BuildingData in building_roster:
		if b == null:
			continue
		for prereq: StringName in b.get_prerequisite_ids():
			if not b_ids.has(prereq):
				warnings.append("[%s] Building '%s' prerequisite '%s' not found in building_roster." % [label, String(b.building_id), String(prereq)])

	var u_ids: Dictionary = {}
	for u: UnitData in unit_roster:
		if u == null:
			warnings.append("[%s] null UnitData entry in unit_roster." % label)
			continue
		if u.unit_type_id == &"":
			warnings.append("[%s] UnitData '%s' has empty unit_type_id." % [label, u.display_name])
		else:
			u_ids[u.unit_type_id] = true
		if u.resolve_unit_scene() == null:
			warnings.append("[%s] Unit '%s' missing unit scene." % [label, String(u.unit_type_id)])

	for role: StringName in [&"hub", &"supply", &"refinery", &"compute_hub", &"barracks_t1"]:
		if get_ai_building_for_role(role) == null:
			warnings.append("[%s] ai_build_profile missing valid building for role '%s'." % [label, String(role)])

	if ai_scout_unit_id != &"" and not u_ids.has(ai_scout_unit_id):
		warnings.append("[%s] ai_scout_unit_id '%s' not found in unit_roster." % [label, String(ai_scout_unit_id)])

	for sid: StringName in ai_salvage_unit_ids:
		if sid != &"" and not u_ids.has(sid):
			warnings.append("[%s] ai_salvage_unit_ids entry '%s' not found in unit_roster." % [label, String(sid)])

	for posture: Variant in ai_counter_units.keys():
		var arr: Variant = ai_counter_units[posture]
		if arr is Array:
			for uid_v: Variant in arr:
				var uid: StringName = StringName(String(uid_v))
				if not u_ids.has(uid):
					warnings.append("[%s] ai_counter_units['%s'] references unknown unit '%s'." % [label, String(posture), String(uid)])

	return warnings
