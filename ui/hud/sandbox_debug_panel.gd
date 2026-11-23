class_name SandboxDebugPanel
extends Control

@export var spawner_path: NodePath
@export var selection_controller_path: NodePath

@onready var status_label: Label = %StatusLabel
@onready var groups_label: Label = %GroupsLabel
@onready var btn_unit_1: Button = %BtnUnit1
@onready var btn_unit_5: Button = %BtnUnit5
@onready var btn_scout_1: Button = %BtnScout1
@onready var btn_worker_1: Button = %BtnWorker1
@onready var btn_toggle_aggro_ai: Button = %BtnToggleAggroAI
@onready var btn_toggle_zone: Button = %BtnToggleZone
@onready var btn_harvester_1: Button = %BtnHarvester1
@onready var btn_engineer_1: Button = %BtnEngineer1
@onready var btn_grant_res: Button = %BtnGrantRes
@onready var btn_trigger_zone: Button = %BtnTriggerZone
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

var _spawner: SandboxSpawner = null
var _selection_controller: SelectionController = null
var _camera: RTSCamera = null
var _match_manager: MatchManager = null
var _zone: EncroachingZone = null
var _catalog_team: Unit.Team = Unit.Team.PLAYER


func _ready() -> void:
	var panel: Control = get_node_or_null("MarginContainer/PanelContainer") as Control
	if panel != null:
		panel.add_to_group("blocks_edge_pan")
	_spawner = get_node_or_null(spawner_path) as SandboxSpawner
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController
	_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
	if _camera != null and not _camera.edge_pan_toggled.is_connected(_on_camera_edge_pan_toggled):
		_camera.edge_pan_toggled.connect(_on_camera_edge_pan_toggled)
	if _camera != null and not _camera.fullscreen_toggled.is_connected(_on_camera_fullscreen_toggled):
		_camera.fullscreen_toggled.connect(_on_camera_fullscreen_toggled)
	_connect_match_manager()
	_connect_zone()

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
	btn_toggle_zone.pressed.connect(func() -> void:
		_connect_zone()
		if _zone != null:
			_zone.toggle_zone()
		_refresh_zone_button()
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
	btn_trigger_zone.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.trigger_zone_phase()
	)
	btn_toggle_edge_pan.pressed.connect(func() -> void:
		if _camera == null and is_inside_tree():
			_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
		if _camera != null:
			_camera.toggle_edge_pan()
	)
	btn_toggle_fullscreen.pressed.connect(func() -> void:
		if _camera == null and is_inside_tree():
			_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
		if _camera != null:
			_camera.toggle_fullscreen()
		else:
			var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
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

	_refresh_edge_pan_button()
	_refresh_fullscreen_button()
	_refresh_aggro_ai_button()
	_refresh_zone_button()
	_refresh_status()


func _setup_genesis_catalog_controls() -> void:
	if unit_catalog_option != null:
		unit_catalog_option.clear()
		for i: int in range(SandboxSpawner.GENESIS_UNIT_CATALOG.size()):
			unit_catalog_option.add_item(String(SandboxSpawner.GENESIS_UNIT_CATALOG[i]["label"]), i)
	if building_catalog_option != null:
		building_catalog_option.clear()
		for i: int in range(SandboxSpawner.GENESIS_BUILDING_CATALOG.size()):
			building_catalog_option.add_item(String(SandboxSpawner.GENESIS_BUILDING_CATALOG[i]["label"]), i)

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
				_spawner.spawn_genesis_unit_by_index(unit_catalog_option.selected, _catalog_team, 1)
		)
	if btn_spawn_catalog_building != null:
		btn_spawn_catalog_building.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _spawner != null and building_catalog_option != null:
				_spawner.spawn_genesis_building_by_index(building_catalog_option.selected, _catalog_team)
		)
	_refresh_catalog_team_button()


func _refresh_catalog_team_button() -> void:
	if btn_spawn_team == null:
		return
	var is_player: bool = (_catalog_team == Unit.Team.PLAYER)
	btn_spawn_team.text = "Team: PLAYER" if is_player else "Team: ENEMY"
	btn_spawn_team.modulate = Color(0.42, 0.98, 0.88, 1.0) if is_player else Color(1.0, 0.44, 0.34, 1.0)


func _connect_zone() -> void:
	if _zone != null and is_instance_valid(_zone):
		return
	if is_inside_tree():
		_zone = get_tree().get_first_node_in_group("encroaching_zone") as EncroachingZone
		if _zone != null and not _zone.zone_toggled.is_connected(_on_zone_toggled):
			_zone.zone_toggled.connect(_on_zone_toggled)


func _on_zone_toggled(_enabled: bool) -> void:
	_refresh_zone_button()


func _refresh_zone_button() -> void:
	if btn_toggle_zone == null:
		return
	var zone_on: bool = _zone.active if (_zone != null and is_instance_valid(_zone)) else false
	btn_toggle_zone.text = "Zone: ON" if zone_on else "Zone: OFF"
	btn_toggle_zone.modulate = Color(1.0, 0.48, 0.54, 1.0) if zone_on else Color(0.68, 0.74, 0.80, 0.85)
	if btn_trigger_zone != null:
		btn_trigger_zone.disabled = not zone_on


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
	btn_toggle_aggro_ai.text = "Aggro AI: ON (F10)" if aggro_on else "Aggro AI: OFF (F10)"
	btn_toggle_aggro_ai.modulate = Color(0.42, 0.98, 0.78, 1.0) if aggro_on else Color(1.0, 0.64, 0.28, 1.0)


func _on_camera_edge_pan_toggled(_enabled: bool) -> void:
	_refresh_edge_pan_button()


func _on_camera_fullscreen_toggled(_enabled: bool) -> void:
	_refresh_fullscreen_button()


func _refresh_edge_pan_button() -> void:
	if btn_toggle_edge_pan == null:
		return
	var enabled: bool = _camera.edge_pan_enabled if _camera != null else true
	btn_toggle_edge_pan.text = "Edge Pan: ON (F12)" if enabled else "Edge Pan: OFF (F12)"
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
	btn_toggle_fullscreen.text = "Fullscreen: ON (F11)" if is_fs else "Fullscreen: OFF (F11)"
	btn_toggle_fullscreen.modulate = Color(0.55, 1.0, 0.92, 1.0) if is_fs else Color(0.76, 0.82, 0.88, 0.9)


func _process(_delta: float) -> void:
	_connect_match_manager()
	_connect_zone()
	_refresh_status()
	_refresh_fullscreen_button()
	_refresh_aggro_ai_button()
	_refresh_zone_button()


func _refresh_status() -> void:
	if status_label == null:
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
			groups_label.text = "Control Groups: None (Ctrl/Shift/Alt + 1-9)"
		else:
			var parts: PackedStringArray = PackedStringArray()
			for num: int in range(1, 10):
				if summary.has(num):
					parts.append("[%d]: %d" % [num, int(summary[num])])
			groups_label.text = "Control Groups: " + "  ".join(parts)
