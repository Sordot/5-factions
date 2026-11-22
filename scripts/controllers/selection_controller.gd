class_name SelectionController
extends Node2D

const MOVE_MARKER_SCRIPT: GDScript = preload("res://ui/overlays/move_marker.gd")
const DOUBLE_TAP_WINDOW_MS: int = 350
const DEFAULT_UNIT_RADIUS: float = 16.0
const RING_SPACING_MULTIPLIER: float = 2.6

signal selection_updated(selected_count: int)
signal control_groups_changed(summary: Dictionary)

@export var drag_threshold: float = 6.0
@export var camera_path: NodePath

@onready var selection_box: SelectionBox = $SelectionBox

var selected_units: Array[Unit] = []
var inspected_enemy: Unit = null
var control_groups: Dictionary = {}

var _is_dragging: bool = false
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_start_screen: Vector2 = Vector2.ZERO
var _last_recall_group: int = -1
var _last_recall_time_ms: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			var group_num: int = _get_control_group_key(key_event)
			if group_num > 0:
				_handle_control_group_key(group_num, key_event)
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("cmd_attack_move"):
		if event is InputEventKey:
			var a_key: InputEventKey = event
			if a_key.ctrl_pressed or a_key.shift_pressed or a_key.alt_pressed or a_key.echo:
				return
		issue_attack_move_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_stop"):
		issue_stop_command()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_hold"):
		issue_hold_command()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_is_dragging = true
				_drag_start_world = get_global_mouse_position()
				_drag_start_screen = mouse_event.position
			elif _is_dragging:
				_finish_left_selection(mouse_event.position)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_handle_right_click(get_global_mouse_position())
	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event: InputEventMouseMotion = event
		if motion_event.position.distance_to(_drag_start_screen) >= drag_threshold:
			var rect: Rect2 = _build_world_rect(_drag_start_world, get_global_mouse_position())
			selection_box.update_box(rect, true)


func clear_selection() -> void:
	_set_inspected_enemy(null)
	_set_selected_units([])


func select_in_world_rect(world_rect: Rect2) -> void:
	_select_in_rect(world_rect)


func select_at_world_point(world_point: Vector2) -> void:
	_select_at_point(world_point)


func issue_right_click_at(world_point: Vector2) -> void:
	_handle_right_click(world_point)


func issue_attack_move_at(world_point: Vector2) -> void:
	_prune_invalid_units()
	if selected_units.is_empty():
		return

	var clicked_enemy: Unit = _find_unit_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy)
		_spawn_move_marker(clicked_enemy.global_position, MoveMarker.MarkerStyle.ATTACK)
	else:
		var targets: Array[Vector2] = _assign_group_destinations(selected_units, world_point)
		for i: int in range(selected_units.size()):
			selected_units[i].command_attack_move(targets[i])
		_spawn_move_marker(world_point, MoveMarker.MarkerStyle.ATTACK)


func issue_stop_command() -> void:
	_prune_invalid_units()
	for unit: Unit in selected_units:
		unit.command_stop()


func issue_hold_command() -> void:
	_prune_invalid_units()
	for unit: Unit in selected_units:
		unit.command_hold_position()


func assign_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if selected_units.is_empty():
		return
	control_groups[group_num] = selected_units.duplicate()
	_emit_control_groups_changed()


func append_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if selected_units.is_empty():
		return
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	for unit: Unit in selected_units:
		if not group_units.has(unit):
			group_units.append(unit)
	if not group_units.is_empty():
		control_groups[group_num] = group_units
	_emit_control_groups_changed()


func remove_from_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if not control_groups.has(group_num):
		return
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	var remaining: Array[Unit] = []
	for unit: Unit in group_units:
		if not selected_units.has(unit):
			remaining.append(unit)
	if remaining.is_empty():
		control_groups.erase(group_num)
	else:
		control_groups[group_num] = remaining
	_emit_control_groups_changed()


func recall_control_group(group_num: int, allow_double_tap_center: bool = true) -> void:
	if group_num < 1 or group_num > 9:
		return
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	if group_units.is_empty():
		control_groups.erase(group_num)
		_emit_control_groups_changed()
		return

	control_groups[group_num] = group_units
	_set_inspected_enemy(null)
	_set_selected_units(group_units)
	_emit_control_groups_changed()

	if allow_double_tap_center:
		var now_ms: int = Time.get_ticks_msec()
		if _last_recall_group == group_num and (now_ms - _last_recall_time_ms) <= DOUBLE_TAP_WINDOW_MS:
			_center_camera_on_units(group_units)
			_last_recall_group = -1
			_last_recall_time_ms = 0
		else:
			_last_recall_group = group_num
			_last_recall_time_ms = now_ms


func get_control_group_units(group_num: int) -> Array[Unit]:
	return _get_pruned_group(group_num)


func get_control_groups_summary() -> Dictionary:
	var summary: Dictionary = {}
	for num: int in range(1, 10):
		if not control_groups.has(num):
			continue
		var group_units: Array[Unit] = _get_pruned_group(num)
		if group_units.is_empty():
			control_groups.erase(num)
		else:
			control_groups[num] = group_units
			summary[num] = group_units.size()
	return summary


func clear_control_groups() -> void:
	control_groups.clear()
	_emit_control_groups_changed()


func _handle_control_group_key(group_num: int, key_event: InputEventKey) -> void:
	if key_event.ctrl_pressed:
		assign_control_group(group_num)
	elif key_event.shift_pressed:
		append_control_group(group_num)
	elif key_event.alt_pressed:
		remove_from_control_group(group_num)
	else:
		recall_control_group(group_num, true)


func _get_control_group_key(key_event: InputEventKey) -> int:
	var code: Key = key_event.physical_keycode
	if code < KEY_1 or code > KEY_9:
		code = key_event.keycode
	if code >= KEY_1 and code <= KEY_9:
		return int(code - KEY_1) + 1
	return 0


func _get_pruned_group(group_num: int) -> Array[Unit]:
	var valid: Array[Unit] = []
	if not control_groups.has(group_num):
		return valid
	var raw: Variant = control_groups[group_num]
	if raw is Array:
		for item: Variant in raw:
			if is_instance_valid(item) and item is Unit:
				var unit: Unit = item
				if not unit.is_dead and unit.team == Unit.Team.PLAYER:
					valid.append(unit)
	return valid


func _emit_control_groups_changed() -> void:
	control_groups_changed.emit(get_control_groups_summary())


func _center_camera_on_units(units: Array[Unit]) -> void:
	if units.is_empty():
		return
	var cam: RTSCamera = _get_rts_camera()
	if cam == null:
		return
	var centroid: Vector2 = Vector2.ZERO
	for unit: Unit in units:
		centroid += unit.global_position
	centroid /= float(units.size())
	cam.center_on(centroid)


func _get_rts_camera() -> RTSCamera:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as RTSCamera
	if get_parent() != null:
		return get_parent().get_node_or_null("RTSCamera") as RTSCamera
	return null


func _finish_left_selection(end_screen_pos: Vector2) -> void:
	_is_dragging = false
	selection_box.update_box(Rect2(), false)

	var end_world_pos: Vector2 = get_global_mouse_position()
	if end_screen_pos.distance_to(_drag_start_screen) < drag_threshold:
		_select_at_point(end_world_pos)
	else:
		_select_in_rect(_build_world_rect(_drag_start_world, end_world_pos))


func _select_at_point(world_point: Vector2) -> void:
	var clicked_player: Unit = _find_unit_at_point(world_point, Unit.Team.PLAYER)
	if clicked_player != null:
		_set_inspected_enemy(null)
		_set_selected_units([clicked_player])
		return

	var clicked_enemy: Unit = _find_unit_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy != null:
		_set_selected_units([])
		_set_inspected_enemy(clicked_enemy)
		return

	_set_inspected_enemy(null)
	_set_selected_units([])


func _select_in_rect(world_rect: Rect2) -> void:
	_set_inspected_enemy(null)
	var hits: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead:
			continue
		if unit.team != Unit.Team.PLAYER:
			continue
		if world_rect.has_point(unit.global_position):
			hits.append(unit)
	_set_selected_units(hits)


func _set_selected_units(new_selection: Array[Unit]) -> void:
	for item: Variant in selected_units:
		if is_instance_valid(item) and item is Unit:
			var prev_unit: Unit = item
			if not new_selection.has(prev_unit):
				prev_unit.set_selected(false)

	selected_units = []
	for item: Variant in new_selection:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if not unit.is_dead and unit.team == Unit.Team.PLAYER:
				selected_units.append(unit)
				unit.set_selected(true)

	selection_updated.emit(selected_units.size())


func _set_inspected_enemy(enemy: Unit) -> void:
	if inspected_enemy != null and is_instance_valid(inspected_enemy) and inspected_enemy != enemy:
		inspected_enemy.set_selected(false)
	inspected_enemy = enemy
	if inspected_enemy != null and is_instance_valid(inspected_enemy):
		inspected_enemy.set_selected(true)


func _handle_right_click(world_pos: Vector2) -> void:
	_prune_invalid_units()
	if selected_units.is_empty():
		return

	var clicked_enemy: Unit = _find_unit_at_point(world_pos, Unit.Team.ENEMY)
	if clicked_enemy != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy)
		_spawn_move_marker(clicked_enemy.global_position, MoveMarker.MarkerStyle.ATTACK)
	else:
		var targets: Array[Vector2] = _assign_group_destinations(selected_units, world_pos)
		for i: int in range(selected_units.size()):
			selected_units[i].command_move(targets[i])
		_spawn_move_marker(world_pos, MoveMarker.MarkerStyle.MOVE)


func _assign_group_destinations(units: Array[Unit], center_pos: Vector2) -> Array[Vector2]:
	var count: int = units.size()
	var assigned: Array[Vector2] = []
	if count == 0:
		return assigned

	var map_rid: RID = _get_navigation_map(units[0])
	var has_map: bool = map_rid.is_valid() and NavigationServer2D.map_get_iteration_id(map_rid) > 0
	if count == 1:
		var single_pos: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, center_pos) if has_map else center_pos
		assigned.append(single_pos)
		return assigned

	var unit_radius: float = units[0].data.collision_radius if units[0].data != null else DEFAULT_UNIT_RADIUS
	var spacing: float = unit_radius * RING_SPACING_MULTIPLIER
	var slots: Array[Vector2] = _generate_ring_slots(count, center_pos, spacing, map_rid, has_map)

	# Greedy nearest-slot assignment avoids units crisscrossing through each other.
	var used: Array[bool] = []
	used.resize(slots.size())
	used.fill(false)
	assigned.resize(count)

	for i: int in range(count):
		var u_pos: Vector2 = units[i].global_position
		var best_idx: int = 0
		var best_dist_sq: float = INF
		for s_idx: int in range(slots.size()):
			if used[s_idx]:
				continue
			var d_sq: float = u_pos.distance_squared_to(slots[s_idx])
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_idx = s_idx
		used[best_idx] = true
		assigned[i] = slots[best_idx]

	return assigned


func _generate_ring_slots(count: int, center_pos: Vector2, spacing: float, map_rid: RID, has_map: bool) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var first_pos: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, center_pos) if has_map else center_pos
	slots.append(first_pos)

	var ring: int = 1
	while slots.size() < count:
		var ring_radius: float = float(ring) * spacing
		var circumference: float = TAU * ring_radius
		var ring_slots: int = maxi(6, int(round(circumference / spacing)))
		var angle_offset: float = 0.0 if (ring % 2) == 1 else (PI / float(ring_slots))
		for k: int in range(ring_slots):
			if slots.size() >= count:
				break
			var angle: float = angle_offset + (TAU * float(k) / float(ring_slots))
			var candidate: Vector2 = center_pos + Vector2.RIGHT.rotated(angle) * ring_radius
			if has_map:
				candidate = NavigationServer2D.map_get_closest_point(map_rid, candidate)
			slots.append(candidate)
		ring += 1

	return slots


func _get_navigation_map(sample_unit: Unit) -> RID:
	if sample_unit != null and sample_unit.nav_agent != null:
		return sample_unit.nav_agent.get_navigation_map()
	return get_world_2d().navigation_map


func _find_unit_at_point(world_point: Vector2, target_team: Unit.Team) -> Unit:
	var closest: Unit = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.team != target_team:
			continue
		if unit.contains_point(world_point):
			var dist_sq: float = unit.global_position.distance_squared_to(world_point)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest = unit
	return closest


func _spawn_move_marker(target_pos: Vector2, marker_style: MoveMarker.MarkerStyle) -> void:
	if get_parent() == null:
		return
	var marker: MoveMarker = MOVE_MARKER_SCRIPT.new()
	marker.global_position = target_pos
	marker.z_index = 60
	get_parent().add_child(marker)
	marker.configure(marker_style)


func _prune_invalid_units() -> void:
	var valid: Array[Unit] = []
	for item: Variant in selected_units:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if not unit.is_dead and unit.team == Unit.Team.PLAYER:
				valid.append(unit)
	if valid.size() != selected_units.size():
		selected_units = valid
		selection_updated.emit(selected_units.size())
	if inspected_enemy != null and (not is_instance_valid(inspected_enemy) or inspected_enemy.is_dead):
		inspected_enemy = null


func _build_world_rect(a: Vector2, b: Vector2) -> Rect2:
	var top_left: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size: Vector2 = Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(top_left, size)
