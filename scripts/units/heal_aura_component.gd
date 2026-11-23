class_name HealAuraComponent
extends Node2D

const TICK_INTERVAL: float = 0.5
const PULSE_VISUAL_DURATION: float = 0.42

@export var heal_per_second: float = 2.0
@export var aura_radius: float = 130.0

var _tick_timer: float = 0.0
var _pulse_timer: float = 0.0
var _ambient_time: float = 0.0


func _process(delta: float) -> void:
	var owner_unit: Unit = get_parent() as Unit
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed:
		return

	_ambient_time += delta
	if _pulse_timer > 0.0:
		_pulse_timer = maxf(0.0, _pulse_timer - delta)
	queue_redraw()

	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer -= TICK_INTERVAL
	_apply_heal_tick(owner_unit)


func _apply_heal_tick(owner_unit: Unit) -> void:
	var rate: float = owner_unit.data.heal_aura_rate if (owner_unit.data != null and owner_unit.data.heal_aura_rate > 0.0) else heal_per_second
	var radius: float = owner_unit.data.heal_aura_radius if (owner_unit.data != null and owner_unit.data.heal_aura_radius > 0.0) else aura_radius
	if rate <= 0.0 or radius <= 0.0 or not owner_unit.is_inside_tree():
		return

	var heal_amount: float = rate * TICK_INTERVAL
	var radius_sq: float = radius * radius
	var healed_any: bool = false

	for node: Node in owner_unit.get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or node == owner_unit or not is_instance_valid(node):
			continue
		var ally: Unit = node
		if ally.is_dead or ally.is_staffed or ally.team != owner_unit.team or ally.data == null:
			continue
		if ally.current_hp >= ally.data.max_hp:
			continue
		if owner_unit.global_position.distance_squared_to(ally.global_position) <= radius_sq:
			ally.heal(heal_amount)
			healed_any = true

	if healed_any:
		_pulse_timer = PULSE_VISUAL_DURATION
		queue_redraw()


func _draw() -> void:
	var owner_unit: Unit = get_parent() as Unit
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed:
		return
	var radius: float = owner_unit.data.heal_aura_radius if (owner_unit.data != null and owner_unit.data.heal_aura_radius > 0.0) else aura_radius
	if radius <= 0.0:
		return

	var aura_col: Color = Color(0.26, 0.98, 0.68, 1.0) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.44, 0.36, 1.0)
	var ambient_pulse: float = 0.5 + 0.5 * sin(_ambient_time * 2.6)
	var base_alpha: float = 0.32 if owner_unit.is_selected else (0.10 + ambient_pulse * 0.07)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 44, Color(aura_col.r, aura_col.g, aura_col.b, base_alpha), 1.5 if owner_unit.is_selected else 1.1, true)
	draw_circle(Vector2.ZERO, radius, Color(aura_col.r, aura_col.g, aura_col.b, 0.035 if owner_unit.is_selected else 0.018))

	if _pulse_timer > 0.0:
		var t: float = 1.0 - (_pulse_timer / PULSE_VISUAL_DURATION)
		var ring_r: float = lerpf(16.0, radius, t)
		var alpha: float = (1.0 - t) * 0.45
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 36, Color(aura_col.r, aura_col.g, aura_col.b, alpha), 2.0, true)
		draw_circle(Vector2.ZERO, ring_r * 0.65, Color(aura_col.r, aura_col.g, aura_col.b, alpha * 0.16))
