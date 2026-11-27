class_name AIEconomyManager
extends RefCounted

var ai: SkirmishAICommander = null

var hub_data: BuildingData = null
var refinery_data: BuildingData = null
var supply_data: BuildingData = null
var compute_hub_data: BuildingData = null
var turret_data: BuildingData = null
var barracks_t1_data: BuildingData = null
var counter_foundry_data: BuildingData = null
var heavy_t2_data: BuildingData = null
var worker_data: UnitData = null
var harvester_data: UnitData = null
var engineer_data: UnitData = null

var last_macro_goal: String = "BOOT"

var _vat_production_counter: int = 0
var _foundry_production_counter: int = 0
var _fab_production_counter: int = 0
var _tier2_transmission_sent: bool = false
var _last_block_warn_ms: Dictionary = {}
var _under_pressure_until: float = 0.0
var _worker_evac_until: Dictionary = {}


func setup(owner_ai: SkirmishAICommander) -> void:
	ai = owner_ai


func note_base_pressure(duration: float = 75.0) -> void:
	if ai != null:
		_under_pressure_until = maxf(_under_pressure_until, ai.ai_elapsed + duration)


func bind_from_planner(planner: AIBuildPlanner) -> void:
	if planner == null:
		return
	hub_data = planner.get_building_for_role(&"hub")
	refinery_data = planner.get_building_for_role(&"refinery")
	supply_data = planner.get_building_for_role(&"supply")
	compute_hub_data = planner.get_building_for_role(&"compute_hub")
	turret_data = planner.get_building_for_role(&"turret")
	barracks_t1_data = planner.get_building_for_role(&"barracks_t1")
	counter_foundry_data = planner.get_building_for_role(&"counter_foundry")
	heavy_t2_data = planner.get_building_for_role(&"heavy_t2")
	worker_data = planner.get_unit_for_role(&"worker")
	harvester_data = planner.get_unit_for_role(&"harvester")
	engineer_data = planner.get_unit_for_role(&"engineer")


func collect_safe_salvage(core: Building) -> void:
	if ai == null or core == null or not is_instance_valid(core) or not ai.is_inside_tree():
		return

	var candidate_cores: Array[Node2D] = []
	var seen_ids: Dictionary = {}
	var search_anchors: Array[Dictionary] = [
		{"pos": core.global_position, "r": 950.0},
	]
	if ai.army.staging_point_valid:
		search_anchors.append({"pos": ai.army.staging_point, "r": 950.0})
	if not ai.army.wave_units.is_empty():
		var centroid: Vector2 = Vector2.ZERO
		var cnt: int = 0
		for wu: Unit in ai.army.wave_units:
			if is_instance_valid(wu) and not wu.is_dead:
				centroid += wu.global_position
				cnt += 1
		if cnt > 0:
			search_anchors.append({"pos": centroid / float(cnt), "r": 450.0})

	for anchor: Dictionary in search_anchors:
		var a_pos: Vector2 = anchor["pos"] as Vector2
		var a_r: float = float(anchor["r"])
		var found: Array = SpatialGrid.query_salvage_in_radius(a_pos, a_r) if SpatialGrid != null else ai.get_tree().get_nodes_in_group("salvage_cores")
		for item: Variant in found:
			if not is_instance_valid(item) or not (item is Node2D):
				continue
			var sc: Node2D = item as Node2D
			if bool(sc.get("is_claimed")) or sc.is_queued_for_deletion():
				continue
			if sc.global_position.distance_squared_to(a_pos) > a_r * a_r:
				continue
			var sid: int = sc.get_instance_id()
			if not seen_ids.has(sid):
				seen_ids[sid] = true
				candidate_cores.append(sc)

	if candidate_cores.is_empty():
		return

	var target_core: Node2D = null
	var best_d_sq: float = INF
	for sc: Node2D in candidate_cores:
		if is_salvage_already_claimed_by_ally(sc):
			continue
		if not ai.scout_intel.is_spot_safe(sc.global_position, 360.0, true):
			continue
		var d_sq: float = core.global_position.distance_squared_to(sc.global_position)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			target_core = sc

	if target_core == null:
		return

	# Pick 1 available fast specialist (engineer) or 1 worker (never pulling below 3 primary gatherers)
	var salvage_ids: Array[StringName] = ai.planner.get_salvage_unit_ids()
	var team_units: Array[Unit] = ai.get_team_units(ai.ai_team)
	var primary_gatherers: int = 0
	var best_engineer: Unit = null
	var best_eng_d_sq: float = INF
	var best_worker: Unit = null
	var best_wrk_d_sq: float = INF

	for u: Unit in team_units:
		if u.data == null:
			continue
		var is_primary_worker: bool = u.data.can_gather and not u.data.auto_gather_on_spawn
		var is_specialist: bool = u.data.can_staff_compute or u.data.has_tag(&"engineer")
		if is_primary_worker and u.command_state == Unit.CommandState.GATHERING:
			primary_gatherers += 1
		if not u.can_salvage_core():
			continue
		if not salvage_ids.is_empty() and not salvage_ids.has(u.get_unit_type_id()):
			continue
		if u.command_state == Unit.CommandState.CONSTRUCTING or u.command_state == Unit.CommandState.SALVAGING or u.command_state == Unit.CommandState.STAFFING_BUILDING:
			continue
		if not u.command_queue.is_empty():
			continue
		var d_sq: float = u.global_position.distance_squared_to(target_core.global_position)
		if is_specialist and u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_eng_d_sq:
				best_eng_d_sq = d_sq
				best_engineer = u
		elif is_primary_worker:
			if u.command_state == Unit.CommandState.IDLE:
				if d_sq < best_wrk_d_sq:
					best_wrk_d_sq = d_sq
					best_worker = u
			elif u.command_state == Unit.CommandState.GATHERING:
				if u.gather_component != null and u.gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and u.is_carrying_cargo():
					continue
				if d_sq < best_wrk_d_sq:
					best_wrk_d_sq = d_sq
					best_worker = u

	if best_engineer != null:
		best_engineer.command_salvage(target_core)
		return
	if best_worker != null:
		if best_worker.command_state == Unit.CommandState.IDLE or primary_gatherers > 3:
			best_worker.command_salvage(target_core)


func is_salvage_already_claimed_by_ally(sc: Node2D) -> bool:
	for node: Node in ai.get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node as Unit
		if u.is_dead or u.is_staffed or not ai.is_allied_team(int(u.team)):
			continue
		if u.command_state == Unit.CommandState.SALVAGING and u.active_command.get("target", null) == sc:
			return true
		for cmd: Dictionary in u.command_queue:
			if cmd.get("type", &"") == &"salvage" and cmd.get("target", null) == sc:
				return true
	return false


func assign_idle_workers(core: Building) -> void:
	var constructed_hubs: Array[Building] = []
	for b: Building in ai.get_team_buildings(ai.ai_team):
		if b.is_constructed and not b.is_destroyed and b.is_command_hub():
			constructed_hubs.append(b)
	if constructed_hubs.is_empty() and core != null:
		constructed_hubs.append(core)

	# Build per-hub local Biomass anchors so multi-hub economies saturate both main and natural expansions cleanly.
	var hub_clusters: Array[Dictionary] = []
	for hub: Building in constructed_hubs:
		var local_bio: Array[ResourceNode] = ai.get_resources_near(hub.global_position, &"biomass", 620.0)
		if local_bio.is_empty():
			continue
		var closest_bio: ResourceNode = local_bio[0]
		var closest_d_sq: float = hub.global_position.distance_squared_to(closest_bio.global_position)
		for rn: ResourceNode in local_bio:
			var d_sq: float = hub.global_position.distance_squared_to(rn.global_position)
			if d_sq < closest_d_sq:
				closest_d_sq = d_sq
				closest_bio = rn
		hub_clusters.append({
			"hub": hub,
			"anchor": closest_bio,
			"nodes": local_bio,
		})

	var fallback_biomass: Array[ResourceNode] = []
	if hub_clusters.is_empty():
		fallback_biomass = ai.get_resources_near(core.global_position, &"biomass", 3000.0)
		if fallback_biomass.is_empty():
			return

	for unit: Unit in ai.get_team_units(ai.ai_team):
		if unit.data == null or not unit.data.can_gather or unit.data.auto_gather_on_spawn:
			continue
		if unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo():
				continue

		var best_node: ResourceNode = null
		if not hub_clusters.is_empty():
			# Sort hubs by proximity to this idle worker; pick the nearest hub cluster that has an unsaturated slot.
			var ordered: Array[Dictionary] = hub_clusters.duplicate()
			ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ha: Building = a["hub"] as Building
				var hb: Building = b["hub"] as Building
				return unit.global_position.distance_squared_to(ha.global_position) < unit.global_position.distance_squared_to(hb.global_position)
			)
			for entry: Dictionary in ordered:
				var c_nodes: Array[ResourceNode] = entry["nodes"] as Array[ResourceNode]
				var has_free: bool = false
				for rn: ResourceNode in c_nodes:
					if rn.has_free_slot(int(ai.ai_team)):
						has_free = true
						break
				if has_free:
					best_node = ResourceNode.pick_best_cluster_node(entry["anchor"] as ResourceNode, unit, int(ai.ai_team), 560.0, 950.0)
					if best_node != null:
						break
			if best_node == null:
				# All owned hub clusters saturated -> distribute evenly across all local nodes
				var all_hub_nodes: Array[ResourceNode] = []
				for entry: Dictionary in ordered:
					for rn: ResourceNode in (entry["nodes"] as Array[ResourceNode]):
						if not all_hub_nodes.has(rn):
							all_hub_nodes.append(rn)
				best_node = ai.pick_least_crowded_resource(unit.global_position, all_hub_nodes)
		else:
			best_node = ResourceNode.pick_best_cluster_node(fallback_biomass[0], unit, int(ai.ai_team), 520.0, 1400.0)
			if best_node == null:
				best_node = ai.pick_least_crowded_resource(unit.global_position, fallback_biomass)

		if best_node != null:
			best_node.assign_worker(unit)
			unit.command_gather(best_node)


func assign_idle_harvesters() -> void:
	var silica_nodes: Array[ResourceNode] = []
	for b: Building in ai.get_team_buildings(ai.ai_team):
		if b.is_constructed and not b.is_command_hub() and b.accepts_resource(&"silica"):
			for rn: ResourceNode in ai.get_resources_near(b.global_position, &"silica", 520.0):
				if not silica_nodes.has(rn):
					silica_nodes.append(rn)
	for unit: Unit in ai.get_team_units(ai.ai_team):
		if unit.data == null or not unit.data.can_gather or not unit.data.auto_gather_on_spawn:
			continue
		if unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo():
				continue
		var anchor_vein: ResourceNode = silica_nodes[0] if not silica_nodes.is_empty() else ai.find_nearest_resource(unit.global_position, &"silica")
		var vein: ResourceNode = ResourceNode.pick_best_cluster_node(anchor_vein, unit, int(ai.ai_team), 480.0, 1400.0) if anchor_vein != null else null
		if vein == null:
			vein = anchor_vein
		if vein != null:
			vein.assign_worker(unit)
			unit.command_gather(vein)


func assign_idle_engineers() -> void:
	var open_mainframes: Array[Building] = []
	for b: Building in ai.get_team_buildings(ai.ai_team):
		if b.is_constructed and b.max_staff_slots > 0 and b.get_assigned_engineer_count() < b.max_staff_slots:
			open_mainframes.append(b)
	if open_mainframes.is_empty():
		return
	for unit: Unit in ai.get_team_units(ai.ai_team):
		if not unit.can_staff_compute() or unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		for mf: Building in open_mainframes:
			if mf.can_accept_staff(unit):
				unit.command_staff_building(mf)
				break


func evacuate_harassed_workers(core: Building) -> void:
	if ai == null or core == null or not is_instance_valid(core) or not ai.is_inside_tree():
		return
	var now: float = ai.ai_elapsed
	var friendly_hubs: Array[Building] = []
	for b: Building in ai.get_team_buildings(ai.ai_team):
		if b.is_constructed and not b.is_destroyed and b.is_command_hub():
			friendly_hubs.append(b)
	if friendly_hubs.is_empty():
		friendly_hubs.append(core)

	var safe_bounds: Rect2 = ai.arena_bounds.grow(-48.0)
	var live_ids: Dictionary = {}
	for u: Unit in ai.get_team_units(ai.ai_team):
		if u.data == null or not u.data.can_gather or u.data.auto_gather_on_spawn:
			continue
		var uid: int = u.get_instance_id()
		live_ids[uid] = true
		if u.command_state != Unit.CommandState.GATHERING and u.command_state != Unit.CommandState.IDLE:
			continue
		if now < float(_worker_evac_until.get(uid, 0.0)):
			continue
		var wounded: bool = u.current_hp < u.get_max_hp() * 0.85
		var scan_r: float = 240.0 if wounded else 170.0
		var near_hostile: Unit = null
		var best_d_sq: float = scan_r * scan_r
		var nearby: Array = SpatialGrid.query_units_in_radius(u.global_position, scan_r) if SpatialGrid != null else []
		for item: Variant in nearby:
			if not is_instance_valid(item) or not (item is Unit):
				continue
			var h: Unit = item as Unit
			if h.is_dead or h.is_staffed or not ai.is_enemy_team(int(h.team)) or not ai.is_combat_unit(h):
				continue
			if not ai.scout_intel.is_entity_visible_to_ai(h):
				continue
			var d_sq: float = u.global_position.distance_squared_to(h.global_position)
			if d_sq <= best_d_sq:
				best_d_sq = d_sq
				near_hostile = h
		if near_hostile == null:
			continue
		# Pick safest friendly Command Hub (farthest from hostile)
		var safest_hub: Building = friendly_hubs[0]
		var best_hub_d_sq: float = -1.0
		for fh: Building in friendly_hubs:
			var hd_sq: float = fh.global_position.distance_squared_to(near_hostile.global_position)
			if hd_sq > best_hub_d_sq:
				best_hub_d_sq = hd_sq
				safest_hub = fh
		var away: Vector2 = (u.global_position - near_hostile.global_position).normalized()
		if away.length_squared() < 0.01:
			away = Vector2.RIGHT
		var to_hub: Vector2 = (safest_hub.global_position - u.global_position).normalized()
		var flee_dir: Vector2 = (away * 0.65 + to_hub * 0.35).normalized()
		if flee_dir.length_squared() < 0.01:
			flee_dir = away
		var evac_pos: Vector2 = u.global_position + flee_dir * 210.0
		if safe_bounds.has_area():
			evac_pos.x = clampf(evac_pos.x, safe_bounds.position.x, safe_bounds.end.x)
			evac_pos.y = clampf(evac_pos.y, safe_bounds.position.y, safe_bounds.end.y)
		u.command_move(evac_pos, false)
		_worker_evac_until[uid] = now + 4.0

	for k: Variant in _worker_evac_until.keys():
		if not live_ids.has(k):
			_worker_evac_until.erase(k)


func manage_base_repairs() -> void:
	if ai == null or ai.is_relaxed_difficulty() or not ai.is_inside_tree():
		return
	var econ: EconomyManager = ai.get_economy_manager()
	if econ == null:
		return
	if econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS) < 60 or econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA) < 30:
		return

	var team_units: Array[Unit] = ai.get_team_units(ai.ai_team)
	var already_repaired_ids: Dictionary = {}
	var primary_gatherers: int = 0
	for u: Unit in team_units:
		if u.data != null and u.data.can_gather and not u.data.auto_gather_on_spawn and u.command_state == Unit.CommandState.GATHERING:
			primary_gatherers += 1
		if u.command_state == Unit.CommandState.REPAIRING and u.repair_component != null:
			var r_tgt: Variant = u.repair_component.get("target_entity")
			if r_tgt is Node and is_instance_valid(r_tgt):
				already_repaired_ids[(r_tgt as Node).get_instance_id()] = true

	var best_target: Node2D = null
	var best_ratio: float = 1.0
	for b: Building in ai.get_team_buildings(ai.ai_team):
		if not b.is_constructed or b.is_destroyed or b.is_salvaging:
			continue
		if not (b.is_command_hub() or b.is_military_production_building() or b.has_turret):
			continue
		var ratio_b: float = b.current_hp / maxf(1.0, b.max_hp)
		if ratio_b >= 0.80 or already_repaired_ids.has(b.get_instance_id()):
			continue
		if not ai.scout_intel.is_spot_safe(b.global_position, 240.0, true):
			continue
		if ratio_b < best_ratio:
			best_ratio = ratio_b
			best_target = b

	if best_target == null:
		for u_h: Unit in team_units:
			if u_h.data == null or not u_h.data.is_heavy_unit():
				continue
			if not (u_h.data.has_tag(&"mechanical") or u_h.data.has_tag(&"synthetic")):
				continue
			if u_h.command_state != Unit.CommandState.IDLE:
				continue
			var ratio_u: float = u_h.current_hp / maxf(1.0, u_h.get_max_hp())
			if ratio_u >= 0.75 or already_repaired_ids.has(u_h.get_instance_id()):
				continue
			if not ai.scout_intel.is_spot_safe(u_h.global_position, 240.0, true):
				continue
			if ratio_u < best_ratio:
				best_ratio = ratio_u
				best_target = u_h

	if best_target == null:
		return

	var best_idle_rep: Unit = null
	var best_idle_d_sq: float = INF
	var best_gather_rep: Unit = null
	var best_gather_d_sq: float = INF
	for u: Unit in team_units:
		if not u.can_repair():
			continue
		if u.command_state == Unit.CommandState.CONSTRUCTING or u.command_state == Unit.CommandState.SALVAGING or u.command_state == Unit.CommandState.REPAIRING or u.command_state == Unit.CommandState.STAFFING_BUILDING:
			continue
		if not u.command_queue.is_empty():
			continue
		var d_sq: float = u.global_position.distance_squared_to(best_target.global_position)
		if u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_idle_d_sq:
				best_idle_d_sq = d_sq
				best_idle_rep = u
		elif u.command_state == Unit.CommandState.GATHERING and primary_gatherers > 3 and u.data != null and not u.data.auto_gather_on_spawn:
			if d_sq < best_gather_d_sq:
				best_gather_d_sq = d_sq
				best_gather_rep = u

	var chosen_rep: Unit = best_idle_rep if best_idle_rep != null else best_gather_rep
	if chosen_rep != null:
		chosen_rep.command_repair(best_target, false)


func _can_spend_unreserved(biomass: int, silica: int, compute: int, cost: Dictionary, res_b: int, res_s: int, res_c: int) -> bool:
	var need_b: int = int(cost.get(EconomyManager.RESOURCE_BIOMASS, 0))
	var need_s: int = int(cost.get(EconomyManager.RESOURCE_SILICA, 0))
	var need_c: int = int(cost.get(EconomyManager.RESOURCE_COMPUTE, 0))
	return (biomass - res_b) >= need_b and (silica - res_s) >= need_s and (compute - res_c) >= need_c


func _reserve_building_cost(bdata: BuildingData, res: Dictionary) -> void:
	if bdata == null:
		return
	res["b"] = int(res["b"]) + maxi(0, bdata.biomass_cost)
	res["s"] = int(res["s"]) + maxi(0, bdata.silica_cost)
	res["c"] = int(res["c"]) + maxi(0, bdata.compute_cost)


func _warn_build_blocked(data: BuildingData, reason: String) -> void:
	if data == null or ai == null:
		return
	var key: String = "%s:%s" % [String(data.building_id), reason]
	var now_ms: int = Time.get_ticks_msec()
	var prev_ms: int = int(_last_block_warn_ms.get(key, -999999))
	if (now_ms - prev_ms) < 30000:
		return
	_last_block_warn_ms[key] = now_ms
	push_warning("AI [Team %d] blocked placing '%s' (reason=%s)." % [int(ai.ai_team) + 1, String(data.building_id), reason])


func resume_unfinished_buildings() -> void:
	for b: Building in ai.get_team_buildings(ai.ai_team):
		if b.is_destroyed or b.is_constructed:
			continue
		if has_worker_building(b):
			continue
		var worker: Unit = find_available_worker(b.global_position)
		if worker != null:
			worker.command_construct_building(b)


func manage_economy_and_production(econ: EconomyManager, core: Building) -> void:
	var buildings: Array[Building] = ai.get_team_buildings(ai.ai_team)
	var units: Array[Unit] = ai.get_team_units(ai.ai_team)

	var worker_count: int = 0
	var harvester_count: int = 0
	var engineer_count: int = 0
	for u: Unit in units:
		if u.data == null:
			continue
		if u.data.can_gather and not u.data.auto_gather_on_spawn:
			worker_count += 1
		elif u.data.can_gather and u.data.auto_gather_on_spawn:
			harvester_count += 1
		elif u.data.can_staff_compute:
			engineer_count += 1

	var command_hubs: Array[Building] = []
	var constructed_hubs: Array[Building] = []
	var refineries: Array[Building] = []
	var constructed_refineries: Array[Building] = []
	var constructed_refinery: Building = null
	var compute_hubs: Array[Building] = []
	var constructed_compute_hubs: Array[Building] = []
	var constructed_compute_hub: Building = null
	var barracks_list: Array[Building] = []
	var constructed_barracks: Array[Building] = []
	var foundries: Array[Building] = []
	var constructed_foundries: Array[Building] = []
	var heavy_plants: Array[Building] = []
	var constructed_heavy_plants: Array[Building] = []
	var turrets: Array[Building] = []
	var unfinished_supply: int = 0
	var staffed_engineers: int = 0
	var total_compute_slots: int = 0

	for b: Building in buildings:
		if b.is_command_hub():
			command_hubs.append(b)
			if b.is_constructed:
				constructed_hubs.append(b)
		elif ai.planner.is_role_building(b, &"refinery"):
			refineries.append(b)
			if b.is_constructed:
				constructed_refineries.append(b)
				constructed_refinery = b
		elif ai.planner.is_role_building(b, &"compute_hub"):
			compute_hubs.append(b)
			if b.is_constructed:
				constructed_compute_hubs.append(b)
				constructed_compute_hub = b
				staffed_engineers += b.get_assigned_engineer_count()
				total_compute_slots += b.max_staff_slots
		elif ai.planner.is_role_building(b, &"turret"):
			turrets.append(b)
		elif ai.planner.is_role_building(b, &"barracks_t1"):
			barracks_list.append(b)
			if b.is_constructed:
				constructed_barracks.append(b)
		elif ai.planner.is_role_building(b, &"counter_foundry"):
			foundries.append(b)
			if b.is_constructed:
				constructed_foundries.append(b)
		elif ai.planner.is_role_building(b, &"heavy_t2"):
			heavy_plants.append(b)
			if b.is_constructed:
				constructed_heavy_plants.append(b)
		elif ai.planner.is_role_building(b, &"supply") and not b.is_constructed:
			unfinished_supply += 1

	var queued_workers: int = ai.count_queued_unit_type(buildings, worker_data.unit_type_id) if worker_data != null else 0
	var queued_harvesters: int = ai.count_queued_unit_type(buildings, harvester_data.unit_type_id) if harvester_data != null else 0
	var queued_engineers: int = ai.count_queued_unit_type(buildings, engineer_data.unit_type_id) if engineer_data != null else 0
	var total_workers: int = worker_count + queued_workers
	var total_harvesters: int = harvester_count + queued_harvesters
	var total_engineers: int = engineer_count + staffed_engineers + queued_engineers

	var bw_used: int = econ.get_bandwidth_used(ai.ai_team)
	var bw_cap: int = econ.get_bandwidth_cap(ai.ai_team)
	var needs_supply: bool = (bw_used >= bw_cap - 4) and unfinished_supply == 0 and bw_cap < ai.max_bandwidth_cap
	var biomass: int = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
	var silica: int = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
	var compute: int = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	var is_swarm_rush: bool = (ai.ai_playstyle == int(GameConfig.AIPlaystyle.SWARM_RUSH)) if GameConfig != null else false
	var is_synth_tech: bool = (ai.ai_playstyle == int(GameConfig.AIPlaystyle.SYNTHETICS_TECH)) if GameConfig != null else false
	var is_brutal: bool = ai.is_brutal_difficulty()
	var counter_strength: float = ai.scout_intel.get_counter_reaction_strength()
	var active_posture: StringName = ai.scout_intel.active_counter_posture
	var rally_pt: Vector2 = ai.army.staging_point if ai.army.staging_point_valid else core.global_position.lerp(Vector2.ZERO, 0.34)
	var reserved: Dictionary = {"b": 0, "s": 0, "c": 0}
	var goal_set: bool = false

	# Priority 0: Emergency Supply Unblock (always precedes worker training when at/near cap, never deadlocks).
	if needs_supply and supply_data != null and bw_used >= bw_cap - 1:
		if econ.can_afford(ai.ai_team, supply_data.get_cost_dict()):
			var away_em: Vector2 = (core.global_position - Vector2.ZERO).normalized()
			if away_em.length_squared() < 0.01:
				away_em = Vector2.RIGHT
			if try_place_and_build(supply_data, core.global_position + away_em * 125.0, core.global_position) != null:
				unfinished_supply += 1
				needs_supply = false
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
		else:
			_reserve_building_cost(supply_data, reserved)
		if not goal_set:
			last_macro_goal = "SUPPLY"
			goal_set = true

	# Priority 1: Ensure baseline worker core (3 early on Swarm Rush, 4 baseline) without hard-returning.
	var early_workers: int = 3 if is_swarm_rush else 4
	if total_workers < early_workers and worker_data != null:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(worker_data):
			if _can_spend_unreserved(biomass, silica, compute, worker_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
				if core.queue_unit_data(worker_data):
					total_workers += 1
					biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
					silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
					compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
					if not goal_set:
						last_macro_goal = "WORKERS"
						goal_set = true

	# Priority 1.2: Universal Hub Silica Bootstrapping (fixes MONOLITH_OS 50S vs 60S Smelter deadlock & future factions!).
	var early_silica_needed: bool = (
		(refinery_data != null and silica < refinery_data.silica_cost)
		or (barracks_t1_data != null and silica < barracks_t1_data.silica_cost)
		or (supply_data != null and silica < supply_data.silica_cost)
	)
	var core_trains_harvester: bool = (
		harvester_data != null
		and core.accepts_resource(&"silica")
		and core.can_train_unit_data(harvester_data)
	)
	if total_harvesters < 1 and core_trains_harvester and (early_silica_needed or total_workers >= early_workers):
		if core.get_training_queue_size() < 2 and core.queue_unit_data(harvester_data):
			total_harvesters += 1
			biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
			silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
			compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
			if not goal_set:
				last_macro_goal = "SILICA_BOOT"
				goal_set = true

	# Priority 1.5 (Proactive Power Lattice Recovery — non-blocking for any power-grid faction):
	if supply_data != null and supply_data.provides_power_grid and supply_data.power_radius > 0.0:
		var unpowered_bldg: Building = null
		for b_chk: Building in buildings:
			if b_chk.is_constructed and not b_chk.is_destroyed and b_chk.requires_power_grid and not b_chk.is_powered:
				unpowered_bldg = b_chk
				break
		if unpowered_bldg != null:
			var recovery_r: float = supply_data.power_radius * 0.95
			var recovery_in_progress: bool = false
			for b_p: Building in buildings:
				if not b_p.is_destroyed and not b_p.is_constructed and b_p.provides_power_grid:
					if b_p.global_position.distance_to(unpowered_bldg.global_position) <= recovery_r:
						recovery_in_progress = true
						break
			if not recovery_in_progress:
				if econ.can_afford(ai.ai_team, supply_data.get_cost_dict()):
					var to_core_dir: Vector2 = (core.global_position - unpowered_bldg.global_position).normalized()
					if to_core_dir.length_squared() < 0.01:
						to_core_dir = Vector2.RIGHT
					var recovery_offset: float = minf(115.0, supply_data.power_radius * 0.58)
					var recovery_anchor: Vector2 = unpowered_bldg.global_position + to_core_dir * recovery_offset
					if try_place_and_build(supply_data, recovery_anchor, unpowered_bldg.global_position) != null:
						unfinished_supply += 1
						needs_supply = false
						biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
						silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
						compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
					else:
						_reserve_building_cost(supply_data, reserved)
				else:
					_reserve_building_cost(supply_data, reserved)
				if not goal_set:
					last_macro_goal = "POWER"
					goal_set = true

	# Swarm Rush prioritizes its first Tier-1 Barracks before the Refinery via non-blocking reservation.
	if is_swarm_rush and barracks_list.is_empty() and barracks_t1_data != null and ai.planner.are_prerequisites_met(barracks_t1_data, econ, int(ai.ai_team)):
		if _can_spend_unreserved(biomass, silica, compute, barracks_t1_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var to_c_rush: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var rush_b: Building = try_place_and_build(barracks_t1_data, core.global_position + to_c_rush * 175.0, core.global_position)
			if rush_b != null:
				rush_b.set_rally_position(rally_pt)
				barracks_list.append(rush_b)
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
			else:
				_reserve_building_cost(barracks_t1_data, reserved)
		else:
			_reserve_building_cost(barracks_t1_data, reserved)
		if not goal_set:
			last_macro_goal = "RUSH_T1"
			goal_set = true

	# Priority 2: Build Silica Refinery near nearest Silica Vein (non-blocking reservation!).
	if refineries.is_empty() and refinery_data != null and ai.planner.are_prerequisites_met(refinery_data, econ, int(ai.ai_team)):
		if _can_spend_unreserved(biomass, silica, compute, refinery_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var vein: ResourceNode = ai.find_nearest_resource(core.global_position, &"silica")
			var anchor: Vector2 = core.global_position.lerp(vein.global_position, 0.58) if vein != null else (core.global_position + Vector2(-120.0, 180.0))
			var built_ref: Building = try_place_and_build(refinery_data, anchor, core.global_position)
			if built_ref != null:
				refineries.append(built_ref)
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
			else:
				_reserve_building_cost(refinery_data, reserved)
		else:
			_reserve_building_cost(refinery_data, reserved)
		if not goal_set:
			last_macro_goal = "REFINERY"
			goal_set = true

	# Priority 3: Expand Bandwidth cap via Supply Provider before hitting population block (non-blocking!).
	if needs_supply and supply_data != null and ai.planner.are_prerequisites_met(supply_data, econ, int(ai.ai_team)):
		if _can_spend_unreserved(biomass, silica, compute, supply_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var away_dir: Vector2 = (core.global_position - Vector2.ZERO).normalized()
			if away_dir.length_squared() < 0.01:
				away_dir = Vector2.RIGHT
			var supply_anchor: Vector2 = core.global_position + away_dir * 125.0
			if try_place_and_build(supply_data, supply_anchor, core.global_position) != null:
				unfinished_supply += 1
				needs_supply = false
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
			else:
				_reserve_building_cost(supply_data, reserved)
		else:
			_reserve_building_cost(supply_data, reserved)
		if not goal_set:
			last_macro_goal = "SUPPLY"
			goal_set = true

	# Priority 4: Train automated Harvesters from Refinery OR Universal Command Hub (respects faction saturation bonuses).
	var per_vein_cap: int = 2
	var ref_origin: Vector2 = constructed_refinery.global_position if constructed_refinery != null else core.global_position
	var near_vein: ResourceNode = ai.find_nearest_resource(ref_origin, &"silica")
	if near_vein != null:
		per_vein_cap = maxi(2, near_vein.get_effective_max_harvesters(int(ai.ai_team)))
	var desired_harvesters: int = 1
	if constructed_refineries.size() >= 2:
		desired_harvesters = mini(6, per_vein_cap * 2) if is_brutal else mini(5, per_vein_cap + 1)
	elif is_brutal:
		desired_harvesters = maxi(3, per_vein_cap)
	elif constructed_barracks.size() >= 1 or constructed_refinery != null:
		desired_harvesters = per_vein_cap
	var can_hub_harvest: bool = constructed_refinery != null or core.accepts_resource(&"silica")
	if harvester_data != null and can_hub_harvest and total_harvesters < desired_harvesters:
		var trainer: Building = constructed_refinery if (constructed_refinery != null and constructed_refinery.can_train_unit_data(harvester_data)) else (core if core.accepts_resource(&"silica") else null)
		if trainer != null and trainer.get_training_queue_size() < 2 and trainer.can_train_unit_data(harvester_data):
			var allow_harv_spend: bool = (total_harvesters == 0) or _can_spend_unreserved(biomass, silica, compute, harvester_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"]))
			if allow_harv_spend and trainer.queue_unit_data(harvester_data):
				total_harvesters += 1
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
				if not goal_set:
					last_macro_goal = "HARVESTERS"
					goal_set = true

	# Priority 5: Construct primary Tier-1 Barracks facing the map center (non-blocking reservation!).
	if barracks_list.is_empty() and barracks_t1_data != null and ai.planner.are_prerequisites_met(barracks_t1_data, econ, int(ai.ai_team)):
		if _can_spend_unreserved(biomass, silica, compute, barracks_t1_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var to_center: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var vat_anchor: Vector2 = core.global_position + to_center * 175.0
			var built_vat: Building = try_place_and_build(barracks_t1_data, vat_anchor, core.global_position)
			if built_vat != null:
				built_vat.set_rally_position(rally_pt)
				barracks_list.append(built_vat)
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
			else:
				_reserve_building_cost(barracks_t1_data, reserved)
		else:
			_reserve_building_cost(barracks_t1_data, reserved)
		if not goal_set:
			last_macro_goal = "BARRACKS"
			goal_set = true

	# Priority 6: Saturate workers across all owned Command Hubs (scales +4 workers per expansion hub).
	var max_workers_cap: int = 8 if ai.is_relaxed_difficulty() else (16 if is_brutal else 12)
	var eff_target_workers: int = mini(max_workers_cap, ai.target_worker_count + 4 * maxi(0, constructed_hubs.size() - 1))
	if worker_data != null and total_workers < eff_target_workers:
		var sorted_hubs: Array[Building] = []
		if not constructed_hubs.is_empty():
			sorted_hubs = constructed_hubs.duplicate()
		elif core != null:
			sorted_hubs.append(core)
		sorted_hubs.sort_custom(func(a: Building, b: Building) -> bool:
			return a.get_training_queue_size() < b.get_training_queue_size()
		)
		for hub_t: Building in sorted_hubs:
			if total_workers >= eff_target_workers:
				break
			if hub_t.get_training_queue_size() < 2 and hub_t.can_train_unit_data(worker_data):
				if _can_spend_unreserved(biomass, silica, compute, worker_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
					if hub_t.queue_unit_data(worker_data):
						total_workers += 1
						biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
						silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
						compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Priority 6.5: 2nd & 3rd Expansion Command Hubs.
	if hub_data != null and not barracks_list.is_empty() and not refineries.is_empty():
		var main_bio_ratio: float = get_main_biomass_ratio(core)
		if command_hubs.size() < 2:
			var exp_time_gate: float = 150.0 if is_brutal else (270.0 if ai.is_relaxed_difficulty() else 195.0)
			var hub_buffer: int = 40 if is_brutal else 90
			if (ai.ai_elapsed >= exp_time_gate or main_bio_ratio < 0.35) and (biomass - int(reserved["b"])) >= (hub_data.biomass_cost + hub_buffer):
				if _can_spend_unreserved(biomass, silica, compute, hub_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
					var exp_spot: Vector2 = find_natural_expansion_hub_spot(core, hub_data)
					if exp_spot != Vector2.INF and try_place_and_build(hub_data, exp_spot, exp_spot) != null:
						biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
						silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
						compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
						if not goal_set:
							last_macro_goal = "EXPAND_2"
							goal_set = true
		elif command_hubs.size() < 3 and not ai.is_relaxed_difficulty():
			if (ai.ai_elapsed >= 390.0 or main_bio_ratio < 0.25) and (biomass - int(reserved["b"])) >= (hub_data.biomass_cost + 140):
				if _can_spend_unreserved(biomass, silica, compute, hub_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
					var exp3_spot: Vector2 = find_natural_expansion_hub_spot(core, hub_data)
					if exp3_spot != Vector2.INF and try_place_and_build(hub_data, exp3_spot, exp3_spot) != null:
						biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
						silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
						compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
						if not goal_set:
							last_macro_goal = "EXPAND_3"
							goal_set = true

	# Priority 7: Compute Hubs on natural, expansion, and safe surging Geothermal Compute Vents + Engineers.
	var exp_vent_biomass: int = 160 if (is_synth_tech or is_brutal) else 220
	if (not constructed_barracks.is_empty() or is_synth_tech) and compute_hub_data != null:
		if compute_hubs.is_empty():
			var vent: ResourceNode = find_nearest_unoccupied_vent(core.global_position, 580.0, true)
			if vent != null and _can_spend_unreserved(biomass, silica, compute, compute_hub_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
				if try_place_and_build_on_vent(compute_hub_data, vent) != null:
					biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
					silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
					compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
					if not goal_set:
						last_macro_goal = "COMPUTE"
						goal_set = true
		elif compute_hubs.size() < 3 and constructed_compute_hubs.size() >= 1 and staffed_engineers >= 1 and (biomass - int(reserved["b"])) >= exp_vent_biomass:
			var surge_vent: ResourceNode = find_nearest_surging_safe_vent(core.global_position, 2200.0)
			if surge_vent != null and _can_spend_unreserved(biomass, silica, compute, compute_hub_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
				if try_place_and_build_on_vent(compute_hub_data, surge_vent) != null:
					biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
					silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
					compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
			elif compute_hubs.size() == 1:
				var exp_vent: ResourceNode = find_nearest_unoccupied_vent(core.global_position, 1650.0, true)
				if exp_vent != null and _can_spend_unreserved(biomass, silica, compute, compute_hub_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
					if try_place_and_build_on_vent(compute_hub_data, exp_vent) != null:
						biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
						silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
						compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	var desired_engineers: int = mini(6, total_compute_slots)
	if constructed_compute_hub != null and engineer_data != null and total_engineers < desired_engineers:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(engineer_data):
			if _can_spend_unreserved(biomass, silica, compute, engineer_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
				if core.queue_unit_data(engineer_data):
					biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
					silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
					compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Priority 7.2: Adaptive Static Defense Turrets (1 per expansion + 1-2 extra under pressure/anti-swarm; capped aggressively).
	var under_pressure: bool = ai.ai_elapsed < _under_pressure_until
	var turret_enabled: bool = (not ai.is_relaxed_difficulty()) or under_pressure
	var max_turrets: int = mini(6, maxi(2, command_hubs.size() * 2))
	if turret_enabled and turret_data != null and not constructed_barracks.is_empty() and turrets.size() < max_turrets:
		if ai.planner.are_prerequisites_met(turret_data, econ, int(ai.ai_team)) and _can_spend_unreserved(biomass, silica, compute, turret_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var reactive_extra: bool = under_pressure or active_posture == &"ANTI_SWARM"
			for hub_d: Building in constructed_hubs:
				var is_main_hub: bool = (hub_d == core)
				var desired_here: int = (2 if (under_pressure and active_posture == &"ANTI_SWARM") else (1 if reactive_extra else 0)) if is_main_hub else (2 if reactive_extra else 1)
				if desired_here <= 0:
					continue
				var local_turrets: int = 0
				for t_b: Building in turrets:
					if is_instance_valid(t_b) and not t_b.is_destroyed and t_b.global_position.distance_squared_to(hub_d.global_position) <= 380.0 * 380.0:
						local_turrets += 1
				if local_turrets < desired_here:
					var fwd_dir: Vector2 = (Vector2.ZERO - hub_d.global_position).normalized()
					if fwd_dir.length_squared() < 0.01:
						fwd_dir = Vector2.RIGHT
					var side_dir: Vector2 = Vector2(-fwd_dir.y, fwd_dir.x)
					var side_off: float = 0.0 if local_turrets == 0 else (95.0 if (local_turrets % 2 == 1) else -95.0)
					var t_anchor: Vector2 = hub_d.global_position + fwd_dir * 165.0 + side_dir * side_off
					var built_t: Building = try_place_and_build(turret_data, t_anchor, hub_d.global_position)
					if built_t != null:
						turrets.append(built_t)
						biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
						silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
						compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
						if not goal_set:
							last_macro_goal = "TURRET"
							goal_set = true
						break

	# Priority 7.5: Expand Silica economy to expansion cluster once Tier-1 is established.
	var exp_cond_biomass: int = 180 if is_brutal else 240
	if refineries.size() < 2 and not constructed_refineries.is_empty() and not constructed_barracks.is_empty() and (biomass - int(reserved["b"])) >= exp_cond_biomass and refinery_data != null:
		if _can_spend_unreserved(biomass, silica, compute, refinery_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var exp_vein: ResourceNode = find_expansion_silica_vein(core.global_position, refineries)
			if exp_vein != null:
				var exp_anchor: Vector2 = exp_vein.global_position.lerp(core.global_position, 0.16)
				if try_place_and_build(refinery_data, exp_anchor, exp_vein.global_position) != null:
					biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
					silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
					compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Priority 8: Mid-game Upgrades at Tier-1 Production (faction-driven upgrade order).
	if not constructed_barracks.is_empty():
		var primary_barracks: Building = constructed_barracks[0]
		if primary_barracks.production_component != null and primary_barracks.get_training_queue_size() < 2:
			var next_t1_upg: UpgradeData = ai.planner.choose_next_upgrade_for_building(primary_barracks)
			if next_t1_upg != null and _can_spend_unreserved(biomass, silica, compute, next_t1_upg.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
				if primary_barracks.production_component.enqueue_upgrade(primary_barracks, next_t1_upg):
					biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
					silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
					compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Reactive Counter Foundry priority when ANTI_ARMOR intel is active.
	var urgent_anti_armor_foundry: bool = (active_posture == &"ANTI_ARMOR" and counter_strength >= 0.70)
	if urgent_anti_armor_foundry and foundries.is_empty() and constructed_compute_hub != null and counter_foundry_data != null and silica >= counter_foundry_data.silica_cost:
		if _can_spend_unreserved(biomass, silica, compute, counter_foundry_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var to_c_aa: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_aa: Vector2 = Vector2(-to_c_aa.y, to_c_aa.x)
			var built_aa: Building = try_place_and_build(counter_foundry_data, core.global_position + to_c_aa * 160.0 + perp_aa * 145.0, core.global_position)
			if built_aa != null:
				built_aa.set_rally_position(rally_pt)
				foundries.append(built_aa)
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
				if not goal_set:
					last_macro_goal = "COUNTER"
					goal_set = true

	# Priority 9: Late-game Tier-2 Heavy Production.
	if heavy_plants.is_empty() and heavy_t2_data != null and ai.planner.are_prerequisites_met(heavy_t2_data, econ, int(ai.ai_team)) and compute >= heavy_t2_data.compute_cost:
		if _can_spend_unreserved(biomass, silica, compute, heavy_t2_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var to_center_f: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_f: Vector2 = Vector2(-to_center_f.y, to_center_f.x)
			var fab_anchor: Vector2 = core.global_position + to_center_f * 165.0 - perp_f * 145.0
			var built_fab: Building = try_place_and_build(heavy_t2_data, fab_anchor, core.global_position)
			if built_fab != null:
				built_fab.set_rally_position(rally_pt)
				heavy_plants.append(built_fab)
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
				if not goal_set:
					last_macro_goal = "TECH_T2"
					goal_set = true

	# Priority 10: Mid-game Counter Foundry for specialized counter tech (and Tier-2 prerequisites like Ballistics Lab -> Siege Gantry).
	var t2_needs_foundry: bool = (
		heavy_t2_data != null
		and counter_foundry_data != null
		and heavy_t2_data.get_prerequisite_ids().has(counter_foundry_data.building_id)
	)
	var allow_foundry: bool = (not is_synth_tech or not heavy_plants.is_empty() or urgent_anti_armor_foundry or t2_needs_foundry)
	if allow_foundry and foundries.is_empty() and constructed_compute_hub != null and counter_foundry_data != null and silica >= counter_foundry_data.silica_cost:
		if _can_spend_unreserved(biomass, silica, compute, counter_foundry_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var to_center_cf: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_cf: Vector2 = Vector2(-to_center_cf.y, to_center_cf.x)
			var cf_anchor: Vector2 = core.global_position + to_center_cf * 160.0 + perp_cf * 145.0
			var built_cf: Building = try_place_and_build(counter_foundry_data, cf_anchor, core.global_position)
			if built_cf != null:
				built_cf.set_rally_position(rally_pt)
				foundries.append(built_cf)
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
				if not goal_set:
					last_macro_goal = "FOUNDRY"
					goal_set = true

	# Priority 11: Tier-2 Heavy Production mix (faction-weighted + reactive intel).
	for heavy_b: Building in constructed_heavy_plants:
		if not heavy_b.has_rally():
			heavy_b.set_rally_position(rally_pt)
		if heavy_b.get_training_queue_size() >= 2:
			continue
		var t2_upg: UpgradeData = ai.planner.choose_next_upgrade_for_building(heavy_b)
		if t2_upg != null and heavy_b.production_component != null and _can_spend_unreserved(biomass, silica, compute, t2_upg.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			if heavy_b.production_component.enqueue_upgrade(heavy_b, t2_upg):
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
				continue
		var heavy_choice: UnitData = ai.planner.choose_unit_for_building(heavy_b, ai.ai_playstyle, active_posture, counter_strength, _fab_production_counter)
		if heavy_choice != null and heavy_b.can_train_unit_data(heavy_choice) and _can_spend_unreserved(biomass, silica, compute, heavy_choice.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			if heavy_b.queue_unit_data(heavy_choice):
				_fab_production_counter += 1
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Priority 12: Counter Foundry production & tech upgrades (biased by intel & playstyle).
	for foundry: Building in constructed_foundries:
		if not foundry.has_rally():
			foundry.set_rally_position(rally_pt)
		if foundry.get_training_queue_size() >= 2:
			continue
		var foundry_upg: UpgradeData = ai.planner.choose_next_upgrade_for_building(foundry)
		if foundry_upg != null and foundry.production_component != null and _can_spend_unreserved(biomass, silica, compute, foundry_upg.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			if foundry.production_component.enqueue_upgrade(foundry, foundry_upg):
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)
				continue
		var foundry_choice: UnitData = ai.planner.choose_unit_for_building(foundry, ai.ai_playstyle, active_posture, counter_strength, _foundry_production_counter)
		if foundry_choice != null and foundry.can_train_unit_data(foundry_choice) and _can_spend_unreserved(biomass, silica, compute, foundry_choice.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			if foundry.queue_unit_data(foundry_choice):
				_foundry_production_counter += 1
				biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
				silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
				compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Priority 13: Tier-1 core army production (weighted by playstyle + reactive intel).
	var hold_for_t2: bool = is_synth_tech and heavy_plants.is_empty() and constructed_compute_hub != null and compute >= 15
	if not hold_for_t2:
		for bar: Building in constructed_barracks:
			if not bar.has_rally():
				bar.set_rally_position(rally_pt)
			if bar.get_training_queue_size() >= 2:
				continue
			var chosen: UnitData = ai.planner.choose_unit_for_building(bar, ai.ai_playstyle, active_posture, counter_strength, _vat_production_counter)
			if chosen != null and bar.can_train_unit_data(chosen) and _can_spend_unreserved(biomass, silica, compute, chosen.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
				if bar.queue_unit_data(chosen):
					_vat_production_counter += 1
					biomass = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_BIOMASS)
					silica = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_SILICA)
					compute = econ.get_resource(ai.ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Priority 14: Additional Tier-1 Barracks when floating surplus Biomass.
	var extra_vat_biomass: int = 200 if is_swarm_rush else (230 if is_brutal else 280)
	var extra_vat_silica: int = 40 if is_swarm_rush else 60
	if barracks_t1_data != null and barracks_list.size() < ai.max_cloning_vats and (biomass - int(reserved["b"])) >= extra_vat_biomass and (silica - int(reserved["s"])) >= extra_vat_silica:
		if _can_spend_unreserved(biomass, silica, compute, barracks_t1_data.get_cost_dict(), int(reserved["b"]), int(reserved["s"]), int(reserved["c"])):
			var to_center2: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp: Vector2 = Vector2(-to_center2.y, to_center2.x)
			var vat_anchor2: Vector2 = core.global_position + to_center2 * 180.0 + perp * 130.0
			var second_vat: Building = try_place_and_build(barracks_t1_data, vat_anchor2, core.global_position)
			if second_vat != null:
				second_vat.set_rally_position(rally_pt)

	if not goal_set:
		last_macro_goal = "T2_ARMY" if not constructed_heavy_plants.is_empty() else ("ARMY" if not constructed_barracks.is_empty() else "ECON")


func manage_overclock_macro() -> void:
	# Faction-agnostic Core Overclock macro: any hub with can_cast_overclock() boosts the highest-priority active producer.
	var ai_buildings: Array[Building] = ai.get_team_buildings(ai.ai_team)
	var ready_hubs: Array[Building] = []
	for b: Building in ai_buildings:
		if b.is_constructed and not b.is_destroyed and b.can_cast_overclock():
			ready_hubs.append(b)
	if ready_hubs.is_empty():
		return

	for hub: Building in ready_hubs:
		var best_target: Building = null
		var best_score: float = -1.0
		for cand: Building in ai_buildings:
			if not cand.is_constructed or cand.is_destroyed or cand.is_overclocked():
				continue
			if cand.production_component == null or cand.get_training_queue_size() <= 0:
				continue
			var score: float = 0.0
			if ai.planner.is_role_building(cand, &"heavy_t2") or (cand.is_military_production_building() and cand.get_tech_tier() >= 2):
				score = 400.0
			elif ai.planner.is_role_building(cand, &"counter_foundry"):
				score = 300.0
			elif ai.planner.is_role_building(cand, &"barracks_t1") or cand.is_military_production_building():
				score = 200.0
			elif cand.is_command_hub():
				score = 100.0
			else:
				score = 150.0
			var active_st: Dictionary = cand.get_active_training_status()
			if active_st.get("kind", ProductionComponent.KIND_UNIT) == ProductionComponent.KIND_UPGRADE:
				score += 65.0
			score += float(cand.get_training_queue_size()) * 12.0
			if score > best_score:
				best_score = score
				best_target = cand
		if best_target != null:
			hub.cast_overclock_on(best_target)


func try_place_and_build(data: BuildingData, preferred_pos: Vector2, fallback_origin: Vector2) -> Building:
	var econ: EconomyManager = ai.get_economy_manager()
	if econ == null or data == null or data.resolve_scene() == null:
		return null
	if not ai.planner.are_prerequisites_met(data, econ, int(ai.ai_team)):
		_warn_build_blocked(data, "prereq")
		return null
	if not econ.can_afford(ai.ai_team, data.get_cost_dict()):
		return null

	var worker: Unit = find_available_worker(preferred_pos)
	if worker == null:
		_warn_build_blocked(data, "no_worker")
		return null

	var spot: Vector2 = find_valid_build_position(data, preferred_pos, fallback_origin)
	if spot == Vector2.INF:
		if data.requires_power_grid and ai.planner != null:
			var power_data: BuildingData = ai.planner.get_power_provider_building()
			if power_data != null and power_data != data and econ.can_afford(ai.ai_team, power_data.get_cost_dict()):
				var p_spot: Vector2 = find_valid_build_position(power_data, preferred_pos, fallback_origin)
				if p_spot != Vector2.INF and econ.spend_resources(ai.ai_team, power_data.get_cost_dict()):
					return instantiate_ai_building(power_data, p_spot, worker, null)
		_warn_build_blocked(data, "no_spot")
		return null

	if not econ.spend_resources(ai.ai_team, data.get_cost_dict()):
		return null

	return instantiate_ai_building(data, spot, worker, null)


func try_place_and_build_on_vent(data: BuildingData, vent: ResourceNode) -> Building:
	var econ: EconomyManager = ai.get_economy_manager()
	if econ == null or data == null or data.resolve_scene() == null or vent == null or not is_instance_valid(vent) or vent.is_occupied():
		return null
	if not econ.can_afford(ai.ai_team, data.get_cost_dict()):
		return null
	var worker: Unit = find_available_worker(vent.global_position)
	if worker == null:
		return null
	if not econ.spend_resources(ai.ai_team, data.get_cost_dict()):
		return null
	return instantiate_ai_building(data, vent.global_position, worker, vent)


func instantiate_ai_building(data: BuildingData, spot: Vector2, worker: Unit, vent: ResourceNode) -> Building:
	var scene_root: Node = ai.get_tree().current_scene
	var buildings_container: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if buildings_container == null:
		buildings_container = ai.get_parent()
	if buildings_container == null:
		return null

	var building_scene: PackedScene = data.resolve_scene()
	if building_scene == null:
		return null
	var instance: Node = building_scene.instantiate()
	if not (instance is Building):
		instance.queue_free()
		return null

	var new_building: Building = instance
	new_building.global_position = spot
	new_building.is_constructed = false
	buildings_container.add_child(new_building)
	new_building.begin_construction(data, ai.ai_team, vent)
	if not new_building.construction_completed.is_connected(on_ai_building_completed):
		new_building.construction_completed.connect(on_ai_building_completed)
	ai.nudge_units_out_of_building(new_building)

	worker.command_construct_building(new_building)
	return new_building


func on_ai_building_completed(building: Building) -> void:
	if ai == null or not is_instance_valid(ai) or not ai.is_inside_tree():
		return
	if building == null or not is_instance_valid(building) or building.is_destroyed:
		return
	if not building.destroyed.is_connected(on_ai_building_destroyed_radio):
		building.destroyed.connect(on_ai_building_destroyed_radio)
	if building.is_command_hub():
		var near_exp_bio: ResourceNode = ai.find_nearest_resource(building.global_position, &"biomass")
		if near_exp_bio != null and near_exp_bio.global_position.distance_to(building.global_position) <= 620.0:
			building.set_rally_target(near_exp_bio)
		var primary_core: Building = ai.find_ai_command_core()
		ai.army.compute_staging_point(primary_core if primary_core != null else building)
		ai.army.sync_military_rallies()
	elif ai.is_military_production_building(building) and ai.army.staging_point_valid:
		building.set_rally_position(ai.army.staging_point)
	var is_heavy_t2: bool = (
		(heavy_t2_data != null and building.building_type_id == heavy_t2_data.building_id)
		or (building.get_tech_tier() >= 2 and building.is_military_production_building())
	)
	if not _tier2_transmission_sent and is_heavy_t2:
		_tier2_transmission_sent = true
		ai.try_emit_ai_transmission(&"tier2_online", Vector2.INF)


func on_ai_building_destroyed_radio(building: Building) -> void:
	if ai == null or not is_instance_valid(ai) or not ai.is_inside_tree():
		return
	if building == null or not is_instance_valid(building):
		return
	note_base_pressure()
	ai.try_emit_ai_transmission(&"under_attack", ai.sanitize_transmission_pos(building.global_position, false))


func find_valid_build_position(data: BuildingData, preferred_pos: Vector2, fallback_origin: Vector2) -> Vector2:
	if data != null and data.requires_power_grid and ai.is_inside_tree():
		var footprint_r: float = data.get_footprint_radius()
		var providers: Array[Building] = []
		for node: Node in ai.get_tree().get_nodes_in_group("buildings"):
			if not (node is Building) or not is_instance_valid(node):
				continue
			var b: Building = node as Building
			if b.is_destroyed or not b.is_constructed or b.is_salvaging or int(b.team) != int(ai.ai_team):
				continue
			if b.provides_power_grid and b.power_radius > footprint_r + 24.0:
				providers.append(b)
		if providers.is_empty():
			return Vector2.INF
		providers.sort_custom(func(a: Building, b: Building) -> bool:
			return a.global_position.distance_squared_to(preferred_pos) < b.global_position.distance_squared_to(preferred_pos)
		)
		var p_steps: int = 16
		for prov: Building in providers:
			var max_r: float = maxf(prov.footprint_radius + footprint_r + 18.0, prov.power_radius - footprint_r - 12.0)
			var min_r: float = prov.footprint_radius + footprint_r + 16.0
			var ring_radii: PackedFloat32Array = PackedFloat32Array([
				min_r,
				lerpf(min_r, max_r, 0.45),
				lerpf(min_r, max_r, 0.80),
				max_r,
			])
			for r: float in ring_radii:
				if r > prov.power_radius - 6.0:
					continue
				for k: int in range(p_steps):
					var angle: float = TAU * float(k) / float(p_steps)
					var candidate: Vector2 = prov.global_position + Vector2.RIGHT.rotated(angle) * r
					if is_build_spot_valid(data, candidate):
						return candidate
		return Vector2.INF

	var anchors: Array[Vector2] = [preferred_pos, fallback_origin]
	var radii: PackedFloat32Array = PackedFloat32Array([0.0, 75.0, 125.0, 175.0, 230.0, 290.0, 355.0, 420.0])
	var angle_steps: int = 16

	for anchor: Vector2 in anchors:
		for r: float in radii:
			if r <= 0.1:
				if is_build_spot_valid(data, anchor):
					return anchor
				continue
			for k: int in range(angle_steps):
				var angle: float = TAU * float(k) / float(angle_steps)
				var candidate: Vector2 = anchor + Vector2.RIGHT.rotated(angle) * r
				if is_build_spot_valid(data, candidate):
					return candidate
	return Vector2.INF


func is_build_spot_valid(data: BuildingData, world_pos: Vector2) -> bool:
	var router: CommandRouter = ai.get_command_router()
	if router != null:
		var eval: Dictionary = router.evaluate_build_placement(data, world_pos, ai.ai_team)
		return bool(eval.get("valid", false))

	var half: Vector2 = data.footprint_size * 0.5
	var safe_bounds: Rect2 = Rect2(
		ai.arena_bounds.position + half + Vector2(8.0, 8.0),
		ai.arena_bounds.size - data.footprint_size - Vector2(16.0, 16.0)
	)
	if not safe_bounds.has_point(world_pos):
		return false
	var new_radius: float = data.get_footprint_radius()
	for node: Node in ai.get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.overlaps_circle(world_pos, new_radius + 8.0):
				return false
	for node: Node in ai.get_tree().get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.overlaps_circle(world_pos, new_radius + 8.0):
				return false
	for node: Node in ai.get_tree().get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(node) and not bool(node.get("is_destroyed")) and node.has_method("overlaps_circle"):
			if node.call("overlaps_circle", world_pos, new_radius + 8.0):
				return false
	for node: Node in ai.get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node) and not (node as Building).is_destroyed:
			var min_d: float = (node as Building).footprint_radius + new_radius + 10.0
			if (node as Building).global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	for node: Node in ai.get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if rn.is_depleted() or rn.is_vent:
				continue
			var min_d: float = rn.collision_radius + new_radius + 8.0
			if rn.global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	if data.requires_power_grid and not Building.is_position_powered_for_team(ai.get_tree(), world_pos, int(ai.ai_team)):
		return false
	return true


func get_main_biomass_ratio(core: Building) -> float:
	if core == null or not is_instance_valid(core):
		return 1.0
	var local_bio: Array[ResourceNode] = ai.get_resources_near(core.global_position, &"biomass", 520.0)
	if local_bio.is_empty():
		return 0.0
	var rem_sum: float = 0.0
	var max_sum: float = 0.0
	for rn: ResourceNode in local_bio:
		rem_sum += float(maxi(0, rn.remaining_amount))
		max_sum += float(maxi(1, rn.max_amount))
	return rem_sum / maxf(1.0, max_sum)


func find_natural_expansion_hub_spot(core: Building, exp_hub_data: BuildingData) -> Vector2:
	if core == null or not is_instance_valid(core) or exp_hub_data == null or not ai.is_inside_tree():
		return Vector2.INF

	var friendly_hubs: Array[Vector2] = []
	var visible_enemy_hubs: Array[Vector2] = []
	for node: Node in ai.get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node as Building
		if b.is_destroyed or not b.is_command_hub():
			continue
		if ai.is_allied_team(int(b.team)):
			friendly_hubs.append(b.global_position)
		elif ai.is_enemy_team(int(b.team)) and ai.scout_intel.is_entity_visible_to_ai(b):
			visible_enemy_hubs.append(b.global_position)

	var candidates: Array[ResourceNode] = []
	for node: Node in ai.get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.is_depleted() or rn.is_vent or rn.resource_type != &"biomass":
			continue
		var too_close_friendly: bool = false
		for fh: Vector2 in friendly_hubs:
			if rn.global_position.distance_to(fh) < 460.0:
				too_close_friendly = true
				break
		if too_close_friendly:
			continue
		var too_close_enemy: bool = false
		for eh: Vector2 in visible_enemy_hubs:
			if rn.global_position.distance_to(eh) < 520.0:
				too_close_enemy = true
				break
		if too_close_enemy:
			continue
		candidates.append(rn)

	if candidates.is_empty():
		return Vector2.INF

	# Group candidate Biomass nodes into local clusters (320 px radius)
	var visited: Dictionary = {}
	var clusters: Array[Dictionary] = []
	for seed_rn: ResourceNode in candidates:
		var sid: int = seed_rn.get_instance_id()
		if visited.has(sid):
			continue
		var group: Array[ResourceNode] = [seed_rn]
		visited[sid] = true
		for other_rn: ResourceNode in candidates:
			var oid: int = other_rn.get_instance_id()
			if visited.has(oid):
				continue
			if seed_rn.global_position.distance_to(other_rn.global_position) <= 320.0:
				group.append(other_rn)
				visited[oid] = true
		var centroid: Vector2 = Vector2.ZERO
		var hy_count: int = 0
		for rn_g: ResourceNode in group:
			centroid += rn_g.global_position
			if rn_g.is_high_yield:
				hy_count += 1
		centroid /= float(group.size())
		if not ai.scout_intel.is_spot_safe(centroid, 440.0, true):
			continue
		var dist_core: float = core.global_position.distance_to(centroid)
		# Favor >= 2 node clusters and apply a modest tie-breaker for safe high-yield clusters
		var cluster_score: float = dist_core - (220.0 if group.size() >= 2 else 0.0) - (110.0 if hy_count > 0 else 0.0)
		clusters.append({
			"centroid": centroid,
			"score": cluster_score,
		})

	if clusters.is_empty():
		return Vector2.INF

	clusters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"])
	)

	for cl: Dictionary in clusters:
		var centroid: Vector2 = cl["centroid"] as Vector2
		var inward_target: Vector2 = core.global_position.lerp(Vector2.ZERO, 0.35)
		var inward_dir: Vector2 = (inward_target - centroid).normalized()
		if inward_dir.length_squared() < 0.01:
			inward_dir = (-centroid).normalized() if centroid.length_squared() > 16.0 else Vector2.RIGHT
		var anchor: Vector2 = centroid + inward_dir * 185.0
		var valid_spot: Vector2 = find_valid_build_position(exp_hub_data, anchor, centroid)
		if valid_spot != Vector2.INF:
			return valid_spot

	return Vector2.INF


func find_nearest_surging_safe_vent(origin: Vector2, max_radius: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = max_radius * max_radius
	for node: Node in ai.get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node as ResourceNode
			if not rn.is_vent or rn.is_occupied() or not rn.is_surging():
				continue
			var d_sq: float = origin.distance_squared_to(rn.global_position)
			if d_sq <= best_d_sq and ai.scout_intel.is_spot_safe(rn.global_position, 440.0, true):
				best_d_sq = d_sq
				best = rn
	return best


func find_nearest_unoccupied_vent(origin: Vector2, max_radius: float, prioritize_surging: bool = false) -> ResourceNode:
	var best: ResourceNode = null
	var best_score: float = INF
	var max_r_sq: float = max_radius * max_radius
	for node: Node in ai.get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if not rn.is_vent or rn.is_occupied():
				continue
			var d_sq: float = origin.distance_squared_to(rn.global_position)
			if d_sq > max_r_sq:
				continue
			var score: float = sqrt(d_sq)
			if prioritize_surging and rn.is_surging() and ai.scout_intel.is_spot_safe(rn.global_position, 440.0, true):
				score -= 1000.0
			if score < best_score:
				best_score = score
				best = rn
	return best


func find_expansion_silica_vein(core_pos: Vector2, existing_condensers: Array[Building]) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = INF
	var min_sep_sq: float = 420.0 * 420.0
	for node: Node in ai.get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted() or rn.is_vent or rn.resource_type != &"silica":
			continue
		var too_close: bool = false
		for cond: Building in existing_condensers:
			if is_instance_valid(cond) and cond.global_position.distance_squared_to(rn.global_position) < min_sep_sq:
				too_close = true
				break
		if too_close:
			continue
		var d_sq: float = core_pos.distance_squared_to(rn.global_position)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best = rn
	return best


func find_available_worker(near_pos: Vector2) -> Unit:
	var best_idle: Unit = null
	var best_idle_d_sq: float = INF
	var best_gathering: Unit = null
	var best_gather_d_sq: float = INF
	var best_returning: Unit = null
	var best_ret_d_sq: float = INF

	for u: Unit in ai.get_team_units(ai.ai_team):
		if not u.can_construct():
			continue
		if u.command_state == Unit.CommandState.CONSTRUCTING or u.command_state == Unit.CommandState.SALVAGING:
			continue
		if not u.command_queue.is_empty():
			continue
		var d_sq: float = u.global_position.distance_squared_to(near_pos)
		if u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_idle_d_sq:
				best_idle_d_sq = d_sq
				best_idle = u
		elif u.command_state == Unit.CommandState.GATHERING:
			if u.gather_component != null and u.gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and u.is_carrying_cargo():
				if d_sq < best_ret_d_sq:
					best_ret_d_sq = d_sq
					best_returning = u
				continue
			if d_sq < best_gather_d_sq:
				best_gather_d_sq = d_sq
				best_gathering = u

	if best_idle != null:
		return best_idle
	if best_gathering != null:
		return best_gathering
	return best_returning


func has_worker_building(target_b: Building) -> bool:
	for u: Unit in ai.get_team_units(ai.ai_team):
		if u.command_state == Unit.CommandState.CONSTRUCTING and u._construction_target == target_b:
			return true
		for queued_cmd: Dictionary in u.command_queue:
			if queued_cmd.get("type", &"") == &"build" and queued_cmd.get("target", null) == target_b:
				return true
	return false
