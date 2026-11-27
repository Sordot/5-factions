class_name AIArmyController
extends RefCounted

const MapLandmarkScript = preload("res://scripts/world/map_landmark.gd")

const BARRICADE_MIN_MATCH_TIME: float = 150.0
const BASE_DEFENSE_CLEAR_TIME: float = 3.0
const RETREAT_REGROUP_DURATION: float = 8.0

var ai: SkirmishAICommander = null
var army_state: SkirmishAICommander.ArmyState = SkirmishAICommander.ArmyState.STAGING
var staging_point: Vector2 = Vector2.ZERO
var staging_point_valid: bool = false
var staging_snapped_to_nav: bool = false
var last_core_count: int = 0
var wave_units: Array[Unit] = []
var defense_units: Array[Unit] = []
var raid_units: Array[Unit] = []
var wave_launch_strength: float = 0.0
var _raid_launch_strength: float = 0.0
var _raid_target: Vector2 = Vector2.ZERO
var _raid_cooldown_timer: float = 0.0
var current_attack_target: Vector2 = Vector2.ZERO
var regroup_timer: float = 0.0
var defense_clear_timer: float = 0.0
var breach_target: Node2D = null
var last_staging_count: int = 0

var wave_timer: float = 0.0
var wave_cooldown_timer: float = 0.0
var wave_number: int = 0

var _unit_last_pos: Dictionary = {}
var _unit_stall_ticks: Dictionary = {}
var _deploy_idle_timers: Dictionary = {}
var _kite_cooldowns: Dictionary = {}
var _cleared_anchor_times: Dictionary = {}
var _sweep_anchor_index: int = 0


func setup(owner_ai: SkirmishAICommander) -> void:
	ai = owner_ai


func tick_timers(delta: float) -> void:
	wave_timer += delta
	if wave_cooldown_timer > 0.0:
		wave_cooldown_timer = maxf(0.0, wave_cooldown_timer - delta)
	if _raid_cooldown_timer > 0.0:
		_raid_cooldown_timer = maxf(0.0, _raid_cooldown_timer - delta)


func ensure_staging_anchor(core: Building, core_count: int) -> void:
	if not staging_point_valid or not staging_snapped_to_nav or core_count != last_core_count:
		last_core_count = core_count
		compute_staging_point(core)


func compute_staging_point(core: Building) -> Vector2:
	if ai == null or core == null or not is_instance_valid(core):
		return staging_point

	var center_ref: Vector2 = Vector2.ZERO
	var uplink: HyperUplink = ai.get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if uplink != null and is_instance_valid(uplink):
		center_ref = uplink.global_position

	var map_rid: RID = ai.get_viewport().world_2d.navigation_map if ai.get_viewport() != null else RID()
	var nav_ready: bool = map_rid.is_valid() and NavigationServer2D.map_get_iteration_id(map_rid) > 0

	# Phase C.2 — High-Ground Plateau Staging & Ambush Posture:
	# Prefer a friendly-side mid-field HighGroundPlateau overlook (340-820 px from core, closer to center than core).
	var core_to_center_dist: float = core.global_position.distance_to(center_ref)
	var best_hg_pos: Vector2 = Vector2.INF
	var best_hg_score: float = INF
	var hg_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(36.0, 0.0),
		Vector2(-36.0, 0.0),
		Vector2(0.0, 36.0),
		Vector2(0.0, -36.0),
		Vector2(28.0, 28.0),
		Vector2(-28.0, -28.0),
	]
	for p_node: Node in ai.get_tree().get_nodes_in_group("high_ground_plateaus"):
		if not (p_node is HighGroundPlateau) or not is_instance_valid(p_node):
			continue
		var plateau: HighGroundPlateau = p_node as HighGroundPlateau
		if plateau.elevation_level < 1:
			continue
		var wpoly: PackedVector2Array = plateau.get_world_polygon()
		if wpoly.size() < 3:
			continue
		var p_center: Vector2 = Vector2.ZERO
		for v: Vector2 in wpoly:
			p_center += v
		p_center /= float(wpoly.size())

		var d_core: float = core.global_position.distance_to(p_center)
		if d_core < 340.0 or d_core > 820.0:
			continue
		var d_center: float = p_center.distance_to(center_ref)
		if d_center >= core_to_center_dist:
			continue

		var valid_cand: Vector2 = Vector2.INF
		for off: Vector2 in hg_offsets:
			var cand_hg: Vector2 = p_center + off
			if not plateau.contains_world_point(cand_hg):
				continue
			if not is_staging_spot_clear(cand_hg, 44.0):
				continue
			var snapped: Vector2 = cand_hg
			if nav_ready:
				snapped = NavigationServer2D.map_get_closest_point(map_rid, cand_hg)
				if plateau.get_world_elevation_at(snapped) < 1:
					continue
			valid_cand = snapped
			break
		if valid_cand == Vector2.INF:
			continue
		var score: float = d_core + d_center * 0.15
		if score < best_hg_score:
			best_hg_score = score
			best_hg_pos = valid_cand

	if best_hg_pos != Vector2.INF:
		staging_snapped_to_nav = nav_ready
		staging_point = best_hg_pos
		staging_point_valid = true
		return staging_point

	var to_center: Vector2 = center_ref - core.global_position
	var base_dir: Vector2 = to_center.normalized() if to_center.length_squared() > 16.0 else Vector2.RIGHT

	var safe_bounds: Rect2 = ai.arena_bounds.grow(-92.0)
	var distances: PackedFloat32Array = PackedFloat32Array([390.0, 355.0, 435.0, 310.0])
	var angles: PackedFloat32Array = PackedFloat32Array([0.0, 0.24, -0.24, 0.50, -0.50, 0.80, -0.80])

	var chosen: Vector2 = core.global_position + base_dir * 380.0
	var found_clear: bool = false
	for dist: float in distances:
		for ang: float in angles:
			var cand: Vector2 = core.global_position + base_dir.rotated(ang) * dist
			if safe_bounds.has_area():
				cand.x = clampf(cand.x, safe_bounds.position.x, safe_bounds.end.x)
				cand.y = clampf(cand.y, safe_bounds.position.y, safe_bounds.end.y)
			if is_staging_spot_clear(cand, 44.0):
				chosen = cand
				found_clear = true
				break
		if found_clear:
			break

	if nav_ready:
		chosen = NavigationServer2D.map_get_closest_point(map_rid, chosen)
		staging_snapped_to_nav = true
	else:
		staging_snapped_to_nav = false

	staging_point = chosen
	staging_point_valid = true
	return staging_point


func is_staging_spot_clear(world_pos: Vector2, clearance_r: float) -> bool:
	for node: Node in ai.get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_r)):
				return false
	for node: Node in ai.get_tree().get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_r)):
				return false
	for node: Node in ai.get_tree().get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(node) and not bool(node.get("is_destroyed")) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_r)):
				return false
	for node: Node in ai.get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node) and not (node as Building).is_destroyed:
			var min_d: float = (node as Building).footprint_radius + clearance_r
			if (node as Building).global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	return true


func sync_military_rallies() -> void:
	if not staging_point_valid:
		return
	var rally_lead: Unit = null
	if army_state == SkirmishAICommander.ArmyState.ATTACKING and get_wave_strength_ratio() > 0.70:
		for u: Unit in wave_units:
			if is_instance_valid(u) and not u.is_dead and not u.is_staffed:
				rally_lead = u
				break

	for b: Building in ai.get_team_buildings(ai.ai_team):
		if not b.is_constructed or b.is_destroyed or not b.can_set_rally:
			continue
		if not ai.is_military_production_building(b):
			continue
		if rally_lead != null:
			if b.get_rally_target() != rally_lead:
				b.set_rally_target_unit(rally_lead)
		else:
			if b.get_rally_target() != null or b.get_rally_world_position().distance_squared_to(staging_point) > 36.0:
				b.set_rally_position(staging_point)


func tick_army_state_machine(core: Building, tick_dt: float) -> void:
	prune_wave_units()

	# 1. Proportional Home Defense (swats small harassers locally without freezing winning main pushes!)
	var threat_info: Dictionary = find_base_perimeter_threat(core)
	if not threat_info.is_empty():
		ai.economy.note_base_pressure()
		defense_clear_timer = 0.0
		var recalled_main_wave: bool = dispatch_proportional_defense(threat_info, core)
		if recalled_main_wave:
			army_state = SkirmishAICommander.ArmyState.DEFENDING
			return
	elif army_state == SkirmishAICommander.ArmyState.DEFENDING or not defense_units.is_empty():
		defense_clear_timer += tick_dt
		if defense_clear_timer >= BASE_DEFENSE_CLEAR_TIME:
			defense_clear_timer = 0.0
			defense_units.clear()
			if army_state == SkirmishAICommander.ArmyState.DEFENDING:
				army_state = SkirmishAICommander.ArmyState.STAGING
			rally_idle_combat_to_staging(true)
		if army_state == SkirmishAICommander.ArmyState.DEFENDING:
			return

	match army_state:
		SkirmishAICommander.ArmyState.RETREATING:
			tick_retreating_state(tick_dt)
		SkirmishAICommander.ArmyState.BREACHING:
			tick_breaching_state(core)
		SkirmishAICommander.ArmyState.ATTACKING:
			tick_attacking_state(core)
		SkirmishAICommander.ArmyState.STAGING:
			tick_staging_state(core)


func find_base_perimeter_threat(core: Building) -> Dictionary:
	var ai_buildings: Array[Building] = ai.get_team_buildings(ai.ai_team)
	var seen_threat_ids: Dictionary = {}
	var threat_power: float = 0.0
	var primary_threat_unit: Unit = null
	var threatened_hub: Building = core
	var best_d_sq: float = INF

	# Check ~650px perimeter around every owned Command Hub and economy drop-off via SpatialGrid.
	# Obeys Fog of War / high-ground vision (only reacts to visible hostiles or those actively firing on AI assets).
	for b: Building in ai_buildings:
		var check_r: float = ai.base_defense_radius if (b.is_command_hub() or b.is_resource_dropoff) else 380.0
		var nearby: Array = SpatialGrid.query_units_in_radius(b.global_position, check_r) if SpatialGrid != null else ai.get_tree().get_nodes_in_group("units")
		var r_sq: float = check_r * check_r
		for item: Variant in nearby:
			if not is_instance_valid(item) or not (item is Unit):
				continue
			var hostile: Unit = item as Unit
			if hostile.is_dead or hostile.is_staffed or not ai.is_enemy_team(int(hostile.team)):
				continue
			if not ai.is_combat_unit(hostile) and hostile.command_state != Unit.CommandState.ATTACKING_TARGET:
				continue
			var attacking_ai_asset: bool = false
			if hostile.current_target != null and is_instance_valid(hostile.current_target):
				if hostile.current_target is Unit and ai.is_allied_team(int((hostile.current_target as Unit).team)):
					attacking_ai_asset = true
				elif hostile.current_target is Building and ai.is_allied_team(int((hostile.current_target as Building).team)):
					attacking_ai_asset = true
			if not attacking_ai_asset and not ai.scout_intel.is_entity_visible_to_ai(hostile):
				continue
			var d_sq: float = b.global_position.distance_squared_to(hostile.global_position)
			if d_sq <= r_sq:
				var hid: int = hostile.get_instance_id()
				if not seen_threat_ids.has(hid):
					seen_threat_ids[hid] = true
					threat_power += ai.get_unit_power_weight(hostile)
				if d_sq < best_d_sq:
					best_d_sq = d_sq
					primary_threat_unit = hostile
					if b.is_command_hub():
						threatened_hub = b

	if primary_threat_unit == null:
		return {}
	return {
		"pos": primary_threat_unit.global_position,
		"threat_power": maxf(1.0, threat_power),
		"hub": threatened_hub if (threatened_hub != null and is_instance_valid(threatened_hub)) else core,
	}


func is_backline_support_unit(u: Unit) -> bool:
	if u == null or not is_instance_valid(u) or u.data == null:
		return false
	return u.data.has_tag(&"support") or u.data.tether_emit_radius > 0.0 or u.data.heal_aura_rate > 0.0


func compute_support_trailing_pos(dest: Vector2, anchor_back: Vector2, offset_dist: float = 100.0) -> Vector2:
	var back_vec: Vector2 = anchor_back - dest
	var back_dir: Vector2 = back_vec.normalized() if back_vec.length_squared() > 16.0 else Vector2.LEFT
	var pos: Vector2 = dest + back_dir * offset_dist
	var safe: Rect2 = ai.arena_bounds.grow(-48.0)
	if safe.has_area():
		pos.x = clampf(pos.x, safe.position.x, safe.end.x)
		pos.y = clampf(pos.y, safe.position.y, safe.end.y)
	return pos


func dispatch_proportional_defense(threat_info: Dictionary, core: Building) -> bool:
	var threat_pos: Vector2 = threat_info["pos"] as Vector2
	var threat_power: float = float(threat_info.get("threat_power", 1.0))
	var hub: Building = threat_info.get("hub", core) as Building
	var needed_power: float = maxf(2.5, threat_power * 1.45)

	# Gather home/staging candidates sorted closest to threat first (never stealing active scout or raid unless emergency)
	var home_candidates: Array[Unit] = []
	for u: Unit in ai.get_team_units(ai.ai_team):
		if not ai.is_combat_unit(u) or u == ai.scout_intel.active_scout:
			continue
		if defense_units.has(u) or wave_units.has(u) or raid_units.has(u):
			continue
		home_candidates.append(u)
	home_candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.global_position.distance_squared_to(threat_pos) < b.global_position.distance_squared_to(threat_pos)
	)

	var current_def_power: float = compute_units_strength(defense_units)
	for cand: Unit in home_candidates:
		if current_def_power >= needed_power:
			break
		defense_units.append(cand)
		current_def_power += ai.get_unit_power_weight(cand)

	var hub_critical: bool = hub != null and is_instance_valid(hub) and (hub.current_hp / maxf(1.0, hub.max_hp)) < 0.65
	var need_full_recall: bool = hub_critical or (current_def_power < needed_power * 0.65)
	if need_full_recall and not wave_units.is_empty():
		for wu: Unit in wave_units:
			if is_instance_valid(wu) and not wu.is_dead and not defense_units.has(wu):
				defense_units.append(wu)
		wave_units.clear()
		wave_launch_strength = 0.0
		breach_target = null
	elif need_full_recall and wave_units.is_empty():
		breach_target = null

	var anchor_hub: Building = hub if (hub != null and is_instance_valid(hub)) else core
	var frontline_sum: Vector2 = Vector2.ZERO
	var frontline_cnt: int = 0
	for u_a: Unit in defense_units:
		if u_a.data != null and u_a.data.attack_damage > 0.0 and not is_backline_support_unit(u_a):
			frontline_sum += u_a.global_position
			frontline_cnt += 1
	if frontline_cnt == 0:
		for u_a2: Unit in defense_units:
			if u_a2.data != null and u_a2.data.attack_damage > 0.0:
				frontline_sum += u_a2.global_position
				frontline_cnt += 1
	var frontline_centroid_def: Vector2 = (frontline_sum / float(frontline_cnt)) if frontline_cnt > 0 else anchor_hub.global_position

	for u: Unit in defense_units:
		if is_backline_support_unit(u):
			var is_pure_support: bool = u.data != null and u.data.attack_damage <= 0.0
			if is_pure_support:
				var escort_def: Vector2 = compute_support_trailing_pos(frontline_centroid_def, anchor_hub.global_position, 98.0)
				if frontline_centroid_def.distance_squared_to(threat_pos) > 400.0:
					escort_def = compute_support_trailing_pos(frontline_centroid_def, frontline_centroid_def + (frontline_centroid_def - threat_pos), 98.0)
				if u.global_position.distance_to(escort_def) > 105.0 or u.command_state == Unit.CommandState.IDLE:
					u.command_move(escort_def, false)
				continue
			var sup_def_dest: Vector2 = compute_support_trailing_pos(threat_pos, anchor_hub.global_position, 100.0)
			if u.command_state == Unit.CommandState.IDLE or u.command_state == Unit.CommandState.MOVING:
				u.command_attack_move(sup_def_dest, false)
			continue
		var needs_order: bool = (
			u.command_state == Unit.CommandState.IDLE
			or u.command_state == Unit.CommandState.MOVING
			or (u.command_state == Unit.CommandState.ATTACK_MOVING and u.current_target == null and u.global_position.distance_to(threat_pos) > 220.0)
			or (u.command_state == Unit.CommandState.ATTACKING_TARGET and u.current_target != null and u.current_target.is_in_group("destructible_barricades"))
		)
		if needs_order:
			u.command_attack_move(threat_pos, false)

	return need_full_recall


func tick_raid_squad(core: Building, _tick_dt: float) -> void:
	if ai == null or ai.is_relaxed_difficulty() or core == null or not is_instance_valid(core):
		return
	if not raid_units.is_empty():
		var raid_power: float = compute_units_strength(raid_units)
		var raid_centroid: Vector2 = Vector2.ZERO
		for ru: Unit in raid_units:
			raid_centroid += ru.global_position
		raid_centroid /= float(raid_units.size())

		var enemy_near_power: float = 0.0
		for eu_var: Variant in ai.scout_intel.visible_enemy_units.values():
			var eu: Unit = eu_var as Unit
			if is_instance_valid(eu) and not eu.is_dead and ai.is_combat_unit(eu):
				if eu.global_position.distance_squared_to(raid_centroid) <= 320.0 * 320.0:
					enemy_near_power += ai.get_unit_power_weight(eu)

		var overwhelmed: bool = enemy_near_power > raid_power * 1.6
		var depleted: bool = _raid_launch_strength > 0.01 and (raid_power / _raid_launch_strength) < 0.40
		var all_idle_near_target: bool = true
		for ru_i: Unit in raid_units:
			if ru_i.command_state != Unit.CommandState.IDLE or ru_i.global_position.distance_squared_to(_raid_target) > 220.0 * 220.0:
				all_idle_near_target = false
				break

		if overwhelmed or depleted or all_idle_near_target:
			var ret_pt: Vector2 = staging_point if staging_point_valid else core.global_position
			var ret_gid: int = CommandRouter.allocate_move_group_id() if raid_units.size() > 1 else 0
			for ru_r: Unit in raid_units:
				ru_r.command_move(ret_pt, false, ret_gid)
			raid_units.clear()
			_raid_launch_strength = 0.0
			_raid_cooldown_timer = 55.0
		return

	if ai.ai_elapsed < 135.0 or _raid_cooldown_timer > 0.0:
		return

	var staging: Array[Unit] = collect_staging_combat_units()
	if staging.size() <= get_target_wave_size() + 2:
		return

	var fast_pool: Array[Unit] = []
	for u: Unit in staging:
		if u.data == null or is_backline_support_unit(u) or u.data.is_heavy_unit():
			continue
		if u.data.has_tag(&"flanker") or u.data.has_tag(&"scout") or u.data.move_speed >= 220.0:
			fast_pool.append(u)
	if fast_pool.size() < 2:
		return

	var raid_target_pos: Vector2 = Vector2.INF
	var relay_cand: Variant = ai.scout_intel.find_nearest_neutral_sensor_relay_pos(core.global_position)
	if relay_cand is Vector2:
		raid_target_pos = relay_cand as Vector2
	else:
		var lkeb: Vector2 = ai.scout_intel.scouted_intel.get("last_known_enemy_base", Vector2.INF) as Vector2
		if lkeb != Vector2.INF:
			var north_lane: bool = (wave_number % 2) == 0
			var flank_wp: Vector2 = get_flank_corridor_waypoint(north_lane)
			if find_nearby_intact_barricade(flank_wp, 220.0) == null:
				raid_target_pos = lkeb
			else:
				var alt_wp: Vector2 = get_flank_corridor_waypoint(not north_lane)
				if find_nearby_intact_barricade(alt_wp, 220.0) == null:
					raid_target_pos = lkeb

	if raid_target_pos == Vector2.INF:
		return

	var desired_cnt: int = mini(3, fast_pool.size())
	raid_units.clear()
	for i: int in range(desired_cnt):
		raid_units.append(fast_pool[i])
	_raid_launch_strength = compute_units_strength(raid_units)
	_raid_target = raid_target_pos
	var raid_gid: int = CommandRouter.allocate_move_group_id() if raid_units.size() > 1 else 0
	for ru_d: Unit in raid_units:
		ru_d.command_attack_move(_raid_target, false, raid_gid)


func tick_retreating_state(tick_dt: float) -> void:
	regroup_timer = maxf(0.0, regroup_timer - tick_dt)
	var all_arrived: bool = true
	for u: Unit in wave_units:
		if u.global_position.distance_to(staging_point) > 220.0:
			all_arrived = false
			if u.command_state != Unit.CommandState.MOVING:
				u.command_move(staging_point, false)
	if regroup_timer <= 0.0 or wave_units.is_empty() or all_arrived:
		wave_units.clear()
		wave_launch_strength = 0.0
		regroup_timer = 0.0
		army_state = SkirmishAICommander.ArmyState.STAGING


func tick_breaching_state(core: Building) -> void:
	if breach_target == null or not is_instance_valid(breach_target) or bool(breach_target.get("is_destroyed")) or breach_target.is_queued_for_deletion():
		# Gate breached! Push through as a flank raid if squad is healthy, else regroup at staging
		breach_target = null
		if wave_units.size() >= 4:
			launch_wave_from_units(wave_units, core, false)
		else:
			wave_units.clear()
			wave_launch_strength = 0.0
			army_state = SkirmishAICommander.ArmyState.STAGING
		return

	if wave_units.is_empty():
		breach_target = null
		army_state = SkirmishAICommander.ArmyState.STAGING
		return

	# Interrupt breaching immediately if hostile combat units engage the breaching squad
	var intercept_pos: Variant = find_hostile_near_squad(wave_units, 340.0)
	if intercept_pos is Vector2:
		breach_target = null
		wave_launch_strength = compute_units_strength(wave_units)
		current_attack_target = intercept_pos as Vector2
		army_state = SkirmishAICommander.ArmyState.ATTACKING
		var intercept_gid: int = CommandRouter.allocate_move_group_id() if wave_units.size() > 1 else 0
		for u: Unit in wave_units:
			u.command_attack_move(current_attack_target, false, intercept_gid)
		return

	# Keep breaching squad explicitly focus-firing the DestructibleBarricade (backline supports trail ~100 px behind)
	var breach_back_ref: Vector2 = staging_point if staging_point_valid else core.global_position
	var breach_escort_pt: Vector2 = compute_support_trailing_pos(breach_target.global_position, breach_back_ref, 102.0)
	for u: Unit in wave_units:
		if is_backline_support_unit(u) and u.data != null and u.data.attack_damage <= 0.0:
			if u.global_position.distance_to(breach_escort_pt) > 95.0 or u.command_state == Unit.CommandState.IDLE:
				u.command_move(breach_escort_pt, false)
			continue
		if u.command_state != Unit.CommandState.ATTACKING_TARGET or u.current_target != breach_target:
			u.command_attack_target(breach_target, false)


func tick_attacking_state(core: Building) -> void:
	if wave_units.is_empty():
		wave_launch_strength = 0.0
		army_state = SkirmishAICommander.ArmyState.STAGING
		return

	var remaining_ratio: float = get_wave_strength_ratio()
	var retreat_threshold: float = 0.30 if ai.is_brutal_difficulty() else 0.25
	if remaining_ratio < retreat_threshold and not is_wave_finishing_enemy_core():
		# Pull survivors back to staging_point and pop ready escape/defensive self-abilities
		army_state = SkirmishAICommander.ArmyState.RETREATING
		regroup_timer = RETREAT_REGROUP_DURATION
		wave_cooldown_timer = 16.0 if ai.is_relaxed_difficulty() else 8.0
		var retreat_gid: int = CommandRouter.allocate_move_group_id() if wave_units.size() > 1 else 0
		for u: Unit in wave_units:
			_trigger_retreat_escape_ability(u)
			u.command_move(staging_point, false, retreat_gid)
		return

	# Keep non-wave newly spawned reinforcements calmly staged at staging_point
	rally_idle_combat_to_staging(true)

	# Light ranged kiting micro (Standard / Brutal only — AI-only, zero player formation changes)
	if not ai.is_relaxed_difficulty():
		_tick_ranged_kiting()

	# Phase C.3 — Live Support & Tether Anchor Escort Positioning (AI-only; zero player formation changes):
	# Compute live centroid of non-support combat units in wave_units and keep pure supports ~95 px behind frontline.
	var combat_sum: Vector2 = Vector2.ZERO
	var combat_count: int = 0
	for u_f: Unit in wave_units:
		if u_f.data != null and u_f.data.attack_damage > 0.0 and not is_backline_support_unit(u_f):
			combat_sum += u_f.global_position
			combat_count += 1
	if combat_count == 0:
		for u_f2: Unit in wave_units:
			if u_f2.data != null and u_f2.data.attack_damage > 0.0:
				combat_sum += u_f2.global_position
				combat_count += 1
	var back_anchor: Vector2 = staging_point if staging_point_valid else core.global_position
	if combat_count > 0:
		var combat_centroid: Vector2 = combat_sum / float(combat_count)
		var back_dir: Vector2 = (combat_centroid - current_attack_target).normalized() if current_attack_target.distance_squared_to(combat_centroid) > 400.0 else ((back_anchor - combat_centroid).normalized() if combat_centroid.distance_squared_to(back_anchor) > 100.0 else Vector2.LEFT)
		var escort_pt: Vector2 = combat_centroid + back_dir * 95.0
		var safe_esc: Rect2 = ai.arena_bounds.grow(-48.0)
		if safe_esc.has_area():
			escort_pt.x = clampf(escort_pt.x, safe_esc.position.x, safe_esc.end.x)
			escort_pt.y = clampf(escort_pt.y, safe_esc.position.y, safe_esc.end.y)
		var frontline_to_target_sq: float = combat_centroid.distance_squared_to(current_attack_target)
		for u_s: Unit in wave_units:
			if u_s.data != null and u_s.data.attack_damage <= 0.0 and is_backline_support_unit(u_s):
				var drifted_far: bool = u_s.global_position.distance_to(combat_centroid) > 165.0
				var ahead_of_frontline: bool = u_s.global_position.distance_squared_to(current_attack_target) < frontline_to_target_sq
				if drifted_far or ahead_of_frontline or u_s.command_state == Unit.CommandState.IDLE:
					u_s.command_move(escort_pt, false)

	# Re-push any armed wave units that went idle after clearing an enemy pocket
	var idle_wave: Array[Unit] = []
	for u: Unit in wave_units:
		if u.data != null and u.data.attack_damage <= 0.0:
			continue
		if u.command_state == Unit.CommandState.IDLE:
			idle_wave.append(u)
	if not idle_wave.is_empty():
		current_attack_target = select_wave_target(wave_number, core)
		var router: CommandRouter = ai.get_command_router()
		var slots: Array[Vector2] = []
		if router != null:
			slots = router.assign_group_destinations(idle_wave, current_attack_target)
		var repush_gid: int = CommandRouter.allocate_move_group_id() if idle_wave.size() > 1 else 0
		for i: int in range(idle_wave.size()):
			var dest: Vector2 = slots[i] if i < slots.size() else current_attack_target
			if is_backline_support_unit(idle_wave[i]):
				dest = compute_support_trailing_pos(dest, back_anchor, 100.0)
			idle_wave[i].command_attack_move(dest, false, repush_gid)


func _trigger_retreat_escape_ability(u: Unit) -> void:
	if u == null or not is_instance_valid(u) or u.is_dead or u.data == null or u.data.abilities.is_empty():
		return
	for ab: AbilityData in u.data.abilities:
		if ab == null:
			continue
		if ab.ability_id == &"solar_step" or ab.ability_id == &"kinetic_barrier" or ab.ability_id == &"adrenal_surge":
			if u.is_ability_ready(ab):
				u.command_cast_ability(ab, u.global_position, u)
				return


func _tick_ranged_kiting() -> void:
	var now: float = ai.ai_elapsed
	var safe_bounds: Rect2 = ai.arena_bounds.grow(-48.0)
	var live_ids: Dictionary = {}
	for u: Unit in wave_units:
		if not is_instance_valid(u) or u.is_dead or u.is_staffed or u.is_deployed() or u.is_deploy_transitioning():
			continue
		var uid: int = u.get_instance_id()
		live_ids[uid] = true
		if is_backline_support_unit(u) or u.get_effective_attack_range() < 150.0:
			continue
		if u.current_hp >= u.get_max_hp() * 0.50:
			continue
		if u.combat_component == null or u.combat_component._attack_cooldown_timer <= 0.20:
			continue
		if now < float(_kite_cooldowns.get(uid, 0.0)):
			continue
		var near_melee: Unit = null
		var best_d_sq: float = 90.0 * 90.0
		var nearby: Array = SpatialGrid.query_units_in_radius(u.global_position, 96.0) if SpatialGrid != null else []
		for item: Variant in nearby:
			if not is_instance_valid(item) or not (item is Unit):
				continue
			var h: Unit = item as Unit
			if h.is_dead or h.is_staffed or not ai.is_enemy_team(int(h.team)) or not ai.is_combat_unit(h):
				continue
			if h.get_effective_attack_range() > 130.0:
				continue
			if not ai.scout_intel.is_entity_visible_to_ai(h):
				continue
			var d_sq: float = u.global_position.distance_squared_to(h.global_position)
			if d_sq <= best_d_sq:
				best_d_sq = d_sq
				near_melee = h
		if near_melee == null:
			continue
		var away: Vector2 = (u.global_position - near_melee.global_position).normalized()
		if away.length_squared() < 0.01:
			away = Vector2.LEFT
		var step_pos: Vector2 = u.global_position + away * 95.0
		if safe_bounds.has_area():
			step_pos.x = clampf(step_pos.x, safe_bounds.position.x, safe_bounds.end.x)
			step_pos.y = clampf(step_pos.y, safe_bounds.position.y, safe_bounds.end.y)
		u.command_move(step_pos, false)
		u.command_attack_move(current_attack_target, true)
		_kite_cooldowns[uid] = now + 2.0

	for k: Variant in _kite_cooldowns.keys():
		if not live_ids.has(k):
			_kite_cooldowns.erase(k)


func _try_assist_allied_hub(staging_units: Array[Unit]) -> bool:
	if TeamManager == null or staging_units.size() < 3:
		return false
	var has_ally_team: bool = false
	for tid: int in TeamManager.get_active_teams():
		if tid != int(ai.ai_team) and ai.is_allied_team(tid):
			has_ally_team = true
			break
	if not has_ally_team:
		return false

	var best_threat_pos: Vector2 = Vector2.INF
	var highest_threat: float = 0.0
	for node: Node in ai.get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node as Building
		if b.is_destroyed or not b.is_command_hub() or int(b.team) == int(ai.ai_team) or not ai.is_allied_team(int(b.team)):
			continue
		var local_power: float = 0.0
		var near_pos: Vector2 = b.global_position
		for eu_var: Variant in ai.scout_intel.visible_enemy_units.values():
			var eu: Unit = eu_var as Unit
			if is_instance_valid(eu) and not eu.is_dead and ai.is_combat_unit(eu):
				if eu.global_position.distance_squared_to(b.global_position) <= 560.0 * 560.0:
					local_power += ai.get_unit_power_weight(eu)
					near_pos = eu.global_position
		if local_power >= 3.0 and local_power > highest_threat:
			highest_threat = local_power
			best_threat_pos = near_pos

	if best_threat_pos == Vector2.INF:
		return false

	var send_cnt: int = maxi(2, staging_units.size() / 2)
	var assist_gid: int = CommandRouter.allocate_move_group_id() if send_cnt > 1 else 0
	for i: int in range(send_cnt):
		var u: Unit = staging_units[i]
		if u.command_state == Unit.CommandState.IDLE:
			u.command_attack_move(best_threat_pos, false, assist_gid)
	return true


func tick_staging_state(core: Building) -> void:
	var staging_units: Array[Unit] = collect_staging_combat_units()
	last_staging_count = staging_units.size()

	# 2v2 Allied Base Assistance: reinforce an allied Command Hub under heavy visible attack
	if _try_assist_allied_hub(staging_units):
		return

	# Form up idle/stray combat units cleanly around staging_point
	rally_idle_combat_to_staging(false)

	# Phase C.1: Mid-game DestructibleBarricade breaching on Twin Causeway / Quad Nexus
	if ai.ai_elapsed >= BARRICADE_MIN_MATCH_TIME and staging_units.size() >= 4:
		var breach_gate: Node2D = find_nearby_intact_barricade(core.global_position, 1100.0)
		if breach_gate != null and (squad_has_anti_armor_or_siege(staging_units) or staging_units.size() >= 6):
			army_state = SkirmishAICommander.ArmyState.BREACHING
			breach_target = breach_gate
			wave_units = staging_units.duplicate()
			wave_launch_strength = compute_units_strength(wave_units)
			var b_back: Vector2 = staging_point if staging_point_valid else core.global_position
			var b_escort: Vector2 = compute_support_trailing_pos(breach_target.global_position, b_back, 102.0)
			for u: Unit in wave_units:
				if u.data != null and u.data.attack_damage > 0.0:
					u.command_attack_target(breach_target, false)
				else:
					u.command_move(b_escort, false)
			ai.try_emit_ai_transmission(&"barricade_breach", ai.sanitize_transmission_pos(breach_target.global_position, false))
			return

	if wave_cooldown_timer > 0.0:
		return

	var target_size: int = get_target_wave_size()
	var ready_by_size: bool = staging_units.size() >= target_size
	var ready_by_timer: bool = wave_timer >= ai.max_wave_interval and staging_units.size() >= maxi(3, target_size - 2)
	if not ready_by_size and not ready_by_timer:
		return

	launch_wave_from_units(staging_units, core, true)


func launch_wave_from_units(squad: Array[Unit], core: Building, allow_flank: bool) -> void:
	if squad.is_empty():
		return
	wave_number += 1
	wave_timer = 0.0
	wave_cooldown_timer = 30.0 if ai.is_relaxed_difficulty() else (8.0 if ai.is_brutal_difficulty() else 12.0)

	wave_units = squad.duplicate()
	wave_launch_strength = compute_units_strength(wave_units)
	current_attack_target = select_wave_target(wave_number, core)
	army_state = SkirmishAICommander.ArmyState.ATTACKING
	var uplink_node: Node2D = ai.get_tree().get_first_node_in_group("hyper_uplinks") as Node2D
	if uplink_node != null and is_instance_valid(uplink_node) and current_attack_target.distance_squared_to(uplink_node.global_position) <= 140.0 * 140.0:
		ai.try_emit_ai_transmission(&"uplink_contest", uplink_node.global_position)
	else:
		ai.try_emit_ai_transmission(&"wave_launch", Vector2.INF)

	var router: CommandRouter = ai.get_command_router()
	var destinations: Array[Vector2] = []
	if router != null:
		destinations = router.assign_group_destinations(wave_units, current_attack_target)

	var use_flank: bool = allow_flank and wave_number >= 2 and (wave_number % 2) == 0
	var flank_wp: Vector2 = Vector2.ZERO
	if use_flank:
		var north_lane: bool = ((wave_number / 2) % 2) == 1
		flank_wp = get_flank_corridor_waypoint(north_lane)
		# Don't route a flank wave into an intact barricade unless actively breaching it
		if find_nearby_intact_barricade(flank_wp, 240.0) != null:
			use_flank = false

	var flank_slots: Array[Vector2] = []
	if use_flank and router != null:
		flank_slots = router.assign_group_destinations(wave_units, flank_wp)

	var rear_ref: Vector2 = staging_point if staging_point_valid else core.global_position
	var flank_gid: int = CommandRouter.allocate_move_group_id() if (use_flank and wave_units.size() > 1) else 0
	var dest_gid: int = CommandRouter.allocate_move_group_id() if wave_units.size() > 1 else 0
	for i: int in range(wave_units.size()):
		var trooper: Unit = wave_units[i]
		var dest: Vector2 = destinations[i] if i < destinations.size() else current_attack_target
		var is_sup: bool = is_backline_support_unit(trooper)
		var is_pure_sup: bool = is_sup and trooper.data != null and trooper.data.attack_damage <= 0.0
		if is_sup:
			dest = compute_support_trailing_pos(dest, rear_ref, 100.0)
		if use_flank:
			var leg1: Vector2 = flank_slots[i] if i < flank_slots.size() else flank_wp
			if is_sup:
				leg1 = compute_support_trailing_pos(leg1, rear_ref, 100.0)
			if is_pure_sup:
				trooper.command_move(leg1, false, flank_gid)
				trooper.command_move(dest, true, dest_gid)
			else:
				trooper.command_attack_move(leg1, false, flank_gid)
				trooper.command_attack_move(dest, true, dest_gid)
		else:
			if is_pure_sup:
				trooper.command_move(dest, false, dest_gid)
			else:
				trooper.command_attack_move(dest, false, dest_gid)


func collect_staging_combat_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in ai.get_team_units(ai.ai_team):
		if not ai.is_combat_unit(u) or u == ai.scout_intel.active_scout:
			continue
		if raid_units.has(u) or defense_units.has(u):
			continue
		out.append(u)
	return out


func rally_idle_combat_to_staging(exclude_active_wave: bool = false) -> void:
	if not staging_point_valid:
		return
	var strays: Array[Unit] = []
	for u: Unit in ai.get_team_units(ai.ai_team):
		if not ai.is_combat_unit(u) or u == ai.scout_intel.active_scout:
			continue
		if raid_units.has(u) or defense_units.has(u):
			continue
		if exclude_active_wave and wave_units.has(u):
			continue
		if u.command_state == Unit.CommandState.IDLE and u.global_position.distance_to(staging_point) > 220.0:
			strays.append(u)
	if strays.is_empty():
		return
	var core_ref: Building = ai.find_ai_command_core()
	var back_pos: Vector2 = core_ref.global_position if core_ref != null else Vector2.ZERO
	var router: CommandRouter = ai.get_command_router()
	var slots: Array[Vector2] = []
	if router != null:
		slots = router.assign_group_destinations(strays, staging_point)
	var rally_gid: int = CommandRouter.allocate_move_group_id() if strays.size() > 1 else 0
	for i: int in range(strays.size()):
		var dest: Vector2 = slots[i] if i < slots.size() else staging_point
		if is_backline_support_unit(strays[i]):
			dest = compute_support_trailing_pos(dest, back_pos, 100.0)
		strays[i].command_move(dest, false, rally_gid)


func get_target_wave_size() -> int:
	var base_sz: int = ai.wave_squad_size
	if ai.is_brutal_difficulty():
		var scale_up: int = mini(3, int(floor(ai.ai_elapsed / 150.0)))
		return clampi(base_sz + scale_up, 6, 10)
	elif not ai.is_relaxed_difficulty():
		var scale_std: int = mini(2, int(floor(ai.ai_elapsed / 180.0)))
		return clampi(base_sz + scale_std, 5, 9)
	return base_sz


func compute_units_strength(units: Array[Unit]) -> float:
	var total: float = 0.0
	for u: Unit in units:
		if is_instance_valid(u) and not u.is_dead and not u.is_staffed:
			total += ai.get_unit_power_weight(u)
	return total


func get_wave_strength_ratio() -> float:
	if wave_launch_strength <= 0.01:
		return 1.0
	return compute_units_strength(wave_units) / wave_launch_strength


func is_wave_finishing_enemy_core() -> bool:
	var enemy_cores: Array[Building] = []
	for eb_var: Variant in ai.scout_intel.visible_enemy_buildings.values():
		var b: Building = eb_var as Building
		if is_instance_valid(b) and not b.is_destroyed and b.is_command_hub():
			if (b.current_hp / maxf(1.0, b.max_hp)) < 0.35:
				enemy_cores.append(b)
	if enemy_cores.is_empty():
		return false
	for u: Unit in wave_units:
		if not is_instance_valid(u) or u.is_dead:
			continue
		for ec: Building in enemy_cores:
			if u.global_position.distance_squared_to(ec.global_position) <= 320.0 * 320.0:
				return true
	return false


func find_hostile_near_squad(squad: Array[Unit], radius: float) -> Variant:
	var r_sq: float = radius * radius
	for u: Unit in squad:
		if not is_instance_valid(u) or u.is_dead:
			continue
		var nearby: Array = SpatialGrid.query_units_in_radius(u.global_position, radius) if SpatialGrid != null else []
		for item: Variant in nearby:
			if is_instance_valid(item) and item is Unit:
				var h: Unit = item as Unit
				if not h.is_dead and not h.is_staffed and ai.is_enemy_team(int(h.team)) and ai.is_combat_unit(h):
					if u.global_position.distance_squared_to(h.global_position) <= r_sq and ai.scout_intel.is_entity_visible_to_ai(h):
						return h.global_position
	return null


func _prune_unit_array(arr: Array[Unit]) -> Array[Unit]:
	var kept: Array[Unit] = []
	for u: Unit in arr:
		if is_instance_valid(u) and not u.is_dead and not u.is_staffed and not u.is_queued_for_deletion():
			kept.append(u)
	return kept


func prune_wave_units() -> void:
	wave_units = _prune_unit_array(wave_units)
	defense_units = _prune_unit_array(defense_units)
	raid_units = _prune_unit_array(raid_units)


func find_nearby_intact_barricade(origin: Vector2, max_radius: float) -> Node2D:
	var best: Node2D = null
	var best_d_sq: float = max_radius * max_radius
	for node: Node in ai.get_tree().get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if bool(node.get("is_destroyed")) or node.is_queued_for_deletion():
			continue
		var d_sq: float = origin.distance_squared_to((node as Node2D).global_position)
		if d_sq <= best_d_sq:
			best_d_sq = d_sq
			best = node as Node2D
	return best


func count_nearby_intact_barricades(origin: Vector2, max_radius: float) -> int:
	var count: int = 0
	var max_r_sq: float = max_radius * max_radius
	for node: Node in ai.get_tree().get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if bool(node.get("is_destroyed")) or node.is_queued_for_deletion():
			continue
		if origin.distance_squared_to((node as Node2D).global_position) <= max_r_sq:
			count += 1
	return count


func squad_has_anti_armor_or_siege(squad: Array[Unit]) -> bool:
	for u: Unit in squad:
		if ai.planner.is_breach_capable(u):
			return true
	return false


func recover_stalled_combat_units() -> void:
	var live_ids: Dictionary = {}
	for u: Unit in ai.get_team_units(ai.ai_team):
		if not ai.is_combat_unit(u):
			continue
		if u.is_movement_locked_by_deploy():
			continue
		var uid: int = u.get_instance_id()
		live_ids[uid] = true
		var is_traveling: bool = (
			u.command_state == Unit.CommandState.MOVING
			or (u.command_state == Unit.CommandState.ATTACK_MOVING and (u.current_target == null or not is_instance_valid(u.current_target)))
		)
		if not is_traveling:
			_unit_last_pos[uid] = u.global_position
			_unit_stall_ticks[uid] = 0
			continue
		if _unit_last_pos.has(uid):
			var prev_pos: Vector2 = _unit_last_pos[uid]
			if u.global_position.distance_to(prev_pos) < 18.0:
				var ticks: int = int(_unit_stall_ticks.get(uid, 0)) + 1
				_unit_stall_ticks[uid] = ticks
				if ticks >= 3:
					_unit_stall_ticks[uid] = 0
					var final_dest: Vector2 = staging_point if (army_state == SkirmishAICommander.ArmyState.STAGING or army_state == SkirmishAICommander.ArmyState.RETREATING) else current_attack_target
					if final_dest == Vector2.ZERO:
						final_dest = select_wave_target(wave_number, ai.find_ai_command_core())
					var to_dest: Vector2 = final_dest - u.global_position
					var dir: Vector2 = to_dest.normalized() if to_dest.length_squared() > 4.0 else Vector2.LEFT
					var side_sign: float = 1.0 if ((uid + wave_number) % 2) == 0 else -1.0
					var detour: Vector2 = u.global_position + Vector2(-dir.y, dir.x) * (150.0 * side_sign) + dir * 75.0
					detour = Vector2(
						clampf(detour.x, ai.arena_bounds.position.x + 80.0, ai.arena_bounds.end.x - 80.0),
						clampf(detour.y, ai.arena_bounds.position.y + 80.0, ai.arena_bounds.end.y - 80.0)
					)
					u.command_move(detour, false)
					if army_state == SkirmishAICommander.ArmyState.ATTACKING:
						u.command_attack_move(final_dest, true)
					else:
						u.command_move(final_dest, true)
			else:
				_unit_stall_ticks[uid] = 0
		_unit_last_pos[uid] = u.global_position

	for k: Variant in _unit_last_pos.keys():
		if not live_ids.has(k):
			_unit_last_pos.erase(k)
			_unit_stall_ticks.erase(k)


func trigger_combat_abilities() -> void:
	for u: Unit in ai.get_team_units(ai.ai_team):
		if u.data == null or u.data.abilities.is_empty():
			continue
		var has_target: bool = u.current_target != null and is_instance_valid(u.current_target)
		var dist: float = u.global_position.distance_to(u.current_target.global_position) if has_target else INF
		for ab: AbilityData in u.data.abilities:
			if ab == null or ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
				continue
			# Allied-target AOE abilities (Shield Overcharge, Luminous Mend) are handled by AbilityComponent autocast.
			if ab.ability_id == &"monolith_shield_overcharge" or ab.ability_id == &"luminous_mend":
				continue
			if not u.is_ability_ready(ab):
				continue

			if ab.ability_id == &"solar_step":
				var closing_in: bool = has_target and dist > u.get_effective_attack_range() * 0.85 and dist <= u.get_effective_attack_range() + 260.0
				var wounded_in_fight: bool = has_target and u.current_hp < u.get_max_hp() * 0.70
				if closing_in or wounded_in_fight:
					u.command_cast_ability(ab, u.global_position, u)
					break
				continue

			if ab.ability_id == &"radiant_mark":
				var best_rm: Unit = find_highest_hp_visible_hostile_unit(u.global_position, ab.cast_range)
				if best_rm != null:
					u.command_cast_ability(ab, best_rm.global_position, best_rm)
					break
				continue

			if ab.ability_id == &"focus_alignment":
				if has_target and dist <= u.get_effective_attack_range() + 45.0:
					var is_armored_or_bldg: bool = (
						(u.current_target is Building)
						or (u.current_target.is_in_group("destructible_barricades"))
						or (u.current_target is Unit and (u.current_target as Unit).data != null and (u.current_target as Unit).data.is_armored)
					)
					if is_armored_or_bldg:
						u.command_cast_ability(ab, u.global_position, u)
						break
				continue

			if ab.ability_id == &"blinding_glare":
				if has_target and dist <= ab.cast_range:
					var glare_cnt: int = count_hostile_combat_near(u.current_target.global_position, maxf(70.0, ab.aoe_radius))
					if glare_cnt >= 2:
						u.command_cast_ability(ab, u.current_target.global_position)
						break
				continue

			if ab.ability_id == &"aureole_surge":
				if has_target and dist <= u.get_effective_attack_range() + 45.0 and u.current_hp >= u.get_max_hp() * 0.50:
					u.command_cast_ability(ab, u.global_position, u)
					break
				continue

			if ab.ability_id == &"solar_convergence":
				var conv_pt: Variant = find_solar_convergence_target(u, ab.cast_range, maxf(75.0, ab.aoe_radius))
				if conv_pt is Vector2:
					u.command_cast_ability(ab, conv_pt as Vector2)
					break
				continue

			if not has_target:
				continue

			if ab.ability_id == &"kinetic_barrier":
				var low_shd: bool = u.max_shield > 0.0 and u.current_shield <= u.max_shield * 0.25
				var low_hp: bool = u.current_hp < u.get_max_hp() * 0.80
				if (low_shd or low_hp) and dist <= u.get_effective_attack_range() + 80.0:
					u.command_cast_ability(ab, u.global_position, u)
					break
				continue
			if ab.ability_id == &"grav_pulse":
				if dist <= ab.cast_range:
					var cluster_cnt: int = count_hostile_combat_near(u.current_target.global_position, maxf(60.0, ab.aoe_radius))
					if cluster_cnt >= 2:
						u.command_cast_ability(ab, u.current_target.global_position)
						break
				continue
			if ab.target_type == AbilityData.TargetType.INSTANT:
				if ab.aoe_radius > 0.0:
					if dist <= maxf(80.0, ab.aoe_radius * 0.92):
						u.command_cast_ability(ab, u.global_position, u)
						break
				elif dist <= u.get_effective_attack_range() + 45.0:
					u.command_cast_ability(ab, u.global_position, u)
					break
			elif ab.target_type == AbilityData.TargetType.POINT_AOE:
				if dist <= ab.cast_range and dist >= 100.0:
					u.command_cast_ability(ab, u.current_target.global_position)
					break
			elif ab.target_type == AbilityData.TargetType.UNIT_TARGET:
				if dist <= ab.cast_range and u.current_target is Unit:
					u.command_cast_ability(ab, u.current_target.global_position, u.current_target as Unit)
					break


func find_highest_hp_visible_hostile_unit(origin: Vector2, cast_range: float) -> Unit:
	var best: Unit = null
	var best_hp: float = -1.0
	var list: Array = SpatialGrid.query_units_in_radius(origin, cast_range + 24.0) if SpatialGrid != null else ai.get_tree().get_nodes_in_group("units")
	var r_sq: float = cast_range * cast_range
	for node: Variant in list:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var e: Unit = node as Unit
		if e.is_dead or e.is_staffed or not ai.is_enemy_team(int(e.team)):
			continue
		if e.global_position.distance_squared_to(origin) > r_sq:
			continue
		if not ai.scout_intel.is_entity_visible_to_ai(e):
			continue
		if e.has_status_effect(&"radiant_mark"):
			continue
		if e.current_hp > best_hp:
			best_hp = e.current_hp
			best = e
	return best


func find_solar_convergence_target(caster: Unit, cast_range: float, aoe_radius: float) -> Variant:
	var origin: Vector2 = caster.global_position
	var r_sq: float = cast_range * cast_range
	# 1. Active breach barricade or hostile building in cast_range (strictly visible)
	if caster.current_target != null and is_instance_valid(caster.current_target):
		if caster.current_target.is_in_group("destructible_barricades") and not bool(caster.current_target.get("is_destroyed")):
			if caster.current_target.global_position.distance_squared_to(origin) <= r_sq:
				return caster.current_target.global_position
		elif caster.current_target is Building:
			var tb: Building = caster.current_target as Building
			if not tb.is_destroyed and ai.is_enemy_team(int(tb.team)) and tb.global_position.distance_squared_to(origin) <= r_sq and ai.scout_intel.is_entity_visible_to_ai(tb):
				return tb.global_position

	# 2. Visible deployed siege units or clustered (>= 2) hostile units in cast_range
	var unit_list: Array = SpatialGrid.query_units_in_radius(origin, cast_range + 24.0) if SpatialGrid != null else ai.get_tree().get_nodes_in_group("units")
	var best_cluster_pos: Variant = null
	var best_cluster_cnt: int = 1
	for node: Variant in unit_list:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var e: Unit = node as Unit
		if e.is_dead or e.is_staffed or not ai.is_enemy_team(int(e.team)):
			continue
		if e.global_position.distance_squared_to(origin) > r_sq or not ai.scout_intel.is_entity_visible_to_ai(e):
			continue
		if e.is_deployed():
			return e.global_position
		var cnt: int = count_hostile_combat_near(e.global_position, aoe_radius)
		if cnt > best_cluster_cnt:
			best_cluster_cnt = cnt
			best_cluster_pos = e.global_position
	if best_cluster_pos is Vector2:
		return best_cluster_pos

	# 3. Any visible hostile building in cast_range (prioritize turrets/production)
	var bldg_list: Array = SpatialGrid.query_buildings_in_radius(origin, cast_range + 48.0) if SpatialGrid != null else ai.get_tree().get_nodes_in_group("buildings")
	for node: Variant in bldg_list:
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if b.is_destroyed or not ai.is_enemy_team(int(b.team)):
			continue
		if b.global_position.distance_squared_to(origin) <= r_sq and ai.scout_intel.is_entity_visible_to_ai(b):
			return b.global_position

	return null


func count_hostile_combat_near(center: Vector2, radius: float) -> int:
	var cnt: int = 0
	var list: Array = SpatialGrid.query_units_in_radius(center, radius) if SpatialGrid != null else ai.get_tree().get_nodes_in_group("units")
	var r_sq: float = radius * radius
	for node: Variant in list:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var e: Unit = node as Unit
		if e.is_dead or e.is_staffed or not ai.is_enemy_team(int(e.team)):
			continue
		if e.data != null and (e.data.can_gather or e.data.can_staff_compute):
			continue
		if e.global_position.distance_squared_to(center) <= r_sq:
			cnt += 1
	return cnt


func manage_deploy_micro(tick_dt: float) -> void:
	# Faction-agnostic Deploy/Anchor micro (e.g. Anvil Siege-Walker) consuming shared per-tick vision cache — zero map-hacking.
	var deployers: Array[Unit] = []
	for u: Unit in ai.get_team_units(ai.ai_team):
		if u.can_toggle_deploy() and u.data != null:
			deployers.append(u)
	if deployers.is_empty():
		_deploy_idle_timers.clear()
		return

	ai.scout_intel.refresh_vision_cache(false)
	var seen_enemy_units: Dictionary = ai.scout_intel.visible_enemy_units
	var seen_enemy_buildings: Dictionary = ai.scout_intel.visible_enemy_buildings

	var econ: EconomyManager = ai.get_economy_manager()
	var rail_bonus: float = econ.get_rail_range_bonus(int(ai.ai_team)) if econ != null else 0.0
	var live_dep_ids: Dictionary = {}

	for u: Unit in deployers:
		var uid: int = u.get_instance_id()
		live_dep_ids[uid] = true
		if u.is_deploy_transitioning():
			continue

		var dep_max_r: float = u.data.deployed_attack_range + (rail_bonus if u.data.unit_type_id == &"anvil_siege_walker" else 0.0)
		var dep_min_r: float = u.data.deployed_min_attack_range
		if dep_max_r <= 0.0:
			continue
		var my_r: float = u.data.collision_radius

		var has_close_threat: bool = false
		var has_deploy_target: bool = false
		var has_keep_target: bool = false
		var engage_max: float = dep_max_r * 0.92
		var keep_max: float = dep_max_r * 1.05

		for eu_var: Variant in seen_enemy_units.values():
			var eu: Unit = eu_var as Unit
			if not is_instance_valid(eu) or eu.is_dead or eu.is_staffed:
				continue
			var other_r: float = eu.data.collision_radius if eu.data != null else 16.0
			var edge_d: float = maxf(0.0, u.global_position.distance_to(eu.global_position) - my_r - other_r)
			if dep_min_r > 0.0 and edge_d < dep_min_r + 12.0:
				if eu.data == null or eu.data.attack_damage > 0.0:
					has_close_threat = true
			elif edge_d <= engage_max and edge_d >= dep_min_r + 8.0:
				has_deploy_target = true
				has_keep_target = true
			elif edge_d <= keep_max and edge_d >= dep_min_r:
				has_keep_target = true

		if not has_deploy_target or not has_keep_target:
			for eb_var: Variant in seen_enemy_buildings.values():
				var eb: Building = eb_var as Building
				if not is_instance_valid(eb) or eb.is_destroyed:
					continue
				var edge_db: float = maxf(0.0, u.global_position.distance_to(eb.global_position) - my_r - eb.footprint_radius)
				if edge_db <= engage_max and edge_db >= dep_min_r + 8.0:
					has_deploy_target = true
					has_keep_target = true
				elif edge_db <= keep_max and edge_db >= dep_min_r:
					has_keep_target = true

		if army_state == SkirmishAICommander.ArmyState.BREACHING and breach_target != null and is_instance_valid(breach_target) and not bool(breach_target.get("is_destroyed")):
			var bar_r: float = float(breach_target.call("get_footprint_radius")) if breach_target.has_method("get_footprint_radius") else 40.0
			var edge_bar: float = maxf(0.0, u.global_position.distance_to(breach_target.global_position) - my_r - bar_r)
			if edge_bar <= engage_max and edge_bar >= dep_min_r + 8.0:
				has_deploy_target = true
				has_keep_target = true
			elif edge_bar <= keep_max and edge_bar >= dep_min_r:
				has_keep_target = true

		if u.is_deployed():
			if army_state == SkirmishAICommander.ArmyState.RETREATING or has_close_threat:
				_deploy_idle_timers[uid] = 0.0
				u.request_undeploy()
			elif has_keep_target:
				_deploy_idle_timers[uid] = 0.0
			else:
				var idle_t: float = float(_deploy_idle_timers.get(uid, 0.0)) + tick_dt
				_deploy_idle_timers[uid] = idle_t
				if idle_t >= 2.5:
					_deploy_idle_timers[uid] = 0.0
					u.request_undeploy()
		else:
			_deploy_idle_timers[uid] = 0.0
			var combat_posture: bool = (
				army_state == SkirmishAICommander.ArmyState.ATTACKING
				or army_state == SkirmishAICommander.ArmyState.DEFENDING
				or army_state == SkirmishAICommander.ArmyState.BREACHING
			)
			if combat_posture and has_deploy_target and not has_close_threat:
				u.request_deploy()

	for key: Variant in _deploy_idle_timers.keys():
		if not live_dep_ids.has(key):
			_deploy_idle_timers.erase(key)


func select_wave_target(wave_idx: int, core: Building = null) -> Vector2:
	var origin: Vector2 = core.global_position if (core != null and is_instance_valid(core)) else (staging_point if staging_point_valid else Vector2.ZERO)

	# 1. Urgent Data Hyper-Uplink denial when Uplink Victory is active or an enemy holds/captures it
	var mm: Node = ai.get_tree().get_first_node_in_group("match_manager")
	if mm != null and mm.has_method("get_uplink_victory_status"):
		var vst: Dictionary = mm.call("get_uplink_victory_status") as Dictionary
		if bool(vst.get("enabled", false)) and bool(vst.get("has_uplink", false)):
			var ctrl_t: int = int(vst.get("controlling_team", -1))
			var lead_t: int = int(vst.get("leading_team", -1))
			var lead_s: float = float(vst.get("leading_seconds", 0.0))
			var target_s: float = maxf(1.0, float(vst.get("target_seconds", 180.0)))
			var enemy_holds_now: bool = ctrl_t >= 0 and ai.is_enemy_team(ctrl_t)
			var enemy_timer_urgent: bool = lead_t >= 0 and ai.is_enemy_team(lead_t) and lead_s >= target_s * 0.40
			if enemy_holds_now or enemy_timer_urgent:
				return vst.get("uplink_pos", Vector2.ZERO) as Vector2

	var uplink: HyperUplink = ai.get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if uplink != null and is_instance_valid(uplink):
		var enemy_controls_uplink: bool = uplink.controlling_team >= 0 and ai.is_enemy_team(uplink.controlling_team)
		var enemy_capturing_uplink: bool = uplink.capturing_team >= 0 and ai.is_enemy_team(uplink.capturing_team) and uplink.capture_progress > 0.35
		var allied_controls_uplink: bool = uplink.controlling_team >= 0 and ai.is_allied_team(uplink.controlling_team)
		if enemy_controls_uplink or enemy_capturing_uplink:
			return uplink.global_position
		if (wave_idx % 2) == 1 and not allied_controls_uplink:
			return uplink.global_position

	# 2. Fair Fog-Respecting Visible Enemy Buildings (Command Hubs / production first — zero map-hacking!)
	ai.scout_intel.refresh_vision_cache(false)
	var best_vis_bldg: Building = null
	var best_vis_score: float = INF
	for eb_var: Variant in ai.scout_intel.visible_enemy_buildings.values():
		var b: Building = eb_var as Building
		if not is_instance_valid(b) or b.is_destroyed:
			continue
		var score: float = origin.distance_to(b.global_position)
		if b.is_command_hub():
			score -= 600.0
		elif b.is_military_production_building():
			score -= 260.0
		if uplink != null and (uplink.controlling_team == int(b.team) or (uplink.capturing_team == int(b.team) and uplink.capture_progress > 0.40)):
			score -= 480.0
		if score < best_vis_score:
			best_vis_score = score
			best_vis_bldg = b
	if best_vis_bldg != null:
		return best_vis_bldg.global_position

	# 2.5. Scouted last-known enemy base coordinates (only if not yet cleared while visible)
	var scouted_base: Vector2 = ai.scout_intel.scouted_intel.get("last_known_enemy_base", Vector2.INF) as Vector2
	if scouted_base != Vector2.INF:
		if not ai.scout_intel.is_world_pos_visible_to_ai(scouted_base):
			return scouted_base
		ai.scout_intel.scouted_intel["last_known_enemy_base"] = Vector2.INF

	# 3. Unexplored Map Spawn Anchors / Opposing Arena Quadrants (fair scouting sweeps!)
	var friendly_hubs: Array[Vector2] = []
	for node: Node in ai.get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var fb: Building = node as Building
			if not fb.is_destroyed and fb.is_command_hub() and ai.is_allied_team(int(fb.team)):
				friendly_hubs.append(fb.global_position)

	var sweep_points: Array[Vector2] = []
	for a_node: Node in ai.get_tree().get_nodes_in_group("spawn_anchors"):
		if is_instance_valid(a_node) and a_node is Node2D:
			sweep_points.append((a_node as Node2D).global_position)
	if sweep_points.is_empty():
		var half: Vector2 = ai.arena_bounds.size * 0.34
		var ctr: Vector2 = ai.arena_bounds.get_center()
		sweep_points = [
			ctr + Vector2(-half.x, -half.y),
			ctr + Vector2(half.x, -half.y),
			ctr + Vector2(half.x, half.y),
			ctr + Vector2(-half.x, half.y),
		]

	var candidate_anchors: Array[Vector2] = []
	var now: float = ai.ai_elapsed
	for sp: Vector2 in sweep_points:
		var is_friendly_base: bool = false
		for fh_pos: Vector2 in friendly_hubs:
			if sp.distance_squared_to(fh_pos) <= 520.0 * 520.0:
				is_friendly_base = true
				break
		if is_friendly_base:
			continue
		var sp_key: String = "%d,%d" % [int(round(sp.x / 64.0)), int(round(sp.y / 64.0))]
		if ai.scout_intel.is_world_pos_visible_to_ai(sp):
			_cleared_anchor_times[sp_key] = now
			continue
		var cleared_at: float = float(_cleared_anchor_times.get(sp_key, -999.0))
		if (now - cleared_at) < 60.0:
			continue
		candidate_anchors.append(sp)

	if not candidate_anchors.is_empty():
		candidate_anchors.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return origin.distance_squared_to(a) < origin.distance_squared_to(b)
		)
		var chosen_a: Vector2 = candidate_anchors[_sweep_anchor_index % candidate_anchors.size()]
		_sweep_anchor_index += 1
		return chosen_a

	# 4. Visible Enemy Units Fallback (strictly from shared vision cache)
	var nearest_u: Unit = null
	var nearest_u_d_sq: float = INF
	for eu_var: Variant in ai.scout_intel.visible_enemy_units.values():
		var u: Unit = eu_var as Unit
		if is_instance_valid(u) and not u.is_dead and not u.is_staffed:
			var d_sq: float = origin.distance_squared_to(u.global_position)
			if d_sq < nearest_u_d_sq:
				nearest_u_d_sq = d_sq
				nearest_u = u
	if nearest_u != null:
		return nearest_u.global_position

	return ai.arena_bounds.get_center()


func get_flank_corridor_waypoint(north_lane: bool) -> Vector2:
	var best_pos: Vector2 = Vector2(-80.0, -810.0) if north_lane else Vector2(80.0, 810.0)
	for node: Node in ai.get_tree().get_nodes_in_group("map_landmarks"):
		if not (node is MapLandmarkScript) or not is_instance_valid(node):
			continue
		var lm: MapLandmarkScript = node
		if lm.visual_style != MapLandmarkScript.VisualStyle.RELAY_ARCH:
			continue
		if north_lane and lm.global_position.y < -200.0:
			return lm.global_position
		if not north_lane and lm.global_position.y > 200.0:
			return lm.global_position
	return best_pos


func get_debug_status_line(_core: Building) -> String:
	var tag: String = TeamManager.get_team_short_label(int(ai.ai_team), false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("T%d" % (int(ai.ai_team) + 1))
	var state_str: String = "STAGING"
	match army_state:
		SkirmishAICommander.ArmyState.ATTACKING:
			state_str = "ATTACKING"
		SkirmishAICommander.ArmyState.DEFENDING:
			state_str = "DEFENDING"
		SkirmishAICommander.ArmyState.RETREATING:
			state_str = "RETREATING"
		SkirmishAICommander.ArmyState.BREACHING:
			state_str = "BREACHING"
	var count_str: String = ""
	if army_state == SkirmishAICommander.ArmyState.STAGING:
		count_str = " (%d/%d)" % [last_staging_count, get_target_wave_size()]
	elif army_state == SkirmishAICommander.ArmyState.ATTACKING or army_state == SkirmishAICommander.ArmyState.RETREATING or army_state == SkirmishAICommander.ArmyState.BREACHING:
		var pct: int = int(round(get_wave_strength_ratio() * 100.0))
		count_str = " (%d | %d%%)" % [wave_units.size(), pct]
	var econ_goal: String = ai.economy.last_macro_goal if ai.economy != null else "BOOT"
	return "AI [%s]: %s%s | R:%d D:%d | INTEL:%s | ECON:%s" % [
		tag,
		state_str,
		count_str,
		raid_units.size(),
		defense_units.size(),
		String(ai.scout_intel.active_counter_posture),
		econ_goal,
	]
