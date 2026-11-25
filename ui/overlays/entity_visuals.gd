class_name EntityVisuals
extends Node2D

## Procedural Technozen / Y2K silhouette renderer for GENESIS_V2 units and structures.
## Attached as a child of a Unit's BodyVisual (inherits rotation & hit-flash modulate)
## or directly inside a Building's BodyVisual (handles blueprint wireframe & progressive fill).

enum Mode {
	UNIT,
	BUILDING,
}

var mode: Mode = Mode.UNIT
var entity_type_id: StringName = &""
var team: int = 0
var _owner_unit: Unit = null
var _owner_building: Building = null
var _anim_time: float = 0.0


func bind_unit(unit: Unit) -> void:
	mode = Mode.UNIT
	_owner_unit = unit
	entity_type_id = unit.get_unit_type_id()
	team = int(unit.team)
	queue_redraw()


func bind_building(building: Building) -> void:
	mode = Mode.BUILDING
	_owner_building = building
	entity_type_id = building.building_type_id
	team = int(building.team)
	queue_redraw()


func _process(delta: float) -> void:
	_anim_time += delta
	if mode == Mode.UNIT:
		if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.is_dead:
			return
		entity_type_id = _owner_unit.get_unit_type_id()
		team = int(_owner_unit.team)
		# Redraw animated units (pulses, overdrive, adrenal flashes, striders)
		if (
			entity_type_id == &"symbiote"
			or entity_type_id == &"signal_jammer"
			or entity_type_id == &"arc_lancer"
			or entity_type_id == &"goliath_frame"
			or entity_type_id == &"clone_trooper"
			or _owner_unit.has_status_effect(&"adrenal_surge")
		):
			queue_redraw()
	else:
		if _owner_building == null or not is_instance_valid(_owner_building) or _owner_building.is_destroyed:
			return
		entity_type_id = _owner_building.building_type_id
		team = int(_owner_building.team)
		queue_redraw()


func _get_palette() -> Dictionary:
	if TeamManager != null:
		return TeamManager.get_team_palette(team)
	var is_enemy: bool = (team == int(Unit.Team.ENEMY))
	if is_enemy:
		return {
			"shell": Color(0.84, 0.78, 0.80, 0.96),
			"shell_hi": Color(0.95, 0.88, 0.88, 0.98),
			"deck": Color(0.20, 0.12, 0.14, 0.98),
			"trim": Color(0.54, 0.30, 0.32, 1.0),
			"core": Color(1.0, 0.32, 0.24, 1.0),
			"core_alt": Color(1.0, 0.66, 0.24, 1.0),
			"outline": Color(1.0, 0.42, 0.32, 0.92),
			"wire": Color(1.0, 0.42, 0.32, 0.88),
		}
	return {
		"shell": Color(0.90, 0.95, 0.98, 0.96),
		"shell_hi": Color(0.97, 0.99, 1.0, 0.98),
		"deck": Color(0.14, 0.22, 0.29, 0.98),
		"trim": Color(0.50, 0.64, 0.74, 1.0),
		"core": Color(0.20, 0.96, 0.86, 1.0),
		"core_alt": Color(0.28, 0.98, 0.62, 1.0),
		"outline": Color(0.30, 0.96, 0.92, 0.92),
		"wire": Color(0.28, 0.96, 1.0, 0.88),
	}


func _draw() -> void:
	var p: Dictionary = _get_palette()
	_draw_marquee_preview_ring()
	if mode == Mode.UNIT:
		_draw_unit_silhouette(p)
	else:
		_draw_building_silhouette(p)


func _draw_marquee_preview_ring() -> void:
	var smart_mode: bool = SettingsManager != null and SettingsManager.smart_box_select_enabled
	var ring_col: Color = Color(0.961, 0.620, 0.043, 0.92) if smart_mode else Color(0.220, 0.741, 0.973, 0.92)
	if mode == Mode.UNIT:
		if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.is_dead:
			return
		if not _owner_unit.is_marquee_highlighted or _owner_unit.is_selected:
			return
		var r: float = _owner_unit.get_selection_radius() + 2.0
		draw_circle(Vector2.ZERO, r, Color(ring_col.r, ring_col.g, ring_col.b, 0.14))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, ring_col, 1.8, true)
	else:
		if _owner_building == null or not is_instance_valid(_owner_building) or _owner_building.is_destroyed:
			return
		if not _owner_building.is_marquee_highlighted or _owner_building.is_selected:
			return
		var r_b: float = maxf(_owner_building.selection_radius, _owner_building.footprint_radius + 6.0)
		draw_circle(Vector2.ZERO, r_b, Color(ring_col.r, ring_col.g, ring_col.b, 0.11))
		draw_arc(Vector2.ZERO, r_b, 0.0, TAU, 36, ring_col, 2.0, true)


# =============================================================================
# UNIT SILHOUETTES
# =============================================================================

func _draw_unit_silhouette(p: Dictionary) -> void:
	var shell: Color = p["shell"]
	var shell_hi: Color = p["shell_hi"]
	var deck: Color = p["deck"]
	var trim: Color = p["trim"]
	var core: Color = p["core"]
	var core_alt: Color = p["core_alt"]
	var outline: Color = p["outline"]
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.5)

	match entity_type_id:
		&"worker":
			# Compact utility chassis with dual front bio-claw prongs
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(10, -7), Vector2(10, 7), Vector2(1, 11),
				Vector2(-10, 9), Vector2(-12, 0), Vector2(-10, -9), Vector2(1, -11),
			])
			_poly_outlined(hull, shell, outline, 1.4)
			# Bio-claw prongs
			draw_colored_polygon(PackedVector2Array([Vector2(8, -8), Vector2(17, -6.5), Vector2(15.5, -3), Vector2(8, -4)]), trim)
			draw_colored_polygon(PackedVector2Array([Vector2(8, 4), Vector2(15.5, 3), Vector2(17, 6.5), Vector2(8, 8)]), trim)
			draw_line(Vector2(15.5, -5.5), Vector2(18.5, -3.5), core_alt, 1.8, true)
			draw_line(Vector2(15.5, 5.5), Vector2(18.5, 3.5), core_alt, 1.8, true)
			# Dorsal core
			draw_colored_polygon(PackedVector2Array([Vector2(5, -4), Vector2(5, 4), Vector2(-4, 5), Vector2(-6.5, 0), Vector2(-4, -5)]), deck)
			draw_circle(Vector2(-0.5, 0.0), 3.4, core_alt)

		&"silica_harvester":
			# Heavy automated crawler with wide front crystal scoop and amber dorsal hopper
			var hull: PackedVector2Array = PackedVector2Array([
				Vector2(14, -10), Vector2(14, 10), Vector2(3, 14.5),
				Vector2(-15, 13.5), Vector2(-17, 0), Vector2(-15, -13.5), Vector2(3, -14.5),
			])
			var harv_shell: Color = Color(0.86, 0.84, 0.78, 0.97) if team == 0 else shell
			var amber: Color = Color(0.98, 0.78, 0.24, 1.0) if team == 0 else core_alt
			_poly_outlined(hull, harv_shell, amber, 1.6)
			# Wide crystal scoop
			var scoop: PackedVector2Array = PackedVector2Array([
				Vector2(12, -12), Vector2(21, -8.5), Vector2(21, 8.5), Vector2(12, 12), Vector2(14, 7), Vector2(14, -7),
			])
			_poly_outlined(scoop, trim, amber, 1.3)
			# Treads & hopper bed
			draw_rect(Rect2(-13, -13.5, 18, 3.2), deck, true)
			draw_rect(Rect2(-13, 10.3, 18, 3.2), deck, true)
			draw_rect(Rect2(-10, -7, 15, 14), deck, true)
			draw_rect(Rect2(-7, -4.5, 9, 9), amber, true)

		&"engineer":
			# Sleek hexagonal compute specialist with glowing neural wrench prong
			var hex: PackedVector2Array = PackedVector2Array([
				Vector2(12, 0), Vector2(6, 10.5), Vector2(-7, 10.5),
				Vector2(-13, 0), Vector2(-7, -10.5), Vector2(6, -10.5),
			])
			var eng_accent: Color = Color(0.28, 0.86, 1.0, 1.0) if team == 0 else core
			_poly_outlined(hex, shell_hi, eng_accent, 1.5)
			# Neural wrench front emitter
			draw_line(Vector2(9, -3.5), Vector2(16.5, -5.5), trim, 2.2, true)
			draw_line(Vector2(9, 3.5), Vector2(16.5, 5.5), trim, 2.2, true)
			draw_arc(Vector2(15.5, 0.0), 4.2, -1.1, 1.1, 10, eng_accent, 2.0, true)
			# Inner neural visor
			draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(1, 5.5), Vector2(-5, 5.5), Vector2(-8, 0), Vector2(-5, -5.5), Vector2(1, -5.5)]), deck)
			draw_circle(Vector2(1.0, 0.0), 3.2, eng_accent)

		&"clone_trooper":
			# Crisp infantry silhouette with rifle barrel + glowing cyan/crimson visor (flashes green/gold in Adrenal Surge)
			var adrenal_active: bool = (_owner_unit != null and _owner_unit.has_status_effect(&"adrenal_surge"))
			var visor_col: Color = core
			var border_col: Color = outline
			if adrenal_active:
				visor_col = Color(0.32, 1.0, 0.56, 1.0).lerp(Color(1.0, 0.92, 0.28, 1.0), pulse)
				border_col = visor_col
			# Torso / shoulders
			var body: PackedVector2Array = PackedVector2Array([
				Vector2(12, -4), Vector2(12, 4), Vector2(2, 11.5),
				Vector2(-10, 9.5), Vector2(-12, 0), Vector2(-10, -9.5), Vector2(2, -11.5),
			])
			_poly_outlined(body, shell_hi, border_col, 1.6)
			# Polymer shoulder pads
			draw_colored_polygon(PackedVector2Array([Vector2(3, -11), Vector2(-7, -9), Vector2(-7, -5), Vector2(4, -6)]), trim)
			draw_colored_polygon(PackedVector2Array([Vector2(3, 11), Vector2(-7, 9), Vector2(-7, 5), Vector2(4, 6)]), trim)
			# Rifle barrel on right side
			draw_rect(Rect2(6, 2.0, 15.5, 3.4), deck, true)
			draw_line(Vector2(8, 3.7), Vector2(21.5, 3.7), visor_col, 1.6, true)
			# Visor helmet
			draw_circle(Vector2(2.0, 0.0), 5.4, deck)
			draw_colored_polygon(PackedVector2Array([Vector2(8.5, 0), Vector2(3.0, -4.4), Vector2(-0.5, 0), Vector2(3.0, 4.4)]), visor_col)

		&"stinger":
			# Sleek, swept-back triangular speed-dart silhouette
			var dart_accent: Color = Color(0.98, 0.80, 0.24, 1.0) if team == 0 else core_alt
			var wings: PackedVector2Array = PackedVector2Array([
				Vector2(19, 0), Vector2(1, -5), Vector2(-12, -12.5),
				Vector2(-7, -3.5), Vector2(-14, 0), Vector2(-7, 3.5),
				Vector2(-12, 12.5), Vector2(1, 5),
			])
			_poly_outlined(wings, shell_hi, dart_accent, 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(-3, -4.5), Vector2(-8, 0), Vector2(-3, 4.5)]), deck)
			draw_colored_polygon(PackedVector2Array([Vector2(14, 0), Vector2(1, -2.6), Vector2(-3, 0), Vector2(1, 2.6)]), dart_accent)

		&"symbiote":
			# Floating orb-drone with bioluminescent core and bio-cross filaments
			var bio_col: Color = Color(0.24, 1.0, 0.66, 1.0) if team == 0 else core
			var halo_r: float = 13.0 + pulse * 2.0
			draw_circle(Vector2.ZERO, halo_r, Color(bio_col.r, bio_col.g, bio_col.b, 0.16))
			draw_circle(Vector2.ZERO, 11.5, shell_hi)
			draw_arc(Vector2.ZERO, 11.5, 0.0, TAU, 24, bio_col, 1.8, true)
			# Orbiting 3 stabilizer petals
			for k: int in range(3):
				var a: float = _anim_time * 1.8 + float(k) * (TAU / 3.0)
				var pt: Vector2 = Vector2.RIGHT.rotated(a) * 11.0
				draw_circle(pt, 2.6, trim)
			draw_circle(Vector2.ZERO, 6.2, deck)
			draw_circle(Vector2.ZERO, 4.2 + pulse * 0.6, bio_col)
			# Bio-support cross
			draw_line(Vector2(-3.5, 0), Vector2(3.5, 0), Color(0.95, 1.0, 0.98, 0.95), 1.6, true)
			draw_line(Vector2(0, -3.5), Vector2(0, 3.5), Color(0.95, 1.0, 0.98, 0.95), 1.6, true)

		&"lance_rig":
			# Heavy bipedal/tracked rail-walker with elongated anti-armor lance barrel
			var lance_col: Color = Color(0.98, 0.72, 0.26, 1.0) if team == 0 else core
			# Side track pods
			draw_rect(Rect2(-15, -17, 24, 6), deck, true)
			draw_rect(Rect2(-15, 11, 24, 6), deck, true)
			draw_rect(Rect2(-15, -17, 24, 6), trim, false, 1.2)
			draw_rect(Rect2(-15, 11, 24, 6), trim, false, 1.2)
			# Angular turret chassis
			var turret: PackedVector2Array = PackedVector2Array([
				Vector2(11, -11), Vector2(11, 11), Vector2(-10, 13),
				Vector2(-17, 7), Vector2(-17, -7), Vector2(-10, -13),
			])
			_poly_outlined(turret, shell, lance_col, 1.7)
			# Elongated twin-rail anti-armor lance barrel
			draw_rect(Rect2(5, -5.5, 22, 3.2), trim, true)
			draw_rect(Rect2(5, 2.3, 22, 3.2), trim, true)
			draw_line(Vector2(6, 0.0), Vector2(28, 0.0), lance_col, 2.6, true)
			# Core capacitor
			draw_colored_polygon(PackedVector2Array([Vector2(6, -5), Vector2(6, 5), Vector2(-7, 6), Vector2(-10, 0), Vector2(-7, -6)]), deck)
			draw_circle(Vector2(-1.0, 0.0), 4.2, lance_col)

		&"signal_jammer":
			# Dish-topped support walker with rotating/pulsing radar array
			var jam_col: Color = Color(0.74, 0.50, 1.0, 1.0) if team == 0 else core_alt
			var chassis: PackedVector2Array = PackedVector2Array([
				Vector2(14, -7), Vector2(14, 7), Vector2(4, 15),
				Vector2(-12, 13), Vector2(-16, 0), Vector2(-12, -13), Vector2(4, -15),
			])
			_poly_outlined(chassis, shell, jam_col, 1.6)
			# Support legs
			draw_line(Vector2(5, -13), Vector2(9, -18), trim, 2.4, true)
			draw_line(Vector2(5, 13), Vector2(9, 18), trim, 2.4, true)
			draw_line(Vector2(-10, -11), Vector2(-14, -16), trim, 2.4, true)
			draw_line(Vector2(-10, 11), Vector2(-14, 16), trim, 2.4, true)
			# Parabolic dish array
			draw_circle(Vector2(-1, 0), 9.5, deck)
			draw_arc(Vector2(-1, 0), 9.5, 0.0, TAU, 20, jam_col, 1.8, true)
			var sweep_a: float = _anim_time * 3.0
			draw_arc(Vector2(-1, 0), 6.2, sweep_a, sweep_a + PI * 0.85, 12, jam_col, 2.0, true)
			draw_circle(Vector2(-1, 0), 3.0 + pulse * 0.8, jam_col)

		&"goliath_frame":
			# Broad imposing heavy mech with layered shoulder plates + Compute Overdrive trim
			var has_overdrive: bool = false
			if _owner_unit != null and _owner_unit.is_inside_tree():
				var econ: EconomyManager = _owner_unit.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
				if econ != null:
					has_overdrive = econ.has_upgrade(_owner_unit.team, UpgradeManager.UPGRADE_COMPUTE_OVERDRIVE)
			var accent_col: Color = Color(0.32, 0.96, 1.0, 1.0) if team == 0 else core
			var od_col: Color = Color(1.0, 0.86, 0.28, 1.0) if team == 0 else Color(1.0, 0.62, 0.16, 1.0)
			var main_hull: PackedVector2Array = PackedVector2Array([
				Vector2(20, -11), Vector2(20, 11), Vector2(9, 22),
				Vector2(-15, 22), Vector2(-22, 12), Vector2(-22, -12), Vector2(-15, -22), Vector2(9, -22),
			])
			_poly_outlined(main_hull, shell_hi, od_col if has_overdrive else accent_col, 2.2)
			# Layered shoulder plates
			var sh_l: PackedVector2Array = PackedVector2Array([Vector2(13, -22), Vector2(13, -10), Vector2(-15, -10), Vector2(-19, -19)])
			var sh_r: PackedVector2Array = PackedVector2Array([Vector2(13, 10), Vector2(13, 22), Vector2(-19, 19), Vector2(-15, 10)])
			_poly_outlined(sh_l, trim, od_col if has_overdrive else outline, 1.6)
			_poly_outlined(sh_r, trim, od_col if has_overdrive else outline, 1.6)
			# Twin heavy gauntlet cannons
			draw_rect(Rect2(14, -15, 10, 5), deck, true)
			draw_rect(Rect2(14, 10, 10, 5), deck, true)
			# Central reactor core
			var core_poly: PackedVector2Array = PackedVector2Array([
				Vector2(12, 0), Vector2(5, -9), Vector2(-9, -9), Vector2(-13, 0), Vector2(-9, 9), Vector2(5, 9),
			])
			draw_colored_polygon(core_poly, deck)
			draw_circle(Vector2(0, 0), 6.2, accent_col)
			if has_overdrive:
				draw_arc(Vector2.ZERO, 16.5, 0.0, TAU, 24, Color(od_col.r, od_col.g, od_col.b, 0.65 + pulse * 0.35), 2.2, true)
				draw_line(Vector2(-13, -15), Vector2(11, -15), od_col, 2.2, true)
				draw_line(Vector2(-13, 15), Vector2(11, 15), od_col, 2.2, true)

		&"arc_lancer":
			# Tall slender tripod/strider elevated slightly so Colossus-stride reads immediately
			var arc_col: Color = Color(0.42, 0.98, 1.0, 1.0) if team == 0 else core
			# Long splayed strider legs (3 tripod struts)
			var leg_angles: PackedFloat32Array = PackedFloat32Array([-2.25, 2.25, PI])
			for a: float in leg_angles:
				var knee: Vector2 = Vector2.RIGHT.rotated(a) * 16.0
				var foot: Vector2 = Vector2.RIGHT.rotated(a) * 24.0
				draw_line(Vector2.ZERO, knee, trim, 3.4, true)
				draw_line(knee, foot, deck, 2.4, true)
				draw_circle(knee, 3.0, arc_col)
			# Elevated upper spire/capacitors
			var spire: PackedVector2Array = PackedVector2Array([
				Vector2(26, 0), Vector2(10, -9), Vector2(-6, -15),
				Vector2(-14, -10), Vector2(-9, 0), Vector2(-14, 10), Vector2(-6, 15), Vector2(10, 9),
			])
			_poly_outlined(spire, shell_hi, arc_col, 1.9)
			# Forward arc capacitor forks
			draw_line(Vector2(4, -7), Vector2(27, -4.5), trim, 3.0, true)
			draw_line(Vector2(4, 7), Vector2(27, 4.5), trim, 3.0, true)
			draw_line(Vector2(6, 0), Vector2(25, 0), Color(arc_col.r, arc_col.g, arc_col.b, 0.7 + pulse * 0.3), 2.4, true)
			draw_circle(Vector2(1.0, 0.0), 5.0, deck)
			draw_circle(Vector2(1.0, 0.0), 3.2 + pulse * 0.6, arc_col)

		&"chrysalis_mortar":
			# Wide low-slung artillery carapace with central dorsal mortar tube
			var acid_col: Color = Color(0.42, 1.0, 0.52, 1.0) if team == 0 else core_alt
			var carapace: PackedVector2Array = PackedVector2Array([
				Vector2(18, -9), Vector2(18, 9), Vector2(6, 20),
				Vector2(-13, 19), Vector2(-21, 9), Vector2(-21, -9), Vector2(-13, -19), Vector2(6, -20),
			])
			_poly_outlined(carapace, shell, acid_col, 1.8)
			# Stabilizer outriggers
			draw_colored_polygon(PackedVector2Array([Vector2(-6, -19), Vector2(4, -22), Vector2(6, -16), Vector2(-8, -15)]), trim)
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 19), Vector2(4, 22), Vector2(6, 16), Vector2(-8, 15)]), trim)
			# Mortar cradle & central dorsal tube
			draw_circle(Vector2(-2.0, 0.0), 11.5, deck)
			draw_rect(Rect2(-4, -5.5, 22, 11), trim, true)
			draw_rect(Rect2(-4, -5.5, 22, 11), acid_col, false, 1.4)
			draw_circle(Vector2(14.5, 0.0), 4.6, deck)
			draw_circle(Vector2(14.5, 0.0), 3.0, acid_col)
			draw_circle(Vector2(-6.0, 0.0), 4.4, acid_col)

		_:
			# Fallback crisp Y2K hull for legacy/dummy units
			var r: float = _owner_unit.data.collision_radius if (_owner_unit != null and _owner_unit.data != null) else 15.0
			var fallback_poly: PackedVector2Array = PackedVector2Array([
				Vector2(r, 0), Vector2(-r * 0.5, -r * 0.8), Vector2(-r * 0.8, 0), Vector2(-r * 0.5, r * 0.8),
			])
			_poly_outlined(fallback_poly, shell, outline, 1.6)
			draw_circle(Vector2.ZERO, r * 0.35, core)


# =============================================================================
# BUILDING SILHOUETTES & CONSTRUCTION BLUEPRINT FILL
# =============================================================================

func _draw_building_silhouette(p: Dictionary) -> void:
	if _owner_building == null:
		return
	var is_built: bool = _owner_building.is_constructed
	var progress: float = clampf(_owner_building.construction_progress, 0.0, 1.0)
	var hull_poly: PackedVector2Array = _get_building_outer_poly(entity_type_id, _owner_building.footprint_radius)

	if not is_built:
		_draw_building_blueprint(hull_poly, progress, p)
		return

	_draw_building_completed(hull_poly, p)


func _draw_building_blueprint(hull_poly: PackedVector2Array, progress: float, p: Dictionary) -> void:
	var wire: Color = p["wire"]
	var shell: Color = p["shell"]
	var deck: Color = p["deck"]
	var core: Color = p["core"]

	# Compute bounding box of hull for bottom-to-top fill
	var min_y: float = 9999.0
	var max_y: float = -9999.0
	var min_x: float = 9999.0
	var max_x: float = -9999.0
	for pt: Vector2 in hull_poly:
		min_y = minf(min_y, pt.y)
		max_y = maxf(max_y, pt.y)
		min_x = minf(min_x, pt.x)
		max_x = maxf(max_x, pt.x)

	# 1. Translucent holographic blueprint base & grid lines
	draw_colored_polygon(hull_poly, Color(wire.r, wire.g, wire.b, 0.11))
	var step: float = 12.0
	var gx: float = min_x + step
	while gx < max_x:
		draw_line(Vector2(gx, min_y + 4.0), Vector2(gx, max_y - 4.0), Color(wire.r, wire.g, wire.b, 0.16), 1.0)
		gx += step
	var gy: float = min_y + step
	while gy < max_y:
		draw_line(Vector2(min_x + 4.0, gy), Vector2(max_x - 4.0, gy), Color(wire.r, wire.g, wire.b, 0.16), 1.0)
		gy += step

	# 2. Progressive bottom-to-top clipped solid fill
	var fill_top_y: float = lerpf(max_y, min_y, progress)
	if progress > 0.01:
		var clip_rect: PackedVector2Array = PackedVector2Array([
			Vector2(min_x - 4.0, fill_top_y),
			Vector2(max_x + 4.0, fill_top_y),
			Vector2(max_x + 4.0, max_y + 4.0),
			Vector2(min_x - 4.0, max_y + 4.0),
		])
		var clipped_list: Array[PackedVector2Array] = Geometry2D.intersect_polygons(hull_poly, clip_rect)
		for part: PackedVector2Array in clipped_list:
			if part.size() >= 3:
				draw_colored_polygon(part, Color(shell.r, shell.g, shell.b, 0.68))
		# Inner dark deck clipped fill
		var inner_poly: PackedVector2Array = _scale_poly(hull_poly, 0.72)
		var inner_clips: Array[PackedVector2Array] = Geometry2D.intersect_polygons(inner_poly, clip_rect)
		for part_i: PackedVector2Array in inner_clips:
			if part_i.size() >= 3:
				draw_colored_polygon(part_i, Color(deck.r, deck.g, deck.b, 0.72))
		# Bright laser scanline along the rising build edge
		var scan_w: float = (max_x - min_x) * 0.48
		draw_line(Vector2(-scan_w, fill_top_y), Vector2(scan_w, fill_top_y), Color(core.r, core.g, core.b, 0.96), 2.4, true)

	# 3. Crisp wireframe outline & corner scaffolding pylons
	_draw_closed_outline(hull_poly, wire, 2.0)
	_draw_closed_outline(_scale_poly(hull_poly, 0.72), Color(wire.r, wire.g, wire.b, 0.45), 1.2)
	var corners: PackedVector2Array = PackedVector2Array([
		Vector2(min_x, min_y), Vector2(max_x, min_y), Vector2(max_x, max_y), Vector2(min_x, max_y),
	])
	for c: Vector2 in corners:
		var toward: Vector2 = -c.normalized() * 7.0
		draw_line(c, c + Vector2(toward.x, 0.0), wire, 2.0)
		draw_line(c, c + Vector2(0.0, toward.y), wire, 2.0)


func _draw_building_completed(hull_poly: PackedVector2Array, p: Dictionary) -> void:
	var shell: Color = p["shell"]
	var shell_hi: Color = p["shell_hi"]
	var deck: Color = p["deck"]
	var trim: Color = p["trim"]
	var core: Color = p["core"]
	var core_alt: Color = p["core_alt"]
	var outline: Color = p["outline"]
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 3.4)
	var is_training: bool = _owner_building.get_training_queue_size() > 0

	# Subtle Technozen circuit grounding pad under completed structures
	if SettingsManager == null or SettingsManager.battle_scars_enabled:
		var pad_poly: PackedVector2Array = _scale_poly(hull_poly, 1.18)
		draw_colored_polygon(pad_poly, Color(0.04, 0.07, 0.10, 0.42))
		_draw_closed_outline(pad_poly, Color(core.r, core.g, core.b, 0.20), 1.1)
		var pad_r: float = maxf(26.0, _owner_building.footprint_radius * 1.12)
		for ci: int in range(4):
			var c_ang: float = PI * 0.25 + float(ci) * (PI * 0.5)
			var c_dir: Vector2 = Vector2.RIGHT.rotated(c_ang)
			draw_line(c_dir * (pad_r * 0.86), c_dir * (pad_r * 1.06), Color(core.r, core.g, core.b, 0.26), 1.4, true)

	match entity_type_id:
		&"nexus_vat":
			# Wide octagonal Y2K server base with docking bays & central pulsing bioluminescent culture core
			_poly_outlined(hull_poly, shell_hi, outline, 2.4)
			var inner_oct: PackedVector2Array = _scale_poly(hull_poly, 0.76)
			draw_colored_polygon(inner_oct, deck)
			# 4 recessed docking bays
			draw_rect(Rect2(-40, -7, 13, 14), trim, true)
			draw_rect(Rect2(27, -7, 13, 14), trim, true)
			draw_rect(Rect2(-7, -40, 14, 13), trim, true)
			draw_rect(Rect2(-7, 27, 14, 13), trim, true)
			# Cross-conduits
			draw_line(Vector2(-34, 0), Vector2(34, 0), Color(core.r, core.g, core.b, 0.75), 3.0, true)
			draw_line(Vector2(0, -34), Vector2(0, 34), Color(core.r, core.g, core.b, 0.75), 3.0, true)
			# Central culture vat ring
			draw_circle(Vector2.ZERO, 19.0, Color(0.08, 0.14, 0.20, 1.0))
			draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 28, outline, 1.8, true)
			var core_r: float = 12.0 + pulse * 2.2
			draw_circle(Vector2.ZERO, core_r, core)
			draw_circle(Vector2.ZERO, core_r * 0.52, Color(0.88, 1.0, 0.98, 0.85))
			if is_training:
				draw_arc(Vector2.ZERO, 25.0, _anim_time * 2.2, _anim_time * 2.2 + PI * 1.1, 20, core_alt, 2.2, true)

		&"synapse_pylon":
			# Tall diamond/needle spire with orbiting signal ring
			var py_col: Color = Color(0.76, 0.58, 1.0, 1.0) if team == 0 else core
			_poly_outlined(hull_poly, shell_hi, py_col, 2.0)
			# Inner diamond spire
			var diamond: PackedVector2Array = PackedVector2Array([
				Vector2(0, -24), Vector2(13, 0), Vector2(0, 24), Vector2(-13, 0),
			])
			_poly_outlined(diamond, deck, py_col, 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -13), Vector2(7, 0), Vector2(0, 13), Vector2(-7, 0)]), py_col)
			# Orbiting signal ring + node
			draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 28, Color(py_col.r, py_col.g, py_col.b, 0.42), 1.4, true)
			var orb_a: float = _anim_time * 2.1
			var orb_pt: Vector2 = Vector2.RIGHT.rotated(orb_a) * 21.0
			draw_circle(orb_pt, 3.2, py_col)
			draw_circle(-orb_pt, 2.4, Color(py_col.r, py_col.g, py_col.b, 0.72))

		&"silica_condenser":
			# Dual-tank geometric extractor with crystalline prism accents
			var sil_col: Color = Color(0.98, 0.78, 0.28, 1.0) if team == 0 else core_alt
			_poly_outlined(hull_poly, shell, sil_col, 2.2)
			draw_colored_polygon(_scale_poly(hull_poly, 0.74), deck)
			# Dual geometric tanks
			draw_rect(Rect2(-24, -15, 18, 30), trim, true)
			draw_rect(Rect2(6, -15, 18, 30), trim, true)
			draw_rect(Rect2(-21, -12, 12, 24), Color(sil_col.r, sil_col.g, sil_col.b, 0.85), true)
			draw_rect(Rect2(9, -12, 12, 24), Color(sil_col.r, sil_col.g, sil_col.b, 0.65 + pulse * 0.3), true)
			# Crystalline prism accent at center
			var prism: PackedVector2Array = PackedVector2Array([
				Vector2(0, -12), Vector2(7, 0), Vector2(0, 12), Vector2(-7, 0),
			])
			_poly_outlined(prism, Color(1.0, 0.94, 0.68, 0.95) if team == 0 else core, sil_col, 1.5)

		&"wetware_mainframe":
			# Brutalist server monolith with glowing neural-grid circuit lines & staffing indicator pips
			var cmp_col: Color = Color(0.28, 0.88, 1.0, 1.0) if team == 0 else core
			_poly_outlined(hull_poly, shell_hi, cmp_col, 2.2)
			draw_rect(Rect2(-24, -24, 48, 48), deck, true)
			# Neural-grid circuit lines
			var staffed: int = _owner_building.get_assigned_engineer_count()
			var grid_alpha: float = 0.32 if staffed == 0 else (0.58 + pulse * 0.38)
			var g_col: Color = Color(cmp_col.r, cmp_col.g, cmp_col.b, grid_alpha)
			for gx: float in [-16.0, -6.0, 6.0, 16.0]:
				draw_line(Vector2(gx, -21), Vector2(gx, 14), g_col, 1.6)
			for gy: float in [-16.0, -4.0, 8.0]:
				draw_line(Vector2(-21, gy), Vector2(21, gy), g_col, 1.6)
			# Central compute processor diamond
			var cpu: PackedVector2Array = PackedVector2Array([
				Vector2(0, -11), Vector2(11, 0), Vector2(0, 11), Vector2(-11, 0),
			])
			draw_colored_polygon(cpu, Color(cmp_col.r, cmp_col.g, cmp_col.b, 0.45 + float(staffed) * 0.25))
			# Crisp staffing indicator pips (0/2, 1/2, 2/2)
			var slots: int = maxi(1, _owner_building.max_staff_slots)
			for s: int in range(slots):
				var px: float = (float(s) - float(slots - 1) * 0.5) * 16.0
				var pip_rect: Rect2 = Rect2(px - 5.5, 16.5, 11.0, 6.0)
				var filled: bool = s < staffed
				draw_rect(pip_rect, cmp_col if filled else Color(0.14, 0.20, 0.26, 0.95), true)
				draw_rect(pip_rect, cmp_col, false, 1.2)

		&"cloning_vat":
			# Twin-chambered translucent bio-tank with animated dual-pulse indicators while training
			var vat_col: Color = Color(0.22, 0.96, 0.76, 1.0) if team == 0 else core
			_poly_outlined(hull_poly, shell_hi, vat_col, 2.4)
			draw_colored_polygon(_scale_poly(hull_poly, 0.76), deck)
			# Twin translucent bio-chambers
			var chamber_l: Rect2 = Rect2(-26, -20, 20, 40)
			var chamber_r: Rect2 = Rect2(6, -20, 20, 40)
			var glow_a: float = (0.62 + pulse * 0.36) if is_training else 0.72
			draw_rect(chamber_l, Color(vat_col.r, vat_col.g, vat_col.b, glow_a * 0.75), true)
			draw_rect(chamber_r, Color(vat_col.r, vat_col.g, vat_col.b, glow_a * 0.75), true)
			draw_rect(chamber_l, shell_hi, false, 1.6)
			draw_rect(chamber_r, shell_hi, false, 1.6)
			# Inner vat spine bridge
			draw_rect(Rect2(-6, -10, 12, 20), trim, true)
			if is_training:
				var wave_y: float = lerpf(16.0, -16.0, fmod(_anim_time * 1.4, 1.0))
				draw_line(Vector2(-24, wave_y), Vector2(-8, wave_y), Color(0.92, 1.0, 0.96, 0.95), 2.4)
				draw_line(Vector2(8, -wave_y), Vector2(24, -wave_y), Color(0.92, 1.0, 0.96, 0.95), 2.4)
				draw_circle(Vector2(-16, 0), 4.0 + pulse * 2.5, Color(0.9, 1.0, 0.96, 0.45))
				draw_circle(Vector2(16, 0), 4.0 + pulse * 2.5, Color(0.9, 1.0, 0.96, 0.45))
			else:
				draw_circle(Vector2(-16, 0), 4.5, Color(0.86, 1.0, 0.95, 0.55))
				draw_circle(Vector2(16, 0), 4.5, Color(0.86, 1.0, 0.95, 0.55))

		&"calibration_foundry":
			# Angular industrial chassis bay with gantry arms
			var fnd_col: Color = Color(0.98, 0.68, 0.26, 1.0) if team == 0 else core_alt
			_poly_outlined(hull_poly, shell, fnd_col, 2.4)
			draw_colored_polygon(_scale_poly(hull_poly, 0.76), deck)
			# Twin industrial gantry rails
			draw_rect(Rect2(-27, -28, 9, 56), trim, true)
			draw_rect(Rect2(18, -28, 9, 56), trim, true)
			# Articulated cross-gantry bridge (slides gently when training)
			var bridge_y: float = sin(_anim_time * 2.4) * 10.0 if is_training else 0.0
			draw_rect(Rect2(-26, bridge_y - 4, 52, 8), shell_hi, true)
			draw_rect(Rect2(-11, -13, 22, 26), Color(fnd_col.r, fnd_col.g, fnd_col.b, 0.85), true)
			draw_rect(Rect2(-11, -13, 22, 26), shell_hi, false, 1.5)

		&"synthetics_fabricator":
			# Heavy reinforced mega-bay with glowing high-Compute capacitor coils
			var fab_col: Color = Color(0.32, 0.96, 1.0, 1.0) if team == 0 else core
			_poly_outlined(hull_poly, shell_hi, fab_col, 2.6)
			draw_colored_polygon(_scale_poly(hull_poly, 0.78), deck)
			# 4 corner high-Compute capacitor coils
			var coil_pts: PackedVector2Array = PackedVector2Array([
				Vector2(-26, -26), Vector2(26, -26), Vector2(26, 26), Vector2(-26, 26),
			])
			for cp: Vector2 in coil_pts:
				draw_circle(cp, 8.5, trim)
				draw_circle(cp, 5.0 + pulse * 1.2, fab_col)
				draw_line(cp, cp.normalized() * 14.0, Color(fab_col.r, fab_col.g, fab_col.b, 0.75), 2.0, true)
			# Central mega-bay assembly ring
			draw_circle(Vector2.ZERO, 20.0, Color(0.08, 0.16, 0.24, 1.0))
			draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, fab_col, 2.2, true)
			var spin: float = _anim_time * (2.6 if is_training else 0.9)
			draw_arc(Vector2.ZERO, 13.5, spin, spin + PI * 0.75, 16, Color(0.92, 1.0, 1.0, 0.9), 2.4, true)
			draw_arc(Vector2.ZERO, 13.5, spin + PI, spin + PI * 1.75, 16, Color(0.92, 1.0, 1.0, 0.9), 2.4, true)
			draw_circle(Vector2.ZERO, 6.8 + pulse * 1.4, fab_col)

		&"defense_turret":
			# Armored Sentry Pylon bastion base with corner stabilizer lugs & turret ring
			var tur_col: Color = Color(0.28, 0.96, 0.92, 1.0) if team == 0 else core
			_poly_outlined(hull_poly, shell_hi, tur_col, 2.2)
			draw_colored_polygon(_scale_poly(hull_poly, 0.72), deck)
			# 4 armored corner anchor lugs
			for lug: Vector2 in [Vector2(-19, -19), Vector2(19, -19), Vector2(19, 19), Vector2(-19, 19)]:
				draw_circle(lug, 4.2, trim)
				draw_circle(lug, 1.8, tur_col)
			# Turret bearing ring
			draw_circle(Vector2.ZERO, 14.5, Color(0.08, 0.14, 0.20, 1.0))
			draw_arc(Vector2.ZERO, 14.5, 0.0, TAU, 24, Color(tur_col.r, tur_col.g, tur_col.b, 0.65 + pulse * 0.25), 1.8, true)

		_:
			_poly_outlined(hull_poly, shell, outline, 2.2)
			draw_colored_polygon(_scale_poly(hull_poly, 0.65), deck)
			draw_circle(Vector2.ZERO, _owner_building.footprint_radius * 0.32, core)

	if _owner_building.has_turret:
		_draw_building_turret_overlay(p)

	_draw_hub_saturation_badge()


func _draw_hub_saturation_badge() -> void:
	if _owner_building == null or not is_instance_valid(_owner_building) or not _owner_building.is_constructed or _owner_building.is_destroyed:
		return
	var is_hub: bool = _owner_building.is_core_hub or entity_type_id == &"nexus_vat" or entity_type_id == &"silica_condenser"
	if not is_hub:
		return
	var is_local: bool = TeamManager.is_team_controlled_by_local_human(int(_owner_building.team)) if TeamManager != null else (_owner_building.team == Unit.Team.PLAYER)
	if not is_local:
		return

	var should_show: bool = _owner_building.is_selected
	if not should_show and _owner_building.is_inside_tree():
		var mouse_world: Vector2 = _owner_building.get_global_mouse_position()
		var hover_r: float = _owner_building.selection_radius + 8.0
		if _owner_building.global_position.distance_squared_to(mouse_world) <= hover_r * hover_r:
			should_show = true
	if not should_show and _owner_building.is_inside_tree():
		var want_res: StringName = &"silica" if entity_type_id == &"silica_condenser" else &"biomass"
		var sel: Node = _owner_building.get_tree().get_first_node_in_group("selection_controller")
		if sel != null:
			var sel_units: Variant = sel.get("selected_units")
			if sel_units is Array:
				for item: Variant in (sel_units as Array):
					if is_instance_valid(item) and item is Unit and (item as Unit).can_gather_resource(want_res):
						should_show = true
						break
	if not should_show:
		return

	var sat: Dictionary = _owner_building.get_cluster_saturation()
	if not bool(sat.get("has_nodes", false)):
		return
	var assigned: int = int(sat.get("assigned", 0))
	var cap: int = maxi(1, int(sat.get("capacity", 0)))
	var text_str: String = "%d/%d" % [assigned, cap]
	var col: Color = ResourceNode.get_saturation_color(assigned, cap)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var txt_sz: Vector2 = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pill_w: float = txt_sz.x + 14.0
	var pill_h: float = 17.0
	var pill_pos: Vector2 = Vector2(-pill_w * 0.5, -_owner_building.footprint_radius - pill_h - 14.0)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.03, 0.06, 0.10, 0.88), true)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(col.r, col.g, col.b, 0.90), false, 1.3)
	draw_string(font, pill_pos + Vector2(7.0, pill_h - 4.0), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_building_turret_overlay(p: Dictionary) -> void:
	if _owner_building == null or not _owner_building.is_constructed:
		return
	var shell_hi: Color = p["shell_hi"]
	var deck: Color = p["deck"]
	var trim: Color = p["trim"]
	var core: Color = p["core"]
	var core_alt: Color = p["core_alt"]
	var ang: float = _owner_building.get_turret_angle()
	var recoil: float = _owner_building.get_turret_recoil()
	var dir: Vector2 = Vector2.RIGHT.rotated(ang)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var style: StringName = _owner_building.turret_tracer_style
	var accent: Color = Color(1.0, 0.82, 0.32, 1.0) if (style == &"rail" and team == 0) else core
	if style == &"mortar" and team == 0:
		accent = core_alt

	# Rotating armored turret housing
	var base_pts: PackedVector2Array = PackedVector2Array([
		dir * 12.0 + perp * -6.5,
		dir * 12.0 + perp * 6.5,
		dir * -8.0 + perp * 9.5,
		dir * -12.0 + perp * 4.5,
		dir * -12.0 + perp * -4.5,
		dir * -8.0 + perp * -9.5,
	])
	_poly_outlined(base_pts, shell_hi, accent, 1.6)

	# Barrel assembly (slides back slightly with recoil kick)
	var b_start: Vector2 = dir * (6.0 - recoil)
	var b_end: Vector2 = dir * (26.0 - recoil)
	if style == &"heavy":
		draw_line(b_start + perp * -4.0, b_end + perp * -4.0, deck, 4.2, true)
		draw_line(b_start + perp * 4.0, b_end + perp * 4.0, deck, 4.2, true)
		draw_line(b_start + perp * -4.0, b_end + perp * -4.0, accent, 1.6, true)
		draw_line(b_start + perp * 4.0, b_end + perp * 4.0, accent, 1.6, true)
	elif style == &"mortar":
		draw_line(b_start, dir * (21.0 - recoil), trim, 9.0, true)
		draw_circle(dir * (20.0 - recoil), 4.2, deck)
		draw_circle(dir * (20.0 - recoil), 2.4, accent)
	else:
		# Rail / Pulse twin-rail barrel with glowing central emitter channel
		draw_line(b_start + perp * -3.2, b_end + perp * -2.6, trim, 2.8, true)
		draw_line(b_start + perp * 3.2, b_end + perp * 2.6, trim, 2.8, true)
		draw_line(dir * (4.0 - recoil), dir * (27.5 - recoil), accent, 2.2, true)

	# Central sensor dome
	draw_circle(Vector2.ZERO, 6.2, deck)
	draw_circle(dir * 1.5, 3.2, accent)


func _get_building_outer_poly(type_id: StringName, radius: float) -> PackedVector2Array:
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
			# Clean Y2K chamfered octagon
			var c: float = r * 0.42
			var e: float = r * 0.96
			return PackedVector2Array([
				Vector2(e, -c), Vector2(e, c), Vector2(c, e), Vector2(-c, e),
				Vector2(-e, c), Vector2(-e, -c), Vector2(-c, -e), Vector2(c, -e),
			])


func _scale_poly(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(poly.size())
	for i: int in range(poly.size()):
		out[i] = poly[i] * factor
	return out


func _poly_outlined(poly: PackedVector2Array, fill_col: Color, outline_col: Color, width: float) -> void:
	draw_colored_polygon(poly, fill_col)
	_draw_closed_outline(poly, outline_col, width)


func _draw_closed_outline(poly: PackedVector2Array, outline_col: Color, width: float) -> void:
	if poly.size() < 2:
		return
	var pts: PackedVector2Array = poly.duplicate()
	pts.append(poly[0])
	draw_polyline(pts, outline_col, width, true)
