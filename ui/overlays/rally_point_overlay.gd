class_name RallyPointOverlay
extends Node2D

const DASH_LENGTH: float = 12.0
const GAP_LENGTH: float = 8.0

var _inspected_building: Building = null
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("rally_point_overlay")
	z_index = 85


func bind_selection_controller(controller: Node) -> void:
	if controller == null:
		return
	if controller.has_signal("inspection_changed") and not controller.is_connected("inspection_changed", _on_inspection_changed):
		controller.connect("inspection_changed", _on_inspection_changed)
	var current_entity: Node = controller.get("inspected_entity") as Node
	_on_inspection_changed(current_entity)


func _on_inspection_changed(entity: Node) -> void:
	_disconnect_building()
	if entity != null and is_instance_valid(entity) and entity is Building:
		var b: Building = entity
		if not b.is_destroyed and b.team == Unit.Team.PLAYER and b.can_set_rally:
			_inspected_building = b
			if not b.rally_changed.is_connected(_on_building_changed):
				b.rally_changed.connect(_on_building_changed)
			if not b.destroyed.is_connected(_on_building_destroyed):
				b.destroyed.connect(_on_building_destroyed)
	queue_redraw()


func _on_building_changed(_building: Building) -> void:
	queue_redraw()


func _on_building_destroyed(_building: Building) -> void:
	_disconnect_building()
	queue_redraw()


func _disconnect_building() -> void:
	if _inspected_building != null and is_instance_valid(_inspected_building):
		if _inspected_building.rally_changed.is_connected(_on_building_changed):
			_inspected_building.rally_changed.disconnect(_on_building_changed)
		if _inspected_building.destroyed.is_connected(_on_building_destroyed):
			_inspected_building.destroyed.disconnect(_on_building_destroyed)
	_inspected_building = null


func _process(delta: float) -> void:
	if _inspected_building == null:
		return
	if not is_instance_valid(_inspected_building) or _inspected_building.is_destroyed:
		_disconnect_building()
		queue_redraw()
		return
	if _inspected_building.has_rally():
		_pulse_time += delta
		queue_redraw()


func _draw() -> void:
	if _inspected_building == null or not is_instance_valid(_inspected_building):
		return
	if _inspected_building.is_destroyed or not _inspected_building.is_constructed or not _inspected_building.has_rally():
		return

	var start_world: Vector2 = _inspected_building.global_position
	var end_world: Vector2 = _inspected_building.get_rally_world_position()
	var p0: Vector2 = to_local(start_world)
	var p1: Vector2 = to_local(end_world)
	var rally_target: Node2D = _inspected_building.get_rally_target()

	var rally_col: Color = Color(0.24, 0.94, 1.0, 0.92)
	var tag_text: String = "RALLY"
	var is_resource_rally: bool = false
	var is_building_rally: bool = false

	if rally_target != null and is_instance_valid(rally_target):
		if rally_target is ResourceNode:
			var rn: ResourceNode = rally_target
			is_resource_rally = true
			if rn.resource_type == &"silica":
				rally_col = Color(1.0, 0.80, 0.28, 0.94)
				tag_text = "GATHER SILICA"
			else:
				rally_col = Color(0.26, 1.0, 0.58, 0.94)
				tag_text = "GATHER BIOMASS"
		elif rally_target is Building:
			is_building_rally = true
			rally_col = Color(0.32, 0.90, 1.0, 0.94)
			tag_text = "AUTO-STAFF"

	# Draw soft glow underlay + animated Technozen dashed line
	var diff: Vector2 = p1 - p0
	var total_len: float = diff.length()
	if total_len > 6.0:
		var dir: Vector2 = diff / total_len
		var start_offset: float = minf(_inspected_building.footprint_radius * 0.7, total_len * 0.4)
		var seg_origin: Vector2 = p0 + dir * start_offset
		var draw_len: float = maxf(0.0, total_len - start_offset)

		draw_line(seg_origin, p1, Color(rally_col.r, rally_col.g, rally_col.b, 0.22), 5.0, true)

		var step: float = DASH_LENGTH + GAP_LENGTH
		var scroll: float = fmod(_pulse_time * 32.0, step)
		var dist: float = -step + scroll
		while dist < draw_len:
			var a: float = maxf(0.0, dist)
			var b: float = minf(draw_len, dist + DASH_LENGTH)
			if b > a + 0.5:
				draw_line(seg_origin + dir * a, seg_origin + dir * b, rally_col, 2.2, true)
			dist += step

	# Pulsing endpoint reticle
	var pulse_r: float = 11.0 + 2.5 * sin(_pulse_time * 4.5)
	draw_circle(p1, pulse_r * 0.75, Color(rally_col.r, rally_col.g, rally_col.b, 0.16))
	draw_arc(p1, pulse_r, 0.0, TAU, 24, rally_col, 2.0, true)

	if is_resource_rally:
		var d: float = 8.0
		var diamond: PackedVector2Array = PackedVector2Array([
			p1 + Vector2(0.0, -d),
			p1 + Vector2(d, 0.0),
			p1 + Vector2(0.0, d),
			p1 + Vector2(-d, 0.0),
			p1 + Vector2(0.0, -d),
		])
		draw_polyline(diamond, rally_col, 2.0, true)
	elif is_building_rally:
		draw_arc(p1, 5.5, 0.0, TAU, 16, Color(0.92, 0.98, 1.0, 0.95), 2.0, true)
	else:
		# Crisp rally flag pennant
		var flag_pts: PackedVector2Array = PackedVector2Array([
			p1 + Vector2(0.0, -2.0),
			p1 + Vector2(0.0, -24.0),
			p1 + Vector2(15.0, -17.0),
			p1 + Vector2(0.0, -10.0),
		])
		draw_colored_polygon(flag_pts, rally_col)
		draw_line(p1, p1 + Vector2(0.0, -24.0), Color(0.95, 1.0, 1.0, 0.95), 2.0, true)

	# Compact endpoint pill label
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 10
	var text_sz: Vector2 = font.get_string_size(tag_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pill_w: float = text_sz.x + 10.0
	var pill_h: float = text_sz.y + 4.0
	var pill_pos: Vector2 = p1 + Vector2(-pill_w * 0.5, 16.0)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.04, 0.08, 0.12, 0.86), true)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(rally_col.r, rally_col.g, rally_col.b, 0.72), false, 1.0)
	draw_string(font, pill_pos + Vector2(5.0, pill_h - 4.0), tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, rally_col)
