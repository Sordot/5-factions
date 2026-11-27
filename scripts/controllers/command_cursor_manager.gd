class_name CommandCursorManager
extends RefCounted

var _command_cursors: Dictionary = {}
var _active_cursor_state: StringName = &""


func build_cursors() -> void:
	_command_cursors.clear()
	_command_cursors[&"attack_move"] = _make_reticle_cursor(&"attack_move")
	_command_cursors[&"patrol"] = _make_reticle_cursor(&"patrol")
	_command_cursors[&"repair"] = _make_reticle_cursor(&"repair")
	_command_cursors[&"ability_target"] = _make_reticle_cursor(&"ability_target")
	_command_cursors[&"overclock_valid"] = _make_reticle_cursor(&"overclock_valid")
	_command_cursors[&"overclock_invalid"] = _make_reticle_cursor(&"overclock_invalid")


func _make_reticle_cursor(style: StringName) -> ImageTexture:
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var primary: Color = Color(1.0, 0.30, 0.43, 1.0) # Crimson #FF4D6D
	var secondary: Color = Color(1.0, 0.78, 0.84, 0.95)
	var shadow: Color = Color(0.02, 0.04, 0.07, 0.85)
	match style:
		&"patrol":
			primary = Color(0.22, 0.74, 0.97, 1.0) # Cyan/Azure #38BDF8
			secondary = Color(0.86, 0.97, 1.0, 0.96)
		&"repair":
			primary = Color(0.20, 0.83, 0.60, 1.0) # Emerald #34D399
			secondary = Color(0.84, 1.0, 0.92, 0.96)
		&"ability_target":
			primary = Color(0.96, 0.62, 0.04, 1.0) # Amber #F59E0B
			secondary = Color(0.76, 0.48, 1.0, 0.96) # Violet accent
		&"overclock_valid":
			primary = Color(1.0, 0.624, 0.110, 1.0) # Hazard Amber #FF9F1C
			secondary = Color(1.0, 0.92, 0.68, 0.98)
		&"overclock_invalid":
			primary = Color(0.82, 0.32, 0.30, 0.92) # Muted Red
			secondary = Color(0.92, 0.56, 0.54, 0.85)

	var put_px: Callable = func(px: int, py: int, col: Color) -> void:
		if px >= 0 and px < 32 and py >= 0 and py < 32:
			img.set_pixel(px, py, col)

	var draw_dot_outlined: Callable = func(px: int, py: int, col: Color) -> void:
		for oy: int in [-1, 0, 1]:
			for ox: int in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				var nx: int = px + ox
				var ny: int = py + oy
				if nx >= 0 and nx < 32 and ny >= 0 and ny < 32 and img.get_pixel(nx, ny).a < 0.05:
					img.set_pixel(nx, ny, shadow)
		put_px.call(px, py, col)

	var draw_seg: Callable = func(x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
		var steps: int = maxi(absi(x1 - x0), absi(y1 - y0))
		if steps <= 0:
			draw_dot_outlined.call(x0, y0, col)
			return
		for i: int in range(steps + 1):
			var t: float = float(i) / float(steps)
			var rx: int = int(round(lerpf(float(x0), float(x1), t)))
			var ry: int = int(round(lerpf(float(y0), float(y1), t)))
			draw_dot_outlined.call(rx, ry, col)

	var draw_ring: Callable = func(radius: float, col: Color) -> void:
		for a_i: int in range(64):
			var ang: float = TAU * float(a_i) / 64.0
			var rx: int = int(round(16.0 + cos(ang) * radius))
			var ry: int = int(round(16.0 + sin(ang) * radius))
			draw_dot_outlined.call(rx, ry, col)

	match style:
		&"attack_move":
			# Sharp crimson reticle with 4 corner brackets + cardinal ticks + hot center pip
			draw_seg.call(5, 5, 10, 5, primary)
			draw_seg.call(5, 5, 5, 10, primary)
			draw_seg.call(26, 5, 21, 5, primary)
			draw_seg.call(26, 5, 26, 10, primary)
			draw_seg.call(5, 26, 10, 26, primary)
			draw_seg.call(5, 26, 5, 21, primary)
			draw_seg.call(26, 26, 21, 26, primary)
			draw_seg.call(26, 26, 26, 21, primary)
			draw_seg.call(16, 4, 16, 11, primary)
			draw_seg.call(16, 21, 16, 28, primary)
			draw_seg.call(4, 16, 11, 16, primary)
			draw_seg.call(21, 16, 28, 16, primary)
			draw_seg.call(15, 16, 17, 16, secondary)
			draw_seg.call(16, 15, 16, 17, secondary)

		&"patrol":
			# Crisp cyan/azure reticle with ring + directional ticks + chevron accents
			draw_ring.call(10.0, primary)
			draw_seg.call(16, 2, 16, 8, secondary)
			draw_seg.call(16, 24, 16, 30, secondary)
			draw_seg.call(2, 16, 8, 16, secondary)
			draw_seg.call(24, 16, 30, 16, secondary)
			# Small directional diamond center
			draw_seg.call(16, 13, 19, 16, primary)
			draw_seg.call(19, 16, 16, 19, primary)
			draw_seg.call(16, 19, 13, 16, primary)
			draw_seg.call(13, 16, 16, 13, primary)

		&"repair":
			# Bioluminescent emerald reticle with bold inner repair cross + corner brackets
			draw_ring.call(11.0, primary)
			draw_seg.call(16, 10, 16, 22, secondary)
			draw_seg.call(15, 11, 15, 21, primary)
			draw_seg.call(17, 11, 17, 21, primary)
			draw_seg.call(10, 16, 22, 16, secondary)
			draw_seg.call(11, 15, 21, 15, primary)
			draw_seg.call(11, 17, 21, 17, primary)

		&"ability_target", &"overclock_valid", &"overclock_invalid":
			# Luminous concentric reticle + ticks
			draw_ring.call(11.5, primary)
			draw_ring.call(5.5, secondary)
			draw_seg.call(16, 2, 16, 6, primary)
			draw_seg.call(16, 26, 16, 30, primary)
			draw_seg.call(2, 16, 6, 16, primary)
			draw_seg.call(26, 16, 30, 16, primary)
			draw_dot_outlined.call(16, 16, secondary)

	return ImageTexture.create_from_image(img)


func clear_cursor() -> void:
	if _active_cursor_state != &"":
		_active_cursor_state = &""
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func apply_cursor(state: StringName) -> void:
	if _active_cursor_state == state:
		return
	if state == &"" or not _command_cursors.has(state):
		clear_cursor()
		return
	_active_cursor_state = state
	Input.set_custom_mouse_cursor(_command_cursors[state] as Texture2D, Input.CURSOR_ARROW, Vector2(16, 16))
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func is_any_modal_open(sc: SelectionController) -> bool:
	if sc == null or not sc.is_inside_tree():
		return true
	var tree: SceneTree = sc.get_tree()
	if tree.paused and not sc._is_post_match_inspection():
		return true
	var pause_node: Node = tree.get_first_node_in_group("pause_menu")
	if pause_node != null and is_instance_valid(pause_node):
		if pause_node.has_method("is_pause_open") and bool(pause_node.call("is_pause_open")):
			return true
		if pause_node.has_method("is_settings_open") and bool(pause_node.call("is_settings_open")):
			return true
		if pause_node.has_method("is_tech_tree_open") and bool(pause_node.call("is_tech_tree_open")):
			return true
		if pause_node.has_method("is_controls_help_open") and bool(pause_node.call("is_controls_help_open")):
			return true
	var settings_node: Node = tree.get_first_node_in_group("settings_menu")
	if settings_node != null and is_instance_valid(settings_node) and not settings_node.is_queued_for_deletion():
		return true
	var tech_node: Node = tree.get_first_node_in_group("tech_tree_overlay")
	if tech_node != null and is_instance_valid(tech_node) and not tech_node.is_queued_for_deletion():
		return true
	var help_node: Node = tree.get_first_node_in_group("controls_reference_overlay")
	if help_node != null and is_instance_valid(help_node) and not help_node.is_queued_for_deletion():
		return true
	var end_node: Node = tree.get_first_node_in_group("match_end_overlay")
	if end_node != null and is_instance_valid(end_node) and end_node.has_method("is_summary_visible"):
		if bool(end_node.call("is_summary_visible")):
			return true
	return false


func is_hovering_repairable_target(sc: SelectionController) -> bool:
	if sc == null or sc.command_router == null or sc.selected_units.is_empty() or sc._is_dragging:
		return false
	var has_repairer: bool = false
	for u: Unit in sc.selected_units:
		if is_instance_valid(u) and not u.is_dead and not u.is_staffed:
			if u.can_repair():
				has_repairer = true
				break
	if not has_repairer:
		return false
	var world_pt: Vector2 = sc.get_global_mouse_position()
	var local_team: Unit.Team = (TeamManager.get_local_human_team() as Unit.Team) if (TeamManager != null and TeamManager.get_local_human_team() >= 0) else Unit.Team.PLAYER
	var hovered_u: Unit = sc.command_router.find_unit_at_point(world_pt, local_team)
	if hovered_u != null:
		for u: Unit in sc.selected_units:
			if is_instance_valid(u) and u.can_repair_target(hovered_u):
				return true
	var hovered_b: Building = sc.command_router.find_building_at_point(world_pt, local_team)
	if hovered_b != null and hovered_b.is_constructed and hovered_b.current_hp < hovered_b.max_hp - 0.5:
		for u: Unit in sc.selected_units:
			if is_instance_valid(u) and u.can_repair_target(hovered_b):
				return true
	return false


func update_cursor(sc: SelectionController) -> void:
	if sc == null or is_any_modal_open(sc) or sc._is_post_match_inspection():
		clear_cursor()
		return
	if sc.active_targeting_ability != null:
		apply_cursor(&"ability_target")
		return
	if sc.is_overclock_targeting:
		var oc_hub: Building = sc.find_ready_overclock_hub()
		var oc_valid: bool = false
		if oc_hub != null and sc.command_router != null:
			var oc_b: Building = sc.command_router.find_building_at_point(sc.get_global_mouse_position(), sc._get_local_human_team_enum())
			oc_valid = oc_b != null and oc_b.is_valid_overclock_target(int(oc_hub.team))
		apply_cursor(&"overclock_valid" if oc_valid else &"overclock_invalid")
		return
	if sc.is_attack_move_targeting:
		apply_cursor(&"attack_move")
		return
	if sc.is_patrol_targeting:
		apply_cursor(&"patrol")
		return
	if is_hovering_repairable_target(sc):
		apply_cursor(&"repair")
		return
	clear_cursor()
