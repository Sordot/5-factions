class_name ArenaNavRegion
extends NavigationRegion2D

@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
@export var agent_radius: float = 24.0
@export var obstacle_group_name: StringName = &"terrain_obstacles"


func _ready() -> void:
	call_deferred("rebake_navmesh")


func rebake_navmesh() -> void:
	var nav_poly: NavigationPolygon = NavigationPolygon.new()
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav_poly.source_geometry_group_name = obstacle_group_name
	nav_poly.parsed_collision_mask = 1
	nav_poly.agent_radius = agent_radius

	var p0: Vector2 = arena_bounds.position
	var p1: Vector2 = Vector2(arena_bounds.end.x, arena_bounds.position.y)
	var p2: Vector2 = arena_bounds.end
	var p3: Vector2 = Vector2(arena_bounds.position.x, arena_bounds.end.y)
	nav_poly.add_outline(PackedVector2Array([p0, p1, p2, p3]))

	navigation_polygon = nav_poly
	bake_navigation_polygon(false)
