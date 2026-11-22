class_name AttackTracer
extends Node2D

@export var color: Color = Color(0.35, 0.98, 0.92, 0.95)
@export var duration: float = 0.12
@export var line_width: float = 2.5

var start_world: Vector2 = Vector2.ZERO
var end_world: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0


func setup(from_world: Vector2, to_world: Vector2, tracer_color: Color = Color(0.35, 0.98, 0.92, 0.95)) -> void:
	start_world = from_world
	end_world = to_world
	color = tracer_color
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
	draw_line(p0, p1, draw_col, line_width, true)
	draw_circle(p1, lerpf(5.0, 1.5, t), draw_col)
