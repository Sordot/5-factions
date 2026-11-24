class_name AbilityTargetingReticle
extends Node2D

var _active: bool = false
var _ability: AbilityData = null
var _caster_pos: Vector2 = Vector2.ZERO
var _has_caster: bool = false
var _cursor_world: Vector2 = Vector2.ZERO

var _command_mode: StringName = &""
var _command_cursor_world: Vector2 = Vector2.ZERO


func set_targeting(ability: AbilityData, caster_pos: Vector2, has_caster: bool, cursor_world: Vector2) -> void:
	_ability = ability
	_active = ability != null
	_caster_pos = caster_pos
	_has_caster = has_caster
	_cursor_world = cursor_world
	if _active:
		_command_mode = &""
	queue_redraw()


func clear_targeting() -> void:
	if not _active:
		return
	_active = false
	_ability = null
	_has_caster = false
	queue_redraw()


func set_command_mode_reticle(mode: StringName, cursor_world: Vector2) -> void:
	_command_mode = mode
	_command_cursor_world = cursor_world
	queue_redraw()


func clear_command_mode_reticle() -> void:
	if _command_mode == &"":
		return
	_command_mode = &""
	queue_redraw()


func _draw() -> void:
	if _active and _ability != null:
		_draw_ability_reticle()
		return
	if _command_mode != &"":
		_draw_command_mode_reticle()


func _draw_ability_reticle() -> void:
	var cursor_local: Vector2 = to_local(_cursor_world)
	var in_range: bool = true
	if _has_caster and _ability.cast_range > 0.0:
		var caster_local: Vector2 = to_local(_caster_pos)
		in_range = _caster_pos.distance_to(_cursor_world) <= _ability.cast_range
		var range_col: Color = Color(0.56, 0.88, 1.0, 0.34) if in_range else Color(1.0, 0.62, 0.24, 0.42)
		_draw_dashed_circle(caster_local, _ability.cast_range, range_col, 1.6, 36)

	# Color-coded reticle: amber/violet tint for ability targeting, warm orange warning when out of cast range
	var base_accent: Color = Color(0.74, 0.56, 1.0, 0.94) if _ability.ability_id == &"static_pulse" else Color(1.0, 0.78, 0.30, 0.94)
	if _ability.effect_color.a > 0.2 and _ability.ability_id != &"static_pulse":
		base_accent = base_accent.lerp(_ability.effect_color, 0.45)
	var accent: Color = base_accent if in_range else Color(1.0, 0.46, 0.22, 0.94)

	if _ability.target_type == AbilityData.TargetType.POINT_AOE and _ability.aoe_radius > 0.0:
		draw_circle(cursor_local, _ability.aoe_radius, Color(accent.r, accent.g, accent.b, 0.14))
		draw_arc(cursor_local, _ability.aoe_radius, 0.0, TAU, 40, accent, 2.0, true)
		_draw_dashed_circle(cursor_local, _ability.aoe_radius * 0.55, Color(accent.r, accent.g, accent.b, 0.42), 1.2, 16)

	_draw_crosshair(cursor_local, accent, 10.0, 17.0)


func _draw_command_mode_reticle() -> void:
	var cursor_local: Vector2 = to_local(_command_cursor_world)
	var accent: Color = Color(0.30, 0.92, 1.0, 0.94)
	if _command_mode == &"attack_move":
		accent = Color(1.0, 0.34, 0.28, 0.96)
	elif _command_mode == &"patrol":
		accent = Color(0.32, 0.94, 0.98, 0.94)

	draw_circle(cursor_local, 13.0, Color(accent.r, accent.g, accent.b, 0.12))
	_draw_crosshair(cursor_local, accent, 11.0, 18.0)

	if _command_mode == &"patrol":
		# Gold secondary diamond accent to distinguish Patrol cleanly from Move/Ability
		var gold: Color = Color(1.0, 0.84, 0.32, 0.92)
		var pts: PackedVector2Array = PackedVector2Array([
			cursor_local + Vector2(0.0, -7.0),
			cursor_local + Vector2(7.0, 0.0),
			cursor_local + Vector2(0.0, 7.0),
			cursor_local + Vector2(-7.0, 0.0),
			cursor_local + Vector2(0.0, -7.0),
		])
		draw_polyline(pts, gold, 1.5, true)


func _draw_crosshair(center: Vector2, accent: Color, ring_r: float, arm_outer: float) -> void:
	draw_arc(center, ring_r, 0.0, TAU, 24, accent, 1.8, true)
	draw_line(center + Vector2(-arm_outer, 0.0), center + Vector2(-5.0, 0.0), accent, 1.8, true)
	draw_line(center + Vector2(5.0, 0.0), center + Vector2(arm_outer, 0.0), accent, 1.8, true)
	draw_line(center + Vector2(0.0, -arm_outer), center + Vector2(0.0, -5.0), accent, 1.8, true)
	draw_line(center + Vector2(0.0, 5.0), center + Vector2(0.0, arm_outer), accent, 1.8, true)


func _draw_dashed_circle(center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(6, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.56
		draw_arc(center, radius, a0, a1, 4, col, width, true)
