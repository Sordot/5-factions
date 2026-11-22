class_name RTSCamera
extends Camera2D

@export var pan_speed: float = 550.0
@export var zoom_step: float = 0.12
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var zoom_smoothness: float = 12.0
@export var pan_bounds: Rect2 = Rect2(-960.0, -540.0, 1920.0, 1080.0)

var _target_zoom: float = 1.0
var _is_middle_dragging: bool = false


func _ready() -> void:
	_target_zoom = clampf(zoom.x, min_zoom, max_zoom)
	zoom = Vector2(_target_zoom, _target_zoom)


func _process(delta: float) -> void:
	var pan_input: Vector2 = Input.get_vector(
		"camera_pan_left",
		"camera_pan_right",
		"camera_pan_up",
		"camera_pan_down"
	)
	if pan_input != Vector2.ZERO:
		global_position += pan_input * (pan_speed / zoom.x) * delta
		_clamp_position()

	var next_zoom: float = lerpf(zoom.x, _target_zoom, clampf(zoom_smoothness * delta, 0.0, 1.0))
	zoom = Vector2(next_zoom, next_zoom)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_middle_dragging = mouse_event.pressed
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
	elif event is InputEventMouseMotion and _is_middle_dragging:
		var motion_event: InputEventMouseMotion = event
		global_position -= motion_event.relative / zoom
		_clamp_position()


func _clamp_position() -> void:
	if not pan_bounds.has_area():
		return
	global_position.x = clampf(global_position.x, pan_bounds.position.x, pan_bounds.end.x)
	global_position.y = clampf(global_position.y, pan_bounds.position.y, pan_bounds.end.y)
