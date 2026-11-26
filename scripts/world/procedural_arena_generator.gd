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

const BIOME_POOL: Array = [&"vat_basin", &"twin_causeway", &"quad_nexus"]
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
}

const BASIN_NAMES: Array = ["Alpha Sector", "Omega Sector", "Sigma Sector", "Delta Sector"]

var generated_seed: int = 0
var generated_biome: StringName = &"vat_basin"
var generated_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
var _has_generated: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_four_way: bool = false
var _reserved_circles: Array[Dictionary] = [] # {"pos": Vector2, "r": float}
var _reserved_corridors: Array[Dictionary] = [] # {"a": Vector2, "b": Vector2, "half_w": float}
var _placed_solids: Array[Dictionary] = [] # {"pos": Vector2, "r": float}
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
	_is_four_way = (p_count >= 3)

	if _is_four_way:
		generated_bounds = Rect2(-1400.0, -1050.0, 2800.0, 2100.0)
	else:
		generated_bounds = Rect2(-1300.0, -950.0, 2600.0, 1900.0)

	if biome_pref != &"auto" and BIOME_PALETTES.has(biome_pref):
		generated_biome = biome_pref
	else:
		generated_biome = BIOME_POOL[_rng.randi() % BIOME_POOL.size()] as StringName

	_reserved_circles.clear()
	_reserved_corridors.clear()
	_placed_solids.clear()
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

	# Step 5 — High-Ground Plateaus (when proc_map_high_ground >= 1)
	if hg_level >= 1:
		_spawn_high_ground_plateaus(hg_parent, hg_level)

	# Step 6 — Symmetric Cover Monoliths & Barricaded Flanks
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
	var base_spawn: Vector2 = Vector2(
		-_rng.randf_range(990.0, 1055.0) if _is_four_way else -_rng.randf_range(890.0, 965.0),
		_rng.randf_range(670.0, 735.0) if _is_four_way else _rng.randf_range(560.0, 640.0)
	)
	_spawn_positions = _mirror_points(base_spawn)

	# Natural expansion location: either along X perimeter or Y perimeter (deterministically chosen)
	var nat_along_x: bool = (_rng.randi() % 2 == 0)
	var nat_base: Vector2 = Vector2.ZERO
	if _is_four_way:
		if nat_along_x:
			nat_base = Vector2(-_rng.randf_range(380.0, 470.0), _rng.randf_range(760.0, 840.0))
		else:
			nat_base = Vector2(-_rng.randf_range(1030.0, 1120.0), _rng.randf_range(260.0, 350.0))
	else:
		if nat_along_x:
			nat_base = Vector2(-_rng.randf_range(240.0, 360.0), _rng.randf_range(680.0, 760.0))
		else:
			nat_base = Vector2(-_rng.randf_range(930.0, 1020.0), -_rng.randf_range(60.0, 180.0))

	var nat_positions: Array[Vector2] = _mirror_points(nat_base)

	var flank_wp_base: Vector2 = Vector2(
		-_rng.randf_range(1140.0, 1200.0) if _is_four_way else -_rng.randf_range(1030.0, 1100.0),
		0.0
	)
	if not nat_along_x:
		flank_wp_base = Vector2(
			0.0,
			_rng.randf_range(820.0, 880.0) if _is_four_way else _rng.randf_range(730.0, 790.0)
		)
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

		_reserved_circles.append({"pos": spos, "r": 290.0})
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

	# Contested side-pocket expansion on Rich / Abundant
	if richness >= 1:
		var pocket_base: Vector2 = Vector2(-_rng.randf_range(860.0, 960.0), -_rng.randf_range(520.0, 620.0))
		if _is_four_way:
			# Edge midpoint pockets (West/East + North/South)
			var w_mid: Vector2 = Vector2(generated_bounds.position.x + 175.0, 0.0)
			var n_mid: Vector2 = Vector2(0.0, generated_bounds.position.y + 165.0)
			for mid_pt: Vector2 in [w_mid, -w_mid, n_mid, -n_mid]:
				var dir_out: Vector2 = mid_pt.normalized()
				var perp: Vector2 = dir_out.orthogonal()
				_spawn_single_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(mid_pt - dir_out * 52.0, 76.0), yield_mult)
				_spawn_single_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(mid_pt + perp * 88.0, 76.0), yield_mult)
				_spawn_single_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(mid_pt - perp * 88.0, 76.0), yield_mult)
				_spawn_single_resource(res_parent, COMPUTE_VENT_SCENE, _clamp_inside_arena(mid_pt + dir_out * 45.0, 86.0), yield_mult)
				_reserved_circles.append({"pos": mid_pt, "r": 160.0})
		else:
			var p_ang: float = pocket_base.normalized().angle()
			_place_mirrored_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang - 0.35), sin(p_ang - 0.35)) * 96.0, 80.0), yield_mult)
			_place_mirrored_resource(res_parent, BIOMASS_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang + 0.35), sin(p_ang + 0.35)) * 96.0, 80.0), yield_mult)
			_place_mirrored_resource(res_parent, SILICA_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang + 1.25), sin(p_ang + 1.25)) * 112.0, 80.0), yield_mult)
			_place_mirrored_resource(res_parent, COMPUTE_VENT_SCENE, _clamp_inside_arena(pocket_base + Vector2(cos(p_ang - 1.25), sin(p_ang - 1.25)) * 124.0, 92.0), yield_mult)
			for mp: Vector2 in _mirror_points(pocket_base):
				_reserved_circles.append({"pos": mp, "r": 175.0})


func _place_mirrored_resource(parent: Node, scene: PackedScene, base_pos: Vector2, yield_mult: float) -> void:
	var pts: Array[Vector2] = _mirror_points(base_pos)
	for pt: Vector2 in pts:
		_spawn_single_resource(parent, scene, pt, yield_mult)


func _spawn_single_resource(parent: Node, scene: PackedScene, pos: Vector2, yield_mult: float) -> void:
	var rn: ResourceNode = scene.instantiate() as ResourceNode
	if rn == null:
		return
	rn.position = pos
	if absf(yield_mult - 1.0) > 0.01 and not rn.is_vent:
		var scaled: int = maxi(100, int(round(float(rn.max_amount) * yield_mult)))
		rn.max_amount = scaled
		rn.remaining_amount = scaled
	parent.add_child(rn)
	_reserved_circles.append({"pos": pos, "r": 108.0})


func _spawn_high_ground_plateaus(hg_parent: Node, hg_level: int) -> void:
	var pal: Dictionary = BIOME_PALETTES.get(generated_biome, BIOME_PALETTES[&"vat_basin"]) as Dictionary
	var tint: Color = pal["plateau_tint"] as Color

	var target_sets: int = 2 if (hg_level >= 2 and not _is_four_way) else 1
	var half_w: float = 112.0 if hg_level >= 2 else 96.0
	var half_h: float = 88.0 if hg_level >= 2 else 78.0
	var check_r: float = maxf(half_w, half_h) + 36.0

	# Chamfered hexagonal plateau with 2 wide open ramp edges (>= 140px): edge 0 (top/center) & edge 5 (west/base)
	var chamfer: float = 34.0
	var base_poly: PackedVector2Array = PackedVector2Array([
		Vector2(-half_w, -half_h),
		Vector2(half_w - chamfer, -half_h),
		Vector2(half_w, -half_h + chamfer),
		Vector2(half_w, half_h),
		Vector2(-half_w + chamfer, half_h),
		Vector2(-half_w, half_h - chamfer),
	])
	var ramp_indices: PackedInt32Array = PackedInt32Array([0, 5])

	for set_i: int in range(target_sets):
		var placed: bool = false
		for _attempt: int in range(36):
			var cand: Vector2 = Vector2.ZERO
			if set_i == 0:
				# Inner tactical overlook between base and Hyper-Uplink Plaza
				cand = Vector2(
					-_rng.randf_range(310.0, 500.0),
					_rng.randf_range(260.0, 440.0)
				)
			else:
				# Secondary outer flank high-ground terrace (2P Elevated mode)
				cand = Vector2(
					-_rng.randf_range(520.0, 740.0),
					-_rng.randf_range(220.0, 430.0)
				)
			if not _is_mirrored_spot_clear(cand, check_r, 136.0):
				continue
			var pts: Array[Vector2] = _mirror_points(cand)
			for sym_i: int in range(pts.size()):
				var pl: HighGroundPlateau = HIGH_GROUND_SCENE.instantiate() as HighGroundPlateau
				if pl != null:
					pl.name = "ProcPlateau_%d_%d" % [set_i, sym_i]
					pl.position = pts[sym_i]
					pl.plateau_polygon = _mirror_polygon(base_poly, sym_i)
					pl.ramp_edge_indices = ramp_indices
					pl.biome_tint = tint
					hg_parent.add_child(pl)
					_placed_solids.append({"pos": pts[sym_i], "r": check_r})
			placed = true
			break
		if not placed:
			continue


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

		for _attempt: int in range(40):
			var cand: Vector2 = Vector2(
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
					obs.set("obstacle_size", obs_size)
					obs_parent.add_child(obs)
					_placed_solids.append({"pos": pts[sym_i], "r": foot_r})
			break


func _spawn_flank_barricades(bar_parent: Node) -> void:
	# Place 2 (2P) or 4 (4P) symmetric destructible barricades on outer flank shortcuts (never main center lane)
	var cand_base: Vector2 = Vector2(
		-_rng.randf_range(120.0, 220.0),
		_rng.randf_range(760.0, 860.0) if _is_four_way else _rng.randf_range(640.0, 740.0)
	)
	for _attempt: int in range(28):
		if _is_mirrored_spot_clear(cand_base, 72.0, 96.0, true):
			var pts: Array[Vector2] = _mirror_points(cand_base)
			for sym_i: int in range(pts.size()):
				var bar: Node2D = BARRICADE_SCENE.instantiate() as Node2D
				if bar != null:
					bar.name = "ProcBarricade_%d" % sym_i
					bar.position = pts[sym_i]
					bar.rotation = PI * 0.5
					bar_parent.add_child(bar)
					_placed_solids.append({"pos": pts[sym_i], "r": 64.0})
			return
		cand_base = Vector2(
			-_rng.randf_range(160.0, 420.0),
			_rng.randf_range(620.0, generated_bounds.end.y - 160.0)
		)


func _spawn_sensor_relays(obj_parent: Node) -> void:
	var names: Array = ["West Flank Sensor Relay", "East Flank Sensor Relay", "NW Flank Sensor Relay", "SE Flank Sensor Relay"]
	for _attempt: int in range(36):
		var cand: Vector2 = Vector2(
			-_rng.randf_range(620.0, 840.0),
			-_rng.randf_range(120.0, 320.0) if not _is_four_way else _rng.randf_range(180.0, 420.0)
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
