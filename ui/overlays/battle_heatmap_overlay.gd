class_name BattleHeatmapOverlay
extends Node2D

## Post-Match Battle Heatmap Overlay (Milestone 3.5a).
## Renders layered radial heat blooms over engagement & casualty flashpoints
## during post-match View Battlefield inspection (toggleable via H or banner button).

var _events: Array[Dictionary] = []
var _is_enabled: bool = false


func _ready() -> void:
	add_to_group("battle_heatmap_overlay")
	z_index = 48
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func set_heatmap_events(events: Array) -> void:
	_events.clear()
	for ev: Variant in events:
		if ev is Dictionary:
			_events.append((ev as Dictionary).duplicate())
	if _is_enabled:
		queue_redraw()


func set_heatmap_visible(enabled: bool) -> void:
	_is_enabled = enabled
	visible = enabled
	if enabled:
		queue_redraw()


func is_heatmap_visible() -> bool:
	return _is_enabled


func toggle_heatmap() -> bool:
	set_heatmap_visible(not _is_enabled)
	return _is_enabled


func _draw() -> void:
	if not _is_enabled or _events.is_empty():
		return

	# Pass 1 — Broad cool/amber low-intensity atmospheric blooms
	for ev: Dictionary in _events:
		var pos: Vector2 = to_local(ev.get("pos", Vector2.ZERO) as Vector2)
		var w: float = clampf(float(ev.get("weight", 1.0)), 0.25, 5.0)
		var outer_r: float = clampf(42.0 + w * 24.0, 48.0, 155.0)
		var mid_r: float = outer_r * 0.56
		var core_r: float = outer_r * 0.26

		var low_a: float = clampf(0.055 + w * 0.022, 0.05, 0.16)
		var mid_a: float = clampf(0.08 + w * 0.032, 0.08, 0.24)
		var hot_a: float = clampf(0.11 + w * 0.042, 0.11, 0.34)

		draw_circle(pos, outer_r, Color(0.18, 0.72, 0.94, low_a))
		draw_circle(pos, mid_r, Color(1.0, 0.64, 0.14, mid_a))
		draw_circle(pos, core_r, Color(1.0, 0.24, 0.22, hot_a))

	# Pass 2 — Crisp skull/diamond flashpoint markers on Command Hub & heavy-unit death sites
	for ev: Dictionary in _events:
		var kind: StringName = ev.get("kind", &"") as StringName
		if kind != &"hub_destroyed" and kind != &"heavy_unit_death":
			continue
		var pos: Vector2 = to_local(ev.get("pos", Vector2.ZERO) as Vector2)
		var tid: int = int(ev.get("team", 0))
		var team_col: Color = TeamManager.get_team_color(tid) if TeamManager != null else Color(1.0, 0.36, 0.28, 1.0)
		if kind == &"hub_destroyed":
			var r: float = 13.0
			var dia: PackedVector2Array = PackedVector2Array([
				pos + Vector2(0.0, -r),
				pos + Vector2(r, 0.0),
				pos + Vector2(0.0, r),
				pos + Vector2(-r, 0.0),
			])
			draw_colored_polygon(dia, Color(0.06, 0.08, 0.12, 0.92))
			var outline: PackedVector2Array = dia.duplicate()
			outline.append(dia[0])
			draw_polyline(outline, Color(1.0, 0.32, 0.28, 0.98), 2.4, true)
			draw_line(pos + Vector2(-5.5, -5.5), pos + Vector2(5.5, 5.5), team_col, 2.2, true)
			draw_line(pos + Vector2(5.5, -5.5), pos + Vector2(-5.5, 5.5), team_col, 2.2, true)
		else:
			var r2: float = 7.5
			var dia2: PackedVector2Array = PackedVector2Array([
				pos + Vector2(0.0, -r2),
				pos + Vector2(r2, 0.0),
				pos + Vector2(0.0, r2),
				pos + Vector2(-r2, 0.0),
			])
			draw_colored_polygon(dia2, Color(0.08, 0.09, 0.13, 0.88))
			var out2: PackedVector2Array = dia2.duplicate()
			out2.append(dia2[0])
			draw_polyline(out2, Color(1.0, 0.78, 0.26, 0.95), 1.8, true)
			draw_circle(pos, 2.6, team_col)
