class_name OpticalTetherOverlay
extends Node2D

## Renders active Optical Tether ("Harmonic Communion") links between friendly
## emitter nodes and linked combat units (Milestone 3.9).
## Fog-of-War gated and zero-draw idle when no active links exist.

const MAGENTA_GLOW: Color = Color(0.94, 0.22, 0.68, 0.24)
const GOLD_HAIRLINE: Color = Color(0.98, 0.80, 0.14, 0.78)
const CORE_PULSE: Color = Color(1.0, 0.96, 0.78, 0.92)

var _anim_time: float = 0.0
var _had_links_last_frame: bool = false


func _ready() -> void:
	z_index = 46
	add_to_group("optical_tether_overlay")


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	var tether_sys: OpticalTetherSystem = get_tree().get_first_node_in_group("optical_tether_system") as OpticalTetherSystem
	var has_links: bool = tether_sys != null and not tether_sys.active_links.is_empty()
	if has_links:
		_anim_time += delta
		_had_links_last_frame = true
		queue_redraw()
	elif _had_links_last_frame:
		_had_links_last_frame = false
		queue_redraw()


func _draw() -> void:
	if not is_inside_tree():
		return
	var tether_sys: OpticalTetherSystem = get_tree().get_first_node_in_group("optical_tether_system") as OpticalTetherSystem
	if tether_sys == null or tether_sys.active_links.is_empty():
		return

	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	var fog_active: bool = fog != null and fog.fog_enabled
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)

	for link: Dictionary in tether_sys.active_links:
		var from_node: Variant = link.get("from_node", null)
		var to_node: Variant = link.get("to_node", null)
		var p_from: Vector2 = link.get("from_pos", Vector2.ZERO) as Vector2
		var p_to: Vector2 = link.get("to_pos", Vector2.ZERO) as Vector2
		if is_instance_valid(from_node) and from_node is Node2D:
			p_from = (from_node as Node2D).global_position
		if is_instance_valid(to_node) and to_node is Node2D:
			p_to = (to_node as Node2D).global_position

		var link_team: int = int(link.get("team", 0))
		var is_allied_view: bool = viewer_team < 0 or (TeamManager.are_allies(viewer_team, link_team) if TeamManager != null else (link_team == int(Unit.Team.PLAYER)))
		if fog_active and not is_allied_view:
			if not fog.is_world_pos_visible_strict(p_from) and not fog.is_world_pos_visible_strict(p_to):
				continue

		var lp0: Vector2 = to_local(p_from)
		var lp1: Vector2 = to_local(p_to)
		var seg: Vector2 = lp1 - lp0
		var seg_len: float = seg.length()
		if seg_len < 4.0:
			continue
		var dir: Vector2 = seg / seg_len
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var stack_idx: int = int(link.get("stack_index", 1))
		var glow_w: float = 4.2 if stack_idx >= 2 else 3.4
		var core_w: float = 1.45 if stack_idx >= 2 else 1.15

		draw_line(lp0, lp1, MAGENTA_GLOW, glow_w, true)
		draw_line(lp0, lp1, GOLD_HAIRLINE, core_w, true)

		# Subtle diamond pips at emitter & receiver anchors
		_draw_diamond(lp0, dir, perp, 3.6, Color(0.94, 0.22, 0.68, 0.80))
		_draw_diamond(lp1, dir, perp, 3.2, Color(0.98, 0.80, 0.14, 0.85))

		# Animated traveling diamond light pulses from emitter -> receiver
		var pulse_count: int = 3 if seg_len > 150.0 else 2
		for i: int in range(pulse_count):
			var u: float = fposmod(_anim_time * 0.72 + float(i) / float(pulse_count), 1.0)
			var pos: Vector2 = lp0.lerp(lp1, u)
			var edge_fade: float = sin(u * PI)
			var p_col: Color = Color(CORE_PULSE.r, CORE_PULSE.g, CORE_PULSE.b, CORE_PULSE.a * edge_fade)
			_draw_diamond(pos, dir, perp, 2.8 + (0.6 if stack_idx >= 2 else 0.0), p_col)


func _draw_diamond(center: Vector2, dir: Vector2, perp: Vector2, half_sz: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		center + dir * (half_sz * 1.35),
		center + perp * (half_sz * 0.85),
		center - dir * (half_sz * 1.35),
		center - perp * (half_sz * 0.85),
	])
	draw_colored_polygon(pts, col)
