class_name SettingsMenu
extends CanvasLayer

signal closed

@onready var tab_btn_controls: Button = %TabBtnControls
@onready var tab_btn_camera: Button = %TabBtnCamera
@onready var tab_btn_audio: Button = %TabBtnAudio
@onready var tab_btn_display: Button = %TabBtnDisplay

@onready var panel_controls: Control = %PanelControls
@onready var panel_camera: Control = %PanelCamera
@onready var panel_audio: Control = %PanelAudio
@onready var panel_display: Control = %PanelDisplay

@onready var keybind_list: VBoxContainer = %KeybindList
@onready var capture_banner: PanelContainer = %CaptureBanner
@onready var capture_label: Label = %CaptureLabel

@onready var chk_edge_pan: CheckButton = %ChkEdgePan
@onready var sld_edge_speed: HSlider = %SldEdgeSpeed
@onready var val_edge_speed: Label = %ValEdgeSpeed
@onready var sld_edge_margin: HSlider = %SldEdgeMargin
@onready var val_edge_margin: Label = %ValEdgeMargin
@onready var sld_kb_speed: HSlider = %SldKbSpeed
@onready var val_kb_speed: Label = %ValKbSpeed
@onready var sld_zoom_speed: HSlider = %SldZoomSpeed
@onready var val_zoom_speed: Label = %ValZoomSpeed

@onready var sld_master_vol: HSlider = %SldMasterVol
@onready var val_master_vol: Label = %ValMasterVol
@onready var sld_sfx_vol: HSlider = %SldSfxVol
@onready var val_sfx_vol: Label = %ValSfxVol
@onready var sld_ui_vol: HSlider = %SldUiVol
@onready var val_ui_vol: Label = %ValUiVol
@onready var chk_mute_all: CheckButton = %ChkMuteAll
@onready var btn_test_audio: Button = %BtnTestAudio

@onready var opt_window_mode: OptionButton = %OptWindowMode
@onready var opt_resolution: OptionButton = %OptResolution

@onready var btn_reset_tab: Button = %BtnResetTab
@onready var btn_reset_all: Button = %BtnResetAll
@onready var btn_close: Button = %BtnClose

var _active_tab: StringName = &"controls"
var _capturing_action: StringName = &""
var _capturing_label: String = ""
var _keybind_buttons: Dictionary = {}
var _suppress_callbacks: bool = false


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("settings_menu")

	tab_btn_controls.pressed.connect(func() -> void: _select_tab(&"controls"))
	tab_btn_camera.pressed.connect(func() -> void: _select_tab(&"camera"))
	tab_btn_audio.pressed.connect(func() -> void: _select_tab(&"audio"))
	tab_btn_display.pressed.connect(func() -> void: _select_tab(&"display"))

	_wire_camera_controls()
	_wire_audio_controls()
	_wire_display_controls()
	_build_keybind_rows()

	btn_reset_tab.pressed.connect(_on_reset_tab_pressed)
	btn_reset_all.pressed.connect(_on_reset_all_pressed)
	btn_close.pressed.connect(_close_menu)

	if capture_banner != null:
		capture_banner.visible = false

	_sync_all_from_manager()
	_select_tab(&"controls", false)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_ev: InputEventKey = event
		if not key_ev.pressed or key_ev.echo:
			return
		if _capturing_action != &"":
			get_viewport().set_input_as_handled()
			if key_ev.keycode == KEY_ESCAPE:
				_cancel_capture()
				return
			if key_ev.keycode == KEY_CTRL or key_ev.keycode == KEY_SHIFT or key_ev.keycode == KEY_ALT or key_ev.keycode == KEY_META:
				return
			var chosen: int = int(key_ev.keycode if key_ev.keycode != KEY_NONE else key_ev.physical_keycode)
			if SettingsManager.is_key_reserved_for_editor(chosen):
				AudioManager.play_error()
				if capture_label != null:
					capture_label.text = "F5–F8 are reserved for Godot Editor shortcuts. Press another key for '%s' (Esc to cancel)..." % _capturing_label
				return
			SettingsManager.set_action_key(_capturing_action, chosen)
			AudioManager.play_ui_click()
			_cancel_capture()
			_refresh_keybind_buttons()
			return
		if key_ev.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close_menu()
			return


func _select_tab(tab_id: StringName, play_sound: bool = true) -> void:
	if play_sound:
		AudioManager.play_ui_click()
	_cancel_capture()
	_active_tab = tab_id
	panel_controls.visible = (tab_id == &"controls")
	panel_camera.visible = (tab_id == &"camera")
	panel_audio.visible = (tab_id == &"audio")
	panel_display.visible = (tab_id == &"display")

	var active_col: Color = Color(0.38, 1.0, 0.90, 1.0)
	var idle_col: Color = Color(0.68, 0.76, 0.82, 0.82)
	tab_btn_controls.modulate = active_col if tab_id == &"controls" else idle_col
	tab_btn_camera.modulate = active_col if tab_id == &"camera" else idle_col
	tab_btn_audio.modulate = active_col if tab_id == &"audio" else idle_col
	tab_btn_display.modulate = active_col if tab_id == &"display" else idle_col


func _build_keybind_rows() -> void:
	if keybind_list == null:
		return
	for child: Node in keybind_list.get_children():
		child.queue_free()
	_keybind_buttons.clear()

	var current_cat: String = ""
	for entry: Dictionary in SettingsManager.KEYBIND_DEFS:
		var cat: String = String(entry["category"])
		if cat != current_cat:
			current_cat = cat
			var cat_lbl: Label = Label.new()
			cat_lbl.text = cat.to_upper()
			cat_lbl.add_theme_font_size_override("font_size", 11)
			cat_lbl.add_theme_color_override("font_color", Color(0.32, 0.92, 0.88, 0.95))
			keybind_list.add_child(cat_lbl)

		var act: StringName = entry["action"]
		var disp_label: String = String(entry["label"])

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var lbl: Label = Label.new()
		lbl.text = disp_label
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl)

		var conflict_lbl: Label = Label.new()
		conflict_lbl.text = ""
		conflict_lbl.add_theme_font_size_override("font_size", 10)
		conflict_lbl.add_theme_color_override("font_color", Color(1.0, 0.56, 0.28, 1.0))
		row.add_child(conflict_lbl)

		var bind_btn: Button = Button.new()
		bind_btn.custom_minimum_size = Vector2(124.0, 28.0)
		bind_btn.focus_mode = Control.FOCUS_NONE
		bind_btn.add_theme_font_size_override("font_size", 12)
		var captured_act: StringName = act
		var captured_disp: String = disp_label
		bind_btn.pressed.connect(func() -> void:
			_begin_capture(captured_act, captured_disp)
		)
		row.add_child(bind_btn)

		var reset_btn: Button = Button.new()
		reset_btn.text = "Default"
		reset_btn.custom_minimum_size = Vector2(68.0, 28.0)
		reset_btn.focus_mode = Control.FOCUS_NONE
		reset_btn.add_theme_font_size_override("font_size", 11)
		reset_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			SettingsManager.reset_action_to_default(captured_act)
			_refresh_keybind_buttons()
		)
		row.add_child(reset_btn)

		keybind_list.add_child(row)
		_keybind_buttons[act] = {
			"button": bind_btn,
			"conflict": conflict_lbl,
		}


func _begin_capture(action_name: StringName, disp_label: String) -> void:
	AudioManager.play_ui_click()
	_capturing_action = action_name
	_capturing_label = disp_label
	if capture_banner != null:
		capture_banner.visible = true
	if capture_label != null:
		capture_label.text = "Press any key to bind '%s'...  (Esc to cancel • F5–F8 reserved)" % disp_label
	_refresh_keybind_buttons()


func _cancel_capture() -> void:
	_capturing_action = &""
	_capturing_label = ""
	if capture_banner != null:
		capture_banner.visible = false
	_refresh_keybind_buttons()


func _refresh_keybind_buttons() -> void:
	for entry: Dictionary in SettingsManager.KEYBIND_DEFS:
		var act: StringName = entry["action"]
		if not _keybind_buttons.has(act):
			continue
		var pack: Dictionary = _keybind_buttons[act]
		var btn: Button = pack["button"] as Button
		var conflict_lbl: Label = pack["conflict"] as Label
		var code: int = SettingsManager.get_action_keycode(act)
		var conflicts: Array[StringName] = SettingsManager.find_conflicting_actions(act, code)

		if _capturing_action == act:
			btn.text = "[ PRESS KEY... ]"
			btn.modulate = Color(1.0, 0.86, 0.30, 1.0)
		else:
			btn.text = "[ %s ]" % SettingsManager.format_keycode(code)
			if not conflicts.is_empty():
				btn.modulate = Color(1.0, 0.44, 0.32, 1.0)
			else:
				btn.modulate = Color(0.72, 0.96, 1.0, 1.0)

		if conflict_lbl != null:
			conflict_lbl.text = "CONFLICT" if not conflicts.is_empty() else ""


func _wire_camera_controls() -> void:
	chk_edge_pan.toggled.connect(func(_on: bool) -> void: _push_camera_settings())
	sld_edge_speed.value_changed.connect(func(_v: float) -> void: _push_camera_settings())
	sld_edge_margin.value_changed.connect(func(_v: float) -> void: _push_camera_settings())
	sld_kb_speed.value_changed.connect(func(_v: float) -> void: _push_camera_settings())
	sld_zoom_speed.value_changed.connect(func(_v: float) -> void: _push_camera_settings())


func _push_camera_settings() -> void:
	if _suppress_callbacks:
		return
	SettingsManager.set_camera_settings(
		chk_edge_pan.button_pressed,
		sld_edge_speed.value,
		sld_edge_margin.value,
		sld_kb_speed.value,
		sld_zoom_speed.value
	)
	_refresh_camera_labels()


func _refresh_camera_labels() -> void:
	val_edge_speed.text = "%d px/s" % int(round(sld_edge_speed.value))
	val_edge_margin.text = "%d px" % int(round(sld_edge_margin.value))
	val_kb_speed.text = "%d px/s" % int(round(sld_kb_speed.value))
	val_zoom_speed.text = "%.2f" % sld_zoom_speed.value


func _wire_audio_controls() -> void:
	sld_master_vol.value_changed.connect(func(_v: float) -> void: _push_audio_settings())
	sld_sfx_vol.value_changed.connect(func(_v: float) -> void: _push_audio_settings())
	sld_ui_vol.value_changed.connect(func(_v: float) -> void: _push_audio_settings())
	chk_mute_all.toggled.connect(func(_on: bool) -> void: _push_audio_settings())
	btn_test_audio.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"build_complete", -2.0, 0.0)
	)


func _push_audio_settings() -> void:
	if _suppress_callbacks:
		return
	SettingsManager.set_audio_settings(
		sld_master_vol.value / 100.0,
		sld_sfx_vol.value / 100.0,
		sld_ui_vol.value / 100.0,
		chk_mute_all.button_pressed
	)
	_refresh_audio_labels()


func _refresh_audio_labels() -> void:
	val_master_vol.text = "%d%%" % int(round(sld_master_vol.value))
	val_sfx_vol.text = "%d%%" % int(round(sld_sfx_vol.value))
	val_ui_vol.text = "%d%%" % int(round(sld_ui_vol.value))


func _wire_display_controls() -> void:
	opt_window_mode.clear()
	opt_window_mode.add_item("Windowed", 0)
	opt_window_mode.add_item("Borderless Fullscreen", 1)
	opt_window_mode.add_item("Fullscreen", 2)
	opt_window_mode.item_selected.connect(func(_idx: int) -> void: _push_display_settings())

	opt_resolution.clear()
	for i: int in range(SettingsManager.RESOLUTION_PRESETS.size()):
		var res: Vector2i = SettingsManager.RESOLUTION_PRESETS[i]
		opt_resolution.add_item("%d × %d" % [res.x, res.y], i)
	opt_resolution.item_selected.connect(func(_idx: int) -> void: _push_display_settings())


func _push_display_settings() -> void:
	if _suppress_callbacks:
		return
	var mode_idx: int = maxi(0, opt_window_mode.selected)
	var res_idx: int = clampi(opt_resolution.selected, 0, SettingsManager.RESOLUTION_PRESETS.size() - 1)
	var chosen_res: Vector2i = SettingsManager.RESOLUTION_PRESETS[res_idx]
	SettingsManager.set_display_settings(mode_idx, chosen_res)
	opt_resolution.disabled = (mode_idx != 0)
	AudioManager.play_ui_click()


func _sync_all_from_manager() -> void:
	_suppress_callbacks = true

	chk_edge_pan.button_pressed = SettingsManager.edge_pan_enabled
	sld_edge_speed.value = SettingsManager.edge_pan_speed
	sld_edge_margin.value = SettingsManager.edge_pan_margin
	sld_kb_speed.value = SettingsManager.keyboard_pan_speed
	sld_zoom_speed.value = SettingsManager.zoom_speed
	_refresh_camera_labels()

	sld_master_vol.value = SettingsManager.master_volume * 100.0
	sld_sfx_vol.value = SettingsManager.sfx_volume * 100.0
	sld_ui_vol.value = SettingsManager.ui_volume * 100.0
	chk_mute_all.button_pressed = SettingsManager.muted
	_refresh_audio_labels()

	opt_window_mode.select(clampi(SettingsManager.window_mode, 0, 2))
	var matched_res: int = 0
	for i: int in range(SettingsManager.RESOLUTION_PRESETS.size()):
		if SettingsManager.RESOLUTION_PRESETS[i] == SettingsManager.window_resolution:
			matched_res = i
			break
	opt_resolution.select(matched_res)
	opt_resolution.disabled = (SettingsManager.window_mode != 0)

	_refresh_keybind_buttons()
	_suppress_callbacks = false


func _on_reset_tab_pressed() -> void:
	AudioManager.play_ui_click()
	_cancel_capture()
	SettingsManager.reset_category(_active_tab)
	_sync_all_from_manager()


func _on_reset_all_pressed() -> void:
	AudioManager.play_ui_click()
	_cancel_capture()
	SettingsManager.reset_all_to_defaults()
	_sync_all_from_manager()


func _close_menu() -> void:
	AudioManager.play_ui_click()
	SettingsManager.save_settings()
	closed.emit()
	queue_free()
