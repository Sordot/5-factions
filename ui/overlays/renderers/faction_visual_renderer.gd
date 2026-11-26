class_name FactionVisualRenderer
extends RefCounted

## Base contract for pluggable procedural faction unit & structure silhouette renderers.
## Subclasses (GenesisVisualRenderer, MonolithVisualRenderer, and future Factions #3-#5)
## draw exclusively via the passed CanvasItem and lightweight ctx Dictionary without
## querying the SceneTree per frame.


func handles_unit(_type_id: StringName) -> bool:
	return false


func handles_building(_type_id: StringName) -> bool:
	return false


func needs_unit_animation(_type_id: StringName, _ctx: Dictionary) -> bool:
	return false


func get_building_outer_poly(_type_id: StringName, radius: float) -> PackedVector2Array:
	var r: float = maxf(22.0, radius)
	var c: float = r * 0.42
	var e: float = r * 0.96
	return PackedVector2Array([
		Vector2(e, -c), Vector2(e, c), Vector2(c, e), Vector2(-c, e),
		Vector2(-e, c), Vector2(-e, -c), Vector2(-c, -e), Vector2(c, -e),
	])


func draw_unit(_canvas: CanvasItem, _type_id: StringName, _unit: Unit, _ctx: Dictionary) -> void:
	pass


func draw_unit_upgrade_telltales(_canvas: CanvasItem, _type_id: StringName, _unit: Unit, _ctx: Dictionary) -> void:
	pass


func draw_building(
	_canvas: CanvasItem,
	_type_id: StringName,
	_building: Building,
	_hull_poly: PackedVector2Array,
	_ctx: Dictionary
) -> void:
	pass


func draw_building_upgrade_telltales(_canvas: CanvasItem, _type_id: StringName, _building: Building, _ctx: Dictionary) -> void:
	pass


func draw_building_turret(_canvas: CanvasItem, _building: Building, _ctx: Dictionary) -> bool:
	return false


func get_completion_flash_color(_type_id: StringName) -> Color:
	return Color(0.90, 1.0, 0.98, 1.0)


func is_mechanical_damage_style(_type_id: StringName, is_building: bool) -> bool:
	return is_building


# =============================================================================
# SHARED GEOMETRY & VECTOR DRAWING UTILITIES
# =============================================================================

static func scale_poly(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(poly.size())
	for i: int in range(poly.size()):
		out[i] = poly[i] * factor
	return out


static func draw_closed_outline(canvas: CanvasItem, poly: PackedVector2Array, outline_col: Color, width: float) -> void:
	if poly.size() < 2:
		return
	var pts: PackedVector2Array = poly.duplicate()
	pts.append(poly[0])
	canvas.draw_polyline(pts, outline_col, width, true)


static func poly_outlined(
	canvas: CanvasItem,
	poly: PackedVector2Array,
	fill_col: Color,
	outline_col: Color,
	width: float
) -> void:
	canvas.draw_colored_polygon(poly, fill_col)
	draw_closed_outline(canvas, poly, outline_col, width)


static func build_chamfer_rect_poly(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var c: float = clampf(chamfer, 0.0, minf(rect.size.x, rect.size.y) * 0.45)
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.end.x
	var y1: float = rect.end.y
	return PackedVector2Array([
		Vector2(x0 + c, y0), Vector2(x1 - c, y0),
		Vector2(x1, y0 + c), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0 + c, y1),
		Vector2(x0, y1 - c), Vector2(x0, y0 + c),
	])


static func draw_active_conduit_sparks(canvas: CanvasItem, col: Color, spread_r: float, anim_time: float) -> void:
	# Lightweight rising vector telemetry sparks (zero particle nodes)
	for i: int in range(4):
		var phase: float = fmod(anim_time * 0.95 + float(i) * 0.25, 1.0)
		var fade: float = sin(phase * PI)
		if fade <= 0.05:
			continue
		var lane_x: float = (float(i) - 1.5) * (spread_r * 0.56) + sin(anim_time * 3.0 + float(i) * 1.9) * 2.5
		var y_pos: float = lerpf(spread_r * 0.45, -spread_r * 0.85, phase)
		var spark_col: Color = Color(col.r, col.g, col.b, fade * 0.85)
		canvas.draw_circle(Vector2(lane_x, y_pos), 1.8 * fade + 0.6, spark_col)
		canvas.draw_line(
			Vector2(lane_x, y_pos + 1.5),
			Vector2(lane_x, y_pos + 5.5 * fade),
			Color(0.92, 1.0, 0.98, fade * 0.62),
			1.1,
			true
		)


static func ctx_has_upgrade(ctx: Dictionary, upgrade_id: StringName) -> bool:
	var lookup: Variant = ctx.get("upgrades", null)
	if lookup is Callable and (lookup as Callable).is_valid():
		return bool((lookup as Callable).call(upgrade_id))
	return false
