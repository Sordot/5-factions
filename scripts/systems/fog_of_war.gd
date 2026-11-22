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
@export var update_interval: float = 0.15
@export var fog_enabled: bool = true

var grid_width: int = 1
var grid_height: int = 1
var fog_image: Image = null
var fog_texture: ImageTexture = null

var _grid: PackedByteArray = PackedByteArray()
var _prev_grid: PackedByteArray = PackedByteArray()
var _spotted_buildings: Dictionary = {}
var _update_timer: float = 0.0


func _ready() -> void:
	add_to_group("fog_of_war")
	_initialize_grid()
	refresh_visibility()
	call_deferred("refresh_visibility")


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < maxf(0.05, update_interval):
		return
	_update_timer = 0.0
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

	fog_image = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	fog_image.fill(COLOR_UNEXPLORED)
	fog_texture = ImageTexture.create_from_image(fog_image)


func set_fog_enabled(enabled: bool) -> void:
	if fog_enabled == enabled:
		return
	fog_enabled = enabled
	refresh_visibility()


func reset_fog() -> void:
	_spotted_buildings.clear()
	_grid.fill(VisibilityState.UNEXPLORED)
	_prev_grid.fill(255)
	refresh_visibility()


func refresh_visibility() -> void:
	if not is_inside_tree() or fog_image == null or fog_texture == null:
		return

	var total: int = grid_width * grid_height
	if not fog_enabled:
		for i: int in range(total):
			_grid[i] = VisibilityState.VISIBLE
		_sync_texture_if_dirty()
		_apply_enemy_visibility(true)
		visibility_updated.emit()
		return

	# Demote previous live vision cells to explored fog memory.
	for i: int in range(total):
		if _grid[i] == VisibilityState.VISIBLE:
			_grid[i] = VisibilityState.EXPLORED

	# Stamp live vision circles for all living Team.PLAYER units.
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed or unit.team != Unit.Team.PLAYER:
			continue
		_reveal_circle(unit.global_position, unit.get_vision_range())

	# Stamp live vision circles for all living Team.PLAYER buildings.
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var building: Building = node
		if building.is_destroyed or building.team != Unit.Team.PLAYER:
			continue
		_reveal_circle(building.global_position, building.get_vision_range())

	_sync_texture_if_dirty()
	_apply_enemy_visibility(false)
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
	if not fog_enabled:
		return VisibilityState.VISIBLE
	var cell: Vector2i = world_to_cell(world_pos)
	return get_visibility_at_cell(cell)


func is_world_pos_visible(world_pos: Vector2) -> bool:
	return get_visibility_at_world_pos(world_pos) == VisibilityState.VISIBLE


func is_world_pos_explored(world_pos: Vector2) -> bool:
	return get_visibility_at_world_pos(world_pos) >= VisibilityState.EXPLORED


func _reveal_circle(world_center: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	var cell_w: float = arena_bounds.size.x / float(grid_width)
	var cell_h: float = arena_bounds.size.y / float(grid_height)
	var eff_radius: float = radius + maxf(cell_w, cell_h) * 0.35
	var eff_radius_sq: float = eff_radius * eff_radius

	var min_cell: Vector2i = world_to_cell(world_center - Vector2(eff_radius, eff_radius))
	var max_cell: Vector2i = world_to_cell(world_center + Vector2(eff_radius, eff_radius))

	for cy: int in range(min_cell.y, max_cell.y + 1):
		var wy: float = arena_bounds.position.y + (float(cy) + 0.5) * cell_h
		var dy: float = wy - world_center.y
		var dy_sq: float = dy * dy
		var row_offset: int = cy * grid_width
		for cx: int in range(min_cell.x, max_cell.x + 1):
			var wx: float = arena_bounds.position.x + (float(cx) + 0.5) * cell_w
			var dx: float = wx - world_center.x
			if dx * dx + dy_sq <= eff_radius_sq:
				_grid[row_offset + cx] = VisibilityState.VISIBLE


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
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed or unit.team != Unit.Team.ENEMY:
			continue
		unit.visible = true if force_reveal_all else is_world_pos_visible(unit.global_position)

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var building: Building = node
		if building.is_destroyed or building.team != Unit.Team.ENEMY:
			continue
		if force_reveal_all:
			building.visible = true
			continue
		var vis_state: int = get_visibility_at_world_pos(building.global_position)
		var b_id: int = building.get_instance_id()
		if vis_state == VisibilityState.VISIBLE:
			_spotted_buildings[b_id] = true
			building.has_been_spotted = true
			building.visible = true
		elif vis_state == VisibilityState.EXPLORED and (_spotted_buildings.has(b_id) or building.has_been_spotted):
			building.visible = true
		else:
			building.visible = false
