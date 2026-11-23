class_name EconomyManager
extends Node

const RESOURCE_BIOMASS: StringName = &"biomass"
const RESOURCE_SILICA: StringName = &"silica"
const RESOURCE_COMPUTE: StringName = &"compute"

signal resources_changed(team: int, resources: Dictionary)
signal bandwidth_changed(team: int, used: int, cap: int)
signal production_bonus_changed(team: int, multiplier: float)
signal upgrade_completed(team: int, upgrade_id: StringName)
signal tech_changed(team: int)

@export var starting_biomass: int = 50
@export var starting_silica: int = 0
@export var starting_compute: int = 0
@export var enemy_matches_starting_resources: bool = true

var upgrade_manager: UpgradeManager = UpgradeManager.new()

var _resources: Dictionary = {}
var _bandwidth_used: Dictionary = {}
var _bandwidth_reserved: Dictionary = {}
var _bandwidth_cap: Dictionary = {}
var _bandwidth_providers: Dictionary = {}
var _bandwidth_units: Dictionary = {}
var _uplink_controller: int = -1
var _uplink_bonus_pct: float = 0.05


func _ready() -> void:
	add_to_group("economy_manager")
	if not upgrade_manager.upgrade_completed.is_connected(_on_upgrade_manager_completed):
		upgrade_manager.upgrade_completed.connect(_on_upgrade_manager_completed)
	_init_team_state(Unit.Team.PLAYER, starting_biomass, starting_silica, starting_compute)
	if enemy_matches_starting_resources:
		_init_team_state(Unit.Team.ENEMY, starting_biomass, starting_silica, starting_compute)
	else:
		_init_team_state(Unit.Team.ENEMY, 0, 0, 0)
	call_deferred("_sync_initial_scene_state")


func _sync_initial_scene_state() -> void:
	recalculate_bandwidth(Unit.Team.PLAYER)
	recalculate_bandwidth(Unit.Team.ENEMY)
	resources_changed.emit(Unit.Team.PLAYER, get_resources(Unit.Team.PLAYER))
	resources_changed.emit(Unit.Team.ENEMY, get_resources(Unit.Team.ENEMY))


func _init_team_state(team: int, biomass: int, silica: int, compute: int) -> void:
	_resources[team] = {
		RESOURCE_BIOMASS: biomass,
		RESOURCE_SILICA: silica,
		RESOURCE_COMPUTE: compute,
	}
	if not _bandwidth_used.has(team):
		_bandwidth_used[team] = 0
	if not _bandwidth_reserved.has(team):
		_bandwidth_reserved[team] = 0
	if not _bandwidth_cap.has(team):
		_bandwidth_cap[team] = 0


func _ensure_team(team: int) -> void:
	if not _resources.has(team):
		_init_team_state(team, 0, 0, 0)


func reset_economy() -> void:
	_resources[Unit.Team.PLAYER] = {
		RESOURCE_BIOMASS: starting_biomass,
		RESOURCE_SILICA: starting_silica,
		RESOURCE_COMPUTE: starting_compute,
	}
	_resources[Unit.Team.ENEMY] = {
		RESOURCE_BIOMASS: starting_biomass if enemy_matches_starting_resources else 0,
		RESOURCE_SILICA: starting_silica if enemy_matches_starting_resources else 0,
		RESOURCE_COMPUTE: starting_compute if enemy_matches_starting_resources else 0,
	}
	_bandwidth_reserved[Unit.Team.PLAYER] = 0
	_bandwidth_reserved[Unit.Team.ENEMY] = 0
	upgrade_manager.reset()
	set_uplink_controller(-1, _uplink_bonus_pct)
	recalculate_bandwidth(Unit.Team.PLAYER)
	recalculate_bandwidth(Unit.Team.ENEMY)
	resources_changed.emit(Unit.Team.PLAYER, get_resources(Unit.Team.PLAYER))
	resources_changed.emit(Unit.Team.ENEMY, get_resources(Unit.Team.ENEMY))
	tech_changed.emit(Unit.Team.PLAYER)
	tech_changed.emit(Unit.Team.ENEMY)


func add_resource(team: int, resource_type: StringName, amount: int) -> void:
	if amount <= 0:
		return
	_ensure_team(team)
	var team_res: Dictionary = _resources[team]
	team_res[resource_type] = int(team_res.get(resource_type, 0)) + amount
	resources_changed.emit(team, get_resources(team))


func get_resource(team: int, resource_type: StringName) -> int:
	if not _resources.has(team):
		return 0
	var team_res: Dictionary = _resources[team]
	return int(team_res.get(resource_type, 0))


func get_resources(team: int) -> Dictionary:
	_ensure_team(team)
	var team_res: Dictionary = _resources[team]
	return team_res.duplicate()


func can_afford(team: int, costs: Dictionary) -> bool:
	_ensure_team(team)
	var team_res: Dictionary = _resources[team]
	for res_key: Variant in costs.keys():
		var cost_amount: int = int(costs[res_key])
		if cost_amount <= 0:
			continue
		if int(team_res.get(res_key, 0)) < cost_amount:
			return false
	return true


func spend_resources(team: int, costs: Dictionary) -> bool:
	if not can_afford(team, costs):
		return false
	var team_res: Dictionary = _resources[team]
	for res_key: Variant in costs.keys():
		var cost_amount: int = int(costs[res_key])
		if cost_amount <= 0:
			continue
		team_res[res_key] = maxi(0, int(team_res.get(res_key, 0)) - cost_amount)
	resources_changed.emit(team, get_resources(team))
	return true


func register_bandwidth_provider(provider: Node, team: int, amount: int) -> void:
	if provider == null or amount <= 0:
		return
	_ensure_team(team)
	var provider_id: int = provider.get_instance_id()
	if _bandwidth_providers.has(provider_id):
		var prev: Dictionary = _bandwidth_providers[provider_id]
		if int(prev["team"]) == team and int(prev["amount"]) == amount:
			return
	_bandwidth_providers[provider_id] = {
		"node": provider,
		"team": team,
		"amount": amount,
	}
	recalculate_bandwidth(team)


func unregister_bandwidth_provider(provider: Node) -> void:
	if provider == null:
		return
	var provider_id: int = provider.get_instance_id()
	if not _bandwidth_providers.has(provider_id):
		return
	var entry: Dictionary = _bandwidth_providers[provider_id]
	var team: int = int(entry["team"])
	_bandwidth_providers.erase(provider_id)
	recalculate_bandwidth(team, provider)


func register_unit_bandwidth(unit: Node, team: int, cost: int = 1) -> void:
	if unit == null or cost <= 0:
		return
	_ensure_team(team)
	var unit_id: int = unit.get_instance_id()
	_bandwidth_units[unit_id] = {
		"node": unit,
		"team": team,
		"cost": cost,
	}
	recalculate_bandwidth(team)


func unregister_unit_bandwidth(unit: Node) -> void:
	if unit == null:
		return
	var unit_id: int = unit.get_instance_id()
	if not _bandwidth_units.has(unit_id):
		return
	var entry: Dictionary = _bandwidth_units[unit_id]
	var team: int = int(entry["team"])
	_bandwidth_units.erase(unit_id)
	recalculate_bandwidth(team, unit)


func update_bandwidth_used(team: int, used: int) -> void:
	_ensure_team(team)
	var clamped_used: int = maxi(0, used)
	if int(_bandwidth_used.get(team, 0)) == clamped_used:
		return
	_bandwidth_used[team] = clamped_used
	bandwidth_changed.emit(team, clamped_used, get_bandwidth_cap(team))


func reserve_bandwidth(team: int, amount: int) -> void:
	if amount <= 0:
		return
	_ensure_team(team)
	_bandwidth_reserved[team] = int(_bandwidth_reserved.get(team, 0)) + amount
	recalculate_bandwidth(team)


func release_bandwidth(team: int, amount: int) -> void:
	if amount <= 0:
		return
	_ensure_team(team)
	_bandwidth_reserved[team] = maxi(0, int(_bandwidth_reserved.get(team, 0)) - amount)
	recalculate_bandwidth(team)


func set_uplink_controller(team: int, bonus_pct: float = 0.05) -> void:
	_uplink_controller = team
	_uplink_bonus_pct = maxf(0.0, bonus_pct)
	production_bonus_changed.emit(Unit.Team.PLAYER, get_production_speed_multiplier(Unit.Team.PLAYER))
	production_bonus_changed.emit(Unit.Team.ENEMY, get_production_speed_multiplier(Unit.Team.ENEMY))


func get_production_speed_multiplier(team: int) -> float:
	if _uplink_controller == team:
		return 1.0 + _uplink_bonus_pct
	return 1.0


func get_bandwidth_used(team: int) -> int:
	return int(_bandwidth_used.get(team, 0))


func get_bandwidth_cap(team: int) -> int:
	return int(_bandwidth_cap.get(team, 0))


func has_bandwidth(team: int, cost: int = 1) -> bool:
	if cost <= 0:
		return true
	return get_bandwidth_used(team) + cost <= get_bandwidth_cap(team)


func recalculate_bandwidth(team: int, excluded_node: Node = null) -> void:
	_ensure_team(team)
	var used: int = 0
	var cap: int = 0

	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group("units"):
			if node == excluded_node or not is_instance_valid(node) or not (node is Unit):
				continue
			var unit: Unit = node
			if unit.is_dead or unit.is_queued_for_deletion() or unit.team != team:
				continue
			var cost: int = unit.data.bandwidth_cost if unit.data != null else 1
			used += maxi(0, cost)

		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if node == excluded_node or not is_instance_valid(node) or not (node is Building):
				continue
			var building: Building = node
			if building.is_destroyed or building.is_queued_for_deletion() or not building.is_constructed or building.team != team:
				continue
			cap += maxi(0, building.bandwidth_provided)
	else:
		for provider_id: Variant in _bandwidth_providers.keys():
			var p_entry: Dictionary = _bandwidth_providers[provider_id]
			if p_entry["node"] != excluded_node and int(p_entry["team"]) == team and is_instance_valid(p_entry["node"]):
				cap += int(p_entry["amount"])
		for unit_id: Variant in _bandwidth_units.keys():
			var u_entry: Dictionary = _bandwidth_units[unit_id]
			if u_entry["node"] != excluded_node and int(u_entry["team"]) == team and is_instance_valid(u_entry["node"]):
				used += int(u_entry["cost"])

	var reserved: int = maxi(0, int(_bandwidth_reserved.get(team, 0)))
	_bandwidth_used[team] = used + reserved
	_bandwidth_cap[team] = cap
	bandwidth_changed.emit(team, _bandwidth_used[team], cap)


func _on_upgrade_manager_completed(team: int, upgrade_id: StringName) -> void:
	upgrade_completed.emit(team, upgrade_id)
	tech_changed.emit(team)
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group("units"):
			if node is Unit and is_instance_valid(node):
				var u: Unit = node
				if not u.is_dead and u.team == team and u.has_method("on_team_upgrade_completed"):
					u.on_team_upgrade_completed(upgrade_id)


func notify_building_tech_changed(team: int) -> void:
	tech_changed.emit(team)


func has_constructed_building(team: int, required_building_id: StringName) -> bool:
	if required_building_id == &"":
		return true
	if not is_inside_tree():
		return false
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or not b.is_constructed or b.team != team:
			continue
		if b.building_type_id == required_building_id:
			return true
		if required_building_id == &"nexus_vat" and b.building_type_id == &"command_core":
			return true
	return false


func has_upgrade(team: int, upgrade_id: StringName) -> bool:
	return upgrade_manager.has_upgrade(team, upgrade_id)


func is_upgrade_in_progress(team: int, upgrade_id: StringName) -> bool:
	return upgrade_manager.is_upgrade_in_progress(team, upgrade_id)


func can_start_upgrade(team: int, upgrade: UpgradeData) -> bool:
	if upgrade == null:
		return false
	return upgrade_manager.can_start_research(team, upgrade.upgrade_id)


func reserve_upgrade_research(team: int, upgrade_id: StringName) -> void:
	upgrade_manager.reserve_research(team, upgrade_id)
	tech_changed.emit(team)


func release_upgrade_research(team: int, upgrade_id: StringName) -> void:
	upgrade_manager.release_research(team, upgrade_id)
	tech_changed.emit(team)


func complete_upgrade(team: int, upgrade_id: StringName) -> bool:
	return upgrade_manager.complete_upgrade(team, upgrade_id)


func get_batch_cost_multiplier(team: int, base_multiplier: float = 1.75) -> float:
	return upgrade_manager.get_batch_cost_multiplier(team, base_multiplier)


func get_batch_time_multiplier(team: int) -> float:
	return upgrade_manager.get_batch_time_multiplier(team)


func get_adrenal_duration(team: int, base_duration: float = 4.0) -> float:
	return upgrade_manager.get_adrenal_duration(team, base_duration)


func get_adrenal_attack_speed_bonus(team: int, base_bonus: float = 0.30) -> float:
	return upgrade_manager.get_adrenal_attack_speed_bonus(team, base_bonus)


func get_goliath_speed_multiplier(team: int) -> float:
	return upgrade_manager.get_goliath_speed_multiplier(team)


func get_goliath_extra_damage_reduction(team: int) -> float:
	return upgrade_manager.get_goliath_extra_damage_reduction(team)
