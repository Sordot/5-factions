class_name UnitWorldOverlay
extends RefCounted


static func should_draw_attack_range(unit: Unit) -> bool:
	if not unit.is_selected or not unit._can_attack() or unit.data == null:
		return false
	var mode: int = SettingsManager.attack_range_mode if SettingsManager != null else 1
	if mode == 2:
		return false
	if mode == 0:
		return true
	if unit.is_inside_tree():
		var sel: Node = unit.get_tree().get_first_node_in_group("selection_controller")
		if sel != null and sel.has_method("is_targeting_command_active"):
			return bool(sel.call("is_targeting_command_active"))
	return false


static func draw_unit_overlays(unit: Unit) -> void:
	var eff_atk_range: float = unit.get_effective_attack_range()
	var eff_min_range: float = unit.get_effective_min_attack_range()
	var eff_aoe: float = unit.get_effective_aoe_radius()
	# Selected unit attack-range & min-range tactical previews
	if unit.is_selected and unit.is_deployed() and eff_atk_range > 0.0 and unit.data != null:
		var dep_r: float = eff_atk_range + unit.data.collision_radius
		var dep_col: Color = Color(1.0, 0.68, 0.18, 0.42) if unit.team == Unit.Team.PLAYER else Color(1.0, 0.38, 0.28, 0.34)
		draw_dashed_ring(unit, Vector2.ZERO, dep_r, dep_col, 1.6, 48 if dep_r > 260.0 else 36)
		if eff_min_range > 0.0:
			var dep_min_r: float = eff_min_range + unit.data.collision_radius
			unit.draw_circle(Vector2.ZERO, dep_min_r, Color(1.0, 0.28, 0.24, 0.05))
			draw_dashed_ring(unit, Vector2.ZERO, dep_min_r, Color(1.0, 0.36, 0.28, 0.44), 1.4, 20)
	elif should_draw_attack_range(unit):
		var atk_r: float = eff_atk_range + unit.data.collision_radius
		var is_siege: bool = eff_min_range > 0.0 or eff_aoe > 0.0
		var range_col: Color = (Color(0.46, 1.0, 0.56, 0.34) if is_siege else Color(0.32, 0.94, 0.96, 0.24)) if unit.team == Unit.Team.PLAYER else Color(1.0, 0.38, 0.28, 0.26)
		draw_dashed_ring(unit, Vector2.ZERO, atk_r, range_col, 1.5 if is_siege else 1.2, 40 if atk_r > 220.0 else 28)
		if eff_min_range > 0.0:
			var min_r: float = eff_min_range + unit.data.collision_radius
			unit.draw_circle(Vector2.ZERO, min_r, Color(1.0, 0.28, 0.24, 0.05))
			draw_dashed_ring(unit, Vector2.ZERO, min_r, Color(1.0, 0.36, 0.28, 0.44), 1.4, 20)

	# Deploy / Anchor 4 corner stabilizer clamps when anchored
	if unit.is_deployed():
		var clamp_r: float = (unit.data.collision_radius if unit.data != null else 16.0) + 4.0
		var amber_pin: Color = Color(1.0, 0.624, 0.110, 0.96)
		var steel_pad: Color = Color(0.18, 0.24, 0.30, 0.95)
		var trim_col: Color = Color(0.62, 0.72, 0.80, 0.92)
		for ci: int in range(4):
			var c_ang: float = PI * 0.25 + float(ci) * (PI * 0.5)
			var c_dir: Vector2 = Vector2.RIGHT.rotated(c_ang)
			var perp: Vector2 = Vector2(-c_dir.y, c_dir.x)
			var p_in: Vector2 = c_dir * (clamp_r - 5.5)
			var p_out: Vector2 = c_dir * (clamp_r + 3.5)
			unit.draw_line(p_in, p_out, trim_col, 3.0, true)
			var pad_pts: PackedVector2Array = PackedVector2Array([
				p_out + perp * -3.5 - c_dir * 2.0,
				p_out + perp * 3.5 - c_dir * 2.0,
				p_out + perp * 4.2 + c_dir * 2.2,
				p_out + perp * -4.2 + c_dir * 2.2,
			])
			unit.draw_colored_polygon(pad_pts, steel_pad)
			unit.draw_polyline(pad_pts + PackedVector2Array([pad_pts[0]]), amber_pin, 1.2, true)
			unit.draw_circle(p_out, 1.6, amber_pin)

	# Shield-hit flash ripple ring
	if unit._shield_hit_flash_timer > 0.0:
		var sf: float = clampf(unit._shield_hit_flash_timer / Unit.SHIELD_HIT_FLASH_DURATION, 0.0, 1.0)
		var sr: float = (unit.data.collision_radius if unit.data != null else 16.0) + 3.5 + (1.0 - sf) * 4.5
		unit.draw_circle(Vector2.ZERO, sr * 0.92, Color(0.220, 0.741, 0.973, sf * 0.18))
		unit.draw_arc(Vector2.ZERO, sr, 0.0, TAU, 24, Color(0.220, 0.741, 0.973, sf * 0.92), 2.2, true)

	# PRISMA_DEI Radiant Mark golden amplification halo (+15% dmg taken) & Blinding Glare ring
	if unit.has_status_effect(&"radiant_mark"):
		var rm_r: float = (unit.data.collision_radius if unit.data != null else 16.0) + 6.5
		var gold_mark: Color = Color(0.98, 0.80, 0.14, 0.92)
		unit.draw_arc(Vector2.ZERO, rm_r, 0.0, TAU, 24, gold_mark, 1.8, true)
		for ri: int in range(4):
			var ra: float = float(ri) * (PI * 0.5)
			var rd: Vector2 = Vector2.RIGHT.rotated(ra)
			unit.draw_line(rd * (rm_r - 3.5), rd * (rm_r + 4.5), Color(1.0, 0.96, 0.72, 0.96), 1.8, true)
	if unit.has_status_effect(&"blinding_glare"):
		var bg_r: float = (unit.data.collision_radius if unit.data != null else 16.0) + 4.0
		unit.draw_arc(Vector2.ZERO, bg_r, 0.0, TAU, 20, Color(0.94, 0.36, 0.96, 0.72), 1.6, true)

	# Rail-Lance targeting lock-line telegraph during attack windup
	if unit.combat_component != null and unit.combat_component.is_in_windup() and unit.get_effective_weapon_tracer_style() == &"rail_lance":
		var lock_tgt: Node2D = unit.combat_component.get_windup_target()
		if lock_tgt != null and is_instance_valid(lock_tgt):
			var lock_p: float = unit.combat_component.get_windup_progress(unit)
			var muzzle_local: Vector2 = Vector2.RIGHT.rotated(unit.body_visual.rotation) * ((unit.data.collision_radius if unit.data != null else 16.0) + 2.0)
			var tgt_local: Vector2 = unit.to_local(lock_tgt.global_position)
			var lock_col: Color = Color(1.0, 0.624, 0.110, 0.35 + lock_p * 0.60)
			unit.draw_line(muzzle_local, tgt_local, lock_col, 1.0 + lock_p * 1.1, true)
			unit.draw_line(muzzle_local, tgt_local, Color(1.0, 0.96, 0.86, 0.25 + lock_p * 0.55), 0.7, true)
			unit.draw_arc(tgt_local, lerpf(16.0, 6.0, lock_p), 0.0, TAU, 16, lock_col, 1.3, true)

	# Deploy / Undeploy transition progress bar
	if unit.is_deploy_transitioning():
		var d_prog: float = unit.get_deploy_progress()
		var d_w: float = Unit.HEALTH_BAR_WIDTH
		var d_h: float = 4.0
		var base_bar_y: float = unit.health_bar_root.position.y if unit.health_bar_root != null else -((unit.data.collision_radius if unit.data != null else 16.0) + 14.0)
		var d_y: float = base_bar_y - (12.0 if unit.max_shield > 0.0 else 7.0)
		var d_pos: Vector2 = Vector2(-d_w * 0.5, d_y)
		unit.draw_rect(Rect2(d_pos - Vector2(1.0, 1.0), Vector2(d_w + 2.0, d_h + 2.0)), Color(0.04, 0.06, 0.10, 0.92), true)
		unit.draw_rect(Rect2(d_pos, Vector2(d_w * d_prog, d_h)), Color(1.0, 0.624, 0.110, 0.96), true)

	# Elevated ground shadow for Colossus Stride units
	if unit.data != null and unit.data.ignore_friendly_unit_collision:
		unit.draw_circle(Vector2(5.0, 11.0), 17.5, Color(0.02, 0.04, 0.06, 0.42))
		unit.draw_arc(Vector2(5.0, 11.0), 17.5, 0.0, TAU, 24, Color(0.28, 0.92, 1.0, 0.22) if unit.team == Unit.Team.PLAYER else Color(1.0, 0.36, 0.26, 0.22), 1.2, true)

	# Speed-dart motion trail for fast flanker units
	if unit.data != null and unit.data.has_tag(&"flanker") and unit._trail_points.size() >= 2:
		var trail_base: Color = Color(0.98, 0.80, 0.24, 1.0) if unit.team == Unit.Team.PLAYER else Color(1.0, 0.46, 0.24, 1.0)
		for i: int in range(1, unit._trail_points.size()):
			var t: float = float(i) / float(unit._trail_points.size())
			var p0: Vector2 = unit.to_local(unit._trail_points[i - 1])
			var p1: Vector2 = unit.to_local(unit._trail_points[i])
			unit.draw_line(p0, p1, Color(trail_base.r, trail_base.g, trail_base.b, t * 0.45), 1.4 + t * 2.2, true)

	var r: float = (unit.data.collision_radius + 6.0) if unit.data != null else 22.0
	if unit.has_status_effect(&"adrenal_surge"):
		# Pulsing emerald/gold rim + upward chevron pip
		var pulse: float = 0.5 + 0.5 * sin(unit._vfx_anim_time * 10.0)
		var rim_col: Color = Color(0.28, 1.0, 0.72, 0.88).lerp(Color(1.0, 0.88, 0.34, 0.96), pulse * 0.55)
		unit.draw_arc(Vector2.ZERO, r + pulse * 1.8, 0.0, TAU, 24, rim_col, 2.4, true)
		unit.draw_circle(Vector2.ZERO, r * 0.75, Color(0.24, 0.98, 0.78, 0.12 + pulse * 0.08))
		var chev_y: float = -(r + 6.0 + pulse * 2.5)
		var chev: PackedVector2Array = PackedVector2Array([
			Vector2(-4.5, chev_y + 3.0),
			Vector2(0.0, chev_y - 2.0),
			Vector2(4.5, chev_y + 3.0),
		])
		unit.draw_polyline(chev, Color(0.98, 0.94, 0.42, 0.95), 2.0, true)
	if unit.has_status_effect(&"static_slow"):
		# Flickering violet/cyan static disruption interference arcs
		var spin: float = unit._vfx_anim_time * 4.5
		var flicker: float = 0.65 + 0.35 * sin(unit._vfx_anim_time * 24.0)
		unit.draw_circle(Vector2.ZERO, r * 0.82, Color(0.56, 0.34, 1.0, 0.14))
		for k: int in range(3):
			var a0: float = spin + float(k) * (TAU / 3.0)
			var arc_col: Color = Color(0.72, 0.42, 1.0, 0.92 * flicker) if (k % 2 == 0) else Color(0.36, 0.92, 1.0, 0.86 * flicker)
			unit.draw_arc(Vector2.ZERO, r + 3.0, a0, a0 + 1.15, 10, arc_col, 2.3, true)
			var crack_dir: Vector2 = Vector2.RIGHT.rotated(a0 + 0.55)
			unit.draw_line(crack_dir * (r - 1.0), crack_dir * (r + 6.5), arc_col, 1.4, true)
	if unit.has_status_effect(&"grav_pulse"):
		# Heavy amber/violet gravity compression chevrons & ring
		var g_spin: float = -unit._vfx_anim_time * 3.2
		var g_pulse: float = 0.72 + 0.28 * sin(unit._vfx_anim_time * 12.0)
		unit.draw_circle(Vector2.ZERO, r * 0.86, Color(0.72, 0.36, 0.96, 0.14 * g_pulse))
		unit.draw_arc(Vector2.ZERO, r + 2.0, 0.0, TAU, 24, Color(1.0, 0.624, 0.110, 0.72 * g_pulse), 1.8, true)
		for gi: int in range(4):
			var ga: float = g_spin + float(gi) * (PI * 0.5)
			var g_dir: Vector2 = Vector2.RIGHT.rotated(ga)
			unit.draw_line(g_dir * (r + 6.0), g_dir * (r + 1.0), Color(0.84, 0.52, 1.0, 0.90 * g_pulse), 2.0, true)

	# Diegetic Defensive Stance anchor leash ring (when selected) + crisp shield/anchor pip
	if unit.stance == Unit.Stance.DEFENSIVE:
		var def_col: Color = Color(0.24, 0.96, 0.78, 0.92)
		if unit.is_selected:
			var local_anchor: Vector2 = unit.to_local(unit.defensive_anchor)
			draw_dashed_ring(unit, local_anchor, Unit.DEFENSIVE_LEASH_RADIUS, Color(0.24, 0.96, 0.78, 0.24), 1.3, 36)
			unit.draw_arc(local_anchor, 7.0, 0.0, TAU, 16, Color(0.24, 0.96, 0.78, 0.56), 1.3, true)
			unit.draw_circle(local_anchor, 2.5, Color(0.24, 0.96, 0.78, 0.75))
			if local_anchor.length_squared() > 144.0:
				unit.draw_line(Vector2.ZERO, local_anchor, Color(0.24, 0.96, 0.78, 0.22), 1.1, true)
		var pip_y: float = unit.health_bar_root.position.y + 1.0 if unit.health_bar_root != null else -(r + 8.0)
		var pip_x: float = (Unit.HEALTH_BAR_WIDTH * 0.5 + 8.0)
		var shield_pts: PackedVector2Array = PackedVector2Array([
			Vector2(pip_x - 3.6, pip_y - 3.8),
			Vector2(pip_x + 3.6, pip_y - 3.8),
			Vector2(pip_x + 3.6, pip_y + 0.4),
			Vector2(pip_x, pip_y + 4.4),
			Vector2(pip_x - 3.6, pip_y + 0.4),
		])
		unit.draw_colored_polygon(shield_pts, Color(0.06, 0.20, 0.22, 0.88))
		unit.draw_polyline(shield_pts + PackedVector2Array([shield_pts[0]]), def_col, 1.4, true)

	# Diegetic Veterancy rank chevron pips beside unit's health bar
	if unit.veterancy_rank > 0:
		var base_y: float = unit.health_bar_root.position.y + 1.0 if unit.health_bar_root != null else -(r + 8.0)
		var base_x: float = -(Unit.HEALTH_BAR_WIDTH * 0.5 + 8.0)
		var pip_col: Color = Color(1.0, 0.86, 0.28, 1.0) if unit.veterancy_rank >= 3 else Color(0.76, 0.96, 1.0, 0.96)
		var badge_h: float = 4.0 + float(unit.veterancy_rank) * 3.8
		unit.draw_rect(Rect2(base_x - 5.0, base_y - badge_h * 0.5 - 1.5, 10.0, badge_h + 3.0), Color(0.03, 0.06, 0.10, 0.80), true)
		for i: int in range(unit.veterancy_rank):
			var cy: float = base_y + (float(unit.veterancy_rank - 1) * 0.5 - float(i)) * 3.6
			var chev_pts: PackedVector2Array = PackedVector2Array([
				Vector2(base_x - 3.2, cy + 1.5),
				Vector2(base_x, cy - 1.7),
				Vector2(base_x + 3.2, cy + 1.5),
			])
			unit.draw_polyline(chev_pts, pip_col, 1.6, true)


static func draw_dashed_ring(canvas: CanvasItem, center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(8, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.54
		canvas.draw_arc(center, radius, a0, a1, 4, col, width, true)
