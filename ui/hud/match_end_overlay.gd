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
@onready var btn_play_again: Button = %BtnPlayAgain
@onready var btn_main_menu: Button = %BtnMainMenu
@onready var btn_sandbox_mode: Button = %BtnSandboxMode

var _active_tab: StringName = &"summary"
var _active_metric: StringName = TimelineGraph.METRIC_ARMY_VALUE


func _ready() -> void:
	add_to_group("match_end_overlay")
	layer = 10
	if root_control != null:
		root_control.visible = false
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
	if btn_play_again != null:
		btn_play_again.pressed.connect(_on_play_again_pressed)
	if btn_main_menu != null:
		btn_main_menu.pressed.connect(_on_main_menu_pressed)
	if btn_sandbox_mode != null:
		btn_sandbox_mode.pressed.connect(_on_sandbox_mode_pressed)
	_set_active_tab(&"summary")
	_set_active_metric(TimelineGraph.METRIC_ARMY_VALUE)


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


func show_summary(stats: Dictionary) -> void:
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
		subtitle_label.text = str(stats.get("reason", ""))
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


func _populate_timeline_graph(stats: Dictionary) -> void:
	if timeline_graph == null:
		return
	var samples: Array = stats.get("timeline_samples", []) as Array
	var team_names: Dictionary = {}
	var team_colors: Dictionary = {}
	var is_spec: bool = bool(stats.get("is_spectator", false))
	if is_spec and GameConfig != null:
		team_names[0] = "AI-01"
		team_names[1] = "AI-02"
	else:
		team_names[0] = "PLAYER"
		team_names[1] = "AI"
	if TeamManager != null:
		for tid: int in TeamManager.get_active_teams():
			if not team_names.has(tid):
				team_names[tid] = TeamManager.get_team_display_name(tid)
			team_colors[tid] = TeamManager.get_team_color(tid)
	timeline_graph.set_samples(samples, team_names, team_colors)
	_set_active_metric(_active_metric)


func _populate_scoreboard(stats: Dictionary) -> void:
	if scoreboard_grid == null:
		return
	for child: Node in scoreboard_grid.get_children():
		child.queue_free()

	var p: Dictionary = stats.get("player", {}) as Dictionary
	var e: Dictionary = stats.get("enemy", {}) as Dictionary

	var p_col_title: String = "PLAYER (GENESIS_V2)"
	var ai_tag: String = "AI (GENESIS_V2)"
	if bool(stats.get("is_spectator", false)) and GameConfig != null:
		p_col_title = "AI-01 (%s)" % GameConfig.get_difficulty_label(GameConfig.team0_ai_difficulty)
		ai_tag = "AI-02 (%s)" % GameConfig.get_difficulty_label(GameConfig.team1_ai_difficulty)
	elif GameConfig != null:
		ai_tag = "AI (%s)" % GameConfig.get_difficulty_label()

	_add_header_row("TELEMETRY METRIC", p_col_title, ai_tag)

	_add_stat_row("Biomass Gathered", int(p.get("biomass_gathered", 0)), int(e.get("biomass_gathered", 0)), true)
	_add_stat_row("Silica Gathered", int(p.get("silica_gathered", 0)), int(e.get("silica_gathered", 0)), true)
	_add_stat_row("Compute Gathered", int(p.get("compute_gathered", 0)), int(e.get("compute_gathered", 0)), true)
	_add_stat_row("Units Trained", int(p.get("units_trained", stats.get("units_trained", 0))), int(e.get("units_trained", 0)), true)
	_add_stat_row("Units Lost", int(p.get("units_lost", stats.get("units_lost", 0))), int(e.get("units_lost", stats.get("enemies_destroyed", 0))), false)
	_add_stat_row("Hostiles Eliminated", int(p.get("enemies_destroyed", stats.get("enemies_destroyed", 0))), int(e.get("enemies_destroyed", stats.get("units_lost", 0))), true)
	_add_stat_row("Structures Built", int(p.get("buildings_built", 0)), int(e.get("buildings_built", 0)), true)
	_add_stat_row("Structures Lost", int(p.get("buildings_lost", 0)), int(e.get("buildings_lost", stats.get("structures_destroyed", 0))), false)
	_add_stat_row("Peak Bandwidth", int(p.get("peak_bandwidth", 0)), int(e.get("peak_bandwidth", 0)), true)

	var p_up_s: float = float(p.get("uplink_seconds", 0.0))
	var e_up_s: float = float(e.get("uplink_seconds", 0.0))
	var p_up_txt: String = "%s (%d%%)" % [String(p.get("uplink_formatted", "00:00")), int(round(float(p.get("uplink_pct", stats.get("uplink_control_pct", 0.0)))))]
	var e_up_txt: String = "%s (%d%%)" % [String(e.get("uplink_formatted", "00:00")), int(round(float(e.get("uplink_pct", 0.0))))]
	_add_custom_row("Hyper-Uplink Control", p_up_txt, e_up_txt, p_up_s > e_up_s + 0.5, e_up_s > p_up_s + 0.5)


func _add_header_row(col1: String, col2: String, col3: String) -> void:
	var h1: Label = Label.new()
	h1.text = col1
	h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.add_theme_font_size_override("font_size", 11)
	h1.add_theme_color_override("font_color", Color(0.46, 0.74, 0.84, 0.92))
	scoreboard_grid.add_child(h1)

	var h2: Label = Label.new()
	h2.text = col2
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h2.custom_minimum_size = Vector2(140.0, 0.0)
	h2.add_theme_font_size_override("font_size", 11)
	h2.add_theme_color_override("font_color", Color(0.24, 0.98, 0.88, 1.0))
	scoreboard_grid.add_child(h2)

	var h3: Label = Label.new()
	h3.text = col3
	h3.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h3.custom_minimum_size = Vector2(140.0, 0.0)
	h3.add_theme_font_size_override("font_size", 11)
	h3.add_theme_color_override("font_color", Color(1.0, 0.46, 0.36, 1.0))
	scoreboard_grid.add_child(h3)


func _add_stat_row(metric: String, p_val: int, e_val: int, higher_is_better: bool) -> void:
	var p_better: bool = (p_val > e_val) if higher_is_better else (p_val < e_val)
	var e_better: bool = (e_val > p_val) if higher_is_better else (e_val < p_val)
	_add_custom_row(
		metric,
		InspectionHelper.format_number(p_val),
		InspectionHelper.format_number(e_val),
		p_better,
		e_better
	)


func _add_custom_row(metric: String, p_text: String, e_text: String, p_highlight: bool, e_highlight: bool) -> void:
	var m_lbl: Label = Label.new()
	m_lbl.text = metric
	m_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_lbl.add_theme_font_size_override("font_size", 12)
	m_lbl.add_theme_color_override("font_color", Color(0.68, 0.82, 0.88, 0.92))
	scoreboard_grid.add_child(m_lbl)

	var p_lbl: Label = Label.new()
	p_lbl.text = p_text
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p_lbl.add_theme_font_size_override("font_size", 12)
	p_lbl.add_theme_color_override(
		"font_color",
		Color(0.26, 1.0, 0.88, 1.0) if p_highlight else Color(0.84, 0.92, 0.96, 0.88)
	)
	scoreboard_grid.add_child(p_lbl)

	var e_lbl: Label = Label.new()
	e_lbl.text = e_text
	e_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	e_lbl.add_theme_font_size_override("font_size", 12)
	e_lbl.add_theme_color_override(
		"font_color",
		Color(1.0, 0.62, 0.42, 1.0) if e_highlight else Color(0.84, 0.92, 0.96, 0.88)
	)
	scoreboard_grid.add_child(e_lbl)


func hide_summary() -> void:
	if root_control != null:
		root_control.visible = false
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()


func _on_play_again_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().change_scene_to_file(GameConfig.MAIN_MENU_SCENE)


func _on_sandbox_mode_pressed() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	hide_summary()
	if is_inside_tree():
		var match_mgr: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if match_mgr != null:
			match_mgr.enter_sandbox_mode()
