class_name FactionHudTheme
extends RefCounted

## Centralized procedural faction OS HUD theme helper & pluggable provider registry shared across
## SelectionHUD, ResourceHUD, ProductionTicker, TacticalMinimap, TacticalEventFeed, and CommandIconButton.
## Register new faction HUD themes via FactionHudTheme.register_theme_provider(faction_id, palette_dict).

static var _theme_providers: Dictionary = {} # StringName -> Dictionary
static var _builtins_registered: bool = false


static func _ensure_builtin_providers() -> void:
	if _builtins_registered:
		return
	_builtins_registered = true
	register_theme_provider(&"monolith_os", {
		"faction_id": &"monolith_os",
		"style": &"brutalist",
		"bg": Color(0.150, 0.165, 0.185, 0.96),
		"bg_hover": Color(0.205, 0.222, 0.248, 0.98),
		"bg_row": Color(0.125, 0.138, 0.156, 0.96),
		"border": Color(0.039, 0.051, 0.071, 0.98), # #0A0D12 thick ink
		"inner_trim": Color(0.949, 0.937, 0.914, 0.88), # #F2EFE9 off-white
		"accent": Color(1.0, 0.624, 0.110, 1.0), # #FF9F1C Hazard Amber
		"secondary": Color(0.220, 0.741, 0.973, 1.0), # #38BDF8 Shield Cyan
		"primary": Color(0.949, 0.937, 0.914, 1.0),
		"corner_radius": 0,
		"border_width": 3,
		"shadow_size": 1,
		"shadow_offset": Vector2(3.0, 3.0),
		"shadow_color": Color(0.03, 0.04, 0.06, 0.80),
	})
	register_theme_provider(&"spectator", {
		"faction_id": &"spectator",
		"style": &"technozen",
		"bg": Color(0.050, 0.070, 0.100, 0.92),
		"bg_hover": Color(0.085, 0.120, 0.170, 0.96),
		"bg_row": Color(0.042, 0.062, 0.092, 0.90),
		"border": Color(0.360, 0.780, 0.960, 0.82),
		"inner_trim": Color(0.420, 0.880, 1.000, 0.45),
		"accent": Color(0.420, 0.880, 1.000, 1.0),
		"secondary": Color(0.760, 0.880, 0.960, 1.0),
		"primary": Color(0.900, 0.960, 1.000, 1.0),
		"corner_radius": 4,
		"border_width": 1,
		"shadow_size": 4,
		"shadow_offset": Vector2(0.0, 2.0),
		"shadow_color": Color(0.0, 0.02, 0.05, 0.50),
	})
	register_theme_provider(&"genesis_v2", {
		"faction_id": &"genesis_v2",
		"style": &"technozen",
		"bg": Color(0.040, 0.080, 0.120, 0.92),
		"bg_hover": Color(0.065, 0.130, 0.185, 0.96),
		"bg_row": Color(0.035, 0.072, 0.110, 0.90),
		"border": Color(0.125, 0.961, 0.863, 0.88), # #20F5DC
		"inner_trim": Color(0.200, 0.960, 0.860, 0.45),
		"accent": Color(0.200, 0.960, 0.860, 1.0),
		"secondary": Color(0.280, 0.980, 0.620, 1.0),
		"primary": Color(0.900, 0.960, 0.980, 1.0),
		"corner_radius": 6,
		"border_width": 2,
		"shadow_size": 6,
		"shadow_offset": Vector2(0.0, 2.0),
		"shadow_color": Color(0.0, 0.03, 0.06, 0.55),
	})


static func register_theme_provider(faction_id: StringName, provider: Dictionary) -> void:
	if faction_id == &"" or provider.is_empty():
		return
	var entry: Dictionary = provider.duplicate(true)
	entry["faction_id"] = faction_id
	_theme_providers[faction_id] = entry


static func has_theme_provider(faction_id: StringName) -> bool:
	_ensure_builtin_providers()
	return _theme_providers.has(faction_id)


static func resolve_local_faction_id() -> StringName:
	if TeamManager == null:
		return &"genesis_v2"
	if TeamManager.has_method("is_spectator_mode") and TeamManager.is_spectator_mode():
		return &"spectator"
	var local_t: int = TeamManager.get_local_human_team()
	if local_t >= 0 and TeamManager.has_method("get_team_faction"):
		var fid: StringName = TeamManager.get_team_faction(local_t)
		if fid != &"":
			return fid
	return &"genesis_v2"


static func get_palette(faction_id: StringName) -> Dictionary:
	_ensure_builtin_providers()
	var resolved_id: StringName = &"genesis_v2" if faction_id == &"" else faction_id
	if _theme_providers.has(resolved_id):
		return _theme_providers[resolved_id] as Dictionary

	# Future factions (#3-#5) without a custom provider: dynamic Technozen palette tinted from FactionData
	var accent_col: Color = Color(0.20, 0.96, 0.86, 1.0)
	var prim_col: Color = Color(0.90, 0.96, 0.98, 1.0)
	if TeamManager != null and TeamManager.has_method("get_faction_data"):
		var fac: FactionData = TeamManager.get_faction_data(resolved_id) as FactionData
		if fac != null:
			accent_col = fac.hud_accent_color
			prim_col = fac.primary_color
	return {
		"faction_id": resolved_id,
		"style": &"technozen",
		"bg": Color(0.045, 0.078, 0.115, 0.92),
		"bg_hover": Color(0.075, 0.125, 0.175, 0.96),
		"bg_row": Color(0.038, 0.068, 0.102, 0.90),
		"border": Color(accent_col.r, accent_col.g, accent_col.b, 0.86),
		"inner_trim": Color(accent_col.r, accent_col.g, accent_col.b, 0.42),
		"accent": accent_col,
		"secondary": prim_col,
		"primary": prim_col,
		"corner_radius": 6,
		"border_width": 2,
		"shadow_size": 5,
		"shadow_offset": Vector2(0.0, 2.0),
		"shadow_color": Color(0.0, 0.03, 0.06, 0.52),
	}


static func make_panel_style(faction_id: StringName, compact: bool = false) -> StyleBoxFlat:
	var pal: Dictionary = get_palette(faction_id)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	var is_brutal: bool = (pal["style"] == &"brutalist")
	sb.bg_color = pal["bg"] as Color
	sb.border_color = pal["border"] as Color
	var bw: int = int(pal["border_width"])
	if compact and not is_brutal:
		bw = maxi(1, bw - 1)
	sb.set_border_width_all(bw)
	var rad: int = int(pal["corner_radius"])
	if compact and rad > 0:
		rad = maxi(3, rad - 2)
	sb.set_corner_radius_all(rad)
	sb.shadow_color = pal["shadow_color"] as Color
	sb.shadow_size = int(pal["shadow_size"])
	sb.shadow_offset = pal["shadow_offset"] as Vector2
	if compact:
		sb.content_margin_left = 8.0
		sb.content_margin_top = 5.0
		sb.content_margin_right = 8.0
		sb.content_margin_bottom = 5.0
	else:
		sb.content_margin_left = 10.0
		sb.content_margin_top = 8.0
		sb.content_margin_right = 10.0
		sb.content_margin_bottom = 8.0
	return sb


static func make_utility_button_style(faction_id: StringName, hovered: bool = false) -> StyleBoxFlat:
	var pal: Dictionary = get_palette(faction_id)
	var is_brutal: bool = (pal["style"] == &"brutalist")
	var accent: Color = pal["accent"] as Color
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	if is_brutal:
		sb.bg_color = Color(0.20, 0.215, 0.24, 0.96) if hovered else Color(0.135, 0.148, 0.168, 0.96)
		sb.set_corner_radius_all(0)
		sb.set_border_width_all(2)
		sb.border_color = accent if hovered else (pal["inner_trim"] as Color)
	else:
		sb.bg_color = Color(0.08, 0.16, 0.22, 0.94) if hovered else Color(0.04, 0.09, 0.14, 0.90)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(1)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.92 if hovered else 0.45)
	return sb


static func style_utility_button(btn: Button, faction_id: StringName) -> void:
	if btn == null:
		return
	var norm: StyleBoxFlat = make_utility_button_style(faction_id, false)
	var hov: StyleBoxFlat = make_utility_button_style(faction_id, true)
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("focus", hov)


static func attach_frame_overlay(target_panel: Control, faction_id: StringName, variant: StringName = &"default") -> Control:
	if target_panel == null:
		return null
	var existing: Control = target_panel.get_node_or_null("FactionHudFrameOverlay") as Control
	var overlay: _HudFrameOverlay = existing as _HudFrameOverlay if existing is _HudFrameOverlay else null
	if overlay == null:
		if existing != null:
			existing.queue_free()
		overlay = _HudFrameOverlay.new()
		overlay.name = "FactionHudFrameOverlay"
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.z_index = 4
		target_panel.add_child(overlay)
	var pal: Dictionary = get_palette(faction_id)
	overlay.configure(pal, variant)
	return overlay


class _HudFrameOverlay extends Control:
	var _style: StringName = &"technozen"
	var _variant: StringName = &"default"
	var _accent: Color = Color(0.20, 0.96, 0.86, 1.0)
	var _inner_trim: Color = Color(0.95, 0.94, 0.91, 0.85)
	var _ink: Color = Color(0.04, 0.05, 0.07, 0.96)
	var _palette: Dictionary = {}
	var _custom_drawer: Callable = Callable()

	func configure(pal: Dictionary, variant: StringName) -> void:
		_palette = pal
		_style = pal.get("style", &"technozen") as StringName
		_variant = variant
		_accent = pal.get("accent", Color(0.20, 0.96, 0.86, 1.0)) as Color
		_inner_trim = pal.get("inner_trim", Color(0.95, 0.94, 0.91, 0.85)) as Color
		_ink = pal.get("border", Color(0.04, 0.05, 0.07, 0.96)) as Color
		var drawer_val: Variant = pal.get("frame_drawer", Callable())
		_custom_drawer = drawer_val as Callable if drawer_val is Callable else Callable()
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 24.0 or h < 18.0:
			return

		if _custom_drawer.is_valid():
			_custom_drawer.call(self, size, _variant, _palette)
			return

		if _style == &"brutalist":
			var amber: Color = _accent
			var offwhite: Color = _inner_trim
			var inset: float = 3.5

			# Crisp off-white inner hairline frame inside the thick ink outer border
			draw_rect(Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0), Color(offwhite.r, offwhite.g, offwhite.b, 0.78), false, 1.2)

			# Optional diagonal hazard-stripe bar above SelectionHUD's Command Card
			if _variant == &"selection" and w > 240.0:
				var bar_x: float = maxf(8.0, w - 208.0)
				var bar_w: float = w - bar_x - 6.0
				draw_rect(Rect2(bar_x, 4.5, bar_w, 4.5), _ink, true)
				var sx: float = bar_x + 2.0
				while sx < bar_x + bar_w - 6.0:
					draw_line(Vector2(sx, 8.8), Vector2(sx + 5.0, 4.8), Color(amber.r, amber.g, amber.b, 0.75), 2.0)
					sx += 11.0

			# Bold Hazard Amber L-brackets
			var arm: float = 15.0 if (_variant == &"selection" or _variant == &"minimap") else 10.0
			var bw: float = 2.8 if (_variant == &"selection" or _variant == &"minimap") else 2.2
			# Top-Left & Bottom-Right in Hazard Amber
			draw_line(Vector2(1.5, 1.5), Vector2(1.5 + arm, 1.5), amber, bw)
			draw_line(Vector2(1.5, 1.5), Vector2(1.5, 1.5 + arm), amber, bw)
			draw_line(Vector2(w - 1.5, h - 1.5), Vector2(w - 1.5 - arm, h - 1.5), amber, bw)
			draw_line(Vector2(w - 1.5, h - 1.5), Vector2(w - 1.5, h - 1.5 - arm), amber, bw)
			# Opposite corners: Amber on Minimap (4 full L-clamps), off-white on other panels
			var opp_col: Color = amber if _variant == &"minimap" else Color(offwhite.r, offwhite.g, offwhite.b, 0.85)
			var opp_arm: float = arm if _variant == &"minimap" else (arm * 0.65)
			draw_line(Vector2(w - 1.5, 1.5), Vector2(w - 1.5 - opp_arm, 1.5), opp_col, 2.0)
			draw_line(Vector2(w - 1.5, 1.5), Vector2(w - 1.5, 1.5 + opp_arm), opp_col, 2.0)
			draw_line(Vector2(1.5, h - 1.5), Vector2(1.5 + opp_arm, h - 1.5), opp_col, 2.0)
			draw_line(Vector2(1.5, h - 1.5), Vector2(1.5, h - 1.5 - opp_arm), opp_col, 2.0)

			# Compact procedural halftone dot strip in lower-right corner (strictly outside text area)
			if _variant == &"selection":
				_draw_halftone_corner(Rect2(maxf(12.0, w - 74.0), maxf(12.0, h - 20.0), 66.0, 14.0), amber, 0.24)
			elif _variant == &"top_bar" or _variant == &"ticker":
				_draw_halftone_corner(Rect2(w - 34.0, h - 11.0, 28.0, 6.0), amber, 0.22)
		else:
			# Technozen / Bio-Synth (and Spectator / Future Factions)
			var glow: Color = Color(_accent.r, _accent.g, _accent.b, 0.58)
			var soft: Color = Color(_accent.r, _accent.g, _accent.b, 0.24)
			var inset_x: float = minf(18.0, w * 0.12)
			draw_line(Vector2(inset_x, 2.2), Vector2(w - inset_x, 2.2), glow, 1.3, true)
			draw_line(Vector2(inset_x + 6.0, h - 2.2), Vector2(w - inset_x - 6.0, h - 2.2), soft, 1.1, true)

			var node_off: float = 6.5 if (_variant == &"selection" or _variant == &"minimap") else 5.0
			var dot_r: float = 2.0 if (_variant == &"selection" or _variant == &"minimap") else 1.5
			var corners: PackedVector2Array = PackedVector2Array([
				Vector2(node_off, node_off),
				Vector2(w - node_off, node_off),
				Vector2(w - node_off, h - node_off),
				Vector2(node_off, h - node_off),
			])
			for pt: Vector2 in corners:
				draw_circle(pt, dot_r + 2.4, Color(_accent.r, _accent.g, _accent.b, 0.14))
				draw_arc(pt, dot_r + 1.8, 0.0, TAU, 12, Color(_accent.r, _accent.g, _accent.b, 0.50), 1.0, true)
				draw_circle(pt, dot_r, _accent)

			if h > 56.0:
				draw_line(Vector2(3.0, 18.0), Vector2(3.0, h - 18.0), soft, 1.0)
				draw_line(Vector2(w - 3.0, 18.0), Vector2(w - 3.0, h - 18.0), soft, 1.0)

	func _draw_halftone_corner(bounds: Rect2, col: Color, alpha: float) -> void:
		var dot_col: Color = Color(col.r, col.g, col.b, alpha)
		var row: int = 0
		var y: float = bounds.position.y
		while y <= bounds.end.y:
			var x: float = bounds.position.x + (3.5 if (row % 2 == 1) else 0.0)
			while x <= bounds.end.x:
				draw_circle(Vector2(x, y), 1.05, dot_col)
				x += 7.0
			y += 5.5
			row += 1
