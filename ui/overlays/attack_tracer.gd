class_name AttackTracer
extends Node2D

enum TracerStyle {
	PULSE_BOLT = 0,
	RAIL_BEAM = 1,
	ARC_LANCE = 2,
	TWIN_SLUG = 3,
	ARC_SHELL = 4,
}

@export var color: Color = Color(0.35, 0.98, 0.92, 0.95)
@export var duration: float = 0.12
@export var line_width: float = 2.5

var start_world: Vector2 = Vector2.ZERO
var end_world: Vector2 = Vector2.ZERO
var _arc_height: float = 0.0
var _style: int = TracerStyle.PULSE_BOLT
var _elapsed: float = 0.0
var is_pooled: bool = false


func reset_for_pool() -> void:
	start_world = Vector2.ZERO
	end_world = Vector2.ZERO
	color = Color(0.35, 0.98, 0.92, 0.95)
	duration = 0.12
	line_width = 2.5
	_arc_height = 0.0
	_style = TracerStyle.PULSE_BOLT
	_elapsed = 0.0
	global_position = Vector2.ZERO


func recycle() -> void:
	if is_pooled and VFXPool != null:
		VFXPool.recycle_node(self)
	else:
		queue_free()


func setup(
	from_world: Vector2,
	to_world: Vector2,
	tracer_color: Color = Color(0.35, 0.98, 0.92, 0.95),
	width: float = 2.5,
	tracer_duration: float = 0.12,
	arc_height: float = 0.0,
	style: int = TracerStyle.PULSE_BOLT
) -> void:
	start_world = from_world
	end_world = to_world
	color = tracer_color
	line_width = width
	duration = maxf(0.05, tracer_duration)
	_arc_height = arc_height
	_style = TracerStyle.ARC_SHELL if arc_height > 1.0 else style
	_elapsed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		recycle()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var fade: float = 1.0 - t
	var alpha: float = fade * color.a
	var draw_col: Color = Color(color.r, color.g, color.b, alpha)

	var p0: Vector2 = to_local(start_world)
	var p1: Vector2 = to_local(end_world)

	if _style == TracerStyle.ARC_SHELL or _arc_height > 1.0:
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
		return

	var seg: Vector2 = p1 - p0
	var seg_len: float = seg.length()
	var dir: Vector2 = (seg / seg_len) if seg_len > 0.01 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x)

	match _style:
		TracerStyle.RAIL_BEAM:
			# Focused high-voltage Lance-Rig rail beam with lingering ionized core
			draw_line(p0, p1, Color(color.r, color.g, color.b, alpha * 0.42), line_width * 2.2, true)
			draw_line(p0, p1, draw_col, line_width, true)
			draw_line(p0, p1, Color(1.0, 0.98, 0.90, alpha * 0.95), maxf(1.2, line_width * 0.42), true)
			if t < 0.45:
				var mf: float = 1.0 - (t / 0.45)
				draw_circle(p0, 5.5 * mf, Color(1.0, 0.95, 0.72, mf * 0.85))
			draw_circle(p1, lerpf(line_width * 2.1, 1.6, t), Color(1.0, 0.94, 0.72, alpha))

		TracerStyle.ARC_LANCE:
			# Wide piercing Arc-Lancer plasma beam with transverse sweep flash
			var beam_w: float = line_width * lerpf(1.25, 0.45, t)
			draw_line(p0, p1, Color(color.r, color.g, color.b, alpha * 0.34), beam_w * 2.4, true)
			draw_line(p0, p1, draw_col, beam_w, true)
			draw_line(p0, p1, Color(0.96, 1.0, 1.0, alpha * 0.96), maxf(1.5, beam_w * 0.44), true)
			# Transverse plasma sweep flares along the piercing corridor
			for k: int in range(1, 4):
				var frac: float = float(k) * 0.25 + t * 0.08
				if frac < 0.98:
					var mp: Vector2 = p0.lerp(p1, frac)
					var half_tick: float = (8.0 + float(k) * 1.5) * fade
					draw_line(mp - perp * half_tick, mp + perp * half_tick, Color(0.90, 1.0, 1.0, alpha * 0.72), 1.6, true)
			draw_circle(p0, lerpf(7.5, 2.5, t), Color(0.86, 1.0, 1.0, alpha * 0.82))
			draw_circle(p1, lerpf(9.0, 2.0, t), draw_col)

		TracerStyle.TWIN_SLUG:
			# Heavy Goliath Frame twin-slug parallel autocannon bursts
			var offset_px: float = 5.2
			for s: float in [-1.0, 1.0]:
				var s0: Vector2 = p0 + perp * (s * offset_px)
				var s1: Vector2 = p1 + perp * (s * offset_px * 0.55)
				var head_u: float = clampf(t * 2.1, 0.25, 1.0)
				var tail_u: float = clampf(head_u - 0.58, 0.0, 0.92)
				var b0: Vector2 = s0.lerp(s1, tail_u)
				var b1: Vector2 = s0.lerp(s1, head_u)
				draw_line(b0, b1, Color(color.r, color.g, color.b, alpha * 0.48), line_width * 1.6, true)
				draw_line(b0, b1, draw_col, line_width, true)
				draw_line(b0, b1, Color(1.0, 0.98, 0.92, alpha * 0.9), maxf(1.1, line_width * 0.4), true)
				if t < 0.40:
					var mf_g: float = 1.0 - (t / 0.40)
					draw_circle(s0, 4.8 * mf_g, Color(1.0, 0.88, 0.58, mf_g * 0.88))
			draw_circle(p1, lerpf(7.0, 2.0, t), draw_col)

		_:
			# PULSE_BOLT (Clone Trooper / standard): brief muzzle flash + crisp tapering energy bolt
			var bolt_head_u: float = clampf(t * 2.4, 0.35, 1.0)
			var bolt_tail_u: float = clampf(bolt_head_u - 0.65, 0.0, 0.88)
			var bp0: Vector2 = p0.lerp(p1, bolt_tail_u)
			var bp1: Vector2 = p0.lerp(p1, bolt_head_u)
			draw_line(p0, p1, Color(color.r, color.g, color.b, alpha * 0.25), maxf(1.0, line_width * 0.65), true)
			draw_line(bp0, bp1, draw_col, line_width, true)
			draw_line(bp0, bp1, Color(0.95, 1.0, 1.0, alpha * 0.85), maxf(1.0, line_width * 0.42), true)
			if t < 0.35:
				var mf_p: float = 1.0 - (t / 0.35)
				draw_circle(p0, 4.2 * mf_p, Color(0.95, 1.0, 0.98, mf_p * 0.82))
			draw_circle(p1, lerpf(line_width * 1.8, 1.4, t), draw_col)
