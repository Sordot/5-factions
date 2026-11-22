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
	CASTING_ABILITY,
	GATHERING,
}

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")
const ABILITY_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/ability_component.gd")
const HIT_FLASH_DURATION: float = 0.10
const HEALTH_BAR_WIDTH: float = 36.0
const GATHER_BAR_WIDTH: float = 32.0
const SETTLE_PROXIMITY_RADIUS: float = 160.0
const SETTLE_NO_PROGRESS_TIME: float = 0.45

signal selection_changed(unit: Unit, selected: bool)
signal health_changed(unit: Unit, current_hp: float, max_hp: float)
signal died(unit: Unit)
signal ability_cooldown_updated(ability_id: StringName, remaining: float, duration: float)
signal ability_executed(ability_id: StringName, target_pos: Vector2)
signal cargo_changed(unit: Unit, resource_type: StringName, amount: int)

@export var team: Team = Team.PLAYER
@export var data: UnitData
@export var always_show_health_bar: bool = false

@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
@onready var selection_ring: Node2D = $SelectionRing
@onready var body_visual: Node2D = $BodyVisual
@onready var health_bar_root: Node2D = get_node_or_null("HealthBar") as Node2D
@onready var health_bar_fill: ColorRect = get_node_or_null("HealthBar/Fill") as ColorRect
@onready var gather_component: GatherComponent = get_node_or_null("GatherComponent") as GatherComponent
@onready var cargo_visual: Node2D = get_node_or_null("BodyVisual/CargoVisual") as Node2D
@onready var gather_bar_root: Node2D = get_node_or_null("GatherBar") as Node2D
@onready var gather_bar_fill: ColorRect = get_node_or_null("GatherBar/Fill") as ColorRect

var is_selected: bool = false
var is_dead: bool = false
var current_hp: float = 100.0
var command_state: CommandState = CommandState.IDLE
var current_target: Unit = null
var ability_component: AbilityComponent = null

var _move_destination: Vector2 = Vector2.ZERO
var _attack_move_destination: Vector2 = Vector2.ZERO
var _attack_cooldown_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _last_nav_target: Vector2 = Vector2.INF

var _wants_nav_movement: bool = false
var _desired_move_velocity: Vector2 = Vector2.ZERO
var _last_delta: float = 1.0 / 60.0
var _no_progress_timer: float = 0.0
var _best_dist_to_goal: float = INF


func _ready() -> void:
	add_to_group("units")
	add_to_group("selectable_units")
	if data == null:
		data = UnitData.new()
	current_hp = data.max_hp
	selection_ring.visible = is_selected
	_update_health_bar()

	if nav_agent != null:
		nav_agent.max_speed = maxf(1.0, data.move_speed)
		nav_agent.radius = data.collision_radius + 2.0
		if not nav_agent.velocity_computed.is_connected(_on_nav_velocity_computed):
			nav_agent.velocity_computed.connect(_on_nav_velocity_computed)

	ability_component = ABILITY_COMPONENT_SCRIPT.new()
	ability_component.name = "AbilityComponent"
	add_child(ability_component)
	ability_component.ability_cooldown_updated.connect(func(ability_id: StringName, remaining: float, duration: float) -> void:
		ability_cooldown_updated.emit(ability_id, remaining, duration)
	)
	ability_component.ability_executed.connect(func(ability_id: StringName, target_pos: Vector2) -> void:
		ability_executed.emit(ability_id, target_pos)
	)

	if gather_component != null:
		if not gather_component.cargo_changed.is_connected(_on_gather_cargo_changed):
			gather_component.cargo_changed.connect(_on_gather_cargo_changed)
		if not gather_component.gather_progress_changed.is_connected(_on_gather_progress_changed):
			gather_component.gather_progress_changed.connect(_on_gather_progress_changed)
	if cargo_visual != null:
		cargo_visual.visible = false
	if gather_bar_root != null:
		gather_bar_root.visible = false

	_register_with_economy()


func _exit_tree() -> void:
	_unregister_from_economy()


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


func get_unit_type_id() -> StringName:
	return data.unit_type_id if data != null else &"unit"


func is_ability_ready(ability: AbilityData) -> bool:
	return ability_component != null and ability_component.is_ability_ready(ability)


func get_ability_remaining_cooldown(ability_id: StringName) -> float:
	return ability_component.get_remaining_cooldown(ability_id) if ability_component != null else 0.0


func command_cast_ability(ability: AbilityData, target_pos: Vector2, target_unit: Unit = null) -> bool:
	if is_dead or ability_component == null or ability == null:
		return false
	var accepted: bool = ability_component.request_cast(self, ability, target_pos, target_unit)
	if not accepted:
		return false
	if gather_component != null:
		gather_component.cancel()
	if ability_component.has_pending_cast():
		if not _can_move():
			ability_component.cancel_pending_cast()
			return false
		command_state = CommandState.CASTING_ABILITY
		current_target = null
		_reset_progress_tracker()
		_last_nav_target = Vector2.INF
	return true


func can_gather() -> bool:
	return data != null and data.can_gather and gather_component != null


func is_carrying_cargo() -> bool:
	return gather_component != null and gather_component.has_cargo()


func get_carried_amount() -> int:
	return gather_component.carried_amount if gather_component != null else 0


func get_carried_type() -> StringName:
	return gather_component.carried_type if gather_component != null else &""


func command_gather(resource_node: ResourceNode) -> bool:
	if is_dead or not can_gather() or not _can_move() or resource_node == null:
		return false
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if not gather_component.start_gather(self, resource_node):
		return false
	command_state = CommandState.GATHERING
	current_target = null
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF
	return true


func command_return_cargo(building: Building = null) -> bool:
	if is_dead or not can_gather() or not _can_move() or not is_carrying_cargo():
		return false
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if not gather_component.start_return_cargo(self, building):
		return false
	command_state = CommandState.GATHERING
	current_target = null
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF
	return true


func request_component_navigation(target_point: Vector2, repath_threshold: float = 10.0) -> void:
	_request_nav_toward_point(target_point, repath_threshold)
	if not _wants_nav_movement:
		var to_target: Vector2 = target_point - global_position
		if to_target.length_squared() > 4.0:
			var dir: Vector2 = _steer_around_static_units(to_target.normalized())
			_wants_nav_movement = true
			_desired_move_velocity = dir * data.move_speed


func face_world_point(world_point: Vector2, delta: float) -> void:
	_face_point(world_point, delta)


func stop_component_navigation() -> void:
	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_clear_nav_target()


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0 or data == null:
		return
	var next_hp: float = minf(data.max_hp, current_hp + amount)
	if is_equal_approx(next_hp, current_hp):
		return
	current_hp = next_hp
	_update_health_bar()
	health_changed.emit(self, current_hp, data.max_hp)


func command_move(target_pos: Vector2) -> void:
	if is_dead or not _can_move():
		return
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if gather_component != null:
		gather_component.cancel()
	command_state = CommandState.MOVING
	current_target = null
	_move_destination = target_pos
	_reset_progress_tracker()
	_set_nav_target(target_pos)


func command_attack_target(target: Unit) -> void:
	if is_dead or not _can_attack():
		return
	if not is_instance_valid(target) or target.is_dead or target.team == team:
		return
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if gather_component != null:
		gather_component.cancel()
	command_state = CommandState.ATTACKING_TARGET
	current_target = target
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF


func command_attack_move(target_pos: Vector2) -> void:
	if is_dead or not _can_move():
		return
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if gather_component != null:
		gather_component.cancel()
	command_state = CommandState.ATTACK_MOVING
	_attack_move_destination = target_pos
	_move_destination = target_pos
	current_target = null
	_reset_progress_tracker()
	_set_nav_target(target_pos)


func command_stop() -> void:
	if is_dead:
		return
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if gather_component != null:
		gather_component.cancel()
	command_state = CommandState.IDLE
	current_target = null
	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO
	_reset_progress_tracker()
	velocity = Vector2.ZERO
	_clear_nav_target()


func command_hold_position() -> void:
	if is_dead:
		return
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if gather_component != null:
		gather_component.cancel()
	command_state = CommandState.HOLD_POSITION
	current_target = null
	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO
	_reset_progress_tracker()
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
	if gather_component != null:
		gather_component.cancel()
	command_state = CommandState.IDLE
	current_target = null
	_wants_nav_movement = false
	velocity = Vector2.ZERO
	set_selected(false)
	_unregister_from_economy()
	died.emit(self)
	queue_free()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_last_delta = delta
	if current_target != null and (not is_instance_valid(current_target) or current_target.is_dead):
		current_target = null

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)

	if ability_component != null:
		ability_component.tick_cooldowns(delta)

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _hit_flash_timer <= 0.0:
			body_visual.modulate = Color.WHITE

	if not _can_move() and not _can_attack():
		return

	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO

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
		CommandState.CASTING_ABILITY:
			_process_casting_ability(delta)
		CommandState.GATHERING:
			_process_gathering(delta)

	if _can_move() and nav_agent != null and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(_desired_move_velocity)
		if not _wants_nav_movement:
			_apply_stationary_separation(delta)
	else:
		_apply_direct_motion(_desired_move_velocity, delta)


func _on_nav_velocity_computed(safe_velocity: Vector2) -> void:
	if is_dead or not _wants_nav_movement:
		return
	_apply_direct_motion(safe_velocity, _last_delta)


func _process_idle(delta: float) -> void:
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
	if _should_settle_at_destination(_move_destination, delta):
		command_state = CommandState.IDLE
		_reset_progress_tracker()
		velocity = Vector2.ZERO
		return
	_compute_nav_desired_velocity()


func _process_attack_moving(delta: float) -> void:
	if _can_attack():
		var leash_range: float = maxf(data.aggro_range, data.attack_range) * 1.25
		if not _is_valid_enemy_in_range(current_target, leash_range):
			current_target = null
		if current_target == null:
			current_target = _find_nearest_enemy(data.aggro_range)

	if current_target != null:
		_reset_progress_tracker()
		if _distance_to_unit_edge(current_target) <= data.attack_range:
			_face_point(current_target.global_position, delta)
			_try_fire_at(current_target)
			return
		_request_nav_toward_point(current_target.global_position, 8.0)
		return

	if nav_agent == null:
		command_state = CommandState.IDLE
		return
	if _last_nav_target == Vector2.INF or _last_nav_target.distance_squared_to(_attack_move_destination) > 1.0:
		_set_nav_target(_attack_move_destination)
	if not _is_nav_map_ready():
		return
	if _should_settle_at_destination(_attack_move_destination, delta):
		command_state = CommandState.IDLE
		_reset_progress_tracker()
		velocity = Vector2.ZERO
		return
	_compute_nav_desired_velocity()


func _process_attacking_target(delta: float) -> void:
	if not is_instance_valid(current_target) or current_target.is_dead:
		current_target = null
		command_state = CommandState.IDLE
		velocity = Vector2.ZERO
		return

	if _distance_to_unit_edge(current_target) <= data.attack_range:
		_face_point(current_target.global_position, delta)
		_try_fire_at(current_target)
		return

	if _can_move():
		_request_nav_toward_point(current_target.global_position, 6.0)


func _process_hold_position(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _can_attack():
		return
	if not _is_valid_enemy_in_range(current_target, data.attack_range):
		current_target = _find_nearest_enemy(data.attack_range)
	if current_target != null:
		_face_point(current_target.global_position, delta)
		_try_fire_at(current_target)


func _process_casting_ability(delta: float) -> void:
	if ability_component == null or not ability_component.has_pending_cast():
		command_state = CommandState.IDLE
		return
	if ability_component.try_complete_pending_cast(self):
		command_state = CommandState.IDLE
		velocity = Vector2.ZERO
		return
	var dest: Vector2 = ability_component.get_pending_destination()
	_face_point(dest, delta)
	_request_nav_toward_point(dest, 8.0)


func _process_gathering(delta: float) -> void:
	if gather_component == null or not gather_component.is_active():
		command_state = CommandState.IDLE
		return
	gather_component.tick(self, delta)


func _request_nav_toward_point(target_point: Vector2, repath_threshold: float) -> void:
	if nav_agent == null:
		return
	if _last_nav_target == Vector2.INF or _last_nav_target.distance_squared_to(target_point) > repath_threshold * repath_threshold:
		_set_nav_target(target_point)
	if not _is_nav_map_ready():
		return
	if nav_agent.is_navigation_finished():
		return
	_compute_nav_desired_velocity()


func _compute_nav_desired_velocity() -> void:
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var to_next: Vector2 = next_point - global_position
	if to_next.length_squared() < 1.0:
		return
	var dir: Vector2 = to_next.normalized()
	dir = _steer_around_static_units(dir)
	_wants_nav_movement = true
	_desired_move_velocity = dir * data.move_speed


func _steer_around_static_units(move_dir: Vector2) -> Vector2:
	# Prevent head-on deadlocks against stationary TargetDummy bodies by adding
	# a deterministic tangential bias when a static unit blocks the forward path.
	var steer: Vector2 = move_dir
	var my_r: float = data.collision_radius if data != null else 16.0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or node == self:
			continue
		var other: Unit = node
		if not is_instance_valid(other) or other.is_dead:
			continue
		if other._can_move():
			continue
		var to_other: Vector2 = other.global_position - global_position
		var dist: float = to_other.length()
		var other_r: float = other.data.collision_radius if other.data != null else 18.0
		var avoid_dist: float = my_r + other_r + 36.0
		if dist <= 0.001 or dist > avoid_dist:
			continue
		var to_other_dir: Vector2 = to_other / dist
		var forward_dot: float = move_dir.dot(to_other_dir)
		if forward_dot <= 0.15:
			continue
		var cross: float = move_dir.cross(to_other_dir)
		var side: float = -1.0 if cross >= 0.0 else 1.0
		var tangent: Vector2 = Vector2(-to_other_dir.y, to_other_dir.x) * side
		var weight: float = clampf((avoid_dist - dist) / avoid_dist, 0.25, 1.0) * 1.4
		steer += tangent * weight
	return steer.normalized() if steer.length_squared() > 0.0001 else move_dir


func _apply_direct_motion(target_velocity: Vector2, delta: float) -> void:
	var accel: float = data.acceleration if data.acceleration > 0.0 else 1800.0
	if _wants_nav_movement:
		var sep: Vector2 = _compute_overlap_separation(1.0)
		var combined: Vector2 = target_velocity + sep
		if combined.length() > data.move_speed:
			combined = combined.normalized() * data.move_speed
		velocity = velocity.move_toward(combined, accel * delta)
		if velocity.length_squared() > 4.0:
			_face_angle(velocity.angle(), delta)
		move_and_slide()
		_check_post_slide_settling()
	else:
		_apply_stationary_separation(delta)


func _apply_stationary_separation(delta: float) -> void:
	if not _can_move():
		return
	if command_state == CommandState.GATHERING and gather_component != null and gather_component.is_harvesting_in_place():
		velocity = Vector2.ZERO
		return
	var sep_margin: float = 0.0 if command_state == CommandState.HOLD_POSITION else 2.5
	var sep: Vector2 = _compute_overlap_separation(sep_margin)
	if sep.length_squared() > 1.0:
		velocity = sep
		move_and_slide()
	elif velocity.length_squared() > 0.01:
		var decel: float = data.acceleration if data.acceleration > 0.0 else 1800.0
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
	else:
		velocity = Vector2.ZERO


func _compute_overlap_separation(extra_margin: float) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var my_r: float = data.collision_radius if data != null else 16.0
	var max_push: float = data.move_speed * 0.85 if data != null else 220.0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or node == self:
			continue
		var other: Unit = node
		if not is_instance_valid(other) or other.is_dead:
			continue
		var other_r: float = other.data.collision_radius if other.data != null else 16.0
		var min_dist: float = my_r + other_r + extra_margin
		var diff: Vector2 = global_position - other.global_position
		var dist_sq: float = diff.length_squared()
		if dist_sq >= min_dist * min_dist:
			continue
		var dir: Vector2
		var dist: float = sqrt(dist_sq)
		if dist < 0.01:
			var angle: float = fmod(float(get_instance_id() % 360) * 1.618, TAU)
			dir = Vector2.RIGHT.rotated(angle)
		else:
			dir = diff / dist
		var overlap_ratio: float = clampf((min_dist - dist) / maxf(1.0, min_dist), 0.15, 1.0)
		push += dir * max_push * overlap_ratio
	if push.length() > max_push:
		push = push.normalized() * max_push
	return push


func _reset_progress_tracker() -> void:
	_no_progress_timer = 0.0
	_best_dist_to_goal = INF


func _should_settle_at_destination(goal_pos: Vector2, delta: float) -> bool:
	var dist_to_goal: float = global_position.distance_to(goal_pos)
	if dist_to_goal <= nav_agent.target_desired_distance or nav_agent.is_navigation_finished():
		return true
	if dist_to_goal < _best_dist_to_goal - 4.0:
		_best_dist_to_goal = dist_to_goal
		_no_progress_timer = 0.0
	elif dist_to_goal <= SETTLE_PROXIMITY_RADIUS:
		_no_progress_timer += delta
		if _no_progress_timer >= SETTLE_NO_PROGRESS_TIME:
			return true
	return false


func _check_post_slide_settling() -> void:
	if command_state != CommandState.MOVING and not (command_state == CommandState.ATTACK_MOVING and current_target == null):
		return
	var goal_pos: Vector2 = _move_destination if command_state == CommandState.MOVING else _attack_move_destination
	if global_position.distance_to(goal_pos) > SETTLE_PROXIMITY_RADIUS:
		return
	for i: int in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider is Unit:
			var other: Unit = collider
			if other.team == team and other.command_state == CommandState.IDLE:
				command_state = CommandState.IDLE
				_wants_nav_movement = false
				_reset_progress_tracker()
				velocity = Vector2.ZERO
				return


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
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector2.ZERO)


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


func _on_gather_cargo_changed(resource_type: StringName, amount: int) -> void:
	if cargo_visual != null:
		cargo_visual.visible = amount > 0
	cargo_changed.emit(self, resource_type, amount)


func _on_gather_progress_changed(progress: float, is_active: bool) -> void:
	if gather_bar_root == null or gather_bar_fill == null:
		return
	gather_bar_root.visible = is_active
	gather_bar_fill.size.x = GATHER_BAR_WIDTH * clampf(progress, 0.0, 1.0)


func _register_with_economy() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		var cost: int = data.bandwidth_cost if data != null else 1
		econ.register_unit_bandwidth(self, team, cost)


func _unregister_from_economy() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.unregister_unit_bandwidth(self)
