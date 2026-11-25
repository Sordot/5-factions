class_name EntityVisuals
extends Node2D

## Procedural Technozen / Y2K silhouette renderer for GENESIS_V2 units and structures.
## Attached as a child of a Unit's BodyVisual (inherits rotation & hit-flash modulate)
## or directly inside a Building's BodyVisual (handles blueprint wireframe & progressive fill).

enum Mode {
	UNIT,
	BUILDING,
}

const MONO_INK: Color = Color(0.04, 0.05, 0.07, 0.96)
const MONO_SHADOW: Color = Color(0.04, 0.05, 0.07, 0.85)
const MONO_CONCRETE_DARK: Color = Color(0.169, 0.180, 0.200, 0.98) # #2B2E33
const MONO_CONCRETE_MID: Color = Color(0.227, 0.243, 0.271, 0.98)  # #3A3E45
const MONO_OFFWHITE: Color = Color(0.949, 0.937, 0.914, 0.98)      # #F2EFE9
const MONO_AMBER: Color = Color(1.0, 0.624, 0.110, 1.0)            # #FF9F1C
const MONO_SHIELD_CYAN: Color = Color(0.220, 0.741, 0.973, 1.0)    # #38BDF8

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
		# Redraw animated units (pulses, overdrive, adrenal flashes, striders, hover & spawn anim)
		if (
			_owner_unit.is_hovered
			or _owner_unit.spawn_anim_timer > 0.0
			or entity_type_id == &"symbiote"
			or entity_type_id == &"signal_jammer"
			or entity_type_id == &"arc_lancer"
			or entity_type_id == &"goliath_frame"
			or entity_type_id == &"clone_trooper"
			or entity_type_id == &"aegis_relay"
			or entity_type_id == &"monolith_dreadnought"
			or entity_type_id == &"null_grid_projector"
			or entity_type_id == &"anvil_siege_walker"
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
	_draw_hover_ring()
	_draw_marquee_preview_ring()
	if mode == Mode.UNIT:
		_draw_unit_silhouette(p)
		_draw_unit_spawn_flash(p)
	else:
		_draw_building_silhouette(p)


func _get_zoom_invariant_width(base_px: float) -> float:
	if is_inside_tree():
		var cam: Camera2D = get_viewport().get_camera_2d()
		if cam != null:
			return base_px / maxf(0.25, cam.zoom.x)
	return base_px


func _is_entity_hostile(entity_team: int) -> bool:
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	if viewer < 0:
		return false
	if TeamManager != null:
		return TeamManager.are_enemies(viewer, entity_team)
	return entity_team != int(Unit.Team.PLAYER)


func _draw_hover_ring() -> void:
	var pulse_a: float = 0.86 + 0.14 * sin(_anim_time * 5.2)
	var line_w: float = _get_zoom_invariant_width(1.4)
	if mode == Mode.UNIT:
		if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.is_dead:
			return
		if not _owner_unit.is_hovered or _owner_unit.is_marquee_highlighted:
			return
		var is_hostile: bool = _is_entity_hostile(int(_owner_unit.team))
		var base_col: Color = Color(1.0, 0.302, 0.427, 0.65) if is_hostile else Color(0.220, 0.741, 0.973, 0.55)
		var r: float = _owner_unit.get_selection_radius() + (4.5 if _owner_unit.is_selected else 1.5)
		var alpha: float = (base_col.a * 0.58 if _owner_unit.is_selected else base_col.a) * pulse_a
		if not _owner_unit.is_selected:
			draw_circle(Vector2.ZERO, r, Color(base_col.r, base_col.g, base_col.b, 0.08 * pulse_a))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(base_col.r, base_col.g, base_col.b, alpha), line_w, true)
	else:
		if _owner_building == null or not is_instance_valid(_owner_building) or _owner_building.is_destroyed:
			return
		if not _owner_building.is_hovered or _owner_building.is_marquee_highlighted:
			return
		var is_hostile_b: bool = _is_entity_hostile(int(_owner_building.team))
		var base_col_b: Color = Color(1.0, 0.302, 0.427, 0.65) if is_hostile_b else Color(0.220, 0.741, 0.973, 0.55)
		var r_b: float = maxf(_owner_building.selection_radius, _owner_building.footprint_radius + 6.0) + (5.0 if _owner_building.is_selected else 0.0)
		var alpha_b: float = (base_col_b.a * 0.58 if _owner_building.is_selected else base_col_b.a) * pulse_a
		if not _owner_building.is_selected:
			draw_circle(Vector2.ZERO, r_b, Color(base_col_b.r, base_col_b.g, base_col_b.b, 0.07 * pulse_a))
		draw_arc(Vector2.ZERO, r_b, 0.0, TAU, 36, Color(base_col_b.r, base_col_b.g, base_col_b.b, alpha_b), line_w, true)


func _draw_unit_spawn_flash(p: Dictionary) -> void:
	if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.spawn_anim_timer <= 0.0:
		return
	var frac: float = clampf(_owner_unit.spawn_anim_timer / Unit.SPAWN_ANIM_DURATION, 0.0, 1.0)
	var base_r: float = _owner_unit.data.collision_radius if _owner_unit.data != null else 15.0
	var rim_r: float = base_r * lerpf(1.38, 0.92, frac)
	var flash_col: Color = p["core"] if team != 0 else Color(0.24, 0.98, 0.88, 1.0)
	draw_circle(Vector2.ZERO, base_r * 1.05, Color(flash_col.r, flash_col.g, flash_col.b, frac * 0.34))
	draw_arc(Vector2.ZERO, rim_r, 0.0, TAU, 24, Color(0.86, 1.0, 0.98, frac * 0.85), 2.4 * frac + 0.8, true)


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
	if _is_monolith_unit(entity_type_id):
		_draw_monolith_unit_silhouette(p)
		return
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
	var active_pulse: float = 0.5 + 0.5 * sin(_anim_time * TAU * 2.2)
	var is_training: bool = _owner_building.get_training_queue_size() > 0
	var is_active_prod: bool = _owner_building.is_actively_producing()
	var standby_slate: Color = Color(0.28, 0.42, 0.50, 0.72)

	if _is_monolith_building(entity_type_id):
		_draw_monolith_building_completed(hull_poly, p)
		if _owner_building.has_turret:
			_draw_building_turret_overlay(p)
		if _owner_building.completion_flash_timer > 0.0:
			var cf_m: float = clampf(_owner_building.completion_flash_timer / Building.COMPLETION_FLASH_DURATION, 0.0, 1.0)
			_draw_closed_outline(_scale_poly(hull_poly, 1.0 + (1.0 - cf_m) * 0.10), Color(1.0, 0.72, 0.22, cf_m * 0.95), 3.0)
		_draw_hub_saturation_badge()
		return

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
			var mf_border: Color = cmp_col if is_active_prod else standby_slate.lerp(cmp_col, 0.45)
			_poly_outlined(hull_poly, shell_hi, mf_border, 2.2)
			draw_rect(Rect2(-24, -24, 48, 48), deck, true)
			# Neural-grid circuit lines (cool dimmed standby when idle, 2.2Hz glowing pulse when active)
			var staffed: int = _owner_building.get_assigned_engineer_count()
			var g_col: Color = Color(cmp_col.r, cmp_col.g, cmp_col.b, 0.62 + active_pulse * 0.36) if is_active_prod else Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42)
			for gx: float in [-16.0, -6.0, 6.0, 16.0]:
				draw_line(Vector2(gx, -21), Vector2(gx, 14), g_col, 1.8 if is_active_prod else 1.4)
			for gy: float in [-16.0, -4.0, 8.0]:
				draw_line(Vector2(-21, gy), Vector2(21, gy), g_col, 1.8 if is_active_prod else 1.4)
			# Central compute processor diamond
			var cpu: PackedVector2Array = PackedVector2Array([
				Vector2(0, -11), Vector2(11, 0), Vector2(0, 11), Vector2(-11, 0),
			])
			if is_active_prod:
				draw_colored_polygon(cpu, Color(cmp_col.r, cmp_col.g, cmp_col.b, 0.68 + active_pulse * 0.30))
				draw_circle(Vector2.ZERO, 4.0 + active_pulse * 1.4, Color(0.90, 1.0, 1.0, 0.82))
				_draw_active_conduit_sparks(cmp_col, 22.0)
			else:
				draw_colored_polygon(cpu, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.45))
			# Crisp staffing indicator pips (0/2, 1/2, 2/2)
			var slots: int = maxi(1, _owner_building.max_staff_slots)
			for s: int in range(slots):
				var px: float = (float(s) - float(slots - 1) * 0.5) * 16.0
				var pip_rect: Rect2 = Rect2(px - 5.5, 16.5, 11.0, 6.0)
				var filled: bool = s < staffed
				draw_rect(pip_rect, cmp_col if filled else Color(0.14, 0.20, 0.26, 0.95), true)
				draw_rect(pip_rect, mf_border, false, 1.2)

		&"cloning_vat":
			# Twin-chambered translucent bio-tank: unmistakable active pulse + rising sparks vs cool dimmed standby
			var vat_col: Color = Color(0.22, 0.96, 0.76, 1.0) if team == 0 else core
			var vat_border: Color = vat_col if is_active_prod else standby_slate.lerp(vat_col, 0.45)
			_poly_outlined(hull_poly, shell_hi, vat_border, 2.4)
			draw_colored_polygon(_scale_poly(hull_poly, 0.76), deck)
			# Twin translucent bio-chambers
			var chamber_l: Rect2 = Rect2(-26, -20, 20, 40)
			var chamber_r: Rect2 = Rect2(6, -20, 20, 40)
			if is_active_prod:
				var glow_a: float = 0.62 + active_pulse * 0.36
				draw_rect(chamber_l, Color(vat_col.r, vat_col.g, vat_col.b, glow_a * 0.82), true)
				draw_rect(chamber_r, Color(vat_col.r, vat_col.g, vat_col.b, glow_a * 0.82), true)
				draw_rect(chamber_l, shell_hi, false, 1.6)
				draw_rect(chamber_r, shell_hi, false, 1.6)
				draw_rect(Rect2(-6, -10, 12, 20), trim, true)
				draw_line(Vector2(-6, 0), Vector2(6, 0), Color(0.88, 1.0, 0.96, 0.65 + active_pulse * 0.35), 2.4, true)
				var wave_y: float = lerpf(16.0, -16.0, fmod(_anim_time * 1.5, 1.0))
				draw_line(Vector2(-24, wave_y), Vector2(-8, wave_y), Color(0.92, 1.0, 0.96, 0.95), 2.4)
				draw_line(Vector2(8, -wave_y), Vector2(24, -wave_y), Color(0.92, 1.0, 0.96, 0.95), 2.4)
				draw_circle(Vector2(-16, 0), 4.2 + active_pulse * 2.4, Color(0.9, 1.0, 0.96, 0.52))
				draw_circle(Vector2(16, 0), 4.2 + active_pulse * 2.4, Color(0.9, 1.0, 0.96, 0.52))
				_draw_active_conduit_sparks(vat_col, 24.0)
			else:
				var idle_tank: Color = standby_slate.lerp(vat_col, 0.25)
				draw_rect(chamber_l, Color(idle_tank.r, idle_tank.g, idle_tank.b, 0.44), true)
				draw_rect(chamber_r, Color(idle_tank.r, idle_tank.g, idle_tank.b, 0.44), true)
				draw_rect(chamber_l, Color(trim.r, trim.g, trim.b, 0.72), false, 1.4)
				draw_rect(chamber_r, Color(trim.r, trim.g, trim.b, 0.72), false, 1.4)
				draw_rect(Rect2(-6, -10, 12, 20), trim, true)
				draw_circle(Vector2(-16, 0), 3.6, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42))
				draw_circle(Vector2(16, 0), 3.6, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42))

		&"calibration_foundry":
			# Angular industrial chassis bay with gantry arms (glowing forged bay + sparks when active vs dim standby)
			var fnd_col: Color = Color(0.98, 0.68, 0.26, 1.0) if team == 0 else core_alt
			var fnd_border: Color = fnd_col if is_active_prod else standby_slate.lerp(fnd_col, 0.45)
			_poly_outlined(hull_poly, shell, fnd_border, 2.4)
			draw_colored_polygon(_scale_poly(hull_poly, 0.76), deck)
			# Twin industrial gantry rails
			draw_rect(Rect2(-27, -28, 9, 56), trim, true)
			draw_rect(Rect2(18, -28, 9, 56), trim, true)
			if is_active_prod:
				var bridge_y: float = sin(_anim_time * 2.6) * 10.0
				draw_line(Vector2(-22.5, -24), Vector2(-22.5, 24), Color(fnd_col.r, fnd_col.g, fnd_col.b, 0.55 + active_pulse * 0.42), 2.2, true)
				draw_line(Vector2(22.5, -24), Vector2(22.5, 24), Color(fnd_col.r, fnd_col.g, fnd_col.b, 0.55 + active_pulse * 0.42), 2.2, true)
				draw_rect(Rect2(-26, bridge_y - 4, 52, 8), shell_hi, true)
				draw_rect(Rect2(-11, -13, 22, 26), Color(fnd_col.r, fnd_col.g, fnd_col.b, 0.74 + active_pulse * 0.26), true)
				draw_rect(Rect2(-11, -13, 22, 26), Color(1.0, 0.96, 0.84, 0.92), false, 1.6)
				draw_circle(Vector2(0.0, bridge_y), 3.6 + active_pulse * 1.4, Color(1.0, 0.95, 0.80, 0.88))
				_draw_active_conduit_sparks(fnd_col, 24.0)
			else:
				var idle_bay: Color = standby_slate.lerp(fnd_col, 0.22)
				draw_rect(Rect2(-26, -4, 52, 8), Color(trim.r, trim.g, trim.b, 0.85), true)
				draw_rect(Rect2(-11, -13, 22, 26), Color(idle_bay.r, idle_bay.g, idle_bay.b, 0.45), true)
				draw_rect(Rect2(-11, -13, 22, 26), Color(trim.r, trim.g, trim.b, 0.72), false, 1.3)

		&"synthetics_fabricator":
			# Heavy reinforced mega-bay with glowing high-Compute capacitor coils
			var fab_col: Color = Color(0.32, 0.96, 1.0, 1.0) if team == 0 else core
			var fab_border: Color = fab_col if is_active_prod else standby_slate.lerp(fab_col, 0.45)
			_poly_outlined(hull_poly, shell_hi, fab_border, 2.6)
			draw_colored_polygon(_scale_poly(hull_poly, 0.78), deck)
			# 4 corner high-Compute capacitor coils
			var coil_pts: PackedVector2Array = PackedVector2Array([
				Vector2(-26, -26), Vector2(26, -26), Vector2(26, 26), Vector2(-26, 26),
			])
			for cp: Vector2 in coil_pts:
				draw_circle(cp, 8.5, trim)
				if is_active_prod:
					draw_circle(cp, 5.2 + active_pulse * 1.6, fab_col)
					draw_line(cp, cp.normalized() * 14.0, Color(fab_col.r, fab_col.g, fab_col.b, 0.65 + active_pulse * 0.35), 2.4, true)
				else:
					draw_circle(cp, 4.4, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.48))
					draw_line(cp, cp.normalized() * 14.0, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.38), 1.6, true)
			# Central mega-bay assembly ring
			draw_circle(Vector2.ZERO, 20.0, Color(0.08, 0.16, 0.24, 1.0))
			if is_active_prod:
				draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, fab_col, 2.4, true)
				var spin: float = _anim_time * 3.0
				draw_arc(Vector2.ZERO, 13.5, spin, spin + PI * 0.75, 16, Color(0.92, 1.0, 1.0, 0.94), 2.5, true)
				draw_arc(Vector2.ZERO, 13.5, spin + PI, spin + PI * 1.75, 16, Color(0.92, 1.0, 1.0, 0.94), 2.5, true)
				draw_circle(Vector2.ZERO, 6.8 + active_pulse * 2.0, fab_col)
				draw_circle(Vector2.ZERO, 3.6, Color(0.94, 1.0, 1.0, 0.90))
				_draw_active_conduit_sparks(fab_col, 28.0)
			else:
				draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.52), 1.8, true)
				draw_arc(Vector2.ZERO, 13.5, 0.4, 0.4 + PI * 0.75, 16, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42), 1.8, true)
				draw_arc(Vector2.ZERO, 13.5, 0.4 + PI, 0.4 + PI * 1.75, 16, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.42), 1.8, true)
				draw_circle(Vector2.ZERO, 5.4, Color(standby_slate.r, standby_slate.g, standby_slate.b, 0.45))

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

	if _owner_building.completion_flash_timer > 0.0:
		var cf: float = clampf(_owner_building.completion_flash_timer / Building.COMPLETION_FLASH_DURATION, 0.0, 1.0)
		_draw_closed_outline(_scale_poly(hull_poly, 1.0 + (1.0 - cf) * 0.10), Color(0.90, 1.0, 0.98, cf * 0.95), 3.0)

	_draw_hub_saturation_badge()


func _draw_active_conduit_sparks(col: Color, spread_r: float) -> void:
	# Lightweight rising vector telemetry sparks (zero particle nodes)
	for i: int in range(4):
		var phase: float = fmod(_anim_time * 0.95 + float(i) * 0.25, 1.0)
		var fade: float = sin(phase * PI)
		if fade <= 0.05:
			continue
		var lane_x: float = (float(i) - 1.5) * (spread_r * 0.56) + sin(_anim_time * 3.0 + float(i) * 1.9) * 2.5
		var y_pos: float = lerpf(spread_r * 0.45, -spread_r * 0.85, phase)
		var spark_col: Color = Color(col.r, col.g, col.b, fade * 0.85)
		draw_circle(Vector2(lane_x, y_pos), 1.8 * fade + 0.6, spark_col)
		draw_line(Vector2(lane_x, y_pos + 1.5), Vector2(lane_x, y_pos + 5.5 * fade), Color(0.92, 1.0, 0.98, fade * 0.62), 1.1, true)


func _draw_hub_saturation_badge() -> void:
	if _owner_building == null or not is_instance_valid(_owner_building) or not _owner_building.is_constructed or _owner_building.is_destroyed:
		return
	var is_silica_dropoff: bool = entity_type_id == &"silica_condenser" or (not _owner_building.is_command_hub() and _owner_building.is_resource_dropoff and _owner_building.accepts_resource(&"silica"))
	var is_hub: bool = _owner_building.is_command_hub() or is_silica_dropoff
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
		var want_res: StringName = &"silica" if is_silica_dropoff else &"biomass"
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

	if style == &"heavy_slug":
		# MONOLITH_OS Bastion Emplacement heavy brutalist AP turret housing + twin pneumatic barrels
		var mono_ink: Color = Color(0.05, 0.06, 0.08, 0.96)
		var mono_slab: Color = Color(0.24, 0.27, 0.31, 0.98)
		var mono_amber: Color = Color(1.0, 0.624, 0.110, 1.0)
		var mono_white: Color = Color(0.95, 0.94, 0.91, 0.96)
		var team_col: Color = TeamManager.get_team_color(team) if TeamManager != null else core
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
		# Hard offset drop shadow
		var shadow_base: PackedVector2Array = PackedVector2Array()
		for pt_b: Vector2 in mono_base:
			shadow_base.append(pt_b + Vector2(2.5, 2.5))
		draw_colored_polygon(shadow_base, Color(0.04, 0.05, 0.07, 0.80))
		_poly_outlined(mono_base, mono_slab, mono_ink, 2.2)
		# Heavy twin AP cannon barrels
		var bs_m: Vector2 = dir * (8.0 - recoil)
		var be_m: Vector2 = dir * (28.0 - recoil)
		draw_line(bs_m + perp * -4.2, be_m + perp * -4.2, mono_ink, 6.2, true)
		draw_line(bs_m + perp * 4.2, be_m + perp * 4.2, mono_ink, 6.2, true)
		draw_line(bs_m + perp * -4.2, be_m + perp * -4.2, mono_white, 2.8, true)
		draw_line(bs_m + perp * 4.2, be_m + perp * 4.2, mono_white, 2.8, true)
		# Muzzle brake collars
		draw_line(dir * (24.0 - recoil) + perp * -6.5, dir * (24.0 - recoil) + perp * 6.5, mono_amber, 2.6, true)
		# Team-color dorsal stripe + amber optic slit
		draw_line(dir * -9.0 + perp * -7.0, dir * -9.0 + perp * 7.0, team_col, 3.0, true)
		draw_line(dir * 5.0 + perp * -5.0, dir * 5.0 + perp * 5.0, mono_amber, 2.2, true)
		return

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
		&"foundry_core", &"capacitor_pylon", &"silica_smelter", &"logic_monolith", &"assembly_bay", &"ballistics_lab", &"bastion_emplacement", &"siege_gantry":
			var e_m: float = r * 0.96
			var ch_m: float = r * 0.24
			return PackedVector2Array([
				Vector2(-e_m + ch_m, -e_m), Vector2(e_m - ch_m, -e_m),
				Vector2(e_m, -e_m + ch_m), Vector2(e_m, e_m - ch_m),
				Vector2(e_m - ch_m, e_m), Vector2(-e_m + ch_m, e_m),
				Vector2(-e_m, e_m - ch_m), Vector2(-e_m, -e_m + ch_m),
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


# =============================================================================
# MONOLITH_OS — NEO-BRUTALIST HALFTONE PROCEDURAL VISUALS
# =============================================================================


func _is_monolith_unit(type_id: StringName) -> bool:
	return (
		type_id == &"servo_drone"
		or type_id == &"ore_crawler"
		or type_id == &"grid_tech"
		or type_id == &"bulwark_automaton"
		or type_id == &"picket_drone"
		or type_id == &"rail_sentinel"
		or type_id == &"aegis_relay"
		or type_id == &"anvil_siege_walker"
		or type_id == &"monolith_dreadnought"
		or type_id == &"null_grid_projector"
	)


func _is_monolith_building(type_id: StringName) -> bool:
	return (
		type_id == &"foundry_core"
		or type_id == &"capacitor_pylon"
		or type_id == &"silica_smelter"
		or type_id == &"logic_monolith"
		or type_id == &"assembly_bay"
		or type_id == &"ballistics_lab"
		or type_id == &"bastion_emplacement"
		or type_id == &"siege_gantry"
	)


func _get_monolith_team_color(p: Dictionary) -> Color:
	if TeamManager != null:
		return TeamManager.get_team_color(team)
	return p["core"]


func _build_chamfer_rect_poly(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var c: float = clampf(chamfer, 0.0, minf(rect.size.x, rect.size.y) * 0.45)
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.end.x
	var y1: float = rect.end.y
	return PackedVector2Array([
		Vector2(x0 + c, y0), Vector2(x1 - c, y0),
		Vector2(x1, y0 + c), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0 + c, y1),
		Vector2(x0, y1 - c), Vector2(x0, y0 + c),
	])


func _draw_brutalist_slab(
	canvas: CanvasItem,
	rect: Rect2,
	fill_col: Color,
	outline_col: Color,
	shadow_offset: Vector2 = Vector2(3.0, 3.0),
	chamfer: float = 5.0,
	trim_col: Color = MONO_OFFWHITE
) -> void:
	var poly: PackedVector2Array = _build_chamfer_rect_poly(rect, chamfer)
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
	# Crisp inner top-left highlight trim stripe
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


func _draw_halftone_dots(
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


func _draw_team_corner_brackets(canvas: CanvasItem, rect: Rect2, team_col: Color, arm: float = 7.0, width: float = 2.2) -> void:
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


func _draw_monolith_unit_silhouette(p: Dictionary) -> void:
	var team_col: Color = _get_monolith_team_color(p)
	var slab_base: Color = MONO_CONCRETE_MID.lerp(team_col, 0.14)
	var slab_dark: Color = MONO_CONCRETE_DARK.lerp(team_col, 0.10)
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.5)

	match entity_type_id:
		&"servo_drone":
			# Compact brutalist utility block with twin weld-prongs & halftone rear cap
			_draw_brutalist_slab(self, Rect2(-11, -9, 21, 18), slab_base, MONO_INK, Vector2(2.2, 2.2), 3.5, MONO_OFFWHITE)
			# Twin industrial manipulator prongs
			draw_rect(Rect2(9, -7.5, 7.5, 3.2), MONO_INK, true)
			draw_rect(Rect2(9, 4.3, 7.5, 3.2), MONO_INK, true)
			draw_line(Vector2(10, -5.9), Vector2(16, -5.9), MONO_OFFWHITE, 1.5, true)
			draw_line(Vector2(10, 5.9), Vector2(16, 5.9), MONO_OFFWHITE, 1.5, true)
			# Halftone rear vent dots (4 dots)
			_draw_halftone_dots(self, Rect2(-10, -7, 10, 14), 5.0, 1.2, Color(0.04, 0.05, 0.07, 0.55), 2.5)
			# Team hazard bar + amber sensor slit
			draw_rect(Rect2(-9, -6, 3.5, 12), team_col, true)
			draw_rect(Rect2(3, -3.5, 4.2, 7.0), MONO_AMBER, true)

		&"ore_crawler":
			# Heavily armored tread-block with wide brutalist mining jaw & silica hopper
			# Heavy side tread blocks
			draw_rect(Rect2(-15, -14.5, 28, 4.5), MONO_INK, true)
			draw_rect(Rect2(-15, 10.0, 28, 4.5), MONO_INK, true)
			_draw_brutalist_slab(self, Rect2(-15, -11.5, 29, 23), slab_base, MONO_INK, Vector2(2.5, 2.5), 4.0, MONO_AMBER)
			# Wide bolted ore scoop
			var jaw: PackedVector2Array = PackedVector2Array([
				Vector2(12, -12), Vector2(20, -9), Vector2(20, 9), Vector2(12, 12),
				Vector2(15, 6), Vector2(15, -6),
			])
			_poly_outlined(jaw, MONO_OFFWHITE, MONO_INK, 2.0)
			# Recessed hopper bay + halftone rear plate (6 dots)
			draw_rect(Rect2(-10, -7, 15, 14), slab_dark, true)
			draw_rect(Rect2(-8, -4.5, 9, 9), MONO_AMBER, true)
			draw_rect(Rect2(-13.5, -9, 3.0, 18), team_col, true)
			_draw_halftone_dots(self, Rect2(-9, -7, 12, 14), 6.0, 1.2, Color(0.04, 0.05, 0.07, 0.48), 2.0)

		&"grid_tech":
			# Angular compute technician slab with twin arc-welder clamps & cyan logic core
			_draw_brutalist_slab(self, Rect2(-12, -10.5, 23, 21), MONO_OFFWHITE.lerp(slab_base, 0.35), MONO_INK, Vector2(2.2, 2.2), 4.0, MONO_AMBER)
			# Twin diagnostic clamps
			draw_line(Vector2(9, -5.5), Vector2(16.5, -6.5), MONO_INK, 3.6, true)
			draw_line(Vector2(9, 5.5), Vector2(16.5, 6.5), MONO_INK, 3.6, true)
			draw_line(Vector2(9, -5.5), Vector2(16, -6.2), MONO_SHIELD_CYAN, 1.5, true)
			draw_line(Vector2(9, 5.5), Vector2(16, 6.2), MONO_SHIELD_CYAN, 1.5, true)
			# Recessed logic deck + cyan emitter + team stripe
			draw_rect(Rect2(-7, -6.5, 13, 13), slab_dark, true)
			draw_rect(Rect2(-3, -3.5, 7, 7), MONO_SHIELD_CYAN, true)
			draw_rect(Rect2(-10.5, -7.5, 3.2, 15), team_col, true)
			_draw_halftone_dots(self, Rect2(-7, -6, 12, 12), 5.5, 1.1, Color(0.95, 0.94, 0.91, 0.32), 2.0)

		&"bulwark_automaton":
			# Broad monolithic frontline bruiser with heavy forward ballistic shield slab & twin cannons
			# Heavy shoulder twin-slug barrels
			draw_rect(Rect2(6, -16.5, 15, 5.2), MONO_INK, true)
			draw_rect(Rect2(6, 11.3, 15, 5.2), MONO_INK, true)
			draw_line(Vector2(8, -13.9), Vector2(20, -13.9), MONO_OFFWHITE, 1.8, true)
			draw_line(Vector2(8, 13.9), Vector2(20, 13.9), MONO_OFFWHITE, 1.8, true)
			# Main heavy chassis slab
			_draw_brutalist_slab(self, Rect2(-16, -15, 29, 30), slab_base, MONO_INK, Vector2(3.2, 3.2), 5.0, MONO_OFFWHITE)
			# Thick forward riot-shield bulkhead plate
			_draw_brutalist_slab(self, Rect2(8, -13, 8, 26), MONO_OFFWHITE.lerp(team_col, 0.12), MONO_INK, Vector2(1.5, 1.5), 2.5, MONO_AMBER)
			# Halftone armor shading band (6 dots)
			_draw_halftone_dots(self, Rect2(-14, -12, 16, 24), 7.0, 1.4, Color(0.04, 0.05, 0.07, 0.55), 3.0)
			# Bold team-color shoulder hazard bars + Hazard Amber visor slit
			draw_rect(Rect2(-12, -13, 16, 4.2), team_col, true)
			draw_rect(Rect2(-12, 8.8, 16, 4.2), team_col, true)
			draw_rect(Rect2(10.5, -5.5, 3.2, 11.0), MONO_AMBER, true)
			draw_rect(Rect2(-4, -5, 8, 10), slab_dark, true)
			draw_rect(Rect2(-2, -3, 4, 6), MONO_SHIELD_CYAN, true)

		&"picket_drone":
			# Sharp angular wedge-block scout/skirmisher with forward arc-tether prongs
			var drop_pts: PackedVector2Array = PackedVector2Array([
				Vector2(17, 0), Vector2(5, -11), Vector2(-11, -11),
				Vector2(-14, -5), Vector2(-14, 5), Vector2(-11, 11), Vector2(5, 11),
			])
			var sh_pts: PackedVector2Array = PackedVector2Array()
			for pt_p: Vector2 in drop_pts:
				sh_pts.append(pt_p + Vector2(2.4, 2.4))
			draw_colored_polygon(sh_pts, MONO_SHADOW)
			_poly_outlined(drop_pts, slab_base, MONO_INK, 2.2)
			# Forward arc-tether prongs
			draw_line(Vector2(10, -5.5), Vector2(20, -3.5), MONO_INK, 3.4, true)
			draw_line(Vector2(10, 5.5), Vector2(20, 3.5), MONO_INK, 3.4, true)
			draw_line(Vector2(11, -5.2), Vector2(19.5, -3.5), MONO_OFFWHITE, 1.4, true)
			draw_line(Vector2(11, 5.2), Vector2(19.5, 3.5), MONO_OFFWHITE, 1.4, true)
			# Stark off-white dorsal keel + cyan/amber tether core + team wing stripes
			draw_rect(Rect2(-9, -4, 16, 8), slab_dark, true)
			draw_rect(Rect2(-3, -2.5, 9, 5), MONO_SHIELD_CYAN, true)
			draw_line(Vector2(-9, -8.5), Vector2(4, -8.5), team_col, 3.0, true)
			draw_line(Vector2(-9, 8.5), Vector2(4, 8.5), team_col, 3.0, true)
			_draw_halftone_dots(self, Rect2(-12, -8, 10, 16), 5.5, 1.1, Color(0.95, 0.94, 0.91, 0.35), 2.0)

		&"rail_sentinel":
			# Heavy long-range anti-armor precision walker with stark off-white slab & elongated rail barrel
			# Stabilizer outrigger tread pods
			draw_rect(Rect2(-18, -18, 28, 6), MONO_INK, true)
			draw_rect(Rect2(-18, 12, 28, 6), MONO_INK, true)
			draw_line(Vector2(-15, -15), Vector2(7, -15), team_col, 2.6, true)
			draw_line(Vector2(-15, 15), Vector2(7, 15), team_col, 2.6, true)
			# Monolithic off-white / gunmetal turret slab
			_draw_brutalist_slab(self, Rect2(-17, -13, 29, 26), MONO_OFFWHITE.lerp(slab_base, 0.30), MONO_INK, Vector2(3.2, 3.2), 4.5, MONO_AMBER)
			# Elongated heavy twin-rail barrel + glowing amber accelerator slot
			draw_rect(Rect2(6, -6.2, 24, 4.0), MONO_INK, true)
			draw_rect(Rect2(6, 2.2, 24, 4.0), MONO_INK, true)
			draw_line(Vector2(8, -4.2), Vector2(28, -4.2), MONO_OFFWHITE, 1.6, true)
			draw_line(Vector2(8, 4.2), Vector2(28, 4.2), MONO_OFFWHITE, 1.6, true)
			draw_line(Vector2(5, 0.0), Vector2(29, 0.0), MONO_AMBER, 2.8, true)
			# Rear halftone heatsink + capacitor core
			draw_rect(Rect2(-14, -9, 14, 18), slab_dark, true)
			_draw_halftone_dots(self, Rect2(-13, -8, 12, 16), 5.5, 1.2, Color(0.95, 0.94, 0.91, 0.40), 2.0)
			draw_rect(Rect2(-1, -5, 7, 10), MONO_AMBER, true)

		&"aegis_relay":
			# Unarmed hovering shield-support prism with stark off-white diamond slabs & cyan emitter core
			var hover_off: Vector2 = Vector2(3.8, 4.2)
			var outer_d: PackedVector2Array = PackedVector2Array([
				Vector2(15, 0), Vector2(8, -12), Vector2(-8, -12),
				Vector2(-15, 0), Vector2(-8, 12), Vector2(8, 12),
			])
			var sh_d: PackedVector2Array = PackedVector2Array()
			for pt_a: Vector2 in outer_d:
				sh_d.append(pt_a + hover_off)
			draw_colored_polygon(sh_d, Color(0.04, 0.05, 0.07, 0.65))
			# Pulsing shield-emitter halo
			draw_arc(Vector2.ZERO, 15.0 + pulse * 1.8, 0.0, TAU, 24, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.40 + pulse * 0.28), 1.6, true)
			_poly_outlined(outer_d, MONO_OFFWHITE.lerp(slab_base, 0.25), MONO_INK, 2.2)
			# Inner recessed prism + pulsing cyan core
			var inner_d: PackedVector2Array = PackedVector2Array([
				Vector2(9, 0), Vector2(0, -8), Vector2(-9, 0), Vector2(0, 8),
			])
			_poly_outlined(inner_d, slab_dark, team_col, 1.8)
			draw_circle(Vector2.ZERO, 4.2 + pulse * 0.9, MONO_SHIELD_CYAN)
			draw_circle(Vector2.ZERO, 2.0, MONO_OFFWHITE)
			# Team-color prism corner ticks
			draw_line(Vector2(-7, -11), Vector2(7, -11), team_col, 2.6, true)
			draw_line(Vector2(-7, 11), Vector2(7, 11), team_col, 2.6, true)

		&"anvil_siege_walker":
			# Quadruped Deploy/Anchor siege artillery walker with splayed hydraulic legs & elevating siege cannon
			var dep_prog: float = _owner_unit.get_deploy_progress() if _owner_unit != null else 0.0
			var leg_spread: float = lerpf(16.0, 25.5, dep_prog)
			var leg_w: float = lerpf(4.4, 5.6, dep_prog)
			# 4 heavy articulated quadruped legs (splay outward as deploy_progress -> 1.0)
			for li: int in range(4):
				var base_a: float = PI * 0.25 + float(li) * (PI * 0.5)
				var l_dir: Vector2 = Vector2.RIGHT.rotated(base_a)
				var knee: Vector2 = l_dir * lerpf(11.0, 15.5, dep_prog)
				var foot: Vector2 = l_dir * leg_spread
				draw_line(Vector2.ZERO, knee, MONO_INK, leg_w + 1.8, true)
				draw_line(knee, foot, MONO_INK, leg_w, true)
				draw_line(Vector2.ZERO, foot, MONO_OFFWHITE.lerp(slab_base, 0.35), 2.2, true)
				var pad_sz: float = lerpf(3.0, 4.6, dep_prog)
				draw_rect(Rect2(foot - Vector2(pad_sz, pad_sz), Vector2(pad_sz * 2.0, pad_sz * 2.0)), MONO_INK, true)
				draw_rect(Rect2(foot - Vector2(pad_sz * 0.65, pad_sz * 0.65), Vector2(pad_sz * 1.3, pad_sz * 1.3)), MONO_AMBER if dep_prog > 0.5 else team_col, true)
			# Heavy hexagonal-chamfered armored siege chassis slab
			_draw_brutalist_slab(self, Rect2(-18, -15, 34, 30), slab_base, MONO_INK, Vector2(3.4, 3.4), 6.0, MONO_OFFWHITE)
			_draw_halftone_dots(self, Rect2(-16, -12, 16, 24), 6.5, 1.4, Color(0.04, 0.05, 0.07, 0.52), 2.5)
			# Team dorsal flank stripes
			draw_rect(Rect2(-14, -13.5, 22, 3.8), team_col, true)
			draw_rect(Rect2(-14, 9.7, 22, 3.8), team_col, true)
			# Turret breech housing
			_draw_brutalist_slab(self, Rect2(-10, -9, 20, 18), MONO_OFFWHITE.lerp(slab_base, 0.26), MONO_INK, Vector2(1.8, 1.8), 3.5, MONO_AMBER)
			# Siege barrel: compact twin autocannon when mobile -> elongated massive heavy mortar/howitzer barrel when deployed
			var barrel_len: float = lerpf(23.0, 35.0, dep_prog)
			var barrel_thick: float = lerpf(6.5, 10.5, dep_prog)
			draw_rect(Rect2(6.0, -barrel_thick * 0.5, barrel_len - 4.0, barrel_thick), MONO_INK, true)
			draw_line(Vector2(7.0, 0.0), Vector2(barrel_len + 1.0, 0.0), MONO_OFFWHITE, barrel_thick * 0.50, true)
			draw_line(Vector2(6.0, 0.0), Vector2(barrel_len - 2.0, 0.0), MONO_AMBER if dep_prog > 0.5 else MONO_SHIELD_CYAN, 2.2, true)
			# Heavy muzzle brake collar
			draw_rect(Rect2(barrel_len - 5.0, -barrel_thick * 0.68, 5.0, barrel_thick * 1.36), MONO_AMBER, true)
			draw_rect(Rect2(barrel_len - 5.0, -barrel_thick * 0.68, 5.0, barrel_thick * 1.36), MONO_INK, false, 1.5)
			# Reactor / Siege-Lock beacon
			var lock_col: Color = Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.78 + pulse * 0.22) if dep_prog > 0.5 else MONO_SHIELD_CYAN
			draw_rect(Rect2(-5.5, -4.5, 9.0, 9.0), slab_dark, true)
			draw_rect(Rect2(-3.5, -2.5, 5.0, 5.0), lock_col, true)

		&"monolith_dreadnought":
			# Colossal frontline fortress-mech with dual heavy arm cannons & pulsing Kinetic Barrier hex halo
			var barrier_amt: float = _owner_unit.get_shield_amount() if _owner_unit != null else 0.0
			# Twin colossal shoulder/arm autocannons
			draw_rect(Rect2(4, -22.5, 22, 7.5), MONO_INK, true)
			draw_rect(Rect2(4, 15.0, 22, 7.5), MONO_INK, true)
			draw_line(Vector2(7, -18.8), Vector2(25, -18.8), MONO_OFFWHITE, 2.6, true)
			draw_line(Vector2(7, 18.8), Vector2(25, 18.8), MONO_OFFWHITE, 2.6, true)
			draw_line(Vector2(21, -22.5), Vector2(21, -15.0), MONO_AMBER, 2.2, true)
			draw_line(Vector2(21, 15.0), Vector2(21, 22.5), MONO_AMBER, 2.2, true)
			# Massive main monolithic fortress hull
			_draw_brutalist_slab(self, Rect2(-22, -20, 40, 40), slab_base, MONO_INK, Vector2(4.2, 4.2), 7.0, MONO_OFFWHITE)
			# Stepped upper fortress carapace + forward bastion prow
			_draw_brutalist_slab(self, Rect2(-15, -15, 28, 30), MONO_OFFWHITE.lerp(slab_base, 0.30), MONO_INK, Vector2(2.0, 2.0), 4.5, MONO_AMBER)
			_draw_brutalist_slab(self, Rect2(10, -16, 10, 32), MONO_OFFWHITE.lerp(team_col, 0.14), MONO_INK, Vector2(1.8, 1.8), 3.0, MONO_AMBER)
			# Halftone rear heat-sink band
			_draw_halftone_dots(self, Rect2(-20, -15, 14, 30), 6.5, 1.5, Color(0.04, 0.05, 0.07, 0.56), 2.5)
			# Bold team-color shoulder plates + glowing cyan reactor + amber visor
			draw_rect(Rect2(-18, -18.5, 24, 5.2), team_col, true)
			draw_rect(Rect2(-18, 13.3, 24, 5.2), team_col, true)
			draw_rect(Rect2(-6, -7.5, 12, 15), slab_dark, true)
			draw_rect(Rect2(-3.5, -5.0, 7, 10), MONO_SHIELD_CYAN, true)
			draw_rect(Rect2(13, -7.0, 3.8, 14.0), MONO_AMBER, true)
			# Pulsing hexagonal Kinetic Barrier halo when temporary barrier is active
			if barrier_amt > 0.0:
				var hex_r: float = 28.5 + pulse * 2.2
				var hex_pts: PackedVector2Array = PackedVector2Array()
				for hi: int in range(6):
					var ha: float = float(hi) * (TAU / 6.0) + _anim_time * 0.45
					hex_pts.append(Vector2.RIGHT.rotated(ha) * hex_r)
				draw_colored_polygon(hex_pts, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.14 + pulse * 0.08))
				_draw_closed_outline(hex_pts, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.85 + pulse * 0.15), 2.4)
				for hi2: int in range(6):
					draw_circle(hex_pts[hi2], 2.2, MONO_AMBER)

		&"null_grid_projector":
			# Angular grav-control dish/monolith walker with rotating amber-violet grav core
			var grav_violet: Color = Color(0.74, 0.40, 1.0, 1.0)
			# Rear twin stabilizer pylons
			_draw_brutalist_slab(self, Rect2(-18, -16, 20, 9), slab_dark, MONO_INK, Vector2(2.4, 2.4), 3.0, team_col)
			_draw_brutalist_slab(self, Rect2(-18, 7, 20, 9), slab_dark, MONO_INK, Vector2(2.4, 2.4), 3.0, team_col)
			# Central brutalist chassis core
			_draw_brutalist_slab(self, Rect2(-14, -12, 26, 24), slab_base, MONO_INK, Vector2(3.0, 3.0), 5.0, MONO_OFFWHITE)
			_draw_halftone_dots(self, Rect2(-12, -10, 14, 20), 6.0, 1.3, Color(0.04, 0.05, 0.07, 0.50), 2.5)
			# Forward parabolic grav-projector dish/prongs
			var dish: PackedVector2Array = PackedVector2Array([
				Vector2(6, -15), Vector2(18, -11), Vector2(15, -5),
				Vector2(15, 5), Vector2(18, 11), Vector2(6, 15),
				Vector2(2, 9), Vector2(2, -9),
			])
			_poly_outlined(dish, MONO_OFFWHITE.lerp(slab_base, 0.22), MONO_INK, 2.2)
			draw_line(Vector2(-14, -11), Vector2(2, -11), team_col, 2.8, true)
			draw_line(Vector2(-14, 11), Vector2(2, 11), team_col, 2.8, true)
			# Rotating amber-violet gravity prism core
			var rot_a: float = _anim_time * 2.6
			var core_pts: PackedVector2Array = PackedVector2Array()
			for ci: int in range(4):
				var ca: float = rot_a + float(ci) * (PI * 0.5)
				core_pts.append(Vector2(6.0, 0.0) + Vector2.RIGHT.rotated(ca) * (6.2 + pulse * 0.9))
			draw_arc(Vector2(6.0, 0.0), 10.5 + pulse * 1.4, rot_a, rot_a + PI * 1.15, 16, Color(grav_violet.r, grav_violet.g, grav_violet.b, 0.80), 1.8, true)
			draw_arc(Vector2(6.0, 0.0), 10.5 + pulse * 1.4, rot_a + PI, rot_a + PI * 1.65, 12, Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.85), 1.8, true)
			_poly_outlined(core_pts, grav_violet, MONO_AMBER, 1.6)
			draw_circle(Vector2(6.0, 0.0), 2.4, MONO_OFFWHITE)


func _draw_monolith_building_completed(hull_poly: PackedVector2Array, p: Dictionary) -> void:
	var team_col: Color = _get_monolith_team_color(p)
	var slab_base: Color = MONO_CONCRETE_MID.lerp(team_col, 0.10)
	var slab_dark: Color = MONO_CONCRETE_DARK.lerp(team_col, 0.08)
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 3.4)
	var active_pulse: float = 0.5 + 0.5 * sin(_anim_time * TAU * 2.2)
	var is_training: bool = _owner_building.get_training_queue_size() > 0
	var is_active_prod: bool = _owner_building.is_actively_producing()
	var r: float = maxf(24.0, _owner_building.footprint_radius)
	var half: float = r * 0.94

	# Subtle brutalist concrete foundation pad
	if SettingsManager == null or SettingsManager.battle_scars_enabled:
		var pad_poly: PackedVector2Array = _scale_poly(hull_poly, 1.12)
		draw_colored_polygon(pad_poly, Color(0.04, 0.05, 0.07, 0.45))
		_draw_closed_outline(pad_poly, Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.22), 1.2)

	match entity_type_id:
		&"foundry_core":
			# Massive neo-brutalist command fortress (92x92) with 4 corner buttresses & Axiom reactor
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(4.5, 4.5), 10.0, MONO_OFFWHITE)
			# Halftone shadow band on lower-right terrace (~18 dots)
			_draw_halftone_dots(self, Rect2(-half + 6, 4, half * 2.0 - 12, half - 10), 8.5, 1.5, Color(0.04, 0.05, 0.07, 0.48), 3.0)
			# 4 heavy architectural corner buttresses
			for b_pos: Vector2 in [Vector2(-38, -38), Vector2(22, -38), Vector2(22, 22), Vector2(-38, 22)]:
				_draw_brutalist_slab(self, Rect2(b_pos, Vector2(16, 16)), slab_dark, MONO_INK, Vector2(1.5, 1.5), 3.0, team_col)
			# Central stepped off-white command monolith + recessed amber core
			_draw_brutalist_slab(self, Rect2(-22, -22, 44, 44), MONO_OFFWHITE.lerp(slab_base, 0.22), MONO_INK, Vector2(2.5, 2.5), 6.0, MONO_AMBER)
			draw_rect(Rect2(-13, -13, 26, 26), slab_dark, true)
			draw_rect(Rect2(-8, -8, 16, 16), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.80 + pulse * 0.20), true)
			draw_rect(Rect2(-4, -4, 8, 8), MONO_OFFWHITE, true)
			# Cardinal industrial conduits + team brackets
			draw_line(Vector2(-36, 0), Vector2(-22, 0), MONO_AMBER, 3.0)
			draw_line(Vector2(22, 0), Vector2(36, 0), MONO_AMBER, 3.0)
			draw_line(Vector2(0, -36), Vector2(0, -22), MONO_AMBER, 3.0)
			draw_line(Vector2(0, 22), Vector2(0, 36), MONO_AMBER, 3.0)
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 11.0, 2.6)
			if is_training:
				draw_arc(Vector2.ZERO, 26.0, _anim_time * 2.4, _anim_time * 2.4 + PI * 1.15, 20, MONO_AMBER, 2.5, true)

		&"capacitor_pylon":
			# Brutalist capacitor obelisk (56x56) with twin cyan bus-bars & shield-aura core
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(3.5, 3.5), 7.0, MONO_OFFWHITE)
			_draw_halftone_dots(self, Rect2(-half + 4, 2, half * 2.0 - 8, half - 6), 7.5, 1.3, Color(0.04, 0.05, 0.07, 0.45), 2.5)
			# Twin vertical cyan shield-capacitor bus bars
			draw_rect(Rect2(-16, -15, 7, 30), slab_dark, true)
			draw_rect(Rect2(9, -15, 7, 30), slab_dark, true)
			draw_rect(Rect2(-14, -12, 3, 24), MONO_SHIELD_CYAN, true)
			draw_rect(Rect2(11, -12, 3, 24), MONO_SHIELD_CYAN, true)
			# Central chamfered monolith core
			_draw_brutalist_slab(self, Rect2(-8, -11, 16, 22), MONO_OFFWHITE, MONO_INK, Vector2(1.5, 1.5), 3.0, MONO_AMBER)
			draw_circle(Vector2.ZERO, 4.5 + pulse * 1.2, MONO_SHIELD_CYAN)
			draw_arc(Vector2.ZERO, 17.5, 0.0, TAU, 24, Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.30 + pulse * 0.25), 1.4, true)
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 8.0, 2.2)

		&"silica_smelter":
			# Twin-furnace industrial smelter (74x74) with molten amber crucible channel
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(4.0, 4.0), 8.0, MONO_AMBER)
			_draw_halftone_dots(self, Rect2(-half + 5, 6, half * 2.0 - 10, half - 10), 8.0, 1.4, Color(0.04, 0.05, 0.07, 0.48), 3.0)
			# Dual concrete furnace stacks
			_draw_brutalist_slab(self, Rect2(-26, -22, 18, 36), slab_dark, MONO_INK, Vector2(1.8, 1.8), 3.0, MONO_OFFWHITE)
			_draw_brutalist_slab(self, Rect2(8, -22, 18, 36), slab_dark, MONO_INK, Vector2(1.8, 1.8), 3.0, MONO_OFFWHITE)
			draw_rect(Rect2(-22, -16, 10, 24), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.72 + pulse * 0.24), true)
			draw_rect(Rect2(12, -16, 10, 24), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.58 + pulse * 0.32), true)
			# Center molten channel
			draw_rect(Rect2(-5, -18, 10, 28), MONO_INK, true)
			draw_line(Vector2(0, -14), Vector2(0, 6), MONO_OFFWHITE, 3.0)
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 9.0, 2.4)

		&"logic_monolith":
			# Severe brutalist server monolith (74x74) with 3 crisp Grid-Tech staffing pips
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			var staffed: int = _owner_building.get_assigned_engineer_count()
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(4.0, 4.0), 7.0, MONO_SHIELD_CYAN if is_active_prod else MONO_OFFWHITE)
			draw_rect(Rect2(-25, -26, 50, 38), slab_dark, true)
			# Vertical brutalist server rack fins
			var fin_col: Color = Color(MONO_SHIELD_CYAN.r, MONO_SHIELD_CYAN.g, MONO_SHIELD_CYAN.b, 0.65 + active_pulse * 0.35) if is_active_prod else Color(0.45, 0.50, 0.56, 0.45)
			for fx: float in [-18.0, -9.0, 0.0, 9.0, 18.0]:
				draw_line(Vector2(fx, -22), Vector2(fx, 8), fin_col, 2.2)
			# Central Axiom processor block
			_draw_brutalist_slab(self, Rect2(-10, -15, 20, 16), MONO_OFFWHITE, MONO_INK, Vector2(1.2, 1.2), 2.5, MONO_AMBER)
			draw_rect(Rect2(-5, -11, 10, 8), MONO_SHIELD_CYAN if is_active_prod else Color(0.28, 0.32, 0.38, 0.9), true)
			if is_active_prod:
				_draw_active_conduit_sparks(MONO_SHIELD_CYAN, 22.0)
			# 3 staffing indicator pips along bottom terrace
			var slots: int = maxi(1, _owner_building.max_staff_slots)
			var pip_span: float = 13.5
			for s: int in range(slots):
				var px: float = (float(s) - float(slots - 1) * 0.5) * pip_span
				var pip_rect: Rect2 = Rect2(px - 5.0, 17.0, 10.0, 6.5)
				var filled: bool = s < staffed
				draw_rect(pip_rect, MONO_AMBER if filled else Color(0.12, 0.14, 0.17, 0.96), true)
				draw_rect(pip_rect, MONO_OFFWHITE if filled else MONO_INK, false, 1.4)
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 9.0, 2.4)

		&"assembly_bay":
			# Primary robotics factory slab (82x82) with industrial gantry rails & sliding overhead beam
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(4.2, 4.2), 8.0, MONO_AMBER if is_active_prod else MONO_OFFWHITE)
			# Recessed assembly bay deck + halftone grid (~16 dots)
			draw_rect(Rect2(-26, -24, 52, 48), slab_dark, true)
			_draw_halftone_dots(self, Rect2(-24, -22, 48, 44), 9.5, 1.4, Color(0.95, 0.94, 0.91, 0.24), 4.0)
			# Twin heavy vertical crane rails
			draw_rect(Rect2(-31, -28, 8, 56), MONO_OFFWHITE.lerp(slab_base, 0.35), true)
			draw_rect(Rect2(23, -28, 8, 56), MONO_OFFWHITE.lerp(slab_base, 0.35), true)
			draw_rect(Rect2(-31, -28, 8, 56), MONO_INK, false, 1.8)
			draw_rect(Rect2(23, -28, 8, 56), MONO_INK, false, 1.8)
			# Sliding overhead gantry beam + active forge glow
			var bridge_y: float = sin(_anim_time * 2.4) * 12.0 if is_active_prod else -2.0
			draw_rect(Rect2(-30, bridge_y - 4.5, 60, 9.0), MONO_OFFWHITE, true)
			draw_rect(Rect2(-30, bridge_y - 4.5, 60, 9.0), MONO_INK, false, 1.8)
			if is_active_prod:
				draw_rect(Rect2(-12, -13, 24, 26), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.68 + active_pulse * 0.28), true)
				draw_rect(Rect2(-12, -13, 24, 26), MONO_OFFWHITE, false, 1.6)
				draw_circle(Vector2(0.0, bridge_y), 3.8 + active_pulse * 1.4, MONO_AMBER)
				_draw_active_conduit_sparks(MONO_AMBER, 24.0)
			else:
				draw_rect(Rect2(-12, -13, 24, 26), Color(0.24, 0.27, 0.31, 0.75), true)
				draw_rect(Rect2(-12, -13, 24, 26), MONO_INK, false, 1.4)
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 10.0, 2.4)

		&"ballistics_lab":
			# Precision & support facility (80x80) with central rail-test channel & twin shield capacitor banks
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(4.2, 4.2), 9.0, MONO_SHIELD_CYAN if is_active_prod else MONO_OFFWHITE)
			_draw_halftone_dots(self, Rect2(-half + 5, -half + 5, half * 2.0 - 10, half - 6), 8.5, 1.3, Color(0.04, 0.05, 0.07, 0.42), 3.0)
			# Twin precision capacitor banks (top and bottom flanks)
			_draw_brutalist_slab(self, Rect2(-26, -27, 52, 13), slab_dark, MONO_INK, Vector2(1.4, 1.4), 3.0, MONO_SHIELD_CYAN)
			_draw_brutalist_slab(self, Rect2(-26, 14, 52, 13), slab_dark, MONO_INK, Vector2(1.4, 1.4), 3.0, MONO_AMBER)
			# Central horizontal rail-calibration corridor
			draw_rect(Rect2(-28, -9, 56, 18), MONO_INK, true)
			var rail_col: Color = Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.70 + active_pulse * 0.30) if is_active_prod else Color(0.42, 0.46, 0.52, 0.65)
			draw_line(Vector2(-24, -4), Vector2(24, -4), MONO_OFFWHITE, 2.0)
			draw_line(Vector2(-24, 4), Vector2(24, 4), MONO_OFFWHITE, 2.0)
			draw_line(Vector2(-24, 0), Vector2(24, 0), rail_col, 3.0)
			if is_active_prod:
				var sweep_x: float = lerpf(-20.0, 20.0, fmod(_anim_time * 1.4, 1.0))
				draw_circle(Vector2(sweep_x, 0.0), 4.2, MONO_SHIELD_CYAN)
				_draw_active_conduit_sparks(MONO_SHIELD_CYAN, 24.0)
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 10.0, 2.4)

		&"bastion_emplacement":
			# Heavy fortified concrete turret bunker (64x64) with 4 blast buttresses & turret pit
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(4.0, 4.0), 9.0, MONO_AMBER)
			_draw_halftone_dots(self, Rect2(-half + 4, -half + 4, half * 2.0 - 8, half * 2.0 - 8), 8.0, 1.3, Color(0.04, 0.05, 0.07, 0.44), 3.0)
			# 4 heavy corner blast buttresses
			for lug: Vector2 in [Vector2(-24, -24), Vector2(14, -24), Vector2(14, 14), Vector2(-24, 14)]:
				draw_rect(Rect2(lug, Vector2(10, 10)), MONO_OFFWHITE.lerp(slab_dark, 0.45), true)
				draw_rect(Rect2(lug, Vector2(10, 10)), MONO_INK, false, 1.8)
			# Recessed turret bearing pit
			draw_circle(Vector2.ZERO, 15.5, slab_dark)
			draw_arc(Vector2.ZERO, 15.5, 0.0, TAU, 24, MONO_AMBER, 2.0, true)
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 8.5, 2.4)

		&"siege_gantry":
			# Massive Tier-2 heavy robotics mega-bay (90x90) with 4 amber buttresses & twin crane bridges
			var main_rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
			_draw_brutalist_slab(self, main_rect, slab_base, MONO_INK, Vector2(4.6, 4.6), 10.0, MONO_AMBER if is_active_prod else MONO_OFFWHITE)
			# Heavy recessed mega-assembly pit + halftone concrete apron
			draw_rect(Rect2(-30, -28, 60, 56), slab_dark, true)
			_draw_halftone_dots(self, Rect2(-28, -26, 56, 52), 9.5, 1.5, Color(0.95, 0.94, 0.91, 0.22), 4.0)
			# 4 heavy amber-capped corner gantry buttresses
			for butt: Vector2 in [Vector2(-40, -40), Vector2(24, -40), Vector2(24, 24), Vector2(-40, 24)]:
				_draw_brutalist_slab(self, Rect2(butt, Vector2(16, 16)), slab_dark, MONO_INK, Vector2(1.6, 1.6), 3.0, MONO_AMBER)
				draw_rect(Rect2(butt + Vector2(4.5, 4.5), Vector2(7, 7)), MONO_AMBER if is_active_prod else Color(0.42, 0.46, 0.52, 0.8), true)
			# Twin heavy vertical crane track rails
			draw_rect(Rect2(-35, -30, 8, 60), MONO_OFFWHITE.lerp(slab_base, 0.30), true)
			draw_rect(Rect2(27, -30, 8, 60), MONO_OFFWHITE.lerp(slab_base, 0.30), true)
			draw_rect(Rect2(-35, -30, 8, 60), MONO_INK, false, 1.8)
			draw_rect(Rect2(27, -30, 8, 60), MONO_INK, false, 1.8)
			# Twin parallel overhead crane bridges (slide counter-phase while producing)
			var bridge_a_y: float = -12.0 + (sin(_anim_time * 2.2) * 7.5 if is_active_prod else 0.0)
			var bridge_b_y: float = 12.0 - (sin(_anim_time * 2.2) * 7.5 if is_active_prod else 0.0)
			draw_rect(Rect2(-34, bridge_a_y - 3.8, 68, 7.6), MONO_OFFWHITE, true)
			draw_rect(Rect2(-34, bridge_a_y - 3.8, 68, 7.6), MONO_INK, false, 1.8)
			draw_rect(Rect2(-34, bridge_b_y - 3.8, 68, 7.6), MONO_OFFWHITE, true)
			draw_rect(Rect2(-34, bridge_b_y - 3.8, 68, 7.6), MONO_INK, false, 1.8)
			# Central chassis fabrication crucible
			if is_active_prod:
				draw_rect(Rect2(-15, -15, 30, 30), Color(MONO_AMBER.r, MONO_AMBER.g, MONO_AMBER.b, 0.64 + active_pulse * 0.30), true)
				draw_rect(Rect2(-15, -15, 30, 30), MONO_OFFWHITE, false, 1.8)
				draw_circle(Vector2(0.0, 0.0), 6.5 + active_pulse * 2.2, MONO_SHIELD_CYAN)
				draw_circle(Vector2(0.0, bridge_a_y), 3.4, MONO_AMBER)
				draw_circle(Vector2(0.0, bridge_b_y), 3.4, MONO_AMBER)
				_draw_active_conduit_sparks(MONO_AMBER, 28.0)
			else:
				draw_rect(Rect2(-15, -15, 30, 30), Color(0.22, 0.25, 0.30, 0.80), true)
				draw_rect(Rect2(-15, -15, 30, 30), MONO_INK, false, 1.6)
				draw_circle(Vector2(0.0, 0.0), 5.0, Color(0.32, 0.40, 0.48, 0.72))
			_draw_team_corner_brackets(self, Rect2(-half + 3, -half + 3, half * 2.0 - 6, half * 2.0 - 6), team_col, 11.0, 2.6)
