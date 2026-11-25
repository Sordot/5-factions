class_name SandboxDebugPanel
extends Control

@export var spawner_path: NodePath
@export var selection_controller_path: NodePath

@onready var margin_container: MarginContainer = %MarginContainer
@onready var panel_container: PanelContainer = %PanelContainer
@onready var status_label: Label = %StatusLabel
@onready var btn_collapse: Button = %BtnCollapse
@onready var body_vbox: VBoxContainer = %BodyVBox
@onready var groups_label: Label = %GroupsLabel
@onready var btn_unit_1: Button = %BtnUnit1
@onready var btn_unit_5: Button = %BtnUnit5
@onready var btn_scout_1: Button = %BtnScout1
@onready var btn_worker_1: Button = %BtnWorker1
@onready var btn_toggle_aggro_ai: Button = %BtnToggleAggroAI
@onready var btn_harvester_1: Button = %BtnHarvester1
@onready var btn_engineer_1: Button = %BtnEngineer1
@onready var btn_grant_res: Button = %BtnGrantRes
@onready var btn_toggle_edge_pan: Button = %BtnToggleEdgePan
@onready var btn_toggle_fullscreen: Button = %BtnToggleFullscreen
@onready var btn_dummy_1: Button = %BtnDummy1
@onready var btn_dummy_3: Button = %BtnDummy3
@onready var btn_enemy_1: Button = %BtnEnemy1
@onready var btn_clear_dummies: Button = %BtnClearDummies
@onready var btn_reset: Button = %BtnReset
@onready var btn_main_menu: Button = %BtnMainMenu
@onready var btn_spawn_team: Button = %BtnSpawnTeam
@onready var unit_catalog_option: OptionButton = %UnitCatalogOption
@onready var btn_spawn_catalog_unit: Button = %BtnSpawnCatalogUnit
@onready var building_catalog_option: OptionButton = %BuildingCatalogOption
@onready var btn_spawn_catalog_building: Button = %BtnSpawnCatalogBuilding
@onready var btn_spawn_turret: Button = %BtnSpawnTurret
@onready var btn_toggle_combat_lab: Button = %BtnToggleCombatLab
@onready var combat_lab_row: HBoxContainer = %CombatLabRow
@onready var combat_lab_preset_option: OptionButton = %CombatLabPresetOption
@onready var btn_lab_spawn_fight: Button = %BtnLabSpawnFight
@onready var btn_lab_clear: Button = %BtnLabClear

var _spawner: SandboxSpawner = null
var _selection_controller: SelectionController = null
var _camera: RTSCamera = null
var _match_manager: MatchManager = null
var _catalog_team: Unit.Team = Unit.Team.PLAYER
var _active_faction_id: StringName = &""
var _catalog_units: Array[UnitData] = []
var _catalog_buildings: Array[BuildingData] = []
var _faction_option: OptionButton = null
var _combat_lab_open: bool = false
var _is_collapsed: bool = false
var _ai_telemetry_label: Label = null


func _ready() -> void:
	add_to_group("sandbox_debug_panel")
	if panel_container != null:
		panel_container.add_to_group("blocks_edge_pan")
	if btn_collapse != null:
		btn_collapse.pressed.connect(_on_toggle_collapse)

	# Auto-hide on skirmish maps; stay visible by default on Sandbox Testbed (milestone_0_test.tscn).
	var scene_path: String = ""
	if owner != null and not owner.scene_file_path.is_empty():
		scene_path = owner.scene_file_path
	elif is_inside_tree() and get_tree().current_scene != null:
		scene_path = get_tree().current_scene.scene_file_path
	var is_testbed: bool = scene_path.ends_with("milestone_0_test.tscn")
	set_panel_visible(is_testbed)
	_apply_collapsed_state()
	_spawner = get_node_or_null(spawner_path) as SandboxSpawner
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController
	_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
	if _camera != null and not _camera.edge_pan_toggled.is_connected(_on_camera_edge_pan_toggled):
		_camera.edge_pan_toggled.connect(_on_camera_edge_pan_toggled)
	if _camera != null and not _camera.fullscreen_toggled.is_connected(_on_camera_fullscreen_toggled):
		_camera.fullscreen_toggled.connect(_on_camera_fullscreen_toggled)
	_connect_match_manager()

	btn_unit_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_player_units(1)
	)
	btn_unit_5.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_player_units(5)
	)
	btn_scout_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_scout_units(1)
	)
	btn_worker_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_worker_units(1)
	)
	btn_toggle_aggro_ai.pressed.connect(func() -> void:
		_connect_match_manager()
		if _match_manager != null:
			_match_manager.toggle_aggro_ai()
		else:
			MatchManager._global_aggro_ai_enabled = not MatchManager._global_aggro_ai_enabled
		_refresh_aggro_ai_button()
	)
	btn_harvester_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_harvester_units(1)
	)
	btn_engineer_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_engineer_units(1)
	)
	btn_grant_res.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.grant_debug_resources()
	)
	btn_toggle_edge_pan.pressed.connect(func() -> void:
		if _camera == null and is_inside_tree():
			_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
		if _camera != null:
			_camera.toggle_edge_pan()
	)
	btn_toggle_fullscreen.pressed.connect(func() -> void:
		if SettingsManager != null:
			SettingsManager.toggle_fullscreen()
		elif _camera != null:
			_camera.toggle_fullscreen()
		_refresh_fullscreen_button()
	)
	btn_dummy_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_target_dummies(1)
	)
	btn_dummy_3.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_target_dummies(3)
	)
	btn_enemy_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_enemy_troopers(1)
	)
	btn_clear_dummies.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.clear_dummies()
	)
	btn_reset.pressed.connect(func() -> void:
		if AudioManager != null:
			AudioManager.play_ui_click()
		if _spawner != null:
			_spawner.reset_sandbox()
	)
	if btn_main_menu != null:
		btn_main_menu.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if is_inside_tree():
				get_tree().change_scene_to_file(GameConfig.MAIN_MENU_SCENE)
		)

	_setup_genesis_catalog_controls()
	_setup_ai_telemetry_label()

	_refresh_edge_pan_button()
	_refresh_fullscreen_button()
	_refresh_aggro_ai_button()
	_refresh_status()


func _setup_genesis_catalog_controls() -> void:
	_setup_faction_catalog_selector()
	_populate_faction_catalog_options()

	if btn_spawn_team != null:
		btn_spawn_team.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_catalog_team = Unit.Team.ENEMY if _catalog_team == Unit.Team.PLAYER else Unit.Team.PLAYER
			_refresh_catalog_team_button()
		)
	if btn_spawn_catalog_unit != null:
		btn_spawn_catalog_unit.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _spawner != null and unit_catalog_option != null:
				var idx: int = unit_catalog_option.selected
				if idx >= 0 and idx < _catalog_units.size():
					_spawner.spawn_unit_data(_catalog_units[idx], _catalog_team, 1)
				else:
					_spawner.spawn_genesis_unit_by_index(idx, _catalog_team, 1)
		)
	if btn_spawn_catalog_building != null:
		btn_spawn_catalog_building.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _spawner != null and building_catalog_option != null:
				var idx: int = building_catalog_option.selected
				if idx >= 0 and idx < _catalog_buildings.size():
					_spawner.spawn_building_data(_catalog_buildings[idx], _catalog_team)
				else:
					_spawner.spawn_genesis_building_by_index(idx, _catalog_team)
		)
	if btn_spawn_turret != null:
		btn_spawn_turret.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _spawner != null:
				_spawner.spawn_defense_turret(_catalog_team)
		)
	if combat_lab_preset_option != null:
		combat_lab_preset_option.clear()
		for i: int in range(SandboxSpawner.COMBAT_LAB_PRESETS.size()):
			combat_lab_preset_option.add_item(String(SandboxSpawner.COMBAT_LAB_PRESETS[i]["label"]), i)
	if btn_toggle_combat_lab != null:
		btn_toggle_combat_lab.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_combat_lab_open = not _combat_lab_open
			_refresh_combat_lab_visibility()
		)
	if btn_lab_spawn_fight != null:
		btn_lab_spawn_fight.modulate = Color(0.36, 1.0, 0.86, 1.0)
		btn_lab_spawn_fight.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _spawner != null and combat_lab_preset_option != null:
				_spawner.spawn_combat_lab_preset(combat_lab_preset_option.selected)
		)
	if btn_lab_clear != null:
		btn_lab_clear.modulate = Color(1.0, 0.62, 0.42, 1.0)
		btn_lab_clear.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _spawner != null:
				_spawner.clear_combat_lab_entities()
		)
	_refresh_combat_lab_visibility()
	_refresh_catalog_team_button()


func _setup_faction_catalog_selector() -> void:
	if TeamManager == null:
		return
	var playable: Array[FactionData] = TeamManager.get_playable_factions()
	if playable.is_empty():
		return
	var local_t: int = TeamManager.get_local_human_team()
	_active_faction_id = TeamManager.get_team_faction(local_t if local_t >= 0 else 0)
	if playable.size() <= 1 or btn_spawn_team == null or btn_spawn_team.get_parent() == null:
		return
	_faction_option = OptionButton.new()
	_faction_option.name = "FactionCatalogOption"
	_faction_option.focus_mode = Control.FOCUS_NONE
	_faction_option.custom_minimum_size = Vector2(96.0, 22.0)
	_faction_option.add_theme_font_size_override("font_size", 10)
	var sel_idx: int = 0
	for i: int in range(playable.size()):
		var fdata: FactionData = playable[i]
		_faction_option.add_item(fdata.short_code if not fdata.short_code.is_empty() else fdata.display_name, i)
		_faction_option.set_item_metadata(i, fdata.faction_id)
		if fdata.faction_id == _active_faction_id:
			sel_idx = i
	_faction_option.select(sel_idx)
	_faction_option.item_selected.connect(func(index: int) -> void:
		if AudioManager != null:
			AudioManager.play_ui_click()
		_active_faction_id = _faction_option.get_item_metadata(index) as StringName
		_populate_faction_catalog_options()
	)
	btn_spawn_team.get_parent().add_child(_faction_option)
	btn_spawn_team.get_parent().move_child(_faction_option, btn_spawn_team.get_index() + 1)


func _populate_faction_catalog_options() -> void:
	_catalog_units.clear()
	_catalog_buildings.clear()
	var fdata: FactionData = TeamManager.get_faction_data(_active_faction_id) if (TeamManager != null and _active_faction_id != &"") else null
	if fdata == null and TeamManager != null:
		fdata = TeamManager.get_team_faction_data(0)

	if unit_catalog_option != null:
		unit_catalog_option.clear()
		if fdata != null and not fdata.unit_roster.is_empty():
			for udata: UnitData in fdata.unit_roster:
				if udata == null or (udata.unit_scene == null and udata.unit_scene_path.is_empty()):
					continue
				_catalog_units.append(udata)
				unit_catalog_option.add_item(udata.display_name, _catalog_units.size() - 1)
		else:
			for i: int in range(SandboxSpawner.GENESIS_UNIT_CATALOG.size()):
				unit_catalog_option.add_item(String(SandboxSpawner.GENESIS_UNIT_CATALOG[i]["label"]), i)

	if building_catalog_option != null:
		building_catalog_option.clear()
		if fdata != null and not fdata.building_roster.is_empty():
			for bdata: BuildingData in fdata.building_roster:
				if bdata == null or (bdata.scene == null and bdata.scene_path.is_empty()):
					continue
				_catalog_buildings.append(bdata)
				building_catalog_option.add_item(bdata.display_name, _catalog_buildings.size() - 1)
		else:
			for i: int in range(SandboxSpawner.GENESIS_BUILDING_CATALOG.size()):
				building_catalog_option.add_item(String(SandboxSpawner.GENESIS_BUILDING_CATALOG[i]["label"]), i)


func _setup_ai_telemetry_label() -> void:
	if body_vbox == null or _ai_telemetry_label != null:
		return
	_ai_telemetry_label = Label.new()
	_ai_telemetry_label.name = "AITelemetryLabel"
	_ai_telemetry_label.visible = false
	_ai_telemetry_label.add_theme_font_size_override("font_size", 10)
	_ai_telemetry_label.add_theme_color_override("font_color", Color(0.98, 0.84, 0.38, 0.96))
	body_vbox.add_child(_ai_telemetry_label)
	var ctrl_idx: int = maxi(0, body_vbox.get_child_count() - 2)
	body_vbox.move_child(_ai_telemetry_label, ctrl_idx)


func _refresh_combat_lab_visibility() -> void:
	if combat_lab_row != null:
		combat_lab_row.visible = _combat_lab_open
	if btn_toggle_combat_lab != null:
		btn_toggle_combat_lab.text = "Combat Lab ▾" if _combat_lab_open else "Combat Lab ▸"
		btn_toggle_combat_lab.modulate = Color(0.36, 1.0, 0.88, 1.0) if _combat_lab_open else Color(0.84, 0.92, 0.96, 0.92)


func _refresh_catalog_team_button() -> void:
	if btn_spawn_team == null:
		return
	var is_player: bool = (_catalog_team == Unit.Team.PLAYER)
	btn_spawn_team.text = "Team: PLAYER" if is_player else "Team: ENEMY"
	btn_spawn_team.modulate = Color(0.42, 0.98, 0.88, 1.0) if is_player else Color(1.0, 0.44, 0.34, 1.0)


func _connect_match_manager() -> void:
	if _match_manager != null and is_instance_valid(_match_manager):
		return
	if is_inside_tree():
		_match_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if _match_manager != null and not _match_manager.aggro_ai_toggled.is_connected(_on_aggro_ai_toggled):
			_match_manager.aggro_ai_toggled.connect(_on_aggro_ai_toggled)


func _on_aggro_ai_toggled(_enabled: bool) -> void:
	_refresh_aggro_ai_button()


func _refresh_aggro_ai_button() -> void:
	if btn_toggle_aggro_ai == null:
		return
	var aggro_on: bool = MatchManager.is_aggro_ai_enabled(get_tree() if is_inside_tree() else null)
	var hk: String = SettingsManager.get_action_key_label(&"debug_toggle_aggro_ai") if SettingsManager != null else "F10"
	btn_toggle_aggro_ai.text = ("Aggro AI: ON (%s)" % hk) if aggro_on else ("Aggro AI: OFF (%s)" % hk)
	btn_toggle_aggro_ai.modulate = Color(0.42, 0.98, 0.78, 1.0) if aggro_on else Color(1.0, 0.64, 0.28, 1.0)


func _on_camera_edge_pan_toggled(_enabled: bool) -> void:
	_refresh_edge_pan_button()


func _on_camera_fullscreen_toggled(_enabled: bool) -> void:
	_refresh_fullscreen_button()


func _refresh_edge_pan_button() -> void:
	if btn_toggle_edge_pan == null:
		return
	var enabled: bool = _camera.edge_pan_enabled if _camera != null else true
	var hk: String = SettingsManager.get_action_key_label(&"camera_toggle_edge_pan") if SettingsManager != null else "F12"
	btn_toggle_edge_pan.text = ("Edge Pan: ON (%s)" % hk) if enabled else ("Edge Pan: OFF (%s)" % hk)
	btn_toggle_edge_pan.modulate = Color(0.55, 1.0, 0.92, 1.0) if enabled else Color(0.76, 0.72, 0.72, 0.85)


func _refresh_fullscreen_button() -> void:
	if btn_toggle_fullscreen == null:
		return
	var is_fs: bool = false
	if _camera != null:
		is_fs = _camera.is_fullscreen()
	else:
		var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		is_fs = (mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	var hk: String = SettingsManager.get_action_key_label(&"camera_toggle_fullscreen") if SettingsManager != null else "F11"
	btn_toggle_fullscreen.text = ("Fullscreen: ON (%s)" % hk) if is_fs else ("Fullscreen: OFF (%s)" % hk)
	btn_toggle_fullscreen.modulate = Color(0.55, 1.0, 0.92, 1.0) if is_fs else Color(0.76, 0.82, 0.88, 0.9)


func set_panel_visible(show_panel: bool) -> void:
	visible = show_panel
	if show_panel:
		_refresh_edge_pan_button()
		_refresh_fullscreen_button()
		_refresh_aggro_ai_button()
		_refresh_status()


func toggle_panel_visible() -> bool:
	set_panel_visible(not visible)
	return visible


func is_panel_visible() -> bool:
	return visible


func _on_toggle_collapse() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	_is_collapsed = not _is_collapsed
	_apply_collapsed_state()


func _apply_collapsed_state() -> void:
	if body_vbox != null:
		body_vbox.visible = not _is_collapsed
	if btn_collapse != null:
		btn_collapse.text = "+" if _is_collapsed else "–"
		btn_collapse.tooltip_text = "Expand Debug HUD" if _is_collapsed else "Minimize Debug HUD"
	if margin_container != null:
		margin_container.reset_size()
	if panel_container != null:
		panel_container.reset_size()
	_refresh_status()


func _process(_delta: float) -> void:
	if not visible:
		return
	_connect_match_manager()
	_refresh_status()
	if not _is_collapsed:
		_refresh_fullscreen_button()
		_refresh_aggro_ai_button()


func _refresh_status() -> void:
	if status_label == null:
		return
	if _is_collapsed:
		status_label.text = "DEBUG HUD"
		return
	var player_count: int = 0
	var dummy_count: int = 0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_queued_for_deletion():
			continue
		if unit.team == Unit.Team.PLAYER:
			player_count += 1
		else:
			dummy_count += 1

	var selected_count: int = _selection_controller.selected_units.size() if _selection_controller != null else 0
	status_label.text = "Units: %d (Selected: %d)  |  Hostiles: %d" % [
		player_count,
		selected_count,
		dummy_count,
	]

	if groups_label != null and _selection_controller != null:
		var summary: Dictionary = _selection_controller.get_control_groups_summary()
		if summary.is_empty():
			groups_label.text = "Control Groups: None (Ctrl=Set, Shift=Add, Alt=Steal + 1-9)"
		else:
			var parts: PackedStringArray = PackedStringArray()
			for num: int in range(1, 10):
				if summary.has(num):
					parts.append("[%d]: %d" % [num, int(summary[num])])
			groups_label.text = "Control Groups: " + "  ".join(parts)

	_refresh_ai_telemetry()


func _refresh_ai_telemetry() -> void:
	if _ai_telemetry_label == null or not is_inside_tree():
		return
	var ai_nodes: Array[Node] = get_tree().get_nodes_in_group("skirmish_ai")
	var lines: PackedStringArray = PackedStringArray()
	var sorted_ais: Array[Node] = []
	for node: Node in ai_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("get_debug_status_line"):
			sorted_ais.append(node)
	sorted_ais.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get("ai_team")) < int(b.get("ai_team"))
	)
	for ai_node: Node in sorted_ais:
		lines.append(String(ai_node.call("get_debug_status_line")))
	_ai_telemetry_label.visible = not lines.is_empty()
	if not lines.is_empty():
		_ai_telemetry_label.text = "\n".join(lines)
