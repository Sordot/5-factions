class_name MoveMarker
extends Node2D

enum MarkerStyle {
	MOVE,
	ATTACK,
	GATHER,
	INTERACT,
}

@export var style: MarkerStyle = MarkerStyle.MOVE
@export var color: Color = Color(0.24, 0.94, 1.0, 0.95)
@export var duration: float = 0.36
@export var max_radius: float = 22.0

var _elapsed: float = 0.0


func configure(marker_style: MarkerStyle) -> void:
	style = marker_style
	match style:
		MarkerStyle.ATTACK:
			color = Color(1.0, 0.34, 0.24, 0.96)
		MarkerStyle.GATHER:
			color = Color(0.26, 1.0, 0.56, 0.96)
		MarkerStyle.INTERACT:
			color = Color(1.0, 0.78, 0.28, 0.96)
		_:
			color = Color(0.24, 0.94, 1.0, 0.95)
	queue_redraw()


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
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, ring_color, 2.2, true)

	match style:
		MarkerStyle.ATTACK:
			var inner_r: float = lerpf(max_radius * 0.62, 4.0, t)
			draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 20, ring_color, 1.6, true)
			var tick: float = 6.5
			draw_line(Vector2(-radius - tick, 0.0), Vector2(-radius + 2.0, 0.0), ring_color, 1.8, true)
			draw_line(Vector2(radius - 2.0, 0.0), Vector2(radius + tick, 0.0), ring_color, 1.8, true)
			draw_line(Vector2(0.0, -radius - tick), Vector2(0.0, -radius + 2.0), ring_color, 1.8, true)
			draw_line(Vector2(0.0, radius - 2.0), Vector2(0.0, radius + tick), ring_color, 1.8, true)
		MarkerStyle.GATHER:
			var d: float = lerpf(max_radius * 0.72, 6.0, t)
			var diamond: PackedVector2Array = PackedVector2Array([
				Vector2(0.0, -d),
				Vector2(d, 0.0),
				Vector2(0.0, d),
				Vector2(-d, 0.0),
				Vector2(0.0, -d),
			])
			draw_polyline(diamond, ring_color, 2.0, true)
		MarkerStyle.INTERACT:
			var hex_r: float = lerpf(max_radius * 0.76, 6.0, t)
			var hex: PackedVector2Array = PackedVector2Array()
			for i: int in range(7):
				var ang: float = (TAU * float(i) / 6.0) - PI * 0.5
				hex.append(Vector2.RIGHT.rotated(ang) * hex_r)
			draw_polyline(hex, ring_color, 2.0, true)
			draw_circle(Vector2.ZERO, lerpf(3.5, 1.0, t), ring_color)
		_:
			var dot_r: float = lerpf(4.0, 1.0, t)
			draw_circle(Vector2.ZERO, dot_r, ring_color)
