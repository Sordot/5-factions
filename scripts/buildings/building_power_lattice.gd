class_name BuildingPowerLattice
extends RefCounted


static func is_position_powered_for_team(tree: SceneTree, world_pos: Vector2, target_team: int, exclude_building: Building = null) -> bool:
	if tree == null:
		return false
	var candidates: Array = SpatialGrid.query_buildings_in_radius(world_pos, 480.0) if SpatialGrid != null else tree.get_nodes_in_group("buildings")
	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if b == exclude_building or b.is_destroyed or b.is_queued_for_deletion():
			continue
		if not b.is_constructed or b.is_salvaging:
			continue
		if int(b.team) != target_team:
			continue
		if not b.provides_power_grid or b.power_radius <= 0.0:
			continue
		if world_pos.distance_squared_to(b.global_position) <= b.power_radius * b.power_radius:
			return true
	return false


static func refresh_team_power_grid(tree: SceneTree, target_team: int, exclude_building: Building = null) -> void:
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if b == exclude_building or b.is_destroyed or b.is_queued_for_deletion():
			continue
		if int(b.team) != target_team:
			continue
		var next_powered: bool = true
		if b.is_constructed and b.requires_power_grid:
			next_powered = is_position_powered_for_team(tree, b.global_position, target_team, exclude_building)
		if next_powered != b.is_powered:
			b.set_powered_state(next_powered)


static func apply_powered_state(building: Building, powered: bool) -> void:
	if building.is_powered == powered:
		return
	building.is_powered = powered
	if building.is_powered:
		building._unpowered_pulse_time = 0.0
	else:
		if building.turret_component != null:
			building.turret_component.current_target = null
			building.turret_component.explicit_target = null
		var is_local_owned: bool = TeamManager.is_team_controlled_by_local_human(int(building.team)) if TeamManager != null else (building.team == Unit.Team.PLAYER)
		if is_local_owned and building.is_inside_tree():
			var now_ms: int = Time.get_ticks_msec()
			if now_ms - building._last_unpowered_alert_ms >= 6000:
				building._last_unpowered_alert_ms = now_ms
				var mm: MatchManager = building.get_tree().get_first_node_in_group("match_manager") as MatchManager
				if mm != null:
					mm.push_tactical_alert(building.global_position, &"under_attack", "%s Unpowered!" % building.display_name)
	building._update_construction_visuals()
	building.queue_redraw()
	building.status_changed.emit(building)


static func get_shield_regen_delay_speedup_at(tree: SceneTree, world_pos: Vector2, target_team: int) -> float:
	if tree == null:
		return 0.0
	var best_speedup: float = 0.0
	var candidates: Array = SpatialGrid.query_buildings_in_radius(world_pos, 320.0) if SpatialGrid != null else tree.get_nodes_in_group("buildings")
	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if b.is_destroyed or not b.is_constructed or b.is_salvaging or b.shield_regen_aura_radius <= 0.0 or b.shield_regen_delay_speedup <= 0.0:
			continue
		var is_ally: bool = (int(b.team) == target_team) or (TeamManager != null and TeamManager.are_allies(target_team, int(b.team)))
		if not is_ally:
			continue
		if world_pos.distance_squared_to(b.global_position) <= b.shield_regen_aura_radius * b.shield_regen_aura_radius:
			best_speedup = maxf(best_speedup, b.shield_regen_delay_speedup)
	return best_speedup
