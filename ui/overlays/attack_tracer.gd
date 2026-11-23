class_name AttackTracer
extends Node2D

@export var color: Color = Color(0.35, 0.98, 0.92, 0.95)
@export var duration: float = 0.12
@export var line_width: float = 2.5

var start_world: Vector2 = Vector2.ZERO
var end_world: Vector2 = Vector2.ZERO
var _arc_height: float = 0.0
var _elapsed: float = 0.0


func setup(
	from_world: Vector2,
	to_world: Vector2,
	tracer_color: Color = Color(0.35, 0.98, 0.92, 0.95),
	width: float = 2.5,
	tracer_duration: float = 0.12,
	arc_height: float = 0.0
) -> void:
	start_world = from_world
	end_world = to_world
	color = tracer_color
	line_width = width
	duration = maxf(0.05, tracer_duration)
	_arc_height = arc_height
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var alpha: float = (1.0 - t) * color.a
	var draw_col: Color = color
	draw_col.a = alpha

	var p0: Vector2 = to_local(start_world)
	var p1: Vector2 = to_local(end_world)
	if _arc_height > 1.0:
		var segments: int = 12
		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(segments + 1)
		for i: int in range(segments + 1):
			var u: float = float(i) / float(segments)
			var base: Vector2 = p0.lerp(p1, u)
			var lift: float = sin(u * PI) * _arc_height
			pts[i] = base + Vector2(0.0, -lift)
		draw_polyline(pts, draw_col, line_width, true)
		var shell_u: float = clampf(t * 1.4, 0.0, 1.0)
		var shell_pos: Vector2 = p0.lerp(p1, shell_u) + Vector2(0.0, -sin(shell_u * PI) * _arc_height)
		draw_circle(shell_pos, 4.5, Color(color.r, color.g, color.b, alpha))
	else:
		draw_line(p0, p1, draw_col, line_width, true)
		draw_circle(p1, lerpf(line_width * 2.0, 1.5, t), draw_col)
