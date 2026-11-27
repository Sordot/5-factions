class_name BoxSelectionResolver
extends RefCounted


static func circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var clamped: Vector2 = Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y)
	)
	return center.distance_squared_to(clamped) <= radius * radius


static func collect_box_candidates(sc: SelectionController, world_rect: Rect2) -> Dictionary:
	var local_t: Unit.Team = sc._get_local_human_team_enum()
	var all_unit_hits: Array[Unit] = []
	var combat_hits: Array[Unit] = []
	var utility_hits: Array[Unit] = []
	for node: Node in sc.get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.is_staffed or unit.team != local_t:
			continue
		if circle_intersects_rect(unit.global_position, unit.get_selection_radius(), world_rect):
			all_unit_hits.append(unit)
			if sc._is_utility_unit(unit):
				utility_hits.append(unit)
			else:
				combat_hits.append(unit)

	var smart_box_enabled: bool = SettingsManager != null and SettingsManager.smart_box_select_enabled
	var unit_hits: Array[Unit] = all_unit_hits
	if smart_box_enabled:
		unit_hits = combat_hits if not combat_hits.is_empty() else utility_hits

	var b_hits: Array[Building] = []
	if unit_hits.is_empty():
		for node: Node in sc.get_tree().get_nodes_in_group("selectable_buildings"):
			if not (node is Building) or not is_instance_valid(node):
				continue
			var b: Building = node
			if b.is_destroyed or b.team != local_t:
				continue
			if circle_intersects_rect(b.global_position, b.footprint_radius * 0.75, world_rect):
				b_hits.append(b)

	return {
		"units": unit_hits,
		"combat_units": combat_hits,
		"buildings": b_hits,
		"smart_box_enabled": smart_box_enabled,
	}


static func find_top_hover_entity(sc: SelectionController, world_point: Vector2) -> Node:
	if sc == null or sc.command_router == null:
		return null
	var router: CommandRouter = sc.command_router
	var is_spec: bool = (TeamManager != null and TeamManager.is_spectator_mode()) or sc._is_post_match_inspection()
	if is_spec:
		var su: Unit = router.find_any_unit_at_point(world_point)
		if su != null:
			return su
		var sb: Building = router.find_any_building_at_point(world_point)
		if sb != null:
			return sb
	else:
		var local_t: Unit.Team = sc._get_local_human_team_enum()
		var local_int: int = int(local_t)
		var fu: Unit = router.find_unit_at_point(world_point, local_t)
		if fu != null:
			return fu
		var eu: Unit = router.find_hostile_unit_at_point(world_point, local_int)
		if eu != null:
			return eu
		var fb: Building = router.find_building_at_point(world_point, local_t)
		if fb != null:
			return fb
		var eb: Building = router.find_hostile_building_at_point(world_point, local_int)
		if eb != null:
			return eb

	var bar: Node2D = router.find_barricade_at_point(world_point)
	if bar != null:
		return bar
	var relay_h: Node2D = router.find_sensor_relay_at_point(world_point)
	if relay_h != null:
		return relay_h
	var uplink_h: Node2D = router.find_hyper_uplink_at_point(world_point)
	if uplink_h != null:
		return uplink_h
	var salv: Node2D = router.find_salvage_core_at_point(world_point)
	if salv != null:
		return salv
	var res: ResourceNode = router.find_resource_node_at_point(world_point)
	if res != null:
		return res
	return null


static func find_visible_units_of_type(sc: SelectionController, type_id: StringName, target_team: Unit.Team) -> Array[Unit]:
	var matches: Array[Unit] = []
	var cam: RTSCamera = sc._get_rts_camera()
	var view_rect: Rect2 = Rect2()
	var use_view_rect: bool = false
	if cam != null:
		var vp_size: Vector2 = sc.get_viewport_rect().size / cam.zoom
		view_rect = Rect2(cam.global_position - vp_size * 0.5, vp_size)
		use_view_rect = true
	for node: Node in sc.get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed or unit.team != target_team or unit.get_unit_type_id() != type_id:
			continue
		if not use_view_rect or view_rect.has_point(unit.global_position):
			matches.append(unit)
	return matches


static func find_visible_buildings_of_type(sc: SelectionController, type_id: StringName, target_team: Unit.Team) -> Array[Building]:
	var matches: Array[Building] = []
	var cam: RTSCamera = sc._get_rts_camera()
	var view_rect: Rect2 = Rect2()
	var use_view_rect: bool = false
	if cam != null:
		var vp_size: Vector2 = sc.get_viewport_rect().size / cam.zoom
		view_rect = Rect2(cam.global_position - vp_size * 0.5, vp_size)
		use_view_rect = true
	for node: Node in sc.get_tree().get_nodes_in_group("selectable_buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.team != target_team or b.building_type_id != type_id:
			continue
		if not use_view_rect or view_rect.has_point(b.global_position):
			matches.append(b)
	return matches


static func get_building_subgroup_sort_rank(b: Building) -> int:
	if b.is_command_hub():
		return 0
	if b.is_military_production_building():
		return 1
	if not b.researchable_upgrades.is_empty() or b.max_staff_slots > 0:
		return 2
	return 3


static func rebuild_building_subgroups(selected_buildings: Array[Building], preserve_type_id: StringName = &"") -> Dictionary:
	var out_subgroups: Array[Dictionary] = []
	if selected_buildings.is_empty():
		return {"subgroups": out_subgroups, "active_index": 0}

	var grouped: Dictionary = {}
	for b: Building in selected_buildings:
		if not is_instance_valid(b) or b.is_destroyed or b.is_queued_for_deletion():
			continue
		var tid: StringName = b.building_type_id
		if not grouped.has(tid):
			var b_arr: Array[Building] = []
			grouped[tid] = {
				"type_id": tid,
				"display_name": b.display_name,
				"tech_tier": b.get_tech_tier(),
				"is_hub": b.is_command_hub(),
				"sort_rank": get_building_subgroup_sort_rank(b),
				"buildings": b_arr,
			}
		var list_ref: Array[Building] = grouped[tid]["buildings"] as Array[Building]
		list_ref.append(b)

	for entry: Variant in grouped.values():
		out_subgroups.append(entry as Dictionary)

	out_subgroups.sort_custom(func(a: Dictionary, b_dict: Dictionary) -> bool:
		var ra: int = int(a["sort_rank"])
		var rb: int = int(b_dict["sort_rank"])
		if ra != rb:
			return ra < rb
		var ta: int = int(a["tech_tier"])
		var tb: int = int(b_dict["tech_tier"])
		if ta != tb:
			return ta < tb
		return String(a["type_id"]) < String(b_dict["type_id"])
	)

	var next_idx: int = 0
	if preserve_type_id != &"":
		for i: int in range(out_subgroups.size()):
			if (out_subgroups[i]["type_id"] as StringName) == preserve_type_id:
				next_idx = i
				break
	var active_index: int = clampi(next_idx, 0, maxi(0, out_subgroups.size() - 1))
	return {"subgroups": out_subgroups, "active_index": active_index}
