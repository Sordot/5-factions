class_name TimelineGraph
extends Control

const METRIC_ARMY_VALUE: StringName = &"army_value"
const METRIC_INCOME_RATE: StringName = &"income_rate"
const METRIC_UNIT_COUNT: StringName = &"unit_count"

var _samples: Array = []
var _metric_key: StringName = METRIC_ARMY_VALUE
var _team_names: Dictionary = {}
var _team_colors: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(540.0, 220.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_samples(samples: Array, team_names: Dictionary = {}, team_colors: Dictionary = {}) -> void:
	_samples = samples.duplicate(true)
	_team_names = team_names.duplicate()
	_team_colors = team_colors.duplicate()
	queue_redraw()


func set_metric(metric_key: StringName) -> void:
	if _metric_key == metric_key:
		return
	_metric_key = metric_key
	queue_redraw()


func get_metric() -> StringName:
	return _metric_key


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if rect.size.x < 40.0 or rect.size.y < 40.0:
		return

	# Technozen dark glass chart backdrop
	draw_rect(rect, Color(0.032, 0.056, 0.082, 0.94), true)
	draw_rect(rect, Color(0.20, 0.62, 0.72, 0.55), false, 1.2)

	var font: Font = ThemeDB.fallback_font
	var pad_left: float = 52.0
	var pad_right: float = 16.0
	var pad_top: float = 28.0
	var pad_bottom: float = 26.0
	var plot: Rect2 = Rect2(
		Vector2(pad_left, pad_top),
		Vector2(maxf(20.0, rect.size.x - pad_left - pad_right), maxf(20.0, rect.size.y - pad_top - pad_bottom))
	)

	# Metric header (top-left)
	var metric_title: String = _get_metric_title(_metric_key)
	draw_string(font, Vector2(pad_left, 17.0), metric_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.90, 0.96, 0.92))

	if _samples.is_empty():
		var msg: String = "No timeline samples recorded yet."
		var tw: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 12).x
		draw_string(font, Vector2(plot.position.x + (plot.size.x - tw) * 0.5, plot.position.y + plot.size.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.76, 0.84, 0.78))
		return

	# Discover all team IDs present in samples
	var team_ids: Array[int] = []
	var max_time: float = 10.0
	var raw_max_val: float = 0.0
	for s_var: Variant in _samples:
		if not (s_var is Dictionary):
			continue
		var s: Dictionary = s_var as Dictionary
		max_time = maxf(max_time, float(s.get("time", 0.0)))
		var teams_dict: Variant = s.get("teams", {})
		if teams_dict is Dictionary:
			for k: Variant in (teams_dict as Dictionary).keys():
				var tid: int = int(k)
				if not team_ids.has(tid):
					team_ids.append(tid)
				var td: Variant = (teams_dict as Dictionary)[k]
				if td is Dictionary:
					var v: float = float((td as Dictionary).get(_metric_key, 0.0))
					raw_max_val = maxf(raw_max_val, v)
	team_ids.sort()

	var y_max: float = _compute_nice_ceiling(raw_max_val)

	# Horizontal gridlines & Y-axis labels (0%, 25%, 50%, 75%, 100%)
	var y_steps: int = 4
	for i: int in range(y_steps + 1):
		var frac: float = float(i) / float(y_steps)
		var gy: float = plot.end.y - frac * plot.size.y
		var grid_col: Color = Color(0.24, 0.54, 0.64, 0.30 if i == 0 else 0.16)
		draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), grid_col, 1.0)
		var val_num: int = int(round(y_max * frac))
		var lbl: String = _format_compact_value(val_num)
		var lbl_w: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_RIGHT, -1, 10).x
		draw_string(font, Vector2(plot.position.x - lbl_w - 6.0, gy + 3.5), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.58, 0.78, 0.86, 0.85))

	# Vertical gridlines & time axis ticks
	var x_steps: int = 5
	for j: int in range(x_steps + 1):
		var fx: float = float(j) / float(x_steps)
		var gx: float = plot.position.x + fx * plot.size.x
		var v_col: Color = Color(0.24, 0.54, 0.64, 0.30 if j == 0 else 0.14)
		draw_line(Vector2(gx, plot.position.y), Vector2(gx, plot.end.y), v_col, 1.0)
		var t_lbl: String = _format_time(max_time * fx)
		var tw: float = font.get_string_size(t_lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 10).x
		var tx: float = clampf(gx - tw * 0.5, plot.position.x - 4.0, rect.size.x - tw - 4.0)
		draw_string(font, Vector2(tx, plot.end.y + 15.0), t_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.58, 0.78, 0.86, 0.85))

	# Plot each team's curve
	var legend_x: float = plot.end.x
	for idx_rev: int in range(team_ids.size() - 1, -1, -1):
		var tid: int = team_ids[idx_rev]
		var col: Color = _resolve_team_color(tid)
		var pts: PackedVector2Array = PackedVector2Array()
		var last_val: float = 0.0
		for s_var: Variant in _samples:
			if not (s_var is Dictionary):
				continue
			var s: Dictionary = s_var as Dictionary
			var t_val: float = float(s.get("time", 0.0))
			var teams_dict: Dictionary = s.get("teams", {}) as Dictionary
			var td: Dictionary = teams_dict.get(tid, teams_dict.get(str(tid), {})) as Dictionary
			var metric_val: float = float(td.get(_metric_key, 0.0))
			last_val = metric_val
			var px: float = plot.position.x + clampf(t_val / maxf(1.0, max_time), 0.0, 1.0) * plot.size.x
			var py: float = plot.end.y - clampf(metric_val / maxf(1.0, y_max), 0.0, 1.0) * plot.size.y
			pts.append(Vector2(px, py))

		if pts.size() == 1:
			# Extend single point horizontally so a 1-sample match still displays cleanly
			var p0: Vector2 = pts[0]
			pts.append(Vector2(plot.end.x, p0.y))

		if pts.size() >= 2:
			# Subtle translucent area fill beneath curve
			var fill_poly: PackedVector2Array = PackedVector2Array()
			fill_poly.append(Vector2(pts[0].x, plot.end.y))
			for pt: Vector2 in pts:
				fill_poly.append(pt)
			fill_poly.append(Vector2(pts[pts.size() - 1].x, plot.end.y))
			draw_colored_polygon(fill_poly, Color(col.r, col.g, col.b, 0.08))

			# Outer soft glow + crisp anti-aliased polyline
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.28), 5.0, true)
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.96), 2.3, true)

			var end_pt: Vector2 = pts[pts.size() - 1]
			draw_circle(end_pt, 3.6, Color(col.r, col.g, col.b, 1.0))
			draw_circle(end_pt, 1.6, Color(0.96, 1.0, 1.0, 0.95))

		# Top-right team legend pill
		var t_name: String = String(_team_names.get(tid, "Team %d" % (tid + 1)))
		var leg_txt: String = "%s (%s)" % [t_name, _format_compact_value(int(round(last_val)))]
		var leg_w: float = font.get_string_size(leg_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		legend_x -= leg_w
		draw_string(font, Vector2(legend_x, 17.0), leg_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		legend_x -= 12.0
		draw_circle(Vector2(legend_x + 4.0, 13.0), 3.2, col)
		legend_x -= 12.0


func _resolve_team_color(tid: int) -> Color:
	if _team_colors.has(tid):
		return _team_colors[tid] as Color
	if TeamManager != null:
		return TeamManager.get_team_color(tid)
	return Color(0.22, 0.96, 0.88, 1.0) if tid == 0 else Color(1.0, 0.36, 0.28, 1.0)


func _get_metric_title(metric_key: StringName) -> String:
	match metric_key:
		METRIC_INCOME_RATE:
			return "COMBINED RESOURCE INCOME (PER MIN)"
		METRIC_UNIT_COUNT:
			return "LIVING UNIT COUNT"
		_:
			return "LIVING ARMY VALUE (TOTAL COST)"


func _compute_nice_ceiling(raw_max: float) -> float:
	if raw_max <= 1.0:
		return 10.0 if _metric_key == METRIC_UNIT_COUNT else 100.0
	var magnitude: float = pow(10.0, floor(log(raw_max) / log(10.0)))
	var normalized: float = raw_max / maxf(1.0, magnitude)
	var step: float = 1.0
	if normalized <= 1.2:
		step = 1.2
	elif normalized <= 2.0:
		step = 2.0
	elif normalized <= 2.5:
		step = 2.5
	elif normalized <= 4.0:
		step = 4.0
	elif normalized <= 5.0:
		step = 5.0
	elif normalized <= 8.0:
		step = 8.0
	else:
		step = 10.0
	return maxf(4.0, step * magnitude)


func _format_compact_value(val: int) -> String:
	if val >= 10000:
		return "%.1fk" % (float(val) / 1000.0)
	return str(val)


func _format_time(seconds: float) -> String:
	var total_s: int = maxi(0, int(round(seconds)))
	var mins: int = total_s / 60
	var secs: int = total_s % 60
	return "%d:%02d" % [mins, secs]
