class_name MatchBootVeil
extends Control

const TOTAL_DURATION: float = 1.20
const VEIL_FADE_DURATION: float = 1.10
const INPUT_UNLOCK_TIME: float = 0.25

var banner_text: String = "// NEURAL LINK ONLINE"
var accent_color: Color = Color(0.204, 0.827, 0.600, 1.0)
var host_layer: CanvasLayer = null
var _elapsed: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= INPUT_UNLOCK_TIME and mouse_filter != Control.MOUSE_FILTER_IGNORE:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _elapsed >= TOTAL_DURATION:
		if host_layer != null and is_instance_valid(host_layer):
			host_layer.queue_free()
		else:
			queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var sz: Vector2 = size
	if sz.x <= 2.0 or sz.y <= 2.0:
		return
	var veil_t: float = clampf(_elapsed / VEIL_FADE_DURATION, 0.0, 1.0)
	var veil_alpha: float = 0.85 * pow(1.0 - veil_t, 2.2)
	if veil_alpha > 0.005:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.06, 0.10, veil_alpha), true)

	# Crisp horizontal Technozen scanline sweep
	var scan_t: float = clampf(_elapsed / 0.88, 0.0, 1.0)
	if scan_t < 1.0:
		var scan_y: float = lerpf(-12.0, sz.y + 12.0, 1.0 - pow(1.0 - scan_t, 2.0))
		var scan_a: float = sin(scan_t * PI) * 0.68
		draw_rect(Rect2(0.0, scan_y - 10.0, sz.x, 12.0), Color(accent_color.r, accent_color.g, accent_color.b, scan_a * 0.14), true)
		draw_line(Vector2(0.0, scan_y), Vector2(sz.x, scan_y), Color(accent_color.r, accent_color.g, accent_color.b, scan_a), 1.6, true)

	# Slim centered terminal banner fading smoothly out over 1.2s
	var banner_fade: float = 1.0
	if _elapsed < 0.12:
		banner_fade = _elapsed / 0.12
	elif _elapsed > 0.72:
		banner_fade = clampf(1.0 - (_elapsed - 0.72) / (TOTAL_DURATION - 0.72), 0.0, 1.0)
	if banner_fade > 0.01:
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 14
		var txt_sz: Vector2 = font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pad_x: float = 28.0
		var box_w: float = txt_sz.x + pad_x * 2.0
		var box_h: float = 34.0
		var cx: float = sz.x * 0.5
		var cy: float = sz.y * 0.24
		var rect: Rect2 = Rect2(cx - box_w * 0.5, cy - box_h * 0.5, box_w, box_h)
		draw_rect(rect, Color(0.04, 0.08, 0.13, 0.82 * banner_fade), true)
		draw_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Color(accent_color.r, accent_color.g, accent_color.b, 0.92 * banner_fade), 1.6, true)
		draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Color(accent_color.r, accent_color.g, accent_color.b, 0.72 * banner_fade), 1.2, true)
		draw_string(font, Vector2(cx - txt_sz.x * 0.5, cy + txt_sz.y * 0.34), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.86, 0.98, 1.0, 0.96 * banner_fade))
