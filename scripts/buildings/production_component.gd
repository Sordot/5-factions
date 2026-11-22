class_name ProductionComponent
extends Node

const MAX_QUEUE_SIZE: int = 5

signal queue_changed(queue: Array[Dictionary], progress: float, duration: float)
signal unit_produced(unit: Unit)

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
	var data: UnitData = front["data"] as UnitData
	return {
		"display_name": data.display_name if data != null else "Unit",
		"progress": get_active_progress(),
		"duration": get_active_duration(),
		"queue_size": _queue.size(),
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
	if not econ.can_afford(owner_building.team, unit_data.get_cost_dict()):
		return false
	return econ.has_bandwidth(owner_building.team, unit_data.bandwidth_cost)


func enqueue_unit(owner_building: Building, unit_data: UnitData, unit_scene_override: PackedScene = null) -> bool:
	if not can_queue_unit(owner_building, unit_data, unit_scene_override):
		return false
	var scene: PackedScene = unit_scene_override if unit_scene_override != null else unit_data.resolve_unit_scene()
	var econ: EconomyManager = _get_economy_manager(owner_building)
	if econ == null:
		return false
	var costs: Dictionary = unit_data.get_cost_dict()
	if not econ.spend_resources(owner_building.team, costs):
		return false
	var bw_cost: int = maxi(0, unit_data.bandwidth_cost)
	econ.reserve_bandwidth(owner_building.team, bw_cost)

	var train_duration: float = unit_data.train_time if unit_data.train_time > 0.0 else unit_data.build_time
	_queue.append({
		"data": unit_data,
		"scene": scene,
		"costs": costs,
		"bandwidth_cost": bw_cost,
		"duration": maxf(0.5, train_duration),
	})
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
			econ.add_resource(owner_building.team, res_key, int(costs[res_key]))
		econ.release_bandwidth(owner_building.team, int(entry.get("bandwidth_cost", 0)))

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
				econ.add_resource(owner_building.team, res_key, int(costs[res_key]))
			econ.release_bandwidth(owner_building.team, int(entry.get("bandwidth_cost", 0)))
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

	# Release reserved slot right before adding the spawned unit so supply transfers cleanly 1-to-1.
	if econ != null:
		econ.release_bandwidth(owner_building.team, int(front.get("bandwidth_cost", 0)))

	var unit_scene: PackedScene = front["scene"] as PackedScene
	var spawned: Unit = _spawn_unit(owner_building, unit_scene)
	if spawned != null:
		owner_building.apply_rally_to_unit(spawned)
		unit_produced.emit(spawned)
	_emit_queue_changed()


func _spawn_unit(owner_building: Building, unit_scene: PackedScene) -> Unit:
	if unit_scene == null or not owner_building.is_inside_tree():
		return null
	var scene_root: Node = owner_building.get_tree().current_scene
	var units_container: Node = scene_root.get_node_or_null("Units") if scene_root != null else null
	if units_container == null:
		units_container = owner_building.get_parent()
	if units_container == null:
		return null

	var node: Node = unit_scene.instantiate()
	if not (node is Unit):
		node.queue_free()
		return null
	var unit: Unit = node
	unit.team = owner_building.team
	var spawn_dir: Vector2 = Vector2.RIGHT.rotated(float(_spawn_slot_index) * 0.85)
	if owner_building.has_rally():
		var to_rally: Vector2 = owner_building.get_rally_world_position() - owner_building.global_position
		if to_rally.length_squared() > 4.0:
			var jitter: float = (float(_spawn_slot_index % 3) - 1.0) * 0.22
			spawn_dir = to_rally.normalized().rotated(jitter)
	_spawn_slot_index = (_spawn_slot_index + 1) % 8
	var spawn_dist: float = owner_building.footprint_radius + 26.0
	unit.global_position = owner_building.global_position + spawn_dir * spawn_dist
	units_container.add_child(unit)
	return unit


func _emit_queue_changed() -> void:
	queue_changed.emit(_queue, get_active_progress(), get_active_duration())


func _get_economy_manager(owner_building: Building) -> EconomyManager:
	if owner_building == null or not owner_building.is_inside_tree():
		return null
	return owner_building.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
