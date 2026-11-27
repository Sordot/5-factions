class_name MonolithVisualRenderer
extends FactionVisualRenderer

## Faction #2 (MONOLITH_OS — The Iron Axiom) Neo-Brutalist Halftone procedural renderer.

const MONO_INK: Color = Color(0.04, 0.05, 0.07, 0.96)
const MONO_SHADOW: Color = Color(0.04, 0.05, 0.07, 0.85)
const MONO_CONCRETE_DARK: Color = Color(0.169, 0.180, 0.200, 0.98) # #2B2E33
const MONO_CONCRETE_MID: Color = Color(0.227, 0.243, 0.271, 0.98)  # #3A3E45
const MONO_OFFWHITE: Color = Color(0.949, 0.937, 0.914, 0.98)      # #F2EFE9
const MONO_AMBER: Color = Color(1.0, 0.624, 0.110, 1.0)            # #FF9F1C
const MONO_SHIELD_CYAN: Color = Color(0.220, 0.741, 0.973, 1.0)    # #38BDF8

const UNIT_IDS: Dictionary = {
	&"servo_drone": true,
	&"ore_crawler": true,
	&"grid_tech": true,
	&"bulwark_automaton": true,
	&"picket_drone": true,
	&"rail_sentinel": true,
	&"aegis_relay": true,
	&"anvil_siege_walker": true,
	&"monolith_dreadnought": true,
	&"null_grid_projector": true,
}

const COMBAT_UNIT_IDS: Dictionary = {
	&"bulwark_automaton": true,
	&"picket_drone": true,
	&"rail_sentinel": true,
	&"aegis_relay": true,
	&"anvil_siege_walker": true,
	&"monolith_dreadnought": true,
	&"null_grid_projector": true,
}

const BUILDING_IDS: Dictionary = {
	&"foundry_core": true,
	&"capacitor_pylon": true,
	&"silica_smelter": true,
	&"logic_monolith": true,
	&"assembly_bay": true,
	&"ballistics_lab": true,
	&"bastion_emplacement": true,
	&"siege_gantry": true,
}

const ANIMATED_UNITS: Dictionary = {
	&"aegis_relay": true,
	&"monolith_dreadnought": true,
	&"null_grid_projector": true,
	&"anvil_siege_walker": true,
}


func handles_unit(type_id: StringName) -> bool:
	return UNIT_IDS.has(type_id)


func handles_building(type_id: StringName) -> bool:
	return BUILDING_IDS.has(type_id)


func needs_unit_animation(type_id: StringName, ctx: Dictionary) -> bool:
	if ANIMATED_UNITS.has(type_id):
		return true
	return COMBAT_UNIT_IDS.has(type_id) and ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_RAPID_CAPACITORS)


func is_mechanical_damage_style(_type_id: StringName, _is_building: bool) -> bool:
	return true


func get_completion_flash_color(_type_id: StringName) -> Color:
	return Color(1.0, 0.72, 0.22, 1.0)


func get_building_outer_poly(_type_id: StringName, radius: float) -> PackedVector2Array:
	var r: float = maxf(22.0, radius)
	var e_m: float = r * 0.96
	var ch_m: float = r * 0.24
	return PackedVector2Array([
		Vector2(-e_m + ch_m, -e_m), Vector2(e_m - ch_m, -e_m),
		Vector2(e_m, -e_m + ch_m), Vector2(e_m, e_m - ch_m),
		Vector2(e_m - ch_m, e_m), Vector2(-e_m + ch_m, e_m),
		Vector2(-e_m, e_m - ch_m), Vector2(-e_m, -e_m + ch_m),
	])


static func draw_brutalist_slab(
	canvas: CanvasItem,
	rect: Rect2,
	fill_col: Color,
	outline_col: Color,
	shadow_offset: Vector2 = Vector2(3.0, 3.0),
	chamfer: float = 5.0,
	trim_col: Color = MONO_OFFWHITE
) -> void:
	var poly: PackedVector2Array = build_chamfer_rect_poly(rect, chamfer)
	if shadow_offset.length_squared() > 0.01:
		var shadow_poly: PackedVector2Array = PackedVector2Array()
		shadow_poly.resize(poly.size())
		for i: int in range(poly.size()):
			shadow_poly[i] = poly[i] + shadow_offset
		canvas.draw_colored_polygon(shadow_poly, MONO_SHADOW)
	canvas.draw_colored_polygon(poly, fill_col)
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	canvas.draw_polyline(closed, outline_col, 2.2, true)
	var inset: float = 2.2
	var c_in: float = maxf(1.5, chamfer - 1.2)
	if rect.size.x > 10.0 and rect.size.y > 10.0:
		canvas.draw_line(
			Vector2(rect.position.x + c_in + inset, rect.position.y + inset),
			Vector2(rect.end.x - c_in - inset, rect.position.y + inset),
			Color(trim_col.r, trim_col.g, trim_col.b, 0.85),
			1.4,
			true
		)


static func draw_halftone_dots(
	canvas: CanvasItem,
	bounds: Rect2,
	spacing: float,
	dot_radius: float,
	col: Color,
	clip_inset: float = 4.0
) -> void:
	var step: float = maxf(4.0, spacing)
	var inner: Rect2 = bounds.grow(-clip_inset)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var row_idx: int = 0
	var y: float = inner.position.y
	while y <= inner.end.y:
		var x_offset: float = (step * 0.5) if (row_idx % 2 == 1) else 0.0
		var x: float = inner.position.x + x_offset
		while x <= inner.end.x:
			canvas.draw_circle(Vector2(x, y), dot_radius, col)
			x += step
		y += step
		row_idx += 1


static func draw_team_corner_brackets(
	canvas: CanvasItem,
	rect: Rect2,
	team_col: Color,
	arm: float = 7.0,
	width: float = 2.2
) -> void:
	var tl: Vector2 = rect.position
	var tr: Vector2 = Vector2(rect.end.x, rect.position.y)
	var br: Vector2 = rect.end
	var bl: Vector2 = Vector2(rect.position.x, rect.end.y)
	canvas.draw_line(tl, tl + Vector2(arm, 0.0), team_col, width, true)
	canvas.draw_line(tl, tl + Vector2(0.0, arm), team_col, width, true)
	canvas.draw_line(tr, tr + Vector2(-arm, 0.0), team_col, width, true)
	canvas.draw_line(tr, tr + Vector2(0.0, arm), team_col, width, true)
	canvas.draw_line(br, br + Vector2(-arm, 0.0), team_col, width, true)
	canvas.draw_line(br, br + Vector2(0.0, -arm), team_col, width, true)
	canvas.draw_line(bl, bl + Vector2(arm, 0.0), team_col, width, true)
	canvas.draw_line(bl, bl + Vector2(0.0, -arm), team_col, width, true)


func draw_unit(canvas: CanvasItem, type_id: StringName, unit: Unit, ctx: Dictionary) -> void:
	var team_col: Color = ctx["team_color"] as Color
	var anim_time: float = float(ctx["anim_time"])
	var pulse: float = float(ctx["pulse"])
	var slab_base: Color = MONO_CONCRETE_MID.lerp(team_col, 0.14)
	var slab_dark: Color = MONO_CONCRETE_DARK.lerp(team_col, 0.10)

	match type_id:
		&"servo_drone":
			draw_brutalist_slab(canvas, Rect2(-11, -9, 21, 18), slab_base, MONO_INK, Vector2(2.2, 2.2), 3.5, MONO_OFFWHITE)
			canvas.draw_rect(Rect2(9, -7.5, 7.5, 3.2), MONO_INK, true)
			canvas.draw_rect(Rect2(9, 4.3, 7.5, 3.2), MONO_INK, true)
			canvas.draw_line(Vector2(10, -5.9), Vector2(16, -5.9), MONO_OFFWHITE, 1.5, true)
			canvas.draw_line(Vector2(10, 5.9), Vector2(16, 5.9), MONO_OFFWHITE, 1.5, true)
			draw_halftone_dots(canvas, Rect2(-10, -7, 10, 14), 5.0, 1.2, Color(0.04, 0.05, 0.07, 0.55), 2.5)
			canvas.draw_rect(Rect2(-9, -6, 3.5, 12), team_col, true)
			canvas.draw_rect(Rect2(3, -3.5, 4.2, 7.0), MONO_AMBER, true)

		&"ore_crawler":
			canvas.draw_rect(Rect2(-15, -14.5, 28, 4.5), MONO_INK, true)
			canvas.draw_rect(Rect2(-15, 10.0, 28, 4.5), MONO_INK, true)
			draw_brutalist_slab(canvas, Rect2(-15, -11.5, 29, 23), slab_base, MONO_INK, Vector2(2.5, 2.5), 4.0, MONO_AMBER)
			var jaw: PackedVector2Array = PackedVector2Array([
				Vector2(12, -12), Vector2(20, -9), Vector2(20, 9), Vector2(12, 12),
				Vector2(15, 6), Vector2(15, -6),
			])
			poly_outlined(canvas, jaw, MONO_OFFWHITE, MONO_INK, 2.0)
			canvas.draw_rect(Rect2(-10, -7, 15, 14), slab_dark, true)
			canvas.draw_rect(Rect2(-8, -4.5, 9, 9), MONO_AMBER, true)
			canvas.draw_rect(Rect2(-13.5, -9, 3.0, 18), team_col, true)
			draw_halftone_dots(canvas, Rect2(-9, -7, 12, 14), 6.0, 1.2, Color(0.04, 0.05, 0.07, 0.48), 2.0)

		&"grid_tech":
			draw_brutalist_slab(canvas, Rect2(-12, -10.5, 23, 21), MONO_OFFWHITE.lerp(slab_base, 0.35), MONO_INK, Vector2(2.2, 2.2), 4.0, MONO_AMBER)
			canvas.draw_line(Vector2(9, -5.5), Vector2(16.5, -6.5), MONO_INK, 3.6, true)
			canvas.draw_line(Vector2(9, 5.5), Vector2(16.5, 6.5), MONO_INK, 3.6, true)
			canvas.draw_line(Vector2(9, -5.5), Vector2(16, -6.2), MONO_SHIELD_CYAN, 1.5, true)
			canvas.draw_line(Vector2(9, 5.5), Vector2(16, 6.2), MONO_SHIELD_CYAN, 1.5, true)
			canvas.draw_rect(Rect2(-7, -6.5, 13, 13), slab_dark, true)
			canvas.draw_rect(Rect2(-3, -3.5, 7, 7), MONO_SHIELD_CYAN, true)
			canvas.draw_rect(Rect2(-10.5, -7.5, 3.2, 15), team_col, true)
			draw_halftone_dots(canvas, Rect2(-7, -6, 12, 12), 5.5, 1.1, Color(0.95, 0.94, 0.91, 0.32), 2.0)

		&"bulwark_automaton":
			canvas.draw_rect(Rect2(6, -16.5, 15, 5.2), MONO_INK, true)
			canvas.draw_rect(Rect2(6, 11.3, 15, 5.2), MONO_INK, true)
			canvas.draw_line(Vector2(8, -13.9), Vector2(20, -13.9), MONO_OFFWHITE, 1.8, true)
			canvas.draw_line(Vector2(8, 13.9), Vector2(20, 13.9), MONO_OFFWHITE, 1.8, true)
			draw_brutalist_slab(canvas, Rect2(-16, -15, 29, 30), slab_base, MONO_INK, Vector2(3.2, 3.2), 5.0, MONO_OFFWHITE)
			draw_brutalist_slab(canvas, Rect2(8, -13, 8, 26), MONO_OFFWHITE.lerp(team_col, 0.12), MONO_INK, Vector2(1.5, 1.5), 2.5, MONO_AMBER)
			draw_halftone_dots(canvas, Rect2(-14, -12, 16, 24), 7.0, 1.4, Color(0.04, 0.05, 0.07, 0.55), 3.0)
			canvas.draw_rect(Rect2(-12, -13, 16, 4.2), team_col, true)
			canvas.draw_rect(Rect2(-12, 8.8, 16, 4.2), team_col, true)
			canvas.draw_rect(Rect2(10.5, -5.5, 3.2, 11.0), MONO_AMBER, true)
			canvas.draw_rect(Rect2(-4, -5, 8, 10), slab_dark, true)
			canvas.draw_rect(Rect2(-2, -3, 4, 6), MONO_SHIELD_CYAN, true)

		&"picket_drone":
			var drop_pts: PackedVector2Array = PackedVector2Array([
				Vector2(17, 0), Vector2(5, -11), Vector2(-11, -11),
				Vector2(-14, -5), Vector2(-14, 5), Vector2(-11, 11), Vector2(5, 11),
			])
			var sh_pts: PackedVector2Array = PackedVector2Array()
			for pt_p: Vector2 in drop_pts:
				sh_pts.append(pt_p + Vector2(2.4, 2.4))
			canvas.draw_colored_polygon(sh_pts, MONO_SHADOW)
			poly_outlined(canvas, drop_pts, slab_base, MONO_INK, 2.2)
			canvas.draw_line(Vector2(10, -5.5), Vector2(20, -3.5), MONO_INK, 3.4, true)
			canvas.draw_line(Vector2(10, 5.5), Vector2(20, 3.5), MONO_INK, 3.4, true)
			canvas.draw_line(Vector2(11, -5.2), Vector2(19.5, -3.5), MONO_OFFWHITE, 1.4, true)
			canvas.draw_line(Vector2(11, 5.2), Vector2(19.5, 3.5), MONO_OFFWHITE, 1.4, true)
			canvas.draw_rect(Rect2(-9, -4, 16, 8), slab_dark, true)
			canvas.draw_rect(Rect2(-3, -2.5, 9, 5), MONO_SHIELD_CYAN, true)
			canvas.draw_line(Vector2(-9, -8.5), Vector2(4, -8.5), team_col, 3.0, true)
			canvas.draw_line(Vector2(-9, 8.5), Vector2(4, 8.5), team_col, 3.0, true)
			draw_halftone_dots(canvas, Rect2(-12, -8, 10, 16), 5.5, 1.1, Color(0.95, 0.94, 0.91, 0.35), 2.0)

		&"rail_sentinel":
			canvas.draw_rect(Rect2(-18, -18, 28, 6), MONO_INK, true)
			canvas.draw_rect(Rect2(-18, 12, 28, 6), MONO_INK, true)
			canvas.draw_line(Vector2(-15, -15), Vector2(7, -15), team_col, 2.6, true)
			canvas.draw_line(Vector2(-15, 15), Vector2(7, 15), team_col, 2.6, true)
			draw_brutalist_slab(canvas, Rect2(-17, -13, 29, 26), MONO_OFFWHITE.lerp(slab_base, 0.30), MONO_INK, Vector2(3.2, 3.2), 4.5, MONO_AMBER)
			canvas.draw_rect(Rect2(6, -6.2, 24, 4.0), MONO_INK, true)
			canvas.draw_rect(Rect2(6, 2.2, 24, 4.0), MONO_INK, true)
			canvas.draw_line(Vector2(8, -4.2), Vector2(28, -4.2), MONO_OFFWHITE, 1.6, true)
			canvas.draw_line(Vector2(8, 4.2), Vector2(28, 4.2), MONO_OFFWHITE, 1.6, true)
			canvas.draw_line(Vector2(5, 0.0), Vector2(29, 0.0), MONO_AMBER, 2.8, true)
			canvas.draw_rect(Rect2(-14, -9, 14, 18), slab_dark, true)
			draw_halftone_dots(canvas, Rect2(-13, -8, 12, 16), 5.5, 1.2, Color(0.95, 0.94, 0.91, 0.40), 2.0)
			canvas.draw_rect(Rect2(-1, -5, 7, 10), MONO_AMBER, true)

		&"aegis_relay":
			var hover_off: Vector2 = Vector2(3.8, 4.2)
			var outer_d: PackedVector2Array = PackedVector2Array([
				Vector2(15, 0), Vector2(8, -12), Vector2(-8, -12),
				Vector2(-15, 0), Vector2(-8, 12), Vector2(8, 12),
			])
			var sh_d: PackedVector2Array = PackedVector2Array()
			for pt_a: Vector2 in outer_d:
				sh_d.append(pt_a + hover_off)
			canvas.draw_colored_polygon(sh_d, Color(0.04, 0.05, 0.07, 0.65))
			canvas.draw_arc(Vector2.ZERO, 15.0 + pulse * 1.8, 0.0, TAU, 24, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.40 + pulse * 0.28), 1.6, true)
			poly_outlined(canvas, outer_d, MONO_OFFWHITE.lerp(slab_base, 0.25), MONO_INK, 2.2)
			var inner_d: PackedVector2Array = PackedVector2Array([
				Vector2(9, 0), Vector2(0, -8), Vector2(-9, 0), Vector2(0, 8),
			])
			poly_outlined(canvas, inner_d, slab_dark, team_col, 1.8)
			canvas.draw_circle(Vector2.ZERO, 4.2 + pulse * 0.9, MONO_SHIELD_CYAN)
			canvas.draw_circle(Vector2.ZERO, 2.0, MONO_OFFWHITE)
			canvas.draw_line(Vector2(-7, -11), Vector2(7, -11), team_col, 2.6, true)
			canvas.draw_line(Vector2(-7, 11), Vector2(7, 11), team_col, 2.6, true)

		&"anvil_siege_walker":
			var dep_prog: float = unit.get_deploy_progress() if unit != null else 0.0
			var leg_spread: float = lerpf(16.0, 25.5, dep_prog)
			var leg_w: float = lerpf(4.4, 5.6, dep_prog)
			for li: int in range(4):
				var base_a: float = PI * 0.25 + float(li) * (PI * 0.5)
				var l_dir: Vector2 = Vector2.RIGHT.rotated(base_a)
				var knee: Vector2 = l_dir * lerpf(11.0, 15.5, dep_prog)
				var foot: Vector2 = l_dir * leg_spread
				canvas.draw_line(Vector2.ZERO, knee, MONO_INK, leg_w + 1.8, true)
				canvas.draw_line(knee, foot, MONO_INK, leg_w, true)
				canvas.draw_line(Vector2.ZERO, foot, MONO_OFFWHITE.lerp(slab_base, 0.35), 2.2, true)
				var pad_sz: float = lerpf(3.0, 4.6, dep_prog)
				canvas.draw_rect(Rect2(foot - Vector2(pad_sz, pad_sz), Vector2(pad_sz * 2.0, pad_sz * 2.0)), MONO_INK, true)
				canvas.draw_rect(Rect2(foot - Vector2(pad_sz * 0.65, pad_sz * 0.65), Vector2(pad_sz * 1.3, pad_sz * 1.3)), MONO_AMBER if dep_prog > 0.5 else team_col, true)
			draw_brutalist_slab(canvas, Rect2(-18, -15, 34, 30), slab_base, MONO_INK, Vector2(3.4, 3.4), 6.0, MONO_OFFWHITE)
			draw_halftone_dots(canvas, Rect2(-16, -12, 16, 24), 6.5, 1.4, Color(0.04, 0.05, 0.07, 0.52), 2.5)
			canvas.draw_rect(Rect2(-14, -13.5, 22, 3.8), team_col, true)
			canvas.draw_rect(Rect2(-14, 9.7, 22, 3.8), team_col, true)
			draw_brutalist_slab(canvas, Rect2(-10, -9, 20, 18), MONO_OFFWHITE.lerp(slab_base, 0.26), MONO_INK, Vector2(1.8, 1.8), 3.5, MONO_AMBER)
			var barrel_len: float = lerpf(23.0, 35.0, dep_prog)
			var barrel_thick: float = lerpf(6.5, 10.5, dep_prog)
			canvas.draw_rect(Rect2(6.0, -barrel_thick * 0.5, barrel_len - 4.0, barrel_thick), MONO_INK, true)
			canvas.draw_line(Vector2(7.0, 0.0), Vector2(barrel_len + 1.0, 0.0), MONO_OFFWHITE, barrel_thick * 0.50, true)
			canvas.draw_line(Vector2(6.0, 0.0), Vector2(barrel_len - 2.0, 0.0), MONO_AMBER if dep_prog > 0.5 else MONO_SHIELD_CYAN, 2.2, true)
			canvas.draw_rect(Rect2(barrel_len - 5.0, -barrel_thick * 0.68, 5.0, barrel_thick * 1.36), MONO_AMBER, true)
			canvas.draw_rect(Rect2(barrel_len - 5.0, -barrel_thick * 0.68, 5.0, barrel_thick * 1.36), MONO_INK, false, 1.5)
			var lock_col: Color = Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.78 + pulse * 0.22) if dep_prog > 0.5 else MONO_SHIELD_CYAN
			canvas.draw_rect(Rect2(-5.5, -4.5, 9.0, 9.0), slab_dark, true)
			canvas.draw_rect(Rect2(-3.5, -2.5, 5.0, 5.0), lock_col, true)

		&"monolith_dreadnought":
			var barrier_amt: float = unit.get_shield_amount() if unit != null else 0.0
			canvas.draw_rect(Rect2(4, -22.5, 22, 7.5), MONO_INK, true)
			canvas.draw_rect(Rect2(4, 15.0, 22, 7.5), MONO_INK, true)
			canvas.draw_line(Vector2(7, -18.8), Vector2(25, -18.8), MONO_OFFWHITE, 2.6, true)
			canvas.draw_line(Vector2(7, 18.8), Vector2(25, 18.8), MONO_OFFWHITE, 2.6, true)
			canvas.draw_line(Vector2(21, -22.5), Vector2(21, -15.0), MONO_AMBER, 2.2, true)
			canvas.draw_line(Vector2(21, 15.0), Vector2(21, 22.5), MONO_AMBER, 2.2, true)
			draw_brutalist_slab(canvas, Rect2(-22, -20, 40, 40), slab_base, MONO_INK, Vector2(4.2, 4.2), 7.0, MONO_OFFWHITE)
			draw_brutalist_slab(canvas, Rect2(-15, -15, 28, 30), MONO_OFFWHITE.lerp(slab_base, 0.30), MONO_INK, Vector2(2.0, 2.0), 4.5, MONO_AMBER)
			draw_brutalist_slab(canvas, Rect2(10, -16, 10, 32), MONO_OFFWHITE.lerp(team_col, 0.14), MONO_INK, Vector2(1.8, 1.8), 3.0, MONO_AMBER)
			draw_halftone_dots(canvas, Rect2(-20, -15, 14, 30), 6.5, 1.5, Color(0.04, 0.05, 0.07, 0.56), 2.5)
			canvas.draw_rect(Rect2(-18, -18.5, 24, 5.2), team_col, true)
			canvas.draw_rect(Rect2(-18, 13.3, 24, 5.2), team_col, true)
			canvas.draw_rect(Rect2(-6, -7.5, 12, 15), slab_dark, true)
			canvas.draw_rect(Rect2(-3.5, -5.0, 7, 10), MONO_SHIELD_CYAN, true)
			canvas.draw_rect(Rect2(13, -7.0, 3.8, 14.0), MONO_AMBER, true)
			if barrier_amt > 0.0:
				var hex_r: float = 28.5 + pulse * 2.2
				var hex_pts: PackedVector2Array = PackedVector2Array()
				for hi: int in range(6):
					var ha: float = float(hi) * (TAU / 6.0) + anim_time * 0.45
					hex_pts.append(Vector2.RIGHT.rotated(ha) * hex_r)
				canvas.draw_colored_polygon(hex_pts, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.14 + pulse * 0.08))
				draw_closed_outline(canvas, hex_pts, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.85 + pulse * 0.15), 2.4)
				for hi2: int in range(6):
					canvas.draw_circle(hex_pts[hi2], 2.2, MONO_AMBER)

		&"null_grid_projector":
			var grav_violet: Color = Color(0.74, 0.40, 1.0, 1.0)
			draw_brutalist_slab(canvas, Rect2(-18, -16, 20, 9), slab_dark, MONO_INK, Vector2(2.4, 2.4), 3.0, team_col)
			draw_brutalist_slab(canvas, Rect2(-18, 7, 20, 9), slab_dark, MONO_INK, Vector2(2.4, 2.4), 3.0, team_col)
			draw_brutalist_slab(canvas, Rect2(-14, -12, 26, 24), slab_base, MONO_INK, Vector2(3.0, 3.0), 5.0, MONO_OFFWHITE)
			draw_halftone_dots(canvas, Rect2(-12, -10, 14, 20), 6.0, 1.3, Color(0.04, 0.05, 0.07, 0.50), 2.5)
			var dish: PackedVector2Array = PackedVector2Array([
				Vector2(6, -15), Vector2(18, -11), Vector2(15, -5),
				Vector2(15, 5), Vector2(18, 11), Vector2(6, 15),
				Vector2(2, 9), Vector2(2, -9),
			])
			poly_outlined(canvas, dish, MONO_OFFWHITE.lerp(slab_base, 0.22), MONO_INK, 2.2)
			canvas.draw_line(Vector2(-14, -11), Vector2(2, -11), team_col, 2.8, true)
			canvas.draw_line(Vector2(-14, 11), Vector2(2, 11), team_col, 2.8, true)
			var rot_a: float = anim_time * 2.6
			var core_pts: PackedVector2Array = PackedVector2Array()
			for ci: int in range(4):
				var ca: float = rot_a + float(ci) * (PI * 0.5)
				core_pts.append(Vector2(6.0, 0.0) + Vector2.RIGHT.rotated(ca) * (6.2 + pulse * 0.9))
			canvas.draw_arc(Vector2(6.0, 0.0), 10.5 + pulse * 1.4, rot_a, rot_a + PI * 1.15, 16, Color(grav_violet.r, grav_violet.g, grav_violet.b, 0.80), 1.8, true)
			canvas.draw_arc(Vector2(6.0, 0.0), 10.5 + pulse * 1.4, rot_a + PI, rot_a + PI * 1.65, 12, Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.85), 1.8, true)
			poly_outlined(canvas, core_pts, grav_violet, MONO_AMBER, 1.6)
			canvas.draw_circle(Vector2(6.0, 0.0), 2.4, MONO_OFFWHITE)


func draw_unit_upgrade_telltales(canvas: CanvasItem, type_id: StringName, unit: Unit, ctx: Dictionary) -> void:
	var anim_time: float = float(ctx["anim_time"])
	var pulse: float = float(ctx["pulse"])
	var is_mono_combat: bool = COMBAT_UNIT_IDS.has(type_id)

	# 1. Hardened Plating: stark off-white reinforced front-slab armor brackets
	if is_mono_combat and ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_HARDENED_PLATING):
		var r: float = clampf(unit.data.collision_radius if (unit != null and unit.data != null) else 16.0, 12.0, 26.0)
		var fx: float = r * 0.72
		var sy: float = r * 0.68
		var back_x: float = r * 0.12
		canvas.draw_polyline(PackedVector2Array([Vector2(back_x, -sy - 2.0), Vector2(fx, -sy * 0.72), Vector2(fx + 2.5, -sy * 0.28)]), MONO_OFFWHITE, 2.8, true)
		canvas.draw_polyline(PackedVector2Array([Vector2(back_x, sy + 2.0), Vector2(fx, sy * 0.72), Vector2(fx + 2.5, sy * 0.28)]), MONO_OFFWHITE, 2.8, true)
		canvas.draw_line(Vector2(fx - 2.0, -sy * 0.78), Vector2(fx - 2.0, -sy * 0.56), MONO_INK, 1.6)
		canvas.draw_line(Vector2(fx - 2.0, sy * 0.56), Vector2(fx - 2.0, sy * 0.78), MONO_INK, 1.6)

	# 2. Rapid Capacitors: twin bright Shield-Cyan dorsal pips + shimmering outer energy arc
	if is_mono_combat and ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_RAPID_CAPACITORS):
		var rc: float = clampf(unit.data.collision_radius if (unit != null and unit.data != null) else 16.0, 12.0, 26.0)
		canvas.draw_circle(Vector2(-rc * 0.28, -rc * 0.42), 2.3, MONO_SHIELD_CYAN)
		canvas.draw_circle(Vector2(-rc * 0.28, rc * 0.42), 2.3, MONO_SHIELD_CYAN)
		var arc_a: float = anim_time * 1.9
		var arc_col: Color = Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.42 + pulse * 0.30)
		canvas.draw_arc(Vector2.ZERO, rc * 0.92, arc_a, arc_a + PI * 0.65, 12, arc_col, 1.5, true)
		canvas.draw_arc(Vector2.ZERO, rc * 0.92, arc_a + PI, arc_a + PI * 1.65, 12, arc_col, 1.5, true)

	# 3. Hyper-Velocity Rails: glowing Hazard Amber induction coils + off-white muzzle highlight
	if ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_HYPER_VELOCITY_RAILS):
		if type_id == &"rail_sentinel":
			canvas.draw_line(Vector2(11.0, -4.5), Vector2(11.0, 4.5), MONO_AMBER, 2.2, true)
			canvas.draw_line(Vector2(17.5, -4.0), Vector2(17.5, 4.0), MONO_AMBER, 2.2, true)
			canvas.draw_circle(Vector2(23.5, 0.0), 2.3, MONO_OFFWHITE)
		elif type_id == &"anvil_siege_walker":
			canvas.draw_line(Vector2(14.0, -6.5), Vector2(14.0, 6.5), MONO_AMBER, 2.6, true)
			canvas.draw_line(Vector2(21.0, -5.8), Vector2(21.0, 5.8), MONO_AMBER, 2.6, true)
			canvas.draw_circle(Vector2(27.5, 0.0), 2.8, MONO_OFFWHITE)


func draw_building(
	canvas: CanvasItem,
	type_id: StringName,
	building: Building,
	hull_poly: PackedVector2Array,
	ctx: Dictionary
) -> void:
	var team_col: Color = ctx["team_color"] as Color
	var anim_time: float = float(ctx["anim_time"])
	var pulse: float = float(ctx["pulse"])
	var active_pulse: float = float(ctx["active_pulse"])
	var slab_base: Color = MONO_CONCRETE_MID.lerp(team_col, 0.10)
	var slab_dark: Color = MONO_CONCRETE_DARK.lerp(team_col, 0.08)
	var has_b: bool = building != null and is_instance_valid(building)
	var is_training: bool = building.get_training_queue_size() > 0 if has_b else false
	var is_active_prod: bool = building.is_actively_producing() if has_b else false
	var r: float = maxf(24.0, building.footprint_radius if has_b else float(ctx.get("footprint_radius", 34.0)))
	var half: float = r * 0.94

	# Subtle brutalist concrete foundation pad
	if SettingsManager == null or SettingsManager.battle_scars_enabled:
		var pad_poly: PackedVector2Array = scale_poly(hull_poly, 1.12)
		canvas.draw_colored_polygon(pad_poly, Color(0.04, 0.05, 0.07, 0.45))
		draw_closed_outline(canvas, pad_poly, Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.22), 1.2)

	match type_id:
		&"foundry_core":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(4.5, 4.5), 10.0, MONO_OFFWHITE)
			draw_halftone_dots(canvas, Rect2(-half + 6, 4, half * 2.0 - 12, half - 10), 8.5, 1.5, Color(0.04, 0.05, 0.07, 0.48), 3.0)
			for b_pos: Vector2 in [Vector2(-38, -38), Vector2(22, -38), Vector2(22, 22), Vector2(-38, 22)]:
				draw_brutalist_slab(canvas, Rect2(b_pos, Vector2(16, 16)), slab_dark, MONO_INK, Vector2(1.5, 1.5), 3.0, team_col)
			draw_brutalist_slab(canvas, Rect2(-22, -22, 44, 44), MONO_OFFWHITE.lerp(slab_base, 0.22), MONO_INK, Vector2(2.5, 2.5), 6.0, MONO_AMBER)
			canvas.draw_rect(Rect2(-13, -13, 26, 26), slab_dark, true)
			canvas.draw_rect(Rect2(-8, -8, 16, 16), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.80 + pulse * 0.20), true)
			canvas.draw_rect(Rect2(-4, -4, 8, 8), MONO_OFFWHITE, true)
			canvas.draw_line(Vector2(-36, 0), Vector2(-22, 0), MONO_AMBER, 3.0)
			canvas.draw_line(Vector2(22, 0), Vector2(36, 0), MONO_AMBER, 3.0)
			canvas.draw_line(Vector2(0, -36), Vector2(0, -22), MONO_AMBER, 3.0)
			canvas.draw_line(Vector2(0, 22), Vector2(0, 36), MONO_AMBER, 3.0)
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 11.0, 2.6)
			if is_training:
				canvas.draw_arc(Vector2.ZERO, 26.0, anim_time * 2.4, anim_time * 2.4 + PI * 1.15, 20, MONO_AMBER, 2.5, true)

		&"capacitor_pylon":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(3.5, 3.5), 7.0, MONO_OFFWHITE)
			draw_halftone_dots(canvas, Rect2(-half + 4, 2, half * 2.0 - 8, half - 6), 7.5, 1.3, Color(0.04, 0.05, 0.07, 0.45), 2.5)
			canvas.draw_rect(Rect2(-16, -15, 7, 30), slab_dark, true)
			canvas.draw_rect(Rect2(9, -15, 7, 30), slab_dark, true)
			canvas.draw_rect(Rect2(-14, -12, 3, 24), MONO_SHIELD_CYAN, true)
			canvas.draw_rect(Rect2(11, -12, 3, 24), MONO_SHIELD_CYAN, true)
			draw_brutalist_slab(canvas, Rect2(-8, -11, 16, 22), MONO_OFFWHITE, MONO_INK, Vector2(1.5, 1.5), 3.0, MONO_AMBER)
			canvas.draw_circle(Vector2.ZERO, 4.5 + pulse * 1.2, MONO_SHIELD_CYAN)
			canvas.draw_arc(Vector2.ZERO, 17.5, 0.0, TAU, 24, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.30 + pulse * 0.25), 1.4, true)
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 8.0, 2.2)

		&"silica_smelter":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(4.0, 4.0), 8.0, MONO_AMBER)
			draw_halftone_dots(canvas, Rect2(-half + 5, 6, half * 2.0 - 10, half - 10), 8.0, 1.4, Color(0.04, 0.05, 0.07, 0.48), 3.0)
			draw_brutalist_slab(canvas, Rect2(-26, -22, 18, 36), slab_dark, MONO_INK, Vector2(1.8, 1.8), 3.0, MONO_OFFWHITE)
			draw_brutalist_slab(canvas, Rect2(8, -22, 18, 36), slab_dark, MONO_INK, Vector2(1.8, 1.8), 3.0, MONO_OFFWHITE)
			canvas.draw_rect(Rect2(-22, -16, 10, 24), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.72 + pulse * 0.24), true)
			canvas.draw_rect(Rect2(12, -16, 10, 24), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.58 + pulse * 0.32), true)
			canvas.draw_rect(Rect2(-5, -18, 10, 28), MONO_INK, true)
			canvas.draw_line(Vector2(0, -14), Vector2(0, 6), MONO_OFFWHITE, 3.0)
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 9.0, 2.4)

		&"logic_monolith":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			var staffed: int = building.get_assigned_engineer_count() if has_b else int(ctx.get("staffed_count", 0))
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(4.0, 4.0), 7.0, MONO_SHIELD_CYAN if is_active_prod else MONO_OFFWHITE)
			canvas.draw_rect(Rect2(-25, -26, 50, 38), slab_dark, true)
			var fin_col: Color = Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.65 + active_pulse * 0.35) if is_active_prod else Color(0.45, 0.50, 0.56, 0.45)
			for fx: float in [-18.0, -9.0, 0.0, 9.0, 18.0]:
				canvas.draw_line(Vector2(fx, -22), Vector2(fx, 8), fin_col, 2.2)
			draw_brutalist_slab(canvas, Rect2(-10, -15, 20, 16), MONO_OFFWHITE, MONO_INK, Vector2(1.2, 1.2), 2.5, MONO_AMBER)
			canvas.draw_rect(Rect2(-5, -11, 10, 8), MONO_SHIELD_CYAN if is_active_prod else Color(0.28, 0.32, 0.38, 0.9), true)
			if is_active_prod:
				draw_active_conduit_sparks(canvas, MONO_SHIELD_CYAN, 22.0, anim_time)
			var slots: int = maxi(1, building.max_staff_slots if has_b else int(ctx.get("max_staff_slots", 3)))
			var pip_span: float = 13.5
			for s: int in range(slots):
				var px: float = (float(s) - float(slots - 1) * 0.5) * pip_span
				var pip_rect: Rect2 = Rect2(px - 5.0, 17.0, 10.0, 6.5)
				var filled: bool = s < staffed
				canvas.draw_rect(pip_rect, MONO_AMBER if filled else Color(0.12, 0.14, 0.17, 0.96), true)
				canvas.draw_rect(pip_rect, MONO_OFFWHITE if filled else MONO_INK, false, 1.4)
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 9.0, 2.4)

		&"assembly_bay":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(4.2, 4.2), 8.0, MONO_AMBER if is_active_prod else MONO_OFFWHITE)
			canvas.draw_rect(Rect2(-26, -24, 52, 48), slab_dark, true)
			draw_halftone_dots(canvas, Rect2(-24, -22, 48, 44), 9.5, 1.4, Color(0.95, 0.94, 0.91, 0.24), 4.0)
			canvas.draw_rect(Rect2(-31, -28, 8, 56), MONO_OFFWHITE.lerp(slab_base, 0.35), true)
			canvas.draw_rect(Rect2(23, -28, 8, 56), MONO_OFFWHITE.lerp(slab_base, 0.35), true)
			canvas.draw_rect(Rect2(-31, -28, 8, 56), MONO_INK, false, 1.8)
			canvas.draw_rect(Rect2(23, -28, 8, 56), MONO_INK, false, 1.8)
			var bridge_y: float = sin(anim_time * 2.4) * 12.0 if is_active_prod else -2.0
			canvas.draw_rect(Rect2(-30, bridge_y - 4.5, 60, 9.0), MONO_OFFWHITE, true)
			canvas.draw_rect(Rect2(-30, bridge_y - 4.5, 60, 9.0), MONO_INK, false, 1.8)
			if is_active_prod:
				canvas.draw_rect(Rect2(-12, -13, 24, 26), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.68 + active_pulse * 0.28), true)
				canvas.draw_rect(Rect2(-12, -13, 24, 26), MONO_OFFWHITE, false, 1.6)
				canvas.draw_circle(Vector2(0.0, bridge_y), 3.8 + active_pulse * 1.4, MONO_AMBER)
				draw_active_conduit_sparks(canvas, MONO_AMBER, 24.0, anim_time)
			else:
				canvas.draw_rect(Rect2(-12, -13, 24, 26), Color(0.24, 0.27, 0.31, 0.75), true)
				canvas.draw_rect(Rect2(-12, -13, 24, 26), MONO_INK, false, 1.4)
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 10.0, 2.4)

		&"ballistics_lab":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(4.2, 4.2), 9.0, MONO_SHIELD_CYAN if is_active_prod else MONO_OFFWHITE)
			draw_halftone_dots(canvas, Rect2(-half + 5, -half + 5, half * 2.0 - 10, half - 6), 8.5, 1.3, Color(0.04, 0.05, 0.07, 0.42), 3.0)
			draw_brutalist_slab(canvas, Rect2(-26, -27, 52, 13), slab_dark, MONO_INK, Vector2(1.4, 1.4), 3.0, MONO_SHIELD_CYAN)
			draw_brutalist_slab(canvas, Rect2(-26, 14, 52, 13), slab_dark, MONO_INK, Vector2(1.4, 1.4), 3.0, MONO_AMBER)
			canvas.draw_rect(Rect2(-28, -9, 56, 18), MONO_INK, true)
			var rail_col: Color = Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.70 + active_pulse * 0.30) if is_active_prod else Color(0.42, 0.46, 0.52, 0.65)
			canvas.draw_line(Vector2(-24, -4), Vector2(24, -4), MONO_OFFWHITE, 2.0)
			canvas.draw_line(Vector2(-24, 4), Vector2(24, 4), MONO_OFFWHITE, 2.0)
			canvas.draw_line(Vector2(-24, 0), Vector2(24, 0), rail_col, 3.0)
			if is_active_prod:
				var sweep_x: float = lerpf(-20.0, 20.0, fmod(anim_time * 1.4, 1.0))
				canvas.draw_circle(Vector2(sweep_x, 0.0), 4.2, MONO_SHIELD_CYAN)
				draw_active_conduit_sparks(canvas, MONO_SHIELD_CYAN, 24.0, anim_time)
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 10.0, 2.4)

		&"bastion_emplacement":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(4.0, 4.0), 9.0, MONO_AMBER)
			draw_halftone_dots(canvas, Rect2(-half + 4, -half + 4, half * 2.0 - 8, half * 2.0 - 8), 8.0, 1.3, Color(0.04, 0.05, 0.07, 0.44), 3.0)
			for lug: Vector2 in [Vector2(-24, -24), Vector2(14, -24), Vector2(14, 14), Vector2(-24, 14)]:
				canvas.draw_rect(Rect2(lug, Vector2(10, 10)), MONO_OFFWHITE.lerp(slab_dark, 0.45), true)
				canvas.draw_rect(Rect2(lug, Vector2(10, 10)), MONO_INK, false, 1.8)
			canvas.draw_circle(Vector2.ZERO, 15.5, slab_dark)
			canvas.draw_arc(Vector2.ZERO, 15.5, 0.0, TAU, 24, MONO_AMBER, 2.0, true)
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 8.5, 2.4)

		&"siege_gantry":
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_brutalist_slab(canvas, main_rect, slab_base, MONO_INK, Vector2(4.6, 4.6), 10.0, MONO_AMBER if is_active_prod else MONO_OFFWHITE)
			canvas.draw_rect(Rect2(-30, -28, 60, 56), slab_dark, true)
			draw_halftone_dots(canvas, Rect2(-28, -26, 56, 52), 9.5, 1.5, Color(0.95, 0.94, 0.91, 0.22), 4.0)
			for butt: Vector2 in [Vector2(-40, -40), Vector2(24, -40), Vector2(24, 24), Vector2(-40, 24)]:
				draw_brutalist_slab(canvas, Rect2(butt, Vector2(16, 16)), slab_dark, MONO_INK, Vector2(1.6, 1.6), 3.0, MONO_AMBER)
				canvas.draw_rect(Rect2(butt + Vector2(4.5, 4.5), Vector2(7, 7)), MONO_AMBER if is_active_prod else Color(0.42, 0.46, 0.52, 0.8), true)
			canvas.draw_rect(Rect2(-35, -30, 8, 60), MONO_OFFWHITE.lerp(slab_base, 0.30), true)
			canvas.draw_rect(Rect2(27, -30, 8, 60), MONO_OFFWHITE.lerp(slab_base, 0.30), true)
			canvas.draw_rect(Rect2(-35, -30, 8, 60), MONO_INK, false, 1.8)
			canvas.draw_rect(Rect2(27, -30, 8, 60), MONO_INK, false, 1.8)
			var bridge_a_y: float = -12.0 + (sin(anim_time * 2.2) * 7.5 if is_active_prod else 0.0)
			var bridge_b_y: float = 12.0 - (sin(anim_time * 2.2) * 7.5 if is_active_prod else 0.0)
			canvas.draw_rect(Rect2(-34, bridge_a_y - 3.8, 68, 7.6), MONO_OFFWHITE, true)
			canvas.draw_rect(Rect2(-34, bridge_a_y - 3.8, 68, 7.6), MONO_INK, false, 1.8)
			canvas.draw_rect(Rect2(-34, bridge_b_y - 3.8, 68, 7.6), MONO_OFFWHITE, true)
			canvas.draw_rect(Rect2(-34, bridge_b_y - 3.8, 68, 7.6), MONO_INK, false, 1.8)
			if is_active_prod:
				canvas.draw_rect(Rect2(-15, -15, 30, 30), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.64 + active_pulse * 0.30), true)
				canvas.draw_rect(Rect2(-15, -15, 30, 30), MONO_OFFWHITE, false, 1.8)
				canvas.draw_circle(Vector2(0.0, 0.0), 6.5 + active_pulse * 2.2, MONO_SHIELD_CYAN)
				canvas.draw_circle(Vector2(0.0, bridge_a_y), 3.4, MONO_AMBER)
				canvas.draw_circle(Vector2(0.0, bridge_b_y), 3.4, MONO_AMBER)
				draw_active_conduit_sparks(canvas, MONO_AMBER, 28.0, anim_time)
			else:
				canvas.draw_rect(Rect2(-15, -15, 30, 30), Color(0.22, 0.25, 0.30, 0.80), true)
				canvas.draw_rect(Rect2(-15, -15, 30, 30), MONO_INK, false, 1.6)
				canvas.draw_circle(Vector2(0.0, 0.0), 5.0, Color(0.32, 0.40, 0.48, 0.72))
			draw_team_corner_brackets(canvas, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 11.0, 2.6)


func draw_building_turret(canvas: CanvasItem, building: Building, ctx: Dictionary) -> bool:
	var has_b: bool = building != null and is_instance_valid(building)
	var style: StringName = building.turret_tracer_style if has_b else (ctx.get("turret_tracer_style", &"") as StringName)
	if style != &"heavy_slug":
		return false
	var ang: float = building.get_turret_angle() if has_b else float(ctx.get("turret_angle", 0.0))
	var recoil: float = building.get_turret_recoil() if has_b else 0.0
	var dir: Vector2 = Vector2.RIGHT.rotated(ang)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var mono_ink: Color = Color(0.05, 0.06, 0.08, 0.96)
	var mono_slab: Color = Color(0.24, 0.27, 0.31, 0.98)
	var mono_white: Color = Color(0.95, 0.94, 0.91, 0.96)
	var team_col: Color = ctx["team_color"] as Color
	var mono_base: PackedVector2Array = PackedVector2Array([
		dir * 13.0 + perp * -8.5,
		dir * 13.0 + perp * 8.5,
		dir * 6.0 + perp * 12.0,
		dir * -12.0 + perp * 12.0,
		dir * -15.0 + perp * 8.0,
		dir * -15.0 + perp * -8.0,
		dir * -12.0 + perp * -12.0,
		dir * 6.0 + perp * -12.0,
	])
	var shadow_base: PackedVector2Array = PackedVector2Array()
	for pt_b: Vector2 in mono_base:
		shadow_base.append(pt_b + Vector2(2.5, 2.5))
	canvas.draw_colored_polygon(shadow_base, Color(0.04, 0.05, 0.07, 0.80))
	poly_outlined(canvas, mono_base, mono_slab, mono_ink, 2.2)
	var bs_m: Vector2 = dir * (8.0 - recoil)
	var be_m: Vector2 = dir * (28.0 - recoil)
	canvas.draw_line(bs_m + perp * -4.2, be_m + perp * -4.2, mono_ink, 6.2, true)
	canvas.draw_line(bs_m + perp * 4.2, be_m + perp * 4.2, mono_ink, 6.2, true)
	canvas.draw_line(bs_m + perp * -4.2, be_m + perp * -4.2, mono_white, 2.8, true)
	canvas.draw_line(bs_m + perp * 4.2, be_m + perp * 4.2, mono_white, 2.8, true)
	canvas.draw_line(dir * (24.0 - recoil) + perp * -6.5, dir * (24.0 - recoil) + perp * 6.5, MONO_AMBER, 2.6, true)
	canvas.draw_line(dir * -9.0 + perp * -7.0, dir * -9.0 + perp * 7.0, team_col, 3.0, true)
	canvas.draw_line(dir * 5.0 + perp * -5.0, dir * 5.0 + perp * 5.0, MONO_AMBER, 2.2, true)
	return true


func draw_building_upgrade_telltales(canvas: CanvasItem, type_id: StringName, building: Building, ctx: Dictionary) -> void:
	var anim_time: float = float(ctx["anim_time"])
	var pulse: float = 0.5 + 0.5 * sin(anim_time * 4.2)

	# 1. Hardened Plating on Bastion Emplacement
	if type_id == &"bastion_emplacement" and ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_HARDENED_PLATING):
		var h: float = maxf(18.0, building.footprint_radius * 0.78)
		canvas.draw_polyline(PackedVector2Array([Vector2(-h, -h + 9.0), Vector2(-h, -h), Vector2(-h + 9.0, -h)]), MONO_OFFWHITE, 3.0)
		canvas.draw_polyline(PackedVector2Array([Vector2(h - 9.0, -h), Vector2(h, -h), Vector2(h, -h + 9.0)]), MONO_OFFWHITE, 3.0)
		canvas.draw_polyline(PackedVector2Array([Vector2(-h, h - 9.0), Vector2(-h, h), Vector2(-h + 9.0, h)]), MONO_OFFWHITE, 3.0)
		canvas.draw_polyline(PackedVector2Array([Vector2(h - 9.0, h), Vector2(h, h), Vector2(h, h - 9.0)]), MONO_OFFWHITE, 3.0)

	# 2. Rapid Capacitors on Capacitor Pylon
	if type_id == &"capacitor_pylon" and ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_RAPID_CAPACITORS):
		canvas.draw_circle(Vector2(-11.0, -17.0), 2.6, MONO_SHIELD_CYAN)
		canvas.draw_circle(Vector2(11.0, -17.0), 2.6, MONO_SHIELD_CYAN)
		var c_ang: float = anim_time * 1.8
		var c_col: Color = Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.50 + pulse * 0.34)
		canvas.draw_arc(Vector2.ZERO, 22.0, c_ang, c_ang + PI * 0.72, 14, c_col, 1.8, true)
		canvas.draw_arc(Vector2.ZERO, 22.0, c_ang + PI, c_ang + PI * 1.72, 14, c_col, 1.8, true)

	# 3. Hyper-Velocity Rails on Bastion Emplacement
	if type_id == &"bastion_emplacement" and ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_HYPER_VELOCITY_RAILS):
		var aim_ang: float = building.get_turret_angle()
		var dir: Vector2 = Vector2.RIGHT.rotated(aim_ang)
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		canvas.draw_line(dir * 12.0 - perp * 7.5, dir * 12.0 + perp * 7.5, MONO_AMBER, 2.4, true)
		canvas.draw_line(dir * 19.0 - perp * 6.8, dir * 19.0 + perp * 6.8, MONO_AMBER, 2.4, true)
		canvas.draw_circle(dir * 25.0 - perp * 3.8, 2.2, MONO_OFFWHITE)
		canvas.draw_circle(dir * 25.0 + perp * 3.8, 2.2, MONO_OFFWHITE)
