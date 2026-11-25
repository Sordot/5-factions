class_name MovementComponent
extends Node

const SETTLE_PROXIMITY_RADIUS: float = 160.0
const SETTLE_NO_PROGRESS_TIME: float = 0.45
const SOFT_SETTLE_SAMPLE_WINDOW: float = 0.25
const SOFT_SETTLE_MAX_DISP_PX: float = 8.0
const SOFT_SETTLE_CONFIRM_TIME: float = 0.30

var last_nav_target: Vector2 = Vector2.INF
var wants_nav_movement: bool = false
var desired_move_velocity: Vector2 = Vector2.ZERO

var _no_progress_timer: float = 0.0
var _best_dist_to_goal: float = INF
var _settle_timer: float = 0.0
var _settle_sample_pos: Vector2 = Vector2.ZERO
var _settle_sample_timer: float = 0.0
var _settle_low_motion: bool = false
var _stuck_sample_pos: Vector2 = Vector2.ZERO
var _stuck_sample_timer: float = 0.0
var _stuck_accum_time: float = 0.0
var _stuck_nudge_timer: float = 0.0
var _stuck_nudge_dir: Vector2 = Vector2.ZERO
var _stuck_side_sign: float = 1.0
var _stuck_consecutive_nudges: int = 0
var _cached_approach_point: Vector2 = Vector2.INF
var _cached_approach_target_pos: Vector2 = Vector2.INF
var _cached_approach_target_id: int = 0


func initialize_for_unit(owner_unit: Unit) -> void:
	if owner_unit == null:
		return
	_stuck_sample_pos = owner_unit.global_position
	_settle_sample_pos = owner_unit.global_position
	_stuck_side_sign = 1.0 if (owner_unit.get_instance_id() % 2) == 0 else -1.0


func begin_frame() -> void:
	wants_nav_movement = false
	desired_move_velocity = Vector2.ZERO


func is_nav_map_ready(owner_unit: Unit) -> bool:
	return owner_unit != null and owner_unit.nav_agent != null and NavigationServer2D.map_get_iteration_id(owner_unit.nav_agent.get_navigation_map()) > 0


func set_nav_target(owner_unit: Unit, target_pos: Vector2) -> void:
	if owner_unit == null or owner_unit.nav_agent == null:
		return
	owner_unit.nav_agent.target_position = target_pos
	last_nav_target = target_pos


func clear_nav_target(owner_unit: Unit) -> void:
	last_nav_target = Vector2.INF
	if owner_unit != null and owner_unit.nav_agent != null and owner_unit.is_inside_tree():
		owner_unit.nav_agent.target_position = owner_unit.global_position
		if owner_unit.nav_agent.avoidance_enabled:
			owner_unit.nav_agent.set_velocity(Vector2.ZERO)


func stop_navigation(owner_unit: Unit) -> void:
	wants_nav_movement = false
	desired_move_velocity = Vector2.ZERO
	if owner_unit != null:
		owner_unit.velocity = Vector2.ZERO
		reset_progress_tracker(owner_unit)
		clear_cached_approach_point()
		clear_nav_target(owner_unit)


func invalidate_nav_path() -> void:
	last_nav_target = Vector2.INF
	clear_cached_approach_point()


func get_cached_approach_point() -> Vector2:
	return _cached_approach_point


func clear_cached_approach_point() -> void:
	_cached_approach_point = Vector2.INF
	_cached_approach_target_pos = Vector2.INF
	_cached_approach_target_id = 0


func reset_progress_tracker(owner_unit: Unit) -> void:
	_no_progress_timer = 0.0
	_best_dist_to_goal = INF
	_settle_timer = 0.0
	_settle_sample_pos = owner_unit.global_position if owner_unit != null else Vector2.ZERO
	_settle_sample_timer = 0.0
	_settle_low_motion = false
	_stuck_sample_pos = owner_unit.global_position if owner_unit != null else Vector2.ZERO
	_stuck_sample_timer = 0.0
	_stuck_accum_time = 0.0
	_stuck_nudge_timer = 0.0
	_stuck_consecutive_nudges = 0


func should_settle_at_destination(owner_unit: Unit, goal_pos: Vector2, delta: float) -> bool:
	if owner_unit == null or owner_unit.nav_agent == null:
		return true
	var dist_to_goal: float = owner_unit.global_position.distance_to(goal_pos)
	var arrive_dist: float = owner_unit.nav_agent.target_desired_distance + (14.0 if not owner_unit.command_queue.is_empty() else 0.0)
	if dist_to_goal <= arrive_dist or owner_unit.nav_agent.is_navigation_finished():
		_settle_timer = 0.0
		return true

	# Phase C.3: Soft-settling for shared Move destinations when settled allies occupy the goal center.
	if owner_unit.command_state == Unit.CommandState.MOVING:
		var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
		var settle_band: float = maxf(arrive_dist * 2.5, unit_r * 3.5)
		if dist_to_goal <= settle_band:
			_settle_sample_timer += delta
			if _settle_sample_timer >= SOFT_SETTLE_SAMPLE_WINDOW:
				var disp: float = owner_unit.global_position.distance_to(_settle_sample_pos)
				_settle_low_motion = disp < SOFT_SETTLE_MAX_DISP_PX
				_settle_sample_pos = owner_unit.global_position
				_settle_sample_timer = 0.0
			if _settle_low_motion and _has_settled_ally_near_goal(owner_unit, goal_pos, maxf(unit_r * 2.8, 36.0)):
				_settle_timer += delta
				if _settle_timer >= SOFT_SETTLE_CONFIRM_TIME:
					stop_navigation(owner_unit)
					return true
			else:
				_settle_timer = maxf(0.0, _settle_timer - delta * 2.0)
		else:
			_settle_timer = 0.0
			_settle_sample_timer = 0.0
			_settle_sample_pos = owner_unit.global_position
			_settle_low_motion = false

	if dist_to_goal < _best_dist_to_goal - 4.0:
		_best_dist_to_goal = dist_to_goal
		_no_progress_timer = 0.0
	elif dist_to_goal <= SETTLE_PROXIMITY_RADIUS:
		_no_progress_timer += delta
		if _no_progress_timer >= SETTLE_NO_PROGRESS_TIME:
			return true
	return false


func _has_settled_ally_near_goal(owner_unit: Unit, goal_pos: Vector2, radius: float) -> bool:
	if owner_unit == null or not owner_unit.is_inside_tree():
		return false
	var candidates: Array = SpatialGrid.query_units_in_radius(goal_pos, radius, int(owner_unit.team)) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
	var r_sq: float = radius * radius
	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Unit) or node == owner_unit:
			continue
		var other: Unit = node as Unit
		if other.is_dead or other.is_staffed or other.team != owner_unit.team:
			continue
		if other.command_state != Unit.CommandState.IDLE and other.command_state != Unit.CommandState.HOLD_POSITION:
			continue
		if other.global_position.distance_squared_to(goal_pos) <= r_sq:
			return true
	return false


func request_nav_toward_point(owner_unit: Unit, target_point: Vector2, repath_threshold: float, stop_distance: float = 0.0) -> void:
	if owner_unit == null:
		return
	var dist_to_target: float = owner_unit.global_position.distance_to(target_point)
	if stop_distance > 0.0 and dist_to_target <= stop_distance:
		return
	if owner_unit.nav_agent == null:
		steer_direct_toward(owner_unit, target_point)
		return
	if last_nav_target == Vector2.INF or last_nav_target.distance_squared_to(target_point) > repath_threshold * repath_threshold:
		set_nav_target(owner_unit, target_point)
	if not is_nav_map_ready(owner_unit):
		steer_direct_toward(owner_unit, target_point)
		return
	if owner_unit.nav_agent.is_navigation_finished():
		var reach_cutoff: float = stop_distance if stop_distance > 0.0 else maxf(owner_unit.nav_agent.target_desired_distance, 6.0)
		if dist_to_target > reach_cutoff:
			steer_direct_toward(owner_unit, target_point)
		return
	compute_nav_desired_velocity(owner_unit)
	if not wants_nav_movement and dist_to_target > maxf(stop_distance, 4.0):
		steer_direct_toward(owner_unit, target_point)


func steer_direct_toward(owner_unit: Unit, target_point: Vector2) -> void:
	var to_target: Vector2 = target_point - owner_unit.global_position
	if to_target.length_squared() <= 4.0:
		return
	var dir: Vector2 = _steer_around_obstacles_and_units(owner_unit, to_target.normalized())
	wants_nav_movement = true
	desired_move_velocity = dir * owner_unit.get_effective_move_speed()


func compute_nav_desired_velocity(owner_unit: Unit) -> void:
	if owner_unit == null or owner_unit.nav_agent == null:
		return
	var next_point: Vector2 = owner_unit.nav_agent.get_next_path_position()
	var to_next: Vector2 = next_point - owner_unit.global_position
	if to_next.length_squared() < 1.0:
		return
	var dir: Vector2 = _steer_around_static_units(owner_unit, to_next.normalized())
	wants_nav_movement = true
	desired_move_velocity = dir * owner_unit.get_effective_move_speed()


func finish_physics_step(owner_unit: Unit, delta: float) -> void:
	if owner_unit == null:
		return
	update_worker_collision_passing(owner_unit)
	apply_anti_stuck_steering(owner_unit, delta)

	if owner_unit.can_unit_move() and owner_unit.nav_agent != null and owner_unit.nav_agent.avoidance_enabled:
		owner_unit.nav_agent.set_velocity(desired_move_velocity)
		if not wants_nav_movement:
			apply_stationary_separation(owner_unit, delta)
	else:
		apply_direct_motion(owner_unit, desired_move_velocity, delta)


func on_nav_velocity_computed(owner_unit: Unit, safe_velocity: Vector2, last_delta: float) -> void:
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed or not wants_nav_movement:
		return
	if owner_unit.nav_agent != null and not owner_unit.nav_agent.avoidance_enabled:
		return
	apply_direct_motion(owner_unit, safe_velocity, last_delta)


func apply_direct_motion(owner_unit: Unit, target_velocity: Vector2, delta: float) -> void:
	var accel: float = owner_unit.data.acceleration if (owner_unit.data != null and owner_unit.data.acceleration > 0.0) else 1800.0
	var eff_speed: float = owner_unit.get_effective_move_speed()
	if wants_nav_movement:
		var combined: Vector2 = target_velocity + compute_overlap_separation(owner_unit, 1.0)
		if combined.length() > eff_speed:
			combined = combined.normalized() * eff_speed
		owner_unit.velocity = owner_unit.velocity.move_toward(combined, accel * delta)
		if owner_unit.velocity.length_squared() > 4.0:
			face_angle(owner_unit, owner_unit.velocity.angle(), delta)
		owner_unit.move_and_slide()
		if SpatialGrid != null:
			SpatialGrid.update_unit(owner_unit)
		_check_post_slide_settling(owner_unit)
	else:
		apply_stationary_separation(owner_unit, delta)


func apply_stationary_separation(owner_unit: Unit, delta: float) -> void:
	if not owner_unit.can_unit_move():
		return
	if owner_unit.command_state == Unit.CommandState.GATHERING and owner_unit.gather_component != null and owner_unit.gather_component.is_harvesting_in_place():
		_apply_harvester_perimeter_separation(owner_unit, delta)
		return
	if owner_unit.command_state == Unit.CommandState.REPAIRING and owner_unit.repair_component != null and bool(owner_unit.repair_component.get("is_repairing_in_place")):
		owner_unit.velocity = Vector2.ZERO
		return
	if owner_unit.command_state == Unit.CommandState.SALVAGING and owner_unit.is_salvaging_in_place():
		owner_unit.velocity = Vector2.ZERO
		return
	if owner_unit.command_state == Unit.CommandState.CONSTRUCTING and owner_unit._construction_target != null and is_instance_valid(owner_unit._construction_target):
		var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
		if owner_unit.global_position.distance_to(owner_unit._construction_target.global_position) <= owner_unit._construction_target.footprint_radius + unit_r + 28.0:
			owner_unit.velocity = Vector2.ZERO
			return
	var sep_margin: float = 0.0 if owner_unit.command_state == Unit.CommandState.HOLD_POSITION else 2.5
	var sep: Vector2 = compute_overlap_separation(owner_unit, sep_margin)
	if sep.length_squared() > 1.0:
		owner_unit.velocity = sep
		owner_unit.move_and_slide()
		if SpatialGrid != null:
			SpatialGrid.update_unit(owner_unit)
	elif owner_unit.velocity.length_squared() > 0.01:
		var decel: float = owner_unit.data.acceleration if (owner_unit.data != null and owner_unit.data.acceleration > 0.0) else 1800.0
		owner_unit.velocity = owner_unit.velocity.move_toward(Vector2.ZERO, decel * delta)
		owner_unit.move_and_slide()
		if SpatialGrid != null:
			SpatialGrid.update_unit(owner_unit)
	else:
		owner_unit.velocity = Vector2.ZERO


func _apply_harvester_perimeter_separation(owner_unit: Unit, _delta: float) -> void:
	var target_rn: ResourceNode = owner_unit.gather_component.target_node if owner_unit.gather_component != null else null
	if target_rn == null or not is_instance_valid(target_rn):
		owner_unit.velocity = Vector2.ZERO
		return
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var min_sep: float = my_r * 1.95
	var query_r: float = my_r * 2.35
	var candidates: Array = SpatialGrid.query_units_in_radius(owner_unit.global_position, query_r, int(owner_unit.team)) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")

	var radial: Vector2 = owner_unit.global_position - target_rn.global_position
	var radial_len: float = radial.length()
	var radial_dir: Vector2 = (radial / radial_len) if radial_len > 0.1 else Vector2.RIGHT
	var tangent: Vector2 = Vector2(-radial_dir.y, radial_dir.x)
	var tangent_push: float = 0.0

	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Unit) or node == owner_unit:
			continue
		var other: Unit = node as Unit
		if other.is_dead or other.is_staffed or other.team != owner_unit.team:
			continue
		if other.command_state != Unit.CommandState.GATHERING or other.gather_component == null:
			continue
		# Only separate against peers actively HARVESTING the same node (immune to passing transit workers)
		if not other.gather_component.is_harvesting_in_place() or other.gather_component.target_node != target_rn:
			continue
		var diff: Vector2 = owner_unit.global_position - other.global_position
		var dist: float = diff.length()
		if dist >= min_sep:
			continue
		var strength: float = clampf((min_sep - dist) / maxf(1.0, min_sep), 0.15, 1.0)
		var side: float = diff.dot(tangent)
		if absf(side) < 0.05:
			side = 1.0 if owner_unit.get_instance_id() > other.get_instance_id() else -1.0
		tangent_push += (1.0 if side >= 0.0 else -1.0) * strength

	if absf(tangent_push) < 0.01:
		owner_unit.velocity = Vector2.ZERO
		return

	var desired_r: float = target_rn.collision_radius + my_r + 6.0
	var radial_corr: Vector2 = radial_dir * clampf((desired_r - radial_len) * 3.0, -45.0, 45.0)
	var nudge_speed: float = clampf(absf(tangent_push), 0.2, 1.0) * 95.0
	owner_unit.velocity = tangent * (1.0 if tangent_push >= 0.0 else -1.0) * nudge_speed + radial_corr
	owner_unit.move_and_slide()
	if SpatialGrid != null:
		SpatialGrid.update_unit(owner_unit)


func update_worker_collision_passing(owner_unit: Unit) -> void:
	if owner_unit.data == null or owner_unit.data.ignore_friendly_unit_collision:
		return
	var is_worker_role: bool = owner_unit.data.can_gather or owner_unit.data.can_staff_compute or owner_unit.can_construct()
	if not is_worker_role:
		return
	# During active task transit (gather, construct, staff, repair, salvage, or moving into a task),
	# slide cleanly past friendly units while still colliding with World (Layer 1) and hostile units.
	var active_type: StringName = owner_unit.active_command.get("type", &"")
	var next_type: StringName = owner_unit.command_queue[0].get("type", &"") if not owner_unit.command_queue.is_empty() else &""
	var is_task_transit: bool = (
		owner_unit.command_state == Unit.CommandState.GATHERING
		or owner_unit.command_state == Unit.CommandState.CONSTRUCTING
		or owner_unit.command_state == Unit.CommandState.STAFFING_BUILDING
		or owner_unit.command_state == Unit.CommandState.REPAIRING
		or owner_unit.command_state == Unit.CommandState.SALVAGING
		or (owner_unit.command_state == Unit.CommandState.MOVING and (
			active_type == &"gather"
			or active_type == &"return_cargo"
			or active_type == &"build"
			or active_type == &"staff"
			or active_type == &"repair"
			or active_type == &"salvage"
			or next_type == &"gather"
			or next_type == &"return_cargo"
			or next_type == &"build"
			or next_type == &"staff"
			or next_type == &"repair"
			or next_type == &"salvage"
		))
	)
	var hostile_bit: int = 4 if int(owner_unit.team) == 0 else 2
	var want_mask: int = (1 | hostile_bit) if is_task_transit else 7
	if owner_unit.collision_mask != want_mask:
		owner_unit.collision_mask = want_mask

	# Disable RVO avoidance on workers during active task transit so Godot's RVO2 solver never
	# zeros safe_velocity behind teammates or resource nodes.
	if owner_unit.nav_agent != null:
		var want_avoidance: bool = not is_task_transit
		if owner_unit.nav_agent.avoidance_enabled != want_avoidance:
			owner_unit.nav_agent.avoidance_enabled = want_avoidance
			if not want_avoidance:
				owner_unit.nav_agent.set_velocity(Vector2.ZERO)


func apply_anti_stuck_steering(owner_unit: Unit, delta: float) -> void:
	if not wants_nav_movement or desired_move_velocity.length_squared() <= 4.0:
		_stuck_sample_pos = owner_unit.global_position
		_stuck_sample_timer = 0.0
		_stuck_accum_time = 0.0
		_stuck_nudge_timer = 0.0
		_stuck_consecutive_nudges = 0
		return

	_stuck_sample_timer += delta
	if _stuck_sample_timer >= 0.25:
		var moved_dist: float = owner_unit.global_position.distance_to(_stuck_sample_pos)
		var actual_speed: float = moved_dist / maxf(0.05, _stuck_sample_timer)
		var eff_speed: float = maxf(1.0, owner_unit.get_effective_move_speed())
		if actual_speed < eff_speed * 0.16:
			_stuck_accum_time += _stuck_sample_timer
			if _stuck_accum_time >= 0.55:
				var forward: Vector2 = desired_move_velocity.normalized()
				if _stuck_consecutive_nudges == 0:
					_stuck_side_sign = _pick_clearer_detour_side(owner_unit, forward)
				elif _stuck_consecutive_nudges >= 2:
					_stuck_side_sign = -_stuck_side_sign
					_stuck_consecutive_nudges = 0
				_stuck_consecutive_nudges += 1
				_stuck_nudge_dir = Vector2(-forward.y, forward.x) * _stuck_side_sign
				_stuck_nudge_timer = 0.65
				_stuck_accum_time = 0.0
				invalidate_nav_path()
		else:
			_stuck_accum_time = 0.0
			if actual_speed >= eff_speed * 0.30:
				_stuck_consecutive_nudges = 0
		_stuck_sample_pos = owner_unit.global_position
		_stuck_sample_timer = 0.0

	if _stuck_nudge_timer > 0.0:
		_stuck_nudge_timer = maxf(0.0, _stuck_nudge_timer - delta)
		var base_dir: Vector2 = desired_move_velocity.normalized()
		var blended: Vector2 = (base_dir * 0.35 + _stuck_nudge_dir * 0.90)
		if blended.length_squared() > 0.001:
			desired_move_velocity = blended.normalized() * owner_unit.get_effective_move_speed()


func compute_overlap_separation(owner_unit: Unit, extra_margin: float) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
	var max_push: float = owner_unit.get_effective_move_speed() * 0.85 if owner_unit.data != null else 220.0
	var self_is_worker: bool = owner_unit.data != null and (owner_unit.data.can_gather or owner_unit.data.can_staff_compute or owner_unit.can_construct())
	var self_in_task: bool = (
		owner_unit.command_state == Unit.CommandState.GATHERING
		or owner_unit.command_state == Unit.CommandState.CONSTRUCTING
		or owner_unit.command_state == Unit.CommandState.STAFFING_BUILDING
		or owner_unit.command_state == Unit.CommandState.REPAIRING
		or owner_unit.command_state == Unit.CommandState.SALVAGING
	)
	var active_dest: Variant = owner_unit.get_active_command_destination() if self_in_task else null
	var self_near_task: bool = active_dest is Vector2 and owner_unit.global_position.distance_squared_to(active_dest as Vector2) <= 105.0 * 105.0

	var query_r: float = my_r + 36.0 + extra_margin
	var candidates: Array = SpatialGrid.query_units_in_radius(owner_unit.global_position, query_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")

	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Unit) or node == owner_unit:
			continue
		var other: Unit = node
		if other.is_dead or other.is_staffed or other.is_queued_for_deletion():
			continue
		if _should_ignore_unit_collision(owner_unit, other):
			continue
		var other_r: float = other.data.collision_radius if other.data != null else 16.0
		var min_dist: float = my_r + other_r + extra_margin
		var diff: Vector2 = owner_unit.global_position - other.global_position
		var dist_sq: float = diff.length_squared()
		if dist_sq >= min_dist * min_dist:
			continue
		var dist: float = sqrt(dist_sq)
		var dir: Vector2 = Vector2.RIGHT.rotated(fmod(float(owner_unit.get_instance_id() % 360) * 1.618, TAU)) if dist < 0.01 else (diff / dist)
		var overlap_ratio: float = clampf((min_dist - dist) / maxf(1.0, min_dist), 0.15, 1.0)
		var push_scale: float = 1.0
		if self_is_worker and other.team == owner_unit.team and other.data != null and (other.data.can_gather or other.data.can_staff_compute or other.can_construct()):
			# True transit ghosting: workers moving to resources or returning cargo pass smoothly through other workers
			if owner_unit.command_state == Unit.CommandState.GATHERING and owner_unit.gather_component != null and not owner_unit.gather_component.is_harvesting_in_place():
				continue
			var other_stationary_working: bool = (
				(other.command_state == Unit.CommandState.GATHERING and other.gather_component != null and other.gather_component.is_harvesting_in_place())
				or (other.command_state == Unit.CommandState.CONSTRUCTING and not other.is_nav_movement_active())
				or (other.command_state == Unit.CommandState.REPAIRING and other.repair_component != null and bool(other.repair_component.get("is_repairing_in_place")))
				or (other.command_state == Unit.CommandState.SALVAGING and other.is_salvaging_in_place())
			)
			if self_near_task and other_stationary_working:
				continue
			if self_in_task or other.command_state == Unit.CommandState.GATHERING or other.command_state == Unit.CommandState.CONSTRUCTING or other.command_state == Unit.CommandState.SALVAGING:
				push_scale = 0.25
		push += dir * max_push * overlap_ratio * push_scale
	return push.normalized() * max_push if push.length() > max_push else push


func get_or_compute_approach_point(
	owner_unit: Unit,
	target_node: Node2D,
	target_radius: float,
	margin: float = 8.0,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null
) -> Vector2:
	if owner_unit == null:
		return Vector2.ZERO
	if target_node == null or not is_instance_valid(target_node):
		clear_cached_approach_point()
		return owner_unit.global_position
	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var bounds: Rect2 = _get_arena_bounds(owner_unit)
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(unit_r + 6.0, unit_r + 6.0),
		bounds.size - Vector2((unit_r + 6.0) * 2.0, (unit_r + 6.0) * 2.0)
	)
	var target_id: int = target_node.get_instance_id()
	var can_reuse: bool = (
		_cached_approach_point != Vector2.INF
		and _cached_approach_target_id == target_id
		and _cached_approach_target_pos.distance_squared_to(target_node.global_position) <= 16.0
		and last_nav_target != Vector2.INF
		and _is_point_clear_of_obstacles(owner_unit, _cached_approach_point, unit_r + 2.0, safe_bounds, ignore_building, ignore_resource)
	)
	if can_reuse:
		return _cached_approach_point

	var computed: Vector2 = find_clear_approach_point(
		owner_unit,
		target_node.global_position,
		target_radius,
		margin,
		ignore_building,
		ignore_resource,
		true
	)
	_cached_approach_point = computed
	_cached_approach_target_pos = target_node.global_position
	_cached_approach_target_id = target_id
	return computed


func find_clear_approach_point(
	owner_unit: Unit,
	target_center: Vector2,
	target_radius: float,
	margin: float = 8.0,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null,
	avoid_friendly_workers: bool = true
) -> Vector2:
	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var stand_dist: float = target_radius + unit_r + margin
	var offset: Vector2 = owner_unit.global_position - target_center
	var base_angle: float = offset.angle() if offset.length_squared() > 0.01 else 0.0
	var slot_bias: float = float((owner_unit.get_instance_id() % 5) - 2) * 0.14 if avoid_friendly_workers else 0.0
	var bounds: Rect2 = _get_arena_bounds(owner_unit)
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(unit_r + 6.0, unit_r + 6.0),
		bounds.size - Vector2((unit_r + 6.0) * 2.0, (unit_r + 6.0) * 2.0)
	)

	var busy_slots: Array[Vector2] = []
	if avoid_friendly_workers and owner_unit.is_inside_tree():
		var nearby_r: float = stand_dist + 84.0
		var nearby_r_sq: float = nearby_r * nearby_r
		var nearby_units: Array = SpatialGrid.query_units_in_radius(target_center, nearby_r + 64.0, int(owner_unit.team)) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
		for node: Variant in nearby_units:
			if not (node is Unit) or not is_instance_valid(node) or node == owner_unit:
				continue
			var other: Unit = node
			if other.is_dead or other.is_staffed or other.team != owner_unit.team:
				continue
			if other.data == null or not (other.data.can_gather or other.data.can_staff_compute or other.can_construct()):
				continue
			var other_working_or_approaching: bool = (
				other.command_state == Unit.CommandState.GATHERING
				or other.command_state == Unit.CommandState.CONSTRUCTING
				or other.command_state == Unit.CommandState.STAFFING_BUILDING
				or other.command_state == Unit.CommandState.REPAIRING
				or other.command_state == Unit.CommandState.SALVAGING
			)
			if not other_working_or_approaching:
				continue
			if other.global_position.distance_squared_to(target_center) <= nearby_r_sq:
				busy_slots.append(other.global_position)
			var other_cached: Vector2 = other.get_cached_approach_point()
			if other_cached != Vector2.INF and other_cached.distance_squared_to(target_center) <= nearby_r_sq:
				busy_slots.append(other_cached)

	var slot_clear_dist: float = unit_r * 1.85
	var slot_clear_sq: float = slot_clear_dist * slot_clear_dist
	var best_fallback: Vector2 = Vector2.INF
	var best_fallback_clearance: float = -1.0

	var steps: int = 16
	var step_angle: float = TAU / float(steps)
	for i: int in range(steps):
		var ring_offset: int = 0 if i == 0 else ((i + 1) >> 1)
		var sign_mult: float = 1.0 if (i % 2) == 1 else -1.0
		var ang: float = base_angle + slot_bias + float(ring_offset) * step_angle * sign_mult
		var cand: Vector2 = target_center + Vector2.RIGHT.rotated(ang) * stand_dist
		if not _is_point_clear_of_obstacles(owner_unit, cand, unit_r + 3.0, safe_bounds, ignore_building, ignore_resource):
			continue
		if busy_slots.is_empty():
			return cand
		var min_slot_sq: float = INF
		for occ: Vector2 in busy_slots:
			min_slot_sq = minf(min_slot_sq, cand.distance_squared_to(occ))
		if min_slot_sq >= slot_clear_sq:
			return cand
		if min_slot_sq > best_fallback_clearance:
			best_fallback_clearance = min_slot_sq
			best_fallback = cand

	if best_fallback != Vector2.INF:
		return best_fallback

	var fallback: Vector2 = target_center + Vector2.RIGHT.rotated(base_angle) * stand_dist
	if safe_bounds.has_area():
		fallback.x = clampf(fallback.x, safe_bounds.position.x, safe_bounds.end.x)
		fallback.y = clampf(fallback.y, safe_bounds.position.y, safe_bounds.end.y)
	return fallback


func face_point(owner_unit: Unit, world_point: Vector2, delta: float) -> void:
	if owner_unit == null:
		return
	var to_point: Vector2 = world_point - owner_unit.global_position
	if to_point.length_squared() > 0.01:
		face_angle(owner_unit, to_point.angle(), delta)


func face_angle(owner_unit: Unit, target_angle: float, delta: float) -> void:
	if owner_unit == null or owner_unit.body_visual == null:
		return
	var turn_speed: float = owner_unit.data.turn_speed if owner_unit.data != null else 14.0
	owner_unit.body_visual.rotation = lerp_angle(owner_unit.body_visual.rotation, target_angle, clampf(turn_speed * delta, 0.0, 1.0))


func _steer_around_obstacles_and_units(owner_unit: Unit, move_dir: Vector2) -> Vector2:
	var steer: Vector2 = _steer_around_static_units(owner_unit, move_dir)
	if not owner_unit.is_inside_tree():
		return steer
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
	var probe_dist: float = my_r + 22.0
	var probe_pt: Vector2 = owner_unit.global_position + steer * probe_dist
	var ignore_b: Building = _get_active_target_building(owner_unit)
	var ignore_rn: ResourceNode = _get_active_target_resource(owner_unit)
	var bounds: Rect2 = _get_arena_bounds(owner_unit)
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(my_r + 4.0, my_r + 4.0),
		bounds.size - Vector2((my_r + 4.0) * 2.0, (my_r + 4.0) * 2.0)
	)
	if _is_point_clear_of_obstacles(owner_unit, probe_pt, my_r + 2.0, safe_bounds, ignore_b, ignore_rn):
		return steer

	var tangent_l: Vector2 = Vector2(-steer.y, steer.x)
	var tangent_r: Vector2 = Vector2(steer.y, -steer.x)
	var left_clear: bool = _is_point_clear_of_obstacles(owner_unit, owner_unit.global_position + (steer * 0.45 + tangent_l * 0.85).normalized() * probe_dist, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	var right_clear: bool = _is_point_clear_of_obstacles(owner_unit, owner_unit.global_position + (steer * 0.45 + tangent_r * 0.85).normalized() * probe_dist, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	if left_clear and not right_clear:
		return (steer * 0.40 + tangent_l * 0.90).normalized()
	if right_clear and not left_clear:
		return (steer * 0.40 + tangent_r * 0.90).normalized()
	var chosen_t: Vector2 = tangent_l if _stuck_side_sign >= 0.0 else tangent_r
	return (steer * 0.35 + chosen_t * 0.92).normalized()


func _steer_around_static_units(owner_unit: Unit, move_dir: Vector2) -> Vector2:
	var steer: Vector2 = move_dir
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
	var scan_r: float = my_r + 58.0
	var candidates: Array = SpatialGrid.query_units_in_radius(owner_unit.global_position, scan_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Unit) or node == owner_unit:
			continue
		var other: Unit = node
		if other.is_dead or other.is_staffed or other.is_queued_for_deletion() or other.can_unit_move():
			continue
		if _should_ignore_unit_collision(owner_unit, other):
			continue
		var to_other: Vector2 = other.global_position - owner_unit.global_position
		var dist: float = to_other.length()
		var other_r: float = other.data.collision_radius if other.data != null else 18.0
		var avoid_dist: float = my_r + other_r + 36.0
		if dist <= 0.001 or dist > avoid_dist:
			continue
		var to_other_dir: Vector2 = to_other / dist
		if move_dir.dot(to_other_dir) <= 0.15:
			continue
		var side: float = -1.0 if move_dir.cross(to_other_dir) >= 0.0 else 1.0
		var tangent: Vector2 = Vector2(-to_other_dir.y, to_other_dir.x) * side
		var weight: float = clampf((avoid_dist - dist) / avoid_dist, 0.25, 1.0) * 1.4
		steer += tangent * weight
	return steer.normalized() if steer.length_squared() > 0.0001 else move_dir


func _pick_clearer_detour_side(owner_unit: Unit, forward: Vector2) -> float:
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
	var bounds: Rect2 = _get_arena_bounds(owner_unit)
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(my_r + 6.0, my_r + 6.0),
		bounds.size - Vector2((my_r + 6.0) * 2.0, (my_r + 6.0) * 2.0)
	)
	var ignore_b: Building = _get_active_target_building(owner_unit)
	var ignore_rn: ResourceNode = _get_active_target_resource(owner_unit)
	var probe_r: float = my_r + 24.0
	var pos_dir: Vector2 = Vector2(-forward.y, forward.x)
	var neg_dir: Vector2 = Vector2(forward.y, -forward.x)
	var pos_clear: bool = _is_point_clear_of_obstacles(owner_unit, owner_unit.global_position + pos_dir * probe_r, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	var neg_clear: bool = _is_point_clear_of_obstacles(owner_unit, owner_unit.global_position + neg_dir * probe_r, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	if pos_clear and not neg_clear:
		return 1.0
	if neg_clear and not pos_clear:
		return -1.0
	return _stuck_side_sign


func _check_post_slide_settling(owner_unit: Unit) -> void:
	if owner_unit.command_state != Unit.CommandState.MOVING and not (owner_unit.command_state == Unit.CommandState.ATTACK_MOVING and owner_unit.current_target == null):
		return
	var goal_pos: Vector2 = owner_unit._move_destination if owner_unit.command_state == Unit.CommandState.MOVING else owner_unit._attack_move_destination
	if owner_unit.global_position.distance_to(goal_pos) > SETTLE_PROXIMITY_RADIUS:
		return
	for i: int in range(owner_unit.get_slide_collision_count()):
		var collider: Object = owner_unit.get_slide_collision(i).get_collider()
		if collider is Unit:
			var other: Unit = collider
			if other.team == owner_unit.team and (other.command_state == Unit.CommandState.IDLE or other.command_state == Unit.CommandState.HOLD_POSITION):
				wants_nav_movement = false
				reset_progress_tracker(owner_unit)
				owner_unit.advance_command_queue()
				return


func _should_ignore_unit_collision(owner_unit: Unit, other: Unit) -> bool:
	if other == null or owner_unit.data == null or other.data == null:
		return false
	if other.team != owner_unit.team:
		return false
	var self_strider: bool = owner_unit.data.ignore_friendly_unit_collision
	var other_strider: bool = other.data.ignore_friendly_unit_collision
	return self_strider != other_strider


func _get_active_target_building(owner_unit: Unit) -> Building:
	if owner_unit.command_state == Unit.CommandState.CONSTRUCTING and is_instance_valid(owner_unit._construction_target):
		return owner_unit._construction_target
	if owner_unit.command_state == Unit.CommandState.STAFFING_BUILDING and owner_unit.staff_component != null and is_instance_valid(owner_unit.staff_component.target_building):
		return owner_unit.staff_component.target_building
	if owner_unit.command_state == Unit.CommandState.GATHERING and owner_unit.gather_component != null and owner_unit.gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and is_instance_valid(owner_unit.gather_component.dropoff_building):
		return owner_unit.gather_component.dropoff_building
	if owner_unit.command_state == Unit.CommandState.REPAIRING and owner_unit.repair_component != null:
		var rep_t: Variant = owner_unit.repair_component.get("target_entity")
		if rep_t is Building and is_instance_valid(rep_t):
			return rep_t as Building
	return null


func _get_active_target_resource(owner_unit: Unit) -> ResourceNode:
	if owner_unit.command_state == Unit.CommandState.GATHERING and owner_unit.gather_component != null and is_instance_valid(owner_unit.gather_component.target_node):
		return owner_unit.gather_component.target_node
	return null


func _get_arena_bounds(owner_unit: Unit) -> Rect2:
	if owner_unit != null and owner_unit.is_inside_tree():
		var nav_reg: Node = owner_unit.get_tree().get_first_node_in_group("arena_nav_region")
		if nav_reg != null and "arena_bounds" in nav_reg:
			var b: Variant = nav_reg.get("arena_bounds")
			if b is Rect2:
				return b as Rect2
	return Rect2(-1300.0, -950.0, 2600.0, 1900.0)


func _is_point_clear_of_obstacles(
	owner_unit: Unit,
	world_pos: Vector2,
	clearance_radius: float,
	safe_bounds: Rect2,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null
) -> bool:
	if safe_bounds.has_area() and not safe_bounds.has_point(world_pos):
		return false
	if owner_unit == null or not owner_unit.is_inside_tree():
		return true
	var tree: SceneTree = owner_unit.get_tree()
	for node: Node in tree.get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_radius)):
				return false
	for node: Node in tree.get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_radius)):
				return false
	for node: Node in tree.get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(node) and not bool(node.get("is_destroyed")) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_radius)):
				return false
	var nearby_b: Array = SpatialGrid.query_buildings_in_radius(world_pos, clearance_radius + 80.0) if SpatialGrid != null else tree.get_nodes_in_group("buildings")
	for node: Variant in nearby_b:
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b == ignore_building:
			continue
		var min_d: float = b.footprint_radius + clearance_radius
		if b.global_position.distance_squared_to(world_pos) < min_d * min_d:
			return false
	for node: Node in tree.get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted() or rn.is_vent or rn == ignore_resource:
			continue
		var min_d: float = rn.collision_radius + clearance_radius
		if rn.global_position.distance_squared_to(world_pos) < min_d * min_d:
			return false
	return true
