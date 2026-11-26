class_name CombatVFX
extends Node2D

enum VFXMode {
	MORTAR_SHELL,
	MELEE_CLEAVE,
	ARMOR_PIERCE_SPARK,
	DEATH_BURST,
	HEAL_TICK,
	RANK_UP_PULSE,
	REPAIR_BEAM,
	FLOATING_TEXT,
	BUILDING_COMPLETE,
	RALLY_RIPPLE,
	SHIELD_SHATTER,
}

var _mode: VFXMode = VFXMode.DEATH_BURST
var _elapsed: float = 0.0
var _duration: float = 0.30
var _color: Color = Color(0.32, 0.98, 0.90, 1.0)

# Mortar shell state
var _from_world: Vector2 = Vector2.ZERO
var _target_world: Vector2 = Vector2.ZERO
var _radius: float = 64.0
var _flight_time: float = 0.48
var _blast_duration: float = 0.28
var _arc_height: float = 72.0
var _impacted: bool = false
var _on_impact: Callable = Callable()

# Cleave / spark / burst state
var _dir: Vector2 = Vector2.RIGHT
var _is_heavy: bool = false
var _is_monolith_style: bool = false
var _rank_level: int = 1
var _seed: int = 1337
var _draw_visuals: bool = true
var _label_text: String = ""
var is_pooled: bool = false


func is_critical_flight() -> bool:
	return _mode == VFXMode.MORTAR_SHELL and not _impacted


func reset_for_pool() -> void:
	_mode = VFXMode.DEATH_BURST
	_elapsed = 0.0
	_duration = 0.30
	_color = Color(0.32, 0.98, 0.90, 1.0)
	_from_world = Vector2.ZERO
	_target_world = Vector2.ZERO
	_radius = 64.0
	_flight_time = 0.48
	_blast_duration = 0.28
	_arc_height = 72.0
	_impacted = false
	_on_impact = Callable()
	_dir = Vector2.RIGHT
	_is_heavy = false
	_is_monolith_style = false
	_rank_level = 1
	_draw_visuals = true
	_label_text = ""
	global_position = Vector2.ZERO


func recycle() -> void:
	_on_impact = Callable()
	if is_pooled and VFXPool != null:
		VFXPool.recycle_node(self)
	else:
		queue_free()


func setup_mortar_shell(
	from_world: Vector2,
	target_world: Vector2,
	splash_radius: float,
	flight_time: float,
	arc_height: float,
	vfx_color: Color,
	on_impact_callback: Callable = Callable()
) -> void:
	_mode = VFXMode.MORTAR_SHELL
	_from_world = from_world
	_target_world = target_world
	_radius = maxf(18.0, splash_radius)
	_flight_time = maxf(0.18, flight_time)
	_blast_duration = 0.28
	_duration = _flight_time + _blast_duration
	_arc_height = maxf(28.0, arc_height)
	_color = vfx_color
	_on_impact = on_impact_callback
	_impacted = false
	_elapsed = 0.0
	_refresh_fog_visibility()
	queue_redraw()


func setup_melee_cleave(origin_world: Vector2, target_world: Vector2, vfx_color: Color) -> void:
	_mode = VFXMode.MELEE_CLEAVE
	_from_world = origin_world
	_target_world = target_world
	var diff: Vector2 = target_world - origin_world
	_dir = diff.normalized() if diff.length_squared() > 0.01 else Vector2.RIGHT
	_color = vfx_color
	_duration = 0.16
	_elapsed = 0.0
	_seed = int(Time.get_ticks_usec() & 0x7FFFFFFF)
	queue_redraw()


func setup_armor_pierce_spark(world_pos: Vector2, dir: Vector2, vfx_color: Color) -> void:
	_mode = VFXMode.ARMOR_PIERCE_SPARK
	_target_world = world_pos
	_dir = dir.normalized() if dir.length_squared() > 0.01 else Vector2.RIGHT
	_color = vfx_color
	_duration = 0.22
	_elapsed = 0.0
	_seed = int(Time.get_ticks_usec() & 0x7FFFFFFF)
	queue_redraw()


func setup_death_burst(world_pos: Vector2, radius: float, primary_color: Color, is_heavy: bool = false) -> void:
	_mode = VFXMode.DEATH_BURST
	_target_world = world_pos
	_radius = maxf(14.0, radius)
	_color = primary_color
	_is_heavy = is_heavy
	_duration = 0.48 if is_heavy else 0.28
	_elapsed = 0.0
	_seed = int(Time.get_ticks_usec() & 0x7FFFFFFF)
	queue_redraw()


func setup_heal_tick(world_pos: Vector2, vfx_color: Color = Color(0.32, 1.0, 0.68, 0.95)) -> void:
	_mode = VFXMode.HEAL_TICK
	_target_world = world_pos
	_color = vfx_color
	_duration = 0.56
	_elapsed = 0.0
	queue_redraw()


func setup_rank_up_pulse(world_pos: Vector2, rank_level: int = 1) -> void:
	_mode = VFXMode.RANK_UP_PULSE
	_target_world = world_pos
	_rank_level = clampi(rank_level, 1, 3)
	_color = Color(1.0, 0.86, 0.28, 1.0) if _rank_level >= 3 else Color(0.42, 0.96, 1.0, 1.0)
	_duration = 0.62
	_elapsed = 0.0
	queue_redraw()


func setup_repair_beam(from_world: Vector2, to_world: Vector2, vfx_color: Color = Color(0.24, 0.98, 0.86, 0.95)) -> void:
	_mode = VFXMode.REPAIR_BEAM
	_from_world = from_world
	_target_world = to_world
	_color = vfx_color
	_duration = 0.20
	_elapsed = 0.0
	_seed = int(Time.get_ticks_usec() & 0x7FFFFFFF)
	queue_redraw()


func setup_floating_text(world_pos: Vector2, text_str: String, vfx_color: Color = Color(1.0, 0.86, 0.34, 1.0)) -> void:
	_mode = VFXMode.FLOATING_TEXT
	_target_world = world_pos
	_label_text = text_str
	_color = vfx_color
	_duration = 1.25
	_elapsed = 0.0
	queue_redraw()


func setup_building_complete(world_pos: Vector2, footprint_radius: float, vfx_color: Color = Color(0.24, 0.96, 0.88, 1.0)) -> void:
	_mode = VFXMode.BUILDING_COMPLETE
	_target_world = world_pos
	_radius = maxf(24.0, footprint_radius)
	_color = vfx_color
	_duration = 0.36
	_elapsed = 0.0
	queue_redraw()


func setup_rally_ripple(world_pos: Vector2, vfx_color: Color = Color(0.22, 0.92, 1.0, 1.0)) -> void:
	_mode = VFXMode.RALLY_RIPPLE
	_target_world = world_pos
	_radius = 30.0
	_color = vfx_color
	_duration = 0.35
	_elapsed = 0.0
	queue_redraw()


func setup_shield_shatter(world_pos: Vector2, radius: float, is_monolith_style: bool = false) -> void:
	_mode = VFXMode.SHIELD_SHATTER
	_target_world = world_pos
	_radius = maxf(16.0, radius)
	_is_monolith_style = is_monolith_style
	_color = Color(0.220, 0.741, 0.973, 1.0) # #38BDF8
	_duration = 0.34
	_elapsed = 0.0
	_seed = int(Time.get_ticks_usec() & 0x7FFFFFFF)
	_draw_visuals = true
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _mode == VFXMode.MORTAR_SHELL:
		if not _impacted and _elapsed >= _flight_time:
			_impacted = true
			if is_inside_tree():
				var scars: Node = get_tree().get_first_node_in_group("battle_scars")
				if scars != null and scars.has_method("add_scar"):
					var scar_kind: StringName = &"scorch_large" if _radius >= 50.0 else &"scorch_small"
					scars.call("add_scar", scar_kind, _target_world, clampf(_radius * 0.62, 16.0, 56.0), _color)
			if _on_impact.is_valid():
				_on_impact.call()
		_refresh_fog_visibility()
	if _elapsed >= _duration:
		if _mode == VFXMode.MORTAR_SHELL and not _impacted:
			_impacted = true
			if _on_impact.is_valid():
				_on_impact.call()
		recycle()
		return
	queue_redraw()


func _refresh_fog_visibility() -> void:
	if not is_inside_tree():
		_draw_visuals = true
		return
	var fog: Node = get_tree().get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
		_draw_visuals = bool(fog.call("is_world_pos_visible", _target_world)) or bool(fog.call("is_world_pos_visible", _from_world))
	else:
		_draw_visuals = true


func _draw() -> void:
	if not _draw_visuals:
		return
	match _mode:
		VFXMode.MORTAR_SHELL:
			_draw_mortar_shell()
		VFXMode.MELEE_CLEAVE:
			_draw_melee_cleave()
		VFXMode.ARMOR_PIERCE_SPARK:
			_draw_armor_pierce_spark()
		VFXMode.DEATH_BURST:
			_draw_death_burst()
		VFXMode.HEAL_TICK:
			_draw_heal_tick()
		VFXMode.RANK_UP_PULSE:
			_draw_rank_up_pulse()
		VFXMode.REPAIR_BEAM:
			_draw_repair_beam()
		VFXMode.FLOATING_TEXT:
			_draw_floating_text()
		VFXMode.BUILDING_COMPLETE:
			_draw_building_complete()
		VFXMode.RALLY_RIPPLE:
			_draw_rally_ripple()
		VFXMode.SHIELD_SHATTER:
			_draw_shield_shatter()


func _draw_mortar_shell() -> void:
	var p0: Vector2 = to_local(_from_world)
	var p1: Vector2 = to_local(_target_world)

	if not _impacted:
		var u: float = clampf(_elapsed / _flight_time, 0.0, 1.0)
		# Ground impact telegraph ring: dashed outer splash boundary + filling inner danger pulse
		var warn_alpha: float = lerpf(0.42, 0.92, u)
		var ring_col: Color = Color(_color.r, _color.g, _color.b, warn_alpha)
		_draw_dashed_circle(p1, _radius, ring_col, 2.0, 20)
		# Filling inner telegraph pulse that reaches outer splash radius right at impact
		var fill_r: float = lerpf(_radius * 0.14, _radius, u)
		draw_circle(p1, fill_r, Color(_color.r, _color.g, _color.b, 0.07 + 0.14 * u))
		draw_arc(p1, fill_r, 0.0, TAU, 28, Color(_color.r, _color.g, _color.b, 0.30 + 0.45 * u), 1.4, true)
		# Target center cross pip
		draw_line(p1 + Vector2(-6.0, 0.0), p1 + Vector2(6.0, 0.0), ring_col, 1.4, true)
		draw_line(p1 + Vector2(0.0, -6.0), p1 + Vector2(0.0, 6.0), ring_col, 1.4, true)

		# Faint parabolic trajectory arc behind shell
		var trail_steps: int = 10
		var trail_start: float = maxf(0.0, u - 0.38)
		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(trail_steps + 1)
		for i: int in range(trail_steps + 1):
			var tu: float = lerpf(trail_start, u, float(i) / float(trail_steps))
			pts[i] = p0.lerp(p1, tu) + Vector2(0.0, -sin(tu * PI) * _arc_height)
		draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.58), 2.4, true)

		# Ground shadow beneath arcing shell
		var ground_pos: Vector2 = p0.lerp(p1, u)
		draw_circle(ground_pos, 4.5, Color(0.02, 0.05, 0.06, 0.34))

		# Caustic shell orb with bright core
		var shell_pos: Vector2 = ground_pos + Vector2(0.0, -sin(u * PI) * _arc_height)
		draw_circle(shell_pos, 6.8, Color(_color.r, _color.g, _color.b, 0.36))
		draw_circle(shell_pos, 4.2, _color)
		draw_circle(shell_pos, 2.0, Color(0.95, 1.0, 0.94, 0.95))
	else:
		# Impact blast shockwave + caustic splash scatter
		var bt: float = clampf((_elapsed - _flight_time) / _blast_duration, 0.0, 1.0)
		var fade: float = 1.0 - bt
		var blast_r: float = lerpf(_radius * 0.30, _radius * 1.06, sqrt(bt))
		draw_circle(p1, blast_r, Color(_color.r, _color.g, _color.b, fade * 0.28))
		draw_arc(p1, blast_r, 0.0, TAU, 36, Color(_color.r, _color.g, _color.b, fade * 0.95), 3.2, true)
		draw_arc(p1, blast_r * 0.65, 0.0, TAU, 24, Color(0.95, 1.0, 0.92, fade * 0.72), 2.0, true)
		# Radial splash droplets
		for i: int in range(8):
			var ang: float = (TAU * float(i) / 8.0) + 0.35
			var radial: Vector2 = Vector2.RIGHT.rotated(ang)
			var inner_p: Vector2 = p1 + radial * (_radius * 0.25 + blast_r * 0.32)
			var outer_p: Vector2 = p1 + radial * (_radius * 0.35 + blast_r * 0.62)
			draw_line(inner_p, outer_p, Color(_color.r, _color.g, _color.b, fade * 0.85), 2.0, true)


func _draw_melee_cleave() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var fade: float = 1.0 - t
	var center: Vector2 = to_local(_from_world.lerp(_target_world, 0.68))
	var base_ang: float = _dir.angle()
	var sweep: float = lerpf(0.75, 1.15, t)
	var arc_r: float = lerpf(11.0, 22.0, sqrt(t))

	# Outer glowing slash crescent
	draw_arc(center, arc_r, base_ang - sweep, base_ang + sweep, 14, Color(_color.r, _color.g, _color.b, fade * 0.95), 3.4 * fade + 1.2, true)
	# White-hot blade edge
	draw_arc(center, arc_r * 0.82, base_ang - sweep * 0.85, base_ang + sweep * 0.85, 12, Color(1.0, 0.98, 0.88, fade * 0.88), 1.8, true)
	# Twin acid slash streaks
	var perp: Vector2 = Vector2(-_dir.y, _dir.x)
	var tip: Vector2 = to_local(_target_world)
	for s: float in [-1.0, 1.0]:
		var sp0: Vector2 = tip - _dir * 6.0 + perp * (s * 7.0)
		var sp1: Vector2 = tip + _dir * (8.0 + t * 9.0) + perp * (s * (11.0 + t * 6.0))
		draw_line(sp0, sp1, Color(_color.r, _color.g, _color.b, fade * 0.85), 1.8, true)


func _draw_armor_pierce_spark() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var fade: float = 1.0 - t
	var p: Vector2 = to_local(_target_world)
	var back_dir: Vector2 = -_dir
	var core_r: float = lerpf(8.5, 2.0, t)

	# Bright anti-armor flash ring + golden starburst
	draw_circle(p, core_r * 1.4, Color(_color.r, _color.g, _color.b, fade * 0.38))
	draw_circle(p, core_r * 0.72, Color(1.0, 0.99, 0.90, fade * 0.95))
	draw_arc(p, lerpf(6.0, 24.0, sqrt(t)), 0.0, TAU, 20, Color(_color.r, _color.g, _color.b, fade * 0.90), 2.2, true)

	# Focused armor-shatter rays fanning backward & radially
	for i: int in range(6):
		var spread: float = (float(i) - 2.5) * 0.42
		var ray_dir: Vector2 = back_dir.rotated(spread)
		var r0: Vector2 = p + ray_dir * lerpf(3.0, 10.0, t)
		var r1: Vector2 = p + ray_dir * lerpf(10.0, 26.0, sqrt(t))
		draw_line(r0, r1, Color(1.0, 0.92, 0.56, fade * 0.95), 2.0, true)


func _draw_death_burst() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var fade: float = 1.0 - t
	var p: Vector2 = to_local(_target_world)

	var max_r: float = _radius * (1.85 if _is_heavy else 1.45)
	var cur_r: float = lerpf(_radius * 0.22, max_r, sqrt(t))

	# Expanding shockwave ring
	draw_circle(p, cur_r * 0.65, Color(_color.r, _color.g, _color.b, fade * (0.28 if _is_heavy else 0.18)))
	draw_arc(p, cur_r, 0.0, TAU, 32 if _is_heavy else 20, Color(_color.r, _color.g, _color.b, fade * 0.92), 3.2 if _is_heavy else 2.0, true)

	if _is_heavy:
		# Secondary delayed inner rupture ring + white flash core
		var inner_r: float = lerpf(_radius * 0.12, max_r * 0.68, t)
		draw_arc(p, inner_r, 0.0, TAU, 24, Color(1.0, 0.92, 0.72, fade * 0.82), 2.2, true)
		if t < 0.35:
			var flash_fade: float = 1.0 - (t / 0.35)
			draw_circle(p, _radius * 0.55 * flash_fade, Color(1.0, 0.98, 0.92, flash_fade * 0.85))

	# Flying geometric shards/sparks
	var shard_count: int = 12 if _is_heavy else 7
	var angle_offset: float = float(_seed % 360) * 0.017453
	for i: int in range(shard_count):
		var ang: float = angle_offset + (TAU * float(i) / float(shard_count)) + float((i * 17) % 7) * 0.06
		var radial: Vector2 = Vector2.RIGHT.rotated(ang)
		var speed_scale: float = 0.78 + float((i * 31) % 10) * 0.055
		var dist: float = lerpf(_radius * 0.18, max_r * 1.15 * speed_scale, sqrt(t))
		var shard_len: float = (10.0 if _is_heavy else 6.0) * fade
		var s0: Vector2 = p + radial * dist
		var s1: Vector2 = p + radial * (dist + shard_len)
		var shard_col: Color = Color(1.0, 0.92, 0.72, fade * 0.92) if (i % 3 == 0) else Color(_color.r, _color.g, _color.b, fade * 0.88)
		draw_line(s0, s1, shard_col, 2.4 if _is_heavy else 1.6, true)


func _draw_heal_tick() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var fade: float = sin(t * PI) if t < 0.25 else (1.0 - ((t - 0.25) / 0.75))
	var p: Vector2 = to_local(_target_world) + Vector2(0.0, -14.0 - t * 20.0)
	var col: Color = Color(_color.r, _color.g, _color.b, clampf(fade, 0.0, 1.0) * 0.92)
	var arm: float = 4.2
	draw_line(p + Vector2(-arm, 0.0), p + Vector2(arm, 0.0), col, 2.0, true)
	draw_line(p + Vector2(0.0, -arm), p + Vector2(0.0, arm), col, 2.0, true)


func _draw_rank_up_pulse() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var fade: float = 1.0 - t
	var p: Vector2 = to_local(_target_world)
	var ring_r: float = lerpf(12.0, 38.0, sqrt(t))
	draw_circle(p, ring_r * 0.72, Color(_color.r, _color.g, _color.b, fade * 0.16))
	draw_arc(p, ring_r, 0.0, TAU, 28, Color(_color.r, _color.g, _color.b, fade * 0.94), 2.4, true)
	draw_arc(p, ring_r * 0.68, 0.0, TAU, 20, Color(1.0, 0.98, 0.84, fade * 0.80), 1.5, true)
	# Rising rank chevrons above unit
	var lift: float = -18.0 - t * 24.0
	for i: int in range(_rank_level):
		var cy: float = lift - float(i) * 5.5
		var chev: PackedVector2Array = PackedVector2Array([
			p + Vector2(-5.5, cy + 3.2),
			p + Vector2(0.0, cy - 2.2),
			p + Vector2(5.5, cy + 3.2),
		])
		draw_polyline(chev, Color(_color.r, _color.g, _color.b, fade * 0.96), 2.0, true)


func _draw_repair_beam() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var fade: float = 1.0 - t * 0.65
	var p0: Vector2 = to_local(_from_world)
	var p1: Vector2 = to_local(_target_world)
	# Soft outer nanite beam + crisp bright inner conduit
	draw_line(p0, p1, Color(_color.r, _color.g, _color.b, fade * 0.28), 6.0, true)
	draw_line(p0, p1, Color(_color.r, _color.g, _color.b, fade * 0.90), 2.2, true)
	draw_line(p0, p1, Color(0.92, 1.0, 0.98, fade * 0.85), 1.0, true)
	# Traveling nanite pulse bead
	var bead: Vector2 = p0.lerp(p1, t)
	draw_circle(bead, 3.2, Color(0.94, 1.0, 0.98, fade))
	# Welding sparks at target point
	draw_circle(p1, lerpf(6.5, 2.5, t), Color(_color.r, _color.g, _color.b, fade * 0.65))
	var ang0: float = float(_seed % 360) * 0.017453
	for k: int in range(4):
		var dir: Vector2 = Vector2.RIGHT.rotated(ang0 + float(k) * 1.57)
		draw_line(p1 + dir * 2.0, p1 + dir * lerpf(4.0, 12.0, t), Color(0.96, 1.0, 0.88, fade * 0.92), 1.5, true)


func _draw_floating_text() -> void:
	if _label_text.is_empty():
		return
	var t: float = clampf(_elapsed / maxf(0.01, _duration), 0.0, 1.0)
	var fade: float = 1.0 if t < 0.55 else clampf(1.0 - (t - 0.55) / 0.45, 0.0, 1.0)
	var p: Vector2 = to_local(_target_world) + Vector2(0.0, -t * 36.0)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	var sz: Vector2 = font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var box_pos: Vector2 = p + Vector2(-sz.x * 0.5 - 7.0, -sz.y * 0.5 - 4.0)
	draw_rect(Rect2(box_pos, Vector2(sz.x + 14.0, sz.y + 8.0)), Color(0.03, 0.06, 0.10, 0.82 * fade), true)
	draw_rect(Rect2(box_pos, Vector2(sz.x + 14.0, sz.y + 8.0)), Color(_color.r, _color.g, _color.b, 0.88 * fade), false, 1.2)
	draw_string(font, box_pos + Vector2(7.0, sz.y + 1.0), _label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(_color.r, _color.g, _color.b, fade))


func _draw_building_complete() -> void:
	var t: float = clampf(_elapsed / maxf(0.01, _duration), 0.0, 1.0)
	var ease_out: float = 1.0 - pow(1.0 - t, 3.0)
	var fade: float = 1.0 - t
	var p: Vector2 = to_local(_target_world)

	# Expanding crisp perimeter pulse ring
	var outer_r: float = lerpf(_radius * 0.92, _radius * 1.48, ease_out)
	draw_arc(p, outer_r, 0.0, TAU, 36, Color(_color.r, _color.g, _color.b, fade * 0.92), 2.4 * fade + 0.8, true)

	# Brief 0.22s bright Technozen frame flash around footprint
	if _elapsed < 0.22:
		var ft: float = 1.0 - (_elapsed / 0.22)
		var frame_r: float = _radius * (1.0 + (1.0 - ft) * 0.10)
		draw_circle(p, frame_r * 0.92, Color(_color.r, _color.g, _color.b, ft * 0.22))
		draw_arc(p, frame_r, 0.0, TAU, 32, Color(0.92, 1.0, 0.98, ft * 0.90), 2.6, true)


func _draw_rally_ripple() -> void:
	var t: float = clampf(_elapsed / maxf(0.01, _duration), 0.0, 1.0)
	var ease_out: float = 1.0 - pow(1.0 - t, 2.4)
	var fade: float = 1.0 - t
	var p: Vector2 = to_local(_target_world)

	# Primary expanding concentric ripple
	var r1: float = lerpf(8.0, _radius * 1.25, ease_out)
	draw_arc(p, r1, 0.0, TAU, 28, Color(_color.r, _color.g, _color.b, fade * 0.92), 2.0, true)
	# Secondary trailing inner ripple
	var t2: float = clampf((t - 0.16) / 0.84, 0.0, 1.0)
	if t2 > 0.0:
		var r2: float = lerpf(6.0, _radius * 0.88, 1.0 - pow(1.0 - t2, 2.0))
		draw_arc(p, r2, 0.0, TAU, 24, Color(0.92, 1.0, 0.98, (1.0 - t2) * 0.72), 1.4, true)
	# Crisp cardinal tick pips expanding outward
	for i: int in range(4):
		var dir: Vector2 = Vector2.RIGHT.rotated(float(i) * PI * 0.5)
		draw_line(p + dir * (r1 - 3.0), p + dir * (r1 + 4.5), Color(_color.r, _color.g, _color.b, fade * 0.85), 1.5, true)


func _draw_shield_shatter() -> void:
	var t: float = clampf(_elapsed / maxf(0.01, _duration), 0.0, 1.0)
	var ease_out: float = sqrt(t)
	var fade: float = 1.0 - t
	var p: Vector2 = to_local(_target_world)

	var cyan: Color = Color(0.220, 0.741, 0.973, 1.0) # #38BDF8
	var offwhite: Color = Color(0.949, 0.937, 0.914, 1.0) # #F2EFE9
	var amber: Color = Color(1.0, 0.624, 0.110, 1.0) # #FF9F1C
	var ring_col: Color = cyan.lerp(offwhite, clampf(1.0 - t * 2.2, 0.0, 1.0))

	# Expanding fractured cyan-white ring (6 crisp broken segments)
	var ring_r: float = lerpf(_radius * 0.80, _radius * 1.65, ease_out)
	var seg_count: int = 6
	var seg_step: float = TAU / float(seg_count)
	var base_rot: float = float(_seed % 360) * 0.017453
	for s: int in range(seg_count):
		var a0: float = base_rot + float(s) * seg_step + t * 0.25
		var span: float = seg_step * lerpf(0.76, 0.34, t)
		draw_arc(p, ring_r, a0, a0 + span, 6, Color(ring_col.r, ring_col.g, ring_col.b, fade * 0.96), 2.8 * fade + 0.8, true)

	# Brief crisp flash halo on snap frame
	if t < 0.24:
		var ff: float = 1.0 - (t / 0.24)
		draw_circle(p, _radius * 0.95, Color(offwhite.r, offwhite.g, offwhite.b, ff * 0.28))

	# 7 angular polygonal shard fragments flying outward
	var shard_count: int = 7
	for i: int in range(shard_count):
		var ang: float = base_rot + (TAU * float(i) / float(shard_count)) + float((i * 23) % 7) * 0.05
		var rad: Vector2 = Vector2.RIGHT.rotated(ang)
		var perp: Vector2 = Vector2(-rad.y, rad.x)
		var dist_scale: float = 0.86 + float((i * 19) % 7) * 0.05
		var pos: Vector2 = p + rad * lerpf(_radius * 0.65, _radius * 1.95 * dist_scale, ease_out)
		var sz: float = clampf(_radius * 0.22, 4.0, 8.5) * fade
		if sz > 1.2:
			var shard_pts: PackedVector2Array = PackedVector2Array([
				pos + rad * sz * 1.35,
				pos - rad * sz * 0.65 + perp * sz * 0.72,
				pos - rad * sz * 0.65 - perp * sz * 0.72,
			])
			var sc: Color = offwhite if (i % 3 == 0) else cyan
			draw_colored_polygon(shard_pts, Color(sc.r, sc.g, sc.b, fade * 0.92))

	# MONOLITH_OS neo-brutalist Hazard Amber / off-white halftone burst dots
	if _is_monolith_style:
		for m: int in range(4):
			var ma: float = base_rot + float(m) * (PI * 0.5) + 0.38
			var mdir: Vector2 = Vector2.RIGHT.rotated(ma)
			var mpos: Vector2 = p + mdir * lerpf(_radius * 0.72, _radius * 1.72, ease_out)
			var dot_col: Color = amber if (m % 2 == 0) else offwhite
			draw_circle(mpos, maxf(1.5, 3.2 * fade), Color(dot_col.r, dot_col.g, dot_col.b, fade * 0.94))


func _draw_dashed_circle(center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(4, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.58
		draw_arc(center, radius, a0, a1, 4, col, width, true)
