class_name PrismaVisualRenderer
extends FactionVisualRenderer

## Faction #3 (PRISMA_DEI — The Divine Lattice) Bauhaus Sacred Geometry procedural renderer.
## Alabaster ceramic hulls (#F6F4EE), obsidian refraction chambers (#14111D),
## Liturgical Gold filigree (#FACC15), Ultraviolet Magenta lenses (#D946EF), and
## crisp team-colored ribbons/pennants for instant mirror-match readability.

const PRISMA_ALABASTER: Color = Color(0.965, 0.957, 0.933, 0.98) # #F6F4EE
const PRISMA_ALABASTER_SHADE: Color = Color(0.845, 0.830, 0.805, 0.98)
const PRISMA_OBSIDIAN: Color = Color(0.078, 0.067, 0.114, 0.98)  # #14111D
const PRISMA_GOLD: Color = Color(0.980, 0.800, 0.082, 1.0)       # #FACC15
const PRISMA_MAGENTA: Color = Color(0.851, 0.275, 0.937, 1.0)    # #D946EF
const PRISMA_WHITE_HOT: Color = Color(1.0, 0.99, 0.92, 1.0)
const PRISMA_SHADOW: Color = Color(0.05, 0.04, 0.09, 0.56)

const UNIT_IDS: Dictionary = {
	&"acolyte": true,
	&"prism_dredge": true,
	&"luminant": true,
	&"votary": true,
	&"lumen_skiff": true,
	&"cantor": true,
	&"lens_adjudicator": true,
	&"prism_weaver": true,
}

const BUILDING_IDS: Dictionary = {
	&"sanctum_core": true,
	&"halo_spire": true,
	&"alabaster_kiln": true,
	&"oracle_reliquary": true,
	&"choir_basilica": true,
	&"refraction_cloister": true,
	&"solar_obelisk": true,
}

const ANIMATED_UNITS: Dictionary = {
	&"luminant": true,
	&"cantor": true,
	&"lens_adjudicator": true,
	&"prism_weaver": true,
}


func handles_unit(type_id: StringName) -> bool:
	return UNIT_IDS.has(type_id)


func handles_building(type_id: StringName) -> bool:
	return BUILDING_IDS.has(type_id)


func needs_unit_animation(type_id: StringName, _ctx: Dictionary) -> bool:
	return ANIMATED_UNITS.has(type_id)


func get_completion_flash_color(_type_id: StringName) -> Color:
	return Color(0.98, 0.84, 0.26, 1.0)


func is_mechanical_damage_style(_type_id: StringName, is_building: bool) -> bool:
	return is_building


func get_building_outer_poly(type_id: StringName, radius: float) -> PackedVector2Array:
	var r: float = maxf(22.0, radius)
	if type_id == &"halo_spire":
		var d: float = r * 0.98
		var ch: float = r * 0.22
		return PackedVector2Array([
			Vector2(0.0, -d), Vector2(ch, -d + ch),
			Vector2(d, 0.0), Vector2(d - ch, ch),
			Vector2(0.0, d), Vector2(-ch, d - ch),
			Vector2(-d, 0.0), Vector2(-d + ch, -ch),
		])
	if type_id == &"oracle_reliquary":
		return PackedVector2Array([
			Vector2(0.0, -r * 0.98),
			Vector2(r * 0.88, r * 0.68),
			Vector2(-r * 0.88, r * 0.68),
		])
	if type_id == &"refraction_cloister":
		var e: float = r * 0.96
		var w: float = r * 0.56
		return PackedVector2Array([
			Vector2(0.0, -e), Vector2(e * 0.86, -w * 0.45),
			Vector2(e * 0.86, w * 0.65), Vector2(0.0, e * 0.94),
			Vector2(-e * 0.86, w * 0.65), Vector2(-e * 0.86, -w * 0.45),
		])
	var e_oct: float = r * 0.96
	var c_oct: float = r * 0.40
	return PackedVector2Array([
		Vector2(e_oct, -c_oct), Vector2(e_oct, c_oct),
		Vector2(c_oct, e_oct), Vector2(-c_oct, e_oct),
		Vector2(-e_oct, c_oct), Vector2(-e_oct, -c_oct),
		Vector2(-c_oct, -e_oct), Vector2(c_oct, -e_oct),
	])


static func _draw_diamond(canvas: CanvasItem, center: Vector2, rx: float, ry: float, fill: Color, outline: Color, lw: float = 1.2) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(rx, 0.0),
		center + Vector2(0.0, ry),
		center + Vector2(-rx, 0.0),
		center + Vector2(0.0, -ry),
	])
	poly_outlined(canvas, pts, fill, outline, lw)


static func _draw_soft_shadow(canvas: CanvasItem, poly: PackedVector2Array, offset: Vector2 = Vector2(2.4, 2.8)) -> void:
	var sh: PackedVector2Array = PackedVector2Array()
	sh.resize(poly.size())
	for i: int in range(poly.size()):
		sh[i] = poly[i] + offset
	canvas.draw_colored_polygon(sh, PRISMA_SHADOW)


# =============================================================================
# UNITS (8 BESPOKE BAUHAUS SILHOUETTES)
# =============================================================================

func draw_unit(canvas: CanvasItem, type_id: StringName, unit: Unit, ctx: Dictionary) -> void:
	var team_col: Color = ctx["team_color"] as Color
	var anim_time: float = float(ctx["anim_time"])
	var pulse: float = float(ctx["pulse"])
	var ceramic: Color = PRISMA_ALABASTER
	var ceramic_shade: Color = PRISMA_ALABASTER_SHADE.lerp(team_col, 0.12)
	var ribbon: Color = team_col.lerp(PRISMA_GOLD, 0.18)

	match type_id:
		&"acolyte":
			# Compact triangular alabaster hover-disc with twin golden tuning prongs & magenta core
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(11.5, 0.0), Vector2(-4.0, -9.5), Vector2(-10.5, -5.5),
				Vector2(-10.5, 5.5), Vector2(-4.0, 9.5),
			])
			_draw_soft_shadow(canvas, hull, Vector2(1.8, 2.2))
			poly_outlined(canvas, hull, ceramic, PRISMA_OBSIDIAN, 1.4)
			# Twin golden tuning prongs
			canvas.draw_line(Vector2(6.0, -4.5), Vector2(14.5, -3.2), PRISMA_GOLD, 1.6, true)
			canvas.draw_line(Vector2(6.0, 4.5), Vector2(14.5, 3.2), PRISMA_GOLD, 1.6, true)
			# Team dorsal ribbon
			var rib: PackedVector2Array = PackedVector2Array([
				Vector2(-2.0, -6.5), Vector2(-7.5, -4.5), Vector2(-7.5, 4.5), Vector2(-2.0, 6.5),
			])
			canvas.draw_colored_polygon(rib, ribbon)
			canvas.draw_circle(Vector2(1.5, 0.0), 4.0, PRISMA_OBSIDIAN)
			_draw_diamond(canvas, Vector2(1.5, 0.0), 3.0, 2.6, PRISMA_MAGENTA, PRISMA_GOLD, 1.0)

		&"prism_dredge":
			# Broad geometric diamond barge with obsidian ore hopper & golden collector wings
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(15.0, 0.0), Vector2(2.0, -13.0), Vector2(-14.0, -9.0),
				Vector2(-14.0, 9.0), Vector2(2.0, 13.0),
			])
			_draw_soft_shadow(canvas, hull, Vector2(2.0, 2.4))
			poly_outlined(canvas, hull, ceramic, PRISMA_OBSIDIAN, 1.5)
			# Golden collector wing trims
			canvas.draw_polyline(PackedVector2Array([Vector2(14.0, 0.0), Vector2(2.0, -12.0), Vector2(-8.0, -10.5)]), PRISMA_GOLD, 1.7, true)
			canvas.draw_polyline(PackedVector2Array([Vector2(14.0, 0.0), Vector2(2.0, 12.0), Vector2(-8.0, 10.5)]), PRISMA_GOLD, 1.7, true)
			# Obsidian ore hopper + team side bands
			canvas.draw_rect(Rect2(-9.5, -5.5, 13.0, 11.0), PRISMA_OBSIDIAN, true)
			canvas.draw_rect(Rect2(-9.5, -5.5, 13.0, 11.0), PRISMA_GOLD, false, 1.2)
			canvas.draw_line(Vector2(-12.0, -7.2), Vector2(-2.0, -7.2), ribbon, 2.2, true)
			canvas.draw_line(Vector2(-12.0, 7.2), Vector2(-2.0, 7.2), ribbon, 2.2, true)
			_draw_diamond(canvas, Vector2(6.5, 0.0), 3.5, 3.0, PRISMA_GOLD, PRISMA_WHITE_HOT, 1.0)

		&"luminant":
			# Sleek floating crescent-ring reliquary craft with bright gold-white halo crown
			var halo_rot: float = anim_time * 1.15
			canvas.draw_arc(Vector2.ZERO, 12.5, halo_rot, halo_rot + PI * 1.35, 18, PRISMA_GOLD, 1.5, true)
			canvas.draw_arc(Vector2.ZERO, 12.5, halo_rot + PI * 1.55, halo_rot + TAU - 0.15, 8, ribbon, 1.5, true)
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(12.5, 0.0), Vector2(1.0, -9.0), Vector2(-10.0, -5.5),
				Vector2(-6.5, 0.0), Vector2(-10.0, 5.5), Vector2(1.0, 9.0),
			])
			_draw_soft_shadow(canvas, hull, Vector2(1.8, 2.2))
			poly_outlined(canvas, hull, ceramic, PRISMA_OBSIDIAN, 1.4)
			canvas.draw_line(Vector2(-6.0, -4.5), Vector2(2.0, -6.5), ribbon, 2.0, true)
			canvas.draw_line(Vector2(-6.0, 4.5), Vector2(2.0, 6.5), ribbon, 2.0, true)
			_draw_diamond(canvas, Vector2(2.0, 0.0), 4.2, 3.6, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.2)
			canvas.draw_circle(Vector2(2.0, 0.0), 2.2 + pulse * 0.4, PRISMA_WHITE_HOT)

		&"votary":
			# Crisp forward-swept alabaster dart/chevron frame with twin golden needle vanes & magenta focus slit
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(16.0, 0.0), Vector2(3.0, -6.5), Vector2(-10.0, -11.5),
				Vector2(-5.5, 0.0), Vector2(-10.0, 11.5), Vector2(3.0, 6.5),
			])
			_draw_soft_shadow(canvas, hull, Vector2(2.0, 2.4))
			poly_outlined(canvas, hull, ceramic, PRISMA_OBSIDIAN, 1.45)
			# Team wing pennants
			var wing_l: PackedVector2Array = PackedVector2Array([Vector2(1.0, -5.0), Vector2(-8.0, -9.2), Vector2(-5.5, -3.0)])
			var wing_r: PackedVector2Array = PackedVector2Array([Vector2(1.0, 5.0), Vector2(-8.0, 9.2), Vector2(-5.5, 3.0)])
			canvas.draw_colored_polygon(wing_l, ribbon)
			canvas.draw_colored_polygon(wing_r, ribbon)
			# Twin golden needle vanes
			canvas.draw_line(Vector2(-3.0, -4.5), Vector2(13.5, -1.8), PRISMA_GOLD, 1.4, true)
			canvas.draw_line(Vector2(-3.0, 4.5), Vector2(13.5, 1.8), PRISMA_GOLD, 1.4, true)
			# Obsidian focus slit & magenta core
			canvas.draw_line(Vector2(-2.0, 0.0), Vector2(12.5, 0.0), PRISMA_OBSIDIAN, 3.0, true)
			canvas.draw_line(Vector2(0.0, 0.0), Vector2(11.5, 0.0), PRISMA_MAGENTA, 1.6, true)

		&"lumen_skiff":
			# Razor-thin elongated diamond interceptor with wide swept hairline wing arcs & solar-gold thruster pip
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(18.0, 0.0), Vector2(1.0, -6.8), Vector2(-14.0, 0.0), Vector2(1.0, 6.8),
			])
			_draw_soft_shadow(canvas, hull, Vector2(1.8, 2.4))
			# Wide swept hairline wing arcs
			canvas.draw_arc(Vector2(-3.0, 0.0), 14.5, -1.18, -0.32, 10, PRISMA_GOLD, 1.6, true)
			canvas.draw_arc(Vector2(-3.0, 0.0), 14.5, 0.32, 1.18, 10, PRISMA_GOLD, 1.6, true)
			poly_outlined(canvas, hull, ceramic, PRISMA_OBSIDIAN, 1.35)
			# Team dorsal stripe
			var stripe: PackedVector2Array = PackedVector2Array([
				Vector2(9.0, 0.0), Vector2(-1.0, -3.5), Vector2(-9.0, 0.0), Vector2(-1.0, 3.5),
			])
			canvas.draw_colored_polygon(stripe, ribbon)
			_draw_diamond(canvas, Vector2(3.5, 0.0), 4.0, 2.2, PRISMA_OBSIDIAN, PRISMA_MAGENTA, 1.1)
			canvas.draw_circle(Vector2(-12.5, 0.0), 2.4 + pulse * 0.5, PRISMA_GOLD)

		&"cantor":
			# Distinctive circular alabaster halo-ring vessel with rotating inner golden triangle & magenta chalice core
			canvas.draw_circle(Vector2(2.0, 2.4), 14.2, PRISMA_SHADOW)
			canvas.draw_circle(Vector2.ZERO, 14.0, ceramic)
			canvas.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, PRISMA_OBSIDIAN, 1.6, true)
			canvas.draw_circle(Vector2.ZERO, 10.2, PRISMA_OBSIDIAN)
			# Team arc bands on outer halo
			canvas.draw_arc(Vector2.ZERO, 12.1, -0.85, 0.85, 10, ribbon, 2.6, true)
			canvas.draw_arc(Vector2.ZERO, 12.1, PI - 0.85, PI + 0.85, 10, ribbon, 2.6, true)
			# Slowly rotating inner golden triangle
			var rot: float = anim_time * 0.95
			var tri: PackedVector2Array = PackedVector2Array()
			for ti: int in range(3):
				var ta: float = rot + float(ti) * (TAU / 3.0)
				tri.append(Vector2.RIGHT.rotated(ta) * 9.5)
			draw_closed_outline(canvas, tri, PRISMA_GOLD, 1.6)
			for pt: Vector2 in tri:
				canvas.draw_circle(pt, 1.8, PRISMA_WHITE_HOT)
			# Radiant magenta chalice core
			var core_r: float = 4.6 + pulse * 0.8
			canvas.draw_circle(Vector2.ZERO, core_r + 1.8, Color(PRISMA_MAGENTA.r, PRISMA_MAGENTA.g, PRISMA_MAGENTA.b, 0.34))
			canvas.draw_circle(Vector2.ZERO, core_r, PRISMA_MAGENTA)
			canvas.draw_circle(Vector2.ZERO, core_r * 0.48, PRISMA_WHITE_HOT)

		&"lens_adjudicator":
			# Hexagonal prism-frigate with open front twin-rail focusing crystal glowing magenta -> solar-white on beam ramp
			var ramp_ratio: float = 0.0
			if unit != null and is_instance_valid(unit) and unit.combat_component != null:
				ramp_ratio = unit.combat_component.get_beam_ramp_ratio(unit)
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(11.0, -9.5), Vector2(18.5, -5.5), Vector2(18.5, -2.6),
				Vector2(8.0, -2.6), Vector2(8.0, 2.6), Vector2(18.5, 2.6),
				Vector2(18.5, 5.5), Vector2(11.0, 9.5), Vector2(-11.0, 11.5),
				Vector2(-16.5, 6.0), Vector2(-16.5, -6.0), Vector2(-11.0, -11.5),
			])
			_draw_soft_shadow(canvas, hull, Vector2(2.4, 2.8))
			poly_outlined(canvas, hull, ceramic, PRISMA_OBSIDIAN, 1.55)
			# Obsidian inner nave & team wing bands
			var inner_hull: PackedVector2Array = PackedVector2Array([
				Vector2(6.0, -5.5), Vector2(-9.0, -7.0), Vector2(-12.5, 0.0), Vector2(-9.0, 7.0), Vector2(6.0, 5.5),
			])
			poly_outlined(canvas, inner_hull, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.3)
			canvas.draw_line(Vector2(-10.0, -9.2), Vector2(6.0, -7.8), ribbon, 2.4, true)
			canvas.draw_line(Vector2(-10.0, 9.2), Vector2(6.0, 7.8), ribbon, 2.4, true)
			# Twin golden focusing rails
			canvas.draw_line(Vector2(6.0, -4.2), Vector2(18.5, -4.0), PRISMA_GOLD, 1.8, true)
			canvas.draw_line(Vector2(6.0, 4.2), Vector2(18.5, 4.0), PRISMA_GOLD, 1.8, true)
			# Escalating focal crystal (Magenta -> Gold -> White-Hot as ramp rises)
			var crystal_col: Color = PRISMA_MAGENTA.lerp(PRISMA_GOLD, clampf(ramp_ratio * 1.25, 0.0, 1.0)).lerp(PRISMA_WHITE_HOT, ramp_ratio * 0.65)
			var glow_r: float = lerpf(4.5, 8.8, ramp_ratio) + pulse * 0.6
			canvas.draw_circle(Vector2(11.5, 0.0), glow_r, Color(crystal_col.r, crystal_col.g, crystal_col.b, 0.28 + ramp_ratio * 0.30))
			_draw_diamond(canvas, Vector2(11.5, 0.0), lerpf(4.8, 6.8, ramp_ratio), lerpf(2.8, 4.2, ramp_ratio), crystal_col, PRISMA_WHITE_HOT, 1.1)

		&"prism_weaver":
			# Wide tri-wing geometric star-prism with 3 golden outer mirror nodes & pulsing ultraviolet core
			var tri_body: PackedVector2Array = PackedVector2Array([
				Vector2(16.5, 0.0), Vector2(2.0, -5.5), Vector2(-11.0, -14.5),
				Vector2(-6.5, -4.5), Vector2(-14.0, 0.0), Vector2(-6.5, 4.5),
				Vector2(-11.0, 14.5), Vector2(2.0, 5.5),
			])
			_draw_soft_shadow(canvas, tri_body, Vector2(2.2, 2.6))
			poly_outlined(canvas, tri_body, ceramic, PRISMA_OBSIDIAN, 1.5)
			# Team geometric facets
			var f_l: PackedVector2Array = PackedVector2Array([Vector2(2.0, -4.2), Vector2(-8.8, -11.8), Vector2(-5.8, -3.5)])
			var f_r: PackedVector2Array = PackedVector2Array([Vector2(2.0, 4.2), Vector2(-8.8, 11.8), Vector2(-5.8, 3.5)])
			canvas.draw_colored_polygon(f_l, ribbon)
			canvas.draw_colored_polygon(f_r, ribbon)
			# 3 golden outer mirror nodes linked by hairline filigree
			var mirrors: Array[Vector2] = [Vector2(15.5, 0.0), Vector2(-10.5, -13.5), Vector2(-10.5, 13.5)]
			for mp: Vector2 in mirrors:
				canvas.draw_line(Vector2.ZERO, mp, PRISMA_GOLD, 1.3, true)
				_draw_diamond(canvas, mp, 3.0, 3.0, PRISMA_GOLD, PRISMA_WHITE_HOT, 1.0)
			# Pulsing ultraviolet core
			var w_r: float = 5.2 + pulse * 0.7
			canvas.draw_circle(Vector2.ZERO, w_r + 2.0, Color(PRISMA_MAGENTA.r, PRISMA_MAGENTA.g, PRISMA_MAGENTA.b, 0.28))
			_draw_diamond(canvas, Vector2.ZERO, w_r, w_r, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.3)
			canvas.draw_circle(Vector2.ZERO, 2.8 + pulse * 0.5, PRISMA_MAGENTA)
		_:
			var fallback: PackedVector2Array = PackedVector2Array([
				Vector2(14.0, 0.0), Vector2(0.0, -11.0), Vector2(-14.0, 0.0), Vector2(0.0, 11.0),
			])
			poly_outlined(canvas, fallback, ceramic_shade, PRISMA_GOLD, 1.5)


# =============================================================================
# BUILDINGS (7 BAUHAUS SACRED GEOMETRY SILHOUETTES + SOLAR OBELISK TURRET)
# =============================================================================

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
	var is_producing: bool = building != null and is_instance_valid(building) and building.is_actively_producing()
	var is_powered: bool = building == null or not is_instance_valid(building) or building.is_powered
	var r: float = building.footprint_radius if (building != null and is_instance_valid(building)) else 40.0
	var ribbon: Color = team_col.lerp(PRISMA_GOLD, 0.16)
	var energy_col: Color = PRISMA_MAGENTA if is_powered else Color(0.36, 0.30, 0.44, 0.75)

	# Grounded shadow + Alabaster ceramic primary slab + Obsidian hairline rim
	_draw_soft_shadow(canvas, hull_poly, Vector2(3.2, 3.8))
	poly_outlined(canvas, hull_poly, PRISMA_ALABASTER, PRISMA_OBSIDIAN, 1.8)
	draw_closed_outline(canvas, scale_poly(hull_poly, 0.88), PRISMA_GOLD, 1.3)

	match type_id:
		&"sanctum_core":
			# Grand 8-sided cathedral-rotunda: concentric gold halo rings, 4 radial buttress spires, obsidian nave, sun core
			var nave: PackedVector2Array = scale_poly(hull_poly, 0.62)
			poly_outlined(canvas, nave, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			# 4 radial stained-glass team buttress spires
			for bi: int in range(4):
				var ba: float = float(bi) * (PI * 0.5)
				var bd: Vector2 = Vector2.RIGHT.rotated(ba)
				var bp: Vector2 = bd.orthogonal()
				var buttress: PackedVector2Array = PackedVector2Array([
					bd * (r * 0.44) + bp * 5.0,
					bd * (r * 0.92) + bp * 2.5,
					bd * (r * 0.92) - bp * 2.5,
					bd * (r * 0.44) - bp * 5.0,
				])
				poly_outlined(canvas, buttress, ribbon, PRISMA_GOLD, 1.1)
			# Concentric gold halo arcs
			var rot_s: float = anim_time * (0.95 if is_producing else 0.35)
			canvas.draw_arc(Vector2.ZERO, r * 0.46, 0.0, TAU, 32, PRISMA_GOLD, 1.5, true)
			canvas.draw_arc(Vector2.ZERO, r * 0.34, rot_s, rot_s + PI * 1.4, 20, PRISMA_ALABASTER, 1.2, true)
			# Pulsing magenta-gold sun core
			var sun_r: float = r * (0.24 + (active_pulse * 0.05 if is_producing else pulse * 0.02))
			canvas.draw_circle(Vector2.ZERO, sun_r + 5.0, Color(energy_col.r, energy_col.g, energy_col.b, 0.28 + (active_pulse * 0.18 if is_producing else 0.0)))
			_draw_diamond(canvas, Vector2.ZERO, sun_r, sun_r, energy_col, PRISMA_GOLD, 1.5)
			canvas.draw_circle(Vector2.ZERO, sun_r * 0.45, PRISMA_WHITE_HOT)
			if is_producing:
				draw_active_conduit_sparks(canvas, PRISMA_GOLD, r * 0.62, anim_time)

		&"halo_spire":
			# Tall narrow alabaster obelisk-ring with twin rotating gold halo arcs & floating ultraviolet diamond
			var inner_d: PackedVector2Array = scale_poly(hull_poly, 0.62)
			poly_outlined(canvas, inner_d, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.3)
			# Team cardinal accents
			for hi: int in range(4):
				var hd: Vector2 = Vector2.RIGHT.rotated(float(hi) * PI * 0.5)
				canvas.draw_line(hd * (r * 0.52), hd * (r * 0.86), ribbon, 2.4, true)
			# Twin counter-rotating gold halo arcs
			var h_rot: float = anim_time * 1.25
			canvas.draw_arc(Vector2.ZERO, r * 0.58, h_rot, h_rot + PI * 0.72, 14, PRISMA_GOLD, 1.7, true)
			canvas.draw_arc(Vector2.ZERO, r * 0.58, h_rot + PI, h_rot + PI * 1.72, 14, PRISMA_GOLD, 1.7, true)
			var core_r: float = r * (0.28 + pulse * 0.04)
			canvas.draw_circle(Vector2.ZERO, core_r + 3.5, Color(PRISMA_MAGENTA.r, PRISMA_MAGENTA.g, PRISMA_MAGENTA.b, 0.28))
			_draw_diamond(canvas, Vector2.ZERO, core_r, core_r, PRISMA_MAGENTA, PRISMA_WHITE_HOT, 1.2)

		&"alabaster_kiln":
			# Twin trapezoidal ceramic crucibles bridged by a golden prism conduit glowing warm amber-gold
			var left_c: PackedVector2Array = PackedVector2Array([
				Vector2(-r * 0.76, -r * 0.52), Vector2(-r * 0.22, -r * 0.42),
				Vector2(-r * 0.22, r * 0.42), Vector2(-r * 0.76, r * 0.52),
			])
			var right_c: PackedVector2Array = PackedVector2Array([
				Vector2(r * 0.22, -r * 0.42), Vector2(r * 0.76, -r * 0.52),
				Vector2(r * 0.76, r * 0.52), Vector2(r * 0.22, r * 0.42),
			])
			poly_outlined(canvas, left_c, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			poly_outlined(canvas, right_c, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			# Team ceramic edge strips
			canvas.draw_line(Vector2(-r * 0.64, -r * 0.40), Vector2(-r * 0.64, r * 0.40), ribbon, 2.4, true)
			canvas.draw_line(Vector2(r * 0.64, -r * 0.40), Vector2(r * 0.64, r * 0.40), ribbon, 2.4, true)
			# Golden prism conduit bridge
			canvas.draw_rect(Rect2(-r * 0.34, -6.0, r * 0.68, 12.0), PRISMA_OBSIDIAN, true)
			canvas.draw_line(Vector2(-r * 0.55, 0.0), Vector2(r * 0.55, 0.0), PRISMA_GOLD, 3.0 + pulse * 0.8, true)
			_draw_diamond(canvas, Vector2.ZERO, 8.0, 8.0, PRISMA_GOLD, PRISMA_WHITE_HOT, 1.2)

		&"oracle_reliquary":
			# Symmetrical triangular reliquary spire over thermal vent with 3 recessed gold/magenta diamond staffing pips
			var inner_tri: PackedVector2Array = scale_poly(hull_poly, 0.66)
			poly_outlined(canvas, inner_tri, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			canvas.draw_line(Vector2(0.0, -r * 0.86), Vector2(0.0, r * 0.52), ribbon, 2.2, true)
			canvas.draw_arc(Vector2(0.0, -r * 0.08), r * 0.28, 0.0, TAU, 22, PRISMA_GOLD, 1.4, true)
			# 3 recessed gold/magenta diamond staffing pips
			var staffed: int = building.get_assigned_engineer_count() if (building != null and is_instance_valid(building)) else 0
			var pip_xs: Array[float] = [-14.0, 0.0, 14.0]
			for pi: int in range(3):
				var p_pos: Vector2 = Vector2(pip_xs[pi], r * 0.34)
				var is_lit: bool = pi < staffed
				var pip_fill: Color = PRISMA_MAGENTA if is_lit else Color(0.18, 0.16, 0.24, 0.92)
				var pip_rim: Color = PRISMA_WHITE_HOT if is_lit else PRISMA_GOLD
				_draw_diamond(canvas, p_pos, 4.6, 4.6, pip_fill, pip_rim, 1.2)
			var eye_col: Color = PRISMA_MAGENTA if staffed > 0 else Color(0.55, 0.32, 0.68, 0.72)
			canvas.draw_circle(Vector2(0.0, -r * 0.08), 5.0 + (active_pulse * 1.4 if staffed > 0 else 0.0), eye_col)
			if staffed > 0:
				draw_active_conduit_sparks(canvas, PRISMA_MAGENTA, r * 0.50, anim_time)

		&"choir_basilica":
			# Twin nave-wing cathedral hall with an arched gold rose-window centerpiece that pulses magenta during training
			var wing_l: PackedVector2Array = PackedVector2Array([
				Vector2(-r * 0.84, -r * 0.52), Vector2(-r * 0.36, -r * 0.64),
				Vector2(-r * 0.36, r * 0.64), Vector2(-r * 0.84, r * 0.52),
			])
			var wing_r: PackedVector2Array = PackedVector2Array([
				Vector2(r * 0.36, -r * 0.64), Vector2(r * 0.84, -r * 0.52),
				Vector2(r * 0.84, r * 0.52), Vector2(r * 0.36, r * 0.64),
			])
			poly_outlined(canvas, wing_l, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			poly_outlined(canvas, wing_r, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			canvas.draw_line(Vector2(-r * 0.60, -r * 0.46), Vector2(-r * 0.60, r * 0.46), ribbon, 3.0, true)
			canvas.draw_line(Vector2(r * 0.60, -r * 0.46), Vector2(r * 0.60, r * 0.46), ribbon, 3.0, true)
			# Arched gold rose-window centerpiece
			var rose_r: float = r * 0.38
			canvas.draw_circle(Vector2.ZERO, rose_r, PRISMA_OBSIDIAN)
			canvas.draw_arc(Vector2.ZERO, rose_r, 0.0, TAU, 28, PRISMA_GOLD, 1.7, true)
			for si: int in range(8):
				var sa: float = float(si) * (TAU / 8.0) + (anim_time * 0.45 if is_producing else 0.0)
				canvas.draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(sa) * rose_r, Color(PRISMA_GOLD.r, PRISMA_GOLD.g, PRISMA_GOLD.b, 0.72), 1.1, true)
			var core_r: float = rose_r * (0.48 + (active_pulse * 0.14 if is_producing else pulse * 0.04))
			canvas.draw_circle(Vector2.ZERO, core_r, energy_col)
			canvas.draw_circle(Vector2.ZERO, core_r * 0.44, PRISMA_WHITE_HOT if is_powered else PRISMA_ALABASTER_SHADE)
			if is_producing:
				draw_active_conduit_sparks(canvas, PRISMA_MAGENTA, r * 0.56, anim_time)

		&"refraction_cloister":
			# Precision triangular lens gallery with 3 mirrored gold focal prisms framing a central magenta beam chamber
			var chamber: PackedVector2Array = scale_poly(hull_poly, 0.66)
			poly_outlined(canvas, chamber, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			# 3 mirrored gold focal prisms at 120-deg symmetry
			for pi: int in range(3):
				var pa: float = -PI * 0.5 + float(pi) * (TAU / 3.0)
				var pd: Vector2 = Vector2.RIGHT.rotated(pa)
				var pp: Vector2 = pd.orthogonal()
				var prism_pt: Vector2 = pd * (r * 0.56)
				var p_tri: PackedVector2Array = PackedVector2Array([
					prism_pt + pd * 8.0,
					prism_pt - pd * 4.0 + pp * 7.5,
					prism_pt - pd * 4.0 - pp * 7.5,
				])
				poly_outlined(canvas, p_tri, ribbon if pi == 0 else PRISMA_ALABASTER, PRISMA_GOLD, 1.3)
				canvas.draw_line(Vector2.ZERO, prism_pt, Color(energy_col.r, energy_col.g, energy_col.b, 0.78), 1.6, true)
			var c_rad: float = r * (0.24 + (active_pulse * 0.06 if is_producing else 0.0))
			_draw_diamond(canvas, Vector2.ZERO, c_rad, c_rad, energy_col, PRISMA_WHITE_HOT, 1.4)
			if is_producing:
				draw_active_conduit_sparks(canvas, PRISMA_GOLD, r * 0.54, anim_time)

		&"solar_obelisk":
			# Octagonal alabaster plinth with gold/team corner filigree (turret lens drawn via draw_building_turret)
			var plinth: PackedVector2Array = scale_poly(hull_poly, 0.66)
			poly_outlined(canvas, plinth, PRISMA_OBSIDIAN, PRISMA_GOLD, 1.4)
			for ci: int in range(4):
				var ca: float = PI * 0.25 + float(ci) * (PI * 0.5)
				var cd: Vector2 = Vector2.RIGHT.rotated(ca)
				canvas.draw_line(cd * (r * 0.52), cd * (r * 0.88), ribbon, 2.4, true)
			canvas.draw_arc(Vector2.ZERO, r * 0.44, 0.0, TAU, 24, PRISMA_GOLD, 1.5, true)


func draw_building_turret(canvas: CanvasItem, building: Building, ctx: Dictionary) -> bool:
	if building == null or not is_instance_valid(building) or building.building_type_id != &"solar_obelisk":
		return false
	var angle: float = building.get_turret_angle()
	var recoil: float = building.get_turret_recoil()
	var dir: Vector2 = Vector2.RIGHT.rotated(angle)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var base: Vector2 = -dir * recoil
	var is_powered: bool = building.is_powered
	var lens_col: Color = PRISMA_MAGENTA if is_powered else Color(0.35, 0.30, 0.42, 0.75)
	var team_col: Color = ctx["team_color"] as Color

	# Rotating alabaster turret crown
	var crown: PackedVector2Array = PackedVector2Array([
		base + dir * 10.0 + perp * 7.0,
		base + dir * 10.0 - perp * 7.0,
		base - dir * 9.0 - perp * 8.0,
		base - dir * 9.0 + perp * 8.0,
	])
	poly_outlined(canvas, crown, PRISMA_ALABASTER, PRISMA_OBSIDIAN, 1.5)
	# Twin golden focusing prongs
	canvas.draw_line(base + dir * 4.0 + perp * 5.2, base + dir * 24.0 + perp * 3.0, PRISMA_GOLD, 2.4, true)
	canvas.draw_line(base + dir * 4.0 - perp * 5.2, base + dir * 24.0 - perp * 3.0, PRISMA_GOLD, 2.4, true)
	# Team crest strip
	canvas.draw_line(base - dir * 5.0 + perp * 5.0, base - dir * 5.0 - perp * 5.0, team_col, 2.4, true)
	# Central floating focusing prism lens
	var lens_pos: Vector2 = base + dir * 14.0
	var lens_pts: PackedVector2Array = PackedVector2Array([
		lens_pos + dir * 5.5,
		lens_pos + perp * 3.8,
		lens_pos - dir * 5.5,
		lens_pos - perp * 3.8,
	])
	poly_outlined(canvas, lens_pts, lens_col, PRISMA_WHITE_HOT if is_powered else PRISMA_GOLD, 1.2)
	return true
