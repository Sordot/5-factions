class_name EncroachingZone
extends Node2D

enum ZoneState {
	WAITING,
	SHRINKING,
	FINAL_LOCK,
}

signal zone_updated(phase_index: int, state_label: String, time_remaining: float, current_radius: float)

@export var zone_center: Vector2 = Vector2.ZERO
@export var initial_radius: float = 760.0
@export var phase_wait_times: PackedFloat32Array = PackedFloat32Array([180.0, 60.0, 45.0])
@export var phase_shrink_durations: PackedFloat32Array = PackedFloat32Array([35.0, 30.0, 25.0])
@export var phase_target_radii: PackedFloat32Array = PackedFloat32Array([500.0, 320.0, 175.0])
@export var hazard_dps: float = 12.0
@export var tick_interval: float = 0.5
@export var active: bool = true

var current_phase: int = 0
var state: ZoneState = ZoneState.WAITING
var current_radius: float = 760.0

var _phase_timer: float = 0.0
var _shrink_start_radius: float = 760.0
var _damage_tick_timer: float = 0.0
var _hud_emit_timer: float = 0.0
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("encroaching_zone")
	z_index = 40
	reset_zone()


func reset_zone() -> void:
	current_phase = 0
	state = ZoneState.WAITING
	current_radius = initial_radius
	_shrink_start_radius = initial_radius
	_phase_timer = phase_wait_times[0] if phase_wait_times.size() > 0 else 180.0
	_damage_tick_timer = 0.0
	_emit_zone_status()
	queue_redraw()


func trigger_next_phase_now() -> void:
	if state == ZoneState.WAITING and current_phase < phase_target_radii.size():
		_start_shrinking_phase()
	elif state == ZoneState.SHRINKING:
		current_radius = phase_target_radii[current_phase]
		_advance_after_shrink()
	_emit_zone_status()
	queue_redraw()


func _process(delta: float) -> void:
	if not active:
		return
	_pulse_time += delta

	match state:
		ZoneState.WAITING:
			_phase_timer = maxf(0.0, _phase_timer - delta)
			if _phase_timer <= 0.0:
				_start_shrinking_phase()
		ZoneState.SHRINKING:
			var dur: float = maxf(0.1, phase_shrink_durations[current_phase])
			_phase_timer = maxf(0.0, _phase_timer - delta)
			var t: float = clampf(1.0 - (_phase_timer / dur), 0.0, 1.0)
			current_radius = lerpf(_shrink_start_radius, phase_target_radii[current_phase], t)
			if _phase_timer <= 0.0:
				current_radius = phase_target_radii[current_phase]
				_advance_after_shrink()
		ZoneState.FINAL_LOCK:
			pass

	# Apply periodic disruption damage to any unit or building outside safe radius.
	_damage_tick_timer += delta
	if _damage_tick_timer >= tick_interval:
		_damage_tick_timer -= tick_interval
		_apply_hazard_damage(hazard_dps * tick_interval)

	_hud_emit_timer += delta
	if _hud_emit_timer >= 0.25:
		_hud_emit_timer = 0.0
		_emit_zone_status()

	queue_redraw()


func _start_shrinking_phase() -> void:
	if current_phase >= phase_target_radii.size():
		state = ZoneState.FINAL_LOCK
		_phase_timer = 0.0
		return
	state = ZoneState.SHRINKING
	_shrink_start_radius = current_radius
	_phase_timer = phase_shrink_durations[current_phase] if current_phase < phase_shrink_durations.size() else 30.0
	_emit_zone_status()


func _advance_after_shrink() -> void:
	current_phase += 1
	if current_phase >= phase_target_radii.size():
		state = ZoneState.FINAL_LOCK
		_phase_timer = 0.0
	else:
		state = ZoneState.WAITING
		_phase_timer = phase_wait_times[current_phase] if current_phase < phase_wait_times.size() else 45.0
	_emit_zone_status()


func _apply_hazard_damage(damage_amount: float) -> void:
	if damage_amount <= 0.0:
		return
	var safe_r_sq: float = current_radius * current_radius
	var world_center: Vector2 = global_position + zone_center

	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed:
			continue
		if unit.global_position.distance_squared_to(world_center) > safe_r_sq:
			unit.take_damage(damage_amount, null)

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed:
			continue
		if b.global_position.distance_squared_to(world_center) > safe_r_sq:
			b.take_damage(damage_amount)


func get_state_label() -> String:
	match state:
		ZoneState.WAITING:
			return "ZONE P%d" % (current_phase + 1)
		ZoneState.SHRINKING:
			return "SHRINK P%d" % (current_phase + 1)
		ZoneState.FINAL_LOCK:
			return "ZONE FINAL"
	return "ZONE"


func _emit_zone_status() -> void:
	zone_updated.emit(current_phase + 1, get_state_label(), _phase_timer, current_radius)


func _draw() -> void:
	var pulse: float = 0.72 + 0.28 * sin(_pulse_time * 4.5)
	var ring_col: Color = Color(1.0, 0.24, 0.36, 0.85 * pulse) if state == ZoneState.SHRINKING else Color(1.0, 0.36, 0.42, 0.58)
	draw_arc(zone_center, current_radius, 0.0, TAU, 96, ring_col, 3.0, true)
	draw_arc(zone_center, current_radius + 6.0, 0.0, TAU, 96, Color(ring_col.r, ring_col.g, ring_col.b, 0.22), 8.0, true)

	# Show next target perimeter preview while waiting or shrinking
	if current_phase < phase_target_radii.size():
		var next_r: float = phase_target_radii[current_phase]
		var preview_col: Color = Color(1.0, 0.72, 0.28, 0.32)
		var segs: int = 48
		for i: int in range(0, segs, 2):
			var a0: float = TAU * float(i) / float(segs)
			var a1: float = TAU * float(i + 1) / float(segs)
			draw_arc(zone_center, next_r, a0, a1, 4, preview_col, 1.5, true)
