class_name CommandQueueOverlay
extends Node2D

var _controller: Node = null
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("command_queue_overlay")
	z_index = 84


func bind_selection_controller(controller: Node) -> void:
	_controller = controller
	if _controller == null:
		return
	if _controller.has_signal("selection_changed") and not _controller.is_connected("selection_changed", _on_selection_changed):
		_controller.connect("selection_changed", _on_selection_changed)
	queue_redraw()


func _on_selection_changed(_units: Variant, _subgroups: Variant, _active_idx: Variant) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if _controller == null or not is_instance_valid(_controller):
		return
	var raw_units: Variant = _controller.get("selected_units")
	if raw_units is Array and not (raw_units as Array).is_empty():
		_pulse_time += delta
		queue_redraw()


func _draw() -> void:
	if _controller == null or not is_instance_valid(_controller):
		return
	var raw_units: Variant = _controller.get("selected_units")
	if not (raw_units is Array):
		return
	var selected: Array = raw_units
	if selected.is_empty():
		return

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 10

	# Collect ordered focus-fire kill list across selected friendly units (Shift+RMB queue)
	var kill_list: Array[Node2D] = _collect_ordered_kill_list(selected)
	var kill_lookup: Dictionary = {}
	for k_node: Node2D in kill_list:
		kill_lookup[k_node.get_instance_id()] = true

	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	for item: Variant in selected:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if unit.is_dead or unit.is_staffed or (local_team >= 0 and int(unit.team) != local_team):
			continue

		# Render active Patrol loops with azure/cyan directional loop indicators.
		if unit.command_state == Unit.CommandState.PATROLLING and unit.patrol_waypoints.size() >= 2:
			_draw_patrol_loop(unit, font, font_size)

		if unit.command_queue.is_empty():
			continue

		var prev_pt: Vector2 = to_local(unit.global_position)
		var active_dest: Variant = unit.get_active_command_destination()
		if active_dest is Vector2:
			var first_pt: Vector2 = to_local(active_dest as Vector2)
			var active_col: Color = _color_for_command(unit.active_command)
			draw_line(prev_pt, first_pt, Color(active_col.r, active_col.g, active_col.b, 0.55), 1.8, true)
			_draw_segment_chevrons(prev_pt, first_pt, Color(active_col.r, active_col.g, active_col.b, 0.78))
			if not (unit.active_command.get("type", &"") == &"attack_target" and kill_list.size() >= 2):
				_draw_waypoint_diamond(first_pt, 5.5, Color(active_col.r, active_col.g, active_col.b, 0.85))
			prev_pt = first_pt

		var step_idx: int = 1
		for cmd: Dictionary in unit.command_queue:
			var cmd_type: StringName = cmd.get("type", &"move")
			var target_world: Variant = _resolve_cmd_pos(cmd, to_global(prev_pt))
			if not (target_world is Vector2):
				continue
			var next_pt: Vector2 = to_local(target_world as Vector2)
			var col: Color = _color_for_command(cmd)

			if cmd_type == &"attack_target" and kill_list.size() >= 2:
				var atk_t: Variant = cmd.get("target", null)
				if atk_t is Node2D and is_instance_valid(atk_t) and kill_lookup.has((atk_t as Node2D).get_instance_id()):
					prev_pt = next_pt
					step_idx += 1
					continue

			# Glow underlay + crisp segment + directional chevrons
			if prev_pt.distance_squared_to(next_pt) > 4.0:
				draw_line(prev_pt, next_pt, Color(col.r, col.g, col.b, 0.22), 4.5, true)
				draw_line(prev_pt, next_pt, col, 2.0, true)
				_draw_segment_chevrons(prev_pt, next_pt, col)

			var pulse: float = 1.2 * sin(_pulse_time * 4.0 + float(step_idx))
			var ring_r: float = 8.0 + pulse

			if cmd_type == &"cast_ability":
				# Distinct luminous amber ability reticle + cardinal crosshair ticks
				var ret_r: float = ring_r + 2.5
				draw_circle(next_pt, ret_r * 0.72, Color(0.10, 0.07, 0.03, 0.86))
				draw_arc(next_pt, ret_r, 0.0, TAU, 24, col, 2.0, true)
				var tick_in: float = ret_r - 2.0
				var tick_out: float = ret_r + 5.0
				draw_line(next_pt + Vector2(tick_in, 0.0), next_pt + Vector2(tick_out, 0.0), col, 1.8, true)
				draw_line(next_pt - Vector2(tick_in, 0.0), next_pt - Vector2(tick_out, 0.0), col, 1.8, true)
				draw_line(next_pt + Vector2(0.0, tick_in), next_pt + Vector2(0.0, tick_out), col, 1.8, true)
				draw_line(next_pt - Vector2(0.0, tick_in), next_pt - Vector2(0.0, tick_out), col, 1.8, true)
			elif cmd_type == &"build":
				# Distinct amber square + inner diamond for queued construction
				var sq_half: float = ring_r + 1.5
				var sq_rect: Rect2 = Rect2(next_pt - Vector2(sq_half, sq_half), Vector2(sq_half * 2.0, sq_half * 2.0))
				draw_rect(sq_rect, Color(0.10, 0.08, 0.03, 0.86), true)
				draw_rect(sq_rect, col, false, 2.0)
				_draw_waypoint_diamond(next_pt, ring_r * 0.62, Color(col.r, col.g, col.b, 0.68))
			else:
				# Crisp Technozen waypoint diamond vertex
				_draw_waypoint_diamond(next_pt, ring_r + 1.2, col, true)

			var label: String = str(step_idx)
			var t_sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(font, next_pt + Vector2(-t_sz.x * 0.5, t_sz.y * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

			prev_pt = next_pt
			step_idx += 1

	# Render numbered crimson focus-fire kill list (1, 2, 3...) + dashed sightlines
	if kill_list.size() >= 2:
		_draw_focus_fire_kill_list(kill_list, font)


func _draw_waypoint_diamond(center: Vector2, radius: float, col: Color, fill_backdrop: bool = false) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	if fill_backdrop:
		draw_colored_polygon(pts, Color(0.04, 0.08, 0.13, 0.86))
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, col, 1.8, true)


func _draw_segment_chevrons(a: Vector2, b: Vector2, col: Color) -> void:
	var diff: Vector2 = b - a
	var seg_len: float = diff.length()
	if seg_len < 28.0:
		return
	var dir: Vector2 = diff / seg_len
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var count: int = clampi(int(floor(seg_len / 76.0)), 1, 6)
	var wing: float = 5.0
	var back: float = 4.5
	for i: int in range(count):
		var frac: float = float(i + 1) / float(count + 1)
		var tip: Vector2 = a.lerp(b, frac) + dir * (back * 0.4)
		var p_l: Vector2 = tip - dir * back + perp * wing
		var p_r: Vector2 = tip - dir * back - perp * wing
		draw_polyline(PackedVector2Array([p_l, tip, p_r]), col, 1.8, true)


func _draw_patrol_loop(unit: Unit, font: Font, font_size: int) -> void:
	var pts: Array[Vector2] = unit.patrol_waypoints
	var count: int = pts.size()
	if count < 2:
		return
	var azure: Color = Color(0.376, 0.647, 0.980, 0.92) # #60A5FA
	var gold: Color = Color(0.961, 0.780, 0.280, 0.94)
	var active_idx: int = clampi(unit.patrol_index, 0, count - 1)
	var active_local: Vector2 = to_local(pts[active_idx])
	var u_local: Vector2 = to_local(unit.global_position)
	draw_line(u_local, active_local, Color(gold.r, gold.g, gold.b, 0.55), 1.8, true)
	_draw_segment_chevrons(u_local, active_local, Color(gold.r, gold.g, gold.b, 0.78))

	for i: int in range(count):
		var a: Vector2 = to_local(pts[i])
		var b: Vector2 = to_local(pts[(i + 1) % count])
		var seg_col: Color = gold if (i == count - 1) else azure
		draw_line(a, b, Color(seg_col.r, seg_col.g, seg_col.b, 0.22), 4.2, true)
		draw_line(a, b, seg_col, 1.9, true)
		_draw_segment_chevrons(a, b, seg_col)

		var pulse: float = 1.0 * sin(_pulse_time * 4.5 + float(i))
		var r: float = 8.5 + pulse
		_draw_waypoint_diamond(a, r, gold if i == active_idx else azure, true)
		var lbl: String = "P%d" % (i + 1)
		var t_sz: Vector2 = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, a + Vector2(-t_sz.x * 0.5, t_sz.y * 0.35), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, gold)


func _resolve_cmd_pos(cmd: Dictionary, anchor_world: Vector2) -> Variant:
	var cmd_type: StringName = cmd.get("type", &"move")
	if cmd_type == &"cast_ability":
		var ab: AbilityData = cmd.get("ability", null) as AbilityData
		if ab != null and ab.target_type == AbilityData.TargetType.INSTANT:
			return anchor_world
		if ab != null and ab.target_type == AbilityData.TargetType.UNIT_TARGET:
			var ab_t: Variant = cmd.get("target", null)
			if ab_t == null or not is_instance_valid(ab_t) or not (ab_t is Unit):
				return null
			var u_t: Unit = ab_t
			if u_t.is_dead or u_t.is_queued_for_deletion():
				return null
			return u_t.global_position

	var target: Variant = cmd.get("target", null)
	if cmd_type == &"attack_target" or cmd_type == &"build" or cmd_type == &"gather" or cmd_type == &"staff" or cmd_type == &"repair" or cmd_type == &"salvage":
		if target == null or not is_instance_valid(target) or not (target is Node2D):
			return null
		if (target as Node).is_queued_for_deletion():
			return null
		if target is Unit and (target as Unit).is_dead:
			return null
		if target is Building and ((target as Building).is_destroyed or (cmd_type == &"build" and (target as Building).is_constructed)):
			return null
		if target is ResourceNode and (target as ResourceNode).is_depleted():
			return null
		if cmd_type == &"salvage" and bool(target.get("is_claimed")):
			return null
		return (target as Node2D).global_position

	if target != null and is_instance_valid(target) and target is Node2D and not (target as Node).is_queued_for_deletion():
		return (target as Node2D).global_position
	if cmd.has("pos"):
		return cmd["pos"]
	return null


func _color_for_command(cmd: Dictionary) -> Color:
	var cmd_type: StringName = cmd.get("type", &"move")
	match cmd_type:
		&"attack_move", &"attack_target":
			return Color(1.0, 0.302, 0.427, 0.95) # Crimson #FF4D6D
		&"gather", &"repair", &"salvage", &"return_cargo":
			return Color(0.204, 0.827, 0.600, 0.95) # Bioluminescent Emerald #34D399
		&"build", &"cast_ability", &"staff":
			return Color(0.961, 0.620, 0.043, 0.96) # Luminous Amber #F59E0B
		&"patrol":
			return Color(0.376, 0.647, 0.980, 0.95) # Azure #60A5FA
		_:
			return Color(0.220, 0.741, 0.973, 0.94) # Cyan #38BDF8


func _is_valid_kill_target(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Node2D):
		return false
	var n2: Node2D = node as Node2D
	if n2.is_queued_for_deletion() or not n2.visible:
		return false
	if n2 is Unit and (n2 as Unit).is_dead:
		return false
	if n2 is Building and (n2 as Building).is_destroyed:
		return false
	if n2.is_in_group("destructible_barricades") and bool(n2.get("is_destroyed")):
		return false
	return true


func _collect_ordered_kill_list(selected: Array) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var seen: Dictionary = {}
	var has_queued_attack: bool = false
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)

	for item: Variant in selected:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item as Unit
		if unit.is_dead or unit.is_staffed or (local_team >= 0 and int(unit.team) != local_team):
			continue
		var unit_has_q_atk: bool = false
		for cmd: Dictionary in unit.command_queue:
			if cmd.get("type", &"") == &"attack_target" and _is_valid_kill_target(cmd.get("target", null)):
				unit_has_q_atk = true
				break
		if not unit_has_q_atk:
			continue
		has_queued_attack = true

		# Include current active target first in priority order
		if unit.command_state == Unit.CommandState.ATTACKING_TARGET and _is_valid_kill_target(unit.current_target):
			var cur_t: Node2D = unit.current_target
			var cid: int = cur_t.get_instance_id()
			if not seen.has(cid) and out.size() < 9:
				seen[cid] = true
				out.append(cur_t)

		for cmd: Dictionary in unit.command_queue:
			if cmd.get("type", &"") != &"attack_target":
				continue
			var qt: Variant = cmd.get("target", null)
			if not _is_valid_kill_target(qt):
				continue
			var q_node: Node2D = qt as Node2D
			var qid: int = q_node.get_instance_id()
			if not seen.has(qid) and out.size() < 9:
				seen[qid] = true
				out.append(q_node)

	if not has_queued_attack:
		return []
	return out


func _draw_focus_fire_kill_list(kill_list: Array[Node2D], font: Font) -> void:
	var crimson: Color = Color(1.0, 0.302, 0.427, 0.96)
	var line_col: Color = Color(1.0, 0.302, 0.427, 0.55)
	var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 6.5)

	# 1. Dashed crimson sightlines connecting T1 -> T2 -> T3...
	for i: int in range(kill_list.size() - 1):
		var p0: Vector2 = to_local(kill_list[i].global_position)
		var p1: Vector2 = to_local(kill_list[i + 1].global_position)
		var diff: Vector2 = p1 - p0
		var total: float = diff.length()
		if total > 12.0:
			var dir: Vector2 = diff / total
			var dist: float = 12.0
			while dist < total - 12.0:
				var seg_end: float = minf(total - 12.0, dist + 10.0)
				draw_line(p0 + dir * dist, p0 + dir * seg_end, line_col, 1.8, true)
				dist += 17.0

	# 2. Crimson corner-bracket crosshair + numbered priority badge (1..9) on each target
	for i: int in range(kill_list.size()):
		var t_node: Node2D = kill_list[i]
		var center: Vector2 = to_local(t_node.global_position)
		var rad: float = 20.0
		if t_node is Unit:
			var u: Unit = t_node as Unit
			rad = (u.data.collision_radius if u.data != null else 16.0) + 6.0
		elif t_node is Building:
			rad = (t_node as Building).footprint_radius + 6.0
		elif t_node.has_method("get_footprint_radius"):
			rad = float(t_node.call("get_footprint_radius")) + 6.0

		var r_pulse: float = rad + (2.0 * pulse if i == 0 else 0.0)
		var arm: float = clampf(r_pulse * 0.38, 6.0, 12.0)
		var b_col: Color = Color(1.0, 0.38, 0.48, 0.98) if i == 0 else crimson
		# 4 crisp corner brackets
		draw_polyline(PackedVector2Array([center + Vector2(-r_pulse, -r_pulse + arm), center + Vector2(-r_pulse, -r_pulse), center + Vector2(-r_pulse + arm, -r_pulse)]), b_col, 2.2)
		draw_polyline(PackedVector2Array([center + Vector2(r_pulse - arm, -r_pulse), center + Vector2(r_pulse, -r_pulse), center + Vector2(r_pulse, -r_pulse + arm)]), b_col, 2.2)
		draw_polyline(PackedVector2Array([center + Vector2(-r_pulse, r_pulse - arm), center + Vector2(-r_pulse, r_pulse), center + Vector2(-r_pulse + arm, r_pulse)]), b_col, 2.2)
		draw_polyline(PackedVector2Array([center + Vector2(r_pulse - arm, r_pulse), center + Vector2(r_pulse, r_pulse), center + Vector2(r_pulse, r_pulse - arm)]), b_col, 2.2)

		# High-contrast priority badge offset above-right of target
		var badge_center: Vector2 = center + Vector2(r_pulse + 4.0, -r_pulse - 4.0)
		var badge_rect: Rect2 = Rect2(badge_center - Vector2(9.0, 9.0), Vector2(18.0, 18.0))
		draw_rect(badge_rect, Color(0.06, 0.08, 0.12, 0.92), true)
		draw_rect(badge_rect, b_col, false, 1.6)
		var digit: String = str(i + 1)
		var d_sz: Vector2 = font.get_string_size(digit, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
		draw_string(font, badge_center + Vector2(-d_sz.x * 0.5, d_sz.y * 0.34), digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.98, 0.99, 1.0, 1.0))
