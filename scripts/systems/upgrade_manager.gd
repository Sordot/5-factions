class_name UpgradeManager
extends RefCounted

const UPGRADE_BATCH_EFFICIENCY: StringName = &"batch_efficiency"
const UPGRADE_ADRENAL_POTENCY: StringName = &"adrenal_potency"
const UPGRADE_COMPUTE_OVERDRIVE: StringName = &"compute_overdrive"
const UPGRADE_HARDENED_PLATING: StringName = &"monolith_hardened_plating"
const UPGRADE_RAPID_CAPACITORS: StringName = &"monolith_rapid_capacitors"
const UPGRADE_HYPER_VELOCITY_RAILS: StringName = &"monolith_hyper_velocity_rails"

signal upgrade_completed(team: int, upgrade_id: StringName)

var researched_upgrades: Dictionary = {}
var _in_progress_upgrades: Dictionary = {}


func reset() -> void:
	researched_upgrades.clear()
	_in_progress_upgrades.clear()


func _ensure_team(team: int) -> void:
	if not researched_upgrades.has(team):
		var empty_done: Array[StringName] = []
		researched_upgrades[team] = empty_done
	if not _in_progress_upgrades.has(team):
		var empty_prog: Array[StringName] = []
		_in_progress_upgrades[team] = empty_prog


func has_upgrade(team: int, upgrade_id: StringName) -> bool:
	if upgrade_id == &"" or not researched_upgrades.has(team):
		return false
	var list: Array = researched_upgrades[team]
	return list.has(upgrade_id)


func is_upgrade_in_progress(team: int, upgrade_id: StringName) -> bool:
	if upgrade_id == &"" or not _in_progress_upgrades.has(team):
		return false
	var list: Array = _in_progress_upgrades[team]
	return list.has(upgrade_id)


func can_start_research(team: int, upgrade_id: StringName) -> bool:
	if upgrade_id == &"":
		return false
	return not has_upgrade(team, upgrade_id) and not is_upgrade_in_progress(team, upgrade_id)


func reserve_research(team: int, upgrade_id: StringName) -> void:
	if upgrade_id == &"":
		return
	_ensure_team(team)
	var prog: Array = _in_progress_upgrades[team]
	if not prog.has(upgrade_id):
		prog.append(upgrade_id)


func release_research(team: int, upgrade_id: StringName) -> void:
	if upgrade_id == &"" or not _in_progress_upgrades.has(team):
		return
	var prog: Array = _in_progress_upgrades[team]
	prog.erase(upgrade_id)


func complete_upgrade(team: int, upgrade_id: StringName) -> bool:
	if upgrade_id == &"":
		return false
	_ensure_team(team)
	var prog: Array = _in_progress_upgrades[team]
	prog.erase(upgrade_id)
	var done: Array = researched_upgrades[team]
	if done.has(upgrade_id):
		return false
	done.append(upgrade_id)
	upgrade_completed.emit(team, upgrade_id)
	return true


func get_researched_upgrades(team: int) -> Array[StringName]:
	var result: Array[StringName] = []
	if not researched_upgrades.has(team):
		return result
	for id: Variant in researched_upgrades[team]:
		result.append(id as StringName)
	return result


func get_batch_cost_multiplier(team: int, base_multiplier: float = 1.75) -> float:
	if has_upgrade(team, UPGRADE_BATCH_EFFICIENCY):
		return minf(base_multiplier, 1.50)
	return base_multiplier


func get_batch_time_multiplier(team: int) -> float:
	if has_upgrade(team, UPGRADE_BATCH_EFFICIENCY):
		return 0.90
	return 1.0


func get_adrenal_duration(team: int, base_duration: float = 4.0) -> float:
	if has_upgrade(team, UPGRADE_ADRENAL_POTENCY):
		return base_duration + 2.0
	return base_duration


func get_adrenal_attack_speed_bonus(team: int, base_bonus: float = 0.30) -> float:
	if has_upgrade(team, UPGRADE_ADRENAL_POTENCY):
		return base_bonus + 0.15
	return base_bonus


func get_goliath_speed_multiplier(team: int) -> float:
	if has_upgrade(team, UPGRADE_COMPUTE_OVERDRIVE):
		return 1.20
	return 1.0


func get_goliath_extra_damage_reduction(team: int) -> float:
	if has_upgrade(team, UPGRADE_COMPUTE_OVERDRIVE):
		return 0.15
	return 0.0


func get_bonus_armor(team: int) -> float:
	if has_upgrade(team, UPGRADE_HARDENED_PLATING):
		return 0.10
	return 0.0


func get_shield_regen_delay_multiplier(team: int) -> float:
	if has_upgrade(team, UPGRADE_RAPID_CAPACITORS):
		return 0.60
	return 1.0


func get_shield_regen_rate_multiplier(team: int) -> float:
	if has_upgrade(team, UPGRADE_RAPID_CAPACITORS):
		return 1.40
	return 1.0


func has_hyper_velocity_rails(team: int) -> bool:
	return has_upgrade(team, UPGRADE_HYPER_VELOCITY_RAILS)


func get_rail_damage_multiplier(team: int) -> float:
	if has_upgrade(team, UPGRADE_HYPER_VELOCITY_RAILS):
		return 1.20
	return 1.0


func get_rail_range_bonus(team: int) -> float:
	if has_upgrade(team, UPGRADE_HYPER_VELOCITY_RAILS):
		return 45.0
	return 0.0


## Data-driven modifier queries for FactionData.upgrade_roster (UpgradeData.modifier_key / modifier_value).
## Allows Faction #3+ upgrades to register numeric bonuses purely via .tres without hardcoding new getters.
func get_modifier_sum(team: int, modifier_key: StringName) -> float:
	if modifier_key == &"" or not researched_upgrades.has(team):
		return 0.0
	var done: Array = researched_upgrades[team]
	if done.is_empty() or TeamManager == null or not TeamManager.has_method("get_team_faction_data"):
		return 0.0
	var fdata: FactionData = TeamManager.get_team_faction_data(team)
	if fdata == null:
		return 0.0
	var total: float = 0.0
	for upg: UpgradeData in fdata.upgrade_roster:
		if upg != null and upg.modifier_key == modifier_key and done.has(upg.upgrade_id):
			total += upg.modifier_value
	return total


func get_modifier_product(team: int, modifier_key: StringName, default_value: float = 1.0) -> float:
	if modifier_key == &"" or not researched_upgrades.has(team):
		return default_value
	var done: Array = researched_upgrades[team]
	if done.is_empty() or TeamManager == null or not TeamManager.has_method("get_team_faction_data"):
		return default_value
	var fdata: FactionData = TeamManager.get_team_faction_data(team)
	if fdata == null:
		return default_value
	var result: float = default_value
	for upg: UpgradeData in fdata.upgrade_roster:
		if upg != null and upg.modifier_key == modifier_key and done.has(upg.upgrade_id):
			result *= upg.modifier_value
	return result


func has_modifier(team: int, modifier_key: StringName) -> bool:
	if modifier_key == &"" or not researched_upgrades.has(team):
		return false
	var done: Array = researched_upgrades[team]
	if done.is_empty() or TeamManager == null or not TeamManager.has_method("get_team_faction_data"):
		return false
	var fdata: FactionData = TeamManager.get_team_faction_data(team)
	if fdata == null:
		return false
	for upg: UpgradeData in fdata.upgrade_roster:
		if upg != null and upg.modifier_key == modifier_key and done.has(upg.upgrade_id):
			return true
	return false
