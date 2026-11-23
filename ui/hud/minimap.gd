class_name TacticalMinimap
extends Control

@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
@export var camera_path: NodePath
@export var selection_controller_path: NodePath
@export var fog_system_path: NodePath
@export var refresh_rate_hz: float = 20.0

@onready var map_viewport: Control = %MapViewport
@onready var status_badge: Label = %StatusBadge

var _camera: RTSCamera = null
var _selection_controller: SelectionController = null
var _fog_system: FogOfWarSystem = null
var _is_left_dragging: bool = false
var _redraw_timer: float = 0.0
var _ping_pos: Vector2 = Vector2.ZERO
var _ping_color: Color = Color(0.24, 0.96, 0.90, 1.0)
var _ping_timer: float = 0.0


func _ready() -> void:
	add_to_group("tactical_minimap")
	if map_viewport != null:
		map_viewport.add_to_group("blocks_edge_pan")
		map_viewport.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if not map_viewport.draw.is_connected(_on_map_viewport_draw):
			map_viewport.draw.connect(_on_map_viewport_draw)
		if not map_viewport.gui_input.is_connected(_on_map_viewport_gui_input):
			map_viewport.gui_input.connect(_on_map_viewport_gui_input)
	call_deferred("_resolve_references")


func _resolve_references() -> void:
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as RTSCamera
	if _camera == null and is_inside_tree():
		_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera

	if not selection_controller_path.is_empty():
		_selection_controller = get_node_or_null(selection_controller_path) as SelectionController

	if not fog_system_path.is_empty():
		_fog_system = get_node_or_null(fog_system_path) as FogOfWarSystem
	if _fog_system == null and is_inside_tree():
		_fog_system = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if _fog_system != null:
		arena_bounds = _fog_system.arena_bounds
		if not _fog_system.visibility_updated.is_connected(_on_fog_updated):
			_fog_system.visibility_updated.connect(_on_fog_updated)

	if map_viewport != null:
		map_viewport.queue_redraw()


func _process(delta: float) -> void:
	if _ping_timer > 0.0:
		_ping_timer = maxf(0.0, _ping_timer - delta)

	_redraw_timer += delta
	var interval: float = 1.0 / maxf(5.0, refresh_rate_hz)
	if _redraw_timer >= interval:
		_redraw_timer = 0.0
		if map_viewport != null:
			map_viewport.queue_redraw()
		if status_badge != null and _fog_system != null:
			status_badge.text = "FOG: ON" if _fog_system.fog_enabled else "FOG: OFF"


func _on_fog_updated() -> void:
	if map_viewport != null:
		map_viewport.queue_redraw()


func _on_map_viewport_gui_input(event: InputEvent) -> void:
	if map_viewport == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_left_dragging = true
				_move_camera_to_minimap_point(mb.position)
				map_viewport.accept_event()
			else:
				_is_left_dragging = false
				map_viewport.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_issue_order_at_minimap_point(mb.position)
			map_viewport.accept_event()
	elif event is InputEventMouseMotion and _is_left_dragging:
		var mm: InputEventMouseMotion = event
		_move_camera_to_minimap_point(mm.position)
		map_viewport.accept_event()


func _move_camera_to_minimap_point(local_pos: Vector2) -> void:
	if _camera == null:
		_resolve_references()
	if _camera == null:
		return
	var world_pos: Vector2 = _minimap_to_world(local_pos)
	_camera.center_on(world_pos)
	if map_viewport != null:
		map_viewport.queue_redraw()


func _issue_order_at_minimap_point(local_pos: Vector2) -> void:
	if _selection_controller == null:
		_resolve_references()
	if _selection_controller == null:
		return
	var world_pos: Vector2 = _minimap_to_world(local_pos)
	var is_attack_move: bool = Input.is_action_pressed("cmd_attack_move") or Input.is_key_pressed(KEY_A)
	var shift_queued: bool = Input.is_key_pressed(KEY_SHIFT)
	if is_attack_move:
		_selection_controller.issue_attack_move_at(world_pos, shift_queued)
		_ping_color = Color(1.0, 0.36, 0.28, 1.0)
	else:
		_selection_controller.issue_right_click_at(world_pos, shift_queued)
		_ping_color = Color(0.24, 0.96, 0.88, 1.0)
	_ping_pos = _world_to_minimap(world_pos)
	_ping_timer = 0.45
	if map_viewport != null:
		map_viewport.queue_redraw()


func _on_map_viewport_draw() -> void:
	if map_viewport == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, map_viewport.size)
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return

	# 1. Arena backdrop + subtle tactical grid.
	map_viewport.draw_rect(rect, Color(0.06, 0.09, 0.13, 1.0), true)
	var grid_col: Color = Color(0.14, 0.24, 0.32, 0.35)
	for i: int in range(1, 4):
		var gx: float = rect.size.x * float(i) * 0.25
		var gy: float = rect.size.y * float(i) * 0.25
		map_viewport.draw_line(Vector2(gx, 0.0), Vector2(gx, rect.size.y), grid_col, 1.0)
		map_viewport.draw_line(Vector2(0.0, gy), Vector2(rect.size.x, gy), grid_col, 1.0)

	# 2. Terrain obstacle silhouettes.
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if not is_instance_valid(node) or not node.has_method("get_world_polygon"):
			continue
		var world_poly: PackedVector2Array = node.get_world_polygon()
		if world_poly.size() < 3:
			continue
		var mini_poly: PackedVector2Array = PackedVector2Array()
		mini_poly.resize(world_poly.size())
		for i: int in range(world_poly.size()):
			mini_poly[i] = _world_to_minimap(world_poly[i])
		map_viewport.draw_colored_polygon(mini_poly, Color(0.24, 0.32, 0.40, 0.96))
		map_viewport.draw_polyline(mini_poly + PackedVector2Array([mini_poly[0]]), Color(0.36, 0.62, 0.72, 0.65), 1.0)

	# 3. Resource nodes (Biomass, Silica, Compute Vents).
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted():
			continue
		var p: Vector2 = _world_to_minimap(rn.global_position)
		if rn.is_vent:
			map_viewport.draw_arc(p, 3.2, 0.0, TAU, 10, Color(0.28, 0.88, 1.0, 0.9), 1.2)
		elif rn.resource_type == &"silica":
			map_viewport.draw_circle(p, 2.3, Color(0.98, 0.78, 0.28, 0.95))
		else:
			map_viewport.draw_circle(p, 2.2, Color(0.24, 0.94, 0.56, 0.92))

	# 4. Central Data Hyper-Uplink.
	for node: Node in get_tree().get_nodes_in_group("hyper_uplinks"):
		if not (node is HyperUplink) or not is_instance_valid(node):
			continue
		var uplink: HyperUplink = node
		var up: Vector2 = _world_to_minimap(uplink.global_position)
		var live_vis: bool = _fog_system == null or not _fog_system.fog_enabled or _fog_system.is_world_pos_visible(uplink.global_position)
		var u_col: Color = Color(0.64, 0.74, 0.84, 0.85)
		if live_vis:
			if uplink.is_contested:
				u_col = Color(1.0, 0.80, 0.24, 1.0)
			elif uplink.controlling_team == int(Unit.Team.PLAYER):
				u_col = Color(0.18, 0.98, 0.90, 1.0)
			elif uplink.controlling_team == int(Unit.Team.ENEMY):
				u_col = Color(1.0, 0.34, 0.28, 1.0)
		var scale_x: float = rect.size.x / maxf(1.0, arena_bounds.size.x)
		map_viewport.draw_arc(up, maxf(6.0, uplink.capture_radius * scale_x), 0.0, TAU, 24, Color(u_col.r, u_col.g, u_col.b, 0.65), 1.2)
		map_viewport.draw_circle(up, 3.0, u_col)

	# 5. Fog of War shroud overlay over terrain/resources/uplink.
	if _fog_system != null and _fog_system.fog_enabled and _fog_system.fog_texture != null:
		map_viewport.draw_texture_rect(_fog_system.fog_texture, rect, false)

	# 6. Encroaching Zone perimeter ring.
	var zone: EncroachingZone = get_tree().get_first_node_in_group("encroaching_zone") as EncroachingZone
	if zone != null and zone.active:
		var zc: Vector2 = _world_to_minimap(zone.global_position + zone.zone_center)
		var zr: float = zone.current_radius * (rect.size.x / maxf(1.0, arena_bounds.size.x))
		map_viewport.draw_arc(zc, zr, 0.0, TAU, 48, Color(1.0, 0.30, 0.40, 0.55), 1.1)

	# 7. Buildings (Friendly cyan/green; Enemy red if spotted/visible).
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed:
			continue
		if b.team == Unit.Team.ENEMY and not b.visible:
			continue
		var bp: Vector2 = _world_to_minimap(b.global_position)
		var sz: float = 6.5 if (b.building_type_id == &"nexus_vat" or b.building_type_id == &"command_core") else 4.6
		var col: Color = Color(0.22, 0.96, 0.88, 1.0) if b.team == Unit.Team.PLAYER else Color(1.0, 0.32, 0.26, 0.95)
		if b.team == Unit.Team.ENEMY and _fog_system != null and _fog_system.fog_enabled and not _fog_system.is_world_pos_visible(b.global_position):
			col = Color(0.82, 0.32, 0.28, 0.65)
		map_viewport.draw_rect(Rect2(bp - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), col, true)

	# 8. Units (Friendly cyan/green; Visible Enemy red).
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node
		if u.is_dead or u.is_staffed:
			continue
		if u.team == Unit.Team.ENEMY and not u.visible:
			continue
		var upos: Vector2 = _world_to_minimap(u.global_position)
		var ucol: Color = Color(1.0, 0.30, 0.24, 1.0)
		if u.team == Unit.Team.PLAYER:
			if u.get_unit_type_id() == &"worker" or u.get_unit_type_id() == &"silica_harvester":
				ucol = Color(0.32, 0.98, 0.60, 1.0)
			elif u.get_unit_type_id() == &"scout_unit" or u.get_unit_type_id() == &"stinger":
				ucol = Color(0.98, 0.86, 0.32, 1.0)
			else:
				ucol = Color(0.26, 0.96, 1.0, 1.0)
		map_viewport.draw_circle(upos, 2.3, ucol)

	# 9. Minimap command ping ripple.
	if _ping_timer > 0.0:
		var pt: float = 1.0 - (_ping_timer / 0.45)
		var ring_col: Color = _ping_color
		ring_col.a = (1.0 - pt) * 0.95
		map_viewport.draw_arc(_ping_pos, lerpf(3.0, 13.0, pt), 0.0, TAU, 16, ring_col, 1.6)

	# 10. White Camera Viewport Rectangle.
	if _camera != null and is_instance_valid(_camera):
		var vp_size: Vector2 = get_viewport().get_visible_rect().size / _camera.zoom
		var cam_world_rect: Rect2 = Rect2(_camera.global_position - vp_size * 0.5, vp_size)
		var tl: Vector2 = _world_to_minimap(cam_world_rect.position)
		var br: Vector2 = _world_to_minimap(cam_world_rect.end)
		var cam_mini: Rect2 = Rect2(tl, br - tl).intersection(rect)
		if cam_mini.has_area():
			map_viewport.draw_rect(cam_mini, Color(0.96, 0.99, 1.0, 0.92), false, 1.5)

	# Crisp outer frame line.
	map_viewport.draw_rect(rect.grow(-0.5), Color(0.22, 0.68, 0.78, 0.85), false, 1.2)


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var sz: Vector2 = map_viewport.size
	var nx: float = (world_pos.x - arena_bounds.position.x) / maxf(1.0, arena_bounds.size.x)
	var ny: float = (world_pos.y - arena_bounds.position.y) / maxf(1.0, arena_bounds.size.y)
	return Vector2(nx * sz.x, ny * sz.y)


func _minimap_to_world(local_pos: Vector2) -> Vector2:
	var sz: Vector2 = map_viewport.size
	var nx: float = clampf(local_pos.x / maxf(1.0, sz.x), 0.0, 1.0)
	var ny: float = clampf(local_pos.y / maxf(1.0, sz.y), 0.0, 1.0)
	return Vector2(
		arena_bounds.position.x + nx * arena_bounds.size.x,
		arena_bounds.position.y + ny * arena_bounds.size.y
	)
