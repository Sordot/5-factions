class_name BuildGhostPreview
extends Node2D

var _active: bool = false
var _building_data: BuildingData = null
var _world_pos: Vector2 = Vector2.ZERO
var _is_valid: bool = false
var _status_text: String = ""
var _snapped_vent: ResourceNode = null


func set_preview(
	building_data: BuildingData,
	world_pos: Vector2,
	is_valid: bool,
	status_text: String = "",
	snapped_vent: ResourceNode = null
) -> void:
	_building_data = building_data
	_active = building_data != null
	_world_pos = world_pos
	_is_valid = is_valid
	_status_text = status_text
	_snapped_vent = snapped_vent
	queue_redraw()


func clear_preview() -> void:
	if not _active:
		return
	_active = false
	_building_data = null
	_snapped_vent = null
	_status_text = ""
	queue_redraw()


func _draw() -> void:
	if not _active or _building_data == null:
		return

	var center: Vector2 = to_local(_world_pos)
	var size: Vector2 = _building_data.footprint_size
	var half: Vector2 = size * 0.5
	var rect: Rect2 = Rect2(center - half, size)

	var line_col: Color = Color(0.24, 0.98, 0.76, 0.95) if _is_valid else Color(1.0, 0.30, 0.26, 0.95)
	var fill_col: Color = Color(line_col.r, line_col.g, line_col.b, 0.20)

	draw_rect(rect, fill_col, true)
	draw_rect(rect, line_col, false, 2.2)

	# Cross-hatch accent lines inside footprint
	var grid_col: Color = Color(line_col.r, line_col.g, line_col.b, 0.32)
	draw_line(center + Vector2(-half.x, 0.0), center + Vector2(half.x, 0.0), grid_col, 1.2, true)
	draw_line(center + Vector2(0.0, -half.y), center + Vector2(0.0, half.y), grid_col, 1.2, true)
	draw_arc(center, minf(half.x, half.y) * 0.65, 0.0, TAU, 28, grid_col, 1.4, true)

	if _snapped_vent != null and is_instance_valid(_snapped_vent):
		var vent_local: Vector2 = to_local(_snapped_vent.global_position)
		draw_arc(vent_local, maxf(half.x, half.y) + 8.0, 0.0, TAU, 36, Color(0.32, 0.92, 1.0, 0.9), 2.0, true)

	# Tooltip pill above footprint
	if not _status_text.is_empty():
		var display_text: String = _status_text
		if _is_valid and Input.is_key_pressed(KEY_SHIFT):
			display_text += "  [SHIFT: CHAIN]"
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 12
		var text_size: Vector2 = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pill_w: float = text_size.x + 16.0
		var pill_h: float = text_size.y + 8.0
		var pill_pos: Vector2 = Vector2(center.x - pill_w * 0.5, rect.position.y - pill_h - 8.0)
		draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.04, 0.07, 0.11, 0.9), true)
		draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), line_col, false, 1.2)
		var text_pos: Vector2 = Vector2(pill_pos.x + 8.0, pill_pos.y + pill_h - 6.0)
		draw_string(font, text_pos, display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, line_col)
