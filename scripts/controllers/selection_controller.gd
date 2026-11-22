class_name SelectionController
extends Node2D

const MOVE_MARKER_SCRIPT: GDScript = preload("res://ui/overlays/move_marker.gd")

@export var drag_threshold: float = 6.0

@onready var selection_box: SelectionBox = $SelectionBox

var selected_units: Array[Unit] = []
var _is_dragging: bool = false
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_start_screen: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
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
			_issue_move_to_selected(get_global_mouse_position())
	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event: InputEventMouseMotion = event
		if motion_event.position.distance_to(_drag_start_screen) >= drag_threshold:
			var rect: Rect2 = _build_world_rect(_drag_start_world, get_global_mouse_position())
			selection_box.update_box(rect, true)


func _finish_left_selection(end_screen_pos: Vector2) -> void:
	_is_dragging = false
	selection_box.update_box(Rect2(), false)

	var end_world_pos: Vector2 = get_global_mouse_position()
	if end_screen_pos.distance_to(_drag_start_screen) < drag_threshold:
		_select_at_point(end_world_pos)
	else:
		_select_in_rect(_build_world_rect(_drag_start_world, end_world_pos))


func _select_at_point(world_point: Vector2) -> void:
	var clicked_unit: Unit = null
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if node is Unit and node.contains_point(world_point):
			clicked_unit = node
			break

	if clicked_unit != null:
		_set_selected_units([clicked_unit])
	else:
		_set_selected_units([])


func _select_in_rect(world_rect: Rect2) -> void:
	var hits: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if node is Unit and world_rect.has_point(node.global_position):
			hits.append(node)
	_set_selected_units(hits)


func _set_selected_units(new_selection: Array[Unit]) -> void:
	for unit: Unit in selected_units:
		if is_instance_valid(unit) and not new_selection.has(unit):
			unit.set_selected(false)

	selected_units = new_selection
	for unit: Unit in selected_units:
		if is_instance_valid(unit):
			unit.set_selected(true)


func _issue_move_to_selected(target_pos: Vector2) -> void:
	_prune_invalid_units()
	if selected_units.is_empty():
		return

	for unit: Unit in selected_units:
		unit.issue_move_command(target_pos)

	_spawn_move_marker(target_pos)


func _spawn_move_marker(target_pos: Vector2) -> void:
	var marker: Node2D = MOVE_MARKER_SCRIPT.new()
	marker.global_position = target_pos
	get_parent().add_child(marker)


func _prune_invalid_units() -> void:
	var valid: Array[Unit] = []
	for unit: Unit in selected_units:
		if is_instance_valid(unit):
			valid.append(unit)
	selected_units = valid


func _build_world_rect(a: Vector2, b: Vector2) -> Rect2:
	var top_left: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size: Vector2 = Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(top_left, size)
