class_name HighGroundPlateau
extends Node2D

## Procedural 2D elevated terrace (Milestone 3.4).
## Generates impassable cliff colliders along non-ramp edges while keeping wide
## walkable ramps open for ArenaNavRegion baking, renders crisp dropped cliff
## extrusions & ramp chevrons, and feeds one-way high-ground vision into FogOfWar.

@export var plateau_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-110.0, -85.0),
	Vector2(110.0, -85.0),
	Vector2(110.0, 85.0),
	Vector2(-110.0, 85.0),
])
@export var ramp_edge_indices: PackedInt32Array = PackedInt32Array()
@export var elevation_level: int = 1
@export var biome_tint: Color = Color(0.14, 0.20, 0.26, 1.0)
@export var cliff_thickness: float = 12.0
@export var cliff_drop_height: float = 14.0

var _cliff_segments: Array[Dictionary] = []
var _ramp_segments: Array[Dictionary] = []
var _cliff_bodies: Array[StaticBody2D] = []
var _bounds_local: Rect2 = Rect2()


func _ready() -> void:
	z_index = -50
	set_process(false)
	set_physics_process(false)
	add_to_group("high_ground_plateaus")
	_rebuild_geometry()
	queue_redraw()


func _rebuild_geometry() -> void:
	for body: StaticBody2D in _cliff_bodies:
		if is_instance_valid(body):
			body.queue_free()
	_cliff_bodies.clear()
	_cliff_segments.clear()
	_ramp_segments.clear()

	var n: int = plateau_polygon.size()
	if n < 3:
		_bounds_local = Rect2()
		return

	# Compute local AABB and signed area (in Godot Y-down: positive signed area = clockwise).
	var min_p: Vector2 = plateau_polygon[0]
	var max_p: Vector2 = plateau_polygon[0]
	var signed_area2: float = 0.0
	for i: int in range(n):
		var v0: Vector2 = plateau_polygon[i]
		var v1: Vector2 = plateau_polygon[(i + 1) % n]
		min_p.x = minf(min_p.x, v0.x)
		min_p.y = minf(min_p.y, v0.y)
		max_p.x = maxf(max_p.x, v0.x)
		max_p.y = maxf(max_p.y, v0.y)
		signed_area2 += (v0.x * v1.y - v1.x * v0.y)
	_bounds_local = Rect2(min_p, max_p - min_p)
	var is_cw: bool = signed_area2 >= 0.0

	var ramp_lookup: Dictionary = {}
	for r_idx: int in ramp_edge_indices:
		ramp_lookup[r_idx] = true

	for i: int in range(n):
		var a: Vector2 = plateau_polygon[i]
		var b: Vector2 = plateau_polygon[(i + 1) % n]
		var edge: Vector2 = b - a
		var edge_len: float = edge.length()
		if edge_len <= 1.0:
			continue
		var dir: Vector2 = edge / edge_len
		# Outward normal in Y-down coordinates: for CW polygon, outward is (dir.y, -dir.x)
		var out_n: Vector2 = Vector2(dir.y, -dir.x) if is_cw else Vector2(-dir.y, dir.x)
		var seg_info: Dictionary = {
			"a": a,
			"b": b,
			"dir": dir,
			"len": edge_len,
			"out_normal": out_n,
		}
		if ramp_lookup.has(i):
			_ramp_segments.append(seg_info)
		else:
			_cliff_segments.append(seg_info)
			_spawn_cliff_collider(a, b, edge_len, dir, i)


func _spawn_cliff_collider(a: Vector2, b: Vector2, edge_len: float, dir: Vector2, edge_idx: int) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "CliffWall_%d" % edge_idx
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = (a + b) * 0.5
	body.rotation = dir.angle()
	body.add_to_group("nav_bake_obstacles")
	body.add_to_group("high_ground_cliffs")

	var col_shape: CollisionShape2D = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(edge_len + 4.0, maxf(6.0, cliff_thickness))
	col_shape.shape = rect_shape
	body.add_child(col_shape)

	add_child(body)
	_cliff_bodies.append(body)


func contains_world_point(world_pos: Vector2) -> bool:
	if plateau_polygon.size() < 3:
		return false
	var lp: Vector2 = to_local(world_pos)
	if not _bounds_local.has_point(lp):
		return false
	return Geometry2D.is_point_in_polygon(lp, plateau_polygon)


func get_world_polygon() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(plateau_polygon.size())
	for i: int in range(plateau_polygon.size()):
		out[i] = to_global(plateau_polygon[i])
	return out


func overlaps_cliff_wall(world_pos: Vector2, radius: float) -> bool:
	if _cliff_segments.is_empty():
		return false
	var lp: Vector2 = to_local(world_pos)
	var pad: float = maxf(0.0, radius) + cliff_thickness * 0.5
	if not _bounds_local.grow(pad + 6.0).has_point(lp):
		return false
	var pad_sq: float = pad * pad
	for seg: Dictionary in _cliff_segments:
		var a: Vector2 = seg["a"] as Vector2
		var b: Vector2 = seg["b"] as Vector2
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(lp, a, b)
		if lp.distance_squared_to(closest) <= pad_sq:
			return true
	return false


func _draw() -> void:
	if plateau_polygon.size() < 3:
		return

	var drop: Vector2 = Vector2(0.0, cliff_drop_height)
	var shadow_col: Color = Color(0.02, 0.03, 0.05, 0.58)
	var wall_dark: Color = biome_tint.darkened(0.56)
	wall_dark.a = 0.98
	var wall_stripe: Color = biome_tint.darkened(0.72)
	wall_stripe.a = 0.72
	var rim_dark: Color = Color(0.03, 0.05, 0.08, 0.92)
	var rim_hi: Color = biome_tint.lightened(0.32)
	rim_hi.a = 0.85

	# 1. Soft ground shadow beneath plateau footprint
	var shadow_poly: PackedVector2Array = PackedVector2Array()
	shadow_poly.resize(plateau_polygon.size())
	for i: int in range(plateau_polygon.size()):
		shadow_poly[i] = plateau_polygon[i] + Vector2(3.0, cliff_drop_height + 5.0)
	draw_colored_polygon(shadow_poly, shadow_col)

	# 2. Dropped cliff-wall extrusions on bottom/side-facing non-ramp edges
	for seg: Dictionary in _cliff_segments:
		var out_n: Vector2 = seg["out_normal"] as Vector2
		if out_n.y <= -0.25:
			continue
		var a: Vector2 = seg["a"] as Vector2
		var b: Vector2 = seg["b"] as Vector2
		var edge_len: float = float(seg["len"])
		var quad: PackedVector2Array = PackedVector2Array([a, b, b + drop, a + drop])
		draw_colored_polygon(quad, wall_dark)
		# Vertical cliff striations
		var stripe_cnt: int = maxi(2, int(floor(edge_len / 24.0)))
		for s: int in range(1, stripe_cnt):
			var frac: float = float(s) / float(stripe_cnt)
			var top_p: Vector2 = a.lerp(b, frac)
			draw_line(top_p, top_p + drop, wall_stripe, 1.3)
		draw_line(a + drop, b + drop, rim_dark, 1.8)

	# 3. Sloped walkable ramp aprons + side guide rails + ramp-step chevrons
	var ramp_depth: float = 24.0
	var ramp_fill: Color = biome_tint.darkened(0.22)
	ramp_fill.a = 0.92
	var rail_col: Color = biome_tint.lightened(0.38)
	rail_col.a = 0.72
	var step_col: Color = biome_tint.lightened(0.26)
	step_col.a = 0.48
	for rseg: Dictionary in _ramp_segments:
		var a: Vector2 = rseg["a"] as Vector2
		var b: Vector2 = rseg["b"] as Vector2
		var out_n: Vector2 = rseg["out_normal"] as Vector2
		var edge_dir: Vector2 = rseg["dir"] as Vector2
		var a_out: Vector2 = a + out_n * ramp_depth
		var b_out: Vector2 = b + out_n * ramp_depth
		var apron: PackedVector2Array = PackedVector2Array([a, b, b_out, a_out])
		draw_colored_polygon(apron, ramp_fill)
		# Side guide rails framing the walkable ramp
		draw_line(a, a_out, rail_col, 2.4, true)
		draw_line(b, b_out, rail_col, 2.4, true)
		# 3 parallel ramp-step tread lines sloping from Level 0 up to Level 1
		for st: int in range(1, 4):
			var d_frac: float = float(st) / 4.0
			var p0: Vector2 = a.lerp(a_out, d_frac) + edge_dir * 8.0
			var p1: Vector2 = b.lerp(b_out, d_frac) - edge_dir * 8.0
			draw_line(p0, p1, step_col, 1.4, true)
		# Subtle uphill chevron at center of ramp pointing onto plateau (-out_n)
		var r_mid: Vector2 = (a + b) * 0.5 + out_n * (ramp_depth * 0.52)
		var tip: Vector2 = r_mid - out_n * 6.5
		var wing_l: Vector2 = r_mid + out_n * 3.5 - edge_dir * 12.0
		var wing_r: Vector2 = r_mid + out_n * 3.5 + edge_dir * 12.0
		draw_polyline(PackedVector2Array([wing_l, tip, wing_r]), rail_col, 1.8, true)

	# 4. Raised Level 1 plateau deck fill
	draw_colored_polygon(plateau_polygon, biome_tint)

	# Subtle recessed terrace grid / tactical deck inset outline
	var center: Vector2 = _bounds_local.get_center()
	var inset_poly: PackedVector2Array = PackedVector2Array()
	inset_poly.resize(plateau_polygon.size())
	for i: int in range(plateau_polygon.size()):
		var v: Vector2 = plateau_polygon[i]
		var to_c: Vector2 = (center - v)
		var to_c_len: float = to_c.length()
		inset_poly[i] = v + (to_c / to_c_len) * 8.0 if to_c_len > 12.0 else v
	var inset_closed: PackedVector2Array = inset_poly + PackedVector2Array([inset_poly[0]])
	var inset_col: Color = biome_tint.lightened(0.18)
	inset_col.a = 0.34
	draw_polyline(inset_closed, inset_col, 1.2, true)

	# 5. Crisp 2px bevel outline strictly on cliff edges (leaving ramp lips cleanly open)
	for seg: Dictionary in _cliff_segments:
		var a: Vector2 = seg["a"] as Vector2
		var b: Vector2 = seg["b"] as Vector2
		var out_n: Vector2 = seg["out_normal"] as Vector2
		draw_line(a, b, rim_dark, 3.2, true)
		draw_line(a - out_n * 1.4, b - out_n * 1.4, rim_hi, 1.6, true)
