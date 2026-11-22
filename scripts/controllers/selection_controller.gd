class_name SelectionController
extends Node2D

const MOVE_MARKER_SCRIPT: GDScript = preload("res://ui/overlays/move_marker.gd")

signal selection_updated(selected_count: int)
signal command_mode_changed(mode_name: String)

@export var drag_threshold: float = 6.0

@onready var selection_box: SelectionBox = $SelectionBox

var selected_units: Array[Unit] = []
var inspected_enemy: Unit = null
var is_attack_move_armed: bool = false

var _is_dragging: bool = false
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_start_screen: Vector2 = Vector2.ZERO


func _process(_delta: float) -> void:
	if is_attack_move_armed:
		queue_redraw()


func _draw() -> void:
	if not is_attack_move_armed:
		return
	var local_mouse: Vector2 = to_local(get_global_mouse_position())
	var col: Color = Color(1.0, 0.38, 0.26, 0.9)
	draw_arc(local_mouse, 12.0, 0.0, TAU, 24, col, 1.8, true)
	draw_line(local_mouse + Vector2(-17.0, 0.0), local_mouse + Vector2(-7.0, 0.0), col, 1.8, true)
	draw_line(local_mouse + Vector2(7.0, 0.0), local_mouse + Vector2(17.0, 0.0), col, 1.8, true)
	draw_line(local_mouse + Vector2(0.0, -17.0), local_mouse + Vector2(0.0, -7.0), col, 1.8, true)
	draw_line(local_mouse + Vector2(0.0, 7.0), local_mouse + Vector2(0.0, 17.0), col, 1.8, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cmd_cancel"):
		if is_attack_move_armed:
			_set_attack_move_armed(false)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_attack_move"):
		_prune_invalid_units()
		if not selected_units.is_empty():
			_set_attack_move_armed(true)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_stop"):
		_set_attack_move_armed(false)
		_issue_stop_to_selected()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_hold"):
		_set_attack_move_armed(false)
		_issue_hold_to_selected()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if is_attack_move_armed:
					_execute_armed_attack_move(get_global_mouse_position())
					get_viewport().set_input_as_handled()
					return
				_is_dragging = true
				_drag_start_world = get_global_mouse_position()
				_drag_start_screen = mouse_event.position
			elif _is_dragging:
				_finish_left_selection(mouse_event.position)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			if is_attack_move_armed:
				_set_attack_move_armed(false)
				get_viewport().set_input_as_handled()
				return
			_handle_right_click(get_global_mouse_position())
	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event: InputEventMouseMotion = event
		if motion_event.position.distance_to(_drag_start_screen) >= drag_threshold:
			var rect: Rect2 = _build_world_rect(_drag_start_world, get_global_mouse_position())
			selection_box.update_box(rect, true)


func clear_selection() -> void:
	_set_attack_move_armed(false)
	_set_inspected_enemy(null)
	_set_selected_units([])


func select_in_world_rect(world_rect: Rect2) -> void:
	_select_in_rect(world_rect)


func select_at_world_point(world_point: Vector2) -> void:
	_select_at_point(world_point)


func issue_right_click_at(world_point: Vector2) -> void:
	_handle_right_click(world_point)


func issue_attack_move_at(world_point: Vector2) -> void:
	_execute_armed_attack_move(world_point)


func issue_stop_command() -> void:
	_set_attack_move_armed(false)
	_issue_stop_to_selected()


func issue_hold_command() -> void:
	_set_attack_move_armed(false)
	_issue_hold_to_selected()


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

	if selected_units.is_empty():
		_set_attack_move_armed(false)
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
		for unit: Unit in selected_units:
			unit.command_move(world_pos)
		_spawn_move_marker(world_pos, MoveMarker.MarkerStyle.MOVE)


func _execute_armed_attack_move(world_pos: Vector2) -> void:
	_set_attack_move_armed(false)
	_prune_invalid_units()
	if selected_units.is_empty():
		return

	var clicked_enemy: Unit = _find_unit_at_point(world_pos, Unit.Team.ENEMY)
	if clicked_enemy != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy)
		_spawn_move_marker(clicked_enemy.global_position, MoveMarker.MarkerStyle.ATTACK)
	else:
		for unit: Unit in selected_units:
			unit.command_attack_move(world_pos)
		_spawn_move_marker(world_pos, MoveMarker.MarkerStyle.ATTACK)


func _issue_stop_to_selected() -> void:
	_prune_invalid_units()
	for unit: Unit in selected_units:
		unit.command_stop()


func _issue_hold_to_selected() -> void:
	_prune_invalid_units()
	for unit: Unit in selected_units:
		unit.command_hold_position()


func _set_attack_move_armed(armed: bool) -> void:
	if is_attack_move_armed == armed:
		return
	is_attack_move_armed = armed
	if is_attack_move_armed:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		command_mode_changed.emit("ATTACK_MOVE")
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		command_mode_changed.emit("NORMAL")
	queue_redraw()


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
