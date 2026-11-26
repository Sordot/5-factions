class_name GenesisVisualRenderer
extends FactionVisualRenderer

## Faction #1 (GENESIS_V2 — The Vat-Born) Technozen / Y2K Bio-Synth procedural renderer.

const GENESIS_EMERALD: Color = Color(0.204, 0.827, 0.600, 1.0) # #34D399

const UNIT_IDS: Dictionary = {
	&"worker": true,
	&"silica_harvester": true,
	&"engineer": true,
	&"clone_trooper": true,
	&"stinger": true,
	&"symbiote": true,
	&"lance_rig": true,
	&"signal_jammer": true,
	&"goliath_frame": true,
	&"arc_lancer": true,
	&"chrysalis_mortar": true,
}

const BUILDING_IDS: Dictionary = {
	&"nexus_vat": true,
	&"synapse_pylon": true,
	&"silica_condenser": true,
	&"wetware_mainframe": true,
	&"cloning_vat": true,
	&"calibration_foundry": true,
	&"synthetics_fabricator": true,
	&"defense_turret": true,
}

const ANIMATED_UNITS: Dictionary = {
	&"symbiote": true,
	&"signal_jammer": true,
	&"arc_lancer": true,
	&"goliath_frame": true,
	&"clone_trooper": true,
}

const MECH_UNITS: Dictionary = {
	&"silica_harvester": true,
	&"lance_rig": true,
	&"signal_jammer": true,
	&"goliath_frame": true,
	&"arc_lancer": true,
	&"chrysalis_mortar": true,
}


func handles_unit(type_id: StringName) -> bool:
	return UNIT_IDS.has(type_id)


func handles_building(type_id: StringName) -> bool:
	return BUILDING_IDS.has(type_id)


func needs_unit_animation(type_id: StringName, _ctx: Dictionary) -> bool:
	return ANIMATED_UNITS.has(type_id)


func is_mechanical_damage_style(type_id: StringName, is_building: bool) -> bool:
	if is_building:
		return true
	return MECH_UNITS.has(type_id)


func get_building_outer_poly(type_id: StringName, radius: float) -> PackedVector2Array:
	var r: float = maxf(22.0, radius)
	match type_id:
		&"synapse_pylon":
			return PackedVector2Array([
				Vector2(0, -r), Vector2(r * 0.85, -r * 0.45), Vector2(r * 0.85, r * 0.45),
				Vector2(0, r), Vector2(-r * 0.85, r * 0.45), Vector2(-r * 0.85, -r * 0.45),
			])
		&"silica_condenser":
			return PackedVector2Array([
				Vector2(-r * 0.95, -r * 0.70), Vector2(r * 0.55, -r * 0.95), Vector2(r * 0.95, -r * 0.55),
				Vector2(r * 0.95, r * 0.70), Vector2(-r * 0.55, r * 0.95), Vector2(-r * 0.95, r * 0.55),
			])
		&"wetware_mainframe":
			return PackedVector2Array([
				Vector2(-r * 0.92, -r * 0.92), Vector2(r * 0.92, -r * 0.92),
				Vector2(r * 0.92, r * 0.92), Vector2(-r * 0.92, r * 0.92),
			])
		_:
			return super.get_building_outer_poly(type_id, radius)


func draw_unit(canvas: CanvasItem, type_id: StringName, unit: Unit, ctx: Dictionary) -> void:
	var p: Dictionary = ctx["palette"] as Dictionary
	var team: int = int(ctx["team"])
	var anim_time: float = float(ctx["anim_time"])
	var pulse: float = float(ctx["pulse"])
	var shell: Color = p["shell"]
	var shell_hi: Color = p["shell_hi"]
	var deck: Color = p["deck"]
	var trim: Color = p["trim"]
	var core: Color = p["core"]
	var core_alt: Color = p["core_alt"]
	var outline: Color = p["outline"]

	match type_id:
		&"worker":
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(10, -7), Vector2(10, 7), Vector2(1, 11),
				Vector2(-10, 9), Vector2(-12, 0), Vector2(-10, -9), Vector2(1, -11),
			])
			poly_outlined(canvas, hull, shell, outline, 1.4)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(8, -8), Vector2(17, -6.5), Vector2(15.5, -3), Vector2(8, -4)]), trim)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(8, 4), Vector2(15.5, 3), Vector2(17, 6.5), Vector2(8, 8)]), trim)
			canvas.draw_line(Vector2(15.5, -5.5), Vector2(18.5, -3.5), core_alt, 1.8, true)
			canvas.draw_line(Vector2(15.5, 5.5), Vector2(18.5, 3.5), core_alt, 1.8, true)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(5, -4), Vector2(5, 4), Vector2(-4, 5), Vector2(-6.5, 0), Vector2(-4, -5)]), deck)
			canvas.draw_circle(Vector2(-0.5, 0.0), 3.4, core_alt)

		&"silica_harvester":
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(14, -10), Vector2(14, 10), Vector2(3, 14.5),
				Vector2(-15, 13.5), Vector2(-17, 0), Vector2(-15, -13.5), Vector2(3, -14.5),
			])
			var harv_shell: Color = Color(0.86, 0.84, 0.78, 0.97) if team == 0 else shell
			var amber: Color = Color(0.98, 0.78, 0.24, 1.0) if team == 0 else core_alt
			poly_outlined(canvas, hull, harv_shell, amber, 1.6)
			var scoop: PackedVector2Array = PackedVector2Array([
				Vector2(12, -12), Vector2(21, -8.5), Vector2(21, 8.5), Vector2(12, 12), Vector2(14, 7), Vector2(14, -7),
			])
			poly_outlined(canvas, scoop, trim, amber, 1.3)
			canvas.draw_rect(Rect2(-13, -13.5, 18, 3.2), deck, true)
			canvas.draw_rect(Rect2(-13, 10.3, 18, 3.2), deck, true)
			canvas.draw_rect(Rect2(-10, -7, 15, 14), deck, true)
			canvas.draw_rect(Rect2(-7, -4.5, 9, 9), amber, true)

		&"engineer":
			var hex: PackedVector2Array = PackedVector2Array([
				Vector2(12, 0), Vector2(6, 10.5), Vector2(-7, 10.5),
				Vector2(-13, 0), Vector2(-7, -10.5), Vector2(6, -10.5),
			])
			var eng_accent: Color = Color(0.28, 0.86, 1.0, 1.0) if team == 0 else core
			poly_outlined(canvas, hex, shell_hi, eng_accent, 1.5)
			canvas.draw_line(Vector2(9, -3.5), Vector2(16.5, -5.5), trim, 2.2, true)
			canvas.draw_line(Vector2(9, 3.5), Vector2(16.5, 5.5), trim, 2.2, true)
			canvas.draw_arc(Vector2(15.5, 0.0), 4.2, -1.1, 1.1, 10, eng_accent, 2.0, true)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(1, 5.5), Vector2(-5, 5.5), Vector2(-8, 0), Vector2(-5, -5.5), Vector2(1, -5.5)]), deck)
			canvas.draw_circle(Vector2(1.0, 0.0), 3.2, eng_accent)

		&"clone_trooper":
			var adrenal_active: bool = (unit != null and unit.has_status_effect(&"adrenal_surge"))
			var visor_col: Color = core
			var border_col: Color = outline
			if adrenal_active:
				visor_col = Color(0.32, 1.0, 0.56, 1.0).lerp(Color(1.0, 0.92, 0.28, 1.0), pulse)
				border_col = visor_col
			var body: PackedVector2Array = PackedVector2Array([
				Vector2(12, -4), Vector2(12, 4), Vector2(2, 11.5),
				Vector2(-10, 9.5), Vector2(-12, 0), Vector2(-10, -9.5), Vector2(2, -11.5),
			])
			poly_outlined(canvas, body, shell_hi, border_col, 1.6)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(3, -11), Vector2(-7, -9), Vector2(-7, -5), Vector2(4, -6)]), trim)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(3, 11), Vector2(-7, 9), Vector2(-7, 5), Vector2(4, 6)]), trim)
			canvas.draw_rect(Rect2(6, 2.0, 15.5, 3.4), deck, true)
			canvas.draw_line(Vector2(8, 3.7), Vector2(21.5, 3.7), visor_col, 1.6, true)
			canvas.draw_circle(Vector2(2.0, 0.0), 5.4, deck)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(8.5, 0), Vector2(3.0, -4.4), Vector2(-0.5, 0), Vector2(3.0, 4.4)]), visor_col)

		&"stinger":
			var dart_accent: Color = Color(0.98, 0.80, 0.24, 1.0) if team == 0 else core_alt
			var wings: PackedVector2Array = PackedVector2Array([
				Vector2(19, 0), Vector2(1, -5), Vector2(-12, -12.5),
				Vector2(-7, -3.5), Vector2(-14, 0), Vector2(-7, 3.5),
				Vector2(-12, 12.5), Vector2(1, 5),
			])
			poly_outlined(canvas, wings, shell_hi, dart_accent, 1.5)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(-3, -4.5), Vector2(-8, 0), Vector2(-3, 4.5)]), deck)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(14, 0), Vector2(1, -2.6), Vector2(-3, 0), Vector2(1, 2.6)]), dart_accent)

		&"symbiote":
			var bio_col: Color = Color(0.24, 1.0, 0.66, 1.0) if team == 0 else core
			var halo_r: float = 13.0 + pulse * 2.0
			canvas.draw_circle(Vector2.ZERO, halo_r, Color(bio_col.r, bio_col.g, bio_col.b, 0.16))
			canvas.draw_circle(Vector2.ZERO, 11.5, shell_hi)
			canvas.draw_arc(Vector2.ZERO, 11.5, 0.0, TAU, 24, bio_col, 1.8, true)
			for k: int in range(3):
				var a: float = anim_time * 1.8 + float(k) * (TAU / 3.0)
				var pt: Vector2 = Vector2.RIGHT.rotated(a) * 11.0
				canvas.draw_circle(pt, 2.6, trim)
			canvas.draw_circle(Vector2.ZERO, 6.2, deck)
			canvas.draw_circle(Vector2.ZERO, 4.2 + pulse * 0.6, bio_col)
			canvas.draw_line(Vector2(-3.5, 0), Vector2(3.5, 0), Color(0.95, 1.0, 0.98, 0.95), 1.6, true)
			canvas.draw_line(Vector2(0, -3.5), Vector2(0, 3.5), Color(0.95, 1.0, 0.98, 0.95), 1.6, true)

		&"lance_rig":
			var lance_col: Color = Color(0.98, 0.72, 0.26, 1.0) if team == 0 else core
			canvas.draw_rect(Rect2(-15, -17, 24, 6), deck, true)
			canvas.draw_rect(Rect2(-15, 11, 24, 6), deck, true)
			canvas.draw_rect(Rect2(-15, -17, 24, 6), trim, false, 1.2)
			canvas.draw_rect(Rect2(-15, 11, 24, 6), trim, false, 1.2)
			var turret: PackedVector2Array = PackedVector2Array([
				Vector2(11, -11), Vector2(11, 11), Vector2(-10, 13),
				Vector2(-17, 7), Vector2(-17, -7), Vector2(-10, -13),
			])
			poly_outlined(canvas, turret, shell, lance_col, 1.7)
			canvas.draw_rect(Rect2(5, -5.5, 22, 3.2), trim, true)
			canvas.draw_rect(Rect2(5, 2.3, 22, 3.2), trim, true)
			canvas.draw_line(Vector2(6, 0.0), Vector2(28, 0.0), lance_col, 2.6, true)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(6, -5), Vector2(6, 5), Vector2(-7, 6), Vector2(-10, 0), Vector2(-7, -6)]), deck)
			canvas.draw_circle(Vector2(-1.0, 0.0), 4.2, lance_col)

		&"signal_jammer":
			var jam_col: Color = Color(0.74, 0.50, 1.0, 1.0) if team == 0 else core_alt
			var chassis: PackedVector2Array = PackedVector2Array([
				Vector2(14, -7), Vector2(14, 7), Vector2(4, 15),
				Vector2(-12, 13), Vector2(-16, 0), Vector2(-12, -13), Vector2(4, -15),
			])
			poly_outlined(canvas, chassis, shell, jam_col, 1.6)
			canvas.draw_line(Vector2(5, -13), Vector2(9, -18), trim, 2.4, true)
			canvas.draw_line(Vector2(5, 13), Vector2(9, 18), trim, 2.4, true)
			canvas.draw_line(Vector2(-10, -11), Vector2(-14, -16), trim, 2.4, true)
			canvas.draw_line(Vector2(-10, 11), Vector2(-14, 16), trim, 2.4, true)
			canvas.draw_circle(Vector2(-1, 0), 9.5, deck)
			canvas.draw_arc(Vector2(-1, 0), 9.5, 0.0, TAU, 20, jam_col, 1.8, true)
			var sweep_a: float = anim_time * 3.0
			canvas.draw_arc(Vector2(-1, 0), 6.2, sweep_a, sweep_a + PI * 0.85, 12, jam_col, 2.0, true)
			canvas.draw_circle(Vector2(-1, 0), 3.0 + pulse * 0.8, jam_col)

		&"goliath_frame":
			var has_overdrive: bool = ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_COMPUTE_OVERDRIVE)
			var accent_col: Color = Color(0.32, 0.96, 1.0, 1.0) if team == 0 else core
			var od_col: Color = Color(1.0, 0.86, 0.28, 1.0) if team == 0 else Color(1.0, 0.62, 0.16, 1.0)
			var main_hull: PackedVector2Array = PackedVector2Array([
				Vector2(20, -11), Vector2(20, 11), Vector2(9, 22),
				Vector2(-15, 22), Vector2(-22, 12), Vector2(-22, -12), Vector2(-15, -22), Vector2(9, -22),
			])
			poly_outlined(canvas, main_hull, shell_hi, od_col if has_overdrive else accent_col, 2.2)
			var sh_l: PackedVector2Array = PackedVector2Array([Vector2(13, -22), Vector2(13, -10), Vector2(-15, -10), Vector2(-19, -19)])
			var sh_r: PackedVector2Array = PackedVector2Array([Vector2(13, 10), Vector2(13, 22), Vector2(-19, 19), Vector2(-15, 10)])
			poly_outlined(canvas, sh_l, trim, od_col if has_overdrive else outline, 1.6)
			poly_outlined(canvas, sh_r, trim, od_col if has_overdrive else outline, 1.6)
			canvas.draw_rect(Rect2(14, -15, 10, 5), deck, true)
			canvas.draw_rect(Rect2(14, 10, 10, 5), deck, true)
			var core_poly: PackedVector2Array = PackedVector2Array([
				Vector2(12, 0), Vector2(5, -9), Vector2(-9, -9), Vector2(-13, 0), Vector2(-9, 9), Vector2(5, 9),
			])
			canvas.draw_colored_polygon(core_poly, deck)
			canvas.draw_circle(Vector2(0, 0), 6.2, accent_col)
			if has_overdrive:
				canvas.draw_arc(Vector2.ZERO, 16.5, 0.0, TAU, 24, Color(od_col.r, od_col.g, od_col.b, 0.65 + pulse * 0.35), 2.2, true)
				canvas.draw_line(Vector2(-13, -15), Vector2(11, -15), od_col, 2.2, true)
				canvas.draw_line(Vector2(-13, 15), Vector2(11, 15), od_col, 2.2, true)

		&"arc_lancer":
			var arc_col: Color = Color(0.42, 0.98, 1.0, 1.0) if team == 0 else core
			var leg_angles: PackedFloat32Array = PackedFloat32Array([-2.25, 2.25, PI])
			for a: float in leg_angles:
				var knee: Vector2 = Vector2.RIGHT.rotated(a) * 16.0
				var foot: Vector2 = Vector2.RIGHT.rotated(a) * 24.0
				canvas.draw_line(Vector2.ZERO, knee, trim, 3.4, true)
				canvas.draw_line(knee, foot, deck, 2.4, true)
				canvas.draw_circle(knee, 3.0, arc_col)
			var spire: PackedVector2Array = PackedVector2Array([
				Vector2(26, 0), Vector2(10, -9), Vector2(-6, -15),
				Vector2(-14, -10), Vector2(-9, 0), Vector2(-14, 10), Vector2(-6, 15), Vector2(10, 9),
			])
			poly_outlined(canvas, spire, shell_hi, arc_col, 1.9)
			canvas.draw_line(Vector2(4, -7), Vector2(27, -4.5), trim, 3.0, true)
			canvas.draw_line(Vector2(4, 7), Vector2(27, 4.5), trim, 3.0, true)
			canvas.draw_line(Vector2(6, 0), Vector2(25, 0), Color(arc_col.r, arc_col.g, arc_col.b, 0.7 + pulse * 0.3), 2.4, true)
			canvas.draw_circle(Vector2(1.0, 0.0), 5.0, deck)
			canvas.draw_circle(Vector2(1.0, 0.0), 3.2 + pulse * 0.6, arc_col)

		&"chrysalis_mortar":
			var acid_col: Color = Color(0.42, 1.0, 0.52, 1.0) if team == 0 else core_alt
			var carapace: PackedVector2Array = PackedVector2Array([
				Vector2(18, -9), Vector2(18, 9), Vector2(6, 20),
				Vector2(-13, 19), Vector2(-21, 9), Vector2(-21, -9), Vector2(-13, -19), Vector2(6, -20),
			])
			poly_outlined(canvas, carapace, shell, acid_col, 1.8)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(-6, -19), Vector2(4, -22), Vector2(6, -16), Vector2(-8, -15)]), trim)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(-6, 19), Vector2(4, 22), Vector2(6, 16), Vector2(-8, 15)]), trim)
			canvas.draw_circle(Vector2(-2.0, 0.0), 11.5, deck)
			canvas.draw_rect(Rect2(-4, -5.5, 22, 11), trim, true)
			canvas.draw_rect(Rect2(-4, -5.5, 22, 11), acid_col, false, 1.4)
			canvas.draw_circle(Vector2(14.5, 0.0), 4.6, deck)
			canvas.draw_circle(Vector2(14.5, 0.0), 3.0, acid_col)
			canvas.draw_circle(Vector2(-6.0, 0.0), 4.4, acid_col)


func draw_unit_upgrade_telltales(canvas: CanvasItem, type_id: StringName, _unit: Unit, ctx: Dictionary) -> void:
	# 1. Batch Efficiency: crisp emerald-mint collar/wingtip chevrons
	if ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_BATCH_EFFICIENCY):
		if type_id == &"clone_trooper" or type_id == &"stinger" or type_id == &"symbiote":
			canvas.draw_polyline(PackedVector2Array([Vector2(-3.5, -10.5), Vector2(1.5, -7.5), Vector2(-3.5, -4.5)]), GENESIS_EMERALD, 1.7, true)
			canvas.draw_polyline(PackedVector2Array([Vector2(-3.5, 10.5), Vector2(1.5, 7.5), Vector2(-3.5, 4.5)]), GENESIS_EMERALD, 1.7, true)

	# 2. Adrenal Potency: glowing twin-cell crimson/gold dorsal stim-pack + bright visor ridge
	if ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_ADRENAL_POTENCY) and type_id == &"clone_trooper":
		canvas.draw_rect(Rect2(-9.5, -5.5, 4.0, 4.2), Color(1.0, 0.34, 0.24, 0.96), true)
		canvas.draw_rect(Rect2(-9.5, 1.3, 4.0, 4.2), Color(1.0, 0.84, 0.28, 0.96), true)
		canvas.draw_line(Vector2(6.5, -3.6), Vector2(6.5, 3.6), Color(1.0, 0.94, 0.62, 0.98), 2.1, true)


func draw_building(
	canvas: CanvasItem,
	type_id: StringName,
	building: Building,
	hull_poly: PackedVector2Array,
	ctx: Dictionary
) -> void:
	var p: Dictionary = ctx["palette"] as Dictionary
	var team: int = int(ctx["team"])
	var anim_time: float = float(ctx["anim_time"])
	var pulse: float = float(ctx["pulse"])
	var active_pulse: float = float(ctx["active_pulse"])
	var shell: Color = p["shell"]
	var shell_hi: Color = p["shell_hi"]
	var deck: Color = p["deck"]
	var trim: Color = p["trim"]
	var core: Color = p["core"]
	var core_alt: Color = p["core_alt"]
	var outline: Color = p["outline"]
	var is_training: bool = building.get_training_queue_size() > 0
	var is_active_prod: bool = building.is_actively_producing()
	var standby_slate: Color = Color(0.28, 0.42, 0.50, 0.72)

	# Subtle Technozen circuit grounding pad under completed structures
	if SettingsManager == null or SettingsManager.battle_scars_enabled:
		var pad_poly: PackedVector2Array = scale_poly(hull_poly, 1.18)
		canvas.draw_colored_polygon(pad_poly, Color(0.04, 0.07, 0.10, 0.42))
		draw_closed_outline(canvas, pad_poly, Color(core.r, core.g, core.b, 0.20), 1.1)
		var pad_r: float = maxf(26.0, building.footprint_radius * 1.12)
		for ci: int in range(4):
			var c_ang: float = PI * 0.25 + float(ci) * (PI * 0.5)
			var c_dir: Vector2 = Vector2.RIGHT.rotated(c_ang)
			canvas.draw_line(c_dir * (pad_r * 0.86), c_dir * (pad_r * 1.06), Color(core.r, core.g, core.b, 0.26), 1.4, true)

	match type_id:
		&"nexus_vat":
			poly_outlined(canvas, hull_poly, shell_hi, outline, 2.4)
			var inner_oct: PackedVector2Array = scale_poly(hull_poly, 0.76)
			canvas.draw_colored_polygon(inner_oct, deck)
			canvas.draw_rect(Rect2(-40, -7, 13, 14), trim, true)
			canvas.draw_rect(Rect2(27, -7, 13, 14), trim, true)
			canvas.draw_rect(Rect2(-7, -40, 14, 13), trim, true)
			canvas.draw_rect(Rect2(-7, 27, 14, 13), trim, true)
			canvas.draw_line(Vector2(-34, 0), Vector2(34, 0), Color(core.r, core.g, core.b, 0.75), 3.0, true)
			canvas.draw_line(Vector2(0, -34), Vector2(0, 34), Color(core.r, core.g, core.b, 0.75), 3.0, true)
			canvas.draw_circle(Vector2.ZERO, 19.0, Color(0.08, 0.14, 0.20, 1.0))
			canvas.draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 28, outline, 1.8, true)
			var core_r: float = 12.0 + pulse * 2.2
			canvas.draw_circle(Vector2.ZERO, core_r, core)
			canvas.draw_circle(Vector2.ZERO, core_r * 0.52, Color(0.88, 1.0, 0.98, 0.85))
			if is_training:
				canvas.draw_arc(Vector2.ZERO, 25.0, anim_time * 2.2, anim_time * 2.2 + PI * 1.1, 20, core_alt, 2.2, true)

		&"synapse_pylon":
			var py_col: Color = Color(0.76, 0.58, 1.0, 1.0) if team == 0 else core
			poly_outlined(canvas, hull_poly, shell_hi, py_col, 2.0)
			var diamond: PackedVector2Array = PackedVector2Array([
				Vector2(0, -24), Vector2(13, 0), Vector2(0, 24), Vector2(-13, 0),
			])
			poly_outlined(canvas, diamond, deck, py_col, 1.5)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, -13), Vector2(7, 0), Vector2(0, 13), Vector2(-7, 0)]), py_col)
			canvas.draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 28, Color(py_col.r, py_col.g, py_col.b, 0.42), 1.4, true)
			var orb_a: float = anim_time * 2.1
			var orb_pt: Vector2 = Vector2.RIGHT.rotated(orb_a) * 21.0
			canvas.draw_circle(orb_pt, 3.2, py_col)
			canvas.draw_circle(-orb_pt, 2.4, Color(py_col.r, py_col.g, py_col.b, 0.72))

		&"silica_condenser":
			var sil_col: Color = Color(0.98, 0.78, 0.28, 1.0) if team == 0 else core_alt
			poly_outlined(canvas, hull_poly, shell, sil_col, 2.2)
			canvas.draw_colored_polygon(scale_poly(hull_poly, 0.74), deck)
			canvas.draw_rect(Rect2(-24, -15, 18, 30), trim, true)
			canvas.draw_rect(Rect2(6, -15, 18, 30), trim, true)
			canvas.draw_rect(Rect2(-21, -12, 12, 24), Color(sil_col.r, sil_col.g, sil_col.b, 0.85), true)
			canvas.draw_rect(Rect2(9, -12, 12, 24), Color(sil_col.r, sil_col.g, sil_col.b, 0.65 + pulse * 0.3), true)
			var prism: PackedVector2Array = PackedVector2Array([
				Vector2(0, -12), Vector2(7, 0), Vector2(0, 12), Vector2(-7, 0),
			])
			poly_outlined(canvas, prism, Color(1.0, 0.94, 0.68, 0.95) if team == 0 else core, sil_col, 1.5)

		&"wetware_mainframe":
			var cmp_col: Color = Color(0.28, 0.88, 1.0, 1.0) if team == 0 else core
			var mf_border: Color = cmp_col if is_active_prod else standby_slate.lerp(cmp_col, 0.45)
			poly_outlined(canvas, hull_poly, shell_hi, mf_border, 2.2)
			canvas.draw_rect(Rect2(-24, -24, 48, 48), deck, true)
			var staffed: int = building.get_assigned_engineer_count()
			var g_col: Color = Color(cmp_col.r, cmp_col.g, cmp_col.b, 0.62 + active_pulse * 0.36) if is_active_prod else Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42)
			for gx: float in [-16.0, -6.0, 6.0, 16.0]:
				canvas.draw_line(Vector2(gx, -21), Vector2(gx, 14), g_col, 1.8 if is_active_prod else 1.4)
			for gy: float in [-16.0, -4.0, 8.0]:
				canvas.draw_line(Vector2(-21, gy), Vector2(21, gy), g_col, 1.8 if is_active_prod else 1.4)
			var cpu: PackedVector2Array = PackedVector2Array([
				Vector2(0, -11), Vector2(11, 0), Vector2(0, 11), Vector2(-11, 0),
			])
			if is_active_prod:
				canvas.draw_colored_polygon(cpu, Color(cmp_col.r, cmp_col.g, cmp_col.b, 0.68 + active_pulse * 0.30))
				canvas.draw_circle(Vector2.ZERO, 4.0 + active_pulse * 1.4, Color(0.90, 1.0, 1.0, 0.82))
				draw_active_conduit_sparks(canvas, cmp_col, 22.0, anim_time)
			else:
				canvas.draw_colored_polygon(cpu, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.45))
			var slots: int = maxi(1, building.max_staff_slots)
			for s: int in range(slots):
				var px: float = (float(s) - float(slots - 1) * 0.5) * 16.0
				var pip_rect: Rect2 = Rect2(px - 5.5, 16.5, 11.0, 6.0)
				var filled: bool = s < staffed
				canvas.draw_rect(pip_rect, cmp_col if filled else Color(0.14, 0.20, 0.26, 0.95), true)
				canvas.draw_rect(pip_rect, mf_border, false, 1.2)

		&"cloning_vat":
			var vat_col: Color = Color(0.22, 0.96, 0.76, 1.0) if team == 0 else core
			var vat_border: Color = vat_col if is_active_prod else standby_slate.lerp(vat_col, 0.45)
			poly_outlined(canvas, hull_poly, shell_hi, vat_border, 2.4)
			canvas.draw_colored_polygon(scale_poly(hull_poly, 0.76), deck)
			var chamber_l: Rect2 = Rect2(-26, -20, 20, 40)
			var chamber_r: Rect2 = Rect2(6, -20, 20, 40)
			if is_active_prod:
				var glow_a: float = 0.62 + active_pulse * 0.36
				canvas.draw_rect(chamber_l, Color(vat_col.r, vat_col.g, vat_col.b, glow_a * 0.82), true)
				canvas.draw_rect(chamber_r, Color(vat_col.r, vat_col.g, vat_col.b, glow_a * 0.82), true)
				canvas.draw_rect(chamber_l, shell_hi, false, 1.6)
				canvas.draw_rect(chamber_r, shell_hi, false, 1.6)
				canvas.draw_rect(Rect2(-6, -10, 12, 20), trim, true)
				canvas.draw_line(Vector2(-6, 0), Vector2(6, 0), Color(0.88, 1.0, 0.96, 0.65 + active_pulse * 0.35), 2.4, true)
				var wave_y: float = lerpf(16.0, -16.0, fmod(anim_time * 1.5, 1.0))
				canvas.draw_line(Vector2(-24, wave_y), Vector2(-8, wave_y), Color(0.92, 1.0, 0.96, 0.95), 2.4)
				canvas.draw_line(Vector2(8, -wave_y), Vector2(24, -wave_y), Color(0.92, 1.0, 0.96, 0.95), 2.4)
				canvas.draw_circle(Vector2(-16, 0), 4.2 + active_pulse * 2.4, Color(0.9, 1.0, 0.96, 0.52))
				canvas.draw_circle(Vector2(16, 0), 4.2 + active_pulse * 2.4, Color(0.9, 1.0, 0.96, 0.52))
				draw_active_conduit_sparks(canvas, vat_col, 24.0, anim_time)
			else:
				var idle_tank: Color = standby_slate.lerp(vat_col, 0.25)
				canvas.draw_rect(chamber_l, Color(idle_tank.r, idle_tank.g, idle_tank.b, 0.44), true)
				canvas.draw_rect(chamber_r, Color(idle_tank.r, idle_tank.g, idle_tank.b, 0.44), true)
				canvas.draw_rect(chamber_l, Color(trim.r, trim.g, trim.b, 0.72), false, 1.4)
				canvas.draw_rect(chamber_r, Color(trim.r, trim.g, trim.b, 0.72), false, 1.4)
				canvas.draw_rect(Rect2(-6, -10, 12, 20), trim, true)
				canvas.draw_circle(Vector2(-16, 0), 3.6, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42))
				canvas.draw_circle(Vector2(16, 0), 3.6, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42))

		&"calibration_foundry":
			var fnd_col: Color = Color(0.98, 0.68, 0.26, 1.0) if team == 0 else core_alt
			var fnd_border: Color = fnd_col if is_active_prod else standby_slate.lerp(fnd_col, 0.45)
			poly_outlined(canvas, hull_poly, shell, fnd_border, 2.4)
			canvas.draw_colored_polygon(scale_poly(hull_poly, 0.76), deck)
			canvas.draw_rect(Rect2(-27, -28, 9, 56), trim, true)
			canvas.draw_rect(Rect2(18, -28, 9, 56), trim, true)
			if is_active_prod:
				var bridge_y: float = sin(anim_time * 2.6) * 10.0
				canvas.draw_line(Vector2(-22.5, -24), Vector2(-22.5, 24), Color(fnd_col.r, fnd_col.g, fnd_col.b, 0.55 + active_pulse * 0.42), 2.2, true)
				canvas.draw_line(Vector2(22.5, -24), Vector2(22.5, 24), Color(fnd_col.r, fnd_col.g, fnd_col.b, 0.55 + active_pulse * 0.42), 2.2, true)
				canvas.draw_rect(Rect2(-26, bridge_y - 4, 52, 8), shell_hi, true)
				canvas.draw_rect(Rect2(-11, -13, 22, 26), Color(fnd_col.r, fnd_col.g, fnd_col.b, 0.74 + active_pulse * 0.26), true)
				canvas.draw_rect(Rect2(-11, -13, 22, 26), Color(1.0, 0.96, 0.84, 0.92), false, 1.6)
				canvas.draw_circle(Vector2(0.0, bridge_y), 3.6 + active_pulse * 1.4, Color(1.0, 0.95, 0.80, 0.88))
				draw_active_conduit_sparks(canvas, fnd_col, 24.0, anim_time)
			else:
				var idle_bay: Color = standby_slate.lerp(fnd_col, 0.22)
				canvas.draw_rect(Rect2(-26, -4, 52, 8), Color(trim.r, trim.g, trim.b, 0.85), true)
				canvas.draw_rect(Rect2(-11, -13, 22, 26), Color(idle_bay.r, idle_bay.g, idle_bay.b, 0.45), true)
				canvas.draw_rect(Rect2(-11, -13, 22, 26), Color(trim.r, trim.g, trim.b, 0.72), false, 1.3)

		&"synthetics_fabricator":
			var fab_col: Color = Color(0.32, 0.96, 1.0, 1.0) if team == 0 else core
			var fab_border: Color = fab_col if is_active_prod else standby_slate.lerp(fab_col, 0.45)
			poly_outlined(canvas, hull_poly, shell_hi, fab_border, 2.6)
			canvas.draw_colored_polygon(scale_poly(hull_poly, 0.78), deck)
			var coil_pts: PackedVector2Array = PackedVector2Array([
				Vector2(-26, -26), Vector2(26, -26), Vector2(26, 26), Vector2(-26, 26),
			])
			for cp: Vector2 in coil_pts:
				canvas.draw_circle(cp, 8.5, trim)
				if is_active_prod:
					canvas.draw_circle(cp, 5.2 + active_pulse * 1.6, fab_col)
					canvas.draw_line(cp, cp.normalized() * 14.0, Color(fab_col.r, fab_col.g, fab_col.b, 0.65 + active_pulse * 0.35), 2.4, true)
				else:
					canvas.draw_circle(cp, 4.4, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.48))
					canvas.draw_line(cp, cp.normalized() * 14.0, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.38), 1.6, true)
			canvas.draw_circle(Vector2.ZERO, 20.0, Color(0.08, 0.16, 0.24, 1.0))
			if is_active_prod:
				canvas.draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, fab_col, 2.4, true)
				var spin: float = anim_time * 3.0
				canvas.draw_arc(Vector2.ZERO, 13.5, spin, spin + PI * 0.75, 16, Color(0.92, 1.0, 1.0, 0.94), 2.5, true)
				canvas.draw_arc(Vector2.ZERO, 13.5, spin + PI, spin + PI * 1.75, 16, Color(0.92, 1.0, 1.0, 0.94), 2.5, true)
				canvas.draw_circle(Vector2.ZERO, 6.8 + active_pulse * 2.0, fab_col)
				canvas.draw_circle(Vector2.ZERO, 3.6, Color(0.94, 1.0, 1.0, 0.90))
				draw_active_conduit_sparks(canvas, fab_col, 28.0, anim_time)
			else:
				canvas.draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.52), 1.8, true)
				canvas.draw_arc(Vector2.ZERO, 13.5, 0.4, 0.4 + PI * 0.75, 16, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42), 1.8, true)
				canvas.draw_arc(Vector2.ZERO, 13.5, 0.4 + PI, 0.4 + PI * 1.75, 16, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42), 1.8, true)
				canvas.draw_circle(Vector2.ZERO, 5.4, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.45))

		&"defense_turret":
			var tur_col: Color = Color(0.28, 0.96, 0.92, 1.0) if team == 0 else core
			poly_outlined(canvas, hull_poly, shell_hi, tur_col, 2.2)
			canvas.draw_colored_polygon(scale_poly(hull_poly, 0.72), deck)
			for lug: Vector2 in [Vector2(-19, -19), Vector2(19, -19), Vector2(19, 19), Vector2(-19, 19)]:
				canvas.draw_circle(lug, 4.2, trim)
				canvas.draw_circle(lug, 1.8, tur_col)
			canvas.draw_circle(Vector2.ZERO, 14.5, Color(0.08, 0.14, 0.20, 1.0))
			canvas.draw_arc(Vector2.ZERO, 14.5, 0.0, TAU, 24, Color(tur_col.r, tur_col.g, tur_col.b, 0.65 + pulse * 0.25), 1.8, true)


func draw_building_upgrade_telltales(canvas: CanvasItem, type_id: StringName, _building: Building, ctx: Dictionary) -> void:
	if type_id == &"cloning_vat" and ctx_has_upgrade(ctx, UpgradeManager.UPGRADE_BATCH_EFFICIENCY):
		canvas.draw_polyline(PackedVector2Array([Vector2(-7.0, -4.0), Vector2(0.0, -10.0), Vector2(7.0, -4.0)]), GENESIS_EMERALD, 2.2, true)
		canvas.draw_polyline(PackedVector2Array([Vector2(-7.0, 4.0), Vector2(0.0, 10.0), Vector2(7.0, 4.0)]), GENESIS_EMERALD, 2.2, true)
		canvas.draw_circle(Vector2(-15.0, -18.0), 2.8, GENESIS_EMERALD)
		canvas.draw_circle(Vector2(15.0, -18.0), 2.8, GENESIS_EMERALD)
