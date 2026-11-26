class_name Unit
extends CharacterBody2D

enum Team {
	PLAYER = 0,
	ENEMY = 1,
	TEAM_3 = 2,
	TEAM_4 = 3,
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
	REPAIRING,
	SALVAGING,
}

enum Stance {
	AGGRESSIVE,
	DEFENSIVE,
	HOLD_POSITION,
}

enum DeployState {
	MOBILE,
	DEPLOYING,
	DEPLOYED,
	UNDEPLOYING,
}

const DEFENSIVE_LEASH_RADIUS: float = 260.0

const CMD_EXEC_FAILED: int = 0
const CMD_EXEC_ACTIVE: int = 1
const CMD_EXEC_IMMEDIATE_DONE: int = 2

const ABILITY_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/ability_component.gd")
const COMBAT_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/combat_component.gd")
const HEAL_AURA_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/heal_aura_component.gd")
const REPAIR_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/repair_component.gd")
const MOVEMENT_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/movement_component.gd")
const STATUS_EFFECT_COMPONENT_SCRIPT: GDScript = preload("res://scripts/units/status_effect_component.gd")
const ENTITY_VISUALS_SCRIPT: GDScript = preload("res://ui/overlays/entity_visuals.gd")
const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const SALVAGE_CORE_SCENE_PATH: String = "res://scenes/world/salvage_core.tscn"
const AUTO_RETARGET_INTERVAL: float = 0.25
const VETERANCY_THRESHOLDS: Array = [0, 3, 6, 10]
const VETERANCY_NAMES: Array = ["Standard", "Veteran", "Elite", "Apex"]
const HIT_FLASH_DURATION: float = 0.08
const SHIELD_HIT_FLASH_DURATION: float = 0.14
const SPAWN_ANIM_DURATION: float = 0.25
const HEALTH_BAR_WIDTH: float = 36.0
const GATHER_BAR_WIDTH: float = 32.0

signal selection_changed(unit: Unit, selected: bool)
signal health_changed(unit: Unit, current_hp: float, max_hp: float)
signal shield_changed(unit: Unit, current_shield: float, max_shield: float)
signal status_changed(unit: Unit)
signal died(unit: Unit)
signal ability_cooldown_updated(ability_id: StringName, remaining: float, duration: float)
signal ability_executed(ability_id: StringName, target_pos: Vector2)
signal cargo_changed(unit: Unit, resource_type: StringName, amount: int)
signal staffed_state_changed(unit: Unit, staffed: bool)
signal command_queue_changed(unit: Unit)
signal stance_changed(unit: Unit, new_stance: Stance)
signal deploy_state_changed(unit: Unit, new_state: DeployState)

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
var is_hovered: bool = false
var is_marquee_highlighted: bool = false
var spawn_anim_timer: float = 0.0
var is_dead: bool = false
var is_staffed: bool = false
var current_hp: float = 100.0
var max_shield: float = 0.0
var current_shield: float = 0.0
var deploy_state: DeployState = DeployState.MOBILE
var kill_count: int = 0
var veterancy_rank: int = 0
var last_attacker_team: int = -1
var _last_unseen_retaliate_ms: int = -9999
var command_state: CommandState = CommandState.IDLE
var current_target: Node2D = null
var ability_component: AbilityComponent = null
var combat_component: CombatComponent = null
var repair_component: Node = null
var movement_component: Node = null
var status_effect_component: Node = null
var command_queue: Array[Dictionary] = []
var active_command: Dictionary = {}
var patrol_waypoints: Array[Vector2] = []
var patrol_index: int = 0
var defensive_anchor: Vector2 = Vector2.ZERO

var _construction_target: Building = null
var _salvage_target: Node2D = null
var _is_salvaging_in_place: bool = false
var _salvage_vfx_timer: float = 0.0
var _move_destination: Vector2 = Vector2.ZERO
var _attack_move_destination: Vector2 = Vector2.ZERO
var _hit_flash_timer: float = 0.0
var _shield_hit_flash_timer: float = 0.0
var _shield_regen_timer: float = 0.0
var _shield_aura_poll_timer: float = 0.0
var _cached_shield_delay_speedup: float = 0.0
var _was_in_rail_windup: bool = false
var _last_emitted_shield_int: int = -1
var _shield_bar_bg: ColorRect = null
var _shield_bar_fill: ColorRect = null
var _deploy_timer: float = 0.0
var _deploy_duration_active: float = 1.2
var _last_delta: float = 1.0 / 60.0
var _entity_visuals: EntityVisuals = null
var _trail_points: Array[Vector2] = []
var _trail_sample_timer: float = 0.0
var _auto_retarget_timer: float = 0.0
var _vfx_anim_time: float = 0.0
var _recoil_offset: float = 0.0
var _recoil_decay_rate: float = 28.0


func _ready() -> void:
	add_to_group("units")
	add_to_group("selectable_units")
	if data == null:
		data = UnitData.new()
	current_hp = data.max_hp
	max_shield = maxf(0.0, data.max_shield)
	current_shield = max_shield
	_last_emitted_shield_int = int(round(current_shield))
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

	if data.is_worker_class():
		repair_component = get_node_or_null("RepairComponent")
		if repair_component == null:
			repair_component = REPAIR_COMPONENT_SCRIPT.new()
			repair_component.name = "RepairComponent"
			add_child(repair_component)

	ability_component = ABILITY_COMPONENT_SCRIPT.new()
	ability_component.name = "AbilityComponent"
	add_child(ability_component)
	ability_component.init_autocast_defaults(self)
	ability_component.ability_cooldown_updated.connect(func(ability_id: StringName, remaining: float, duration: float) -> void:
		ability_cooldown_updated.emit(ability_id, remaining, duration)
	)
	ability_component.ability_executed.connect(func(ability_id: StringName, target_pos: Vector2) -> void:
		ability_executed.emit(ability_id, target_pos)
	)

	movement_component = MOVEMENT_COMPONENT_SCRIPT.new()
	movement_component.name = "MovementComponent"
	add_child(movement_component)
	movement_component.call("initialize_for_unit", self)

	status_effect_component = STATUS_EFFECT_COMPONENT_SCRIPT.new()
	status_effect_component.name = "StatusEffectComponent"
	add_child(status_effect_component)

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
	if SpatialGrid != null:
		SpatialGrid.register_unit(self)
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	if data != null and data.auto_gather_on_spawn and can_gather():
		call_deferred("_try_start_auto_gather")


func _exit_tree() -> void:
	if SpatialGrid != null:
		SpatialGrid.unregister_unit(self)
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
		if _entity_visuals != null and is_instance_valid(_entity_visuals):
			_entity_visuals.queue_redraw()
		_update_health_bar()
		queue_redraw()
	selection_changed.emit(self, is_selected)


func set_marquee_highlighted(active: bool) -> void:
	if is_marquee_highlighted == active:
		return
	is_marquee_highlighted = active
	if _entity_visuals != null and is_instance_valid(_entity_visuals):
		_entity_visuals.queue_redraw()
	queue_redraw()


func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	if _entity_visuals != null and is_instance_valid(_entity_visuals):
		_entity_visuals.queue_redraw()
	queue_redraw()


func trigger_spawn_animation() -> void:
	spawn_anim_timer = SPAWN_ANIM_DURATION
	if is_node_ready() and body_visual != null:
		body_visual.scale = Vector2(0.72, 0.72)
	if _entity_visuals != null and is_instance_valid(_entity_visuals):
		_entity_visuals.queue_redraw()


func get_selection_radius() -> float:
	if data != null:
		return maxf(data.selection_radius, data.collision_radius + 4.0)
	return 20.0


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
		var is_local_owned: bool = TeamManager.is_team_controlled_by_local_human(int(team)) if TeamManager != null else (team == Team.PLAYER)
		if get_parent() != null and (is_local_owned or visible):
			var fx: CombatVFX = VFXPool.acquire_combat_vfx(56) if VFXPool != null else null
			if fx == null:
				fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
				fx.z_index = 56
				get_parent().add_child(fx)
			fx.setup_rank_up_pulse(global_position, veterancy_rank)
		if is_local_owned and AudioManager != null:
			AudioManager.play_sfx(&"veterancy_rank_up", -3.0, 0.03)
		queue_redraw()
	status_changed.emit(self)


func get_vision_range() -> float:
	if data != null and data.vision_range > 0.0:
		return data.vision_range
	return 360.0


func is_ability_ready(ability: AbilityData) -> bool:
	if status_effect_component != null and bool(status_effect_component.call("is_abilities_blocked")):
		return false
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
		invalidate_nav_path()
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


func can_repair() -> bool:
	return not is_dead and not is_staffed and repair_component != null and bool(repair_component.call("can_unit_repair", self))


func can_repair_target(target: Node2D) -> bool:
	return can_repair() and bool(repair_component.call("is_eligible_target", self, target))


func command_repair(target: Node2D, append_to_queue: bool = false) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return issue_command({"type": &"repair", "target": target, "pos": target.global_position}, append_to_queue)


func _start_repair(target: Node2D) -> bool:
	if is_dead or is_staffed or not _can_move() or not can_repair_target(target):
		return false
	_cancel_active_tasks(false)
	if not bool(repair_component.call("start_repair", self, target)):
		return false
	command_state = CommandState.REPAIRING
	current_target = null
	_reset_progress_tracker()
	invalidate_nav_path()
	status_changed.emit(self)
	return true


func can_salvage_core() -> bool:
	if is_dead or is_staffed or data == null:
		return false
	return data.is_worker_class()


func is_salvaging_in_place() -> bool:
	return command_state == CommandState.SALVAGING and _is_salvaging_in_place


func command_salvage(salvage_core: Node2D, append_to_queue: bool = false) -> bool:
	if salvage_core == null or not is_instance_valid(salvage_core):
		return false
	return issue_command({"type": &"salvage", "target": salvage_core, "pos": salvage_core.global_position}, append_to_queue)


func _start_salvage(salvage_core: Node2D) -> bool:
	if is_dead or is_staffed or not _can_move() or not can_salvage_core():
		return false
	if salvage_core == null or not is_instance_valid(salvage_core) or bool(salvage_core.get("is_claimed")):
		return false
	_cancel_active_tasks(false)
	_salvage_target = salvage_core
	_is_salvaging_in_place = false
	_salvage_vfx_timer = 0.0
	command_state = CommandState.SALVAGING
	current_target = null
	_reset_progress_tracker()
	invalidate_nav_path()
	status_changed.emit(self)
	return true


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
	if not data.is_worker_class():
		return false
	if command_state != CommandState.IDLE or not command_queue.is_empty() or not active_command.is_empty():
		return false
	if _construction_target != null:
		return false
	if gather_component != null and gather_component.is_active():
		return false
	if staff_component != null and staff_component.is_active():
		return false
	if repair_component != null and bool(repair_component.call("is_active")):
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
	var cmd_type_check: StringName = cmd.get("type", &"")
	# Anchored/deploying units ignore Move/Attack-Move/Patrol without accidentally undeploying or breaking focus-fire.
	if is_movement_locked_by_deploy() and (cmd_type_check == &"move" or cmd_type_check == &"attack_move" or cmd_type_check == &"patrol"):
		return false
	if append_to_queue:
		var is_idle_now: bool = (
			(command_state == CommandState.IDLE or command_state == CommandState.HOLD_POSITION)
			and active_command.is_empty()
			and command_queue.is_empty()
		)
		if not is_idle_now:
			if cmd_type_check == &"attack_target":
				var new_atk_t: Variant = cmd.get("target", null)
				if not command_queue.is_empty():
					var last_cmd: Dictionary = command_queue[command_queue.size() - 1]
					if last_cmd.get("type", &"") == &"attack_target" and last_cmd.get("target", null) == new_atk_t:
						return true
				elif command_state == CommandState.ATTACKING_TARGET and current_target == new_atk_t:
					return true
			command_queue.append(cmd.duplicate())
			command_queue_changed.emit(self)
			status_changed.emit(self)
			return true
	else:
		clear_command_queue()
		if gather_component != null:
			var cmd_type: StringName = cmd.get("type", &"")
			if (
				cmd_type == &"move"
				or cmd_type == &"attack_move"
				or cmd_type == &"attack_target"
				or cmd_type == &"patrol"
				or cmd_type == &"build"
				or cmd_type == &"repair"
				or cmd_type == &"salvage"
				or cmd_type == &"staff"
			):
				gather_component.cancel(self, true)
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
		&"repair":
			var rep_t: Variant = cmd.get("target", null)
			if rep_t != null and is_instance_valid(rep_t) and rep_t is Node2D and not (rep_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if _start_repair(rep_t as Node2D) else CMD_EXEC_FAILED
		&"salvage":
			var salv_t: Variant = cmd.get("target", null)
			if salv_t != null and is_instance_valid(salv_t) and salv_t is Node2D and not (salv_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if _start_salvage(salv_t as Node2D) else CMD_EXEC_FAILED
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
		CommandState.REPAIRING:
			if repair_component != null:
				var rep_node: Variant = repair_component.get("target_entity")
				if rep_node is Node2D and is_instance_valid(rep_node):
					return (rep_node as Node2D).global_position
		CommandState.SALVAGING:
			if _salvage_target != null and is_instance_valid(_salvage_target):
				return _salvage_target.global_position
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
	invalidate_nav_path()
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
	invalidate_nav_path()
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
	invalidate_nav_path()
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
	invalidate_nav_path()
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
	if SpatialGrid != null:
		SpatialGrid.unregister_unit(self)
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
	if SpatialGrid != null:
		SpatialGrid.register_unit(self)
	set_physics_process(true)
	staffed_state_changed.emit(self, false)


func is_nav_movement_active() -> bool:
	return movement_component != null and bool(movement_component.get("wants_nav_movement"))


func can_unit_move() -> bool:
	return _can_move()


func request_component_navigation(target_point: Vector2, repath_threshold: float = 10.0, stop_distance: float = 4.0) -> void:
	_request_nav_toward_point(target_point, repath_threshold, stop_distance)


func face_world_point(world_point: Vector2, delta: float) -> void:
	_face_point(world_point, delta)


func stop_component_navigation() -> void:
	if movement_component != null:
		movement_component.call("stop_navigation", self)
	else:
		velocity = Vector2.ZERO


func reset_progress_tracker() -> void:
	_reset_progress_tracker()


func invalidate_nav_path() -> void:
	if movement_component != null:
		movement_component.call("invalidate_nav_path")


func get_cached_approach_point() -> Vector2:
	return (movement_component.call("get_cached_approach_point") as Vector2) if movement_component != null else Vector2.INF


func clear_cached_approach_point() -> void:
	if movement_component != null:
		movement_component.call("clear_cached_approach_point")


func get_or_compute_approach_point(
	target_node: Node2D,
	target_radius: float,
	margin: float = 8.0,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null
) -> Vector2:
	if movement_component != null:
		return movement_component.call("get_or_compute_approach_point", self, target_node, target_radius, margin, ignore_building, ignore_resource) as Vector2
	return target_node.global_position if (target_node != null and is_instance_valid(target_node)) else global_position


func find_clear_approach_point(
	target_center: Vector2,
	target_radius: float,
	margin: float = 8.0,
	ignore_building: Building = null,
	ignore_resource: ResourceNode = null,
	avoid_friendly_workers: bool = true
) -> Vector2:
	if movement_component != null:
		return movement_component.call("find_clear_approach_point", self, target_center, target_radius, margin, ignore_building, ignore_resource, avoid_friendly_workers) as Vector2
	return target_center


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


func has_shields() -> bool:
	return max_shield > 0.0


func restore_shield(amount: float) -> float:
	if is_dead or is_staffed or max_shield <= 0.0 or amount <= 0.0:
		return 0.0
	var prev: float = current_shield
	current_shield = minf(max_shield, current_shield + amount)
	var restored: float = current_shield - prev
	if restored > 0.0:
		_last_emitted_shield_int = int(round(current_shield))
		_update_health_bar()
		queue_redraw()
		shield_changed.emit(self, current_shield, max_shield)
		status_changed.emit(self)
	return restored


func can_toggle_deploy() -> bool:
	return data != null and data.can_deploy and not is_dead and not is_staffed


func is_deployed() -> bool:
	return deploy_state == DeployState.DEPLOYED


func is_deploy_transitioning() -> bool:
	return deploy_state == DeployState.DEPLOYING or deploy_state == DeployState.UNDEPLOYING


func is_movement_locked_by_deploy() -> bool:
	return deploy_state != DeployState.MOBILE


func get_deploy_progress() -> float:
	var dur: float = maxf(0.1, _deploy_duration_active)
	if deploy_state == DeployState.DEPLOYING:
		return 1.0 - clampf(_deploy_timer / dur, 0.0, 1.0)
	if deploy_state == DeployState.UNDEPLOYING:
		return clampf(_deploy_timer / dur, 0.0, 1.0)
	if deploy_state == DeployState.DEPLOYED:
		return 1.0
	return 0.0


func request_deploy() -> void:
	if not can_toggle_deploy():
		return
	if deploy_state == DeployState.DEPLOYED or deploy_state == DeployState.DEPLOYING:
		return
	var total_dur: float = maxf(0.1, data.deploy_duration)
	if deploy_state == DeployState.UNDEPLOYING:
		_deploy_timer = maxf(0.05, _deploy_duration_active - _deploy_timer)
	else:
		_deploy_duration_active = total_dur
		_deploy_timer = _deploy_duration_active
	clear_command_queue()
	_cancel_active_tasks(false)
	command_state = CommandState.IDLE
	current_target = null
	stop_component_navigation()
	velocity = Vector2.ZERO
	deploy_state = DeployState.DEPLOYING
	if AudioManager != null:
		AudioManager.play_sfx(&"deploy_lock", -3.0, 0.03, global_position, true)
	queue_redraw()
	deploy_state_changed.emit(self, deploy_state)
	status_changed.emit(self)


func request_undeploy() -> void:
	if not can_toggle_deploy():
		return
	if deploy_state == DeployState.MOBILE or deploy_state == DeployState.UNDEPLOYING:
		return
	var total_dur: float = maxf(0.1, data.deploy_duration)
	if deploy_state == DeployState.DEPLOYING:
		_deploy_timer = maxf(0.05, _deploy_duration_active - _deploy_timer)
	else:
		_deploy_duration_active = total_dur
		_deploy_timer = _deploy_duration_active
	if combat_component != null:
		combat_component.cancel_attack_animation()
	deploy_state = DeployState.UNDEPLOYING
	if AudioManager != null:
		AudioManager.play_sfx(&"deploy_release", -3.0, 0.03, global_position, true)
	queue_redraw()
	deploy_state_changed.emit(self, deploy_state)
	status_changed.emit(self)


func toggle_deploy() -> void:
	if deploy_state == DeployState.MOBILE or deploy_state == DeployState.UNDEPLOYING:
		request_deploy()
	else:
		request_undeploy()


func command_move(target_pos: Vector2, append_to_queue: bool = false) -> void:
	issue_command({"type": &"move", "pos": target_pos}, append_to_queue)


func _start_move(target_pos: Vector2) -> bool:
	if is_dead or is_staffed or not _can_move():
		return false
	if stance != Stance.AGGRESSIVE:
		stance = Stance.AGGRESSIVE
		stance_changed.emit(self, stance)
		queue_redraw()
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
	invalidate_nav_path()
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
		var immediate_target: Node2D = combat_component.force_immediate_target_scan(self, get_effective_aggro_range())
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
		stop_component_navigation()
	elif stance == Stance.DEFENSIVE:
		clear_command_queue()
		_cancel_active_tasks(false)
		defensive_anchor = global_position
		command_state = CommandState.IDLE
		current_target = null
		stop_component_navigation()
	elif command_state == CommandState.HOLD_POSITION:
		command_state = CommandState.IDLE
		current_target = null
	queue_redraw()
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
	if stance == Stance.DEFENSIVE:
		defensive_anchor = global_position
	command_state = CommandState.HOLD_POSITION if stance == Stance.HOLD_POSITION else CommandState.IDLE
	current_target = null
	stop_component_navigation()
	queue_redraw()
	status_changed.emit(self)


func command_hold_position() -> void:
	set_stance(Stance.HOLD_POSITION)


func command_defensive_stance() -> void:
	set_stance(Stance.DEFENSIVE)


func take_damage(amount: float, attacker: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	if attacker != null and is_instance_valid(attacker):
		if attacker is Unit:
			last_attacker_team = int((attacker as Unit).team)
		elif attacker is Building:
			last_attacker_team = int((attacker as Building).team)

	var econ: EconomyManager = _get_economy_manager()
	if max_shield > 0.0:
		var delay_mult: float = econ.get_shield_regen_delay_multiplier(int(team)) if econ != null else 1.0
		var base_delay: float = data.shield_regen_delay if data != null else 6.0
		_shield_regen_timer = maxf(0.0, base_delay * delay_mult)

	var dmg_taken_mult: float = float(status_effect_component.call("get_damage_taken_multiplier")) if status_effect_component != null else 1.0
	var remaining: float = amount * maxf(0.0, dmg_taken_mult)
	var absorbed_temp: float = 0.0
	# Layer 1 — Temporary Bonus Barrier (Unmitigated)
	if status_effect_component != null and remaining > 0.0:
		var before_temp: float = remaining
		remaining = float(status_effect_component.call("absorb_damage_shield", remaining, &"generic"))
		absorbed_temp = maxf(0.0, before_temp - remaining)

	# Layer 2 — Native Regenerating Shield (Unmitigated)
	var had_native_shield: bool = (current_shield > 0.001)
	var absorbed_native: float = 0.0
	if remaining > 0.0 and current_shield > 0.0:
		absorbed_native = minf(current_shield, remaining)
		current_shield = maxf(0.0, current_shield - absorbed_native)
		remaining = maxf(0.0, remaining - absorbed_native)

	var shield_absorbed: bool = (absorbed_temp > 0.0 or absorbed_native > 0.0)
	if shield_absorbed:
		_shield_hit_flash_timer = SHIELD_HIT_FLASH_DURATION
		if absorbed_native > 0.0:
			_last_emitted_shield_int = int(round(current_shield))
			shield_changed.emit(self, current_shield, max_shield)
			if had_native_shield and current_shield <= 0.001:
				var shatter_dir: Vector2 = Vector2.ZERO
				if attacker is Node2D and is_instance_valid(attacker):
					var d_vec: Vector2 = global_position - (attacker as Node2D).global_position
					if d_vec.length_squared() > 1.0:
						shatter_dir = d_vec.normalized()
				_trigger_shield_shatter_feedback(shatter_dir)
		_emit_hit_feedback_pip(HitFeedbackOverlay.KIND_SHIELD_ABSORB, int(round(absorbed_temp + absorbed_native)))

	# Layer 3 — Hull HP (Mitigated)
	var hull_damaged: bool = false
	if remaining > 0.0:
		var mitigation: float = get_effective_damage_reduction()
		var dmg_mult: float = float(status_effect_component.call("get_damage_taken_multiplier")) if status_effect_component != null else 1.0
		var effective_damage: float = remaining * (1.0 - mitigation) * dmg_mult
		if effective_damage > 0.0:
			current_hp = maxf(0.0, current_hp - effective_damage)
			hull_damaged = true
			_hit_flash_timer = HIT_FLASH_DURATION
			if is_node_ready():
				body_visual.modulate = Color(1.95, 2.25, 2.35, 1.0)
			health_changed.emit(self, current_hp, get_max_hp())
			if mitigation >= 0.25 and remaining <= 24.0:
				_emit_hit_feedback_pip(HitFeedbackOverlay.KIND_ARMOR_BLUNTED, int(round(effective_damage)))
	elif shield_absorbed and is_node_ready() and _hit_flash_timer <= 0.0:
		# Subtle cyan shield-hit flash distinct from hull damage flash
		body_visual.modulate = Color(0.82, 1.48, 2.15, 1.0)

	if not hull_damaged and not shield_absorbed:
		status_changed.emit(self)
		return

	if is_inside_tree():
		var mm_hm: Node = get_tree().get_first_node_in_group("match_manager")
		if mm_hm != null and mm_hm.has_method("record_combat_heatmap_damage"):
			mm_hm.call("record_combat_heatmap_damage", global_position, int(team))

	_update_health_bar()
	queue_redraw()
	var is_local_owned: bool = TeamManager.is_team_controlled_by_local_human(int(team)) if TeamManager != null else (team == Team.PLAYER)
	if is_local_owned and is_inside_tree():
		var mm: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if mm != null:
			var unit_label: String = data.display_name if data != null else "Unit"
			mm.push_tactical_alert(global_position, &"under_attack", "%s Under Attack!" % unit_label)
	status_changed.emit(self)

	# Idle aggressive/defensive combatants retaliate against visible attackers (within leash when Defensive).
	# If taking unseen fire (e.g., from fogged high ground), NEVER shoot through fog; instead advance up
	# the nearest navigable ramp toward the firing sector to establish high-ground vision.
	if MatchManager.is_aggro_ai_enabled(get_tree()) and command_state == CommandState.IDLE and (current_target == null or not is_instance_valid(current_target)) and attacker != null and is_instance_valid(attacker) and (attacker is Unit or attacker is Building) and _can_attack():
		if combat_component != null and combat_component.should_pursue_targets(self):
			var atk_node: Node2D = attacker as Node2D
			if combat_component.is_valid_target(self, attacker):
				var allow_retaliate: bool = true
				if stance == Stance.DEFENSIVE:
					var max_engage: float = DEFENSIVE_LEASH_RADIUS + get_effective_attack_range()
					allow_retaliate = combat_component.is_within_attack_envelope(self, atk_node) or defensive_anchor.distance_to(atk_node.global_position) <= max_engage
				if allow_retaliate:
					current_target = atk_node
			else:
				var atk_team: int = int((attacker as Unit).team) if attacker is Unit else int((attacker as Building).team)
				var is_hostile_atk: bool = TeamManager.are_enemies(int(team), atk_team) if TeamManager != null else (atk_team != int(team))
				var now_ret_ms: int = Time.get_ticks_msec()
				if is_hostile_atk and (now_ret_ms - _last_unseen_retaliate_ms) >= 1200:
					_last_unseen_retaliate_ms = now_ret_ms
					var dir_to_fire: Vector2 = atk_node.global_position - global_position
					var dist_to_fire: float = dir_to_fire.length()
					var probe_pos: Vector2 = atk_node.global_position
					if dist_to_fire > 420.0:
						probe_pos = global_position + (dir_to_fire / dist_to_fire) * 420.0
					if stance == Stance.DEFENSIVE:
						var from_anchor: Vector2 = probe_pos - defensive_anchor
						if from_anchor.length() > DEFENSIVE_LEASH_RADIUS:
							probe_pos = defensive_anchor + from_anchor.normalized() * DEFENSIVE_LEASH_RADIUS
					var nav_map: RID = get_world_2d().get_navigation_map() if is_inside_tree() else RID()
					if nav_map.is_valid():
						probe_pos = NavigationServer2D.map_get_closest_point(nav_map, probe_pos)
					if probe_pos.distance_squared_to(global_position) > 24.0 * 24.0:
						command_attack_move(probe_pos, false)

	if current_hp <= 0.0:
		if attacker != null and is_instance_valid(attacker) and attacker is Unit:
			var killer: Unit = attacker as Unit
			var is_enemy_killer: bool = TeamManager.are_enemies(int(killer.team), int(team)) if TeamManager != null else (killer.team != team)
			if not killer.is_dead and is_enemy_killer:
				killer.register_kill(self)
		_die()


func _emit_hit_feedback_pip(kind: StringName, val: int = 0) -> void:
	if not is_inside_tree():
		return
	var is_local_view: bool = TeamManager.is_team_controlled_by_local_human(int(team)) if TeamManager != null else (team == Team.PLAYER)
	if not is_local_view and not visible:
		return
	var ov: Node = get_tree().get_first_node_in_group("hit_feedback_overlay")
	if ov != null and ov.has_method("push_hit_pip"):
		ov.call("push_hit_pip", global_position, kind, val, get_instance_id())


func trigger_weapon_recoil(kick_px: float) -> void:
	_recoil_offset = maxf(_recoil_offset, clampf(kick_px, 0.0, 7.5))


func _trigger_shield_shatter_feedback(impact_dir: Vector2 = Vector2.ZERO) -> void:
	if not is_inside_tree():
		return
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Team.PLAYER)
	var is_friendly_view: bool = viewer < 0 or (TeamManager.are_allies(viewer, int(team)) if TeamManager != null else (team == Team.PLAYER))
	if not is_friendly_view and not visible:
		return
	var is_mono: bool = TeamManager != null and TeamManager.has_method("get_team_faction") and TeamManager.get_team_faction(int(team)) == &"monolith_os"
	var host: Node = get_parent()
	if host != null:
		var fx: CombatVFX = VFXPool.acquire_combat_vfx(56) if VFXPool != null else null
		if fx == null:
			fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
			fx.z_index = 56
			host.add_child(fx)
		var rad: float = (data.collision_radius if data != null else 16.0) * 1.25
		fx.setup_shield_shatter(global_position, rad, is_mono, impact_dir)
	if AudioManager != null:
		AudioManager.play_sfx(&"shield_shatter", -4.5, 0.06, global_position, true)


func apply_adrenal_surge(duration: float, speed_bonus: float, attack_speed_bonus: float) -> void:
	if is_dead or duration <= 0.0:
		return
	if status_effect_component != null:
		status_effect_component.call("apply_adrenal_surge", duration, speed_bonus, attack_speed_bonus)
	_sync_nav_max_speed()
	queue_redraw()
	status_changed.emit(self)


func apply_slow_debuff(duration: float, move_penalty: float, attack_penalty: float) -> void:
	if is_dead or duration <= 0.0:
		return
	if status_effect_component != null:
		status_effect_component.call("apply_slow_debuff", duration, move_penalty, attack_penalty)
	_sync_nav_max_speed()
	queue_redraw()
	status_changed.emit(self)


func has_status_effect(effect_id: StringName) -> bool:
	return status_effect_component != null and bool(status_effect_component.call("has_effect", effect_id))


func apply_status_effect(effect_id: StringName, config: Dictionary) -> void:
	if is_dead or status_effect_component == null:
		return
	status_effect_component.call("apply_effect", effect_id, config)
	_sync_nav_max_speed()
	queue_redraw()
	status_changed.emit(self)


func add_unit_tag(tag: StringName, duration: float = -1.0) -> void:
	if is_dead or status_effect_component == null:
		return
	status_effect_component.call("add_tag", tag, duration)
	status_changed.emit(self)


func remove_unit_tag(tag: StringName) -> void:
	if status_effect_component == null:
		return
	status_effect_component.call("remove_tag", tag)
	status_changed.emit(self)


func has_unit_tag(tag: StringName) -> bool:
	if tag == &"":
		return false
	if data != null and data.unit_tags.has(tag):
		return true
	return status_effect_component != null and bool(status_effect_component.call("has_tag", tag))


func add_damage_shield(amount: float, duration: float = -1.0, label: String = "Barrier") -> void:
	if is_dead or status_effect_component == null:
		return
	status_effect_component.call("add_damage_shield", amount, duration, label)
	queue_redraw()
	status_changed.emit(self)


func get_shield_amount() -> float:
	return float(status_effect_component.call("get_shield_amount")) if status_effect_component != null else 0.0


func get_active_status_effects() -> Array[Dictionary]:
	if status_effect_component != null:
		return status_effect_component.call("get_active_effects_summary") as Array[Dictionary]
	return []


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
	if status_effect_component != null:
		spd *= float(status_effect_component.call("get_move_speed_multiplier"))
	return spd


func get_effective_attack_damage() -> float:
	if data == null:
		return 0.0
	var dmg: float = data.deployed_attack_damage if (is_deployed() and data.deployed_attack_damage > 0.0) else data.attack_damage
	if dmg > 0.0 and (data.unit_type_id == &"rail_sentinel" or data.unit_type_id == &"anvil_siege_walker"):
		var econ: EconomyManager = _get_economy_manager()
		if econ != null:
			dmg *= econ.get_rail_damage_multiplier(int(team))
	return dmg


func get_effective_attack_range() -> float:
	if data == null:
		return 0.0
	var rng: float = data.deployed_attack_range if (is_deployed() and data.deployed_attack_range > 0.0) else data.attack_range
	if rng > 0.0 and (data.unit_type_id == &"rail_sentinel" or data.unit_type_id == &"anvil_siege_walker"):
		var econ: EconomyManager = _get_economy_manager()
		if econ != null:
			rng += econ.get_rail_range_bonus(int(team))
	if rng > 0.0 and status_effect_component != null:
		rng += float(status_effect_component.call("get_bonus_attack_range"))
	return rng


func get_effective_beam_ramp_speed_multiplier() -> float:
	if status_effect_component != null:
		return float(status_effect_component.call("get_beam_ramp_speed_multiplier"))
	return 1.0


func get_optical_tether_stacks() -> int:
	if status_effect_component != null:
		return int(status_effect_component.call("get_optical_tether_stacks"))
	return 0


func get_effective_min_attack_range() -> float:
	if data == null:
		return 0.0
	if is_deployed() and data.deployed_min_attack_range > 0.0:
		return data.deployed_min_attack_range
	return data.min_attack_range


func get_effective_aoe_radius() -> float:
	if data == null:
		return 0.0
	if is_deployed() and data.deployed_aoe_radius > 0.0:
		return data.deployed_aoe_radius
	return data.aoe_attack_radius


func get_effective_weapon_tracer_style() -> StringName:
	if data == null:
		return &"pulse"
	if is_deployed() and data.deployed_weapon_tracer_style != &"":
		return data.deployed_weapon_tracer_style
	return data.weapon_tracer_style


func get_effective_aggro_range() -> float:
	if data == null:
		return 280.0
	return maxf(data.aggro_range, get_effective_attack_range())


func get_effective_attack_cooldown() -> float:
	if data == null:
		return 1.0
	var base_cd: float = data.deployed_attack_cooldown if (is_deployed() and data.deployed_attack_cooldown > 0.0) else data.attack_cooldown
	if base_cd <= 0.0:
		return 1.0
	var rate_mult: float = float(status_effect_component.call("get_attack_speed_multiplier")) if status_effect_component != null else 1.0
	return base_cd / maxf(0.25, rate_mult)


func get_effective_damage_reduction() -> float:
	if data == null:
		return 0.0
	var dr: float = maxf(0.0, data.damage_reduction)
	var econ: EconomyManager = _get_economy_manager()
	if econ != null:
		dr += econ.get_bonus_armor(int(team))
		if data.unit_type_id == &"goliath_frame":
			dr += econ.get_goliath_extra_damage_reduction(team)
	if is_deployed() and data.deployed_damage_reduction_bonus > 0.0:
		dr += data.deployed_damage_reduction_bonus
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
	var eff_atk_range: float = get_effective_attack_range()
	var eff_min_range: float = get_effective_min_attack_range()
	var eff_aoe: float = get_effective_aoe_radius()
	# Selected unit attack-range & min-range tactical previews
	if is_selected and is_deployed() and eff_atk_range > 0.0 and data != null:
		var dep_r: float = eff_atk_range + data.collision_radius
		var dep_col: Color = Color(1.0, 0.68, 0.18, 0.42) if team == Team.PLAYER else Color(1.0, 0.38, 0.28, 0.34)
		_draw_dashed_ring(Vector2.ZERO, dep_r, dep_col, 1.6, 48 if dep_r > 260.0 else 36)
		if eff_min_range > 0.0:
			var dep_min_r: float = eff_min_range + data.collision_radius
			draw_circle(Vector2.ZERO, dep_min_r, Color(1.0, 0.28, 0.24, 0.05))
			_draw_dashed_ring(Vector2.ZERO, dep_min_r, Color(1.0, 0.36, 0.28, 0.44), 1.4, 20)
	elif _should_draw_attack_range():
		var atk_r: float = eff_atk_range + data.collision_radius
		var is_siege: bool = eff_min_range > 0.0 or eff_aoe > 0.0
		var range_col: Color = (Color(0.46, 1.0, 0.56, 0.34) if is_siege else Color(0.32, 0.94, 0.96, 0.24)) if team == Team.PLAYER else Color(1.0, 0.38, 0.28, 0.26)
		_draw_dashed_ring(Vector2.ZERO, atk_r, range_col, 1.5 if is_siege else 1.2, 40 if atk_r > 220.0 else 28)
		if eff_min_range > 0.0:
			var min_r: float = eff_min_range + data.collision_radius
			draw_circle(Vector2.ZERO, min_r, Color(1.0, 0.28, 0.24, 0.05))
			_draw_dashed_ring(Vector2.ZERO, min_r, Color(1.0, 0.36, 0.28, 0.44), 1.4, 20)

	# Deploy / Anchor 4 corner stabilizer clamps when anchored
	if is_deployed():
		var clamp_r: float = (data.collision_radius if data != null else 16.0) + 4.0
		var amber_pin: Color = Color(1.0, 0.624, 0.110, 0.96)
		var steel_pad: Color = Color(0.18, 0.24, 0.30, 0.95)
		var trim_col: Color = Color(0.62, 0.72, 0.80, 0.92)
		for ci: int in range(4):
			var c_ang: float = PI * 0.25 + float(ci) * (PI * 0.5)
			var c_dir: Vector2 = Vector2.RIGHT.rotated(c_ang)
			var perp: Vector2 = Vector2(-c_dir.y, c_dir.x)
			var p_in: Vector2 = c_dir * (clamp_r - 5.5)
			var p_out: Vector2 = c_dir * (clamp_r + 3.5)
			draw_line(p_in, p_out, trim_col, 3.0, true)
			var pad_pts: PackedVector2Array = PackedVector2Array([
				p_out + perp * -3.5 - c_dir * 2.0,
				p_out + perp * 3.5 - c_dir * 2.0,
				p_out + perp * 4.2 + c_dir * 2.2,
				p_out + perp * -4.2 + c_dir * 2.2,
			])
			draw_colored_polygon(pad_pts, steel_pad)
			draw_polyline(pad_pts + PackedVector2Array([pad_pts[0]]), amber_pin, 1.2, true)
			draw_circle(p_out, 1.6, amber_pin)

	# Shield-hit flash ripple ring
	if _shield_hit_flash_timer > 0.0:
		var sf: float = clampf(_shield_hit_flash_timer / SHIELD_HIT_FLASH_DURATION, 0.0, 1.0)
		var sr: float = (data.collision_radius if data != null else 16.0) + 3.5 + (1.0 - sf) * 4.5
		draw_circle(Vector2.ZERO, sr * 0.92, Color(0.220, 0.741, 0.973, sf * 0.18))
		draw_arc(Vector2.ZERO, sr, 0.0, TAU, 24, Color(0.220, 0.741, 0.973, sf * 0.92), 2.2, true)

	# PRISMA_DEI Radiant Mark golden amplification halo (+15% dmg taken) & Blinding Glare ring
	if has_status_effect(&"radiant_mark"):
		var rm_r: float = (data.collision_radius if data != null else 16.0) + 6.5
		var gold_mark: Color = Color(0.98, 0.80, 0.14, 0.92)
		draw_arc(Vector2.ZERO, rm_r, 0.0, TAU, 24, gold_mark, 1.8, true)
		for ri: int in range(4):
			var ra: float = float(ri) * (PI * 0.5)
			var rd: Vector2 = Vector2.RIGHT.rotated(ra)
			draw_line(rd * (rm_r - 3.5), rd * (rm_r + 4.5), Color(1.0, 0.96, 0.72, 0.96), 1.8, true)
	if has_status_effect(&"blinding_glare"):
		var bg_r: float = (data.collision_radius if data != null else 16.0) + 4.0
		draw_arc(Vector2.ZERO, bg_r, 0.0, TAU, 20, Color(0.94, 0.36, 0.96, 0.72), 1.6, true)

	# Rail-Lance targeting lock-line telegraph during attack windup
	if combat_component != null and combat_component.is_in_windup() and get_effective_weapon_tracer_style() == &"rail_lance":
		var lock_tgt: Node2D = combat_component.get_windup_target()
		if lock_tgt != null and is_instance_valid(lock_tgt):
			var lock_p: float = combat_component.get_windup_progress(self)
			var muzzle_local: Vector2 = Vector2.RIGHT.rotated(body_visual.rotation) * ((data.collision_radius if data != null else 16.0) + 2.0)
			var tgt_local: Vector2 = to_local(lock_tgt.global_position)
			var lock_col: Color = Color(1.0, 0.624, 0.110, 0.35 + lock_p * 0.60)
			draw_line(muzzle_local, tgt_local, lock_col, 1.0 + lock_p * 1.1, true)
			draw_line(muzzle_local, tgt_local, Color(1.0, 0.96, 0.86, 0.25 + lock_p * 0.55), 0.7, true)
			draw_arc(tgt_local, lerpf(16.0, 6.0, lock_p), 0.0, TAU, 16, lock_col, 1.3, true)

	# Deploy / Undeploy transition progress bar
	if is_deploy_transitioning():
		var d_prog: float = get_deploy_progress()
		var d_w: float = HEALTH_BAR_WIDTH
		var d_h: float = 4.0
		var base_bar_y: float = health_bar_root.position.y if health_bar_root != null else -((data.collision_radius if data != null else 16.0) + 14.0)
		var d_y: float = base_bar_y - (12.0 if max_shield > 0.0 else 7.0)
		var d_pos: Vector2 = Vector2(-d_w * 0.5, d_y)
		draw_rect(Rect2(d_pos - Vector2(1.0, 1.0), Vector2(d_w + 2.0, d_h + 2.0)), Color(0.04, 0.06, 0.10, 0.92), true)
		draw_rect(Rect2(d_pos, Vector2(d_w * d_prog, d_h)), Color(1.0, 0.624, 0.110, 0.96), true)

	# Elevated ground shadow for Colossus Stride units
	if data != null and data.ignore_friendly_unit_collision:
		draw_circle(Vector2(5.0, 11.0), 17.5, Color(0.02, 0.04, 0.06, 0.42))
		draw_arc(Vector2(5.0, 11.0), 17.5, 0.0, TAU, 24, Color(0.28, 0.92, 1.0, 0.22) if team == Team.PLAYER else Color(1.0, 0.36, 0.26, 0.22), 1.2, true)

	# Speed-dart motion trail for fast flanker units
	if data != null and data.has_tag(&"flanker") and _trail_points.size() >= 2:
		var trail_base: Color = Color(0.98, 0.80, 0.24, 1.0) if team == Team.PLAYER else Color(1.0, 0.46, 0.24, 1.0)
		for i: int in range(1, _trail_points.size()):
			var t: float = float(i) / float(_trail_points.size())
			var p0: Vector2 = to_local(_trail_points[i - 1])
			var p1: Vector2 = to_local(_trail_points[i])
			draw_line(p0, p1, Color(trail_base.r, trail_base.g, trail_base.b, t * 0.45), 1.4 + t * 2.2, true)

	var r: float = (data.collision_radius + 6.0) if data != null else 22.0
	if has_status_effect(&"adrenal_surge"):
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
	if has_status_effect(&"static_slow"):
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
	if has_status_effect(&"grav_pulse"):
		# Heavy amber/violet gravity compression chevrons & ring
		var g_spin: float = -_vfx_anim_time * 3.2
		var g_pulse: float = 0.72 + 0.28 * sin(_vfx_anim_time * 12.0)
		draw_circle(Vector2.ZERO, r * 0.86, Color(0.72, 0.36, 0.96, 0.14 * g_pulse))
		draw_arc(Vector2.ZERO, r + 2.0, 0.0, TAU, 24, Color(1.0, 0.624, 0.110, 0.72 * g_pulse), 1.8, true)
		for gi: int in range(4):
			var ga: float = g_spin + float(gi) * (PI * 0.5)
			var g_dir: Vector2 = Vector2.RIGHT.rotated(ga)
			draw_line(g_dir * (r + 6.0), g_dir * (r + 1.0), Color(0.84, 0.52, 1.0, 0.90 * g_pulse), 2.0, true)

	# Diegetic Defensive Stance anchor leash ring (when selected) + crisp shield/anchor pip
	if stance == Stance.DEFENSIVE:
		var def_col: Color = Color(0.24, 0.96, 0.78, 0.92)
		if is_selected:
			var local_anchor: Vector2 = to_local(defensive_anchor)
			_draw_dashed_ring(local_anchor, DEFENSIVE_LEASH_RADIUS, Color(0.24, 0.96, 0.78, 0.24), 1.3, 36)
			draw_arc(local_anchor, 7.0, 0.0, TAU, 16, Color(0.24, 0.96, 0.78, 0.56), 1.3, true)
			draw_circle(local_anchor, 2.5, Color(0.24, 0.96, 0.78, 0.75))
			if local_anchor.length_squared() > 144.0:
				draw_line(Vector2.ZERO, local_anchor, Color(0.24, 0.96, 0.78, 0.22), 1.1, true)
		var pip_y: float = health_bar_root.position.y + 1.0 if health_bar_root != null else -(r + 8.0)
		var pip_x: float = (HEALTH_BAR_WIDTH * 0.5 + 8.0)
		var shield_pts: PackedVector2Array = PackedVector2Array([
			Vector2(pip_x - 3.6, pip_y - 3.8),
			Vector2(pip_x + 3.6, pip_y - 3.8),
			Vector2(pip_x + 3.6, pip_y + 0.4),
			Vector2(pip_x, pip_y + 4.4),
			Vector2(pip_x - 3.6, pip_y + 0.4),
		])
		draw_colored_polygon(shield_pts, Color(0.06, 0.20, 0.22, 0.88))
		draw_polyline(shield_pts + PackedVector2Array([shield_pts[0]]), def_col, 1.4, true)

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
	if gather_component != null:
		gather_component.cancel(self, true)
	_cancel_active_tasks(false)
	command_state = CommandState.IDLE
	current_target = null
	stop_component_navigation()
	velocity = Vector2.ZERO
	set_selected(false)
	if SpatialGrid != null:
		SpatialGrid.unregister_unit(self)
	_unregister_from_economy()
	if data != null and (data.salvage_silica > 0 or data.salvage_compute > 0) and get_parent() != null:
		var salvage_scene: PackedScene = load(SALVAGE_CORE_SCENE_PATH) as PackedScene
		if salvage_scene != null:
			var core: Node2D = salvage_scene.instantiate() as Node2D
			if core != null:
				core.global_position = global_position
				get_parent().add_child(core)
				if core.has_method("configure_payload"):
					core.call("configure_payload", data.salvage_silica, data.salvage_compute, data.display_name)
	var is_heavy: bool = data != null and data.is_heavy_unit()
	var burst_r: float = (data.collision_radius * 1.15) if data != null else 18.0
	var burst_col: Color = TeamManager.get_team_color(int(team)) if TeamManager != null else (Color(0.34, 0.98, 0.88, 1.0) if team == Team.PLAYER else Color(1.0, 0.42, 0.28, 1.0))
	if data != null and team == Team.PLAYER and (data.has_tag(&"artillery") or data.has_tag(&"anti_armor")):
		burst_col = data.weapon_tracer_color
	if is_heavy and is_inside_tree():
		var scars: Node = get_tree().get_first_node_in_group("battle_scars")
		if scars != null and scars.has_method("add_scar"):
			scars.call("add_scar", &"wreck_splatter", global_position, maxf(24.0, burst_r * 1.15), burst_col)
	var viewer_t: int = TeamManager.get_local_human_team() if TeamManager != null else int(Team.PLAYER)
	var is_friendly_view: bool = viewer_t < 0 or (TeamManager.are_allies(viewer_t, int(team)) if TeamManager != null else (team == Team.PLAYER))
	if get_parent() != null and (is_friendly_view or visible):
		var fx: CombatVFX = VFXPool.acquire_combat_vfx(53) if VFXPool != null else null
		if fx == null:
			fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
			fx.z_index = 53
			get_parent().add_child(fx)
		fx.setup_death_burst(global_position, burst_r, burst_col, is_heavy)
		if is_heavy and is_inside_tree():
			var cam_die: Node = get_tree().get_first_node_in_group("rts_camera")
			if cam_die != null and cam_die.has_method("add_camera_shake"):
				cam_die.call("add_camera_shake", 2.4, 0.13, global_position)
	if AudioManager != null and (is_friendly_view or visible):
		AudioManager.play_explosion_sfx(global_position, -4.5 if is_heavy else -6.0, is_heavy)
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
		combat_component.tick_beam_decay(self, delta)
	if ability_component != null:
		ability_component.tick_cooldowns(delta)
		ability_component.tick_autocast(self, delta)
	if repair_component != null:
		repair_component.call("tick_auto_repair", self, delta)
	_tick_status_effects(delta)
	_tick_shield_regen(delta)
	_tick_deploy_transition(delta)

	if _recoil_offset > 0.0 or (body_visual != null and body_visual.position != Vector2.ZERO):
		_recoil_offset = move_toward(_recoil_offset, 0.0, _recoil_decay_rate * delta)
		if body_visual != null:
			if _recoil_offset > 0.01:
				body_visual.position = Vector2(-cos(body_visual.rotation), -sin(body_visual.rotation)) * _recoil_offset
			else:
				body_visual.position = Vector2.ZERO

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _hit_flash_timer <= 0.0 and _shield_hit_flash_timer <= 0.0:
			body_visual.modulate = Color.WHITE

	if _shield_hit_flash_timer > 0.0:
		_shield_hit_flash_timer = maxf(0.0, _shield_hit_flash_timer - delta)
		queue_redraw()
		if _shield_hit_flash_timer <= 0.0 and _hit_flash_timer <= 0.0:
			body_visual.modulate = Color.WHITE

	if spawn_anim_timer > 0.0:
		spawn_anim_timer = maxf(0.0, spawn_anim_timer - delta)
		if body_visual != null:
			if spawn_anim_timer <= 0.0:
				body_visual.scale = Vector2.ONE
			else:
				var u_spawn: float = clampf(1.0 - (spawn_anim_timer / SPAWN_ANIM_DURATION), 0.0, 1.0)
				var ease_out: float = 1.0 - pow(1.0 - u_spawn, 3.0)
				var s_val: float = lerpf(0.72, 1.0, ease_out)
				body_visual.scale = Vector2(s_val, s_val)

	if data != null and data.has_tag(&"flanker"):
		_update_stinger_trail(delta)

	if not _can_move() and not _can_attack():
		velocity = Vector2.ZERO
		return

	if movement_component != null:
		movement_component.call("begin_frame")

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
		CommandState.REPAIRING:
			_process_repairing(delta)
		CommandState.SALVAGING:
			_process_salvaging(delta)

	if movement_component != null:
		movement_component.call("finish_physics_step", self, delta)

	var in_rail_windup: bool = combat_component != null and combat_component.is_in_windup() and get_effective_weapon_tracer_style() == &"rail_lance"
	if in_rail_windup or _was_in_rail_windup:
		_was_in_rail_windup = in_rail_windup
		queue_redraw()


func _on_nav_velocity_computed(safe_velocity: Vector2) -> void:
	if movement_component != null:
		movement_component.call("on_nav_velocity_computed", self, safe_velocity, _last_delta)


func _tick_status_effects(delta: float) -> void:
	if status_effect_component == null:
		return
	var had_any: bool = bool(status_effect_component.call("has_any_active"))
	var changed: bool = bool(status_effect_component.call("tick", delta, self))
	if had_any:
		_vfx_anim_time += delta
		queue_redraw()
	if changed:
		_sync_nav_max_speed()
		queue_redraw()
		status_changed.emit(self)


func _tick_shield_regen(delta: float) -> void:
	if max_shield <= 0.0 or current_shield >= max_shield:
		return
	if _shield_regen_timer > 0.0:
		_shield_aura_poll_timer -= delta
		if _shield_aura_poll_timer <= 0.0:
			_shield_aura_poll_timer = 0.25
			_cached_shield_delay_speedup = Building.get_shield_regen_delay_speedup_at(get_tree(), global_position, int(team)) if is_inside_tree() else 0.0
		_shield_regen_timer = maxf(0.0, _shield_regen_timer - delta * (1.0 + _cached_shield_delay_speedup))
		return
	var base_rate: float = data.shield_regen_rate if data != null else 0.0
	if base_rate <= 0.0:
		return
	var econ: EconomyManager = _get_economy_manager()
	var rate_mult: float = econ.get_shield_regen_rate_multiplier(int(team)) if econ != null else 1.0
	var next_shd: float = minf(max_shield, current_shield + base_rate * rate_mult * delta)
	if is_equal_approx(next_shd, current_shield):
		return
	current_shield = next_shd
	_update_health_bar()
	var shd_int: int = int(round(current_shield))
	if shd_int != _last_emitted_shield_int or current_shield >= max_shield:
		_last_emitted_shield_int = shd_int
		shield_changed.emit(self, current_shield, max_shield)
		status_changed.emit(self)


func _tick_deploy_transition(delta: float) -> void:
	if not is_deploy_transitioning():
		return
	velocity = Vector2.ZERO
	_deploy_timer = maxf(0.0, _deploy_timer - delta)
	queue_redraw()
	if _deploy_timer <= 0.0:
		if deploy_state == DeployState.DEPLOYING:
			deploy_state = DeployState.DEPLOYED
			_trigger_deploy_anchor_impact()
		elif deploy_state == DeployState.UNDEPLOYING:
			deploy_state = DeployState.MOBILE
		if _entity_visuals != null and is_instance_valid(_entity_visuals):
			_entity_visuals.queue_redraw()
		queue_redraw()
		deploy_state_changed.emit(self, deploy_state)
		status_changed.emit(self)


func _trigger_deploy_anchor_impact() -> void:
	if not is_inside_tree():
		return
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_friendly_view: bool = viewer < 0 or (TeamManager.are_allies(viewer, int(team)) if TeamManager != null else (team == Team.PLAYER))
	if not is_friendly_view and not visible:
		return
	var host: Node = get_parent()
	if host != null:
		var fx: CombatVFX = VFXPool.acquire_combat_vfx(52) if VFXPool != null else null
		if fx == null:
			fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
			fx.z_index = 52
			host.add_child(fx)
		var rad: float = (data.collision_radius if data != null else 22.0) * 1.45
		fx.setup_anchor_thud(global_position, rad, Color(1.0, 0.624, 0.110, 1.0))
	if AudioManager != null:
		AudioManager.play_sfx(&"deploy_anchor_lock", -3.0, 0.04, global_position, true)
	var cam: Node = get_tree().get_first_node_in_group("rts_camera")
	if cam != null and cam.has_method("add_camera_shake"):
		cam.call("add_camera_shake", 1.6, 0.10, global_position)


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
	if stance == Stance.DEFENSIVE:
		_process_defensive_stance(delta)
		return
	if not _can_attack() or combat_component == null:
		return

	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	# When Aggro AI is toggled OFF, idle/guard units do not passively acquire or chase targets.
	if not MatchManager.is_aggro_ai_enabled(get_tree()):
		current_target = null
		return

	var eff_atk_r: float = get_effective_attack_range()
	var eff_aggro_r: float = get_effective_aggro_range()

	# Aggressive combat units acquire enemies inside aggro_range and pursue within leash range.
	if combat_component.should_pursue_targets(self) and _can_move():
		var leash: float = maxf(eff_aggro_r, eff_atk_r) * 1.35
		if current_target == null or not combat_component.is_valid_target_in_range(self, current_target, leash):
			current_target = combat_component.find_nearest_enemy(self, eff_aggro_r)
		else:
			_maybe_retarget_higher_threat(delta, eff_atk_r)
		if current_target != null and is_instance_valid(current_target):
			if combat_component.is_within_attack_envelope(self, current_target):
				_face_point(current_target.global_position, delta)
				combat_component.process_attack_at(self, current_target, delta)
			elif combat_component.is_target_inside_min_range(self, current_target):
				combat_component.cancel_attack_animation()
				current_target = combat_component.find_nearest_enemy(self, eff_aggro_r)
			else:
				combat_component.cancel_attack_animation()
				_request_nav_toward_point(current_target.global_position, 8.0)
		return

	if current_target == null or not combat_component.is_within_attack_envelope(self, current_target):
		current_target = combat_component.find_nearest_enemy(self, eff_atk_r)
	else:
		_maybe_retarget_higher_threat(delta, eff_atk_r)
	if current_target != null and is_instance_valid(current_target):
		_face_point(current_target.global_position, delta)
		combat_component.process_attack_at(self, current_target, delta)


func _process_defensive_stance(delta: float) -> void:
	if is_selected and velocity.length_squared() > 4.0:
		queue_redraw()
	if not _can_attack() or combat_component == null or not MatchManager.is_aggro_ai_enabled(get_tree()):
		current_target = null
		_return_to_defensive_anchor()
		return

	var dist_from_anchor: float = global_position.distance_to(defensive_anchor)
	var attack_r: float = get_effective_attack_range()
	var scan_r: float = get_effective_aggro_range()
	var max_target_anchor_dist: float = DEFENSIVE_LEASH_RADIUS + attack_r + 24.0

	if current_target != null:
		if not is_instance_valid(current_target) or not combat_component.is_valid_target(self, current_target):
			current_target = null
		elif dist_from_anchor > DEFENSIVE_LEASH_RADIUS + 8.0:
			combat_component.cancel_attack_animation()
			current_target = null
		elif defensive_anchor.distance_to(current_target.global_position) > max_target_anchor_dist and not combat_component.is_within_attack_envelope(self, current_target):
			combat_component.cancel_attack_animation()
			current_target = null

	if current_target == null:
		if dist_from_anchor <= DEFENSIVE_LEASH_RADIUS:
			var candidate: Node2D = combat_component.find_nearest_enemy(self, scan_r)
			if candidate != null and is_instance_valid(candidate):
				if combat_component.is_within_attack_envelope(self, candidate) or defensive_anchor.distance_to(candidate.global_position) <= max_target_anchor_dist:
					current_target = candidate
	else:
		_maybe_retarget_higher_threat(delta, attack_r)

	if current_target != null and is_instance_valid(current_target):
		if combat_component.is_within_attack_envelope(self, current_target):
			_face_point(current_target.global_position, delta)
			combat_component.process_attack_at(self, current_target, delta)
			return
		if combat_component.is_target_inside_min_range(self, current_target):
			combat_component.cancel_attack_animation()
			current_target = null
		elif _can_move() and combat_component.should_pursue_targets(self) and dist_from_anchor < DEFENSIVE_LEASH_RADIUS - 6.0:
			combat_component.cancel_attack_animation()
			_request_nav_toward_point(current_target.global_position, 8.0)
			return
		else:
			combat_component.cancel_attack_animation()
			current_target = null

	_return_to_defensive_anchor()


func _return_to_defensive_anchor() -> void:
	if not _can_move():
		velocity = Vector2.ZERO
		return
	var dist_sq: float = global_position.distance_squared_to(defensive_anchor)
	if dist_sq > 18.0 * 18.0:
		_request_nav_toward_point(defensive_anchor, 8.0, 10.0)
		if is_selected:
			queue_redraw()
	else:
		stop_component_navigation()
		velocity = Vector2.ZERO


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
		var eff_atk_am: float = get_effective_attack_range()
		var eff_aggro_am: float = get_effective_aggro_range()
		var leash_range: float = maxf(eff_aggro_am, eff_atk_am) * 1.25
		if current_target != null and not combat_component.is_valid_target_in_range(self, current_target, leash_range):
			current_target = null
		if current_target == null:
			current_target = combat_component.find_nearest_enemy(self, eff_aggro_am)
		else:
			_maybe_retarget_higher_threat(delta, eff_atk_am)

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
	var last_t: Vector2 = (movement_component.get("last_nav_target") as Vector2) if movement_component != null else Vector2.INF
	if last_t == Vector2.INF or last_t.distance_squared_to(_attack_move_destination) > 1.0:
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
	elif is_deployed():
		_face_point(current_target.global_position, delta)


func _process_hold_position(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _can_attack() or combat_component == null:
		return
	if current_target != null and not is_instance_valid(current_target):
		current_target = null
	var eff_atk_r: float = get_effective_attack_range()
	if current_target == null or not combat_component.is_within_attack_envelope(self, current_target):
		current_target = combat_component.find_nearest_enemy(self, eff_atk_r)
	else:
		_maybe_retarget_higher_threat(delta, eff_atk_r)
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


func _process_repairing(delta: float) -> void:
	if repair_component == null or not bool(repair_component.call("is_active")):
		_advance_command_queue()
		return
	repair_component.call("tick", self, delta)


func _process_salvaging(delta: float) -> void:
	if _salvage_target == null or not is_instance_valid(_salvage_target) or bool(_salvage_target.get("is_claimed")) or _salvage_target.is_queued_for_deletion():
		_salvage_target = null
		_is_salvaging_in_place = false
		stop_component_navigation()
		if gather_bar_root != null:
			gather_bar_root.visible = false
		_advance_command_queue()
		return

	var unit_r: float = data.collision_radius if data != null else 13.0
	var core_r: float = float(_salvage_target.get("interaction_radius")) if _salvage_target.get("interaction_radius") != null else 22.0
	var reach: float = core_r + unit_r + 32.0
	var dist: float = global_position.distance_to(_salvage_target.global_position)
	if dist <= reach:
		_is_salvaging_in_place = true
		stop_component_navigation()
		_face_point(_salvage_target.global_position, delta)
		var completed: bool = bool(_salvage_target.call("advance_extraction", self, delta))
		if gather_bar_root != null and gather_bar_fill != null:
			var prog: float = float(_salvage_target.get("extraction_progress")) if is_instance_valid(_salvage_target) else 1.0
			gather_bar_root.visible = not completed
			gather_bar_fill.size.x = GATHER_BAR_WIDTH * clampf(prog, 0.0, 1.0)
		_salvage_vfx_timer -= delta
		if _salvage_vfx_timer <= 0.0 and get_parent() != null and visible and is_instance_valid(_salvage_target):
			_salvage_vfx_timer = 0.18
			var fx: CombatVFX = VFXPool.acquire_combat_vfx(53) if VFXPool != null else null
			if fx == null:
				fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
				fx.z_index = 53
				get_parent().add_child(fx)
			fx.setup_repair_beam(global_position, _salvage_target.global_position, Color(1.0, 0.80, 0.30, 0.96))
		if completed:
			_salvage_target = null
			_is_salvaging_in_place = false
			if gather_bar_root != null:
				gather_bar_root.visible = false
			_advance_command_queue()
		return

	_is_salvaging_in_place = false
	var approach: Vector2 = get_or_compute_approach_point(_salvage_target, core_r, 6.0, null, null)
	request_component_navigation(approach, 10.0, 4.0)


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
		var eff_atk_p: float = get_effective_attack_range()
		var eff_aggro_p: float = get_effective_aggro_range()
		var leash_range: float = maxf(eff_aggro_p, eff_atk_p) * 1.25
		if current_target != null and not combat_component.is_valid_target_in_range(self, current_target, leash_range):
			current_target = null
		if current_target == null:
			current_target = combat_component.find_nearest_enemy(self, eff_aggro_p)
		else:
			_maybe_retarget_higher_threat(delta, eff_atk_p)
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
	var last_p: Vector2 = (movement_component.get("last_nav_target") as Vector2) if movement_component != null else Vector2.INF
	if last_p == Vector2.INF or last_p.distance_squared_to(dest) > 1.0:
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
		gather_component.cancel(self, false)
	if staff_component != null:
		staff_component.cancel()
	if repair_component != null:
		repair_component.call("cancel")
	patrol_waypoints.clear()
	patrol_index = 0
	if _construction_target != null:
		_construction_target = null
		if gather_bar_root != null:
			gather_bar_root.visible = false
	if _salvage_target != null or _is_salvaging_in_place:
		_salvage_target = null
		_is_salvaging_in_place = false
		if gather_bar_root != null:
			gather_bar_root.visible = false


func _try_start_auto_gather() -> void:
	if is_dead or is_staffed or not can_gather() or not is_inside_tree():
		return
	if command_state != CommandState.IDLE:
		return
	var target_type: StringName = data.allowed_resource if data.allowed_resource != &"" else &"silica"
	var best: ResourceNode = ResourceNode.pick_best_cluster_node_from_pos(
		get_tree(),
		global_position,
		target_type,
		self,
		int(team),
		520.0,
		2400.0
	)
	if best != null:
		best.assign_worker(self)
		command_gather(best)


func _request_nav_toward_point(target_point: Vector2, repath_threshold: float, stop_distance: float = 0.0) -> void:
	if movement_component != null:
		movement_component.call("request_nav_toward_point", self, target_point, repath_threshold, stop_distance)


func _compute_nav_desired_velocity() -> void:
	if movement_component != null:
		movement_component.call("compute_nav_desired_velocity", self)


func _reset_progress_tracker() -> void:
	if movement_component != null:
		movement_component.call("reset_progress_tracker", self)


func _should_settle_at_destination(goal_pos: Vector2, delta: float) -> bool:
	if movement_component != null:
		return bool(movement_component.call("should_settle_at_destination", self, goal_pos, delta))
	return true


func _face_point(world_point: Vector2, delta: float) -> void:
	if movement_component != null:
		movement_component.call("face_point", self, world_point, delta)


func _set_nav_target(target_pos: Vector2) -> void:
	if movement_component != null:
		movement_component.call("set_nav_target", self, target_pos)


func _clear_nav_target() -> void:
	if movement_component != null:
		movement_component.call("clear_nav_target", self)


func _is_nav_map_ready() -> bool:
	return movement_component != null and bool(movement_component.call("is_nav_map_ready", self))


func _can_move() -> bool:
	return nav_agent != null and data != null and data.move_speed > 0.0 and not is_movement_locked_by_deploy()


func _can_attack() -> bool:
	return combat_component != null and combat_component.can_attack(self)


func _ensure_shield_bar_nodes() -> void:
	if health_bar_root == null or _shield_bar_bg != null:
		return
	_shield_bar_bg = ColorRect.new()
	_shield_bar_bg.name = "ShieldBg"
	_shield_bar_bg.offset_left = -1.0
	_shield_bar_bg.offset_top = -6.0
	_shield_bar_bg.offset_right = HEALTH_BAR_WIDTH + 1.0
	_shield_bar_bg.offset_bottom = -1.0
	_shield_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_bar_bg.color = Color(0.04, 0.07, 0.11, 0.88)
	health_bar_root.add_child(_shield_bar_bg)

	_shield_bar_fill = ColorRect.new()
	_shield_bar_fill.name = "ShieldFill"
	_shield_bar_fill.offset_left = 0.0
	_shield_bar_fill.offset_top = -5.0
	_shield_bar_fill.offset_right = HEALTH_BAR_WIDTH
	_shield_bar_fill.offset_bottom = -2.0
	_shield_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_bar_fill.color = Color(0.220, 0.741, 0.973, 1.0) # #38BDF8
	health_bar_root.add_child(_shield_bar_fill)


func _update_health_bar() -> void:
	if health_bar_root == null or health_bar_fill == null or data == null:
		return
	var max_val: float = maxf(1.0, get_max_hp())
	var ratio: float = clampf(current_hp / max_val, 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	var has_shd: bool = max_shield > 0.0
	var shield_damaged: bool = has_shd and current_shield < max_shield - 0.01
	var mode: int = SettingsManager.health_bar_mode if SettingsManager != null else 0
	if mode == 1:
		health_bar_root.visible = true
	elif mode == 2:
		health_bar_root.visible = is_selected
	else:
		health_bar_root.visible = always_show_health_bar or is_selected or ratio < 0.999 or shield_damaged

	if has_shd:
		_ensure_shield_bar_nodes()
		if _shield_bar_bg != null and _shield_bar_fill != null:
			var shd_ratio: float = clampf(current_shield / maxf(1.0, max_shield), 0.0, 1.0)
			_shield_bar_bg.visible = true
			_shield_bar_fill.visible = shd_ratio > 0.001
			_shield_bar_fill.size.x = HEALTH_BAR_WIDTH * shd_ratio
	elif _shield_bar_bg != null and _shield_bar_fill != null:
		_shield_bar_bg.visible = false
		_shield_bar_fill.visible = false


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
	if data != null and data.ignore_friendly_unit_collision:
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
	if int(team) == 0:
		return
	var type_id: StringName = get_unit_type_id()
	if type_id == &"target_dummy":
		return
	var tc: Color = TeamManager.get_team_color(int(team)) if TeamManager != null else Color(0.98, 0.34, 0.26, 1.0)
	if _entity_visuals == null and body_visual is Polygon2D:
		(body_visual as Polygon2D).color = tc.darkened(0.14)
	var core_accent: Polygon2D = body_visual.get_node_or_null("CoreAccent") as Polygon2D if body_visual != null else null
	if core_accent != null:
		core_accent.color = tc.lightened(0.18)
	if health_bar_fill != null:
		health_bar_fill.color = tc
	if selection_ring != null:
		var ring_fill: Polygon2D = selection_ring.get_node_or_null("Fill") as Polygon2D
		if ring_fill != null:
			ring_fill.color = Color(tc.r, tc.g, tc.b, 0.16)
		var ring_outline: Line2D = selection_ring.get_node_or_null("Outline") as Line2D
		if ring_outline != null:
			ring_outline.default_color = Color(tc.r, tc.g, tc.b, 0.95)


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
	if data.is_heavy_unit() and data.has_tag(&"synthetic"):
		return "Heavy Synthetic"
	if data.is_armored:
		return "Armored"
	return "Light"


func get_inspection_data() -> Dictionary:
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Team.PLAYER)
	var is_local_owned_unit: bool = TeamManager.is_team_controlled_by_local_human(int(team)) if TeamManager != null else (team == Team.PLAYER)
	var is_allied_ai: bool = (not is_local_owned_unit) and viewer_team >= 0 and TeamManager != null and TeamManager.are_allies(viewer_team, int(team))
	var is_enemy: bool = (not is_local_owned_unit) and (not is_allied_ai)
	var accent: Color = TeamManager.get_team_color(int(team)) if TeamManager != null else (Color(1.0, 0.36, 0.26, 1.0) if is_enemy else Color(0.24, 0.92, 0.88, 1.0))
	var class_tag: String = get_armor_class_label().to_upper()
	var subtitle: String = ("HOSTILE %s" % class_tag) if is_enemy else (("ALLIED %s" % class_tag) if is_allied_ai else ("FRIENDLY %s" % class_tag))

	if not is_enemy and data != null:
		if not data.role_tags_display.is_empty():
			subtitle = "%s  •  %s" % [class_tag, data.role_tags_display.to_upper()]
			if data.has_tag(&"flanker") or data.has_tag(&"scout"):
				accent = Color(0.98, 0.78, 0.24, 1.0)
			elif data.has_tag(&"anti_armor"):
				accent = Color(0.98, 0.68, 0.28, 1.0)
			elif data.has_tag(&"disruptor"):
				accent = Color(0.76, 0.56, 1.0, 1.0)
			elif data.has_tag(&"support") or data.has_tag(&"artillery"):
				accent = Color(0.38, 1.0, 0.60, 1.0)
			elif data.is_heavy_unit():
				accent = Color(0.40, 0.94, 1.0, 1.0)
			elif data.can_staff_compute:
				accent = Color(0.32, 0.82, 1.0, 1.0)
			elif data.can_gather:
				accent = Color(0.96, 0.68, 0.22, 1.0) if data.allowed_resource == &"silica" else Color(0.28, 0.94, 0.56, 1.0)
			else:
				accent = Color(0.24, 0.94, 0.82, 1.0)
		elif data.can_staff_compute:
			accent = Color(0.32, 0.82, 1.0, 1.0)
			subtitle = "%s  •  COMPUTE SPECIALIST" % class_tag
		elif data.can_gather:
			accent = Color(0.28, 0.94, 0.56, 1.0)
			subtitle = "%s  •  UTILITY WORKER" % class_tag

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
		var eff_dmg: float = get_effective_attack_damage()
		var eff_rng: float = get_effective_attack_range()
		var eff_min_rng: float = get_effective_min_attack_range()
		var eff_aoe: float = get_effective_aoe_radius()
		var dmg_str: String = "%d" % int(round(eff_dmg))
		if data.bonus_vs_armored > 0.0:
			dmg_str += " (+%d vs Armored)" % int(round(data.bonus_vs_armored))
		elif eff_aoe > 0.0:
			dmg_str += " (AoE %dpx)" % int(round(eff_aoe))
		elif data.line_pierce_width > 0.0:
			dmg_str += " (Line Pierce)"
		stats.append({"label": "Damage", "value": dmg_str})

		var range_str: String = "%d px" % int(round(eff_rng))
		if eff_min_rng > 0.0:
			range_str = "%d–%d px (Min)" % [int(round(eff_min_rng)), int(round(eff_rng))]
		stats.append({"label": "Range", "value": range_str})

		var spd_str: String = "ANCHORED" if is_deployed() else ("DEPLOYING..." if deploy_state == DeployState.DEPLOYING else ("UNDEPLOYING..." if deploy_state == DeployState.UNDEPLOYING else "%d px/s" % int(round(get_effective_move_speed()))))
		if not is_movement_locked_by_deploy():
			if has_status_effect(&"adrenal_surge"):
				spd_str += " [SURGE]"
			elif has_status_effect(&"static_slow"):
				spd_str += " [SLOW]"
		var spd_entry: Dictionary = {"label": "Speed", "value": spd_str}
		if is_movement_locked_by_deploy():
			spd_entry["color"] = Color(1.0, 0.624, 0.110, 1.0)
		stats.append(spd_entry)

		var dr: float = get_effective_damage_reduction()
		if data.heal_aura_rate > 0.0:
			stats.append({"label": "Aura", "value": "+%.0f HP/s (%dpx)" % [data.heal_aura_rate, int(round(data.heal_aura_radius))]})
		elif data.ignore_friendly_unit_collision:
			stats.append({"label": "Class", "value": "%s • Stride" % get_armor_class_label()})
		elif dr > 0.001:
			stats.append({"label": "Armor", "value": "%s (-%d%% Dmg)" % [get_armor_class_label(), int(round(dr * 100.0))]})
		elif eff_dmg > 0.0 and get_effective_attack_cooldown() > 0.0:
			stats.append({"label": "Class", "value": "%s • %.1f/s" % [get_armor_class_label(), 1.0 / get_effective_attack_cooldown()]})
		else:
			stats.append({"label": "Class", "value": get_armor_class_label()})

		if eff_dmg > 0.0 or kill_count > 0:
			if veterancy_rank > 0:
				var rank_col: Color = Color(1.0, 0.86, 0.28, 1.0) if veterancy_rank >= 3 else Color(0.46, 0.98, 1.0, 1.0)
				stats.append({
					"label": "Rank",
					"value": "%s (%d Kills)" % [get_veterancy_rank_name().to_upper(), kill_count],
					"color": rank_col,
				})
			else:
				stats.append({"label": "Kills", "value": "%d" % kill_count})

		var tether_stacks: int = get_optical_tether_stacks()
		if tether_stacks > 0:
			stats.append({
				"label": "Lattice Link",
				"value": "x%d Active" % tether_stacks,
				"color": Color(0.98, 0.80, 0.14, 1.0),
			})
		if data.tether_emit_radius > 0.0 and data.tether_max_links > 0:
			stats.append({
				"label": "Tether Anchor",
				"value": "x%d Links (%dpx)" % [data.tether_max_links, int(round(data.tether_emit_radius))],
				"color": Color(0.851, 0.275, 0.937, 1.0),
			})
		if data.is_continuous_beam and combat_component != null:
			var ramp_pct: int = int(round(combat_component.get_beam_ramp_ratio(self) * 100.0))
			if ramp_pct > 0:
				stats.append({
					"label": "Beam Charge",
					"value": "%d%% (%.1fx)" % [ramp_pct, lerpf(1.0, maxf(1.0, data.beam_ramp_max_multiplier), float(ramp_pct) * 0.01)],
					"color": Color(0.94, 0.22, 0.68, 1.0),
				})

	var is_local_controlled: bool = TeamManager.is_team_controlled_by_local_human(int(team)) if TeamManager != null else (not is_enemy)
	return {
		"title": data.display_name if data != null else name,
		"subtitle": subtitle,
		"affiliation": &"enemy" if is_enemy else &"player",
		"accent_color": accent,
		"ring_color": accent,
		"show_hp_bar": true,
		"hp_current": current_hp,
		"hp_max": max_hp_val,
		"show_shield_bar": max_shield > 0.0,
		"shield_current": current_shield,
		"shield_max": max_shield,
		"show_primary_bar": show_primary,
		"primary_bar_label": primary_label,
		"primary_bar_value": primary_val,
		"primary_bar_max": primary_max,
		"primary_bar_color": accent,
		"stats": stats,
		"is_commandable": is_local_controlled,
		"readonly_label": "SPECTATOR TELEMETRY" if (TeamManager != null and TeamManager.is_spectator_mode()) else "HOSTILE UNIT  —  READ-ONLY TELEMETRY",
	}


func _get_command_state_label() -> String:
	match command_state:
		CommandState.IDLE:
			return "Defending Post" if stance == Stance.DEFENSIVE else "Idle"
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
		CommandState.REPAIRING:
			return "Repairing"
		CommandState.SALVAGING:
			return "Extracting Salvage"
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
