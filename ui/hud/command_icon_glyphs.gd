class_name CommandIconGlyphs
extends RefCounted

## Procedural 28x28 vector glyph library for CommandIconButton.
## Separates shared RTS command glyphs and faction unit/building/ability/upgrade emblems
## from the interactive button widget, and supports pluggable custom drawers for future factions.

static var _custom_drawers: Array[Callable] = []


## Register an optional custom glyph drawer Callable(canvas, icon_id, icon_category, c, fg, hi, dark) -> bool.
## Return true when handled so future factions (#3-#5) can plug in custom emblems without editing core HUD code.
static func register_glyph_drawer(drawer: Callable) -> void:
	if drawer.is_valid() and not _custom_drawers.has(drawer):
		_custom_drawers.append(drawer)


static func poly_icon(canvas: CanvasItem, pts: PackedVector2Array, fill: Color, line: Color, lw: float = 1.4) -> void:
	canvas.draw_colored_polygon(pts, fill)
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	canvas.draw_polyline(closed, line, lw, true)


static func draw_icon(
	canvas: CanvasItem,
	icon_id: StringName,
	icon_category: StringName,
	c: Vector2,
	fg: Color,
	hi: Color,
	dark: Color
) -> void:
	for drawer: Callable in _custom_drawers:
		if drawer.is_valid() and bool(drawer.call(canvas, icon_id, icon_category, c, fg, hi, dark)):
			return

	match icon_id:
		# --- STANDARD UNIT COMMANDS ---
		&"cmd_move":
			var arr: PackedVector2Array = PackedVector2Array([
				c + Vector2(-9, -3), c + Vector2(1, -3), c + Vector2(1, -8),
				c + Vector2(11, 0), c + Vector2(1, 8), c + Vector2(1, 3), c + Vector2(-9, 3),
			])
			poly_icon(canvas, arr, Color(fg.r, fg.g, fg.b, 0.32), fg, 1.8)
		&"cmd_stop":
			var oct: PackedVector2Array = PackedVector2Array([
				c + Vector2(-4, -9), c + Vector2(4, -9), c + Vector2(9, -4), c + Vector2(9, 4),
				c + Vector2(4, 9), c + Vector2(-4, 9), c + Vector2(-9, 4), c + Vector2(-9, -4),
			])
			poly_icon(canvas, oct, Color(fg.r, fg.g, fg.b, 0.25), fg, 1.8)
			canvas.draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), hi, true)
		&"cmd_hold":
			var sh: PackedVector2Array = PackedVector2Array([
				c + Vector2(-8, -8), c + Vector2(8, -8), c + Vector2(8, 1),
				c + Vector2(0, 10), c + Vector2(-8, 1),
			])
			poly_icon(canvas, sh, Color(fg.r, fg.g, fg.b, 0.28), fg, 1.8)
			canvas.draw_line(c + Vector2(0, -5), c + Vector2(0, 5), hi, 2.0, true)
			canvas.draw_line(c + Vector2(-4.5, 0), c + Vector2(4.5, 0), hi, 2.0, true)
		&"cmd_defensive":
			var sh_d: PackedVector2Array = PackedVector2Array([
				c + Vector2(-6.5, -6), c + Vector2(6.5, -6), c + Vector2(6.5, 1),
				c + Vector2(0, 8), c + Vector2(-6.5, 1),
			])
			poly_icon(canvas, sh_d, Color(fg.r, fg.g, fg.b, 0.30), fg, 1.6)
			canvas.draw_arc(c, 11.5, -PI * 0.85, -PI * 0.15, 8, hi, 1.5, true)
			canvas.draw_arc(c, 11.5, PI * 0.15, PI * 0.85, 8, hi, 1.5, true)
		&"cmd_patrol":
			canvas.draw_line(c + Vector2(-9, -4), c + Vector2(8, -4), fg, 2.0, true)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(4, -8), c + Vector2(9, -4), c + Vector2(4, 0)]), hi, 1.8, true)
			canvas.draw_line(c + Vector2(9, 4), c + Vector2(-8, 4), fg, 2.0, true)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-9, 4), c + Vector2(-4, 8)]), hi, 1.8, true)
		&"cmd_amove":
			canvas.draw_arc(c, 8.5, 0.0, TAU, 20, fg, 1.8, true)
			canvas.draw_circle(c, 2.4, hi)
			canvas.draw_line(c + Vector2(-12, 0), c + Vector2(-5, 0), fg, 1.8, true)
			canvas.draw_line(c + Vector2(5, 0), c + Vector2(12, 0), fg, 1.8, true)
			canvas.draw_line(c + Vector2(0, -12), c + Vector2(0, -5), fg, 1.8, true)
			canvas.draw_line(c + Vector2(0, 5), c + Vector2(0, 12), fg, 1.8, true)

		# --- FACILITY & UTILITY SPECIALS ---
		&"overclock":
			canvas.draw_rect(Rect2(c - Vector2(10, 10), Vector2(20, 20)), Color(fg.r, fg.g, fg.b, 0.16), true)
			canvas.draw_rect(Rect2(c - Vector2(10, 10), Vector2(20, 20)), fg, false, 1.6)
			var bolt: PackedVector2Array = PackedVector2Array([
				c + Vector2(2, -9), c + Vector2(-5, 1), c + Vector2(0, 1),
				c + Vector2(-2, 9), c + Vector2(6, -1), c + Vector2(1, -1),
			])
			poly_icon(canvas, bolt, hi, fg, 1.3)
		&"deploy":
			for di: int in range(4):
				var da: float = PI * 0.25 + float(di) * (PI * 0.5)
				var dv: Vector2 = Vector2.RIGHT.rotated(da)
				canvas.draw_line(c + dv * 4.5, c + dv * 11.0, fg, 2.2, true)
				canvas.draw_circle(c + dv * 11.0, 2.0, hi)
			canvas.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), dark, true)
			canvas.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), fg, false, 1.6)
			canvas.draw_line(c, c + Vector2(11, 0), hi, 3.0, true)
		&"auto_repair":
			canvas.draw_arc(c, 9.5, 0.0, TAU, 18, Color(fg.r, fg.g, fg.b, 0.55), 1.4, true)
			canvas.draw_rect(Rect2(c - Vector2(2.5, 7.5), Vector2(5, 15)), fg, true)
			canvas.draw_rect(Rect2(c - Vector2(7.5, 2.5), Vector2(15, 5)), fg, true)
			canvas.draw_circle(c, 2.0, hi)
		&"eject_engineers":
			canvas.draw_rect(Rect2(c + Vector2(-9, 2), Vector2(18, 7)), Color(fg.r, fg.g, fg.b, 0.25), true)
			canvas.draw_rect(Rect2(c + Vector2(-9, 2), Vector2(18, 7)), fg, false, 1.6)
			canvas.draw_line(c + Vector2(0, 3), c + Vector2(0, -9), hi, 2.2, true)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-6, -4), c + Vector2(0, -10), c + Vector2(6, -4)]), hi, 2.0, true)
		&"salvage", &"cancel_build":
			canvas.draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), Color(fg.r, fg.g, fg.b, 0.16), true)
			canvas.draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), fg, false, 1.4)
			canvas.draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), hi, 2.4, true)
			canvas.draw_line(c + Vector2(6, -6), c + Vector2(-6, 6), hi, 2.4, true)

		# --- UNITS (GENESIS_V2 & MONOLITH_OS) ---
		&"worker", &"servo_drone":
			var body_w: PackedVector2Array = PackedVector2Array([
				c + Vector2(-8, -6), c + Vector2(3, -6), c + Vector2(3, 6), c + Vector2(-8, 6),
			])
			poly_icon(canvas, body_w, dark, fg, 1.6)
			canvas.draw_line(c + Vector2(3, -4), c + Vector2(10, -5), hi, 2.2, true)
			canvas.draw_line(c + Vector2(3, 4), c + Vector2(10, 5), hi, 2.2, true)
			canvas.draw_circle(c + Vector2(-2.5, 0), 2.5, fg)
		&"silica_harvester", &"ore_crawler":
			canvas.draw_rect(Rect2(c + Vector2(-10, -8), Vector2(15, 16)), dark, true)
			canvas.draw_rect(Rect2(c + Vector2(-10, -8), Vector2(15, 16)), fg, false, 1.6)
			canvas.draw_rect(Rect2(c + Vector2(-7, -4.5), Vector2(9, 9)), fg, true)
			var scoop: PackedVector2Array = PackedVector2Array([
				c + Vector2(5, -9), c + Vector2(11, -6), c + Vector2(11, 6), c + Vector2(5, 9),
			])
			poly_icon(canvas, scoop, hi, dark, 1.2)
		&"engineer", &"grid_tech":
			var hex_e: PackedVector2Array = PackedVector2Array([
				c + Vector2(9, 0), c + Vector2(4.5, 8), c + Vector2(-4.5, 8),
				c + Vector2(-9, 0), c + Vector2(-4.5, -8), c + Vector2(4.5, -8),
			])
			poly_icon(canvas, hex_e, dark, fg, 1.7)
			canvas.draw_circle(c, 3.4, hi)
			canvas.draw_line(c + Vector2(6, -3), c + Vector2(11, -5), hi, 1.6, true)
			canvas.draw_line(c + Vector2(6, 3), c + Vector2(11, 5), hi, 1.6, true)
		&"clone_trooper":
			canvas.draw_circle(c + Vector2(-2, 0), 6.5, dark)
			canvas.draw_arc(c + Vector2(-2, 0), 6.5, 0.0, TAU, 16, fg, 1.8, true)
			canvas.draw_line(c + Vector2(2, 2), c + Vector2(12, 2), hi, 2.4, true)
			canvas.draw_circle(c + Vector2(0, -1), 2.5, fg)
		&"stinger":
			var dart: PackedVector2Array = PackedVector2Array([
				c + Vector2(11, 0), c + Vector2(-8, -9), c + Vector2(-3, 0), c + Vector2(-8, 9),
			])
			poly_icon(canvas, dart, Color(fg.r, fg.g, fg.b, 0.35), hi, 1.6)
		&"symbiote":
			canvas.draw_circle(c, 8.5, Color(fg.r, fg.g, fg.b, 0.22))
			canvas.draw_arc(c, 8.5, 0.0, TAU, 18, fg, 1.6, true)
			canvas.draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), hi, 2.4, true)
			canvas.draw_line(c + Vector2(0, -5), c + Vector2(0, 5), hi, 2.4, true)
		&"lance_rig", &"rail_sentinel":
			canvas.draw_rect(Rect2(c + Vector2(-10, -6), Vector2(14, 12)), dark, true)
			canvas.draw_rect(Rect2(c + Vector2(-10, -6), Vector2(14, 12)), fg, false, 1.6)
			canvas.draw_line(c + Vector2(0, -2.5), c + Vector2(12, -2.5), hi, 1.8, true)
			canvas.draw_line(c + Vector2(0, 2.5), c + Vector2(12, 2.5), hi, 1.8, true)
			canvas.draw_line(c + Vector2(-4, 0), c + Vector2(12, 0), fg, 2.0, true)
		&"signal_jammer":
			canvas.draw_arc(c, 5.0, -1.1, 1.1, 10, hi, 1.8, true)
			canvas.draw_arc(c, 9.5, -1.0, 1.0, 12, fg, 1.8, true)
			canvas.draw_circle(c + Vector2(-4, 0), 3.6, fg)
		&"goliath_frame", &"monolith_dreadnought":
			canvas.draw_rect(Rect2(c + Vector2(-10, -9), Vector2(18, 18)), dark, true)
			canvas.draw_rect(Rect2(c + Vector2(-10, -9), Vector2(18, 18)), fg, false, 2.0)
			canvas.draw_line(c + Vector2(2, -10.5), c + Vector2(12, -10.5), hi, 2.8, true)
			canvas.draw_line(c + Vector2(2, 10.5), c + Vector2(12, 10.5), hi, 2.8, true)
			canvas.draw_rect(Rect2(c + Vector2(-5, -4), Vector2(8, 8)), fg, true)
		&"arc_lancer":
			var lance_pts: PackedVector2Array = PackedVector2Array([
				c + Vector2(-9, -7), c + Vector2(3, -5), c + Vector2(3, 5), c + Vector2(-9, 7),
			])
			poly_icon(canvas, lance_pts, dark, fg, 1.6)
			canvas.draw_line(c + Vector2(2, 0), c + Vector2(12, 0), hi, 3.0, true)
			canvas.draw_circle(c + Vector2(11, 0), 2.5, fg)
		&"chrysalis_mortar", &"anvil_siege_walker":
			for li: int in range(4):
				var la: float = PI * 0.25 + float(li) * (PI * 0.5)
				canvas.draw_line(c, c + Vector2.RIGHT.rotated(la) * 11.0, fg, 2.0, true)
			canvas.draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), dark, true)
			canvas.draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), hi, false, 1.5)
			canvas.draw_line(c, c + Vector2(11, -3), hi, 3.4, true)
			canvas.draw_circle(c + Vector2(11, -3), 2.2, fg)
		&"bulwark_automaton":
			canvas.draw_rect(Rect2(c + Vector2(-9, -8), Vector2(13, 16)), dark, true)
			canvas.draw_rect(Rect2(c + Vector2(-9, -8), Vector2(13, 16)), fg, false, 1.7)
			canvas.draw_rect(Rect2(c + Vector2(4, -9), Vector2(5, 18)), hi, true)
			canvas.draw_rect(Rect2(c + Vector2(-5, -3), Vector2(6, 6)), fg, true)
		&"picket_drone":
			var p_poly: PackedVector2Array = PackedVector2Array([
				c + Vector2(11, 0), c + Vector2(1, -8), c + Vector2(-9, -7),
				c + Vector2(-9, 7), c + Vector2(1, 8),
			])
			poly_icon(canvas, p_poly, dark, fg, 1.7)
			canvas.draw_line(c + Vector2(4, -3), c + Vector2(12, -2), hi, 1.6, true)
			canvas.draw_line(c + Vector2(4, 3), c + Vector2(12, 2), hi, 1.6, true)
		&"aegis_relay":
			var dia: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -10), c + Vector2(10, 0), c + Vector2(0, 10), c + Vector2(-10, 0),
			])
			poly_icon(canvas, dia, Color(fg.r, fg.g, fg.b, 0.26), hi, 1.7)
			canvas.draw_circle(c, 3.6, fg)
		&"null_grid_projector":
			canvas.draw_arc(c + Vector2(2, 0), 9.0, -1.2, 1.2, 12, hi, 2.0, true)
			canvas.draw_rect(Rect2(c + Vector2(-10, -7), Vector2(9, 14)), dark, true)
			canvas.draw_rect(Rect2(c + Vector2(-10, -7), Vector2(9, 14)), fg, false, 1.6)
			canvas.draw_circle(c + Vector2(4, 0), 3.6, fg)

		# --- PRISMA_DEI UNITS (BAUHAUS SACRED GEOMETRY) ---
		&"acolyte":
			var aco: PackedVector2Array = PackedVector2Array([
				c + Vector2(9, 0), c + Vector2(-7, -8), c + Vector2(-4, 0), c + Vector2(-7, 8),
			])
			poly_icon(canvas, aco, dark, fg, 1.6)
			canvas.draw_line(c + Vector2(5, -4), c + Vector2(11, -3), hi, 1.6, true)
			canvas.draw_line(c + Vector2(5, 4), c + Vector2(11, 3), hi, 1.6, true)
			canvas.draw_circle(c, 2.4, hi)
		&"prism_dredge":
			var drg: PackedVector2Array = PackedVector2Array([
				c + Vector2(11, 0), c + Vector2(0, -9), c + Vector2(-10, 0), c + Vector2(0, 9),
			])
			poly_icon(canvas, drg, dark, fg, 1.7)
			canvas.draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), hi, true)
		&"luminant":
			canvas.draw_arc(c, 8.5, -2.3, 2.3, 18, fg, 1.8, true)
			var lum: PackedVector2Array = PackedVector2Array([
				c + Vector2(6, 0), c + Vector2(-2, -6), c + Vector2(-6, 0), c + Vector2(-2, 6),
			])
			poly_icon(canvas, lum, dark, hi, 1.5)
			canvas.draw_circle(c, 2.2, hi)
		&"votary":
			var vot: PackedVector2Array = PackedVector2Array([
				c + Vector2(11, 0), c + Vector2(-8, -9), c + Vector2(-3, 0), c + Vector2(-8, 9),
			])
			poly_icon(canvas, vot, dark, fg, 1.7)
			canvas.draw_line(c + Vector2(-2, 0), c + Vector2(10, 0), hi, 1.8, true)
		&"lumen_skiff":
			var skf: PackedVector2Array = PackedVector2Array([
				c + Vector2(12, 0), c + Vector2(0, -6), c + Vector2(-11, 0), c + Vector2(0, 6),
			])
			poly_icon(canvas, skf, dark, fg, 1.6)
			canvas.draw_arc(c + Vector2(-2, 0), 9.5, -1.1, 1.1, 12, hi, 1.5, true)
			canvas.draw_circle(c + Vector2(-8, 0), 2.0, hi)
		&"cantor":
			canvas.draw_arc(c, 9.5, 0.0, TAU, 22, fg, 1.8, true)
			var tri_c: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -7), c + Vector2(6.5, 5), c + Vector2(-6.5, 5),
			])
			poly_icon(canvas, tri_c, dark, hi, 1.5)
			canvas.draw_circle(c, 2.6, fg)
		&"lens_adjudicator":
			var adj: PackedVector2Array = PackedVector2Array([
				c + Vector2(11, -4), c + Vector2(11, 4), c + Vector2(1, 9),
				c + Vector2(-10, 6), c + Vector2(-10, -6), c + Vector2(1, -9),
			])
			poly_icon(canvas, adj, dark, fg, 1.7)
			canvas.draw_line(c + Vector2(2, -5), c + Vector2(12, -3), hi, 1.8, true)
			canvas.draw_line(c + Vector2(2, 5), c + Vector2(12, 3), hi, 1.8, true)
			canvas.draw_circle(c + Vector2(3, 0), 3.0, hi)
		&"prism_weaver":
			for wi: int in range(3):
				var wa: float = float(wi) * (TAU / 3.0)
				var wd: Vector2 = Vector2.RIGHT.rotated(wa)
				canvas.draw_line(c, c + wd * 10.5, fg, 2.0, true)
				canvas.draw_circle(c + wd * 10.5, 2.2, hi)
			var wcore: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0),
			])
			poly_icon(canvas, wcore, dark, hi, 1.5)
		&"seraph_cruiser":
			# Swept angelic delta wings + double halo core
			var s_l: PackedVector2Array = PackedVector2Array([c + Vector2(10, -2), c + Vector2(-9, -11), c + Vector2(-4, -3)])
			var s_r: PackedVector2Array = PackedVector2Array([c + Vector2(10, 2), c + Vector2(-9, 11), c + Vector2(-4, 3)])
			poly_icon(canvas, s_l, dark, fg, 1.5)
			poly_icon(canvas, s_r, dark, fg, 1.5)
			canvas.draw_arc(c + Vector2(-1, 0), 5.8, 0.0, TAU, 16, hi, 1.6, true)
			canvas.draw_circle(c + Vector2(4, 0), 2.5, hi)
		&"solstice_lance":
			# Twin gilded siege rails + floating central lens diamond
			var sl_b: PackedVector2Array = PackedVector2Array([c + Vector2(1, -7), c + Vector2(-10, -8), c + Vector2(-10, 8), c + Vector2(1, 7)])
			poly_icon(canvas, sl_b, dark, fg, 1.5)
			canvas.draw_line(c + Vector2(-2, -4), c + Vector2(11, -2.5), hi, 2.0, true)
			canvas.draw_line(c + Vector2(-2, 4), c + Vector2(11, 2.5), hi, 2.0, true)
			var sl_d: PackedVector2Array = PackedVector2Array([c + Vector2(9, 0), c + Vector2(5, -3), c + Vector2(1, 0), c + Vector2(5, 3)])
			poly_icon(canvas, sl_d, hi, fg, 1.1)

		# --- PRISMA_DEI ABILITIES ---
		&"aureole_surge":
			# Radiant double-halo corona with 4 cardinal flare spikes
			canvas.draw_arc(c, 9.5, 0.0, TAU, 22, fg, 1.8, true)
			canvas.draw_arc(c, 5.2, 0.0, TAU, 16, hi, 1.6, true)
			for ai: int in range(4):
				var aa: float = float(ai) * (PI * 0.5)
				var ad: Vector2 = Vector2.RIGHT.rotated(aa)
				canvas.draw_line(c + ad * 5.5, c + ad * 12.0, hi, 1.8, true)
			canvas.draw_circle(c, 2.4, hi)
		&"solar_convergence":
			# Vertical orbital beam column piercing a sacred target ring
			canvas.draw_arc(c + Vector2(0, 4), 8.5, 0.0, TAU, 20, fg, 1.6, true)
			canvas.draw_line(c + Vector2(0, -11), c + Vector2(0, 5), hi, 3.2, true)
			canvas.draw_line(c + Vector2(-9, 4), c + Vector2(9, 4), fg, 1.4, true)
			canvas.draw_circle(c + Vector2(0, 4), 3.0, hi)

		# --- PRISMA_DEI UPGRADES ---
		&"prisma_harmonic_communion":
			# Concentric gold tether ring + 4 cardinal diamond nodes
			canvas.draw_arc(c, 8.2, 0.0, TAU, 20, fg, 1.7, true)
			for ci: int in range(4):
				var ca: float = float(ci) * (PI * 0.5)
				var cp: Vector2 = c + Vector2.RIGHT.rotated(ca) * 8.2
				canvas.draw_circle(cp, 2.4, hi)
			canvas.draw_circle(c, 3.0, hi)
		&"prisma_specular_focusing":
			# Split refracting prism beam (1 incoming -> 3 fanned rays)
			var sf_t: PackedVector2Array = PackedVector2Array([c + Vector2(-1, -7), c + Vector2(5, 6), c + Vector2(-7, 6)])
			poly_icon(canvas, sf_t, dark, fg, 1.6)
			canvas.draw_line(c + Vector2(-11, 0), c + Vector2(-3, 0), hi, 2.0, true)
			canvas.draw_line(c + Vector2(2, 0), c + Vector2(11, -7), hi, 1.7, true)
			canvas.draw_line(c + Vector2(2, 0), c + Vector2(11, 0), fg, 1.7, true)
			canvas.draw_line(c + Vector2(2, 0), c + Vector2(11, 7), hi, 1.7, true)
		&"prisma_solar_apotheosis":
			# Solar gold double crown chevrons + apex sunburst diamond
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-9, 6), c + Vector2(0, -2), c + Vector2(9, 6)]), fg, 2.0, true)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(0, -7), c + Vector2(7, 0)]), hi, 2.2, true)
			canvas.draw_circle(c + Vector2(0, -9), 2.4, hi)
		&"solar_step":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-8, -6), c + Vector2(0, 0), c + Vector2(-8, 6)]), fg, 2.0, true)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(0, -7), c + Vector2(9, 0), c + Vector2(0, 7)]), hi, 2.2, true)
			canvas.draw_circle(c + Vector2(-3, 0), 2.0, hi)
		&"radiant_mark":
			canvas.draw_arc(c, 8.5, 0.0, TAU, 20, fg, 1.7, true)
			var rm_d: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -11), c + Vector2(4, 0), c + Vector2(0, 11), c + Vector2(-4, 0),
			])
			poly_icon(canvas, rm_d, Color(fg.r, fg.g, fg.b, 0.25), hi, 1.5)
			canvas.draw_circle(c, 2.4, hi)
		&"luminous_mend":
			canvas.draw_arc(c, 9.5, 0.0, TAU, 20, fg, 1.7, true)
			for mi: int in range(8):
				var ma: float = float(mi) * (TAU / 8.0)
				var md: Vector2 = Vector2.RIGHT.rotated(ma)
				canvas.draw_line(c + md * 4.5, c + md * 10.5, hi if (mi % 2 == 0) else fg, 1.5, true)
			canvas.draw_circle(c, 3.2, hi)
		&"focus_alignment":
			canvas.draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), hi, 2.2, true)
			var fa_d: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -9), c + Vector2(7, 0), c + Vector2(0, 9), c + Vector2(-7, 0),
			])
			poly_icon(canvas, fa_d, Color(fg.r, fg.g, fg.b, 0.26), fg, 1.7)
			canvas.draw_circle(c, 2.8, hi)
		&"blinding_glare":
			for bi: int in range(8):
				var ba: float = float(bi) * (TAU / 8.0)
				var bd: Vector2 = Vector2.RIGHT.rotated(ba)
				var r_out: float = 11.0 if (bi % 2 == 0) else 7.5
				canvas.draw_line(c + bd * 2.5, c + bd * r_out, hi if (bi % 2 == 0) else fg, 1.8, true)
			canvas.draw_circle(c, 3.5, hi)

		# --- ABILITIES ---
		&"adrenal_surge":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-8, 2), c + Vector2(0, -7), c + Vector2(8, 2)]), hi, 2.2, true)
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-7, 8), c + Vector2(0, 0), c + Vector2(7, 8)]), fg, 2.2, true)
		&"monolith_shield_overcharge":
			canvas.draw_arc(c, 9.5, 0.0, TAU, 20, fg, 1.8, true)
			canvas.draw_circle(c, 4.2, Color(fg.r, fg.g, fg.b, 0.40))
			canvas.draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), hi, 2.2, true)
			canvas.draw_line(c + Vector2(0, -5), c + Vector2(0, 5), hi, 2.2, true)
		&"kinetic_barrier":
			var hex_kb: PackedVector2Array = PackedVector2Array()
			for ki: int in range(6):
				var ka: float = float(ki) * (TAU / 6.0) + PI / 6.0
				hex_kb.append(c + Vector2.RIGHT.rotated(ka) * 10.5)
			poly_icon(canvas, hex_kb, Color(fg.r, fg.g, fg.b, 0.28), hi, 2.0)
			canvas.draw_circle(c, 3.5, fg)
		&"static_pulse", &"monolith_suppressive_lock", &"grav_pulse":
			canvas.draw_arc(c, 10.0, 0.0, TAU, 20, fg, 1.8, true)
			canvas.draw_arc(c, 5.5, 0.0, TAU, 16, hi, 1.6, true)
			for gi: int in range(4):
				var ga: float = float(gi) * (PI * 0.5) + PI * 0.25
				var gd: Vector2 = Vector2.RIGHT.rotated(ga)
				canvas.draw_line(c + gd * 12.0, c + gd * 6.5, hi, 1.8, true)
		&"seismic_slam", &"spore_barrage":
			canvas.draw_circle(c, 4.0, hi)
			canvas.draw_arc(c, 8.5, 0.0, TAU, 18, fg, 2.0, true)
			for si: int in range(6):
				var sa: float = float(si) * (TAU / 6.0)
				canvas.draw_line(c + Vector2.RIGHT.rotated(sa) * 6.5, c + Vector2.RIGHT.rotated(sa) * 11.5, fg, 1.6, true)

		_:
			# Category-based crisp fallback icons for buildings, upgrades & generic abilities
			if icon_category == &"building":
				draw_building_icon(canvas, icon_id, c, fg, hi, dark)
			elif icon_category == &"upgrade":
				draw_upgrade_icon(canvas, c, fg, hi, dark)
			elif icon_category == &"ability":
				canvas.draw_circle(c, 7.5, Color(fg.r, fg.g, fg.b, 0.28))
				canvas.draw_arc(c, 9.0, 0.0, TAU, 18, fg, 1.8, true)
				canvas.draw_circle(c, 3.0, hi)
			else:
				canvas.draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), dark, true)
				canvas.draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), fg, false, 1.8)
				canvas.draw_circle(c, 3.0, hi)


static func draw_building_icon(canvas: CanvasItem, icon_id: StringName, c: Vector2, fg: Color, hi: Color, dark: Color) -> void:
	# Chamfered structure outline + semantic interior emblem based on building id
	var r: float = 10.0
	var ch: float = 3.0
	var poly: PackedVector2Array = PackedVector2Array([
		c + Vector2(-r + ch, -r), c + Vector2(r - ch, -r),
		c + Vector2(r, -r + ch), c + Vector2(r, r - ch),
		c + Vector2(r - ch, r), c + Vector2(-r + ch, r),
		c + Vector2(-r, r - ch), c + Vector2(-r, -r + ch),
	])
	poly_icon(canvas, poly, dark, fg, 1.7)
	var id_s: String = String(icon_id)
	if id_s.contains("sanctum_core"):
		canvas.draw_arc(c, 6.5, 0.0, TAU, 16, fg, 1.5, true)
		var sc_d: PackedVector2Array = PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
		poly_icon(canvas, sc_d, hi, fg, 1.2)
	elif id_s.contains("halo_spire"):
		canvas.draw_arc(c, 7.2, -1.2, 1.2, 10, hi, 1.6, true)
		canvas.draw_arc(c, 7.2, PI - 1.2, PI + 1.2, 10, hi, 1.6, true)
		var hs_d: PackedVector2Array = PackedVector2Array([c + Vector2(0, -5.5), c + Vector2(4, 0), c + Vector2(0, 5.5), c + Vector2(-4, 0)])
		poly_icon(canvas, hs_d, fg, hi, 1.2)
	elif id_s.contains("alabaster_kiln"):
		canvas.draw_rect(Rect2(c + Vector2(-6.5, -5), Vector2(4.5, 10)), fg, true)
		canvas.draw_rect(Rect2(c + Vector2(2.0, -5), Vector2(4.5, 10)), fg, true)
		canvas.draw_line(c + Vector2(-2, 0), c + Vector2(2, 0), hi, 2.4, true)
	elif id_s.contains("oracle_reliquary"):
		var rel: PackedVector2Array = PackedVector2Array([c + Vector2(0, -7), c + Vector2(6.5, 5), c + Vector2(-6.5, 5)])
		poly_icon(canvas, rel, Color(fg.r, fg.g, fg.b, 0.28), hi, 1.5)
		canvas.draw_circle(c + Vector2(0, 1), 2.2, hi)
	elif id_s.contains("choir_basilica"):
		canvas.draw_arc(c, 5.5, 0.0, TAU, 14, hi, 1.5, true)
		canvas.draw_line(c + Vector2(-7, -5), c + Vector2(-7, 5), fg, 2.2, true)
		canvas.draw_line(c + Vector2(7, -5), c + Vector2(7, 5), fg, 2.2, true)
		canvas.draw_circle(c, 2.2, fg)
	elif id_s.contains("refraction_cloister"):
		var cl_t: PackedVector2Array = PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 5), c + Vector2(-7, 5)])
		poly_icon(canvas, cl_t, dark, fg, 1.6)
		canvas.draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), hi, 1.6, true)
		canvas.draw_circle(c, 2.4, hi)
	elif id_s.contains("solar_obelisk"):
		canvas.draw_circle(c, 4.0, fg)
		canvas.draw_line(c + Vector2(0, -2), c + Vector2(9, -6), hi, 1.8, true)
		canvas.draw_line(c + Vector2(0, 2), c + Vector2(9, 6), hi, 1.8, true)
	elif id_s.contains("cathedral_foundry"):
		# Grand rose-window astrolabe flanked by twin gilded apse bars
		canvas.draw_line(c + Vector2(-7.5, -5.5), c + Vector2(-7.5, 5.5), fg, 2.2, true)
		canvas.draw_line(c + Vector2(7.5, -5.5), c + Vector2(7.5, 5.5), fg, 2.2, true)
		canvas.draw_arc(c, 5.2, 0.0, TAU, 16, hi, 1.6, true)
		var cf_d: PackedVector2Array = PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)])
		poly_icon(canvas, cf_d, fg, hi, 1.1)
	elif id_s.contains("pylon"):
		canvas.draw_line(c + Vector2(0, -6), c + Vector2(0, 6), hi, 2.2, true)
		canvas.draw_circle(c, 3.5, fg)
	elif id_s.contains("silica") or id_s.contains("condenser") or id_s.contains("smelter"):
		canvas.draw_rect(Rect2(c + Vector2(-6, -5), Vector2(4.5, 10)), fg, true)
		canvas.draw_rect(Rect2(c + Vector2(1.5, -5), Vector2(4.5, 10)), hi, true)
	elif id_s.contains("mainframe") or id_s.contains("monolith"):
		canvas.draw_line(c + Vector2(-5, -5), c + Vector2(-5, 5), hi, 2.0)
		canvas.draw_line(c + Vector2(0, -5), c + Vector2(0, 5), fg, 2.0)
		canvas.draw_line(c + Vector2(5, -5), c + Vector2(5, 5), hi, 2.0)
	elif id_s.contains("turret") or id_s.contains("bastion"):
		canvas.draw_circle(c, 4.5, fg)
		canvas.draw_line(c, c + Vector2(9, -6), hi, 2.6, true)
	elif id_s.contains("nexus") or id_s.contains("foundry_core"):
		canvas.draw_rect(Rect2(c - Vector2(4.5, 4.5), Vector2(9, 9)), fg, true)
		canvas.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), hi, true)
	elif id_s.contains("fabricator") or id_s.contains("siege_gantry"):
		canvas.draw_line(c + Vector2(-7, -4), c + Vector2(7, -4), hi, 2.2)
		canvas.draw_line(c + Vector2(-7, 4), c + Vector2(7, 4), hi, 2.2)
		canvas.draw_circle(c, 3.2, fg)
	elif id_s.contains("foundry") or id_s.contains("ballistics"):
		canvas.draw_line(c + Vector2(-6, 0), c + Vector2(6, 0), fg, 2.2)
		canvas.draw_line(c + Vector2(0, -6), c + Vector2(0, 6), hi, 1.8)
		canvas.draw_circle(c, 2.4, hi)
	else:
		canvas.draw_rect(Rect2(c + Vector2(-6, -5), Vector2(12, 10)), Color(fg.r, fg.g, fg.b, 0.35), true)
		canvas.draw_line(c + Vector2(-6, 0), c + Vector2(6, 0), hi, 2.0)


static func draw_upgrade_icon(canvas: CanvasItem, c: Vector2, fg: Color, hi: Color, dark: Color) -> void:
	# Tech upgrade badge: square frame + double upward chevrons
	canvas.draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), dark, true)
	canvas.draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), fg, false, 1.5)
	canvas.draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(0, -6), c + Vector2(6, 0)]), hi, 2.0, true)
	canvas.draw_polyline(PackedVector2Array([c + Vector2(-6, 5.5), c + Vector2(0, -0.5), c + Vector2(6, 5.5)]), fg, 2.0, true)
