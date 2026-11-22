class_name Unit
extends CharacterBody2D

enum Team {
	PLAYER,
	ENEMY,
}

enum CommandState {
	IDLE,
	MOVING,
	ATTACK_MOVING,
	ATTACKING_TARGET,
	HOLD_POSITION,
}

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")
const HIT_FLASH_DURATION: float = 0.10
const HEALTH_BAR_WIDTH: float = 36.0

signal selection_changed(unit: Unit, selected: bool)
signal health_changed(unit: Unit, current_hp: float, max_hp: float)
signal died(unit: Unit)

@export var team: Team = Team.PLAYER
@export var data: UnitData
@export var always_show_health_bar: bool = false

@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
@onready var selection_ring: Node2D = $SelectionRing
@onready var body_visual: Node2D = $BodyVisual
@onready var health_bar_root: Node2D = get_node_or_null("HealthBar") as Node2D
@onready var health_bar_fill: ColorRect = get_node_or_null("HealthBar/Fill") as ColorRect

var is_selected: bool = false
var is_dead: bool = false
var current_hp: float = 100.0
var command_state: CommandState = CommandState.IDLE
var current_target: Unit = null

var _attack_move_destination: Vector2 = Vector2.ZERO
var _attack_cooldown_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _last_nav_target: Vector2 = Vector2.INF


func _ready() -> void:
	add_to_group("units")
	add_to_group("selectable_units")
	if data == null:
		data = UnitData.new()
	current_hp = data.max_hp
	selection_ring.visible = is_selected
	_update_health_bar()


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	if is_node_ready():
		selection_ring.visible = is_selected
		_update_health_bar()
	selection_changed.emit(self, is_selected)


func contains_point(world_point: Vector2) -> bool:
	if is_dead:
		return false
	var radius: float = data.selection_radius if data != null else 20.0
	return global_position.distance_squared_to(world_point) <= radius * radius


func issue_move_command(target_pos: Vector2) -> void:
	command_move(target_pos)


func command_move(target_pos: Vector2) -> void:
	if is_dead or not _can_move():
		return
	command_state = CommandState.MOVING
	current_target = null
	_set_nav_target(target_pos)


func command_attack_target(target: Unit) -> void:
	if is_dead or not _can_attack():
		return
	if not is_instance_valid(target) or target.is_dead or target.team == team:
		return
	command_state = CommandState.ATTACKING_TARGET
	current_target = target
	_last_nav_target = Vector2.INF


func command_attack_move(target_pos: Vector2) -> void:
	if is_dead:
		return
	if not _can_move():
		return
	command_state = CommandState.ATTACK_MOVING
	_attack_move_destination = target_pos
	current_target = null
	_set_nav_target(target_pos)


func command_stop() -> void:
	if is_dead:
		return
	command_state = CommandState.IDLE
	current_target = null
	velocity = Vector2.ZERO
	_clear_nav_target()


func command_hold_position() -> void:
	if is_dead:
		return
	command_state = CommandState.HOLD_POSITION
	current_target = null
	velocity = Vector2.ZERO
	_clear_nav_target()


func take_damage(amount: float, _attacker: Unit = null) -> void:
	if is_dead or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_hit_flash_timer = HIT_FLASH_DURATION
	if is_node_ready():
		body_visual.modulate = Color(2.2, 2.2, 2.2, 1.0)
	_update_health_bar()
	health_changed.emit(self, current_hp, data.max_hp)
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	command_state = CommandState.IDLE
	current_target = null
	velocity = Vector2.ZERO
	set_selected(false)
	died.emit(self)
	queue_free()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if current_target != null and (not is_instance_valid(current_target) or current_target.is_dead):
		current_target = null

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _hit_flash_timer <= 0.0:
			body_visual.modulate = Color.WHITE

	if not _can_move() and not _can_attack():
		return

	match command_state:
		CommandState.IDLE:
			_process_idle(delta)
		CommandState.MOVING:
			_process_moving(delta)
		CommandState.ATTACK_MOVING:
			_process_attack_moving(delta)
		CommandState.ATTACKING_TARGET:
			_process_attacking_target(delta)
		CommandState.HOLD_POSITION:
			_process_hold_position(delta)


func _process_idle(delta: float) -> void:
	_decelerate_to_stop(delta)
	if not _can_attack():
		return
	if not _is_valid_enemy_in_range(current_target, data.attack_range):
		current_target = _find_nearest_enemy(data.attack_range)
	if current_target != null:
		_face_point(current_target.global_position, delta)
		_try_fire_at(current_target)


func _process_moving(delta: float) -> void:
	if nav_agent == null:
		command_state = CommandState.IDLE
		return
	if not _is_nav_map_ready():
		return
	if nav_agent.is_navigation_finished():
		command_state = CommandState.IDLE
		velocity = Vector2.ZERO
		return
	_step_along_nav_path(delta)


func _process_attack_moving(delta: float) -> void:
	if _can_attack():
		var leash_range: float = maxf(data.aggro_range, data.attack_range) * 1.25
		if not _is_valid_enemy_in_range(current_target, leash_range):
			current_target = null
		if current_target == null:
			current_target = _find_nearest_enemy(data.aggro_range)

	if current_target != null:
		if _distance_to_unit_edge(current_target) <= data.attack_range:
			_decelerate_to_stop(delta)
			_face_point(current_target.global_position, delta)
			_try_fire_at(current_target)
			return
		_navigate_toward_point(current_target.global_position, delta, 8.0)
		return

	if nav_agent == null:
		command_state = CommandState.IDLE
		return
	if _last_nav_target.distance_squared_to(_attack_move_destination) > 1.0:
		_set_nav_target(_attack_move_destination)
	if not _is_nav_map_ready():
		return
	if nav_agent.is_navigation_finished():
		command_state = CommandState.IDLE
		velocity = Vector2.ZERO
		return
	_step_along_nav_path(delta)


func _process_attacking_target(delta: float) -> void:
	if not is_instance_valid(current_target) or current_target.is_dead:
		current_target = null
		command_state = CommandState.IDLE
		velocity = Vector2.ZERO
		return

	if _distance_to_unit_edge(current_target) <= data.attack_range:
		_decelerate_to_stop(delta)
		_face_point(current_target.global_position, delta)
		_try_fire_at(current_target)
		return

	if _can_move():
		_navigate_toward_point(current_target.global_position, delta, 6.0)
	else:
		_decelerate_to_stop(delta)


func _process_hold_position(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _can_attack():
		return
	if not _is_valid_enemy_in_range(current_target, data.attack_range):
		current_target = _find_nearest_enemy(data.attack_range)
	if current_target != null:
		_face_point(current_target.global_position, delta)
		_try_fire_at(current_target)


func _navigate_toward_point(target_point: Vector2, delta: float, repath_threshold: float) -> void:
	if nav_agent == null:
		return
	if _last_nav_target == Vector2.INF or _last_nav_target.distance_squared_to(target_point) > repath_threshold * repath_threshold:
		_set_nav_target(target_point)
	if not _is_nav_map_ready():
		return
	if nav_agent.is_navigation_finished():
		_decelerate_to_stop(delta)
		return
	_step_along_nav_path(delta)


func _step_along_nav_path(delta: float) -> void:
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var to_next: Vector2 = next_point - global_position
	if to_next.length_squared() < 1.0:
		return
	var desired_velocity: Vector2 = to_next.normalized() * data.move_speed
	velocity = velocity.move_toward(desired_velocity, data.acceleration * delta)
	_face_angle(to_next.angle(), delta)
	move_and_slide()


func _decelerate_to_stop(delta: float) -> void:
	if velocity.length_squared() > 0.01:
		var decel: float = data.acceleration if data.acceleration > 0.0 else 1800.0
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
	else:
		velocity = Vector2.ZERO


func _face_point(world_point: Vector2, delta: float) -> void:
	var to_point: Vector2 = world_point - global_position
	if to_point.length_squared() > 0.01:
		_face_angle(to_point.angle(), delta)


func _face_angle(target_angle: float, delta: float) -> void:
	var turn_speed: float = data.turn_speed if data != null else 14.0
	body_visual.rotation = lerp_angle(
		body_visual.rotation,
		target_angle,
		clampf(turn_speed * delta, 0.0, 1.0)
	)


func _try_fire_at(target: Unit) -> void:
	if _attack_cooldown_timer > 0.0 or not is_instance_valid(target) or target.is_dead:
		return
	_attack_cooldown_timer = data.attack_cooldown
	var muzzle_offset: Vector2 = Vector2.RIGHT.rotated(body_visual.rotation) * data.collision_radius
	var tracer_origin: Vector2 = global_position + muzzle_offset
	var tracer_end: Vector2 = target.global_position
	_spawn_attack_tracer(tracer_origin, tracer_end)
	target.take_damage(data.attack_damage, self)


func _spawn_attack_tracer(from_pos: Vector2, to_pos: Vector2) -> void:
	if get_parent() == null:
		return
	var tracer: AttackTracer = ATTACK_TRACER_SCRIPT.new()
	tracer.z_index = 50
	get_parent().add_child(tracer)
	var tracer_color: Color = Color(0.32, 0.98, 0.90, 0.95) if team == Team.PLAYER else Color(1.0, 0.35, 0.25, 0.95)
	tracer.setup(from_pos, to_pos, tracer_color)


func _find_nearest_enemy(max_range: float) -> Unit:
	var best_enemy: Unit = null
	var best_dist: float = max_range
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit):
			continue
		var candidate: Unit = node
		if not is_instance_valid(candidate) or candidate.is_dead or candidate.team == team:
			continue
		var dist: float = _distance_to_unit_edge(candidate)
		if dist <= best_dist:
			best_dist = dist
			best_enemy = candidate
	return best_enemy


func _is_valid_enemy_in_range(candidate: Variant, max_range: float) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Unit):
		return false
	var target_unit: Unit = candidate
	if target_unit.is_dead or target_unit.team == team:
		return false
	return _distance_to_unit_edge(target_unit) <= max_range


func _distance_to_unit_edge(other: Unit) -> float:
	var center_dist: float = global_position.distance_to(other.global_position)
	var my_r: float = data.collision_radius if data != null else 16.0
	var other_r: float = other.data.collision_radius if other.data != null else 16.0
	return maxf(0.0, center_dist - my_r - other_r)


func _set_nav_target(target_pos: Vector2) -> void:
	if nav_agent == null:
		return
	nav_agent.target_position = target_pos
	_last_nav_target = target_pos


func _clear_nav_target() -> void:
	_last_nav_target = Vector2.INF
	if nav_agent != null and is_inside_tree():
		nav_agent.target_position = global_position


func _is_nav_map_ready() -> bool:
	if nav_agent == null:
		return false
	return NavigationServer2D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0


func _can_move() -> bool:
	return nav_agent != null and data != null and data.move_speed > 0.0


func _can_attack() -> bool:
	return data != null and data.attack_damage > 0.0 and data.attack_range > 0.0


func _update_health_bar() -> void:
	if health_bar_root == null or health_bar_fill == null or data == null:
		return
	var max_val: float = maxf(1.0, data.max_hp)
	var ratio: float = clampf(current_hp / max_val, 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	health_bar_root.visible = always_show_health_bar or is_selected or ratio < 0.999
