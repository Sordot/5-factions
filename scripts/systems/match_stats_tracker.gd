class_name MatchStatsTracker
extends RefCounted

const MAX_HEATMAP_EVENTS: int = 800

var team_stats: Dictionary = {}
var timeline_samples: Array[Dictionary] = []
var combat_heatmap_events: Array[Dictionary] = []
var heatmap_damage_throttle: Dictionary = {}
var alliance_uplink_times: Dictionary = {}
var uplink_milestones_announced: Dictionary = {}
var alliance_uplink_rep_team: Dictionary = {}

var player_uplink_time: float = 0.0
var enemy_uplink_time: float = 0.0
var player_units_trained: int = 0
var enemy_units_trained: int = 0
var player_units_lost: int = 0
var enemy_units_destroyed: int = 0
var player_buildings_built: int = 0
var enemy_buildings_built: int = 0
var player_buildings_lost: int = 0
var enemy_structures_destroyed: int = 0
var player_peak_bandwidth: int = 0
var enemy_peak_bandwidth: int = 0


func init_teams(active_teams: Array[int]) -> void:
	team_stats.clear()
	timeline_samples.clear()
	combat_heatmap_events.clear()
	heatmap_damage_throttle.clear()
	alliance_uplink_times.clear()
	uplink_milestones_announced.clear()
	alliance_uplink_rep_team.clear()
	for tid: int in active_teams:
		ensure_bucket(tid)


func ensure_bucket(tid: int) -> Dictionary:
	if not team_stats.has(tid):
		team_stats[tid] = {
			"units_trained": 0,
			"units_lost": 0,
			"enemies_destroyed": 0,
			"buildings_built": 0,
			"buildings_lost": 0,
			"peak_bandwidth": 0,
			"uplink_seconds": 0.0,
			"supply_blocked_seconds": 0.0,
			"resource_float_sum": 0.0,
			"resource_float_samples": 0,
			"resources_lost_value": 0,
			"resources_destroyed_value": 0,
		}
	return team_stats[tid] as Dictionary


func get_team_supply_blocked_seconds(tid: int) -> float:
	if not team_stats.has(tid):
		return 0.0
	return float((team_stats[tid] as Dictionary).get("supply_blocked_seconds", 0.0))


func on_bandwidth_changed(tid: int, used: int) -> void:
	var bucket: Dictionary = ensure_bucket(tid)
	bucket["peak_bandwidth"] = maxi(int(bucket["peak_bandwidth"]), used)
	if tid == int(Unit.Team.PLAYER):
		player_peak_bandwidth = maxi(player_peak_bandwidth, used)
	elif tid == int(Unit.Team.ENEMY):
		enemy_peak_bandwidth = maxi(enemy_peak_bandwidth, used)


func on_unit_produced(unit: Unit) -> void:
	if unit == null:
		return
	var tid: int = int(unit.team)
	var bucket: Dictionary = ensure_bucket(tid)
	bucket["units_trained"] = int(bucket["units_trained"]) + 1
	if tid == int(Unit.Team.PLAYER):
		player_units_trained += 1
	elif tid == int(Unit.Team.ENEMY):
		enemy_units_trained += 1


func on_unit_died(mm: MatchManager, unit: Unit) -> void:
	if mm == null or unit == null:
		return
	var tid: int = int(unit.team)
	var bucket: Dictionary = ensure_bucket(tid)
	bucket["units_lost"] = int(bucket["units_lost"]) + 1
	var u_val: int = 0
	if unit.data != null:
		u_val = maxi(0, unit.data.biomass_cost) + maxi(0, unit.data.silica_cost) + maxi(0, unit.data.compute_cost)
	bucket["resources_lost_value"] = int(bucket["resources_lost_value"]) + u_val
	var is_heavy_u: bool = unit.data != null and unit.data.is_heavy_unit()
	push_heatmap_event(unit.global_position, 2.4 if is_heavy_u else 1.0, tid, &"heavy_unit_death" if is_heavy_u else &"unit_death")

	# Credit kill count & trade value to killer team (or opponent in 2-team matches)
	var active_teams: Array[int] = [0, 1]
	if TeamManager != null:
		active_teams = TeamManager.get_active_teams()
	var killer_tid: int = unit.last_attacker_team
	if killer_tid < 0 and active_teams.size() == 2:
		killer_tid = active_teams[1] if tid == active_teams[0] else active_teams[0]
	if killer_tid >= 0 and killer_tid != tid:
		var killer_b: Dictionary = ensure_bucket(killer_tid)
		killer_b["enemies_destroyed"] = int(killer_b["enemies_destroyed"]) + 1
		killer_b["resources_destroyed_value"] = int(killer_b["resources_destroyed_value"]) + u_val
	if tid == int(Unit.Team.PLAYER):
		player_units_lost += 1
	elif tid == int(Unit.Team.ENEMY):
		enemy_units_destroyed += 1

	# Log heavy unit losses in Tactical Event Feed
	if unit.data != null and unit.data.is_heavy_unit():
		var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		var is_ally: bool = viewer >= 0 and (TeamManager.are_allies(viewer, tid) if TeamManager != null else (tid == viewer))
		if is_ally or viewer < 0 or unit.visible:
			var tag: String = TeamManager.get_team_short_label(tid, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1))
			var u_name: String = unit.data.display_name
			var col: Color = Color(1.0, 0.34, 0.28, 1.0) if is_ally else Color(1.0, 0.72, 0.28, 1.0)
			mm.emit_tactical_event(&"combat", "%s %s Destroyed" % [tag, u_name], unit.global_position, col)


func on_building_completed(mm: MatchManager, building: Building) -> void:
	if mm == null or building == null:
		return
	var tid: int = int(building.team)
	var bucket: Dictionary = ensure_bucket(tid)
	bucket["buildings_built"] = int(bucket["buildings_built"]) + 1
	if tid == int(Unit.Team.PLAYER):
		player_buildings_built += 1
	elif tid == int(Unit.Team.ENEMY):
		enemy_buildings_built += 1

	var is_notable_tech: bool = building.get_tech_tier() >= 2 or building.max_staff_slots > 0 or (building.is_military_production_building() and building.batch_production_count <= 1)
	if is_notable_tech:
		var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		var is_visible_to_feed: bool = viewer < 0 or (TeamManager.are_allies(viewer, tid) if TeamManager != null else (tid == viewer))
		if is_visible_to_feed:
			var tag: String = TeamManager.get_team_short_label(tid, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1))
			mm.emit_tactical_event(&"economy", "%s %s Online" % [tag, building.display_name], building.global_position, Color(0.28, 0.96, 0.92, 1.0))


func on_building_destroyed(mm: MatchManager, building: Building) -> void:
	if mm == null or building == null:
		return
	var tid: int = int(building.team)
	var bucket: Dictionary = ensure_bucket(tid)
	bucket["buildings_lost"] = int(bucket["buildings_lost"]) + 1
	var b_val: int = 150
	if building.building_data != null:
		b_val = maxi(0, building.building_data.biomass_cost) + maxi(0, building.building_data.silica_cost) + maxi(0, building.building_data.compute_cost)
	bucket["resources_lost_value"] = int(bucket["resources_lost_value"]) + b_val
	var active_teams_b: Array[int] = [0, 1]
	if TeamManager != null:
		active_teams_b = TeamManager.get_active_teams()
	var b_killer: int = building.last_attacker_team
	if b_killer < 0 and active_teams_b.size() == 2:
		b_killer = active_teams_b[1] if tid == active_teams_b[0] else active_teams_b[0]
	if b_killer >= 0 and b_killer != tid:
		var kb: Dictionary = ensure_bucket(b_killer)
		kb["resources_destroyed_value"] = int(kb["resources_destroyed_value"]) + b_val
	var is_hub_b: bool = building.is_command_hub()
	push_heatmap_event(building.global_position, 4.5 if is_hub_b else 3.0, tid, &"hub_destroyed" if is_hub_b else &"building_destroyed")
	if tid == int(Unit.Team.ENEMY):
		enemy_structures_destroyed += 1
	elif tid == int(Unit.Team.PLAYER):
		player_buildings_lost += 1

	var is_major_bldg: bool = building.is_command_hub() or building.is_military_production_building() or building.max_staff_slots > 0 or building.has_turret
	if is_major_bldg:
		var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		var is_ally: bool = viewer >= 0 and (TeamManager.are_allies(viewer, tid) if TeamManager != null else (tid == viewer))
		if is_ally or viewer < 0 or building.visible or building.is_command_hub():
			var tag: String = TeamManager.get_team_short_label(tid, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1))
			var col: Color = Color(1.0, 0.30, 0.26, 1.0) if is_ally else Color(1.0, 0.72, 0.28, 1.0)
			mm.emit_tactical_event(&"combat", "%s %s Destroyed!" % [tag, building.display_name], building.global_position, col)


func record_timeline_sample(mm: MatchManager, force_append: bool = false) -> void:
	if mm == null or not mm.is_inside_tree():
		return
	if not force_append and not timeline_samples.is_empty():
		var last_t: float = float(timeline_samples[timeline_samples.size() - 1].get("time", -1.0))
		if absf(mm.match_elapsed - last_t) < 0.25:
			return
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	var econ: EconomyManager = mm.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var army_values: Dictionary = {}
	var unit_counts: Dictionary = {}
	for tid: int in active_teams:
		army_values[tid] = 0
		unit_counts[tid] = 0

	for node: Node in mm.get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node
		if u.is_dead or u.is_queued_for_deletion():
			continue
		var tid: int = int(u.team)
		if not unit_counts.has(tid):
			unit_counts[tid] = 0
			army_values[tid] = 0
		unit_counts[tid] = int(unit_counts[tid]) + 1
		if u.data != null and u.data.is_combat_unit():
			var val: int = maxi(0, u.data.biomass_cost) + maxi(0, u.data.silica_cost) + maxi(0, u.data.compute_cost)
			army_values[tid] = int(army_values[tid]) + val

	var teams_snapshot: Dictionary = {}
	for tid: int in active_teams:
		var inc_rate: float = 0.0
		if econ != null:
			inc_rate = float(
				econ.get_income_rate_per_minute(tid, EconomyManager.RESOURCE_BIOMASS)
				+ econ.get_income_rate_per_minute(tid, EconomyManager.RESOURCE_SILICA)
				+ econ.get_income_rate_per_minute(tid, EconomyManager.RESOURCE_COMPUTE)
			)
		teams_snapshot[tid] = {
			"income_rate": inc_rate,
			"army_value": int(army_values.get(tid, 0)),
			"unit_count": int(unit_counts.get(tid, 0)),
		}

	timeline_samples.append({
		"time": mm.match_elapsed,
		"teams": teams_snapshot,
	})


func sample_macro_efficiency(mm: MatchManager) -> void:
	if mm == null or not mm.is_inside_tree() or mm.is_match_over or mm.sandbox_mode_active:
		return
	var econ: EconomyManager = mm.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ == null:
		return
	var active_teams: Array[int] = [0, 1]
	if TeamManager != null:
		active_teams = TeamManager.get_active_teams()
	for tid: int in active_teams:
		if mm._eliminated_teams.has(tid):
			continue
		var bucket: Dictionary = ensure_bucket(tid)
		var bw_used: int = econ.get_bandwidth_used(tid)
		var bw_cap: int = econ.get_bandwidth_cap(tid)
		if bw_cap > 0 and bw_cap < 200 and bw_used >= bw_cap:
			bucket["supply_blocked_seconds"] = float(bucket["supply_blocked_seconds"]) + 1.0
		var res: Dictionary = econ.get_resources(tid)
		var total_flt: float = (
			float(res.get(EconomyManager.RESOURCE_BIOMASS, 0))
			+ float(res.get(EconomyManager.RESOURCE_SILICA, 0))
			+ float(res.get(EconomyManager.RESOURCE_COMPUTE, 0))
		)
		bucket["resource_float_sum"] = float(bucket["resource_float_sum"]) + total_flt
		bucket["resource_float_samples"] = int(bucket["resource_float_samples"]) + 1


func record_combat_heatmap_damage(mm: MatchManager, world_pos: Vector2, victim_team: int) -> void:
	if mm == null or mm.is_match_over or mm.sandbox_mode_active:
		return
	var cx: int = int(floor(world_pos.x / 180.0))
	var cy: int = int(floor(world_pos.y / 180.0))
	var key: int = (cx + 2048) * 4096 + (cy + 2048)
	var last_t: float = float(heatmap_damage_throttle.get(key, -10.0))
	if (mm.match_elapsed - last_t) < 1.5:
		return
	heatmap_damage_throttle[key] = mm.match_elapsed
	push_heatmap_event(world_pos, 0.45, victim_team, &"damage")


func push_heatmap_event(world_pos: Vector2, weight: float, team_id: int, kind: StringName) -> void:
	if combat_heatmap_events.size() >= MAX_HEATMAP_EVENTS:
		# Merge into nearest low-weight damage sample to preserve memory cap cleanly
		for ev: Dictionary in combat_heatmap_events:
			if (ev.get("kind", &"") as StringName) == &"damage":
				var ep: Vector2 = ev.get("pos", Vector2.ZERO) as Vector2
				if ep.distance_squared_to(world_pos) <= 180.0 * 180.0:
					ev["weight"] = minf(3.0, float(ev["weight"]) + weight * 0.5)
					return
		if kind == &"damage":
			return
		combat_heatmap_events.pop_front()
	combat_heatmap_events.append({
		"pos": world_pos,
		"weight": weight,
		"team": team_id,
		"kind": kind,
	})


func compute_macro_grade(supply_blocked_s: float, match_dur_s: float, avg_float: int, trade_ratio: float) -> String:
	var blocked_pct: float = clampf(supply_blocked_s / maxf(1.0, match_dur_s), 0.0, 1.0)
	var supply_score: float = clampf(40.0 - blocked_pct * 200.0, 0.0, 40.0)
	var float_score: float = clampf(30.0 * (1.0 - maxf(0.0, float(avg_float - 350)) / 1250.0), 0.0, 30.0)
	var trade_score: float = clampf((trade_ratio / 1.45) * 30.0, 0.0, 30.0)
	var total: float = supply_score + float_score + trade_score
	if total >= 84.0:
		return "S"
	if total >= 72.0:
		return "A"
	if total >= 58.0:
		return "B"
	if total >= 42.0:
		return "C"
	return "D"


func build_match_end_stats(mm: MatchManager, winner_team: Unit.Team, winner_label: String, reason: String) -> Dictionary:
	var is_spectator: bool = TeamManager != null and TeamManager.is_spectator_mode()
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_local_win: bool = true if is_spectator else (
		TeamManager.are_allies(local_team, int(winner_team)) if (TeamManager != null and local_team >= 0) else (int(winner_team) == local_team)
	)

	var safe_duration: float = maxf(1.0, mm.match_elapsed)
	var econ: EconomyManager = mm.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	var teams_stats_out: Dictionary = {}
	for tid: int in active_teams:
		var bucket: Dictionary = ensure_bucket(tid)
		var totals: Dictionary = econ.get_all_totals_gathered(tid) if econ != null else {}
		var up_s: float = float(bucket.get("uplink_seconds", 0.0))
		var up_pct: float = clampf((up_s / safe_duration) * 100.0, 0.0, 100.0)
		var sb_s: float = float(bucket.get("supply_blocked_seconds", 0.0))
		var flt_n: int = maxi(1, int(bucket.get("resource_float_samples", 0)))
		var avg_flt: int = int(round(float(bucket.get("resource_float_sum", 0.0)) / float(flt_n)))
		var lost_v: int = int(bucket.get("resources_lost_value", 0))
		var dest_v: int = int(bucket.get("resources_destroyed_value", 0))
		var trade_r: float = float(dest_v) / float(maxi(1, lost_v)) if (dest_v > 0 or lost_v > 0) else 1.0
		var m_grade: String = compute_macro_grade(sb_s, safe_duration, avg_flt, trade_r)
		teams_stats_out[tid] = {
			"team_id": tid,
			"alliance_id": TeamManager.get_team_alliance(tid) if TeamManager != null else tid,
			"short_label": TeamManager.get_team_short_label(tid, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1)),
			"display_name": TeamManager.get_team_display_name(tid) if TeamManager != null else ("TEAM %d" % (tid + 1)),
			"color": TeamManager.get_team_color(tid) if TeamManager != null else Color(0.24, 0.96, 0.88, 1.0),
			"biomass_gathered": int(totals.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			"silica_gathered": int(totals.get(EconomyManager.RESOURCE_SILICA, 0)),
			"compute_gathered": int(totals.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			"units_trained": int(bucket.get("units_trained", 0)),
			"units_lost": int(bucket.get("units_lost", 0)),
			"enemies_destroyed": int(bucket.get("enemies_destroyed", 0)),
			"buildings_built": int(bucket.get("buildings_built", 0)),
			"buildings_lost": int(bucket.get("buildings_lost", 0)),
			"peak_bandwidth": int(bucket.get("peak_bandwidth", 0)),
			"uplink_seconds": up_s,
			"uplink_formatted": format_duration(up_s),
			"uplink_pct": up_pct,
			"supply_blocked_seconds": sb_s,
			"supply_blocked_formatted": format_duration(sb_s),
			"avg_unspent_float": avg_flt,
			"resources_lost_value": lost_v,
			"resources_destroyed_value": dest_v,
			"trade_ratio": trade_r,
			"macro_grade": m_grade,
		}

	var player_uplink_pct: float = clampf((player_uplink_time / safe_duration) * 100.0, 0.0, 100.0)
	var enemy_uplink_pct: float = clampf((enemy_uplink_time / safe_duration) * 100.0, 0.0, 100.0)
	var p_totals: Dictionary = econ.get_all_totals_gathered(Unit.Team.PLAYER) if econ != null else {}
	var e_totals: Dictionary = econ.get_all_totals_gathered(Unit.Team.ENEMY) if econ != null else {}

	return {
		"winner_team": int(winner_team),
		"winner_label": winner_label,
		"is_victory": is_local_win,
		"is_spectator": is_spectator,
		"reason": reason,
		"duration_seconds": mm.match_elapsed,
		"duration_formatted": format_duration(mm.match_elapsed),
		"uplink_control_pct": player_uplink_pct,
		"units_trained": player_units_trained,
		"units_lost": player_units_lost,
		"enemies_destroyed": enemy_units_destroyed,
		"structures_destroyed": enemy_structures_destroyed,
		"timeline_samples": timeline_samples.duplicate(true),
		"combat_heatmap_events": combat_heatmap_events.duplicate(true),
		"procedural_seed_tag": GameConfig.get_procedural_summary_tag() if (GameConfig != null and GameConfig.is_procedural_map_selected()) else "",
		"active_mutators": GameConfig.get_active_mutator_labels() if (GameConfig != null and GameConfig.has_method("get_active_mutator_labels")) else PackedStringArray(),
		"active_teams": active_teams,
		"teams": teams_stats_out,
		"player": {
			"biomass_gathered": int(p_totals.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			"silica_gathered": int(p_totals.get(EconomyManager.RESOURCE_SILICA, 0)),
			"compute_gathered": int(p_totals.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			"units_trained": player_units_trained,
			"units_lost": player_units_lost,
			"enemies_destroyed": enemy_units_destroyed,
			"buildings_built": player_buildings_built,
			"buildings_lost": player_buildings_lost,
			"peak_bandwidth": player_peak_bandwidth,
			"uplink_seconds": player_uplink_time,
			"uplink_formatted": format_duration(player_uplink_time),
			"uplink_pct": player_uplink_pct,
		},
		"enemy": {
			"biomass_gathered": int(e_totals.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			"silica_gathered": int(e_totals.get(EconomyManager.RESOURCE_SILICA, 0)),
			"compute_gathered": int(e_totals.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			"units_trained": enemy_units_trained,
			"units_lost": enemy_units_destroyed,
			"enemies_destroyed": player_units_lost,
			"buildings_built": enemy_buildings_built,
			"buildings_lost": enemy_structures_destroyed,
			"peak_bandwidth": enemy_peak_bandwidth,
			"uplink_seconds": enemy_uplink_time,
			"uplink_formatted": format_duration(enemy_uplink_time),
			"uplink_pct": enemy_uplink_pct,
		},
	}


static func format_duration(seconds: float) -> String:
	var total_s: int = maxi(0, int(floor(seconds)))
	var mins: int = total_s / 60
	var secs: int = total_s % 60
	return "%02d:%02d" % [mins, secs]
