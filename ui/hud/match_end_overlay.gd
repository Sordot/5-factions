class_name MatchEndOverlay
extends CanvasLayer

@onready var root_control: Control = %RootControl
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var duration_value: Label = %DurationValue
@onready var winner_value: Label = %WinnerValue
@onready var uplink_value: Label = %UplinkValue
@onready var trained_value: Label = %TrainedValue
@onready var lost_value: Label = %LostValue
@onready var destroyed_value: Label = %DestroyedValue
@onready var btn_play_again: Button = %BtnPlayAgain
@onready var btn_main_menu: Button = %BtnMainMenu
@onready var btn_sandbox_mode: Button = %BtnSandboxMode


func _ready() -> void:
	add_to_group("match_end_overlay")
	layer = 10
	if root_control != null:
		root_control.visible = false
	if btn_play_again != null:
		btn_play_again.pressed.connect(_on_play_again_pressed)
	if btn_main_menu != null:
		btn_main_menu.pressed.connect(_on_main_menu_pressed)
	if btn_sandbox_mode != null:
		btn_sandbox_mode.pressed.connect(_on_sandbox_mode_pressed)


func is_summary_visible() -> bool:
	return root_control != null and root_control.visible


func show_summary(stats: Dictionary) -> void:
	var is_victory: bool = bool(stats.get("is_victory", false))
	if AudioManager != null:
		AudioManager.play_sfx(&"match_victory" if is_victory else &"match_defeat", -2.0, 0.0)
	if title_label != null:
		title_label.text = "VICTORY" if is_victory else "DEFEAT"
		title_label.add_theme_color_override(
			"font_color",
			Color(0.22, 0.98, 0.90, 1.0) if is_victory else Color(1.0, 0.36, 0.30, 1.0)
		)
	if subtitle_label != null:
		subtitle_label.text = str(stats.get("reason", ""))
	if duration_value != null:
		duration_value.text = str(stats.get("duration_formatted", "00:00"))
	if winner_value != null:
		winner_value.text = str(stats.get("winner_label", "--"))
	if uplink_value != null:
		uplink_value.text = "%d%%" % int(round(float(stats.get("uplink_control_pct", 0.0))))
	if trained_value != null:
		trained_value.text = str(int(stats.get("units_trained", 0)))
	if lost_value != null:
		lost_value.text = str(int(stats.get("units_lost", 0)))
	if destroyed_value != null:
		destroyed_value.text = str(int(stats.get("enemies_destroyed", 0)))

	if root_control != null:
		root_control.visible = true
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func hide_summary() -> void:
	if root_control != null:
		root_control.visible = false
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func _on_play_again_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		get_tree().change_scene_to_file(GameConfig.MAIN_MENU_SCENE)


func _on_sandbox_mode_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	hide_summary()
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null:
			match_mgr.enter_sandbox_mode()
