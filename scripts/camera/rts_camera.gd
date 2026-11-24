class_name RTSCamera
extends Camera2D

signal edge_pan_toggled(enabled: bool)
signal fullscreen_toggled(enabled: bool)
signal camera_toast(message: String)

const EDGE_BOUNDS_TOLERANCE_PX: float = 4.0
const MAX_FRAME_DELTA: float = 0.05
const ALERT_CYCLE_WINDOW_MS: int = 2500

@export var pan_speed: float = 650.0
@export var edge_pan_enabled: bool = true
@export var edge_margin_px: float = 24.0
@export var edge_pan_speed: float = 900.0
@export_range(0.1, 1.0, 0.05) var edge_inner_speed_ratio: float = 0.45
@export var pan_smoothing: float = 18.0
@export var scale_speed_with_zoom: bool = true
@export var zoom_step: float = 0.12
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var zoom_smoothness: float = 14.0
@export var zoom_to_cursor: bool = true
@export var invert_zoom: bool = false
@export var middle_drag_speed: float = 1.0
@export var pan_bounds: Rect2 = Rect2(-960.0, -540.0, 1920.0, 1080.0)

var camera_bookmarks: Dictionary = {}

var _target_position: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0
var _is_middle_dragging: bool = false
var _mouse_in_window: bool = true
var _base_hub_cycle_index: int = -1
var _alert_cycle_index: int = -1
var _last_alert_jump_ms: int = 0
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _shake_duration: float = 0.15


func _ready() -> void:
	add_to_group("rts_camera")
	_sync_from_settings()
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	_target_zoom = clampf(zoom.x, min_zoom, max_zoom)
	zoom = Vector2(_target_zoom, _target_zoom)
	_target_position = _clamp_point(global_position)
	global_position = _target_position


func _on_settings_changed(category: StringName) -> void:
	if category == &"camera" or category == &"all":
		_sync_from_settings()
	if category == &"display" or category == &"all":
		_target_position = _clamp_point(_target_position)
		global_position = _clamp_point(global_position)
		fullscreen_toggled.emit(is_fullscreen())


func _sync_from_settings() -> void:
	if SettingsManager == null:
		return
	var prev_edge: bool = edge_pan_enabled
	edge_pan_enabled = SettingsManager.edge_pan_enabled
	edge_pan_speed = SettingsManager.edge_pan_speed
	edge_margin_px = SettingsManager.edge_pan_margin
	pan_speed = SettingsManager.keyboard_pan_speed
	zoom_step = SettingsManager.zoom_speed
	zoom_to_cursor = SettingsManager.zoom_to_cursor
	invert_zoom = SettingsManager.invert_zoom
	middle_drag_speed = SettingsManager.middle_drag_speed
	if prev_edge != edge_pan_enabled:
		edge_pan_toggled.emit(edge_pan_enabled)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_ENTER, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_mouse_in_window = true
		NOTIFICATION_WM_MOUSE_EXIT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_mouse_in_window = false
			_is_middle_dragging = false


func _input(event: InputEvent) -> void:
	# Recover mouse-in-window tracking automatically if cursor was already inside on launch or focus regain.
	if event is InputEventMouseMotion:
		var vp: Viewport = get_viewport()
		if vp != null and vp.get_visible_rect().grow(EDGE_BOUNDS_TOLERANCE_PX).has_point((event as InputEventMouseMotion).position):
			_mouse_in_window = true
		return


func _process(delta: float) -> void:
	var dt: float = minf(delta, MAX_FRAME_DELTA)
	var kb_input: Vector2 = Input.get_vector(
		"camera_pan_left",
		"camera_pan_right",
		"camera_pan_up",
		"camera_pan_down"
	)
	var edge_vec: Vector2 = _get_edge_pan_vector()
	var combined_dir: Vector2 = (kb_input + edge_vec).limit_length(1.0)

	if combined_dir != Vector2.ZERO:
		var base_speed: float = pan_speed
		var apply_zoom_scale: bool = true
		if edge_vec != Vector2.ZERO and kb_input == Vector2.ZERO:
			base_speed = edge_pan_speed
			apply_zoom_scale = scale_speed_with_zoom
		elif edge_vec != Vector2.ZERO and kb_input != Vector2.ZERO:
			base_speed = maxf(pan_speed, edge_pan_speed)
			apply_zoom_scale = scale_speed_with_zoom

		var effective_speed: float = base_speed / maxf(0.1, zoom.x) if apply_zoom_scale else base_speed
		_target_position = _clamp_point(_target_position + combined_dir * effective_speed * dt)

	# Frame-rate-independent exponential chase for silky SC2 / LoL / Dota camera motion.
	if pan_smoothing > 0.0:
		var pan_alpha: float = 1.0 - exp(-pan_smoothing * dt)
		global_position = global_position.lerp(_target_position, pan_alpha)
		if global_position.distance_squared_to(_target_position) < 0.04:
			global_position = _target_position
	else:
		global_position = _target_position

	var zoom_alpha: float = 1.0 - exp(-zoom_smoothness * dt)
	var next_zoom: float = lerpf(zoom.x, _target_zoom, zoom_alpha)
	if absf(next_zoom - _target_zoom) < 0.0005:
		next_zoom = _target_zoom
	zoom = Vector2(next_zoom, next_zoom)

	_update_camera_shake(dt)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_toggle_edge_pan") and not event.is_echo():
		toggle_edge_pan()
		get_viewport().set_input_as_handled()
		return

	if not event.is_echo():
		var ctrl_down: bool = Input.is_key_pressed(KEY_CTRL)
		var alt_down: bool = Input.is_key_pressed(KEY_ALT)
		if event is InputEventKey:
			var k_mod: InputEventKey = event
			ctrl_down = ctrl_down or k_mod.ctrl_pressed
			alt_down = alt_down or k_mod.alt_pressed

		for slot: int in range(1, 5):
			var act_name: StringName = StringName("cam_bookmark_%d" % slot)
			if event.is_action_pressed(act_name):
				if ctrl_down:
					save_camera_bookmark(slot)
				else:
					recall_camera_bookmark(slot)
				get_viewport().set_input_as_handled()
				return

		if not ctrl_down and not alt_down:
			if event.is_action_pressed("jump_base_hub"):
				jump_to_next_base_hub()
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("jump_last_alert"):
				jump_to_last_alert()
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			var middle_bound: bool = SettingsManager != null and SettingsManager.is_mouse_button_bound(MOUSE_BUTTON_MIDDLE)
			if middle_bound:
				_is_middle_dragging = false
			else:
				_is_middle_dragging = mouse_event.pressed
				if _is_middle_dragging:
					_target_position = global_position
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var delta_up: float = -zoom_step if invert_zoom else zoom_step
			_apply_zoom_delta(delta_up)
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var delta_dn: float = zoom_step if invert_zoom else -zoom_step
			_apply_zoom_delta(delta_dn)
	elif event is InputEventMouseMotion and _is_middle_dragging:
		var motion_event: InputEventMouseMotion = event
		_target_position = _clamp_point(_target_position - (motion_event.relative * middle_drag_speed) / zoom)
		global_position = _target_position


func _apply_zoom_delta(zoom_delta: float) -> void:
	var old_target_zoom: float = _target_zoom
	var next_target_zoom: float = clampf(old_target_zoom + zoom_delta, min_zoom, max_zoom)
	if is_equal_approx(old_target_zoom, next_target_zoom):
		return
	_target_zoom = next_target_zoom
	if not zoom_to_cursor:
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		return
	var vp_size: Vector2 = vp.get_visible_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return
	var mouse_offset: Vector2 = vp.get_mouse_position() - vp_size * 0.5
	# Shift camera target so the world point under the mouse cursor stays anchored through the zoom step.
	var world_shift: Vector2 = mouse_offset * ((1.0 / maxf(0.05, old_target_zoom)) - (1.0 / maxf(0.05, next_target_zoom)))
	_target_position = _clamp_point(_target_position + world_shift)


func set_edge_pan_enabled(enabled: bool) -> void:
	if edge_pan_enabled == enabled:
		return
	edge_pan_enabled = enabled
	if SettingsManager != null and SettingsManager.edge_pan_enabled != edge_pan_enabled:
		SettingsManager.set_camera_settings(
			edge_pan_enabled,
			SettingsManager.edge_pan_speed,
			SettingsManager.edge_pan_margin,
			SettingsManager.keyboard_pan_speed,
			SettingsManager.zoom_speed
		)
	edge_pan_toggled.emit(edge_pan_enabled)


func toggle_edge_pan() -> bool:
	set_edge_pan_enabled(not edge_pan_enabled)
	return edge_pan_enabled


func save_camera_bookmark(slot: int) -> void:
	if slot < 1 or slot > 4:
		return
	camera_bookmarks[slot] = global_position
	if AudioManager != null:
		AudioManager.play_ui_click()
	camera_toast.emit("Camera Bookmark %d Saved" % slot)


func recall_camera_bookmark(slot: int) -> bool:
	if not camera_bookmarks.has(slot):
		if AudioManager != null:
			AudioManager.play_error()
		camera_toast.emit("Bookmark %d Empty (Ctrl+%s to Save)" % [slot, SettingsManager.get_action_key_label(StringName("cam_bookmark_%d" % slot)) if SettingsManager != null else ("F%d" % slot)])
		return false
	var target_pos: Vector2 = camera_bookmarks[slot] as Vector2
	smooth_center_on(target_pos)
	if AudioManager != null:
		AudioManager.play_sfx(&"unit_select", -6.0, 0.03)
	return true


func jump_to_next_base_hub() -> bool:
	if not is_inside_tree():
		return false
	var hubs: Array[Building] = []
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	if local_team < 0:
		local_team = 0
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or int(b.team) != local_team:
			continue
		if b.is_core_hub or b.building_type_id == &"nexus_vat":
			hubs.append(b)
	if hubs.is_empty():
		return false
	hubs.sort_custom(func(a: Building, b: Building) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)
	_base_hub_cycle_index = (_base_hub_cycle_index + 1) % hubs.size()
	smooth_center_on(hubs[_base_hub_cycle_index].global_position)
	if AudioManager != null:
		AudioManager.play_sfx(&"unit_select", -6.0, 0.02)
	return true


func jump_to_last_alert() -> bool:
	if not is_inside_tree():
		return false
	var mm: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if mm == null:
		return false
	var alerts: Array[Dictionary] = mm.get_recent_alerts()
	if alerts.is_empty():
		return false
	var now_ms: int = Time.get_ticks_msec()
	if (now_ms - _last_alert_jump_ms) <= ALERT_CYCLE_WINDOW_MS and alerts.size() > 1:
		_alert_cycle_index = (_alert_cycle_index + 1) % alerts.size()
	else:
		_alert_cycle_index = 0
	_last_alert_jump_ms = now_ms
	var chosen: Dictionary = alerts[_alert_cycle_index]
	smooth_center_on(chosen["pos"] as Vector2)
	if AudioManager != null:
		AudioManager.play_sfx(&"unit_select", -5.0, 0.03)
	camera_toast.emit("Alert: %s" % String(chosen.get("message", "Tactical Alert")))
	return true


func smooth_center_on(world_pos: Vector2) -> void:
	_target_position = _clamp_point(world_pos)


func is_fullscreen() -> bool:
	if SettingsManager != null:
		return SettingsManager.is_fullscreen()
	var win: Window = get_window()
	if win != null:
		return win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	return false


func set_fullscreen(enabled: bool) -> void:
	if SettingsManager != null:
		var target_mode: int = 1 if enabled else 0
		SettingsManager.set_display_settings(target_mode, SettingsManager.window_resolution)
		return
	var win: Window = get_window()
	if win != null:
		win.borderless = false
		win.mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
	fullscreen_toggled.emit(is_fullscreen())


func toggle_fullscreen() -> bool:
	if SettingsManager != null:
		SettingsManager.toggle_fullscreen()
		return SettingsManager.is_fullscreen()
	set_fullscreen(not is_fullscreen())
	return is_fullscreen()


func center_on(world_pos: Vector2) -> void:
	_target_position = _clamp_point(world_pos)
	global_position = _target_position


func add_camera_shake(intensity: float, duration: float = 0.15, world_pos: Variant = null) -> void:
	if SettingsManager != null and not SettingsManager.camera_shake_enabled:
		return
	var clamped_intensity: float = clampf(intensity, 0.0, 5.0)
	if clamped_intensity <= 0.05:
		return
	if world_pos is Vector2:
		var vp: Viewport = get_viewport()
		if vp != null:
			var half_view: Vector2 = (vp.get_visible_rect().size / maxf(0.25, zoom.x)) * 0.55 + Vector2(96.0, 96.0)
			var delta_p: Vector2 = (world_pos as Vector2) - global_position
			if absf(delta_p.x) > half_view.x or absf(delta_p.y) > half_view.y:
				return
	_shake_intensity = maxf(_shake_intensity, clamped_intensity)
	_shake_duration = maxf(0.08, duration)
	_shake_timer = maxf(_shake_timer, _shake_duration)


func _update_camera_shake(dt: float) -> void:
	if _shake_timer <= 0.0 or _shake_intensity <= 0.05:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		_shake_intensity = 0.0
		_shake_timer = 0.0
		return
	if SettingsManager != null and not SettingsManager.camera_shake_enabled:
		offset = Vector2.ZERO
		_shake_intensity = 0.0
		_shake_timer = 0.0
		return
	_shake_timer = maxf(0.0, _shake_timer - dt)
	var ratio: float = clampf(_shake_timer / maxf(0.01, _shake_duration), 0.0, 1.0)
	var amp: float = _shake_intensity * ratio * ratio
	offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	if _shake_timer <= 0.0:
		offset = Vector2.ZERO
		_shake_intensity = 0.0


func _get_edge_pan_vector() -> Vector2:
	if not edge_pan_enabled or not _mouse_in_window or _is_middle_dragging:
		return Vector2.ZERO
	var win: Window = get_window()
	if win == null or not win.has_focus():
		return Vector2.ZERO

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO

	# Don't yank the camera while hovering clickable HUD buttons or interactive minimap near viewport borders.
	var hovered: Control = viewport.gui_get_hovered_control()
	if hovered != null and (hovered is BaseButton or hovered.is_in_group("blocks_edge_pan")):
		return Vector2.ZERO

	var viewport_size: Vector2 = viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or edge_margin_px <= 0.0:
		return Vector2.ZERO

	# Allow small subpixel/DPI tolerance at borders so canvas_items stretch scaling never drops frames at the edge.
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	if (
		mouse_pos.x < -EDGE_BOUNDS_TOLERANCE_PX
		or mouse_pos.y < -EDGE_BOUNDS_TOLERANCE_PX
		or mouse_pos.x > viewport_size.x + EDGE_BOUNDS_TOLERANCE_PX
		or mouse_pos.y > viewport_size.y + EDGE_BOUNDS_TOLERANCE_PX
	):
		return Vector2.ZERO

	var clamped_pos: Vector2 = Vector2(
		clampf(mouse_pos.x, 0.0, viewport_size.x),
		clampf(mouse_pos.y, 0.0, viewport_size.y)
	)

	var raw_dir: Vector2 = Vector2.ZERO
	var max_penetration: float = 0.0

	if clamped_pos.x <= edge_margin_px:
		raw_dir.x -= 1.0
		max_penetration = maxf(max_penetration, 1.0 - (clamped_pos.x / edge_margin_px))
	elif clamped_pos.x >= viewport_size.x - edge_margin_px:
		raw_dir.x += 1.0
		max_penetration = maxf(max_penetration, 1.0 - ((viewport_size.x - clamped_pos.x) / edge_margin_px))

	if clamped_pos.y <= edge_margin_px:
		raw_dir.y -= 1.0
		max_penetration = maxf(max_penetration, 1.0 - (clamped_pos.y / edge_margin_px))
	elif clamped_pos.y >= viewport_size.y - edge_margin_px:
		raw_dir.y += 1.0
		max_penetration = maxf(max_penetration, 1.0 - ((viewport_size.y - clamped_pos.y) / edge_margin_px))

	if raw_dir == Vector2.ZERO:
		return Vector2.ZERO

	# Progressive edge curve: gentle nudge at inner edge, full 100% speed in the outer ~8px border.
	var ramp_t: float = clampf(max_penetration * 1.5, 0.0, 1.0)
	var strength: float = lerpf(edge_inner_speed_ratio, 1.0, ramp_t)
	return raw_dir.normalized() * strength


func _clamp_point(pos: Vector2) -> Vector2:
	if not pan_bounds.has_area():
		return pos
	return Vector2(
		clampf(pos.x, pan_bounds.position.x, pan_bounds.end.x),
		clampf(pos.y, pan_bounds.position.y, pan_bounds.end.y)
	)
