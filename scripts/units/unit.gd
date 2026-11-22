class_name Unit
extends CharacterBody2D

signal selection_changed(unit: Unit, selected: bool)

@export var data: UnitData

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var selection_ring: Node2D = $SelectionRing
@onready var body_visual: Node2D = $BodyVisual

var is_selected: bool = false
var _has_move_target: bool = false


func _ready() -> void:
	add_to_group("selectable_units")
	if data == null:
		data = UnitData.new()
	selection_ring.visible = is_selected


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	if is_node_ready():
		selection_ring.visible = is_selected
	selection_changed.emit(self, is_selected)


func contains_point(world_point: Vector2) -> bool:
	var radius: float = data.selection_radius if data != null else 20.0
	return global_position.distance_squared_to(world_point) <= radius * radius


func issue_move_command(target_pos: Vector2) -> void:
	nav_agent.target_position = target_pos
	_has_move_target = true


func stop_movement() -> void:
	_has_move_target = false
	velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	var move_speed: float = data.move_speed if data != null else 260.0
	var accel: float = data.acceleration if data != null else 1800.0
	var turn_speed: float = data.turn_speed if data != null else 14.0

	if not _has_move_target:
		if velocity.length_squared() > 0.01:
			velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
			move_and_slide()
		else:
			velocity = Vector2.ZERO
		return

	if NavigationServer2D.map_get_iteration_id(nav_agent.get_navigation_map()) == 0:
		return

	if nav_agent.is_navigation_finished():
		_has_move_target = false
		velocity = Vector2.ZERO
		return

	var next_point: Vector2 = nav_agent.get_next_path_position()
	var to_next: Vector2 = next_point - global_position
	if to_next.length_squared() < 1.0:
		return

	var desired_velocity: Vector2 = to_next.normalized() * move_speed
	velocity = velocity.move_toward(desired_velocity, accel * delta)

	var target_angle: float = to_next.angle()
	body_visual.rotation = lerp_angle(
		body_visual.rotation,
		target_angle,
		clampf(turn_speed * delta, 0.0, 1.0)
	)
	move_and_slide()
