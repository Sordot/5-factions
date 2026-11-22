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
	CONSTRUCTING,
	STAFFING_BUILDING,
}

const ABILITY_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/ability_component.gd")
const COMBAT_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/combat_component.gd")
const HIT_FLASH_DURATION: float = 0.10
const HEALTH_BAR_WIDTH: float = 36.0
const GATHER_BAR_WIDTH: float = 32.0
const SETTLE_PROXIMITY_RADIUS: float = 160.0
const SETTLE_NO_PROGRESS_TIME: float = 0.45

signal selection_changed(unit: Unit, selected: bool)
signal health_changed(unit: Unit, current_hp: float, max_hp: float)
signal status_changed(unit: Unit)
signal died(unit: Unit)
signal ability_cooldown_updated(ability_id: StringName, remaining: float, duration: float)
signal ability_executed(ability_id: StringName, target_pos: Vector2)
signal cargo_changed(unit: Unit, resource_type: StringName, amount: int)
signal staffed_state_changed(unit: Unit, staffed: bool)

@export var team: Team = Team.PLAYER
@export var data: UnitData
@export var always_show_health_bar: bool = false

@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
@onready var selection_ring: Node2D = $SelectionRing
@onready var body_visual: Node2D = $BodyVisual
@onready var health_bar_root: Node2D = get_node_or_null("HealthBar") as Node2D
@onready var health_bar_fill: ColorRect = get_node_or_null("HealthBar/Fill") as ColorRect
@onready var gather_component: GatherComponent = get_node_or_null("GatherComponent") as GatherComponent
@onready var staff_component: StaffComponent = get_node_or_null("StaffComponent") as StaffComponent
@onready var cargo_visual: Node2D = get_node_or_null("BodyVisual/CargoVisual") as Node2D
@onready var gather_bar_root: Node2D = get_node_or_null("GatherBar") as Node2D
@onready var gather_bar_fill: ColorRect = get_node_or_null("GatherBar/Fill") as ColorRect

var is_selected: bool = false
var is_dead: bool = false
var is_staffed: bool = false
var current_hp: float = 100.0
var command_state: CommandState = CommandState.IDLE
var current_target: Node2D = null
var ability_component: AbilityComponent = null
var combat_component: CombatComponent = null

var _construction_target: Building = null
var _move_destination: Vector2 = Vector2.ZERO
var _attack_move_destination: Vector2 = Vector2.ZERO
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
	_apply_team_visuals()
	_update_health_bar()

	if nav_agent != null:
		nav_agent.max_speed = maxf(1.0, data.move_speed)
		nav_agent.radius = data.collision_radius + 2.0
		if not nav_agent.velocity_computed.is_connected(_on_nav_velocity_computed):
			nav_agent.velocity_computed.connect(_on_nav_velocity_computed)

	combat_component = get_node_or_null("CombatComponent") as CombatComponent
	if combat_component == null:
		combat_component = COMBAT_COMPONENT_SCRIPT.new()
		combat_component.name = "CombatComponent"
		add_child(combat_component)

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
		if not gather_component.gather_state_changed.is_connected(_on_gather_state_changed):
			gather_component.gather_state_changed.connect(_on_gather_state_changed)
	if cargo_visual != null:
		cargo_visual.visible = false
	if gather_bar_root != null:
		gather_bar_root.visible = false

	_register_with_economy()
	if data != null and data.auto_gather_on_spawn and can_gather():
		call_deferred("_try_start_auto_gather")


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
	if is_dead or is_staffed:
		return false
	var radius: float = data.selection_radius if data != null else 20.0
	return global_position.distance_squared_to(world_point) <= radius * radius


func issue_move_command(target_pos: Vector2) -> void:
	command_move(target_pos)


func get_unit_type_id() -> StringName:
	return data.unit_type_id if data != null else &"unit"


func get_vision_range() -> float:
	if data != null and data.vision_range > 0.0:
		return data.vision_range
	return 360.0


func is_ability_ready(ability: AbilityData) -> bool:
	return ability_component != null and ability_component.is_ability_ready(ability)


func get_ability_remaining_cooldown(ability_id: StringName) -> float:
	return ability_component.get_remaining_cooldown(ability_id) if ability_component != null else 0.0


func command_cast_ability(ability: AbilityData, target_pos: Vector2, target_unit: Unit = null) -> bool:
	if is_dead or is_staffed or ability_component == null or ability == null:
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
	return not is_dead and not is_staffed and data != null and data.can_gather and gather_component != null


func can_gather_resource(resource_type: StringName) -> bool:
	if not can_gather():
		return false
	if data.allowed_resource != &"" and data.allowed_resource != resource_type:
		return false
	return true


func can_construct() -> bool:
	if is_dead or is_staffed or data == null:
		return false
	for ability: AbilityData in data.abilities:
		if ability != null and ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
			return true
	return false


func can_staff_compute() -> bool:
	return not is_dead and not is_staffed and data != null and data.can_staff_compute and staff_component != null


func is_carrying_cargo() -> bool:
	return gather_component != null and gather_component.has_cargo()


func get_carried_amount() -> int:
	return gather_component.carried_amount if gather_component != null else 0


func get_carried_type() -> StringName:
	return gather_component.carried_type if gather_component != null else &""


func command_gather(resource_node: ResourceNode) -> bool:
	if is_dead or is_staffed or not can_gather() or not _can_move() or resource_node == null:
		return false
	_cancel_active_tasks(true)
	if not gather_component.start_gather(self, resource_node):
		return false
	command_state = CommandState.GATHERING
	current_target = null
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF
	status_changed.emit(self)
	return true


func command_return_cargo(building: Building = null) -> bool:
	if is_dead or is_staffed or not can_gather() or not _can_move() or not is_carrying_cargo():
		return false
	_cancel_active_tasks(true)
	if not gather_component.start_return_cargo(self, building):
		return false
	command_state = CommandState.GATHERING
	current_target = null
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF
	status_changed.emit(self)
	return true


func command_construct_building(building: Building) -> bool:
	if is_dead or is_staffed or not can_construct() or not _can_move():
		return false
	if building == null or not is_instance_valid(building) or building.is_destroyed or building.is_constructed or building.team != team:
		return false
	_cancel_active_tasks(false)
	_construction_target = building
	command_state = CommandState.CONSTRUCTING
	current_target = null
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF
	status_changed.emit(self)
	return true


func command_staff_building(building: Building) -> bool:
	if is_dead or is_staffed or not can_staff_compute() or not _can_move():
		return false
	if building == null or not is_instance_valid(building) or not building.can_accept_staff(self):
		return false
	_cancel_active_tasks(false)
	if not staff_component.start_staffing(self, building):
		return false
	command_state = CommandState.STAFFING_BUILDING
	current_target = null
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF
	status_changed.emit(self)
	return true


func enter_staffed_building(_building: Building) -> void:
	if is_staffed:
		return
	is_staffed = true
	_cancel_active_tasks(false)
	command_state = CommandState.IDLE
	current_target = null
	stop_component_navigation()
	set_selected(false)
	visible = false
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	if is_in_group("selectable_units"):
		remove_from_group("selectable_units")
	set_physics_process(false)
	staffed_state_changed.emit(self, true)


func exit_staffed_building(world_pos: Vector2) -> void:
	if not is_staffed:
		return
	is_staffed = false
	global_position = world_pos
	velocity = Vector2.ZERO
	command_state = CommandState.IDLE
	if staff_component != null:
		staff_component.staffed_building = null
	visible = true
	if collision_shape != null:
		collision_shape.set_deferred("disabled", false)
	if not is_in_group("selectable_units"):
		add_to_group("selectable_units")
	set_physics_process(true)
	staffed_state_changed.emit(self, false)


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
	status_changed.emit(self)


func command_move(target_pos: Vector2) -> void:
	if is_dead or is_staffed or not _can_move():
		return
	_cancel_active_tasks(false)
	command_state = CommandState.MOVING
	current_target = null
	_move_destination = target_pos
	_reset_progress_tracker()
	_set_nav_target(target_pos)


func command_attack_target(target: Node2D) -> void:
	if is_dead or is_staffed or not _can_attack():
		return
	if combat_component == null or not combat_component.is_valid_target(self, target):
		return
	_cancel_active_tasks(false)
	command_state = CommandState.ATTACKING_TARGET
	current_target = target
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF


func command_attack_move(target_pos: Vector2) -> void:
	if is_dead or is_staffed or not _can_move():
		return
	_cancel_active_tasks(false)
	command_state = CommandState.ATTACK_MOVING
	_attack_move_destination = target_pos
	_move_destination = target_pos
	current_target = null
	_reset_progress_tracker()
	_set_nav_target(target_pos)


func command_stop() -> void:
	if is_dead or is_staffed:
		return
	_cancel_active_tasks(false)
	command_state = CommandState.IDLE
	current_target = null
	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO
	_reset_progress_tracker()
	velocity = Vector2.ZERO
	_clear_nav_target()


func command_hold_position() -> void:
	if is_dead or is_staffed:
		return
	_cancel_active_tasks(false)
	command_state = CommandState.HOLD_POSITION
	current_target = null
	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO
	_reset_progress_tracker()
	velocity = Vector2.ZERO
	_clear_nav_target()


func take_damage(amount: float, attacker: Unit = null) -> void:
	if is_dead or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_hit_flash_timer = HIT_FLASH_DURATION
	if is_node_ready():
		body_visual.modulate = Color(2.2, 2.2, 2.2, 1.0)
	_update_health_bar()
	health_changed.emit(self, current_hp, data.max_hp)
	status_changed.emit(self)

	# Idle enemy combatants retaliate against attackers even if attacked from beyond aggro range.
	if team == Team.ENEMY and command_state == CommandState.IDLE and current_target == null and attacker != null and _can_attack():
		if combat_component != null and combat_component.is_valid_target(self, attacker):
			current_target = attacker

	if current_hp <= 0.0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_cancel_active_tasks(false)
	command_state = CommandState.IDLE
	current_target = null
	_wants_nav_movement = false
	velocity = Vector2.ZERO
	set_selected(false)
	_unregister_from_economy()
	died.emit(self)
	queue_free()


func _physics_process(delta: float) -> void:
	if is_dead or is_staffed:
		return

	_last_delta = delta
	if current_target != null and (combat_component == null or not combat_component.is_valid_target(self, current_target)):
		current_target = null

	if combat_component != null:
		combat_component.tick_cooldown(delta)
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
		CommandState.CONSTRUCTING:
			_process_constructing(delta)
		CommandState.STAFFING_BUILDING:
			_process_staffing_building(delta)

	if _can_move() and nav_agent != null and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(_desired_move_velocity)
		if not _wants_nav_movement:
			_apply_stationary_separation(delta)
	else:
		_apply_direct_motion(_desired_move_velocity, delta)


func _on_nav_velocity_computed(safe_velocity: Vector2) -> void:
	if is_dead or is_staffed or not _wants_nav_movement:
		return
	_apply_direct_motion(safe_velocity, _last_delta)


func _process_idle(delta: float) -> void:
	if not _can_attack() or combat_component == null:
		return

	# Active Enemy AI (GUARD): scan aggro_range, pursue into attack_range, and return fire.
	if team == Team.ENEMY and _can_move():
		var leash: float = maxf(data.aggro_range, data.attack_range) * 1.35
		if not combat_component.is_valid_target_in_range(self, current_target, leash):
			current_target = combat_component.find_nearest_enemy(self, data.aggro_range)
		if current_target != null:
			if combat_component.distance_to_target_edge(self, current_target) <= data.attack_range:
				_face_point(current_target.global_position, delta)
				combat_component.try_fire_at(self, current_target)
			else:
				_request_nav_toward_point(current_target.global_position, 8.0)
		return

	if not combat_component.is_valid_target_in_range(self, current_target, data.attack_range):
		current_target = combat_component.find_nearest_enemy(self, data.attack_range)
	if current_target != null:
		_face_point(current_target.global_position, delta)
		combat_component.try_fire_at(self, current_target)


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
		if data != null and data.auto_gather_on_spawn and can_gather():
			if is_carrying_cargo():
				if not command_return_cargo():
					_try_start_auto_gather()
			else:
				_try_start_auto_gather()
		return
	_compute_nav_desired_velocity()


func _process_attack_moving(delta: float) -> void:
	if _can_attack() and combat_component != null:
		var leash_range: float = maxf(data.aggro_range, data.attack_range) * 1.25
		if not combat_component.is_valid_target_in_range(self, current_target, leash_range):
			current_target = null
		if current_target == null:
			current_target = combat_component.find_nearest_enemy(self, data.aggro_range)

	if current_target != null and combat_component != null:
		_reset_progress_tracker()
		if combat_component.distance_to_target_edge(self, current_target) <= data.attack_range:
			_face_point(current_target.global_position, delta)
			combat_component.try_fire_at(self, current_target)
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
	if combat_component == null or not combat_component.is_valid_target(self, current_target):
		current_target = null
		command_state = CommandState.IDLE
		velocity = Vector2.ZERO
		return

	if combat_component.distance_to_target_edge(self, current_target) <= data.attack_range:
		_face_point(current_target.global_position, delta)
		combat_component.try_fire_at(self, current_target)
		return

	if _can_move():
		_request_nav_toward_point(current_target.global_position, 6.0)


func _process_hold_position(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _can_attack() or combat_component == null:
		return
	if not combat_component.is_valid_target_in_range(self, current_target, data.attack_range):
		current_target = combat_component.find_nearest_enemy(self, data.attack_range)
	if current_target != null:
		_face_point(current_target.global_position, delta)
		combat_component.try_fire_at(self, current_target)


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


func _process_constructing(delta: float) -> void:
	if _construction_target == null or not is_instance_valid(_construction_target) or _construction_target.is_destroyed or _construction_target.is_constructed:
		_construction_target = null
		command_state = CommandState.IDLE
		stop_component_navigation()
		if gather_bar_root != null:
			gather_bar_root.visible = false
		return

	var unit_r: float = data.collision_radius if data != null else 13.0
	var build_reach: float = _construction_target.footprint_radius + unit_r + 24.0
	var dist: float = global_position.distance_to(_construction_target.global_position)
	if dist <= build_reach:
		stop_component_navigation()
		face_world_point(_construction_target.global_position, delta)
		var completed: bool = _construction_target.advance_construction(delta)
		if gather_bar_root != null and gather_bar_fill != null:
			gather_bar_root.visible = not completed
			gather_bar_fill.size.x = GATHER_BAR_WIDTH * clampf(_construction_target.construction_progress, 0.0, 1.0)
		if completed:
			_construction_target = null
			command_state = CommandState.IDLE
		return

	var offset: Vector2 = global_position - _construction_target.global_position
	var dir: Vector2 = offset.normalized() if offset.length_squared() > 0.01 else Vector2.RIGHT
	var approach: Vector2 = _construction_target.global_position + dir * (_construction_target.footprint_radius * 0.75)
	request_component_navigation(approach, 12.0)


func _process_staffing_building(delta: float) -> void:
	if staff_component == null or not staff_component.is_active():
		command_state = CommandState.IDLE
		return
	staff_component.tick(self, delta)


func _cancel_active_tasks(keep_gather: bool) -> void:
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if not keep_gather and gather_component != null:
		gather_component.cancel()
	if staff_component != null:
		staff_component.cancel()
	if _construction_target != null:
		_construction_target = null
		if gather_bar_root != null:
			gather_bar_root.visible = false


func _try_start_auto_gather() -> void:
	if is_dead or is_staffed or not can_gather() or not is_inside_tree():
		return
	if command_state != CommandState.IDLE:
		return
	var target_type: StringName = data.allowed_resource if data.allowed_resource != &"" else &"silica"
	var best: ResourceNode = null
	var best_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var res_node: ResourceNode = node
		if res_node.is_depleted() or res_node.is_vent or res_node.resource_type != target_type:
			continue
		var d_sq: float = global_position.distance_squared_to(res_node.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = res_node
	if best != null:
		command_gather(best)


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
	var dir: Vector2 = _steer_around_static_units(to_next.normalized())
	_wants_nav_movement = true
	_desired_move_velocity = dir * data.move_speed


func _steer_around_static_units(move_dir: Vector2) -> Vector2:
	var steer: Vector2 = move_dir
	var my_r: float = data.collision_radius if data != null else 16.0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or node == self:
			continue
		var other: Unit = node
		if not is_instance_valid(other) or other.is_dead or other.is_staffed or other._can_move():
			continue
		var to_other: Vector2 = other.global_position - global_position
		var dist: float = to_other.length()
		var other_r: float = other.data.collision_radius if other.data != null else 18.0
		var avoid_dist: float = my_r + other_r + 36.0
		if dist <= 0.001 or dist > avoid_dist:
			continue
		var to_other_dir: Vector2 = to_other / dist
		if move_dir.dot(to_other_dir) <= 0.15:
			continue
		var side: float = -1.0 if move_dir.cross(to_other_dir) >= 0.0 else 1.0
		var tangent: Vector2 = Vector2(-to_other_dir.y, to_other_dir.x) * side
		var weight: float = clampf((avoid_dist - dist) / avoid_dist, 0.25, 1.0) * 1.4
		steer += tangent * weight
	return steer.normalized() if steer.length_squared() > 0.0001 else move_dir


func _apply_direct_motion(target_velocity: Vector2, delta: float) -> void:
	var accel: float = data.acceleration if data.acceleration > 0.0 else 1800.0
	if _wants_nav_movement:
		var combined: Vector2 = target_velocity + _compute_overlap_separation(1.0)
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
	if command_state == CommandState.CONSTRUCTING and _construction_target != null and is_instance_valid(_construction_target):
		var unit_r: float = data.collision_radius if data != null else 13.0
		if global_position.distance_to(_construction_target.global_position) <= _construction_target.footprint_radius + unit_r + 24.0:
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
		if not is_instance_valid(other) or other.is_dead or other.is_staffed:
			continue
		var other_r: float = other.data.collision_radius if other.data != null else 16.0
		var min_dist: float = my_r + other_r + extra_margin
		var diff: Vector2 = global_position - other.global_position
		var dist_sq: float = diff.length_squared()
		if dist_sq >= min_dist * min_dist:
			continue
		var dist: float = sqrt(dist_sq)
		var dir: Vector2 = Vector2.RIGHT.rotated(fmod(float(get_instance_id() % 360) * 1.618, TAU)) if dist < 0.01 else (diff / dist)
		var overlap_ratio: float = clampf((min_dist - dist) / maxf(1.0, min_dist), 0.15, 1.0)
		push += dir * max_push * overlap_ratio
	return push.normalized() * max_push if push.length() > max_push else push


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
		var collider: Object = get_slide_collision(i).get_collider()
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
	body_visual.rotation = lerp_angle(body_visual.rotation, target_angle, clampf(turn_speed * delta, 0.0, 1.0))


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
	return nav_agent != null and NavigationServer2D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0


func _can_move() -> bool:
	return nav_agent != null and data != null and data.move_speed > 0.0


func _can_attack() -> bool:
	return combat_component != null and combat_component.can_attack(self)


func _update_health_bar() -> void:
	if health_bar_root == null or health_bar_fill == null or data == null:
		return
	var max_val: float = maxf(1.0, data.max_hp)
	var ratio: float = clampf(current_hp / max_val, 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	health_bar_root.visible = always_show_health_bar or is_selected or ratio < 0.999


func _apply_team_visuals() -> void:
	if team != Team.ENEMY:
		return
	var type_id: StringName = get_unit_type_id()
	if type_id == &"enemy_trooper" or type_id == &"target_dummy":
		return
	if body_visual is Polygon2D:
		(body_visual as Polygon2D).color = Color(0.84, 0.28, 0.26, 1.0)
	var core_accent: Polygon2D = body_visual.get_node_or_null("CoreAccent") as Polygon2D if body_visual != null else null
	if core_accent != null:
		core_accent.color = Color(1.0, 0.68, 0.24, 1.0)
	if health_bar_fill != null:
		health_bar_fill.color = Color(0.98, 0.34, 0.26, 1.0)
	if selection_ring != null:
		var ring_fill: Polygon2D = selection_ring.get_node_or_null("Fill") as Polygon2D
		if ring_fill != null:
			ring_fill.color = Color(1.0, 0.30, 0.24, 0.16)
		var ring_outline: Line2D = selection_ring.get_node_or_null("Outline") as Line2D
		if ring_outline != null:
			ring_outline.default_color = Color(1.0, 0.36, 0.26, 0.95)


func _on_gather_cargo_changed(resource_type: StringName, amount: int) -> void:
	if cargo_visual != null:
		cargo_visual.visible = amount > 0
	cargo_changed.emit(self, resource_type, amount)
	status_changed.emit(self)


func _on_gather_progress_changed(progress: float, is_active: bool) -> void:
	if gather_bar_root == null or gather_bar_fill == null:
		return
	gather_bar_root.visible = is_active
	gather_bar_fill.size.x = GATHER_BAR_WIDTH * clampf(progress, 0.0, 1.0)


func _on_gather_state_changed(_new_state: GatherComponent.GatherState) -> void:
	status_changed.emit(self)


func get_inspection_data() -> Dictionary:
	var is_enemy: bool = (team == Team.ENEMY)
	var accent: Color = Color(1.0, 0.36, 0.26, 1.0) if is_enemy else Color(0.24, 0.92, 0.88, 1.0)
	var subtitle: String = "HOSTILE UNIT" if is_enemy else "FRIENDLY UNIT"

	if not is_enemy and data != null:
		if data.unit_type_id == &"scout_unit":
			accent = Color(0.98, 0.78, 0.24, 1.0)
			subtitle = "RECON UNIT"
		elif data.unit_type_id == &"silica_harvester":
			accent = Color(0.96, 0.68, 0.22, 1.0)
			subtitle = "AUTOMATED HARVESTER"
		elif data.can_staff_compute:
			accent = Color(0.32, 0.82, 1.0, 1.0)
			subtitle = "COMPUTE SPECIALIST"
		elif data.can_gather:
			accent = Color(0.28, 0.94, 0.56, 1.0)
			subtitle = "UTILITY WORKER"

	var max_hp_val: float = data.max_hp if data != null else 100.0
	var stats: Array[Dictionary] = []
	var show_primary: bool = false
	var primary_label: String = ""
	var primary_val: float = 0.0
	var primary_max: float = 1.0

	if data != null and data.can_gather:
		var res_label: String = String(data.allowed_resource).capitalize() if data.allowed_resource != &"" else "Resource"
		var carried: int = get_carried_amount()
		show_primary = true
		primary_label = "Cargo: %d / %d %s" % [carried, data.carry_capacity, res_label]
		primary_val = float(carried)
		primary_max = float(maxi(1, data.carry_capacity))
		stats.append({"label": "Cargo", "value": "%d / %d %s" % [carried, data.carry_capacity, res_label]})
		stats.append({"label": "Harvest", "value": "%.1fs Cycle" % data.gather_duration})
		stats.append({"label": "Speed", "value": "%d px/s" % int(round(data.move_speed))})
		stats.append({"label": "State", "value": _get_command_state_label()})
	elif data != null and data.can_staff_compute:
		stats.append({"label": "Role", "value": "Compute Staff"})
		stats.append({"label": "Output", "value": "+5 Compute / 3.0s"})
		stats.append({"label": "Speed", "value": "%d px/s" % int(round(data.move_speed))})
		stats.append({"label": "Bandwidth", "value": "%d BW" % data.bandwidth_cost})
	elif data != null:
		stats.append({"label": "Damage", "value": "%d" % int(round(data.attack_damage))})
		stats.append({"label": "Range", "value": "%d px" % int(round(data.attack_range))})
		stats.append({"label": "Speed", "value": "%d px/s" % int(round(data.move_speed))})
		if data.attack_damage > 0.0 and data.attack_cooldown > 0.0:
			stats.append({"label": "Fire Rate", "value": "%.1f /s" % (1.0 / data.attack_cooldown)})
		else:
			stats.append({"label": "Status", "value": "Stationary Target"})

	return {
		"title": data.display_name if data != null else name,
		"subtitle": subtitle,
		"affiliation": &"enemy" if is_enemy else &"player",
		"accent_color": accent,
		"ring_color": accent,
		"show_hp_bar": true,
		"hp_current": current_hp,
		"hp_max": max_hp_val,
		"show_primary_bar": show_primary,
		"primary_bar_label": primary_label,
		"primary_bar_value": primary_val,
		"primary_bar_max": primary_max,
		"primary_bar_color": accent,
		"stats": stats,
		"is_commandable": not is_enemy,
		"readonly_label": "HOSTILE UNIT  —  READ-ONLY TELEMETRY",
	}


func _get_command_state_label() -> String:
	match command_state:
		CommandState.IDLE:
			return "Idle"
		CommandState.MOVING:
			return "Moving"
		CommandState.ATTACK_MOVING:
			return "Attack-Moving"
		CommandState.ATTACKING_TARGET:
			return "Engaging"
		CommandState.HOLD_POSITION:
			return "Holding"
		CommandState.CASTING_ABILITY:
			return "Casting"
		CommandState.GATHERING:
			if gather_component != null:
				match gather_component.state:
					GatherComponent.GatherState.GATHER_MOVING_TO_NODE:
						return "To Resource"
					GatherComponent.GatherState.GATHERING:
						return "Harvesting"
					GatherComponent.GatherState.GATHER_RETURNING_TO_BASE:
						return "Returning Cargo"
			return "Gathering"
		CommandState.CONSTRUCTING:
			return "Constructing"
		CommandState.STAFFING_BUILDING:
			return "Entering Node"
	return "Active"


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
