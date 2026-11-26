class_name SpectatorComparisonBar
extends CanvasLayer

const REFRESH_INTERVAL: float = 0.35

const UPGRADE_DISPLAY_NAMES: Dictionary = {
	&"batch_efficiency": "Batch Efficiency",
	&"adrenal_potency": "Adrenal Potency",
	&"compute_overdrive": "Compute Overdrive",
	&"monolith_hardened_plating": "Hardened Plating",
	&"monolith_rapid_capacitors": "Rapid Capacitors",
	&"monolith_hyper_velocity_rails": "Hyper-Velocity Rails",
}

@onready var root_control: Control = %RootControl
@onready var main_panel: PanelContainer = %MainPanel
@onready var content_host: HBoxContainer = %ContentHost

var _refresh_timer: float = 0.0
var _built_team_ids: Array[int] = []
var _is_two_player_layout: bool = true
var _team_widgets: Dictionary = {} # team_id -> Dictionary of label/button refs
var _tug_bar: ArmyTugOfWarBar = null


func _ready() -> void:
	layer = 3
	add_to_group("spectator_comparison_bar")
	if main_panel != null:
		main_panel.add_to_group("blocks_edge_pan")
		main_panel.add_theme_stylebox_override("panel", FactionHudTheme.make_panel_style(&"spectator", true))
		FactionHudTheme.attach_frame_overlay(main_panel, &"spectator", &"top_bar")
	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(_on_teams_reconfigured):
		TeamManager.teams_reconfigured.connect(_on_teams_reconfigured)
	_sync_visibility_and_layout()
	_refresh_telemetry()


func _process(delta: float) -> void:
	var should_show: bool = _should_be_visible()
	if root_control != null and root_control.visible != should_show:
		root_control.visible = should_show
	if not should_show:
		return
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_telemetry()


func _should_be_visible() -> bool:
	if TeamManager == null or not TeamManager.is_spectator_mode():
		return false
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null and (match_mgr.is_match_over or match_mgr.sandbox_mode_active):
			return false
	return true


func _on_teams_reconfigured(_mode: StringName = &"") -> void:
	_sync_visibility_and_layout()
	_refresh_telemetry()


func _sync_visibility_and_layout() -> void:
	var should_show: bool = _should_be_visible()
	if root_control != null:
		root_control.visible = should_show
	if not should_show or content_host == null:
		return

	var active_teams: Array[int] = [0, 1]
	if TeamManager != null:
		active_teams = TeamManager.get_active_teams()
	if active_teams == _built_team_ids and not _team_widgets.is_empty():
		return

	_built_team_ids = active_teams.duplicate()
	_team_widgets.clear()
	_tug_bar = null
	for child: Node in content_host.get_children():
		child.queue_free()

	_is_two_player_layout = (active_teams.size() <= 2)
	if _is_two_player_layout and active_teams.size() >= 2:
		_build_two_player_layout(active_teams[0], active_teams[1])
	else:
		_build_multi_player_layout(active_teams)


func _build_two_player_layout(left_tid: int, right_tid: int) -> void:
	content_host.add_theme_constant_override("separation", 8)
	var left_wing: Control = _create_2p_wing(left_tid, false)
	content_host.add_child(left_wing)

	_tug_bar = ArmyTugOfWarBar.new()
	_tug_bar.custom_minimum_size = Vector2(148.0, 38.0)
	_tug_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tug_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tug_bar.left_color = TeamManager.get_team_color(left_tid) if TeamManager != null else Color(0.20, 0.96, 0.86, 1.0)
	_tug_bar.right_color = TeamManager.get_team_color(right_tid) if TeamManager != null else Color(1.0, 0.34, 0.26, 1.0)
	content_host.add_child(_tug_bar)

	var right_wing: Control = _create_2p_wing(right_tid, true)
	content_host.add_child(right_wing)


func _create_2p_wing(tid: int, mirrored: bool) -> Control:
	var col: Color = TeamManager.get_team_color(tid) if TeamManager != null else Color(0.24, 0.96, 0.88, 1.0)
	var btn: Button = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(262.0, 42.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "Click to jump camera to %s Command Hub" % _get_team_header_label(tid)
	btn.pressed.connect(_on_team_wing_clicked.bind(tid))
	btn.add_to_group("blocks_edge_pan")

	var bg_sb: StyleBoxFlat = StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.06, 0.09, 0.14, 0.72)
	bg_sb.border_color = Color(col.r, col.g, col.b, 0.45)
	bg_sb.set_border_width_all(1)
	bg_sb.set_corner_radius_all(3)
	bg_sb.content_margin_left = 6.0
	bg_sb.content_margin_right = 6.0
	bg_sb.content_margin_top = 3.0
	bg_sb.content_margin_bottom = 3.0
	btn.add_theme_stylebox_override("normal", bg_sb)

	var hover_sb: StyleBoxFlat = bg_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.10, 0.15, 0.22, 0.90)
	hover_sb.border_color = Color(col.r, col.g, col.b, 0.92)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 4.0
	hbox.offset_right = -4.0
	hbox.offset_top = 2.0
	hbox.offset_bottom = -2.0
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)
	btn.add_child(hbox)

	var stripe: ColorRect = ColorRect.new()
	stripe.custom_minimum_size = Vector2(4.0, 32.0)
	stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stripe.color = col
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 6)

	var name_lbl: Label = Label.new()
	name_lbl.text = _get_team_header_label(tid)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", col.lightened(0.12))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var upg_lbl: Label = Label.new()
	upg_lbl.text = "UPG 0/3"
	upg_lbl.add_theme_font_size_override("font_size", 10)
	upg_lbl.add_theme_color_override("font_color", Color(0.76, 0.88, 0.96, 0.90))
	upg_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	upg_lbl.tooltip_text = "Upgrades: None"

	if mirrored:
		top_row.add_child(upg_lbl)
		top_row.add_child(name_lbl)
	else:
		top_row.add_child(name_lbl)
		top_row.add_child(upg_lbl)

	var metrics_lbl: Label = Label.new()
	metrics_lbl.text = "B 0  S 0  C 0  •  BW 0/0  •  ARMY 0"
	metrics_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	metrics_lbl.add_theme_font_size_override("font_size", 10)
	metrics_lbl.add_theme_color_override("font_color", Color(0.86, 0.94, 0.98, 0.92))
	metrics_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	vbox.add_child(top_row)
	vbox.add_child(metrics_lbl)

	if mirrored:
		hbox.add_child(vbox)
		hbox.add_child(stripe)
	else:
		hbox.add_child(stripe)
		hbox.add_child(vbox)

	_team_widgets[tid] = {
		"root": btn,
		"name_lbl": name_lbl,
		"upg_lbl": upg_lbl,
		"metrics_lbl": metrics_lbl,
		"color": col,
	}
	return btn


func _build_multi_player_layout(active_teams: Array[int]) -> void:
	content_host.add_theme_constant_override("separation", 6)
	var card_w: float = 166.0 if active_teams.size() >= 4 else 222.0
	for tid: int in active_teams:
		var col: Color = TeamManager.get_team_color(tid) if TeamManager != null else Color(0.24, 0.96, 0.88, 1.0)
		var btn: Button = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(card_w, 42.0)
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = true
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = "Click to jump camera to %s Command Hub" % _get_team_header_label(tid)
		btn.pressed.connect(_on_team_wing_clicked.bind(tid))
		btn.add_to_group("blocks_edge_pan")

		var bg_sb: StyleBoxFlat = StyleBoxFlat.new()
		bg_sb.bg_color = Color(0.06, 0.09, 0.14, 0.74)
		bg_sb.border_color = Color(col.r, col.g, col.b, 0.48)
		bg_sb.set_border_width_all(1)
		bg_sb.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", bg_sb)

		var hover_sb: StyleBoxFlat = bg_sb.duplicate() as StyleBoxFlat
		hover_sb.bg_color = Color(0.10, 0.15, 0.22, 0.92)
		hover_sb.border_color = Color(col.r, col.g, col.b, 0.92)
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.add_theme_stylebox_override("pressed", hover_sb)

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 5.0
		vbox.offset_right = -5.0
		vbox.offset_top = 3.0
		vbox.offset_bottom = -3.0
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 2)
		btn.add_child(vbox)

		var top_bar: ColorRect = ColorRect.new()
		top_bar.custom_minimum_size = Vector2(0.0, 2.5)
		top_bar.color = col
		top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(top_bar)

		var header_row: HBoxContainer = HBoxContainer.new()
		header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_row.add_theme_constant_override("separation", 4)

		var name_lbl: Label = Label.new()
		name_lbl.text = _get_team_header_label(tid, true)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", col.lightened(0.12))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var upg_lbl: Label = Label.new()
		upg_lbl.text = "U:0/3"
		upg_lbl.add_theme_font_size_override("font_size", 9)
		upg_lbl.add_theme_color_override("font_color", Color(0.76, 0.88, 0.96, 0.90))
		upg_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		upg_lbl.tooltip_text = "Upgrades: None"

		header_row.add_child(name_lbl)
		header_row.add_child(upg_lbl)
		vbox.add_child(header_row)

		var metrics_lbl: Label = Label.new()
		metrics_lbl.text = "BW 0/0 • ARMY 0 • R 0"
		metrics_lbl.add_theme_font_size_override("font_size", 9)
		metrics_lbl.add_theme_color_override("font_color", Color(0.84, 0.92, 0.98, 0.92))
		metrics_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(metrics_lbl)

		content_host.add_child(btn)
		_team_widgets[tid] = {
			"root": btn,
			"name_lbl": name_lbl,
			"upg_lbl": upg_lbl,
			"metrics_lbl": metrics_lbl,
			"color": col,
		}


func _get_team_header_label(tid: int, compact: bool = false) -> String:
	var short_tag: String = TeamManager.get_team_short_label(tid, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("AI-%d" % (tid + 1))
	var fac_id: StringName = TeamManager.get_team_faction(tid) if (TeamManager != null and TeamManager.has_method("get_team_faction")) else &"genesis_v2"
	var fac_code: String = "GEN-V2"
	if fac_id == &"monolith_os":
		fac_code = "MON-OS"
	elif fac_id != &"genesis_v2" and fac_id != &"":
		fac_code = String(fac_id).to_upper().substr(0, 6)
	if compact:
		return "%s %s" % [short_tag, fac_code]
	return "%s // %s" % [short_tag, fac_code]


func _format_upgrade_tooltip(upgrades: Array[StringName]) -> String:
	if upgrades.is_empty():
		return "Researched Upgrades: None"
	var lines: PackedStringArray = PackedStringArray()
	for uid: StringName in upgrades:
		if UPGRADE_DISPLAY_NAMES.has(uid):
			lines.append("• " + String(UPGRADE_DISPLAY_NAMES[uid]))
		else:
			lines.append("• " + String(uid).replace("_", " ").capitalize())
	return "Researched Upgrades (%d/3):\n%s" % [upgrades.size(), "\n".join(lines)]


func _refresh_telemetry() -> void:
	if not is_inside_tree() or not _should_be_visible():
		return
	_sync_visibility_and_layout()
	if _team_widgets.is_empty():
		return

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var army_values: Dictionary = {}
	var alive_buildings: Dictionary = {}
	for tid: int in _built_team_ids:
		army_values[tid] = 0
		alive_buildings[tid] = 0

	for u_node: Node in get_tree().get_nodes_in_group("units"):
		if not (u_node is Unit) or not is_instance_valid(u_node):
			continue
		var u: Unit = u_node as Unit
		if u.is_dead or u.is_queued_for_deletion():
			continue
		var ut: int = int(u.team)
		if not army_values.has(ut):
			continue
		var u_val: int = 50
		if u.data != null:
			u_val = u.data.biomass_cost + u.data.silica_cost + u.data.compute_cost
		army_values[ut] = int(army_values[ut]) + maxi(25, u_val)

	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (b_node is Building) or not is_instance_valid(b_node):
			continue
		var b: Building = b_node as Building
		if b.is_destroyed or b.is_queued_for_deletion():
			continue
		var bt: int = int(b.team)
		if alive_buildings.has(bt):
			alive_buildings[bt] = int(alive_buildings[bt]) + 1

	for tid: int in _built_team_ids:
		var w: Dictionary = _team_widgets.get(tid, {}) as Dictionary
		if w.is_empty():
			continue
		var root_btn: Button = w.get("root", null) as Button
		var name_lbl: Label = w.get("name_lbl", null) as Label
		var upg_lbl: Label = w.get("upg_lbl", null) as Label
		var metrics_lbl: Label = w.get("metrics_lbl", null) as Label
		var col: Color = w.get("color", Color.WHITE) as Color

		var bio: int = econ.get_resource(tid, EconomyManager.RESOURCE_BIOMASS) if econ != null else 0
		var sil: int = econ.get_resource(tid, EconomyManager.RESOURCE_SILICA) if econ != null else 0
		var cmp: int = econ.get_resource(tid, EconomyManager.RESOURCE_COMPUTE) if econ != null else 0
		var bw_used: int = econ.get_bandwidth_used(tid) if econ != null else 0
		var bw_cap: int = econ.get_bandwidth_cap(tid) if econ != null else 0
		var army_val: int = int(army_values.get(tid, 0))
		var is_elim: bool = int(alive_buildings.get(tid, 0)) <= 0 and army_val <= 0

		var upgs: Array[StringName] = []
		if econ != null and econ.upgrade_manager != null:
			upgs = econ.upgrade_manager.get_researched_upgrades(tid)

		if name_lbl != null:
			var base_hdr: String = _get_team_header_label(tid, not _is_two_player_layout)
			name_lbl.text = ("%s [ELIM]" % base_hdr) if is_elim else base_hdr
			name_lbl.add_theme_color_override("font_color", Color(0.56, 0.62, 0.68, 0.72) if is_elim else col.lightened(0.12))

		if upg_lbl != null:
			upg_lbl.text = ("UPG %d/3" % upgs.size()) if _is_two_player_layout else ("U:%d/3" % upgs.size())
			upg_lbl.tooltip_text = _format_upgrade_tooltip(upgs)
			upg_lbl.add_theme_color_override(
				"font_color",
				Color(1.0, 0.84, 0.34, 0.98) if upgs.size() > 0 else Color(0.68, 0.78, 0.86, 0.75)
			)

		if metrics_lbl != null:
			if _is_two_player_layout:
				metrics_lbl.text = "B %d  S %d  C %d  •  BW %d/%d  •  ARMY %s" % [
					bio,
					sil,
					cmp,
					bw_used,
					bw_cap,
					InspectionHelper.format_number(army_val),
				]
			else:
				var total_res: int = bio + sil + cmp
				metrics_lbl.text = "BW %d/%d • A:%s • R:%s" % [
					bw_used,
					bw_cap,
					InspectionHelper.format_number(army_val),
					InspectionHelper.format_number(total_res),
				]

		if root_btn != null:
			root_btn.modulate = Color(0.65, 0.68, 0.72, 0.62) if is_elim else Color.WHITE

	if _is_two_player_layout and _tug_bar != null and _built_team_ids.size() >= 2:
		var lt: int = _built_team_ids[0]
		var rt: int = _built_team_ids[1]
		_tug_bar.left_value = int(army_values.get(lt, 0))
		_tug_bar.right_value = int(army_values.get(rt, 0))
		_tug_bar.left_color = TeamManager.get_team_color(lt) if TeamManager != null else _tug_bar.left_color
		_tug_bar.right_color = TeamManager.get_team_color(rt) if TeamManager != null else _tug_bar.right_color
		_tug_bar.queue_redraw()


func _on_team_wing_clicked(tid: int) -> void:
	if not is_inside_tree():
		return
	if AudioManager != null:
		AudioManager.play_ui_click()
	var target_pos: Vector2 = _find_team_focus_position(tid)
	if not target_pos.is_finite():
		return
	var cam: RTSCamera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
	if cam != null:
		cam.smooth_center_on(target_pos)


func _find_team_focus_position(tid: int) -> Vector2:
	var fallback_bldg: Vector2 = Vector2.INF
	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (b_node is Building) or not is_instance_valid(b_node):
			continue
		var b: Building = b_node as Building
		if b.is_destroyed or b.is_queued_for_deletion() or int(b.team) != tid:
			continue
		if b.is_command_hub():
			return b.global_position
		if not fallback_bldg.is_finite():
			fallback_bldg = b.global_position
	if fallback_bldg.is_finite():
		return fallback_bldg
	for u_node: Node in get_tree().get_nodes_in_group("units"):
		if not (u_node is Unit) or not is_instance_valid(u_node):
			continue
		var u: Unit = u_node as Unit
		if not u.is_dead and not u.is_queued_for_deletion() and int(u.team) == tid:
			return u.global_position
	return Vector2.INF


class ArmyTugOfWarBar extends Control:
	var left_value: int = 0
	var right_value: int = 0
	var left_color: Color = Color(0.20, 0.96, 0.86, 1.0)
	var right_color: Color = Color(1.0, 0.34, 0.26, 1.0)

	func _draw() -> void:
		var sz: Vector2 = size
		if sz.x <= 8.0 or sz.y <= 8.0:
			return
		var font: Font = ThemeDB.fallback_font
		var title: String = "ARMY VALUE"
		var title_sz: Vector2 = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		draw_string(
			font,
			Vector2((sz.x - title_sz.x) * 0.5, 10.0),
			title,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			9,
			Color(0.68, 0.82, 0.90, 0.88)
		)

		var bar_y: float = 14.0
		var bar_h: float = 9.0
		var bar_rect: Rect2 = Rect2(2.0, bar_y, sz.x - 4.0, bar_h)
		draw_rect(bar_rect, Color(0.04, 0.06, 0.10, 0.92), true)

		var total: float = float(left_value + right_value)
		var left_ratio: float = 0.5 if total <= 0.01 else clampf(float(left_value) / total, 0.04, 0.96)
		var split_x: float = bar_rect.position.x + bar_rect.size.x * left_ratio

		draw_rect(
			Rect2(bar_rect.position.x, bar_y, split_x - bar_rect.position.x, bar_h),
			Color(left_color.r, left_color.g, left_color.b, 0.88),
			true
		)
		draw_rect(
			Rect2(split_x, bar_y, bar_rect.end.x - split_x, bar_h),
			Color(right_color.r, right_color.g, right_color.b, 0.88),
			true
		)
		# Crisp split indicator + 50% midpoint tick
		var mid_x: float = bar_rect.position.x + bar_rect.size.x * 0.5
		draw_line(Vector2(mid_x, bar_y - 1.5), Vector2(mid_x, bar_y + bar_h + 1.5), Color(0.90, 0.96, 1.0, 0.35), 1.0, true)
		draw_line(Vector2(split_x, bar_y - 1.0), Vector2(split_x, bar_y + bar_h + 1.0), Color(0.98, 0.99, 1.0, 0.95), 1.6, true)
		draw_rect(bar_rect, Color(0.42, 0.72, 0.88, 0.45), false, 1.0)

		var left_str: String = InspectionHelper.format_number(left_value)
		var right_str: String = InspectionHelper.format_number(right_value)
		var r_sz: Vector2 = font.get_string_size(right_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		draw_string(font, Vector2(3.0, sz.y - 2.0), left_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, left_color.lightened(0.18))
		draw_string(font, Vector2(sz.x - r_sz.x - 3.0, sz.y - 2.0), right_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, right_color.lightened(0.18))
