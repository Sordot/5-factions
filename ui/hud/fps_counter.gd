extends CanvasLayer

const UPDATE_INTERVAL: float = 0.25

var _fps_label: Label = null
var _elapsed: float = 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	_refresh_fps()


func _build_overlay() -> void:
	var root: Control = Control.new()
	root.name = "RootControl"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "FPSPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -88.0
	panel.offset_top = -30.0
	panel.offset_right = -10.0
	panel.offset_bottom = -8.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.09, 0.80)
	style.border_color = Color(0.22, 0.78, 0.86, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	_fps_label = Label.new()
	_fps_label.name = "FPSLabel"
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.add_theme_font_size_override("font_size", 11)
	_fps_label.add_theme_color_override("font_color", Color(0.32, 0.96, 0.88, 0.96))
	_fps_label.text = "-- FPS"
	panel.add_child(_fps_label)


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL:
		return
	_elapsed = 0.0
	_refresh_fps()


func _refresh_fps() -> void:
	if _fps_label == null:
		return
	var fps: int = int(round(Engine.get_frames_per_second()))
	_fps_label.text = "%d FPS" % fps
	if fps >= 55:
		_fps_label.add_theme_color_override("font_color", Color(0.32, 0.96, 0.88, 0.96))
	elif fps >= 30:
		_fps_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.30, 0.96))
	else:
		_fps_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.30, 0.98))
