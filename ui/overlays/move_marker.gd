class_name MoveMarker
extends Node2D

@export var color: Color = Color(0.3, 0.98, 0.82, 0.95)
@export var duration: float = 0.35
@export var max_radius: float = 22.0

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var radius: float = lerpf(4.0, max_radius, t)
	var ring_color: Color = color
	ring_color.a = (1.0 - t) * color.a
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, ring_color, 2.0, true)
