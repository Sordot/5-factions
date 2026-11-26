class_name AttackTracer
extends Node2D

enum TracerStyle {
	PULSE_BOLT = 0,
	RAIL_BEAM = 1,
	ARC_LANCE = 2,
	TWIN_SLUG = 3,
	ARC_SHELL = 4,
	HEAVY_SLUG = 5,
	RAIL_LANCE = 6,
	ARC_TETHER = 7,
	PRISM_BEAM = 8,
	PRISM_REFRACT = 9,
}

@export var color: Color = Color(0.35, 0.98, 0.92, 0.95)
@export var duration: float = 0.12
@export var line_width: float = 2.5

var start_world: Vector2 = Vector2.ZERO
var end_world: Vector2 = Vector2.ZERO
var _arc_height: float = 0.0
var _style: int = TracerStyle.PULSE_BOLT
var _elapsed: float = 0.0
var _hide_origin_muzzle: bool = false
var _live_from_node: Node2D = null
var _live_to_node: Node2D = null
var _beam_intensity: float = 0.0
var _muzzle_dist: float = 16.0
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
	_hide_origin_muzzle = false
	_live_from_node = null
	_live_to_node = null
	_beam_intensity = 0.0
	_muzzle_dist = 16.0
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
	style: int = TracerStyle.PULSE_BOLT,
	hide_origin_muzzle: bool = false
) -> void:
	start_world = from_world
	end_world = to_world
	color = tracer_color
	line_width = width
	duration = maxf(0.05, tracer_duration)
	_arc_height = arc_height
	_style = TracerStyle.ARC_SHELL if arc_height > 1.0 else style
	_hide_origin_muzzle = hide_origin_muzzle
	_live_from_node = null
	_live_to_node = null
	_beam_intensity = 0.0
	_muzzle_dist = 16.0
	_elapsed = 0.0
	queue_redraw()


func attach_live_endpoints(from_node: Node2D, to_node: Node2D, intensity: float = 0.0, muzzle_dist: float = 16.0) -> void:
	_live_from_node = from_node
	_live_to_node = to_node
	_beam_intensity = clampf(intensity, 0.0, 1.0)
	_muzzle_dist = maxf(0.0, muzzle_dist)
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

	if _live_to_node != null and is_instance_valid(_live_to_node):
		end_world = _live_to_node.global_position
	if _live_from_node != null and is_instance_valid(_live_from_node):
		var aim_vec: Vector2 = end_world - _live_from_node.global_position
		var aim_dir: Vector2 = aim_vec.normalized() if aim_vec.length_squared() > 1.0 else Vector2.RIGHT
		start_world = _live_from_node.global_position + aim_dir * _muzzle_dist

	var effective_start: Vector2 = start_world.lerp(end_world, 0.28) if _hide_origin_muzzle else start_world
	var p0: Vector2 = to_local(effective_start)
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
			if not _hide_origin_muzzle and t < 0.45:
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
			if not _hide_origin_muzzle:
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
				if not _hide_origin_muzzle and t < 0.40:
					var mf_g: float = 1.0 - (t / 0.40)
					draw_circle(s0, 4.8 * mf_g, Color(1.0, 0.88, 0.58, mf_g * 0.88))
			draw_circle(p1, lerpf(7.0, 2.0, t), draw_col)

		TracerStyle.HEAVY_SLUG:
			# MONOLITH_OS thick amber/off-white high-impact twin-slug tracer with chunky brutalist muzzle flash
			var h_offset: float = 4.2
			var head_hs: float = clampf(t * 2.2, 0.30, 1.0)
			var tail_hs: float = clampf(head_hs - 0.52, 0.0, 0.90)
			for s: float in [-1.0, 1.0]:
				var hs0: Vector2 = p0 + perp * (s * h_offset)
				var hs1: Vector2 = p1 + perp * (s * h_offset * 0.45)
				var hb0: Vector2 = hs0.lerp(hs1, tail_hs)
				var hb1: Vector2 = hs0.lerp(hs1, head_hs)
				draw_line(hb0, hb1, Color(0.06, 0.07, 0.09, alpha * 0.72), line_width * 1.9, true)
				draw_line(hb0, hb1, draw_col, line_width * 1.25, true)
				draw_line(hb0, hb1, Color(0.96, 0.95, 0.91, alpha * 0.96), maxf(1.4, line_width * 0.50), true)
			if not _hide_origin_muzzle and t < 0.38:
				var mf_h: float = 1.0 - (t / 0.38)
				var flash_r: float = 7.5 * mf_h
				if flash_r > 0.8:
					var box: PackedVector2Array = PackedVector2Array([
						p0 + dir * (flash_r * 1.35) + perp * (flash_r * 0.45),
						p0 + dir * (flash_r * 1.35) - perp * (flash_r * 0.45),
						p0 - dir * (flash_r * 0.25) - perp * (flash_r * 0.85),
						p0 - dir * (flash_r * 0.25) + perp * (flash_r * 0.85),
					])
					draw_colored_polygon(box, Color(1.0, 0.76, 0.24, mf_h * 0.92))
			draw_circle(p1, lerpf(8.5, 2.2, t), draw_col)
			draw_circle(p1, lerpf(4.2, 1.0, t), Color(0.98, 0.97, 0.94, alpha))

		TracerStyle.RAIL_LANCE:
			# MONOLITH_OS Rail-Sentinel stark white-core / Hazard Amber halo lingering rail lance (0.18s)
			var rail_w: float = line_width * lerpf(1.35, 0.42, t)
			draw_line(p0, p1, Color(1.0, 0.624, 0.110, alpha * 0.36), rail_w * 2.8, true)
			draw_line(p0, p1, draw_col, rail_w * 1.25, true)
			draw_line(p0, p1, Color(0.98, 0.98, 0.96, alpha * 0.98), maxf(1.6, rail_w * 0.55), true)
			# Crisp brutalist shock-bars along the pierce vector
			for k: int in range(1, 5):
				var frac: float = float(k) * 0.20 + t * 0.05
				if frac < 0.96:
					var mp: Vector2 = p0.lerp(p1, frac)
					var bar_half: float = (7.5 + float(k) * 1.2) * fade
					draw_line(mp - perp * bar_half, mp + perp * bar_half, Color(1.0, 0.72, 0.22, alpha * 0.82), 1.8, true)
			if not _hide_origin_muzzle and t < 0.45:
				var mf_r: float = 1.0 - (t / 0.45)
				draw_circle(p0, 7.2 * mf_r, Color(0.98, 0.96, 0.90, mf_r * 0.92))
			draw_circle(p1, lerpf(9.5, 2.0, t), Color(1.0, 0.68, 0.18, alpha))

		TracerStyle.ARC_TETHER:
			# MONOLITH_OS Picket Drone crisp jagged amber-cyan suppressive arc
			var segs: int = 7
			var pts_arc: PackedVector2Array = PackedVector2Array()
			pts_arc.resize(segs + 1)
			pts_arc[0] = p0
			pts_arc[segs] = p1
			var phase_seed: float = floor(_elapsed * 45.0)
			for i: int in range(1, segs):
				var u_arc: float = float(i) / float(segs)
				var base_pt: Vector2 = p0.lerp(p1, u_arc)
				var zig: float = (1.0 if ((i + int(phase_seed)) % 2 == 0) else -1.0) * (5.2 * sin(u_arc * PI))
				pts_arc[i] = base_pt + perp * zig
			var cyan_halo: Color = Color(0.220, 0.741, 0.973, alpha * 0.62)
			draw_polyline(pts_arc, cyan_halo, line_width * 2.1, true)
			draw_polyline(pts_arc, draw_col, line_width, true)
			draw_polyline(pts_arc, Color(0.95, 0.99, 1.0, alpha * 0.90), maxf(1.0, line_width * 0.42), true)
			draw_circle(p1, lerpf(6.5, 1.8, t), cyan_halo)

		TracerStyle.PRISM_BEAM:
			# Escalating continuous optical beam: shifts Electric Magenta -> Liturgical Gold -> White-Gold core
			var hold_fade: float = 1.0 if t < 0.65 else clampf(1.0 - (t - 0.65) / 0.35, 0.0, 1.0)
			var b_alpha: float = hold_fade * maxf(color.a, 0.92)
			var magenta_c: Color = Color(0.94, 0.22, 0.68, 1.0)
			var gold_c: Color = Color(0.98, 0.82, 0.18, 1.0)
			var beam_tint: Color = magenta_c.lerp(gold_c, _beam_intensity)
			var glow_w: float = line_width * lerpf(2.3, 3.1, _beam_intensity)
			var core_w: float = maxf(1.3, line_width * lerpf(0.42, 0.64, _beam_intensity))
			draw_line(p0, p1, Color(beam_tint.r, beam_tint.g, beam_tint.b, b_alpha * 0.34), glow_w, true)
			draw_line(p0, p1, Color(beam_tint.r, beam_tint.g, beam_tint.b, b_alpha * 0.95), line_width, true)
			draw_line(p0, p1, Color(1.0, 0.98, 0.92, b_alpha), core_w, true)
			# Bauhaus diamond focal lens at emitter & crystalline impact star at target
			if not _hide_origin_muzzle:
				var lens_r: float = lerpf(4.2, 7.6, _beam_intensity) * hold_fade
				var lens_pts: PackedVector2Array = PackedVector2Array([
					p0 + dir * (lens_r * 1.25),
					p0 + perp * lens_r,
					p0 - dir * (lens_r * 0.55),
					p0 - perp * lens_r,
				])
				draw_colored_polygon(lens_pts, Color(1.0, 0.96, 0.86, b_alpha * 0.92))
			var hit_r: float = lerpf(5.0, 10.5, _beam_intensity) * hold_fade
			var hit_pts: PackedVector2Array = PackedVector2Array([
				p1 + dir * hit_r,
				p1 + perp * hit_r,
				p1 - dir * hit_r,
				p1 - perp * hit_r,
			])
			draw_colored_polygon(hit_pts, Color(beam_tint.r, beam_tint.g, beam_tint.b, b_alpha * 0.82))
			draw_circle(p1, hit_r * 0.45, Color(1.0, 0.99, 0.94, b_alpha))

		TracerStyle.PRISM_REFRACT:
			# Crisp crystalline split-beam bounce ray with diamond refraction glint
			var r_col: Color = Color(color.r, color.g, color.b, alpha * 0.94)
			draw_line(p0, p1, Color(0.94, 0.22, 0.68, alpha * 0.36), line_width * 2.1, true)
			draw_line(p0, p1, r_col, line_width, true)
			draw_line(p0, p1, Color(1.0, 0.98, 0.90, alpha * 0.96), maxf(1.0, line_width * 0.45), true)
			var glint_r: float = lerpf(5.2, 1.5, t)
			if not _hide_origin_muzzle:
				var o_pts: PackedVector2Array = PackedVector2Array([
					p0 + dir * glint_r,
					p0 + perp * glint_r,
					p0 - dir * glint_r,
					p0 - perp * glint_r,
				])
				draw_colored_polygon(o_pts, Color(1.0, 0.95, 0.78, alpha * 0.90))
			draw_circle(p1, lerpf(4.8, 1.4, t), r_col)

		_:
			# PULSE_BOLT (Clone Trooper / standard): brief muzzle flash + crisp tapering energy bolt
			var bolt_head_u: float = clampf(t * 2.4, 0.35, 1.0)
			var bolt_tail_u: float = clampf(bolt_head_u - 0.65, 0.0, 0.88)
			var bp0: Vector2 = p0.lerp(p1, bolt_tail_u)
			var bp1: Vector2 = p0.lerp(p1, bolt_head_u)
			draw_line(p0, p1, Color(color.r, color.g, color.b, alpha * 0.25), maxf(1.0, line_width * 0.65), true)
			draw_line(bp0, bp1, draw_col, line_width, true)
			draw_line(bp0, bp1, Color(0.95, 1.0, 1.0, alpha * 0.85), maxf(1.0, line_width * 0.42), true)
			if not _hide_origin_muzzle and t < 0.35:
				var mf_p: float = 1.0 - (t / 0.35)
				draw_circle(p0, 4.2 * mf_p, Color(0.95, 1.0, 0.98, mf_p * 0.82))
			draw_circle(p1, lerpf(line_width * 1.8, 1.4, t), draw_col)
