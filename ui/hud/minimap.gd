class_name TacticalMinimap
extends Control

const MapLandmarkScript = preload("res://scripts/world/map_landmark.gd")

@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
@export var camera_path: NodePath
@export var selection_controller_path: NodePath
@export var fog_system_path: NodePath
@export var refresh_rate_hz: float = 20.0

@onready var map_viewport: Control = %MapViewport
@onready var status_badge: Label = %StatusBadge

var _camera: RTSCamera = null
var _selection_controller: SelectionController = null
var _fog_system: FogOfWarSystem = null
var _match_manager: MatchManager = null
var _is_left_dragging: bool = false
var _redraw_timer: float = 0.0
var _ping_pos: Vector2 = Vector2.ZERO
var _ping_color: Color = Color(0.24, 0.96, 0.90, 1.0)
var _ping_timer: float = 0.0
var _alert_pings: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("tactical_minimap")
	if map_viewport != null:
		map_viewport.add_to_group("blocks_edge_pan")
		map_viewport.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if not map_viewport.draw.is_connected(_on_map_viewport_draw):
			map_viewport.draw.connect(_on_map_viewport_draw)
		if not map_viewport.gui_input.is_connected(_on_map_viewport_gui_input):
			map_viewport.gui_input.connect(_on_map_viewport_gui_input)
	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(_apply_faction_theme):
		TeamManager.teams_reconfigured.connect(_apply_faction_theme)
	_apply_faction_theme()
	call_deferred("_resolve_references")


func _apply_faction_theme() -> void:
	var fid: StringName = FactionHudTheme.resolve_local_faction_id()
	var pal: Dictionary = FactionHudTheme.get_palette(fid)
	var accent: Color = pal["accent"] as Color
	var frame_panel: PanelContainer = get_node_or_null("BottomLeftAnchor/FramePanel") as PanelContainer
	if frame_panel != null:
		frame_panel.add_to_group("blocks_edge_pan")
		frame_panel.add_theme_stylebox_override("panel", FactionHudTheme.make_panel_style(fid, true))
		FactionHudTheme.attach_frame_overlay(frame_panel, fid, &"minimap")
	var title_lbl: Label = get_node_or_null("BottomLeftAnchor/FramePanel/VBox/HeaderRow/TitleLabel") as Label
	if title_lbl != null:
		title_lbl.add_theme_color_override("font_color", accent)
	if status_badge != null:
		var badge_col: Color = (pal["primary"] as Color) if pal["style"] == &"brutalist" else Color(0.58, 0.80, 0.86, 0.88)
		status_badge.add_theme_color_override("font_color", badge_col)


func _resolve_references() -> void:
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as RTSCamera
	if _camera == null and is_inside_tree():
		_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera

	if not selection_controller_path.is_empty():
		_selection_controller = get_node_or_null(selection_controller_path) as SelectionController

	if not fog_system_path.is_empty():
		_fog_system = get_node_or_null(fog_system_path) as FogOfWarSystem
	if _fog_system == null and is_inside_tree():
		_fog_system = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if _fog_system != null:
		arena_bounds = _fog_system.arena_bounds
		if not _fog_system.visibility_updated.is_connected(_on_fog_updated):
			_fog_system.visibility_updated.connect(_on_fog_updated)

	if _match_manager == null and is_inside_tree():
		_match_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if _match_manager != null and not _match_manager.tactical_alert_triggered.is_connected(_on_tactical_alert_triggered):
		_match_manager.tactical_alert_triggered.connect(_on_tactical_alert_triggered)

	if map_viewport != null:
		map_viewport.queue_redraw()


func _on_tactical_alert_triggered(world_pos: Vector2, alert_type: StringName, _message: String) -> void:
	var col: Color = Color(0.24, 0.98, 0.86, 1.0)
	match alert_type:
		&"under_attack", &"damage":
			col = Color(1.0, 0.24, 0.24, 1.0)
		&"uplink_contested", &"uplink":
			col = Color(1.0, 0.80, 0.22, 1.0)
		&"tech_complete", &"upgrade", &"construction":
			col = Color(0.24, 0.98, 0.86, 1.0)
	_alert_pings.append({
		"world_pos": world_pos,
		"color": col,
		"age": 0.0,
		"duration": 2.4,
	})
	while _alert_pings.size() > 8:
		_alert_pings.pop_front()
	if map_viewport != null:
		map_viewport.queue_redraw()


func flash_ping(world_pos: Vector2, color: Color = Color(0.28, 0.96, 1.0, 1.0), duration: float = 1.8) -> void:
	_alert_pings.append({
		"world_pos": world_pos,
		"color": color,
		"age": 0.0,
		"duration": maxf(0.6, duration),
	})
	while _alert_pings.size() > 8:
		_alert_pings.pop_front()
	if map_viewport != null:
		map_viewport.queue_redraw()


func _process(delta: float) -> void:
	if _ping_timer > 0.0:
		_ping_timer = maxf(0.0, _ping_timer - delta)

	if not _alert_pings.is_empty():
		var active: Array[Dictionary] = []
		for p: Dictionary in _alert_pings:
			var next_age: float = float(p["age"]) + delta
			if next_age < float(p["duration"]):
				p["age"] = next_age
				active.append(p)
		_alert_pings = active

	_redraw_timer += delta
	var interval: float = 1.0 / maxf(5.0, refresh_rate_hz)
	if _redraw_timer >= interval or not _alert_pings.is_empty():
		_redraw_timer = 0.0
		if map_viewport != null:
			map_viewport.queue_redraw()
		if status_badge != null and _fog_system != null:
			if _is_post_match_inspection():
				status_badge.text = "INSPECT"
			else:
				status_badge.text = "FOG: ON" if _fog_system.fog_enabled else "FOG: OFF"


func _is_post_match_inspection() -> bool:
	if _match_manager != null and is_instance_valid(_match_manager):
		return bool(_match_manager.get("is_inspecting_post_match"))
	if is_inside_tree():
		var mm: Node = get_tree().get_first_node_in_group("match_manager")
		return mm != null and is_instance_valid(mm) and bool(mm.get("is_inspecting_post_match"))
	return false


func _on_fog_updated() -> void:
	if map_viewport != null:
		map_viewport.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _is_left_dragging or map_viewport == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_is_left_dragging = false
			return
	elif event is InputEventMouseMotion:
		var local_pos: Vector2 = map_viewport.get_local_mouse_position()
		var clamped_pos: Vector2 = Vector2(
			clampf(local_pos.x, 0.0, map_viewport.size.x),
			clampf(local_pos.y, 0.0, map_viewport.size.y)
		)
		_move_camera_to_minimap_point(clamped_pos)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if map_viewport == null or not is_visible_in_tree() or event.is_echo() or _is_post_match_inspection():
		return
	if not event.is_action_pressed("cmd_attack_move"):
		return
	if SettingsManager != null and SettingsManager.attack_move_mode != SettingsManager.AttackMoveMode.QUICK_CAST:
		return
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.ctrl_pressed or k.alt_pressed:
			return
	var local_pos: Vector2 = map_viewport.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, map_viewport.size).has_point(local_pos):
		return
	if _selection_controller == null:
		_resolve_references()
	if _selection_controller == null or _selection_controller.selected_units.is_empty():
		return
	var world_pos: Vector2 = _minimap_to_world(local_pos)
	var shift_queued: bool = Input.is_key_pressed(KEY_SHIFT)
	if event is InputEventKey:
		shift_queued = shift_queued or (event as InputEventKey).shift_pressed
	_selection_controller.issue_attack_move_at(world_pos, shift_queued)
	_ping_color = Color(1.0, 0.36, 0.28, 1.0)
	_ping_pos = _world_to_minimap(world_pos)
	_ping_timer = 0.45
	map_viewport.queue_redraw()
	get_viewport().set_input_as_handled()


func _on_map_viewport_gui_input(event: InputEvent) -> void:
	if map_viewport == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _is_post_match_inspection():
					_is_left_dragging = true
					_move_camera_to_minimap_point(mb.position)
					map_viewport.accept_event()
					return
				if _selection_controller == null:
					_resolve_references()
				if _selection_controller != null and _selection_controller.is_attack_move_targeting:
					var amove_world: Vector2 = _minimap_to_world(mb.position)
					_selection_controller.confirm_attack_move_target_at(amove_world, mb.shift_pressed or Input.is_key_pressed(KEY_SHIFT))
					_ping_color = Color(1.0, 0.36, 0.28, 1.0)
					_ping_pos = _world_to_minimap(amove_world)
					_ping_timer = 0.45
					map_viewport.queue_redraw()
					map_viewport.accept_event()
					return
				if _selection_controller != null and _selection_controller.is_patrol_targeting:
					var patrol_world: Vector2 = _minimap_to_world(mb.position)
					_selection_controller.confirm_patrol_target_at(patrol_world, mb.shift_pressed or Input.is_key_pressed(KEY_SHIFT))
					_ping_color = Color(0.22, 0.74, 0.98, 1.0)
					_ping_pos = _world_to_minimap(patrol_world)
					_ping_timer = 0.45
					map_viewport.queue_redraw()
					map_viewport.accept_event()
					return
				if _selection_controller != null and Input.is_action_pressed("cmd_attack_move") and not _selection_controller.selected_units.is_empty():
					var quick_world: Vector2 = _minimap_to_world(mb.position)
					_selection_controller.issue_attack_move_at(quick_world, mb.shift_pressed or Input.is_key_pressed(KEY_SHIFT))
					_ping_color = Color(1.0, 0.36, 0.28, 1.0)
					_ping_pos = _world_to_minimap(quick_world)
					_ping_timer = 0.45
					map_viewport.queue_redraw()
					map_viewport.accept_event()
					return
				if _selection_controller != null and _selection_controller.active_targeting_ability != null:
					return
				_is_left_dragging = true
				_move_camera_to_minimap_point(mb.position)
				map_viewport.accept_event()
			else:
				_is_left_dragging = false
				map_viewport.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _selection_controller == null:
				_resolve_references()
			if _selection_controller != null and _selection_controller.is_attack_move_targeting:
				_selection_controller.cancel_attack_move_targeting()
				map_viewport.accept_event()
				return
			if _selection_controller != null and _selection_controller.is_patrol_targeting:
				_selection_controller.cancel_patrol_targeting()
				map_viewport.accept_event()
				return
			_issue_order_at_minimap_point(mb.position)
			map_viewport.accept_event()
	elif event is InputEventMouseMotion and _is_left_dragging:
		var mm: InputEventMouseMotion = event
		_move_camera_to_minimap_point(mm.position)
		map_viewport.accept_event()


func _move_camera_to_minimap_point(local_pos: Vector2) -> void:
	if _camera == null:
		_resolve_references()
	if _camera == null:
		return
	var world_pos: Vector2 = _minimap_to_world(local_pos)
	_camera.center_on(world_pos)
	if map_viewport != null:
		map_viewport.queue_redraw()


func _issue_order_at_minimap_point(local_pos: Vector2) -> void:
	if _is_post_match_inspection():
		return
	if _selection_controller == null:
		_resolve_references()
	if _selection_controller == null:
		return
	var world_pos: Vector2 = _minimap_to_world(local_pos)
	var is_attack_move: bool = Input.is_action_pressed("cmd_attack_move")
	var shift_queued: bool = Input.is_key_pressed(KEY_SHIFT)
	if is_attack_move:
		_selection_controller.issue_attack_move_at(world_pos, shift_queued)
		_ping_color = Color(1.0, 0.36, 0.28, 1.0)
	else:
		_selection_controller.issue_right_click_at(world_pos, shift_queued)
		_ping_color = Color(0.24, 0.96, 0.88, 1.0)
	_ping_pos = _world_to_minimap(world_pos)
	_ping_timer = 0.45
	if map_viewport != null:
		map_viewport.queue_redraw()


func _on_map_viewport_draw() -> void:
	if map_viewport == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, map_viewport.size)
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return

	# 1. Arena backdrop + subtle tactical grid.
	map_viewport.draw_rect(rect, Color(0.06, 0.09, 0.13, 1.0), true)
	var grid_col: Color = Color(0.14, 0.24, 0.32, 0.35)
	for i: int in range(1, 4):
		var gx: float = rect.size.x * float(i) * 0.25
		var gy: float = rect.size.y * float(i) * 0.25
		map_viewport.draw_line(Vector2(gx, 0.0), Vector2(gx, rect.size.y), grid_col, 1.0)
		map_viewport.draw_line(Vector2(0.0, gy), Vector2(rect.size.x, gy), grid_col, 1.0)

	# 2. Terrain obstacle silhouettes.
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if not is_instance_valid(node) or not node.has_method("get_world_polygon"):
			continue
		var world_poly: PackedVector2Array = node.get_world_polygon()
		if world_poly.size() < 3:
			continue
		var mini_poly: PackedVector2Array = PackedVector2Array()
		mini_poly.resize(world_poly.size())
		for i: int in range(world_poly.size()):
			mini_poly[i] = _world_to_minimap(world_poly[i])
		map_viewport.draw_colored_polygon(mini_poly, Color(0.24, 0.32, 0.40, 0.96))
		map_viewport.draw_polyline(mini_poly + PackedVector2Array([mini_poly[0]]), Color(0.36, 0.62, 0.72, 0.65), 1.0)

	# 2.25. Destructible Barricades (distinct hashed amber/slate rectangular block matching orientation).
	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node) or bool(node.get("is_destroyed")) or not node.has_method("get_world_polygon"):
			continue
		var bar_poly: PackedVector2Array = node.call("get_world_polygon")
		if bar_poly.size() < 4:
			continue
		var mini_bar: PackedVector2Array = PackedVector2Array()
		mini_bar.resize(bar_poly.size())
		for bi: int in range(bar_poly.size()):
			mini_bar[bi] = _world_to_minimap(bar_poly[bi])
		map_viewport.draw_colored_polygon(mini_bar, Color(0.32, 0.30, 0.24, 0.96))
		# Diagonal amber hash stripes across the barricade quad
		var top_a: Vector2 = mini_bar[0]
		var top_b: Vector2 = mini_bar[1]
		var bot_b: Vector2 = mini_bar[2]
		var bot_a: Vector2 = mini_bar[3]
		var hash_col: Color = Color(0.98, 0.72, 0.20, 0.92)
		for hi: int in range(1, 4):
			var frac: float = float(hi) / 4.0
			var p_top: Vector2 = top_a.lerp(top_b, frac)
			var p_bot: Vector2 = bot_a.lerp(bot_b, clampf(frac - 0.18, 0.0, 1.0))
			map_viewport.draw_line(p_top, p_bot, hash_col, 1.1)
		map_viewport.draw_polyline(mini_bar + PackedVector2Array([mini_bar[0]]), Color(1.0, 0.78, 0.28, 0.96), 1.3)

	# 2.5. Map landmarks (subtle Technozen geometric pips).
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if not (node is MapLandmarkScript) or not is_instance_valid(node):
			continue
		var lm: MapLandmarkScript = node
		if not lm.show_on_minimap:
			continue
		var lp: Vector2 = _world_to_minimap(lm.global_position)
		var lcol: Color = lm.accent_color
		match lm.visual_style:
			MapLandmarkScript.VisualStyle.MONOLITH_SPIRE:
				var d_pts: PackedVector2Array = PackedVector2Array([
					lp + Vector2(0.0, -3.6),
					lp + Vector2(3.6, 0.0),
					lp + Vector2(0.0, 3.6),
					lp + Vector2(-3.6, 0.0),
				])
				map_viewport.draw_colored_polygon(d_pts, Color(lcol.r, lcol.g, lcol.b, 0.85))
				map_viewport.draw_polyline(d_pts + PackedVector2Array([d_pts[0]]), Color(0.92, 0.98, 1.0, 0.85), 1.0)
			MapLandmarkScript.VisualStyle.RELAY_ARCH:
				var arch_col: Color = Color(lcol.r, lcol.g, lcol.b, 0.82)
				map_viewport.draw_line(lp + Vector2(-5.0, -1.6), lp + Vector2(5.0, -1.6), arch_col, 1.2)
				map_viewport.draw_line(lp + Vector2(-5.0, 1.6), lp + Vector2(5.0, 1.6), arch_col, 1.2)
			MapLandmarkScript.VisualStyle.CAPACITOR_PYLON:
				map_viewport.draw_rect(Rect2(lp - Vector2(1.8, 1.8), Vector2(3.6, 3.6)), Color(lcol.r, lcol.g, lcol.b, 0.82), true)
			MapLandmarkScript.VisualStyle.PLAZA_BEACON:
				map_viewport.draw_arc(lp, 5.4, 0.0, TAU, 14, Color(lcol.r, lcol.g, lcol.b, 0.42), 1.1)

	# 3. Resource nodes (Biomass green, Silica gold, Compute Vents violet/cyan).
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted():
			continue
		var p: Vector2 = _world_to_minimap(rn.global_position)
		if rn.is_vent:
			map_viewport.draw_arc(p, 3.4, 0.0, TAU, 12, Color(0.58, 0.64, 1.0, 0.96), 1.3)
			map_viewport.draw_circle(p, 1.5, Color(0.32, 0.94, 1.0, 0.92))
		elif rn.resource_type == &"silica":
			map_viewport.draw_circle(p, 2.3, Color(0.98, 0.78, 0.28, 0.95))
		else:
			map_viewport.draw_circle(p, 2.2, Color(0.24, 0.94, 0.56, 0.92))

	# 4. Central Data Hyper-Uplink (crisp concentric gold/white beacon ring + diamond core).
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.0045)
	for node: Node in get_tree().get_nodes_in_group("hyper_uplinks"):
		if not (node is HyperUplink) or not is_instance_valid(node):
			continue
		var uplink: HyperUplink = node
		var up: Vector2 = _world_to_minimap(uplink.global_position)
		var live_vis: bool = _fog_system == null or not _fog_system.fog_enabled or _fog_system.is_world_pos_visible(uplink.global_position)
		var u_col: Color = Color(1.0, 0.84, 0.30, 0.96)
		if live_vis:
			if uplink.is_contested:
				u_col = Color(1.0, 0.80, 0.24, 1.0)
			elif uplink.controlling_team >= 0:
				u_col = TeamManager.get_team_color(uplink.controlling_team) if TeamManager != null else (Color(0.18, 0.98, 0.90, 1.0) if uplink.controlling_team == int(Unit.Team.PLAYER) else Color(1.0, 0.34, 0.28, 1.0))
		var scale_x: float = rect.size.x / maxf(1.0, arena_bounds.size.x)
		map_viewport.draw_arc(up, maxf(7.5, uplink.capture_radius * scale_x), 0.0, TAU, 24, Color(1.0, 0.86, 0.34, 0.58 + pulse * 0.26), 1.3)
		map_viewport.draw_arc(up, lerpf(4.8, 9.2, pulse), 0.0, TAU, 18, Color(0.98, 0.99, 1.0, (1.0 - pulse) * 0.78), 1.1)
		var dr: float = 4.0 + pulse * 0.6
		var diamond: PackedVector2Array = PackedVector2Array([
			up + Vector2(0.0, -dr),
			up + Vector2(dr, 0.0),
			up + Vector2(0.0, dr),
			up + Vector2(-dr, 0.0),
		])
		map_viewport.draw_colored_polygon(diamond, u_col)
		map_viewport.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(0.98, 1.0, 1.0, 0.96), 1.2)

	# 4.5. Capturable Sensor Relays (radar-diamond + subtle sensor ring).
	for node: Node in get_tree().get_nodes_in_group("sensor_relays"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var relay: Node2D = node as Node2D
		var rp: Vector2 = _world_to_minimap(relay.global_position)
		var r_vis: bool = _fog_system == null or not _fog_system.fog_enabled or _fog_system.is_world_pos_visible(relay.global_position)
		var r_col: Color = Color(0.56, 0.78, 0.88, 0.92)
		var r_active: bool = relay.has_method("is_active") and bool(relay.call("is_active"))
		var r_contested: bool = relay.has_method("is_contested") and bool(relay.call("is_contested"))
		var ctrl_t: int = int(relay.get("controlling_team"))
		var viewer_r: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		var is_allied_r: bool = r_active and ctrl_t >= 0 and (viewer_r < 0 or (TeamManager.are_allies(viewer_r, ctrl_t) if TeamManager != null else (ctrl_t == int(Unit.Team.PLAYER))))
		if r_vis or is_allied_r:
			if r_contested:
				r_col = Color(1.0, 0.78, 0.24, 1.0)
			elif r_active and ctrl_t >= 0:
				r_col = TeamManager.get_team_color(ctrl_t) if TeamManager != null else (Color(0.22, 0.96, 0.88, 1.0) if ctrl_t == int(Unit.Team.PLAYER) else Color(1.0, 0.36, 0.28, 1.0))
		if is_allied_r:
			var r_scale: float = rect.size.x / maxf(1.0, arena_bounds.size.x)
			var vis_mini_r: float = clampf(float(relay.get("vision_radius")) * r_scale, 6.0, 48.0)
			map_viewport.draw_arc(rp, vis_mini_r, 0.0, TAU, 20, Color(r_col.r, r_col.g, r_col.b, 0.28), 1.0)
		map_viewport.draw_arc(rp, 5.2 + pulse * 1.4, 0.0, TAU, 16, Color(r_col.r, r_col.g, r_col.b, 0.56), 1.0)
		var r_dia: PackedVector2Array = PackedVector2Array([
			rp + Vector2(0.0, -3.5),
			rp + Vector2(3.5, 0.0),
			rp + Vector2(0.0, 3.5),
			rp + Vector2(-3.5, 0.0),
		])
		map_viewport.draw_colored_polygon(r_dia, r_col)
		map_viewport.draw_polyline(r_dia + PackedVector2Array([r_dia[0]]), Color(0.94, 0.99, 1.0, 0.90), 1.0)

	# 5. Fog of War shroud overlay over terrain/landmarks/resources/uplink.
	if _fog_system != null and _fog_system.fog_enabled and _fog_system.fog_texture != null:
		map_viewport.draw_texture_rect(_fog_system.fog_texture, rect, false)

	# 5.5. Salvage Cores (pulsing 4.0px amber/cyan diamonds when explored/visible).
	for node: Node in get_tree().get_nodes_in_group("salvage_cores"):
		if not is_instance_valid(node) or not (node is Node2D) or bool(node.get("is_claimed")):
			continue
		var sc: Node2D = node as Node2D
		if _fog_system != null and _fog_system.fog_enabled and not _fog_system.is_world_pos_explored(sc.global_position):
			continue
		var sp: Vector2 = _world_to_minimap(sc.global_position)
		var sr: float = 3.4 + pulse * 1.1
		var s_dia: PackedVector2Array = PackedVector2Array([
			sp + Vector2(0.0, -sr),
			sp + Vector2(sr, 0.0),
			sp + Vector2(0.0, sr),
			sp + Vector2(-sr, 0.0),
		])
		map_viewport.draw_colored_polygon(s_dia, Color(1.0, 0.78, 0.24, 0.96))
		map_viewport.draw_polyline(s_dia + PackedVector2Array([s_dia[0]]), Color(0.32, 0.96, 1.0, 0.96), 1.1)

	# 6. Buildings (Command Hubs = 7x7 bordered square; Standard = 4.5x4.5 solid square).
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed:
			continue
		var is_hostile_b: bool = TeamManager.are_enemies(viewer_team, int(b.team)) if (TeamManager != null and viewer_team >= 0) else (b.team == Unit.Team.ENEMY)
		if is_hostile_b and not b.visible:
			continue
		var bp: Vector2 = _world_to_minimap(b.global_position)
		var is_hub: bool = b.is_command_hub()
		var sz: float = 7.0 if is_hub else 4.5
		var col: Color = TeamManager.get_team_color(int(b.team)) if TeamManager != null else (Color(0.22, 0.96, 0.88, 1.0) if b.team == Unit.Team.PLAYER else Color(1.0, 0.32, 0.26, 0.95))
		if is_hostile_b and _fog_system != null and _fog_system.fog_enabled and not _fog_system.is_world_pos_visible(b.global_position):
			col.a = 0.62
		var b_rect: Rect2 = Rect2(bp - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz))
		map_viewport.draw_rect(b_rect, col, true)
		if is_hub:
			map_viewport.draw_rect(b_rect.grow(0.5), Color(0.96, 0.99, 1.0, 0.92 * col.a), false, 1.1)
		else:
			map_viewport.draw_rect(b_rect, Color(0.03, 0.06, 0.10, 0.75 * col.a), false, 0.9)

	# 8. Units (Heavy = 5.5px upward triangle; Infantry/Support = 2.6px dot; Workers = compact 2.0px dot).
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node
		if u.is_dead or u.is_staffed:
			continue
		var is_hostile_u: bool = TeamManager.are_enemies(viewer_team, int(u.team)) if (TeamManager != null and viewer_team >= 0) else (u.team == Unit.Team.ENEMY)
		if is_hostile_u and not u.visible:
			continue
		var upos: Vector2 = _world_to_minimap(u.global_position)
		var ucol: Color = TeamManager.get_team_color(int(u.team)) if TeamManager != null else (Color(0.26, 0.96, 1.0, 1.0) if u.team == Unit.Team.PLAYER else Color(1.0, 0.30, 0.24, 1.0))
		var shape: StringName = u.data.minimap_icon_shape if u.data != null else &"dot"
		var is_worker: bool = (shape == &"worker") or (u.data != null and u.data.is_worker_class() and not u.data.can_staff_compute)
		var is_heavy: bool = (shape == &"triangle_heavy") or (u.data != null and u.data.is_heavy_unit())
		var is_flanker: bool = (u.data != null and u.data.has_tag(&"flanker"))
		if viewer_team >= 0 and int(u.team) == viewer_team:
			if is_worker:
				ucol = Color(0.32, 0.94, 0.62, 0.88)
			elif is_flanker:
				ucol = Color(0.98, 0.86, 0.32, 1.0)
		if is_heavy:
			var half_b: float = 2.85
			var tri: PackedVector2Array = PackedVector2Array([
				upos + Vector2(0.0, -3.2),
				upos + Vector2(half_b, 2.3),
				upos + Vector2(-half_b, 2.3),
			])
			map_viewport.draw_colored_polygon(tri, ucol)
			map_viewport.draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0.03, 0.05, 0.08, 0.92), 1.0)
		elif is_worker:
			map_viewport.draw_circle(upos, 1.9, ucol)
		else:
			map_viewport.draw_circle(upos, 2.55, ucol)

	# 9. Minimap command ping ripple.
	if _ping_timer > 0.0:
		var pt: float = 1.0 - (_ping_timer / 0.45)
		var ring_col: Color = _ping_color
		ring_col.a = (1.0 - pt) * 0.95
		map_viewport.draw_arc(_ping_pos, lerpf(3.0, 13.0, pt), 0.0, TAU, 16, ring_col, 1.6)

	# 9.5. Tactical Alert Pings (two staggered expanding rings + bright center diamond above Fog of War).
	for ping: Dictionary in _alert_pings:
		var age: float = float(ping["age"])
		var dur: float = maxf(0.1, float(ping["duration"]))
		var u: float = clampf(age / dur, 0.0, 1.0)
		var base_fade: float = 1.0 - u
		var p_col: Color = ping["color"] as Color
		var mp: Vector2 = _world_to_minimap(ping["world_pos"] as Vector2)

		# Two staggered expanding pulse rings cycling twice over the 2.4s lifetime
		for k: int in range(2):
			var phase: float = fmod(u * 2.2 + float(k) * 0.5, 1.0)
			var r_px: float = lerpf(4.0, 22.0, phase)
			var ring_a: float = (1.0 - phase) * base_fade * 0.95
			if ring_a > 0.02:
				map_viewport.draw_arc(mp, r_px, 0.0, TAU, 24, Color(p_col.r, p_col.g, p_col.b, ring_a), 1.8)

		# Bright center diamond pip
		var d_sz: float = lerpf(4.5, 2.2, u)
		var d_pts: PackedVector2Array = PackedVector2Array([
			mp + Vector2(0.0, -d_sz),
			mp + Vector2(d_sz, 0.0),
			mp + Vector2(0.0, d_sz),
			mp + Vector2(-d_sz, 0.0),
		])
		map_viewport.draw_colored_polygon(d_pts, Color(p_col.r, p_col.g, p_col.b, base_fade))
		map_viewport.draw_polyline(d_pts + PackedVector2Array([d_pts[0]]), Color(1.0, 1.0, 1.0, base_fade * 0.9), 1.0)

	# 10. White Camera Viewport Rectangle.
	if _camera != null and is_instance_valid(_camera):
		var vp_size: Vector2 = get_viewport().get_visible_rect().size / _camera.zoom
		var cam_world_rect: Rect2 = Rect2(_camera.global_position - vp_size * 0.5, vp_size)
		var tl: Vector2 = _world_to_minimap(cam_world_rect.position)
		var br: Vector2 = _world_to_minimap(cam_world_rect.end)
		var cam_mini: Rect2 = Rect2(tl, br - tl).intersection(rect)
		if cam_mini.has_area():
			map_viewport.draw_rect(cam_mini, Color(0.96, 0.99, 1.0, 0.92), false, 1.5)

	# Crisp outer frame line.
	map_viewport.draw_rect(rect.grow(-0.5), Color(0.22, 0.68, 0.78, 0.85), false, 1.2)


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var sz: Vector2 = map_viewport.size
	var nx: float = (world_pos.x - arena_bounds.position.x) / maxf(1.0, arena_bounds.size.x)
	var ny: float = (world_pos.y - arena_bounds.position.y) / maxf(1.0, arena_bounds.size.y)
	return Vector2(nx * sz.x, ny * sz.y)


func _minimap_to_world(local_pos: Vector2) -> Vector2:
	var sz: Vector2 = map_viewport.size
	var nx: float = clampf(local_pos.x / maxf(1.0, sz.x), 0.0, 1.0)
	var ny: float = clampf(local_pos.y / maxf(1.0, sz.y), 0.0, 1.0)
	return Vector2(
		arena_bounds.position.x + nx * arena_bounds.size.x,
		arena_bounds.position.y + ny * arena_bounds.size.y
	)
