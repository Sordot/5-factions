class_name ProductionComponent
extends Node

const MAX_QUEUE_SIZE: int = 5
const KIND_UNIT: StringName = &"unit"
const KIND_UPGRADE: StringName = &"upgrade"

signal queue_changed(queue: Array[Dictionary], progress: float, duration: float)
signal unit_produced(unit: Unit)
signal upgrade_researched(upgrade: UpgradeData)

var _queue: Array[Dictionary] = []
var _elapsed: float = 0.0
var _spawn_slot_index: int = 0


func get_queue() -> Array[Dictionary]:
	return _queue


func get_queue_size() -> int:
	return _queue.size()


func is_queue_full() -> bool:
	return _queue.size() >= MAX_QUEUE_SIZE


func get_active_progress() -> float:
	if _queue.is_empty():
		return 0.0
	var duration: float = maxf(0.1, float(_queue[0]["duration"]))
	return clampf(_elapsed / duration, 0.0, 1.0)


func get_active_duration() -> float:
	if _queue.is_empty():
		return 0.0
	return maxf(0.1, float(_queue[0]["duration"]))


func get_active_training_status() -> Dictionary:
	if _queue.is_empty():
		return {}
	var front: Dictionary = _queue[0]
	var kind: StringName = front.get("kind", KIND_UNIT)
	if kind == KIND_UPGRADE:
		var upg: UpgradeData = front["data"] as UpgradeData
		return {
			"kind": KIND_UPGRADE,
			"display_name": upg.display_name if upg != null else "Upgrade",
			"batch_count": 1,
			"progress": get_active_progress(),
			"duration": get_active_duration(),
			"queue_size": _queue.size(),
		}
	var data: UnitData = front["data"] as UnitData
	var batch_count: int = int(front.get("batch_count", 1))
	return {
		"kind": KIND_UNIT,
		"display_name": data.display_name if data != null else "Unit",
		"batch_count": batch_count,
		"progress": get_active_progress(),
		"duration": get_active_duration(),
		"queue_size": _queue.size(),
	}


func get_effective_unit_batch_info(owner_building: Building, unit_data: UnitData) -> Dictionary:
	if owner_building == null or unit_data == null:
		return {
			"batch_count": 1,
			"cost_multiplier": 1.0,
			"costs": {},
			"cost_label": "Free",
			"bandwidth_cost": 0,
			"duration": 1.0,
		}
	var batch_count: int = maxi(1, owner_building.batch_production_count)
	var econ: EconomyManager = _get_economy_manager(owner_building)
	var cost_mult: float = 1.0
	var time_mult: float = 1.0
	if batch_count > 1:
		var base_mult: float = maxf(1.0, owner_building.base_batch_cost_multiplier)
		cost_mult = econ.get_batch_cost_multiplier(owner_building.team, base_mult) if econ != null else base_mult
		time_mult = econ.get_batch_time_multiplier(owner_building.team) if econ != null else 1.0
	var base_duration: float = unit_data.train_time if unit_data.train_time > 0.0 else unit_data.build_time
	return {
		"batch_count": batch_count,
		"cost_multiplier": cost_mult,
		"costs": unit_data.get_scaled_cost_dict(cost_mult),
		"cost_label": unit_data.get_scaled_cost_label(cost_mult),
		"bandwidth_cost": maxi(0, unit_data.bandwidth_cost) * batch_count,
		"duration": maxf(0.5, base_duration * time_mult),
	}


func can_queue_unit(owner_building: Building, unit_data: UnitData, unit_scene_override: PackedScene = null) -> bool:
	if owner_building == null or owner_building.is_destroyed or not owner_building.is_constructed:
		return false
	if unit_data == null or is_queue_full():
		return false
	var scene: PackedScene = unit_scene_override if unit_scene_override != null else unit_data.resolve_unit_scene()
	if scene == null:
		return false
	var econ: EconomyManager = _get_economy_manager(owner_building)
	if econ == null:
		return false
	var info: Dictionary = get_effective_unit_batch_info(owner_building, unit_data)
	if not econ.can_afford(owner_building.team, info["costs"]):
		return false
	return econ.has_bandwidth(owner_building.team, int(info["bandwidth_cost"]))


func enqueue_unit(owner_building: Building, unit_data: UnitData, unit_scene_override: PackedScene = null) -> bool:
	var econ: EconomyManager = _get_economy_manager(owner_building)
	if not can_queue_unit(owner_building, unit_data, unit_scene_override):
		if owner_building != null and owner_building.team == Unit.Team.PLAYER and econ != null and unit_data != null and not is_queue_full():
			var fail_info: Dictionary = get_effective_unit_batch_info(owner_building, unit_data)
			var missing: StringName = econ.find_missing_resource(owner_building.team, fail_info["costs"], int(fail_info["bandwidth_cost"]))
			if missing != &"":
				econ.notify_insufficient(owner_building.team, missing)
		return false
	var scene: PackedScene = unit_scene_override if unit_scene_override != null else unit_data.resolve_unit_scene()
	if econ == null:
		return false
	var info: Dictionary = get_effective_unit_batch_info(owner_building, unit_data)
	var costs: Dictionary = info["costs"]
	if not econ.spend_resources(owner_building.team, costs):
		return false
	var bw_cost: int = int(info["bandwidth_cost"])
	econ.reserve_bandwidth(owner_building.team, bw_cost)

	_queue.append({
		"kind": KIND_UNIT,
		"data": unit_data,
		"scene": scene,
		"costs": costs,
		"cost_label": String(info["cost_label"]),
		"bandwidth_cost": bw_cost,
		"batch_count": int(info["batch_count"]),
		"duration": float(info["duration"]),
	})
	if owner_building.team == Unit.Team.PLAYER and AudioManager != null:
		AudioManager.play_ui_click()
	_emit_queue_changed()
	return true


func can_queue_upgrade(owner_building: Building, upgrade_data: UpgradeData) -> bool:
	if owner_building == null or owner_building.is_destroyed or not owner_building.is_constructed:
		return false
	if upgrade_data == null or upgrade_data.upgrade_id == &"" or is_queue_full():
		return false
	var econ: EconomyManager = _get_economy_manager(owner_building)
	if econ == null:
		return false
	if not econ.can_start_upgrade(owner_building.team, upgrade_data):
		return false
	return econ.can_afford(owner_building.team, upgrade_data.get_cost_dict())


func enqueue_upgrade(owner_building: Building, upgrade_data: UpgradeData) -> bool:
	var econ: EconomyManager = _get_economy_manager(owner_building)
	if not can_queue_upgrade(owner_building, upgrade_data):
		if owner_building != null and owner_building.team == Unit.Team.PLAYER and econ != null and upgrade_data != null and econ.can_start_upgrade(owner_building.team, upgrade_data):
			var missing: StringName = econ.find_missing_resource(owner_building.team, upgrade_data.get_cost_dict(), 0)
			if missing != &"":
				econ.notify_insufficient(owner_building.team, missing)
		return false
	if econ == null:
		return false
	var costs: Dictionary = upgrade_data.get_cost_dict()
	if not econ.spend_resources(owner_building.team, costs):
		return false
	econ.reserve_upgrade_research(owner_building.team, upgrade_data.upgrade_id)

	_queue.append({
		"kind": KIND_UPGRADE,
		"data": upgrade_data,
		"scene": null,
		"costs": costs,
		"cost_label": upgrade_data.get_cost_label(),
		"bandwidth_cost": 0,
		"batch_count": 1,
		"duration": maxf(0.5, upgrade_data.research_time),
	})
	if owner_building.team == Unit.Team.PLAYER and AudioManager != null:
		AudioManager.play_ui_click()
	_emit_queue_changed()
	return true


func cancel_queue_item(owner_building: Building, index: int) -> bool:
	if index < 0 or index >= _queue.size():
		return false
	var entry: Dictionary = _queue[index]
	_queue.remove_at(index)
	if index == 0:
		_elapsed = 0.0

	var econ: EconomyManager = _get_economy_manager(owner_building)
	if econ != null and owner_building != null:
		var costs: Dictionary = entry.get("costs", {})
		for res_key: Variant in costs.keys():
			econ.add_resource(owner_building.team, res_key, int(costs[res_key]), false)
		econ.release_bandwidth(owner_building.team, int(entry.get("bandwidth_cost", 0)))
		if entry.get("kind", KIND_UNIT) == KIND_UPGRADE:
			var upg: UpgradeData = entry.get("data", null) as UpgradeData
			if upg != null:
				econ.release_upgrade_research(owner_building.team, upg.upgrade_id)

	_emit_queue_changed()
	return true


func cancel_all_and_refund(owner_building: Building) -> void:
	if _queue.is_empty():
		return
	var econ: EconomyManager = _get_economy_manager(owner_building)
	for entry: Dictionary in _queue:
		if econ != null and owner_building != null:
			var costs: Dictionary = entry.get("costs", {})
			for res_key: Variant in costs.keys():
				econ.add_resource(owner_building.team, res_key, int(costs[res_key]), false)
			econ.release_bandwidth(owner_building.team, int(entry.get("bandwidth_cost", 0)))
			if entry.get("kind", KIND_UNIT) == KIND_UPGRADE:
				var upg: UpgradeData = entry.get("data", null) as UpgradeData
				if upg != null:
					econ.release_upgrade_research(owner_building.team, upg.upgrade_id)
	_queue.clear()
	_elapsed = 0.0
	_emit_queue_changed()


func tick(owner_building: Building, delta: float) -> void:
	if owner_building == null or owner_building.is_destroyed or not owner_building.is_constructed:
		return
	if _queue.is_empty():
		return

	var econ: EconomyManager = _get_economy_manager(owner_building)
	var speed_mult: float = econ.get_production_speed_multiplier(owner_building.team) if econ != null else 1.0
	var front: Dictionary = _queue[0]
	var duration: float = maxf(0.1, float(front["duration"]))
	_elapsed += delta * speed_mult

	if _elapsed < duration:
		_emit_queue_changed()
		return

	_elapsed = 0.0
	_queue.remove_at(0)

	var kind: StringName = front.get("kind", KIND_UNIT)
	if kind == KIND_UPGRADE:
		var upg: UpgradeData = front["data"] as UpgradeData
		if upg != null and econ != null:
			econ.complete_upgrade(owner_building.team, upg.upgrade_id)
			owner_building.pulse_deposit_feedback()
			var b_tid: int = int(owner_building.team)
			var is_local_upg: bool = TeamManager.is_team_controlled_by_local_human(b_tid) if TeamManager != null else (b_tid == int(Unit.Team.PLAYER))
			var viewer_u: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
			var show_upg_feed: bool = viewer_u < 0 or (TeamManager.are_allies(viewer_u, b_tid) if TeamManager != null else is_local_upg)
			var mm: MatchManager = owner_building.get_tree().get_first_node_in_group("match_manager") as MatchManager
			if is_local_upg:
				if mm != null:
					mm.push_tactical_alert(owner_building.global_position, &"tech_complete", "%s Researched" % upg.display_name)
				elif AudioManager != null:
					AudioManager.play_sfx(&"upgrade_complete", -2.0, 0.0)
			if show_upg_feed and mm != null and mm.has_method("emit_tactical_event"):
				var tag: String = TeamManager.get_team_short_label(b_tid, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (b_tid + 1))
				mm.call("emit_tactical_event", &"economy", "%s %s Complete" % [tag, upg.display_name], owner_building.global_position, Color(0.26, 0.98, 0.88, 1.0))
			upgrade_researched.emit(upg)
		_emit_queue_changed()
		return

	# Release reserved supply right before adding spawned unit(s) so bandwidth transfers cleanly.
	if econ != null:
		econ.release_bandwidth(owner_building.team, int(front.get("bandwidth_cost", 0)))

	var unit_scene: PackedScene = front["scene"] as PackedScene
	var batch_count: int = maxi(1, int(front.get("batch_count", 1)))
	var spawned_units: Array[Unit] = _spawn_unit_batch(owner_building, unit_scene, batch_count)
	for spawned: Unit in spawned_units:
		owner_building.apply_rally_to_unit(spawned)
		unit_produced.emit(spawned)
	if not spawned_units.is_empty() and owner_building.team == Unit.Team.PLAYER and AudioManager != null:
		AudioManager.play_sfx(&"unit_ready", -4.0, 0.04)
	_emit_queue_changed()


func _spawn_unit_batch(owner_building: Building, unit_scene: PackedScene, batch_count: int) -> Array[Unit]:
	var spawned: Array[Unit] = []
	if unit_scene == null or not owner_building.is_inside_tree():
		return spawned
	var scene_root: Node = owner_building.get_tree().current_scene
	var units_container: Node = scene_root.get_node_or_null("Units") if scene_root != null else null
	if units_container == null:
		units_container = owner_building.get_parent()
	if units_container == null:
		return spawned

	var base_dir: Vector2 = Vector2.RIGHT.rotated(float(_spawn_slot_index) * 0.85)
	if owner_building.has_rally():
		var to_rally: Vector2 = owner_building.get_rally_world_position() - owner_building.global_position
		if to_rally.length_squared() > 4.0:
			var jitter: float = (float(_spawn_slot_index % 3) - 1.0) * 0.16
			base_dir = to_rally.normalized().rotated(jitter)
	_spawn_slot_index = (_spawn_slot_index + 1) % 8

	var spawn_dist: float = owner_building.footprint_radius + 26.0
	var base_exit_pos: Vector2 = owner_building.global_position + base_dir * spawn_dist
	var perp: Vector2 = Vector2(-base_dir.y, base_dir.x)

	for i: int in range(batch_count):
		var node: Node = unit_scene.instantiate()
		if not (node is Unit):
			node.queue_free()
			continue
		var unit: Unit = node
		unit.team = owner_building.team
		var lateral_offset: Vector2 = Vector2.ZERO
		if batch_count > 1:
			var spacing: float = maxf(36.0, (unit.data.collision_radius * 2.4) if unit.data != null else 36.0)
			var centered: float = float(i) - float(batch_count - 1) * 0.5
			lateral_offset = perp * (centered * spacing)
		unit.global_position = base_exit_pos + lateral_offset
		units_container.add_child(unit)
		spawned.append(unit)

	return spawned


func _emit_queue_changed() -> void:
	queue_changed.emit(_queue, get_active_progress(), get_active_duration())


func _get_economy_manager(owner_building: Building) -> EconomyManager:
	if owner_building == null or not owner_building.is_inside_tree():
		return null
	return owner_building.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
