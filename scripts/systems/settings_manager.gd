extends Node

signal settings_changed(category: StringName)
signal keybind_changed(action_name: StringName)

const CONFIG_PATH: String = "user://settings.cfg"
const FPS_COUNTER_SCRIPT: GDScript = preload("res://ui/hud/fps_counter.gd")

const RESOLUTION_PRESETS: Array = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

const FPS_CAP_PRESETS: Array = [0, 60, 120, 144]

const ALLOWED_MOUSE_BUTTONS: Array = [
	MOUSE_BUTTON_XBUTTON1,
	MOUSE_BUTTON_XBUTTON2,
	MOUSE_BUTTON_MIDDLE,
]

## Godot-safe default keybind catalog (explicitly avoids F5, F6, F7, F8).
const KEYBIND_DEFS: Array = [
	{"action": &"cmd_attack_move", "label": "Attack-Move", "default_key": KEY_A, "category": "Unit Commands"},
	{"action": &"cmd_stop", "label": "Stop", "default_key": KEY_S, "category": "Unit Commands"},
	{"action": &"cmd_hold", "label": "Hold Position", "default_key": KEY_H, "category": "Unit Commands"},
	{"action": &"cmd_defensive_stance", "label": "Defensive Stance", "default_key": KEY_D, "category": "Unit Commands"},
	{"action": &"cmd_patrol", "label": "Patrol", "default_key": KEY_P, "category": "Unit Commands"},
	{"action": &"cmd_select_idle_worker", "label": "Select Idle Worker", "default_key": KEY_QUOTELEFT, "category": "Abilities & Selection"},
	{"action": &"cmd_select_idle_production", "label": "Select Idle Production", "default_key": KEY_SEMICOLON, "category": "Abilities & Selection"},
	{"action": &"cmd_select_all_army", "label": "Select All Army", "default_key": KEY_F9, "category": "Abilities & Selection"},
	{"action": &"cmd_toggle_smart_box_select", "label": "Toggle Combat-Only Box Select", "default_key": KEY_B, "category": "Abilities & Selection"},
	{"action": &"ui_cycle_subgroup", "label": "Cycle Subgroup", "default_key": KEY_TAB, "category": "Abilities & Selection"},
	{"action": &"cmd_ability_q", "label": "Ability / Build Slot Q", "default_key": KEY_Q, "category": "Abilities & Selection"},
	{"action": &"cmd_ability_w", "label": "Ability / Build Slot W", "default_key": KEY_W, "category": "Abilities & Selection"},
	{"action": &"cmd_ability_e", "label": "Ability / Build / Eject Slot E", "default_key": KEY_E, "category": "Abilities & Selection"},
	{"action": &"cmd_ability_r", "label": "Ability / Build Slot R", "default_key": KEY_R, "category": "Abilities & Selection"},
	{"action": &"cmd_ability_t", "label": "Ability / Build Slot T", "default_key": KEY_T, "category": "Abilities & Selection"},
	{"action": &"cmd_ability_y", "label": "Ability / Build Slot Y", "default_key": KEY_Y, "category": "Abilities & Selection"},
	{"action": &"cmd_ability_f", "label": "Ability / Build Slot F", "default_key": KEY_F, "category": "Abilities & Selection"},
	{"action": &"jump_base_hub", "label": "Jump to Nexus Vat", "default_key": KEY_BACKSPACE, "category": "Camera & Navigation"},
	{"action": &"jump_last_alert", "label": "Jump to Last Alert", "default_key": KEY_SPACE, "category": "Camera & Navigation"},
	{"action": &"cam_bookmark_1", "label": "Camera Bookmark 1 (Ctrl=Save)", "default_key": KEY_F1, "category": "Camera & Navigation"},
	{"action": &"cam_bookmark_2", "label": "Camera Bookmark 2 (Ctrl=Save)", "default_key": KEY_F2, "category": "Camera & Navigation"},
	{"action": &"cam_bookmark_3", "label": "Camera Bookmark 3 (Ctrl=Save)", "default_key": KEY_F3, "category": "Camera & Navigation"},
	{"action": &"cam_bookmark_4", "label": "Camera Bookmark 4 (Ctrl=Save)", "default_key": KEY_F4, "category": "Camera & Navigation"},
	{"action": &"camera_pan_up", "label": "Camera Pan Up", "default_key": KEY_UP, "category": "Camera & Navigation"},
	{"action": &"camera_pan_down", "label": "Camera Pan Down", "default_key": KEY_DOWN, "category": "Camera & Navigation"},
	{"action": &"camera_pan_left", "label": "Camera Pan Left", "default_key": KEY_LEFT, "category": "Camera & Navigation"},
	{"action": &"camera_pan_right", "label": "Camera Pan Right", "default_key": KEY_RIGHT, "category": "Camera & Navigation"},
	{"action": &"camera_toggle_edge_pan", "label": "Toggle Edge-Pan", "default_key": KEY_F12, "category": "Camera & Navigation"},
	{"action": &"camera_toggle_fullscreen", "label": "Toggle Fullscreen", "default_key": KEY_F11, "category": "System"},
	{"action": &"ui_toggle_tech_tree", "label": "Toggle Tech Tree", "default_key": KEY_U, "category": "System"},
	{"action": &"game_speed_down", "label": "Game Speed Slower", "default_key": KEY_BRACKETLEFT, "category": "System"},
	{"action": &"game_speed_up", "label": "Game Speed Faster", "default_key": KEY_BRACKETRIGHT, "category": "System"},
	{"action": &"debug_toggle_aggro_ai", "label": "Toggle Aggro AI (Debug)", "default_key": KEY_F10, "category": "System"},
]

const RESERVED_EDITOR_KEYS: Array = [KEY_F5, KEY_F6, KEY_F7, KEY_F8]

# Camera preferences
var edge_pan_enabled: bool = true
var edge_pan_speed: float = 900.0
var edge_pan_margin: float = 24.0
var keyboard_pan_speed: float = 650.0
var zoom_speed: float = 0.12
var zoom_to_cursor: bool = true
var confine_cursor: bool = false
var invert_zoom: bool = false
var middle_drag_speed: float = 1.0

enum AttackRangeMode {
	ALWAYS_SHOW = 0,
	SHOW_WHILE_TARGETING = 1,
	DONT_SHOW = 2,
}

enum AttackMoveMode {
	QUICK_CAST = 0,
	CLICK_TO_CONFIRM = 1,
}

# Gameplay / HUD preferences
var health_bar_mode: int = 0 # 0 = Damaged / Selected, 1 = Always On, 2 = Selected Only
var attack_range_mode: int = AttackRangeMode.SHOW_WHILE_TARGETING
var attack_move_mode: int = AttackMoveMode.QUICK_CAST
var smart_box_select_enabled: bool = false
var show_alert_toasts: bool = true
var camera_shake_enabled: bool = true
var battle_scars_enabled: bool = true
var build_grid_snap_enabled: bool = false

# Audio preferences
var master_volume: float = 0.72
var sfx_volume: float = 0.85
var ui_volume: float = 0.85
var ambience_volume: float = 0.35
var muted: bool = false
var mute_when_unfocused: bool = false

# Display preferences
var window_mode: int = 0 # 0 = Windowed, 1 = Borderless Fullscreen, 2 = Fullscreen
var window_resolution: Vector2i = Vector2i(1280, 720)
var vsync_enabled: bool = true
var fps_cap: int = 0 # 0 = Unlimited, 60, 120, 144
var show_fps_counter: bool = false

# Action -> encoded binding string ("key:<int>", "mouse:<int>", or "none")
var keybinds: Dictionary = {}

var _gameplay_cursor_active: bool = false
var _window_focused: bool = true
var _fps_counter_overlay: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_default_keybinds()
	load_settings()
	apply_input_map()
	call_deferred("apply_display_settings")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focused = false
			refresh_mouse_mode()
			if mute_when_unfocused and AudioManager != null and AudioManager.has_method("set_unfocused_mute"):
				AudioManager.set_unfocused_mute(true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true
			refresh_mouse_mode()
			if AudioManager != null and AudioManager.has_method("set_unfocused_mute"):
				AudioManager.set_unfocused_mute(false)


func _input(event: InputEvent) -> void:
	# Skip global fullscreen toggle while SettingsMenu is actively capturing a keybind.
	var settings_node: Node = get_tree().get_first_node_in_group("settings_menu") if is_inside_tree() else null
	if settings_node != null and is_instance_valid(settings_node) and settings_node.has_method("is_capturing_key"):
		if bool(settings_node.call("is_capturing_key")):
			return

	var is_fs_action: bool = event.is_action_pressed("camera_toggle_fullscreen") and not event.is_echo()
	var is_alt_enter: bool = false
	if event is InputEventKey:
		var key_ev: InputEventKey = event
		if key_ev.pressed and not key_ev.echo:
			is_alt_enter = key_ev.alt_pressed and (key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_KP_ENTER)

	if is_fs_action or is_alt_enter:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _init_default_keybinds() -> void:
	keybinds.clear()
	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		keybinds[act] = encode_key_binding(int(entry["default_key"]))


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(CONFIG_PATH)
	if err != OK:
		apply_input_map()
		save_settings()
		return

	edge_pan_enabled = bool(cfg.get_value("camera", "edge_pan_enabled", true))
	edge_pan_speed = clampf(float(cfg.get_value("camera", "edge_pan_speed", 900.0)), 300.0, 1800.0)
	edge_pan_margin = clampf(float(cfg.get_value("camera", "edge_pan_margin", 24.0)), 8.0, 64.0)
	keyboard_pan_speed = clampf(float(cfg.get_value("camera", "keyboard_pan_speed", 650.0)), 250.0, 1400.0)
	zoom_speed = clampf(float(cfg.get_value("camera", "zoom_speed", 0.12)), 0.05, 0.30)
	zoom_to_cursor = bool(cfg.get_value("camera", "zoom_to_cursor", true))
	confine_cursor = bool(cfg.get_value("camera", "confine_cursor", false))
	invert_zoom = bool(cfg.get_value("camera", "invert_zoom", false))
	middle_drag_speed = clampf(float(cfg.get_value("camera", "middle_drag_speed", 1.0)), 0.4, 2.5)

	health_bar_mode = clampi(int(cfg.get_value("gameplay", "health_bar_mode", 0)), 0, 2)
	attack_range_mode = clampi(int(cfg.get_value("gameplay", "attack_range_mode", AttackRangeMode.SHOW_WHILE_TARGETING)), 0, 2)
	attack_move_mode = clampi(int(cfg.get_value("gameplay", "attack_move_mode", AttackMoveMode.QUICK_CAST)), 0, 1)
	smart_box_select_enabled = bool(cfg.get_value("gameplay", "smart_box_select_enabled", false))
	show_alert_toasts = bool(cfg.get_value("gameplay", "show_alert_toasts", true))
	camera_shake_enabled = bool(cfg.get_value("gameplay", "camera_shake_enabled", true))
	battle_scars_enabled = bool(cfg.get_value("gameplay", "battle_scars_enabled", true))
	build_grid_snap_enabled = bool(cfg.get_value("gameplay", "build_grid_snap_enabled", false))

	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 0.72)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 0.85)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value("audio", "ui_volume", 0.85)), 0.0, 1.0)
	ambience_volume = clampf(float(cfg.get_value("audio", "ambience_volume", 0.35)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", false))
	mute_when_unfocused = bool(cfg.get_value("audio", "mute_when_unfocused", false))

	window_mode = clampi(int(cfg.get_value("display", "window_mode", 0)), 0, 2)
	var res_x: int = int(cfg.get_value("display", "resolution_x", 1280))
	var res_y: int = int(cfg.get_value("display", "resolution_y", 720))
	window_resolution = Vector2i(maxi(800, res_x), maxi(600, res_y))
	vsync_enabled = bool(cfg.get_value("display", "vsync_enabled", true))
	var loaded_fps: int = int(cfg.get_value("display", "fps_cap", 0))
	fps_cap = loaded_fps if FPS_CAP_PRESETS.has(loaded_fps) else 0
	show_fps_counter = bool(cfg.get_value("display", "show_fps_counter", false))

	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		var default_bind: String = encode_key_binding(int(entry["default_key"]))
		var raw_val: Variant = cfg.get_value("keybinds", String(act), default_bind)
		keybinds[act] = _normalize_loaded_binding(raw_val, default_bind)


func _normalize_loaded_binding(raw_val: Variant, fallback_bind: String) -> String:
	# Backward compatibility: Milestone 1.6 saved raw integer keycodes in [keybinds].
	if raw_val is int:
		var k_int: int = int(raw_val)
		if k_int == KEY_NONE:
			return "none"
		if RESERVED_EDITOR_KEYS.has(k_int):
			return fallback_bind
		return encode_key_binding(k_int)
	if raw_val is String:
		var s: String = (raw_val as String).strip_edges().to_lower()
		if s == "none" or s.is_empty():
			return "none"
		if s.begins_with("key:"):
			var k_parsed: int = int(s.substr(4))
			if k_parsed <= 0 or RESERVED_EDITOR_KEYS.has(k_parsed):
				return fallback_bind
			return "key:%d" % k_parsed
		if s.begins_with("mouse:"):
			var m_parsed: int = int(s.substr(6))
			if not is_mouse_button_allowed(m_parsed):
				return fallback_bind
			return "mouse:%d" % m_parsed
		if s.is_valid_int():
			var legacy_int: int = int(s)
			if legacy_int == KEY_NONE:
				return "none"
			if RESERVED_EDITOR_KEYS.has(legacy_int):
				return fallback_bind
			return "key:%d" % legacy_int
	return fallback_bind


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("camera", "edge_pan_enabled", edge_pan_enabled)
	cfg.set_value("camera", "edge_pan_speed", edge_pan_speed)
	cfg.set_value("camera", "edge_pan_margin", edge_pan_margin)
	cfg.set_value("camera", "keyboard_pan_speed", keyboard_pan_speed)
	cfg.set_value("camera", "zoom_speed", zoom_speed)
	cfg.set_value("camera", "zoom_to_cursor", zoom_to_cursor)
	cfg.set_value("camera", "confine_cursor", confine_cursor)
	cfg.set_value("camera", "invert_zoom", invert_zoom)
	cfg.set_value("camera", "middle_drag_speed", middle_drag_speed)

	cfg.set_value("gameplay", "health_bar_mode", health_bar_mode)
	cfg.set_value("gameplay", "attack_range_mode", attack_range_mode)
	cfg.set_value("gameplay", "attack_move_mode", attack_move_mode)
	cfg.set_value("gameplay", "smart_box_select_enabled", smart_box_select_enabled)
	cfg.set_value("gameplay", "show_alert_toasts", show_alert_toasts)
	cfg.set_value("gameplay", "camera_shake_enabled", camera_shake_enabled)
	cfg.set_value("gameplay", "battle_scars_enabled", battle_scars_enabled)
	cfg.set_value("gameplay", "build_grid_snap_enabled", build_grid_snap_enabled)

	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "mute_when_unfocused", mute_when_unfocused)

	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "resolution_x", window_resolution.x)
	cfg.set_value("display", "resolution_y", window_resolution.y)
	cfg.set_value("display", "vsync_enabled", vsync_enabled)
	cfg.set_value("display", "fps_cap", fps_cap)
	cfg.set_value("display", "show_fps_counter", show_fps_counter)

	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		var default_bind: String = encode_key_binding(int(entry["default_key"]))
		cfg.set_value("keybinds", String(act), String(keybinds.get(act, default_bind)))

	cfg.save(CONFIG_PATH)


func set_camera_settings(
	p_edge_pan_enabled: bool,
	p_edge_pan_speed: float,
	p_edge_pan_margin: float,
	p_keyboard_pan_speed: float,
	p_zoom_speed: float,
	p_confine_cursor: Variant = null,
	p_invert_zoom: Variant = null,
	p_middle_drag_speed: Variant = null,
	p_zoom_to_cursor: Variant = null
) -> void:
	edge_pan_enabled = p_edge_pan_enabled
	edge_pan_speed = clampf(p_edge_pan_speed, 300.0, 1800.0)
	edge_pan_margin = clampf(p_edge_pan_margin, 8.0, 64.0)
	keyboard_pan_speed = clampf(p_keyboard_pan_speed, 250.0, 1400.0)
	zoom_speed = clampf(p_zoom_speed, 0.05, 0.30)
	if p_confine_cursor is bool:
		confine_cursor = bool(p_confine_cursor)
	if p_invert_zoom is bool:
		invert_zoom = bool(p_invert_zoom)
	if p_middle_drag_speed is float or p_middle_drag_speed is int:
		middle_drag_speed = clampf(float(p_middle_drag_speed), 0.4, 2.5)
	if p_zoom_to_cursor is bool:
		zoom_to_cursor = bool(p_zoom_to_cursor)
	refresh_mouse_mode()
	save_settings()
	settings_changed.emit(&"camera")


func set_gameplay_settings(
	p_health_bar_mode: int,
	p_show_alert_toasts: bool,
	p_camera_shake_enabled: Variant = null,
	p_attack_range_mode: Variant = null,
	p_attack_move_mode: Variant = null,
	p_smart_box_select_enabled: Variant = null,
	p_battle_scars_enabled: Variant = null,
	p_build_grid_snap_enabled: Variant = null
) -> void:
	health_bar_mode = clampi(p_health_bar_mode, 0, 2)
	show_alert_toasts = p_show_alert_toasts
	if p_camera_shake_enabled is bool:
		camera_shake_enabled = bool(p_camera_shake_enabled)
	if p_attack_range_mode is int:
		attack_range_mode = clampi(int(p_attack_range_mode), 0, 2)
	if p_attack_move_mode is int:
		attack_move_mode = clampi(int(p_attack_move_mode), 0, 1)
	if p_smart_box_select_enabled is bool:
		smart_box_select_enabled = bool(p_smart_box_select_enabled)
	if p_battle_scars_enabled is bool:
		battle_scars_enabled = bool(p_battle_scars_enabled)
	if p_build_grid_snap_enabled is bool:
		build_grid_snap_enabled = bool(p_build_grid_snap_enabled)
	save_settings()
	settings_changed.emit(&"gameplay")


func toggle_smart_box_select() -> bool:
	smart_box_select_enabled = not smart_box_select_enabled
	save_settings()
	settings_changed.emit(&"gameplay")
	return smart_box_select_enabled


func set_audio_settings(
	p_master: float,
	p_sfx: float,
	p_ui: float,
	p_muted: bool,
	p_mute_unfocused: Variant = null,
	p_ambience: Variant = null
) -> void:
	master_volume = clampf(p_master, 0.0, 1.0)
	sfx_volume = clampf(p_sfx, 0.0, 1.0)
	ui_volume = clampf(p_ui, 0.0, 1.0)
	if p_ambience is float or p_ambience is int:
		ambience_volume = clampf(float(p_ambience), 0.0, 1.0)
	muted = p_muted
	if p_mute_unfocused is bool:
		mute_when_unfocused = bool(p_mute_unfocused)
		if not mute_when_unfocused and AudioManager != null and AudioManager.has_method("set_unfocused_mute"):
			AudioManager.set_unfocused_mute(false)
	save_settings()
	settings_changed.emit(&"audio")


func set_display_settings(
	p_window_mode: int,
	p_resolution: Vector2i,
	p_vsync_enabled: Variant = null,
	p_fps_cap: Variant = null,
	p_show_fps_counter: Variant = null
) -> void:
	window_mode = clampi(p_window_mode, 0, 2)
	window_resolution = Vector2i(maxi(800, p_resolution.x), maxi(600, p_resolution.y))
	if p_vsync_enabled is bool:
		vsync_enabled = bool(p_vsync_enabled)
	if p_fps_cap is int:
		var cap_i: int = int(p_fps_cap)
		fps_cap = cap_i if FPS_CAP_PRESETS.has(cap_i) else 0
	if p_show_fps_counter is bool:
		show_fps_counter = bool(p_show_fps_counter)
	apply_display_settings()
	save_settings()
	settings_changed.emit(&"display")


func set_gameplay_cursor_active(active: bool) -> void:
	_gameplay_cursor_active = active
	refresh_mouse_mode()


func refresh_mouse_mode() -> void:
	var should_confine: bool = confine_cursor and _gameplay_cursor_active and _window_focused
	if should_confine and is_inside_tree():
		var settings_node: Node = get_tree().get_first_node_in_group("settings_menu")
		if settings_node != null and is_instance_valid(settings_node) and not settings_node.is_queued_for_deletion():
			should_confine = false
	if should_confine and is_inside_tree():
		var pause_node: Node = get_tree().get_first_node_in_group("pause_menu")
		if pause_node != null and is_instance_valid(pause_node) and pause_node.has_method("is_pause_open"):
			if bool(pause_node.call("is_pause_open")):
				should_confine = false
	if should_confine and is_inside_tree():
		var tech_node: Node = get_tree().get_first_node_in_group("tech_tree_overlay")
		if tech_node != null and is_instance_valid(tech_node) and not tech_node.is_queued_for_deletion():
			should_confine = false
	if should_confine and is_inside_tree():
		var end_node: Node = get_tree().get_first_node_in_group("match_end_overlay")
		if end_node != null and is_instance_valid(end_node) and end_node.has_method("is_summary_visible"):
			if bool(end_node.call("is_summary_visible")):
				should_confine = false

	var target_mode: Input.MouseMode = Input.MOUSE_MODE_CONFINED if should_confine else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != target_mode:
		Input.mouse_mode = target_mode


func toggle_fullscreen() -> void:
	var next_mode: int = 1 if window_mode == 0 else 0
	set_display_settings(next_mode, window_resolution)


func is_fullscreen() -> bool:
	var win: Window = get_window()
	if win != null:
		return win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	return window_mode != 0


func apply_display_settings() -> void:
	var win: Window = get_window()
	if win != null:
		if window_mode == 2:
			win.borderless = false
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		elif window_mode == 1:
			# Godot 4's native borderless fullscreen — leave borderless=false to prevent Win11 DWM overscan/taskbar overlap.
			win.borderless = false
			win.mode = Window.MODE_FULLSCREEN
		else:
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			win.size = window_resolution
			var screen_idx: int = win.current_screen
			var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen_idx)
			if usable.size.x > 0 and usable.size.y > 0:
				var centered_pos: Vector2i = usable.position + (usable.size - window_resolution) / 2
				win.position = Vector2i(
					maxi(usable.position.x, centered_pos.x),
					maxi(usable.position.y, centered_pos.y)
				)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = maxi(0, fps_cap)
	_sync_fps_counter_overlay()
	refresh_mouse_mode()


func _sync_fps_counter_overlay() -> void:
	if show_fps_counter:
		if _fps_counter_overlay == null or not is_instance_valid(_fps_counter_overlay):
			_fps_counter_overlay = FPS_COUNTER_SCRIPT.new() as CanvasLayer
			_fps_counter_overlay.name = "FPSCounterOverlay"
			add_child(_fps_counter_overlay)
		_fps_counter_overlay.visible = true
	elif _fps_counter_overlay != null and is_instance_valid(_fps_counter_overlay):
		_fps_counter_overlay.visible = false


func encode_key_binding(keycode: int) -> String:
	return "none" if keycode == KEY_NONE else ("key:%d" % keycode)


func encode_mouse_binding(button_index: int) -> String:
	return "mouse:%d" % button_index


func is_key_reserved_for_editor(keycode: int) -> bool:
	return RESERVED_EDITOR_KEYS.has(keycode)


func is_mouse_button_allowed(button_index: int) -> bool:
	return ALLOWED_MOUSE_BUTTONS.has(button_index)


func is_mouse_button_bound(button_index: int) -> bool:
	var encoded: String = encode_mouse_binding(button_index)
	for entry: Dictionary in KEYBIND_DEFS:
		if get_action_binding(entry["action"]) == encoded:
			return true
	return false


func set_action_keybind(action_name: StringName, keycode: Key, resolve_conflicts: bool = true) -> Array[StringName]:
	var cleared: Array[StringName] = []
	if is_key_reserved_for_editor(int(keycode)):
		return cleared
	return _set_action_encoded_binding(action_name, encode_key_binding(int(keycode)), resolve_conflicts)


func set_action_mouse_bind(action_name: StringName, button_index: MouseButton, resolve_conflicts: bool = true) -> Array[StringName]:
	var cleared: Array[StringName] = []
	if not is_mouse_button_allowed(int(button_index)):
		return cleared
	return _set_action_encoded_binding(action_name, encode_mouse_binding(int(button_index)), resolve_conflicts)


func clear_action_bind(action_name: StringName) -> void:
	_set_action_encoded_binding(action_name, "none", false)


## Backward-compatible wrapper from Milestone 1.6.
func set_action_key(action_name: StringName, keycode: int) -> bool:
	if is_key_reserved_for_editor(keycode):
		return false
	_set_action_encoded_binding(action_name, encode_key_binding(keycode), true)
	return true


func _set_action_encoded_binding(action_name: StringName, encoded: String, resolve_conflicts: bool) -> Array[StringName]:
	var reassigned: Array[StringName] = []
	if resolve_conflicts and encoded != "none":
		for other_act: StringName in find_conflicting_actions(action_name, encoded):
			keybinds[other_act] = "none"
			_apply_action_binding_to_input_map(other_act, "none")
			reassigned.append(other_act)
			keybind_changed.emit(other_act)

	keybinds[action_name] = encoded
	_apply_action_binding_to_input_map(action_name, encoded)
	save_settings()
	keybind_changed.emit(action_name)
	settings_changed.emit(&"controls")
	return reassigned


func reset_action_to_default(action_name: StringName) -> Array[StringName]:
	for entry: Dictionary in KEYBIND_DEFS:
		if entry["action"] == action_name:
			return _set_action_encoded_binding(action_name, encode_key_binding(int(entry["default_key"])), true)
	return []


func get_action_binding(action_name: StringName) -> String:
	if keybinds.has(action_name):
		return String(keybinds[action_name])
	for entry: Dictionary in KEYBIND_DEFS:
		if entry["action"] == action_name:
			return encode_key_binding(int(entry["default_key"]))
	return "none"


func get_action_keycode(action_name: StringName) -> int:
	var binding: String = get_action_binding(action_name)
	if binding.begins_with("key:"):
		return int(binding.substr(4))
	return KEY_NONE


func get_action_label(action_name: StringName) -> String:
	for entry: Dictionary in KEYBIND_DEFS:
		if entry["action"] == action_name:
			return String(entry["label"])
	return String(action_name)


func get_action_display_label(action_name: StringName, compact: bool = false) -> String:
	return format_binding(get_action_binding(action_name), compact)


func get_action_key_label(action_name: StringName) -> String:
	return get_action_display_label(action_name, false)


func format_binding(encoded: String, compact: bool = false) -> String:
	if encoded == "none" or encoded.is_empty():
		return "" if compact else "Unbound"
	if encoded.begins_with("mouse:"):
		var btn: int = int(encoded.substr(6))
		return format_mouse_button(btn, compact)
	if encoded.begins_with("key:"):
		var code: int = int(encoded.substr(4))
		return format_keycode(code, compact)
	return "" if compact else "Unbound"


func format_mouse_button(button_index: int, compact: bool = false) -> String:
	match button_index:
		MOUSE_BUTTON_XBUTTON1:
			return "M4" if compact else "Mouse 4"
		MOUSE_BUTTON_XBUTTON2:
			return "M5" if compact else "Mouse 5"
		MOUSE_BUTTON_MIDDLE:
			return "M3" if compact else "Mouse 3"
	return ("M%d" % button_index) if compact else ("Mouse %d" % button_index)


func format_keycode(keycode: int, compact: bool = false) -> String:
	match keycode:
		KEY_QUOTELEFT:
			return "`"
		KEY_BACKSPACE:
			return "BKSP" if compact else "Bksp"
		KEY_SPACE:
			return "SPC" if compact else "Space"
		KEY_UP:
			return "UP" if compact else "Up"
		KEY_DOWN:
			return "DN" if compact else "Down"
		KEY_LEFT:
			return "LT" if compact else "Left"
		KEY_RIGHT:
			return "RT" if compact else "Right"
		KEY_HOME:
			return "HOME" if compact else "Home"
		KEY_ESCAPE:
			return "ESC" if compact else "Esc"
		KEY_TAB:
			return "TAB" if compact else "Tab"
		KEY_DELETE:
			return "DEL" if compact else "Del"
		KEY_BRACKETLEFT:
			return "["
		KEY_BRACKETRIGHT:
			return "]"
		KEY_SEMICOLON:
			return ";"
		KEY_PERIOD:
			return "."
		KEY_NONE:
			return "" if compact else "Unbound"
	return OS.get_keycode_string(keycode as Key)


func find_conflicting_actions(action_name: StringName, binding_or_code: Variant) -> Array[StringName]:
	var target_bind: String = ""
	if binding_or_code is String:
		target_bind = String(binding_or_code)
	elif binding_or_code is int:
		target_bind = encode_key_binding(int(binding_or_code))
	var conflicts: Array[StringName] = []
	if target_bind == "none" or target_bind.is_empty():
		return conflicts
	for entry: Dictionary in KEYBIND_DEFS:
		var other: StringName = entry["action"]
		if other == action_name:
			continue
		if get_action_binding(other) == target_bind:
			conflicts.append(other)
	return conflicts


func reset_category(category: StringName) -> void:
	match category:
		&"camera":
			edge_pan_enabled = true
			edge_pan_speed = 900.0
			edge_pan_margin = 24.0
			keyboard_pan_speed = 650.0
			zoom_speed = 0.12
			zoom_to_cursor = true
			confine_cursor = false
			invert_zoom = false
			middle_drag_speed = 1.0
			refresh_mouse_mode()
			save_settings()
			settings_changed.emit(&"camera")
		&"gameplay":
			health_bar_mode = 0
			attack_range_mode = AttackRangeMode.SHOW_WHILE_TARGETING
			attack_move_mode = AttackMoveMode.QUICK_CAST
			smart_box_select_enabled = false
			show_alert_toasts = true
			camera_shake_enabled = true
			battle_scars_enabled = true
			build_grid_snap_enabled = false
			save_settings()
			settings_changed.emit(&"gameplay")
		&"audio":
			master_volume = 0.72
			sfx_volume = 0.85
			ui_volume = 0.85
			ambience_volume = 0.35
			muted = false
			mute_when_unfocused = false
			if AudioManager != null and AudioManager.has_method("set_unfocused_mute"):
				AudioManager.set_unfocused_mute(false)
			save_settings()
			settings_changed.emit(&"audio")
		&"display":
			window_mode = 0
			window_resolution = Vector2i(1280, 720)
			vsync_enabled = true
			fps_cap = 0
			show_fps_counter = false
			apply_display_settings()
			save_settings()
			settings_changed.emit(&"display")
		&"controls":
			_init_default_keybinds()
			apply_input_map()
			save_settings()
			for entry: Dictionary in KEYBIND_DEFS:
				keybind_changed.emit(entry["action"])
			settings_changed.emit(&"controls")


func reset_all_to_defaults() -> void:
	edge_pan_enabled = true
	edge_pan_speed = 900.0
	edge_pan_margin = 24.0
	keyboard_pan_speed = 650.0
	zoom_speed = 0.12
	zoom_to_cursor = true
	confine_cursor = false
	invert_zoom = false
	middle_drag_speed = 1.0
	health_bar_mode = 0
	attack_range_mode = AttackRangeMode.SHOW_WHILE_TARGETING
	attack_move_mode = AttackMoveMode.QUICK_CAST
	smart_box_select_enabled = false
	show_alert_toasts = true
	camera_shake_enabled = true
	battle_scars_enabled = true
	build_grid_snap_enabled = false
	master_volume = 0.72
	sfx_volume = 0.85
	ui_volume = 0.85
	ambience_volume = 0.35
	muted = false
	mute_when_unfocused = false
	if AudioManager != null and AudioManager.has_method("set_unfocused_mute"):
		AudioManager.set_unfocused_mute(false)
	window_mode = 0
	window_resolution = Vector2i(1280, 720)
	vsync_enabled = true
	fps_cap = 0
	show_fps_counter = false
	_init_default_keybinds()
	apply_input_map()
	apply_display_settings()
	save_settings()
	for entry: Dictionary in KEYBIND_DEFS:
		keybind_changed.emit(entry["action"])
	settings_changed.emit(&"all")


func apply_input_map() -> void:
	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		var default_bind: String = encode_key_binding(int(entry["default_key"]))
		var binding: String = String(keybinds.get(act, default_bind))
		_apply_action_binding_to_input_map(act, binding)


func _apply_action_binding_to_input_map(action_name: StringName, encoded: String) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	InputMap.action_erase_events(action_name)

	if encoded == "none" or encoded.is_empty():
		return

	if encoded.begins_with("mouse:"):
		var btn_idx: int = int(encoded.substr(6))
		if is_mouse_button_allowed(btn_idx):
			var mev: InputEventMouseButton = InputEventMouseButton.new()
			mev.button_index = btn_idx as MouseButton
			InputMap.action_add_event(action_name, mev)
		return

	if encoded.begins_with("key:"):
		var keycode: int = int(encoded.substr(4))
		if keycode != KEY_NONE:
			var ev: InputEventKey = InputEventKey.new()
			ev.keycode = keycode as Key
			ev.physical_keycode = keycode as Key
			InputMap.action_add_event(action_name, ev)

		# Keep secondary convenience alias: Home also jumps to Nexus Vat when jump_base_hub is Backspace.
		if action_name == &"jump_base_hub" and keycode == KEY_BACKSPACE:
			var home_ev: InputEventKey = InputEventKey.new()
			home_ev.keycode = KEY_HOME
			home_ev.physical_keycode = KEY_HOME
			InputMap.action_add_event(action_name, home_ev)
