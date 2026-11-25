class_name BuildGhostPreview
extends Node2D

## Smart translucent building placement preview ghost.
## Renders turret range rings, drop-off resource tethers, alignment ticks near
## friendly structures, vent snap brackets, and optional 32px grid-snap reticle.

const DROPOFF_TETHER_RADIUS: float = 480.0
const ALIGNMENT_NEIGHBOR_RADIUS: float = 240.0
const ALIGNMENT_AXIS_TOLERANCE: float = 14.0
const GRID_CELL_SIZE: float = 32.0

var is_active: bool = false
var building_data: BuildingData = null
var preview_pos: Vector2 = Vector2.ZERO
var is_valid: bool = false
var status_text: String = ""
var snapped_vent: ResourceNode = null
var is_grid_snapped: bool = false


func set_preview(
	data: BuildingData,
	world_pos: Vector2,
	valid: bool,
	reason: String,
	vent: ResourceNode = null,
	grid_snapped: bool = false
) -> void:
	is_active = data != null
	building_data = data
	preview_pos = world_pos
	is_valid = valid
	status_text = reason
	snapped_vent = vent
	is_grid_snapped = grid_snapped
	visible = is_active
	queue_redraw()


func clear_preview() -> void:
	is_active = false
	building_data = null
	snapped_vent = null
	is_grid_snapped = false
	visible = false
	queue_redraw()


func _draw() -> void:
	if not is_active or building_data == null:
		return

	var half: Vector2 = building_data.footprint_size * 0.5
	var rect: Rect2 = Rect2(preview_pos - half, building_data.footprint_size)
	var fill_col: Color = Color(0.20, 0.96, 0.78, 0.22) if is_valid else Color(1.0, 0.28, 0.28, 0.24)
	var border_col: Color = Color(0.28, 1.0, 0.88, 0.95) if is_valid else Color(1.0, 0.36, 0.32, 0.95)

	# 1. Faint local 32px snap grid reticle when grid-snap is active
	if is_grid_snapped and not building_data.requires_vent:
		_draw_local_snap_grid(preview_pos)

	# 2. Defensive turret coverage rings (attack range & min range)
	if building_data.has_turret and building_data.turret_attack_range > 0.0:
		var range_r: float = building_data.turret_attack_range + building_data.get_footprint_radius()
		var range_col: Color = Color(1.0, 0.76, 0.26, 0.48) if is_valid else Color(1.0, 0.36, 0.32, 0.32)
		draw_circle(preview_pos, range_r, Color(range_col.r, range_col.g, range_col.b, 0.045))
		_draw_dashed_ring(preview_pos, range_r, range_col, 1.7, 44)
		if building_data.turret_min_range > 0.0:
			var min_r: float = building_data.turret_min_range + building_data.get_footprint_radius()
			draw_circle(preview_pos, min_r, Color(1.0, 0.30, 0.26, 0.06))
			_draw_dashed_ring(preview_pos, min_r, Color(1.0, 0.38, 0.30, 0.52), 1.4, 22)

	# 3. Drop-off tether lines & node rings for economy hubs (Nexus Vat / Biomass Silo / Silica Condenser)
	if building_data.is_dropoff:
		_draw_dropoff_tethers(preview_pos, building_data.accepted_resources)

	# 4. Subtle spacing & axis-alignment ticks near friendly structures
	_draw_friendly_alignment_guides(preview_pos, half)

	# 5. Main footprint body + Technozen corner brackets
	draw_rect(rect, fill_col, true)
	draw_rect(rect, border_col, false, 2.2)

	var corner: float = minf(12.0, minf(half.x, half.y) * 0.5)
	var tl: Vector2 = rect.position
	var tr: Vector2 = Vector2(rect.end.x, rect.position.y)
	var br: Vector2 = rect.end
	var bl: Vector2 = Vector2(rect.position.x, rect.end.y)
	var tick_col: Color = border_col.lightened(0.2)
	draw_line(tl, tl + Vector2(corner, 0.0), tick_col, 2.5)
	draw_line(tl, tl + Vector2(0.0, corner), tick_col, 2.5)
	draw_line(tr, tr + Vector2(-corner, 0.0), tick_col, 2.5)
	draw_line(tr, tr + Vector2(0.0, corner), tick_col, 2.5)
	draw_line(br, br + Vector2(-corner, 0.0), tick_col, 2.5)
	draw_line(br, br + Vector2(0.0, -corner), tick_col, 2.5)
	draw_line(bl, bl + Vector2(corner, 0.0), tick_col, 2.5)
	draw_line(bl, bl + Vector2(0.0, -corner), tick_col, 2.5)

	if snapped_vent != null and is_instance_valid(snapped_vent):
		draw_arc(snapped_vent.global_position, snapped_vent.collision_radius + 10.0, 0.0, TAU, 36, Color(0.56, 0.96, 1.0, 0.9), 2.0, true)

	var font: Font = ThemeDB.fallback_font
	if font != null and not status_text.is_empty():
		var display_label: String = status_text
		if not building_data.requires_vent:
			if is_grid_snapped:
				display_label += "  [GRID 32px]"
		var font_size: int = 12
		var size: Vector2 = font.get_string_size(display_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var label_pos: Vector2 = Vector2(preview_pos.x - size.x * 0.5, rect.position.y - 10.0)
		var bg_rect: Rect2 = Rect2(label_pos + Vector2(-6.0, -size.y), size + Vector2(12.0, 6.0))
		draw_rect(bg_rect, Color(0.04, 0.07, 0.11, 0.86), true)
		draw_rect(bg_rect, border_col, false, 1.0)
		draw_string(font, label_pos, display_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, border_col)


func _draw_local_snap_grid(center: Vector2) -> void:
	var grid_radius: float = 144.0
	var gx0: float = floor((center.x - grid_radius) / GRID_CELL_SIZE) * GRID_CELL_SIZE
	var gy0: float = floor((center.y - grid_radius) / GRID_CELL_SIZE) * GRID_CELL_SIZE
	var steps: int = int(ceil((grid_radius * 2.0) / GRID_CELL_SIZE))
	for i: int in range(steps + 1):
		var x: float = gx0 + float(i) * GRID_CELL_SIZE
		var dist_x: float = absf(x - center.x)
		if dist_x <= grid_radius:
			var a_x: float = clampf(1.0 - dist_x / grid_radius, 0.0, 1.0) * 0.22
			var span_y: float = sqrt(maxf(0.0, grid_radius * grid_radius - dist_x * dist_x))
			draw_line(Vector2(x, center.y - span_y), Vector2(x, center.y + span_y), Color(0.32, 0.92, 0.98, a_x), 1.0)
		var y: float = gy0 + float(i) * GRID_CELL_SIZE
		var dist_y: float = absf(y - center.y)
		if dist_y <= grid_radius:
			var a_y: float = clampf(1.0 - dist_y / grid_radius, 0.0, 1.0) * 0.22
			var span_x: float = sqrt(maxf(0.0, grid_radius * grid_radius - dist_y * dist_y))
			draw_line(Vector2(center.x - span_x, y), Vector2(center.x + span_x, y), Color(0.32, 0.92, 0.98, a_y), 1.0)


func _draw_dropoff_tethers(origin: Vector2, accepted_resources: Array[StringName]) -> void:
	if not is_inside_tree():
		return
	var r_sq: float = DROPOFF_TETHER_RADIUS * DROPOFF_TETHER_RADIUS
	var linked_count: int = 0
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node) or not (node is ResourceNode):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.is_depleted() or rn.is_vent:
			continue
		if not accepted_resources.is_empty() and not accepted_resources.has(rn.resource_type):
			continue
		var d_sq: float = origin.distance_squared_to(rn.global_position)
		if d_sq > r_sq:
			continue
		linked_count += 1
		var is_silica: bool = (rn.resource_type == &"silica")
		var tether_col: Color = Color(0.98, 0.78, 0.28, 0.72) if is_silica else Color(0.20, 0.94, 0.64, 0.72)
		var ring_col: Color = Color(1.0, 0.84, 0.36, 0.90) if is_silica else Color(0.28, 1.0, 0.74, 0.90)
		_draw_dashed_line(origin, rn.global_position, tether_col, 1.6, 10.0, 7.0)
		draw_arc(rn.global_position, rn.collision_radius + 7.0, 0.0, TAU, 24, ring_col, 1.8, true)
		draw_circle(rn.global_position, rn.collision_radius + 7.0, Color(ring_col.r, ring_col.g, ring_col.b, 0.10))

	if linked_count > 0:
		var silica_only: bool = accepted_resources.size() == 1 and accepted_resources[0] == &"silica"
		var halo_col: Color = Color(0.98, 0.78, 0.28, 0.16) if silica_only else Color(0.20, 0.94, 0.64, 0.16)
		_draw_dashed_ring(origin, DROPOFF_TETHER_RADIUS, halo_col, 1.0, 48)


func _draw_friendly_alignment_guides(origin: Vector2, half: Vector2) -> void:
	if not is_inside_tree():
		return
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var max_sq: float = ALIGNMENT_NEIGHBOR_RADIUS * ALIGNMENT_NEIGHBOR_RADIUS
	var guide_col: Color = Color(0.46, 0.96, 1.0, 0.42)
	var tick_col: Color = Color(0.64, 0.98, 1.0, 0.72)

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if b.is_destroyed or b.is_queued_for_deletion():
			continue
		var is_friendly: bool = (local_team < 0) or (TeamManager.are_allies(local_team, int(b.team)) if TeamManager != null else (int(b.team) == int(Unit.Team.PLAYER)))
		if not is_friendly:
			continue
		var d_sq: float = origin.distance_squared_to(b.global_position)
		if d_sq > max_sq or d_sq < 1.0:
			continue

		# Axis-aligned snap ticks (horizontal or vertical center alignment)
		if absf(origin.x - b.global_position.x) <= ALIGNMENT_AXIS_TOLERANCE:
			_draw_dashed_line(Vector2(b.global_position.x, b.global_position.y), Vector2(b.global_position.x, origin.y), guide_col, 1.2, 6.0, 5.0)
			draw_line(Vector2(b.global_position.x - 5.0, origin.y), Vector2(b.global_position.x + 5.0, origin.y), tick_col, 1.5)
		if absf(origin.y - b.global_position.y) <= ALIGNMENT_AXIS_TOLERANCE:
			_draw_dashed_line(Vector2(b.global_position.x, b.global_position.y), Vector2(origin.x, b.global_position.y), guide_col, 1.2, 6.0, 5.0)
			draw_line(Vector2(origin.x, b.global_position.y - 5.0), Vector2(origin.x, b.global_position.y + 5.0), tick_col, 1.5)

		# Subtle clearance tick along the connecting edge
		var dir: Vector2 = (b.global_position - origin).normalized()
		var p_from: Vector2 = origin + dir * (maxf(half.x, half.y) + 4.0)
		var p_to: Vector2 = b.global_position - dir * (b.footprint_radius + 4.0)
		if (p_to - p_from).dot(dir) > 6.0:
			var perp: Vector2 = dir.orthogonal() * 4.5
			draw_line(p_from - perp, p_from + perp, Color(0.46, 0.96, 1.0, 0.36), 1.2)
			draw_line(p_to - perp, p_to + perp, Color(0.46, 0.96, 1.0, 0.36), 1.2)


func _draw_dashed_ring(center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(8, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.54
		draw_arc(center, radius, a0, a1, 4, col, width, true)


func _draw_dashed_line(a: Vector2, b: Vector2, col: Color, width: float, dash_len: float, gap_len: float) -> void:
	var diff: Vector2 = b - a
	var total: float = diff.length()
	if total <= 1.0:
		return
	var dir: Vector2 = diff / total
	var stride: float = maxf(2.0, dash_len + gap_len)
	var dist: float = 0.0
	while dist < total:
		var seg_end: float = minf(total, dist + dash_len)
		draw_line(a + dir * dist, a + dir * seg_end, col, width, true)
		dist += stride
