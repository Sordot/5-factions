class_name HighGroundPlateau
extends Node2D

## Procedural 2D elevated terrace (Milestones 3.4 & 3.8).
## Generates corner-inset impassable cliff colliders along non-ramp edges while keeping
## wide walkable assault ramps (180-220 px default; 105-125 px opt-in choke ramps) cleanly open
## for ArenaNavRegion baking, renders dropped cliff extrusions & sloped ramp aprons extending
## outward from the Level 1 crest line onto Level 0 ground, and feeds SC2-accurate elevation into FogOfWar.

const DEFAULT_WIDE_RAMP_MIN_WIDTH: float = 180.0
const DEFAULT_WIDE_RAMP_MAX_WIDTH: float = 220.0
const CHOKE_RAMP_MIN_WIDTH: float = 105.0
const CHOKE_RAMP_MAX_WIDTH: float = 125.0
const RAMP_SLOPE_DEPTH: float = 32.0
const RAMP_CORNER_INSET: float = 5.0

@export var plateau_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-115.0, -105.0),
	Vector2(85.0, -105.0),
	Vector2(125.0, -65.0),
	Vector2(125.0, 115.0),
	Vector2(-80.0, 115.0),
	Vector2(-115.0, 85.0),
])
@export var ramp_edge_indices: PackedInt32Array = PackedInt32Array()
## Opt-in narrow choke ramp override for specialized hand-crafted map chokes (105-125 px).
## Empty by default: standard plateau ramps use wide assault geometry (180-220 px).
@export var choke_ramp_edge_indices: PackedInt32Array = PackedInt32Array()
@export var elevation_level: int = 1
@export var biome_tint: Color = Color(0.14, 0.20, 0.26, 1.0)
@export var rim_highlight_override: Color = Color(0.0, 0.0, 0.0, 0.0)
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


func is_edge_choke_ramp(edge_idx: int) -> bool:
	return choke_ramp_edge_indices.has(edge_idx)


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
			"edge_idx": i,
			"a": a,
			"b": b,
			"dir": dir,
			"len": edge_len,
			"out_normal": out_n,
			"is_choke": is_edge_choke_ramp(i),
		}
		if ramp_lookup.has(i):
			_ramp_segments.append(seg_info)
		else:
			_cliff_segments.append(seg_info)
			var prev_idx: int = (i - 1 + n) % n
			var next_idx: int = (i + 1) % n
			var start_inset: float = RAMP_CORNER_INSET if ramp_lookup.has(prev_idx) else -2.0
			var end_inset: float = RAMP_CORNER_INSET if ramp_lookup.has(next_idx) else -2.0
			_spawn_cliff_collider(a, b, edge_len, dir, i, start_inset, end_inset)


func _spawn_cliff_collider(
	a: Vector2,
	b: Vector2,
	edge_len: float,
	dir: Vector2,
	edge_idx: int,
	start_inset: float = -2.0,
	end_inset: float = -2.0
) -> void:
	# Inset cliff endpoints near ramp corners by RAMP_CORNER_INSET so heavy walkers pushing
	# 3-4 abreast up wide ramps never snag on protruding corner colliders.
	var trimmed_len: float = edge_len - start_inset - end_inset
	if trimmed_len <= 4.0:
		return
	var ca: Vector2 = a + dir * start_inset
	var cb: Vector2 = b - dir * end_inset

	var body: StaticBody2D = StaticBody2D.new()
	body.name = "CliffWall_%d" % edge_idx
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = (ca + cb) * 0.5
	body.rotation = dir.angle()
	body.add_to_group("nav_bake_obstacles")
	body.add_to_group("high_ground_cliffs")

	var col_shape: CollisionShape2D = CollisionShape2D.new()
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(trimmed_len, maxf(6.0, cliff_thickness))
	col_shape.shape = rect_shape
	body.add_child(col_shape)

	add_child(body)
	_cliff_bodies.append(body)


## Exact ramp-crest elevation query:
## - Inside plateau_polygon (upper crest & plateau surface) => elevation_level (1).
## - Outside plateau_polygon (including the ~32 px outward lower ramp approach apron) => 0.
func get_world_elevation_at(world_pos: Vector2) -> int:
	return elevation_level if contains_world_point(world_pos) else 0


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


func get_ramp_segments_world() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rseg: Dictionary in _ramp_segments:
		var a_w: Vector2 = to_global(rseg["a"] as Vector2)
		var b_w: Vector2 = to_global(rseg["b"] as Vector2)
		var out_n_w: Vector2 = ((to_global(rseg["out_normal"] as Vector2) - to_global(Vector2.ZERO))).normalized()
		out.append({
			"edge_idx": int(rseg["edge_idx"]),
			"a": a_w,
			"b": b_w,
			"mid": (a_w + b_w) * 0.5,
			"out_normal": out_n_w,
			"len": a_w.distance_to(b_w),
			"is_choke": bool(rseg["is_choke"]),
		})
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
	var shadow_col: Color = Color(0.02, 0.03, 0.05, 0.48)
	var shadow_outer_col: Color = Color(0.015, 0.025, 0.04, 0.26)
	var wall_dark: Color = biome_tint.darkened(0.56)
	wall_dark.a = 0.98
	var wall_stripe: Color = biome_tint.darkened(0.72)
	wall_stripe.a = 0.72
	var rim_dark: Color = Color(0.03, 0.05, 0.08, 0.92)
	var rim_hi: Color = rim_highlight_override if rim_highlight_override.a > 0.01 else biome_tint.lightened(0.32)
	if rim_highlight_override.a <= 0.01:
		rim_hi.a = 0.85

	# 1. Soft two-pass grounded shadow beneath plateau footprint
	var shadow_outer: PackedVector2Array = PackedVector2Array()
	var shadow_poly: PackedVector2Array = PackedVector2Array()
	shadow_outer.resize(plateau_polygon.size())
	shadow_poly.resize(plateau_polygon.size())
	for i: int in range(plateau_polygon.size()):
		shadow_outer[i] = plateau_polygon[i] + Vector2(5.5, cliff_drop_height + 9.0)
		shadow_poly[i] = plateau_polygon[i] + Vector2(3.0, cliff_drop_height + 5.0)
	draw_colored_polygon(shadow_outer, shadow_outer_col)
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

	# 3. Sloped walkable ramp aprons (Level 0 approach -> Level 1 crest) + side guide rails + chevrons
	var ramp_depth: float = RAMP_SLOPE_DEPTH
	var ramp_fill: Color = biome_tint.darkened(0.24)
	ramp_fill.a = 0.92
	var ramp_lower_shade: Color = biome_tint.darkened(0.42)
	ramp_lower_shade.a = 0.55
	var rail_col: Color = rim_highlight_override.lerp(biome_tint.lightened(0.38), 0.25) if rim_highlight_override.a > 0.01 else biome_tint.lightened(0.38)
	rail_col.a = 0.78
	var step_col: Color = rim_highlight_override.lerp(biome_tint.lightened(0.26), 0.45) if rim_highlight_override.a > 0.01 else biome_tint.lightened(0.26)
	step_col.a = 0.50
	var crest_col: Color = rim_highlight_override if rim_highlight_override.a > 0.01 else biome_tint.lightened(0.48)
	crest_col.a = 0.68 if rim_highlight_override.a > 0.01 else 0.65

	for rseg: Dictionary in _ramp_segments:
		var a: Vector2 = rseg["a"] as Vector2
		var b: Vector2 = rseg["b"] as Vector2
		var out_n: Vector2 = rseg["out_normal"] as Vector2
		var edge_dir: Vector2 = rseg["dir"] as Vector2
		var edge_len: float = float(rseg["len"])
		var is_choke: bool = bool(rseg["is_choke"])
		var a_out: Vector2 = a + out_n * ramp_depth
		var b_out: Vector2 = b + out_n * ramp_depth
		var a_mid: Vector2 = a + out_n * (ramp_depth * 0.5)
		var b_mid: Vector2 = b + out_n * (ramp_depth * 0.5)

		var apron: PackedVector2Array = PackedVector2Array([a, b, b_out, a_out])
		draw_colored_polygon(apron, ramp_fill)
		# Lower slope gradient shading (visually distinguishes foot of ramp = Level 0 from upper crest = Level 1)
		var lower_apron: PackedVector2Array = PackedVector2Array([a_mid, b_mid, b_out, a_out])
		draw_colored_polygon(lower_apron, ramp_lower_shade)

		# Side guide rails framing the full walkable ramp width
		draw_line(a, a_out, rail_col, 2.4, true)
		draw_line(b, b_out, rail_col, 2.4, true)

		# 4 parallel ramp-step tread bars spanning the full ramp width
		for st: int in range(1, 5):
			var d_frac: float = float(st) / 5.0
			var p0: Vector2 = a.lerp(a_out, d_frac) + edge_dir * 6.0
			var p1: Vector2 = b.lerp(b_out, d_frac) - edge_dir * 6.0
			draw_line(p0, p1, step_col, 1.35, true)

		# Uphill directional chevrons spaced cleanly across wide assault ramps (1 on narrow choke ramps)
		var chevron_cnt: int = 1 if (is_choke or edge_len < 155.0) else (3 if edge_len >= 205.0 else 2)
		for ci: int in range(chevron_cnt):
			var u_along: float = float(ci + 1) / float(chevron_cnt + 1)
			var r_mid: Vector2 = a.lerp(b, u_along) + out_n * (ramp_depth * 0.52)
			var tip: Vector2 = r_mid - out_n * 7.0
			var wing_l: Vector2 = r_mid + out_n * 4.0 - edge_dir * 13.0
			var wing_r: Vector2 = r_mid + out_n * 4.0 + edge_dir * 13.0
			draw_polyline(PackedVector2Array([wing_l, tip, wing_r]), rail_col, 1.85, true)

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

	# Crisp subtle crest threshold highlight along ramp lips (marks exact Elevation 0 -> 1 vision boundary)
	for rseg: Dictionary in _ramp_segments:
		var a: Vector2 = rseg["a"] as Vector2
		var b: Vector2 = rseg["b"] as Vector2
		var edge_dir: Vector2 = rseg["dir"] as Vector2
		draw_line(a + edge_dir * 4.0, b - edge_dir * 4.0, crest_col, 1.6, true)

	# 5. Crisp 2px bevel outline strictly on cliff edges (leaving ramp lips cleanly open),
	# plus north-facing cliff rim shadows, inner bevel ledges, and buttress ticks for 360-degree readability.
	var north_outer_shadow: Color = Color(0.02, 0.03, 0.05, 0.65)
	var north_inner_ledge: Color = biome_tint.lightened(0.24)
	north_inner_ledge.a = 0.88
	var north_tick_col: Color = Color(0.03, 0.05, 0.08, 0.78)
	for seg: Dictionary in _cliff_segments:
		var a: Vector2 = seg["a"] as Vector2
		var b: Vector2 = seg["b"] as Vector2
		var out_n: Vector2 = seg["out_normal"] as Vector2
		if out_n.y <= -0.25:
			var edge_len_n: float = float(seg["len"])
			var outer_lip: PackedVector2Array = PackedVector2Array([a, b, b + out_n * 5.0, a + out_n * 5.0])
			draw_colored_polygon(outer_lip, north_outer_shadow)
			var inner_ledge: PackedVector2Array = PackedVector2Array([a, b, b - out_n * 4.5, a - out_n * 4.5])
			draw_colored_polygon(inner_ledge, north_inner_ledge)
			var tick_cnt: int = maxi(2, int(floor(edge_len_n / 26.0)))
			for ti: int in range(1, tick_cnt):
				var t_frac: float = float(ti) / float(tick_cnt)
				var tp: Vector2 = a.lerp(b, t_frac)
				draw_line(tp - out_n * 1.0, tp + out_n * 4.5, north_tick_col, 1.6, true)
		draw_line(a, b, rim_dark, 3.2, true)
		draw_line(a - out_n * 1.4, b - out_n * 1.4, rim_hi, 1.6, true)
