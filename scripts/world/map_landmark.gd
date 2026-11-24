class_name MapLandmark
extends Node2D

enum VisualStyle {
	MONOLITH_SPIRE = 0,
	RELAY_ARCH = 1,
	CAPACITOR_PYLON = 2,
	PLAZA_BEACON = 3,
}

@export var landmark_name: String = "Landmark"
@export_enum("Monolith Spire:0", "Relay Arch:1", "Capacitor Pylon:2", "Plaza Beacon:3") var visual_style: int = VisualStyle.MONOLITH_SPIRE
@export var accent_color: Color = Color(0.24, 0.94, 0.90, 1.0)
@export var has_collision: bool = true
@export var show_on_minimap: bool = true
@export var collider_radius: float = 28.0
@export var label_offset: Vector2 = Vector2(0.0, 44.0)
@export var show_region_label: bool = true

var _collider_body: StaticBody2D = null
var _local_polygon: PackedVector2Array = PackedVector2Array()
var _anim_time: float = 0.0


func _ready() -> void:
	add_to_group("map_landmarks")
	if visual_style == VisualStyle.PLAZA_BEACON:
		z_index = -4
	elif visual_style == VisualStyle.RELAY_ARCH:
		z_index = 4
	else:
		z_index = 2

	_setup_collision()
	queue_redraw()


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


func _setup_collision() -> void:
	if not has_collision or collider_radius <= 1.0:
		return
	if visual_style == VisualStyle.PLAZA_BEACON:
		return

	_local_polygon = _build_collision_polygon(collider_radius)
	if _local_polygon.size() < 3:
		return

	_collider_body = StaticBody2D.new()
	_collider_body.name = "LandmarkCollider"
	_collider_body.collision_layer = 1
	_collider_body.collision_mask = 0
	_collider_body.add_to_group("nav_bake_obstacles")

	var col_poly: CollisionPolygon2D = CollisionPolygon2D.new()
	col_poly.name = "CollisionPolygon2D"
	col_poly.polygon = _local_polygon
	_collider_body.add_child(col_poly)
	add_child(_collider_body)

	var nav_reg: Node = get_tree().get_first_node_in_group("arena_nav_region")
	if nav_reg != null and nav_reg.has_method("request_rebake"):
		nav_reg.call("request_rebake")


func get_collider_node() -> StaticBody2D:
	return _collider_body


func overlaps_circle(world_pos: Vector2, radius: float) -> bool:
	if not has_collision or _local_polygon.size() < 3:
		return false
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


func _build_collision_polygon(r: float) -> PackedVector2Array:
	match visual_style:
		VisualStyle.MONOLITH_SPIRE:
			return PackedVector2Array([
				Vector2(0.0, -r),
				Vector2(r * 0.88, -r * 0.48),
				Vector2(r * 0.88, r * 0.48),
				Vector2(0.0, r),
				Vector2(-r * 0.88, r * 0.48),
				Vector2(-r * 0.88, -r * 0.48),
			])
		VisualStyle.CAPACITOR_PYLON:
			var c: float = r * 0.44
			return PackedVector2Array([
				Vector2(r, -c),
				Vector2(r, c),
				Vector2(c, r),
				Vector2(-c, r),
				Vector2(-r, c),
				Vector2(-r, -c),
				Vector2(-c, -r),
				Vector2(c, -r),
			])
		_:
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in range(8):
				var ang: float = TAU * float(i) / 8.0
				pts.append(Vector2.RIGHT.rotated(ang) * r)
			return pts


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 2.4)
	var shell: Color = Color(0.86, 0.92, 0.97, 0.94)
	var deck: Color = Color(0.13, 0.20, 0.27, 0.96)
	var trim: Color = Color(0.46, 0.60, 0.70, 0.95)
	var acc: Color = accent_color

	match visual_style:
		VisualStyle.MONOLITH_SPIRE:
			var r: float = maxf(24.0, collider_radius)
			# Subtle ground telemetry pad
			draw_arc(Vector2.ZERO, r + 14.0, 0.0, TAU, 36, Color(acc.r, acc.g, acc.b, 0.20 + pulse * 0.12), 1.4, true)
			draw_circle(Vector2.ZERO, r + 14.0, Color(acc.r, acc.g, acc.b, 0.045))
			# Chamfered hexagonal chrome spire base
			var hex: PackedVector2Array = _build_collision_polygon(r)
			_poly_outlined(hex, shell, acc, 2.2)
			draw_colored_polygon(_scale_poly(hex, 0.72), deck)
			# Conduit ribs
			for i: int in range(6):
				var a: float = TAU * float(i) / 6.0 - PI * 0.5
				draw_line(Vector2.RIGHT.rotated(a) * (r * 0.35), Vector2.RIGHT.rotated(a) * (r * 0.85), trim, 2.0, true)
			# Central crystal spire diamond
			var crystal: PackedVector2Array = PackedVector2Array([
				Vector2(0.0, -r * 0.52),
				Vector2(r * 0.34, 0.0),
				Vector2(0.0, r * 0.52),
				Vector2(-r * 0.34, 0.0),
			])
			_poly_outlined(crystal, Color(acc.r, acc.g, acc.b, 0.82 + pulse * 0.18), Color(0.95, 1.0, 1.0, 0.92), 1.5)
			draw_circle(Vector2.ZERO, 4.5 + pulse * 1.4, Color(0.94, 1.0, 1.0, 0.9))

		VisualStyle.RELAY_ARCH:
			# Wide passable flank corridor gate: twin flanking piers + glowing holographic overhead conduit
			var span: float = 96.0
			var pier_w: float = 16.0
			var pier_h: float = 26.0
			# Subtle ground corridor guide rails
			draw_line(Vector2(-span + 12.0, -18.0), Vector2(span - 12.0, -18.0), Color(acc.r, acc.g, acc.b, 0.14), 1.2, true)
			draw_line(Vector2(-span + 12.0, 18.0), Vector2(span - 12.0, 18.0), Color(acc.r, acc.g, acc.b, 0.14), 1.2, true)
			# Left & right chrome arch piers
			for sign_x: float in [-1.0, 1.0]:
				var cx: float = sign_x * span
				var pier_rect: Rect2 = Rect2(cx - pier_w * 0.5, -pier_h * 0.5, pier_w, pier_h)
				draw_rect(pier_rect, shell, true)
				draw_rect(pier_rect, acc, false, 1.8)
				draw_rect(pier_rect.grow(-4.0), deck, true)
				draw_circle(Vector2(cx, 0.0), 4.0, acc)
			# Overhead translucent signal arch beam + drifting pulse chevron
			draw_line(Vector2(-span, 0.0), Vector2(span, 0.0), Color(acc.r, acc.g, acc.b, 0.24), 6.0, true)
			draw_line(Vector2(-span, 0.0), Vector2(span, 0.0), Color(acc.r, acc.g, acc.b, 0.72), 2.0, true)
			var flow_x: float = lerpf(-span + 16.0, span - 16.0, fmod(_anim_time * 0.55, 1.0))
			draw_circle(Vector2(flow_x, 0.0), 3.6, Color(0.95, 1.0, 1.0, 0.92))
			draw_circle(Vector2(-flow_x, 0.0), 2.8, acc)

		VisualStyle.CAPACITOR_PYLON:
			var r: float = maxf(20.0, collider_radius)
			var oct: PackedVector2Array = _build_collision_polygon(r)
			# Soft drop shadow
			draw_colored_polygon(_offset_poly(oct, Vector2(4.0, 5.0)), Color(0.02, 0.04, 0.06, 0.42))
			_poly_outlined(oct, shell, acc, 2.2)
			draw_colored_polygon(_scale_poly(oct, 0.72), deck)
			# Dual capacitor coil bars
			draw_rect(Rect2(-r * 0.48, -r * 0.22, r * 0.96, r * 0.44), trim, true)
			draw_rect(Rect2(-r * 0.36, -r * 0.14, r * 0.72, r * 0.28), Color(acc.r, acc.g, acc.b, 0.72 + pulse * 0.25), true)
			draw_arc(Vector2.ZERO, r * 0.54, _anim_time * 1.4, _anim_time * 1.4 + PI * 0.9, 16, acc, 1.8, true)

		VisualStyle.PLAZA_BEACON:
			# Flush diegetic Technozen floor emblem for main bases / regions
			var ring_r: float = 82.0
			draw_circle(Vector2.ZERO, ring_r, Color(acc.r, acc.g, acc.b, 0.035))
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 48, Color(acc.r, acc.g, acc.b, 0.18 + pulse * 0.08), 1.6, true)
			draw_arc(Vector2.ZERO, ring_r - 12.0, 0.0, TAU, 40, Color(acc.r, acc.g, acc.b, 0.10), 1.0, true)
			for i: int in range(4):
				var a: float = float(i) * PI * 0.5 + PI * 0.25
				var dir: Vector2 = Vector2.RIGHT.rotated(a)
				draw_line(dir * (ring_r - 10.0), dir * (ring_r + 10.0), Color(acc.r, acc.g, acc.b, 0.32), 2.0, true)

	if show_region_label and not landmark_name.is_empty():
		_draw_region_nameplate(acc)


func _draw_region_nameplate(acc: Color) -> void:
	# Counter-rotate so ground labels always remain horizontal and crisp regardless of landmark rotation.
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var text_upper: String = landmark_name.to_upper()
	var text_sz: Vector2 = font.get_string_size(text_upper, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pad_x: float = 10.0
	var pad_y: float = 4.0
	var pill_w: float = text_sz.x + pad_x * 2.0
	var pill_h: float = text_sz.y + pad_y * 2.0
	var pill_pos: Vector2 = label_offset + Vector2(-pill_w * 0.5, -pill_h * 0.5)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.04, 0.07, 0.11, 0.76), true)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(acc.r, acc.g, acc.b, 0.52), false, 1.1)
	draw_string(font, pill_pos + Vector2(pad_x, pill_h - pad_y - 2.0), text_upper, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.88, 0.97, 1.0, 0.90))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _scale_poly(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(poly.size())
	for i: int in range(poly.size()):
		out[i] = poly[i] * factor
	return out


func _offset_poly(poly: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(poly.size())
	for i: int in range(poly.size()):
		out[i] = poly[i] + delta
	return out


func _poly_outlined(poly: PackedVector2Array, fill_col: Color, outline_col: Color, width: float) -> void:
	draw_colored_polygon(poly, fill_col)
	if poly.size() < 2:
		return
	var pts: PackedVector2Array = poly.duplicate()
	pts.append(poly[0])
	draw_polyline(pts, outline_col, width, true)
