class_name SelectionBox
extends Node2D

@export var fill_color: Color = Color(0.2, 0.92, 0.85, 0.16)
@export var border_color: Color = Color(0.35, 0.98, 0.92, 0.85)
@export var border_width: float = 2.0

var _active: bool = false
var _world_rect: Rect2 = Rect2()


func update_box(world_rect: Rect2, active: bool) -> void:
	_world_rect = world_rect
	_active = active
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var local_pos: Vector2 = to_local(_world_rect.position)
	var local_rect: Rect2 = Rect2(local_pos, _world_rect.size)
	draw_rect(local_rect, fill_color, true)
	draw_rect(local_rect, border_color, false, border_width)
