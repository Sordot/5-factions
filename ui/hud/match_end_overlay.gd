class_name MatchEndOverlay
extends CanvasLayer

@onready var root_control: Control = %RootControl
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var duration_value: Label = %DurationValue
@onready var winner_value: Label = %WinnerValue
@onready var mutators_label: Label = %MutatorsLabel
@onready var btn_tab_summary: Button = %BtnTabSummary
@onready var btn_tab_timeline: Button = %BtnTabTimeline
@onready var scoreboard_grid: GridContainer = %ScoreboardGrid
@onready var timeline_tab_box: VBoxContainer = %TimelineTabBox
@onready var btn_metric_army: Button = %BtnMetricArmy
@onready var btn_metric_income: Button = %BtnMetricIncome
@onready var btn_metric_units: Button = %BtnMetricUnits
@onready var timeline_graph: TimelineGraph = %TimelineGraph
@onready var btn_view_battlefield: Button = %BtnViewBattlefield
@onready var btn_play_again: Button = %BtnPlayAgain
@onready var btn_main_menu: Button = %BtnMainMenu
@onready var btn_sandbox_mode: Button = %BtnSandboxMode
@onready var inspection_banner: Control = %InspectionBanner
@onready var btn_toggle_heatmap: Button = %BtnToggleHeatmap
@onready var btn_return_scoreboard: Button = %BtnReturnScoreboard
@onready var btn_banner_rematch: Button = %BtnBannerRematch
@onready var btn_banner_main_menu: Button = %BtnBannerMainMenu

var _active_tab: StringName = &"summary"
var _active_metric: StringName = TimelineGraph.METRIC_ARMY_VALUE
var _is_inspecting_battlefield: bool = false
var _is_mode_result_active: bool = false
var _active_result_mode: StringName = &""
var _mode_result_box: VBoxContainer = null
var _medal_emblem: MedalEmblemControl = null
var _new_best_label: Label = null
var _mode_stats_grid: GridContainer = null
var _btn_continue_endless: Button = null
var _btn_next_drill: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("match_end_overlay")
	layer = 10
	if root_control != null:
		root_control.visible = false
	if inspection_banner != null:
		inspection_banner.visible = false
		inspection_banner.add_to_group("blocks_edge_pan")
	if btn_tab_summary != null:
		btn_tab_summary.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_set_active_tab(&"summary")
		)
	if btn_tab_timeline != null:
		btn_tab_timeline.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_set_active_tab(&"timeline")
		)
	if btn_metric_army != null:
		btn_metric_army.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_set_active_metric(TimelineGraph.METRIC_ARMY_VALUE)
		)
	if btn_metric_income != null:
		btn_metric_income.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_set_active_metric(TimelineGraph.METRIC_INCOME_RATE)
		)
	if btn_metric_units != null:
		btn_metric_units.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_set_active_metric(TimelineGraph.METRIC_UNIT_COUNT)
		)
	if btn_view_battlefield != null:
		btn_view_battlefield.pressed.connect(_on_view_battlefield_pressed)
	if btn_play_again != null:
		btn_play_again.pressed.connect(_on_play_again_pressed)
	if btn_main_menu != null:
		btn_main_menu.pressed.connect(_on_main_menu_pressed)
	if btn_sandbox_mode != null:
		btn_sandbox_mode.pressed.connect(_on_sandbox_mode_pressed)
	if btn_toggle_heatmap != null:
		btn_toggle_heatmap.pressed.connect(_on_toggle_heatmap_pressed)
		_sync_heatmap_button(false)
	if btn_return_scoreboard != null:
		btn_return_scoreboard.pressed.connect(return_to_scoreboard)
	if btn_banner_rematch != null:
		btn_banner_rematch.pressed.connect(_on_play_again_pressed)
	if btn_banner_main_menu != null:
		btn_banner_main_menu.pressed.connect(_on_main_menu_pressed)
	_set_active_tab(&"summary")
	_set_active_metric(TimelineGraph.METRIC_ARMY_VALUE)
	_build_mode_result_widgets()


func _build_mode_result_widgets() -> void:
	var modal_vbox: VBoxContainer = get_node_or_null("RootControl/CenterContainer/ModalPanel/VBox") as VBoxContainer
	if modal_vbox == null:
		return

	_mode_result_box = VBoxContainer.new()
	_mode_result_box.name = "ModeResultBox"
	_mode_result_box.visible = false
	_mode_result_box.add_theme_constant_override("separation", 6)

	var emblem_row: HBoxContainer = HBoxContainer.new()
	emblem_row.alignment = BoxContainer.ALIGNMENT_CENTER
	emblem_row.add_theme_constant_override("separation", 12)
	_mode_result_box.add_child(emblem_row)

	_medal_emblem = MedalEmblemControl.new()
	_medal_emblem.custom_minimum_size = Vector2(76.0, 76.0)
	emblem_row.add_child(_medal_emblem)

	_new_best_label = Label.new()
	_new_best_label.visible = false
	_new_best_label.text = "★ NEW PERSONAL BEST!"
	_new_best_label.add_theme_font_size_override("font_size", 13)
	_new_best_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.28, 1.0))
	emblem_row.add_child(_new_best_label)

	_mode_stats_grid = GridContainer.new()
	_mode_stats_grid.columns = 2
	_mode_stats_grid.add_theme_constant_override("h_separation", 24)
	_mode_stats_grid.add_theme_constant_override("v_separation", 4)
	_mode_result_box.add_child(_mode_stats_grid)

	var grid_idx: int = scoreboard_grid.get_index() if scoreboard_grid != null else modal_vbox.get_child_count()
	modal_vbox.add_child(_mode_result_box)
	modal_vbox.move_child(_mode_result_box, grid_idx)

	var btn_row: HBoxContainer = get_node_or_null("RootControl/CenterContainer/ModalPanel/VBox/ButtonRow") as HBoxContainer
	if btn_row != null:
		_btn_continue_endless = Button.new()
		_btn_continue_endless.visible = false
		_btn_continue_endless.custom_minimum_size = Vector2(148.0, 32.0)
		_btn_continue_endless.focus_mode = Control.FOCUS_NONE
		_btn_continue_endless.text = "Continue Endless"
		_btn_continue_endless.modulate = Color(1.0, 0.82, 0.30, 1.0)
		_btn_continue_endless.pressed.connect(_on_continue_endless_pressed)
		btn_row.add_child(_btn_continue_endless)
		btn_row.move_child(_btn_continue_endless, 0)

		_btn_next_drill = Button.new()
		_btn_next_drill.visible = false
		_btn_next_drill.custom_minimum_size = Vector2(132.0, 32.0)
		_btn_next_drill.focus_mode = Control.FOCUS_NONE
		_btn_next_drill.text = "Next Drill"
		_btn_next_drill.modulate = Color(0.36, 0.98, 0.88, 1.0)
		_btn_next_drill.pressed.connect(_on_next_drill_pressed)
		btn_row.add_child(_btn_next_drill)
		btn_row.move_child(_btn_next_drill, 2)


func _on_continue_endless_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null and match_mgr.has_method("continue_holdout_endless"):
			match_mgr.call("continue_holdout_endless")


func _on_next_drill_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null and match_mgr.has_method("launch_next_gauntlet_drill"):
			match_mgr.call("launch_next_gauntlet_drill")


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _is_mode_result_active and is_summary_visible() and _active_result_mode == &"gauntlet":
		if event is InputEventKey:
			var r_ev: InputEventKey = event as InputEventKey
			if r_ev.pressed and r_ev.keycode == KEY_R:
				get_viewport().set_input_as_handled()
				_on_play_again_pressed()
				return
	if not _is_inspecting_battlefield:
		return
	if event.is_action_pressed("cmd_cancel"):
		get_viewport().set_input_as_handled()
		return_to_scoreboard()
	elif event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and kev.keycode == KEY_H:
			get_viewport().set_input_as_handled()
			_on_toggle_heatmap_pressed()


func _on_toggle_heatmap_pressed() -> void:
	if not _is_inspecting_battlefield or not is_inside_tree():
		return
	if AudioManager != null:
		AudioManager.play_ui_click()
	var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	var is_on: bool = false
	if match_mgr != null and match_mgr.has_method("toggle_post_match_heatmap"):
		is_on = bool(match_mgr.call("toggle_post_match_heatmap"))
	_sync_heatmap_button(is_on)


func _sync_heatmap_button(is_on: bool) -> void:
	if btn_toggle_heatmap == null:
		return
	btn_toggle_heatmap.text = "Heatmap: ON [H]" if is_on else "Heatmap: OFF [H]"
	btn_toggle_heatmap.modulate = Color(1.0, 0.72, 0.28, 1.0) if is_on else Color(0.76, 0.88, 0.94, 0.92)


func _set_active_tab(tab: StringName) -> void:
	_active_tab = tab
	var show_summary_tab: bool = (_active_tab == &"summary")
	if scoreboard_grid != null:
		scoreboard_grid.visible = show_summary_tab
	if timeline_tab_box != null:
		timeline_tab_box.visible = not show_summary_tab
	if btn_tab_summary != null:
		btn_tab_summary.modulate = Color(0.32, 1.0, 0.90, 1.0) if show_summary_tab else Color(0.68, 0.78, 0.84, 0.80)
	if btn_tab_timeline != null:
		btn_tab_timeline.modulate = Color(0.32, 1.0, 0.90, 1.0) if not show_summary_tab else Color(0.68, 0.78, 0.84, 0.80)


func _set_active_metric(metric_key: StringName) -> void:
	_active_metric = metric_key
	if timeline_graph != null:
		timeline_graph.set_metric(metric_key)
	if btn_metric_army != null:
		btn_metric_army.modulate = Color(0.32, 1.0, 0.90, 1.0) if metric_key == TimelineGraph.METRIC_ARMY_VALUE else Color(0.68, 0.78, 0.84, 0.80)
	if btn_metric_income != null:
		btn_metric_income.modulate = Color(1.0, 0.84, 0.34, 1.0) if metric_key == TimelineGraph.METRIC_INCOME_RATE else Color(0.68, 0.78, 0.84, 0.80)
	if btn_metric_units != null:
		btn_metric_units.modulate = Color(0.46, 0.86, 1.0, 1.0) if metric_key == TimelineGraph.METRIC_UNIT_COUNT else Color(0.68, 0.78, 0.84, 0.80)


func is_summary_visible() -> bool:
	return root_control != null and root_control.visible


func is_inspecting_battlefield() -> bool:
	return _is_inspecting_battlefield


func return_to_scoreboard() -> void:
	if not _is_inspecting_battlefield:
		return
	if AudioManager != null:
		AudioManager.play_ui_click()
	_is_inspecting_battlefield = false
	_sync_heatmap_button(false)
	if inspection_banner != null:
		inspection_banner.visible = false
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null:
			match_mgr.exit_post_match_inspection()
	if root_control != null:
		root_control.visible = true
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func show_summary(stats: Dictionary) -> void:
	_set_skirmish_mode_visibility(true)
	_is_mode_result_active = false
	_active_result_mode = &""
	Engine.time_scale = 1.0
	var is_victory: bool = bool(stats.get("is_victory", false))
	var is_spectator: bool = bool(stats.get("is_spectator", false))
	if AudioManager != null:
		AudioManager.play_sfx(&"match_victory" if is_victory else &"match_defeat", -2.0, 0.0)
	if title_label != null:
		title_label.text = "MATCH COMPLETE" if is_spectator else ("VICTORY" if is_victory else "DEFEAT")
		title_label.add_theme_color_override(
			"font_color",
			Color(0.22, 0.98, 0.90, 1.0) if is_victory else Color(1.0, 0.36, 0.30, 1.0)
		)
	if subtitle_label != null:
		var reason_txt: String = str(stats.get("reason", ""))
		var seed_tag: String = str(stats.get("procedural_seed_tag", ""))
		subtitle_label.text = ("%s  •  %s" % [reason_txt, seed_tag]) if not seed_tag.is_empty() else reason_txt
	if duration_value != null:
		duration_value.text = "DURATION: %s" % str(stats.get("duration_formatted", "00:00"))
	if winner_value != null:
		winner_value.text = "WINNER: %s" % str(stats.get("winner_label", "--"))

	if mutators_label != null:
		var mut_list: PackedStringArray = PackedStringArray()
		var raw_mut: Variant = stats.get("active_mutators", PackedStringArray())
		if raw_mut is PackedStringArray:
			mut_list = raw_mut as PackedStringArray
		elif raw_mut is Array:
			for m_item: Variant in raw_mut:
				mut_list.append(String(m_item))
		if mut_list.is_empty() and GameConfig != null and GameConfig.has_method("get_active_mutator_labels"):
			mut_list = GameConfig.get_active_mutator_labels()
		mutators_label.visible = not mut_list.is_empty()
		if not mut_list.is_empty():
			mutators_label.text = "MUTATORS: %s" % " • ".join(mut_list)

	_populate_scoreboard(stats)
	_populate_timeline_graph(stats)
	_set_active_tab(&"summary")

	if root_control != null:
		root_control.visible = true
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func _set_skirmish_mode_visibility(is_skirmish: bool) -> void:
	var meta_strip: Control = get_node_or_null("RootControl/CenterContainer/ModalPanel/VBox/MetaStrip") as Control
	var tab_row: Control = get_node_or_null("RootControl/CenterContainer/ModalPanel/VBox/TabRow") as Control
	if meta_strip != null:
		meta_strip.visible = is_skirmish
	if tab_row != null:
		tab_row.visible = is_skirmish
	if mutators_label != null and not is_skirmish:
		mutators_label.visible = false
	if scoreboard_grid != null:
		scoreboard_grid.visible = is_skirmish
	if timeline_tab_box != null and not is_skirmish:
		timeline_tab_box.visible = false
	if _mode_result_box != null:
		_mode_result_box.visible = not is_skirmish
	if btn_view_battlefield != null:
		btn_view_battlefield.visible = is_skirmish
	if btn_sandbox_mode != null:
		btn_sandbox_mode.visible = is_skirmish
	if _btn_continue_endless != null and is_skirmish:
		_btn_continue_endless.visible = false
	if _btn_next_drill != null and is_skirmish:
		_btn_next_drill.visible = false
	if btn_play_again != null and is_skirmish:
		btn_play_again.text = "Rematch"


func show_mode_summary(result: Dictionary) -> void:
	Engine.time_scale = 1.0
	_set_skirmish_mode_visibility(false)
	_is_mode_result_active = true
	_active_result_mode = result.get("mode", &"gauntlet") as StringName

	var is_victory: bool = bool(result.get("is_victory", false))
	var medal: int = int(result.get("medal", ModeRecords.Medal.NONE))
	var is_new_best: bool = bool(result.get("is_new_best", false))
	var can_endless: bool = bool(result.get("can_continue_endless", false))

	if AudioManager != null:
		AudioManager.play_sfx(&"match_victory" if is_victory else &"match_defeat", -2.0, 0.0)

	if title_label != null:
		title_label.text = String(result.get("title", "VICTORY" if is_victory else "DEFEAT"))
		var title_col: Color = ModeRecords.get_medal_color(medal) if medal > ModeRecords.Medal.NONE else (Color(0.22, 0.98, 0.90, 1.0) if is_victory else Color(1.0, 0.36, 0.30, 1.0))
		title_label.add_theme_color_override("font_color", title_col)
	if subtitle_label != null:
		subtitle_label.text = String(result.get("subtitle", ""))

	if _medal_emblem != null:
		_medal_emblem.medal = medal
		_medal_emblem.succeeded = is_victory
		_medal_emblem.queue_redraw()
	if _new_best_label != null:
		_new_best_label.visible = is_new_best

	if _mode_stats_grid != null:
		for child: Node in _mode_stats_grid.get_children():
			child.queue_free()
		var rows: Array = result.get("rows", []) as Array
		for raw_r: Variant in rows:
			if not (raw_r is Dictionary):
				continue
			var r_dict: Dictionary = raw_r as Dictionary
			var l_lbl: Label = Label.new()
			l_lbl.text = String(r_dict.get("label", ""))
			l_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l_lbl.add_theme_font_size_override("font_size", 12)
			l_lbl.add_theme_color_override("font_color", Color(0.68, 0.84, 0.90, 0.92))
			_mode_stats_grid.add_child(l_lbl)

			var v_lbl: Label = Label.new()
			v_lbl.text = String(r_dict.get("value", "--"))
			v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			v_lbl.add_theme_font_size_override("font_size", 12)
			v_lbl.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0, 0.96))
			_mode_stats_grid.add_child(v_lbl)

	if _btn_continue_endless != null:
		_btn_continue_endless.visible = can_endless
	if _btn_next_drill != null:
		_btn_next_drill.visible = (_active_result_mode == &"gauntlet")
	if btn_play_again != null:
		btn_play_again.text = "Retry Drill [R]" if _active_result_mode == &"gauntlet" else "Rematch"

	if root_control != null:
		root_control.visible = true
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func _populate_timeline_graph(stats: Dictionary) -> void:
	if timeline_graph == null:
		return
	var samples: Array = stats.get("timeline_samples", []) as Array
	var team_names: Dictionary = {}
	var team_colors: Dictionary = {}
	var teams_map: Dictionary = stats.get("teams", {}) as Dictionary
	var active_teams: Array = stats.get("active_teams", []) as Array
	if not active_teams.is_empty():
		for raw_t: Variant in active_teams:
			var tid: int = int(raw_t)
			var tdata: Dictionary = teams_map.get(tid, {}) as Dictionary
			team_names[tid] = String(tdata.get("short_label", TeamManager.get_team_short_label(tid, true) if TeamManager != null else ("P%d" % (tid + 1))))
			team_colors[tid] = tdata.get("color", TeamManager.get_team_color(tid) if TeamManager != null else Color(0.24, 0.96, 0.88, 1.0)) as Color
	else:
		var is_spec: bool = bool(stats.get("is_spectator", false))
		team_names[0] = "AI-01" if is_spec else "PLAYER"
		team_names[1] = "AI-02" if is_spec else "AI"
		if TeamManager != null:
			for tid: int in TeamManager.get_active_teams():
				if not team_names.has(tid):
					team_names[tid] = TeamManager.get_team_short_label(tid, true)
				team_colors[tid] = TeamManager.get_team_color(tid)
	timeline_graph.set_samples(samples, team_names, team_colors)
	_set_active_metric(_active_metric)


func _populate_scoreboard(stats: Dictionary) -> void:
	if scoreboard_grid == null:
		return
	for child: Node in scoreboard_grid.get_children():
		child.queue_free()

	var teams_map: Dictionary = stats.get("teams", {}) as Dictionary
	var raw_active: Array = stats.get("active_teams", []) as Array
	var team_ids: Array[int] = []
	for raw_t: Variant in raw_active:
		team_ids.append(int(raw_t))
	if team_ids.is_empty():
		team_ids = [0, 1]

	var team_entries: Array[Dictionary] = []
	for tid: int in team_ids:
		if teams_map.has(tid):
			team_entries.append(teams_map[tid] as Dictionary)
		elif tid == 0:
			var p: Dictionary = (stats.get("player", {}) as Dictionary).duplicate()
			p["short_label"] = "PLAYER" if not bool(stats.get("is_spectator", false)) else "AI-1"
			p["color"] = TeamManager.get_team_color(0) if TeamManager != null else Color(0.24, 0.98, 0.88, 1.0)
			team_entries.append(p)
		else:
			var e: Dictionary = (stats.get("enemy", {}) as Dictionary).duplicate()
			e["short_label"] = "AI-2"
			e["color"] = TeamManager.get_team_color(tid) if TeamManager != null else Color(1.0, 0.46, 0.36, 1.0)
			team_entries.append(e)

	scoreboard_grid.columns = 1 + team_entries.size()
	scoreboard_grid.add_theme_constant_override("h_separation", 12 if team_entries.size() >= 4 else 16)
	var col_min_w: float = 98.0 if team_entries.size() >= 4 else (118.0 if team_entries.size() == 3 else 140.0)

	# Header row
	var h_metric: Label = Label.new()
	h_metric.text = "TELEMETRY METRIC"
	h_metric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_metric.add_theme_font_size_override("font_size", 11)
	h_metric.add_theme_color_override("font_color", Color(0.46, 0.74, 0.84, 0.92))
	scoreboard_grid.add_child(h_metric)

	for entry: Dictionary in team_entries:
		var h_col: Label = Label.new()
		h_col.text = String(entry.get("short_label", "TEAM"))
		h_col.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h_col.custom_minimum_size = Vector2(col_min_w, 0.0)
		h_col.add_theme_font_size_override("font_size", 11)
		h_col.add_theme_color_override("font_color", entry.get("color", Color(0.84, 0.92, 0.96, 1.0)) as Color)
		scoreboard_grid.add_child(h_col)

	_add_multi_int_row("Biomass Gathered", team_entries, "biomass_gathered", true)
	_add_multi_int_row("Silica Gathered", team_entries, "silica_gathered", true)
	_add_multi_int_row("Compute Gathered", team_entries, "compute_gathered", true)
	_add_multi_int_row("Units Trained", team_entries, "units_trained", true)
	_add_multi_int_row("Units Lost", team_entries, "units_lost", false)
	if team_entries.size() <= 2:
		_add_multi_int_row("Hostiles Eliminated", team_entries, "enemies_destroyed", true)
	_add_multi_int_row("Structures Built", team_entries, "buildings_built", true)
	_add_multi_int_row("Structures Lost", team_entries, "buildings_lost", false)
	_add_multi_int_row("Peak Bandwidth", team_entries, "peak_bandwidth", true)

	# Hyper-Uplink control row
	var up_texts: Array[String] = []
	var up_vals: Array[float] = []
	var max_up: float = -1.0
	for entry: Dictionary in team_entries:
		var up_s: float = float(entry.get("uplink_seconds", 0.0))
		up_vals.append(up_s)
		max_up = maxf(max_up, up_s)
		up_texts.append("%s (%d%%)" % [
			String(entry.get("uplink_formatted", "00:00")),
			int(round(float(entry.get("uplink_pct", 0.0)))),
		])
	var up_highlights: Array[bool] = []
	for v: float in up_vals:
		up_highlights.append(max_up > 0.5 and absf(v - max_up) <= 0.5)
	_add_multi_custom_row("Hyper-Uplink Control", team_entries, up_texts, up_highlights)

	# Milestone 3.5a: Macro Efficiency Grade rows
	var sb_texts: Array[String] = []
	var sb_vals: Array[float] = []
	var min_sb: float = 999999.0
	var sb_all_equal: bool = true
	for i: int in range(team_entries.size()):
		var sb_s: float = float(team_entries[i].get("supply_blocked_seconds", 0.0))
		sb_vals.append(sb_s)
		min_sb = minf(min_sb, sb_s)
		if i > 0 and absf(sb_s - sb_vals[0]) > 0.5:
			sb_all_equal = false
		sb_texts.append(String(team_entries[i].get("supply_blocked_formatted", "00:00")))
	var sb_highlights: Array[bool] = []
	for v: float in sb_vals:
		sb_highlights.append(not sb_all_equal and absf(v - min_sb) <= 0.5)
	_add_multi_custom_row("Supply Blocked", team_entries, sb_texts, sb_highlights)

	_add_multi_int_row("Avg Unspent Float", team_entries, "avg_unspent_float", false)

	var tr_texts: Array[String] = []
	var tr_vals: Array[float] = []
	var max_tr: float = -1.0
	var tr_all_equal: bool = true
	for i: int in range(team_entries.size()):
		var tr_v: float = float(team_entries[i].get("trade_ratio", 1.0))
		var grade_s: String = String(team_entries[i].get("macro_grade", "B"))
		tr_vals.append(tr_v)
		max_tr = maxf(max_tr, tr_v)
		if i > 0 and absf(tr_v - tr_vals[0]) > 0.02:
			tr_all_equal = false
		tr_texts.append("%.2fx [%s]" % [tr_v, grade_s])
	var tr_highlights: Array[bool] = []
	for v: float in tr_vals:
		tr_highlights.append(not tr_all_equal and absf(v - max_tr) <= 0.02)
	_add_multi_custom_row("Trade Ratio / Grade", team_entries, tr_texts, tr_highlights)


func _add_multi_int_row(metric: String, entries: Array[Dictionary], key: String, higher_is_better: bool) -> void:
	var vals: Array[int] = []
	var best_val: int = -999999999 if higher_is_better else 999999999
	var all_equal: bool = true
	for i: int in range(entries.size()):
		var v: int = int(entries[i].get(key, 0))
		vals.append(v)
		if i > 0 and v != vals[0]:
			all_equal = false
		if higher_is_better:
			best_val = maxi(best_val, v)
		else:
			best_val = mini(best_val, v)

	var texts: Array[String] = []
	var highlights: Array[bool] = []
	for v: int in vals:
		texts.append(InspectionHelper.format_number(v))
		highlights.append(not all_equal and v == best_val)
	_add_multi_custom_row(metric, entries, texts, highlights)


func _add_multi_custom_row(metric: String, entries: Array[Dictionary], texts: Array[String], highlights: Array[bool]) -> void:
	var m_lbl: Label = Label.new()
	m_lbl.text = metric
	m_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_lbl.add_theme_font_size_override("font_size", 11)
	m_lbl.add_theme_color_override("font_color", Color(0.68, 0.82, 0.88, 0.92))
	scoreboard_grid.add_child(m_lbl)

	for i: int in range(entries.size()):
		var lbl: Label = Label.new()
		lbl.text = texts[i] if i < texts.size() else "--"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.add_theme_font_size_override("font_size", 11)
		var base_col: Color = entries[i].get("color", Color(0.26, 1.0, 0.88, 1.0)) as Color
		var is_hi: bool = i < highlights.size() and highlights[i]
		lbl.add_theme_color_override(
			"font_color",
			base_col.lightened(0.12) if is_hi else Color(0.84, 0.92, 0.96, 0.86)
		)
		scoreboard_grid.add_child(lbl)


func hide_summary() -> void:
	_is_inspecting_battlefield = false
	_is_mode_result_active = false
	_sync_heatmap_button(false)
	if root_control != null:
		root_control.visible = false
	if inspection_banner != null:
		inspection_banner.visible = false
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func _on_view_battlefield_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	_is_inspecting_battlefield = true
	_sync_heatmap_button(false)
	if root_control != null:
		root_control.visible = false
	if inspection_banner != null:
		inspection_banner.visible = true
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null:
			match_mgr.enter_post_match_inspection()


func _on_play_again_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null:
			match_mgr.request_rematch()
			return
		Engine.time_scale = 1.0
		get_tree().paused = false
		if VFXPool != null:
			VFXPool.clear_pool()
		get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null:
			match_mgr.return_to_main_menu()
			return
		Engine.time_scale = 1.0
		get_tree().paused = false
		if VFXPool != null:
			VFXPool.clear_pool()
		get_tree().change_scene_to_file(GameConfig.MAIN_MENU_SCENE)


func _on_sandbox_mode_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	hide_summary()
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null:
			match_mgr.enter_sandbox_mode()


class MedalEmblemControl extends Control:
	var medal: int = ModeRecords.Medal.NONE
	var succeeded: bool = false

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.44
		var accent: Color = ModeRecords.get_medal_color(medal)
		if medal == ModeRecords.Medal.NONE and not succeeded:
			accent = Color(0.92, 0.36, 0.30, 0.92)
		var fill_col: Color = Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.24, 0.94)

		# Octagonal Technozen medal crest
		var pts: PackedVector2Array = PackedVector2Array()
		var inner_pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(8):
			var ang: float = (TAU * float(i) / 8.0) - (PI / 8.0)
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
			inner_pts.append(c + Vector2(cos(ang), sin(ang)) * (r * 0.78))
		draw_colored_polygon(pts, fill_col)
		draw_polyline(pts + PackedVector2Array([pts[0]]), accent, 2.5, true)
		draw_polyline(inner_pts + PackedVector2Array([inner_pts[0]]), Color(accent.r, accent.g, accent.b, 0.45), 1.2, true)

		# Inner emblem glyph: star for Gold/Silver/Bronze, X for failed
		if medal > ModeRecords.Medal.NONE:
			var star: PackedVector2Array = PackedVector2Array()
			var spikes: int = 5
			for i: int in range(spikes * 2):
				var rad: float = (r * 0.44) if (i % 2 == 0) else (r * 0.20)
				var ang: float = -PI * 0.5 + (TAU * float(i) / float(spikes * 2))
				star.append(c + Vector2(cos(ang), sin(ang)) * rad)
			draw_colored_polygon(star, Color(accent.r, accent.g, accent.b, 0.92))
		elif succeeded:
			draw_circle(c, r * 0.28, accent)
		else:
			var d: float = r * 0.30
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), accent, 3.0, true)
			draw_line(c + Vector2(d, -d), c + Vector2(-d, d), accent, 3.0, true)

		var font: Font = ThemeDB.fallback_font
		var tag: String = ModeRecords.get_medal_label(medal) if medal > ModeRecords.Medal.NONE else ("CLEAR" if succeeded else "FAIL")
		var t_sz: Vector2 = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		draw_string(font, Vector2(c.x - t_sz.x * 0.5, size.y - 2.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, accent)
