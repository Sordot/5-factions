class_name UnitInspectionBuilder
extends RefCounted


static func get_armor_class_label(unit: Unit) -> String:
	if unit.data == null:
		return "Light"
	if unit.data.is_heavy_unit() and unit.data.has_tag(&"synthetic"):
		return "Heavy Synthetic"
	if unit.data.is_armored:
		return "Armored"
	return "Light"


static func get_command_state_label(unit: Unit) -> String:
	match unit.command_state:
		Unit.CommandState.IDLE:
			return "Defending Post" if unit.stance == Unit.Stance.DEFENSIVE else "Idle"
		Unit.CommandState.MOVING:
			return "Moving"
		Unit.CommandState.ATTACK_MOVING:
			return "Attack-Moving"
		Unit.CommandState.ATTACKING_TARGET:
			return "Engaging"
		Unit.CommandState.HOLD_POSITION:
			return "Holding"
		Unit.CommandState.CASTING_ABILITY:
			return "Casting"
		Unit.CommandState.GATHERING:
			if unit.gather_component != null:
				match unit.gather_component.state:
					GatherComponent.GatherState.GATHER_MOVING_TO_NODE:
						return "To Resource"
					GatherComponent.GatherState.GATHERING:
						return "Harvesting"
					GatherComponent.GatherState.GATHER_RETURNING_TO_BASE:
						return "Returning Cargo"
			return "Gathering"
		Unit.CommandState.CONSTRUCTING:
			return "Constructing"
		Unit.CommandState.STAFFING_BUILDING:
			return "Entering Node"
		Unit.CommandState.PATROLLING:
			return "Patrolling"
		Unit.CommandState.REPAIRING:
			return "Repairing"
		Unit.CommandState.SALVAGING:
			return "Extracting Salvage"
	return "Active"


static func build_inspection_data(unit: Unit) -> Dictionary:
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_local_owned_unit: bool = TeamManager.is_team_controlled_by_local_human(int(unit.team)) if TeamManager != null else (unit.team == Unit.Team.PLAYER)
	var is_allied_ai: bool = (not is_local_owned_unit) and viewer_team >= 0 and TeamManager != null and TeamManager.are_allies(viewer_team, int(unit.team))
	var is_enemy: bool = (not is_local_owned_unit) and (not is_allied_ai)
	var accent: Color = TeamManager.get_team_color(int(unit.team)) if TeamManager != null else (Color(1.0, 0.36, 0.26, 1.0) if is_enemy else Color(0.24, 0.92, 0.88, 1.0))
	var class_tag: String = get_armor_class_label(unit).to_upper()
	var subtitle: String = ("HOSTILE %s" % class_tag) if is_enemy else (("ALLIED %s" % class_tag) if is_allied_ai else ("FRIENDLY %s" % class_tag))

	if not is_enemy and unit.data != null:
		if not unit.data.role_tags_display.is_empty():
			subtitle = "%s  •  %s" % [class_tag, unit.data.role_tags_display.to_upper()]
			if unit.data.has_tag(&"flanker") or unit.data.has_tag(&"scout"):
				accent = Color(0.98, 0.78, 0.24, 1.0)
			elif unit.data.has_tag(&"anti_armor"):
				accent = Color(0.98, 0.68, 0.28, 1.0)
			elif unit.data.has_tag(&"disruptor"):
				accent = Color(0.76, 0.56, 1.0, 1.0)
			elif unit.data.has_tag(&"support") or unit.data.has_tag(&"artillery"):
				accent = Color(0.38, 1.0, 0.60, 1.0)
			elif unit.data.is_heavy_unit():
				accent = Color(0.40, 0.94, 1.0, 1.0)
			elif unit.data.can_staff_compute:
				accent = Color(0.32, 0.82, 1.0, 1.0)
			elif unit.data.can_gather:
				accent = Color(0.96, 0.68, 0.22, 1.0) if unit.data.allowed_resource == &"silica" else Color(0.28, 0.94, 0.56, 1.0)
			else:
				accent = Color(0.24, 0.94, 0.82, 1.0)
		elif unit.data.can_staff_compute:
			accent = Color(0.32, 0.82, 1.0, 1.0)
			subtitle = "%s  •  COMPUTE SPECIALIST" % class_tag
		elif unit.data.can_gather:
			accent = Color(0.28, 0.94, 0.56, 1.0)
			subtitle = "%s  •  UTILITY WORKER" % class_tag

	var max_hp_val: float = unit.get_max_hp()
	var stats: Array[Dictionary] = []
	var show_primary: bool = false
	var primary_label: String = ""
	var primary_val: float = 0.0
	var primary_max: float = 1.0

	if unit.data != null and unit.data.can_gather:
		var res_label: String = String(unit.data.allowed_resource).capitalize() if unit.data.allowed_resource != &"" else "Resource"
		var carried: int = unit.get_carried_amount()
		show_primary = true
		primary_label = "Cargo: %d / %d %s" % [carried, unit.data.carry_capacity, res_label]
		primary_val = float(carried)
		primary_max = float(maxi(1, unit.data.carry_capacity))
		stats.append({"label": "Cargo", "value": "%d / %d %s" % [carried, unit.data.carry_capacity, res_label]})
		stats.append({"label": "Harvest", "value": "%.1fs Cycle" % unit.data.gather_duration})
		stats.append({"label": "Speed", "value": "%d px/s" % int(round(unit.get_effective_move_speed()))})
		stats.append({"label": "State", "value": get_command_state_label(unit)})
	elif unit.data != null and unit.data.can_staff_compute:
		stats.append({"label": "Role", "value": "Compute Staff"})
		stats.append({"label": "Output", "value": "+5 Compute / 3.0s"})
		stats.append({"label": "Speed", "value": "%d px/s" % int(round(unit.get_effective_move_speed()))})
		stats.append({"label": "Bandwidth", "value": "%d BW" % unit.data.bandwidth_cost})
	elif unit.data != null:
		var eff_dmg: float = unit.get_effective_attack_damage()
		var eff_rng: float = unit.get_effective_attack_range()
		var eff_min_rng: float = unit.get_effective_min_attack_range()
		var eff_aoe: float = unit.get_effective_aoe_radius()
		var dmg_str: String = "%d" % int(round(eff_dmg))
		if unit.data.bonus_vs_armored > 0.0:
			dmg_str += " (+%d vs Armored)" % int(round(unit.data.bonus_vs_armored))
		elif eff_aoe > 0.0:
			dmg_str += " (AoE %dpx)" % int(round(eff_aoe))
		elif unit.data.line_pierce_width > 0.0:
			dmg_str += " (Line Pierce)"
		stats.append({"label": "Damage", "value": dmg_str})

		var range_str: String = "%d px" % int(round(eff_rng))
		if eff_min_rng > 0.0:
			range_str = "%d–%d px (Min)" % [int(round(eff_min_rng)), int(round(eff_rng))]
		stats.append({"label": "Range", "value": range_str})

		var spd_str: String = "ANCHORED" if unit.is_deployed() else ("DEPLOYING..." if unit.deploy_state == Unit.DeployState.DEPLOYING else ("UNDEPLOYING..." if unit.deploy_state == Unit.DeployState.UNDEPLOYING else "%d px/s" % int(round(unit.get_effective_move_speed()))))
		if not unit.is_movement_locked_by_deploy():
			if unit.has_status_effect(&"adrenal_surge"):
				spd_str += " [SURGE]"
			elif unit.has_status_effect(&"static_slow"):
				spd_str += " [SLOW]"
		var spd_entry: Dictionary = {"label": "Speed", "value": spd_str}
		if unit.is_movement_locked_by_deploy():
			spd_entry["color"] = Color(1.0, 0.624, 0.110, 1.0)
		stats.append(spd_entry)

		var dr: float = unit.get_effective_damage_reduction()
		if unit.data.heal_aura_rate > 0.0:
			stats.append({"label": "Aura", "value": "+%.0f HP/s (%dpx)" % [unit.data.heal_aura_rate, int(round(unit.data.heal_aura_radius))]})
		elif unit.data.ignore_friendly_unit_collision:
			stats.append({"label": "Class", "value": "%s • Stride" % get_armor_class_label(unit)})
		elif dr > 0.001:
			stats.append({"label": "Armor", "value": "%s (-%d%% Dmg)" % [get_armor_class_label(unit), int(round(dr * 100.0))]})
		elif eff_dmg > 0.0 and unit.get_effective_attack_cooldown() > 0.0:
			stats.append({"label": "Class", "value": "%s • %.1f/s" % [get_armor_class_label(unit), 1.0 / unit.get_effective_attack_cooldown()]})
		else:
			stats.append({"label": "Class", "value": get_armor_class_label(unit)})

		if eff_dmg > 0.0 or unit.kill_count > 0:
			if unit.veterancy_rank > 0:
				var rank_col: Color = Color(1.0, 0.86, 0.28, 1.0) if unit.veterancy_rank >= 3 else Color(0.46, 0.98, 1.0, 1.0)
				stats.append({
					"label": "Rank",
					"value": "%s (%d Kills)" % [unit.get_veterancy_rank_name().to_upper(), unit.kill_count],
					"color": rank_col,
				})
			else:
				stats.append({"label": "Kills", "value": "%d" % unit.kill_count})

		var tether_stacks: int = unit.get_optical_tether_stacks()
		if tether_stacks > 0:
			stats.append({
				"label": "Lattice Link",
				"value": "x%d Active" % tether_stacks,
				"color": Color(0.98, 0.80, 0.14, 1.0),
			})
		if unit.data.tether_emit_radius > 0.0 and unit.data.tether_max_links > 0:
			stats.append({
				"label": "Tether Anchor",
				"value": "x%d Links (%dpx)" % [unit.data.tether_max_links, int(round(unit.data.tether_emit_radius))],
				"color": Color(0.851, 0.275, 0.937, 1.0),
			})
		if unit.data.is_continuous_beam and unit.combat_component != null:
			var ramp_pct: int = int(round(unit.combat_component.get_beam_ramp_ratio(unit) * 100.0))
			if ramp_pct > 0:
				stats.append({
					"label": "Beam Charge",
					"value": "%d%% (%.1fx)" % [ramp_pct, lerpf(1.0, maxf(1.0, unit.data.beam_ramp_max_multiplier), float(ramp_pct) * 0.01)],
					"color": Color(0.94, 0.22, 0.68, 1.0),
				})

	var is_local_controlled: bool = TeamManager.is_team_controlled_by_local_human(int(unit.team)) if TeamManager != null else (not is_enemy)
	return {
		"title": unit.data.display_name if unit.data != null else unit.name,
		"subtitle": subtitle,
		"affiliation": &"enemy" if is_enemy else &"player",
		"accent_color": accent,
		"ring_color": accent,
		"show_hp_bar": true,
		"hp_current": unit.current_hp,
		"hp_max": max_hp_val,
		"show_shield_bar": unit.max_shield > 0.0,
		"shield_current": unit.current_shield,
		"shield_max": unit.max_shield,
		"show_primary_bar": show_primary,
		"primary_bar_label": primary_label,
		"primary_bar_value": primary_val,
		"primary_bar_max": primary_max,
		"primary_bar_color": accent,
		"stats": stats,
		"is_commandable": is_local_controlled,
		"readonly_label": "SPECTATOR TELEMETRY" if (TeamManager != null and TeamManager.is_spectator_mode()) else "HOSTILE UNIT  —  READ-ONLY TELEMETRY",
	}
