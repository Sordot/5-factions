class_name SelectionController
extends Node2D

const COMMAND_ROUTER_SCRIPT: GDScript = preload("res://scripts/controllers/command_router.gd")
const DOUBLE_TAP_WINDOW_MS: int = 350

signal selection_updated(selected_count: int)
signal selection_changed(selected_units: Array[Unit], subgroups: Array[Dictionary], active_subgroup_index: int)
signal building_selection_changed(building: Building)
signal inspection_changed(entity: Node)
signal control_groups_changed(summary: Dictionary)
signal ability_targeting_changed(active_ability: AbilityData)

@export var drag_threshold: float = 8.0
@export var camera_path: NodePath
@export var buildable_bounds: Rect2 = Rect2(-640.0, -360.0, 1280.0, 720.0)

@onready var selection_box: SelectionBox = $SelectionBox
@onready var ability_reticle: AbilityTargetingReticle = get_node_or_null("AbilityTargetingReticle") as AbilityTargetingReticle
@onready var build_ghost_preview: BuildGhostPreview = get_node_or_null("BuildGhostPreview") as BuildGhostPreview

var command_router: CommandRouter = null
var selected_units: Array[Unit] = []
var selected_building: Building = null
var inspected_entity: Node = null
var subgroups: Array[Dictionary] = []
var active_subgroup_index: int = 0
var inspected_enemy: Unit = null
var control_groups: Dictionary = {}
var active_targeting_ability: AbilityData = null

var _is_dragging: bool = false
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_start_screen: Vector2 = Vector2.ZERO
var _last_recall_group: int = -1
var _last_recall_time_ms: int = 0
var _last_click_unit: Unit = null
var _last_click_time_ms: int = 0
var _tracked_death_units: Array[Unit] = []


func _ready() -> void:
	command_router = get_node_or_null("CommandRouter") as CommandRouter
	if command_router == null:
		command_router = COMMAND_ROUTER_SCRIPT.new()
		command_router.name = "CommandRouter"
		add_child(command_router)
	command_router.buildable_bounds = buildable_bounds


func _process(_delta: float) -> void:
	if active_targeting_ability == null or command_router == null:
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

	if event.is_action_pressed("ui_cycle_subgroup"):
		if subgroups.size() > 1:
			cycle_subgroup()
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

	if event.is_action_pressed("cmd_ability_e") and selected_units.is_empty() and inspected_entity is Building:
		var b_node: Building = inspected_entity
		if is_instance_valid(b_node) and b_node.team == Unit.Team.PLAYER and b_node.max_staff_slots > 0 and b_node.get_assigned_engineer_count() > 0:
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

	if event.is_action_pressed("cmd_attack_move"):
		if event is InputEventKey:
			var a_key: InputEventKey = event
			if a_key.ctrl_pressed or a_key.shift_pressed or a_key.alt_pressed or a_key.echo:
				return
		cancel_ability_targeting()
		issue_attack_move_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_stop"):
		cancel_ability_targeting()
		issue_stop_command()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_hold"):
		cancel_ability_targeting()
		issue_hold_command()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if active_targeting_ability != null:
					confirm_ability_target_at(get_global_mouse_position())
					get_viewport().set_input_as_handled()
					return
				_is_dragging = true
				_drag_start_world = get_global_mouse_position()
				_drag_start_screen = mouse_event.position
			elif _is_dragging:
				_finish_left_selection(mouse_event.position, mouse_event.shift_pressed)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			if active_targeting_ability != null:
				cancel_ability_targeting()
				get_viewport().set_input_as_handled()
				return
			issue_right_click_at(get_global_mouse_position())
	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event: InputEventMouseMotion = event
		if motion_event.position.distance_to(_drag_start_screen) >= drag_threshold:
			var rect: Rect2 = _build_world_rect(_drag_start_world, get_global_mouse_position())
			selection_box.update_box(rect, true)


func clear_selection() -> void:
	cancel_ability_targeting()
	_set_inspected_entity(null)
	_set_selected_units([])


func select_in_world_rect(world_rect: Rect2) -> void:
	cancel_ability_targeting()
	_select_in_rect(world_rect, false)


func select_at_world_point(world_point: Vector2) -> void:
	cancel_ability_targeting()
	_select_at_point(world_point, false)


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


func request_ability_by_hotkey(hotkey: String) -> bool:
	var active: Dictionary = get_active_subgroup()
	if active.is_empty():
		return false
	var ability: AbilityData = SubgroupHelper.find_ability_by_hotkey(active, hotkey)
	if ability == null:
		return false
	return request_ability_slot(ability)


func request_ability_slot(ability: AbilityData) -> bool:
	if ability == null or command_router == null:
		return false
	_prune_invalid_units()
	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	if subgroup_units.is_empty():
		return false

	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		if ability.building_to_build == null:
			return false
		if command_router.find_closest_builder(subgroup_units, get_global_mouse_position()) == null:
			return false
		active_targeting_ability = ability
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		if ability_reticle != null:
			ability_reticle.clear_targeting()
		ability_targeting_changed.emit(active_targeting_ability)
		return true

	if not SubgroupHelper.has_any_ready_caster(subgroup_units, ability):
		return false

	if ability.target_type == AbilityData.TargetType.INSTANT:
		cancel_ability_targeting()
		var caster: Unit = SubgroupHelper.find_closest_ready_caster(subgroup_units, ability, get_global_mouse_position())
		if caster != null:
			return caster.command_cast_ability(ability, caster.global_position, caster)
		return false

	active_targeting_ability = ability
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	if build_ghost_preview != null:
		build_ghost_preview.clear_preview()
	ability_targeting_changed.emit(active_targeting_ability)
	return true


func confirm_ability_target_at(world_pos: Vector2) -> bool:
	if active_targeting_ability == null or command_router == null:
		return false
	var ability: AbilityData = active_targeting_ability
	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		var placed: bool = command_router.confirm_build_placement(ability, world_pos, get_active_subgroup_units())
		if placed:
			cancel_ability_targeting()
		return placed

	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	var target_enemy: Unit = command_router.find_unit_at_point(world_pos, Unit.Team.ENEMY)
	if ability.target_type == AbilityData.TargetType.UNIT_TARGET and target_enemy == null:
		return false

	var caster: Unit = SubgroupHelper.find_closest_ready_caster(subgroup_units, ability, world_pos)
	cancel_ability_targeting()
	if caster == null:
		return false

	var cast_point: Vector2 = target_enemy.global_position if target_enemy != null else world_pos
	var accepted: bool = caster.command_cast_ability(ability, cast_point, target_enemy)
	if accepted:
		command_router.spawn_move_marker(cast_point, MoveMarker.MarkerStyle.ATTACK)
	return accepted


func cancel_ability_targeting() -> void:
	if active_targeting_ability == null:
		return
	active_targeting_ability = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if ability_reticle != null:
		ability_reticle.clear_targeting()
	if build_ghost_preview != null:
		build_ghost_preview.clear_preview()
	ability_targeting_changed.emit(null)


func issue_right_click_at(world_point: Vector2) -> void:
	_prune_invalid_units()
	if command_router != null:
		command_router.handle_right_click(world_point, selected_units, inspected_entity)


func issue_attack_move_at(world_point: Vector2) -> void:
	_prune_invalid_units()
	if command_router != null:
		command_router.issue_attack_move(world_point, selected_units)


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
	if selected_units.is_empty():
		return
	control_groups[group_num] = selected_units.duplicate()
	_emit_control_groups_changed()


func append_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if selected_units.is_empty():
		return
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	for unit: Unit in selected_units:
		if not group_units.has(unit):
			group_units.append(unit)
	if not group_units.is_empty():
		control_groups[group_num] = group_units
	_emit_control_groups_changed()


func remove_from_control_group(group_num: int) -> void:
	if group_num < 1 or group_num > 9 or not control_groups.has(group_num):
		return
	_prune_invalid_units()
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	var remaining: Array[Unit] = []
	for unit: Unit in group_units:
		if not selected_units.has(unit):
			remaining.append(unit)
	if remaining.is_empty():
		control_groups.erase(group_num)
	else:
		control_groups[group_num] = remaining
	_emit_control_groups_changed()


func recall_control_group(group_num: int, allow_double_tap_center: bool = true) -> void:
	if group_num < 1 or group_num > 9:
		return
	var group_units: Array[Unit] = _get_pruned_group(group_num)
	if group_units.is_empty():
		control_groups.erase(group_num)
		_emit_control_groups_changed()
		return

	control_groups[group_num] = group_units
	cancel_ability_targeting()
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


func get_control_group_units(group_num: int) -> Array[Unit]:
	return _get_pruned_group(group_num)


func get_control_groups_summary() -> Dictionary:
	var summary: Dictionary = {}
	for num: int in range(1, 10):
		if not control_groups.has(num):
			continue
		var group_units: Array[Unit] = _get_pruned_group(num)
		if group_units.is_empty():
			control_groups.erase(num)
		else:
			control_groups[num] = group_units
			summary[num] = group_units.size()
	return summary


func clear_control_groups() -> void:
	control_groups.clear()
	_emit_control_groups_changed()


func _handle_control_group_key(group_num: int, key_event: InputEventKey) -> void:
	if key_event.ctrl_pressed:
		assign_control_group(group_num)
	elif key_event.shift_pressed:
		append_control_group(group_num)
	elif key_event.alt_pressed:
		remove_from_control_group(group_num)
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


func _emit_control_groups_changed() -> void:
	control_groups_changed.emit(get_control_groups_summary())


func _center_camera_on_units(units: Array[Unit]) -> void:
	if units.is_empty():
		return
	var cam: RTSCamera = _get_rts_camera()
	if cam == null:
		return
	var centroid: Vector2 = Vector2.ZERO
	for unit: Unit in units:
		centroid += unit.global_position
	centroid /= float(units.size())
	cam.center_on(centroid)


func _get_rts_camera() -> RTSCamera:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as RTSCamera
	if get_parent() != null:
		return get_parent().get_node_or_null("RTSCamera") as RTSCamera
	return null


func _finish_left_selection(end_screen_pos: Vector2, shift_pressed: bool = false) -> void:
	_is_dragging = false
	selection_box.update_box(Rect2(), false)
	var end_world_pos: Vector2 = get_global_mouse_position()
	if end_screen_pos.distance_to(_drag_start_screen) < drag_threshold:
		_select_at_point(end_world_pos, shift_pressed)
	else:
		_select_in_rect(_build_world_rect(_drag_start_world, end_world_pos), shift_pressed)


func _select_at_point(world_point: Vector2, shift_pressed: bool = false) -> void:
	if command_router == null:
		return

	var clicked_player: Unit = command_router.find_unit_at_point(world_point, Unit.Team.PLAYER)
	if clicked_player != null:
		_set_inspected_entity(null)
		var now_ms: int = Time.get_ticks_msec()
		if not shift_pressed and _last_click_unit == clicked_player and (now_ms - _last_click_time_ms) <= DOUBLE_TAP_WINDOW_MS:
			var same_type: Array[Unit] = _find_visible_units_of_type(clicked_player.get_unit_type_id(), Unit.Team.PLAYER)
			_last_click_unit = null
			_last_click_time_ms = 0
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
		_set_selected_units([])
		_set_inspected_entity(clicked_building)
		return

	var clicked_enemy: Unit = command_router.find_unit_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy != null:
		_set_selected_units([])
		_set_inspected_entity(clicked_enemy)
		return

	var clicked_enemy_building: Building = command_router.find_building_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy_building != null:
		_set_selected_units([])
		_set_inspected_entity(clicked_enemy_building)
		return

	var clicked_resource: ResourceNode = command_router.find_resource_node_at_point(world_point)
	if clicked_resource != null:
		_set_selected_units([])
		_set_inspected_entity(clicked_resource)
		return

	if not shift_pressed:
		_set_inspected_entity(null)
		_set_selected_units([])


func _select_in_rect(world_rect: Rect2, shift_pressed: bool = false) -> void:
	_last_click_unit = null
	_last_click_time_ms = 0
	var hits: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.is_staffed or unit.team != Unit.Team.PLAYER:
			continue
		if world_rect.has_point(unit.global_position):
			hits.append(unit)

	if shift_pressed and not selected_units.is_empty():
		var combined: Array[Unit] = selected_units.duplicate()
		for u: Unit in hits:
			if not combined.has(u):
				combined.append(u)
		_set_inspected_entity(null)
		_set_selected_units(combined, false)
	else:
		_set_inspected_entity(null)
		_set_selected_units(hits)


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

	selection_updated.emit(selected_units.size())
	selection_changed.emit(selected_units, subgroups, active_subgroup_index)


func _on_selected_unit_died(_dead_unit: Unit) -> void:
	_prune_invalid_units()


func _on_selected_unit_staffed(_unit: Unit, _staffed: bool) -> void:
	_prune_invalid_units()


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

	if prev_building != selected_building:
		building_selection_changed.emit(selected_building)
	inspection_changed.emit(inspected_entity)


func _on_inspected_entity_removed(_entity: Variant = null) -> void:
	_set_inspected_entity(null)


func _try_handle_ability_hotkey_event(event: InputEvent, action_name: StringName, hotkey_label: String) -> bool:
	if not event.is_action_pressed(action_name):
		return false
	if event is InputEventKey:
		var key_ev: InputEventKey = event
		if key_ev.ctrl_pressed or key_ev.shift_pressed or key_ev.alt_pressed or key_ev.echo:
			return false
	if request_ability_by_hotkey(hotkey_label):
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
