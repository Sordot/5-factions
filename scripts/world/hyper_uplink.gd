class_name HyperUplink
extends Node2D

signal controller_changed(new_team: int)
signal capture_state_changed(progress: float, contested: bool, controller: int)

@export var capture_radius: float = 140.0
@export var capture_time: float = 8.0
@export var production_bonus_pct: float = 0.05

var capture_progress: float = 0.0 # -1.0 = ENEMY, 0.0 = NEUTRAL, +1.0 = PLAYER
var controlling_team: int = -1
var is_contested: bool = false

var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("hyper_uplinks")
	z_index = -5
	queue_redraw()


func reset_uplink() -> void:
	capture_progress = 0.0
	is_contested = false
	_set_controller(-1)
	capture_state_changed.emit(capture_progress, is_contested, controlling_team)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_time += delta
	var player_count: int = 0
	var enemy_count: int = 0
	var radius_sq: float = capture_radius * capture_radius

	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed:
			continue
		if global_position.distance_squared_to(unit.global_position) <= radius_sq:
			if unit.team == Unit.Team.PLAYER:
				player_count += 1
			elif unit.team == Unit.Team.ENEMY:
				enemy_count += 1

	var prev_progress: float = capture_progress
	var prev_contested: bool = is_contested

	if player_count > 0 and enemy_count > 0:
		is_contested = true
	else:
		is_contested = false
		var rate: float = 1.0 / maxf(0.5, capture_time)
		if player_count > 0:
			capture_progress = minf(1.0, capture_progress + rate * delta)
		elif enemy_count > 0:
			capture_progress = maxf(-1.0, capture_progress - rate * delta)

	if capture_progress >= 1.0:
		_set_controller(Unit.Team.PLAYER)
	elif capture_progress <= -1.0:
		_set_controller(Unit.Team.ENEMY)
	elif controlling_team == int(Unit.Team.PLAYER) and capture_progress <= 0.0:
		_set_controller(-1)
	elif controlling_team == int(Unit.Team.ENEMY) and capture_progress >= 0.0:
		_set_controller(-1)

	if not is_equal_approx(prev_progress, capture_progress) or prev_contested != is_contested:
		capture_state_changed.emit(capture_progress, is_contested, controlling_team)

	queue_redraw()


func _set_controller(next_team: int) -> void:
	if controlling_team == next_team:
		return
	controlling_team = next_team
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.set_uplink_controller(controlling_team, production_bonus_pct)
	controller_changed.emit(controlling_team)


func _draw() -> void:
	var base_col: Color = Color(0.62, 0.72, 0.82, 0.8)
	var status_text: String = "DATA HYPER-UPLINK  —  NEUTRAL"

	if is_contested:
		var blink: float = 0.65 + 0.35 * sin(_pulse_time * 8.0)
		base_col = Color(1.0, 0.78, 0.24, blink)
		status_text = "DATA HYPER-UPLINK  —  CONTESTED"
	elif controlling_team == int(Unit.Team.PLAYER):
		base_col = Color(0.18, 0.96, 0.90, 0.92)
		status_text = "HYPER-UPLINK CONTROLLED  (+%d%% PROD)" % int(round(production_bonus_pct * 100.0))
	elif controlling_team == int(Unit.Team.ENEMY):
		base_col = Color(1.0, 0.34, 0.28, 0.92)
		status_text = "HYPER-UPLINK  —  HOSTILE CONTROL"
	elif capture_progress > 0.01:
		base_col = Color(0.24, 0.92, 0.86, 0.85)
		status_text = "CAPTURING UPLINK  %d%%" % int(round(capture_progress * 100.0))
	elif capture_progress < -0.01:
		base_col = Color(1.0, 0.42, 0.32, 0.85)
		status_text = "HOSTILE CAPTURE  %d%%" % int(round(absf(capture_progress) * 100.0))

	# Outer capture ring + subtle fill
	draw_circle(Vector2.ZERO, capture_radius, Color(base_col.r, base_col.g, base_col.b, 0.06))
	draw_arc(Vector2.ZERO, capture_radius, 0.0, TAU, 64, Color(base_col.r, base_col.g, base_col.b, 0.55), 2.0, true)

	# Progress arc around perimeter
	var mag: float = clampf(absf(capture_progress), 0.0, 1.0)
	if mag > 0.01:
		var arc_col: Color = Color(0.18, 0.98, 0.92, 0.95) if capture_progress > 0.0 else Color(1.0, 0.34, 0.26, 0.95)
		draw_arc(Vector2.ZERO, capture_radius - 5.0, -PI * 0.5, -PI * 0.5 + TAU * mag, 56, arc_col, 4.0, true)

	# Central uplink pylon geometry
	var inner_pulse: float = 18.0 + 2.5 * sin(_pulse_time * 3.0)
	draw_circle(Vector2.ZERO, 26.0, Color(0.08, 0.13, 0.19, 0.95))
	draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, base_col, 2.2, true)
	draw_circle(Vector2.ZERO, inner_pulse * 0.55, Color(base_col.r, base_col.g, base_col.b, 0.88))

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var text_size: Vector2 = font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var label_pos: Vector2 = Vector2(-text_size.x * 0.5, -capture_radius - 8.0)
	draw_string(font, label_pos, status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, base_col)
