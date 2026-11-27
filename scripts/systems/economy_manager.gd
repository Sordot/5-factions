class_name EconomyManager
extends Node

const RESOURCE_BIOMASS: StringName = &"biomass"
const RESOURCE_SILICA: StringName = &"silica"
const RESOURCE_COMPUTE: StringName = &"compute"
const INCOME_WINDOW_SEC: float = 30.0
const INCOME_COMPACT_THRESHOLD: int = 64

signal resources_changed(team: int, resources: Dictionary)
signal bandwidth_changed(team: int, used: int, cap: int)
signal production_bonus_changed(team: int, multiplier: float)
signal upgrade_completed(team: int, upgrade_id: StringName)
signal tech_changed(team: int)
signal resource_insufficient(team: int, missing_key: StringName)

@export var starting_biomass: int = 50
@export var starting_silica: int = 0
@export var starting_compute: int = 0
@export var enemy_matches_starting_resources: bool = true

var upgrade_manager: UpgradeManager = UpgradeManager.new()

var _resources: Dictionary = {}
var _total_gathered: Dictionary = {}
var _income_samples: Dictionary = {}
var _income_heads: Dictionary = {}
var _elapsed_time: float = 0.0
var _bandwidth_used: Dictionary = {}
var _bandwidth_reserved: Dictionary = {}
var _bandwidth_cap: Dictionary = {}
var _bandwidth_providers: Dictionary = {}
var _bandwidth_units: Dictionary = {}
var _team_unit_bw: Dictionary = {}
var _team_provider_bw: Dictionary = {}
var _reserved_by_source: Dictionary = {}
var _reserved_unkeyed: Dictionary = {}
var _constructed_building_counts: Dictionary = {}
var _registered_tech_buildings: Dictionary = {}
var _uplink_controller: int = -1
var _uplink_bonus_pct: float = 0.05


func _ready() -> void:
	add_to_group("economy_manager")
	if not upgrade_manager.upgrade_completed.is_connected(_on_upgrade_manager_completed):
		upgrade_manager.upgrade_completed.connect(_on_upgrade_manager_completed)
	if GameConfig != null and GameConfig.configured_from_menu:
		var preset_res: Dictionary = GameConfig.get_starting_resources()
		starting_biomass = int(preset_res.get("biomass", starting_biomass))
		starting_silica = int(preset_res.get("silica", starting_silica))
		starting_compute = int(preset_res.get("compute", starting_compute))
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	for tid: int in active_teams:
		if tid == 0 or enemy_matches_starting_resources:
			_init_team_state(tid, starting_biomass, starting_silica, starting_compute)
		else:
			_init_team_state(tid, 0, 0, 0)
	call_deferred("_sync_initial_scene_state")


func _sync_initial_scene_state() -> void:
	_rebuild_constructed_tech_cache()
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	for tid: int in active_teams:
		recalculate_bandwidth(tid)
		resources_changed.emit(tid, get_resources(tid))


func _process(delta: float) -> void:
	_elapsed_time += delta


func _init_team_state(team: int, biomass: int, silica: int, compute: int) -> void:
	_resources[team] = {
		RESOURCE_BIOMASS: biomass,
		RESOURCE_SILICA: silica,
		RESOURCE_COMPUTE: compute,
	}
	_total_gathered[team] = {
		RESOURCE_BIOMASS: 0,
		RESOURCE_SILICA: 0,
		RESOURCE_COMPUTE: 0,
	}
	_income_samples[team] = {
		RESOURCE_BIOMASS: [],
		RESOURCE_SILICA: [],
		RESOURCE_COMPUTE: [],
	}
	_income_heads[team] = {
		RESOURCE_BIOMASS: 0,
		RESOURCE_SILICA: 0,
		RESOURCE_COMPUTE: 0,
	}
	if not _bandwidth_used.has(team):
		_bandwidth_used[team] = 0
	if not _bandwidth_reserved.has(team):
		_bandwidth_reserved[team] = 0
	if not _bandwidth_cap.has(team):
		_bandwidth_cap[team] = 0
	if not _team_unit_bw.has(team):
		_team_unit_bw[team] = 0
	if not _team_provider_bw.has(team):
		_team_provider_bw[team] = 0
	if not _reserved_unkeyed.has(team):
		_reserved_unkeyed[team] = 0
	if not _constructed_building_counts.has(team):
		_constructed_building_counts[team] = {}


func _ensure_team(team: int) -> void:
	if not _resources.has(team):
		_init_team_state(team, 0, 0, 0)


func reset_economy() -> void:
	_elapsed_time = 0.0
	_bandwidth_providers.clear()
	_bandwidth_units.clear()
	_team_unit_bw.clear()
	_team_provider_bw.clear()
	_reserved_by_source.clear()
	_reserved_unkeyed.clear()
	_constructed_building_counts.clear()
	_registered_tech_buildings.clear()
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	for tid: int in active_teams:
		if tid == 0 or enemy_matches_starting_resources:
			_init_team_state(tid, starting_biomass, starting_silica, starting_compute)
		else:
			_init_team_state(tid, 0, 0, 0)
		_bandwidth_reserved[tid] = 0
		_bandwidth_used[tid] = 0
		_bandwidth_cap[tid] = 0
	upgrade_manager.reset()
	set_uplink_controller(-1, _uplink_bonus_pct)
	_rebuild_constructed_tech_cache()
	for tid: int in active_teams:
		recalculate_bandwidth(tid)
		resources_changed.emit(tid, get_resources(tid))
		tech_changed.emit(tid)


func set_team_starting_resources(team: int, biomass: int, silica: int, compute: int) -> void:
	_init_team_state(team, maxi(0, biomass), maxi(0, silica), maxi(0, compute))
	resources_changed.emit(team, get_resources(team))


func add_resource(team: int, resource_type: StringName, amount: int, record_as_income: bool = true) -> void:
	if amount <= 0:
		return
	_ensure_team(team)
	var team_res: Dictionary = _resources[team]
	team_res[resource_type] = int(team_res.get(resource_type, 0)) + amount
	if record_as_income:
		var totals: Dictionary = _total_gathered[team]
		totals[resource_type] = int(totals.get(resource_type, 0)) + amount
		var sample_map: Dictionary = _income_samples[team]
		if not sample_map.has(resource_type):
			sample_map[resource_type] = []
		var head_map: Dictionary = _income_heads[team]
		if not head_map.has(resource_type):
			head_map[resource_type] = 0
		var arr: Array = sample_map[resource_type]
		arr.append({"time": _elapsed_time, "amount": amount})
		_prune_income_samples(team, resource_type)
	resources_changed.emit(team, get_resources(team))


func _prune_income_samples(team: int, resource_type: StringName) -> void:
	var sample_map: Dictionary = _income_samples[team]
	var head_map: Dictionary = _income_heads[team]
	var arr: Array = sample_map[resource_type]
	var head: int = int(head_map.get(resource_type, 0))
	var arr_size: int = arr.size()
	var cutoff: float = _elapsed_time - INCOME_WINDOW_SEC
	while head < arr_size:
		var entry: Dictionary = arr[head] as Dictionary
		if float(entry.get("time", 0.0)) < cutoff:
			head += 1
		else:
			break
	if head >= arr_size:
		arr.clear()
		head = 0
	elif head >= INCOME_COMPACT_THRESHOLD:
		sample_map[resource_type] = arr.slice(head)
		head = 0
	head_map[resource_type] = head


func get_income_rate_per_minute(team: int, resource_type: StringName) -> int:
	if not _income_samples.has(team):
		return 0
	var sample_map: Dictionary = _income_samples[team]
	if not sample_map.has(resource_type):
		return 0
	_prune_income_samples(team, resource_type)
	var arr: Array = sample_map[resource_type]
	var head: int = int((_income_heads[team] as Dictionary).get(resource_type, 0))
	if head >= arr.size():
		return 0
	var total_in_window: int = 0
	for i: int in range(head, arr.size()):
		var item: Variant = arr[i]
		if item is Dictionary:
			total_in_window += int((item as Dictionary).get("amount", 0))
	var effective_window: float = clampf(_elapsed_time, 12.0, INCOME_WINDOW_SEC)
	return int(round(float(total_in_window) * (60.0 / effective_window)))


func get_total_gathered(team: int, resource_type: StringName) -> int:
	if not _total_gathered.has(team):
		return 0
	var totals: Dictionary = _total_gathered[team]
	return int(totals.get(resource_type, 0))


func get_all_totals_gathered(team: int) -> Dictionary:
	_ensure_team(team)
	return (_total_gathered[team] as Dictionary).duplicate()


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


func find_missing_resource(team: int, costs: Dictionary, bandwidth_cost: int = 0) -> StringName:
	_ensure_team(team)
	var team_res: Dictionary = _resources[team]
	for key: StringName in [RESOURCE_BIOMASS, RESOURCE_SILICA, RESOURCE_COMPUTE]:
		var needed: int = int(costs.get(key, 0))
		if needed > 0 and int(team_res.get(key, 0)) < needed:
			return key
	if bandwidth_cost > 0 and not has_bandwidth(team, bandwidth_cost):
		return &"bandwidth"
	return &""


func notify_insufficient(team: int, missing_key: StringName) -> void:
	if missing_key == &"":
		return
	resource_insufficient.emit(team, missing_key)
	var is_local: bool = TeamManager.is_team_controlled_by_local_human(team) if TeamManager != null else (team == int(Unit.Team.PLAYER))
	if is_local and AudioManager != null:
		AudioManager.play_error()


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


func _emit_bandwidth_if_changed(team: int) -> void:
	_ensure_team(team)
	var next_used: int = maxi(0, int(_team_unit_bw.get(team, 0))) + maxi(0, int(_bandwidth_reserved.get(team, 0)))
	var next_cap: int = maxi(0, int(_team_provider_bw.get(team, 0)))
	var prev_used: int = int(_bandwidth_used.get(team, -1))
	var prev_cap: int = int(_bandwidth_cap.get(team, -1))
	_bandwidth_used[team] = next_used
	_bandwidth_cap[team] = next_cap
	if next_used != prev_used or next_cap != prev_cap:
		bandwidth_changed.emit(team, next_used, next_cap)


func register_bandwidth_provider(provider: Node, team: int, amount: int) -> void:
	if provider == null or amount <= 0:
		return
	_ensure_team(team)
	var provider_id: int = provider.get_instance_id()
	if _bandwidth_providers.has(provider_id):
		var prev: Dictionary = _bandwidth_providers[provider_id] as Dictionary
		var prev_team: int = int(prev["team"])
		var prev_amt: int = int(prev["amount"])
		if prev_team == team and prev_amt == amount:
			return
		_team_provider_bw[prev_team] = maxi(0, int(_team_provider_bw.get(prev_team, 0)) - prev_amt)
		if prev_team != team:
			_emit_bandwidth_if_changed(prev_team)
	_bandwidth_providers[provider_id] = {
		"node": provider,
		"team": team,
		"amount": amount,
	}
	_team_provider_bw[team] = int(_team_provider_bw.get(team, 0)) + amount
	_emit_bandwidth_if_changed(team)


func unregister_bandwidth_provider(provider: Node) -> void:
	if provider == null:
		return
	var provider_id: int = provider.get_instance_id()
	if not _bandwidth_providers.has(provider_id):
		return
	var entry: Dictionary = _bandwidth_providers[provider_id] as Dictionary
	var team: int = int(entry["team"])
	var amt: int = int(entry["amount"])
	_bandwidth_providers.erase(provider_id)
	_team_provider_bw[team] = maxi(0, int(_team_provider_bw.get(team, 0)) - amt)
	_emit_bandwidth_if_changed(team)


func register_unit_bandwidth(unit: Node, team: int, cost: int = 1) -> void:
	if unit == null or cost <= 0:
		return
	_ensure_team(team)
	var unit_id: int = unit.get_instance_id()
	if _bandwidth_units.has(unit_id):
		var prev: Dictionary = _bandwidth_units[unit_id] as Dictionary
		var prev_team: int = int(prev["team"])
		var prev_cost: int = int(prev["cost"])
		if prev_team == team and prev_cost == cost:
			return
		_team_unit_bw[prev_team] = maxi(0, int(_team_unit_bw.get(prev_team, 0)) - prev_cost)
		if prev_team != team:
			_emit_bandwidth_if_changed(prev_team)
	_bandwidth_units[unit_id] = {
		"node": unit,
		"team": team,
		"cost": cost,
	}
	_team_unit_bw[team] = int(_team_unit_bw.get(team, 0)) + cost
	_emit_bandwidth_if_changed(team)


func unregister_unit_bandwidth(unit: Node) -> void:
	if unit == null:
		return
	var unit_id: int = unit.get_instance_id()
	if not _bandwidth_units.has(unit_id):
		return
	var entry: Dictionary = _bandwidth_units[unit_id] as Dictionary
	var team: int = int(entry["team"])
	var cost: int = int(entry["cost"])
	_bandwidth_units.erase(unit_id)
	_team_unit_bw[team] = maxi(0, int(_team_unit_bw.get(team, 0)) - cost)
	_emit_bandwidth_if_changed(team)


func update_bandwidth_used(team: int, used: int) -> void:
	_ensure_team(team)
	var clamped_used: int = maxi(0, used)
	if int(_bandwidth_used.get(team, 0)) == clamped_used:
		return
	_bandwidth_used[team] = clamped_used
	bandwidth_changed.emit(team, clamped_used, get_bandwidth_cap(team))


func reserve_bandwidth(team: int, amount: int, source_node: Node = null) -> void:
	if amount <= 0:
		return
	_ensure_team(team)
	if source_node != null:
		var sid: int = source_node.get_instance_id()
		if _reserved_by_source.has(sid):
			var rec: Dictionary = _reserved_by_source[sid] as Dictionary
			rec["amount"] = int(rec.get("amount", 0)) + amount
		else:
			_reserved_by_source[sid] = {
				"team": team,
				"amount": amount,
			}
	else:
		_reserved_unkeyed[team] = int(_reserved_unkeyed.get(team, 0)) + amount
	_bandwidth_reserved[team] = int(_bandwidth_reserved.get(team, 0)) + amount
	_emit_bandwidth_if_changed(team)


func release_bandwidth(team: int, amount: int, source_node: Node = null) -> void:
	if amount <= 0:
		return
	_ensure_team(team)
	var released: int = amount
	if source_node != null:
		var sid: int = source_node.get_instance_id()
		if _reserved_by_source.has(sid):
			var rec: Dictionary = _reserved_by_source[sid] as Dictionary
			var cur_amt: int = int(rec.get("amount", 0))
			released = mini(amount, cur_amt)
			var rem: int = cur_amt - released
			if rem <= 0:
				_reserved_by_source.erase(sid)
			else:
				rec["amount"] = rem
		else:
			released = 0
	else:
		var unkeyed_cur: int = int(_reserved_unkeyed.get(team, 0))
		released = mini(amount, unkeyed_cur)
		_reserved_unkeyed[team] = maxi(0, unkeyed_cur - released)
	if released > 0:
		_bandwidth_reserved[team] = maxi(0, int(_bandwidth_reserved.get(team, 0)) - released)
		_emit_bandwidth_if_changed(team)


func clear_source_reservations(source_node: Node) -> void:
	if source_node == null:
		return
	var sid: int = source_node.get_instance_id()
	if not _reserved_by_source.has(sid):
		return
	var rec: Dictionary = _reserved_by_source[sid] as Dictionary
	var team: int = int(rec.get("team", 0))
	var rem: int = int(rec.get("amount", 0))
	_reserved_by_source.erase(sid)
	if rem > 0:
		_ensure_team(team)
		_bandwidth_reserved[team] = maxi(0, int(_bandwidth_reserved.get(team, 0)) - rem)
		_emit_bandwidth_if_changed(team)


func set_uplink_controller(team: int, bonus_pct: float = 0.05) -> void:
	_uplink_controller = team
	_uplink_bonus_pct = maxf(0.0, bonus_pct)
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	for tid: int in active_teams:
		production_bonus_changed.emit(tid, get_production_speed_multiplier(tid))


func get_production_speed_multiplier(team: int) -> float:
	var has_uplink: bool = false
	if _uplink_controller >= 0:
		has_uplink = TeamManager.are_allies(_uplink_controller, team) if TeamManager != null else (_uplink_controller == team)
	var base_mult: float = (1.0 + _uplink_bonus_pct) if has_uplink else 1.0
	var fast_mult: float = GameConfig.get_build_speed_multiplier() if (GameConfig != null and GameConfig.has_method("get_build_speed_multiplier")) else 1.0
	return base_mult * fast_mult


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
		# Purge existing cached entries for this team before rebuilding cleanly from the live scene.
		for uid_key: Variant in _bandwidth_units.keys():
			if int((_bandwidth_units[uid_key] as Dictionary).get("team", -1)) == team:
				_bandwidth_units.erase(uid_key)
		for pid_key: Variant in _bandwidth_providers.keys():
			if int((_bandwidth_providers[pid_key] as Dictionary).get("team", -1)) == team:
				_bandwidth_providers.erase(pid_key)

		for node: Node in get_tree().get_nodes_in_group("units"):
			if node == excluded_node or not is_instance_valid(node) or not (node is Unit):
				continue
			var unit: Unit = node
			if unit.is_dead or unit.is_queued_for_deletion() or int(unit.team) != team:
				continue
			var cost: int = maxi(0, unit.data.bandwidth_cost if unit.data != null else 1)
			if cost > 0:
				_bandwidth_units[unit.get_instance_id()] = {"node": unit, "team": team, "cost": cost}
				used += cost

		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if node == excluded_node or not is_instance_valid(node) or not (node is Building):
				continue
			var building: Building = node
			if building.is_destroyed or building.is_queued_for_deletion() or not building.is_constructed or int(building.team) != team:
				continue
			var prov_amt: int = maxi(0, building.bandwidth_provided)
			if prov_amt > 0:
				_bandwidth_providers[building.get_instance_id()] = {"node": building, "team": team, "amount": prov_amt}
				cap += prov_amt
	else:
		for provider_id: Variant in _bandwidth_providers.keys():
			var p_entry: Dictionary = _bandwidth_providers[provider_id] as Dictionary
			if p_entry["node"] != excluded_node and int(p_entry["team"]) == team and is_instance_valid(p_entry["node"]):
				cap += int(p_entry["amount"])
		for unit_id: Variant in _bandwidth_units.keys():
			var u_entry: Dictionary = _bandwidth_units[unit_id] as Dictionary
			if u_entry["node"] != excluded_node and int(u_entry["team"]) == team and is_instance_valid(u_entry["node"]):
				used += int(u_entry["cost"])

	# Reconcile reserved bandwidth from live keyed sources + unkeyed fallback
	var reserved_sum: int = maxi(0, int(_reserved_unkeyed.get(team, 0)))
	for sid_key: Variant in _reserved_by_source.keys():
		var rec: Dictionary = _reserved_by_source[sid_key] as Dictionary
		if int(rec.get("team", -1)) == team:
			reserved_sum += maxi(0, int(rec.get("amount", 0)))
	_bandwidth_reserved[team] = reserved_sum
	_team_unit_bw[team] = used
	_team_provider_bw[team] = cap
	_bandwidth_used[team] = used + reserved_sum
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


func register_constructed_building(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if building.is_destroyed or not building.is_constructed or building.is_salvaging or building.building_type_id == &"":
		return
	var bid: int = building.get_instance_id()
	var team: int = int(building.team)
	var type_id: StringName = building.building_type_id
	_ensure_team(team)
	if _registered_tech_buildings.has(bid):
		var prev: Dictionary = _registered_tech_buildings[bid] as Dictionary
		if int(prev["team"]) == team and (prev["type_id"] as StringName) == type_id:
			return
		unregister_constructed_building(building)
	_registered_tech_buildings[bid] = {
		"team": team,
		"type_id": type_id,
	}
	var counts: Dictionary = _constructed_building_counts[team] as Dictionary
	counts[type_id] = int(counts.get(type_id, 0)) + 1


func unregister_constructed_building(building: Building) -> void:
	if building == null:
		return
	var bid: int = building.get_instance_id()
	if not _registered_tech_buildings.has(bid):
		return
	var entry: Dictionary = _registered_tech_buildings[bid] as Dictionary
	_registered_tech_buildings.erase(bid)
	var team: int = int(entry["team"])
	var type_id: StringName = entry["type_id"] as StringName
	if _constructed_building_counts.has(team):
		var counts: Dictionary = _constructed_building_counts[team] as Dictionary
		var next_cnt: int = int(counts.get(type_id, 0)) - 1
		if next_cnt <= 0:
			counts.erase(type_id)
		else:
			counts[type_id] = next_cnt


func _rebuild_constructed_tech_cache() -> void:
	_constructed_building_counts.clear()
	_registered_tech_buildings.clear()
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node as Building
			if not b.is_destroyed and not b.is_queued_for_deletion() and b.is_constructed and not b.is_salvaging:
				register_constructed_building(b)


func has_constructed_building(team: int, required_building_id: StringName) -> bool:
	if required_building_id == &"":
		return true
	if not _constructed_building_counts.has(team):
		return false
	var counts: Dictionary = _constructed_building_counts[team] as Dictionary
	return int(counts.get(required_building_id, 0)) > 0


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


func get_shield_regen_delay_multiplier(team: int) -> float:
	return upgrade_manager.get_shield_regen_delay_multiplier(team)


func get_shield_regen_rate_multiplier(team: int) -> float:
	return upgrade_manager.get_shield_regen_rate_multiplier(team)


func get_bonus_armor(team: int) -> float:
	return upgrade_manager.get_bonus_armor(team)


func has_hyper_velocity_rails(team: int) -> bool:
	return upgrade_manager.has_hyper_velocity_rails(team)


func get_rail_damage_multiplier(team: int) -> float:
	return upgrade_manager.get_rail_damage_multiplier(team)


func get_rail_range_bonus(team: int) -> float:
	return upgrade_manager.get_rail_range_bonus(team)


func get_bonus_tether_links(team: int) -> int:
	return upgrade_manager.get_bonus_tether_links(team)


func get_bonus_tether_radius(team: int) -> float:
	return upgrade_manager.get_bonus_tether_radius(team)


func get_beam_ramp_upgrade_multiplier(team: int) -> float:
	return upgrade_manager.get_beam_ramp_upgrade_multiplier(team)


func get_bonus_refract_bounces(team: int, unit_type_id: StringName) -> int:
	return upgrade_manager.get_bonus_refract_bounces(team, unit_type_id)


func get_prisma_move_speed_multiplier(team: int) -> float:
	return upgrade_manager.get_prisma_move_speed_multiplier(team)


func get_prisma_beam_range_bonus(team: int, unit_type_id: StringName) -> float:
	return upgrade_manager.get_prisma_beam_range_bonus(team, unit_type_id)


func get_upgrade_modifier_sum(team: int, modifier_key: StringName) -> float:
	return upgrade_manager.get_modifier_sum(team, modifier_key)


func get_upgrade_modifier_product(team: int, modifier_key: StringName, default_value: float = 1.0) -> float:
	return upgrade_manager.get_modifier_product(team, modifier_key, default_value)


func has_upgrade_modifier(team: int, modifier_key: StringName) -> bool:
	return upgrade_manager.has_modifier(team, modifier_key)
