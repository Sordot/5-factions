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
signal overclock_targeting_changed(active: bool)
signal idle_workers_changed(idle_workers: Array[Unit])
signal idle_workers_updated(count: int)
signal idle_production_updated(count: int)
signal army_count_updated(count: int)
signal hud_toast_requested(message: String)

@export var drag_threshold: float = 4.0
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
var is_overclock_targeting: bool = false
var idle_worker_count: int = 0
var idle_production_count: int = 0
var army_unit_count: int = 0

var _is_dragging: bool = false
var _drag_box_active: bool = false
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_start_screen: Vector2 = Vector2.ZERO
var _marquee_preview_entities: Array[Node] = []
var _hovered_entity: Node = null
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
var _idle_prod_cycle_index: int = -1
var _last_idle_prod_click_ms: int = 0
var _last_idle_prod_building: Building = null
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

	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)

	call_deferred("_refresh_idle_workers", true)


func _exit_tree() -> void:
	_clear_marquee_preview()
	_set_hovered_entity(null)
	if SettingsManager != null and SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.disconnect(_on_settings_changed)
	_clear_custom_cursor()


func _on_settings_changed(category: StringName) -> void:
	if category != &"gameplay" and category != &"all":
		return
	if SettingsManager != null and SettingsManager.attack_move_mode == SettingsManager.AttackMoveMode.QUICK_CAST:
		if is_attack_move_targeting:
			cancel_attack_move_targeting()
			_clear_custom_cursor()
	if _is_dragging and _drag_box_active:
		if selection_box != null:
			selection_box.queue_redraw()
		var rect: Rect2 = _build_world_rect(_drag_start_world, get_global_mouse_position())
		_update_marquee_preview(rect)
		for ent: Node in _marquee_preview_entities:
			if is_instance_valid(ent) and ent is CanvasItem:
				(ent as CanvasItem).queue_redraw()
				var ev: Node = ent.get_node_or_null("BodyVisual/EntityVisuals")
				if ev is CanvasItem:
					(ev as CanvasItem).queue_redraw()


func _process(delta: float) -> void:
	_idle_refresh_timer += delta
	if _idle_refresh_timer >= 0.15:
		_idle_refresh_timer = 0.0
		_refresh_idle_workers(false)

	if _is_dragging:
		_update_active_drag_marquee()
	_update_hover_target()

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
		if is_overclock_targeting:
			var oc_hub: Building = find_ready_overclock_hub()
			if oc_hub == null or command_router == null:
				cancel_overclock_targeting()
			elif ability_reticle != null:
				var oc_cursor: Vector2 = get_global_mouse_position()
				var oc_b: Building = command_router.find_building_at_point(oc_cursor, _get_local_human_team_enum())
				var oc_valid: bool = oc_b != null and oc_b.is_valid_overclock_target(int(oc_hub.team))
				ability_reticle.set_overclock_targeting(oc_cursor, oc_b if oc_valid else null, oc_valid)
			return
		if ability_reticle != null:
			ability_reticle.clear_overclock_targeting()
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
			var eval: Dictionary = command_router.evaluate_build_placement(active_targeting_ability.building_to_build, cursor_world, _get_local_human_team_enum(), true)
			build_ghost_preview.set_preview(
				active_targeting_ability.building_to_build,
				eval["pos"],
				eval["valid"],
				eval["reason"],
				eval["vent"],
				bool(eval.get("grid_snapped", false))
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


func _input(event: InputEvent) -> void:
	if not _is_dragging:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			var was_box: bool = _drag_box_active
			_finish_left_selection(
				mb.position,
				mb.shift_pressed or Input.is_key_pressed(KEY_SHIFT),
				_click_was_double_click,
				_click_ctrl_pressed or mb.ctrl_pressed
			)
			if was_box:
				get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _drag_box_active:
			_cancel_drag_box()
			get_viewport().set_input_as_handled()
			return
	elif event.is_action_pressed("cmd_cancel") and _drag_box_active:
		_cancel_drag_box()
		get_viewport().set_input_as_handled()


func _is_post_match_inspection() -> bool:
	if not is_inside_tree():
		return false
	var mm: Node = get_tree().get_first_node_in_group("match_manager")
	return mm != null and is_instance_valid(mm) and bool(mm.get("is_inspecting_post_match"))


func _unhandled_input(event: InputEvent) -> void:
	if _is_post_match_inspection():
		if event is InputEventMouseButton:
			var pm_mb: InputEventMouseButton = event
			if pm_mb.button_index == MOUSE_BUTTON_LEFT and pm_mb.pressed:
				_select_at_point(get_global_mouse_position(), false, false, false)
				get_viewport().set_input_as_handled()
			elif pm_mb.button_index == MOUSE_BUTTON_RIGHT and pm_mb.pressed:
				get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cmd_cancel"):
		if _is_dragging:
			_cancel_drag_box()
			get_viewport().set_input_as_handled()
			return
		if active_targeting_ability != null:
			cancel_ability_targeting()
			get_viewport().set_input_as_handled()
			return
		if is_overclock_targeting:
			cancel_overclock_targeting()
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
		var help_open: bool = get_tree().get_first_node_in_group("controls_reference_overlay") != null
		if pause_menu != null and not pause_menu.is_settings_open() and not pause_menu.is_tech_tree_open() and not pause_menu.is_controls_help_open() and not help_open:
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

	if event.is_action_pressed("cmd_select_idle_production") and not event.is_echo():
		var allow_prod_hotkey: bool = true
		var shift_prod: bool = Input.is_key_pressed(KEY_SHIFT)
		if event is InputEventKey:
			var prod_k: InputEventKey = event
			if prod_k.ctrl_pressed or prod_k.alt_pressed:
				allow_prod_hotkey = false
			shift_prod = shift_prod or prod_k.shift_pressed
		if allow_prod_hotkey:
			if select_next_idle_production(true, shift_prod) > 0 or event is InputEventMouseButton:
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

	if event.is_action_pressed("cmd_toggle_smart_box_select") and not event.is_echo():
		var allow_smart_toggle: bool = true
		if event is InputEventKey:
			var smart_k: InputEventKey = event
			if smart_k.ctrl_pressed or smart_k.alt_pressed:
				allow_smart_toggle = false
		if allow_smart_toggle:
			_toggle_smart_box_select_hotkey()
			get_viewport().set_input_as_handled()
			return

	if _try_handle_ability_hotkey_event(event, "cmd_ability_q", "Q"):
		return
	if _try_handle_building_hotkey_event(event, &"cmd_ability_q", &"train", 0):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_w", "W"):
		return
	if _try_handle_building_hotkey_event(event, &"cmd_ability_w", &"train", 1):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_e", "E"):
		return
	if _try_handle_building_hotkey_event(event, &"cmd_ability_e", &"train", 2):
		return
	if event.is_action_pressed("cmd_ability_e") and not event.is_echo():
		var allow_e_key: bool = true
		if event is InputEventKey:
			var e_key: InputEventKey = event
			if e_key.ctrl_pressed or e_key.alt_pressed:
				allow_e_key = false
		if allow_e_key and not selected_units.is_empty():
			if toggle_deploy_active_subgroup():
				get_viewport().set_input_as_handled()
				return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_r", "R"):
		return
	if _try_handle_building_hotkey_event(event, &"cmd_ability_r", &"upgrade", 0):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_t", "T"):
		return
	if _try_handle_building_hotkey_event(event, &"cmd_ability_t", &"upgrade", 1):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_y", "Y"):
		return
	if _try_handle_ability_hotkey_event(event, "cmd_ability_f", "F"):
		return
	if _try_handle_building_hotkey_event(event, &"cmd_ability_f", &"facility_special", 0):
		return
	if event is InputEventKey:
		var g_key: InputEventKey = event as InputEventKey
		if g_key.pressed and not g_key.echo and not g_key.ctrl_pressed and not g_key.alt_pressed and (g_key.physical_keycode == KEY_G or g_key.keycode == KEY_G):
			if not selected_units.is_empty() and request_ability_by_hotkey("G", g_key.shift_pressed or Input.is_key_pressed(KEY_SHIFT)):
				get_viewport().set_input_as_handled()
				return

	# Convenience fallback: E still ejects engineers on pure compute facilities (0 trainable units).
	if event.is_action_pressed("cmd_ability_e") and not event.is_echo() and selected_units.is_empty() and inspected_entity is Building:
		var allow_e_eject: bool = true
		if event is InputEventKey:
			var e_ej_key: InputEventKey = event as InputEventKey
			if e_ej_key.ctrl_pressed or e_ej_key.alt_pressed:
				allow_e_eject = false
		var b_node: Building = inspected_entity as Building
		var b_local: bool = TeamManager.is_team_controlled_by_local_human(int(b_node.team)) if TeamManager != null else (b_node.team == Unit.Team.PLAYER)
		if allow_e_eject and is_instance_valid(b_node) and b_local and b_node.is_constructed and b_node.trainable_unit_data.is_empty() and b_node.max_staff_slots > 0 and b_node.get_assigned_engineer_count() > 0:
			eject_engineers_from_selected_buildings()
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
		var shift_amove: bool = Input.is_key_pressed(KEY_SHIFT)
		if event is InputEventKey:
			var a_key: InputEventKey = event
			if a_key.ctrl_pressed or a_key.alt_pressed:
				return
			shift_amove = shift_amove or a_key.shift_pressed
		_prune_invalid_units()
		if _has_selected_combat_capable_unit():
			var use_click_confirm: bool = (
				SettingsManager != null
				and SettingsManager.attack_move_mode == SettingsManager.AttackMoveMode.CLICK_TO_CONFIRM
			)
			if use_click_confirm:
				begin_attack_move_targeting()
			else:
				cancel_ability_targeting()
				cancel_attack_move_targeting()
				cancel_patrol_targeting()
				issue_attack_move_at(get_global_mouse_position(), shift_amove)
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

	if event.is_action_pressed("cmd_defensive_stance") and not event.is_echo():
		if event is InputEventKey:
			var d_key: InputEventKey = event
			if d_key.ctrl_pressed or d_key.alt_pressed:
				return
		if not selected_units.is_empty():
			cancel_ability_targeting()
			cancel_attack_move_targeting()
			cancel_patrol_targeting()
			issue_defensive_command()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
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
				if is_overclock_targeting:
					confirm_overclock_target_at(get_global_mouse_position())
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
				_drag_box_active = false
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
			if _is_dragging:
				_cancel_drag_box()
				get_viewport().set_input_as_handled()
				return
			if active_targeting_ability != null:
				cancel_ability_targeting()
				get_viewport().set_input_as_handled()
				return
			if is_overclock_targeting:
				cancel_overclock_targeting()
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
		_update_active_drag_marquee()


func clear_selection() -> void:
	cancel_ability_targeting()
	cancel_overclock_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_set_selected_buildings([])
	_set_inspected_entity(null)
	_set_selected_units([])


func select_in_world_rect(world_rect: Rect2) -> void:
	cancel_ability_targeting()
	cancel_overclock_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_select_in_rect(world_rect, false)


func select_at_world_point(world_point: Vector2) -> void:
	cancel_ability_targeting()
	cancel_overclock_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_select_at_point(world_point, false)


func select_single_entity(entity: Node, focus_camera: bool = false) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	cancel_ability_targeting()
	cancel_overclock_targeting()
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
	_play_active_subgroup_bark()
	selection_changed.emit(selected_units, subgroups, active_subgroup_index)


func set_active_subgroup(index: int) -> void:
	if index < 0 or index >= subgroups.size() or active_subgroup_index == index:
		return
	cancel_ability_targeting()
	active_subgroup_index = index
	_play_active_subgroup_bark()
	selection_changed.emit(selected_units, subgroups, active_subgroup_index)


func _play_active_subgroup_bark() -> void:
	if AudioManager == null or subgroups.is_empty():
		return
	var active_units: Array[Unit] = get_active_subgroup_units()
	if active_units.is_empty():
		return
	var lead: Unit = active_units[0]
	if is_instance_valid(lead) and not lead.is_dead:
		var cls: StringName = lead.data.audio_bark_class if (lead.data != null and lead.data.audio_bark_class != &"") else AudioManager.classify_unit_bark_class(lead.get_unit_type_id())
		AudioManager.play_selection_audio(active_units, cls)


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
		var local_t: Unit.Team = _get_local_human_team_enum()
		var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
		if ability.building_to_build.required_building_id != &"":
			if econ == null or not econ.has_constructed_building(local_t, ability.building_to_build.required_building_id):
				if AudioManager != null:
					AudioManager.play_error()
				return false
		if econ != null and not econ.can_afford(local_t, ability.building_to_build.get_cost_dict()):
			var missing: StringName = econ.find_missing_resource(local_t, ability.building_to_build.get_cost_dict(), 0)
			if missing != &"":
				econ.notify_insufficient(local_t, missing)
			return false
		if command_router.find_closest_builder(subgroup_units, get_global_mouse_position()) == null:
			return false
		cancel_overclock_targeting()
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

	cancel_overclock_targeting()
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
				keep_placing = (econ == null or econ.can_afford(_get_local_human_team_enum(), ability.building_to_build.get_cost_dict()))
			if not keep_placing:
				cancel_ability_targeting()
		return placed

	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	var target_enemy: Unit = command_router.find_hostile_unit_at_point(world_pos, int(_get_local_human_team_enum()))
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
	if not _has_selected_combat_capable_unit():
		return
	cancel_ability_targeting()
	cancel_overclock_targeting()
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
	cancel_overclock_targeting()
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
	cancel_overclock_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_clear_custom_cursor()


func has_selected_overclock_hub() -> bool:
	var local_t: Unit.Team = _get_local_human_team_enum()
	for b: Building in selected_buildings:
		if is_instance_valid(b) and not b.is_destroyed and b.is_constructed and b.team == local_t and b.has_overclock_ability():
			return true
	if selected_building != null and is_instance_valid(selected_building):
		if not selected_building.is_destroyed and selected_building.is_constructed and selected_building.team == local_t and selected_building.has_overclock_ability():
			return true
	return false


func find_ready_overclock_hub() -> Building:
	var local_t: Unit.Team = _get_local_human_team_enum()
	for b: Building in selected_buildings:
		if is_instance_valid(b) and b.team == local_t and b.can_cast_overclock():
			return b
	if selected_building != null and is_instance_valid(selected_building):
		if selected_building.team == local_t and selected_building.can_cast_overclock():
			return selected_building
	return null


func begin_overclock_targeting() -> bool:
	_prune_invalid_units()
	var hub: Building = find_ready_overclock_hub()
	if hub == null:
		return false
	cancel_ability_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	is_overclock_targeting = true
	_update_command_cursor()
	if AudioManager != null:
		AudioManager.play_ui_click()
	overclock_targeting_changed.emit(true)
	return true


func cancel_overclock_targeting() -> void:
	if not is_overclock_targeting:
		return
	is_overclock_targeting = false
	if ability_reticle != null:
		ability_reticle.clear_overclock_targeting()
	_update_command_cursor()
	overclock_targeting_changed.emit(false)


func confirm_overclock_target_at(world_pos: Vector2) -> bool:
	if not is_overclock_targeting or command_router == null:
		return false
	var hub: Building = find_ready_overclock_hub()
	if hub == null:
		cancel_overclock_targeting()
		return false
	var target_b: Building = command_router.find_building_at_point(world_pos, _get_local_human_team_enum())
	if target_b == null or not target_b.is_valid_overclock_target(int(hub.team)):
		if AudioManager != null:
			AudioManager.play_error()
		return false
	var cast_ok: bool = hub.cast_overclock_on(target_b)
	if cast_ok:
		command_router.spawn_move_marker(target_b.global_position, MoveMarker.MarkerStyle.INTERACT)
		cancel_overclock_targeting()
	return cast_ok


func toggle_deploy_active_subgroup() -> bool:
	_prune_invalid_units()
	var subgroup_units: Array[Unit] = get_active_subgroup_units()
	var deployables: Array[Unit] = []
	var has_mobile_or_undeploying: bool = false
	for u: Unit in subgroup_units:
		if is_instance_valid(u) and u.can_toggle_deploy():
			deployables.append(u)
			if u.deploy_state == Unit.DeployState.MOBILE or u.deploy_state == Unit.DeployState.UNDEPLOYING:
				has_mobile_or_undeploying = true
	if deployables.is_empty():
		return false
	if has_mobile_or_undeploying:
		for u: Unit in deployables:
			if u.deploy_state == Unit.DeployState.MOBILE or u.deploy_state == Unit.DeployState.UNDEPLOYING:
				u.request_deploy()
	else:
		for u: Unit in deployables:
			if u.deploy_state == Unit.DeployState.DEPLOYED or u.deploy_state == Unit.DeployState.DEPLOYING:
				u.request_undeploy()
	return true


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


func _toggle_smart_box_select_hotkey() -> void:
	if SettingsManager == null:
		return
	var enabled: bool = SettingsManager.toggle_smart_box_select()
	if AudioManager != null:
		AudioManager.play_ui_click()
	var msg: String = "Combat-Only Box Select: ON" if enabled else "Combat-Only Box Select: OFF (All Units)"
	hud_toast_requested.emit(msg)
	if _is_dragging and selection_box != null:
		selection_box.queue_redraw()


func _has_selected_combat_capable_unit() -> bool:
	for u: Unit in selected_units:
		if not is_instance_valid(u) or u.is_dead or u.is_staffed:
			continue
		if (u.data != null and u.data.attack_damage > 0.0) or not _is_utility_unit(u):
			return true
	return false


func issue_attack_move_at(world_point: Vector2, shift_queued: bool = false) -> void:
	_prune_invalid_units()
	if not _has_selected_combat_capable_unit():
		return
	_amove_preview_timer = 0.35
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
		if u.data.is_combat_unit():
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


func get_idle_production_buildings() -> Array[Building]:
	var idle_list: Array[Building] = []
	if not is_inside_tree():
		return idle_list
	if TeamManager != null and TeamManager.is_spectator_mode():
		return idle_list
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if b.is_destroyed or b.is_queued_for_deletion() or not b.is_constructed or b.is_salvaging:
			continue
		if int(b.team) != local_team:
			continue
		if not b.is_military_production_building():
			continue
		if b.production_component == null or b.production_component.get_queue_size() > 0:
			continue
		idle_list.append(b)
	idle_list.sort_custom(func(a: Building, b: Building) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)
	return idle_list


func select_next_idle_production(allow_center_on_repeat: bool = true, select_all: bool = false) -> int:
	var idle_list: Array[Building] = get_idle_production_buildings()
	if idle_list.is_empty():
		_idle_prod_cycle_index = -1
		_last_idle_prod_building = null
		_refresh_idle_workers(false)
		return 0

	cancel_ability_targeting()
	cancel_overclock_targeting()
	cancel_attack_move_targeting()
	cancel_patrol_targeting()
	_set_selected_units([])

	if select_all:
		_set_selected_buildings(idle_list)
		return idle_list.size()

	var now_ms: int = Time.get_ticks_msec()
	var is_rapid_repeat: bool = (
		allow_center_on_repeat
		and _last_idle_prod_building != null
		and is_instance_valid(_last_idle_prod_building)
		and selected_buildings.size() == 1
		and selected_buildings[0] == _last_idle_prod_building
		and (now_ms - _last_idle_prod_click_ms) <= DOUBLE_TAP_WINDOW_MS
	)
	if is_rapid_repeat:
		var cam_rep: RTSCamera = _get_rts_camera()
		if cam_rep != null:
			cam_rep.smooth_center_on(_last_idle_prod_building.global_position)
		_last_idle_prod_click_ms = 0
		return 1

	var next_idx: int = (_idle_prod_cycle_index + 1) % idle_list.size()
	if selected_buildings.size() == 1 and is_instance_valid(selected_buildings[0]):
		var cur_idx: int = idle_list.find(selected_buildings[0])
		if cur_idx >= 0:
			next_idx = (cur_idx + 1) % idle_list.size()

	_idle_prod_cycle_index = next_idx
	var chosen: Building = idle_list[next_idx]
	_last_idle_prod_building = chosen
	_last_idle_prod_click_ms = now_ms
	_set_selected_buildings([chosen])

	if allow_center_on_repeat and idle_list.size() == 1:
		var cam_one: RTSCamera = _get_rts_camera()
		if cam_one != null:
			var vp_size: Vector2 = get_viewport_rect().size / cam_one.zoom
			var inner_rect: Rect2 = Rect2(cam_one.global_position - vp_size * 0.5, vp_size).grow(-64.0)
			if not inner_rect.has_point(chosen.global_position):
				cam_one.smooth_center_on(chosen.global_position)
	return 1


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

	var cur_idle_prod: int = get_idle_production_buildings().size()
	if force_emit or cur_idle_prod != idle_production_count:
		idle_production_count = cur_idle_prod
		idle_production_updated.emit(idle_production_count)

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


func issue_defensive_command() -> void:
	_prune_invalid_units()
	if command_router != null:
		command_router.issue_defensive(selected_units)


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
		cancel_overclock_targeting()
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


func _get_local_human_team_enum() -> Unit.Team:
	if TeamManager != null and TeamManager.get_local_human_team() >= 0:
		return TeamManager.get_local_human_team() as Unit.Team
	return Unit.Team.PLAYER


func _get_pruned_group(group_num: int) -> Array[Unit]:
	var valid: Array[Unit] = []
	if not control_groups.has(group_num):
		return valid
	var local_t: Unit.Team = _get_local_human_team_enum()
	var raw: Variant = control_groups[group_num]
	if raw is Array:
		for item: Variant in raw:
			if is_instance_valid(item) and item is Unit:
				var unit: Unit = item
				if not unit.is_dead and not unit.is_staffed and unit.team == local_t:
					valid.append(unit)
	return valid


func _get_pruned_building_group(group_num: int) -> Array[Building]:
	var valid: Array[Building] = []
	if not control_groups.has(group_num):
		return valid
	var local_t: Unit.Team = _get_local_human_team_enum()
	var raw: Variant = control_groups[group_num]
	if raw is Array:
		for item: Variant in raw:
			if is_instance_valid(item) and item is Building:
				var b: Building = item
				if not b.is_destroyed and not b.is_queued_for_deletion() and b.team == local_t:
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


func _update_active_drag_marquee() -> void:
	if not _is_dragging:
		return
	var cur_world: Vector2 = get_global_mouse_position()
	var vp: Viewport = get_viewport()
	var cur_screen: Vector2 = vp.get_mouse_position() if vp != null else _drag_start_screen
	if not _drag_box_active:
		if cur_screen.distance_to(_drag_start_screen) >= drag_threshold or cur_world.distance_to(_drag_start_world) >= drag_threshold:
			_drag_box_active = true
	if _drag_box_active:
		var rect: Rect2 = _build_world_rect(_drag_start_world, cur_world)
		if selection_box != null:
			selection_box.update_box(rect, true)
		_update_marquee_preview(rect)


func _cancel_drag_box() -> void:
	_is_dragging = false
	_drag_box_active = false
	_click_was_double_click = false
	_click_ctrl_pressed = false
	if selection_box != null:
		selection_box.update_box(Rect2(), false)
	_clear_marquee_preview()


func _circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var clamped: Vector2 = Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y)
	)
	return center.distance_squared_to(clamped) <= radius * radius


func _collect_box_selection_candidates(world_rect: Rect2) -> Dictionary:
	var local_t: Unit.Team = _get_local_human_team_enum()
	var all_unit_hits: Array[Unit] = []
	var combat_hits: Array[Unit] = []
	var utility_hits: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.is_staffed or unit.team != local_t:
			continue
		if _circle_intersects_rect(unit.global_position, unit.get_selection_radius(), world_rect):
			all_unit_hits.append(unit)
			if _is_utility_unit(unit):
				utility_hits.append(unit)
			else:
				combat_hits.append(unit)

	var smart_box_enabled: bool = SettingsManager != null and SettingsManager.smart_box_select_enabled
	var unit_hits: Array[Unit] = all_unit_hits
	if smart_box_enabled:
		unit_hits = combat_hits if not combat_hits.is_empty() else utility_hits

	var b_hits: Array[Building] = []
	if unit_hits.is_empty():
		for node: Node in get_tree().get_nodes_in_group("selectable_buildings"):
			if not (node is Building) or not is_instance_valid(node):
				continue
			var b: Building = node
			if b.is_destroyed or b.team != local_t:
				continue
			if _circle_intersects_rect(b.global_position, b.footprint_radius * 0.75, world_rect):
				b_hits.append(b)

	return {
		"units": unit_hits,
		"combat_units": combat_hits,
		"buildings": b_hits,
		"smart_box_enabled": smart_box_enabled,
	}


func _update_marquee_preview(world_rect: Rect2) -> void:
	if TeamManager != null and TeamManager.is_spectator_mode():
		_clear_marquee_preview()
		return
	var result: Dictionary = _collect_box_selection_candidates(world_rect)
	var next_entities: Array[Node] = []
	for u: Unit in (result["units"] as Array[Unit]):
		next_entities.append(u)
	if next_entities.is_empty():
		for b: Building in (result["buildings"] as Array[Building]):
			next_entities.append(b)

	for prev: Node in _marquee_preview_entities:
		if is_instance_valid(prev) and not next_entities.has(prev):
			if prev.has_method("set_marquee_highlighted"):
				prev.call("set_marquee_highlighted", false)
	for cur: Node in next_entities:
		if is_instance_valid(cur) and cur.has_method("set_marquee_highlighted"):
			cur.call("set_marquee_highlighted", true)
	_marquee_preview_entities = next_entities


func _clear_marquee_preview() -> void:
	for ent: Node in _marquee_preview_entities:
		if is_instance_valid(ent) and ent.has_method("set_marquee_highlighted"):
			ent.call("set_marquee_highlighted", false)
	_marquee_preview_entities.clear()


func _finish_left_selection(end_screen_pos: Vector2, shift_pressed: bool = false, is_double_click: bool = false, ctrl_pressed: bool = false) -> void:
	var was_box_drag: bool = _drag_box_active
	_is_dragging = false
	_drag_box_active = false
	_click_was_double_click = false
	_click_ctrl_pressed = false
	if selection_box != null:
		selection_box.update_box(Rect2(), false)
	_clear_marquee_preview()
	var end_world_pos: Vector2 = get_global_mouse_position()
	if not was_box_drag and end_screen_pos.distance_to(_drag_start_screen) < drag_threshold:
		_select_at_point(end_world_pos, shift_pressed, is_double_click, ctrl_pressed)
	else:
		_select_in_rect(_build_world_rect(_drag_start_world, end_world_pos), shift_pressed)


func _select_at_point(world_point: Vector2, shift_pressed: bool = false, is_double_click: bool = false, ctrl_pressed: bool = false) -> void:
	if command_router == null:
		return

	if (TeamManager != null and TeamManager.is_spectator_mode()) or _is_post_match_inspection():
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
		var spec_relay: Node2D = command_router.find_sensor_relay_at_point(world_point)
		if spec_relay != null:
			_set_inspected_entity(spec_relay)
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

	var local_t: Unit.Team = _get_local_human_team_enum()
	var clicked_player: Unit = command_router.find_unit_at_point(world_point, local_t)
	if clicked_player != null:
		_set_selected_buildings([])
		_set_inspected_entity(null)
		var now_ms: int = Time.get_ticks_msec()
		var rapid_second_click: bool = (_last_click_unit == clicked_player and (now_ms - _last_click_time_ms) <= DOUBLE_TAP_WINDOW_MS)
		if is_double_click or ctrl_pressed or (not shift_pressed and rapid_second_click):
			var same_type: Array[Unit] = _find_visible_units_of_type(clicked_player.get_unit_type_id(), local_t)
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

	var clicked_building: Building = command_router.find_building_at_point(world_point, local_t)
	if clicked_building != null:
		var now_b_ms: int = Time.get_ticks_msec()
		var rapid_second_b: bool = (_last_click_building == clicked_building and (now_b_ms - _last_click_building_time_ms) <= DOUBLE_TAP_WINDOW_MS)
		_set_selected_units([])
		if is_double_click or ctrl_pressed or (not shift_pressed and rapid_second_b):
			var same_b: Array[Building] = _find_visible_buildings_of_type(clicked_building.building_type_id, local_t)
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

	var clicked_relay: Node2D = command_router.find_sensor_relay_at_point(world_point)
	if clicked_relay != null:
		_set_selected_units([])
		_set_selected_buildings([])
		_set_inspected_entity(clicked_relay)
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
	return unit.data.is_worker_class()


func _select_in_rect(world_rect: Rect2, shift_pressed: bool = false) -> void:
	if TeamManager != null and TeamManager.is_spectator_mode():
		return
	_last_click_unit = null
	_last_click_building = null
	_last_click_time_ms = 0
	_last_click_building_time_ms = 0
	var candidates: Dictionary = _collect_box_selection_candidates(world_rect)
	var hits: Array[Unit] = candidates["units"] as Array[Unit]
	var combat_hits: Array[Unit] = candidates["combat_units"] as Array[Unit]
	var smart_box_enabled: bool = bool(candidates["smart_box_enabled"])

	if not hits.is_empty():
		if shift_pressed:
			var to_add: Array[Unit] = hits
			if smart_box_enabled and not combat_hits.is_empty():
				var existing_has_combat: bool = false
				for prev_u: Unit in selected_units:
					if is_instance_valid(prev_u) and not prev_u.is_dead and not _is_utility_unit(prev_u):
						existing_has_combat = true
						break
				if existing_has_combat:
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
	var b_hits: Array[Building] = candidates["buildings"] as Array[Building]

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
	var local_t: Unit.Team = _get_local_human_team_enum()
	for item: Variant in buildings:
		if is_instance_valid(item) and item is Building:
			var b: Building = item
			if not b.is_destroyed and b.team == local_t and not selected_buildings.has(b):
				selected_buildings.append(b)

	if selected_buildings.is_empty():
		cancel_overclock_targeting()
		_set_inspected_entity(null)
		buildings_selection_changed.emit(selected_buildings)
		return

	for b: Building in selected_buildings:
		b.set_selected(true)
		if not b.destroyed.is_connected(_on_selected_building_destroyed):
			b.destroyed.connect(_on_selected_building_destroyed)

	_set_inspected_entity(selected_buildings[0], false)
	# Re-ensure every multi-selected building stays visibly selected after _set_inspected_entity.
	for b: Building in selected_buildings:
		if is_instance_valid(b):
			b.set_selected(true)
	if AudioManager != null:
		AudioManager.play_selection_audio(selected_buildings)
	buildings_selection_changed.emit(selected_buildings)


func _on_selected_building_destroyed(dead_b: Building) -> void:
	if selected_buildings.has(dead_b):
		var rem: Array[Building] = []
		for b: Building in selected_buildings:
			if is_instance_valid(b) and b != dead_b and not b.is_destroyed:
				rem.append(b)
		_set_selected_buildings(rem)


func queue_unit_distributed(unit_data: UnitData, play_audio: bool = true) -> bool:
	if unit_data == null:
		return false
	var candidates: Array[Building] = _collect_compatible_production_buildings(unit_data, null)
	if candidates.is_empty():
		return false
	var best: Building = _pick_shortest_queue_building(candidates)
	return best.queue_unit_data(unit_data, null, play_audio)


func queue_unit_distributed_batch(unit_data: UnitData, count: int, fallback_building: Building = null) -> int:
	if unit_data == null or count <= 0:
		return 0
	var candidates: Array[Building] = _collect_compatible_production_buildings(unit_data, fallback_building)
	if candidates.is_empty():
		return 0
	var queued: int = 0
	for _i: int in range(count):
		var best: Building = _pick_shortest_queue_building(candidates)
		if best == null or best.production_component == null or best.production_component.is_queue_full():
			break
		if best.queue_unit_data(unit_data, null, false):
			queued += 1
		else:
			if queued == 0:
				# Surface the normal insufficient resource/bandwidth toast once when 0 could be queued
				best.queue_unit_data(unit_data, null, true)
			break
	if queued > 0 and AudioManager != null:
		AudioManager.play_ui_click()
	return queued


func _collect_compatible_production_buildings(unit_data: UnitData, fallback_building: Building) -> Array[Building]:
	var candidates: Array[Building] = []
	var local_t: Unit.Team = _get_local_human_team_enum()
	for b: Building in selected_buildings:
		if is_instance_valid(b) and not b.is_destroyed and b.is_constructed and not b.is_salvaging and b.team == local_t:
			if b.trainable_unit_data.has(unit_data):
				candidates.append(b)
	if candidates.is_empty() and selected_building != null and is_instance_valid(selected_building):
		if not selected_building.is_destroyed and selected_building.is_constructed and not selected_building.is_salvaging and selected_building.trainable_unit_data.has(unit_data):
			candidates.append(selected_building)
	if candidates.is_empty() and fallback_building != null and is_instance_valid(fallback_building):
		if not fallback_building.is_destroyed and fallback_building.is_constructed and not fallback_building.is_salvaging and fallback_building.trainable_unit_data.has(unit_data):
			candidates.append(fallback_building)
	return candidates


func _pick_shortest_queue_building(candidates: Array[Building]) -> Building:
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
	if best == null and not candidates.is_empty():
		best = candidates[0]
	return best


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


func _set_selected_units(new_selection: Array[Unit], reset_subgroup_index: bool = true, play_audio: bool = true) -> void:
	for item: Variant in selected_units:
		if is_instance_valid(item) and item is Unit:
			var prev_unit: Unit = item
			if not new_selection.has(prev_unit):
				prev_unit.set_selected(false)

	_disconnect_death_trackers()
	selected_units = []
	var local_t: Unit.Team = _get_local_human_team_enum()
	for item: Variant in new_selection:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if not unit.is_dead and not unit.is_staffed and unit.team == local_t:
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
	elif play_audio and AudioManager != null:
		AudioManager.play_selection_audio(selected_units)

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


func _set_inspected_entity(entity: Node, emit_audio: bool = true) -> void:
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
		elif entity.is_in_group("sensor_relays"):
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
		elif inspected_entity.is_in_group("sensor_relays"):
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
		elif inspected_entity.is_in_group("sensor_relays"):
			if inspected_entity.has_method("set_selected"):
				inspected_entity.call("set_selected", true)

	if emit_audio and inspected_entity != null and AudioManager != null:
		AudioManager.play_selection_audio([inspected_entity])

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


func _get_selected_friendly_constructed_buildings() -> Array[Building]:
	var out: Array[Building] = []
	var local_t: Unit.Team = _get_local_human_team_enum()
	for b: Building in selected_buildings:
		if is_instance_valid(b) and not b.is_destroyed and b.is_constructed and not b.is_salvaging and b.team == local_t:
			out.append(b)
	if out.is_empty() and selected_building != null and is_instance_valid(selected_building):
		if not selected_building.is_destroyed and selected_building.is_constructed and not selected_building.is_salvaging and selected_building.team == local_t:
			out.append(selected_building)
	return out


func _try_handle_building_hotkey_event(event: InputEvent, action_name: StringName, slot_kind: StringName, slot_index: int) -> bool:
	if not selected_units.is_empty() or not event.is_action_pressed(action_name):
		return false
	var shift_queued: bool = Input.is_key_pressed(KEY_SHIFT)
	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.ctrl_pressed or key_ev.alt_pressed or key_ev.echo:
			return false
		shift_queued = key_ev.shift_pressed or shift_queued
	elif event.is_echo():
		return false

	_prune_invalid_units()
	var friendly_bldgs: Array[Building] = _get_selected_friendly_constructed_buildings()
	if friendly_bldgs.is_empty():
		return false
	var lead: Building = friendly_bldgs[0]

	if slot_kind == &"train":
		if slot_index < 0 or slot_index >= lead.trainable_unit_data.size():
			return false
		var u_data: UnitData = lead.trainable_unit_data[slot_index]
		if u_data == null:
			return false
		if shift_queued:
			queue_unit_distributed_batch(u_data, 5, lead)
		elif friendly_bldgs.size() > 1:
			queue_unit_distributed(u_data, true)
		else:
			lead.queue_unit_training(slot_index, true)
		get_viewport().set_input_as_handled()
		return true

	if slot_kind == &"upgrade":
		if slot_index < 0 or slot_index >= lead.researchable_upgrades.size():
			return false
		var upg: UpgradeData = lead.researchable_upgrades[slot_index]
		if upg == null:
			return false
		var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
		if econ != null and (econ.has_upgrade(int(lead.team), upg.upgrade_id) or econ.is_upgrade_in_progress(int(lead.team), upg.upgrade_id)):
			get_viewport().set_input_as_handled()
			return true
		var started: bool = false
		for cand: Building in friendly_bldgs:
			var idx: int = cand.researchable_upgrades.find(upg)
			if idx >= 0 and cand.can_research_upgrade(idx):
				if cand.queue_upgrade_research(idx):
					started = true
					break
		if not started:
			lead.queue_upgrade_research(slot_index)
		get_viewport().set_input_as_handled()
		return true

	if slot_kind == &"facility_special":
		if has_selected_overclock_hub():
			if is_overclock_targeting:
				cancel_overclock_targeting()
			elif not begin_overclock_targeting() and AudioManager != null:
				AudioManager.play_error()
			get_viewport().set_input_as_handled()
			return true
		var any_staffable: bool = false
		var any_staffed: bool = false
		for b: Building in friendly_bldgs:
			if b.max_staff_slots > 0:
				any_staffable = true
				if b.get_assigned_engineer_count() > 0:
					any_staffed = true
		if any_staffable:
			if any_staffed:
				if AudioManager != null:
					AudioManager.play_ui_click()
				eject_engineers_from_selected_buildings()
			elif AudioManager != null:
				AudioManager.play_error()
			get_viewport().set_input_as_handled()
			return true
	return false


func _prune_invalid_units() -> void:
	var local_t: Unit.Team = _get_local_human_team_enum()
	var valid: Array[Unit] = []
	for item: Variant in selected_units:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if not unit.is_dead and not unit.is_staffed and unit.team == local_t:
				valid.append(unit)
	if valid.size() != selected_units.size():
		_set_selected_units(valid, false, false)
	if not selected_buildings.is_empty():
		var valid_b: Array[Building] = []
		for item_b: Variant in selected_buildings:
			if is_instance_valid(item_b) and item_b is Building:
				var b: Building = item_b
				if not b.is_destroyed and not b.is_queued_for_deletion() and b.team == local_t:
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
	_command_cursors[&"overclock_valid"] = _make_reticle_cursor(&"overclock_valid")
	_command_cursors[&"overclock_invalid"] = _make_reticle_cursor(&"overclock_invalid")


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
		&"overclock_valid":
			primary = Color(1.0, 0.624, 0.110, 1.0) # Hazard Amber #FF9F1C
			secondary = Color(1.0, 0.92, 0.68, 0.98)
		&"overclock_invalid":
			primary = Color(0.82, 0.32, 0.30, 0.92) # Muted Red
			secondary = Color(0.92, 0.56, 0.54, 0.85)

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

		&"ability_target", &"overclock_valid", &"overclock_invalid":
			# Luminous concentric reticle + ticks
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
	if get_tree().paused and not _is_post_match_inspection():
		return true
	var pause_node: Node = get_tree().get_first_node_in_group("pause_menu")
	if pause_node != null and is_instance_valid(pause_node):
		if pause_node.has_method("is_pause_open") and bool(pause_node.call("is_pause_open")):
			return true
		if pause_node.has_method("is_settings_open") and bool(pause_node.call("is_settings_open")):
			return true
		if pause_node.has_method("is_tech_tree_open") and bool(pause_node.call("is_tech_tree_open")):
			return true
		if pause_node.has_method("is_controls_help_open") and bool(pause_node.call("is_controls_help_open")):
			return true
	var settings_node: Node = get_tree().get_first_node_in_group("settings_menu")
	if settings_node != null and is_instance_valid(settings_node) and not settings_node.is_queued_for_deletion():
		return true
	var tech_node: Node = get_tree().get_first_node_in_group("tech_tree_overlay")
	if tech_node != null and is_instance_valid(tech_node) and not tech_node.is_queued_for_deletion():
		return true
	var help_node: Node = get_tree().get_first_node_in_group("controls_reference_overlay")
	if help_node != null and is_instance_valid(help_node) and not help_node.is_queued_for_deletion():
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
			if u.can_repair():
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


func _update_hover_target() -> void:
	if _hovered_entity != null and not is_instance_valid(_hovered_entity):
		_hovered_entity = null
	if command_router == null or _is_dragging or _is_any_modal_open():
		_set_hovered_entity(null)
		return
	var vp: Viewport = get_viewport()
	if vp != null:
		var ui_ctrl: Control = vp.gui_get_hovered_control()
		if ui_ctrl != null and ui_ctrl.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_set_hovered_entity(null)
			return
	var world_pt: Vector2 = get_global_mouse_position()
	_set_hovered_entity(_find_top_hover_entity(world_pt))


func _set_hovered_entity(next_entity: Node) -> void:
	if _hovered_entity == next_entity:
		return
	if _hovered_entity != null and is_instance_valid(_hovered_entity) and _hovered_entity.has_method("set_hovered"):
		_hovered_entity.call("set_hovered", false)
	_hovered_entity = next_entity
	if _hovered_entity != null and is_instance_valid(_hovered_entity) and _hovered_entity.has_method("set_hovered"):
		_hovered_entity.call("set_hovered", true)


func _find_top_hover_entity(world_point: Vector2) -> Node:
	if command_router == null:
		return null
	var is_spec: bool = (TeamManager != null and TeamManager.is_spectator_mode()) or _is_post_match_inspection()
	if is_spec:
		var su: Unit = command_router.find_any_unit_at_point(world_point)
		if su != null:
			return su
		var sb: Building = command_router.find_any_building_at_point(world_point)
		if sb != null:
			return sb
	else:
		var local_t: Unit.Team = _get_local_human_team_enum()
		var local_int: int = int(local_t)
		var fu: Unit = command_router.find_unit_at_point(world_point, local_t)
		if fu != null:
			return fu
		var eu: Unit = command_router.find_hostile_unit_at_point(world_point, local_int)
		if eu != null:
			return eu
		var fb: Building = command_router.find_building_at_point(world_point, local_t)
		if fb != null:
			return fb
		var eb: Building = command_router.find_hostile_building_at_point(world_point, local_int)
		if eb != null:
			return eb

	var bar: Node2D = command_router.find_barricade_at_point(world_point)
	if bar != null:
		return bar
	var relay_h: Node2D = command_router.find_sensor_relay_at_point(world_point)
	if relay_h != null:
		return relay_h
	var salv: Node2D = command_router.find_salvage_core_at_point(world_point)
	if salv != null:
		return salv
	var res: ResourceNode = command_router.find_resource_node_at_point(world_point)
	if res != null:
		return res
	return null


func _update_command_cursor() -> void:
	if _is_any_modal_open() or _is_post_match_inspection():
		_clear_custom_cursor()
		return
	if active_targeting_ability != null:
		_apply_command_cursor(&"ability_target")
		return
	if is_overclock_targeting:
		var oc_hub: Building = find_ready_overclock_hub()
		var oc_valid: bool = false
		if oc_hub != null and command_router != null:
			var oc_b: Building = command_router.find_building_at_point(get_global_mouse_position(), _get_local_human_team_enum())
			oc_valid = oc_b != null and oc_b.is_valid_overclock_target(int(oc_hub.team))
		_apply_command_cursor(&"overclock_valid" if oc_valid else &"overclock_invalid")
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
