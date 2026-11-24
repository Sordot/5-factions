class_name SelectionController
extends Node2D

const COMMAND_ROUTER_SCRIPT: GDScript = preload("res://scripts/controllers/command_router.gd")
const RALLY_POINT_OVERLAY_SCRIPT: GDScript = preload("res://ui/overlays/rally_point_overlay.gd")
const COMMAND_QUEUE_OVERLAY_SCRIPT: GDScript = preload("res://ui/overlays/command_queue_overlay.gd")
const DOUBLE_TAP_WINDOW_MS: int = 350

signal selection_updated(selected_count: int)
signal selection_changed(selected_units: Array[Unit], subgroups: Array[Dictionary], active_subgroup_index: int)
signal building_selection_changed(building: Building)
signal buildings_selection_changed(buildings: Array[Building])
signal inspection_changed(entity: Node)
signal control_groups_changed(summary: Dictionary)
signal ability_targeting_changed(active_ability: AbilityData)
signal patrol_targeting_changed(active: bool)
signal attack_move_targeting_changed(active: bool)
signal idle_workers_changed(idle_workers: Array[Unit])
signal idle_workers_updated(count: int)
signal army_count_updated(count: int)

@export var drag_threshold: float = 8.0
@export var camera_path: NodePath
@export var buildable_bounds: Rect2 = Rect2(-640.0, -360.0, 1280.0, 720.0)

@onready var selection_box: SelectionBox = $SelectionBox
@onready var ability_reticle: AbilityTargetingReticle = get_node_or_null("AbilityTargetingReticle") as AbilityTargetingReticle
@onready var build_ghost_preview: BuildGhostPreview = get_node_or_null("BuildGhostPreview") as BuildGhostPreview
@onready var rally_point_overlay: Node2D = get_node_or_null("RallyPointOverlay") as Node2D
@onready var command_queue_overlay: Node2D = get_node_or_null("CommandQueueOverlay") as Node2D

var command_router: CommandRouter = null
var selected_units: Array[Unit] = []
var selected_building: Building = null
var selected_buildings: Array[Building] = []
var inspected_entity: Node = null
var subgroups: Array[Dictionary] = []
var active_subgroup_index: int = 0
var inspected_enemy: Unit = null
var control_groups: Dictionary = {}
var active_targeting_ability: AbilityData = null
var is_patrol_targeting: bool = false
var is_attack_move_targeting: bool = false
var idle_worker_count: int = 0
var army_unit_count: int = 0

var _is_dragging: bool = false
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_start_screen: Vector2 = Vector2.ZERO
var _last_recall_group: int = -1
var _last_recall_time_ms: int = 0
var _last_army_select_ms: int = 0
var _last_click_unit: Unit = null
var _last_click_building: Building = null
var _last_click_time_ms: int = 0
var _last_click_building_time_ms: int = 0
var _click_was_double_click: bool = false
var _click_ctrl_pressed: bool = false
var _tracked_death_units: Array[Unit] = []
var _idle_cycle_index: int = -1
var _idle_refresh_timer: float = 0.0
var _last_idle_ids: PackedInt64Array = PackedInt64Array()
var _amove_preview_timer: float = 0.0
var _last_targeting_active: bool = false
var _command_cursors: Dictionary = {}
var _active_cursor_state: StringName = &""


func _ready() -> void:
	add_to_group("selection_controller")
	_build_command_cursors()
	command_router = get_node_or_null("CommandRouter") as CommandRouter
	if command_router == null:
		command_router = COMMAND_ROUTER_SCRIPT.new()
		command_router.name = "CommandRouter"
		add_child(command_router)
	command_router.buildable_bounds = buildable_bounds

	if rally_point_overlay == null:
		rally_point_overlay = RALLY_POINT_OVERLAY_SCRIPT.new() as Node2D
		rally_point_overlay.name = "RallyPointOverlay"
		add_child(rally_point_overlay)
	if rally_point_overlay != null and rally_point_overlay.has_method("bind_selection_controller"):
		rally_point_overlay.call("bind_selection_controller", self)

	if command_queue_overlay == null:
		command_queue_overlay = COMMAND_QUEUE_OVERLAY_SCRIPT.new() as Node2D
		command_queue_overlay.name = "CommandQueueOverlay"
		add_child(command_queue_overlay)
	if command_queue_overlay != null and command_queue_overlay.has_method("bind_selection_controller"):
		command_queue_overlay.call("bind_selection_controller", self)

	call_deferred("_refresh_idle_workers", true)


func _exit_tree() -> void:
	_clear_custom_cursor()


func _process(delta: float) -> void:
	_idle_refresh_timer += delta
	if _idle_refresh_timer >= 0.15:
		_idle_refresh_timer = 0.0
		_refresh_idle_workers(false)

	if _amove_preview_timer > 0.0:
		_amove_preview_timer = maxf(0.0, _amove_preview_timer - delta)
	var cur_targeting: bool = is_targeting_command_active()
	if cur_targeting != _last_targeting_active:
		_last_targeting_active = cur_targeting
		_redraw_selected_units()

	_update_command_cursor()

	# Drop inspection if an inspected non-local entity disappears into Fog of War.
	if inspected_entity != null and is_instance_valid(inspected_entity):
		if inspected_entity is Unit:
			var iu: Unit = inspected_entity
			var iu_local: bool = TeamManager.is_team_controlled_by_local_human(int(iu.team)) if TeamManager != null else (iu.team == Unit.Team.PLAYER)
			if not iu_local and not iu.visible:
				_set_inspected_entity(null)
		elif inspected_entity is Building:
			var ib: Building = inspected_entity
			var ib_local: bool = TeamManager.is_team_controlled_by_local_human(int(ib.team)) if TeamManager != null else (ib.team == Unit.Team.PLAYER)
			if not ib_local and not ib.visible:
				_set_inspected_entity(null)

	if active_targeting_ability == null or command_router == null:
		if ability_reticle != null:
			if is_attack_move_targeting:
				ability_reticle.set_command_mode_reticle(&"attack_move", get_global_mouse_position())
			elif is_patrol_targeting:
				ability_reticle.set_command_mode_reticle(&"patrol", get_global_mouse_position())
			else:
				ability_reticle.clear_command_mode_reticle()
		return
	var cursor_world: Vector2 = get_global_mouse_position()
	if active_targeting_ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		var builder: Unit = command_router.find_closest_builder(get_active_subgroup_units(), cursor_world)
		if builder == null or active_targeting_ability.building_to_build == null:
			cancel_ability_targeting()
			return
		if ability_reticle != null:
			ability_reticle.clear_targeting()
		if build_ghost_preview != null:
			var eval: Dictionary = command_router.evaluate_build_placement(active_targeting_ability.building_to_build, cursor_world)
			build_ghost_preview.set_preview(
				active_targeting_ability.building_to_build,
				eval["pos"],
				eval["valid"],
				eval["reason"],
				eval["vent"]
			)
		return

	if ability_reticle != null:
		var caster: Unit = SubgroupHelper.find_closest_ready_caster(
			get_active_subgroup_units(),
			active_targeting_ability,
			cursor_world
		)
		if caster != null:
			ability_reticle.set_targeting(active_targeting_ability, caster.global_position, true, cursor_world)
		else:
			cancel_ability_targeting()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cmd_cancel"):
		if active_targeting_ability != null:
			cancel_ability_targeting()
			get_viewport().set_input_as_handled()
			return
		if is_attack_move_targeting:
			cancel_attack_move_targeting()
			get_viewport().set_input_as_handled()
			return
		if is_patrol_targeting:
			cancel_patrol_targeting()
			get_viewport().set_input_as_handled()
			return
		var pause_menu: PauseMenu = get_tree().get_first_node_in_group("pause_menu") as PauseMenu
		if pause_menu != null and not pause_menu.is_settings_open() and not pause_menu.is_tech_tree_open():
			pause_menu.toggle_pause()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cycle_subgroup") and not event.is_echo():
		if subgroups.size() > 1:
			cycle_subgroup()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_select_idle_worker") and not event.is_echo():
		var allow_idle_hotkey: bool = true
		if event is InputEventKey:
			var idle_k: InputEventKey = event
			if idle_k.ctrl_pressed or idle_k.alt_pressed:
				allow_idle_hotkey = false
		if allow_idle_hotkey:
			if select_next_idle_worker(true) != null or event is InputEventMouseButton:
				get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("cmd_select_all_army") and not event.is_echo():
		var allow_army_hotkey: bool = true
		if event is InputEventKey:
			var army_k: InputEventKey = event
			if army_k.ctrl_pressed or army_k.alt_pressed:
				allow_army_hotkey = false
		if allow_army_hotkey:
			if select_all_army(true) > 0 or event is InputEventMouseButton:
				get_viewport().set_input_as_handled()
			return

	if _try_handle_ability_hotkey_event(event, "cmd_ability_q", "Q"):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_w", "W"):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_e", "E"):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_r", "R"):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_t", "T"):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_y", "Y"):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_f", "F"):
		return

	if event.is_action_pressed("cmd_ability_e") and selected_units.is_empty() and inspected_entity is Building:
		var b_node: Building = inspected_entity
		var b_local: bool = TeamManager.is_team_controlled_by_local_human(int(b_node.team)) if TeamManager != null else (b_node.team == Unit.Team.PLAYER)
		if is_instance_valid(b_node) and b_local and b_node.max_staff_slots > 0 and b_node.get_assigned_engineer_count() > 0:
			b_node.eject_engineers()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			var group_num: int = _get_control_group_key(key_event)
			if group_num > 0:
				_handle_control_group_key(group_num, key_event)
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("cmd_attack_move") and not event.is_echo():
		if event is InputEventKey:
			var a_key: InputEventKey = event
			if a_key.ctrl_pressed or a_key.alt_pressed:
				return
		if not selected_units.is_empty():
			begin_attack_move_targeting()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_patrol") and not event.is_echo():
		if event is InputEventKey:
			var p_key: InputEventKey = event
			if p_key.ctrl_pressed or p_key.alt_pressed:
				return
		if not selected_units.is_empty():
			begin_patrol_targeting()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_stop"):
		cancel_ability_targeting()
		cancel_attack_move_targeting()
		cancel_patrol_targeting()
		issue_stop_command()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_hold"):
		cancel_ability_targeting()
		cancel_attack_move_targeting()
		cancel_patrol_targeting()
		issue_hold_command()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if active_targeting_ability != null:
					confirm_ability_target_at(get_global_mouse_position(), mouse_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT))
					get_viewport().set_input_as_handled()
					return
				if is_attack_move_targeting:
					var shift_amove: bool = mouse_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
					confirm_attack_move_target_at(get_global_mouse_position(), shift_amove)
					get_viewport().set_input_as_handled()
					return
				if is_patrol_targeting:
					var shift_patrol: bool = mouse_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
					confirm_patrol_target_at(get_global_mouse_position(), shift_patrol)
					get_viewport().set_input_as_handled()
					return
				_is_dragging = true
				_drag_start_world = get_global_mouse_position()
				_drag_start_screen = mouse_event.position
				_click_was_double_click = mouse_event.double_click
				_click_ctrl_pressed = mouse_event.ctrl_pressed or Input.is_key_pressed(KEY_CTRL)
			elif _is_dragging:
				_finish_left_selection(
					mouse_event.position,
					mouse_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT),
					_click_was_double_click,
					_click_ctrl_pressed or mouse_event.ctrl_pressed
				)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			if active_targeting_ability != null:
				cancel_ability_targeting()
				get_viewport().set_input_as_handled()
				return
			if is_attack_move_targeting:
				cancel_attack_move_targeting()
				get_viewport().set_input_as_handled()
				return
			if is_patrol_targeting:
				cancel_patrol_targeting()
				get_viewport().set_input_as_handled()
				return
			var shift_order: bool = mouse_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
			issue_right_click_at(get_global_mouse_position(), shift_order)
	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event: InputEventMouseMotion = event
		if motion_event.position.distance_to(_drag_start_screen) >= drag_threshold:
			var rect: Rect2 = _build_world_rect(_drag_start_world, get_global_mouse_position())
			selection_box.update_box(rect, true)


func clear_selection() -> void:
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_set_selected_buildings([])
	_set_inspected_entity(null)
	_set_selected_units([])


func select_in_world_rect(world_rect: Rect2) -> void:
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_select_in_rect(world_rect, false)


func select_at_world_point(world_point: Vector2) -> void:
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_select_at_point(world_point, false)


func select_single_entity(entity: Node, focus_camera: bool = false) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	if entity is Building:
		var b: Building = entity
		if b.is_destroyed or b.is_queued_for_deletion():
			return
		_set_selected_units([])
		if b.team == Unit.Team.PLAYER:
			_set_selected_buildings([b])
		else:
			_set_selected_buildings([])
			_set_inspected_entity(b)
		if focus_camera:
			var cam_b: RTSCamera = _get_rts_camera()
			if cam_b != null:
				cam_b.center_on(b.global_position)
	elif entity is Unit:
		var u: Unit = entity
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			return
		_set_selected_buildings([])
		_set_inspected_entity(null)
		if u.team == Unit.Team.PLAYER:
			_set_selected_units([u])
		else:
			_set_selected_units([])
			_set_inspected_entity(u)
		if focus_camera:
			var cam_u: RTSCamera = _get_rts_camera()
			if cam_u != null:
				cam_u.center_on(u.global_position)


func cycle_subgroup() -> void:
	if subgroups.size() <= 1:
		return
	cancel_ability_targeting()
	active_subgroup_index = (active_subgroup_index + 1) % subgroups.size()
	selection_changed.emit(selected_units, subgroups, active_subgroup_index)


func set_active_subgroup(index: int) -> void:
	if index < 0 or index >= subgroups.size() or active_subgroup_index == index:
		return
	cancel_ability_targeting()
	active_subgroup_index = index
	selection_changed.emit(selected_units, subgroups, active_subgroup_index)


func get_active_subgroup() -> Dictionary:
	if active_subgroup_index < 0 or active_subgroup_index >= subgroups.size():
		return {}
	return subgroups[active_subgroup_index]


func get_active_subgroup_units() -> Array[Unit]:
	var active: Dictionary = get_active_subgroup()
	if active.is_empty():
		return []
	return active["units"]


func request_ability_by_hotkey(hotkey: String, shift_queued: bool = false) -> bool:
	var active: Dictionary = get_active_subgroup()
	if active.is_empty():
		return false
	var ability: AbilityData = SubgroupHelper.find_ability_by_hotkey(active, hotkey)
	if ability == null:
		return false
	return request_ability_slot(ability, shift_queued)


func request_ability_slot(ability: AbilityData, shift_queued: bool = false) -> bool:
	if ability == null or command_router == null:
		return false
	_prune_invalid_units()
	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	if subgroup_units.is_empty():
		return false

	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		if ability.building_to_build == null:
			return false
		var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
		if ability.building_to_build.required_building_id != &"":
			if econ == null or not econ.has_constructed_building(Unit.Team.PLAYER, ability.building_to_build.required_building_id):
				if AudioManager != null:
					AudioManager.play_error()
				return false
		if econ != null and not econ.can_afford(Unit.Team.PLAYER, ability.building_to_build.get_cost_dict()):
			var missing: StringName = econ.find_missing_resource(Unit.Team.PLAYER, ability.building_to_build.get_cost_dict(), 0)
			if missing != &"":
				econ.notify_insufficient(Unit.Team.PLAYER, missing)
			return false
		if command_router.find_closest_builder(subgroup_units, get_global_mouse_position()) == null:
			return false
		cancel_attack_move_targeting()
		cancel_patrol_targeting()
		active_targeting_ability = ability
		_update_command_cursor()
		if ability_reticle != null:
			ability_reticle.clear_targeting()
		if AudioManager != null:
			AudioManager.play_ui_click()
		ability_targeting_changed.emit(active_targeting_ability)
		return true

	if not SubgroupHelper.has_any_ready_caster(subgroup_units, ability):
		return false

	if ability.target_type == AbilityData.TargetType.INSTANT:
		cancel_ability_targeting()
		return command_router.issue_ability_order(subgroup_units, ability, get_global_mouse_position(), null, shift_queued)

	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	active_targeting_ability = ability
	_update_command_cursor()
	if build_ghost_preview != null:
		build_ghost_preview.clear_preview()
	ability_targeting_changed.emit(active_targeting_ability)
	return true


func confirm_ability_target_at(world_pos: Vector2, shift_queued: bool = false) -> bool:
	if active_targeting_ability == null or command_router == null:
		return false
	var ability: AbilityData = active_targeting_ability
	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		var placed: bool = command_router.confirm_build_placement(ability, world_pos, get_active_subgroup_units(), shift_queued)
		if placed:
			_refresh_idle_workers(true)
			var keep_placing: bool = false
			if shift_queued and ability.building_to_build != null:
				var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
				keep_placing = (econ == null or econ.can_afford(Unit.Team.PLAYER, ability.building_to_build.get_cost_dict()))
			if not keep_placing:
				cancel_ability_targeting()
		return placed

	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	var target_enemy: Unit = command_router.find_unit_at_point(world_pos, Unit.Team.ENEMY)
	if ability.target_type == AbilityData.TargetType.UNIT_TARGET and target_enemy == null:
		return false

	var accepted: bool = command_router.issue_ability_order(subgroup_units, ability, world_pos, target_enemy, shift_queued)
	cancel_ability_targeting()
	return accepted


func cancel_ability_targeting() -> void:
	if active_targeting_ability == null:
		return
	active_targeting_ability = null
	_update_command_cursor()
	if ability_reticle != null:
		ability_reticle.clear_targeting()
	if build_ghost_preview != null:
		build_ghost_preview.clear_preview()
	ability_targeting_changed.emit(null)


func begin_attack_move_targeting() -> void:
	_prune_invalid_units()
	if selected_units.is_empty():
		return
	cancel_ability_targeting()
	cancel_patrol_targeting()
	is_attack_move_targeting = true
	_update_command_cursor()
	_redraw_selected_units()
	if AudioManager != null:
		AudioManager.play_ui_click()
	attack_move_targeting_changed.emit(true)


func cancel_attack_move_targeting() -> void:
	if not is_attack_move_targeting:
		return
	is_attack_move_targeting = false
	_update_command_cursor()
	_redraw_selected_units()
	if ability_reticle != null and not is_patrol_targeting:
		ability_reticle.clear_command_mode_reticle()
	attack_move_targeting_changed.emit(false)


func confirm_attack_move_target_at(world_pos: Vector2, shift_queued: bool = false) -> void:
	_prune_invalid_units()
	issue_attack_move_at(world_pos, shift_queued)
	if not shift_queued:
		cancel_attack_move_targeting()


func begin_patrol_targeting() -> void:
	_prune_invalid_units()
	if selected_units.is_empty():
		return
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	is_patrol_targeting = true
	_update_command_cursor()
	_redraw_selected_units()
	if AudioManager != null:
		AudioManager.play_ui_click()
	patrol_targeting_changed.emit(true)


func cancel_patrol_targeting() -> void:
	if not is_patrol_targeting:
		return
	is_patrol_targeting = false
	_update_command_cursor()
	_redraw_selected_units()
	if ability_reticle != null and not is_attack_move_targeting:
		ability_reticle.clear_command_mode_reticle()
	patrol_targeting_changed.emit(false)


func confirm_patrol_target_at(world_pos: Vector2, shift_queued: bool = false) -> void:
	_prune_invalid_units()
	if command_router != null and not selected_units.is_empty():
		command_router.issue_patrol_order(selected_units, world_pos, shift_queued)
	if not shift_queued:
		cancel_patrol_targeting()
	_refresh_idle_workers(false)


func reset_command_cursors() -> void:
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_clear_custom_cursor()


func issue_right_click_at(world_point: Vector2, shift_queued: bool = false) -> void:
	_prune_invalid_units()
	if command_router != null:
		command_router.handle_right_click(world_point, selected_units, inspected_entity, shift_queued, selected_buildings)
	_refresh_idle_workers(false)
	_update_command_cursor()


func is_targeting_command_active() -> bool:
	if is_patrol_targeting or is_attack_move_targeting:
		return true
	if active_targeting_ability != null and active_targeting_ability.target_type != AbilityData.TargetType.BUILD_PLACEMENT:
		return true
	if _amove_preview_timer > 0.0 or Input.is_action_pressed("cmd_attack_move"):
		return true
	return false


func _redraw_selected_units() -> void:
	for u: Unit in selected_units:
		if is_instance_valid(u) and not u.is_dead:
			u.queue_redraw()
	for b: Building in selected_buildings:
		if is_instance_valid(b) and not b.is_destroyed:
			b.queue_redraw()
	if inspected_entity is Building and is_instance_valid(inspected_entity):
		(inspected_entity as Building).queue_redraw()


func issue_attack_move_at(world_point: Vector2, shift_queued: bool = false) -> void:
	_prune_invalid_units()
	_amove_preview_timer = 0.85
	_last_targeting_active = true
	_redraw_selected_units()
	if command_router != null:
		command_router.issue_attack_move(world_point, selected_units, shift_queued)
	_refresh_idle_workers(false)


func get_idle_workers() -> Array[Unit]:
	var idle_list: Array[Unit] = []
	if not is_inside_tree():
		return idle_list
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var unit: Unit = node
		if unit.is_idle_worker():
			idle_list.append(unit)
	idle_list.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)
	return idle_list


func select_next_idle_worker(focus_camera: bool = true) -> Unit:
	var idle_list: Array[Unit] = get_idle_workers()
	if idle_list.is_empty():
		_idle_cycle_index = -1
		_refresh_idle_workers(false)
		return null

	var next_idx: int = (_idle_cycle_index + 1) % idle_list.size()
	if selected_units.size() == 1 and is_instance_valid(selected_units[0]):
		var cur_idx: int = idle_list.find(selected_units[0])
		if cur_idx >= 0:
			next_idx = (cur_idx + 1) % idle_list.size()

	_idle_cycle_index = next_idx
	var chosen: Unit = idle_list[next_idx]
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_set_selected_buildings([])
	_set_inspected_entity(null)
	_set_selected_units([chosen])

	if focus_camera:
		var cam: RTSCamera = _get_rts_camera()
		if cam != null:
			var vp_size: Vector2 = get_viewport_rect().size / cam.zoom
			var inner_rect: Rect2 = Rect2(cam.global_position - vp_size * 0.5, vp_size).grow(-64.0)
			if idle_list.size() == 1 or not inner_rect.has_point(chosen.global_position):
				cam.center_on(chosen.global_position)

	return chosen


func get_army_units() -> Array[Unit]:
	var army: Array[Unit] = []
	if not is_inside_tree():
		return army
	if TeamManager != null and TeamManager.is_spectator_mode():
		return army
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var u: Unit = node
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion() or int(u.team) != local_team or u.data == null:
			continue
		var uid: StringName = u.get_unit_type_id()
		if u.data.can_gather or u.data.can_staff_compute or uid == &"worker" or uid == &"silica_harvester" or uid == &"engineer":
			continue
		if u.data.attack_damage > 0.0 or uid == &"symbiote" or uid == &"signal_jammer":
			army.append(u)
	return army


func select_all_army(allow_double_tap_center: bool = true) -> int:
	if TeamManager != null and TeamManager.is_spectator_mode():
		return 0
	var army: Array[Unit] = get_army_units()
	if army.is_empty():
		return 0
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_set_selected_buildings([])
	_set_inspected_entity(null)
	_set_selected_units(army)
	if allow_double_tap_center:
		var now_ms: int = Time.get_ticks_msec()
		if (now_ms - _last_army_select_ms) <= DOUBLE_TAP_WINDOW_MS:
			_center_camera_on_units(army)
			_last_army_select_ms = 0
		else:
			_last_army_select_ms = now_ms
	return army.size()


func _refresh_idle_workers(force_emit: bool = false) -> void:
	var idle_list: Array[Unit] = get_idle_workers()
	var ids: PackedInt64Array = PackedInt64Array()
	ids.resize(idle_list.size())
	for i: int in range(idle_list.size()):
		ids[i] = idle_list[i].get_instance_id()

	var cur_army_count: int = get_army_units().size()
	if force_emit or cur_army_count != army_unit_count:
		army_unit_count = cur_army_count
		army_count_updated.emit(army_unit_count)

	if not force_emit and ids == _last_idle_ids and idle_worker_count == idle_list.size():
		return
	_last_idle_ids = ids
	idle_worker_count = idle_list.size()
	idle_workers_changed.emit(idle_list)
	idle_workers_updated.emit(idle_worker_count)


func issue_stop_command() -> void:
	_prune_invalid_units()
	if command_router != null:
		command_router.issue_stop(selected_units)


func issue_hold_command() -> void:
	_prune_invalid_units()
	if command_router != null:
		command_router.issue_hold(selected_units)


func assign_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if not selected_units.is_empty():
		control_groups[group_num] = selected_units.duplicate()
		_watch_control_group_units(selected_units)
		_emit_control_groups_changed()
		return
	if not selected_buildings.is_empty():
		control_groups[group_num] = selected_buildings.duplicate()
		_watch_control_group_buildings(selected_buildings)
		_emit_control_groups_changed()


func append_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if not selected_units.is_empty():
		var group_units: Array[Unit] = _get_pruned_group(group_num)
		for unit: Unit in selected_units:
			if not group_units.has(unit):
				group_units.append(unit)
		if not group_units.is_empty():
			control_groups[group_num] = group_units
			_watch_control_group_units(group_units)
		_emit_control_groups_changed()
		return
	if not selected_buildings.is_empty():
		var group_buildings: Array[Building] = _get_pruned_building_group(group_num)
		for b: Building in selected_buildings:
			if not group_buildings.has(b):
				group_buildings.append(b)
		if not group_buildings.is_empty():
			control_groups[group_num] = group_buildings
			_watch_control_group_buildings(group_buildings)
		_emit_control_groups_changed()


func _watch_control_group_units(units: Array[Unit]) -> void:
	for u: Unit in units:
		if is_instance_valid(u) and not u.is_dead:
			if not u.died.is_connected(_on_control_group_unit_removed):
				u.died.connect(_on_control_group_unit_removed)


func _watch_control_group_buildings(buildings: Array[Building]) -> void:
	for b: Building in buildings:
		if is_instance_valid(b) and not b.is_destroyed:
			if not b.destroyed.is_connected(_on_control_group_building_removed):
				b.destroyed.connect(_on_control_group_building_removed)


func _on_control_group_unit_removed(_unit: Unit) -> void:
	_emit_control_groups_changed()


func _on_control_group_building_removed(_building: Building) -> void:
	_emit_control_groups_changed()


func remove_from_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9 or not control_groups.has(group_num):
		return
	_prune_invalid_units()
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	if not group_units.is_empty():
		var remaining: Array[Unit] = []
		for unit: Unit in group_units:
			if not selected_units.has(unit):
				remaining.append(unit)
		if remaining.is_empty():
			control_groups.erase(group_num)
		else:
			control_groups[group_num] = remaining
		_emit_control_groups_changed()
		return
	var group_buildings: Array[Building] = _get_pruned_building_group(group_num)
	if not group_buildings.is_empty():
		var rem_b: Array[Building] = []
		for b: Building in group_buildings:
			if not selected_buildings.has(b):
				rem_b.append(b)
		if rem_b.is_empty():
			control_groups.erase(group_num)
		else:
			control_groups[group_num] = rem_b
		_emit_control_groups_changed()


func steal_assign_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if not selected_units.is_empty():
		_strip_from_other_control_groups(group_num, selected_units, [])
		control_groups[group_num] = selected_units.duplicate()
		_watch_control_group_units(selected_units)
		_emit_control_groups_changed()
		return
	if not selected_buildings.is_empty():
		_strip_from_other_control_groups(group_num, [], selected_buildings)
		control_groups[group_num] = selected_buildings.duplicate()
		_watch_control_group_buildings(selected_buildings)
		_emit_control_groups_changed()


func steal_append_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if not selected_units.is_empty():
		_strip_from_other_control_groups(group_num, selected_units, [])
		var group_units: Array[Unit] = _get_pruned_group(group_num)
		for unit: Unit in selected_units:
			if not group_units.has(unit):
				group_units.append(unit)
		if not group_units.is_empty():
			control_groups[group_num] = group_units
			_watch_control_group_units(group_units)
		_emit_control_groups_changed()
		return
	if not selected_buildings.is_empty():
		_strip_from_other_control_groups(group_num, [], selected_buildings)
		var group_buildings: Array[Building] = _get_pruned_building_group(group_num)
		for b: Building in selected_buildings:
			if not group_buildings.has(b):
				group_buildings.append(b)
		if not group_buildings.is_empty():
			control_groups[group_num] = group_buildings
			_watch_control_group_buildings(group_buildings)
		_emit_control_groups_changed()


func _strip_from_other_control_groups(exclude_group: int, units_to_strip: Array[Unit], buildings_to_strip: Array[Building]) -> void:
	for num: int in range(1, 10):
		if num == exclude_group or not control_groups.has(num):
			continue
		if not units_to_strip.is_empty():
			var group_units: Array[Unit] = _get_pruned_group(num)
			if not group_units.is_empty():
				var remaining: Array[Unit] = []
				for u: Unit in group_units:
					if not units_to_strip.has(u):
						remaining.append(u)
				if remaining.is_empty():
					control_groups.erase(num)
				else:
					control_groups[num] = remaining
		if not buildings_to_strip.is_empty():
			var group_buildings: Array[Building] = _get_pruned_building_group(num)
			if not group_buildings.is_empty():
				var rem_b: Array[Building] = []
				for b: Building in group_buildings:
					if not buildings_to_strip.has(b):
						rem_b.append(b)
				if rem_b.is_empty():
					control_groups.erase(num)
				else:
					control_groups[num] = rem_b


func recall_control_group(group_num: int, allow_double_tap_center: bool = true) -> void:
	if group_num < 1 or group_num > 9:
		return
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	if not group_units.is_empty():
		control_groups[group_num] = group_units
		cancel_ability_targeting()
		cancel_attack_move_targeting()
		cancel_patrol_targeting()
		_set_selected_buildings([])
		_set_inspected_entity(null)
		_set_selected_units(group_units)
		_emit_control_groups_changed()
		if allow_double_tap_center:
			var now_ms: int = Time.get_ticks_msec()
			if _last_recall_group == group_num and (now_ms - _last_recall_time_ms) <= DOUBLE_TAP_WINDOW_MS:
				_center_camera_on_units(group_units)
				_last_recall_group = -1
				_last_recall_time_ms = 0
			else:
				_last_recall_group = group_num
				_last_recall_time_ms = now_ms
		return

	var group_buildings: Array[Building] = _get_pruned_building_group(group_num)
	if not group_buildings.is_empty():
		control_groups[group_num] = group_buildings
		cancel_ability_targeting()
		cancel_attack_move_targeting()
		cancel_patrol_targeting()
		_set_selected_units([])
		_set_selected_buildings(group_buildings)
		_emit_control_groups_changed()
		if allow_double_tap_center:
			var now_b_ms: int = Time.get_ticks_msec()
			if _last_recall_group == group_num and (now_b_ms - _last_recall_time_ms) <= DOUBLE_TAP_WINDOW_MS:
				_center_camera_on_nodes(group_buildings)
				_last_recall_group = -1
				_last_recall_time_ms = 0
			else:
				_last_recall_group = group_num
				_last_recall_time_ms = now_b_ms
		return

	control_groups.erase(group_num)
	_emit_control_groups_changed()


func get_control_group_units(group_num: int) -> Array[Unit]:
	return _get_pruned_group(group_num)


func get_control_groups_summary() -> Dictionary:
	var summary: Dictionary = {}
	for num: int in range(1, 10):
		if not control_groups.has(num):
			continue
		var group_units: Array[Unit] = _get_pruned_group(num)
		if not group_units.is_empty():
			control_groups[num] = group_units
			summary[num] = group_units.size()
			continue
		var group_buildings: Array[Building] = _get_pruned_building_group(num)
		if not group_buildings.is_empty():
			control_groups[num] = group_buildings
			summary[num] = group_buildings.size()
		else:
			control_groups.erase(num)
	return summary


func get_control_group_summaries() -> Dictionary:
	var out: Dictionary = {}
	for num: int in range(1, 10):
		if not control_groups.has(num):
			continue
		var group_units: Array[Unit] = _get_pruned_group(num)
		if not group_units.is_empty():
			control_groups[num] = group_units
			var lead_name: String = group_units[0].data.display_name if group_units[0].data != null else "Units"
			var active_u: bool = (selected_units.size() == group_units.size() and not selected_units.is_empty())
			if active_u:
				for gu: Unit in group_units:
					if not selected_units.has(gu):
						active_u = false
						break
			out[num] = {
				"count": group_units.size(),
				"label": lead_name,
				"is_active": active_u,
				"is_building": false,
			}
			continue
		var group_buildings: Array[Building] = _get_pruned_building_group(num)
		if not group_buildings.is_empty():
			control_groups[num] = group_buildings
			var active_b: bool = (selected_buildings.size() == group_buildings.size() and not selected_buildings.is_empty())
			if active_b:
				for gb: Building in group_buildings:
					if not selected_buildings.has(gb):
						active_b = false
						break
			out[num] = {
				"count": group_buildings.size(),
				"label": group_buildings[0].display_name,
				"is_active": active_b,
				"is_building": true,
			}
		else:
			control_groups.erase(num)
	return out


func clear_control_groups() -> void:
	control_groups.clear()
	_emit_control_groups_changed()


func _handle_control_group_key(group_num: int, key_event: InputEventKey) -> void:
	if key_event.alt_pressed and key_event.shift_pressed:
		steal_append_control_group(group_num)
	elif key_event.alt_pressed:
		steal_assign_control_group(group_num)
	elif key_event.ctrl_pressed:
		assign_control_group(group_num)
	elif key_event.shift_pressed:
		append_control_group(group_num)
	else:
		recall_control_group(group_num, true)


func _get_control_group_key(key_event: InputEventKey) -> int:
	var code: Key = key_event.physical_keycode
	if code < KEY_1 or code > KEY_9:
		code = key_event.keycode
	if code >= KEY_1 and code <= KEY_9:
		return int(code - KEY_1) + 1
	return 0


func _get_pruned_group(group_num: int) -> Array[Unit]:
	var valid: Array[Unit] = []
	if not control_groups.has(group_num):
		return valid
	var raw: Variant = control_groups[group_num]
	if raw is Array:
		for item: Variant in raw:
			if is_instance_valid(item) and item is Unit:
				var unit: Unit = item
				if not unit.is_dead and not unit.is_staffed and unit.team == Unit.Team.PLAYER:
					valid.append(unit)
	return valid


func _get_pruned_building_group(group_num: int) -> Array[Building]:
	var valid: Array[Building] = []
	if not control_groups.has(group_num):
		return valid
	var raw: Variant = control_groups[group_num]
	if raw is Array:
		for item: Variant in raw:
			if is_instance_valid(item) and item is Building:
				var b: Building = item
				if not b.is_destroyed and not b.is_queued_for_deletion() and b.team == Unit.Team.PLAYER:
					valid.append(b)
	return valid


func _emit_control_groups_changed() -> void:
	control_groups_changed.emit(get_control_groups_summary())


func _center_camera_on_units(units: Array[Unit]) -> void:
	_center_camera_on_nodes(units)


func _center_camera_on_nodes(nodes: Array) -> void:
	if nodes.is_empty():
		return
	var cam: RTSCamera = _get_rts_camera()
	if cam == null:
		return
	var centroid: Vector2 = Vector2.ZERO
	var valid_count: int = 0
	for item: Variant in nodes:
		if is_instance_valid(item) and item is Node2D:
			centroid += (item as Node2D).global_position
			valid_count += 1
	if valid_count <= 0:
		return
	centroid /= float(valid_count)
	cam.center_on(centroid)


func _get_rts_camera() -> RTSCamera:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as RTSCamera
	if get_parent() != null:
		return get_parent().get_node_or_null("RTSCamera") as RTSCamera
	return null


func _finish_left_selection(end_screen_pos: Vector2, shift_pressed: bool = false, is_double_click: bool = false, ctrl_pressed: bool = false) -> void:
	_is_dragging = false
	_click_was_double_click = false
	_click_ctrl_pressed = false
	selection_box.update_box(Rect2(), false)
	var end_world_pos: Vector2 = get_global_mouse_position()
	if end_screen_pos.distance_to(_drag_start_screen) < drag_threshold:
		_select_at_point(end_world_pos, shift_pressed, is_double_click, ctrl_pressed)
	else:
		_select_in_rect(_build_world_rect(_drag_start_world, end_world_pos), shift_pressed)


func _select_at_point(world_point: Vector2, shift_pressed: bool = false, is_double_click: bool = false, ctrl_pressed: bool = false) -> void:
	if command_router == null:
		return

	if TeamManager != null and TeamManager.is_spectator_mode():
		_set_selected_units([])
		_set_selected_buildings([])
		var any_u: Unit = command_router.find_any_unit_at_point(world_point)
		if any_u != null:
			_set_inspected_entity(any_u)
			return
		var any_b: Building = command_router.find_any_building_at_point(world_point)
		if any_b != null:
			_set_inspected_entity(any_b)
			return
		var spec_bar: Node2D = command_router.find_barricade_at_point(world_point)
		if spec_bar != null:
			_set_inspected_entity(spec_bar)
			return
		var spec_salvage: Node2D = command_router.find_salvage_core_at_point(world_point)
		if spec_salvage != null:
			_set_inspected_entity(spec_salvage)
			return
		var spec_res: ResourceNode = command_router.find_resource_node_at_point(world_point)
		if spec_res != null:
			_set_inspected_entity(spec_res)
			return
		_set_inspected_entity(null)
		return

	var clicked_player: Unit = command_router.find_unit_at_point(world_point, Unit.Team.PLAYER)
	if clicked_player != null:
		_set_selected_buildings([])
		_set_inspected_entity(null)
		var now_ms: int = Time.get_ticks_msec()
		var rapid_second_click: bool = (_last_click_unit == clicked_player and (now_ms - _last_click_time_ms) <= DOUBLE_TAP_WINDOW_MS)
		if is_double_click or ctrl_pressed or (not shift_pressed and rapid_second_click):
			var same_type: Array[Unit] = _find_visible_units_of_type(clicked_player.get_unit_type_id(), Unit.Team.PLAYER)
			_last_click_unit = null
			_last_click_time_ms = 0
			if shift_pressed and not selected_units.is_empty():
				var merged: Array[Unit] = selected_units.duplicate()
				for u: Unit in same_type:
					if not merged.has(u):
						merged.append(u)
				_set_selected_units(merged, false)
			else:
				_set_selected_units(same_type)
			return

		_last_click_unit = clicked_player
		_last_click_time_ms = now_ms
		if shift_pressed:
			var next_sel: Array[Unit] = selected_units.duplicate()
			if next_sel.has(clicked_player):
				next_sel.erase(clicked_player)
			else:
				next_sel.append(clicked_player)
			_set_selected_units(next_sel, false)
		else:
			_set_selected_units([clicked_player])
		return

	_last_click_unit = null
	_last_click_time_ms = 0

	var clicked_building: Building = command_router.find_building_at_point(world_point, Unit.Team.PLAYER)
	if clicked_building != null:
		var now_b_ms: int = Time.get_ticks_msec()
		var rapid_second_b: bool = (_last_click_building == clicked_building and (now_b_ms - _last_click_building_time_ms) <= DOUBLE_TAP_WINDOW_MS)
		_set_selected_units([])
		if is_double_click or ctrl_pressed or (not shift_pressed and rapid_second_b):
			var same_b: Array[Building] = _find_visible_buildings_of_type(clicked_building.building_type_id, Unit.Team.PLAYER)
			_last_click_building = null
			_last_click_building_time_ms = 0
			_set_selected_buildings(same_b)
		elif shift_pressed:
			var next_b: Array[Building] = selected_buildings.duplicate()
			if next_b.has(clicked_building):
				next_b.erase(clicked_building)
			else:
				next_b.append(clicked_building)
			_set_selected_buildings(next_b)
		else:
			_last_click_building = clicked_building
			_last_click_building_time_ms = now_b_ms
			_set_selected_buildings([clicked_building])
		return

	_last_click_building = null
	_last_click_building_time_ms = 0

	var clicked_enemy: Unit = command_router.find_unit_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy != null:
		_set_selected_units([])
		_set_selected_buildings([])
		_set_inspected_entity(clicked_enemy)
		return

	var clicked_enemy_building: Building = command_router.find_building_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy_building != null:
		_set_selected_units([])
		_set_selected_buildings([])
		_set_inspected_entity(clicked_enemy_building)
		return

	var clicked_barricade: Node2D = command_router.find_barricade_at_point(world_point)
	if clicked_barricade != null:
		_set_selected_units([])
		_set_selected_buildings([])
		_set_inspected_entity(clicked_barricade)
		return

	var clicked_salvage: Node2D = command_router.find_salvage_core_at_point(world_point)
	if clicked_salvage != null:
		_set_selected_units([])
		_set_selected_buildings([])
		_set_inspected_entity(clicked_salvage)
		return

	var clicked_resource: ResourceNode = command_router.find_resource_node_at_point(world_point)
	if clicked_resource != null:
		_set_selected_units([])
		_set_selected_buildings([])
		_set_inspected_entity(clicked_resource)
		return

	if not shift_pressed:
		_set_selected_buildings([])
		_set_inspected_entity(null)
		_set_selected_units([])


func _is_utility_unit(unit: Unit) -> bool:
	if unit == null or unit.data == null:
		return false
	if unit.data.can_gather or unit.data.can_staff_compute:
		return true
	var uid: StringName = unit.get_unit_type_id()
	return uid == &"worker" or uid == &"worker_unit" or uid == &"silica_harvester" or uid == &"engineer" or uid == &"engineer_unit"


func _select_in_rect(world_rect: Rect2, shift_pressed: bool = false) -> void:
	if TeamManager != null and TeamManager.is_spectator_mode():
		return
	_last_click_unit = null
	_last_click_building = null
	_last_click_time_ms = 0
	_last_click_building_time_ms = 0
	var combat_hits: Array[Unit] = []
	var utility_hits: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.is_staffed or unit.team != Unit.Team.PLAYER:
			continue
		if world_rect.has_point(unit.global_position):
			if _is_utility_unit(unit):
				utility_hits.append(unit)
			else:
				combat_hits.append(unit)

	# Smart box-selection priority: combat units always take precedence over economy/utility units.
	var hits: Array[Unit] = combat_hits if not combat_hits.is_empty() else utility_hits

	if not hits.is_empty():
		if shift_pressed:
			var existing_has_combat: bool = false
			for prev_u: Unit in selected_units:
				if is_instance_valid(prev_u) and not prev_u.is_dead and not _is_utility_unit(prev_u):
					existing_has_combat = true
					break
			var to_add: Array[Unit] = hits
			if existing_has_combat and not combat_hits.is_empty():
				to_add = combat_hits
			var combined: Array[Unit] = selected_units.duplicate()
			for u: Unit in to_add:
				if not combined.has(u):
					combined.append(u)
			_set_selected_buildings([])
			_set_inspected_entity(null)
			_set_selected_units(combined, false)
		else:
			_set_selected_buildings([])
			_set_inspected_entity(null)
			_set_selected_units(hits)
		return

	# If no player units are inside the box, allow box-selecting friendly buildings for multi-building production.
	var b_hits: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group("selectable_buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.team != Unit.Team.PLAYER:
			continue
		if world_rect.has_point(b.global_position):
			b_hits.append(b)

	if not b_hits.is_empty():
		if shift_pressed:
			var merged_b: Array[Building] = selected_buildings.duplicate()
			for b: Building in b_hits:
				if not merged_b.has(b):
					merged_b.append(b)
			_set_selected_units([])
			_set_selected_buildings(merged_b)
		else:
			_set_selected_units([])
			_set_selected_buildings(b_hits)
		return

	if not shift_pressed:
		_set_selected_buildings([])
		_set_inspected_entity(null)
		_set_selected_units([])


func _find_visible_buildings_of_type(type_id: StringName, target_team: Unit.Team) -> Array[Building]:
	var matches: Array[Building] = []
	var cam: RTSCamera = _get_rts_camera()
	var view_rect: Rect2 = Rect2()
	var use_view_rect: bool = false
	if cam != null:
		var vp_size: Vector2 = get_viewport_rect().size / cam.zoom
		view_rect = Rect2(cam.global_position - vp_size * 0.5, vp_size)
		use_view_rect = true
	for node: Node in get_tree().get_nodes_in_group("selectable_buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.team != target_team or b.building_type_id != type_id:
			continue
		if not use_view_rect or view_rect.has_point(b.global_position):
			matches.append(b)
	return matches


func _set_selected_buildings(buildings: Array[Building]) -> void:
	for prev: Building in selected_buildings:
		if is_instance_valid(prev):
			if prev.destroyed.is_connected(_on_selected_building_destroyed):
				prev.destroyed.disconnect(_on_selected_building_destroyed)
			prev.set_selected(false)

	selected_buildings = []
	for item: Variant in buildings:
		if is_instance_valid(item) and item is Building:
			var b: Building = item
			if not b.is_destroyed and b.team == Unit.Team.PLAYER and not selected_buildings.has(b):
				selected_buildings.append(b)

	if selected_buildings.is_empty():
		_set_inspected_entity(null)
		buildings_selection_changed.emit(selected_buildings)
		return

	for b: Building in selected_buildings:
		b.set_selected(true)
		if not b.destroyed.is_connected(_on_selected_building_destroyed):
			b.destroyed.connect(_on_selected_building_destroyed)

	_set_inspected_entity(selected_buildings[0])
	# Re-ensure every multi-selected building stays visibly selected after _set_inspected_entity.
	for b: Building in selected_buildings:
		if is_instance_valid(b):
			b.set_selected(true)
	if AudioManager != null:
		AudioManager.play_sfx(&"unit_select", -5.0, 0.03)
	buildings_selection_changed.emit(selected_buildings)


func _on_selected_building_destroyed(dead_b: Building) -> void:
	if selected_buildings.has(dead_b):
		var rem: Array[Building] = []
		for b: Building in selected_buildings:
			if is_instance_valid(b) and b != dead_b and not b.is_destroyed:
				rem.append(b)
		_set_selected_buildings(rem)


func queue_unit_distributed(unit_data: UnitData) -> bool:
	if unit_data == null:
		return false
	var candidates: Array[Building] = []
	for b: Building in selected_buildings:
		if is_instance_valid(b) and not b.is_destroyed and b.is_constructed and b.team == Unit.Team.PLAYER:
			if b.trainable_unit_data.has(unit_data):
				candidates.append(b)
	if candidates.is_empty() and selected_building != null and is_instance_valid(selected_building):
		if selected_building.trainable_unit_data.has(unit_data):
			candidates.append(selected_building)
	if candidates.is_empty():
		return false

	# Choose the capable building with the shortest active queue (breaking ties by fewest remaining seconds).
	var best: Building = null
	var best_score: float = INF
	for b: Building in candidates:
		if b.production_component == null or b.production_component.is_queue_full():
			continue
		var q_size: int = b.get_training_queue_size()
		var active_rem: float = 0.0
		if q_size > 0:
			var st: Dictionary = b.get_active_training_status()
			active_rem = (1.0 - float(st.get("progress", 0.0))) * float(st.get("duration", 1.0))
		var score: float = float(q_size) * 100.0 + active_rem
		if score < best_score:
			best_score = score
			best = b

	if best == null:
		# All queues full; fallback to first candidate so standard error/feedback still runs.
		best = candidates[0]
	return best.queue_unit_data(unit_data)


func eject_engineers_from_selected_buildings() -> void:
	if not selected_buildings.is_empty():
		for b: Building in selected_buildings:
			if is_instance_valid(b) and b.max_staff_slots > 0:
				b.eject_engineers()
	elif selected_building != null and is_instance_valid(selected_building):
		selected_building.eject_engineers()


func _find_visible_units_of_type(type_id: StringName, target_team: Unit.Team) -> Array[Unit]:
	var matches: Array[Unit] = []
	var cam: RTSCamera = _get_rts_camera()
	var view_rect: Rect2 = Rect2()
	var use_view_rect: bool = false
	if cam != null:
		var vp_size: Vector2 = get_viewport_rect().size / cam.zoom
		view_rect = Rect2(cam.global_position - vp_size * 0.5, vp_size)
		use_view_rect = true
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed or unit.team != target_team or unit.get_unit_type_id() != type_id:
			continue
		if not use_view_rect or view_rect.has_point(unit.global_position):
			matches.append(unit)
	return matches


func _set_selected_units(new_selection: Array[Unit], reset_subgroup_index: bool = true) -> void:
	for item: Variant in selected_units:
		if is_instance_valid(item) and item is Unit:
			var prev_unit: Unit = item
			if not new_selection.has(prev_unit):
				prev_unit.set_selected(false)

	_disconnect_death_trackers()
	selected_units = []
	for item: Variant in new_selection:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if not unit.is_dead and not unit.is_staffed and unit.team == Unit.Team.PLAYER:
				selected_units.append(unit)
				unit.set_selected(true)
				if not unit.died.is_connected(_on_selected_unit_died):
					unit.died.connect(_on_selected_unit_died)
				if not unit.staffed_state_changed.is_connected(_on_selected_unit_staffed):
					unit.staffed_state_changed.connect(_on_selected_unit_staffed)
				_tracked_death_units.append(unit)

	subgroups = SubgroupHelper.build_subgroups(selected_units)
	if reset_subgroup_index or subgroups.is_empty():
		active_subgroup_index = 0
	else:
		active_subgroup_index = clampi(active_subgroup_index, 0, subgroups.size() - 1)

	if selected_units.is_empty():
		cancel_ability_targeting()
		cancel_attack_move_targeting()
		cancel_patrol_targeting()
	elif AudioManager != null:
		AudioManager.play_sfx(&"unit_select", -4.5, 0.04)
		if not subgroups.is_empty() and AudioManager.has_method("play_unit_bark_for_units"):
			var primary_units: Array[Unit] = subgroups[active_subgroup_index]["units"]
			AudioManager.call("play_unit_bark_for_units", primary_units, &"select")

	selection_updated.emit(selected_units.size())
	selection_changed.emit(selected_units, subgroups, active_subgroup_index)


func _on_selected_unit_died(_dead_unit: Unit) -> void:
	_prune_invalid_units()
	_emit_control_groups_changed()


func _on_selected_unit_staffed(_unit: Unit, _staffed: bool) -> void:
	_prune_invalid_units()
	_emit_control_groups_changed()


func _disconnect_death_trackers() -> void:
	for item: Variant in _tracked_death_units:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if unit.died.is_connected(_on_selected_unit_died):
				unit.died.disconnect(_on_selected_unit_died)
			if unit.staffed_state_changed.is_connected(_on_selected_unit_staffed):
				unit.staffed_state_changed.disconnect(_on_selected_unit_staffed)
	_tracked_death_units.clear()


func _set_inspected_entity(entity: Node) -> void:
	var next_entity: Node = null
	if entity != null and is_instance_valid(entity):
		if entity is Building and not (entity as Building).is_destroyed:
			next_entity = entity
		elif entity is Unit and not (entity as Unit).is_dead:
			next_entity = entity
		elif entity is ResourceNode and not (entity as ResourceNode).is_depleted():
			next_entity = entity
		elif entity.is_in_group("destructible_barricades") and not bool(entity.get("is_destroyed")):
			next_entity = entity
		elif entity.is_in_group("salvage_cores") and not bool(entity.get("is_claimed")):
			next_entity = entity

	if inspected_entity == next_entity:
		return

	if inspected_entity != null and is_instance_valid(inspected_entity):
		if inspected_entity is Building:
			var prev_b: Building = inspected_entity
			if prev_b.destroyed.is_connected(_on_inspected_entity_removed):
				prev_b.destroyed.disconnect(_on_inspected_entity_removed)
			prev_b.set_selected(false)
		elif inspected_entity is Unit:
			var prev_u: Unit = inspected_entity
			if prev_u.died.is_connected(_on_inspected_entity_removed):
				prev_u.died.disconnect(_on_inspected_entity_removed)
			prev_u.set_selected(false)
		elif inspected_entity is ResourceNode:
			var prev_r: ResourceNode = inspected_entity
			if prev_r.depleted.is_connected(_on_inspected_entity_removed):
				prev_r.depleted.disconnect(_on_inspected_entity_removed)
			prev_r.set_inspected(false)
		elif inspected_entity.is_in_group("destructible_barricades"):
			if inspected_entity.has_signal("destroyed") and inspected_entity.is_connected("destroyed", _on_inspected_entity_removed):
				inspected_entity.disconnect("destroyed", _on_inspected_entity_removed)
			if inspected_entity.has_method("set_selected"):
				inspected_entity.call("set_selected", false)
		elif inspected_entity.is_in_group("salvage_cores"):
			if inspected_entity.has_signal("claimed") and inspected_entity.is_connected("claimed", _on_inspected_entity_removed):
				inspected_entity.disconnect("claimed", _on_inspected_entity_removed)
			if inspected_entity.has_signal("expired") and inspected_entity.is_connected("expired", _on_inspected_entity_removed):
				inspected_entity.disconnect("expired", _on_inspected_entity_removed)
			if inspected_entity.has_method("set_selected"):
				inspected_entity.call("set_selected", false)

	var prev_building: Building = selected_building
	inspected_entity = next_entity
	selected_building = inspected_entity as Building if inspected_entity is Building else null
	inspected_enemy = inspected_entity as Unit if (inspected_entity is Unit and (inspected_entity as Unit).team == Unit.Team.ENEMY) else null

	if inspected_entity != null:
		if inspected_entity is Building:
			var b: Building = inspected_entity
			b.set_selected(true)
			if not b.destroyed.is_connected(_on_inspected_entity_removed):
				b.destroyed.connect(_on_inspected_entity_removed)
		elif inspected_entity is Unit:
			var u: Unit = inspected_entity
			u.set_selected(true)
			if not u.died.is_connected(_on_inspected_entity_removed):
				u.died.connect(_on_inspected_entity_removed)
		elif inspected_entity is ResourceNode:
			var r: ResourceNode = inspected_entity
			r.set_inspected(true)
			if not r.depleted.is_connected(_on_inspected_entity_removed):
				r.depleted.connect(_on_inspected_entity_removed)
		elif inspected_entity.is_in_group("destructible_barricades"):
			if inspected_entity.has_method("set_selected"):
				inspected_entity.call("set_selected", true)
			if inspected_entity.has_signal("destroyed") and not inspected_entity.is_connected("destroyed", _on_inspected_entity_removed):
				inspected_entity.connect("destroyed", _on_inspected_entity_removed)
		elif inspected_entity.is_in_group("salvage_cores"):
			if inspected_entity.has_method("set_selected"):
				inspected_entity.call("set_selected", true)
			if inspected_entity.has_signal("claimed") and not inspected_entity.is_connected("claimed", _on_inspected_entity_removed):
				inspected_entity.connect("claimed", _on_inspected_entity_removed)
			if inspected_entity.has_signal("expired") and not inspected_entity.is_connected("expired", _on_inspected_entity_removed):
				inspected_entity.connect("expired", _on_inspected_entity_removed)

	if prev_building != selected_building:
		building_selection_changed.emit(selected_building)
	inspection_changed.emit(inspected_entity)


func _on_inspected_entity_removed(_entity: Variant = null) -> void:
	_set_inspected_entity(null)


func _try_handle_ability_hotkey_event(event: InputEvent, action_name: StringName, hotkey_label: String) -> bool:
	if not event.is_action_pressed(action_name):
		return false
	var shift_queued: bool = Input.is_key_pressed(KEY_SHIFT)
	if event is InputEventKey:
		var key_ev: InputEventKey = event
		if key_ev.ctrl_pressed or key_ev.alt_pressed or key_ev.echo:
			return false
		shift_queued = key_ev.shift_pressed or shift_queued
	if request_ability_by_hotkey(hotkey_label, shift_queued):
		get_viewport().set_input_as_handled()
		return true
	return false


func _prune_invalid_units() -> void:
	var valid: Array[Unit] = []
	for item: Variant in selected_units:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if not unit.is_dead and not unit.is_staffed and unit.team == Unit.Team.PLAYER:
				valid.append(unit)
	if valid.size() != selected_units.size():
		_set_selected_units(valid, false)
	if not selected_buildings.is_empty():
		var valid_b: Array[Building] = []
		for item_b: Variant in selected_buildings:
			if is_instance_valid(item_b) and item_b is Building:
				var b: Building = item_b
				if not b.is_destroyed and not b.is_queued_for_deletion() and b.team == Unit.Team.PLAYER:
					valid_b.append(b)
		if valid_b.size() != selected_buildings.size():
			_set_selected_buildings(valid_b)
	if inspected_entity != null:
		if not is_instance_valid(inspected_entity):
			_set_inspected_entity(null)
		elif inspected_entity is Building and (inspected_entity as Building).is_destroyed:
			_set_inspected_entity(null)
		elif inspected_entity is Unit and (inspected_entity as Unit).is_dead:
			_set_inspected_entity(null)
		elif inspected_entity is ResourceNode and (inspected_entity as ResourceNode).is_depleted():
			_set_inspected_entity(null)


func _build_world_rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(a.x - b.x), absf(a.y - b.y)))


# =============================================================================
# PROCEDURAL TECHNOZEN COMMAND CURSORS (32x32, HOTSPOT 16,16)
# =============================================================================

func _build_command_cursors() -> void:
	_command_cursors.clear()
	_command_cursors[&"attack_move"] = _make_reticle_cursor(&"attack_move")
	_command_cursors[&"patrol"] = _make_reticle_cursor(&"patrol")
	_command_cursors[&"repair"] = _make_reticle_cursor(&"repair")
	_command_cursors[&"ability_target"] = _make_reticle_cursor(&"ability_target")


func _make_reticle_cursor(style: StringName) -> ImageTexture:
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var primary: Color = Color(1.0, 0.30, 0.43, 1.0) # Crimson #FF4D6D
	var secondary: Color = Color(1.0, 0.78, 0.84, 0.95)
	var shadow: Color = Color(0.02, 0.04, 0.07, 0.85)
	match style:
		&"patrol":
			primary = Color(0.22, 0.74, 0.97, 1.0) # Cyan/Azure #38BDF8
			secondary = Color(0.86, 0.97, 1.0, 0.96)
		&"repair":
			primary = Color(0.20, 0.83, 0.60, 1.0) # Emerald #34D399
			secondary = Color(0.84, 1.0, 0.92, 0.96)
		&"ability_target":
			primary = Color(0.96, 0.62, 0.04, 1.0) # Amber #F59E0B
			secondary = Color(0.76, 0.48, 1.0, 0.96) # Violet accent

	var put_px: Callable = func(px: int, py: int, col: Color) -> void:
		if px >= 0 and px < 32 and py >= 0 and py < 32:
			img.set_pixel(px, py, col)

	var draw_dot_outlined: Callable = func(px: int, py: int, col: Color) -> void:
		for oy: int in [-1, 0, 1]:
			for ox: int in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				var nx: int = px + ox
				var ny: int = py + oy
				if nx >= 0 and nx < 32 and ny >= 0 and ny < 32 and img.get_pixel(nx, ny).a < 0.05:
					img.set_pixel(nx, ny, shadow)
		put_px.call(px, py, col)

	var draw_seg: Callable = func(x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
		var steps: int = maxi(absi(x1 - x0), absi(y1 - y0))
		if steps <= 0:
			draw_dot_outlined.call(x0, y0, col)
			return
		for i: int in range(steps + 1):
			var t: float = float(i) / float(steps)
			var rx: int = int(round(lerpf(float(x0), float(x1), t)))
			var ry: int = int(round(lerpf(float(y0), float(y1), t)))
			draw_dot_outlined.call(rx, ry, col)

	var draw_ring: Callable = func(radius: float, col: Color) -> void:
		for a_i: int in range(64):
			var ang: float = TAU * float(a_i) / 64.0
			var rx: int = int(round(16.0 + cos(ang) * radius))
			var ry: int = int(round(16.0 + sin(ang) * radius))
			draw_dot_outlined.call(rx, ry, col)

	match style:
		&"attack_move":
			# Sharp crimson reticle with 4 corner brackets + cardinal ticks + hot center pip
			draw_seg.call(5, 5, 10, 5, primary)
			draw_seg.call(5, 5, 5, 10, primary)
			draw_seg.call(26, 5, 21, 5, primary)
			draw_seg.call(26, 5, 26, 10, primary)
			draw_seg.call(5, 26, 10, 26, primary)
			draw_seg.call(5, 26, 5, 21, primary)
			draw_seg.call(26, 26, 21, 26, primary)
			draw_seg.call(26, 26, 26, 21, primary)
			draw_seg.call(16, 4, 16, 11, primary)
			draw_seg.call(16, 21, 16, 28, primary)
			draw_seg.call(4, 16, 11, 16, primary)
			draw_seg.call(21, 16, 28, 16, primary)
			draw_seg.call(15, 16, 17, 16, secondary)
			draw_seg.call(16, 15, 16, 17, secondary)

		&"patrol":
			# Crisp cyan/azure reticle with ring + directional ticks + chevron accents
			draw_ring.call(10.0, primary)
			draw_seg.call(16, 2, 16, 8, secondary)
			draw_seg.call(16, 24, 16, 30, secondary)
			draw_seg.call(2, 16, 8, 16, secondary)
			draw_seg.call(24, 16, 30, 16, secondary)
			# Small directional diamond center
			draw_seg.call(16, 13, 19, 16, primary)
			draw_seg.call(19, 16, 16, 19, primary)
			draw_seg.call(16, 19, 13, 16, primary)
			draw_seg.call(13, 16, 16, 13, primary)

		&"repair":
			# Bioluminescent emerald reticle with bold inner repair cross + corner brackets
			draw_ring.call(11.0, primary)
			draw_seg.call(16, 10, 16, 22, secondary)
			draw_seg.call(15, 11, 15, 21, primary)
			draw_seg.call(17, 11, 17, 21, primary)
			draw_seg.call(10, 16, 22, 16, secondary)
			draw_seg.call(11, 15, 21, 15, primary)
			draw_seg.call(11, 17, 21, 17, primary)

		&"ability_target":
			# Luminous amber/violet concentric reticle + diagonal ticks
			draw_ring.call(11.5, primary)
			draw_ring.call(5.5, secondary)
			draw_seg.call(16, 2, 16, 6, primary)
			draw_seg.call(16, 26, 16, 30, primary)
			draw_seg.call(2, 16, 6, 16, primary)
			draw_seg.call(26, 16, 30, 16, primary)
			draw_dot_outlined.call(16, 16, secondary)

	return ImageTexture.create_from_image(img)


func _clear_custom_cursor() -> void:
	if _active_cursor_state != &"":
		_active_cursor_state = &""
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _apply_command_cursor(state: StringName) -> void:
	if _active_cursor_state == state:
		return
	if state == &"" or not _command_cursors.has(state):
		_clear_custom_cursor()
		return
	_active_cursor_state = state
	Input.set_custom_mouse_cursor(_command_cursors[state] as Texture2D, Input.CURSOR_ARROW, Vector2(16, 16))
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _is_any_modal_open() -> bool:
	if not is_inside_tree():
		return true
	if get_tree().paused:
		return true
	var pause_node: Node = get_tree().get_first_node_in_group("pause_menu")
	if pause_node != null and is_instance_valid(pause_node):
		if pause_node.has_method("is_pause_open") and bool(pause_node.call("is_pause_open")):
			return true
		if pause_node.has_method("is_settings_open") and bool(pause_node.call("is_settings_open")):
			return true
		if pause_node.has_method("is_tech_tree_open") and bool(pause_node.call("is_tech_tree_open")):
			return true
	var settings_node: Node = get_tree().get_first_node_in_group("settings_menu")
	if settings_node != null and is_instance_valid(settings_node) and not settings_node.is_queued_for_deletion():
		return true
	var tech_node: Node = get_tree().get_first_node_in_group("tech_tree_overlay")
	if tech_node != null and is_instance_valid(tech_node) and not tech_node.is_queued_for_deletion():
		return true
	var end_node: Node = get_tree().get_first_node_in_group("match_end_overlay")
	if end_node != null and is_instance_valid(end_node) and end_node.has_method("is_summary_visible"):
		if bool(end_node.call("is_summary_visible")):
			return true
	return false


func _is_hovering_repairable_target() -> bool:
	if command_router == null or selected_units.is_empty() or _is_dragging:
		return false
	var has_repairer: bool = false
	for u: Unit in selected_units:
		if is_instance_valid(u) and not u.is_dead and not u.is_staffed:
			var uid: StringName = u.get_unit_type_id()
			if uid == &"engineer" or uid == &"worker":
				has_repairer = true
				break
	if not has_repairer:
		return false
	var world_pt: Vector2 = get_global_mouse_position()
	var local_team: Unit.Team = (TeamManager.get_local_human_team() as Unit.Team) if (TeamManager != null and TeamManager.get_local_human_team() >= 0) else Unit.Team.PLAYER
	var hovered_u: Unit = command_router.find_unit_at_point(world_pt, local_team)
	if hovered_u != null:
		for u: Unit in selected_units:
			if is_instance_valid(u) and u.can_repair_target(hovered_u):
				return true
	var hovered_b: Building = command_router.find_building_at_point(world_pt, local_team)
	if hovered_b != null and hovered_b.is_constructed and hovered_b.current_hp < hovered_b.max_hp - 0.5:
		for u: Unit in selected_units:
			if is_instance_valid(u) and u.can_repair_target(hovered_b):
				return true
	return false


func _update_command_cursor() -> void:
	if _is_any_modal_open():
		_clear_custom_cursor()
		return
	if active_targeting_ability != null:
		_apply_command_cursor(&"ability_target")
		return
	if is_attack_move_targeting:
		_apply_command_cursor(&"attack_move")
		return
	if is_patrol_targeting:
		_apply_command_cursor(&"patrol")
		return
	if _is_hovering_repairable_target():
		_apply_command_cursor(&"repair")
		return
	_clear_custom_cursor()
