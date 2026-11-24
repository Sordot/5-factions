class_name SelectionBox
extends Node2D

@export var fill_color: Color = Color(0.2, 0.92, 0.85, 0.16)
@export var border_color: Color = Color(0.35, 0.98, 0.92, 0.88)
@export var smart_fill_color: Color = Color(0.96, 0.62, 0.04, 0.18)
@export var smart_border_color: Color = Color(0.96, 0.62, 0.04, 0.94)
@export var border_width: float = 1.5

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

	var cam_zoom_x: float = 1.0
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		var cam: Camera2D = vp.get_camera_2d() if vp != null else null
		if cam != null:
			cam_zoom_x = maxf(0.25, cam.zoom.x)

	var line_w: float = clampf(border_width / cam_zoom_x, 0.9, 3.0)
	draw_rect(local_rect, f_col, true)
	draw_rect(local_rect, b_col, false, line_w)

	# Crisp zoom-scaled Technozen corner bracket ticks for sharper marquee framing
	var min_side: float = minf(absf(local_rect.size.x), absf(local_rect.size.y))
	var tick_len: float = minf(clampf(6.0 / cam_zoom_x, 3.0, 12.0), min_side * 0.38)
	if tick_len >= 2.0:
		var corner_col: Color = b_col.lightened(0.18)
		var corner_w: float = clampf(line_w * 1.35, 1.2, 3.6)
		var tl: Vector2 = local_rect.position
		var tr: Vector2 = Vector2(local_rect.end.x, local_rect.position.y)
		var bl: Vector2 = Vector2(local_rect.position.x, local_rect.end.y)
		var br: Vector2 = local_rect.end
		draw_line(tl, tl + Vector2(tick_len, 0.0), corner_col, corner_w)
		draw_line(tl, tl + Vector2(0.0, tick_len), corner_col, corner_w)
		draw_line(tr, tr + Vector2(-tick_len, 0.0), corner_col, corner_w)
		draw_line(tr, tr + Vector2(0.0, tick_len), corner_col, corner_w)
		draw_line(bl, bl + Vector2(tick_len, 0.0), corner_col, corner_w)
		draw_line(bl, bl + Vector2(0.0, -tick_len), corner_col, corner_w)
		draw_line(br, br + Vector2(-tick_len, 0.0), corner_col, corner_w)
		draw_line(br, br + Vector2(0.0, -tick_len), corner_col, corner_w)
