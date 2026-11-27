class_name HyperUplink
extends Node2D

signal controller_changed(new_team: int)
signal capture_state_changed(progress: float, contested: bool, controller: int)

const SCAN_INTERVAL: float = 0.15

@export var capture_radius: float = 140.0
@export var capture_time: float = 8.0
@export var production_bonus_pct: float = 0.05
@export var selection_radius: float = 42.0

var capture_progress: float = 0.0 # 0.0 = NEUTRAL, 1.0 = CAPTURED by capturing_team
var capturing_team: int = -1
var controlling_team: int = -1
var controlling_alliance: int = -1
var is_contested: bool = false
var is_selected: bool = false
var is_hovered: bool = false

var _pulse_time: float = 0.0
var _occupant_count: int = 0
var _scan_accum: float = 0.0
var _fog_cache: FogOfWarSystem = null
var _last_known_controller: int = -1
var _last_known_capturing: int = -1
var _last_known_progress: float = 0.0
var _last_known_contested: bool = false
var _last_known_occupants: int = 0


func _ready() -> void:
	add_to_group("hyper_uplinks")
	z_index = -5
	_sync_last_known_if_visible()
	queue_redraw()


func reset_uplink() -> void:
	capture_progress = 0.0
	capturing_team = -1
	controlling_alliance = -1
	is_contested = false
	_occupant_count = 0
	_scan_accum = 0.0
	_last_known_controller = -1
	_last_known_capturing = -1
	_last_known_progress = 0.0
	_last_known_contested = false
	_last_known_occupants = 0
	_set_controller(-1)
	capture_state_changed.emit(capture_progress, is_contested, controlling_team)
	queue_redraw()


func is_live_visible_to_viewer() -> bool:
	if GameConfig != null and GameConfig.is_spectator_mode():
		return true
	if not is_inside_tree():
		return true
	if _fog_cache == null or not is_instance_valid(_fog_cache):
		_fog_cache = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if _fog_cache == null or not _fog_cache.fog_enabled:
		return true
	return _fog_cache.is_world_pos_visible_strict(global_position)


func _sync_last_known_if_visible() -> void:
	if is_live_visible_to_viewer():
		_last_known_controller = controlling_team
		_last_known_capturing = capturing_team
		_last_known_progress = capture_progress
		_last_known_contested = is_contested
		_last_known_occupants = _occupant_count


func _is_on_screen() -> bool:
	if not is_inside_tree():
		return false
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	if cam == null:
		return true
	var zoom_x: float = maxf(0.15, cam.zoom.x)
	var zoom_y: float = maxf(0.15, cam.zoom.y)
	var vis_sz: Vector2 = vp.get_visible_rect().size
	var pad: float = capture_radius + 80.0
	var half_world: Vector2 = Vector2(vis_sz.x / zoom_x, vis_sz.y / zoom_y) * 0.5 + Vector2(pad, pad)
	var cam_rect: Rect2 = Rect2(cam.get_screen_center_position() - half_world, half_world * 2.0)
	return cam_rect.has_point(global_position)


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


func _process(delta: float) -> void:
	_pulse_time += delta
	if is_selected or is_hovered or _is_on_screen():
		queue_redraw()


func _physics_process(delta: float) -> void:
	_scan_accum += delta
	if _scan_accum < SCAN_INTERVAL:
		return
	var step_dt: float = _scan_accum
	_scan_accum = 0.0

	var alliance_units: Dictionary = {} # alliance_id -> {team_id: count}
	var radius_sq: float = capture_radius * capture_radius
	var occ_total: int = 0

	var unit_list: Array = SpatialGrid.query_units_in_radius(global_position, capture_radius + 24.0) if SpatialGrid != null else get_tree().get_nodes_in_group("units")
	for node: Variant in unit_list:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var unit: Unit = node as Unit
		if unit.is_dead or unit.is_staffed or unit.is_queued_for_deletion():
			continue
		if unit.data == null or not unit.data.is_combat_unit():
			continue
		if global_position.distance_squared_to(unit.global_position) <= radius_sq:
			occ_total += 1
			var tid: int = int(unit.team)
			var ally_id: int = TeamManager.get_team_alliance(tid) if TeamManager != null else tid
			if not alliance_units.has(ally_id):
				alliance_units[ally_id] = {}
			var bucket: Dictionary = alliance_units[ally_id]
			bucket[tid] = int(bucket.get(tid, 0)) + 1
	_occupant_count = occ_total

	var prev_progress: float = capture_progress
	var prev_contested: bool = is_contested
	var rate: float = 1.0 / maxf(0.5, capture_time)

	if alliance_units.size() >= 2:
		is_contested = true
	elif alliance_units.size() == 1:
		is_contested = false
		var sole_ally: int = int(alliance_units.keys()[0])
		var bucket: Dictionary = alliance_units[sole_ally]
		# Pick the team in the occupying alliance with the most combat units inside the zone (tie-break: current controller/lowest tid)
		var lead_team: int = -1
		var lead_count: int = -1
		for raw_t: Variant in bucket.keys():
			var tid: int = int(raw_t)
			var cnt: int = int(bucket[raw_t])
			if cnt > lead_count or (cnt == lead_count and (tid == controlling_team or lead_team < 0 or tid < lead_team)):
				lead_count = cnt
				lead_team = tid

		var same_alliance_as_owner: bool = (
			capturing_team >= 0
			and (TeamManager.are_allies(capturing_team, lead_team) if TeamManager != null else (capturing_team == lead_team))
		)
		if capturing_team < 0 or same_alliance_as_owner:
			if capturing_team < 0:
				capturing_team = lead_team
			capture_progress = minf(1.0, capture_progress + rate * step_dt)
			if capture_progress >= 1.0:
				_set_controller(capturing_team)
		else:
			# Neutralize hostile control first, then flip ownership
			capture_progress = maxf(0.0, capture_progress - rate * step_dt)
			if capture_progress <= 0.0:
				capturing_team = lead_team
				if controlling_team >= 0:
					_set_controller(-1)
	else:
		is_contested = false
		# Gently decay partial uncaptured progress back toward current owner when unoccupied.
		var decay_rate: float = rate * 0.35 * step_dt
		if controlling_team >= 0:
			capture_progress = minf(1.0, capture_progress + decay_rate)
			capturing_team = controlling_team
		elif capture_progress > 0.0:
			capture_progress = maxf(0.0, capture_progress - decay_rate)
			if capture_progress <= 0.0:
				capturing_team = -1

	_sync_last_known_if_visible()

	if not is_equal_approx(prev_progress, capture_progress) or prev_contested != is_contested:
		capture_state_changed.emit(capture_progress, is_contested, controlling_team)
		if is_contested and not prev_contested:
			var mm: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
			if mm != null:
				mm.push_tactical_alert(global_position, &"uplink_contested", "Hyper-Uplink Contested!")
				if mm.has_method("emit_tactical_event"):
					mm.call("emit_tactical_event", &"objective", "Hyper-Uplink Contested!", global_position, Color(1.0, 0.80, 0.24, 1.0))


func _set_controller(next_team: int) -> void:
	if controlling_team == next_team:
		return
	controlling_team = next_team
	if controlling_team >= 0:
		controlling_alliance = TeamManager.get_team_alliance(controlling_team) if TeamManager != null else controlling_team
	else:
		controlling_alliance = -1
	_sync_last_known_if_visible()
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.set_uplink_controller(controlling_team, production_bonus_pct)
	var mm: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if mm != null and controlling_team >= 0:
		var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		var is_friendly: bool = local_team >= 0 and (TeamManager.are_allies(local_team, controlling_team) if TeamManager != null else (controlling_team == local_team))
		var team_tag: String = TeamManager.get_team_short_label(controlling_team, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (controlling_team + 1))
		var pct_int: int = int(round(production_bonus_pct * 100.0))
		var msg: String = ("Hyper-Uplink Captured (+%d%%)" % pct_int) if is_friendly else ("%s Captured Hyper-Uplink (+%d%%)" % [team_tag, pct_int])
		mm.push_tactical_alert(global_position, &"uplink_contested", msg)
		if mm.has_method("emit_tactical_event"):
			var feed_msg: String = "%s Captured Hyper-Uplink (+%d%%)" % [team_tag, pct_int]
			mm.call("emit_tactical_event", &"objective", feed_msg, global_position, Color(1.0, 0.84, 0.28, 1.0))
	controller_changed.emit(controlling_team)


func _draw() -> void:
	var has_live_vision: bool = is_live_visible_to_viewer()

	var base_col: Color = Color(0.62, 0.72, 0.82, 0.8)
	var status_text: String = "DATA HYPER-UPLINK  —  NEUTRAL"
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)

	if not has_live_vision:
		base_col = Color(0.52, 0.62, 0.72, 0.72)
		status_text = "DATA HYPER-UPLINK  —  NO LIVE SIGNAL"
	elif is_contested:
		var blink: float = 0.65 + 0.35 * sin(_pulse_time * 8.0)
		base_col = Color(1.0, 0.78, 0.24, blink)
		status_text = "DATA HYPER-UPLINK  —  CONTESTED"
	elif controlling_team >= 0:
		var tc: Color = TeamManager.get_team_color(controlling_team) if TeamManager != null else Color(0.18, 0.96, 0.90, 1.0)
		base_col = Color(tc.r, tc.g, tc.b, 0.95)
		var is_ally: bool = local_team >= 0 and (TeamManager.are_allies(local_team, controlling_team) if TeamManager != null else (controlling_team == local_team))
		if is_ally:
			status_text = "HYPER-UPLINK CONTROLLED  (+%d%% SPEED)" % int(round(production_bonus_pct * 100.0))
		else:
			var tag: String = TeamManager.get_team_short_label(controlling_team, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("TEAM %d" % (controlling_team + 1))
			status_text = "HYPER-UPLINK  —  %s CONTROL" % tag
	elif capture_progress > 0.01 and capturing_team >= 0:
		var cc: Color = TeamManager.get_team_color(capturing_team) if TeamManager != null else Color(0.24, 0.92, 0.86, 1.0)
		base_col = Color(cc.r, cc.g, cc.b, 0.90)
		var c_tag: String = TeamManager.get_team_short_label(capturing_team, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (capturing_team + 1))
		status_text = "%s CAPTURING UPLINK  %d%%" % [c_tag, int(round(capture_progress * 100.0))]

	# Outer capture zone fill, perimeter ring, and 8 radial tactical ticks
	draw_circle(Vector2.ZERO, capture_radius, Color(base_col.r, base_col.g, base_col.b, 0.07))
	draw_arc(Vector2.ZERO, capture_radius, 0.0, TAU, 64, Color(base_col.r, base_col.g, base_col.b, 0.65), 2.2, true)
	draw_arc(Vector2.ZERO, capture_radius - 6.0, 0.0, TAU, 64, Color(0.08, 0.14, 0.2, 0.55), 5.0, true)
	for i: int in range(8):
		var ang: float = TAU * float(i) / 8.0
		var d: Vector2 = Vector2.RIGHT.rotated(ang)
		draw_line(d * (capture_radius - 10.0), d * (capture_radius + 4.0), Color(base_col.r, base_col.g, base_col.b, 0.72), 1.8, true)

	# Progress arc around perimeter (only when live vision covers the uplink)
	var mag: float = clampf(capture_progress, 0.0, 1.0)
	if has_live_vision and mag > 0.01 and capturing_team >= 0:
		var arc_c: Color = TeamManager.get_team_color(capturing_team) if TeamManager != null else Color(0.18, 0.98, 0.92, 1.0)
		draw_arc(Vector2.ZERO, capture_radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * mag, 56, Color(arc_c.r, arc_c.g, arc_c.b, 0.98), 5.0, true)

	# Alternating segmented contest warning ring when opposing combat units clash inside
	if has_live_vision and is_contested:
		var seg_count: int = 16
		var seg_step: float = TAU / float(seg_count)
		var rot_off: float = _pulse_time * 0.95
		var warn_amber: Color = Color(1.0, 0.80, 0.22, 0.92)
		var warn_crimson: Color = Color(1.0, 0.26, 0.24, 0.90)
		for s_i: int in range(seg_count):
			var a0: float = rot_off + float(s_i) * seg_step + 0.045
			var a1: float = rot_off + float(s_i + 1) * seg_step - 0.045
			var s_col: Color = warn_amber if (s_i % 2 == 0) else warn_crimson
			draw_arc(Vector2.ZERO, capture_radius + 3.0, a0, a1, 6, s_col, 3.2, true)

	# Central uplink pylon geometry + hover/selection ring
	if is_hovered and not is_selected:
		draw_arc(Vector2.ZERO, selection_radius, 0.0, TAU, 32, Color(0.28, 0.88, 1.0, 0.60), 1.6, true)
	if is_selected:
		draw_circle(Vector2.ZERO, selection_radius + 2.0, Color(base_col.r, base_col.g, base_col.b, 0.14))
		draw_arc(Vector2.ZERO, selection_radius + 2.0, 0.0, TAU, 36, Color(0.95, 0.99, 1.0, 0.94), 2.0, true)

	var inner_pulse: float = 18.0 + 2.5 * sin(_pulse_time * 3.0)
	draw_circle(Vector2.ZERO, 28.0, Color(0.07, 0.12, 0.18, 0.95))
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 24, base_col, 2.5, true)
	draw_circle(Vector2.ZERO, inner_pulse * 0.58, Color(base_col.r, base_col.g, base_col.b, 0.92))

	# High-contrast pill label above capture ring
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var text_size: Vector2 = font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pill_w: float = text_size.x + 16.0
	var pill_h: float = text_size.y + 8.0
	var pill_pos: Vector2 = Vector2(-pill_w * 0.5, -capture_radius - pill_h - 8.0)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.04, 0.08, 0.12, 0.88), true)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(base_col.r, base_col.g, base_col.b, 0.8), false, 1.2)
	draw_string(font, pill_pos + Vector2(8.0, pill_h - 6.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, base_col)


func get_inspection_data() -> Dictionary:
	var live_vis: bool = is_live_visible_to_viewer()
	if live_vis:
		_sync_last_known_if_visible()

	var disp_controller: int = controlling_team if live_vis else _last_known_controller
	var disp_progress: float = capture_progress if live_vis else _last_known_progress
	var disp_contested: bool = is_contested if live_vis else _last_known_contested
	var disp_occupants: int = _occupant_count if live_vis else _last_known_occupants

	var accent: Color = Color(0.98, 0.82, 0.30, 1.0)
	var controller_str: String = "Neutral"
	var affiliation: StringName = &"neutral"
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)

	if disp_contested:
		controller_str = "CONTESTED"
		accent = Color(1.0, 0.72, 0.22, 1.0)
	elif disp_controller >= 0:
		accent = TeamManager.get_team_color(disp_controller) if TeamManager != null else Color(0.20, 0.96, 0.88, 1.0)
		controller_str = TeamManager.get_team_short_label(disp_controller, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (disp_controller + 1))
		var is_ally: bool = local_team < 0 or (TeamManager.are_allies(local_team, disp_controller) if TeamManager != null else (disp_controller == local_team))
		affiliation = &"player" if is_ally else &"enemy"

	if not live_vis:
		controller_str = "%s (LAST KNOWN)" % controller_str

	var cap_pct: int = int(round(clampf(disp_progress, 0.0, 1.0) * 100.0))
	var cap_val_str: String = ("%d%% (%d Combat Units)" % [cap_pct, disp_occupants]) if live_vis else ("%d%% (LAST KNOWN)" % cap_pct)
	var stats: Array[Dictionary] = [
		{"label": "Controller", "value": controller_str, "color": accent},
		{"label": "Capture", "value": cap_val_str},
		{"label": "Alliance Bonus", "value": "+%d%% Prod Speed" % int(round(production_bonus_pct * 100.0)), "color": Color(0.28, 0.98, 0.86, 1.0)},
	]

	var show_pbar: bool = false
	var pbar_label: String = ""
	var pbar_val: float = 0.0
	var pbar_max: float = 180.0
	if is_inside_tree():
		var mm: Node = get_tree().get_first_node_in_group("match_manager")
		if mm != null and mm.has_method("get_uplink_victory_status"):
			var vst: Dictionary = mm.call("get_uplink_victory_status") as Dictionary
			if bool(vst.get("enabled", false)):
				var target_s: float = maxf(1.0, float(vst.get("target_seconds", 180.0)))
				var lead_s: float = float(vst.get("leading_seconds", 0.0))
				var lead_t: int = int(vst.get("leading_team", -1))
				var lead_tag: String = "—"
				if lead_t >= 0:
					lead_tag = TeamManager.get_team_short_label(lead_t, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (lead_t + 1))
				var m_cur: int = int(lead_s) / 60
				var s_cur: int = int(lead_s) % 60
				var m_tot: int = int(target_s) / 60
				var s_tot: int = int(target_s) % 60
				var timer_str: String = "%02d:%02d / %02d:%02d" % [m_cur, s_cur, m_tot, s_tot]
				stats.append({"label": "Uplink Victory", "value": ("%s (%s)" % [timer_str, lead_tag]) if lead_t >= 0 else ("00:00 / %02d:%02d" % [m_tot, s_tot]), "color": accent})
				show_pbar = true
				pbar_label = "SOVEREIGNTY %s" % timer_str
				pbar_val = lead_s
				pbar_max = target_s
			else:
				stats.append({"label": "Victory Mode", "value": "Domination Only"})

	return {
		"title": "Data Hyper-Uplink",
		"subtitle": "STRATEGIC SECTOR OBJECTIVE" if live_vis else "STRATEGIC SECTOR OBJECTIVE (LAST KNOWN)",
		"affiliation": affiliation,
		"accent_color": accent,
		"ring_color": accent,
		"show_hp_bar": false,
		"show_primary_bar": show_pbar,
		"primary_bar_label": pbar_label,
		"primary_bar_value": pbar_val,
		"primary_bar_max": pbar_max,
		"primary_bar_color": accent,
		"stats": stats,
		"is_commandable": false,
		"readonly_label": "STRATEGIC OBJECTIVE — CAPTURE WITH COMBAT UNITS",
	}
