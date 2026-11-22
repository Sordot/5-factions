class_name TerrainObstacle
extends StaticBody2D

@export var obstacle_size: Vector2 = Vector2(180.0, 68.0)
@export var chamfer: float = 12.0
@export var fill_color: Color = Color(0.14, 0.19, 0.25, 1.0)
@export var inner_color: Color = Color(0.19, 0.26, 0.34, 1.0)
@export var border_color: Color = Color(0.24, 0.66, 0.76, 0.78)
@export var accent_color: Color = Color(0.18, 0.88, 0.92, 0.50)

var _local_polygon: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_index = 2
	add_to_group("terrain_obstacles")
	_build_geometry()


func _build_geometry() -> void:
	var existing_col: CollisionPolygon2D = get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if existing_col != null and existing_col.polygon.size() >= 3:
		_local_polygon = existing_col.polygon
	else:
		_local_polygon = _create_chamfered_box(obstacle_size, chamfer)
		var col: CollisionPolygon2D = CollisionPolygon2D.new()
		col.name = "CollisionPolygon2D"
		col.polygon = _local_polygon
		add_child(col)

	if get_node_or_null("VisualRoot") == null:
		var visual: Node2D = Node2D.new()
		visual.name = "VisualRoot"
		add_child(visual)

		var outer_poly: Polygon2D = Polygon2D.new()
		outer_poly.name = "OuterBody"
		outer_poly.color = fill_color
		outer_poly.polygon = _local_polygon
		visual.add_child(outer_poly)

		var inset_size: Vector2 = Vector2(
			maxf(12.0, obstacle_size.x - 18.0),
			maxf(12.0, obstacle_size.y - 18.0)
		)
		var inner_poly: Polygon2D = Polygon2D.new()
		inner_poly.name = "InnerDeck"
		inner_poly.color = inner_color
		inner_poly.polygon = _create_chamfered_box(inset_size, maxf(4.0, chamfer * 0.6))
		visual.add_child(inner_poly)

		# Subtle Technozen server-monolith conduit line along the long axis.
		var conduit: Line2D = Line2D.new()
		conduit.name = "ConduitAccent"
		conduit.width = 2.0
		conduit.default_color = accent_color
		conduit.antialiased = true
		if obstacle_size.x >= obstacle_size.y:
			var half_len: float = maxf(8.0, obstacle_size.x * 0.5 - 24.0)
			conduit.points = PackedVector2Array([Vector2(-half_len, 0.0), Vector2(half_len, 0.0)])
		else:
			var half_len: float = maxf(8.0, obstacle_size.y * 0.5 - 24.0)
			conduit.points = PackedVector2Array([Vector2(0.0, -half_len), Vector2(0.0, half_len)])
		visual.add_child(conduit)

		var border: Line2D = Line2D.new()
		border.name = "Border"
		border.points = _local_polygon
		border.closed = true
		border.width = 2.0
		border.default_color = border_color
		border.antialiased = true
		visual.add_child(border)


func get_world_polygon() -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	if _local_polygon.is_empty():
		_local_polygon = _create_chamfered_box(obstacle_size, chamfer)
	pts.resize(_local_polygon.size())
	for i: int in range(_local_polygon.size()):
		pts[i] = global_transform * _local_polygon[i]
	return pts


func overlaps_circle(world_pos: Vector2, radius: float) -> bool:
	if _local_polygon.size() < 3:
		_local_polygon = _create_chamfered_box(obstacle_size, chamfer)
	var local_pt: Vector2 = to_local(world_pos)
	if Geometry2D.is_point_in_polygon(local_pt, _local_polygon):
		return true
	var r_sq: float = radius * radius
	var count: int = _local_polygon.size()
	for i: int in range(count):
		var a: Vector2 = _local_polygon[i]
		var b: Vector2 = _local_polygon[(i + 1) % count]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(local_pt, a, b)
		if local_pt.distance_squared_to(closest) <= r_sq:
			return true
	return false


func _create_chamfered_box(size_vec: Vector2, bevel: float) -> PackedVector2Array:
	var hx: float = maxf(4.0, size_vec.x * 0.5)
	var hy: float = maxf(4.0, size_vec.y * 0.5)
	var c: float = clampf(bevel, 0.0, minf(hx, hy) * 0.45)
	if c <= 0.5:
		return PackedVector2Array([
			Vector2(-hx, -hy),
			Vector2(hx, -hy),
			Vector2(hx, hy),
			Vector2(-hx, hy),
		])
	return PackedVector2Array([
		Vector2(-hx + c, -hy),
		Vector2(hx - c, -hy),
		Vector2(hx, -hy + c),
		Vector2(hx, hy - c),
		Vector2(hx - c, hy),
		Vector2(-hx + c, hy),
		Vector2(-hx, hy - c),
		Vector2(-hx, -hy + c),
	])
