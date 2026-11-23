class_name MainMenu
extends Control

@onready var btn_audio_mute: Button = %BtnAudioMute
@onready var map_option: OptionButton = %MapOption
@onready var btn_ai_standard: Button = %BtnAIStandard
@onready var btn_ai_passive: Button = %BtnAIPassive
@onready var btn_res_standard: Button = %BtnResStandard
@onready var btn_res_fast: Button = %BtnResFast
@onready var summary_label: Label = %MatchSummaryLabel
@onready var dossier_notice_label: Label = %DossierNoticeLabel
@onready var btn_launch: Button = %BtnLaunch
@onready var btn_quit: Button = %BtnQuit
@onready var locked_slot_2: Button = %LockedSlot2
@onready var locked_slot_3: Button = %LockedSlot3
@onready var locked_slot_4: Button = %LockedSlot4
@onready var locked_slot_5: Button = %LockedSlot5

var _selected_map_path: String = GameConfig.MAP_SKIRMISH_01
var _aggro_ai_enabled: bool = true
var _resource_preset: StringName = GameConfig.PRESET_STANDARD
var _bg_time: float = 0.0


func _ready() -> void:
	_selected_map_path = GameConfig.selected_map_path
	_aggro_ai_enabled = GameConfig.aggro_ai_enabled
	_resource_preset = GameConfig.resource_preset

	if map_option != null:
		map_option.clear()
		map_option.add_item("Skirmish Arena 01 (1v1 Symmetric)", 0)
		map_option.add_item("Sandbox Testbed (Milestone 0)", 1)
		map_option.select(1 if _selected_map_path == GameConfig.MAP_SANDBOX_TESTBED else 0)
		map_option.item_selected.connect(_on_map_selected)

	if btn_ai_standard != null:
		btn_ai_standard.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_aggro_ai_enabled = true
			_refresh_ui()
		)
	if btn_ai_passive != null:
		btn_ai_passive.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_aggro_ai_enabled = false
			_refresh_ui()
		)

	if btn_res_standard != null:
		btn_res_standard.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_resource_preset = GameConfig.PRESET_STANDARD
			_refresh_ui()
		)
	if btn_res_fast != null:
		btn_res_fast.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_resource_preset = GameConfig.PRESET_FAST_TECH
			_refresh_ui()
		)

	if btn_audio_mute != null:
		btn_audio_mute.pressed.connect(func() -> void:
			AudioManager.toggle_mute()
			_refresh_audio_button()
		)
	if not AudioManager.mute_changed.is_connected(_on_mute_changed):
		AudioManager.mute_changed.connect(_on_mute_changed)

	_wire_locked_card(locked_slot_2, "AETHER_PRIME // The Radiant Grid")
	_wire_locked_card(locked_slot_3, "IRON_CONSENSUS // The Foundry Bloc")
	_wire_locked_card(locked_slot_4, "NULL_VECTOR // The Whisper Net")
	_wire_locked_card(locked_slot_5, "VERDANT_OS // The Canopy Mesh")

	if btn_launch != null:
		btn_launch.pressed.connect(_on_launch_pressed)
	if btn_quit != null:
		btn_quit.pressed.connect(_on_quit_pressed)

	_refresh_audio_button()
	_refresh_ui()


func _process(delta: float) -> void:
	_bg_time += delta
	queue_redraw()


func _draw() -> void:
	var sz: Vector2 = size
	# Deep Technozen terminal backdrop
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.032, 0.048, 0.068, 1.0), true)

	# Subtle radial cyan/emerald bloom behind active dossier
	var glow_center: Vector2 = Vector2(sz.x * 0.30, sz.y * 0.42)
	for i: int in range(5):
		var r: float = (120.0 + float(i) * 95.0) + sin(_bg_time * 0.8 + float(i)) * 12.0
		var a: float = 0.035 - float(i) * 0.005
		draw_circle(glow_center, r, Color(0.12, 0.88, 0.84, maxf(0.005, a)))

	# Subtle animated Y2K orthogonal grid
	var grid_step: float = 48.0
	var drift_y: float = fmod(_bg_time * 10.0, grid_step)
	var grid_col: Color = Color(0.14, 0.42, 0.50, 0.12)
	var x: float = 0.0
	while x <= sz.x:
		draw_line(Vector2(x, 0.0), Vector2(x, sz.y), grid_col, 1.0)
		x += grid_step
	var y: float = drift_y - grid_step
	while y <= sz.y:
		draw_line(Vector2(0.0, y), Vector2(sz.x, y), grid_col, 1.0)
		y += grid_step

	# Drifting translucent scanline bar
	var scan_y: float = fmod(_bg_time * 42.0, sz.y + 120.0) - 60.0
	draw_rect(Rect2(0.0, scan_y, sz.x, 36.0), Color(0.20, 0.92, 0.88, 0.03), true)
	draw_line(Vector2(0.0, scan_y + 18.0), Vector2(sz.x, scan_y + 18.0), Color(0.24, 0.96, 0.92, 0.09), 1.0)

	# Corner Y2K framing brackets
	var m: float = 14.0
	var b: float = 22.0
	var frame_col: Color = Color(0.22, 0.88, 0.92, 0.45)
	draw_line(Vector2(m, m), Vector2(m + b, m), frame_col, 2.0)
	draw_line(Vector2(m, m), Vector2(m, m + b), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, m), Vector2(sz.x - m - b, m), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, m), Vector2(sz.x - m, m + b), frame_col, 2.0)
	draw_line(Vector2(m, sz.y - m), Vector2(m + b, sz.y - m), frame_col, 2.0)
	draw_line(Vector2(m, sz.y - m), Vector2(m, sz.y - m - b), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, sz.y - m), Vector2(sz.x - m - b, sz.y - m), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, sz.y - m), Vector2(sz.x - m, sz.y - m - b), frame_col, 2.0)


func _wire_locked_card(btn: Button, dossier_name: String) -> void:
	if btn == null:
		return
	btn.pressed.connect(func() -> void:
		AudioManager.play_error()
		if dossier_notice_label != null:
			dossier_notice_label.text = "%s — LOCKED (Post-Vertical Slice AI Lord)" % dossier_name
			dossier_notice_label.modulate = Color(1.0, 0.72, 0.34, 1.0)
	)


func _on_map_selected(index: int) -> void:
	AudioManager.play_ui_click()
	_selected_map_path = GameConfig.MAP_SANDBOX_TESTBED if index == 1 else GameConfig.MAP_SKIRMISH_01
	_refresh_ui()


func _on_mute_changed(_muted: bool) -> void:
	_refresh_audio_button()


func _refresh_audio_button() -> void:
	if btn_audio_mute == null:
		return
	if AudioManager.is_muted:
		btn_audio_mute.text = "SFX: MUTED"
		btn_audio_mute.modulate = Color(1.0, 0.56, 0.42, 0.92)
	else:
		btn_audio_mute.text = "SFX: ON"
		btn_audio_mute.modulate = Color(0.45, 0.98, 0.90, 1.0)


func _refresh_ui() -> void:
	if btn_ai_standard != null:
		btn_ai_standard.modulate = Color(0.42, 1.0, 0.88, 1.0) if _aggro_ai_enabled else Color(0.66, 0.74, 0.80, 0.78)
	if btn_ai_passive != null:
		btn_ai_passive.modulate = Color(1.0, 0.78, 0.34, 1.0) if not _aggro_ai_enabled else Color(0.66, 0.74, 0.80, 0.78)

	var is_fast: bool = (_resource_preset == GameConfig.PRESET_FAST_TECH)
	if btn_res_standard != null:
		btn_res_standard.modulate = Color(0.42, 1.0, 0.88, 1.0) if not is_fast else Color(0.66, 0.74, 0.80, 0.78)
	if btn_res_fast != null:
		btn_res_fast.modulate = Color(0.36, 0.92, 1.0, 1.0) if is_fast else Color(0.66, 0.74, 0.80, 0.78)

	if summary_label != null:
		var map_name: String = "Sandbox Testbed" if _selected_map_path == GameConfig.MAP_SANDBOX_TESTBED else "Skirmish Arena 01 (1v1)"
		var ai_str: String = "Standard Skirmish AI (Aggro ON)" if _aggro_ai_enabled else "Passive / Sandbox AI (Aggro OFF)"
		var res_str: String = "1000 B / 500 S / 200 C" if is_fast else "200 B / 50 S / 0 C"
		summary_label.text = "FACTION: GENESIS_V2 (The Vat-Born)\nMAP: %s\nOPPONENT: %s\nRESOURCES: %s" % [map_name, ai_str, res_str]


func _on_launch_pressed() -> void:
	AudioManager.play_sfx(&"build_complete", -3.0, 0.0)
	GameConfig.set_match_config(_selected_map_path, _aggro_ai_enabled, _resource_preset, &"genesis_v2")
	get_tree().change_scene_to_file(_selected_map_path)


func _on_quit_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().quit()
