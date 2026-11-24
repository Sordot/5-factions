class_name PauseMenu
extends CanvasLayer

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const TECH_TREE_SCENE_PATH: String = "res://scenes/ui/tech_tree_overlay.tscn"

@onready var root_control: Control = %RootControl
@onready var btn_resume: Button = %BtnResume
@onready var btn_settings: Button = %BtnSettings
@onready var btn_tech_tree: Button = %BtnTechTree
@onready var btn_toggle_debug_hud: Button = %BtnToggleDebugHud
@onready var btn_restart: Button = %BtnRestart
@onready var btn_main_menu: Button = %BtnMainMenu

var _settings_instance: SettingsMenu = null
var _tech_tree_instance: CanvasLayer = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	if root_control != null:
		root_control.visible = false
	if btn_resume != null:
		btn_resume.pressed.connect(close_pause)
	if btn_settings != null:
		btn_settings.pressed.connect(_open_settings)
	if btn_tech_tree != null:
		btn_tech_tree.pressed.connect(_open_tech_tree)
	if btn_toggle_debug_hud != null:
		btn_toggle_debug_hud.pressed.connect(_on_toggle_debug_hud_pressed)
	if btn_restart != null:
		btn_restart.pressed.connect(_restart_skirmish)
	if btn_main_menu != null:
		btn_main_menu.pressed.connect(_quit_to_main_menu)
	call_deferred("_refresh_debug_hud_button")


func is_pause_open() -> bool:
	return root_control != null and root_control.visible


func is_settings_open() -> bool:
	return _settings_instance != null and is_instance_valid(_settings_instance)


func is_tech_tree_open() -> bool:
	return _tech_tree_instance != null and is_instance_valid(_tech_tree_instance)


func toggle_pause() -> void:
	if is_pause_open():
		close_pause()
	else:
		open_pause()


func _reset_gameplay_cursors() -> void:
	if not is_inside_tree():
		return
	var sel: Node = get_tree().get_first_node_in_group("selection_controller")
	if sel != null and is_instance_valid(sel) and sel.has_method("reset_command_cursors"):
		sel.call("reset_command_cursors")
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func open_pause() -> void:
	if is_pause_open():
		return
	_reset_gameplay_cursors()
	if AudioManager != null:
		AudioManager.play_ui_click()
	Engine.time_scale = 1.0
	if root_control != null:
		root_control.visible = true
	_refresh_debug_hud_button()
	if is_inside_tree():
		get_tree().paused = true
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func _refresh_debug_hud_button() -> void:
	if btn_toggle_debug_hud == null or not is_inside_tree():
		return
	var panel: Node = get_tree().get_first_node_in_group("sandbox_debug_panel")
	if panel == null or not is_instance_valid(panel):
		btn_toggle_debug_hud.visible = false
		return
	btn_toggle_debug_hud.visible = true
	var is_on: bool = bool(panel.call("is_panel_visible")) if panel.has_method("is_panel_visible") else bool(panel.get("visible"))
	btn_toggle_debug_hud.text = "Sandbox / Debug HUD: ON" if is_on else "Sandbox / Debug HUD: OFF"
	btn_toggle_debug_hud.modulate = Color(0.38, 1.0, 0.88, 1.0) if is_on else Color(0.84, 0.90, 0.96, 0.92)


func _on_toggle_debug_hud_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if not is_inside_tree():
		return
	var panel: Node = get_tree().get_first_node_in_group("sandbox_debug_panel")
	if panel != null and is_instance_valid(panel):
		if panel.has_method("toggle_panel_visible"):
			panel.call("toggle_panel_visible")
		else:
			panel.set("visible", not bool(panel.get("visible")))
	_refresh_debug_hud_button()


func close_pause() -> void:
	if not is_pause_open():
		return
	if is_settings_open():
		_settings_instance.queue_free()
		_settings_instance = null
	if _tech_tree_instance != null and is_instance_valid(_tech_tree_instance):
		_tech_tree_instance.queue_free()
		_tech_tree_instance = null
	if AudioManager != null:
		AudioManager.play_ui_click()
	if root_control != null:
		root_control.visible = false
	if is_inside_tree():
		get_tree().paused = false
		var mm: Node = get_tree().get_first_node_in_group("match_manager")
		if mm != null and mm.get("current_game_speed") != null:
			Engine.time_scale = clampf(float(mm.get("current_game_speed")), 0.5, 2.0)
	if SettingsManager != null:
		SettingsManager.call_deferred("refresh_mouse_mode")


func _open_tech_tree() -> void:
	if _tech_tree_instance != null and is_instance_valid(_tech_tree_instance):
		return
	_reset_gameplay_cursors()
	if AudioManager != null:
		AudioManager.play_ui_click()
	var tech_scene: PackedScene = load(TECH_TREE_SCENE_PATH) as PackedScene
	if tech_scene == null:
		return
	_tech_tree_instance = tech_scene.instantiate() as CanvasLayer
	if _tech_tree_instance != null:
		if _tech_tree_instance.has_signal("closed"):
			_tech_tree_instance.connect("closed", func() -> void:
				_tech_tree_instance = null
			)
		get_tree().root.add_child(_tech_tree_instance)


func _unhandled_input(event: InputEvent) -> void:
	if not is_pause_open():
		return
	if is_settings_open() or is_tech_tree_open():
		return
	if event.is_action_pressed("cmd_cancel"):
		close_pause()
		get_viewport().set_input_as_handled()


func _open_settings() -> void:
	if is_settings_open():
		return
	if AudioManager != null:
		AudioManager.play_ui_click()
	_settings_instance = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	if _settings_instance != null:
		_settings_instance.closed.connect(func() -> void:
			_settings_instance = null
		)
		get_tree().root.add_child(_settings_instance)


func _restart_skirmish() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().paused = false
		get_tree().reload_current_scene()


func _quit_to_main_menu() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().paused = false
		get_tree().change_scene_to_file(GameConfig.MAIN_MENU_SCENE)
