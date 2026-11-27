class_name SelectionEntityPortrait
extends Control

## Compact 44x44 procedural vector emblem for SelectionHUD's left column.
## Replaces the flat ColorRect swatch strictly within the existing 740x160 BottomPanel footprint,
## rendering OS-themed framing, entity glyphs, Veterancy chevrons, squad count, fog-ghost scanlines,
## and unpowered warning badges with zero external assets.

var _faction_id: StringName = &"genesis_v2"
var _theme_accent: Color = Color(0.20, 0.96, 0.86, 1.0)
var _glyph_id: StringName = &""
var _glyph_category: StringName = &""
var _accent_color: Color = Color(0.20, 0.96, 0.86, 1.0)
var _veterancy_rank: int = 0
var _squad_count: int = 1
var _is_ghost: bool = false
var _is_unpowered: bool = false
var _pulse_time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(44.0, 44.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func apply_faction_theme(faction_id: StringName, accent: Color) -> void:
	_faction_id = faction_id
	_theme_accent = accent
	queue_redraw()


func bind_display(
	glyph_id: StringName,
	accent_color: Color,
	veterancy_rank: int = 0,
	squad_count: int = 1,
	is_ghost: bool = false,
	is_unpowered: bool = false,
	glyph_category: StringName = &""
) -> void:
	var changed: bool = (
		_glyph_id != glyph_id
		or _glyph_category != glyph_category
		or not _accent_color.is_equal_approx(accent_color)
		or _veterancy_rank != veterancy_rank
		or _squad_count != squad_count
		or _is_ghost != is_ghost
		or _is_unpowered != is_unpowered
	)
	_glyph_id = glyph_id
	_glyph_category = glyph_category
	_accent_color = accent_color
	_veterancy_rank = clampi(veterancy_rank, 0, 3)
	_squad_count = maxi(1, squad_count)
	_is_ghost = is_ghost
	_is_unpowered = is_unpowered
	set_process(_is_unpowered)
	if changed:
		queue_redraw()


func _process(delta: float) -> void:
	if not _is_unpowered:
		set_process(false)
		return
	var real_dt: float = minf(delta / maxf(0.1, Engine.time_scale), 0.05)
	_pulse_time += real_dt
	queue_redraw()


func _draw() -> void:
	var w: float = maxf(44.0, size.x)
	var h: float = maxf(44.0, size.y)
	var pal: Dictionary = FactionHudTheme.get_palette(_faction_id)
	var style: StringName = pal.get("style", &"technozen") as StringName
	var border_col: Color = pal.get("accent", _theme_accent) as Color
	var inner_trim: Color = pal.get("inner_trim", Color(0.90, 0.96, 0.98, 0.65)) as Color
	var bg_col: Color = (pal.get("bg_row", Color(0.035, 0.070, 0.105, 0.96)) as Color).darkened(0.22)
	bg_col.a = 0.96

	# 1. OS-themed dark 44x44 portrait socket
	if style == &"brutalist":
		draw_rect(Rect2(0.0, 0.0, w, h), bg_col, true)
		draw_rect(Rect2(0.5, 0.5, w - 1.0, h - 1.0), Color(0.039, 0.051, 0.071, 0.98), false, 2.0)
		draw_rect(Rect2(3.0, 3.0, w - 6.0, h - 6.0), Color(inner_trim.r, inner_trim.g, inner_trim.b, 0.45), false, 1.0)
		var arm: float = 8.0
		draw_line(Vector2(1.0, 1.0), Vector2(1.0 + arm, 1.0), border_col, 2.2)
		draw_line(Vector2(1.0, 1.0), Vector2(1.0, 1.0 + arm), border_col, 2.2)
		draw_line(Vector2(w - 1.0, h - 1.0), Vector2(w - 1.0 - arm, h - 1.0), border_col, 2.2)
		draw_line(Vector2(w - 1.0, h - 1.0), Vector2(w - 1.0, h - 1.0 - arm), border_col, 2.2)
	elif style == &"bauhaus_sacred":
		draw_rect(Rect2(1.0, 1.0, w - 2.0, h - 2.0), bg_col, true)
		draw_rect(Rect2(1.5, 1.5, w - 3.0, h - 3.0), Color(border_col.r, border_col.g, border_col.b, 0.88), false, 1.8)
		draw_rect(Rect2(4.0, 4.0, w - 8.0, h - 8.0), Color(inner_trim.r, inner_trim.g, inner_trim.b, 0.28), false, 1.0)
		var d_off: float = 4.0
		var d_r: float = 2.4
		for c_pt: Vector2 in [
			Vector2(d_off, d_off), Vector2(w - d_off, d_off),
			Vector2(w - d_off, h - d_off), Vector2(d_off, h - d_off),
		]:
			var dia: PackedVector2Array = PackedVector2Array([
				c_pt + Vector2(0.0, -d_r), c_pt + Vector2(d_r, 0.0),
				c_pt + Vector2(0.0, d_r), c_pt + Vector2(-d_r, 0.0),
			])
			draw_colored_polygon(dia, border_col)
	else:
		# Technozen 4px chamfered teal socket
		var ch: float = 4.0
		var poly: PackedVector2Array = PackedVector2Array([
			Vector2(ch, 1.0), Vector2(w - ch, 1.0),
			Vector2(w - 1.0, ch), Vector2(w - 1.0, h - ch),
			Vector2(w - ch, h - 1.0), Vector2(ch, h - 1.0),
			Vector2(1.0, h - ch), Vector2(1.0, ch),
		])
		draw_colored_polygon(poly, bg_col)
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, Color(border_col.r, border_col.g, border_col.b, 0.78), 1.5, true)
		draw_line(Vector2(7.0, 3.0), Vector2(w - 7.0, 3.0), Color(border_col.r, border_col.g, border_col.b, 0.42), 1.0)

	# 2. Centered 28x28 procedural vector glyph
	var draw_col: Color = _accent_color
	if _is_ghost:
		draw_col = _accent_color.lerp(Color(0.56, 0.64, 0.72, 1.0), 0.62)
		draw_col.a = 0.85
	var glyph_rect: Rect2 = Rect2((w - 28.0) * 0.5, (h - 28.0) * 0.5, 28.0, 28.0)
	CommandIconGlyphs.draw_glyph(self, _glyph_id, glyph_rect, draw_col, _glyph_category)

	# 3. Context micro-overlays
	var font: Font = ThemeDB.fallback_font
	if _is_ghost:
		# Subtle CRT horizontal scanlines + tiny FOG badge
		var sy: float = 4.0
		while sy < h - 3.0:
			draw_line(Vector2(3.0, sy), Vector2(w - 3.0, sy), Color(0.68, 0.80, 0.90, 0.14), 1.0)
			sy += 4.0
		var fog_rect: Rect2 = Rect2(w - 24.0, h - 13.0, 22.0, 11.0)
		draw_rect(fog_rect, Color(0.04, 0.06, 0.10, 0.90), true)
		draw_rect(fog_rect, Color(0.66, 0.76, 0.86, 0.78), false, 1.0)
		draw_string(font, fog_rect.position + Vector2(2.0, 9.0), "FOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.84, 0.92, 0.98, 0.95))

	if _veterancy_rank > 0:
		var gold: Color = Color(0.980, 0.800, 0.082, 0.98) # #FACC15
		for vi: int in range(_veterancy_rank):
			var cy: float = 9.5 + float(vi) * 4.5
			draw_polyline(PackedVector2Array([
				Vector2(4.0, cy),
				Vector2(7.5, cy - 3.0),
				Vector2(11.0, cy),
			]), gold, 1.6, true)

	if _squad_count > 1 and not _is_ghost:
		var sq_txt: String = "×%d" % _squad_count
		var sq_sz: Vector2 = font.get_string_size(sq_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		var bw: float = sq_sz.x + 6.0
		var bh: float = 12.0
		var sq_rect: Rect2 = Rect2(w - bw - 1.5, h - bh - 1.5, bw, bh)
		draw_rect(sq_rect, Color(0.03, 0.06, 0.10, 0.92), true)
		draw_rect(sq_rect, Color(border_col.r, border_col.g, border_col.b, 0.80), false, 1.0)
		draw_string(font, sq_rect.position + Vector2(3.0, 9.5), sq_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.96, 0.99, 1.0, 0.98))

	if _is_unpowered:
		var p_val: float = 0.5 + 0.5 * sin(_pulse_time * 7.0)
		var warn_col: Color = Color(1.0, 0.62, 0.18, 0.92).lerp(Color(1.0, 0.28, 0.24, 0.98), p_val)
		var tri: PackedVector2Array = PackedVector2Array([
			Vector2(w - 13.0, 2.0),
			Vector2(w - 2.0, 2.0),
			Vector2(w - 2.0, 13.0),
		])
		draw_colored_polygon(tri, Color(warn_col.r, warn_col.g, warn_col.b, 0.88))
		draw_line(Vector2(w - 13.0, 2.0), Vector2(w - 2.0, 13.0), Color(0.04, 0.05, 0.08, 0.95), 1.3, true)
