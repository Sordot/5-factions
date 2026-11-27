class_name BuildingWorldOverlay
extends RefCounted


static func draw_dashed_ring(canvas: CanvasItem, center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(8, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.54
		canvas.draw_arc(center, radius, a0, a1, 4, col, width, true)


static func draw_building_overlays(building: Building) -> void:
	if building.is_selected and building.is_constructed and not building.is_destroyed and building.provides_power_grid and building.power_radius > 0.0:
		var lat_r: float = building.power_radius
		var gold_col: Color = Color(0.98, 0.80, 0.14, 0.56)
		var mag_col: Color = Color(0.94, 0.22, 0.68, 0.62)
		building.draw_circle(Vector2.ZERO, lat_r, Color(0.98, 0.80, 0.14, 0.04))
		draw_dashed_ring(building, Vector2.ZERO, lat_r, gold_col, 1.8, 44)
		for li: int in range(12):
			var la: float = float(li) * (TAU / 12.0)
			var ldir: Vector2 = Vector2.RIGHT.rotated(la)
			var lp: Vector2 = ldir * lat_r
			if li % 3 == 0:
				var dia_p: PackedVector2Array = PackedVector2Array([
					lp + ldir * 4.5,
					lp + ldir.orthogonal() * 3.5,
					lp - ldir * 4.5,
					lp - ldir.orthogonal() * 3.5,
				])
				building.draw_colored_polygon(dia_p, mag_col)
			else:
				building.draw_line(ldir * (lat_r - 5.0), ldir * (lat_r + 2.0), gold_col, 1.4, true)

	if building.is_constructed and not building.is_destroyed and building.requires_power_grid and not building.is_powered:
		var up_pulse: float = 0.55 + 0.45 * sin(building._unpowered_pulse_time * 5.2)
		var warn_amber: Color = Color(0.98, 0.72, 0.18, 0.75 + up_pulse * 0.23)
		var warn_mag: Color = Color(0.94, 0.22, 0.58, 0.72 + up_pulse * 0.25)
		var badge_y: float = (building.health_bar_root.position.y if building.health_bar_root != null else -(building.footprint_radius + 14.0)) - (18.0 if building.max_shield > 0.0 else 12.0)
		var dia_c: Vector2 = Vector2(0.0, badge_y - 10.0)
		var dia_pts: PackedVector2Array = PackedVector2Array([
			dia_c + Vector2(0.0, -7.5),
			dia_c + Vector2(7.5, 0.0),
			dia_c + Vector2(0.0, 7.5),
			dia_c + Vector2(-7.5, 0.0),
		])
		building.draw_colored_polygon(dia_pts, Color(0.05, 0.06, 0.10, 0.88))
		building.draw_polyline(dia_pts + PackedVector2Array([dia_pts[0]]), warn_amber, 1.7, true)
		building.draw_line(dia_c + Vector2(-5.5, 5.5), dia_c + Vector2(5.5, -5.5), warn_mag, 2.0, true)
		var font_up: Font = ThemeDB.fallback_font
		if font_up != null:
			var up_lbl: String = "UNPOWERED"
			var up_sz: Vector2 = font_up.get_string_size(up_lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
			var up_pos: Vector2 = Vector2(-up_sz.x * 0.5, badge_y + 2.0)
			building.draw_rect(Rect2(up_pos + Vector2(-4.0, -up_sz.y), up_sz + Vector2(8.0, 4.0)), Color(0.05, 0.06, 0.10, 0.84), true)
			building.draw_string(font_up, up_pos, up_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, warn_amber)

	if building.is_selected and building.is_constructed and not building.is_destroyed and building.shield_regen_aura_radius > 0.0:
		var aura_r: float = building.shield_regen_aura_radius
		var aura_col: Color = Color(0.220, 0.741, 0.973, 0.42)
		var amber_dot: Color = Color(1.0, 0.624, 0.110, 0.50)
		building.draw_circle(Vector2.ZERO, aura_r, Color(0.220, 0.741, 0.973, 0.035))
		draw_dashed_ring(building, Vector2.ZERO, aura_r, aura_col, 1.6, 36)
		# Subtle halftone tick dots along the aura perimeter
		for hi: int in range(18):
			var ha: float = float(hi) * (TAU / 18.0)
			building.draw_circle(Vector2.RIGHT.rotated(ha) * (aura_r - 5.0), 1.8, amber_dot if (hi % 3 == 0) else aura_col)

	if building._should_draw_turret_range_ring():
		var atk_r: float = building.get_effective_turret_attack_range() + building.footprint_radius
		var tc: Color = TeamManager.get_team_color(int(building.team)) if TeamManager != null else (Color(0.28, 0.94, 0.96, 1.0) if building.team == Unit.Team.PLAYER else Color(1.0, 0.38, 0.28, 1.0))
		var ring_col: Color = Color(tc.r, tc.g, tc.b, 0.34)
		building.draw_circle(Vector2.ZERO, atk_r, Color(tc.r, tc.g, tc.b, 0.03))
		draw_dashed_ring(building, Vector2.ZERO, atk_r, ring_col, 1.6, 44 if atk_r > 240.0 else 32)
		if building.turret_min_range > 0.0:
			var min_r: float = building.turret_min_range + building.footprint_radius
			building.draw_circle(Vector2.ZERO, min_r, Color(1.0, 0.28, 0.24, 0.05))
			draw_dashed_ring(building, Vector2.ZERO, min_r, Color(1.0, 0.36, 0.28, 0.44), 1.4, 20)

	if building.is_selected and building.turret_component != null and building.turret_component.explicit_target != null and is_instance_valid(building.turret_component.explicit_target):
		var tgt_local: Vector2 = building.to_local(building.turret_component.explicit_target.global_position)
		building.draw_line(Vector2.ZERO, tgt_local, Color(1.0, 0.34, 0.32, 0.55), 1.4, true)
		building.draw_arc(tgt_local, 14.0, 0.0, TAU, 18, Color(1.0, 0.38, 0.32, 0.85), 1.6, true)

	if building.is_salvaging and building.is_constructed and not building.is_destroyed:
		var prog: float = clampf(building.salvage_elapsed / Building.SALVAGE_DURATION, 0.0, 1.0)
		var bar_w: float = 72.0
		var bar_h: float = 6.0
		var bar_pos: Vector2 = Vector2(-bar_w * 0.5, building.footprint_radius + 10.0)
		var pulse: float = 0.72 + 0.28 * sin(building.salvage_elapsed * 9.0)
		building.draw_rect(Rect2(bar_pos - Vector2(1.0, 1.0), Vector2(bar_w + 2.0, bar_h + 2.0)), Color(0.04, 0.06, 0.09, 0.92), true)
		building.draw_rect(Rect2(bar_pos, Vector2(bar_w * prog, bar_h)), Color(1.0, 0.70, 0.20, pulse), true)
		building.draw_arc(Vector2.ZERO, building.footprint_radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, Color(1.0, 0.72, 0.22, pulse), 2.4, true)

	# Shield-hit ripple ring
	if building._shield_hit_flash_timer > 0.0 and not building.is_destroyed:
		var sf: float = clampf(building._shield_hit_flash_timer / Building.SHIELD_HIT_FLASH_DURATION, 0.0, 1.0)
		var sr: float = building.footprint_radius + 5.0 + (1.0 - sf) * 6.0
		building.draw_circle(Vector2.ZERO, sr * 0.95, Color(0.220, 0.741, 0.973, sf * 0.14))
		building.draw_arc(Vector2.ZERO, sr, 0.0, TAU, 36, Color(0.220, 0.741, 0.973, sf * 0.92), 2.5, true)

	# World-space Core Overclock VFX: pulsing Hazard Amber perimeter frame/chevrons + compact progress bar & 2x tag
	if building.is_overclocked() and building.is_constructed and not building.is_destroyed:
		var oc_pulse: float = 0.5 + 0.5 * sin(building._overclock_anim_time * 7.5)
		var amber: Color = Color(1.0, 0.624, 0.110, 0.72 + oc_pulse * 0.26) # #FF9F1C
		var amber_soft: Color = Color(1.0, 0.624, 0.110, 0.10 + oc_pulse * 0.08)
		var frame_r: float = building.footprint_radius + 7.5 + oc_pulse * 2.0
		building.draw_arc(Vector2.ZERO, frame_r, 0.0, TAU, 36, amber, 2.2, true)
		building.draw_circle(Vector2.ZERO, frame_r * 0.94, amber_soft)
		# 4 pulsing corner chevrons
		for ci: int in range(4):
			var c_ang: float = PI * 0.25 + float(ci) * (PI * 0.5)
			var c_dir: Vector2 = Vector2.RIGHT.rotated(c_ang)
			var perp: Vector2 = Vector2(-c_dir.y, c_dir.x)
			var tip: Vector2 = c_dir * (frame_r + 7.0 + oc_pulse * 2.5)
			var wing_a: Vector2 = tip - c_dir * 6.0 + perp * 6.0
			var wing_b: Vector2 = tip - c_dir * 6.0 - perp * 6.0
			building.draw_polyline(PackedVector2Array([wing_a, tip, wing_b]), amber, 2.2, true)
		# Compact amber timer bar + 2x tag cleanly above building bars
		var oc_ratio: float = clampf(building.overclock_remaining / maxf(0.1, building.overclock_duration_total), 0.0, 1.0)
		var oc_bar_w: float = 54.0
		var oc_bar_h: float = 4.0
		var base_top_y: float = (building.health_bar_root.position.y if building.health_bar_root != null else -(building.footprint_radius + 14.0)) - (15.0 if building.max_shield > 0.0 else 10.0)
		var oc_bar_pos: Vector2 = Vector2(-oc_bar_w * 0.5, base_top_y)
		building.draw_rect(Rect2(oc_bar_pos - Vector2(1.0, 1.0), Vector2(oc_bar_w + 2.0, oc_bar_h + 2.0)), Color(0.04, 0.06, 0.10, 0.92), true)
		building.draw_rect(Rect2(oc_bar_pos, Vector2(oc_bar_w * oc_ratio, oc_bar_h)), amber, true)
		var mult_txt: String = ("%dx" % int(round(building.overclock_speed_mult))) if is_equal_approx(building.overclock_speed_mult, round(building.overclock_speed_mult)) else ("%.1fx" % building.overclock_speed_mult)
		var font: Font = ThemeDB.fallback_font
		var txt_sz: Vector2 = font.get_string_size(mult_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		var tag_pos: Vector2 = Vector2(-txt_sz.x * 0.5, base_top_y - 3.0)
		building.draw_string(font, tag_pos, mult_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.78, 0.30, 0.98))

	if not building.is_selected or not building.has_rally() or building._has_rally_overlay():
		return
	var target_world: Vector2 = building.get_rally_world_position()
	var target_local: Vector2 = building.to_local(target_world)
	var is_smart: bool = (building.get_rally_target() != null)
	var rally_col: Color = Color(0.28, 1.0, 0.62, 0.88) if is_smart else Color(0.24, 0.92, 0.96, 0.85)
	building.draw_line(Vector2.ZERO, target_local, rally_col, 1.8, true)
	building.draw_arc(target_local, 10.0, 0.0, TAU, 20, rally_col, 2.0, true)
	# Crisp rally flag triangle
	var flag_pts: PackedVector2Array = PackedVector2Array([
		target_local + Vector2(0.0, -2.0),
		target_local + Vector2(0.0, -22.0),
		target_local + Vector2(14.0, -15.0),
		target_local + Vector2(0.0, -9.0),
	])
	building.draw_colored_polygon(flag_pts, rally_col)
