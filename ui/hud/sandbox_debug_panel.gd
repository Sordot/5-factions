class_name SandboxDebugPanel
extends Control

@export var spawner_path: NodePath
@export var selection_controller_path: NodePath

@onready var status_label: Label = %StatusLabel
@onready var btn_unit_1: Button = %BtnUnit1
@onready var btn_unit_5: Button = %BtnUnit5
@onready var btn_dummy_1: Button = %BtnDummy1
@onready var btn_dummy_3: Button = %BtnDummy3
@onready var btn_clear_dummies: Button = %BtnClearDummies
@onready var btn_reset: Button = %BtnReset

var _spawner: SandboxSpawner = null
var _selection_controller: SelectionController = null
var _command_mode: String = "NORMAL"


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

	if _selection_controller != null:
		_selection_controller.command_mode_changed.connect(_on_command_mode_changed)

	_refresh_status()


func _process(_delta: float) -> void:
	_refresh_status()


func _on_command_mode_changed(mode_name: String) -> void:
	_command_mode = mode_name
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
	var mode_text: String = "ATTACK-MOVE (LMB target | RMB/Esc cancel)" if _command_mode == "ATTACK_MOVE" else "Normal"
	status_label.text = "Mode: %s  |  Units: %d (Selected: %d)  |  Dummies: %d" % [
		mode_text,
		player_count,
		selected_count,
		dummy_count,
	]
