class_name FogOfWarSystem
extends Node

enum VisibilityState {
	UNEXPLORED = 0,
	EXPLORED = 1,
	VISIBLE = 2,
}

signal visibility_updated

const COLOR_UNEXPLORED: Color = Color(0.02, 0.03, 0.05, 0.92)
const COLOR_EXPLORED: Color = Color(0.03, 0.05, 0.08, 0.50)
const COLOR_VISIBLE: Color = Color(0.0, 0.0, 0.0, 0.0)

@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
@export var cell_size: float = 64.0
@export var update_interval: float = 0.14
@export var fog_enabled: bool = true
@export var los_shadowing_enabled: bool = true

var post_match_reveal: bool = false
var grid_width: int = 1
var grid_height: int = 1
var fog_image: Image = null
var fog_texture: ImageTexture = null

var _grid: PackedByteArray = PackedByteArray()
var _prev_grid: PackedByteArray = PackedByteArray()
var _blocker_grid: PackedByteArray = PackedByteArray()
var _elevation_grid: PackedByteArray = PackedByteArray()
var _static_building_vision_cells: Dictionary = {}
var _spotted_buildings: Dictionary = {}
## Local alliance's high-ground & sensor-relay vision sources captured on each refresh_visibility() pass.
## Guarantees sub-cell precision at ramp crests so low-ground units cannot see past the crest via 64px cell bleed.
var _viewer_elevated_sources: Array[Dictionary] = []
var _update_timer: float = 0.0
var _blocker_dirty: bool = true


func _ready() -> void:
	add_to_group("fog_of_war")
	if (TeamManager != null and TeamManager.is_spectator_mode()) or (GameConfig != null and GameConfig.mutator_no_fog):
		fog_enabled = false
	_initialize_grid()
	call_deferred("_post_ready_init")


func _post_ready_init() -> void:
	rebuild_blocker_grid()
	refresh_visibility()


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < maxf(0.05, update_interval):
		return
	_update_timer = 0.0
	if _blocker_dirty:
		rebuild_blocker_grid()
	refresh_visibility()


func _initialize_grid() -> void:
	var safe_cell: float = maxf(16.0, cell_size)
	grid_width = maxi(1, ceili(arena_bounds.size.x / safe_cell))
	grid_height = maxi(1, ceili(arena_bounds.size.y / safe_cell))
	var total: int = grid_width * grid_height

	_grid.resize(total)
	_grid.fill(VisibilityState.UNEXPLORED)
	_prev_grid.resize(total)
	_prev_grid.fill(255) # Force initial texture paint.
	_blocker_grid.resize(total)
	_blocker_grid.fill(0)
	_elevation_grid.resize(total)
	_elevation_grid.fill(0)
	_static_building_vision_cells.clear()
	_viewer_elevated_sources.clear()
	_blocker_dirty = true

	fog_image = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	fog_image.fill(COLOR_UNEXPLORED)
	fog_texture = ImageTexture.create_from_image(fog_image)


func invalidate_building_vision_cache() -> void:
	_static_building_vision_cells.clear()


func rebuild_static_grids(new_bounds: Rect2 = Rect2()) -> void:
	if new_bounds.has_area():
		arena_bounds = new_bounds
	_initialize_grid()
	rebuild_blocker_grid()
	refresh_visibility()


func rebuild_blocker_grid() -> void:
	_blocker_dirty = false
	_static_building_vision_cells.clear()
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
	var qx: float = cell_w * 0.28
	var qy: float = cell_h * 0.28

	var plateaus: Array = []
	for p_node: Node in get_tree().get_nodes_in_group("high_ground_plateaus"):
		if is_instance_valid(p_node) and (p_node.has_method("get_world_elevation_at") or p_node.has_method("contains_world_point")):
			plateaus.append(p_node)

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

	if blockers.is_empty() and plateaus.is_empty():
		return

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
			# Sample center + 4 sub-quadrants so plateau edges block low-ground LOS cleanly right up to the crest.
			var best_elev: int = 0
			for pl: Variant in plateaus:
				var pl_node: Node = pl as Node
				var e_val: int = _sample_plateau_elev(pl_node, pt)
				if e_val == 0:
					e_val = maxi(
						maxi(_sample_plateau_elev(pl_node, Vector2(wx - qx, wy - qy)), _sample_plateau_elev(pl_node, Vector2(wx + qx, wy - qy))),
						maxi(_sample_plateau_elev(pl_node, Vector2(wx - qx, wy + qy)), _sample_plateau_elev(pl_node, Vector2(wx + qx, wy + qy)))
					)
				if e_val > best_elev:
					best_elev = e_val
			if best_elev > 0:
				_elevation_grid[idx] = best_elev


func _sample_plateau_elev(pl_node: Node, world_pt: Vector2) -> int:
	if pl_node.has_method("get_world_elevation_at"):
		return int(pl_node.call("get_world_elevation_at", world_pt))
	if pl_node.has_method("contains_world_point") and bool(pl_node.call("contains_world_point", world_pt)):
		return int(pl_node.get("elevation_level"))
	return 0


## Exact continuous world elevation query aligned with HighGroundPlateau upper crest lines.
## Never falls back to the coarse 64px grid while in-tree so standing at the foot of a ramp
## always evaluates strictly as Elevation 0.
func get_elevation_at(world_pos: Vector2) -> int:
	if is_inside_tree():
		var best_elev: int = 0
		for p_node: Node in get_tree().get_nodes_in_group("high_ground_plateaus"):
			if is_instance_valid(p_node):
				var ev: int = _sample_plateau_elev(p_node, world_pos)
				if ev > best_elev:
					best_elev = ev
		return best_elev
	if _elevation_grid.is_empty():
		return 0
	var cell: Vector2i = world_to_cell(world_pos)
	return int(_elevation_grid[cell.y * grid_width + cell.x])


## Strict local-viewer visibility check with sub-cell ramp-crest precision:
## Prevents 64px fog grid cells straddling a cliff/ramp crest from leaking an Elevation 1
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
	var spot_units: Array = SpatialGrid.query_units_in_radius(world_pos, 560.0) if SpatialGrid != null else get_tree().get_nodes_in_group("units")
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
	var spot_bldgs: Array = SpatialGrid.query_buildings_in_radius(world_pos, 560.0) if SpatialGrid != null else get_tree().get_nodes_in_group("buildings")
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
	refresh_visibility()


func set_post_match_reveal(enabled: bool) -> void:
	if post_match_reveal == enabled:
		return
	post_match_reveal = enabled
	_prev_grid.fill(255)
	refresh_visibility()


func reset_fog() -> void:
	_spotted_buildings.clear()
	_static_building_vision_cells.clear()
	_viewer_elevated_sources.clear()
	_grid.fill(VisibilityState.UNEXPLORED)
	_prev_grid.fill(255)
	rebuild_blocker_grid()
	refresh_visibility()


func refresh_visibility() -> void:
	if not is_inside_tree() or fog_image == null or fog_texture == null:
		return

	var total: int = grid_width * grid_height
	if post_match_reveal or not fog_enabled or (GameConfig != null and GameConfig.mutator_no_fog):
		for i: int in range(total):
			_grid[i] = VisibilityState.VISIBLE
		_viewer_elevated_sources.clear()
		_sync_texture_if_dirty()
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

	# Stamp live LOS vision for all living allied units (or all active teams in Spectator Mode).
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed or unit.is_queued_for_deletion():
			continue
		var grants_vision: bool = spectator or (TeamManager.are_allies(viewer_team, int(unit.team)) if TeamManager != null else (unit.team == Unit.Team.PLAYER))
		if not grants_vision:
			continue
		var u_vr: float = unit.get_vision_range()
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
		var grants_vision_b: bool = spectator or (TeamManager.are_allies(viewer_team, int(building.team)) if TeamManager != null else (building.team == Unit.Team.PLAYER))
		if not grants_vision_b:
			continue
		var b_vr: float = building.get_vision_range()
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
	var dirty: bool = false
	for cy: int in range(grid_height):
		var row_offset: int = cy * grid_width
		for cx: int in range(grid_width):
			var idx: int = row_offset + cx
			var val: int = _grid[idx]
			if _prev_grid[idx] == val:
				continue
			_prev_grid[idx] = val
			dirty = true
			if val == VisibilityState.VISIBLE:
				fog_image.set_pixel(cx, cy, COLOR_VISIBLE)
			elif val == VisibilityState.EXPLORED:
				fog_image.set_pixel(cx, cy, COLOR_EXPLORED)
			else:
				fog_image.set_pixel(cx, cy, COLOR_UNEXPLORED)
	if dirty:
		fog_texture.update(fog_image)


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
		if force_reveal_all:
			building.visible = true
			continue
		var b_id: int = building.get_instance_id()
		if is_world_pos_visible_strict(building.global_position):
			_spotted_buildings[b_id] = true
			building.has_been_spotted = true
			building.visible = true
		elif is_world_pos_explored(building.global_position) and (_spotted_buildings.has(b_id) or building.has_been_spotted):
			building.visible = true
		else:
			building.visible = false

	for node: Node in get_tree().get_nodes_in_group("salvage_cores"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var sc: Node2D = node as Node2D
		sc.visible = true if force_reveal_all else is_world_pos_explored(sc.global_position)
