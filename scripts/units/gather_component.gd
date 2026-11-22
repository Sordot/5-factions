class_name GatherComponent
extends Node

enum GatherState {
	NONE,
	GATHER_MOVING_TO_NODE,
	GATHERING,
	GATHER_RETURNING_TO_BASE,
}

const NODE_REACQUIRE_RADIUS: float = 420.0

signal gather_state_changed(new_state: GatherState)
signal cargo_changed(resource_type: StringName, amount: int)
signal gather_progress_changed(progress: float, is_active: bool)

var state: GatherState = GatherState.NONE
var target_node: ResourceNode = null
var last_node_position: Vector2 = Vector2.ZERO
var last_resource_type: StringName = &"biomass"
var dropoff_building: Building = null
var gather_timer: float = 0.0
var carried_amount: int = 0
var carried_type: StringName = &""


func is_active() -> bool:
	return state != GatherState.NONE


func is_harvesting_in_place() -> bool:
	return state == GatherState.GATHERING


func has_cargo() -> bool:
	return carried_amount > 0


func start_gather(owner_unit: Unit, resource_node: ResourceNode) -> bool:
	if owner_unit == null or owner_unit.data == null or not owner_unit.data.can_gather:
		return false
	if not is_instance_valid(resource_node) or resource_node.is_depleted():
		return false

	target_node = resource_node
	last_node_position = resource_node.global_position
	last_resource_type = resource_node.resource_type
	gather_timer = 0.0

	if carried_amount >= owner_unit.data.carry_capacity and carried_type == resource_node.resource_type:
		dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
		if dropoff_building != null:
			_set_state(GatherState.GATHER_RETURNING_TO_BASE)
			gather_progress_changed.emit(0.0, false)
			return true

	_set_state(GatherState.GATHER_MOVING_TO_NODE)
	gather_progress_changed.emit(0.0, false)
	return true


func start_return_cargo(owner_unit: Unit, building: Building = null) -> bool:
	if owner_unit == null or owner_unit.data == null or not owner_unit.data.can_gather:
		return false
	if carried_amount <= 0 or carried_type == &"":
		return false

	var resolved_dropoff: Building = building
	if resolved_dropoff == null or not is_instance_valid(resolved_dropoff) or resolved_dropoff.team != owner_unit.team or not resolved_dropoff.accepts_resource(carried_type):
		resolved_dropoff = _find_nearest_dropoff(owner_unit, carried_type)
	if resolved_dropoff == null:
		return false

	dropoff_building = resolved_dropoff
	gather_timer = 0.0
	_set_state(GatherState.GATHER_RETURNING_TO_BASE)
	gather_progress_changed.emit(0.0, false)
	return true


func cancel() -> void:
	if state == GatherState.NONE and gather_timer == 0.0:
		return
	gather_timer = 0.0
	_set_state(GatherState.NONE)
	gather_progress_changed.emit(0.0, false)


func tick(owner_unit: Unit, delta: float) -> void:
	if owner_unit == null or owner_unit.is_dead or owner_unit.data == null:
		cancel()
		return

	match state:
		GatherState.NONE:
			owner_unit.command_state = Unit.CommandState.IDLE
		GatherState.GATHER_MOVING_TO_NODE:
			_tick_moving_to_node(owner_unit)
		GatherState.GATHERING:
			_tick_gathering(owner_unit, delta)
		GatherState.GATHER_RETURNING_TO_BASE:
			_tick_returning_to_base(owner_unit)


func _tick_moving_to_node(owner_unit: Unit) -> void:
	if not _ensure_valid_target_node(owner_unit):
		if carried_amount > 0:
			dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
			if dropoff_building != null:
				_set_state(GatherState.GATHER_RETURNING_TO_BASE)
				return
		cancel()
		owner_unit.stop_component_navigation()
		owner_unit.command_state = Unit.CommandState.IDLE
		return

	last_node_position = target_node.global_position
	last_resource_type = target_node.resource_type
	var reach: float = _get_gather_reach(owner_unit, target_node)
	var dist: float = owner_unit.global_position.distance_to(target_node.global_position)
	if dist <= reach:
		owner_unit.stop_component_navigation()
		gather_timer = 0.0
		_set_state(GatherState.GATHERING)
		gather_progress_changed.emit(0.0, true)
		return

	owner_unit.request_component_navigation(_get_approach_point(owner_unit, target_node.global_position, target_node.collision_radius), 12.0)


func _tick_gathering(owner_unit: Unit, delta: float) -> void:
	if not is_instance_valid(target_node) or target_node.is_depleted():
		gather_timer = 0.0
		gather_progress_changed.emit(0.0, false)
		if _ensure_valid_target_node(owner_unit):
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		elif carried_amount > 0:
			dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
			if dropoff_building != null:
				_set_state(GatherState.GATHER_RETURNING_TO_BASE)
			else:
				cancel()
				owner_unit.command_state = Unit.CommandState.IDLE
		else:
			cancel()
			owner_unit.command_state = Unit.CommandState.IDLE
		return

	# Keep worker stationary and oriented toward the Biomass node while harvesting.
	owner_unit.velocity = Vector2.ZERO
	owner_unit.face_world_point(target_node.global_position, delta)

	var duration: float = maxf(0.1, owner_unit.data.gather_duration)
	gather_timer += delta
	gather_progress_changed.emit(clampf(gather_timer / duration, 0.0, 1.0), true)

	if gather_timer < duration:
		return

	gather_timer = 0.0
	gather_progress_changed.emit(0.0, false)

	var capacity: int = maxi(1, owner_unit.data.carry_capacity)
	if carried_type != &"" and carried_type != target_node.resource_type:
		carried_amount = 0
	var room: int = maxi(0, capacity - carried_amount)
	if room > 0:
		var extracted: int = target_node.extract(room)
		if extracted > 0:
			carried_type = target_node.resource_type
			carried_amount += extracted
			if is_instance_valid(target_node):
				target_node.pulse_harvest_feedback()
			cargo_changed.emit(carried_type, carried_amount)

	if carried_amount > 0:
		dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
		if dropoff_building != null:
			_set_state(GatherState.GATHER_RETURNING_TO_BASE)
		else:
			cancel()
			owner_unit.command_state = Unit.CommandState.IDLE
	else:
		if _ensure_valid_target_node(owner_unit):
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		else:
			cancel()
			owner_unit.command_state = Unit.CommandState.IDLE


func _tick_returning_to_base(owner_unit: Unit) -> void:
	if carried_amount <= 0 or carried_type == &"":
		if _ensure_valid_target_node(owner_unit):
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		else:
			cancel()
			owner_unit.stop_component_navigation()
			owner_unit.command_state = Unit.CommandState.IDLE
		return

	if not is_instance_valid(dropoff_building) or dropoff_building.is_destroyed or not dropoff_building.accepts_resource(carried_type):
		dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
		if dropoff_building == null:
			cancel()
			owner_unit.stop_component_navigation()
			owner_unit.command_state = Unit.CommandState.IDLE
			return

	var reach: float = _get_dropoff_reach(owner_unit, dropoff_building)
	var dist: float = owner_unit.global_position.distance_to(dropoff_building.global_position)
	if dist <= reach:
		var econ: EconomyManager = _get_economy_manager(owner_unit)
		if econ != null:
			econ.add_resource(owner_unit.team, carried_type, carried_amount)
		dropoff_building.pulse_deposit_feedback()

		last_resource_type = carried_type
		carried_amount = 0
		carried_type = &""
		cargo_changed.emit(&"", 0)

		if _ensure_valid_target_node(owner_unit):
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		else:
			cancel()
			owner_unit.stop_component_navigation()
			owner_unit.command_state = Unit.CommandState.IDLE
		return

	owner_unit.request_component_navigation(_get_approach_point(owner_unit, dropoff_building.global_position, dropoff_building.footprint_radius), 12.0)


func _get_approach_point(owner_unit: Unit, target_center: Vector2, target_radius: float) -> Vector2:
	var offset: Vector2 = owner_unit.global_position - target_center
	var dir: Vector2 = offset.normalized() if offset.length_squared() > 0.01 else Vector2.RIGHT
	return target_center + dir * (target_radius * 0.75)


func _ensure_valid_target_node(owner_unit: Unit) -> bool:
	if is_instance_valid(target_node) and not target_node.is_depleted():
		return true
	var search_origin: Vector2 = last_node_position if last_node_position != Vector2.ZERO else owner_unit.global_position
	var res_type: StringName = last_resource_type if last_resource_type != &"" else &"biomass"
	target_node = _find_nearest_resource_node(owner_unit, search_origin, res_type, NODE_REACQUIRE_RADIUS)
	return target_node != null


func _get_gather_reach(owner_unit: Unit, node: ResourceNode) -> float:
	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var configured: float = owner_unit.data.gather_range if owner_unit.data != null else 48.0
	var min_physical: float = node.collision_radius + unit_r + 17.0
	return maxf(configured, min_physical)


func _get_dropoff_reach(owner_unit: Unit, building: Building) -> float:
	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var configured: float = owner_unit.data.dropoff_range if owner_unit.data != null else 64.0
	var min_physical: float = building.footprint_radius + unit_r + 18.0
	return maxf(configured, min_physical)


func _find_nearest_dropoff(owner_unit: Unit, resource_type: StringName) -> Building:
	var best: Building = null
	var best_dist_sq: float = INF
	for node: Node in owner_unit.get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var building: Building = node
		if building.team != owner_unit.team or not building.accepts_resource(resource_type):
			continue
		var d_sq: float = owner_unit.global_position.distance_squared_to(building.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = building
	return best


func _find_nearest_resource_node(owner_unit: Unit, origin: Vector2, resource_type: StringName, max_radius: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist_sq: float = max_radius * max_radius
	for node: Node in owner_unit.get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var res_node: ResourceNode = node
		if res_node.is_depleted() or res_node.resource_type != resource_type:
			continue
		var d_sq: float = origin.distance_squared_to(res_node.global_position)
		if d_sq <= best_dist_sq:
			best_dist_sq = d_sq
			best = res_node
	return best


func _get_economy_manager(owner_unit: Unit) -> EconomyManager:
	return owner_unit.get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func _set_state(new_state: GatherState) -> void:
	if state == new_state:
		return
	state = new_state
	gather_state_changed.emit(state)
