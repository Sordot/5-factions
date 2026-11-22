class_name EconomyManager
extends Node

const RESOURCE_BIOMASS: StringName = &"biomass"
const RESOURCE_SILICA: StringName = &"silica"
const RESOURCE_COMPUTE: StringName = &"compute"

signal resources_changed(team: int, resources: Dictionary)
signal bandwidth_changed(team: int, used: int, cap: int)

@export var starting_biomass: int = 50
@export var starting_silica: int = 0
@export var starting_compute: int = 0

var _resources: Dictionary = {}
var _bandwidth_used: Dictionary = {}
var _bandwidth_cap: Dictionary = {}
var _bandwidth_providers: Dictionary = {}
var _bandwidth_units: Dictionary = {}


func _ready() -> void:
	add_to_group("economy_manager")
	_init_team_state(Unit.Team.PLAYER, starting_biomass, starting_silica, starting_compute)
	_init_team_state(Unit.Team.ENEMY, 0, 0, 0)
	call_deferred("_sync_initial_scene_state")


func _sync_initial_scene_state() -> void:
	recalculate_bandwidth(Unit.Team.PLAYER)
	recalculate_bandwidth(Unit.Team.ENEMY)
	resources_changed.emit(Unit.Team.PLAYER, get_resources(Unit.Team.PLAYER))


func _init_team_state(team: int, biomass: int, silica: int, compute: int) -> void:
	_resources[team] = {
		RESOURCE_BIOMASS: biomass,
		RESOURCE_SILICA: silica,
		RESOURCE_COMPUTE: compute,
	}
	if not _bandwidth_used.has(team):
		_bandwidth_used[team] = 0
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
		RESOURCE_BIOMASS: 0,
		RESOURCE_SILICA: 0,
		RESOURCE_COMPUTE: 0,
	}
	recalculate_bandwidth(Unit.Team.PLAYER)
	recalculate_bandwidth(Unit.Team.ENEMY)
	resources_changed.emit(Unit.Team.PLAYER, get_resources(Unit.Team.PLAYER))
	resources_changed.emit(Unit.Team.ENEMY, get_resources(Unit.Team.ENEMY))


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
			if node == excluded_node or not (node is Unit) or not is_instance_valid(node):
				continue
			var unit: Unit = node
			if unit.is_dead or unit.is_queued_for_deletion() or unit.team != team:
				continue
			var cost: int = unit.data.bandwidth_cost if unit.data != null else 1
			used += maxi(0, cost)

		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if node == excluded_node or not (node is Building) or not is_instance_valid(node):
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

	_bandwidth_used[team] = used
	_bandwidth_cap[team] = cap
	bandwidth_changed.emit(team, used, cap)
