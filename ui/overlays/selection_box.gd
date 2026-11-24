class_name SelectionBox
extends Node2D

@export var fill_color: Color = Color(0.2, 0.92, 0.85, 0.16)
@export var border_color: Color = Color(0.35, 0.98, 0.92, 0.85)
@export var smart_fill_color: Color = Color(0.96, 0.62, 0.04, 0.18)
@export var smart_border_color: Color = Color(0.96, 0.62, 0.04, 0.94)
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
	var smart_mode: bool = SettingsManager != null and SettingsManager.smart_box_select_enabled
	var f_col: Color = smart_fill_color if smart_mode else fill_color
	var b_col: Color = smart_border_color if smart_mode else border_color
	draw_rect(local_rect, f_col, true)
	draw_rect(local_rect, b_col, false, border_width)
