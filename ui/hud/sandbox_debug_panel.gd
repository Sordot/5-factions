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
@onready var btn_harvester_1: Button = %BtnHarvester1
@onready var btn_engineer_1: Button = %BtnEngineer1
@onready var btn_grant_res: Button = %BtnGrantRes
@onready var btn_dummy_1: Button = %BtnDummy1
@onready var btn_dummy_3: Button = %BtnDummy3
@onready var btn_clear_dummies: Button = %BtnClearDummies
@onready var btn_reset: Button = %BtnReset

var _spawner: SandboxSpawner = null
var _selection_controller: SelectionController = null


func _ready() -> void:
	_spawner = get_node_or_null(spawner_path) as SandboxSpawner
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController

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
	btn_dummy_1.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_target_dummies(1)
	)
	btn_dummy_3.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.spawn_target_dummies(3)
	)
	btn_clear_dummies.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.clear_dummies()
	)
	btn_reset.pressed.connect(func() -> void:
		if _spawner != null:
			_spawner.reset_sandbox()
	)

	_refresh_status()


func _process(_delta: float) -> void:
	_refresh_status()


func _refresh_status() -> void:
	if status_label == null:
		return
	var player_count: int = 0
	var dummy_count: int = 0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead:
			continue
		if unit.team == Unit.Team.PLAYER:
			player_count += 1
		else:
			dummy_count += 1

	var selected_count: int = _selection_controller.selected_units.size() if _selection_controller != null else 0
	status_label.text = "Units: %d (Selected: %d)  |  Dummies: %d" % [
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
