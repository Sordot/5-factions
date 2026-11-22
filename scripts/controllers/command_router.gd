class_name CommandRouter
extends Node

const MOVE_MARKER_SCRIPT: GDScript = preload("res://ui/overlays/move_marker.gd")
const DEFAULT_UNIT_RADIUS: float = 16.0
const RING_SPACING_MULTIPLIER: float = 2.6
const VENT_SNAP_RADIUS: float = 64.0

@export var buildable_bounds: Rect2 = Rect2(-640.0, -360.0, 1280.0, 720.0)


func handle_right_click(world_pos: Vector2, selected_units: Array[Unit], inspected_entity: Node) -> void:
	# 1. Rally point assignment when inspecting a friendly rally-capable building.
	if selected_units.is_empty():
		if inspected_entity is Building and is_instance_valid(inspected_entity):
			var building: Building = inspected_entity
			if building.team == Unit.Team.PLAYER and building.is_constructed and building.can_set_rally:
				_handle_building_rally_right_click(building, world_pos)
		return

	# 2. Attack hostile unit or hostile building.
	var clicked_enemy_unit: Unit = find_unit_at_point(world_pos, Unit.Team.ENEMY)
	if clicked_enemy_unit != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy_unit)
		spawn_move_marker(clicked_enemy_unit.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	var clicked_enemy_building: Building = find_building_at_point(world_pos, Unit.Team.ENEMY)
	if clicked_enemy_building != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy_building)
		spawn_move_marker(clicked_enemy_building.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	# 3. Resource node gathering.
	var clicked_resource: ResourceNode = find_resource_node_at_point(world_pos)
	if clicked_resource != null and not clicked_resource.is_vent and _has_any_gatherer_for(selected_units, clicked_resource.resource_type):
		var non_gatherers: Array[Unit] = []
		for unit: Unit in selected_units:
			if unit.can_gather_resource(clicked_resource.resource_type):
				unit.command_gather(clicked_resource)
			else:
				non_gatherers.append(unit)
		if not non_gatherers.is_empty():
			var escort_targets: Array[Vector2] = assign_group_destinations(non_gatherers, clicked_resource.global_position)
			for i: int in range(non_gatherers.size()):
				non_gatherers[i].command_move(escort_targets[i])
		spawn_move_marker(clicked_resource.global_position, MoveMarker.MarkerStyle.GATHER)
		return

	# 4. Friendly building interaction (construct, staff ComputeNode, return cargo).
	var clicked_building: Building = find_building_at_point(world_pos, Unit.Team.PLAYER)
	if clicked_building != null:
		if not clicked_building.is_constructed:
			var builders: Array[Unit] = []
			for unit: Unit in selected_units:
				if unit.can_construct():
					builders.append(unit)
			if not builders.is_empty():
				for worker: Unit in builders:
					worker.command_construct_building(clicked_building)
				spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.GATHER)
				return

		if clicked_building.is_constructed and clicked_building.max_staff_slots > 0:
			var engineers: Array[Unit] = []
			var others: Array[Unit] = []
			for unit: Unit in selected_units:
				if unit.can_staff_compute() and clicked_building.can_accept_staff(unit):
					engineers.append(unit)
				else:
					others.append(unit)
			if not engineers.is_empty():
				for eng: Unit in engineers:
					eng.command_staff_building(clicked_building)
				if not others.is_empty():
					var move_targets_eng: Array[Vector2] = assign_group_destinations(others, world_pos)
					for i: int in range(others.size()):
						others[i].command_move(move_targets_eng[i])
				spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.GATHER)
				return

		if clicked_building.is_constructed and clicked_building.is_resource_dropoff:
			var returning_workers: Array[Unit] = []
			var other_units: Array[Unit] = []
			for unit: Unit in selected_units:
				if unit.can_gather() and unit.is_carrying_cargo() and clicked_building.accepts_resource(unit.get_carried_type()):
					returning_workers.append(unit)
				else:
					other_units.append(unit)
			if not returning_workers.is_empty():
				for worker: Unit in returning_workers:
					worker.command_return_cargo(clicked_building)
				if not other_units.is_empty():
					var move_targets: Array[Vector2] = assign_group_destinations(other_units, world_pos)
					for i: int in range(other_units.size()):
						other_units[i].command_move(move_targets[i])
				spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.GATHER)
				return

	# 5. Ground Move with concentric ring formation offsets.
	var targets: Array[Vector2] = assign_group_destinations(selected_units, world_pos)
	for i: int in range(selected_units.size()):
		selected_units[i].command_move(targets[i])
	spawn_move_marker(world_pos, MoveMarker.MarkerStyle.MOVE)


func _handle_building_rally_right_click(building: Building, world_pos: Vector2) -> void:
	var clicked_res: ResourceNode = find_resource_node_at_point(world_pos)
	if clicked_res != null and not clicked_res.is_vent:
		building.set_rally_target(clicked_res)
		spawn_move_marker(clicked_res.global_position, MoveMarker.MarkerStyle.GATHER)
		return

	var clicked_friendly_building: Building = find_building_at_point(world_pos, Unit.Team.PLAYER)
	if clicked_friendly_building != null and clicked_friendly_building != building and clicked_friendly_building.max_staff_slots > 0:
		building.set_rally_target(clicked_friendly_building)
		spawn_move_marker(clicked_friendly_building.global_position, MoveMarker.MarkerStyle.GATHER)
		return

	building.set_rally_position(world_pos)
	spawn_move_marker(world_pos, MoveMarker.MarkerStyle.MOVE)


func issue_attack_move(world_pos: Vector2, selected_units: Array[Unit]) -> void:
	if selected_units.is_empty():
		return
	var clicked_enemy: Unit = find_unit_at_point(world_pos, Unit.Team.ENEMY)
	if clicked_enemy != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy)
		spawn_move_marker(clicked_enemy.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	var clicked_enemy_building: Building = find_building_at_point(world_pos, Unit.Team.ENEMY)
	if clicked_enemy_building != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy_building)
		spawn_move_marker(clicked_enemy_building.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	var targets: Array[Vector2] = assign_group_destinations(selected_units, world_pos)
	for i: int in range(selected_units.size()):
		selected_units[i].command_attack_move(targets[i])
	spawn_move_marker(world_pos, MoveMarker.MarkerStyle.ATTACK)


func issue_stop(selected_units: Array[Unit]) -> void:
	for unit: Unit in selected_units:
		unit.command_stop()


func issue_hold(selected_units: Array[Unit]) -> void:
	for unit: Unit in selected_units:
		unit.command_hold_position()


func evaluate_build_placement(building_data: BuildingData, cursor_world: Vector2) -> Dictionary:
	var result: Dictionary = {
		"pos": cursor_world,
		"valid": false,
		"reason": "",
		"vent": null,
	}
	if building_data == null or building_data.scene == null:
		result["reason"] = "Invalid building"
		return result

	var place_pos: Vector2 = cursor_world
	var snapped_vent: ResourceNode = null
	if building_data.requires_vent:
		snapped_vent = find_nearest_unoccupied_vent(cursor_world, VENT_SNAP_RADIUS)
		if snapped_vent == null:
			result["reason"] = "Must be built on a Compute Vent"
			return result
		place_pos = snapped_vent.global_position
		result["pos"] = place_pos
		result["vent"] = snapped_vent

	var half: Vector2 = building_data.footprint_size * 0.5
	var new_radius: float = building_data.get_footprint_radius()

	var safe_bounds: Rect2 = Rect2(
		buildable_bounds.position + half + Vector2(8.0, 8.0),
		buildable_bounds.size - building_data.footprint_size - Vector2(16.0, 16.0)
	)
	if not safe_bounds.has_point(place_pos):
		result["reason"] = "Out of buildable bounds"
		return result

	# Keep central Hyper-Uplink clear of structures.
	for node: Node in get_tree().get_nodes_in_group("hyper_uplinks"):
		if node is Node2D and is_instance_valid(node):
			var min_u: float = 72.0 + new_radius
			if (node as Node2D).global_position.distance_squared_to(place_pos) < min_u * min_u:
				result["reason"] = "Too close to Hyper-Uplink"
				return result

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var existing: Building = node
		if existing.is_destroyed:
			continue
		var min_dist: float = existing.footprint_radius + new_radius + 10.0
		if existing.global_position.distance_squared_to(place_pos) < min_dist * min_dist:
			result["reason"] = "Blocked by structure"
			return result

	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var res_node: ResourceNode = node
		if res_node.is_depleted() or res_node.is_vent:
			continue
		var min_dist: float = res_node.collision_radius + new_radius + 8.0
		if res_node.global_position.distance_squared_to(place_pos) < min_dist * min_dist:
			result["reason"] = "Too close to resource node"
			return result

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null and not econ.can_afford(Unit.Team.PLAYER, building_data.get_cost_dict()):
		result["reason"] = "Need %s" % building_data.get_cost_label()
		return result

	result["valid"] = true
	result["reason"] = "%s (%s)" % [building_data.display_name, building_data.get_cost_label()]
	return result


func confirm_build_placement(ability: AbilityData, world_pos: Vector2, subgroup_units: Array[Unit]) -> bool:
	var building_data: BuildingData = ability.building_to_build
	if building_data == null or building_data.scene == null:
		return false

	var eval: Dictionary = evaluate_build_placement(building_data, world_pos)
	if not bool(eval["valid"]):
		return false

	var builder: Unit = find_closest_builder(subgroup_units, eval["pos"])
	if builder == null:
		return false

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null and not econ.spend_resources(Unit.Team.PLAYER, building_data.get_cost_dict()):
		return false

	var scene_root: Node = get_tree().current_scene
	var buildings_container: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if buildings_container == null:
		buildings_container = get_parent().get_parent() if get_parent() != null else null
	if buildings_container == null:
		return false

	var instance: Node = building_data.scene.instantiate()
	if not (instance is Building):
		instance.queue_free()
		return false

	var new_building: Building = instance
	new_building.global_position = eval["pos"]
	new_building.is_constructed = false
	buildings_container.add_child(new_building)
	new_building.begin_construction(building_data, Unit.Team.PLAYER, eval["vent"] as ResourceNode)
	_nudge_units_out_of_building(new_building)

	builder.command_construct_building(new_building)
	spawn_move_marker(new_building.global_position, MoveMarker.MarkerStyle.GATHER)
	return true


func find_closest_builder(units: Array[Unit], target_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_dist_sq: float = INF
	for item: Variant in units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if not unit.can_construct():
			continue
		var d_sq: float = unit.global_position.distance_squared_to(target_pos)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = unit
	return best


func find_nearest_unoccupied_vent(world_point: Vector2, max_radius: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var res_node: ResourceNode = node
		if not res_node.is_vent or res_node.is_occupied():
			continue
		var d_sq: float = res_node.global_position.distance_squared_to(world_point)
		if d_sq <= best_dist_sq:
			best_dist_sq = d_sq
			best = res_node
	return best


func find_unit_at_point(world_point: Vector2, target_team: Unit.Team) -> Unit:
	var closest: Unit = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.team != target_team:
			continue
		if unit.contains_point(world_point):
			var dist_sq: float = unit.global_position.distance_squared_to(world_point)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest = unit
	return closest


func find_building_at_point(world_point: Vector2, target_team: Unit.Team) -> Building:
	var closest: Building = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_buildings"):
		if not (node is Building):
			continue
		var building: Building = node
		if not is_instance_valid(building) or building.is_destroyed or building.team != target_team:
			continue
		if building.contains_point(world_point):
			var dist_sq: float = building.global_position.distance_squared_to(world_point)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest = building
	return closest


func find_resource_node_at_point(world_point: Vector2) -> ResourceNode:
	var closest: ResourceNode = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode):
			continue
		var res_node: ResourceNode = node
		if not is_instance_valid(res_node) or res_node.is_depleted():
			continue
		if res_node.contains_point(world_point):
			var dist_sq: float = res_node.global_position.distance_squared_to(world_point)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest = res_node
	return closest


func assign_group_destinations(units: Array[Unit], center_pos: Vector2) -> Array[Vector2]:
	var count: int = units.size()
	var assigned: Array[Vector2] = []
	if count == 0:
		return assigned

	var map_rid: RID = _get_navigation_map(units[0])
	var has_map: bool = map_rid.is_valid() and NavigationServer2D.map_get_iteration_id(map_rid) > 0
	if count == 1:
		var single_pos: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, center_pos) if has_map else center_pos
		assigned.append(single_pos)
		return assigned

	var unit_radius: float = units[0].data.collision_radius if units[0].data != null else DEFAULT_UNIT_RADIUS
	var spacing: float = unit_radius * RING_SPACING_MULTIPLIER
	var slots: Array[Vector2] = _generate_ring_slots(count, center_pos, spacing, map_rid, has_map)

	var used: Array[bool] = []
	used.resize(slots.size())
	used.fill(false)
	assigned.resize(count)

	for i: int in range(count):
		var u_pos: Vector2 = units[i].global_position
		var best_idx: int = 0
		var best_dist_sq: float = INF
		for s_idx: int in range(slots.size()):
			if used[s_idx]:
				continue
			var d_sq: float = u_pos.distance_squared_to(slots[s_idx])
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_idx = s_idx
		used[best_idx] = true
		assigned[i] = slots[best_idx]

	return assigned


func spawn_move_marker(target_pos: Vector2, marker_style: MoveMarker.MarkerStyle) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		return
	var marker: MoveMarker = MOVE_MARKER_SCRIPT.new()
	marker.global_position = target_pos
	marker.z_index = 60
	host.add_child(marker)
	marker.configure(marker_style)


func _generate_ring_slots(count: int, center_pos: Vector2, spacing: float, map_rid: RID, has_map: bool) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var first_pos: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, center_pos) if has_map else center_pos
	slots.append(first_pos)

	var ring: int = 1
	while slots.size() < count:
		var ring_radius: float = float(ring) * spacing
		var circumference: float = TAU * ring_radius
		var ring_slots: int = maxi(6, int(round(circumference / spacing)))
		var angle_offset: float = 0.0 if (ring % 2) == 1 else (PI / float(ring_slots))
		for k: int in range(ring_slots):
			if slots.size() >= count:
				break
			var angle: float = angle_offset + (TAU * float(k) / float(ring_slots))
			var candidate: Vector2 = center_pos + Vector2.RIGHT.rotated(angle) * ring_radius
			if has_map:
				candidate = NavigationServer2D.map_get_closest_point(map_rid, candidate)
			slots.append(candidate)
		ring += 1

	return slots


func _get_navigation_map(sample_unit: Unit) -> RID:
	if sample_unit != null and sample_unit.nav_agent != null:
		return sample_unit.nav_agent.get_navigation_map()
	return get_viewport().world_2d.navigation_map


func _has_any_gatherer_for(units: Array[Unit], resource_type: StringName) -> bool:
	for unit: Unit in units:
		if is_instance_valid(unit) and not unit.is_dead and unit.can_gather_resource(resource_type):
			return true
	return false


func _nudge_units_out_of_building(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed:
			continue
		var unit_r: float = unit.data.collision_radius if unit.data != null else 14.0
		var min_dist: float = building.footprint_radius + unit_r + 6.0
		var diff: Vector2 = unit.global_position - building.global_position
		if diff.length_squared() < min_dist * min_dist:
			var dir: Vector2 = diff.normalized() if diff.length_squared() > 0.01 else Vector2.RIGHT
			unit.global_position = building.global_position + dir * min_dist
