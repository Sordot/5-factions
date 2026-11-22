class_name SandboxSpawner
extends Node2D

@export var arena_safe_bounds: Rect2 = Rect2(-580.0, -300.0, 1160.0, 600.0)
@export var reload_scene_on_reset: bool = false

signal entities_changed

@export var units_container_path: NodePath
@export var selection_controller_path: NodePath
@export var player_unit_scene: PackedScene = preload("res://scenes/units/test_unit.tscn")
@export var scout_unit_scene: PackedScene = preload("res://scenes/units/scout_unit.tscn")
@export var worker_unit_scene: PackedScene = preload("res://scenes/units/worker_unit.tscn")
@export var harvester_unit_scene: PackedScene = preload("res://scenes/units/silica_harvester.tscn")
@export var engineer_unit_scene: PackedScene = preload("res://scenes/units/engineer_unit.tscn")
@export var target_dummy_scene: PackedScene = preload("res://scenes/units/target_dummy.tscn")
@export var enemy_trooper_scene: PackedScene = preload("res://scenes/units/enemy_trooper.tscn")
@export var player_spawn_origin: Vector2 = Vector2(-280.0, 0.0)
@export var worker_spawn_origin: Vector2 = Vector2(-265.0, 165.0)
@export var harvester_spawn_origin: Vector2 = Vector2(320.0, -110.0)
@export var engineer_spawn_origin: Vector2 = Vector2(-340.0, 50.0)
@export var dummy_spawn_origin: Vector2 = Vector2(260.0, 0.0)
@export var enemy_spawn_origin: Vector2 = Vector2(240.0, 120.0)

var _spawn_cycle: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_spawn_unit_1"):
		spawn_player_units(1, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_unit_5"):
		spawn_player_units(5, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_scout_1"):
		spawn_scout_units(1, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_worker_1"):
		spawn_worker_units(1, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_harvester_1"):
		spawn_harvester_units(1, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_engineer_1"):
		spawn_engineer_units(1, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_dummy_1"):
		spawn_target_dummies(1, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_dummy_3"):
		spawn_target_dummies(3, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_enemy_1"):
		spawn_enemy_troopers(1, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_clear_dummies"):
		clear_dummies()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_reset_sandbox"):
		reset_sandbox()
		get_viewport().set_input_as_handled()


func spawn_player_units(count: int, origin: Vector2 = Vector2.INF) -> Array[Unit]:
	var base_pos: Vector2 = _resolve_origin(origin, player_spawn_origin)
	return _spawn_batch(player_unit_scene, count, base_pos, 42.0)


func spawn_scout_units(count: int, origin: Vector2 = Vector2.INF) -> Array[Unit]:
	var base_pos: Vector2 = _resolve_origin(origin, player_spawn_origin + Vector2(0.0, 64.0))
	return _spawn_batch(scout_unit_scene, count, base_pos, 40.0)


func spawn_worker_units(count: int, origin: Vector2 = Vector2.INF) -> Array[Unit]:
	var base_pos: Vector2 = _resolve_origin(origin, worker_spawn_origin)
	return _spawn_batch(worker_unit_scene, count, base_pos, 38.0)


func spawn_harvester_units(count: int, origin: Vector2 = Vector2.INF) -> Array[Unit]:
	var base_pos: Vector2 = _resolve_origin(origin, harvester_spawn_origin)
	return _spawn_batch(harvester_unit_scene, count, base_pos, 44.0)


func spawn_engineer_units(count: int, origin: Vector2 = Vector2.INF) -> Array[Unit]:
	var base_pos: Vector2 = _resolve_origin(origin, engineer_spawn_origin)
	return _spawn_batch(engineer_unit_scene, count, base_pos, 38.0)


func spawn_enemy_troopers(count: int, origin: Vector2 = Vector2.INF, attack_move_center: bool = false) -> Array[Unit]:
	var base_pos: Vector2 = _resolve_origin(origin, enemy_spawn_origin)
	var spawned: Array[Unit] = _spawn_batch(enemy_trooper_scene, count, base_pos, 42.0)
	if attack_move_center:
		for u: Unit in spawned:
			u.call_deferred("command_attack_move", Vector2.ZERO)
	return spawned


func grant_debug_resources() -> void:
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.add_resource(Unit.Team.PLAYER, EconomyManager.RESOURCE_BIOMASS, 200)
		econ.add_resource(Unit.Team.PLAYER, EconomyManager.RESOURCE_SILICA, 100)


func trigger_zone_phase() -> void:
	var zone: EncroachingZone = get_tree().get_first_node_in_group("encroaching_zone") as EncroachingZone
	if zone != null:
		zone.trigger_next_phase_now()


func spawn_target_dummies(count: int, origin: Vector2 = Vector2.INF) -> Array[Unit]:
	var base_pos: Vector2 = _resolve_origin(origin, dummy_spawn_origin)
	return _spawn_batch(target_dummy_scene, count, base_pos, 52.0)


func clear_dummies() -> void:
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node) and node.team == Unit.Team.ENEMY:
			node.queue_free()
	entities_changed.emit()


func reset_sandbox() -> void:
	if reload_scene_on_reset and is_inside_tree():
		get_tree().reload_current_scene()
		return
	var sel_ctrl: SelectionController = _get_selection_controller()
	if sel_ctrl != null:
		sel_ctrl.clear_selection()
		sel_ctrl.clear_control_groups()

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if b.building_type_id != &"command_core":
				b.queue_free()

	var container: Node = _get_units_container()
	if container != null:
		for child: Node in container.get_children():
			child.queue_free()

	_spawn_cycle = 0
	_spawn_batch(player_unit_scene, 1, player_spawn_origin, 42.0)
	_spawn_batch(worker_unit_scene, 1, Vector2(-430.0, 125.0), 38.0)
	_spawn_batch(worker_unit_scene, 1, Vector2(-430.0, 205.0), 38.0)
	_spawn_batch(target_dummy_scene, 1, dummy_spawn_origin, 52.0)

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.reset_economy()

	for node: Node in get_tree().get_nodes_in_group("hyper_uplinks"):
		if node is HyperUplink:
			(node as HyperUplink).reset_uplink()

	var zone: EncroachingZone = get_tree().get_first_node_in_group("encroaching_zone") as EncroachingZone
	if zone != null:
		zone.reset_zone()

	entities_changed.emit()


func _spawn_batch(scene: PackedScene, count: int, origin: Vector2, spacing: float) -> Array[Unit]:
	var spawned: Array[Unit] = []
	var container: Node = _get_units_container()
	if scene == null or container == null or count <= 0:
		return spawned

	var cols: int = ceili(sqrt(float(count)))
	var rows: int = ceili(float(count) / float(cols))
	for i: int in range(count):
		var col: int = i % cols
		var row: int = i / cols
		var offset: Vector2 = Vector2(
			(float(col) - float(cols - 1) * 0.5) * spacing,
			(float(row) - float(rows - 1) * 0.5) * spacing
		)
		var unit_node: Node = scene.instantiate()
		if not (unit_node is Unit):
			unit_node.queue_free()
			continue
		var unit: Unit = unit_node
		unit.position = _clamp_to_walkable_arena(origin + offset)
		container.add_child(unit)
		spawned.append(unit)

	entities_changed.emit()
	return spawned


func _resolve_origin(origin: Vector2, preset: Vector2) -> Vector2:
	if origin != Vector2.INF:
		return _clamp_to_walkable_arena(origin)
	var angle: float = float(_spawn_cycle) * 1.15
	var radial: float = 0.0 if _spawn_cycle == 0 else 44.0
	_spawn_cycle = (_spawn_cycle + 1) % 8
	return _clamp_to_walkable_arena(preset + Vector2.RIGHT.rotated(angle) * radial)


func _clamp_to_walkable_arena(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, arena_safe_bounds.position.x, arena_safe_bounds.end.x),
		clampf(pos.y, arena_safe_bounds.position.y, arena_safe_bounds.end.y)
	)


func _get_units_container() -> Node:
	if not units_container_path.is_empty():
		return get_node_or_null(units_container_path)
	return get_parent().get_node_or_null("Units")


func _get_selection_controller() -> SelectionController:
	if not selection_controller_path.is_empty():
		return get_node_or_null(selection_controller_path) as SelectionController
	return get_parent().get_node_or_null("SelectionController") as SelectionController
