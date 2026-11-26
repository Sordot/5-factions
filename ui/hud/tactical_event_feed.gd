class_name TacticalEventFeed
extends Control

const MAX_VISIBLE_EVENTS: int = 4
const ENTRY_LIFETIME: float = 6.5
const FADE_DURATION: float = 1.2

@onready var feed_vbox: VBoxContainer = %FeedVBox

var _entries: Array[Dictionary] = []
var _match_manager: MatchManager = null
var _selection_hud_panel: Control = null
var _anchor_check_timer: float = 0.0
var _using_elevated_offset: bool = false
var _active_faction_id: StringName = &"genesis_v2"


func _ready() -> void:
	add_to_group("tactical_event_feed")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if feed_vbox != null:
		feed_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(_on_teams_reconfigured):
		TeamManager.teams_reconfigured.connect(_on_teams_reconfigured)
	_active_faction_id = FactionHudTheme.resolve_local_faction_id()
	call_deferred("_resolve_references")


func _on_teams_reconfigured() -> void:
	_active_faction_id = FactionHudTheme.resolve_local_faction_id()
	for entry: Dictionary in _entries:
		var panel: PanelContainer = entry.get("node", null) as PanelContainer
		var acc: Color = entry.get("accent", Color(0.28, 0.96, 0.92, 1.0)) as Color
		if panel != null and is_instance_valid(panel):
			panel.add_theme_stylebox_override("panel", _make_pill_style(acc, false))


func _make_pill_style(accent: Color, hovered: bool) -> StyleBoxFlat:
	var pal: Dictionary = FactionHudTheme.get_palette(_active_faction_id)
	var is_brutal: bool = (pal["style"] == &"brutalist")
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.content_margin_left = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 4.0
	if is_brutal:
		sb.bg_color = (pal["bg_hover"] as Color) if hovered else (pal["bg"] as Color)
		sb.border_width_left = 4
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.96)
		sb.set_corner_radius_all(0)
		sb.shadow_color = Color(0.03, 0.04, 0.06, 0.80)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(2.0, 2.0)
	else:
		sb.bg_color = (pal["bg_hover"] as Color) if hovered else (pal["bg"] as Color)
		sb.border_width_left = 3
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.88)
		sb.set_corner_radius_all(4)
	return sb


func _resolve_references() -> void:
	if not is_inside_tree():
		return
	if _match_manager == null:
		_match_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if _match_manager != null and _match_manager.has_signal("tactical_event_logged"):
		if not _match_manager.tactical_event_logged.is_connected(_on_tactical_event_logged):
			_match_manager.tactical_event_logged.connect(_on_tactical_event_logged)

	var sel_hud: Node = get_tree().get_first_node_in_group("selection_hud")
	if sel_hud != null:
		_selection_hud_panel = sel_hud.get_node_or_null("BottomStack/BottomPanel") as Control
	_update_bottom_anchor(true)


func _on_tactical_event_logged(category: StringName, message: String, world_pos: Vector2, accent_color: Color) -> void:
	push_event(category, message, world_pos, accent_color)


func push_event(category: StringName, message: String, world_pos: Vector2, accent_color: Color = Color(0.28, 0.96, 0.92, 1.0)) -> void:
	if feed_vbox == null or message.strip_edges().is_empty():
		return

	var pill: PanelContainer = _build_event_pill(category, message, world_pos, accent_color)
	feed_vbox.add_child(pill)
	_entries.append({
		"node": pill,
		"accent": accent_color,
		"age": 0.0,
		"lifetime": ENTRY_LIFETIME,
	})

	while _entries.size() > MAX_VISIBLE_EVENTS:
		var oldest: Dictionary = _entries.pop_front()
		var old_node: Node = oldest.get("node", null) as Node
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()


func _build_event_pill(category: StringName, message: String, world_pos: Vector2, accent: Color) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.custom_minimum_size = Vector2(220.0, 26.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.tooltip_text = "Click to center camera on event"

	var sb_norm: StyleBoxFlat = _make_pill_style(accent, false)
	var sb_hov: StyleBoxFlat = _make_pill_style(accent, true)
	panel.add_theme_stylebox_override("panel", sb_norm)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var tag_lbl: Label = Label.new()
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_lbl.add_theme_font_size_override("font_size", 10)
	tag_lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.98))
	match category:
		&"combat":
			tag_lbl.text = "COMBAT"
		&"objective":
			tag_lbl.text = "OBJ"
		&"economy":
			tag_lbl.text = "TECH"
		_:
			tag_lbl.text = "SYS"
	hbox.add_child(tag_lbl)

	var msg_lbl: Label = Label.new()
	msg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_lbl.text = message
	msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_lbl.custom_minimum_size = Vector2(140.0, 0.0)
	msg_lbl.clip_text = true
	msg_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	msg_lbl.add_theme_font_size_override("font_size", 11)
	msg_lbl.add_theme_color_override("font_color", Color(0.90, 0.96, 0.99, 0.96))
	hbox.add_child(msg_lbl)

	var jump_lbl: Label = Label.new()
	jump_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jump_lbl.text = "◎"
	jump_lbl.add_theme_font_size_override("font_size", 11)
	jump_lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.78))
	hbox.add_child(jump_lbl)

	var target_pos: Vector2 = world_pos
	var target_col: Color = accent
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_jump_to_event(target_pos, target_col)
				panel.accept_event()
	)
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", sb_hov)
	)
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", sb_norm)
	)

	return panel


func _jump_to_event(world_pos: Vector2, accent: Color) -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if not is_inside_tree():
		return
	var cam: Node = get_tree().get_first_node_in_group("rts_camera")
	if cam != null:
		if cam.has_method("smooth_center_on"):
			cam.call("smooth_center_on", world_pos)
		elif cam.has_method("center_on"):
			cam.call("center_on", world_pos)
	var mini: Node = get_tree().get_first_node_in_group("tactical_minimap")
	if mini != null and mini.has_method("flash_ping"):
		mini.call("flash_ping", world_pos, accent, 1.8)


func _process(delta: float) -> void:
	_anchor_check_timer += delta
	if _anchor_check_timer >= 0.15:
		_anchor_check_timer = 0.0
		_update_bottom_anchor(false)

	if _entries.is_empty():
		return

	var remaining: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		var node: Control = entry.get("node", null) as Control
		if node == null or not is_instance_valid(node):
			continue
		var age: float = float(entry["age"]) + delta
		var life: float = float(entry["lifetime"])
		if age >= life:
			node.queue_free()
			continue
		entry["age"] = age
		var time_left: float = life - age
		if time_left < FADE_DURATION:
			node.modulate.a = clampf(time_left / FADE_DURATION, 0.0, 1.0)
		else:
			node.modulate.a = 1.0
		remaining.append(entry)
	_entries = remaining


func _update_bottom_anchor(force: bool) -> void:
	if feed_vbox == null:
		return
	var hud_visible: bool = _selection_hud_panel != null and is_instance_valid(_selection_hud_panel) and _selection_hud_panel.visible
	if not force and hud_visible == _using_elevated_offset:
		return
	_using_elevated_offset = hud_visible
	if hud_visible:
		# Clear SelectionHUD's compact 160px bottom bar cleanly at 1280x720
		feed_vbox.offset_bottom = -176.0
		feed_vbox.offset_top = -336.0
	else:
		feed_vbox.offset_bottom = -16.0
		feed_vbox.offset_top = -176.0
