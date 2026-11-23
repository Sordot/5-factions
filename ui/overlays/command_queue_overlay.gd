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

	for item: Variant in selected:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if unit.is_dead or unit.is_staffed or unit.team != Unit.Team.PLAYER:
			continue
		if unit.command_queue.is_empty():
			continue

		var prev_pt: Vector2 = to_local(unit.global_position)
		var active_dest: Variant = unit.get_active_command_destination()
		if active_dest is Vector2:
			var first_pt: Vector2 = to_local(active_dest as Vector2)
			var active_col: Color = _color_for_command(unit.active_command)
			draw_line(prev_pt, first_pt, Color(active_col.r, active_col.g, active_col.b, 0.55), 1.8, true)
			draw_arc(first_pt, 5.5, 0.0, TAU, 16, Color(active_col.r, active_col.g, active_col.b, 0.8), 1.6, true)
			prev_pt = first_pt

		var step_idx: int = 1
		for cmd: Dictionary in unit.command_queue:
			var cmd_type: StringName = cmd.get("type", &"move")
			var target_world: Variant = _resolve_cmd_pos(cmd, to_global(prev_pt))
			if not (target_world is Vector2):
				continue
			var next_pt: Vector2 = to_local(target_world as Vector2)
			var col: Color = _color_for_command(cmd)

			# Glow underlay + crisp segment (skip zero-length segment for anchored instant casts)
			if prev_pt.distance_squared_to(next_pt) > 4.0:
				draw_line(prev_pt, next_pt, Color(col.r, col.g, col.b, 0.22), 4.5, true)
				draw_line(prev_pt, next_pt, col, 2.0, true)

			var pulse: float = 1.2 * sin(_pulse_time * 4.0 + float(step_idx))
			var ring_r: float = 8.0 + pulse

			if cmd_type == &"cast_ability":
				# Distinct violet/magenta ability reticle + cardinal crosshair ticks
				var ret_r: float = ring_r + 2.5
				draw_circle(next_pt, ret_r * 0.72, Color(0.08, 0.03, 0.14, 0.86))
				draw_arc(next_pt, ret_r, 0.0, TAU, 24, col, 2.0, true)
				var tick_in: float = ret_r - 2.0
				var tick_out: float = ret_r + 5.0
				draw_line(next_pt + Vector2(tick_in, 0.0), next_pt + Vector2(tick_out, 0.0), col, 1.8, true)
				draw_line(next_pt - Vector2(tick_in, 0.0), next_pt - Vector2(tick_out, 0.0), col, 1.8, true)
				draw_line(next_pt + Vector2(0.0, tick_in), next_pt + Vector2(0.0, tick_out), col, 1.8, true)
				draw_line(next_pt - Vector2(0.0, tick_in), next_pt - Vector2(0.0, tick_out), col, 1.8, true)
			elif cmd_type == &"build":
				# Distinct emerald square + inner ring for queued construction
				var sq_half: float = ring_r + 1.5
				var sq_rect: Rect2 = Rect2(next_pt - Vector2(sq_half, sq_half), Vector2(sq_half * 2.0, sq_half * 2.0))
				draw_rect(sq_rect, Color(0.04, 0.12, 0.09, 0.84), true)
				draw_rect(sq_rect, col, false, 2.0)
				draw_arc(next_pt, ring_r * 0.62, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.65), 1.2, true)
			else:
				# Standard waypoint marker ring
				draw_circle(next_pt, ring_r * 0.72, Color(0.05, 0.09, 0.14, 0.82))
				draw_arc(next_pt, ring_r, 0.0, TAU, 20, col, 1.8, true)

			var label: String = str(step_idx)
			var t_sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(font, next_pt + Vector2(-t_sz.x * 0.5, t_sz.y * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

			prev_pt = next_pt
			step_idx += 1


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
	if cmd_type == &"attack_target" or cmd_type == &"build" or cmd_type == &"gather" or cmd_type == &"staff":
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
			return Color(1.0, 0.38, 0.28, 0.92)
		&"gather":
			return Color(0.26, 1.0, 0.58, 0.92)
		&"build":
			return Color(0.20, 0.98, 0.68, 0.96)
		&"cast_ability":
			return Color(0.88, 0.36, 1.0, 0.96)
		&"staff", &"return_cargo":
			return Color(1.0, 0.80, 0.28, 0.92)
		_:
			return Color(0.24, 0.94, 1.0, 0.90)
