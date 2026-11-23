extends Node

signal settings_changed(category: StringName)
signal keybind_changed(action_name: StringName)

const CONFIG_PATH: String = "user://settings.cfg"

const RESOLUTION_PRESETS: Array = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## Godot-safe default keybind catalog (explicitly avoids F5, F6, F7, F8).
const KEYBIND_DEFS: Array = [
	{"action": &"cmd_attack_move", "label": "Attack-Move", "default_key": KEY_A, "category": "Unit Commands"},
	{"action": &"cmd_stop", "label": "Stop", "default_key": KEY_S, "category": "Unit Commands"},
	{"action": &"cmd_hold", "label": "Hold Position", "default_key": KEY_H, "category": "Unit Commands"},
	{"action": &"cmd_patrol", "label": "Patrol", "default_key": KEY_P, "category": "Unit Commands"},
	{"action": &"cmd_select_idle_worker", "label": "Select Idle Worker", "default_key": KEY_QUOTELEFT, "category": "Selection & Spatial"},
	{"action": &"jump_base_hub", "label": "Jump to Nexus Vat", "default_key": KEY_BACKSPACE, "category": "Selection & Spatial"},
	{"action": &"jump_last_alert", "label": "Jump to Last Alert", "default_key": KEY_SPACE, "category": "Selection & Spatial"},
	{"action": &"cam_bookmark_1", "label": "Camera Bookmark 1 (Ctrl=Save)", "default_key": KEY_F1, "category": "Camera Bookmarks"},
	{"action": &"cam_bookmark_2", "label": "Camera Bookmark 2 (Ctrl=Save)", "default_key": KEY_F2, "category": "Camera Bookmarks"},
	{"action": &"cam_bookmark_3", "label": "Camera Bookmark 3 (Ctrl=Save)", "default_key": KEY_F3, "category": "Camera Bookmarks"},
	{"action": &"cam_bookmark_4", "label": "Camera Bookmark 4 (Ctrl=Save)", "default_key": KEY_F4, "category": "Camera Bookmarks"},
	{"action": &"camera_pan_up", "label": "Camera Pan Up", "default_key": KEY_UP, "category": "Camera Controls"},
	{"action": &"camera_pan_down", "label": "Camera Pan Down", "default_key": KEY_DOWN, "category": "Camera Controls"},
	{"action": &"camera_pan_left", "label": "Camera Pan Left", "default_key": KEY_LEFT, "category": "Camera Controls"},
	{"action": &"camera_pan_right", "label": "Camera Pan Right", "default_key": KEY_RIGHT, "category": "Camera Controls"},
	{"action": &"camera_toggle_edge_pan", "label": "Toggle Edge-Pan", "default_key": KEY_F12, "category": "Camera Controls"},
	{"action": &"camera_toggle_fullscreen", "label": "Toggle Fullscreen", "default_key": KEY_F11, "category": "System"},
	{"action": &"debug_toggle_aggro_ai", "label": "Toggle Aggro AI (Debug)", "default_key": KEY_F10, "category": "System"},
]

const RESERVED_EDITOR_KEYS: Array = [KEY_F5, KEY_F6, KEY_F7, KEY_F8]

# Camera preferences
var edge_pan_enabled: bool = true
var edge_pan_speed: float = 900.0
var edge_pan_margin: float = 24.0
var keyboard_pan_speed: float = 650.0
var zoom_speed: float = 0.12

# Audio preferences
var master_volume: float = 0.72
var sfx_volume: float = 0.85
var ui_volume: float = 0.85
var muted: bool = false

# Display preferences
var window_mode: int = 0 # 0 = Windowed, 1 = Borderless Fullscreen, 2 = Fullscreen
var window_resolution: Vector2i = Vector2i(1280, 720)

# Action -> Key mapping
var keybinds: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_default_keybinds()
	load_settings()
	_apply_all_keybinds_to_input_map()
	apply_display_settings()


func _init_default_keybinds() -> void:
	keybinds.clear()
	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		keybinds[act] = int(entry["default_key"])


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(CONFIG_PATH)
	if err != OK:
		_apply_all_keybinds_to_input_map()
		save_settings()
		return

	edge_pan_enabled = bool(cfg.get_value("camera", "edge_pan_enabled", true))
	edge_pan_speed = clampf(float(cfg.get_value("camera", "edge_pan_speed", 900.0)), 300.0, 1800.0)
	edge_pan_margin = clampf(float(cfg.get_value("camera", "edge_pan_margin", 24.0)), 8.0, 64.0)
	keyboard_pan_speed = clampf(float(cfg.get_value("camera", "keyboard_pan_speed", 650.0)), 250.0, 1400.0)
	zoom_speed = clampf(float(cfg.get_value("camera", "zoom_speed", 0.12)), 0.05, 0.30)

	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 0.72)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 0.85)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value("audio", "ui_volume", 0.85)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", false))

	window_mode = clampi(int(cfg.get_value("display", "window_mode", 0)), 0, 2)
	var res_x: int = int(cfg.get_value("display", "resolution_x", 1280))
	var res_y: int = int(cfg.get_value("display", "resolution_y", 720))
	window_resolution = Vector2i(maxi(800, res_x), maxi(600, res_y))

	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		var default_k: int = int(entry["default_key"])
		var loaded_k: int = int(cfg.get_value("keybinds", String(act), default_k))
		if RESERVED_EDITOR_KEYS.has(loaded_k):
			loaded_k = default_k
		keybinds[act] = loaded_k


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("camera", "edge_pan_enabled", edge_pan_enabled)
	cfg.set_value("camera", "edge_pan_speed", edge_pan_speed)
	cfg.set_value("camera", "edge_pan_margin", edge_pan_margin)
	cfg.set_value("camera", "keyboard_pan_speed", keyboard_pan_speed)
	cfg.set_value("camera", "zoom_speed", zoom_speed)

	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
	cfg.set_value("audio", "muted", muted)

	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "resolution_x", window_resolution.x)
	cfg.set_value("display", "resolution_y", window_resolution.y)

	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		cfg.set_value("keybinds", String(act), int(keybinds.get(act, entry["default_key"])))

	cfg.save(CONFIG_PATH)


func set_camera_settings(
	p_edge_pan_enabled: bool,
	p_edge_pan_speed: float,
	p_edge_pan_margin: float,
	p_keyboard_pan_speed: float,
	p_zoom_speed: float
) -> void:
	edge_pan_enabled = p_edge_pan_enabled
	edge_pan_speed = clampf(p_edge_pan_speed, 300.0, 1800.0)
	edge_pan_margin = clampf(p_edge_pan_margin, 8.0, 64.0)
	keyboard_pan_speed = clampf(p_keyboard_pan_speed, 250.0, 1400.0)
	zoom_speed = clampf(p_zoom_speed, 0.05, 0.30)
	save_settings()
	settings_changed.emit(&"camera")


func set_audio_settings(p_master: float, p_sfx: float, p_ui: float, p_muted: bool) -> void:
	master_volume = clampf(p_master, 0.0, 1.0)
	sfx_volume = clampf(p_sfx, 0.0, 1.0)
	ui_volume = clampf(p_ui, 0.0, 1.0)
	muted = p_muted
	save_settings()
	settings_changed.emit(&"audio")


func set_display_settings(p_window_mode: int, p_resolution: Vector2i) -> void:
	window_mode = clampi(p_window_mode, 0, 2)
	window_resolution = Vector2i(maxi(800, p_resolution.x), maxi(600, p_resolution.y))
	apply_display_settings()
	save_settings()
	settings_changed.emit(&"display")


func apply_display_settings() -> void:
	var win: Window = get_window()
	if window_mode == 2:
		if win != null:
			win.borderless = false
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif window_mode == 1:
		if win != null:
			win.borderless = true
			win.mode = Window.MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if win != null:
			win.borderless = false
			win.mode = Window.MODE_WINDOWED
			win.size = window_resolution
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_resolution)


func is_key_reserved_for_editor(keycode: int) -> bool:
	return RESERVED_EDITOR_KEYS.has(keycode)


func set_action_key(action_name: StringName, keycode: int) -> bool:
	if is_key_reserved_for_editor(keycode):
		return false
	keybinds[action_name] = keycode
	_apply_action_to_input_map(action_name, keycode)
	save_settings()
	keybind_changed.emit(action_name)
	settings_changed.emit(&"controls")
	return true


func reset_action_to_default(action_name: StringName) -> void:
	for entry: Dictionary in KEYBIND_DEFS:
		if entry["action"] == action_name:
			set_action_key(action_name, int(entry["default_key"]))
			return


func get_action_keycode(action_name: StringName) -> int:
	if keybinds.has(action_name):
		return int(keybinds[action_name])
	for entry: Dictionary in KEYBIND_DEFS:
		if entry["action"] == action_name:
			return int(entry["default_key"])
	return KEY_NONE


func get_action_key_label(action_name: StringName) -> String:
	var code: int = get_action_keycode(action_name)
	return format_keycode(code)


func format_keycode(keycode: int) -> String:
	match keycode:
		KEY_QUOTELEFT:
			return "`"
		KEY_BACKSPACE:
			return "Bksp"
		KEY_SPACE:
			return "Space"
		KEY_UP:
			return "Up"
		KEY_DOWN:
			return "Down"
		KEY_LEFT:
			return "Left"
		KEY_RIGHT:
			return "Right"
		KEY_HOME:
			return "Home"
		KEY_ESCAPE:
			return "Esc"
		KEY_TAB:
			return "Tab"
		KEY_NONE:
			return "Unbound"
	return OS.get_keycode_string(keycode as Key)


func find_conflicting_actions(action_name: StringName, keycode: int) -> Array[StringName]:
	var conflicts: Array[StringName] = []
	if keycode == KEY_NONE:
		return conflicts
	for entry: Dictionary in KEYBIND_DEFS:
		var other: StringName = entry["action"]
		if other == action_name:
			continue
		if get_action_keycode(other) == keycode:
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
			save_settings()
			settings_changed.emit(&"camera")
		&"audio":
			master_volume = 0.72
			sfx_volume = 0.85
			ui_volume = 0.85
			muted = false
			save_settings()
			settings_changed.emit(&"audio")
		&"display":
			window_mode = 0
			window_resolution = Vector2i(1280, 720)
			apply_display_settings()
			save_settings()
			settings_changed.emit(&"display")
		&"controls":
			_init_default_keybinds()
			_apply_all_keybinds_to_input_map()
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
	master_volume = 0.72
	sfx_volume = 0.85
	ui_volume = 0.85
	muted = false
	window_mode = 0
	window_resolution = Vector2i(1280, 720)
	_init_default_keybinds()
	_apply_all_keybinds_to_input_map()
	apply_display_settings()
	save_settings()
	for entry: Dictionary in KEYBIND_DEFS:
		keybind_changed.emit(entry["action"])
	settings_changed.emit(&"all")


func _apply_all_keybinds_to_input_map() -> void:
	for entry: Dictionary in KEYBIND_DEFS:
		var act: StringName = entry["action"]
		var code: int = int(keybinds.get(act, entry["default_key"]))
		_apply_action_to_input_map(act, code)


func _apply_action_to_input_map(action_name: StringName, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	InputMap.action_erase_events(action_name)
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
