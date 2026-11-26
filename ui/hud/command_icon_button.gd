class_name CommandIconButton
extends Button

## Compact 44x44 procedural vector icon tile for the StarCraft-style 4x3 Command Card.
## Zero external textures: delegates glyph drawing to CommandIconGlyphs and resolves faction styling
## via FactionHudTheme while rendering hotkey badges, status pills, cooldown sweeps, and Auto-Cast borders.

const TILE_SIZE: Vector2 = Vector2(44.0, 44.0)

var icon_id: StringName = &""
var icon_category: StringName = &"command"
var hotkey_text: String = ""
var badge_text: String = ""
var badge_color: Color = Color(0.24, 0.96, 0.88, 1.0)
var accent_color: Color = Color(0.24, 0.96, 0.88, 1.0)
var cooldown_remaining: float = 0.0
var cooldown_total: float = 0.0
var is_active_state: bool = false
var is_locked_state: bool = false
var is_unaffordable: bool = false
var is_empty_socket: bool = false
var autocast_active: bool = false

var theme_profile: StringName = &"genesis_v2"
var theme_style: StringName = &"technozen"
var theme_accent: Color = Color(0.20, 0.96, 0.86, 1.0)
var theme_primary: Color = Color(0.90, 0.96, 0.98, 1.0)

var _autocast_time: float = 0.0
var _is_hovered_tile: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = TILE_SIZE
	text = ""
	clip_contents = true
	mouse_entered.connect(func() -> void:
		_is_hovered_tile = true
		queue_redraw()
	)
	mouse_exited.connect(func() -> void:
		_is_hovered_tile = false
		queue_redraw()
	)
	set_process(false)


func setup_tile(
	p_icon_id: StringName,
	p_category: StringName = &"command",
	p_hotkey: String = "",
	p_accent: Color = Color(0.24, 0.96, 0.88, 1.0)
) -> void:
	icon_id = p_icon_id
	icon_category = p_category
	hotkey_text = p_hotkey
	accent_color = p_accent
	is_empty_socket = false
	disabled = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func setup_empty_socket() -> void:
	icon_id = &""
	icon_category = &"empty"
	hotkey_text = ""
	badge_text = ""
	cooldown_remaining = 0.0
	cooldown_total = 0.0
	is_active_state = false
	is_locked_state = false
	is_unaffordable = false
	autocast_active = false
	set_process(false)
	is_empty_socket = true
	disabled = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_autocast_active(enabled: bool) -> void:
	if autocast_active == enabled:
		return
	autocast_active = enabled
	set_process(autocast_active)
	queue_redraw()


func set_tile_state(
	p_badge_text: String = "",
	p_badge_color: Color = Color(0.24, 0.96, 0.88, 1.0),
	p_active: bool = false,
	p_unaffordable: bool = false,
	p_locked: bool = false,
	p_cd_rem: float = 0.0,
	p_cd_tot: float = 0.0
) -> void:
	badge_text = p_badge_text
	badge_color = p_badge_color
	is_active_state = p_active
	is_unaffordable = p_unaffordable
	is_locked_state = p_locked
	cooldown_remaining = maxf(0.0, p_cd_rem)
	cooldown_total = maxf(0.0, p_cd_tot)
	queue_redraw()


func apply_faction_theme(faction_id: StringName, f_accent: Color, f_primary: Color) -> void:
	theme_profile = faction_id
	theme_accent = f_accent
	theme_primary = f_primary
	var pal: Dictionary = FactionHudTheme.get_palette(faction_id)
	theme_style = pal.get("style", &"technozen") as StringName

	var is_brutal: bool = (theme_style == &"brutalist")
	var radius: int = 0 if is_brutal else 4
	var bw: int = 2 if is_brutal else 1

	var normal_sb: StyleBoxFlat = StyleBoxFlat.new()
	normal_sb.set_corner_radius_all(radius)
	normal_sb.set_border_width_all(bw)
	if is_brutal:
		normal_sb.bg_color = Color(0.137, 0.149, 0.169, 0.98) # #23262B
		normal_sb.border_color = Color(0.039, 0.051, 0.071, 1.0) # #0A0D12
	else:
		normal_sb.bg_color = Color(0.045, 0.095, 0.140, 0.94)
		normal_sb.border_color = Color(f_accent.r, f_accent.g, f_accent.b, 0.42)

	var hover_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	if is_brutal:
		hover_sb.bg_color = Color(0.195, 0.212, 0.238, 0.98)
		hover_sb.border_color = Color(f_accent.r, f_accent.g, f_accent.b, 0.98)
	else:
		hover_sb.bg_color = Color(0.075, 0.165, 0.220, 0.96)
		hover_sb.border_color = Color(f_accent.r, f_accent.g, f_accent.b, 0.96)

	var press_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	if is_brutal:
		press_sb.bg_color = Color(0.250, 0.220, 0.165, 0.98)
		press_sb.border_color = Color(0.949, 0.937, 0.914, 1.0)
	else:
		press_sb.bg_color = Color(0.11, 0.24, 0.29, 0.98)
		press_sb.border_color = Color(0.86, 1.0, 0.98, 1.0)

	var disabled_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	if is_brutal:
		disabled_sb.bg_color = Color(0.095, 0.105, 0.120, 0.72)
		disabled_sb.border_color = Color(0.039, 0.051, 0.071, 0.75)
	else:
		disabled_sb.bg_color = Color(0.030, 0.058, 0.088, 0.65)
		disabled_sb.border_color = Color(f_accent.r, f_accent.g, f_accent.b, 0.18)

	add_theme_stylebox_override("normal", normal_sb)
	add_theme_stylebox_override("hover", hover_sb)
	add_theme_stylebox_override("pressed", press_sb)
	add_theme_stylebox_override("disabled", disabled_sb)
	add_theme_stylebox_override("focus", hover_sb)
	queue_redraw()


func _process(delta: float) -> void:
	if not autocast_active or not visible:
		return
	_autocast_time += delta * 1.4
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 8.0 or h < 8.0:
		return
	var is_brutal: bool = (theme_style == &"brutalist")
	var center: Vector2 = Vector2(w * 0.5, h * 0.5)

	if is_empty_socket:
		if is_brutal:
			# Subtle brutalist recessed dot-matrix socket
			for gx: int in range(3):
				for gy: int in range(3):
					var px: float = 12.0 + float(gx) * 10.0
					var py: float = 12.0 + float(gy) * 10.0
					draw_circle(Vector2(px, py), 1.0, Color(0.95, 0.94, 0.91, 0.10))
		else:
			# Subtle Technozen recessed cross-socket
			var c_col: Color = Color(theme_accent.r, theme_accent.g, theme_accent.b, 0.12)
			draw_line(center - Vector2(5.0, 0.0), center + Vector2(5.0, 0.0), c_col, 1.0)
			draw_line(center - Vector2(0.0, 5.0), center + Vector2(0.0, 5.0), c_col, 1.0)
		return

	# Subtle brutalist inner bevel shadow / off-white top-left lip
	if is_brutal:
		draw_rect(Rect2(2.0, 2.0, w - 4.0, h - 4.0), Color(0.04, 0.05, 0.07, 0.36), false, 1.0)
		draw_line(Vector2(3.0, 3.0), Vector2(w - 3.0, 3.0), Color(0.95, 0.94, 0.91, 0.16), 1.0)

	# Active-state highlight fill & inner rim
	if is_active_state:
		var act_col: Color = theme_accent
		draw_rect(Rect2(2.0, 2.0, w - 4.0, h - 4.0), Color(act_col.r, act_col.g, act_col.b, 0.18), true)
		draw_rect(Rect2(2.0, 2.0, w - 4.0, h - 4.0), Color(act_col.r, act_col.g, act_col.b, 0.92), false, 1.8)

	# Compute icon ink/fill colors based on affordability & lock state
	var fg: Color = accent_color
	var hi: Color = Color(0.949, 0.937, 0.914, 0.96) if is_brutal else Color(0.95, 0.98, 1.0, 0.96)
	var dark: Color = Color(0.08, 0.09, 0.11, 0.96) if is_brutal else Color(0.08, 0.14, 0.20, 0.95)
	if is_locked_state:
		fg = Color(0.76, 0.34, 0.36, 0.72)
		hi = Color(0.68, 0.50, 0.52, 0.62)
	elif is_unaffordable:
		fg = fg.lerp(Color(0.42, 0.46, 0.52, 1.0), 0.62)
		fg.a = 0.65
		hi = hi.lerp(Color(0.48, 0.52, 0.56, 1.0), 0.58)
		hi.a = 0.62
	elif disabled and icon_id != &"cmd_move":
		fg.a = 0.48
		hi.a = 0.45

	# Draw center 28x28 vector glyph (shifted slightly down-right by 1px so top-left hotkey never crowds)
	CommandIconGlyphs.draw_icon(self, icon_id, icon_category, center + Vector2(0.0, 1.0), fg, hi, dark)

	# Cooldown dark curtain sweep + numeric countdown
	if cooldown_remaining > 0.01:
		var ratio: float = clampf(cooldown_remaining / maxf(0.1, cooldown_total), 0.0, 1.0) if cooldown_total > 0.01 else 1.0
		var sweep_h: float = (h - 4.0) * ratio
		draw_rect(Rect2(2.0, 2.0 + (h - 4.0 - sweep_h), w - 4.0, sweep_h), Color(0.02, 0.04, 0.07, 0.74), true)
		var cd_txt: String = ("%.1f" % cooldown_remaining) if cooldown_remaining < 10.0 else ("%ds" % int(ceil(cooldown_remaining)))
		var font: Font = ThemeDB.fallback_font
		var f_sz: int = 11
		var t_sz: Vector2 = font.get_string_size(cd_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, f_sz)
		var pos: Vector2 = Vector2(center.x - t_sz.x * 0.5, center.y + t_sz.y * 0.32)
		draw_string(font, pos + Vector2(1.0, 1.0), cd_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f_sz, Color(0.0, 0.0, 0.0, 0.90))
		draw_string(font, pos, cd_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f_sz, Color(1.0, 0.90, 0.52, 0.98))

	# Top-left crisp hotkey corner badge
	if not hotkey_text.is_empty():
		var hk_font: Font = ThemeDB.fallback_font
		var hk_sz: int = 9
		var hk_dim: Vector2 = hk_font.get_string_size(hotkey_text, HORIZONTAL_ALIGNMENT_LEFT, -1, hk_sz)
		var box_w: float = maxf(13.0, hk_dim.x + 5.0)
		var box_h: float = 12.0
		var hk_bg: Color = Color(0.04, 0.05, 0.07, 0.88) if is_brutal else Color(0.02, 0.06, 0.10, 0.84)
		var hk_col: Color = theme_accent if is_brutal else Color(0.68, 0.98, 1.0, 0.98)
		if is_locked_state:
			hk_col = Color(0.82, 0.44, 0.44, 0.80)
		draw_rect(Rect2(2.0, 2.0, box_w, box_h), hk_bg, true)
		draw_string(hk_font, Vector2(4.5, 11.0), hotkey_text, HORIZONTAL_ALIGNMENT_LEFT, -1, hk_sz, hk_col)

	# Bottom-right crisp status pill (x2, ON, DONE, ACT, LOCK)
	if not badge_text.is_empty():
		var b_font: Font = ThemeDB.fallback_font
		var b_sz: int = 8
		var b_dim: Vector2 = b_font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, b_sz)
		var bw_p: float = b_dim.x + 5.0
		var bh_p: float = 11.0
		var bx: float = w - bw_p - 2.0
		var by: float = h - bh_p - 2.0
		draw_rect(Rect2(bx, by, bw_p, bh_p), Color(0.03, 0.05, 0.08, 0.90), true)
		draw_rect(Rect2(bx, by, bw_p, bh_p), Color(badge_color.r, badge_color.g, badge_color.b, 0.72), false, 1.0)
		draw_string(b_font, Vector2(bx + 2.5, by + 8.5), badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, b_sz, badge_color)

	# Animated chasing Auto-Cast perimeter runners
	if autocast_active:
		var rect: Rect2 = Rect2(Vector2(1.5, 1.5), Vector2(w - 3.0, h - 3.0))
		var ac_ring: Color = Color(theme_accent.r, theme_accent.g, theme_accent.b, 0.68) if is_brutal else Color(0.28, 0.96, 1.0, 0.68)
		draw_rect(rect, ac_ring, false, 1.3)
		var perim: float = (rect.size.x + rect.size.y) * 2.0
		for k: int in range(2):
			var d0: float = fmod((_autocast_time + float(k) * 0.5) * perim, perim)
			var seg_len: float = minf(16.0, perim * 0.14)
			var p0: Vector2 = _point_on_rect(rect, d0)
			var p1: Vector2 = _point_on_rect(rect, fmod(d0 + seg_len, perim))
			var col_r: Color = Color(1.0, 0.86, 0.32, 0.98) if (k == 0) else Color(0.32, 1.0, 0.90, 0.98)
			if absf(p0.x - p1.x) < 1.0 or absf(p0.y - p1.y) < 1.0:
				draw_line(p0, p1, col_r, 2.2, true)
			draw_circle(p0, 2.0, col_r)


func _point_on_rect(r: Rect2, dist: float) -> Vector2:
	var rw: float = r.size.x
	var rh: float = r.size.y
	if dist <= rw:
		return Vector2(r.position.x + dist, r.position.y)
	dist -= rw
	if dist <= rh:
		return Vector2(r.end.x, r.position.y + dist)
	dist -= rh
	if dist <= rw:
		return Vector2(r.end.x - dist, r.end.y)
	dist -= rw
	return Vector2(r.position.x, r.end.y - clampf(dist, 0.0, rh))
