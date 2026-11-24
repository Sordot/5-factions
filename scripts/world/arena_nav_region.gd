class_name ArenaNavRegion
extends NavigationRegion2D

const NAV_BAKE_GROUP: StringName = &"nav_bake_obstacles"
const MapLandmarkScript = preload("res://scripts/world/map_landmark.gd")

@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
@export var agent_radius: float = 24.0
@export var obstacle_group_name: StringName = &"terrain_obstacles"

var _rebake_queued: bool = false


func _ready() -> void:
	add_to_group("arena_nav_region")
	request_rebake()


func request_rebake() -> void:
	if _rebake_queued:
		return
	_rebake_queued = true
	call_deferred("_perform_deferred_rebake")


func _perform_deferred_rebake() -> void:
	_rebake_queued = false
	if not is_inside_tree():
		return
	rebake_navmesh()


func rebake_navmesh() -> void:
	if not is_inside_tree():
		return

	# Synchronize nav bake group with all static terrain obstacles and living buildings/scaffolds.
	for old_node: Node in get_tree().get_nodes_in_group(NAV_BAKE_GROUP):
		if not is_instance_valid(old_node):
			continue
		if old_node is Building:
			var b_old: Building = old_node
			if b_old.is_destroyed or b_old.is_queued_for_deletion():
				b_old.remove_from_group(NAV_BAKE_GROUP)

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

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion():
			if b.is_in_group(NAV_BAKE_GROUP):
				b.remove_from_group(NAV_BAKE_GROUP)
		elif not b.is_in_group(NAV_BAKE_GROUP):
			b.add_to_group(NAV_BAKE_GROUP)

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
	bake_navigation_polygon(false)
