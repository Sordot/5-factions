class_name MapBiomeBackdrop
extends Node2D

## Procedural zero-per-frame-cost map biome floor renderer (Milestone 3.2).
## Renders distinct, dark, low-contrast tactical floor treatments strictly below
## BattleScarsOverlay, landmarks, terrain obstacles, units, and Fog of War.

@export var biome_id: StringName = &"vat_basin"
@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)

var _spawn_pts: Array[Vector2] = []
var _uplink_pt: Vector2 = Vector2.ZERO
var _barricade_pts: Array[Dictionary] = [] # {"pos": Vector2, "rot": float}
var _anchors_collected: bool = false


func _ready() -> void:
	z_index = -100
	set_process(false)
	set_physics_process(false)
	_sync_bounds_from_nav_region()
	_collect_dynamic_anchors()
	queue_redraw()


func refresh_anchors() -> void:
	_sync_bounds_from_nav_region()
	_collect_dynamic_anchors()
	queue_redraw()


func _collect_dynamic_anchors() -> void:
	_spawn_pts.clear()
	_uplink_pt = Vector2.ZERO
	_barricade_pts.clear()
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	for node: Node in tree.get_nodes_in_group("spawn_anchors"):
		if is_instance_valid(node) and node is Node2D:
			_spawn_pts.append(to_local((node as Node2D).global_position))
	var uplink: Node = tree.get_first_node_in_group("hyper_uplinks")
	if is_instance_valid(uplink) and uplink is Node2D:
		_uplink_pt = to_local((uplink as Node2D).global_position)
	for b_node: Node in tree.get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(b_node) and b_node is Node2D:
			var bn: Node2D = b_node as Node2D
			_barricade_pts.append({"pos": to_local(bn.global_position), "rot": bn.rotation})
	_anchors_collected = true


func _get_spawn_points_or_fallback(fallback: Array) -> Array[Vector2]:
	if not _spawn_pts.is_empty():
		return _spawn_pts
	var out: Array[Vector2] = []
	for pt: Variant in fallback:
		if pt is Vector2:
			out.append(pt as Vector2)
	return out


func _sync_bounds_from_nav_region() -> void:
	var nav: Node = get_tree().get_first_node_in_group("arena_nav_region")
	if nav == null and get_parent() != null:
		nav = get_parent().get_node_or_null("NavigationRegion2D")
	if nav != null and nav is ArenaNavRegion:
		var arena_nav: ArenaNavRegion = nav as ArenaNavRegion
		if arena_nav.arena_bounds.size.x > 0.0 and arena_nav.arena_bounds.size.y > 0.0:
			arena_bounds = arena_nav.arena_bounds


func _draw() -> void:
	if not _anchors_collected and is_inside_tree():
		_collect_dynamic_anchors()
	match biome_id:
		&"twin_causeway":
			_draw_twin_causeway()
		&"quad_nexus":
			_draw_quad_nexus()
		&"triad_sanctum":
			_draw_triad_sanctum()
		_:
			_draw_vat_basin()
	_draw_arena_perimeter_frame()


# =============================================================================
# BIOME 1 — VAT BASIN (skirmish_arena_01.tscn)
# Deep cool slate-teal bio-research basin (#081018), orthogonal lab grid,
# concentric basin contour rings, and faint cyan-emerald bio-conduit channels.
# =============================================================================

func _draw_vat_basin() -> void:
	var b: Rect2 = arena_bounds
	var min_x: float = b.position.x
	var max_x: float = b.end.x
	var min_y: float = b.position.y
	var max_y: float = b.end.y

	# 1. Base bio-basin deck fill
	draw_rect(b, Color.html("#081018"), true)

	var bases: Array[Vector2] = _get_spawn_points_or_fallback([Vector2(-900.0, 560.0), Vector2(900.0, -560.0)])
	var center_pt: Vector2 = _uplink_pt

	# 2. Soft recessed basin gradient rings (very low alpha so units pop)
	draw_circle(center_pt, 620.0, Color(0.06, 0.17, 0.22, 0.14))
	draw_circle(center_pt, 390.0, Color(0.08, 0.24, 0.28, 0.11))
	for base_pt: Vector2 in bases:
		draw_circle(base_pt, 340.0, Color(0.06, 0.20, 0.24, 0.12))

	# 3. Orthogonal laboratory grid: 64px faint minor / 128px subtle major
	var minor_col: Color = Color(0.20, 0.56, 0.62, 0.055)
	var major_col: Color = Color(0.24, 0.68, 0.72, 0.095)
	var x: float = ceilf(min_x / 64.0) * 64.0
	while x <= max_x:
		var is_major: bool = is_zero_approx(fmod(absf(x), 128.0))
		draw_line(Vector2(x, min_y), Vector2(x, max_y), major_col if is_major else minor_col, 1.0)
		x += 64.0
	var y: float = ceilf(min_y / 64.0) * 64.0
	while y <= max_y:
		var is_major_y: bool = is_zero_approx(fmod(absf(y), 128.0))
		draw_line(Vector2(min_x, y), Vector2(max_x, y), major_col if is_major_y else minor_col, 1.0)
		y += 64.0

	# 4. Faint diagonal bio-conduit channels connecting each real spawn base -> plaza
	var conduit_outer: Color = Color(0.14, 0.64, 0.60, 0.085)
	var conduit_core: Color = Color(0.28, 0.88, 0.76, 0.095)
	for base_pt: Vector2 in bases:
		var mid_pt: Vector2 = base_pt.lerp(center_pt, 0.56)
		var packed: PackedVector2Array = PackedVector2Array([base_pt, mid_pt, center_pt])
		draw_polyline(packed, conduit_outer, 14.0, true)
		draw_polyline(packed, conduit_core, 2.0, true)
	if _spawn_pts.is_empty():
		var static_flanks: Array[Array] = [
			[Vector2(-900.0, 560.0), Vector2(-820.0, -480.0), Vector2(-260.0, -260.0), center_pt],
			[Vector2(900.0, -560.0), Vector2(820.0, 480.0), Vector2(260.0, 260.0), center_pt],
		]
		for path_pts: Array in static_flanks:
			var packed_f: PackedVector2Array = PackedVector2Array()
			for pt: Vector2 in path_pts:
				packed_f.append(pt)
			draw_polyline(packed_f, conduit_outer, 14.0, true)
			draw_polyline(packed_f, conduit_core, 2.0, true)

	# 5. Concentric topographic basin contour rings around central Hyper-Uplink
	var contour_col: Color = Color(0.26, 0.78, 0.76, 0.11)
	var contour_faint: Color = Color(0.22, 0.68, 0.70, 0.075)
	for rad: float in [150.0, 250.0, 360.0, 490.0, 640.0]:
		var col: Color = contour_col if rad <= 360.0 else contour_faint
		draw_arc(center_pt, rad, 0.0, TAU, 64, col, 1.4, true)
		# Subtle cardinal registration ticks
		for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dir: Vector2 = Vector2.from_angle(ang)
			draw_line(center_pt + dir * (rad - 6.0), center_pt + dir * (rad + 6.0), col, 1.2)

	# 6. Circular pad contours around each actual spawn base (+ classic NW/SE pads on static fallback)
	for base_center: Vector2 in bases:
		draw_arc(base_center, 155.0, 0.0, TAU, 48, contour_col, 1.5, true)
		draw_arc(base_center, 235.0, 0.0, TAU, 56, contour_faint, 1.2, true)
		draw_arc(base_center, 315.0, 0.0, TAU, 64, Color(0.20, 0.62, 0.66, 0.055), 1.0, true)

	if _spawn_pts.is_empty():
		for exp_center: Vector2 in [Vector2(-820.0, -480.0), Vector2(820.0, 480.0)]:
			draw_arc(exp_center, 115.0, 0.0, TAU, 36, contour_faint, 1.2, true)
			draw_arc(exp_center, 185.0, 0.0, TAU, 44, Color(0.20, 0.62, 0.66, 0.055), 1.0, true)


# =============================================================================
# BIOME 2 — TWIN CAUSEWAY (skirmish_arena_02.tscn)
# Matte charcoal-gunmetal industrial deck (#0D1014), 160x120 offset steel deck
# plating with corner rivets, muted amber (#FF9F1C) hazard striping along the
# central choke bridge and flank bypass corridors, and etched lane chevrons.
# =============================================================================

func _draw_twin_causeway() -> void:
	var b: Rect2 = arena_bounds
	var min_x: float = b.position.x
	var max_x: float = b.end.x
	var min_y: float = b.position.y
	var max_y: float = b.end.y

	# 1. Matte gunmetal-charcoal base fill
	draw_rect(b, Color.html("#0D1014"), true)

	# 2. Subtle darkened industrial roadbed strips for the central bridge & flank bypasses
	draw_rect(Rect2(-560.0, -290.0, 1120.0, 580.0), Color(0.06, 0.075, 0.095, 0.45), true)
	draw_rect(Rect2(-760.0, -860.0, 1520.0, 200.0), Color(0.06, 0.07, 0.09, 0.35), true)
	draw_rect(Rect2(-760.0, 660.0, 1520.0, 200.0), Color(0.06, 0.07, 0.09, 0.35), true)

	# 3. Large rectangular 160x120 offset armored steel deck plating + corner rivets
	var seam_col: Color = Color(0.56, 0.62, 0.68, 0.088)
	var highlight_col: Color = Color(0.75, 0.80, 0.86, 0.035)
	var rivet_col: Color = Color(0.65, 0.70, 0.76, 0.11)
	var plate_w: float = 160.0
	var plate_h: float = 120.0
	var row_idx: int = 0
	var py: float = floorf(min_y / plate_h) * plate_h
	while py < max_y:
		var y0: float = maxf(py, min_y)
		var y1: float = minf(py + plate_h, max_y)
		draw_line(Vector2(min_x, y0), Vector2(max_x, y0), seam_col, 1.2)
		if y0 + 2.0 < max_y:
			draw_line(Vector2(min_x, y0 + 2.0), Vector2(max_x, y0 + 2.0), highlight_col, 1.0)
		var x_off: float = (plate_w * 0.5) if (row_idx % 2 != 0) else 0.0
		var px: float = floorf((min_x - x_off) / plate_w) * plate_w + x_off
		while px <= max_x:
			if px >= min_x and px <= max_x:
				draw_line(Vector2(px, y0), Vector2(px, y1), seam_col, 1.2)
				# Tiny corner rivet dots near major plate intersections
				if px + 7.0 < max_x and y0 + 7.0 < max_y:
					draw_circle(Vector2(px + 7.0, y0 + 7.0), 1.4, rivet_col)
				if px - 7.0 > min_x and y0 + 7.0 < max_y:
					draw_circle(Vector2(px - 7.0, y0 + 7.0), 1.4, rivet_col)
			px += plate_w
		py += plate_h
		row_idx += 1

	# 4. Industrial hazard striping (#FF9F1C at ~0.11 alpha) framing key tactical lanes & barricades
	var amber_hazard: Color = Color(1.0, 0.624, 0.11, 0.115)
	var amber_border: Color = Color(1.0, 0.624, 0.11, 0.16)
	var center_pt: Vector2 = _uplink_pt
	# Central Causeway Bridge north & south apron stripes
	_draw_hazard_strip(Rect2(center_pt + Vector2(-460.0, -296.0), Vector2(920.0, 22.0)), amber_hazard, amber_border, 22.0)
	_draw_hazard_strip(Rect2(center_pt + Vector2(-460.0, 274.0), Vector2(920.0, 22.0)), amber_hazard, amber_border, 22.0)

	if not _barricade_pts.is_empty():
		for b_entry: Dictionary in _barricade_pts:
			var bp: Vector2 = b_entry["pos"] as Vector2
			var br: float = float(b_entry["rot"])
			_draw_rotated_hazard_strip(bp, br, 176.0, 22.0, amber_hazard, amber_border, 18.0)
	else:
		# Classic skirmish_arena_02.tscn fallback hazard markers
		_draw_hazard_strip(Rect2(-340.0, -854.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
		_draw_hazard_strip(Rect2(-340.0, -682.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
		_draw_hazard_strip(Rect2(-20.0, 666.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
		_draw_hazard_strip(Rect2(-20.0, 838.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
		_draw_hazard_strip(Rect2(-804.0, -252.0, 168.0, 14.0), amber_hazard, amber_border, 16.0)
		_draw_hazard_strip(Rect2(636.0, 238.0, 168.0, 14.0), amber_hazard, amber_border, 16.0)

	# 5. Subtle central loading-bay frame around the Bridge Plaza
	draw_rect(Rect2(center_pt + Vector2(-240.0, -180.0), Vector2(480.0, 360.0)), Color(0.75, 0.80, 0.86, 0.08), false, 1.8)
	draw_line(center_pt + Vector2(-460.0, 0.0), center_pt + Vector2(-140.0, 0.0), Color(1.0, 0.624, 0.11, 0.085), 2.0)
	draw_line(center_pt + Vector2(140.0, 0.0), center_pt + Vector2(460.0, 0.0), Color(1.0, 0.624, 0.11, 0.085), 2.0)

	# 6. Etched directional lane chevrons pointing toward the center objective
	var chev_col: Color = Color(0.84, 0.86, 0.88, 0.095)
	for cx: float in [-420.0, -340.0, -260.0]:
		_draw_chevron(center_pt + Vector2(cx, 0.0), Vector2.RIGHT, 24.0, 38.0, chev_col)
	for cx_e: float in [420.0, 340.0, 260.0]:
		_draw_chevron(center_pt + Vector2(cx_e, 0.0), Vector2.LEFT, 24.0, 38.0, chev_col)

	var bases: Array[Vector2] = _get_spawn_points_or_fallback([Vector2(-900.0, 420.0), Vector2(900.0, -420.0)])
	for base_pos: Vector2 in bases:
		var approach_dir: Vector2 = (center_pt - base_pos).normalized()
		if approach_dir.length_squared() > 0.01:
			for t: float in [0.28, 0.44]:
				var pt_c: Vector2 = base_pos.lerp(center_pt, t)
				_draw_chevron(pt_c, approach_dir, 18.0, 28.0, Color(0.76, 0.80, 0.84, 0.075))
		# 7. Industrial base pad frames around each spawn anchor
		var pad_r: Rect2 = Rect2(base_pos - Vector2(180.0, 160.0), Vector2(360.0, 320.0))
		draw_rect(pad_r, Color(0.62, 0.68, 0.74, 0.085), false, 1.5)
		_draw_corner_brackets(pad_r, 24.0, Color(1.0, 0.624, 0.11, 0.15), 2.2)


# =============================================================================
# BIOME 3 — QUAD NEXUS (skirmish_arena_03.tscn)
# Deep obsidian-indigo mainframe arena (#090C14), symmetrical 4-quadrant
# circuit-nexus grid, 45° diagonal bus traces linking all 4 spawn corners to
# (0,0), octagonal telemetry rings (180/320/520 px), perimeter corridor markers,
# and neutral quadrant spawn brackets.
# =============================================================================

func _draw_quad_nexus() -> void:
	var b: Rect2 = arena_bounds
	var min_x: float = b.position.x
	var max_x: float = b.end.x
	var min_y: float = b.position.y
	var max_y: float = b.end.y

	# 1. Deep obsidian-indigo base fill
	draw_rect(b, Color.html("#090C14"), true)

	# 2. Symmetrical 4-quadrant geometric circuit-nexus grid (160px major / 80px faint minor)
	var grid_minor: Color = Color(0.28, 0.44, 0.72, 0.048)
	var grid_major: Color = Color(0.36, 0.56, 0.88, 0.088)
	var gx: float = ceilf(min_x / 80.0) * 80.0
	while gx <= max_x:
		var is_major_x: bool = is_zero_approx(fmod(absf(gx), 160.0))
		draw_line(Vector2(gx, min_y), Vector2(gx, max_y), grid_major if is_major_x else grid_minor, 1.0)
		gx += 80.0
	var gy: float = ceilf(min_y / 80.0) * 80.0
	while gy <= max_y:
		var is_major_y: bool = is_zero_approx(fmod(absf(gy), 160.0))
		draw_line(Vector2(min_x, gy), Vector2(max_x, gy), grid_major if is_major_y else grid_minor, 1.0)
		gy += 80.0

	# Cardinal meridian divider axes radiating cleanly from Hyper-Uplink
	var center_pt: Vector2 = _uplink_pt
	var axis_col: Color = Color(0.42, 0.66, 0.96, 0.115)
	draw_line(Vector2(min_x, center_pt.y), Vector2(max_x, center_pt.y), axis_col, 1.6)
	draw_line(Vector2(center_pt.x, min_y), Vector2(center_pt.x, max_y), axis_col, 1.6)

	# 3. Diagonal circuit bus traces linking each actual spawn anchor toward the central Hyper-Uplink ring
	var bus_outer: Color = Color(0.32, 0.56, 0.94, 0.085)
	var bus_inner: Color = Color(0.52, 0.78, 1.0, 0.125)
	var bases: Array[Vector2] = _get_spawn_points_or_fallback([
		Vector2(-1180.0, -1120.0),
		Vector2(1180.0, -1120.0),
		Vector2(-1180.0, 1120.0),
		Vector2(1180.0, 1120.0),
	])
	for corner_pt: Vector2 in bases:
		var delta_v: Vector2 = corner_pt - center_pt
		var total_d: float = delta_v.length()
		if total_d > 220.0:
			var dir_c: Vector2 = delta_v / total_d
			var perp: Vector2 = Vector2(-dir_c.y, dir_c.x)
			var bus_start: Vector2 = corner_pt - dir_c * 84.0
			var bus_end: Vector2 = center_pt + dir_c * 175.0
			# Triple parallel circuit bus trace along spawn -> uplink axis
			draw_line(bus_start, bus_end, bus_outer, 14.0, true)
			draw_line(bus_start, bus_end, bus_inner, 1.8, true)
			draw_line(bus_start + perp * 16.0, bus_end + perp * 16.0, bus_outer, 1.4, true)
			draw_line(bus_start - perp * 16.0, bus_end - perp * 16.0, bus_outer, 1.4, true)
			# Circuit node pads spaced cleanly along each trace
			for frac: float in [0.26, 0.54, 0.80]:
				var node_pt: Vector2 = bus_end.lerp(bus_start, frac)
				draw_circle(node_pt, 5.0, bus_inner)
				draw_arc(node_pt, 10.0, 0.0, TAU, 16, bus_outer, 1.2, true)
			draw_line(corner_pt, bus_start, bus_inner, 1.8, true)

	# 4. Concentric octagonal telemetry rings around central plaza (180 px, 320 px, 520 px)
	var oct_cols: Array[Color] = [
		Color(0.44, 0.74, 1.0, 0.14),
		Color(0.38, 0.64, 0.96, 0.11),
		Color(0.32, 0.54, 0.88, 0.085),
	]
	var oct_rads: Array[float] = [180.0, 320.0, 520.0]
	for idx: int in range(oct_rads.size()):
		_draw_octagon(center_pt, oct_rads[idx], oct_cols[idx], 1.6 if idx == 0 else 1.3)

	# 5. Perimeter outer-corridor lane markers & barricade gate alignment ticks
	var corr_col: Color = Color(0.40, 0.66, 0.96, 0.095)
	var corr_dash: Color = Color(0.52, 0.78, 1.0, 0.12)
	var corr_outer: Rect2 = b.grow(-185.0)
	var corr_inner: Rect2 = b.grow(-315.0)
	if corr_outer.has_area():
		draw_rect(corr_outer, corr_col, false, 1.4)
	if corr_inner.has_area():
		draw_rect(corr_inner, corr_col, false, 1.4)
	if not _barricade_pts.is_empty():
		for b_entry: Dictionary in _barricade_pts:
			_draw_rotated_box_outline(b_entry["pos"] as Vector2, float(b_entry["rot"]), Vector2(96.0, 44.0), corr_dash, 1.4)
	else:
		for gate_pos: Vector2 in [Vector2(0.0, -1060.0), Vector2(0.0, 1060.0), Vector2(-1060.0, 0.0), Vector2(1060.0, 0.0)]:
			draw_rect(Rect2(gate_pos - Vector2(96.0, 44.0), Vector2(192.0, 88.0)), corr_dash, false, 1.4)

	# 6. Neutral spawn sector brackets aligned 1:1 with each actual spawn anchor
	var neutral_bracket: Color = Color(0.68, 0.76, 0.90, 0.16)
	var neutral_frame: Color = Color(0.46, 0.58, 0.78, 0.075)
	for sector_center: Vector2 in bases:
		var sector_rect: Rect2 = Rect2(sector_center - Vector2(210.0, 190.0), Vector2(420.0, 380.0))
		draw_rect(sector_rect, neutral_frame, false, 1.2)
		_draw_corner_brackets(sector_rect, 32.0, neutral_bracket, 2.4)


# =============================================================================
# BIOME 4 — TRIAD SANCTUM (skirmish_arena_04.tscn & 3P Procedural)
# Deep obsidian-slate solar observatory floor (#101118), 60°/120° isometric-
# triangular alabaster lattice hairlines, concentric liturgical-gold & slate
# astrolabe rings around (0,0), and three crisp 120° radial meridian lines.
# =============================================================================

func _draw_triad_sanctum() -> void:
	var b: Rect2 = arena_bounds
	var min_x: float = b.position.x
	var max_x: float = b.end.x
	var min_y: float = b.position.y
	var max_y: float = b.end.y

	# 1. Deep obsidian-slate floor
	draw_rect(b, Color(0.065, 0.068, 0.095, 1.0), true)

	# 2. Subtle obsidian-violet radial floor wash centered on Hyper-Uplink
	var center_pt: Vector2 = _uplink_pt
	draw_circle(center_pt, 680.0, Color(0.11, 0.10, 0.16, 0.22))
	draw_circle(center_pt, 360.0, Color(0.14, 0.12, 0.20, 0.16))

	# 3. 60° / 120° isometric-triangular alabaster lattice hairlines (low alpha 0.06-0.085)
	var tri_minor: Color = Color(0.92, 0.90, 0.86, 0.062)
	var tri_major: Color = Color(0.96, 0.94, 0.90, 0.085)
	var row_step: float = 120.0
	var ty: float = ceilf(min_y / row_step) * row_step
	while ty <= max_y:
		var is_maj: bool = is_zero_approx(fmod(absf(ty), row_step * 2.0))
		draw_line(Vector2(min_x, ty), Vector2(max_x, ty), tri_major if is_maj else tri_minor, 1.0)
		ty += row_step

	var diag_step: float = 138.564 # 120 / sin(60°)
	var span: float = maxf(b.size.x, b.size.y) * 1.65
	var dir_60: Vector2 = Vector2.from_angle(deg_to_rad(60.0))
	var dir_120: Vector2 = Vector2.from_angle(deg_to_rad(120.0))
	var k_max: int = int(ceilf((b.size.x + b.size.y) / diag_step)) + 2
	for k: int in range(-k_max, k_max + 1):
		var col_d: Color = tri_major if (k % 2 == 0) else tri_minor
		var ox: float = float(k) * diag_step
		var a1: Vector2 = Vector2(ox, 0.0) - dir_60 * span
		var b1: Vector2 = Vector2(ox, 0.0) + dir_60 * span
		_draw_clipped_line(a1, b1, b, col_d, 1.0)
		var a2: Vector2 = Vector2(ox, 0.0) - dir_120 * span
		var b2: Vector2 = Vector2(ox, 0.0) + dir_120 * span
		_draw_clipped_line(a2, b2, b, col_d, 1.0)

	# 4. Concentric liturgical-gold & slate astrolabe rings around Hyper-Uplink
	var gold_ring: Color = Color(0.98, 0.80, 0.082, 0.13)
	var gold_soft: Color = Color(0.98, 0.80, 0.082, 0.075)
	var slate_ring: Color = Color(0.76, 0.78, 0.86, 0.085)
	for rad: float in [165.0, 260.0, 410.0, 620.0, 900.0]:
		var rc: Color = gold_ring if (rad <= 260.0 or is_equal_approx(rad, 900.0)) else slate_ring
		draw_arc(center_pt, rad, 0.0, TAU, 72, rc, 1.6 if rad <= 260.0 else 1.2, true)
	# Subtle inscribed 6-point sacred triangle ring at 260 px
	var tri_a: PackedVector2Array = PackedVector2Array()
	var tri_b: PackedVector2Array = PackedVector2Array()
	for ti: int in range(4):
		var ang_a: float = deg_to_rad(-90.0 + float(ti % 3) * 120.0)
		var ang_b: float = deg_to_rad(90.0 + float(ti % 3) * 120.0)
		tri_a.append(center_pt + Vector2.from_angle(ang_a) * 260.0)
		tri_b.append(center_pt + Vector2.from_angle(ang_b) * 260.0)
	draw_polyline(tri_a, gold_soft, 1.3, true)
	draw_polyline(tri_b, slate_ring, 1.1, true)

	# 5. Radial meridian lines & sanctum pad rings aligned to each actual spawn anchor
	var meridian_outer: Color = Color(0.98, 0.80, 0.082, 0.075)
	var meridian_core: Color = Color(0.98, 0.80, 0.082, 0.15)
	var bases: Array[Vector2] = _get_spawn_points_or_fallback([
		center_pt + Vector2.from_angle(deg_to_rad(150.0)) * 900.0,
		center_pt + Vector2.from_angle(deg_to_rad(30.0)) * 900.0,
		center_pt + Vector2.from_angle(deg_to_rad(-90.0)) * 900.0,
	])
	var half_sector_ang: float = PI / maxf(2.0, float(bases.size()))
	for basin_pt: Vector2 in bases:
		var delta_s: Vector2 = basin_pt - center_pt
		var dist_s: float = delta_s.length()
		if dist_s > 170.0:
			var dir_s: Vector2 = delta_s / dist_s
			draw_line(center_pt + dir_s * 165.0, basin_pt, meridian_outer, 12.0, true)
			draw_line(center_pt + dir_s * 165.0, basin_pt, meridian_core, 1.8, true)
			var mid_dir: Vector2 = Vector2.from_angle(dir_s.angle() + half_sector_ang)
			draw_line(center_pt + mid_dir * 260.0, center_pt + mid_dir * minf(1020.0, dist_s + 80.0), Color(0.85, 0.35, 0.94, 0.075), 1.4, true)
			draw_arc(center_pt + mid_dir * minf(980.0, dist_s + 40.0), 125.0, 0.0, TAU, 36, gold_soft, 1.2, true)
		# Observatory sanctum pad rings around each corner spawn basin (neutral alabaster-gold)
		draw_arc(basin_pt, 145.0, 0.0, TAU, 48, gold_ring, 1.5, true)
		draw_arc(basin_pt, 235.0, 0.0, TAU, 56, slate_ring, 1.2, true)


func _draw_clipped_line(p0: Vector2, p1: Vector2, bounds: Rect2, col: Color, width: float) -> void:
	# Liang-Barsky clip so angled lattice lines never extend outside arena_bounds
	var dx: float = p1.x - p0.x
	var dy: float = p1.y - p0.y
	var t0: float = 0.0
	var t1: float = 1.0
	var checks: Array[Array] = [
		[-dx, p0.x - bounds.position.x],
		[dx, bounds.end.x - p0.x],
		[-dy, p0.y - bounds.position.y],
		[dy, bounds.end.y - p0.y],
	]
	for pair: Array in checks:
		var p_val: float = float(pair[0])
		var q_val: float = float(pair[1])
		if is_zero_approx(p_val):
			if q_val < 0.0:
				return
		else:
			var r_val: float = q_val / p_val
			if p_val < 0.0:
				if r_val > t1:
					return
				t0 = maxf(t0, r_val)
			else:
				if r_val < t0:
					return
				t1 = minf(t1, r_val)
	if t1 > t0:
		draw_line(p0 + Vector2(dx, dy) * t0, p0 + Vector2(dx, dy) * t1, col, width)


# =============================================================================
# SHARED GEOMETRIC PRIMITIVES
# =============================================================================

func _draw_hazard_strip(rect: Rect2, stripe_col: Color, border_col: Color, pitch: float) -> void:
	draw_rect(rect, border_col, false, 1.2)
	var h: float = rect.size.y
	var x0: float = rect.position.x
	var x1: float = rect.end.x
	var y0: float = rect.position.y
	var y1: float = rect.end.y
	var half_p: float = pitch * 0.45
	var sx: float = x0 - h
	while sx < x1:
		var p_top_l: float = clampf(sx + h, x0, x1)
		var p_top_r: float = clampf(sx + h + half_p, x0, x1)
		var p_bot_r: float = clampf(sx + half_p, x0, x1)
		var p_bot_l: float = clampf(sx, x0, x1)
		if p_top_r > p_top_l + 1.0 and p_bot_r > p_bot_l + 1.0:
			var poly: PackedVector2Array = PackedVector2Array([
				Vector2(p_top_l, y0),
				Vector2(p_top_r, y0),
				Vector2(p_bot_r, y1),
				Vector2(p_bot_l, y1),
			])
			draw_colored_polygon(poly, stripe_col)
		sx += pitch


func _draw_chevron(center: Vector2, dir: Vector2, length: float, half_width: float, col: Color) -> void:
	var f: Vector2 = dir.normalized()
	var perp: Vector2 = Vector2(-f.y, f.x)
	var tip: Vector2 = center + f * (length * 0.5)
	var tail_a: Vector2 = center - f * (length * 0.5) + perp * half_width
	var tail_b: Vector2 = center - f * (length * 0.5) - perp * half_width
	draw_polyline(PackedVector2Array([tail_a, tip, tail_b]), col, 2.6, true)


func _draw_octagon(center: Vector2, radius: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(9):
		var ang: float = (float(i % 8) + 0.5) * (TAU / 8.0)
		pts.append(center + Vector2.from_angle(ang) * radius)
	draw_polyline(pts, col, width, true)


func _draw_corner_brackets(rect: Rect2, arm: float, col: Color, width: float) -> void:
	var l: float = rect.position.x
	var t: float = rect.position.y
	var r: float = rect.end.x
	var b: float = rect.end.y
	draw_line(Vector2(l, t), Vector2(l + arm, t), col, width)
	draw_line(Vector2(l, t), Vector2(l, t + arm), col, width)
	draw_line(Vector2(r, t), Vector2(r - arm, t), col, width)
	draw_line(Vector2(r, t), Vector2(r, t + arm), col, width)
	draw_line(Vector2(l, b), Vector2(l + arm, b), col, width)
	draw_line(Vector2(l, b), Vector2(l, b - arm), col, width)
	draw_line(Vector2(r, b), Vector2(r - arm, b), col, width)
	draw_line(Vector2(r, b), Vector2(r, b - arm), col, width)


func _draw_rotated_hazard_strip(center: Vector2, rot: float, length: float, thickness: float, stripe_col: Color, border_col: Color, pitch: float) -> void:
	var dir_l: Vector2 = Vector2.from_angle(rot)
	var dir_t: Vector2 = Vector2(-dir_l.y, dir_l.x)
	var hl: float = length * 0.5
	var ht: float = thickness * 0.5
	var p0: Vector2 = center - dir_l * hl - dir_t * ht
	var p1: Vector2 = center + dir_l * hl - dir_t * ht
	var p2: Vector2 = center + dir_l * hl + dir_t * ht
	var p3: Vector2 = center - dir_l * hl + dir_t * ht
	draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]), border_col, 1.2, true)

	var half_p: float = pitch * 0.45
	var sx: float = -hl - thickness
	while sx < hl:
		var t_l: float = clampf(sx + thickness, -hl, hl)
		var t_r: float = clampf(sx + thickness + half_p, -hl, hl)
		var b_r: float = clampf(sx + half_p, -hl, hl)
		var b_l: float = clampf(sx, -hl, hl)
		if t_r > t_l + 1.0 and b_r > b_l + 1.0:
			var poly: PackedVector2Array = PackedVector2Array([
				center + dir_l * t_l - dir_t * ht,
				center + dir_l * t_r - dir_t * ht,
				center + dir_l * b_r + dir_t * ht,
				center + dir_l * b_l + dir_t * ht,
			])
			draw_colored_polygon(poly, stripe_col)
		sx += pitch


func _draw_rotated_box_outline(center: Vector2, rot: float, half_ext: Vector2, col: Color, width: float) -> void:
	var dir_x: Vector2 = Vector2.from_angle(rot)
	var dir_y: Vector2 = Vector2(-dir_x.y, dir_x.x)
	var c0: Vector2 = center - dir_x * half_ext.x - dir_y * half_ext.y
	var c1: Vector2 = center + dir_x * half_ext.x - dir_y * half_ext.y
	var c2: Vector2 = center + dir_x * half_ext.x + dir_y * half_ext.y
	var c3: Vector2 = center - dir_x * half_ext.x + dir_y * half_ext.y
	draw_polyline(PackedVector2Array([c0, c1, c2, c3, c0]), col, width, true)


func _draw_arena_perimeter_frame() -> void:
	var b: Rect2 = arena_bounds
	if not b.has_area():
		return
	var min_x: float = b.position.x
	var max_x: float = b.end.x
	var min_y: float = b.position.y
	var max_y: float = b.end.y

	# Subtle recessed dark inner apron so arena borders read cleanly without affecting unit contrast
	var apron: float = 28.0
	var shade: Color = Color(0.015, 0.022, 0.032, 0.34)
	draw_rect(Rect2(min_x, min_y, b.size.x, apron), shade, true)
	draw_rect(Rect2(min_x, max_y - apron, b.size.x, apron), shade, true)
	draw_rect(Rect2(min_x, min_y + apron, apron, maxf(0.0, b.size.y - apron * 2.0)), shade, true)
	draw_rect(Rect2(max_x - apron, min_y + apron, apron, maxf(0.0, b.size.y - apron * 2.0)), shade, true)

	var inner_frame: Rect2 = b.grow(-14.0)
	var line_col: Color = Color(0.68, 0.78, 0.88, 0.14)
	var tick_col: Color = Color(0.74, 0.86, 0.96, 0.20)
	if inner_frame.has_area():
		draw_rect(inner_frame, line_col, false, 1.2)
		_draw_corner_brackets(inner_frame, 36.0, tick_col, 2.0)

	# 256 px coordinate registration tick marks along all 4 perimeter edges
	var tx: float = ceilf(min_x / 256.0) * 256.0
	while tx <= max_x:
		var is_origin_x: bool = is_zero_approx(tx)
		var t_len: float = 18.0 if is_origin_x else 10.0
		draw_line(Vector2(tx, min_y + 2.0), Vector2(tx, min_y + 2.0 + t_len), tick_col, 1.4 if is_origin_x else 1.1)
		draw_line(Vector2(tx, max_y - 2.0), Vector2(tx, max_y - 2.0 - t_len), tick_col, 1.4 if is_origin_x else 1.1)
		tx += 256.0

	var ty: float = ceilf(min_y / 256.0) * 256.0
	while ty <= max_y:
		var is_origin_y: bool = is_zero_approx(ty)
		var t_len_y: float = 18.0 if is_origin_y else 10.0
		draw_line(Vector2(min_x + 2.0, ty), Vector2(min_x + 2.0 + t_len_y, ty), tick_col, 1.4 if is_origin_y else 1.1)
		draw_line(Vector2(max_x - 2.0, ty), Vector2(max_x - 2.0 - t_len_y, ty), tick_col, 1.4 if is_origin_y else 1.1)
		ty += 256.0
