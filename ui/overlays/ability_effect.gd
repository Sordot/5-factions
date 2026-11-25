class_name AbilityEffect
extends Node2D

enum EffectStyle {
	OFFENSIVE_AOE,
	SELF_PULSE,
	SEISMIC_SLAM,
}

@export var duration: float = 0.35

var _style: EffectStyle = EffectStyle.OFFENSIVE_AOE
var _from_world: Vector2 = Vector2.ZERO
var _to_world: Vector2 = Vector2.ZERO
var _radius: float = 64.0
var _color: Color = Color(0.32, 0.95, 1.0, 0.95)
var _elapsed: float = 0.0
var is_pooled: bool = false


func reset_for_pool() -> void:
	duration = 0.35
	_style = EffectStyle.OFFENSIVE_AOE
	_from_world = Vector2.ZERO
	_to_world = Vector2.ZERO
	_radius = 64.0
	_color = Color(0.32, 0.95, 1.0, 0.95)
	_elapsed = 0.0
	global_position = Vector2.ZERO


func recycle() -> void:
	if is_pooled and VFXPool != null:
		VFXPool.recycle_node(self)
	else:
		queue_free()


func setup_aoe(from_world: Vector2, target_world: Vector2, radius: float, effect_color: Color = Color(0.42, 0.88, 1.0, 0.95)) -> void:
	_style = EffectStyle.OFFENSIVE_AOE
	_from_world = from_world
	_to_world = target_world
	_radius = maxf(12.0, radius)
	_color = effect_color
	duration = 0.35
	_elapsed = 0.0
	queue_redraw()


func setup_self_pulse(center_world: Vector2, radius: float, effect_color: Color = Color(0.32, 0.98, 0.64, 0.95)) -> void:
	_style = EffectStyle.SELF_PULSE
	_from_world = center_world
	_to_world = center_world
	_radius = maxf(16.0, radius)
	_color = effect_color
	duration = 0.35
	_elapsed = 0.0
	queue_redraw()


func setup_seismic_slam(center_world: Vector2, radius: float, effect_color: Color = Color(1.0, 0.72, 0.28, 0.98)) -> void:
	_style = EffectStyle.SEISMIC_SLAM
	_from_world = center_world
	_to_world = center_world
	_radius = maxf(24.0, radius)
	_color = effect_color
	duration = 0.44
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
	var target_local: Vector2 = to_local(_to_world)

	if _style == EffectStyle.OFFENSIVE_AOE:
		if t < 0.45:
			var beam_col: Color = _color
			beam_col.a = (1.0 - (t / 0.45)) * 0.95
			draw_line(to_local(_from_world), target_local, beam_col, 4.0, true)

		var fill_col: Color = _color
		fill_col.a = fade * 0.24
		var current_r: float = lerpf(_radius * 0.25, _radius, sqrt(t))
		draw_circle(target_local, current_r, fill_col)

		var ring_col: Color = _color
		ring_col.a = fade * 0.95
		draw_arc(target_local, current_r, 0.0, TAU, 36, ring_col, 3.0, true)
		draw_arc(target_local, _radius, 0.0, TAU, 36, Color(_color.r, _color.g, _color.b, fade * 0.45), 1.5, true)
	elif _style == EffectStyle.SEISMIC_SLAM:
		# Heavy radial tectonic shockwave + secondary ground-crack ring + dust ticks
		var outer_r: float = lerpf(_radius * 0.18, _radius * 1.05, sqrt(t))
		var inner_r: float = lerpf(10.0, _radius * 0.74, t)
		draw_circle(target_local, outer_r, Color(_color.r, _color.g, _color.b, fade * 0.22))
		draw_arc(target_local, outer_r, 0.0, TAU, 44, Color(_color.r, _color.g, _color.b, fade * 0.98), 4.2, true)
		draw_arc(target_local, inner_r, 0.0, TAU, 36, Color(1.0, 0.95, 0.78, fade * 0.85), 2.4, true)
		draw_arc(target_local, _radius, 0.0, TAU, 44, Color(_color.r, _color.g, _color.b, fade * 0.36), 1.4, true)
		for i: int in range(12):
			var ang: float = TAU * float(i) / 12.0
			var radial: Vector2 = Vector2.RIGHT.rotated(ang)
			var p_in: Vector2 = target_local + radial * maxf(10.0, inner_r * 0.72)
			var p_out: Vector2 = target_local + radial * outer_r
			draw_line(p_in, p_out, Color(1.0, 0.86, 0.54, fade * 0.78), 2.2, true)
	else:
		var pulse_r: float = lerpf(8.0, _radius, t)
		var ring_col: Color = _color
		ring_col.a = fade * 0.95
		draw_arc(target_local, pulse_r, 0.0, TAU, 36, ring_col, 3.0, true)
		draw_arc(target_local, pulse_r * 0.76, t * 2.0, t * 2.0 + PI * 0.75, 16, Color(_color.r, _color.g, _color.b, fade * 0.65), 2.0, true)
		draw_arc(target_local, pulse_r * 0.76, t * 2.0 + PI, t * 2.0 + PI * 1.75, 16, Color(_color.r, _color.g, _color.b, fade * 0.65), 2.0, true)
		draw_circle(target_local, pulse_r * 0.65, Color(_color.r, _color.g, _color.b, fade * 0.16))
