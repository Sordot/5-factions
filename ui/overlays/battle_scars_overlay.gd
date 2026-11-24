class_name BattleScarsOverlay
extends Node2D

const MAX_DECALS: int = 110
const REDRAW_INTERVAL: float = 0.10 # ~10 Hz fade refresh

var _decals: Array[Dictionary] = []
var _redraw_timer: float = 0.0
var _dirty: bool = false


func _ready() -> void:
	add_to_group("battle_scars")
	z_index = -6
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	queue_redraw()


func _exit_tree() -> void:
	if SettingsManager != null and SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.disconnect(_on_settings_changed)


func _on_settings_changed(category: StringName) -> void:
	if category == &"gameplay" or category == &"all":
		if SettingsManager != null and not SettingsManager.battle_scars_enabled:
			_decals.clear()
		_dirty = true
		queue_redraw()


func clear_scars() -> void:
	_decals.clear()
	_dirty = true
	queue_redraw()


func add_scar(kind: StringName, world_pos: Vector2, radius: float = 28.0, tint: Color = Color(1.0, 0.72, 0.34, 1.0)) -> void:
	if SettingsManager != null and not SettingsManager.battle_scars_enabled:
		return

	var life: float = 55.0
	match kind:
		&"scorch_small":
			life = 45.0
		&"scorch_large":
			life = 75.0
		&"wreck_splatter":
			life = 90.0

	var seed_val: int = int((Time.get_ticks_usec() ^ int(world_pos.x * 31.0) ^ int(world_pos.y * 17.0)) & 0x7FFFFFFF)
	var rot_val: float = fmod(float(seed_val % 3600) * 0.00174533, TAU)

	var entry: Dictionary = {
		"kind": kind,
		"pos": to_local(world_pos),
		"radius": clampf(radius, 10.0, 96.0),
		"tint": tint,
		"rot": rot_val,
		"seed": seed_val,
		"age": 0.0,
		"lifetime": life,
	}

	if _decals.size() >= MAX_DECALS:
		_decals.pop_front()
	_decals.append(entry)
	_dirty = true
	queue_redraw()


func _process(delta: float) -> void:
	if _decals.is_empty():
		return
	if SettingsManager != null and not SettingsManager.battle_scars_enabled:
		_decals.clear()
		queue_redraw()
		return

	var write_idx: int = 0
	for i: int in range(_decals.size()):
		var d: Dictionary = _decals[i]
		var next_age: float = float(d["age"]) + delta
		if next_age < float(d["lifetime"]):
			d["age"] = next_age
			_decals[write_idx] = d
			write_idx += 1
	if write_idx < _decals.size():
		_decals.resize(write_idx)

	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL or _dirty:
		_redraw_timer = 0.0
		_dirty = false
		queue_redraw()


func _draw() -> void:
	if _decals.is_empty():
		return
	if SettingsManager != null and not SettingsManager.battle_scars_enabled:
		return

	for d: Dictionary in _decals:
		var age: float = float(d["age"])
		var life: float = maxf(1.0, float(d["lifetime"]))
		var u: float = clampf(age / life, 0.0, 1.0)
		# Hold full visibility for 80% of lifetime, then fade out cleanly over final 20%
		var fade: float = 1.0 if u < 0.80 else clampf(1.0 - (u - 0.80) / 0.20, 0.0, 1.0)
		if fade <= 0.01:
			continue

		var kind: StringName = d["kind"]
		var pos: Vector2 = d["pos"] as Vector2
		var r: float = float(d["radius"])
		var tint: Color = d["tint"] as Color
		var rot: float = float(d["rot"])
		var seed_val: int = int(d["seed"])

		match kind:
			&"scorch_small":
				_draw_scorch(pos, r, tint, rot, seed_val, u, fade, false)
			&"scorch_large":
				_draw_scorch(pos, r, tint, rot, seed_val, u, fade, true)
			&"wreck_splatter":
				_draw_wreck_splatter(pos, r, tint, rot, seed_val, u, fade)
			_:
				_draw_scorch(pos, r, tint, rot, seed_val, u, fade, false)


func _draw_scorch(pos: Vector2, r: float, tint: Color, rot: float, seed_val: int, u: float, fade: float, is_large: bool) -> void:
	# Soft outer soot halo
	draw_circle(pos, r * 1.08, Color(0.025, 0.035, 0.05, 0.28 * fade))
	# Jagged charred crater core polygon
	var sides: int = 9 if is_large else 7
	var poly: PackedVector2Array = PackedVector2Array()
	poly.resize(sides)
	for i: int in range(sides):
		var ang: float = rot + (TAU * float(i) / float(sides))
		var jitter: float = 0.72 + float(((seed_val + i * 73) % 100)) * 0.0042
		poly[i] = pos + Vector2.RIGHT.rotated(ang) * (r * jitter)
	draw_colored_polygon(poly, Color(0.03, 0.04, 0.055, (0.58 if is_large else 0.46) * fade))
	draw_circle(pos, r * 0.44, Color(0.015, 0.022, 0.032, 0.62 * fade))

	# Subtle radial fracture lines + cooling thermal ember glow during first 25% of scar lifetime
	var ember_fade: float = clampf(1.0 - (u / 0.26), 0.0, 1.0) * fade
	var crack_count: int = 6 if is_large else 4
	for k: int in range(crack_count):
		var ang: float = rot + (TAU * float(k) / float(crack_count)) + float((seed_val + k * 29) % 13) * 0.04
		var dir: Vector2 = Vector2.RIGHT.rotated(ang)
		var len_k: float = r * (0.82 + float((seed_val + k * 41) % 35) * 0.01)
		var p0: Vector2 = pos + dir * (r * 0.16)
		var p1: Vector2 = pos + dir * len_k
		draw_line(p0, p1, Color(0.01, 0.015, 0.022, 0.56 * fade), 1.6 if is_large else 1.2, true)
		if ember_fade > 0.02:
			draw_line(p0, pos + dir * (len_k * 0.65), Color(tint.r, tint.g, tint.b, 0.36 * ember_fade), 1.3, true)

	if is_large:
		draw_arc(pos, r * 0.66, rot, rot + TAU, 20, Color(0.14, 0.20, 0.26, 0.28 * fade), 1.2, true)
		if ember_fade > 0.02:
			draw_circle(pos, r * 0.26, Color(tint.r, tint.g, tint.b, 0.18 * ember_fade))


func _draw_wreck_splatter(pos: Vector2, r: float, tint: Color, rot: float, seed_val: int, u: float, fade: float) -> void:
	# Coolant / chassis oil pool
	var blob: PackedVector2Array = PackedVector2Array()
	var pts: int = 8
	blob.resize(pts)
	for i: int in range(pts):
		var ang: float = rot + (TAU * float(i) / float(pts))
		var rad: float = r * (0.64 + float(((seed_val + i * 59) % 100)) * 0.005)
		blob[i] = pos + Vector2.RIGHT.rotated(ang) * rad
	draw_colored_polygon(blob, Color(0.03, 0.05, 0.075, 0.52 * fade))

	# Cooling circuit stain (team/salvage tint)
	var glow_fade: float = clampf(1.0 - (u / 0.38), 0.0, 1.0) * fade
	if glow_fade > 0.02:
		draw_circle(pos, r * 0.36, Color(tint.r, tint.g, tint.b, 0.16 * glow_fade))
		draw_arc(pos, r * 0.48, rot, rot + PI * 1.35, 14, Color(tint.r, tint.g, tint.b, 0.28 * glow_fade), 1.4, true)

	# 5 scattered metallic hull plate shards
	for k: int in range(5):
		var ang: float = rot + (TAU * float(k) / 5.0) + float((seed_val + k * 19) % 17) * 0.05
		var dist: float = r * (0.28 + float((seed_val + k * 47) % 55) * 0.011)
		var shard_center: Vector2 = pos + Vector2.RIGHT.rotated(ang) * dist
		var dir: Vector2 = Vector2.RIGHT.rotated(ang + 0.65)
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var half_l: float = 3.5 + float((seed_val + k * 13) % 5)
		var half_w: float = 1.6 + float((seed_val + k * 7) % 3) * 0.6
		var shard_poly: PackedVector2Array = PackedVector2Array([
			shard_center - dir * half_l - perp * half_w,
			shard_center + dir * half_l - perp * (half_w * 0.6),
			shard_center + dir * (half_l * 0.8) + perp * half_w,
			shard_center - dir * (half_l * 0.9) + perp * (half_w * 0.7),
		])
		draw_colored_polygon(shard_poly, Color(0.24, 0.31, 0.38, 0.74 * fade))
		draw_polyline(shard_poly + PackedVector2Array([shard_poly[0]]), Color(tint.r, tint.g, tint.b, 0.34 * fade), 1.0, true)
