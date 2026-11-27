class_name GatherComponent
extends Node

enum GatherState {
	NONE,
	GATHER_MOVING_TO_NODE,
	GATHERING,
	GATHER_RETURNING_TO_BASE,
}

const CLUSTER_REACQUIRE_RADIUS: float = 480.0
const OVERFLOW_REACQUIRE_RADIUS: float = 1100.0

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

var _owner_unit_ref: Unit = null
var _claimed_slot_pos: Vector2 = Vector2.INF


func is_active() -> bool:
	return state != GatherState.NONE


func is_harvesting_in_place() -> bool:
	return state == GatherState.GATHERING


func has_cargo() -> bool:
	return carried_amount > 0


func clear_carried_cargo(owner_unit: Unit = null) -> void:
	var u: Unit = owner_unit if owner_unit != null else _owner_unit_ref
	if carried_amount == 0 and carried_type == &"":
		return
	carried_amount = 0
	carried_type = &""
	cargo_changed.emit(&"", 0)
	if u != null and is_instance_valid(u):
		u.queue_redraw()


func release_assigned_node(owner_unit: Unit = null) -> void:
	var u: Unit = owner_unit if owner_unit != null else _owner_unit_ref
	if is_instance_valid(target_node) and u != null:
		target_node.release_worker(u)
	_claimed_slot_pos = Vector2.INF


func start_gather(owner_unit: Unit, resource_node: ResourceNode, is_auto_migration: bool = false) -> bool:
	if owner_unit == null or owner_unit.data == null or not owner_unit.data.can_gather:
		return false
	if not is_instance_valid(resource_node) or resource_node.is_depleted() or resource_node.is_vent:
		return false
	if owner_unit.data.allowed_resource != &"" and resource_node.resource_type != owner_unit.data.allowed_resource:
		return false

	_owner_unit_ref = owner_unit
	var switched_target: bool = (target_node != null and target_node != resource_node) or (carried_type != &"" and carried_type != resource_node.resource_type)
	if is_instance_valid(target_node) and target_node != resource_node:
		target_node.release_worker(owner_unit)
	if not is_auto_migration and switched_target and carried_amount > 0:
		clear_carried_cargo(owner_unit)

	target_node = resource_node
	target_node.assign_worker(owner_unit)
	last_node_position = resource_node.global_position
	last_resource_type = resource_node.resource_type
	gather_timer = 0.0
	_claimed_slot_pos = Vector2.INF

	var effective_cap: int = target_node.get_effective_carry_capacity(owner_unit.data.carry_capacity)
	if carried_amount >= effective_cap and carried_type == resource_node.resource_type:
		dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
		target_node.release_harvest_slot(owner_unit)
		_set_state(GatherState.GATHER_RETURNING_TO_BASE)
		gather_progress_changed.emit(0.0, false)
		return true

	_claim_slot_on_target(owner_unit)
	_set_state(GatherState.GATHER_MOVING_TO_NODE)
	gather_progress_changed.emit(0.0, false)
	return true


func start_return_cargo(owner_unit: Unit, building: Building = null) -> bool:
	if owner_unit == null or owner_unit.data == null or not owner_unit.data.can_gather:
		return false
	if carried_amount <= 0 or carried_type == &"":
		return false

	_owner_unit_ref = owner_unit
	var resolved_dropoff: Building = building
	if (
		resolved_dropoff == null
		or not is_instance_valid(resolved_dropoff)
		or resolved_dropoff.is_destroyed
		or not resolved_dropoff.is_constructed
		or resolved_dropoff.is_salvaging
		or resolved_dropoff.team != owner_unit.team
		or not resolved_dropoff.accepts_resource(carried_type)
	):
		resolved_dropoff = _find_nearest_dropoff(owner_unit, carried_type)
	if resolved_dropoff == null:
		return false

	if is_instance_valid(target_node):
		target_node.release_harvest_slot(owner_unit)
	_claimed_slot_pos = Vector2.INF
	dropoff_building = resolved_dropoff
	gather_timer = 0.0
	_set_state(GatherState.GATHER_RETURNING_TO_BASE)
	gather_progress_changed.emit(0.0, false)
	return true


func cancel(owner_unit: Unit = null, drop_cargo: bool = false) -> void:
	var u: Unit = owner_unit if owner_unit != null else _owner_unit_ref
	release_assigned_node(u)
	target_node = null
	if drop_cargo:
		clear_carried_cargo(u)
	if state == GatherState.NONE and gather_timer == 0.0:
		return
	gather_timer = 0.0
	_set_state(GatherState.NONE)
	gather_progress_changed.emit(0.0, false)


func tick(owner_unit: Unit, delta: float) -> void:
	if owner_unit == null or owner_unit.is_dead or owner_unit.data == null:
		cancel(owner_unit, true)
		return
	_owner_unit_ref = owner_unit

	match state:
		GatherState.NONE:
			owner_unit.command_state = Unit.CommandState.IDLE
		GatherState.GATHER_MOVING_TO_NODE:
			_tick_moving_to_node(owner_unit)
		GatherState.GATHERING:
			_tick_gathering(owner_unit, delta)
		GatherState.GATHER_RETURNING_TO_BASE:
			_tick_returning_to_base(owner_unit)


func _claim_slot_on_target(owner_unit: Unit) -> Vector2:
	if not is_instance_valid(target_node) or target_node.is_depleted():
		_claimed_slot_pos = Vector2.INF
		return owner_unit.global_position
	var nearest_hub: Building = _find_nearest_dropoff(owner_unit, target_node.resource_type)
	var hub_pos: Vector2 = nearest_hub.global_position if nearest_hub != null else Vector2.INF
	_claimed_slot_pos = target_node.claim_harvest_slot(owner_unit, hub_pos)
	return _claimed_slot_pos


func _tick_moving_to_node(owner_unit: Unit) -> void:
	if not _ensure_valid_target_node(owner_unit):
		if carried_amount > 0:
			dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
			if dropoff_building != null:
				_set_state(GatherState.GATHER_RETURNING_TO_BASE)
				return
		cancel(owner_unit, false)
		owner_unit.stop_component_navigation()
		if not owner_unit.advance_command_queue():
			owner_unit.command_state = Unit.CommandState.IDLE
		return

	target_node.assign_worker(owner_unit)
	last_node_position = target_node.global_position
	last_resource_type = target_node.resource_type

	if _claimed_slot_pos == Vector2.INF:
		_claim_slot_on_target(owner_unit)

	var slot_dist: float = owner_unit.global_position.distance_to(_claimed_slot_pos)
	var node_dist: float = owner_unit.global_position.distance_to(target_node.global_position)
	var reach: float = _get_gather_reach(owner_unit, target_node)
	if slot_dist <= 12.0 or (node_dist <= reach and slot_dist <= 20.0):
		owner_unit.stop_component_navigation()
		gather_timer = 0.0
		_set_state(GatherState.GATHERING)
		gather_progress_changed.emit(0.0, true)
		return

	owner_unit.request_component_navigation(_claimed_slot_pos, 10.0, 4.0)


func _tick_gathering(owner_unit: Unit, delta: float) -> void:
	if not is_instance_valid(target_node) or target_node.is_depleted():
		gather_timer = 0.0
		gather_progress_changed.emit(0.0, false)
		var depleted_ref: ResourceNode = target_node if is_instance_valid(target_node) else null
		if depleted_ref != null:
			depleted_ref.release_worker(owner_unit)
		target_node = null
		_claimed_slot_pos = Vector2.INF

		# If cargo is already full, deliver first; otherwise auto-migrate immediately preserving partial cargo.
		var depleted_cap: int = depleted_ref.get_effective_carry_capacity(owner_unit.data.carry_capacity) if depleted_ref != null else owner_unit.data.carry_capacity
		if carried_amount >= depleted_cap:
			dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
			if dropoff_building != null:
				_set_state(GatherState.GATHER_RETURNING_TO_BASE)
				return

		if _ensure_valid_target_node(owner_unit, depleted_ref):
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		elif carried_amount > 0:
			dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
			if dropoff_building != null:
				_set_state(GatherState.GATHER_RETURNING_TO_BASE)
			else:
				cancel(owner_unit, false)
				owner_unit.command_state = Unit.CommandState.IDLE
		else:
			cancel(owner_unit, false)
			if not owner_unit.advance_command_queue():
				owner_unit.command_state = Unit.CommandState.IDLE
		return

	# Face the resource node while harvesting (tangential slot separation handled cleanly in MovementComponent).
	owner_unit.face_world_point(target_node.global_position, delta)

	var duration: float = maxf(0.1, owner_unit.data.gather_duration)
	gather_timer += delta
	gather_progress_changed.emit(clampf(gather_timer / duration, 0.0, 1.0), true)

	if gather_timer < duration:
		return

	gather_timer = 0.0
	gather_progress_changed.emit(0.0, false)

	var capacity: int = maxi(1, target_node.get_effective_carry_capacity(owner_unit.data.carry_capacity))
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
		# Dynamic nearest drop-off re-evaluation on every full cargo transition
		dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
		if is_instance_valid(target_node):
			target_node.release_harvest_slot(owner_unit)
		_claimed_slot_pos = Vector2.INF
		if dropoff_building != null or owner_unit.data.auto_gather_on_spawn:
			_set_state(GatherState.GATHER_RETURNING_TO_BASE)
		else:
			cancel(owner_unit, false)
			owner_unit.stop_component_navigation()
			if not owner_unit.advance_command_queue():
				owner_unit.command_state = Unit.CommandState.IDLE
	else:
		if _ensure_valid_target_node(owner_unit):
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		else:
			cancel(owner_unit, false)
			owner_unit.stop_component_navigation()
			if not owner_unit.advance_command_queue():
				owner_unit.command_state = Unit.CommandState.IDLE


func _tick_returning_to_base(owner_unit: Unit) -> void:
	if carried_amount <= 0 or carried_type == &"":
		if owner_unit.has_queued_commands():
			cancel(owner_unit, false)
			owner_unit.stop_component_navigation()
			owner_unit.advance_command_queue()
			return
		if _ensure_valid_target_node(owner_unit):
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		else:
			cancel(owner_unit, false)
			owner_unit.stop_component_navigation()
			owner_unit.command_state = Unit.CommandState.IDLE
		return

	if (
		not is_instance_valid(dropoff_building)
		or dropoff_building.is_destroyed
		or not dropoff_building.is_constructed
		or dropoff_building.is_salvaging
		or not dropoff_building.accepts_resource(carried_type)
	):
		dropoff_building = _find_nearest_dropoff(owner_unit, carried_type)
		if dropoff_building == null:
			# Automated harvesters wait patiently with their full load until a Refinery is constructed.
			if owner_unit.data.auto_gather_on_spawn:
				owner_unit.stop_component_navigation()
				return
			cancel(owner_unit, false)
			owner_unit.stop_component_navigation()
			if owner_unit.has_queued_commands():
				owner_unit.advance_command_queue()
			else:
				owner_unit.command_state = Unit.CommandState.IDLE
			return

	var reach: float = _get_dropoff_reach(owner_unit, dropoff_building)
	var dist: float = owner_unit.global_position.distance_to(dropoff_building.global_position)
	if dist <= reach:
		owner_unit.stop_component_navigation()
		var econ: EconomyManager = _get_economy_manager(owner_unit)
		if econ != null:
			var yield_mult: float = GameConfig.get_yield_multiplier() if (GameConfig != null and GameConfig.has_method("get_yield_multiplier")) else 1.0
			var deposit_amount: int = maxi(1, int(round(float(carried_amount) * yield_mult)))
			econ.add_resource(owner_unit.team, carried_type, deposit_amount)
		dropoff_building.pulse_deposit_feedback()

		last_resource_type = carried_type
		carried_amount = 0
		carried_type = &""
		cargo_changed.emit(&"", 0)

		if owner_unit.has_queued_commands():
			cancel(owner_unit, false)
			owner_unit.advance_command_queue()
			return

		if _ensure_valid_target_node(owner_unit):
			_claim_slot_on_target(owner_unit)
			_set_state(GatherState.GATHER_MOVING_TO_NODE)
		else:
			cancel(owner_unit, false)
			owner_unit.command_state = Unit.CommandState.IDLE
		return

	owner_unit.request_component_navigation(
		_get_approach_point(owner_unit, dropoff_building, dropoff_building.footprint_radius, dropoff_building, null),
		12.0,
		4.0
	)


func _get_approach_point(
	owner_unit: Unit,
	target_entity: Node2D,
	target_radius: float,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null
) -> Vector2:
	return owner_unit.get_or_compute_approach_point(target_entity, target_radius, 8.0, ignore_building, ignore_resource)


func _ensure_valid_target_node(owner_unit: Unit, exclude_node: ResourceNode = null) -> bool:
	if is_instance_valid(target_node) and target_node != exclude_node and not target_node.is_depleted() and not target_node.is_vent:
		target_node.assign_worker(owner_unit)
		return true

	if is_instance_valid(target_node):
		target_node.release_worker(owner_unit)
	target_node = null
	_claimed_slot_pos = Vector2.INF

	var search_origin: Vector2 = last_node_position if last_node_position != Vector2.ZERO else owner_unit.global_position
	var res_type: StringName = owner_unit.data.allowed_resource if (owner_unit.data != null and owner_unit.data.allowed_resource != &"") else (last_resource_type if last_resource_type != &"" else &"biomass")
	var overflow_r: float = 2400.0 if (owner_unit.data != null and owner_unit.data.auto_gather_on_spawn) else OVERFLOW_REACQUIRE_RADIUS

	var migrated: ResourceNode = ResourceNode.pick_best_cluster_node_from_pos(
		owner_unit.get_tree(),
		search_origin,
		res_type,
		owner_unit,
		int(owner_unit.team),
		CLUSTER_REACQUIRE_RADIUS,
		overflow_r,
		null,
		exclude_node
	)
	if migrated == null:
		return false
	target_node = migrated
	target_node.assign_worker(owner_unit)
	last_node_position = target_node.global_position
	last_resource_type = target_node.resource_type
	_claim_slot_on_target(owner_unit)
	return true


func _get_gather_reach(owner_unit: Unit, node: ResourceNode) -> float:
	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var configured: float = owner_unit.data.gather_range if owner_unit.data != null else 54.0
	var min_physical: float = maxf(54.0, node.collision_radius + unit_r + 22.0)
	return maxf(configured, min_physical)


func _get_dropoff_reach(owner_unit: Unit, building: Building) -> float:
	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var configured: float = owner_unit.data.dropoff_range if owner_unit.data != null else 64.0
	var min_physical: float = building.footprint_radius + unit_r + 22.0
	return maxf(configured, min_physical)


func _find_nearest_dropoff(owner_unit: Unit, resource_type: StringName) -> Building:
	var best: Building = null
	var best_dist_sq: float = INF
	for node: Node in owner_unit.get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var building: Building = node
		if (
			building.is_destroyed
			or not building.is_constructed
			or building.is_salvaging
			or building.team != owner_unit.team
			or not building.accepts_resource(resource_type)
		):
			continue
		var d_sq: float = owner_unit.global_position.distance_squared_to(building.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = building
	return best


func _get_economy_manager(owner_unit: Unit) -> EconomyManager:
	return owner_unit.get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func _set_state(new_state: GatherState) -> void:
	if state == new_state:
		return
	state = new_state
	gather_state_changed.emit(state)
