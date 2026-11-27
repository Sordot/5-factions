class_name ArenaNavRegion
extends NavigationRegion2D

const NAV_BAKE_GROUP: StringName = &"nav_bake_obstacles"
const MapLandmarkScript = preload("res://scripts/world/map_landmark.gd")

@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
@export var agent_radius: float = 24.0
@export var obstacle_group_name: StringName = &"terrain_obstacles"
@export var rebake_debounce_seconds: float = 0.15

var _rebake_queued: bool = false
var _rebake_pending: bool = false
var _rebake_timer: float = 0.0
var _rebake_wait_elapsed: float = 0.0
var _has_initial_bake: bool = false
var _is_baking: bool = false
var _rebake_queued_during_bake: bool = false


func _ready() -> void:
	add_to_group("arena_nav_region")
	if not bake_finished.is_connected(_on_bake_finished):
		bake_finished.connect(_on_bake_finished)
	_rebake_queued = true
	call_deferred("_perform_initial_rebake")


func _on_bake_finished() -> void:
	_is_baking = false
	if _rebake_queued_during_bake:
		_rebake_queued_during_bake = false
		_rebake_pending = true
		_rebake_timer = maxf(0.05, rebake_debounce_seconds)


func _process(delta: float) -> void:
	if not _rebake_pending:
		return
	_rebake_timer -= delta
	_rebake_wait_elapsed += delta
	if _rebake_timer <= 0.0 or _rebake_wait_elapsed >= maxf(0.35, rebake_debounce_seconds * 2.5):
		_rebake_pending = false
		_rebake_timer = 0.0
		_rebake_wait_elapsed = 0.0
		if _is_baking:
			_rebake_queued_during_bake = true
			return
		if is_inside_tree():
			rebake_navmesh(true)


func request_rebake() -> void:
	if not _has_initial_bake:
		if not _rebake_queued:
			_rebake_queued = true
			call_deferred("_perform_initial_rebake")
		return
	_rebake_pending = true
	_rebake_timer = maxf(0.05, rebake_debounce_seconds)


func _perform_initial_rebake() -> void:
	_rebake_queued = false
	_has_initial_bake = true
	_rebake_pending = false
	_rebake_timer = 0.0
	_rebake_wait_elapsed = 0.0
	if not is_inside_tree():
		return
	rebake_navmesh(false)


func rebake_navmesh(on_thread: bool = true) -> void:
	if not is_inside_tree():
		return
	if _is_baking:
		_rebake_queued_during_bake = true
		return

	# Synchronize nav bake group with all static terrain obstacles, resources, cliffs, and living buildings/scaffolds.
	for old_node: Node in get_tree().get_nodes_in_group(NAV_BAKE_GROUP):
		if not is_instance_valid(old_node):
			continue
		if old_node is Building:
			var b_old: Building = old_node
			if b_old.is_destroyed or b_old.is_queued_for_deletion():
				b_old.remove_from_group(NAV_BAKE_GROUP)
		elif old_node is ResourceNode:
			var rn_old: ResourceNode = old_node
			if rn_old.is_vent or rn_old.is_depleted() or rn_old.is_queued_for_deletion():
				rn_old.remove_from_group(NAV_BAKE_GROUP)

	for node: Node in get_tree().get_nodes_in_group(obstacle_group_name):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			if not node.is_in_group(NAV_BAKE_GROUP):
				node.add_to_group(NAV_BAKE_GROUP)

	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is MapLandmarkScript:
			var lm: MapLandmarkScript = node
			var col_body: StaticBody2D = lm.get_collider_node()
			if lm.has_collision and col_body != null and is_instance_valid(col_body):
				if not col_body.is_in_group(NAV_BAKE_GROUP):
					col_body.add_to_group(NAV_BAKE_GROUP)

	for node: Node in get_tree().get_nodes_in_group("high_ground_plateaus"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		for child: Node in node.get_children():
			if child is StaticBody2D and is_instance_valid(child) and not child.is_queued_for_deletion():
				if ((child as StaticBody2D).collision_layer & 1) != 0 and not child.is_in_group(NAV_BAKE_GROUP):
					child.add_to_group(NAV_BAKE_GROUP)

	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node) or not (node is ResourceNode):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.is_vent or rn.is_depleted() or rn.is_queued_for_deletion():
			if rn.is_in_group(NAV_BAKE_GROUP):
				rn.remove_from_group(NAV_BAKE_GROUP)
		elif not rn.is_in_group(NAV_BAKE_GROUP):
			rn.add_to_group(NAV_BAKE_GROUP)

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion():
			if b.is_in_group(NAV_BAKE_GROUP):
				b.remove_from_group(NAV_BAKE_GROUP)
		elif not b.is_in_group(NAV_BAKE_GROUP):
			b.add_to_group(NAV_BAKE_GROUP)

	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node):
			continue
		if bool(node.get("is_destroyed")) or node.is_queued_for_deletion():
			if node.is_in_group(NAV_BAKE_GROUP):
				node.remove_from_group(NAV_BAKE_GROUP)
		elif not node.is_in_group(NAV_BAKE_GROUP):
			node.add_to_group(NAV_BAKE_GROUP)

	var nav_poly: NavigationPolygon = NavigationPolygon.new()
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav_poly.source_geometry_group_name = NAV_BAKE_GROUP
	nav_poly.parsed_collision_mask = 1
	nav_poly.agent_radius = agent_radius

	var p0: Vector2 = arena_bounds.position
	var p1: Vector2 = Vector2(arena_bounds.end.x, arena_bounds.position.y)
	var p2: Vector2 = arena_bounds.end
	var p3: Vector2 = Vector2(arena_bounds.position.x, arena_bounds.end.y)
	nav_poly.add_outline(PackedVector2Array([p0, p1, p2, p3]))

	navigation_polygon = nav_poly
	_is_baking = on_thread
	bake_navigation_polygon(on_thread)
