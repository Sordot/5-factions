class_name ModeObjectiveBanner
extends CanvasLayer

signal action_button_pressed

const TECHNOZEN_THEME: Theme = preload("res://resources/themes/technozen_theme.tres")

var _root_control: Control = null
var _panel: PanelContainer = null
var _header_left_label: Label = null
var _header_right_label: Label = null
var _action_btn: Button = null
var _subtitle_label: Label = null
var _progress_bg: ColorRect = null
var _progress_fill: ColorRect = null
var _progress_ratio: float = 0.0
var _progress_color: Color = Color(0.24, 0.96, 0.88, 1.0)


func _ready() -> void:
	layer = 3
	add_to_group("mode_objective_banner")
	_build_ui()
	_apply_faction_theme()
	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(_apply_faction_theme):
		TeamManager.teams_reconfigured.connect(_apply_faction_theme)


func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "RootControl"
	_root_control.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_root_control.offset_left = -218.0
	_root_control.offset_top = 64.0
	_root_control.offset_right = 218.0
	_root_control.offset_bottom = 122.0
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.theme = TECHNOZEN_THEME
	add_child(_root_control)

	_panel = PanelContainer.new()
	_panel.name = "BannerPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_to_group("blocks_edge_pan")
	_root_control.add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_panel.add_child(vbox)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)

	_header_left_label = Label.new()
	_header_left_label.text = "MODE OBJECTIVE"
	_header_left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_left_label.add_theme_font_size_override("font_size", 12)
	_header_left_label.add_theme_color_override("font_color", Color(0.32, 0.98, 0.90, 1.0))
	top_row.add_child(_header_left_label)

	_header_right_label = Label.new()
	_header_right_label.text = ""
	_header_right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header_right_label.add_theme_font_size_override("font_size", 12)
	_header_right_label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 0.96))
	top_row.add_child(_header_right_label)

	_action_btn = Button.new()
	_action_btn.visible = false
	_action_btn.focus_mode = Control.FOCUS_NONE
	_action_btn.custom_minimum_size = Vector2(98.0, 20.0)
	_action_btn.add_theme_font_size_override("font_size", 10)
	_action_btn.add_to_group("blocks_edge_pan")
	_action_btn.pressed.connect(func() -> void:
		if AudioManager != null:
			AudioManager.play_ui_click()
		action_button_pressed.emit()
	)
	top_row.add_child(_action_btn)

	_subtitle_label = Label.new()
	_subtitle_label.text = ""
	_subtitle_label.clip_text = true
	_subtitle_label.add_theme_font_size_override("font_size", 10)
	_subtitle_label.add_theme_color_override("font_color", Color(0.80, 0.90, 0.96, 0.92))
	vbox.add_child(_subtitle_label)

	_progress_bg = ColorRect.new()
	_progress_bg.custom_minimum_size = Vector2(0.0, 5.0)
	_progress_bg.color = Color(0.04, 0.08, 0.12, 0.90)
	_progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_progress_bg)

	_progress_fill = ColorRect.new()
	_progress_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_progress_fill.anchor_right = 0.0
	_progress_fill.color = _progress_color
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(_progress_fill)


func _apply_faction_theme(_mode: StringName = &"") -> void:
	if _panel == null:
		return
	var fid: StringName = FactionHudTheme.resolve_local_faction_id()
	_panel.add_theme_stylebox_override("panel", FactionHudTheme.make_panel_style(fid, true))
	FactionHudTheme.attach_frame_overlay(_panel, fid, &"top_bar")
	if _action_btn != null:
		FactionHudTheme.style_utility_button(_action_btn, fid)


func set_banner_visible(flag: bool) -> void:
	if _root_control != null:
		_root_control.visible = flag


func set_header(left_text: String, right_text: String = "", accent: Color = Color(0.32, 0.98, 0.90, 1.0)) -> void:
	if _header_left_label != null:
		_header_left_label.text = left_text
		_header_left_label.add_theme_color_override("font_color", accent)
	if _header_right_label != null:
		_header_right_label.text = right_text
		_header_right_label.visible = not right_text.is_empty()


func set_subtitle(text: String, color: Color = Color(0.80, 0.90, 0.96, 0.92)) -> void:
	if _subtitle_label != null:
		_subtitle_label.text = text
		_subtitle_label.add_theme_color_override("font_color", color)


func set_progress(ratio: float, fill_color: Color = Color(0.24, 0.96, 0.88, 1.0), show_bar: bool = true) -> void:
	_progress_ratio = clampf(ratio, 0.0, 1.0)
	_progress_color = fill_color
	if _progress_bg != null:
		_progress_bg.visible = show_bar
	if _progress_fill != null:
		_progress_fill.anchor_right = _progress_ratio
		_progress_fill.color = _progress_color


func set_action_button(visible_flag: bool, label: String = "", accent: Color = Color(1.0, 0.82, 0.30, 1.0), tooltip: String = "") -> void:
	if _action_btn == null:
		return
	_action_btn.visible = visible_flag
	if visible_flag:
		_action_btn.text = label
		_action_btn.modulate = accent
		_action_btn.tooltip_text = tooltip
