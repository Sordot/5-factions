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
	PATROLLING,
}

enum Stance {
	AGGRESSIVE,
	HOLD_POSITION,
}

const CMD_EXEC_FAILED: int = 0
const CMD_EXEC_ACTIVE: int = 1
const CMD_EXEC_IMMEDIATE_DONE: int = 2

const ABILITY_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/ability_component.gd")
const COMBAT_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/combat_component.gd")
const HEAL_AURA_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/heal_aura_component.gd")
const ENTITY_VISUALS_SCRIPT: GDScript = preload("res://ui/overlays/entity_visuals.gd")
const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const AUTO_RETARGET_INTERVAL: float = 0.25
const VETERANCY_THRESHOLDS: Array = [0, 3, 6, 10]
const VETERANCY_NAMES: Array = ["Standard", "Veteran", "Elite", "Apex"]
const HIT_FLASH_DURATION: float = 0.08
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
signal command_queue_changed(unit: Unit)
signal stance_changed(unit: Unit, new_stance: Stance)

@export var team: Team = Team.PLAYER
@export var data: UnitData
@export var always_show_health_bar: bool = false
@export var stance: Stance = Stance.AGGRESSIVE

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
var kill_count: int = 0
var veterancy_rank: int = 0
var command_state: CommandState = CommandState.IDLE
var current_target: Node2D = null
var ability_component: AbilityComponent = null
var combat_component: CombatComponent = null
var command_queue: Array[Dictionary] = []
var active_command: Dictionary = {}
var patrol_waypoints: Array[Vector2] = []
var patrol_index: int = 0

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
var _stuck_sample_pos: Vector2 = Vector2.ZERO
var _stuck_sample_timer: float = 0.0
var _stuck_accum_time: float = 0.0
var _stuck_nudge_timer: float = 0.0
var _stuck_nudge_dir: Vector2 = Vector2.ZERO
var _stuck_side_sign: float = 1.0
var _stuck_consecutive_nudges: int = 0
var _cached_approach_point: Vector2 = Vector2.INF
var _cached_approach_target_pos: Vector2 = Vector2.INF
var _cached_approach_target_id: int = 0
var _adrenal_timer: float = 0.0
var _adrenal_speed_bonus: float = 0.0
var _adrenal_attack_speed_bonus: float = 0.0
var _slow_timer: float = 0.0
var _slow_move_penalty: float = 0.0
var _slow_attack_penalty: float = 0.0
var _entity_visuals: EntityVisuals = null
var _trail_points: Array[Vector2] = []
var _trail_sample_timer: float = 0.0
var _auto_retarget_timer: float = 0.0
var _vfx_anim_time: float = 0.0


func _ready() -> void:
	add_to_group("units")
	add_to_group("selectable_units")
	if data == null:
		data = UnitData.new()
	current_hp = data.max_hp
	selection_ring.visible = is_selected
	_setup_procedural_visuals()
	_apply_team_visuals()
	_update_health_bar()

	if data.ignore_friendly_unit_collision:
		# Colossus Stride: collide only with World terrain/buildings, walking cleanly over smaller units.
		collision_layer = 0
		collision_mask = 1
		z_index = maxi(z_index, 8)
	else:
		# Team-separated unit layers (Layer 2 = Player, Layer 3 = Enemy) so workers in transit can slide
		# past friendly teammates while still colliding with World (Layer 1) and hostile units.
		collision_layer = 2 if team == Team.PLAYER else 4
		collision_mask = 7

	if nav_agent != null:
		nav_agent.max_speed = maxf(1.0, get_effective_move_speed())
		nav_agent.radius = data.collision_radius + 2.0
		if data.ignore_friendly_unit_collision:
			nav_agent.avoidance_enabled = false
		if not nav_agent.velocity_computed.is_connected(_on_nav_velocity_computed):
			nav_agent.velocity_computed.connect(_on_nav_velocity_computed)

	combat_component = get_node_or_null("CombatComponent") as CombatComponent
	if combat_component == null:
		combat_component = COMBAT_COMPONENT_SCRIPT.new()
		combat_component.name = "CombatComponent"
		add_child(combat_component)

	if data.heal_aura_rate > 0.0 and get_node_or_null("HealAuraComponent") == null:
		var heal_aura: HealAuraComponent = HEAL_AURA_COMPONENT_SCRIPT.new()
		heal_aura.name = "HealAuraComponent"
		heal_aura.heal_per_second = data.heal_aura_rate
		heal_aura.aura_radius = data.heal_aura_radius
		add_child(heal_aura)

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
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	_stuck_sample_pos = global_position
	_stuck_side_sign = 1.0 if (get_instance_id() % 2) == 0 else -1.0
	if data != null and data.auto_gather_on_spawn and can_gather():
		call_deferred("_try_start_auto_gather")


func _exit_tree() -> void:
	if SettingsManager != null and SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.disconnect(_on_settings_changed)
	_unregister_from_economy()


func _on_settings_changed(category: StringName) -> void:
	if category == &"gameplay" or category == &"all":
		_update_health_bar()
		queue_redraw()


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	if is_node_ready():
		selection_ring.visible = is_selected
		_update_health_bar()
		queue_redraw()
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


func is_alive() -> bool:
	return not is_dead and not is_queued_for_deletion() and current_hp > 0.0


func get_max_hp() -> float:
	return data.max_hp if data != null else 100.0


func get_veterancy_rank_name() -> String:
	return String(VETERANCY_NAMES[clampi(veterancy_rank, 0, VETERANCY_NAMES.size() - 1)])


func register_kill(_victim: Node = null) -> void:
	if is_dead:
		return
	kill_count += 1
	var target_rank: int = 0
	for r: int in range(VETERANCY_THRESHOLDS.size() - 1, -1, -1):
		if kill_count >= int(VETERANCY_THRESHOLDS[r]):
			target_rank = r
			break
	if target_rank > veterancy_rank:
		veterancy_rank = target_rank
		if get_parent() != null and (team == Team.PLAYER or visible):
			var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
			fx.z_index = 56
			get_parent().add_child(fx)
			fx.call("setup_rank_up_pulse", global_position, veterancy_rank)
		if team == Team.PLAYER and AudioManager != null:
			AudioManager.play_sfx(&"veterancy_rank_up", -3.0, 0.03)
		queue_redraw()
	status_changed.emit(self)


func get_vision_range() -> float:
	if data != null and data.vision_range > 0.0:
		return data.vision_range
	return 360.0


func is_ability_ready(ability: AbilityData) -> bool:
	return ability_component != null and ability_component.is_ability_ready(ability)


func get_ability_remaining_cooldown(ability_id: StringName) -> float:
	return ability_component.get_remaining_cooldown(ability_id) if ability_component != null else 0.0


func command_cast_ability(ability: AbilityData, target_pos: Vector2, target_unit: Unit = null, append_to_queue: bool = false) -> bool:
	if is_dead or is_staffed or ability_component == null or ability == null:
		return false
	var cmd: Dictionary = {
		"type": &"cast_ability",
		"ability": ability,
		"pos": target_pos,
		"target": target_unit,
	}
	if append_to_queue:
		return issue_command(cmd, true)
	# Instant self-cast abilities trigger immediately without interrupting active movement or queues.
	if ability.target_type == AbilityData.TargetType.INSTANT:
		return ability_component.request_cast(self, ability, global_position, self)
	return issue_command(cmd, false)


func _start_cast_ability(ability: AbilityData, target_pos: Vector2, target_unit: Unit = null) -> int:
	if is_dead or is_staffed or ability_component == null or ability == null:
		return CMD_EXEC_FAILED
	if ability.target_type == AbilityData.TargetType.INSTANT:
		if ability_component.request_cast(self, ability, global_position, self):
			return CMD_EXEC_IMMEDIATE_DONE
		return CMD_EXEC_FAILED
	if ability.target_type == AbilityData.TargetType.UNIT_TARGET:
		if target_unit == null or not is_instance_valid(target_unit) or target_unit.is_dead or target_unit.is_queued_for_deletion():
			return CMD_EXEC_FAILED
	if not ability_component.is_ability_ready(ability):
		return CMD_EXEC_FAILED
	_cancel_active_tasks(false)
	var accepted: bool = ability_component.request_cast(self, ability, target_pos, target_unit)
	if not accepted:
		return CMD_EXEC_FAILED
	if ability_component.has_pending_cast():
		if not _can_move():
			ability_component.cancel_pending_cast()
			return CMD_EXEC_FAILED
		command_state = CommandState.CASTING_ABILITY
		current_target = null
		_reset_progress_tracker()
		_last_nav_target = Vector2.INF
		status_changed.emit(self)
		return CMD_EXEC_ACTIVE
	return CMD_EXEC_IMMEDIATE_DONE


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


func is_idle_worker() -> bool:
	if is_dead or is_staffed or is_queued_for_deletion() or not is_inside_tree() or data == null:
		return false
	if team != Team.PLAYER or current_hp <= 0.0:
		return false
	var uid: StringName = data.unit_type_id
	var is_worker_role: bool = (
		data.can_gather
		or data.can_staff_compute
		or uid == &"worker"
		or uid == &"silica_harvester"
		or uid == &"engineer"
	)
	if not is_worker_role:
		return false
	if command_state != CommandState.IDLE or not command_queue.is_empty() or not active_command.is_empty():
		return false
	if _construction_target != null:
		return false
	if gather_component != null and gather_component.is_active():
		return false
	if staff_component != null and staff_component.is_active():
		return false
	if ability_component != null and ability_component.has_pending_cast():
		return false
	return true


func has_queued_commands() -> bool:
	return not command_queue.is_empty()


func clear_command_queue() -> void:
	var had_items: bool = not command_queue.is_empty() or not active_command.is_empty()
	command_queue.clear()
	active_command.clear()
	if had_items:
		command_queue_changed.emit(self)


func issue_command(cmd: Dictionary, append_to_queue: bool = false) -> bool:
	if is_dead or is_staffed or cmd.is_empty():
		return false
	if append_to_queue:
		var is_idle_now: bool = (
			(command_state == CommandState.IDLE or command_state == CommandState.HOLD_POSITION)
			and active_command.is_empty()
			and command_queue.is_empty()
		)
		if not is_idle_now:
			command_queue.append(cmd.duplicate())
			command_queue_changed.emit(self)
			status_changed.emit(self)
			return true
	else:
		clear_command_queue()
	return _execute_command(cmd) != CMD_EXEC_FAILED


func advance_command_queue() -> bool:
	return _advance_command_queue()


func _advance_command_queue() -> bool:
	active_command.clear()
	while not command_queue.is_empty():
		var next_cmd: Dictionary = command_queue.pop_front()
		command_queue_changed.emit(self)
		var result: int = _execute_command(next_cmd)
		if result == CMD_EXEC_ACTIVE:
			return true
		if result == CMD_EXEC_IMMEDIATE_DONE:
			continue
	command_state = CommandState.HOLD_POSITION if stance == Stance.HOLD_POSITION else CommandState.IDLE
	velocity = Vector2.ZERO
	command_queue_changed.emit(self)
	status_changed.emit(self)
	return false


func _execute_command(cmd: Dictionary) -> int:
	var cmd_type: StringName = cmd.get("type", &"")
	var result: int = CMD_EXEC_FAILED
	match cmd_type:
		&"move":
			result = CMD_EXEC_ACTIVE if _start_move(cmd.get("pos", global_position) as Vector2) else CMD_EXEC_FAILED
		&"attack_move":
			result = CMD_EXEC_ACTIVE if _start_attack_move(cmd.get("pos", global_position) as Vector2) else CMD_EXEC_FAILED
		&"attack_target":
			var atk_t: Variant = cmd.get("target", null)
			if atk_t != null and is_instance_valid(atk_t) and atk_t is Node2D and not (atk_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if _start_attack_target(atk_t as Node2D) else CMD_EXEC_FAILED
		&"gather":
			var rn: Variant = cmd.get("target", null)
			if rn != null and is_instance_valid(rn) and rn is ResourceNode and not (rn as Node).is_queued_for_deletion() and not (rn as ResourceNode).is_depleted():
				result = CMD_EXEC_ACTIVE if _start_gather(rn as ResourceNode) else CMD_EXEC_FAILED
		&"return_cargo":
			var drop_b: Variant = cmd.get("target", null)
			var drop_building: Building = drop_b as Building if (drop_b != null and is_instance_valid(drop_b) and drop_b is Building and not (drop_b as Building).is_destroyed) else null
			result = CMD_EXEC_ACTIVE if _start_return_cargo(drop_building) else CMD_EXEC_FAILED
		&"build":
			var build_t: Variant = cmd.get("target", null)
			if build_t != null and is_instance_valid(build_t) and build_t is Building and not (build_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if _start_construct_building(build_t as Building) else CMD_EXEC_FAILED
		&"staff":
			var staff_t: Variant = cmd.get("target", null)
			if staff_t != null and is_instance_valid(staff_t) and staff_t is Building and not (staff_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if _start_staff_building(staff_t as Building) else CMD_EXEC_FAILED
		&"cast_ability":
			var ab: AbilityData = cmd.get("ability", null) as AbilityData
			var raw_t: Variant = cmd.get("target", null)
			var t_unit: Unit = raw_t as Unit if (raw_t != null and is_instance_valid(raw_t) and raw_t is Unit) else null
			result = _start_cast_ability(ab, cmd.get("pos", global_position) as Vector2, t_unit)
		&"patrol":
			result = CMD_EXEC_ACTIVE if _start_patrol(cmd.get("pos", global_position) as Vector2) else CMD_EXEC_FAILED
	if result == CMD_EXEC_ACTIVE:
		active_command = cmd.duplicate()
		command_queue_changed.emit(self)
	return result


func get_active_command_destination() -> Variant:
	match command_state:
		CommandState.MOVING:
			return _move_destination
		CommandState.ATTACK_MOVING:
			return _attack_move_destination
		CommandState.ATTACKING_TARGET:
			if current_target != null and is_instance_valid(current_target):
				return current_target.global_position
		CommandState.CASTING_ABILITY:
			if ability_component != null and ability_component.has_pending_cast():
				return ability_component.get_pending_destination()
		CommandState.CONSTRUCTING:
			if _construction_target != null and is_instance_valid(_construction_target):
				return _construction_target.global_position
		CommandState.GATHERING:
			if gather_component != null:
				if gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and is_instance_valid(gather_component.dropoff_building):
					return gather_component.dropoff_building.global_position
				if is_instance_valid(gather_component.target_node):
					return gather_component.target_node.global_position
		CommandState.STAFFING_BUILDING:
			if staff_component != null and is_instance_valid(staff_component.target_building):
				return staff_component.target_building.global_position
		CommandState.PATROLLING:
			if not patrol_waypoints.is_empty():
				return patrol_waypoints[clampi(patrol_index, 0, patrol_waypoints.size() - 1)]
	return null


func command_gather(resource_node: ResourceNode, append_to_queue: bool = false) -> bool:
	if resource_node == null or not is_instance_valid(resource_node):
		return false
	return issue_command({"type": &"gather", "target": resource_node, "pos": resource_node.global_position}, append_to_queue)


func _start_gather(resource_node: ResourceNode) -> bool:
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


func command_return_cargo(building: Building = null, append_to_queue: bool = false) -> bool:
	var dest: Vector2 = building.global_position if (building != null and is_instance_valid(building)) else global_position
	return issue_command({"type": &"return_cargo", "target": building, "pos": dest}, append_to_queue)


func _start_return_cargo(building: Building = null) -> bool:
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


func command_construct_building(building: Building, append_to_queue: bool = false) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	return issue_command({"type": &"build", "target": building, "pos": building.global_position}, append_to_queue)


func _start_construct_building(building: Building) -> bool:
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


func command_staff_building(building: Building, append_to_queue: bool = false) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	return issue_command({"type": &"staff", "target": building, "pos": building.global_position}, append_to_queue)


func _start_staff_building(building: Building) -> bool:
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
	clear_command_queue()
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
	command_queue_changed.emit(self)
	status_changed.emit(self)
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


func request_component_navigation(target_point: Vector2, repath_threshold: float = 10.0, stop_distance: float = 4.0) -> void:
	_request_nav_toward_point(target_point, repath_threshold, stop_distance)


func face_world_point(world_point: Vector2, delta: float) -> void:
	_face_point(world_point, delta)


func stop_component_navigation() -> void:
	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_reset_progress_tracker()
	clear_cached_approach_point()
	_clear_nav_target()


func reset_progress_tracker() -> void:
	_reset_progress_tracker()


func invalidate_nav_path() -> void:
	_last_nav_target = Vector2.INF
	clear_cached_approach_point()


func get_cached_approach_point() -> Vector2:
	return _cached_approach_point


func clear_cached_approach_point() -> void:
	_cached_approach_point = Vector2.INF
	_cached_approach_target_pos = Vector2.INF
	_cached_approach_target_id = 0


func get_or_compute_approach_point(
	target_node: Node2D,
	target_radius: float,
	margin: float = 8.0,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null
) -> Vector2:
	if target_node == null or not is_instance_valid(target_node):
		clear_cached_approach_point()
		return global_position
	var unit_r: float = data.collision_radius if data != null else 13.0
	var bounds: Rect2 = _get_arena_bounds()
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(unit_r + 6.0, unit_r + 6.0),
		bounds.size - Vector2((unit_r + 6.0) * 2.0, (unit_r + 6.0) * 2.0)
	)
	var target_id: int = target_node.get_instance_id()
	var can_reuse: bool = (
		_cached_approach_point != Vector2.INF
		and _cached_approach_target_id == target_id
		and _cached_approach_target_pos.distance_squared_to(target_node.global_position) <= 16.0
		and _last_nav_target != Vector2.INF
		and _is_point_clear_of_obstacles(_cached_approach_point, unit_r + 2.0, safe_bounds, ignore_building, ignore_resource)
	)
	if can_reuse:
		return _cached_approach_point

	var computed: Vector2 = find_clear_approach_point(
		target_node.global_position,
		target_radius,
		margin,
		ignore_building,
		ignore_resource,
		true
	)
	_cached_approach_point = computed
	_cached_approach_target_pos = target_node.global_position
	_cached_approach_target_id = target_id
	return computed


func find_clear_approach_point(
	target_center: Vector2,
	target_radius: float,
	margin: float = 8.0,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null,
	avoid_friendly_workers: bool = true
) -> Vector2:
	var unit_r: float = data.collision_radius if data != null else 13.0
	var stand_dist: float = target_radius + unit_r + margin
	var offset: Vector2 = global_position - target_center
	var base_angle: float = offset.angle() if offset.length_squared() > 0.01 else 0.0
	# Subtle per-unit deterministic angular bias spreads simultaneous multi-worker clicks cleanly.
	var slot_bias: float = float((get_instance_id() % 5) - 2) * 0.14 if avoid_friendly_workers else 0.0
	var bounds: Rect2 = _get_arena_bounds()
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(unit_r + 6.0, unit_r + 6.0),
		bounds.size - Vector2((unit_r + 6.0) * 2.0, (unit_r + 6.0) * 2.0)
	)

	var busy_slots: Array[Vector2] = []
	if avoid_friendly_workers and is_inside_tree():
		var nearby_r_sq: float = (stand_dist + 84.0) * (stand_dist + 84.0)
		for node: Node in get_tree().get_nodes_in_group("units"):
			if not (node is Unit) or not is_instance_valid(node) or node == self:
				continue
			var other: Unit = node
			if other.is_dead or other.is_staffed or other.team != team:
				continue
			if other.data == null or not (other.data.can_gather or other.data.can_staff_compute or other.can_construct()):
				continue
			var other_working_or_approaching: bool = (
				other.command_state == CommandState.GATHERING
				or other.command_state == CommandState.CONSTRUCTING
				or other.command_state == CommandState.STAFFING_BUILDING
			)
			if not other_working_or_approaching:
				continue
			if other.global_position.distance_squared_to(target_center) <= nearby_r_sq:
				busy_slots.append(other.global_position)
			var other_cached: Vector2 = other.get_cached_approach_point()
			if other_cached != Vector2.INF and other_cached.distance_squared_to(target_center) <= nearby_r_sq:
				busy_slots.append(other_cached)

	var slot_clear_dist: float = unit_r * 1.85
	var slot_clear_sq: float = slot_clear_dist * slot_clear_dist
	var best_fallback: Vector2 = Vector2.INF
	var best_fallback_clearance: float = -1.0

	var steps: int = 16
	var step_angle: float = TAU / float(steps)
	for i: int in range(steps):
		var ring_offset: int = 0 if i == 0 else ((i + 1) >> 1)
		var sign_mult: float = 1.0 if (i % 2) == 1 else -1.0
		var ang: float = base_angle + slot_bias + float(ring_offset) * step_angle * sign_mult
		var cand: Vector2 = target_center + Vector2.RIGHT.rotated(ang) * stand_dist
		if not _is_point_clear_of_obstacles(cand, unit_r + 3.0, safe_bounds, ignore_building, ignore_resource):
			continue
		if busy_slots.is_empty():
			return cand
		var min_slot_sq: float = INF
		for occ: Vector2 in busy_slots:
			min_slot_sq = minf(min_slot_sq, cand.distance_squared_to(occ))
		if min_slot_sq >= slot_clear_sq:
			return cand
		if min_slot_sq > best_fallback_clearance:
			best_fallback_clearance = min_slot_sq
			best_fallback = cand

	if best_fallback != Vector2.INF:
		return best_fallback

	var fallback: Vector2 = target_center + Vector2.RIGHT.rotated(base_angle) * stand_dist
	if safe_bounds.has_area():
		fallback.x = clampf(fallback.x, safe_bounds.position.x, safe_bounds.end.x)
		fallback.y = clampf(fallback.y, safe_bounds.position.y, safe_bounds.end.y)
	return fallback


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0 or data == null:
		return
	var max_hp_val: float = get_max_hp()
	var next_hp: float = minf(max_hp_val, current_hp + amount)
	if is_equal_approx(next_hp, current_hp):
		return
	current_hp = next_hp
	_update_health_bar()
	health_changed.emit(self, current_hp, max_hp_val)
	status_changed.emit(self)


func command_move(target_pos: Vector2, append_to_queue: bool = false) -> void:
	issue_command({"type": &"move", "pos": target_pos}, append_to_queue)


func _start_move(target_pos: Vector2) -> bool:
	if is_dead or is_staffed or not _can_move():
		return false
	if combat_component != null:
		combat_component.cancel_attack_animation()
	_cancel_active_tasks(false)
	command_state = CommandState.MOVING
	current_target = null
	_move_destination = target_pos
	_reset_progress_tracker()
	_set_nav_target(target_pos)
	status_changed.emit(self)
	return true


func command_attack_target(target: Node2D, append_to_queue: bool = false) -> void:
	if target == null or not is_instance_valid(target):
		return
	issue_command({"type": &"attack_target", "target": target, "pos": target.global_position}, append_to_queue)


func _start_attack_target(target: Node2D) -> bool:
	if is_dead or is_staffed or not _can_attack():
		return false
	if combat_component == null or not combat_component.is_valid_target(self, target):
		return false
	if stance != Stance.AGGRESSIVE:
		stance = Stance.AGGRESSIVE
		stance_changed.emit(self, stance)
	_cancel_active_tasks(false)
	command_state = CommandState.ATTACKING_TARGET
	current_target = target
	_reset_progress_tracker()
	_last_nav_target = Vector2.INF
	status_changed.emit(self)
	return true


func command_attack_move(target_pos: Vector2, append_to_queue: bool = false) -> void:
	issue_command({"type": &"attack_move", "pos": target_pos}, append_to_queue)


func command_patrol(target_pos: Vector2, append_to_queue: bool = false) -> void:
	if is_dead or is_staffed or not _can_move():
		return
	if append_to_queue and command_state == CommandState.PATROLLING and command_queue.is_empty() and not patrol_waypoints.is_empty():
		patrol_waypoints.append(target_pos)
		command_queue_changed.emit(self)
		status_changed.emit(self)
		return
	issue_command({"type": &"patrol", "pos": target_pos}, append_to_queue)


func _start_patrol(first_target: Vector2) -> bool:
	if is_dead or is_staffed or not _can_move():
		return false
	if stance != Stance.AGGRESSIVE:
		stance = Stance.AGGRESSIVE
		stance_changed.emit(self, stance)
	_cancel_active_tasks(false)
	patrol_waypoints = [global_position, first_target]
	while not command_queue.is_empty() and command_queue[0].get("type", &"") == &"patrol":
		var extra: Dictionary = command_queue.pop_front()
		var extra_pos: Vector2 = extra.get("pos", first_target) as Vector2
		if patrol_waypoints[patrol_waypoints.size() - 1].distance_squared_to(extra_pos) > 16.0:
			patrol_waypoints.append(extra_pos)
	patrol_index = 1
	command_state = CommandState.PATROLLING
	current_target = null
	_reset_progress_tracker()
	_set_nav_target(patrol_waypoints[patrol_index])
	command_queue_changed.emit(self)
	status_changed.emit(self)
	return true


func _start_attack_move(target_pos: Vector2) -> bool:
	if is_dead or is_staffed or not _can_move():
		return false
	if stance != Stance.AGGRESSIVE:
		stance = Stance.AGGRESSIVE
		stance_changed.emit(self, stance)
	_cancel_active_tasks(false)
	command_state = CommandState.ATTACK_MOVING
	_attack_move_destination = target_pos
	_move_destination = target_pos
	current_target = null
	_auto_retarget_timer = 0.0
	_reset_progress_tracker()
	if _can_attack() and combat_component != null:
		# Instant target scan on A-click so rapid stutter-step kiting fires without scan lag
		var immediate_target: Node2D = combat_component.force_immediate_target_scan(self, data.aggro_range)
		if immediate_target != null and is_instance_valid(immediate_target):
			current_target = immediate_target
			if combat_component.is_within_attack_envelope(self, current_target):
				_face_point(current_target.global_position, _last_delta)
				combat_component.process_attack_at(self, current_target, 0.0)
	if current_target == null:
		_set_nav_target(target_pos)
	status_changed.emit(self)
	return true


func set_stance(new_stance: Stance) -> void:
	if is_dead or is_staffed:
		return
	var changed: bool = (stance != new_stance)
	stance = new_stance
	if stance == Stance.HOLD_POSITION:
		clear_command_queue()
		_cancel_active_tasks(false)
		command_state = CommandState.HOLD_POSITION
		current_target = null
		_wants_nav_movement = false
		_desired_move_velocity = Vector2.ZERO
		_reset_progress_tracker()
		velocity = Vector2.ZERO
		_clear_nav_target()
	elif command_state == CommandState.HOLD_POSITION:
		command_state = CommandState.IDLE
		current_target = null
	if changed:
		stance_changed.emit(self, stance)
	status_changed.emit(self)


func command_stop() -> void:
	if is_dead or is_staffed:
		return
	if combat_component != null:
		combat_component.cancel_attack_animation()
	clear_command_queue()
	_cancel_active_tasks(false)
	command_state = CommandState.HOLD_POSITION if stance == Stance.HOLD_POSITION else CommandState.IDLE
	current_target = null
	_wants_nav_movement = false
	_desired_move_velocity = Vector2.ZERO
	_reset_progress_tracker()
	velocity = Vector2.ZERO
	_clear_nav_target()
	status_changed.emit(self)


func command_hold_position() -> void:
	set_stance(Stance.HOLD_POSITION)


func take_damage(amount: float, attacker: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	var mitigation: float = get_effective_damage_reduction()
	var effective_damage: float = amount * (1.0 - mitigation)
	if effective_damage <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - effective_damage)
	_hit_flash_timer = HIT_FLASH_DURATION
	if is_node_ready():
		body_visual.modulate = Color(1.95, 2.25, 2.35, 1.0)
	_update_health_bar()
	if team == Team.PLAYER and is_inside_tree():
		var mm: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if mm != null:
			var unit_label: String = data.display_name if data != null else "Unit"
			mm.push_tactical_alert(global_position, &"under_attack", "%s Under Attack!" % unit_label)
	health_changed.emit(self, current_hp, get_max_hp())
	status_changed.emit(self)

	# Idle aggressive combatants retaliate against attackers even if attacked from beyond aggro range (when Aggro AI is ON).
	if MatchManager.is_aggro_ai_enabled(get_tree()) and command_state == CommandState.IDLE and (current_target == null or not is_instance_valid(current_target)) and attacker != null and is_instance_valid(attacker) and attacker is Unit and _can_attack():
		if combat_component != null and combat_component.should_pursue_targets(self) and combat_component.is_valid_target(self, attacker):
			current_target = attacker as Node2D

	if current_hp <= 0.0:
		if attacker != null and is_instance_valid(attacker) and attacker is Unit:
			var killer: Unit = attacker as Unit
			if not killer.is_dead and killer.team != team:
				killer.register_kill(self)
		_die()


func apply_adrenal_surge(duration: float, speed_bonus: float, attack_speed_bonus: float) -> void:
	if is_dead or duration <= 0.0:
		return
	_adrenal_timer = maxf(_adrenal_timer, duration)
	_adrenal_speed_bonus = maxf(_adrenal_speed_bonus, speed_bonus)
	_adrenal_attack_speed_bonus = maxf(_adrenal_attack_speed_bonus, attack_speed_bonus)
	_sync_nav_max_speed()
	queue_redraw()
	status_changed.emit(self)


func apply_slow_debuff(duration: float, move_penalty: float, attack_penalty: float) -> void:
	if is_dead or duration <= 0.0:
		return
	_slow_timer = maxf(_slow_timer, duration)
	_slow_move_penalty = clampf(maxf(_slow_move_penalty, move_penalty), 0.0, 0.75)
	_slow_attack_penalty = clampf(maxf(_slow_attack_penalty, attack_penalty), 0.0, 0.75)
	_sync_nav_max_speed()
	queue_redraw()
	status_changed.emit(self)


func on_team_upgrade_completed(_upgrade_id: StringName) -> void:
	_sync_nav_max_speed()
	if _entity_visuals != null:
		_entity_visuals.queue_redraw()
	queue_redraw()
	status_changed.emit(self)


func get_effective_move_speed() -> float:
	if data == null or data.move_speed <= 0.0:
		return 0.0
	var spd: float = data.move_speed
	if data.unit_type_id == &"goliath_frame":
		var econ: EconomyManager = _get_economy_manager()
		if econ != null:
			spd *= econ.get_goliath_speed_multiplier(team)
	if _adrenal_timer > 0.0:
		spd *= (1.0 + _adrenal_speed_bonus)
	if _slow_timer > 0.0:
		spd *= maxf(0.25, 1.0 - _slow_move_penalty)
	return spd


func get_effective_attack_cooldown() -> float:
	if data == null or data.attack_cooldown <= 0.0:
		return 1.0
	var rate_mult: float = 1.0
	if _adrenal_timer > 0.0:
		rate_mult *= (1.0 + _adrenal_attack_speed_bonus)
	if _slow_timer > 0.0:
		rate_mult *= maxf(0.35, 1.0 - _slow_attack_penalty)
	return data.attack_cooldown / maxf(0.25, rate_mult)


func get_effective_damage_reduction() -> float:
	if data == null:
		return 0.0
	var dr: float = maxf(0.0, data.damage_reduction)
	if data.unit_type_id == &"goliath_frame":
		var econ: EconomyManager = _get_economy_manager()
		if econ != null:
			dr += econ.get_goliath_extra_damage_reduction(team)
	return clampf(dr, 0.0, 0.75)


func _sync_nav_max_speed() -> void:
	if nav_agent != null and data != null:
		nav_agent.max_speed = maxf(1.0, get_effective_move_speed())


func _get_economy_manager() -> EconomyManager:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func _should_draw_attack_range() -> bool:
	if not is_selected or not _can_attack() or data == null:
		return false
	var mode: int = SettingsManager.attack_range_mode if SettingsManager != null else 1
	if mode == 2:
		return false
	if mode == 0:
		return true
	if is_inside_tree():
		var sel: Node = get_tree().get_first_node_in_group("selection_controller")
		if sel != null and sel.has_method("is_targeting_command_active"):
			return bool(sel.call("is_targeting_command_active"))
	return false


func _draw() -> void:
	var type_id: StringName = get_unit_type_id()
	# Selected unit attack-range & min-range tactical previews (gated by Settings -> Gameplay -> Attack Range Indicator)
	if _should_draw_attack_range():
		var atk_r: float = data.attack_range + data.collision_radius
		var is_siege: bool = data.min_attack_range > 0.0 or data.aoe_attack_radius > 0.0
		var range_col: Color = (Color(0.46, 1.0, 0.56, 0.34) if is_siege else Color(0.32, 0.94, 0.96, 0.24)) if team == Team.PLAYER else Color(1.0, 0.38, 0.28, 0.26)
		_draw_dashed_ring(Vector2.ZERO, atk_r, range_col, 1.5 if is_siege else 1.2, 40 if atk_r > 220.0 else 28)
		if data.min_attack_range > 0.0:
			var min_r: float = data.min_attack_range + data.collision_radius
			draw_circle(Vector2.ZERO, min_r, Color(1.0, 0.28, 0.24, 0.05))
			_draw_dashed_ring(Vector2.ZERO, min_r, Color(1.0, 0.36, 0.28, 0.44), 1.4, 20)

	# Elevated ground shadow for Arc-Lancer Colossus Stride readability
	if type_id == &"arc_lancer":
		draw_circle(Vector2(5.0, 11.0), 17.5, Color(0.02, 0.04, 0.06, 0.42))
		draw_arc(Vector2(5.0, 11.0), 17.5, 0.0, TAU, 24, Color(0.28, 0.92, 1.0, 0.22) if team == Team.PLAYER else Color(1.0, 0.36, 0.26, 0.22), 1.2, true)

	# Speed-dart motion trail for Stingers
	if type_id == &"stinger" and _trail_points.size() >= 2:
		var trail_base: Color = Color(0.98, 0.80, 0.24, 1.0) if team == Team.PLAYER else Color(1.0, 0.46, 0.24, 1.0)
		for i: int in range(1, _trail_points.size()):
			var t: float = float(i) / float(_trail_points.size())
			var p0: Vector2 = to_local(_trail_points[i - 1])
			var p1: Vector2 = to_local(_trail_points[i])
			draw_line(p0, p1, Color(trail_base.r, trail_base.g, trail_base.b, t * 0.45), 1.4 + t * 2.2, true)

	var r: float = (data.collision_radius + 6.0) if data != null else 22.0
	if _adrenal_timer > 0.0:
		# Pulsing emerald/gold rim + upward chevron pip
		var pulse: float = 0.5 + 0.5 * sin(_vfx_anim_time * 10.0)
		var rim_col: Color = Color(0.28, 1.0, 0.72, 0.88).lerp(Color(1.0, 0.88, 0.34, 0.96), pulse * 0.55)
		draw_arc(Vector2.ZERO, r + pulse * 1.8, 0.0, TAU, 24, rim_col, 2.4, true)
		draw_circle(Vector2.ZERO, r * 0.75, Color(0.24, 0.98, 0.78, 0.12 + pulse * 0.08))
		var chev_y: float = -(r + 6.0 + pulse * 2.5)
		var chev: PackedVector2Array = PackedVector2Array([
			Vector2(-4.5, chev_y + 3.0),
			Vector2(0.0, chev_y - 2.0),
			Vector2(4.5, chev_y + 3.0),
		])
		draw_polyline(chev, Color(0.98, 0.94, 0.42, 0.95), 2.0, true)
	if _slow_timer > 0.0:
		# Flickering violet/cyan static disruption interference arcs
		var spin: float = _vfx_anim_time * 4.5
		var flicker: float = 0.65 + 0.35 * sin(_vfx_anim_time * 24.0)
		draw_circle(Vector2.ZERO, r * 0.82, Color(0.56, 0.34, 1.0, 0.14))
		for k: int in range(3):
			var a0: float = spin + float(k) * (TAU / 3.0)
			var arc_col: Color = Color(0.72, 0.42, 1.0, 0.92 * flicker) if (k % 2 == 0) else Color(0.36, 0.92, 1.0, 0.86 * flicker)
			draw_arc(Vector2.ZERO, r + 3.0, a0, a0 + 1.15, 10, arc_col, 2.3, true)
			var crack_dir: Vector2 = Vector2.RIGHT.rotated(a0 + 0.55)
			draw_line(crack_dir * (r - 1.0), crack_dir * (r + 6.5), arc_col, 1.4, true)

	# Diegetic Veterancy rank chevron pips beside unit's health bar
	if veterancy_rank > 0:
		var base_y: float = health_bar_root.position.y + 1.0 if health_bar_root != null else -(r + 8.0)
		var base_x: float = -(HEALTH_BAR_WIDTH * 0.5 + 8.0)
		var pip_col: Color = Color(1.0, 0.86, 0.28, 1.0) if veterancy_rank >= 3 else Color(0.76, 0.96, 1.0, 0.96)
		var badge_h: float = 4.0 + float(veterancy_rank) * 3.8
		draw_rect(Rect2(base_x - 5.0, base_y - badge_h * 0.5 - 1.5, 10.0, badge_h + 3.0), Color(0.03, 0.06, 0.10, 0.80), true)
		for i: int in range(veterancy_rank):
			var cy: float = base_y + (float(veterancy_rank - 1) * 0.5 - float(i)) * 3.6
			var chev_pts: PackedVector2Array = PackedVector2Array([
				Vector2(base_x - 3.2, cy + 1.5),
				Vector2(base_x, cy - 1.7),
				Vector2(base_x + 3.2, cy + 1.5),
			])
			draw_polyline(chev_pts, pip_col, 1.6, true)


func _draw_dashed_ring(center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(8, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.54
		draw_arc(center, radius, a0, a1, 4, col, width, true)


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	clear_command_queue()
	_cancel_active_tasks(false)
	command_state = CommandState.IDLE
	current_target = null
	_wants_nav_movement = false
	velocity = Vector2.ZERO
	set_selected(false)
	_unregister_from_economy()
	if get_parent() != null and (team == Team.PLAYER or visible):
		var uid: StringName = get_unit_type_id()
		var is_heavy: bool = (uid == &"goliath_frame" or uid == &"arc_lancer" or uid == &"chrysalis_mortar")
		var burst_r: float = (data.collision_radius * 1.15) if data != null else 18.0
		var burst_col: Color = Color(0.34, 0.98, 0.88, 1.0) if team == Team.PLAYER else Color(1.0, 0.42, 0.28, 1.0)
		if uid == &"chrysalis_mortar" and team == Team.PLAYER:
			burst_col = Color(0.46, 1.0, 0.56, 1.0)
		elif uid == &"lance_rig" and team == Team.PLAYER:
			burst_col = Color(1.0, 0.80, 0.34, 1.0)
		var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
		fx.z_index = 53
		get_parent().add_child(fx)
		fx.call("setup_death_burst", global_position, burst_r, burst_col, is_heavy)
	if AudioManager != null and (team == Team.PLAYER or visible):
		AudioManager.play_sfx(&"entity_destroyed", -6.0, 0.08)
	died.emit(self)
	queue_free()


func _physics_process(delta: float) -> void:
	if is_dead or is_staffed:
		return

	_last_delta = delta
	if current_target != null and (not is_instance_valid(current_target) or combat_component == null or not combat_component.is_valid_target(self, current_target)):
		current_target = null

	if combat_component != null:
		combat_component.tick_cooldown(delta)
	if ability_component != null:
		ability_component.tick_cooldowns(delta)
	_tick_status_effects(delta)

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _hit_flash_timer <= 0.0:
			body_visual.modulate = Color.WHITE

	if get_unit_type_id() == &"stinger":
		_update_stinger_trail(delta)

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
		CommandState.PATROLLING:
			_process_patrolling(delta)

	_update_worker_collision_passing()
	_apply_anti_stuck_steering(delta)

	if _can_move() and nav_agent != null and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(_desired_move_velocity)
		if not _wants_nav_movement:
			_apply_stationary_separation(delta)
	else:
		_apply_direct_motion(_desired_move_velocity, delta)


func _on_nav_velocity_computed(safe_velocity: Vector2) -> void:
	if is_dead or is_staffed or not _wants_nav_movement:
		return
	if nav_agent != null and not nav_agent.avoidance_enabled:
		return
	_apply_direct_motion(safe_velocity, _last_delta)


func _tick_status_effects(delta: float) -> void:
	var changed: bool = false
	var any_active: bool = _adrenal_timer > 0.0 or _slow_timer > 0.0
	if _adrenal_timer > 0.0:
		_adrenal_timer = maxf(0.0, _adrenal_timer - delta)
		if _adrenal_timer <= 0.0:
			_adrenal_speed_bonus = 0.0
			_adrenal_attack_speed_bonus = 0.0
			changed = true
	if _slow_timer > 0.0:
		_slow_timer = maxf(0.0, _slow_timer - delta)
		if _slow_timer <= 0.0:
			_slow_move_penalty = 0.0
			_slow_attack_penalty = 0.0
			changed = true
	if any_active:
		_vfx_anim_time += delta
		queue_redraw()
	if changed:
		_sync_nav_max_speed()
		queue_redraw()
		status_changed.emit(self)


func _maybe_retarget_higher_threat(delta: float, scan_range: float) -> void:
	if combat_component == null or current_target == null or not is_instance_valid(current_target):
		_auto_retarget_timer = 0.0
		return
	_auto_retarget_timer -= delta
	if _auto_retarget_timer > 0.0:
		return
	_auto_retarget_timer = AUTO_RETARGET_INTERVAL
	var better: Node2D = combat_component.find_higher_priority_threat(self, current_target, scan_range)
	if better != null and is_instance_valid(better) and better != current_target:
		current_target = better


func _process_idle(delta: float) -> void:
	if stance == Stance.HOLD_POSITION:
		_process_hold_position(delta)
		return
	if not _can_attack() or combat_component == null:
		return

	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	# When Aggro AI is toggled OFF, idle/guard units do not passively acquire or chase targets.
	if not MatchManager.is_aggro_ai_enabled(get_tree()):
		current_target = null
		return

	# Aggressive combat units acquire enemies inside aggro_range and pursue within leash range.
	if combat_component.should_pursue_targets(self) and _can_move():
		var leash: float = maxf(data.aggro_range, data.attack_range) * 1.35
		if current_target == null or not combat_component.is_valid_target_in_range(self, current_target, leash):
			current_target = combat_component.find_nearest_enemy(self, data.aggro_range)
		else:
			_maybe_retarget_higher_threat(delta, data.attack_range)
		if current_target != null and is_instance_valid(current_target):
			if combat_component.is_within_attack_envelope(self, current_target):
				_face_point(current_target.global_position, delta)
				combat_component.process_attack_at(self, current_target, delta)
			elif combat_component.is_target_inside_min_range(self, current_target):
				combat_component.cancel_attack_animation()
				current_target = combat_component.find_nearest_enemy(self, data.aggro_range)
			else:
				combat_component.cancel_attack_animation()
				_request_nav_toward_point(current_target.global_position, 8.0)
		return

	if current_target == null or not combat_component.is_within_attack_envelope(self, current_target):
		current_target = combat_component.find_nearest_enemy(self, data.attack_range)
	else:
		_maybe_retarget_higher_threat(delta, data.attack_range)
	if current_target != null and is_instance_valid(current_target):
		_face_point(current_target.global_position, delta)
		combat_component.process_attack_at(self, current_target, delta)


func _process_moving(delta: float) -> void:
	if nav_agent == null:
		_advance_command_queue()
		return
	if not _is_nav_map_ready():
		return
	if _should_settle_at_destination(_move_destination, delta):
		_reset_progress_tracker()
		if _advance_command_queue():
			return
		if data != null and data.auto_gather_on_spawn and can_gather():
			if is_carrying_cargo():
				if not command_return_cargo():
					_try_start_auto_gather()
			else:
				_try_start_auto_gather()
		return
	_compute_nav_desired_velocity()


func _process_attack_moving(delta: float) -> void:
	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	if _can_attack() and combat_component != null:
		var leash_range: float = maxf(data.aggro_range, data.attack_range) * 1.25
		if current_target != null and not combat_component.is_valid_target_in_range(self, current_target, leash_range):
			current_target = null
		if current_target == null:
			current_target = combat_component.find_nearest_enemy(self, data.aggro_range)
		else:
			_maybe_retarget_higher_threat(delta, data.attack_range)

	if current_target != null and is_instance_valid(current_target) and combat_component != null:
		_reset_progress_tracker()
		if combat_component.is_within_attack_envelope(self, current_target):
			_face_point(current_target.global_position, delta)
			combat_component.process_attack_at(self, current_target, delta)
			return
		combat_component.cancel_attack_animation()
		if combat_component.is_target_inside_min_range(self, current_target):
			current_target = null
		else:
			_request_nav_toward_point(current_target.global_position, 8.0)
			return

	if nav_agent == null:
		_advance_command_queue()
		return
	if _last_nav_target == Vector2.INF or _last_nav_target.distance_squared_to(_attack_move_destination) > 1.0:
		_set_nav_target(_attack_move_destination)
	if not _is_nav_map_ready():
		return
	if _should_settle_at_destination(_attack_move_destination, delta):
		_reset_progress_tracker()
		_advance_command_queue()
		return
	_compute_nav_desired_velocity()


func _process_attacking_target(delta: float) -> void:
	if current_target == null or not is_instance_valid(current_target) or combat_component == null or not combat_component.is_valid_target(self, current_target):
		if combat_component != null:
			combat_component.cancel_attack_animation()
		current_target = null
		_advance_command_queue()
		return

	if combat_component.is_within_attack_envelope(self, current_target):
		_face_point(current_target.global_position, delta)
		combat_component.process_attack_at(self, current_target, delta)
		return

	combat_component.cancel_attack_animation()
	if combat_component.is_target_inside_min_range(self, current_target):
		_face_point(current_target.global_position, delta)
		velocity = Vector2.ZERO
		return

	if _can_move():
		_request_nav_toward_point(current_target.global_position, 6.0)


func _process_hold_position(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _can_attack() or combat_component == null:
		return
	if current_target != null and not is_instance_valid(current_target):
		current_target = null
	if current_target == null or not combat_component.is_within_attack_envelope(self, current_target):
		current_target = combat_component.find_nearest_enemy(self, data.attack_range)
	else:
		_maybe_retarget_higher_threat(delta, data.attack_range)
	if current_target != null and is_instance_valid(current_target):
		_face_point(current_target.global_position, delta)
		combat_component.process_attack_at(self, current_target, delta)


func _process_casting_ability(delta: float) -> void:
	if ability_component == null or not ability_component.has_pending_cast():
		_advance_command_queue()
		return
	if ability_component.try_complete_pending_cast(self):
		velocity = Vector2.ZERO
		_advance_command_queue()
		return
	var dest: Vector2 = ability_component.get_pending_destination()
	_face_point(dest, delta)
	_request_nav_toward_point(dest, 8.0)


func _process_gathering(delta: float) -> void:
	if gather_component == null or not gather_component.is_active():
		_advance_command_queue()
		return
	gather_component.tick(self, delta)


func _process_constructing(delta: float) -> void:
	if _construction_target == null or not is_instance_valid(_construction_target) or _construction_target.is_destroyed or _construction_target.is_constructed:
		_construction_target = null
		stop_component_navigation()
		if gather_bar_root != null:
			gather_bar_root.visible = false
		_advance_command_queue()
		return

	var unit_r: float = data.collision_radius if data != null else 13.0
	var build_reach: float = _construction_target.footprint_radius + unit_r + 28.0
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
			_advance_command_queue()
		return

	var approach: Vector2 = get_or_compute_approach_point(
		_construction_target,
		_construction_target.footprint_radius,
		8.0,
		_construction_target,
		null
	)
	request_component_navigation(approach, 12.0, 4.0)


func _process_staffing_building(delta: float) -> void:
	if staff_component == null or not staff_component.is_active():
		_advance_command_queue()
		return
	staff_component.tick(self, delta)


func _process_patrolling(delta: float) -> void:
	if patrol_waypoints.size() < 2:
		patrol_waypoints.clear()
		patrol_index = 0
		_advance_command_queue()
		return

	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	var aggro_on: bool = MatchManager.is_aggro_ai_enabled(get_tree())
	if aggro_on and _can_attack() and combat_component != null:
		var leash_range: float = maxf(data.aggro_range, data.attack_range) * 1.25
		if current_target != null and not combat_component.is_valid_target_in_range(self, current_target, leash_range):
			current_target = null
		if current_target == null:
			current_target = combat_component.find_nearest_enemy(self, data.aggro_range)
		else:
			_maybe_retarget_higher_threat(delta, data.attack_range)
	elif not aggro_on:
		current_target = null

	if current_target != null and is_instance_valid(current_target) and combat_component != null:
		_reset_progress_tracker()
		if combat_component.is_within_attack_envelope(self, current_target):
			_face_point(current_target.global_position, delta)
			combat_component.process_attack_at(self, current_target, delta)
			return
		combat_component.cancel_attack_animation()
		if combat_component.is_target_inside_min_range(self, current_target):
			current_target = null
		else:
			_request_nav_toward_point(current_target.global_position, 8.0)
			return

	if nav_agent == null:
		patrol_waypoints.clear()
		_advance_command_queue()
		return

	patrol_index = clampi(patrol_index, 0, patrol_waypoints.size() - 1)
	var dest: Vector2 = patrol_waypoints[patrol_index]
	if _last_nav_target == Vector2.INF or _last_nav_target.distance_squared_to(dest) > 1.0:
		_set_nav_target(dest)
	if not _is_nav_map_ready():
		return
	if _should_settle_at_destination(dest, delta):
		_reset_progress_tracker()
		patrol_index = (patrol_index + 1) % patrol_waypoints.size()
		_set_nav_target(patrol_waypoints[patrol_index])
		return
	_compute_nav_desired_velocity()


func _cancel_active_tasks(keep_gather: bool) -> void:
	clear_cached_approach_point()
	if combat_component != null:
		combat_component.cancel_attack_animation()
	if ability_component != null:
		ability_component.cancel_pending_cast()
	if not keep_gather and gather_component != null:
		gather_component.cancel()
	if staff_component != null:
		staff_component.cancel()
	patrol_waypoints.clear()
	patrol_index = 0
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


func _request_nav_toward_point(target_point: Vector2, repath_threshold: float, stop_distance: float = 0.0) -> void:
	var dist_to_target: float = global_position.distance_to(target_point)
	if stop_distance > 0.0 and dist_to_target <= stop_distance:
		return
	if nav_agent == null:
		_steer_direct_toward(target_point)
		return
	if _last_nav_target == Vector2.INF or _last_nav_target.distance_squared_to(target_point) > repath_threshold * repath_threshold:
		_set_nav_target(target_point)
	if not _is_nav_map_ready():
		_steer_direct_toward(target_point)
		return
	if nav_agent.is_navigation_finished():
		var reach_cutoff: float = stop_distance if stop_distance > 0.0 else maxf(nav_agent.target_desired_distance, 6.0)
		if dist_to_target > reach_cutoff:
			_steer_direct_toward(target_point)
		return
	_compute_nav_desired_velocity()
	if not _wants_nav_movement and dist_to_target > maxf(stop_distance, 4.0):
		_steer_direct_toward(target_point)


func _steer_direct_toward(target_point: Vector2) -> void:
	var to_target: Vector2 = target_point - global_position
	if to_target.length_squared() <= 4.0:
		return
	var dir: Vector2 = _steer_around_obstacles_and_units(to_target.normalized())
	_wants_nav_movement = true
	_desired_move_velocity = dir * get_effective_move_speed()


func _compute_nav_desired_velocity() -> void:
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var to_next: Vector2 = next_point - global_position
	if to_next.length_squared() < 1.0:
		return
	var dir: Vector2 = _steer_around_static_units(to_next.normalized())
	_wants_nav_movement = true
	_desired_move_velocity = dir * get_effective_move_speed()


func _steer_around_obstacles_and_units(move_dir: Vector2) -> Vector2:
	var steer: Vector2 = _steer_around_static_units(move_dir)
	if not is_inside_tree():
		return steer
	var my_r: float = data.collision_radius if data != null else 16.0
	var probe_dist: float = my_r + 22.0
	var probe_pt: Vector2 = global_position + steer * probe_dist
	var ignore_b: Building = _get_active_target_building()
	var ignore_rn: ResourceNode = _get_active_target_resource()
	var bounds: Rect2 = _get_arena_bounds()
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(my_r + 4.0, my_r + 4.0),
		bounds.size - Vector2((my_r + 4.0) * 2.0, (my_r + 4.0) * 2.0)
	)
	if _is_point_clear_of_obstacles(probe_pt, my_r + 2.0, safe_bounds, ignore_b, ignore_rn):
		return steer

	var tangent_l: Vector2 = Vector2(-steer.y, steer.x)
	var tangent_r: Vector2 = Vector2(steer.y, -steer.x)
	var left_clear: bool = _is_point_clear_of_obstacles(global_position + (steer * 0.45 + tangent_l * 0.85).normalized() * probe_dist, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	var right_clear: bool = _is_point_clear_of_obstacles(global_position + (steer * 0.45 + tangent_r * 0.85).normalized() * probe_dist, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	if left_clear and not right_clear:
		return (steer * 0.40 + tangent_l * 0.90).normalized()
	if right_clear and not left_clear:
		return (steer * 0.40 + tangent_r * 0.90).normalized()
	var chosen_t: Vector2 = tangent_l if _stuck_side_sign >= 0.0 else tangent_r
	return (steer * 0.35 + chosen_t * 0.92).normalized()


func _get_active_target_building() -> Building:
	if command_state == CommandState.CONSTRUCTING and is_instance_valid(_construction_target):
		return _construction_target
	if command_state == CommandState.STAFFING_BUILDING and staff_component != null and is_instance_valid(staff_component.target_building):
		return staff_component.target_building
	if command_state == CommandState.GATHERING and gather_component != null and gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and is_instance_valid(gather_component.dropoff_building):
		return gather_component.dropoff_building
	return null


func _get_active_target_resource() -> ResourceNode:
	if command_state == CommandState.GATHERING and gather_component != null and is_instance_valid(gather_component.target_node):
		return gather_component.target_node
	return null


func _get_arena_bounds() -> Rect2:
	if is_inside_tree():
		var nav_reg: Node = get_tree().get_first_node_in_group("arena_nav_region")
		if nav_reg != null and "arena_bounds" in nav_reg:
			var b: Variant = nav_reg.get("arena_bounds")
			if b is Rect2:
				return b as Rect2
	return Rect2(-1300.0, -950.0, 2600.0, 1900.0)


func _is_point_clear_of_obstacles(
	world_pos: Vector2,
	clearance_radius: float,
	safe_bounds: Rect2,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null
) -> bool:
	if safe_bounds.has_area() and not safe_bounds.has_point(world_pos):
		return false
	if not is_inside_tree():
		return true
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.call("overlaps_circle", world_pos, clearance_radius):
				return false
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.call("overlaps_circle", world_pos, clearance_radius):
				return false
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b == ignore_building:
			continue
		var min_d: float = b.footprint_radius + clearance_radius
		if b.global_position.distance_squared_to(world_pos) < min_d * min_d:
			return false
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted() or rn.is_vent or rn == ignore_resource:
			continue
		var min_d: float = rn.collision_radius + clearance_radius
		if rn.global_position.distance_squared_to(world_pos) < min_d * min_d:
			return false
	return true


func _should_ignore_unit_collision(other: Unit) -> bool:
	if other == null or data == null or other.data == null:
		return false
	if other.team != team:
		return false
	var self_strider: bool = data.ignore_friendly_unit_collision
	var other_strider: bool = other.data.ignore_friendly_unit_collision
	# Colossus Striders walk cleanly over non-strider friendly units, and allies walk cleanly underneath.
	return self_strider != other_strider


func _steer_around_static_units(move_dir: Vector2) -> Vector2:
	var steer: Vector2 = move_dir
	var my_r: float = data.collision_radius if data != null else 16.0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit) or node == self:
			continue
		var other: Unit = node
		if other.is_dead or other.is_staffed or other.is_queued_for_deletion() or other._can_move():
			continue
		if _should_ignore_unit_collision(other):
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
	var eff_speed: float = get_effective_move_speed()
	if _wants_nav_movement:
		var combined: Vector2 = target_velocity + _compute_overlap_separation(1.0)
		if combined.length() > eff_speed:
			combined = combined.normalized() * eff_speed
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
		if global_position.distance_to(_construction_target.global_position) <= _construction_target.footprint_radius + unit_r + 28.0:
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


func _update_worker_collision_passing() -> void:
	if data == null or data.ignore_friendly_unit_collision:
		return
	var is_worker_role: bool = data.can_gather or data.can_staff_compute or can_construct()
	if not is_worker_role:
		return
	# During active task transit (gather, construct, staff, or moving on/into a task command),
	# slide cleanly past friendly units while still colliding with World (Layer 1) and hostile units.
	var active_type: StringName = active_command.get("type", &"")
	var next_type: StringName = command_queue[0].get("type", &"") if not command_queue.is_empty() else &""
	var is_task_transit: bool = (
		command_state == CommandState.GATHERING
		or command_state == CommandState.CONSTRUCTING
		or command_state == CommandState.STAFFING_BUILDING
		or (command_state == CommandState.MOVING and (
			active_type == &"gather"
			or active_type == &"return_cargo"
			or active_type == &"build"
			or active_type == &"staff"
			or next_type == &"gather"
			or next_type == &"return_cargo"
			or next_type == &"build"
			or next_type == &"staff"
		))
	)
	var hostile_bit: int = 4 if team == Team.PLAYER else 2
	var want_mask: int = (1 | hostile_bit) if is_task_transit else 7
	if collision_mask != want_mask:
		collision_mask = want_mask

	# Disable RVO avoidance on workers during active task transit (and while stationary working) so
	# Godot's RVO2 solver never zeros safe_velocity behind teammates or resource nodes. Workers keep
	# NavigationAgent2D pathfinding + direct motion + soft separation, and re-enable RVO when idle/moving.
	if nav_agent != null:
		var want_avoidance: bool = not is_task_transit
		if nav_agent.avoidance_enabled != want_avoidance:
			nav_agent.avoidance_enabled = want_avoidance
			if not want_avoidance:
				nav_agent.set_velocity(Vector2.ZERO)


func _apply_anti_stuck_steering(delta: float) -> void:
	if not _wants_nav_movement or _desired_move_velocity.length_squared() <= 4.0:
		_stuck_sample_pos = global_position
		_stuck_sample_timer = 0.0
		_stuck_accum_time = 0.0
		_stuck_nudge_timer = 0.0
		_stuck_consecutive_nudges = 0
		return

	_stuck_sample_timer += delta
	if _stuck_sample_timer >= 0.25:
		var moved_dist: float = global_position.distance_to(_stuck_sample_pos)
		var actual_speed: float = moved_dist / maxf(0.05, _stuck_sample_timer)
		var eff_speed: float = maxf(1.0, get_effective_move_speed())
		if actual_speed < eff_speed * 0.16:
			_stuck_accum_time += _stuck_sample_timer
			if _stuck_accum_time >= 0.55:
				var forward: Vector2 = _desired_move_velocity.normalized()
				if _stuck_consecutive_nudges == 0:
					_stuck_side_sign = _pick_clearer_detour_side(forward)
				elif _stuck_consecutive_nudges >= 2:
					# Only flip side after two committed detour windows on the first side failed to clear.
					_stuck_side_sign = -_stuck_side_sign
					_stuck_consecutive_nudges = 0
				_stuck_consecutive_nudges += 1
				_stuck_nudge_dir = Vector2(-forward.y, forward.x) * _stuck_side_sign
				_stuck_nudge_timer = 0.65
				_stuck_accum_time = 0.0
				# Force a fresh NavigationAgent2D path & approach slot evaluation around the obstruction.
				invalidate_nav_path()
		else:
			_stuck_accum_time = 0.0
			if actual_speed >= eff_speed * 0.30:
				_stuck_consecutive_nudges = 0
		_stuck_sample_pos = global_position
		_stuck_sample_timer = 0.0

	if _stuck_nudge_timer > 0.0:
		_stuck_nudge_timer = maxf(0.0, _stuck_nudge_timer - delta)
		var base_dir: Vector2 = _desired_move_velocity.normalized()
		var blended: Vector2 = (base_dir * 0.35 + _stuck_nudge_dir * 0.90)
		if blended.length_squared() > 0.001:
			_desired_move_velocity = blended.normalized() * get_effective_move_speed()


func _pick_clearer_detour_side(forward: Vector2) -> float:
	var my_r: float = data.collision_radius if data != null else 16.0
	var bounds: Rect2 = _get_arena_bounds()
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(my_r + 6.0, my_r + 6.0),
		bounds.size - Vector2((my_r + 6.0) * 2.0, (my_r + 6.0) * 2.0)
	)
	var ignore_b: Building = _get_active_target_building()
	var ignore_rn: ResourceNode = _get_active_target_resource()
	var probe_r: float = my_r + 24.0
	var pos_dir: Vector2 = Vector2(-forward.y, forward.x)
	var neg_dir: Vector2 = Vector2(forward.y, -forward.x)
	var pos_clear: bool = _is_point_clear_of_obstacles(global_position + pos_dir * probe_r, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	var neg_clear: bool = _is_point_clear_of_obstacles(global_position + neg_dir * probe_r, my_r + 2.0, safe_bounds, ignore_b, ignore_rn)
	if pos_clear and not neg_clear:
		return 1.0
	if neg_clear and not pos_clear:
		return -1.0
	return _stuck_side_sign


func _compute_overlap_separation(extra_margin: float) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var my_r: float = data.collision_radius if data != null else 16.0
	var max_push: float = get_effective_move_speed() * 0.85 if data != null else 220.0
	var self_is_worker: bool = data != null and (data.can_gather or data.can_staff_compute or can_construct())
	var self_in_task: bool = (
		command_state == CommandState.GATHERING
		or command_state == CommandState.CONSTRUCTING
		or command_state == CommandState.STAFFING_BUILDING
	)
	var active_dest: Variant = get_active_command_destination() if self_in_task else null
	var self_near_task: bool = active_dest is Vector2 and global_position.distance_squared_to(active_dest as Vector2) <= 105.0 * 105.0

	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit) or node == self:
			continue
		var other: Unit = node
		if other.is_dead or other.is_staffed or other.is_queued_for_deletion():
			continue
		if _should_ignore_unit_collision(other):
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
		var push_scale: float = 1.0
		if self_is_worker and other.team == team and other.data != null and (other.data.can_gather or other.data.can_staff_compute or other.can_construct()):
			var other_stationary_working: bool = (
				(other.command_state == CommandState.GATHERING and other.gather_component != null and other.gather_component.is_harvesting_in_place())
				or (other.command_state == CommandState.CONSTRUCTING and not other._wants_nav_movement)
			)
			if self_near_task and other_stationary_working:
				# Do not let stationary harvesting/constructing workers push approaching teammates off reach.
				continue
			if self_in_task or other.command_state == CommandState.GATHERING or other.command_state == CommandState.CONSTRUCTING:
				push_scale = 0.25
		push += dir * max_push * overlap_ratio * push_scale
	return push.normalized() * max_push if push.length() > max_push else push


func _reset_progress_tracker() -> void:
	_no_progress_timer = 0.0
	_best_dist_to_goal = INF
	_stuck_sample_pos = global_position
	_stuck_sample_timer = 0.0
	_stuck_accum_time = 0.0
	_stuck_nudge_timer = 0.0
	_stuck_consecutive_nudges = 0


func _should_settle_at_destination(goal_pos: Vector2, delta: float) -> bool:
	var dist_to_goal: float = global_position.distance_to(goal_pos)
	var arrive_dist: float = nav_agent.target_desired_distance + (14.0 if not command_queue.is_empty() else 0.0)
	if dist_to_goal <= arrive_dist or nav_agent.is_navigation_finished():
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
				_wants_nav_movement = false
				_reset_progress_tracker()
				_advance_command_queue()
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
	var max_val: float = maxf(1.0, get_max_hp())
	var ratio: float = clampf(current_hp / max_val, 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	var mode: int = SettingsManager.health_bar_mode if SettingsManager != null else 0
	if mode == 1:
		health_bar_root.visible = true
	elif mode == 2:
		health_bar_root.visible = is_selected
	else:
		health_bar_root.visible = always_show_health_bar or is_selected or ratio < 0.999


func _setup_procedural_visuals() -> void:
	if body_visual == null:
		return
	var type_id: StringName = get_unit_type_id()
	if type_id == &"target_dummy":
		return
	if body_visual is Polygon2D:
		(body_visual as Polygon2D).color = Color(1.0, 1.0, 1.0, 0.0)
	for child: Node in body_visual.get_children():
		if child == cargo_visual or child == _entity_visuals:
			continue
		if child is CanvasItem:
			(child as CanvasItem).visible = false
	if _entity_visuals == null:
		_entity_visuals = ENTITY_VISUALS_SCRIPT.new()
		_entity_visuals.name = "EntityVisuals"
		body_visual.add_child(_entity_visuals)
	_entity_visuals.bind_unit(self)
	if type_id == &"arc_lancer":
		body_visual.position = Vector2(0.0, -6.0)
		queue_redraw()


func _update_stinger_trail(delta: float) -> void:
	_trail_sample_timer += delta
	if _trail_sample_timer < 0.04:
		return
	_trail_sample_timer = 0.0
	if velocity.length_squared() > 900.0:
		_trail_points.append(global_position)
		if _trail_points.size() > 7:
			_trail_points.pop_front()
		queue_redraw()
	elif not _trail_points.is_empty():
		_trail_points.pop_front()
		queue_redraw()


func _apply_team_visuals() -> void:
	if _entity_visuals != null:
		_entity_visuals.team = int(team)
		_entity_visuals.queue_redraw()
	if team != Team.ENEMY:
		return
	var type_id: StringName = get_unit_type_id()
	if type_id == &"target_dummy":
		return
	if _entity_visuals == null and body_visual is Polygon2D:
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


func get_armor_class_label() -> String:
	if data == null:
		return "Light"
	if data.unit_type_id == &"goliath_frame" or data.unit_type_id == &"arc_lancer":
		return "Heavy Synthetic"
	if data.is_armored:
		return "Armored"
	return "Light"


func get_inspection_data() -> Dictionary:
	var is_enemy: bool = (team == Team.ENEMY)
	var accent: Color = Color(1.0, 0.36, 0.26, 1.0) if is_enemy else Color(0.24, 0.92, 0.88, 1.0)
	var class_tag: String = get_armor_class_label().to_upper()
	var subtitle: String = ("HOSTILE %s" % class_tag) if is_enemy else ("FRIENDLY %s" % class_tag)

	if not is_enemy and data != null:
		if data.unit_type_id == &"scout_unit" or data.unit_type_id == &"stinger":
			accent = Color(0.98, 0.78, 0.24, 1.0)
			subtitle = "LIGHT  •  FAST FLANKER"
		elif data.unit_type_id == &"clone_trooper":
			accent = Color(0.24, 0.94, 0.82, 1.0)
			subtitle = "LIGHT  •  VAT-BORN INFANTRY"
		elif data.unit_type_id == &"symbiote":
			accent = Color(0.32, 1.0, 0.66, 1.0)
			subtitle = "LIGHT  •  BIO-SUPPORT DRONE"
		elif data.unit_type_id == &"lance_rig":
			accent = Color(0.98, 0.68, 0.28, 1.0)
			subtitle = "LIGHT  •  ANTI-ARMOR MECH"
		elif data.unit_type_id == &"signal_jammer":
			accent = Color(0.76, 0.56, 1.0, 1.0)
			subtitle = "LIGHT  •  DISRUPTION WALKER"
		elif data.unit_type_id == &"goliath_frame":
			accent = Color(0.36, 0.92, 1.0, 1.0)
			subtitle = "HEAVY SYNTHETIC  •  JUGGERNAUT"
		elif data.unit_type_id == &"arc_lancer":
			accent = Color(0.46, 0.98, 1.0, 1.0)
			subtitle = "HEAVY SYNTHETIC  •  COLOSSUS STRIDER"
		elif data.unit_type_id == &"chrysalis_mortar":
			accent = Color(0.46, 1.0, 0.54, 1.0)
			subtitle = "ARMORED  •  SIEGE ARTILLERY"
		elif data.unit_type_id == &"silica_harvester":
			accent = Color(0.96, 0.68, 0.22, 1.0)
			subtitle = "ARMORED  •  SILICA HARVESTER"
		elif data.can_staff_compute:
			accent = Color(0.32, 0.82, 1.0, 1.0)
			subtitle = "LIGHT  •  COMPUTE SPECIALIST"
		elif data.can_gather:
			accent = Color(0.28, 0.94, 0.56, 1.0)
			subtitle = "LIGHT  •  UTILITY WORKER"

	var max_hp_val: float = get_max_hp()
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
		stats.append({"label": "Speed", "value": "%d px/s" % int(round(get_effective_move_speed()))})
		stats.append({"label": "State", "value": _get_command_state_label()})
	elif data != null and data.can_staff_compute:
		stats.append({"label": "Role", "value": "Compute Staff"})
		stats.append({"label": "Output", "value": "+5 Compute / 3.0s"})
		stats.append({"label": "Speed", "value": "%d px/s" % int(round(get_effective_move_speed()))})
		stats.append({"label": "Bandwidth", "value": "%d BW" % data.bandwidth_cost})
	elif data != null:
		var dmg_str: String = "%d" % int(round(data.attack_damage))
		if data.bonus_vs_armored > 0.0:
			dmg_str += " (+%d vs Armored)" % int(round(data.bonus_vs_armored))
		elif data.aoe_attack_radius > 0.0:
			dmg_str += " (AoE %dpx)" % int(round(data.aoe_attack_radius))
		elif data.line_pierce_width > 0.0:
			dmg_str += " (Line Pierce)"
		stats.append({"label": "Damage", "value": dmg_str})

		var range_str: String = "%d px" % int(round(data.attack_range))
		if data.min_attack_range > 0.0:
			range_str = "%d–%d px (Min)" % [int(round(data.min_attack_range)), int(round(data.attack_range))]
		stats.append({"label": "Range", "value": range_str})

		var spd_str: String = "%d px/s" % int(round(get_effective_move_speed()))
		if _adrenal_timer > 0.0:
			spd_str += " [SURGE]"
		elif _slow_timer > 0.0:
			spd_str += " [SLOW]"
		stats.append({"label": "Speed", "value": spd_str})

		var dr: float = get_effective_damage_reduction()
		if data.heal_aura_rate > 0.0:
			stats.append({"label": "Aura", "value": "+%.0f HP/s (%dpx)" % [data.heal_aura_rate, int(round(data.heal_aura_radius))]})
		elif data.ignore_friendly_unit_collision:
			stats.append({"label": "Class", "value": "%s • Stride" % get_armor_class_label()})
		elif dr > 0.001:
			stats.append({"label": "Armor", "value": "%s (-%d%% Dmg)" % [get_armor_class_label(), int(round(dr * 100.0))]})
		elif data.attack_damage > 0.0 and data.attack_cooldown > 0.0:
			stats.append({"label": "Class", "value": "%s • %.1f/s" % [get_armor_class_label(), 1.0 / get_effective_attack_cooldown()]})
		else:
			stats.append({"label": "Class", "value": get_armor_class_label()})

		if data.attack_damage > 0.0 or kill_count > 0:
			if veterancy_rank > 0:
				var rank_col: Color = Color(1.0, 0.86, 0.28, 1.0) if veterancy_rank >= 3 else Color(0.46, 0.98, 1.0, 1.0)
				stats.append({
					"label": "Rank",
					"value": "%s (%d Kills)" % [get_veterancy_rank_name().to_upper(), kill_count],
					"color": rank_col,
				})
			else:
				stats.append({"label": "Kills", "value": "%d" % kill_count})

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
		CommandState.PATROLLING:
			return "Patrolling"
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
