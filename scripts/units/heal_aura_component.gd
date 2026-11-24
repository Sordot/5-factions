class_name HealAuraComponent
extends Node2D

const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const TICK_INTERVAL: float = 0.5
const PULSE_VISUAL_DURATION: float = 0.42
const HEAL_TICK_VFX_COOLDOWN_MS: int = 1100

@export var heal_per_second: float = 2.0
@export var aura_radius: float = 130.0

var _tick_timer: float = 0.0
var _pulse_timer: float = 0.0
var _ambient_time: float = 0.0
var _last_vfx_ms: Dictionary = {}


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
	var now_ms: int = Time.get_ticks_msec()
	var tick_col: Color = Color(0.32, 1.0, 0.68, 0.95) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.48, 0.36, 0.95)

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
			var ally_id: int = ally.get_instance_id()
			var prev_ms: int = int(_last_vfx_ms.get(ally_id, -99999))
			if (now_ms - prev_ms) >= HEAL_TICK_VFX_COOLDOWN_MS and ally.visible:
				_last_vfx_ms[ally_id] = now_ms
				_spawn_heal_tick_vfx(owner_unit, ally.global_position, tick_col)

	if healed_any:
		_pulse_timer = PULSE_VISUAL_DURATION
		queue_redraw()


func _spawn_heal_tick_vfx(owner_unit: Unit, world_pos: Vector2, vfx_color: Color) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
	fx.z_index = 54
	owner_unit.get_parent().add_child(fx)
	fx.call("setup_heal_tick", world_pos, vfx_color)


func _draw() -> void:
	var owner_unit: Unit = get_parent() as Unit
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed:
		return
	var radius: float = owner_unit.data.heal_aura_radius if (owner_unit.data != null and owner_unit.data.heal_aura_radius > 0.0) else aura_radius
	if radius <= 0.0:
		return

	var aura_col: Color = Color(0.26, 0.98, 0.68, 1.0) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.44, 0.36, 1.0)
	var ambient_pulse: float = 0.5 + 0.5 * sin(_ambient_time * 2.6)
	var actively_healing: bool = _pulse_timer > 0.0
	var base_alpha: float = 0.36 if owner_unit.is_selected else (0.20 if actively_healing else (0.08 + ambient_pulse * 0.05))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 44, Color(aura_col.r, aura_col.g, aura_col.b, base_alpha), 1.6 if owner_unit.is_selected else 1.1, true)
	draw_circle(Vector2.ZERO, radius, Color(aura_col.r, aura_col.g, aura_col.b, 0.045 if owner_unit.is_selected else (0.025 if actively_healing else 0.012)))

	if actively_healing:
		var t: float = 1.0 - (_pulse_timer / PULSE_VISUAL_DURATION)
		var ring_r: float = lerpf(16.0, radius, t)
		var alpha: float = (1.0 - t) * 0.48
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 36, Color(aura_col.r, aura_col.g, aura_col.b, alpha), 2.0, true)
		draw_circle(Vector2.ZERO, ring_r * 0.65, Color(aura_col.r, aura_col.g, aura_col.b, alpha * 0.16))
