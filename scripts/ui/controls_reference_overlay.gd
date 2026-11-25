class_name ControlsReferenceOverlay
extends CanvasLayer

signal closed

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

@onready var subtitle_label: Label = %SubtitleLabel
@onready var btn_close: Button = %BtnClose
@onready var left_column: VBoxContainer = %LeftColumn
@onready var right_column: VBoxContainer = %RightColumn
@onready var btn_open_keybinds: Button = %BtnOpenKeybinds


func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("controls_reference_overlay")

	# Auto-close Tech Tree overlay if open so reference modals never stack awkwardly.
	if is_inside_tree():
		for tech_node: Node in get_tree().get_nodes_in_group("tech_tree_overlay"):
			if is_instance_valid(tech_node) and not tech_node.is_queued_for_deletion():
				if tech_node.has_method("close_overlay"):
					tech_node.call("close_overlay")
				else:
					tech_node.queue_free()

	if btn_close != null:
		btn_close.pressed.connect(close_overlay)
	if btn_open_keybinds != null:
		btn_open_keybinds.pressed.connect(_on_open_keybinds_pressed)

	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()
		if not SettingsManager.settings_changed.is_connected(_on_settings_changed):
			SettingsManager.settings_changed.connect(_on_settings_changed)
		if not SettingsManager.keybind_changed.is_connected(_on_keybind_changed):
			SettingsManager.keybind_changed.connect(_on_keybind_changed)

	_rebuild_cards()


func _exit_tree() -> void:
	if SettingsManager != null:
		SettingsManager.call_deferred("refresh_mouse_mode")


func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_pressed("cmd_cancel") or event.is_action_pressed("ui_toggle_controls_help"):
		get_viewport().set_input_as_handled()
		close_overlay()


func close_overlay() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	closed.emit()
	queue_free()


func _on_settings_changed(category: StringName) -> void:
	if category == &"controls" or category == &"gameplay" or category == &"all":
		_rebuild_cards()


func _on_keybind_changed(_action_name: StringName) -> void:
	_rebuild_cards()


func _on_open_keybinds_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		var pause_menu: Node = get_tree().get_first_node_in_group("pause_menu")
		if pause_menu != null and is_instance_valid(pause_menu) and pause_menu.has_method("open_settings_from_overlay"):
			var is_paused_menu: bool = pause_menu.has_method("is_pause_open") and bool(pause_menu.call("is_pause_open"))
			if is_paused_menu:
				pause_menu.call("open_settings_from_overlay")
				closed.emit()
				queue_free()
				return
		var existing_settings: Node = get_tree().get_first_node_in_group("settings_menu")
		if existing_settings == null or not is_instance_valid(existing_settings):
			var settings_inst: CanvasLayer = SETTINGS_MENU_SCENE.instantiate() as CanvasLayer
			if settings_inst != null:
				get_tree().root.add_child(settings_inst)
	closed.emit()
	queue_free()


func _key_short(action_name: StringName, fallback: String) -> String:
	if SettingsManager == null:
		return fallback
	var lbl: String = SettingsManager.get_action_short_label(action_name)
	return lbl if not lbl.is_empty() else "—"


func _rebuild_cards() -> void:
	if left_column == null or right_column == null:
		return
	for child: Node in left_column.get_children():
		child.queue_free()
	for child: Node in right_column.get_children():
		child.queue_free()

	var help_key: String = SettingsManager.get_action_short_label(&"ui_toggle_controls_help") if SettingsManager != null else "?"
	if btn_close != null:
		btn_close.text = ("Close (Esc / %s)" % help_key) if not help_key.is_empty() else "Close (Esc)"
	if subtitle_label != null:
		var close_hint: String = ("Press %s or Esc to close" % help_key) if not help_key.is_empty() else "Press Esc to close"
		subtitle_label.text = "Live keybindings pulled directly from your active Settings profile  •  %s" % close_hint

	var amove_mode_note: String = "Quick-Cast at Cursor"
	if SettingsManager != null and SettingsManager.attack_move_mode == SettingsManager.AttackMoveMode.CLICK_TO_CONFIRM:
		amove_mode_note = "Click-to-Confirm"
	var snap_state: String = "ON" if (SettingsManager != null and SettingsManager.build_grid_snap_enabled) else "OFF"
	var smart_box_state: String = "ON" if (SettingsManager != null and SettingsManager.smart_box_select_enabled) else "OFF"

	# Column 1: Selection & Control Groups + Combat & Orders
	left_column.add_child(_build_section_card(
		"SELECTION & CONTROL GROUPS",
		Color(0.28, 0.98, 0.90, 1.0),
		[
			{"key": "LMB / Drag", "desc": "Select unit/building or drag-box squad"},
			{"key": "Dbl-Click / Ctrl+LMB", "desc": "Select all on-screen units of same type"},
			{"key": "Ctrl / Shift / Alt + 1–9", "desc": "Assign / Add to / Steal Control Group (2× tap centers)"},
			{"key": _key_short(&"ui_cycle_subgroup", "TAB"), "desc": "Cycle active subgroup in mixed selection"},
			{"key": _key_short(&"cmd_select_all_army", "F9"), "desc": "Select all combat army units"},
			{"key": _key_short(&"cmd_select_idle_worker", "`"), "desc": "Cycle idle workers (2× centers camera)"},
			{"key": _key_short(&"cmd_select_idle_production", ";"), "desc": "Cycle idle production (+Shift selects all)"},
			{"key": _key_short(&"cmd_toggle_smart_box_select", "B"), "desc": "Toggle Combat-Only Box Select (Now: %s)" % smart_box_state},
		]
	))

	var ab_keys: String = "%s / %s / %s / %s / %s" % [
		_key_short(&"cmd_ability_q", "Q"),
		_key_short(&"cmd_ability_w", "W"),
		_key_short(&"cmd_ability_e", "E"),
		_key_short(&"cmd_ability_r", "R"),
		_key_short(&"cmd_ability_f", "F"),
	]
	left_column.add_child(_build_section_card(
		"COMBAT, ORDERS & PRODUCTION",
		Color(1.0, 0.54, 0.36, 1.0),
		[
			{"key": "RMB", "desc": "Smart Move / Attack / Gather / Repair / Set Rally"},
			{"key": _key_short(&"cmd_attack_move", "A"), "desc": "Attack-Move (%s)" % amove_mode_note},
			{"key": _key_short(&"cmd_patrol", "P"), "desc": "Patrol waypoint loop (Shift chains points)"},
			{"key": "%s / %s" % [_key_short(&"cmd_defensive_stance", "D"), _key_short(&"cmd_hold", "H")], "desc": "Defensive Stance (260px leash) / Hold Position"},
			{"key": _key_short(&"cmd_stop", "S"), "desc": "Stop current order and clear queue"},
			{"key": "Shift + Order / Click", "desc": "Queue waypoints or train ×5 batch in production"},
			{"key": ab_keys, "desc": "Unit abilities, worker build slots & Eject Engineers"},
		]
	))

	# Column 2: Camera & Navigation + Interface & System
	var pan_keys: String = "%s %s %s %s" % [
		_key_short(&"camera_pan_up", "UP"),
		_key_short(&"camera_pan_down", "DN"),
		_key_short(&"camera_pan_left", "LT"),
		_key_short(&"camera_pan_right", "RT"),
	]
	var bm_keys: String = "%s–%s" % [
		_key_short(&"cam_bookmark_1", "F1"),
		_key_short(&"cam_bookmark_4", "F4"),
	]
	right_column.add_child(_build_section_card(
		"CAMERA & NAVIGATION",
		Color(0.42, 0.90, 1.0, 1.0),
		[
			{"key": pan_keys, "desc": "Keyboard camera pan"},
			{"key": "MMB Drag / Edge", "desc": "Middle-mouse drag pan / Screen-edge pan"},
			{"key": "Mouse Wheel", "desc": "Zoom camera in / out"},
			{"key": "Ctrl + %s / %s" % [bm_keys, bm_keys], "desc": "Save / Jump to Camera Bookmarks 1–4"},
			{"key": _key_short(&"jump_base_hub", "BKSP"), "desc": "Jump camera to primary Command Hub"},
			{"key": _key_short(&"jump_last_alert", "SPC"), "desc": "Jump camera to latest tactical alert"},
			{"key": _key_short(&"camera_toggle_edge_pan", "F12"), "desc": "Toggle screen edge-panning"},
		]
	))

	var speed_keys: String = "%s / %s" % [
		_key_short(&"game_speed_down", "["),
		_key_short(&"game_speed_up", "]"),
	]
	right_column.add_child(_build_section_card(
		"INTERFACE, BUILDING & SYSTEM",
		Color(0.98, 0.80, 0.34, 1.0),
		[
			{"key": speed_keys, "desc": "Adjust match speed (0.5× – 2.0×)"},
			{"key": _key_short(&"ui_toggle_tech_tree", "U"), "desc": "Toggle live Faction Tech Tree & Counter Matrix"},
			{"key": _key_short(&"ui_toggle_controls_help", "?"), "desc": "Toggle this Controls Quick-Reference card"},
			{"key": "Hold Alt (Build)", "desc": "Temporarily invert Build Grid Snap (Now: %s)" % snap_state},
			{"key": "%s / Alt+Enter" % _key_short(&"camera_toggle_fullscreen", "F11"), "desc": "Toggle Borderless Fullscreen"},
			{"key": "Esc", "desc": "Cancel targeting / Close modal / Pause Menu"},
			{"key": _key_short(&"debug_toggle_aggro_ai", "F10"), "desc": "Toggle Aggro AI attacks (Debug)"},
		]
	))


func _build_section_card(title: String, accent: Color, rows: Array[Dictionary]) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.13, 0.94)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)

	var hdr: Label = Label.new()
	hdr.text = title
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", accent)
	vbox.add_child(hdr)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	for row: Dictionary in rows:
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var badge_panel: PanelContainer = PanelContainer.new()
		badge_panel.custom_minimum_size = Vector2(142.0, 20.0)
		var b_sb: StyleBoxFlat = StyleBoxFlat.new()
		b_sb.bg_color = Color(0.08, 0.14, 0.20, 0.96)
		b_sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
		b_sb.set_border_width_all(1)
		b_sb.set_corner_radius_all(3)
		b_sb.content_margin_left = 6.0
		b_sb.content_margin_right = 6.0
		b_sb.content_margin_top = 1.0
		b_sb.content_margin_bottom = 1.0
		badge_panel.add_theme_stylebox_override("panel", b_sb)

		var key_lbl: Label = Label.new()
		key_lbl.text = String(row.get("key", "—"))
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.add_theme_color_override("font_color", Color(0.94, 0.99, 1.0, 1.0))
		badge_panel.add_child(key_lbl)
		hbox.add_child(badge_panel)

		var desc_lbl: Label = Label.new()
		desc_lbl.text = String(row.get("desc", ""))
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(0.84, 0.92, 0.96, 0.94))
		hbox.add_child(desc_lbl)

		vbox.add_child(hbox)

	panel.add_child(vbox)
	return panel
