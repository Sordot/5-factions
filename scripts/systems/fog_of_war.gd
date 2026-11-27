class_name FogOfWarSystem
extends Node

enum VisibilityState {
	UNEXPLORED = 0,
	EXPLORED = 1,
	VISIBLE = 2,
}

signal visibility_updated
signal building_ghosts_changed
signal world_fog_visual_updated

const COLOR_UNEXPLORED: Color = Color(0.02, 0.03, 0.05, 0.92)
const COLOR_EXPLORED: Color = Color(0.03, 0.05, 0.08, 0.50)
const COLOR_VISIBLE: Color = Color(0.0, 0.0, 0.0, 0.0)

const UNEXPLORED_R: int = 5
const UNEXPLORED_G: int = 8
const UNEXPLORED_B: int = 13
const UNEXPLORED_A: int = 235

const EXPLORED_R: int = 8
const EXPLORED_G: int = 13
const EXPLORED_B: int = 20
const EXPLORED_A: int = 128

const WORLD_FOG_REVEAL_SPEED: float = 11.0
const WORLD_FOG_DECAY_SPEED: float = 5.5
const FOG_GHOST_OVERLAY_SCRIPT_PATH: String = "res://ui/overlays/fog_ghost_overlay.gd"

@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
@export var cell_size: float = 32.0
@export var update_interval: float = 0.14
@export var fog_enabled: bool = true
@export var los_shadowing_enabled: bool = true

var post_match_reveal: bool = false
var grid_width: int = 1
var grid_height: int = 1
var fog_image: Image = null
var fog_texture: ImageTexture = null
var world_fog_image: Image = null
var world_fog_texture: ImageTexture = null

var _grid: PackedByteArray = PackedByteArray()
var _prev_grid: PackedByteArray = PackedByteArray()
var _minimap_bytes: PackedByteArray = PackedByteArray()
var _world_fog_bytes: PackedByteArray = PackedByteArray()
var _display_vis: PackedFloat32Array = PackedFloat32Array()
var _display_exp: PackedFloat32Array = PackedFloat32Array()
var _blocker_grid: PackedByteArray = PackedByteArray()
var _elevation_grid: PackedByteArray = PackedByteArray()
var _cached_plateaus: Array[Dictionary] = []
var _static_building_vision_cells: Dictionary = {}
var _building_ghosts: Dictionary = {}
## Local alliance's high-ground & sensor-relay vision sources captured on each refresh_visibility() pass.
## Guarantees sub-cell precision at ramp crests so low-ground units cannot see past the crest via cell bleed.
var _viewer_elevated_sources: Array[Dictionary] = []
var _max_vision_radius: float = 560.0
var _update_timer: float = 0.0
var _blocker_dirty: bool = true
var _world_fog_dirty: bool = false
var _has_initial_refresh: bool = false
var _ghost_overlay: Node2D = null


func _ready() -> void:
	add_to_group("fog_of_war")
	if (TeamManager != null and TeamManager.is_spectator_mode()) or (GameConfig != null and GameConfig.mutator_no_fog):
		fog_enabled = false
	_initialize_grid()
	call_deferred("_post_ready_init")


func _post_ready_init() -> void:
	_ensure_ghost_overlay()
	rebuild_blocker_grid(false)
	refresh_visibility()


func _ensure_ghost_overlay() -> void:
	if not is_inside_tree():
		return
	if _ghost_overlay != null and is_instance_valid(_ghost_overlay):
		return
	var existing: Node = get_tree().get_first_node_in_group("fog_ghost_overlay")
	if existing is Node2D and is_instance_valid(existing):
		_ghost_overlay = existing as Node2D
		return
	var script_res: GDScript = load(FOG_GHOST_OVERLAY_SCRIPT_PATH) as GDScript
	if script_res == null:
		return
	var overlay_inst: Variant = script_res.new()
	if not (overlay_inst is Node2D):
		return
	var overlay: Node2D = overlay_inst as Node2D
	overlay.name = "FogGhostOverlay"
	var target_parent: Node = get_parent() if get_parent() != null else get_tree().current_scene
	if target_parent != null:
		target_parent.add_child(overlay)
		_ghost_overlay = overlay


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= maxf(0.05, update_interval):
		_update_timer = 0.0
		if _blocker_dirty:
			rebuild_blocker_grid(false)
		refresh_visibility()
	_update_world_fog_display(delta)


func _initialize_grid() -> void:
	var safe_cell: float = maxf(16.0, cell_size)
	grid_width = maxi(1, ceili(arena_bounds.size.x / safe_cell))
	grid_height = maxi(1, ceili(arena_bounds.size.y / safe_cell))
	var total: int = grid_width * grid_height

	_grid.resize(total)
	_grid.fill(VisibilityState.UNEXPLORED)
	_prev_grid.resize(total)
	_prev_grid.fill(255) # Force initial texture paint.
	_minimap_bytes.resize(total * 4)
	for i: int in range(total):
		var o: int = i * 4
		_minimap_bytes[o] = UNEXPLORED_R
		_minimap_bytes[o + 1] = UNEXPLORED_G
		_minimap_bytes[o + 2] = UNEXPLORED_B
		_minimap_bytes[o + 3] = UNEXPLORED_A

	_world_fog_bytes.resize(total * 2)
	_world_fog_bytes.fill(0)
	_display_vis.resize(total)
	_display_vis.fill(0.0)
	_display_exp.resize(total)
	_display_exp.fill(0.0)

	_blocker_grid.resize(total)
	_blocker_grid.fill(0)
	_elevation_grid.resize(total)
	_elevation_grid.fill(0)
	_cached_plateaus.clear()
	_static_building_vision_cells.clear()
	_viewer_elevated_sources.clear()
	_blocker_dirty = true
	_world_fog_dirty = true
	_has_initial_refresh = false

	fog_image = Image.create_from_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, _minimap_bytes)
	fog_texture = ImageTexture.create_from_image(fog_image)

	world_fog_image = Image.create_from_data(grid_width, grid_height, false, Image.FORMAT_RG8, _world_fog_bytes)
	world_fog_texture = ImageTexture.create_from_image(world_fog_image)


func invalidate_building_vision_cache() -> void:
	_static_building_vision_cells.clear()


func mark_blockers_dirty() -> void:
	_blocker_dirty = true


func rebuild_static_grids(new_bounds: Rect2 = Rect2()) -> void:
	if new_bounds.has_area():
		arena_bounds = new_bounds
	_initialize_grid()
	rebuild_blocker_grid(false)
	refresh_visibility()


func rebuild_blocker_grid(auto_refresh: bool = true) -> void:
	_blocker_dirty = false
	_static_building_vision_cells.clear()
	_cached_plateaus.clear()
	var total: int = grid_width * grid_height
	if _blocker_grid.size() != total:
		_blocker_grid.resize(total)
	_blocker_grid.fill(0)
	if _elevation_grid.size() != total:
		_elevation_grid.resize(total)
	_elevation_grid.fill(0)
	if not is_inside_tree():
		return

	var cell_w: float = arena_bounds.size.x / float(grid_width)
	var cell_h: float = arena_bounds.size.y / float(grid_height)
	var probe_r: float = minf(cell_w, cell_h) * 0.28

	for p_node: Node in get_tree().get_nodes_in_group("high_ground_plateaus"):
		if is_instance_valid(p_node) and (p_node.has_method("get_world_elevation_at") or p_node.has_method("contains_world_point")):
			_cached_plateaus.append({
				"node": p_node,
				"aabb": _compute_plateau_world_aabb(p_node),
			})

	var blockers: Array = []
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			blockers.append(node)
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and bool(node.get("has_collision")) and node.has_method("overlaps_circle"):
			var style_val: int = int(node.get("visual_style")) if node.get("visual_style") != null else 0
			if style_val != 3: # Exclude flat floor plaza beacons
				blockers.append(node)
	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(node) and not bool(node.get("is_destroyed")) and not node.is_queued_for_deletion() and node.has_method("overlaps_circle"):
			blockers.append(node)

	if not blockers.is_empty() or not _cached_plateaus.is_empty():
		for cy: int in range(grid_height):
			var wy: float = arena_bounds.position.y + (float(cy) + 0.5) * cell_h
			var row_offset: int = cy * grid_width
			for cx: int in range(grid_width):
				var wx: float = arena_bounds.position.x + (float(cx) + 0.5) * cell_w
				var pt: Vector2 = Vector2(wx, wy)
				var idx: int = row_offset + cx
				for blk: Variant in blockers:
					if bool((blk as Node).call("overlaps_circle", pt, probe_r)):
						_blocker_grid[idx] = 1
						break
				# At 32px cell resolution, sample strictly at cell center; sub-cell ramp-crest
				# precision is enforced by _viewer_elevated_sources + is_world_pos_visible_strict().
				var best_elev: int = 0
				for p_entry: Dictionary in _cached_plateaus:
					var aabb: Rect2 = p_entry["aabb"] as Rect2
					if not aabb.has_point(pt):
						continue
					var pl_node: Node = p_entry["node"] as Node
					var e_val: int = _sample_plateau_elev(pl_node, pt)
					if e_val > best_elev:
						best_elev = e_val
				if best_elev > 0:
					_elevation_grid[idx] = best_elev

	if auto_refresh and _has_initial_refresh:
		refresh_visibility()


func _compute_plateau_world_aabb(p_node: Node) -> Rect2:
	var poly_var: Variant = p_node.get("plateau_polygon")
	if p_node is Node2D and poly_var is PackedVector2Array:
		var poly: PackedVector2Array = poly_var as PackedVector2Array
		if poly.size() >= 3:
			var n2d: Node2D = p_node as Node2D
			var first_pt: Vector2 = n2d.to_global(poly[0])
			var min_p: Vector2 = first_pt
			var max_p: Vector2 = first_pt
			for i: int in range(1, poly.size()):
				var wp: Vector2 = n2d.to_global(poly[i])
				min_p.x = minf(min_p.x, wp.x)
				min_p.y = minf(min_p.y, wp.y)
				max_p.x = maxf(max_p.x, wp.x)
				max_p.y = maxf(max_p.y, wp.y)
			return Rect2(min_p, max_p - min_p).grow(4.0)
	return arena_bounds.grow(64.0)


func _sample_plateau_elev(pl_node: Node, world_pt: Vector2) -> int:
	if pl_node.has_method("get_world_elevation_at"):
		return int(pl_node.call("get_world_elevation_at", world_pt))
	if pl_node.has_method("contains_world_point") and bool(pl_node.call("contains_world_point", world_pt)):
		return int(pl_node.get("elevation_level"))
	return 0


## Exact continuous world elevation query aligned with HighGroundPlateau upper crest lines.
## Uses cached world AABBs from rebuild_blocker_grid() so hot combat/steering loops never scan the SceneTree.
func get_elevation_at(world_pos: Vector2) -> int:
	if not _cached_plateaus.is_empty():
		var best_elev: int = 0
		for entry: Dictionary in _cached_plateaus:
			var aabb: Rect2 = entry["aabb"] as Rect2
			if not aabb.has_point(world_pos):
				continue
			var p_node: Node = entry["node"] as Node
			if is_instance_valid(p_node):
				var ev: int = _sample_plateau_elev(p_node, world_pos)
				if ev > best_elev:
					best_elev = ev
		return best_elev
	if is_inside_tree() and _blocker_dirty:
		var best_live: int = 0
		for p_node: Node in get_tree().get_nodes_in_group("high_ground_plateaus"):
			if is_instance_valid(p_node):
				var ev: int = _sample_plateau_elev(p_node, world_pos)
				if ev > best_live:
					best_live = ev
		return best_live
	if _elevation_grid.is_empty():
		return 0
	var cell: Vector2i = world_to_cell(world_pos)
	return int(_elevation_grid[cell.y * grid_width + cell.x])


## Strict local-viewer visibility check with sub-cell ramp-crest precision:
## Prevents 32px fog grid cells straddling a cliff/ramp crest from leaking an Elevation 1
## enemy to a low-ground unit standing below the crest.
func is_world_pos_visible_strict(world_pos: Vector2) -> bool:
	if post_match_reveal or not fog_enabled or (GameConfig != null and GameConfig.mutator_no_fog):
		return true
	if not is_world_pos_visible(world_pos):
		return false
	var target_elev: int = get_elevation_at(world_pos)
	if target_elev <= 0:
		return true
	var target_cell: Vector2i = world_to_cell(world_pos)
	for src: Dictionary in _viewer_elevated_sources:
		var src_pos: Vector2 = src["pos"] as Vector2
		var src_r: float = float(src["radius"])
		if src_pos.distance_squared_to(world_pos) > src_r * src_r:
			continue
		if bool(src["ignores_los"]):
			return true
		var src_elev: int = int(src["elev"])
		if src_elev < target_elev:
			continue
		var src_cell: Vector2i = src["cell"] as Vector2i
		if not los_shadowing_enabled or _has_line_of_sight(src_cell.x, src_cell.y, target_cell.x, target_cell.y, src_elev):
			return true
	return false


## Team-agnostic SC2-accurate visibility query (zero AI map-hacking).
## - For the local human's alliance (non-spectator): uses live visibility grid + sub-cell ramp-crest spotter check.
## - For AI / FFA / Spectator teams: queries allied units, buildings & SensorRelays with exact elevation + LOS raycast.
func is_world_pos_visible_to_team(observer_team: int, world_pos: Vector2) -> bool:
	if post_match_reveal or not fog_enabled or (GameConfig != null and GameConfig.mutator_no_fog):
		return true

	var spectator: bool = TeamManager != null and TeamManager.is_spectator_mode()
	if not spectator:
		var local_t: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		if local_t >= 0:
			var is_local_ally: bool = TeamManager.are_allies(local_t, observer_team) if TeamManager != null else (observer_team == local_t)
			if is_local_ally:
				return is_world_pos_visible_strict(world_pos)

	if not is_inside_tree():
		return false

	var target_elev: int = get_elevation_at(world_pos)
	var target_cell: Vector2i = world_to_cell(world_pos)

	# 1. Active allied Sensor Relays
	for relay_node: Node in get_tree().get_nodes_in_group("sensor_relays"):
		if not is_instance_valid(relay_node) or not (relay_node is Node2D):
			continue
		if not relay_node.has_method("is_active") or not bool(relay_node.call("is_active")):
			continue
		var ctrl_t: int = int(relay_node.get("controlling_team"))
		var ally_ok: bool = ctrl_t >= 0 and (TeamManager.are_allies(observer_team, ctrl_t) if TeamManager != null else (ctrl_t == observer_team))
		if not ally_ok:
			continue
		var relay_pos: Vector2 = (relay_node as Node2D).global_position
		var r_vis: float = float(relay_node.get("vision_radius"))
		if relay_pos.distance_squared_to(world_pos) <= r_vis * r_vis:
			if bool(relay_node.get("ignores_los_blockers")) or not los_shadowing_enabled:
				return true
			var r_elev: int = get_elevation_at(relay_pos)
			var r_cell: Vector2i = world_to_cell(relay_pos)
			if r_elev >= target_elev and _has_line_of_sight(r_cell.x, r_cell.y, target_cell.x, target_cell.y, r_elev):
				return true

	# 2. Living allied units within vision range, >= target elevation, and unobstructed LOS
	var query_r: float = _max_vision_radius
	var spot_units: Array = SpatialGrid.query_units_in_radius(world_pos, query_r) if SpatialGrid != null else get_tree().get_nodes_in_group("units")
	for node: Variant in spot_units:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var u: Unit = node as Unit
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			continue
		var u_ally: bool = TeamManager.are_allies(observer_team, int(u.team)) if TeamManager != null else (int(u.team) == observer_team)
		if not u_ally:
			continue
		var vr: float = u.get_vision_range()
		if u.global_position.distance_squared_to(world_pos) > vr * vr:
			continue
		var u_elev: int = get_elevation_at(u.global_position)
		if u_elev < target_elev:
			continue
		if not los_shadowing_enabled:
			return true
		var u_cell: Vector2i = world_to_cell(u.global_position)
		if _has_line_of_sight(u_cell.x, u_cell.y, target_cell.x, target_cell.y, u_elev):
			return true

	# 3. Living allied buildings within vision range, >= target elevation, and unobstructed LOS
	var spot_bldgs: Array = SpatialGrid.query_buildings_in_radius(world_pos, query_r) if SpatialGrid != null else get_tree().get_nodes_in_group("buildings")
	for node_b: Variant in spot_bldgs:
		if not is_instance_valid(node_b) or not (node_b is Building):
			continue
		var b: Building = node_b as Building
		if b.is_destroyed or b.is_queued_for_deletion():
			continue
		var b_ally: bool = TeamManager.are_allies(observer_team, int(b.team)) if TeamManager != null else (int(b.team) == observer_team)
		if not b_ally:
			continue
		var bvr: float = b.get_vision_range()
		if b.global_position.distance_squared_to(world_pos) > bvr * bvr:
			continue
		var b_elev: int = get_elevation_at(b.global_position)
		if b_elev < target_elev:
			continue
		if not los_shadowing_enabled:
			return true
		var b_cell: Vector2i = world_to_cell(b.global_position)
		if _has_line_of_sight(b_cell.x, b_cell.y, target_cell.x, target_cell.y, b_elev):
			return true

	return false


func is_entity_visible_to_team(observer_team: int, target_node: Node2D) -> bool:
	if target_node == null or not is_instance_valid(target_node):
		return false
	if post_match_reveal or not fog_enabled or (GameConfig != null and GameConfig.mutator_no_fog):
		return true
	if target_node is Unit:
		var u: Unit = target_node as Unit
		if u.is_dead or u.is_staffed:
			return false
		var is_ally: bool = TeamManager.are_allies(observer_team, int(u.team)) if TeamManager != null else (int(u.team) == observer_team)
		if is_ally:
			return true
	elif target_node is Building:
		var b: Building = target_node as Building
		if b.is_destroyed:
			return false
		var is_ally_b: bool = TeamManager.are_allies(observer_team, int(b.team)) if TeamManager != null else (int(b.team) == observer_team)
		if is_ally_b:
			return true
	return is_world_pos_visible_to_team(observer_team, target_node.global_position)


func can_team_see_target_elevation(attacker_team: int, _attacker_pos: Vector2, target_pos: Vector2) -> bool:
	return is_world_pos_visible_to_team(attacker_team, target_pos)


func set_fog_enabled(enabled: bool) -> void:
	if fog_enabled == enabled:
		return
	fog_enabled = enabled
	_world_fog_dirty = true
	refresh_visibility()


func set_post_match_reveal(enabled: bool) -> void:
	if post_match_reveal == enabled:
		return
	post_match_reveal = enabled
	_prev_grid.fill(255)
	_world_fog_dirty = true
	refresh_visibility()


func reset_fog() -> void:
	var had_ghosts: bool = not _building_ghosts.is_empty()
	_building_ghosts.clear()
	_static_building_vision_cells.clear()
	_viewer_elevated_sources.clear()
	_grid.fill(VisibilityState.UNEXPLORED)
	_prev_grid.fill(255)
	_display_vis.fill(0.0)
	_display_exp.fill(0.0)
	_world_fog_bytes.fill(0)
	_world_fog_dirty = true
	_has_initial_refresh = false
	if had_ghosts:
		building_ghosts_changed.emit()
	rebuild_blocker_grid(false)
	refresh_visibility()


func get_active_building_ghosts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ghost_val: Variant in _building_ghosts.values():
		if ghost_val is Dictionary:
			var g: Dictionary = ghost_val as Dictionary
			if bool(g.get("active", false)):
				result.append(g)
	return result


func get_building_ghost_by_id(ghost_id: int) -> Dictionary:
	if not _building_ghosts.has(ghost_id):
		return {}
	var g: Dictionary = _building_ghosts[ghost_id] as Dictionary
	if not bool(g.get("active", false)):
		return {}
	return g


func find_building_ghost_at_point(world_point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist_sq: float = INF
	for ghost_val: Variant in _building_ghosts.values():
		if not (ghost_val is Dictionary):
			continue
		var g: Dictionary = ghost_val as Dictionary
		if not bool(g.get("active", false)):
			continue
		var g_pos: Vector2 = g.get("pos", Vector2.ZERO) as Vector2
		var hit_r: float = maxf(24.0, float(g.get("selection_radius", 32.0)))
		var d_sq: float = world_point.distance_squared_to(g_pos)
		if d_sq <= hit_r * hit_r and d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = g
	return best


func refresh_visibility() -> void:
	if not is_inside_tree() or fog_image == null or fog_texture == null:
		return

	var total: int = grid_width * grid_height
	var first_pass: bool = not _has_initial_refresh
	_has_initial_refresh = true

	if post_match_reveal or not fog_enabled or (GameConfig != null and GameConfig.mutator_no_fog):
		for i: int in range(total):
			_grid[i] = VisibilityState.VISIBLE
		_viewer_elevated_sources.clear()
		_sync_texture_if_dirty()
		_snap_world_fog_to_grid()
		_apply_enemy_visibility(true)
		visibility_updated.emit()
		return

	# Demote previous live vision cells to explored fog memory.
	for i: int in range(total):
		if _grid[i] == VisibilityState.VISIBLE:
			_grid[i] = VisibilityState.EXPLORED
	_viewer_elevated_sources.clear()

	var spectator: bool = TeamManager != null and TeamManager.is_spectator_mode()
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var max_seen_vr: float = 0.0

	# Stamp live LOS vision for all living allied units (or all active teams in Spectator Mode).
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed or unit.is_queued_for_deletion():
			continue
		var u_vr: float = unit.get_vision_range()
		if u_vr > max_seen_vr:
			max_seen_vr = u_vr
		var grants_vision: bool = spectator or (TeamManager.are_allies(viewer_team, int(unit.team)) if TeamManager != null else (unit.team == Unit.Team.PLAYER))
		if not grants_vision:
			continue
		var u_elev: int = get_elevation_at(unit.global_position)
		if u_elev > 0:
			_viewer_elevated_sources.append({
				"pos": unit.global_position,
				"cell": world_to_cell(unit.global_position),
				"radius": u_vr,
				"elev": u_elev,
				"ignores_los": false,
			})
		_reveal_circle_los(unit.global_position, u_vr, u_elev)

	# Stamp cached static LOS vision for all living allied buildings.
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var building: Building = node
		if building.is_destroyed or building.is_queued_for_deletion():
			continue
		var b_vr: float = building.get_vision_range()
		if b_vr > max_seen_vr:
			max_seen_vr = b_vr
		var grants_vision_b: bool = spectator or (TeamManager.are_allies(viewer_team, int(building.team)) if TeamManager != null else (building.team == Unit.Team.PLAYER))
		if not grants_vision_b:
			continue
		var b_elev: int = get_elevation_at(building.global_position)
		if b_elev > 0:
			_viewer_elevated_sources.append({
				"pos": building.global_position,
				"cell": world_to_cell(building.global_position),
				"radius": b_vr,
				"elev": b_elev,
				"ignores_los": false,
			})
		var b_id: int = building.get_instance_id()
		var cache_key: int = b_id * 2 + (1 if building.is_constructed else 0)
		var stamped: PackedInt32Array
		if _static_building_vision_cells.has(cache_key):
			stamped = _static_building_vision_cells[cache_key]
		else:
			stamped = _compute_los_cells(building.global_position, b_vr, b_elev)
			_static_building_vision_cells[cache_key] = stamped
		for idx: int in stamped:
			_grid[idx] = VisibilityState.VISIBLE

	_max_vision_radius = clampf(max_seen_vr + 48.0, 560.0, 1200.0)

	# Stamp unobstructed vision for active capturable Sensor Relays held by the viewer's alliance.
	for node: Node in get_tree().get_nodes_in_group("sensor_relays"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if not node.has_method("is_active") or not bool(node.call("is_active")):
			continue
		var ctrl_team: int = int(node.get("controlling_team"))
		if ctrl_team < 0:
			continue
		var grants_vision_r: bool = spectator or (TeamManager.are_allies(viewer_team, ctrl_team) if TeamManager != null else (ctrl_team == int(Unit.Team.PLAYER)))
		if not grants_vision_r:
			continue
		var relay_pos: Vector2 = (node as Node2D).global_position
		var relay_r: float = float(node.get("vision_radius"))
		var ignore_los: bool = bool(node.get("ignores_los_blockers"))
		var r_elev: int = get_elevation_at(relay_pos)
		if ignore_los or r_elev > 0:
			_viewer_elevated_sources.append({
				"pos": relay_pos,
				"cell": world_to_cell(relay_pos),
				"radius": relay_r,
				"elev": maxi(1, r_elev),
				"ignores_los": ignore_los,
			})
		if ignore_los:
			_reveal_circle_unobstructed(relay_pos, relay_r)
		else:
			_reveal_circle_los(relay_pos, relay_r, r_elev)

	_sync_texture_if_dirty()
	if first_pass:
		_snap_world_fog_to_grid()
	_apply_enemy_visibility(spectator)
	visibility_updated.emit()


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var fx: float = (world_pos.x - arena_bounds.position.x) / maxf(1.0, arena_bounds.size.x)
	var fy: float = (world_pos.y - arena_bounds.position.y) / maxf(1.0, arena_bounds.size.y)
	var cx: int = clampi(int(floor(fx * float(grid_width))), 0, grid_width - 1)
	var cy: int = clampi(int(floor(fy * float(grid_height))), 0, grid_height - 1)
	return Vector2i(cx, cy)


func get_visibility_at_cell(cell: Vector2i) -> int:
	if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
		return VisibilityState.UNEXPLORED
	return int(_grid[cell.y * grid_width + cell.x])


func get_visibility_at_world_pos(world_pos: Vector2) -> int:
	if post_match_reveal or not fog_enabled:
		return VisibilityState.VISIBLE
	var cell: Vector2i = world_to_cell(world_pos)
	return get_visibility_at_cell(cell)


func is_world_pos_visible(world_pos: Vector2) -> bool:
	return get_visibility_at_world_pos(world_pos) == VisibilityState.VISIBLE


func is_world_pos_explored(world_pos: Vector2) -> bool:
	return get_visibility_at_world_pos(world_pos) >= VisibilityState.EXPLORED


func _reveal_circle_unobstructed(world_center: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	var cell_w: float = arena_bounds.size.x / float(grid_width)
	var cell_h: float = arena_bounds.size.y / float(grid_height)
	var min_c: Vector2i = world_to_cell(world_center - Vector2(radius, radius))
	var max_c: Vector2i = world_to_cell(world_center + Vector2(radius, radius))
	var r_sq: float = radius * radius

	for cy: int in range(min_c.y, max_c.y + 1):
		var row_offset: int = cy * grid_width
		var wy: float = arena_bounds.position.y + (float(cy) + 0.5) * cell_h
		var dy: float = wy - world_center.y
		var dy_sq: float = dy * dy
		for cx: int in range(min_c.x, max_c.x + 1):
			var wx: float = arena_bounds.position.x + (float(cx) + 0.5) * cell_w
			var dx: float = wx - world_center.x
			if dx * dx + dy_sq > r_sq:
				continue
			_grid[row_offset + cx] = VisibilityState.VISIBLE


func _reveal_circle_los(world_center: Vector2, radius: float, viewer_elev: int = -1) -> void:
	if radius <= 0.0:
		return
	var cell_w: float = arena_bounds.size.x / float(grid_width)
	var cell_h: float = arena_bounds.size.y / float(grid_height)
	var eff_radius: float = radius + maxf(cell_w, cell_h) * 0.35
	var eff_radius_sq: float = eff_radius * eff_radius

	var origin_cell: Vector2i = world_to_cell(world_center)
	var elev_v: int = viewer_elev if viewer_elev >= 0 else get_elevation_at(world_center)
	var min_cell: Vector2i = world_to_cell(world_center - Vector2(eff_radius, eff_radius))
	var max_cell: Vector2i = world_to_cell(world_center + Vector2(eff_radius, eff_radius))
	var check_los: bool = los_shadowing_enabled and (not _blocker_grid.is_empty() or not _elevation_grid.is_empty())

	for cy: int in range(min_cell.y, max_cell.y + 1):
		var wy: float = arena_bounds.position.y + (float(cy) + 0.5) * cell_h
		var dy: float = wy - world_center.y
		var dy_sq: float = dy * dy
		var row_offset: int = cy * grid_width
		for cx: int in range(min_cell.x, max_cell.x + 1):
			var wx: float = arena_bounds.position.x + (float(cx) + 0.5) * cell_w
			var dx: float = wx - world_center.x
			if dx * dx + dy_sq > eff_radius_sq:
				continue
			if not check_los or _has_line_of_sight(origin_cell.x, origin_cell.y, cx, cy, elev_v):
				_grid[row_offset + cx] = VisibilityState.VISIBLE


func _compute_los_cells(world_center: Vector2, radius: float, viewer_elev: int = -1) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if radius <= 0.0:
		return out
	var cell_w: float = arena_bounds.size.x / float(grid_width)
	var cell_h: float = arena_bounds.size.y / float(grid_height)
	var eff_radius: float = radius + maxf(cell_w, cell_h) * 0.35
	var eff_radius_sq: float = eff_radius * eff_radius

	var origin_cell: Vector2i = world_to_cell(world_center)
	var elev_v: int = viewer_elev if viewer_elev >= 0 else get_elevation_at(world_center)
	var min_cell: Vector2i = world_to_cell(world_center - Vector2(eff_radius, eff_radius))
	var max_cell: Vector2i = world_to_cell(world_center + Vector2(eff_radius, eff_radius))
	var check_los: bool = los_shadowing_enabled and (not _blocker_grid.is_empty() or not _elevation_grid.is_empty())

	for cy: int in range(min_cell.y, max_cell.y + 1):
		var wy: float = arena_bounds.position.y + (float(cy) + 0.5) * cell_h
		var dy: float = wy - world_center.y
		var dy_sq: float = dy * dy
		var row_offset: int = cy * grid_width
		for cx: int in range(min_cell.x, max_cell.x + 1):
			var wx: float = arena_bounds.position.x + (float(cx) + 0.5) * cell_w
			var dx: float = wx - world_center.x
			if dx * dx + dy_sq > eff_radius_sq:
				continue
			if not check_los or _has_line_of_sight(origin_cell.x, origin_cell.y, cx, cy, elev_v):
				out.append(row_offset + cx)
	return out


func _has_line_of_sight(x0: int, y0: int, x1: int, y1: int, viewer_elev: int = 0) -> bool:
	var has_elev: bool = not _elevation_grid.is_empty()
	if has_elev and int(_elevation_grid[y1 * grid_width + x1]) > viewer_elev:
		return false
	if x0 == x1 and y0 == y1:
		return true
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var cx: int = x0
	var cy: int = y0

	while true:
		var e2: int = err * 2
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
		# Target cell itself is revealed unless higher elevation (already checked above).
		if cx == x1 and cy == y1:
			return true
		if cx < 0 or cx >= grid_width or cy < 0 or cy >= grid_height:
			return false
		var step_idx: int = cy * grid_width + cx
		# An intermediate opaque wall or higher plateau terminates the ray immediately.
		if _blocker_grid[step_idx] != 0:
			return false
		if has_elev and int(_elevation_grid[step_idx]) > viewer_elev:
			return false
	return true


func _sync_texture_if_dirty() -> void:
	var total: int = grid_width * grid_height
	var dirty: bool = false
	for idx: int in range(total):
		var val: int = _grid[idx]
		if _prev_grid[idx] == val:
			continue
		_prev_grid[idx] = val
		dirty = true
		var o: int = idx * 4
		if val == VisibilityState.VISIBLE:
			_minimap_bytes[o] = 0
			_minimap_bytes[o + 1] = 0
			_minimap_bytes[o + 2] = 0
			_minimap_bytes[o + 3] = 0
		elif val == VisibilityState.EXPLORED:
			_minimap_bytes[o] = EXPLORED_R
			_minimap_bytes[o + 1] = EXPLORED_G
			_minimap_bytes[o + 2] = EXPLORED_B
			_minimap_bytes[o + 3] = EXPLORED_A
		else:
			_minimap_bytes[o] = UNEXPLORED_R
			_minimap_bytes[o + 1] = UNEXPLORED_G
			_minimap_bytes[o + 2] = UNEXPLORED_B
			_minimap_bytes[o + 3] = UNEXPLORED_A
	if dirty:
		fog_image.set_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, _minimap_bytes)
		fog_texture.update(fog_image)
		_world_fog_dirty = true


func _snap_world_fog_to_grid() -> void:
	if world_fog_image == null or world_fog_texture == null:
		return
	var total: int = grid_width * grid_height
	var full_reveal: bool = post_match_reveal or not fog_enabled or (GameConfig != null and GameConfig.mutator_no_fog)
	for i: int in range(total):
		var vis_f: float = 1.0
		var exp_f: float = 1.0
		if not full_reveal:
			var state: int = _grid[i]
			if state == VisibilityState.VISIBLE:
				vis_f = 1.0
				exp_f = 1.0
			elif state == VisibilityState.EXPLORED:
				vis_f = 0.5
				exp_f = 1.0
			else:
				vis_f = 0.0
				exp_f = 0.0
		_display_vis[i] = vis_f
		_display_exp[i] = exp_f
		var b_idx: int = i * 2
		_world_fog_bytes[b_idx] = clampi(int(round(vis_f * 255.0)), 0, 255)
		_world_fog_bytes[b_idx + 1] = clampi(int(round(exp_f * 255.0)), 0, 255)
	world_fog_image.set_data(grid_width, grid_height, false, Image.FORMAT_RG8, _world_fog_bytes)
	world_fog_texture.update(world_fog_image)
	_world_fog_dirty = false
	world_fog_visual_updated.emit()


func _update_world_fog_display(delta: float) -> void:
	if not _world_fog_dirty or world_fog_image == null or world_fog_texture == null:
		return
	if post_match_reveal or not fog_enabled or (GameConfig != null and GameConfig.mutator_no_fog):
		_snap_world_fog_to_grid()
		return

	var total: int = grid_width * grid_height
	var step_reveal: float = WORLD_FOG_REVEAL_SPEED * delta
	var step_decay: float = WORLD_FOG_DECAY_SPEED * delta
	var still_animating: bool = false

	for i: int in range(total):
		var state: int = _grid[i]
		var target_vis: float = 1.0 if state == VisibilityState.VISIBLE else (0.5 if state == VisibilityState.EXPLORED else 0.0)
		var target_exp: float = 1.0 if state >= VisibilityState.EXPLORED else 0.0

		var cur_vis: float = _display_vis[i]
		if cur_vis < target_vis:
			cur_vis = minf(target_vis, cur_vis + step_reveal)
		elif cur_vis > target_vis:
			cur_vis = maxf(target_vis, cur_vis - step_decay)

		var cur_exp: float = _display_exp[i]
		if cur_exp < target_exp:
			cur_exp = minf(target_exp, cur_exp + step_reveal)
		elif cur_exp > target_exp:
			cur_exp = maxf(target_exp, cur_exp - step_decay)

		if absf(cur_vis - target_vis) > 0.002 or absf(cur_exp - target_exp) > 0.002:
			still_animating = true
		else:
			cur_vis = target_vis
			cur_exp = target_exp

		_display_vis[i] = cur_vis
		_display_exp[i] = cur_exp
		var b_idx: int = i * 2
		_world_fog_bytes[b_idx] = clampi(int(round(cur_vis * 255.0)), 0, 255)
		_world_fog_bytes[b_idx + 1] = clampi(int(round(cur_exp * 255.0)), 0, 255)

	world_fog_image.set_data(grid_width, grid_height, false, Image.FORMAT_RG8, _world_fog_bytes)
	world_fog_texture.update(world_fog_image)
	_world_fog_dirty = still_animating
	world_fog_visual_updated.emit()


func _format_match_time() -> String:
	var elapsed: float = 0.0
	if is_inside_tree():
		var mm: Node = get_tree().get_first_node_in_group("match_manager")
		if mm != null and is_instance_valid(mm):
			var v: Variant = mm.get("match_elapsed")
			if v != null:
				elapsed = maxf(0.0, float(v))
	var total_s: int = int(elapsed)
	@warning_ignore("integer_division")
	var mins: int = total_s / 60
	var secs: int = total_s % 60
	return "%02d:%02d" % [mins, secs]


func _capture_building_ghost_snapshot(building: Building, time_str: String) -> Dictionary:
	var raw_info: Dictionary = building.get_inspection_data()
	var frozen_info: Dictionary = raw_info.duplicate(true)
	frozen_info["subtitle"] = "LAST SEEN IN FOG (%s)" % time_str
	frozen_info["is_commandable"] = false
	frozen_info["readonly_label"] = "LAST KNOWN INTEL — OUT OF VISION"

	var t_angle: float = building.get_turret_angle() if building.has_turret else 0.0

	return {
		"id": building.get_instance_id(),
		"active": false,
		"building_type_id": building.building_type_id,
		"display_name": building.display_name,
		"team": int(building.team),
		"pos": building.global_position,
		"footprint_radius": building.footprint_radius,
		"selection_radius": building.selection_radius,
		"is_command_hub": building.is_command_hub(),
		"is_constructed": building.is_constructed,
		"construction_progress": building.construction_progress,
		"current_hp": building.current_hp,
		"max_hp": building.max_hp,
		"current_shield": building.current_shield,
		"max_shield": building.max_shield,
		"has_turret": building.has_turret,
		"turret_angle": t_angle,
		"turret_tracer_style": building.turret_tracer_style,
		"is_powered": building.is_powered,
		"staffed_count": building.get_assigned_engineer_count(),
		"max_staff_slots": building.max_staff_slots,
		"scouted_time_str": time_str,
		"inspection_snapshot": frozen_info,
	}


func _apply_enemy_visibility(force_reveal_all: bool) -> void:
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed or unit.is_queued_for_deletion():
			continue
		var is_hostile: bool = TeamManager.are_enemies(viewer_team, int(unit.team)) if (TeamManager != null and viewer_team >= 0) else (unit.team != Unit.Team.PLAYER)
		if not is_hostile:
			unit.visible = true
			continue
		unit.visible = true if force_reveal_all else is_world_pos_visible_strict(unit.global_position)

	var ghosts_changed: bool = false
	if force_reveal_all:
		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if not is_instance_valid(node) or not (node is Building):
				continue
			var building: Building = node
			if building.is_destroyed or building.is_queued_for_deletion():
				continue
			building.visible = true
		if not _building_ghosts.is_empty():
			_building_ghosts.clear()
			ghosts_changed = true
	else:
		var seen_live_ids: Dictionary = {}
		var time_str: String = _format_match_time()
		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if not is_instance_valid(node) or not (node is Building):
				continue
			var building: Building = node
			if building.is_destroyed or building.is_queued_for_deletion():
				continue
			var is_hostile_b: bool = TeamManager.are_enemies(viewer_team, int(building.team)) if (TeamManager != null and viewer_team >= 0) else (building.team != Unit.Team.PLAYER)
			if not is_hostile_b:
				building.visible = true
				continue
			var b_id: int = building.get_instance_id()
			if is_world_pos_visible_strict(building.global_position):
				seen_live_ids[b_id] = true
				building.has_been_spotted = true
				building.visible = true
				var was_active: bool = _building_ghosts.has(b_id) and bool((_building_ghosts[b_id] as Dictionary).get("active", false))
				_building_ghosts[b_id] = _capture_building_ghost_snapshot(building, time_str)
				if was_active:
					ghosts_changed = true
			else:
				# Authentic SC2 Fog of War: hide the live hostile building node outside live vision.
				building.visible = false
				if _building_ghosts.has(b_id):
					var g_entry: Dictionary = _building_ghosts[b_id] as Dictionary
					var g_pos: Vector2 = g_entry.get("pos", building.global_position) as Vector2
					if is_world_pos_explored(g_pos) and not bool(g_entry.get("active", false)):
						g_entry["active"] = true
						ghosts_changed = true

		# Re-scout verification pass: clear stale ghosts once the player regains live vision
		# on the ghost's tile and sees the structure is gone (or activate ghosts whose real node died in fog).
		var ghost_keys: Array = _building_ghosts.keys()
		for gid_var: Variant in ghost_keys:
			var gid: int = int(gid_var)
			if seen_live_ids.has(gid):
				continue
			var ghost: Dictionary = _building_ghosts[gid] as Dictionary
			var g_pos: Vector2 = ghost.get("pos", Vector2.ZERO) as Vector2
			if is_world_pos_visible_strict(g_pos):
				_building_ghosts.erase(gid)
				ghosts_changed = true
			elif not is_world_pos_explored(g_pos):
				_building_ghosts.erase(gid)
				ghosts_changed = true
			elif not bool(ghost.get("active", false)):
				ghost["active"] = true
				ghosts_changed = true

	if ghosts_changed:
		building_ghosts_changed.emit()

	for node: Node in get_tree().get_nodes_in_group("salvage_cores"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var sc: Node2D = node as Node2D
		sc.visible = true if force_reveal_all else is_world_pos_explored(sc.global_position)
