class_name BuildingInspectionBuilder
extends RefCounted


static func get_rally_summary(building: Building) -> String:
	if not building.has_rally():
		return "Default (RMB to Set)"
	if building.rally_target_unit != null and is_instance_valid(building.rally_target_unit) and not building.rally_target_unit.is_dead:
		var u_name: String = building.rally_target_unit.data.display_name if building.rally_target_unit.data != null else "Unit"
		return "Follow (%s)" % u_name
	var r_target: Node2D = building.get_rally_target()
	if r_target != null and is_instance_valid(r_target):
		if r_target is ResourceNode:
			return "Auto-Gather (%s)" % (r_target as ResourceNode).display_name
		if r_target is Building:
			return "Auto-Staff (%s)" % (r_target as Building).display_name
	return "Ground Point"


static func get_cluster_saturation(building: Building) -> Dictionary:
	if not building.is_inside_tree() or not building.is_constructed or building.is_destroyed:
		return {"assigned": 0, "capacity": 0, "has_nodes": false}
	var res_type: StringName = &""
	var search_radius: float = 0.0
	if building.is_core_hub or building.building_type_id == &"nexus_vat":
		res_type = &"biomass"
		search_radius = 520.0
	elif building.building_type_id == &"silica_condenser" or (building.is_resource_dropoff and building.accepts_resource(&"silica")):
		res_type = &"silica"
		search_radius = 420.0
	else:
		return {"assigned": 0, "capacity": 0, "has_nodes": false}

	var r_sq: float = search_radius * search_radius
	var total_assigned: int = 0
	var total_cap: int = 0
	var node_count: int = 0
	var tid: int = int(building.team)
	for node: Node in building.get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.is_depleted() or rn.is_vent or rn.resource_type != res_type:
			continue
		if building.global_position.distance_squared_to(rn.global_position) <= r_sq:
			total_assigned += rn.get_assigned_count(tid)
			total_cap += rn.get_effective_max_harvesters(tid)
			node_count += 1
	return {
		"assigned": total_assigned,
		"capacity": total_cap,
		"has_nodes": node_count > 0,
		"resource_type": res_type,
	}


static func build_inspection_data(building: Building) -> Dictionary:
	var accent: Color = Color(0.22, 0.88, 0.94, 1.0)
	var bdata: BuildingData = building.building_data
	if bdata == null and building.building_type_id != &"" and TeamManager != null and TeamManager.has_method("get_team_faction_data"):
		var fdata_b: FactionData = TeamManager.get_team_faction_data(int(building.team))
		if fdata_b != null:
			bdata = fdata_b.get_building_by_id(building.building_type_id)
	if bdata != null and bdata.hud_accent_color.a > 0.01:
		accent = bdata.hud_accent_color
	elif building.team == Unit.Team.ENEMY:
		accent = Color(1.0, 0.36, 0.26, 1.0)
	elif TeamManager != null and TeamManager.has_method("get_team_faction_data"):
		var fdata_c: FactionData = TeamManager.get_team_faction_data(int(building.team))
		if fdata_c != null:
			accent = fdata_c.hud_accent_color

	var affil: StringName = &"player" if building.team == Unit.Team.PLAYER else &"enemy"
	var stats: Array[Dictionary] = []

	var is_local_owned: bool = TeamManager.is_team_controlled_by_local_human(int(building.team)) if TeamManager != null else (building.team == Unit.Team.PLAYER)

	if not building.is_constructed:
		var pct: int = int(round(building.construction_progress * 100.0))
		stats.append({"label": "Construction", "value": "%d%% Complete" % pct})
		stats.append({"label": "Builder", "value": "Worker Active" if building._has_active_builder() else "Awaiting Worker"})
		stats.append({"label": "Build Time", "value": "%.1fs Total" % building.build_time})
		stats.append({"label": "Hull", "value": "%d / %d" % [int(round(building.current_hp)), int(round(building.max_hp))]})
		return {
			"title": building.display_name,
			"subtitle": "UNDER CONSTRUCTION",
			"affiliation": affil,
			"accent_color": accent,
			"ring_color": accent,
			"show_hp_bar": true,
			"hp_current": building.current_hp,
			"hp_max": building.max_hp,
			"show_shield_bar": false,
			"shield_current": 0.0,
			"shield_max": building.max_shield,
			"show_primary_bar": true,
			"primary_bar_label": "Building: %d%% — Under Construction" % pct,
			"primary_bar_value": building.construction_progress * 100.0,
			"primary_bar_max": 100.0,
			"primary_bar_color": Color(0.32, 0.96, 1.0, 1.0),
			"stats": stats,
			"is_commandable": is_local_owned,
			"readonly_label": "CONSTRUCTION IN PROGRESS",
		}

	var econ: EconomyManager = building._get_economy_manager()
	var show_primary: bool = false
	var primary_label: String = ""
	var primary_val: float = 0.0
	var primary_max: float = 1.0
	var primary_col: Color = accent
	var subtitle: String = "FRIENDLY STRUCTURE" if is_local_owned else "HOSTILE STRUCTURE"
	var has_commands: bool = is_local_owned

	if building.max_staff_slots > 0:
		subtitle = "COMPUTE FACILITY"
		var staffed: int = building.get_assigned_engineer_count()
		var yield_mult: float = GameConfig.get_yield_multiplier() if (GameConfig != null and GameConfig.has_method("get_yield_multiplier")) else 1.0
		var vent_surging: bool = building.claimed_vent != null and is_instance_valid(building.claimed_vent) and building.claimed_vent.is_surging()
		var surge_mult: float = building.claimed_vent.get_compute_surge_multiplier() if vent_surging else 1.0
		var rate: int = int(round(float(staffed * building.compute_per_engineer) * yield_mult * surge_mult))
		show_primary = true
		primary_label = "Engineers: %d / %d Staffed" % [staffed, building.max_staff_slots]
		primary_val = float(staffed)
		primary_max = float(maxi(1, building.max_staff_slots))
		primary_col = Color(0.28, 0.98, 1.0, 1.0) if vent_surging else Color(0.32, 0.88, 1.0, 1.0)
		var rate_str: String = ("+%d / %.1fs (2x SURGE)" % [rate, building.compute_tick_interval]) if (staffed > 0 and vent_surging) else ("+%d / %.1fs" % [rate, building.compute_tick_interval] if staffed > 0 else "0 / %.1fs (Assign Eng)" % building.compute_tick_interval)
		stats.append({"label": "Compute Rate", "value": rate_str})
		if vent_surging:
			stats.append({
				"label": "Thermal State",
				"value": "OVERPRESSURE SURGE (%dx) — %ds" % [int(round(surge_mult)), int(ceil(building.claimed_vent.surge_remaining))],
				"color": Color(0.28, 0.96, 1.0, 1.0),
			})
		else:
			stats.append({"label": "Vent Status", "value": "Active Thermal Vent"})
		stats.append({"label": "Staff Slots", "value": "%d / %d Engineers" % [staffed, building.max_staff_slots]})
		stats.append({"label": "Construction", "value": "Operational"})
	elif building.has_turret:
		subtitle = "STATIC DEFENSE TURRET" if is_local_owned else "HOSTILE DEFENSE TURRET"
		var eff_t_dmg: float = building.get_effective_turret_damage()
		var eff_t_rng: float = building.get_effective_turret_attack_range()
		var dmg_str: String = "%d (%.2fx Arm)" % [int(round(eff_t_dmg)), building.turret_bonus_vs_armored] if building.turret_bonus_vs_armored > 1.0 else "%d" % int(round(eff_t_dmg))
		stats.append({"label": "Damage", "value": dmg_str})
		stats.append({"label": "Range / Rate", "value": "%dpx / %.2fs" % [int(round(eff_t_rng)), building.turret_attack_interval]})
		if building.turret_splash_radius > 0.0:
			stats.append({"label": "Splash", "value": "%dpx Radius" % int(round(building.turret_splash_radius))})
		else:
			stats.append({"label": "Armor Class", "value": "Armored Structure"})
		var tgt_txt: String = "Locked Target" if (building.turret_component != null and building.turret_component.explicit_target != null and is_instance_valid(building.turret_component.explicit_target)) else ("Auto (RMB Focus)" if is_local_owned else "Automated")
		stats.append({"label": "Targeting", "value": tgt_txt})
	elif building.is_command_hub():
		var fac_hub: FactionData = TeamManager.get_team_faction_data(int(building.team)) if (TeamManager != null and TeamManager.has_method("get_team_faction_data")) else null
		var fac_code: String = fac_hub.short_code if (fac_hub != null and not fac_hub.short_code.is_empty()) else "FACTION"
		subtitle = ("%s PRIMARY HUB" % fac_code) if is_local_owned else "HOSTILE COMMAND HUB"
		var bw_str: String = "%d / %d" % [econ.get_bandwidth_used(building.team), econ.get_bandwidth_cap(building.team)] if econ != null else "--"
		var drop_res: Array[StringName] = building.building_data.get_dropoff_resources() if building.building_data != null else building.accepted_resources
		var drop_parts: PackedStringArray = PackedStringArray()
		for r_id: StringName in drop_res:
			drop_parts.append(String(r_id).capitalize())
		var drop_str: String = " / ".join(drop_parts) if not drop_parts.is_empty() else "Biomass"
		stats.append({"label": "Drop-Off", "value": drop_str})
		stats.append({"label": "Bandwidth", "value": "+%d Capacity" % building.bandwidth_provided})
		stats.append({"label": "Network", "value": bw_str})
		stats.append({"label": "Rally", "value": get_rally_summary(building)})
	elif building.building_type_id == &"cloning_vat":
		subtitle = "TIER-1 BATCH CLONING" if building.team == Unit.Team.PLAYER else "HOSTILE CLONING VAT"
		var mult: float = econ.get_batch_cost_multiplier(building.team, building.base_batch_cost_multiplier) if econ != null else building.base_batch_cost_multiplier
		var spd: int = int(round((econ.get_production_speed_multiplier(building.team) if econ != null else 1.0) * building.get_local_production_speed_multiplier() * 100.0))
		stats.append({"label": "Batch Output", "value": "x%d Units (%.2fx Cost)" % [building.batch_production_count, mult]})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd})
		stats.append({"label": "Rally", "value": get_rally_summary(building)})
		stats.append({"label": "Tech", "value": "Unlocks Fabricator"})
	elif building.building_type_id == &"calibration_foundry":
		subtitle = "TIER-1.5 MECH COUNTER" if building.team == Unit.Team.PLAYER else "HOSTILE FOUNDRY"
		var spd_f: int = int(round((econ.get_production_speed_multiplier(building.team) if econ != null else 1.0) * building.get_local_production_speed_multiplier() * 100.0))
		stats.append({"label": "Roster", "value": "Lance-Rig / Jammer"})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd_f})
		stats.append({"label": "Rally", "value": get_rally_summary(building)})
		stats.append({"label": "Role", "value": "Anti-Armor & Utility"})
	elif building.building_type_id == &"synthetics_fabricator":
		subtitle = "TIER-2 HEAVY SYNTHETICS" if building.team == Unit.Team.PLAYER else "HOSTILE FABRICATOR"
		var spd_s: int = int(round((econ.get_production_speed_multiplier(building.team) if econ != null else 1.0) * building.get_local_production_speed_multiplier() * 100.0))
		stats.append({"label": "Roster", "value": "Goliath / Arc / Mortar"})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd_s})
		stats.append({"label": "Rally", "value": get_rally_summary(building)})
		stats.append({"label": "Role", "value": "Heavy Compute Pivot"})
	elif building.building_type_id == &"assembly_bay" or building.building_type_id == &"ballistics_lab" or building.is_military_production_building():
		var tier_label: String = "TIER-%d PRODUCTION" % maxi(1, building.get_tech_tier())
		subtitle = tier_label if is_local_owned else "HOSTILE PRODUCTION"
		var spd_m: int = int(round((econ.get_production_speed_multiplier(building.team) if econ != null else 1.0) * building.get_local_production_speed_multiplier() * 100.0))
		var roster_names: PackedStringArray = PackedStringArray()
		for u_d: UnitData in building.trainable_unit_data:
			if u_d != null:
				roster_names.append(u_d.display_name)
		stats.append({"label": "Roster", "value": " / ".join(roster_names) if not roster_names.is_empty() else "Military Units"})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd_m})
		stats.append({"label": "Rally", "value": get_rally_summary(building)})
		if building.building_type_id == &"assembly_bay":
			stats.append({"label": "Tech", "value": "Unlocks Ballistics Lab"})
		elif building.building_type_id == &"ballistics_lab":
			stats.append({"label": "Tech", "value": "Unlocks Siege Gantry"})
		elif building.building_type_id == &"siege_gantry":
			stats.append({"label": "Role", "value": "Siege & Heavy Chassis"})
		else:
			stats.append({"label": "Role", "value": "Precision & Support"})
	elif building.building_type_id == &"silica_condenser" or building.building_type_id == &"silica_smelter" or (building.is_resource_dropoff and building.accepts_resource(&"silica") and not building.is_command_hub()):
		subtitle = "SILICA REFINING FACILITY"
		stats.append({"label": "Drop-Off", "value": "Silica"})
		stats.append({"label": "Harvesters", "value": "%d Active" % building._count_friendly_harvesters()})
		stats.append({"label": "Rally", "value": get_rally_summary(building)})
		stats.append({"label": "Throughput", "value": "25 Silica / Trip"})
	elif building.building_type_id == &"synapse_pylon" or building.building_type_id == &"capacitor_pylon" or building.bandwidth_provided > 0:
		subtitle = "INFRASTRUCTURE NODE"
		var bw_net: String = "%d / %d" % [econ.get_bandwidth_used(building.team), econ.get_bandwidth_cap(building.team)] if econ != null else "--"
		stats.append({"label": "Bandwidth", "value": "+%d Capacity" % building.bandwidth_provided})
		stats.append({"label": "Network", "value": bw_net})
		if building.shield_regen_aura_radius > 0.0 and building.shield_regen_delay_speedup > 0.0:
			stats.append({
				"label": "Shield Aura",
				"value": "+%d%% Recovery (%dpx)" % [int(round(building.shield_regen_delay_speedup * 100.0)), int(round(building.shield_regen_aura_radius))],
				"color": Color(0.220, 0.741, 0.973, 1.0),
			})
			stats.append({"label": "Role", "value": "Supply & Capacitor Relay"})
		else:
			stats.append({"label": "Status", "value": "Online"})
			stats.append({"label": "Role", "value": "Population Relay"})
	else:
		stats.append({"label": "Status", "value": "Operational"})

	if building.provides_power_grid and building.power_radius > 0.0:
		stats.append({
			"label": "Power Lattice",
			"value": "%dpx Radius" % int(round(building.power_radius)),
			"color": Color(0.98, 0.80, 0.14, 1.0),
		})
	if building.tether_emit_radius > 0.0 and building.tether_max_links > 0:
		stats.append({
			"label": "Optical Tether",
			"value": "x%d Links (+%d%% RoF, %dpx)" % [building.tether_max_links, int(round(building.tether_fire_rate_bonus * 100.0)), int(round(building.tether_emit_radius))],
			"color": Color(0.851, 0.275, 0.937, 1.0),
		})

	if building.requires_power_grid and not building.is_powered:
		subtitle = "UNPOWERED STRUCTURE"
		stats.append({
			"label": "Lattice",
			"value": "UNPOWERED — Build Power Spire",
			"color": Color(1.0, 0.42, 0.36, 1.0),
		})

	if building.is_overclocked():
		stats.append({
			"label": "Status",
			"value": "OVERCLOCKED %.1fx — %.1fs" % [building.overclock_speed_mult, building.overclock_remaining],
			"color": Color(1.0, 0.624, 0.110, 1.0),
		})

	if building.is_salvaging:
		var rem_s: float = maxf(0.0, Building.SALVAGE_DURATION - building.salvage_elapsed)
		show_primary = true
		primary_label = "SALVAGING (50%% REFUND) — %.1fs" % rem_s
		primary_val = building.salvage_elapsed
		primary_max = Building.SALVAGE_DURATION
		primary_col = Color(1.0, 0.72, 0.22, 1.0)

	return {
		"title": building.display_name,
		"subtitle": subtitle,
		"affiliation": affil,
		"accent_color": accent,
		"ring_color": accent,
		"show_hp_bar": true,
		"hp_current": building.current_hp,
		"hp_max": building.max_hp,
		"show_shield_bar": building.max_shield > 0.0,
		"shield_current": building.current_shield,
		"shield_max": building.max_shield,
		"show_primary_bar": show_primary,
		"primary_bar_label": primary_label,
		"primary_bar_value": primary_val,
		"primary_bar_max": primary_max,
		"primary_bar_color": primary_col,
		"stats": stats,
		"is_commandable": has_commands,
		"readonly_label": "PASSIVE INFRASTRUCTURE" if building.team == Unit.Team.PLAYER else "READ-ONLY TELEMETRY",
	}
