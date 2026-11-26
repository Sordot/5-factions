class_name TacticalGlanceOverlay
extends Node2D

## Non-intrusive Tactical Alt Glance Overlay (Milestone 3.5a).
## Polls KEY_ALT without consuming any input events so Alt+1..9 group stealing
## and Alt build-grid-snap inversion remain 100% untouched.

const FADE_IN_DURATION: float = 0.10
const FADE_OUT_DURATION: float = 0.12

var _controller: Node = null
var _alpha: float = 0.0
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("tactical_glance_overlay")
	z_index = 62


func bind_selection_controller(controller: Node) -> void:
	_controller = controller


func _should_be_active() -> bool:
	if not Input.is_key_pressed(KEY_ALT):
		return false
	if not is_inside_tree() or get_tree().paused:
		return false
	# Never show while a modal overlay is open.
	var pause_m: Node = get_tree().get_first_node_in_group("pause_menu")
	if pause_m != null and is_instance_valid(pause_m):
		if pause_m.has_method("is_pause_open") and bool(pause_m.call("is_pause_open")):
			return false
		if pause_m.has_method("is_settings_open") and bool(pause_m.call("is_settings_open")):
			return false
		if pause_m.has_method("is_tech_tree_open") and bool(pause_m.call("is_tech_tree_open")):
			return false
		if pause_m.has_method("is_controls_help_open") and bool(pause_m.call("is_controls_help_open")):
			return false
	if get_tree().get_first_node_in_group("settings_menu") != null:
		return false
	if get_tree().get_first_node_in_group("tech_tree_overlay") != null:
		return false
	if get_tree().get_first_node_in_group("controls_reference_overlay") != null:
		return false
	var end_ov: Node = get_tree().get_first_node_in_group("match_end_overlay")
	if end_ov != null and is_instance_valid(end_ov) and end_ov.has_method("is_summary_visible") and bool(end_ov.call("is_summary_visible")):
		return false
	# Do not interfere with Alt temporary grid-snap inversion during build placement.
	if _controller != null and is_instance_valid(_controller):
		var ab: Variant = _controller.get("active_targeting_ability")
		if ab != null and ab is AbilityData and (ab as AbilityData).target_type == AbilityData.TargetType.BUILD_PLACEMENT:
			return false
	return true


func _process(delta: float) -> void:
	var active: bool = _should_be_active()
	if active:
		_alpha = minf(1.0, _alpha + delta / FADE_IN_DURATION)
	elif _alpha > 0.0:
		_alpha = maxf(0.0, _alpha - delta / FADE_OUT_DURATION)

	if _alpha <= 0.001:
		if _alpha > 0.0:
			_alpha = 0.0
			queue_redraw()
		return

	_pulse_time += delta
	queue_redraw()


func _get_camera_world_rect() -> Rect2:
	var cam: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	if cam == null:
		return Rect2(-2000.0, -2000.0, 4000.0, 4000.0)
	var vp_sz: Vector2 = get_viewport_rect().size / maxf(0.25, cam.zoom.x)
	return Rect2(cam.global_position - vp_sz * 0.5, vp_sz).grow(120.0)


func _draw() -> void:
	if _alpha <= 0.005 or not is_inside_tree():
		return

	var a: float = _alpha
	var font: Font = ThemeDB.fallback_font
	var view_rect: Rect2 = _get_camera_world_rect()
	var is_spec: bool = TeamManager != null and TeamManager.is_spectator_mode()
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var fid: StringName = FactionHudTheme.resolve_local_faction_id()
	var pal: Dictionary = FactionHudTheme.get_palette(fid)
	var faction_accent: Color = pal["accent"] as Color
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 5.0)

	# 1. Friendly Buildings: Rally lines, Production/Overclock rings, Idle tags, Staffing pills, Turret range rings
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node as Building
		if b.is_destroyed or b.is_queued_for_deletion() or not b.is_constructed:
			continue
		var is_owned: bool = is_spec or (int(b.team) == local_team)
		if not is_owned:
			continue

		var b_pos: Vector2 = to_local(b.global_position)
		var team_col: Color = TeamManager.get_team_color(int(b.team)) if TeamManager != null else faction_accent

		# 1a. All friendly production rally lines (even if off-viewport start/end crosses view)
		if b.has_rally():
			var rally_world: Vector2 = b.get_rally_point()
			if view_rect.has_point(b.global_position) or view_rect.has_point(rally_world):
				var r_pos: Vector2 = to_local(rally_world)
				var r_col: Color = Color(team_col.r, team_col.g, team_col.b, 0.58 * a)
				_draw_dashed_line(b_pos, r_pos, r_col, 1.8, 12.0, 8.0)
				draw_circle(r_pos, 4.5, Color(team_col.r, team_col.g, team_col.b, 0.78 * a))
				# Compact rally flag pennon
				draw_line(r_pos, r_pos + Vector2(0.0, -14.0), Color(0.95, 0.99, 1.0, 0.82 * a), 1.6, true)
				draw_colored_polygon(
					PackedVector2Array([r_pos + Vector2(0.0, -14.0), r_pos + Vector2(10.0, -10.5), r_pos + Vector2(0.0, -7.0)]),
					Color(team_col.r, team_col.g, team_col.b, 0.85 * a)
				)

		if not view_rect.has_point(b.global_position):
			continue

		# 1b. Production / Overclock radial arc OR Idle military production badge
		var q_size: int = b.get_training_queue_size()
		if q_size > 0:
			var st: Dictionary = b.get_active_training_status()
			var prog: float = clampf(float(st.get("progress", 0.0)), 0.0, 1.0)
			var is_oc: bool = b.is_overclocked()
			var ring_r: float = b.footprint_radius + 7.0
			var arc_col: Color = Color(1.0, 0.624, 0.110, 0.92 * a) if is_oc else Color(faction_accent.r, faction_accent.g, faction_accent.b, 0.88 * a)
			draw_arc(b_pos, ring_r, 0.0, TAU, 36, Color(0.06, 0.10, 0.14, 0.55 * a), 3.6, true)
			if prog > 0.01:
				draw_arc(b_pos, ring_r, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, arc_col, 3.4, true)
			var pct_txt: String = "%d%%%s" % [int(round(prog * 100.0)), " OC" if is_oc else ""]
			_draw_pill(font, b_pos + Vector2(0.0, -b.footprint_radius - 16.0), pct_txt, arc_col, a)
		elif b.is_military_production_building():
			var idle_col: Color = Color(1.0, 0.78, 0.24, (0.72 + pulse * 0.28) * a)
			_draw_pill(font, b_pos + Vector2(b.footprint_radius * 0.55, -b.footprint_radius - 10.0), "IDLE", idle_col, a)

		# 1c. Compute facility staffing pill (0/max highlighted amber)
		if b.max_staff_slots > 0:
			var cur_st: int = b.get_assigned_engineer_count()
			var st_col: Color = Color(1.0, 0.72, 0.22, 0.96 * a) if cur_st <= 0 else Color(0.28, 0.92, 1.0, 0.94 * a)
			_draw_pill(font, b_pos + Vector2(0.0, b.footprint_radius + 14.0), "ENG %d/%d" % [cur_st, b.max_staff_slots], st_col, a)

		# 1d. Friendly static defense turret firing range ring
		if b.has_turret and b.turret_attack_range > 0.0:
			var t_rng: float = b.get_effective_turret_attack_range() + b.footprint_radius
			_draw_dashed_ring(b_pos, t_rng, Color(1.0, 0.52, 0.30, 0.22 * a), 1.5, 44)

	# 2. Friendly Deployed Siege Units: subtle firing range rings
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node as Unit
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			continue
		if not is_spec and int(u.team) != local_team:
			continue
		if not u.is_deployed():
			continue
		if not view_rect.has_point(u.global_position):
			continue
		var u_pos: Vector2 = to_local(u.global_position)
		var u_r: float = u.data.collision_radius if u.data != null else 18.0
		var max_rng: float = u.get_effective_attack_range() + u_r
		_draw_dashed_ring(u_pos, max_rng, Color(1.0, 0.624, 0.110, 0.22 * a), 1.6, 48)
		var min_rng: float = u.get_effective_min_attack_range()
		if min_rng > 0.0:
			_draw_dashed_ring(u_pos, min_rng + u_r, Color(1.0, 0.34, 0.32, 0.18 * a), 1.2, 24)

	# 3. Visible / Explored ResourceNode Saturation Badges inside viewport
	var sat_team: int = local_team if local_team >= 0 else 0
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.is_depleted() or rn.is_vent:
			continue
		if not view_rect.has_point(rn.global_position):
			continue
		if fog != null and fog.fog_enabled and not fog.is_world_pos_explored(rn.global_position):
			continue
		var max_h: int = rn.get_effective_max_harvesters(sat_team) if rn.has_method("get_effective_max_harvesters") else rn.max_harvesters
		var cur_h: int = rn.get_active_harvester_count()
		var sat_col: Color = Color(0.68, 0.78, 0.86, 0.90 * a)
		if cur_h > max_h:
			sat_col = Color(1.0, 0.36, 0.30, 0.96 * a)
		elif cur_h == max_h:
			sat_col = Color(0.24, 0.96, 0.68, 0.95 * a)
		elif cur_h > 0:
			sat_col = Color(1.0, 0.80, 0.28, 0.95 * a)
		var r_pt: Vector2 = to_local(rn.global_position)
		_draw_pill(font, r_pt + Vector2(0.0, -rn.collision_radius - 12.0), "%d/%d" % [cur_h, max_h], sat_col, a)


func _draw_pill(font: Font, center: Vector2, text: String, accent: Color, alpha_mul: float) -> void:
	var font_size: int = 10
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pw: float = sz.x + 10.0
	var ph: float = sz.y + 4.0
	var rect: Rect2 = Rect2(center - Vector2(pw * 0.5, ph * 0.5), Vector2(pw, ph))
	draw_rect(rect, Color(0.04, 0.07, 0.11, 0.86 * alpha_mul), true)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.82 * alpha_mul), false, 1.2)
	draw_string(font, rect.position + Vector2(5.0, ph - 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(accent.r, accent.g, accent.b, 0.96 * alpha_mul))


func _draw_dashed_line(a: Vector2, b: Vector2, col: Color, width: float, dash_len: float, gap_len: float) -> void:
	var diff: Vector2 = b - a
	var total_len: float = diff.length()
	if total_len < 2.0:
		return
	var dir: Vector2 = diff / total_len
	var step: float = dash_len + gap_len
	var dist: float = 0.0
	while dist < total_len:
		var seg_end: float = minf(total_len, dist + dash_len)
		draw_line(a + dir * dist, a + dir * seg_end, col, width, true)
		dist += step


func _draw_dashed_ring(center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(8, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.55
		draw_arc(center, radius, a0, a1, 3, col, width, true)
