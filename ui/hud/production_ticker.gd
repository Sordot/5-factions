class_name ProductionTicker
extends Control

const MAX_VISIBLE_ROWS: int = 6
const REFRESH_INTERVAL: float = 0.20

@onready var ticker_panel: PanelContainer = %TickerPanel
@onready var header_label: Label = %HeaderLabel
@onready var btn_collapse: Button = %BtnCollapse
@onready var rows_container: VBoxContainer = %RowsContainer
@onready var overflow_label: Label = %OverflowLabel

var _selection_controller: SelectionController = null
var _collapsed: bool = false
var _refresh_timer: float = 0.0
var _row_widgets: Array[Dictionary] = []
var _active_faction_id: StringName = &"genesis_v2"
var _faction_accent: Color = Color(0.24, 0.96, 0.86, 1.0)
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("production_ticker")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ticker_panel != null:
		ticker_panel.add_to_group("blocks_edge_pan")
		ticker_panel.visible = false
	if btn_collapse != null:
		btn_collapse.add_to_group("blocks_edge_pan")
		btn_collapse.pressed.connect(_on_toggle_collapse)
	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(_apply_faction_theme):
		TeamManager.teams_reconfigured.connect(_apply_faction_theme)
	_apply_faction_theme()
	call_deferred("_resolve_selection_controller")
	call_deferred("_refresh_ticker")


func _apply_faction_theme(_mode: StringName = &"") -> void:
	_active_faction_id = FactionHudTheme.resolve_local_faction_id()
	var pal: Dictionary = FactionHudTheme.get_palette(_active_faction_id)
	_faction_accent = pal["accent"] as Color
	if ticker_panel != null:
		ticker_panel.add_theme_stylebox_override("panel", FactionHudTheme.make_panel_style(_active_faction_id, true))
		FactionHudTheme.attach_frame_overlay(ticker_panel, _active_faction_id, &"ticker")
	if header_label != null:
		header_label.add_theme_color_override("font_color", _faction_accent)
	if btn_collapse != null:
		FactionHudTheme.style_utility_button(btn_collapse, _active_faction_id)
	for w: Dictionary in _row_widgets:
		var row_btn: Button = w.get("button", null) as Button
		if row_btn != null and is_instance_valid(row_btn):
			_apply_row_button_theme(row_btn, _active_faction_id)


func _apply_row_button_theme(btn: Button, fid: StringName) -> void:
	var pal: Dictionary = FactionHudTheme.get_palette(fid)
	var is_brutal: bool = (pal["style"] == &"brutalist")
	var accent: Color = pal["accent"] as Color
	var norm: StyleBoxFlat = StyleBoxFlat.new()
	var hov: StyleBoxFlat = StyleBoxFlat.new()
	if is_brutal:
		norm.bg_color = pal["bg_row"] as Color
		norm.border_width_left = 3
		norm.border_width_top = 1
		norm.border_width_right = 1
		norm.border_width_bottom = 1
		norm.border_color = Color(accent.r, accent.g, accent.b, 0.90)
		norm.set_corner_radius_all(0)
		hov.bg_color = pal["bg_hover"] as Color
		hov.border_width_left = 3
		hov.border_width_top = 1
		hov.border_width_right = 1
		hov.border_width_bottom = 1
		hov.border_color = pal["inner_trim"] as Color
		hov.set_corner_radius_all(0)
	else:
		norm.bg_color = pal["bg_row"] as Color
		norm.set_border_width_all(1)
		norm.border_color = Color(accent.r, accent.g, accent.b, 0.36)
		norm.set_corner_radius_all(4)
		hov.bg_color = pal["bg_hover"] as Color
		hov.set_border_width_all(1)
		hov.border_color = Color(accent.r, accent.g, accent.b, 0.85)
		hov.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("focus", hov)


func _resolve_selection_controller() -> void:
	if is_inside_tree():
		_selection_controller = get_tree().get_first_node_in_group("selection_controller") as SelectionController


func _process(delta: float) -> void:
	var real_dt: float = minf(delta / maxf(0.1, Engine.time_scale), 0.05)
	_pulse_time += real_dt
	_refresh_timer += real_dt
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_refresh_ticker()


func _on_toggle_collapse() -> void:
	_collapsed = not _collapsed
	if AudioManager != null:
		AudioManager.play_ui_click()
	if btn_collapse != null:
		btn_collapse.text = "+" if _collapsed else "−"
	if rows_container != null:
		rows_container.visible = not _collapsed
	if overflow_label != null and _collapsed:
		overflow_label.visible = false
	_refresh_ticker()


func _refresh_ticker() -> void:
	if not is_inside_tree() or ticker_panel == null:
		return

	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	if local_team < 0:
		ticker_panel.visible = false
		return
	var active_entries: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or not b.is_constructed or int(b.team) != local_team:
			continue
		if b.production_component == null:
			continue
		var q_size: int = b.production_component.get_queue_size()
		if q_size <= 0:
			continue
		var status: Dictionary = b.get_active_training_status()
		if status.is_empty():
			continue
		active_entries.append({
			"building": b,
			"building_id": b.get_instance_id(),
			"queue_size": q_size,
			"status": status,
		})

	if active_entries.is_empty():
		ticker_panel.visible = false
		return

	active_entries.sort_custom(func(a: Dictionary, b_item: Dictionary) -> bool:
		return int(a["building_id"]) < int(b_item["building_id"])
	)

	ticker_panel.visible = true
	if header_label != null:
		header_label.text = "PRODUCTION (%d)" % active_entries.size()

	if _collapsed:
		if rows_container != null:
			rows_container.visible = false
		if overflow_label != null:
			overflow_label.visible = false
		return

	if rows_container != null:
		rows_container.visible = true

	var display_count: int = mini(active_entries.size(), MAX_VISIBLE_ROWS)
	_ensure_row_count(display_count)

	for i: int in range(display_count):
		var entry: Dictionary = active_entries[i]
		var b: Building = entry["building"] as Building
		var q_size: int = int(entry["queue_size"])
		var st: Dictionary = entry["status"] as Dictionary
		var kind: StringName = st.get("kind", ProductionComponent.KIND_UNIT)
		var is_upgrade: bool = (kind == ProductionComponent.KIND_UPGRADE)
		var raw_name: String = String(st.get("display_name", "Item"))
		var short_name: String = _shorten_name(raw_name)
		var batch_cnt: int = int(st.get("batch_count", 1))
		var progress: float = clampf(float(st.get("progress", 0.0)), 0.0, 1.0)
		var pct: int = int(round(progress * 100.0))

		var widget: Dictionary = _row_widgets[i]
		widget["building"] = b
		var title_lbl: Label = widget["title"] as Label
		var pct_lbl: Label = widget["pct"] as Label
		var bar: ProgressBar = widget["bar"] as ProgressBar
		var fill_style: StyleBoxFlat = widget["fill"] as StyleBoxFlat

		var prefix: String = "[UPG] " if is_upgrade else ""
		var batch_tag: String = (" x%d" % batch_cnt) if (not is_upgrade and batch_cnt > 1) else ""
		var q_tag: String = (" (+%d)" % (q_size - 1)) if q_size > 1 else ""
		var is_unpowered: bool = b.requires_power_grid and not b.is_powered
		var is_oc: bool = b.is_overclocked() and not is_unpowered
		var oc_tag: String = " [2x]" if is_oc else ""
		title_lbl.text = "%s%s%s%s%s" % [prefix, short_name, batch_tag, q_tag, oc_tag]
		if is_unpowered:
			title_lbl.modulate = Color(1.0, 0.54, 0.42, 1.0)
			pct_lbl.text = "PAUSED"
			pct_lbl.add_theme_color_override("font_color", Color(1.0, 0.40, 0.30, 1.0))
		else:
			title_lbl.modulate = Color(1.0, 0.88, 0.42, 1.0) if (is_upgrade or is_oc) else Color(0.92, 0.96, 0.98, 1.0)
			pct_lbl.text = "%d%%" % pct
			pct_lbl.add_theme_color_override("font_color", Color(0.56, 0.90, 0.96, 0.95))
		bar.value = progress * 100.0
		if fill_style != null:
			if is_unpowered:
				var up_p: float = 0.5 + 0.5 * sin(_pulse_time * 6.0)
				fill_style.bg_color = Color(0.96, 0.48, 0.20, 0.96).lerp(Color(1.0, 0.28, 0.24, 0.98), up_p)
			elif is_oc:
				var oc_p: float = 0.5 + 0.5 * sin(_pulse_time * 8.0)
				fill_style.bg_color = Color(1.0, 0.624, 0.110, 1.0).lerp(Color(1.0, 0.86, 0.40, 1.0), oc_p * 0.55)
			elif is_upgrade:
				fill_style.bg_color = Color(1.0, 0.80, 0.28, 1.0)
			else:
				fill_style.bg_color = _faction_accent

	if overflow_label != null:
		var hidden_count: int = active_entries.size() - display_count
		overflow_label.visible = hidden_count > 0
		if hidden_count > 0:
			overflow_label.text = "+%d more producing..." % hidden_count


func _ensure_row_count(target_count: int) -> void:
	if rows_container == null:
		return
	while _row_widgets.size() < target_count:
		var idx: int = _row_widgets.size()
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(204.0, 32.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = "LMB Select & Center • Shift+LMB All of Type • RMB Focus Camera"
		btn.add_to_group("blocks_edge_pan")
		_apply_row_button_theme(btn, _active_faction_id)

		var margin: MarginContainer = MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_top", 3)
		margin.add_theme_constant_override("margin_bottom", 3)
		btn.add_child(margin)

		var vb: VBoxContainer = VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 3)
		margin.add_child(vb)

		var top_row: HBoxContainer = HBoxContainer.new()
		top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_row.add_theme_constant_override("separation", 4)
		vb.add_child(top_row)

		var title_lbl: Label = Label.new()
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_lbl.clip_text = true
		title_lbl.add_theme_font_size_override("font_size", 11)
		top_row.add_child(title_lbl)

		var pct_lbl: Label = Label.new()
		pct_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pct_lbl.add_theme_font_size_override("font_size", 10)
		pct_lbl.add_theme_color_override("font_color", Color(0.56, 0.90, 0.96, 0.95))
		top_row.add_child(pct_lbl)

		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0.0, 5.0)
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var bg_style: StyleBoxFlat = StyleBoxFlat.new()
		bg_style.bg_color = Color(0.05, 0.09, 0.13, 0.95)
		bg_style.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg_style)

		var fill_style: StyleBoxFlat = StyleBoxFlat.new()
		fill_style.bg_color = Color(0.24, 0.96, 0.86, 1.0)
		fill_style.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill_style)
		vb.add_child(bar)

		var captured_idx: int = idx
		btn.pressed.connect(func() -> void:
			_on_row_clicked(captured_idx)
		)
		btn.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
					_on_row_right_clicked(captured_idx)
					btn.accept_event()
		)

		rows_container.add_child(btn)
		_row_widgets.append({
			"button": btn,
			"title": title_lbl,
			"pct": pct_lbl,
			"bar": bar,
			"fill": fill_style,
			"building": null,
		})

	for i: int in range(_row_widgets.size()):
		var btn_item: Button = _row_widgets[i]["button"] as Button
		if btn_item != null:
			btn_item.visible = (i < target_count)


func _on_row_clicked(row_index: int) -> void:
	if row_index < 0 or row_index >= _row_widgets.size():
		return
	var b: Building = _row_widgets[row_index].get("building", null) as Building
	if b == null or not is_instance_valid(b) or b.is_destroyed:
		return
	if _selection_controller == null:
		_resolve_selection_controller()
	if _selection_controller == null:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_selection_controller.select_buildings_of_type(b.building_type_id, false)
	else:
		_selection_controller.select_single_entity(b, true)


func _on_row_right_clicked(row_index: int) -> void:
	if row_index < 0 or row_index >= _row_widgets.size():
		return
	var b: Building = _row_widgets[row_index].get("building", null) as Building
	if b == null or not is_instance_valid(b) or b.is_destroyed:
		return
	if _selection_controller == null:
		_resolve_selection_controller()
	if _selection_controller == null:
		return
	_selection_controller.focus_camera_on_entity(b)


func _shorten_name(full_name: String) -> String:
	return (
		full_name
		.replace("Worker Drone", "Worker")
		.replace("Systems Engineer", "Engineer")
		.replace("Silica Harvester", "Harvester")
		.replace("Clone Trooper", "Clone")
		.replace("Signal Jammer", "Jammer")
		.replace("Goliath Frame", "Goliath")
		.replace("Chrysalis Mortar", "Mortar")
		.replace("Batch Efficiency", "Batch Eff.")
		.replace("Adrenal Potency", "Adrenal Pot.")
		.replace("Compute Overdrive", "Overdrive")
		.replace("Bulwark Automaton", "Bulwark")
		.replace("Picket Drone", "Picket")
		.replace("Rail-Sentinel", "Rail-Snt")
		.replace("Aegis Relay", "Aegis")
		.replace("Anvil Siege-Walker", "Anvil")
		.replace("Monolith Dreadnought", "Dreadnought")
		.replace("Null-Grid Projector", "Null-Grid")
		.replace("Hardened Plating", "Plating")
		.replace("Rapid Capacitors", "Capacitors")
		.replace("Hyper-Velocity Rails", "HV Rails")
	)
