class_name PauseMenu
extends CanvasLayer

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

@onready var root_control: Control = %RootControl
@onready var btn_resume: Button = %BtnResume
@onready var btn_settings: Button = %BtnSettings
@onready var btn_restart: Button = %BtnRestart
@onready var btn_main_menu: Button = %BtnMainMenu

var _settings_instance: SettingsMenu = null


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
	if btn_restart != null:
		btn_restart.pressed.connect(_restart_skirmish)
	if btn_main_menu != null:
		btn_main_menu.pressed.connect(_quit_to_main_menu)


func is_pause_open() -> bool:
	return root_control != null and root_control.visible


func is_settings_open() -> bool:
	return _settings_instance != null and is_instance_valid(_settings_instance)


func toggle_pause() -> void:
	if is_pause_open():
		close_pause()
	else:
		open_pause()


func open_pause() -> void:
	if is_pause_open():
		return
	if AudioManager != null:
		AudioManager.play_ui_click()
	if root_control != null:
		root_control.visible = true
	if is_inside_tree():
		get_tree().paused = true
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func close_pause() -> void:
	if not is_pause_open():
		return
	if is_settings_open():
		_settings_instance.queue_free()
		_settings_instance = null
	if AudioManager != null:
		AudioManager.play_ui_click()
	if root_control != null:
		root_control.visible = false
	if is_inside_tree():
		get_tree().paused = false
	if SettingsManager != null:
		SettingsManager.call_deferred("refresh_mouse_mode")


func _unhandled_input(event: InputEvent) -> void:
	if not is_pause_open():
		return
	if is_settings_open():
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
	if is_inside_tree():
		get_tree().paused = false
		get_tree().reload_current_scene()


func _quit_to_main_menu() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		get_tree().paused = false
		get_tree().change_scene_to_file(GameConfig.MAIN_MENU_SCENE)
