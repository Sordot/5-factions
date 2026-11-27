class_name ProceduralArenaGenerator
extends Node

const BIOMASS_SCENE: PackedScene = preload("res://scenes/world/biomass_node.tscn")
const SILICA_SCENE: PackedScene = preload("res://scenes/world/silica_vein.tscn")
const COMPUTE_VENT_SCENE: PackedScene = preload("res://scenes/world/compute_vent.tscn")
const HYPER_UPLINK_SCENE: PackedScene = preload("res://scenes/world/hyper_uplink.tscn")
const HIGH_GROUND_SCENE: PackedScene = preload("res://scenes/world/high_ground_plateau.tscn")
const BARRICADE_SCENE: PackedScene = preload("res://scenes/world/destructible_barricade.tscn")
const SENSOR_RELAY_SCENE: PackedScene = preload("res://scenes/world/sensor_relay.tscn")
const LANDMARK_SCENE: PackedScene = preload("res://scenes/world/map_landmark.tscn")
const TERRAIN_OBSTACLE_SCRIPT: GDScript = preload("res://scripts/world/terrain_obstacle.gd")

const BASE_PLATEAU_EXCLUSION_DEFAULT: float = 560.0
const BASE_PLATEAU_EXCLUSION_MIN: float = 520.0
const RESOURCE_PLATEAU_MIN_CLEARANCE: float = 115.0
const RAMP_APPROACH_CLEAR_DEPTH: float = 135.0

const BIOME_POOL: Array = [&"vat_basin", &"twin_causeway", &"quad_nexus", &"triad_sanctum"]
const BIOME_PALETTES: Dictionary = {
	&"vat_basin": {
		"floor": Color(0.031, 0.063, 0.094, 1.0),
		"border": Color(0.22, 0.58, 0.66, 0.78),
		"plateau_tint": Color(0.11, 0.19, 0.25, 1.0),
	},
	&"twin_causeway": {
		"floor": Color(0.055, 0.058, 0.072, 1.0),
		"border": Color(0.92, 0.58, 0.20, 0.78),
		"plateau_tint": Color(0.18, 0.16, 0.14, 1.0),
	},
	&"quad_nexus": {
		"floor": Color(0.035, 0.047, 0.078, 1.0),
		"border": Color(0.32, 0.60, 0.92, 0.80),
		"plateau_tint": Color(0.115, 0.145, 0.22, 1.0),
	},
	&"triad_sanctum": {
		"floor": Color(0.065, 0.068, 0.095, 1.0),
		"border": Color(0.98, 0.80, 0.082, 0.72),
		"plateau_tint": Color(0.16, 0.155, 0.19, 1.0),
		"rim_highlight": Color(0.95, 0.86, 0.56, 0.88),
	},
}

const BASIN_NAMES: Array = ["Alpha Sector", "Omega Sector", "Sigma Sector", "Delta Sector"]

var generated_seed: int = 0
var generated_biome: StringName = &"vat_basin"
var generated_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
var _has_generated: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _symmetry_count: int = 2 # 2 = 180° 2-way, 3 = 120° 3-way rotational, 4 = 4-way quadrant
var _is_four_way: bool = false
var _reserved_circles: Array[Dictionary] = [] # {"pos": Vector2, "r": float}
var _reserved_corridors: Array[Dictionary] = [] # {"a": Vector2, "b": Vector2, "half_w": float}
var _placed_solids: Array[Dictionary] = [] # {"pos": Vector2, "r": float}
var _placed_plateaus: Array[Dictionary] = [] # {"pos": Vector2, "poly": PackedVector2Array}
var _ramp_clear_zones: Array[Dictionary] = [] # {"a": Vector2, "b": Vector2, "out_n": Vector2, "depth": float}
var _resource_positions: Array[Vector2] = []
var _spawn_positions: Array[Vector2] = []


func _ready() -> void:
	add_to_group("procedural_arena_generator")


func generate_arena() -> void:
	if _has_generated or not is_inside_tree():
		return
	_has_generated = true

	var scene_root: Node = get_parent()
	if scene_root == null:
		scene_root = get_tree().current_scene
	if scene_root == null:
		return

	# Resolve seed & parameters from GameConfig
	var p_count: int = 2
	var chokes: int = 1
	var hg_level: int = 1
	var richness: int = 1
	var biome_pref: StringName = &"auto"
	if GameConfig != null:
		p_count = clampi(GameConfig.player_count, 2, 4)
		chokes = clampi(GameConfig.proc_map_chokes, 0, 2)
		hg_level = clampi(GameConfig.proc_map_high_ground, 0, 2)
		richness = clampi(GameConfig.proc_map_richness, 0, 2)
		biome_pref = GameConfig.proc_map_biome
		if GameConfig.proc_map_active_seed <= 0:
			GameConfig.resolve_procedural_seed()
		generated_seed = GameConfig.proc_map_active_seed
	else:
		generated_seed = 482915

	_rng = RandomNumberGenerator.new()
	_rng.seed = int(generated_seed)
	if p_count == 3:
		_symmetry_count = 3
		_is_four_way = false
		generated_bounds = Rect2(-1450.0, -1250.0, 2900.0, 2500.0)
	elif p_count >= 4:
		_symmetry_count = 4
		_is_four_way = true
		generated_bounds = Rect2(-1500.0, -1120.0, 3000.0, 2240.0)
	else:
		_symmetry_count = 2
		_is_four_way = false
		generated_bounds = Rect2(-1300.0, -950.0, 2600.0, 1900.0)

	if biome_pref != &"auto" and BIOME_PALETTES.has(biome_pref):
		generated_biome = biome_pref
	else:
		generated_biome = BIOME_POOL[_rng.randi() % BIOME_POOL.size()] as StringName

	_reserved_circles.clear()
	_reserved_corridors.clear()
	_placed_solids.clear()
	_placed_plateaus.clear()
	_ramp_clear_zones.clear()
	_resource_positions.clear()
	_spawn_positions.clear()

	_sync_scene_bounds_and_biome(scene_root)

	var obj_parent: Node = _ensure_container(scene_root, "Objectives")
	var res_parent: Node = _ensure_container(scene_root, "ResourceNodes")
	var hg_parent: Node = _ensure_container(scene_root, "HighGroundPlateaus")
	var obs_parent: Node = _ensure_container(scene_root, "TerrainObstacles")
	var bar_parent: Node = _ensure_container(scene_root, "Barricades")
	var lm_parent: Node = _ensure_container(scene_root, "Landmarks")
	var anchor_parent: Node = _ensure_container(scene_root, "SpawnAnchors")

	# Step 1 — Central Hyper-Uplink at (0, 0)
	_spawn_hyper_uplink(obj_parent, lm_parent)

	# Step 2 — Symmetric Corner Spawn Anchors & Reserved Anti-Trap Corridors
	var nat_base_pos: Vector2 = _spawn_corner_anchors_and_corridors(anchor_parent, lm_parent)

	# Step 3 — Starting Base Resource Clusters (Guaranteed Mirror)
	var yield_mult: float = 1.0 if richness == 0 else (1.25 if richness == 1 else 1.55)
	_spawn_starting_resources(res_parent, richness, yield_mult)

	# Step 4 — Symmetric Natural & Contested Mid Expansions
	_spawn_expansions(res_parent, nat_base_pos, richness, yield_mult)

	# Step 5 — Spacious High-Ground Plateaus with Wide Assault Ramps (180-220 px)
	if hg_level >= 1:
		_spawn_high_ground_plateaus(hg_parent, hg_level)

	# Step 6 — Symmetric Cover Monoliths & Barricaded Flanks (strictly clear of ramp zones)
	_spawn_cover_monoliths(obs_parent, chokes)
	if chokes >= 1:
		_spawn_flank_barricades(bar_parent)

	# Step 7 — Flank Sensor Relays
	_spawn_sensor_relays(obj_parent)

	# Final Sync — Rebake NavMesh, Rebuild FogOfWar Static Grids, Refresh Minimap
	_finalize_systems(scene_root)


func _ensure_container(root: Node, node_name: String) -> Node2D:
	var existing: Node2D = root.get_node_or_null(node_name) as Node2D
	if existing != null:
		return existing
	var n: Node2D = Node2D.new()
	n.name = node_name
	root.add_child(n)
	return n


func _sync_scene_bounds_and_biome(scene_root: Node) -> void:
	var pal: Dictionary = BIOME_PALETTES.get(generated_biome, BIOME_PALETTES[&"vat_basin"]) as Dictionary
	var floor_col: Color = pal["floor"] as Color
	var border_col: Color = pal["border"] as Color

	var p0: Vector2 = generated_bounds.position
	var p1: Vector2 = Vector2(generated_bounds.end.x, generated_bounds.position.y)
	var p2: Vector2 = generated_bounds.end
	var p3: Vector2 = Vector2(generated_bounds.position.x, generated_bounds.end.y)
	var rect_poly: PackedVector2Array = PackedVector2Array([p0, p1, p2, p3])

	var nav: ArenaNavRegion = scene_root.get_node_or_null("NavigationRegion2D") as ArenaNavRegion
	if nav != null:
		nav.arena_bounds = generated_bounds
		var floor_vis: Polygon2D = nav.get_node_or_null("FloorVisual") as Polygon2D
		if floor_vis != null:
			floor_vis.polygon = rect_poly
			floor_vis.color = floor_col
		var floor_border: Line2D = nav.get_node_or_null("FloorBorder") as Line2D
		if floor_border != null:
			floor_border.points = rect_poly
			floor_border.default_color = border_col

	var backdrop: Node = scene_root.get_node_or_null("MapBiomeBackdrop")
	if backdrop != null:
		backdrop.set("biome_id", generated_biome)
		backdrop.set("arena_bounds", generated_bounds)
		if backdrop is CanvasItem:
			(backdrop as CanvasItem).queue_redraw()

	var cam: RTSCamera = scene_root.get_node_or_null("RTSCamera") as RTSCamera
	if cam != null:
		cam.pan_bounds = generated_bounds.grow(190.0)

	var sel: Node = scene_root.get_node_or_null("SelectionController")
	if sel != null:
		sel.set("buildable_bounds", generated_bounds)
		var router: Node = sel.get_node_or_null("CommandRouter")
		if router != null:
			router.set("buildable_bounds", generated_bounds)

	var spawner: Node = scene_root.get_node_or_null("SandboxSpawner")
	if spawner != null:
		spawner.set("arena_safe_bounds", generated_bounds.grow(-60.0))

	var fog: FogOfWarSystem = scene_root.get_node_or_null("FogOfWarSystem") as FogOfWarSystem
	if fog != null:
		fog.arena_bounds = generated_bounds

	var minimap: Node = scene_root.find_child("TacticalMinimap", true, false)
	if minimap != null:
		minimap.set("arena_bounds", generated_bounds)


func _mirror_points(base_pt: Vector2) -> Array[Vector2]:
	if _symmetry_count == 3:
		return [
			base_pt,
			base_pt.rotated(-TAU / 3.0),
			base_pt.rotated(TAU / 3.0),
		]
	if _is_four_way:
		return [
			base_pt,
			Vector2(-base_pt.x, -base_pt.y),
			Vector2(base_pt.x, -base_pt.y),
			Vector2(-base_pt.x, base_pt.y),
		]
	return [
		base_pt,
		Vector2(-base_pt.x, -base_pt.y),
	]


func _mirror_polygon(poly: PackedVector2Array, sym_idx: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if _symmetry_count == 3:
		var ang: float = 0.0 if sym_idx == 0 else (-TAU / 3.0 if sym_idx == 1 else TAU / 3.0)
		for v: Vector2 in poly:
			out.append(v.rotated(ang))
		return out
	for v: Vector2 in poly:
		match sym_idx:
			1:
				out.append(Vector2(-v.x, -v.y))
			2:
				out.append(Vector2(v.x, -v.y))
			3:
				out.append(Vector2(-v.x, v.y))
			_:
				out.append(v)
	return out


func _spawn_hyper_uplink(obj_parent: Node, lm_parent: Node) -> void:
	var uplink: Node2D = HYPER_UPLINK_SCENE.instantiate() as Node2D
	if uplink != null:
		uplink.name = "HyperUplink"
		uplink.position = Vector2.ZERO
		obj_parent.add_child(uplink)

	var plaza: Node2D = LANDMARK_SCENE.instantiate() as Node2D
	if plaza != null:
		plaza.name = "HyperUplinkPlaza"
		plaza.position = Vector2.ZERO
		plaza.set("landmark_name", "Hyper-Uplink Plaza")
		plaza.set("visual_style", 3)
		plaza.set("accent_color", Color(0.36, 0.92, 1.0, 1.0))
		plaza.set("has_collision", false)
		plaza.set("show_on_minimap", false)
		plaza.set("label_offset", Vector2(0.0, 128.0))
		lm_parent.add_child(plaza)

	_reserved_circles.append({"pos": Vector2.ZERO, "r": 215.0})


func _spawn_corner_anchors_and_corridors(anchor_parent: Node, lm_parent: Node) -> Vector2:
	# Corner anchor inset safely from arena borders with slight deterministic seed jitter
	var base_spawn: Vector2 = Vector2.ZERO
	var nat_base: Vector2 = Vector2.ZERO
	var flank_wp_base: Vector2 = Vector2.ZERO

	if _symmetry_count == 3:
		# Exact 120° equilateral anchors at radius ~900 px (Team 0 = 150°, Team 1 = 30°, Team 2 = -90°)
		base_spawn = Vector2.from_angle(deg_to_rad(150.0)) * _rng.randf_range(885.0, 915.0)
		var nat_ang_offset: float = deg_to_rad(_rng.randf_range(28.0, 34.0))
		nat_base = Vector2.from_angle(deg_to_rad(150.0) + nat_ang_offset) * _rng.randf_range(740.0, 780.0)
		flank_wp_base = Vector2.from_angle(deg_to_rad(150.0) + deg_to_rad(60.0)) * _rng.randf_range(920.0, 980.0)
	else:
		base_spawn = Vector2(
			-_rng.randf_range(1080.0, 1145.0) if _is_four_way else -_rng.randf_range(920.0, 985.0),
			_rng.randf_range(735.0, 795.0) if _is_four_way else _rng.randf_range(585.0, 650.0)
		)
		# Natural expansion location: either along X perimeter or Y perimeter (deterministically chosen)
		var nat_along_x: bool = (_rng.randi() % 2 == 0)
		if _is_four_way:
			if nat_along_x:
				nat_base = Vector2(-_rng.randf_range(400.0, 490.0), _rng.randf_range(830.0, 910.0))
			else:
				nat_base = Vector2(-_rng.randf_range(1130.0, 1215.0), _rng.randf_range(260.0, 350.0))
		else:
			if nat_along_x:
				nat_base = Vector2(-_rng.randf_range(240.0, 360.0), _rng.randf_range(700.0, 775.0))
			else:
				nat_base = Vector2(-_rng.randf_range(940.0, 1025.0), -_rng.randf_range(60.0, 180.0))

		flank_wp_base = Vector2(
			-_rng.randf_range(1230.0, 1300.0) if _is_four_way else -_rng.randf_range(1040.0, 1110.0),
			0.0
		)
		if not nat_along_x:
			flank_wp_base = Vector2(
				0.0,
				_rng.randf_range(880.0, 950.0) if _is_four_way else _rng.randf_range(740.0, 800.0)
			)

	_spawn_positions = _mirror_points(base_spawn)
	var nat_positions: Array[Vector2] = _mirror_points(nat_base)
	var flank_wps: Array[Vector2] = _mirror_points(flank_wp_base)

	for i: int in range(_spawn_positions.size()):
		var spos: Vector2 = _spawn_positions[i]
		var m: Marker2D = Marker2D.new()
		m.name = "SpawnAnchor_Team%d" % i
		m.position = spos
		m.set_meta("team_id", i)
		m.add_to_group("spawn_anchors")
		anchor_parent.add_child(m)

		var lm: Node2D = LANDMARK_SCENE.instantiate() as Node2D
		if lm != null:
			lm.name = "BasinLandmark_%d" % i
			lm.position = spos
			lm.set("landmark_name", String(BASIN_NAMES[i % BASIN_NAMES.size()]))
			lm.set("visual_style", 3)
			var t_col: Color = TeamManager.get_team_color(i) if TeamManager != null else Color(0.24, 0.96, 0.88, 1.0)
			lm.set("accent_color", t_col)
			lm.set("has_collision", false)
			lm.set("show_on_minimap", true)
			lm.set("label_offset", Vector2(0.0, 102.0 if spos.y > 0.0 else -102.0))
			lm_parent.add_child(lm)

		_reserved_circles.append({"pos": spos, "r": 295.0})
		var npos: Vector2 = nat_positions[i]
		_reserved_circles.append({"pos": npos, "r": 185.0})

		# Anti-trap corridor reservations: (1) Spawn->Natural, (2) Spawn->Center, (3) Spawn->Flank, (4) Natural->Center
		_reserved_corridors.append({"a": spos, "b": npos, "half_w": 92.0})
		_reserved_corridors.append({"a": spos, "b": Vector2.ZERO, "half_w": 88.0})
		_reserved_corridors.append({"a": spos, "b": flank_wps[i], "half_w": 84.0})
		_reserved_corridors.append({"a": npos, "b": Vector2.ZERO, "half_w": 80.0})

	return nat_base


func _spawn_starting_resources(res_parent: Node, richness: int, yield_mult: float) -> void:
	if _spawn_positions.is_empty():
		return
	var s0: Vector2 = _spawn_positions[0]
	var away_dir: Vector2 = s0.normalized() # Points outward into the corner behind the hub
	var away_ang: float = away_dir.angle()

	var bio_count: int = 4 if richness >= 2 else 3
	var bio_arc_span: float = deg_to_rad(106.0)
	var bio_offsets: Array[Vector2] = []
	for k: int in range(bio_count):
		var frac: float = 0.0 if bio_count <= 1 else (float(k) / float(bio_count - 1)) - 0.5
		var ang: float = away_ang + frac * bio_arc_span
		var dist: float = 212.0 + (18.0 if (k % 2 == 1) else 0.0)
		bio_offsets.append(s0 + Vector2(cos(ang), sin(ang)) * dist)

	# 2 Silica veins tucked cleanly on the side wing of the base (clear of main center exit)
	var sil_offsets: Array[Vector2] = [
		s0 + Vector2(cos(away_ang - 1.24), sin(away_ang - 1.24)) * 228.0,
		s0 + Vector2(cos(away_ang - 1.56), sin(away_ang - 1.56)) * 246.0,
	]
	# 1 Compute Vent on the opposite wing, inset safely from arena edges
	var vent_pos: Vector2 = s0 + Vector2(cos(away_ang + 1.32), sin(away_ang + 1.32)) * 270.0

	for b_pt: Vector2 in bio_offsets:
		_place_mirrored_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(b_pt, 78.0), yield_mult)
	for s_pt: Vector2 in sil_offsets:
		_place_mirrored_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(s_pt, 78.0), yield_mult)
	_place_mirrored_resource(res_parent, COMPUTE_VENT_SCENE, _clamp_inside_arena(vent_pos, 96.0), yield_mult)


func _spawn_expansions(res_parent: Node, nat_base: Vector2, richness: int, yield_mult: float) -> void:
	var away_ang: float = nat_base.normalized().angle()
	var nat_bio_cnt: int = 3 if richness >= 1 else 2
	for k: int in range(nat_bio_cnt):
		var frac: float = (float(k) / float(maxi(1, nat_bio_cnt - 1))) - 0.5
		var ang: float = away_ang + frac * 1.15
		var pt: Vector2 = _clamp_inside_arena(nat_base + Vector2(cos(ang), sin(ang)) * 120.0, 82.0)
		_place_mirrored_resource(res_parent, BIOMASS_SCENE, pt, yield_mult)

	var nat_sil_cnt: int = 2 if richness >= 1 else 1
	for k: int in range(nat_sil_cnt):
		var ang: float = away_ang - 1.25 - float(k) * 0.42
		var pt: Vector2 = _clamp_inside_arena(nat_base + Vector2(cos(ang), sin(ang)) * 138.0, 82.0)
		_place_mirrored_resource(res_parent, SILICA_SCENE, pt, yield_mult)

	var nat_vent: Vector2 = _clamp_inside_arena(nat_base + Vector2(cos(away_ang + 1.35), sin(away_ang + 1.35)) * 150.0, 96.0)
	_place_mirrored_resource(res_parent, COMPUTE_VENT_SCENE, nat_vent, yield_mult)

	# Contested side-pocket expansion on Rich / Abundant (High-Yield contested flashpoints!)
	if richness >= 1:
		if _symmetry_count == 3:
			var mid_ang: float = deg_to_rad(210.0) # -150°, rotating to 90° and -30°
			var mid_base: Vector2 = Vector2.from_angle(mid_ang) * _rng.randf_range(935.0, 985.0)
			var dir_o: Vector2 = mid_base.normalized()
			var perp_o: Vector2 = dir_o.orthogonal()
			_place_mirrored_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(mid_base - dir_o * 42.0 + perp_o * 54.0, 82.0), yield_mult, true)
			_place_mirrored_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(mid_base - dir_o * 42.0 - perp_o * 54.0, 82.0), yield_mult, true)
			_place_mirrored_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(mid_base + perp_o * 112.0, 82.0), yield_mult, true)
			_place_mirrored_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(mid_base - perp_o * 112.0, 82.0), yield_mult, true)
			_place_mirrored_resource(res_parent, COMPUTE_VENT_SCENE, _clamp_inside_arena(mid_base + dir_o * 64.0, 92.0), yield_mult, false)
			for mp3: Vector2 in _mirror_points(mid_base):
				_reserved_circles.append({"pos": mp3, "r": 180.0})
		elif _is_four_way:
			var w_mid: Vector2 = Vector2(generated_bounds.position.x + 175.0, 0.0)
			var n_mid: Vector2 = Vector2(0.0, generated_bounds.position.y + 165.0)
			for mid_pt: Vector2 in [w_mid, -w_mid, n_mid, -n_mid]:
				var dir_out: Vector2 = mid_pt.normalized()
				var perp: Vector2 = dir_out.orthogonal()
				_spawn_single_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(mid_pt - dir_out * 52.0, 76.0), yield_mult, true)
				_spawn_single_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(mid_pt + perp * 88.0, 76.0), yield_mult, true)
				_spawn_single_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(mid_pt - perp * 88.0, 76.0), yield_mult, true)
				_spawn_single_resource(res_parent, COMPUTE_VENT_SCENE, _clamp_inside_arena(mid_pt + dir_out * 45.0, 86.0), yield_mult, false)
				_reserved_circles.append({"pos": mid_pt, "r": 160.0})
		else:
			var pocket_base: Vector2 = Vector2(-_rng.randf_range(880.0, 975.0), -_rng.randf_range(540.0, 640.0))
			var p_ang: float = pocket_base.normalized().angle()
			_place_mirrored_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang - 0.35), sin(p_ang - 0.35)) * 96.0, 80.0), yield_mult, true)
			_place_mirrored_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang + 0.35), sin(p_ang + 0.35)) * 96.0, 80.0), yield_mult, true)
			_place_mirrored_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang + 1.25), sin(p_ang + 1.25)) * 112.0, 80.0), yield_mult, true)
			_place_mirrored_resource(res_parent, COMPUTE_VENT_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang - 1.25), sin(p_ang - 1.25)) * 124.0, 92.0), yield_mult, false)
			for mp: Vector2 in _mirror_points(pocket_base):
				_reserved_circles.append({"pos": mp, "r": 175.0})


func _place_mirrored_resource(parent: Node, scene: PackedScene, base_pos: Vector2, yield_mult: float, high_yield: bool = false) -> void:
	var pts: Array[Vector2] = _mirror_points(base_pos)
	for pt: Vector2 in pts:
		_spawn_single_resource(parent, scene, pt, yield_mult, high_yield)


func _spawn_single_resource(parent: Node, scene: PackedScene, pos: Vector2, yield_mult: float, high_yield: bool = false) -> void:
	var rn: ResourceNode = scene.instantiate() as ResourceNode
	if rn == null:
		return
	rn.position = pos
	var eff_mult: float = yield_mult
	if high_yield and not rn.is_vent:
		rn.is_high_yield = true
		eff_mult *= 1.25
	if absf(eff_mult - 1.0) > 0.01 and not rn.is_vent:
		var scaled: int = maxi(100, int(round(float(rn.max_amount) * eff_mult)))
		rn.max_amount = scaled
		rn.remaining_amount = scaled
	parent.add_child(rn)
	_resource_positions.append(pos)
	_reserved_circles.append({"pos": pos, "r": 108.0})


## Deterministic chamfered octagon whose cardinal edges have exact controllable widths in [180, 220] px:
## - Edge 0 (Top):   length = width - 2 * chamfer_x
## - Edge 2 (Right): length = height - 2 * chamfer_y
## - Edge 4 (Bot):   length = width - 2 * chamfer_x
## - Edge 6 (Left):  length = height - 2 * chamfer_y
func _build_wide_ramp_octagon(total_w: float, total_h: float, ramp_h_len: float, ramp_v_len: float) -> PackedVector2Array:
	var hw: float = total_w * 0.5
	var hh: float = total_h * 0.5
	var cx: float = clampf((total_w - ramp_h_len) * 0.5, 24.0, hw - 40.0)
	var cy: float = clampf((total_h - ramp_v_len) * 0.5, 24.0, hh - 40.0)
	return PackedVector2Array([
		Vector2(-hw + cx, -hh),
		Vector2(hw - cx, -hh),
		Vector2(hw, -hh + cy),
		Vector2(hw, hh - cy),
		Vector2(hw - cx, hh),
		Vector2(-hw + cx, hh),
		Vector2(-hw, hh - cy),
		Vector2(-hw, -hh + cy),
	])


func _spawn_high_ground_plateaus(hg_parent: Node, hg_level: int) -> void:
	var pal: Dictionary = BIOME_PALETTES.get(generated_biome, BIOME_PALETTES[&"vat_basin"]) as Dictionary
	var tint: Color = pal["plateau_tint"] as Color

	var target_sets: int = 2 if (hg_level >= 2 and _symmetry_count == 2) else 1

	for set_i: int in range(target_sets):
		var base_poly: PackedVector2Array
		var ramp_options: Array[PackedInt32Array] = []
		if set_i == 0:
			# Major Contested Mid-Field Ridge:
			# - Mid Plateaus: 380x280 px (ramps: 200 px & 192 px)
			# - High Ground+: 430x305 px (ramps: 212 px & 200 px) in 2P, or 390x280 px (202 px & 194 px) in 4P
			var maj_w: float = 380.0 if hg_level == 1 else (390.0 if _is_four_way else (400.0 if _symmetry_count == 3 else 430.0))
			var maj_h: float = 280.0 if hg_level == 1 else (280.0 if _is_four_way else (285.0 if _symmetry_count == 3 else 305.0))
			var rh_len: float = 200.0 if hg_level == 1 else (202.0 if _is_four_way else (204.0 if _symmetry_count == 3 else 212.0))
			var rv_len: float = 192.0 if hg_level == 1 else (194.0 if _is_four_way else (194.0 if _symmetry_count == 3 else 200.0))
			base_poly = _build_wide_ramp_octagon(maj_w, maj_h, rh_len, rv_len)
			# Always 2 wide ramps (one center/flank-facing, one base/natural-facing)
			ramp_options = [
				PackedInt32Array([0, 6]),
				PackedInt32Array([4, 2]),
				PackedInt32Array([0, 2]),
				PackedInt32Array([4, 6]),
			]
		else:
			# Secondary Flank Lookout Ledge (High Ground+ 2P): 350x255 px with 1 wide ramp (194 px or 190 px)
			base_poly = _build_wide_ramp_octagon(350.0, 255.0, 194.0, 190.0)
			ramp_options = [
				PackedInt32Array([2]),
				PackedInt32Array([4]),
				PackedInt32Array([0]),
				PackedInt32Array([6]),
			]

		var placed: bool = false
		# Pass 0 enforces strict 560 px base clearance; Pass 1 relaxes only to the 520 px hard minimum.
		for excl_r: float in [BASE_PLATEAU_EXCLUSION_DEFAULT, BASE_PLATEAU_EXCLUSION_MIN]:
			if placed:
				break
			for _attempt: int in range(60):
				var cand: Vector2 = _sample_plateau_candidate(set_i)
				var chosen_ramps: PackedInt32Array = _pick_valid_ramps_for_plateau(cand, base_poly, ramp_options, excl_r)
				if chosen_ramps.is_empty():
					continue
				_commit_mirrored_plateau(hg_parent, set_i, cand, base_poly, chosen_ramps, tint)
				placed = true
				break


func _sample_plateau_candidate(set_i: int) -> Vector2:
	if _symmetry_count == 3:
		# Sample mid-field overlook around 84°-104° (guarantees >= 560 px clearance from all 3 hubs while overlooking center & flank)
		var ang_3: float = deg_to_rad(_rng.randf_range(84.0, 104.0))
		var rad_3: float = _rng.randf_range(445.0, 535.0)
		return Vector2.from_angle(ang_3) * rad_3
	if _is_four_way:
		return Vector2(
			-_rng.randf_range(340.0, 620.0),
			_rng.randf_range(260.0, 500.0)
		)
	if set_i == 0:
		# Spacious mid-field ridges in either the off-diagonal overlook quadrant or mid-flank overlook
		if _rng.randf() < 0.72:
			return Vector2(
				-_rng.randf_range(280.0, 620.0),
				-_rng.randf_range(220.0, 520.0)
			)
		return Vector2(
			-_rng.randf_range(220.0, 420.0),
			_rng.randf_range(210.0, 460.0)
		)
	# Secondary flank lookout ledge (High Ground+ 2P)
	return Vector2(
		-_rng.randf_range(250.0, 740.0),
		_rng.randf_range(-560.0, 520.0)
	)


func _pick_valid_ramps_for_plateau(
	base_pos: Vector2,
	base_poly: PackedVector2Array,
	ramp_options: Array[PackedInt32Array],
	base_excl_r: float
) -> PackedInt32Array:
	if not _is_plateau_body_clear(base_pos, base_poly, base_excl_r):
		return PackedInt32Array()
	for r_opt: PackedInt32Array in ramp_options:
		if _are_mirrored_ramps_clear(base_pos, base_poly, r_opt):
			return r_opt
	return PackedInt32Array()


func _commit_mirrored_plateau(
	hg_parent: Node,
	set_i: int,
	base_pos: Vector2,
	base_poly: PackedVector2Array,
	ramp_indices: PackedInt32Array,
	tint: Color
) -> void:
	var pts: Array[Vector2] = _mirror_points(base_pos)
	var bound_r: float = _polygon_bounding_radius(base_poly)
	for sym_i: int in range(pts.size()):
		var local_poly: PackedVector2Array = _mirror_polygon(base_poly, sym_i)
		var world_poly: PackedVector2Array = _translate_polygon(local_poly, pts[sym_i])
		var pl: HighGroundPlateau = HIGH_GROUND_SCENE.instantiate() as HighGroundPlateau
		if pl != null:
			pl.name = "ProcPlateau_%d_%d" % [set_i, sym_i]
			pl.position = pts[sym_i]
			pl.plateau_polygon = local_poly
			pl.ramp_edge_indices = ramp_indices
			pl.biome_tint = tint
			var pal_r: Dictionary = BIOME_PALETTES.get(generated_biome, {}) as Dictionary
			if pal_r.has("rim_highlight"):
				pl.rim_highlight_override = pal_r["rim_highlight"] as Color
			hg_parent.add_child(pl)
		_placed_plateaus.append({"pos": pts[sym_i], "poly": world_poly})
		_placed_solids.append({"pos": pts[sym_i], "r": bound_r + 12.0})
		for rz: Dictionary in _extract_ramp_clear_zones(world_poly, ramp_indices):
			_ramp_clear_zones.append(rz)


func _translate_polygon(poly: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(poly.size())
	for i: int in range(poly.size()):
		out[i] = poly[i] + offset
	return out


func _polygon_bounding_radius(poly: PackedVector2Array) -> float:
	var max_r: float = 0.0
	for v: Vector2 in poly:
		max_r = maxf(max_r, v.length())
	return max_r


func _point_to_polygon_distance(pt: Vector2, world_poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(pt, world_poly):
		return 0.0
	var best: float = INF
	var n: int = world_poly.size()
	for i: int in range(n):
		var d: float = _point_to_segment_dist(pt, world_poly[i], world_poly[(i + 1) % n])
		if d < best:
			best = d
	return best


func _polygons_min_distance(poly_a: PackedVector2Array, poly_b: PackedVector2Array) -> float:
	var best: float = INF
	for va: Vector2 in poly_a:
		var da: float = _point_to_polygon_distance(va, poly_b)
		if da < best:
			best = da
	for vb: Vector2 in poly_b:
		var db: float = _point_to_polygon_distance(vb, poly_a)
		if db < best:
			best = db
	return best


func _is_plateau_body_clear(base_pos: Vector2, base_poly: PackedVector2Array, base_excl_r: float) -> bool:
	var pts: Array[Vector2] = _mirror_points(base_pos)
	var world_polys: Array[PackedVector2Array] = []
	var border_rect: Rect2 = generated_bounds.grow(-78.0)

	for sym_i: int in range(pts.size()):
		var wpoly: PackedVector2Array = _translate_polygon(_mirror_polygon(base_poly, sym_i), pts[sym_i])
		for v: Vector2 in wpoly:
			if not border_rect.has_point(v):
				return false
		# 1. Strict base exclusion clearance (>= 560 px default, >= 520 px hard minimum)
		for spos: Vector2 in _spawn_positions:
			if _point_to_polygon_distance(spos, wpoly) < base_excl_r:
				return false
		# 2. Central Hyper-Uplink clearance
		if _point_to_polygon_distance(Vector2.ZERO, wpoly) < 195.0:
			return false
		# 3. Resource node clearance (>= 115 px from every starter & expansion node)
		for rpos: Vector2 in _resource_positions:
			if _point_to_polygon_distance(rpos, wpoly) < RESOURCE_PLATEAU_MIN_CLEARANCE:
				return false
		# 4. Primary base exit corridor clearance (avoid boxing spawns)
		for cor: Dictionary in _reserved_corridors:
			var ca: Vector2 = cor["a"] as Vector2
			var cb: Vector2 = cor["b"] as Vector2
			var hw: float = float(cor["half_w"]) * 0.78
			for v: Vector2 in wpoly:
				if _point_to_segment_dist(v, ca, cb) < hw:
					return false
			if _point_to_segment_dist(pts[sym_i], ca, cb) < hw + 54.0:
				return false
		# 5. Separation from previously placed plateaus
		for prev: Dictionary in _placed_plateaus:
			if _polygons_min_distance(wpoly, prev["poly"] as PackedVector2Array) < 150.0:
				return false
		# 6. Do not encroach on existing plateaus' ramp clear zones
		for v: Vector2 in wpoly:
			if _overlaps_any_ramp_zone(v, 30.0):
				return false
		world_polys.append(wpoly)

	# Ensure mirrored copies don't crowd each other across symmetry axes
	for i: int in range(world_polys.size()):
		for j: int in range(i + 1, world_polys.size()):
			if _polygons_min_distance(world_polys[i], world_polys[j]) < 150.0:
				return false

	return true


func _extract_ramp_clear_zones(world_poly: PackedVector2Array, ramp_indices: PackedInt32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: int = world_poly.size()
	if n < 3:
		return out
	var signed_area2: float = 0.0
	for i: int in range(n):
		var v0: Vector2 = world_poly[i]
		var v1: Vector2 = world_poly[(i + 1) % n]
		signed_area2 += (v0.x * v1.y - v1.x * v0.y)
	var is_cw: bool = signed_area2 >= 0.0

	for r_idx: int in ramp_indices:
		if r_idx < 0 or r_idx >= n:
			continue
		var a: Vector2 = world_poly[r_idx]
		var b: Vector2 = world_poly[(r_idx + 1) % n]
		var edge: Vector2 = b - a
		var elen: float = edge.length()
		if elen <= 1.0:
			continue
		var dir: Vector2 = edge / elen
		var out_n: Vector2 = Vector2(dir.y, -dir.x) if is_cw else Vector2(-dir.y, dir.x)
		out.append({
			"a": a,
			"b": b,
			"dir": dir,
			"len": elen,
			"out_n": out_n,
			"depth": RAMP_APPROACH_CLEAR_DEPTH,
		})
	return out


func _are_mirrored_ramps_clear(base_pos: Vector2, base_poly: PackedVector2Array, ramp_indices: PackedInt32Array) -> bool:
	var pts: Array[Vector2] = _mirror_points(base_pos)
	var world_polys: Array[PackedVector2Array] = []
	for sym_i: int in range(pts.size()):
		world_polys.append(_translate_polygon(_mirror_polygon(base_poly, sym_i), pts[sym_i]))

	var safe_arena: Rect2 = generated_bounds.grow(-38.0)

	for sym_i: int in range(world_polys.size()):
		var zones: Array[Dictionary] = _extract_ramp_clear_zones(world_polys[sym_i], ramp_indices)
		for z: Dictionary in zones:
			var a: Vector2 = z["a"] as Vector2
			var b: Vector2 = z["b"] as Vector2
			var out_n: Vector2 = z["out_n"] as Vector2
			var depth: float = float(z["depth"])
			# Verify ramp edge is strictly >= 180 px wide
			if float(z["len"]) < HighGroundPlateau.DEFAULT_WIDE_RAMP_MIN_WIDTH:
				return false
			# Sample 3 across x 3 deep points covering the full width x 135 px ramp approach rectangle
			for du: float in [0.25, 0.62, 1.0]:
				for su: float in [0.08, 0.50, 0.92]:
					var sp: Vector2 = a.lerp(b, su) + out_n * (depth * du)
					if not safe_arena.has_point(sp):
						return false
					if sp.distance_to(Vector2.ZERO) < 165.0:
						return false
					for spawn_p: Vector2 in _spawn_positions:
						if sp.distance_to(spawn_p) < 270.0:
							return false
					for rpos: Vector2 in _resource_positions:
						if sp.distance_to(rpos) < 82.0:
							return false
					for other_i: int in range(world_polys.size()):
						if other_i == sym_i:
							continue
						if _point_to_polygon_distance(sp, world_polys[other_i]) < 36.0:
							return false
					for prev: Dictionary in _placed_plateaus:
						if _point_to_polygon_distance(sp, prev["poly"] as PackedVector2Array) < 36.0:
							return false
	return true


func _overlaps_any_ramp_zone(pt: Vector2, radius: float) -> bool:
	for z: Dictionary in _ramp_clear_zones:
		var a: Vector2 = z["a"] as Vector2
		var dir: Vector2 = z["dir"] as Vector2
		var elen: float = float(z["len"])
		var out_n: Vector2 = z["out_n"] as Vector2
		var depth: float = float(z["depth"])
		var rel: Vector2 = pt - a
		var along: float = rel.dot(dir)
		var out_d: float = rel.dot(out_n)
		if along >= -radius and along <= (elen + radius) and out_d >= -radius and out_d <= (depth + radius):
			return true
	return false


func _spawn_cover_monoliths(obs_parent: Node, chokes: int) -> void:
	var cluster_count: int = 2 if chokes == 0 else (4 if chokes == 1 else 6)
	var min_clearance: float = 132.0

	for c_idx: int in range(cluster_count):
		var is_horizontal: bool = ((c_idx + _rng.randi()) % 2 == 0)
		var w: float = _rng.randf_range(150.0, 215.0) if is_horizontal else _rng.randf_range(56.0, 72.0)
		var h: float = _rng.randf_range(56.0, 72.0) if is_horizontal else _rng.randf_range(150.0, 215.0)
		if chokes >= 2:
			if is_horizontal:
				w += 34.0
			else:
				h += 34.0
		var obs_size: Vector2 = Vector2(w, h)
		var foot_r: float = maxf(w, h) * 0.5 + 14.0

		for _attempt: int in range(44):
			var cand: Vector2
			if _symmetry_count == 3:
				var ang_o: float = deg_to_rad(_rng.randf_range(95.0, 208.0))
				var rad_o: float = _rng.randf_range(340.0, 1020.0)
				cand = _clamp_inside_arena(Vector2.from_angle(ang_o) * rad_o, foot_r + 96.0)
			else:
				cand = Vector2(
					_rng.randf_range(generated_bounds.position.x + 210.0, -140.0),
					_rng.randf_range(140.0, generated_bounds.end.y - 210.0) if _is_four_way else _rng.randf_range(generated_bounds.position.y + 210.0, generated_bounds.end.y - 210.0)
				)
			if not _is_mirrored_spot_clear(cand, foot_r, min_clearance):
				continue
			var pts: Array[Vector2] = _mirror_points(cand)
			for sym_i: int in range(pts.size()):
				var obs: StaticBody2D = TERRAIN_OBSTACLE_SCRIPT.new() as StaticBody2D
				if obs != null:
					obs.name = "ProcObstacle_%d_%d" % [c_idx, sym_i]
					obs.position = pts[sym_i]
					if _symmetry_count == 3:
						obs.rotation = 0.0 if sym_i == 0 else (-TAU / 3.0 if sym_i == 1 else TAU / 3.0)
					obs.set("obstacle_size", obs_size)
					obs_parent.add_child(obs)
					_placed_solids.append({"pos": pts[sym_i], "r": foot_r})
			break


func _spawn_flank_barricades(bar_parent: Node) -> void:
	# Place 2 (2P), 3 (3P), or 4 (4P) symmetric destructible barricades on outer flank shortcuts (never main center lane or ramps)
	var cand_base: Vector2
	if _symmetry_count == 3:
		cand_base = Vector2.from_angle(deg_to_rad(196.0)) * _rng.randf_range(930.0, 1010.0)
	else:
		cand_base = Vector2(
			-_rng.randf_range(120.0, 220.0),
			_rng.randf_range(800.0, 920.0) if _is_four_way else _rng.randf_range(640.0, 740.0)
		)
	for _attempt: int in range(32):
		if _is_mirrored_spot_clear(cand_base, 72.0, 96.0, true):
			var pts: Array[Vector2] = _mirror_points(cand_base)
			for sym_i: int in range(pts.size()):
				var bar: Node2D = BARRICADE_SCENE.instantiate() as Node2D
				if bar != null:
					bar.name = "ProcBarricade_%d" % sym_i
					bar.position = pts[sym_i]
					if _symmetry_count == 3:
						var rot_b: float = 0.0 if sym_i == 0 else (-TAU / 3.0 if sym_i == 1 else TAU / 3.0)
						bar.rotation = cand_base.angle() + rot_b
					else:
						bar.rotation = PI * 0.5
					bar_parent.add_child(bar)
					_placed_solids.append({"pos": pts[sym_i], "r": 64.0})
			return
		if _symmetry_count == 3:
			cand_base = Vector2.from_angle(deg_to_rad(_rng.randf_range(188.0, 206.0))) * _rng.randf_range(880.0, 1050.0)
		else:
			cand_base = Vector2(
				-_rng.randf_range(160.0, 440.0),
				_rng.randf_range(620.0, generated_bounds.end.y - 160.0)
			)


func _spawn_sensor_relays(obj_parent: Node) -> void:
	var names: Array = ["West Flank Sensor Relay", "East Flank Sensor Relay", "North Flank Sensor Relay", "SE Flank Sensor Relay"]
	for _attempt: int in range(40):
		var cand: Vector2
		if _symmetry_count == 3:
			var r_ang: float = deg_to_rad(_rng.randf_range(202.0, 218.0))
			cand = Vector2.from_angle(r_ang) * _rng.randf_range(660.0, 760.0)
		else:
			cand = Vector2(
				-_rng.randf_range(640.0, 880.0),
				-_rng.randf_range(120.0, 320.0) if not _is_four_way else _rng.randf_range(180.0, 440.0)
			)
		if not _is_mirrored_spot_clear(cand, 62.0, 88.0, true):
			continue
		var pts: Array[Vector2] = _mirror_points(cand)
		for sym_i: int in range(pts.size()):
			var relay: Node2D = SENSOR_RELAY_SCENE.instantiate() as Node2D
			if relay != null:
				relay.name = "ProcSensorRelay_%d" % sym_i
				relay.position = pts[sym_i]
				relay.set("relay_name", String(names[sym_i % names.size()]))
				obj_parent.add_child(relay)
				_reserved_circles.append({"pos": pts[sym_i], "r": 68.0})
		return


func _is_mirrored_spot_clear(
	base_pos: Vector2,
	radius: float,
	solid_gap: float,
	allow_corridor_overlap: bool = false
) -> bool:
	var pts: Array[Vector2] = _mirror_points(base_pos)
	var safe_rect: Rect2 = generated_bounds.grow(-(radius + 92.0))
	if not safe_rect.has_area():
		return false

	# Ensure mirrored copies don't overlap each other across symmetry axes
	for i: int in range(pts.size()):
		if not safe_rect.has_point(pts[i]):
			return false
		for j: int in range(i + 1, pts.size()):
			if pts[i].distance_to(pts[j]) < (radius * 2.0 + solid_gap):
				return false

	for pt: Vector2 in pts:
		if _overlaps_any_ramp_zone(pt, radius + 16.0):
			return false
		for pl: Dictionary in _placed_plateaus:
			if _point_to_polygon_distance(pt, pl["poly"] as PackedVector2Array) < (radius + solid_gap * 0.72):
				return false
		for rc: Dictionary in _reserved_circles:
			var rpos: Vector2 = rc["pos"] as Vector2
			var rr: float = float(rc["r"])
			if pt.distance_to(rpos) < (radius + rr):
				return false
		for sol: Dictionary in _placed_solids:
			var spos: Vector2 = sol["pos"] as Vector2
			var sr: float = float(sol["r"])
			if pt.distance_to(spos) < (radius + sr + solid_gap):
				return false
		if not allow_corridor_overlap:
			for cor: Dictionary in _reserved_corridors:
				var d: float = _point_to_segment_dist(pt, cor["a"] as Vector2, cor["b"] as Vector2)
				if d < (radius + float(cor["half_w"])):
					return false
	return true


func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _clamp_inside_arena(pt: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(pt.x, generated_bounds.position.x + margin, generated_bounds.end.x - margin),
		clampf(pt.y, generated_bounds.position.y + margin, generated_bounds.end.y - margin)
	)


func _finalize_systems(scene_root: Node) -> void:
	var nav: ArenaNavRegion = scene_root.get_node_or_null("NavigationRegion2D") as ArenaNavRegion
	if nav != null:
		nav.rebake_navmesh()
	var fog: FogOfWarSystem = scene_root.get_node_or_null("FogOfWarSystem") as FogOfWarSystem
	if fog != null and fog.has_method("rebuild_static_grids"):
		fog.call("rebuild_static_grids", generated_bounds)
	elif fog != null:
		fog.rebuild_blocker_grid()
	var minimap: Node = scene_root.find_child("TacticalMinimap", true, false)
	if minimap != null and minimap.has_method("refresh_arena_bounds"):
		minimap.call("refresh_arena_bounds", generated_bounds)
