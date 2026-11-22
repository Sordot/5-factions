class_name SelectionController
extends Node2D

const MOVE_MARKER_SCRIPT: GDScript = preload("res://ui/overlays/move_marker.gd")
const DOUBLE_TAP_WINDOW_MS: int = 350
const DEFAULT_UNIT_RADIUS: float = 16.0
const RING_SPACING_MULTIPLIER: float = 2.6
const VENT_SNAP_RADIUS: float = 64.0
const ARENA_BOUNDS: Rect2 = Rect2(-640.0, -360.0, 1280.0, 720.0)
const CENTRAL_OBSTACLE_RECT: Rect2 = Rect2(-80.0, -100.0, 160.0, 200.0)

signal selection_updated(selected_count: int)
signal selection_changed(selected_units: Array[Unit], subgroups: Array[Dictionary], active_subgroup_index: int)
signal building_selection_changed(building: Building)
signal inspection_changed(entity: Node)
signal control_groups_changed(summary: Dictionary)
signal ability_targeting_changed(active_ability: AbilityData)

@export var drag_threshold: float = 8.0
@export var camera_path: NodePath

@onready var selection_box: SelectionBox = $SelectionBox
@onready var ability_reticle: AbilityTargetingReticle = get_node_or_null("AbilityTargetingReticle") as AbilityTargetingReticle
@onready var build_ghost_preview: BuildGhostPreview = get_node_or_null("BuildGhostPreview") as BuildGhostPreview

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


func _process(_delta: float) -> void:
	if active_targeting_ability == null:
		return
	var cursor_world: Vector2 = get_global_mouse_position()
	if active_targeting_ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		var builder: Unit = _find_closest_builder(get_active_subgroup_units(), cursor_world)
		if builder == null or active_targeting_ability.building_to_build == null:
			cancel_ability_targeting()
			return
		if ability_reticle != null:
			ability_reticle.clear_targeting()
		if build_ghost_preview != null:
			var eval: Dictionary = _evaluate_build_placement(active_targeting_ability.building_to_build, cursor_world)
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
			_handle_right_click(get_global_mouse_position())
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
	if index < 0 or index >= subgroups.size():
		return
	if active_subgroup_index == index:
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
	if ability == null:
		return false
	_prune_invalid_units()
	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	if subgroup_units.is_empty():
		return false

	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		if ability.building_to_build == null:
			return false
		var builder: Unit = _find_closest_builder(subgroup_units, get_global_mouse_position())
		if builder == null:
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
		var caster: Unit = SubgroupHelper.find_closest_ready_caster(
			subgroup_units,
			ability,
			get_global_mouse_position()
		)
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
	if active_targeting_ability == null:
		return false
	var ability: AbilityData = active_targeting_ability
	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
		return _confirm_build_placement(ability, world_pos)

	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	var target_enemy: Unit = _find_unit_at_point(world_pos, Unit.Team.ENEMY)

	if ability.target_type == AbilityData.TargetType.UNIT_TARGET and target_enemy == null:
		return false

	var caster: Unit = SubgroupHelper.find_closest_ready_caster(subgroup_units, ability, world_pos)
	cancel_ability_targeting()
	if caster == null:
		return false

	var cast_point: Vector2 = target_enemy.global_position if target_enemy != null else world_pos
	var accepted: bool = caster.command_cast_ability(ability, cast_point, target_enemy)
	if accepted:
		_spawn_move_marker(cast_point, MoveMarker.MarkerStyle.ATTACK)
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
	_handle_right_click(world_point)


func issue_attack_move_at(world_point: Vector2) -> void:
	_prune_invalid_units()
	if selected_units.is_empty():
		return

	var clicked_enemy: Unit = _find_unit_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy)
		_spawn_move_marker(clicked_enemy.global_position, MoveMarker.MarkerStyle.ATTACK)
	else:
		var targets: Array[Vector2] = _assign_group_destinations(selected_units, world_point)
		for i: int in range(selected_units.size()):
			selected_units[i].command_attack_move(targets[i])
		_spawn_move_marker(world_point, MoveMarker.MarkerStyle.ATTACK)


func issue_stop_command() -> void:
	_prune_invalid_units()
	for unit: Unit in selected_units:
		unit.command_stop()


func issue_hold_command() -> void:
	_prune_invalid_units()
	for unit: Unit in selected_units:
		unit.command_hold_position()


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
	if group_num < 1 or group_num > 9:
		return
	_prune_invalid_units()
	if not control_groups.has(group_num):
		return
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
	# 1. Friendly player unit (supports Shift+Click toggle & Double-Click type select)
	var clicked_player: Unit = _find_unit_at_point(world_point, Unit.Team.PLAYER)
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

	# 2. Friendly player building -> inspect (and command if commandable)
	var clicked_building: Building = _find_building_at_point(world_point, Unit.Team.PLAYER)
	if clicked_building != null:
		_set_selected_units([])
		_set_inspected_entity(clicked_building)
		return

	# 3. Enemy unit / TargetDummy -> read-only inspection
	var clicked_enemy: Unit = _find_unit_at_point(world_point, Unit.Team.ENEMY)
	if clicked_enemy != null:
		_set_selected_units([])
		_set_inspected_entity(clicked_enemy)
		return

	# 4. ResourceNode (BiomassNode, SilicaVein, ComputeVent) -> read-only inspection
	var clicked_resource: ResourceNode = _find_resource_node_at_point(world_point)
	if clicked_resource != null:
		_set_selected_units([])
		_set_inspected_entity(clicked_resource)
		return

	# 5. Empty ground
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
		if not is_instance_valid(unit) or unit.is_dead or unit.is_staffed:
			continue
		if unit.team != Unit.Team.PLAYER:
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
		if unit.is_dead or unit.is_staffed or unit.team != target_team:
			continue
		if unit.get_unit_type_id() != type_id:
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

	# Clean up previous inspected entity
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

	# Activate visual ring & lifecycle tracker on new inspected entity
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


func _handle_right_click(world_pos: Vector2) -> void:
	_prune_invalid_units()
	if selected_units.is_empty():
		return

	var clicked_enemy: Unit = _find_unit_at_point(world_pos, Unit.Team.ENEMY)
	if clicked_enemy != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy)
		_spawn_move_marker(clicked_enemy.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	var clicked_resource: ResourceNode = _find_resource_node_at_point(world_pos)
	if clicked_resource != null and not clicked_resource.is_vent and _has_any_gatherer_for(selected_units, clicked_resource.resource_type):
		var non_gatherers: Array[Unit] = []
		for unit: Unit in selected_units:
			if unit.can_gather_resource(clicked_resource.resource_type):
				unit.command_gather(clicked_resource)
			else:
				non_gatherers.append(unit)
		if not non_gatherers.is_empty():
			var escort_targets: Array[Vector2] = _assign_group_destinations(non_gatherers, clicked_resource.global_position)
			for i: int in range(non_gatherers.size()):
				non_gatherers[i].command_move(escort_targets[i])
		_spawn_move_marker(clicked_resource.global_position, MoveMarker.MarkerStyle.GATHER)
		return

	var clicked_building: Building = _find_building_at_point(world_pos, Unit.Team.PLAYER)
	if clicked_building != null:
		if not clicked_building.is_constructed:
			var builders: Array[Unit] = []
			for unit: Unit in selected_units:
				if unit.can_construct():
					builders.append(unit)
			if not builders.is_empty():
				for worker: Unit in builders:
					worker.command_construct_building(clicked_building)
				_spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.GATHER)
				return

		if clicked_building.is_constructed and clicked_building.max_staff_slots > 0:
			var engineers: Array[Unit] = []
			var others: Array[Unit] = []
			for unit: Unit in selected_units:
				if unit.can_staff_compute() and clicked_building.can_accept_staff(unit):
					engineers.append(unit)
				else:
					others.append(unit)
			if not engineers.is_empty():
				for eng: Unit in engineers:
					eng.command_staff_building(clicked_building)
				if not others.is_empty():
					var move_targets_eng: Array[Vector2] = _assign_group_destinations(others, world_pos)
					for i: int in range(others.size()):
						others[i].command_move(move_targets_eng[i])
				_spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.GATHER)
				return

		if clicked_building.is_constructed and clicked_building.is_resource_dropoff:
			var returning_workers: Array[Unit] = []
			var other_units: Array[Unit] = []
			for unit: Unit in selected_units:
				if unit.can_gather() and unit.is_carrying_cargo() and clicked_building.accepts_resource(unit.get_carried_type()):
					returning_workers.append(unit)
				else:
					other_units.append(unit)
			if not returning_workers.is_empty():
				for worker: Unit in returning_workers:
					worker.command_return_cargo(clicked_building)
				if not other_units.is_empty():
					var move_targets: Array[Vector2] = _assign_group_destinations(other_units, world_pos)
					for i: int in range(other_units.size()):
						other_units[i].command_move(move_targets[i])
				_spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.GATHER)
				return

	var targets: Array[Vector2] = _assign_group_destinations(selected_units, world_pos)
	for i: int in range(selected_units.size()):
		selected_units[i].command_move(targets[i])
	_spawn_move_marker(world_pos, MoveMarker.MarkerStyle.MOVE)


func _assign_group_destinations(units: Array[Unit], center_pos: Vector2) -> Array[Vector2]:
	var count: int = units.size()
	var assigned: Array[Vector2] = []
	if count == 0:
		return assigned

	var map_rid: RID = _get_navigation_map(units[0])
	var has_map: bool = map_rid.is_valid() and NavigationServer2D.map_get_iteration_id(map_rid) > 0
	if count == 1:
		var single_pos: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, center_pos) if has_map else center_pos
		assigned.append(single_pos)
		return assigned

	var unit_radius: float = units[0].data.collision_radius if units[0].data != null else DEFAULT_UNIT_RADIUS
	var spacing: float = unit_radius * RING_SPACING_MULTIPLIER
	var slots: Array[Vector2] = _generate_ring_slots(count, center_pos, spacing, map_rid, has_map)

	var used: Array[bool] = []
	used.resize(slots.size())
	used.fill(false)
	assigned.resize(count)

	for i: int in range(count):
		var u_pos: Vector2 = units[i].global_position
		var best_idx: int = 0
		var best_dist_sq: float = INF
		for s_idx: int in range(slots.size()):
			if used[s_idx]:
				continue
			var d_sq: float = u_pos.distance_squared_to(slots[s_idx])
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_idx = s_idx
		used[best_idx] = true
		assigned[i] = slots[best_idx]

	return assigned


func _generate_ring_slots(count: int, center_pos: Vector2, spacing: float, map_rid: RID, has_map: bool) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var first_pos: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, center_pos) if has_map else center_pos
	slots.append(first_pos)

	var ring: int = 1
	while slots.size() < count:
		var ring_radius: float = float(ring) * spacing
		var circumference: float = TAU * ring_radius
		var ring_slots: int = maxi(6, int(round(circumference / spacing)))
		var angle_offset: float = 0.0 if (ring % 2) == 1 else (PI / float(ring_slots))
		for k: int in range(ring_slots):
			if slots.size() >= count:
				break
			var angle: float = angle_offset + (TAU * float(k) / float(ring_slots))
			var candidate: Vector2 = center_pos + Vector2.RIGHT.rotated(angle) * ring_radius
			if has_map:
				candidate = NavigationServer2D.map_get_closest_point(map_rid, candidate)
			slots.append(candidate)
		ring += 1

	return slots


func _get_navigation_map(sample_unit: Unit) -> RID:
	if sample_unit != null and sample_unit.nav_agent != null:
		return sample_unit.nav_agent.get_navigation_map()
	return get_world_2d().navigation_map


func _find_unit_at_point(world_point: Vector2, target_team: Unit.Team) -> Unit:
	var closest: Unit = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.team != target_team:
			continue
		if unit.contains_point(world_point):
			var dist_sq: float = unit.global_position.distance_squared_to(world_point)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest = unit
	return closest


func _find_building_at_point(world_point: Vector2, target_team: Unit.Team) -> Building:
	var closest: Building = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_buildings"):
		if not (node is Building):
			continue
		var building: Building = node
		if not is_instance_valid(building) or building.is_destroyed or building.team != target_team:
			continue
		if building.contains_point(world_point):
			var dist_sq: float = building.global_position.distance_squared_to(world_point)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest = building
	return closest


func _find_resource_node_at_point(world_point: Vector2) -> ResourceNode:
	var closest: ResourceNode = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode):
			continue
		var res_node: ResourceNode = node
		if not is_instance_valid(res_node) or res_node.is_depleted():
			continue
		if res_node.contains_point(world_point):
			var dist_sq: float = res_node.global_position.distance_squared_to(world_point)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest = res_node
	return closest


func _has_any_gatherer_for(units: Array[Unit], resource_type: StringName) -> bool:
	for unit: Unit in units:
		if is_instance_valid(unit) and not unit.is_dead and unit.can_gather_resource(resource_type):
			return true
	return false


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


func _find_closest_builder(units: Array[Unit], target_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_dist_sq: float = INF
	for item: Variant in units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if not unit.can_construct():
			continue
		var d_sq: float = unit.global_position.distance_squared_to(target_pos)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = unit
	return best


func _evaluate_build_placement(building_data: BuildingData, cursor_world: Vector2) -> Dictionary:
	var result: Dictionary = {
		"pos": cursor_world,
		"valid": false,
		"reason": "",
		"vent": null,
	}
	if building_data == null or building_data.scene == null:
		result["reason"] = "Invalid building"
		return result

	var place_pos: Vector2 = cursor_world
	var snapped_vent: ResourceNode = null
	if building_data.requires_vent:
		snapped_vent = _find_nearest_unoccupied_vent(cursor_world, VENT_SNAP_RADIUS)
		if snapped_vent == null:
			result["reason"] = "Must be built on a Compute Vent"
			return result
		place_pos = snapped_vent.global_position
		result["pos"] = place_pos
		result["vent"] = snapped_vent

	var half: Vector2 = building_data.footprint_size * 0.5
	var new_radius: float = building_data.get_footprint_radius()

	# Check arena bounds
	var safe_bounds: Rect2 = Rect2(
		ARENA_BOUNDS.position + half + Vector2(8.0, 8.0),
		ARENA_BOUNDS.size - building_data.footprint_size - Vector2(16.0, 16.0)
	)
	if not safe_bounds.has_point(place_pos):
		result["reason"] = "Out of buildable bounds"
		return result

	# Check central obstacle
	var obstacle_expanded: Rect2 = CENTRAL_OBSTACLE_RECT.grow_individual(half.x + 6.0, half.y + 6.0, half.x + 6.0, half.y + 6.0)
	if obstacle_expanded.has_point(place_pos):
		result["reason"] = "Blocked by terrain"
		return result

	# Check existing buildings overlap
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var existing: Building = node
		if existing.is_destroyed:
			continue
		var min_dist: float = existing.footprint_radius + new_radius + 10.0
		if existing.global_position.distance_squared_to(place_pos) < min_dist * min_dist:
			result["reason"] = "Blocked by structure"
			return result

	# Check non-vent resource nodes overlap
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var res_node: ResourceNode = node
		if res_node.is_depleted() or res_node.is_vent:
			continue
		var min_dist: float = res_node.collision_radius + new_radius + 8.0
		if res_node.global_position.distance_squared_to(place_pos) < min_dist * min_dist:
			result["reason"] = "Too close to resource node"
			return result

	# Check affordability
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null and not econ.can_afford(Unit.Team.PLAYER, building_data.get_cost_dict()):
		result["reason"] = "Need %s" % building_data.get_cost_label()
		return result

	result["valid"] = true
	result["reason"] = "%s (%s)" % [building_data.display_name, building_data.get_cost_label()]
	return result


func _find_nearest_unoccupied_vent(world_point: Vector2, max_radius: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var res_node: ResourceNode = node
		if not res_node.is_vent or res_node.is_occupied():
			continue
		var d_sq: float = res_node.global_position.distance_squared_to(world_point)
		if d_sq <= best_dist_sq:
			best_dist_sq = d_sq
			best = res_node
	return best


func _confirm_build_placement(ability: AbilityData, world_pos: Vector2) -> bool:
	var building_data: BuildingData = ability.building_to_build
	if building_data == null or building_data.scene == null:
		cancel_ability_targeting()
		return false

	var eval: Dictionary = _evaluate_build_placement(building_data, world_pos)
	if not bool(eval["valid"]):
		return false

	var builder: Unit = _find_closest_builder(get_active_subgroup_units(), eval["pos"])
	if builder == null:
		cancel_ability_targeting()
		return false

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		if not econ.spend_resources(Unit.Team.PLAYER, building_data.get_cost_dict()):
			return false

	var buildings_container: Node = get_parent().get_node_or_null("Buildings") if get_parent() != null else null
	if buildings_container == null:
		buildings_container = get_parent()
	if buildings_container == null:
		return false

	var instance: Node = building_data.scene.instantiate()
	if not (instance is Building):
		instance.queue_free()
		return false

	var new_building: Building = instance
	new_building.global_position = eval["pos"]
	new_building.is_constructed = false
	buildings_container.add_child(new_building)
	new_building.begin_construction(building_data, Unit.Team.PLAYER, eval["vent"] as ResourceNode)
	_nudge_units_out_of_building(new_building)

	builder.command_construct_building(new_building)
	_spawn_move_marker(new_building.global_position, MoveMarker.MarkerStyle.GATHER)
	cancel_ability_targeting()
	return true


func _nudge_units_out_of_building(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed:
			continue
		var unit_r: float = unit.data.collision_radius if unit.data != null else 14.0
		var min_dist: float = building.footprint_radius + unit_r + 6.0
		var diff: Vector2 = unit.global_position - building.global_position
		if diff.length_squared() < min_dist * min_dist:
			var dir: Vector2 = diff.normalized() if diff.length_squared() > 0.01 else Vector2.RIGHT
			unit.global_position = building.global_position + dir * min_dist


func _spawn_move_marker(target_pos: Vector2, marker_style: MoveMarker.MarkerStyle) -> void:
	if get_parent() == null:
		return
	var marker: MoveMarker = MOVE_MARKER_SCRIPT.new()
	marker.global_position = target_pos
	marker.z_index = 60
	get_parent().add_child(marker)
	marker.configure(marker_style)


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
	var top_left: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size: Vector2 = Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(top_left, size)
