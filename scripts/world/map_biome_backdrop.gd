class_name MapBiomeBackdrop
extends Node2D

## Procedural zero-per-frame-cost map biome floor renderer (Milestone 3.2).
## Renders distinct, dark, low-contrast tactical floor treatments strictly below
## BattleScarsOverlay, landmarks, terrain obstacles, units, and Fog of War.

@export var biome_id: StringName = &"vat_basin"
@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)


func _ready() -> void:
	z_index = -100
	set_process(false)
	set_physics_process(false)
	_sync_bounds_from_nav_region()
	queue_redraw()


func _sync_bounds_from_nav_region() -> void:
	var nav: Node = get_tree().get_first_node_in_group("arena_nav_region")
	if nav == null and get_parent() != null:
		nav = get_parent().get_node_or_null("NavigationRegion2D")
	if nav != null and nav is ArenaNavRegion:
		var arena_nav: ArenaNavRegion = nav as ArenaNavRegion
		if arena_nav.arena_bounds.size.x > 0.0 and arena_nav.arena_bounds.size.y > 0.0:
			arena_bounds = arena_nav.arena_bounds


func _draw() -> void:
	match biome_id:
		&"twin_causeway":
			_draw_twin_causeway()
		&"quad_nexus":
			_draw_quad_nexus()
		_:
			_draw_vat_basin()


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

	# 2. Soft recessed basin gradient rings (very low alpha so units pop)
	draw_circle(Vector2.ZERO, 620.0, Color(0.06, 0.17, 0.22, 0.14))
	draw_circle(Vector2.ZERO, 390.0, Color(0.08, 0.24, 0.28, 0.11))
	draw_circle(Vector2(-900.0, 560.0), 340.0, Color(0.06, 0.20, 0.24, 0.12))
	draw_circle(Vector2(900.0, -560.0), 340.0, Color(0.06, 0.20, 0.24, 0.12))

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

	# 4. Faint diagonal bio-conduit channels connecting bases -> plaza & NW/SE terraces
	var conduit_outer: Color = Color(0.14, 0.64, 0.60, 0.085)
	var conduit_core: Color = Color(0.28, 0.88, 0.76, 0.095)
	var conduits: Array[Array] = [
		[Vector2(-900.0, 560.0), Vector2(-380.0, 220.0), Vector2.ZERO],
		[Vector2(900.0, -560.0), Vector2(380.0, -220.0), Vector2.ZERO],
		[Vector2(-900.0, 560.0), Vector2(-820.0, -480.0), Vector2(-260.0, -260.0), Vector2.ZERO],
		[Vector2(900.0, -560.0), Vector2(820.0, 480.0), Vector2(260.0, 260.0), Vector2.ZERO],
	]
	for path_pts: Array in conduits:
		var packed: PackedVector2Array = PackedVector2Array()
		for pt: Vector2 in path_pts:
			packed.append(pt)
		draw_polyline(packed, conduit_outer, 14.0, true)
		draw_polyline(packed, conduit_core, 2.0, true)

	# 5. Concentric topographic basin contour rings around central Hyper-Uplink (0,0)
	var contour_col: Color = Color(0.26, 0.78, 0.76, 0.11)
	var contour_faint: Color = Color(0.22, 0.68, 0.70, 0.075)
	for rad: float in [150.0, 250.0, 360.0, 490.0, 640.0]:
		var col: Color = contour_col if rad <= 360.0 else contour_faint
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 64, col, 1.4, true)
		# Subtle cardinal registration ticks
		for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dir: Vector2 = Vector2.from_angle(ang)
			draw_line(dir * (rad - 6.0), dir * (rad + 6.0), col, 1.2)

	# 6. Circular pad contours around the two corner Vat Basins + NW/SE expansion pads
	for base_center: Vector2 in [Vector2(-900.0, 560.0), Vector2(900.0, -560.0)]:
		draw_arc(base_center, 155.0, 0.0, TAU, 48, contour_col, 1.5, true)
		draw_arc(base_center, 235.0, 0.0, TAU, 56, contour_faint, 1.2, true)
		draw_arc(base_center, 315.0, 0.0, TAU, 64, Color(0.20, 0.62, 0.66, 0.055), 1.0, true)

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

	# 4. Industrial hazard striping (#FF9F1C at ~0.11 alpha) framing key tactical lanes
	var amber_hazard: Color = Color(1.0, 0.624, 0.11, 0.115)
	var amber_border: Color = Color(1.0, 0.624, 0.11, 0.16)
	# Central Causeway Bridge north & south apron stripes (flanking the CausewayWalls at y = ±340)
	_draw_hazard_strip(Rect2(-460.0, -296.0, 920.0, 22.0), amber_hazard, amber_border, 22.0)
	_draw_hazard_strip(Rect2(-460.0, 274.0, 920.0, 22.0), amber_hazard, amber_border, 22.0)
	# Barricade-sealed North & South flank bypass corridors (around x = ±160, y = ±760)
	_draw_hazard_strip(Rect2(-340.0, -854.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
	_draw_hazard_strip(Rect2(-340.0, -682.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
	_draw_hazard_strip(Rect2(-20.0, 666.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
	_draw_hazard_strip(Rect2(-20.0, 838.0, 360.0, 16.0), amber_hazard, amber_border, 18.0)
	# NW & SE Vault Seal vertical hazard markers (around (-720, -240) and (720, 240))
	_draw_hazard_strip(Rect2(-804.0, -252.0, 168.0, 14.0), amber_hazard, amber_border, 16.0)
	_draw_hazard_strip(Rect2(636.0, 238.0, 168.0, 14.0), amber_hazard, amber_border, 16.0)

	# 5. Subtle central loading-bay frame around the Bridge Plaza (0,0)
	draw_rect(Rect2(-240.0, -180.0, 480.0, 360.0), Color(0.75, 0.80, 0.86, 0.08), false, 1.8)
	draw_line(Vector2(-460.0, 0.0), Vector2(-140.0, 0.0), Color(1.0, 0.624, 0.11, 0.085), 2.0)
	draw_line(Vector2(140.0, 0.0), Vector2(460.0, 0.0), Color(1.0, 0.624, 0.11, 0.085), 2.0)

	# 6. Etched directional lane chevrons pointing toward the center objective
	var chev_col: Color = Color(0.84, 0.86, 0.88, 0.095)
	for cx: float in [-420.0, -340.0, -260.0]:
		_draw_chevron(Vector2(cx, 0.0), Vector2.RIGHT, 24.0, 38.0, chev_col)
	for cx_e: float in [420.0, 340.0, 260.0]:
		_draw_chevron(Vector2(cx_e, 0.0), Vector2.LEFT, 24.0, 38.0, chev_col)
	# Diagonal approach chevrons from West/East bases toward center bridge
	for t: float in [0.28, 0.44]:
		var w_pt: Vector2 = Vector2(-900.0, 420.0).lerp(Vector2(-320.0, 80.0), t)
		_draw_chevron(w_pt, (Vector2(-320.0, 80.0) - Vector2(-900.0, 420.0)).normalized(), 18.0, 28.0, Color(0.76, 0.80, 0.84, 0.075))
		var e_pt: Vector2 = Vector2(900.0, -420.0).lerp(Vector2(320.0, -80.0), t)
		_draw_chevron(e_pt, (Vector2(320.0, -80.0) - Vector2(900.0, -420.0)).normalized(), 18.0, 28.0, Color(0.76, 0.80, 0.84, 0.075))

	# 7. Industrial base pad frames around West & East Causeway Basins
	for base_pos: Vector2 in [Vector2(-900.0, 420.0), Vector2(900.0, -420.0)]:
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

	# Cardinal meridian divider axes radiating cleanly from (0,0)
	var axis_col: Color = Color(0.42, 0.66, 0.96, 0.115)
	draw_line(Vector2(min_x, 0.0), Vector2(max_x, 0.0), axis_col, 1.6)
	draw_line(Vector2(0.0, min_y), Vector2(0.0, max_y), axis_col, 1.6)

	# 3. Clean 45° diagonal bus traces linking all 4 spawn corners to the central Hyper-Uplink ring
	var bus_outer: Color = Color(0.32, 0.56, 0.94, 0.085)
	var bus_inner: Color = Color(0.52, 0.78, 1.0, 0.125)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner_pt: Vector2 = Vector2(sx * 1180.0, sy * 1120.0)
			var diag_start: Vector2 = Vector2(sx * 1080.0, sy * 1080.0)
			var diag_end: Vector2 = Vector2(sx * 140.0, sy * 140.0)
			var perp: Vector2 = Vector2(-sy, sx).normalized()
			# Triple parallel circuit bus trace along exact 45° diagonal
			draw_line(diag_start, diag_end, bus_outer, 14.0, true)
			draw_line(diag_start, diag_end, bus_inner, 1.8, true)
			draw_line(diag_start + perp * 16.0, diag_end + perp * 16.0, bus_outer, 1.4, true)
			draw_line(diag_start - perp * 16.0, diag_end - perp * 16.0, bus_outer, 1.4, true)
			# Small circuit node pads along the diagonal bus
			for d: float in [420.0, 680.0, 920.0]:
				var node_pt: Vector2 = Vector2(sx * d, sy * d)
				draw_circle(node_pt, 5.0, bus_inner)
				draw_arc(node_pt, 10.0, 0.0, TAU, 16, bus_outer, 1.2, true)
			# Short connector from corner basin into diagonal bus
			draw_line(corner_pt, diag_start, bus_inner, 1.8, true)

	# 4. Concentric octagonal telemetry rings around central plaza (180 px, 320 px, 520 px)
	var oct_cols: Array[Color] = [
		Color(0.44, 0.74, 1.0, 0.14),
		Color(0.38, 0.64, 0.96, 0.11),
		Color(0.32, 0.54, 0.88, 0.085),
	]
	var oct_rads: Array[float] = [180.0, 320.0, 520.0]
	for idx: int in range(oct_rads.size()):
		_draw_octagon(Vector2.ZERO, oct_rads[idx], oct_cols[idx], 1.6 if idx == 0 else 1.3)

	# 5. Perimeter outer-corridor lane markers aligning with the 4 barricaded flank gates (±1060)
	var corr_col: Color = Color(0.40, 0.66, 0.96, 0.095)
	var corr_dash: Color = Color(0.52, 0.78, 1.0, 0.11)
	var corr_rect_outer: Rect2 = Rect2(-1135.0, -1135.0, 2270.0, 2270.0)
	var corr_rect_inner: Rect2 = Rect2(-985.0, -985.0, 1970.0, 1970.0)
	draw_rect(corr_rect_outer, corr_col, false, 1.4)
	draw_rect(corr_rect_inner, corr_col, false, 1.4)
	# Subtle gate-lane alignment ticks around the 4 cardinal barricade seals
	for gate_pos: Vector2 in [Vector2(0.0, -1060.0), Vector2(0.0, 1060.0), Vector2(-1060.0, 0.0), Vector2(1060.0, 0.0)]:
		draw_rect(Rect2(gate_pos - Vector2(96.0, 44.0), Vector2(192.0, 88.0)), corr_dash, false, 1.4)

	# 6. Neutral quadrant corner brackets marking all 4 spawn sectors (zero team color bias)
	var neutral_bracket: Color = Color(0.68, 0.76, 0.90, 0.16)
	var neutral_frame: Color = Color(0.46, 0.58, 0.78, 0.075)
	for sx_q: float in [-1.0, 1.0]:
		for sy_q: float in [-1.0, 1.0]:
			var sector_center: Vector2 = Vector2(sx_q * 1180.0, sy_q * 1120.0)
			var sector_rect: Rect2 = Rect2(sector_center - Vector2(210.0, 190.0), Vector2(420.0, 380.0))
			draw_rect(sector_rect, neutral_frame, false, 1.2)
			_draw_corner_brackets(sector_rect, 32.0, neutral_bracket, 2.4)


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
