class_name SettingsMenu
extends CanvasLayer

signal closed

@onready var tab_btn_controls: Button = %TabBtnControls
@onready var tab_btn_camera: Button = %TabBtnCamera
@onready var tab_btn_gameplay: Button = %TabBtnGameplay
@onready var tab_btn_audio: Button = %TabBtnAudio
@onready var tab_btn_display: Button = %TabBtnDisplay

@onready var panel_controls: Control = %PanelControls
@onready var panel_camera: Control = %PanelCamera
@onready var panel_gameplay: Control = %PanelGameplay
@onready var panel_audio: Control = %PanelAudio
@onready var panel_display: Control = %PanelDisplay

@onready var keybind_list: VBoxContainer = %KeybindList
@onready var capture_banner: PanelContainer = %CaptureBanner
@onready var capture_label: Label = %CaptureLabel

@onready var chk_edge_pan: CheckButton = %ChkEdgePan
@onready var chk_confine_cursor: CheckButton = %ChkConfineCursor
@onready var sld_edge_speed: HSlider = %SldEdgeSpeed
@onready var val_edge_speed: Label = %ValEdgeSpeed
@onready var sld_edge_margin: HSlider = %SldEdgeMargin
@onready var val_edge_margin: Label = %ValEdgeMargin
@onready var sld_kb_speed: HSlider = %SldKbSpeed
@onready var val_kb_speed: Label = %ValKbSpeed
@onready var sld_zoom_speed: HSlider = %SldZoomSpeed
@onready var val_zoom_speed: Label = %ValZoomSpeed
@onready var chk_invert_zoom: CheckButton = %ChkInvertZoom
@onready var chk_zoom_to_cursor: CheckButton = %ChkZoomToCursor
@onready var sld_mid_drag_speed: HSlider = %SldMidDragSpeed
@onready var val_mid_drag_speed: Label = %ValMidDragSpeed

@onready var opt_health_bar_mode: OptionButton = %OptHealthBarMode
@onready var opt_attack_range_mode: OptionButton = %OptAttackRangeMode
@onready var opt_attack_move_mode: OptionButton = %OptAttackMoveMode
@onready var chk_smart_box_select: CheckButton = %ChkSmartBoxSelect
@onready var chk_alert_toasts: CheckButton = %ChkAlertToasts
@onready var chk_camera_shake: CheckButton = %ChkCameraShake
@onready var chk_battle_scars: CheckButton = %ChkBattleScars
@onready var chk_build_grid_snap: CheckButton = %ChkBuildGridSnap
@onready var chk_combat_hit_feedback: CheckButton = %ChkCombatHitFeedback
@onready var chk_ai_transmissions: CheckButton = %ChkAITransmissions

@onready var sld_master_vol: HSlider = %SldMasterVol
@onready var val_master_vol: Label = %ValMasterVol
@onready var sld_sfx_vol: HSlider = %SldSfxVol
@onready var val_sfx_vol: Label = %ValSfxVol
@onready var sld_ui_vol: HSlider = %SldUiVol
@onready var val_ui_vol: Label = %ValUiVol
@onready var sld_ambience_vol: HSlider = %SldAmbienceVol
@onready var val_ambience_vol: Label = %ValAmbienceVol
@onready var chk_mute_all: CheckButton = %ChkMuteAll
@onready var chk_mute_unfocused: CheckButton = %ChkMuteUnfocused
@onready var btn_test_audio: Button = %BtnTestAudio

@onready var opt_window_mode: OptionButton = %OptWindowMode
@onready var opt_resolution: OptionButton = %OptResolution
@onready var chk_vsync: CheckButton = %ChkVsync
@onready var opt_fps_cap: OptionButton = %OptFpsCap
@onready var chk_fps_counter: CheckButton = %ChkFpsCounter

@onready var btn_reset_tab: Button = %BtnResetTab
@onready var btn_reset_all: Button = %BtnResetAll
@onready var btn_close: Button = %BtnClose

var _active_tab: StringName = &"controls"
var _capturing_action: StringName = &""
var _capturing_label: String = ""
var _keybind_buttons: Dictionary = {}
var _suppress_callbacks: bool = false
var _notice_timer: float = 0.0
var _last_slider_preview_ms: int = -9999
const SLIDER_PREVIEW_COOLDOWN_MS: int = 220


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("settings_menu")
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()

	tab_btn_controls.pressed.connect(func() -> void: _select_tab(&"controls"))
	tab_btn_camera.pressed.connect(func() -> void: _select_tab(&"camera"))
	tab_btn_gameplay.pressed.connect(func() -> void: _select_tab(&"gameplay"))
	tab_btn_audio.pressed.connect(func() -> void: _select_tab(&"audio"))
	tab_btn_display.pressed.connect(func() -> void: _select_tab(&"display"))

	_wire_camera_controls()
	_wire_gameplay_controls()
	_wire_audio_controls()
	_wire_display_controls()
	_build_keybind_rows()

	btn_reset_tab.pressed.connect(_on_reset_tab_pressed)
	btn_reset_all.pressed.connect(_on_reset_all_pressed)
	btn_close.pressed.connect(_close_menu)

	if capture_banner != null:
		capture_banner.visible = false

	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_external_settings_changed):
		SettingsManager.settings_changed.connect(_on_external_settings_changed)

	_sync_all_from_manager()
	_select_tab(&"controls", false)


func _exit_tree() -> void:
	if SettingsManager != null:
		SettingsManager.call_deferred("refresh_mouse_mode")


func _process(delta: float) -> void:
	if _notice_timer > 0.0 and _capturing_action == &"":
		_notice_timer = maxf(0.0, _notice_timer - delta)
		if _notice_timer <= 0.0 and capture_banner != null:
			capture_banner.visible = false


func is_capturing_key() -> bool:
	return _capturing_action != &""


func _on_external_settings_changed(category: StringName) -> void:
	if category == &"display" or category == &"audio" or category == &"camera" or category == &"gameplay" or category == &"all":
		_sync_all_from_manager()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _capturing_action != &"":
		if event is InputEventKey:
			var key_ev: InputEventKey = event
			if not key_ev.pressed or key_ev.echo:
				return
			get_viewport().set_input_as_handled()
			if key_ev.keycode == KEY_ESCAPE:
				_cancel_capture()
				return
			if key_ev.keycode == KEY_DELETE:
				var cleared_lbl: String = _capturing_label
				SettingsManager.clear_action_bind(_capturing_action)
				AudioManager.play_ui_click()
				_cancel_capture()
				_show_controls_notice("Unbound '%s'" % cleared_lbl)
				return
			if key_ev.keycode == KEY_CTRL or key_ev.keycode == KEY_SHIFT or key_ev.keycode == KEY_ALT or key_ev.keycode == KEY_META:
				return
			var chosen: int = int(key_ev.keycode if key_ev.keycode != KEY_NONE else key_ev.physical_keycode)
			if SettingsManager.is_key_reserved_for_editor(chosen):
				AudioManager.play_error()
				if capture_label != null:
					capture_label.text = "F5–F8 are reserved for Godot Editor shortcuts. Press another key or Mouse 3/4/5 for '%s' (Esc to cancel)..." % _capturing_label
				return
			var target_act: StringName = _capturing_action
			var target_lbl: String = _capturing_label
			var reassigned: Array[StringName] = SettingsManager.set_action_keybind(target_act, chosen as Key, true)
			AudioManager.play_ui_click()
			_cancel_capture()
			_show_reassignment_notice(SettingsManager.format_keycode(chosen), target_lbl, reassigned)
			return

		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if not mb.pressed:
				return
			get_viewport().set_input_as_handled()
			if SettingsManager.is_mouse_button_allowed(int(mb.button_index)):
				var target_act_m: StringName = _capturing_action
				var target_lbl_m: String = _capturing_label
				var reassigned_m: Array[StringName] = SettingsManager.set_action_mouse_bind(target_act_m, mb.button_index, true)
				AudioManager.play_ui_click()
				_cancel_capture()
				_show_reassignment_notice(SettingsManager.format_mouse_button(int(mb.button_index)), target_lbl_m, reassigned_m)
				return
			# Explicitly reject LMB, RMB, and Scroll Wheel so core RTS selection/orders can never be overwritten.
			AudioManager.play_error()
			if capture_label != null:
				capture_label.text = "Left/Right Click and Scroll Wheel are reserved. Press a key or Mouse 3/4/5 for '%s' (Esc to cancel)..." % _capturing_label
			return
		return

	if event is InputEventKey:
		var esc_ev: InputEventKey = event
		if esc_ev.pressed and not esc_ev.echo and esc_ev.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close_menu()


func _select_tab(tab_id: StringName, play_sound: bool = true) -> void:
	if play_sound:
		AudioManager.play_ui_click()
	_cancel_capture()
	_active_tab = tab_id
	panel_controls.visible = (tab_id == &"controls")
	panel_camera.visible = (tab_id == &"camera")
	panel_gameplay.visible = (tab_id == &"gameplay")
	panel_audio.visible = (tab_id == &"audio")
	panel_display.visible = (tab_id == &"display")

	var active_col: Color = Color(0.38, 1.0, 0.90, 1.0)
	var idle_col: Color = Color(0.68, 0.76, 0.82, 0.82)
	tab_btn_controls.modulate = active_col if tab_id == &"controls" else idle_col
	tab_btn_camera.modulate = active_col if tab_id == &"camera" else idle_col
	tab_btn_gameplay.modulate = active_col if tab_id == &"gameplay" else idle_col
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
		row.add_theme_constant_override("separation", 8)

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
		bind_btn.custom_minimum_size = Vector2(132.0, 28.0)
		bind_btn.focus_mode = Control.FOCUS_NONE
		bind_btn.add_theme_font_size_override("font_size", 12)
		var captured_act: StringName = act
		var captured_disp: String = disp_label
		bind_btn.pressed.connect(func() -> void:
			_begin_capture(captured_act, captured_disp)
		)
		row.add_child(bind_btn)

		var clear_btn: Button = Button.new()
		clear_btn.text = "×"
		clear_btn.tooltip_text = "Unbind shortcut"
		clear_btn.custom_minimum_size = Vector2(30.0, 28.0)
		clear_btn.focus_mode = Control.FOCUS_NONE
		clear_btn.add_theme_font_size_override("font_size", 13)
		clear_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_cancel_capture()
			SettingsManager.clear_action_bind(captured_act)
			_refresh_keybind_buttons()
			_show_controls_notice("Unbound '%s'" % captured_disp)
		)
		row.add_child(clear_btn)

		var reset_btn: Button = Button.new()
		reset_btn.text = "Default"
		reset_btn.custom_minimum_size = Vector2(64.0, 28.0)
		reset_btn.focus_mode = Control.FOCUS_NONE
		reset_btn.add_theme_font_size_override("font_size", 11)
		reset_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_cancel_capture()
			var reassigned_r: Array[StringName] = SettingsManager.reset_action_to_default(captured_act)
			_refresh_keybind_buttons()
			_show_reassignment_notice(SettingsManager.get_action_display_label(captured_act), captured_disp, reassigned_r)
		)
		row.add_child(reset_btn)

		keybind_list.add_child(row)
		_keybind_buttons[act] = {
			"button": bind_btn,
			"clear": clear_btn,
			"conflict": conflict_lbl,
		}


func _begin_capture(action_name: StringName, disp_label: String) -> void:
	AudioManager.play_ui_click()
	_notice_timer = 0.0
	_capturing_action = action_name
	_capturing_label = disp_label
	if capture_banner != null:
		capture_banner.visible = true
	if capture_label != null:
		capture_label.text = "Press any key or Mouse 3/4/5 for '%s'...  (Del to unbind • Esc to cancel)" % disp_label
	_refresh_keybind_buttons()


func _cancel_capture() -> void:
	_capturing_action = &""
	_capturing_label = ""
	if capture_banner != null and _notice_timer <= 0.0:
		capture_banner.visible = false
	_refresh_keybind_buttons()


func _show_controls_notice(message: String) -> void:
	if capture_banner == null or capture_label == null:
		return
	capture_label.text = message
	capture_banner.visible = true
	_notice_timer = 3.2


func _show_reassignment_notice(bind_text: String, target_label: String, reassigned: Array[StringName]) -> void:
	if reassigned.is_empty():
		return
	var names: PackedStringArray = PackedStringArray()
	for other_act: StringName in reassigned:
		names.append(SettingsManager.get_action_label(other_act))
	_show_controls_notice("Reassigned [%s] from %s to %s" % [bind_text, ", ".join(names), target_label])


func _refresh_keybind_buttons() -> void:
	for entry: Dictionary in SettingsManager.KEYBIND_DEFS:
		var act: StringName = entry["action"]
		if not _keybind_buttons.has(act):
			continue
		var pack: Dictionary = _keybind_buttons[act]
		var btn: Button = pack["button"] as Button
		var clear_btn: Button = pack["clear"] as Button
		var conflict_lbl: Label = pack["conflict"] as Label
		var binding: String = SettingsManager.get_action_binding(act)
		var conflicts: Array[StringName] = SettingsManager.find_conflicting_actions(act, binding)

		if _capturing_action == act:
			btn.text = "[ PRESS INPUT... ]"
			btn.modulate = Color(1.0, 0.86, 0.30, 1.0)
		else:
			btn.text = "[ %s ]" % SettingsManager.format_binding(binding, false)
			if binding == "none":
				btn.modulate = Color(0.56, 0.64, 0.72, 0.82)
			elif not conflicts.is_empty():
				btn.modulate = Color(1.0, 0.44, 0.32, 1.0)
			else:
				btn.modulate = Color(0.72, 0.96, 1.0, 1.0)

		if clear_btn != null:
			clear_btn.disabled = (binding == "none")
		if conflict_lbl != null:
			conflict_lbl.text = "CONFLICT" if not conflicts.is_empty() else ""


func _wire_camera_controls() -> void:
	chk_edge_pan.toggled.connect(func(_on: bool) -> void: _push_camera_settings())
	chk_confine_cursor.toggled.connect(func(_on: bool) -> void: _push_camera_settings())
	sld_edge_speed.value_changed.connect(func(_v: float) -> void: _push_camera_settings())
	sld_edge_margin.value_changed.connect(func(_v: float) -> void: _push_camera_settings())
	sld_kb_speed.value_changed.connect(func(_v: float) -> void: _push_camera_settings())
	sld_zoom_speed.value_changed.connect(func(_v: float) -> void: _push_camera_settings())
	chk_invert_zoom.toggled.connect(func(_on: bool) -> void: _push_camera_settings())
	chk_zoom_to_cursor.toggled.connect(func(_on: bool) -> void: _push_camera_settings())
	sld_mid_drag_speed.value_changed.connect(func(_v: float) -> void: _push_camera_settings())


func _push_camera_settings() -> void:
	if _suppress_callbacks:
		return
	SettingsManager.set_camera_settings(
		chk_edge_pan.button_pressed,
		sld_edge_speed.value,
		sld_edge_margin.value,
		sld_kb_speed.value,
		sld_zoom_speed.value,
		chk_confine_cursor.button_pressed,
		chk_invert_zoom.button_pressed,
		sld_mid_drag_speed.value,
		chk_zoom_to_cursor.button_pressed
	)
	_refresh_camera_labels()


func _refresh_camera_labels() -> void:
	val_edge_speed.text = "%d px/s" % int(round(sld_edge_speed.value))
	val_edge_margin.text = "%d px" % int(round(sld_edge_margin.value))
	val_kb_speed.text = "%d px/s" % int(round(sld_kb_speed.value))
	val_zoom_speed.text = "%.2f" % sld_zoom_speed.value
	val_mid_drag_speed.text = "%.2fx" % sld_mid_drag_speed.value


func _wire_gameplay_controls() -> void:
	opt_health_bar_mode.clear()
	opt_health_bar_mode.add_item("Damaged / Selected (Default)", 0)
	opt_health_bar_mode.add_item("Always On", 1)
	opt_health_bar_mode.add_item("Selected Only", 2)
	opt_health_bar_mode.item_selected.connect(func(_idx: int) -> void: _push_gameplay_settings())

	opt_attack_range_mode.clear()
	opt_attack_range_mode.add_item("Always Show", 0)
	opt_attack_range_mode.add_item("Show While Targeting (Default)", 1)
	opt_attack_range_mode.add_item("Don't Show", 2)
	opt_attack_range_mode.item_selected.connect(func(_idx: int) -> void: _push_gameplay_settings())

	opt_attack_move_mode.clear()
	opt_attack_move_mode.add_item("Quick-Cast (Instant at Cursor)", int(SettingsManager.AttackMoveMode.QUICK_CAST))
	opt_attack_move_mode.add_item("Click-to-Confirm (Target Cursor)", int(SettingsManager.AttackMoveMode.CLICK_TO_CONFIRM))
	opt_attack_move_mode.item_selected.connect(func(_idx: int) -> void: _push_gameplay_settings())

	chk_smart_box_select.toggled.connect(func(_on: bool) -> void: _push_gameplay_settings())
	chk_alert_toasts.toggled.connect(func(_on: bool) -> void: _push_gameplay_settings())
	chk_camera_shake.toggled.connect(func(_on: bool) -> void: _push_gameplay_settings())
	chk_battle_scars.toggled.connect(func(_on: bool) -> void: _push_gameplay_settings())
	chk_build_grid_snap.toggled.connect(func(_on: bool) -> void: _push_gameplay_settings())
	if chk_combat_hit_feedback != null:
		chk_combat_hit_feedback.toggled.connect(func(_on: bool) -> void: _push_gameplay_settings())
	if chk_ai_transmissions != null:
		chk_ai_transmissions.toggled.connect(func(_on: bool) -> void: _push_gameplay_settings())


func _push_gameplay_settings() -> void:
	if _suppress_callbacks:
		return
	var hb_mode: int = clampi(opt_health_bar_mode.selected, 0, 2)
	var ar_mode: int = clampi(opt_attack_range_mode.selected, 0, 2)
	var am_mode: int = clampi(opt_attack_move_mode.selected, 0, 1)
	SettingsManager.set_gameplay_settings(
		hb_mode,
		chk_alert_toasts.button_pressed,
		chk_camera_shake.button_pressed,
		ar_mode,
		am_mode,
		chk_smart_box_select.button_pressed,
		chk_battle_scars.button_pressed,
		chk_build_grid_snap.button_pressed,
		chk_combat_hit_feedback.button_pressed if chk_combat_hit_feedback != null else true,
		chk_ai_transmissions.button_pressed if chk_ai_transmissions != null else true
	)
	AudioManager.play_ui_click()


func _wire_audio_controls() -> void:
	sld_master_vol.value_changed.connect(func(_v: float) -> void: _push_audio_settings(&"master"))
	sld_sfx_vol.value_changed.connect(func(_v: float) -> void: _push_audio_settings(&"sfx"))
	sld_ui_vol.value_changed.connect(func(_v: float) -> void: _push_audio_settings(&"ui"))
	sld_ambience_vol.value_changed.connect(func(_v: float) -> void: _push_audio_settings(&"ambience"))
	chk_mute_all.toggled.connect(func(_on: bool) -> void: _push_audio_settings(&""))
	chk_mute_unfocused.toggled.connect(func(_on: bool) -> void: _push_audio_settings(&""))
	btn_test_audio.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"build_complete", -2.0, 0.0)
	)


func _push_audio_settings(preview_channel: StringName = &"") -> void:
	if _suppress_callbacks:
		return
	SettingsManager.set_audio_settings(
		sld_master_vol.value / 100.0,
		sld_sfx_vol.value / 100.0,
		sld_ui_vol.value / 100.0,
		chk_mute_all.button_pressed,
		chk_mute_unfocused.button_pressed,
		sld_ambience_vol.value / 100.0
	)
	_refresh_audio_labels()
	if preview_channel == &"master" or preview_channel == &"sfx" or preview_channel == &"ui":
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_slider_preview_ms >= SLIDER_PREVIEW_COOLDOWN_MS:
			_last_slider_preview_ms = now_ms
			if AudioManager != null and AudioManager.has_method("play_slider_preview"):
				AudioManager.call("play_slider_preview", preview_channel)


func _refresh_audio_labels() -> void:
	val_master_vol.text = "%d%%" % int(round(sld_master_vol.value))
	val_sfx_vol.text = "%d%%" % int(round(sld_sfx_vol.value))
	val_ui_vol.text = "%d%%" % int(round(sld_ui_vol.value))
	val_ambience_vol.text = "%d%%" % int(round(sld_ambience_vol.value))


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

	chk_vsync.toggled.connect(func(_on: bool) -> void: _push_display_settings())

	opt_fps_cap.clear()
	for i: int in range(SettingsManager.FPS_CAP_PRESETS.size()):
		var cap_val: int = int(SettingsManager.FPS_CAP_PRESETS[i])
		opt_fps_cap.add_item("Unlimited" if cap_val <= 0 else ("%d FPS" % cap_val), i)
	opt_fps_cap.item_selected.connect(func(_idx: int) -> void: _push_display_settings())

	chk_fps_counter.toggled.connect(func(_on: bool) -> void: _push_display_settings())


func _push_display_settings() -> void:
	if _suppress_callbacks:
		return
	var mode_idx: int = maxi(0, opt_window_mode.selected)
	var res_idx: int = clampi(opt_resolution.selected, 0, SettingsManager.RESOLUTION_PRESETS.size() - 1)
	var chosen_res: Vector2i = SettingsManager.RESOLUTION_PRESETS[res_idx]
	var fps_idx: int = clampi(opt_fps_cap.selected, 0, SettingsManager.FPS_CAP_PRESETS.size() - 1)
	var chosen_fps: int = int(SettingsManager.FPS_CAP_PRESETS[fps_idx])
	SettingsManager.set_display_settings(
		mode_idx,
		chosen_res,
		chk_vsync.button_pressed,
		chosen_fps,
		chk_fps_counter.button_pressed
	)
	opt_resolution.disabled = (mode_idx != 0)
	AudioManager.play_ui_click()


func _sync_all_from_manager() -> void:
	_suppress_callbacks = true

	chk_edge_pan.button_pressed = SettingsManager.edge_pan_enabled
	chk_confine_cursor.button_pressed = SettingsManager.confine_cursor
	sld_edge_speed.value = SettingsManager.edge_pan_speed
	sld_edge_margin.value = SettingsManager.edge_pan_margin
	sld_kb_speed.value = SettingsManager.keyboard_pan_speed
	sld_zoom_speed.value = SettingsManager.zoom_speed
	chk_invert_zoom.button_pressed = SettingsManager.invert_zoom
	chk_zoom_to_cursor.button_pressed = SettingsManager.zoom_to_cursor
	sld_mid_drag_speed.value = SettingsManager.middle_drag_speed
	_refresh_camera_labels()

	opt_health_bar_mode.select(clampi(SettingsManager.health_bar_mode, 0, 2))
	opt_attack_range_mode.select(clampi(SettingsManager.attack_range_mode, 0, 2))
	opt_attack_move_mode.select(clampi(SettingsManager.attack_move_mode, 0, 1))
	chk_smart_box_select.button_pressed = SettingsManager.smart_box_select_enabled
	chk_alert_toasts.button_pressed = SettingsManager.show_alert_toasts
	chk_camera_shake.button_pressed = SettingsManager.camera_shake_enabled
	chk_battle_scars.button_pressed = SettingsManager.battle_scars_enabled
	chk_build_grid_snap.button_pressed = SettingsManager.build_grid_snap_enabled
	if chk_combat_hit_feedback != null:
		chk_combat_hit_feedback.button_pressed = SettingsManager.show_combat_hit_feedback
	if chk_ai_transmissions != null:
		chk_ai_transmissions.button_pressed = SettingsManager.show_ai_transmissions

	sld_master_vol.value = SettingsManager.master_volume * 100.0
	sld_sfx_vol.value = SettingsManager.sfx_volume * 100.0
	sld_ui_vol.value = SettingsManager.ui_volume * 100.0
	sld_ambience_vol.value = SettingsManager.ambience_volume * 100.0
	chk_mute_all.button_pressed = SettingsManager.muted
	chk_mute_unfocused.button_pressed = SettingsManager.mute_when_unfocused
	_refresh_audio_labels()

	opt_window_mode.select(clampi(SettingsManager.window_mode, 0, 2))
	var matched_res: int = 0
	for i: int in range(SettingsManager.RESOLUTION_PRESETS.size()):
		if SettingsManager.RESOLUTION_PRESETS[i] == SettingsManager.window_resolution:
			matched_res = i
			break
	opt_resolution.select(matched_res)
	opt_resolution.disabled = (SettingsManager.window_mode != 0)

	chk_vsync.button_pressed = SettingsManager.vsync_enabled
	var matched_fps: int = 0
	for i: int in range(SettingsManager.FPS_CAP_PRESETS.size()):
		if int(SettingsManager.FPS_CAP_PRESETS[i]) == SettingsManager.fps_cap:
			matched_fps = i
			break
	opt_fps_cap.select(matched_fps)
	chk_fps_counter.button_pressed = SettingsManager.show_fps_counter

	_refresh_keybind_buttons()
	_suppress_callbacks = false


func _on_reset_tab_pressed() -> void:
	AudioManager.play_ui_click()
	_notice_timer = 0.0
	_cancel_capture()
	SettingsManager.reset_category(_active_tab)
	_sync_all_from_manager()


func _on_reset_all_pressed() -> void:
	AudioManager.play_ui_click()
	_notice_timer = 0.0
	_cancel_capture()
	SettingsManager.reset_all_to_defaults()
	_sync_all_from_manager()


func _close_menu() -> void:
	AudioManager.play_ui_click()
	SettingsManager.save_settings()
	closed.emit()
	queue_free()
