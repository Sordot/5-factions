class_name AbilityTargetingReticle
extends Node2D

var _active: bool = false
var _ability: AbilityData = null
var _caster_pos: Vector2 = Vector2.ZERO
var _has_caster: bool = false
var _cursor_world: Vector2 = Vector2.ZERO


func set_targeting(ability: AbilityData, caster_pos: Vector2, has_caster: bool, cursor_world: Vector2) -> void:
	_ability = ability
	_active = ability != null
	_caster_pos = caster_pos
	_has_caster = has_caster
	_cursor_world = cursor_world
	queue_redraw()


func clear_targeting() -> void:
	if not _active:
		return
	_active = false
	_ability = null
	_has_caster = false
	queue_redraw()


func _draw() -> void:
	if not _active or _ability == null:
		return

	var cursor_local: Vector2 = to_local(_cursor_world)
	var in_range: bool = true
	if _has_caster and _ability.cast_range > 0.0:
		var caster_local: Vector2 = to_local(_caster_pos)
		in_range = _caster_pos.distance_to(_cursor_world) <= _ability.cast_range
		draw_arc(caster_local, _ability.cast_range, 0.0, TAU, 48, Color(0.32, 0.88, 0.96, 0.35), 1.5, true)

	var accent: Color = Color(0.32, 0.96, 1.0, 0.9) if in_range else Color(1.0, 0.66, 0.24, 0.9)
	if _ability.target_type == AbilityData.TargetType.POINT_AOE and _ability.aoe_radius > 0.0:
		draw_circle(cursor_local, _ability.aoe_radius, Color(accent.r, accent.g, accent.b, 0.14))
		draw_arc(cursor_local, _ability.aoe_radius, 0.0, TAU, 40, accent, 2.0, true)

	draw_arc(cursor_local, 10.0, 0.0, TAU, 24, accent, 1.8, true)
	draw_line(cursor_local + Vector2(-16.0, 0.0), cursor_local + Vector2(-5.0, 0.0), accent, 1.8, true)
	draw_line(cursor_local + Vector2(5.0, 0.0), cursor_local + Vector2(16.0, 0.0), accent, 1.8, true)
	draw_line(cursor_local + Vector2(0.0, -16.0), cursor_local + Vector2(0.0, -5.0), accent, 1.8, true)
	draw_line(cursor_local + Vector2(0.0, 5.0), cursor_local + Vector2(0.0, 16.0), accent, 1.8, true)
