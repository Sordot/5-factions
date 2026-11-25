class_name SensorRelay
extends Node2D

## Capturable neutral tactical Sensor Relay tower.
## Holding a living ground unit inside capture_radius grants a wide unobstructed
## Fog-of-War vision radius to the controlling team and its allies.

enum RelayState {
	IDLE = 0,
	ACTIVE = 1,
	CONTESTED = 2,
}

signal state_changed(relay: SensorRelay)
signal captured(relay: SensorRelay, new_team: int)

@export var relay_name: String = "Sensor Relay"
@export var capture_radius: float = 115.0
@export var vision_radius: float = 520.0
@export var ignores_los_blockers: bool = true
@export var selection_radius: float = 34.0

var controlling_team: int = -1
var controlling_alliance: int = -1
var relay_state: RelayState = RelayState.IDLE
var is_selected: bool = false
var is_hovered: bool = false

var _scan_timer: float = 0.0
var _sweep_angle: float = 0.0
var _anim_time: float = 0.0
var _lock_pulse: float = 0.0
var _occupant_count: int = 0

const SCAN_INTERVAL: float = 0.20


func _ready() -> void:
	add_to_group("sensor_relays")
	z_index = -3
	queue_redraw()


func _process(delta: float) -> void:
	_anim_time += delta
	match relay_state:
		RelayState.ACTIVE:
			_sweep_angle = wrapf(_sweep_angle + delta * 1.45, 0.0, TAU)
		RelayState.CONTESTED:
			_sweep_angle = wrapf(_sweep_angle + delta * 0.65, 0.0, TAU)
		_:
			_sweep_angle = wrapf(_sweep_angle + delta * 0.28, 0.0, TAU)

	if _lock_pulse > 0.0:
		_lock_pulse = maxf(0.0, _lock_pulse - delta * 1.35)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer < SCAN_INTERVAL:
		return
	_scan_timer = 0.0
	_evaluate_occupancy()


func is_active() -> bool:
	return relay_state == RelayState.ACTIVE and controlling_team >= 0


func is_contested() -> bool:
	return relay_state == RelayState.CONTESTED


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_squared_to(world_point) <= selection_radius * selection_radius


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	queue_redraw()


func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	queue_redraw()


func _evaluate_occupancy() -> void:
	if not is_inside_tree():
		return

	var alliances_present: Dictionary = {} # alliance_id -> representative_team
	var total_units: int = 0
	var r_sq: float = capture_radius * capture_radius

	var candidates: Array = (
		SpatialGrid.query_units_in_radius(global_position, capture_radius + 32.0)
		if SpatialGrid != null
		else get_tree().get_nodes_in_group("units")
	)
	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var u: Unit = node as Unit
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			continue
		if global_position.distance_squared_to(u.global_position) > r_sq:
			continue
		total_units += 1
		var tid: int = int(u.team)
		var aid: int = TeamManager.get_team_alliance(tid) if TeamManager != null else tid
		if not alliances_present.has(aid):
			alliances_present[aid] = tid

	var next_state: RelayState = RelayState.IDLE
	var next_team: int = -1
	var next_alliance: int = -1

	if alliances_present.size() == 1:
		next_state = RelayState.ACTIVE
		next_alliance = int(alliances_present.keys()[0])
		next_team = int(alliances_present[next_alliance])
	elif alliances_present.size() > 1:
		next_state = RelayState.CONTESTED

	var changed: bool = (
		next_state != relay_state
		or next_team != controlling_team
		or next_alliance != controlling_alliance
		or total_units != _occupant_count
	)

	var newly_activated_alliance: bool = (
		next_state == RelayState.ACTIVE
		and (relay_state != RelayState.ACTIVE or next_alliance != controlling_alliance)
	)

	relay_state = next_state
	controlling_team = next_team
	controlling_alliance = next_alliance
	_occupant_count = total_units

	if newly_activated_alliance:
		_lock_pulse = 1.0
		_play_capture_feedback()
		captured.emit(self, controlling_team)

	if changed:
		state_changed.emit(self)
		queue_redraw()


func _play_capture_feedback() -> void:
	if AudioManager == null or controlling_team < 0:
		return
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_local_allied: bool = false
	if viewer < 0:
		is_local_allied = true
	elif TeamManager != null:
		is_local_allied = TeamManager.are_allies(viewer, controlling_team)
	else:
		is_local_allied = (controlling_team == int(Unit.Team.PLAYER))
	if is_local_allied:
		AudioManager.play_sfx(&"relay_captured", -3.0, 0.02)


func _get_state_color() -> Color:
	match relay_state:
		RelayState.ACTIVE:
			if controlling_team >= 0 and TeamManager != null:
				return TeamManager.get_team_color(controlling_team)
			return Color(0.22, 0.96, 0.88, 1.0) if controlling_team == int(Unit.Team.PLAYER) else Color(1.0, 0.36, 0.28, 1.0)
		RelayState.CONTESTED:
			return Color(1.0, 0.78, 0.24, 1.0)
		_:
			return Color(0.56, 0.74, 0.84, 1.0)


func _is_allied_to_viewer() -> bool:
	if not is_active():
		return false
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	if viewer < 0:
		return true
	if TeamManager != null:
		return TeamManager.are_allies(viewer, controlling_team)
	return controlling_team == int(Unit.Team.PLAYER)


func _draw() -> void:
	var accent: Color = _get_state_color()
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.2)

	# 1. Capture zone perimeter ring
	var ring_alpha: float = 0.26 if relay_state == RelayState.IDLE else (0.50 + pulse * 0.16)
	var ring_fill_alpha: float = 0.035 if relay_state == RelayState.IDLE else (0.075 + pulse * 0.025)
	draw_circle(Vector2.ZERO, capture_radius, Color(accent.r, accent.g, accent.b, ring_fill_alpha))
	_draw_dashed_ring(Vector2.ZERO, capture_radius, Color(accent.r, accent.g, accent.b, ring_alpha), 1.6, 28)

	# 2. Expanding radar lock-on pulse on capture
	if _lock_pulse > 0.001:
		var t_lock: float = 1.0 - _lock_pulse
		var lock_r: float = lerpf(24.0, vision_radius * 0.55, t_lock)
		draw_arc(Vector2.ZERO, lock_r, 0.0, TAU, 48, Color(accent.r, accent.g, accent.b, _lock_pulse * 0.62), 2.2, true)

	# 3. Vision radius preview ring when selected or actively held by local alliance (subtle)
	if is_selected or _is_allied_to_viewer():
		var vis_alpha: float = 0.34 if is_selected else 0.14
		_draw_dashed_ring(Vector2.ZERO, vision_radius, Color(accent.r, accent.g, accent.b, vis_alpha), 1.4 if is_selected else 1.0, 56)

	# 4. Rotating translucent radar sweep wedge
	var sweep_r: float = capture_radius * (1.12 if relay_state == RelayState.ACTIVE else 0.86)
	var wedge_span: float = 0.58 if relay_state == RelayState.ACTIVE else 0.32
	var wedge_alpha: float = 0.19 if relay_state == RelayState.ACTIVE else 0.09
	var wedge_pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var steps: int = 8
	for i: int in range(steps + 1):
		var ang: float = _sweep_angle - wedge_span * (1.0 - float(i) / float(steps))
		wedge_pts.append(Vector2.RIGHT.rotated(ang) * sweep_r)
	draw_colored_polygon(wedge_pts, Color(accent.r, accent.g, accent.b, wedge_alpha))
	draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(_sweep_angle) * sweep_r, Color(accent.r, accent.g, accent.b, 0.68 if relay_state == RelayState.ACTIVE else 0.32), 1.6, true)

	# 5. Hover / Selection highlight ring
	if is_hovered and not is_selected:
		draw_arc(Vector2.ZERO, selection_radius + 2.0, 0.0, TAU, 32, Color(0.28, 0.88, 1.0, 0.58), 1.6, true)
	if is_selected:
		draw_circle(Vector2.ZERO, selection_radius + 3.0, Color(accent.r, accent.g, accent.b, 0.12))
		draw_arc(Vector2.ZERO, selection_radius + 3.0, 0.0, TAU, 36, Color(0.95, 0.99, 1.0, 0.92), 2.0, true)

	# 6. Octagonal Technozen sensor tower plinth & dish
	var oct_outer: PackedVector2Array = _make_octagon(22.0)
	var oct_inner: PackedVector2Array = _make_octagon(14.5)
	draw_colored_polygon(oct_outer, Color(0.11, 0.16, 0.22, 0.96))
	draw_polyline(oct_outer + PackedVector2Array([oct_outer[0]]), Color(0.68, 0.84, 0.92, 0.82), 1.6, true)
	draw_colored_polygon(oct_inner, Color(0.17, 0.25, 0.34, 0.96))
	draw_polyline(oct_inner + PackedVector2Array([oct_inner[0]]), Color(accent.r, accent.g, accent.b, 0.90), 1.5, true)

	# Four stabilizer struts
	for k: int in range(4):
		var sa: float = float(k) * (PI * 0.5) + PI * 0.25
		var dir: Vector2 = Vector2.RIGHT.rotated(sa)
		draw_line(dir * 14.0, dir * 25.0, Color(0.84, 0.92, 0.98, 0.72), 2.2, true)

	# Rotating radar receiver dish bar
	var dish_dir: Vector2 = Vector2.RIGHT.rotated(_sweep_angle)
	var dish_perp: Vector2 = dish_dir.orthogonal()
	draw_line(-dish_perp * 11.0 - dish_dir * 2.0, dish_perp * 11.0 - dish_dir * 2.0, Color(0.94, 0.98, 1.0, 0.94), 2.4, true)
	draw_line(Vector2.ZERO, dish_dir * 10.5, accent, 2.0, true)
	draw_circle(Vector2.ZERO, 4.8, accent)
	draw_circle(Vector2.ZERO, 2.2, Color(0.96, 1.0, 1.0, 0.96))


func _make_octagon(radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(8)
	for i: int in range(8):
		var ang: float = float(i) * (TAU / 8.0) + (PI / 8.0)
		pts[i] = Vector2(cos(ang), sin(ang)) * radius
	return pts


func _draw_dashed_ring(center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(8, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.54
		draw_arc(center, radius, a0, a1, 4, col, width, true)


func get_inspection_data() -> Dictionary:
	var accent: Color = _get_state_color()
	var status_str: String = "IDLE (UNOCCUPIED)"
	var controller_str: String = "Neutral"
	var affiliation: StringName = &"neutral"

	match relay_state:
		RelayState.ACTIVE:
			status_str = "ACTIVE — BROADCASTING"
			if TeamManager != null and controlling_team >= 0:
				controller_str = TeamManager.get_team_name(controlling_team)
			else:
				controller_str = "Player" if controlling_team == int(Unit.Team.PLAYER) else "Hostile"
			affiliation = &"player" if _is_allied_to_viewer() else &"enemy"
		RelayState.CONTESTED:
			status_str = "CONTESTED — SIGNAL JAMMED"
			controller_str = "Contested"
			affiliation = &"neutral"

	var stats: Array[Dictionary] = [
		{"label": "Status", "value": status_str, "color": accent},
		{"label": "Controller", "value": controller_str, "color": accent},
		{"label": "Vision", "value": "%d px (%s)" % [int(round(vision_radius)), "Unobstructed" if ignores_los_blockers else "LOS"]},
		{"label": "Capture Zone", "value": "%d px (%d Units)" % [int(round(capture_radius)), _occupant_count]},
	]

	return {
		"title": relay_name,
		"subtitle": "TACTICAL RECONNAISSANCE RELAY",
		"affiliation": affiliation,
		"accent_color": accent,
		"ring_color": accent,
		"show_hp_bar": false,
		"show_primary_bar": false,
		"stats": stats,
		"is_commandable": false,
		"readonly_label": "HOLD GROUND UNIT IN RING TO BROADCAST %dpx UNOBSTRUCTED VISION" % int(round(vision_radius)),
	}
