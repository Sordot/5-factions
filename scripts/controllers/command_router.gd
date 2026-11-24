class_name CommandRouter
extends Node

const MOVE_MARKER_SCRIPT: GDScript = preload("res://ui/overlays/move_marker.gd")
const DEFAULT_UNIT_RADIUS: float = 16.0
const RING_SPACING_MULTIPLIER: float = 2.6
const VENT_SNAP_RADIUS: float = 64.0

@export var buildable_bounds: Rect2 = Rect2(-640.0, -360.0, 1280.0, 720.0)


func handle_right_click(world_pos: Vector2, selected_units: Array[Unit], inspected_entity: Node, shift_queued: bool = false, selected_buildings: Array[Building] = []) -> void:
	if TeamManager != null and TeamManager.is_spectator_mode():
		return
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)

	# 1. Turret explicit focus-fire OR rally point assignment when inspecting/selecting friendly building(s).
	if selected_units.is_empty():
		var turret_buildings: Array[Building] = []
		var rally_buildings: Array[Building] = []
		for b: Building in selected_buildings:
			if is_instance_valid(b) and not b.is_destroyed and int(b.team) == local_team and b.is_constructed:
				if b.has_turret and b.turret_component != null:
					turret_buildings.append(b)
				if b.can_set_rally:
					rally_buildings.append(b)
		if turret_buildings.is_empty() and rally_buildings.is_empty() and inspected_entity is Building and is_instance_valid(inspected_entity):
			var building: Building = inspected_entity
			if int(building.team) == local_team and building.is_constructed:
				if building.has_turret and building.turret_component != null:
					turret_buildings.append(building)
				if building.can_set_rally:
					rally_buildings.append(building)
		if not turret_buildings.is_empty():
			var focus_target: Node2D = find_hostile_unit_at_point(world_pos, local_team)
			if focus_target == null:
				focus_target = find_hostile_building_at_point(world_pos, local_team)
			if focus_target == null:
				focus_target = find_barricade_at_point(world_pos)
			if focus_target != null:
				var locked_any: bool = false
				for tb: Building in turret_buildings:
					if tb.command_turret_focus_target(focus_target):
						locked_any = true
				if locked_any:
					if AudioManager != null:
						AudioManager.play_sfx(&"order_attack", -3.5, 0.04)
					spawn_move_marker(focus_target.global_position, MoveMarker.MarkerStyle.ATTACK)
					return
		if not rally_buildings.is_empty():
			_handle_multi_building_rally_right_click(rally_buildings, world_pos)
		return

	# 2. Attack hostile unit, hostile building, or explicit Destructible Barricade.
	var clicked_enemy_unit: Unit = find_hostile_unit_at_point(world_pos, local_team)
	if clicked_enemy_unit != null:
		issue_attack_target_order(selected_units, clicked_enemy_unit, shift_queued)
		return

	var clicked_enemy_building: Building = find_hostile_building_at_point(world_pos, local_team)
	if clicked_enemy_building != null:
		issue_attack_target_order(selected_units, clicked_enemy_building, shift_queued)
		return

	var clicked_barricade: Node2D = find_barricade_at_point(world_pos)
	if clicked_barricade != null:
		issue_attack_target_order(selected_units, clicked_barricade, shift_queued)
		return

	# 2.5. Engineer repair on damaged friendly mechanical/synthetic unit.
	var clicked_friendly_unit: Unit = find_unit_at_point(world_pos, local_team as Unit.Team)
	if clicked_friendly_unit != null and issue_repair_order(selected_units, clicked_friendly_unit, shift_queued):
		return

	# 2.75. SalvageCore extraction for Workers and Engineers.
	var clicked_salvage: Node2D = find_salvage_core_at_point(world_pos)
	if clicked_salvage != null and issue_salvage_order(selected_units, clicked_salvage, shift_queued):
		return

	# 3. Resource node gathering.
	var clicked_resource: ResourceNode = find_resource_node_at_point(world_pos)
	if clicked_resource != null and not clicked_resource.is_vent and _has_any_gatherer_for(selected_units, clicked_resource.resource_type):
		issue_gather_order(selected_units, clicked_resource, shift_queued)
		return

	# 4. Friendly building interaction (construct, staff Wetware Mainframe, return cargo, repair, or waypoint visit).
	var clicked_building: Building = find_building_at_point(world_pos, local_team as Unit.Team)
	if clicked_building != null:
		if not clicked_building.is_constructed:
			if issue_build_order(selected_units, clicked_building, shift_queued):
				return

		if clicked_building.is_constructed and clicked_building.max_staff_slots > 0:
			if issue_staff_order(selected_units, clicked_building, shift_queued, world_pos):
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
					worker.command_return_cargo(clicked_building, shift_queued)
				if not other_units.is_empty():
					var approach_targets: Array[Vector2] = _assign_building_perimeter_destinations(other_units, clicked_building)
					for i: int in range(other_units.size()):
						other_units[i].command_move(approach_targets[i], shift_queued)
				spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.INTERACT)
				return

		if clicked_building.is_constructed and clicked_building.current_hp < clicked_building.max_hp - 0.5:
			if issue_repair_order(selected_units, clicked_building, shift_queued):
				return

		# Multi-building worker/unit waypoint stop: move cleanly to the building's perimeter so queues advance smoothly.
		var perimeter_targets: Array[Vector2] = _assign_building_perimeter_destinations(selected_units, clicked_building)
		for i: int in range(selected_units.size()):
			selected_units[i].command_move(perimeter_targets[i], shift_queued)
		spawn_move_marker(clicked_building.global_position, MoveMarker.MarkerStyle.INTERACT)
		return

	# 5. Ground Move with concentric ring formation offsets.
	issue_move_order(selected_units, world_pos, shift_queued)


func issue_move_order(selected_units: Array[Unit], world_pos: Vector2, shift_queued: bool = false) -> void:
	if selected_units.is_empty():
		return
	var targets: Array[Vector2] = assign_group_destinations(selected_units, world_pos)
	for i: int in range(selected_units.size()):
		selected_units[i].command_move(targets[i], shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_move", -4.0, 0.05)
		if AudioManager.has_method("play_unit_bark_for_units"):
			AudioManager.call("play_unit_bark_for_units", selected_units, &"order")
	spawn_move_marker(world_pos, MoveMarker.MarkerStyle.MOVE)


func issue_attack_target_order(selected_units: Array[Unit], target: Node2D, shift_queued: bool = false) -> void:
	if selected_units.is_empty() or target == null or not is_instance_valid(target):
		return
	for unit: Unit in selected_units:
		unit.command_attack_target(target, shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_attack", -3.5, 0.04)
		if AudioManager.has_method("play_unit_bark_for_units"):
			AudioManager.call("play_unit_bark_for_units", selected_units, &"order")
	spawn_move_marker(target.global_position, MoveMarker.MarkerStyle.ATTACK)


func issue_gather_order(selected_units: Array[Unit], resource_node: ResourceNode, shift_queued: bool = false) -> void:
	if selected_units.is_empty() or resource_node == null or not is_instance_valid(resource_node):
		return
	var non_gatherers: Array[Unit] = []
	for unit: Unit in selected_units:
		if unit.can_gather_resource(resource_node.resource_type):
			unit.command_gather(resource_node, shift_queued)
		else:
			non_gatherers.append(unit)
	if not non_gatherers.is_empty():
		var escort_targets: Array[Vector2] = assign_group_destinations(non_gatherers, resource_node.global_position)
		for i: int in range(non_gatherers.size()):
			non_gatherers[i].command_move(escort_targets[i], shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_gather", -4.0, 0.04)
		if AudioManager.has_method("play_unit_bark_for_units"):
			AudioManager.call("play_unit_bark_for_units", selected_units, &"order")
	spawn_move_marker(resource_node.global_position, MoveMarker.MarkerStyle.GATHER)


func issue_build_order(selected_units: Array[Unit], building: Building, shift_queued: bool = false) -> bool:
	if selected_units.is_empty() or building == null or not is_instance_valid(building):
		return false
	var builders: Array[Unit] = []
	for unit: Unit in selected_units:
		if unit.can_construct():
			builders.append(unit)
	if builders.is_empty():
		return false
	for worker: Unit in builders:
		worker.command_construct_building(building, shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_gather", -4.0, 0.04)
		if AudioManager.has_method("play_unit_bark_for_units"):
			AudioManager.call("play_unit_bark_for_units", builders, &"order")
	spawn_move_marker(building.global_position, MoveMarker.MarkerStyle.INTERACT)
	return true


func issue_repair_order(selected_units: Array[Unit], target: Node2D, shift_queued: bool = false) -> bool:
	if selected_units.is_empty() or target == null or not is_instance_valid(target):
		return false
	var repairers: Array[Unit] = []
	for unit: Unit in selected_units:
		if is_instance_valid(unit) and unit.can_repair_target(target):
			repairers.append(unit)
	if repairers.is_empty():
		return false
	for rep_unit: Unit in repairers:
		rep_unit.command_repair(target, shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_gather", -4.0, 0.04)
		if AudioManager.has_method("play_unit_bark_for_units"):
			AudioManager.call("play_unit_bark_for_units", repairers, &"order")
	spawn_move_marker(target.global_position, MoveMarker.MarkerStyle.INTERACT)
	return true


func issue_salvage_order(selected_units: Array[Unit], salvage_core: Node2D, shift_queued: bool = false) -> bool:
	if selected_units.is_empty() or salvage_core == null or not is_instance_valid(salvage_core):
		return false
	var extractors: Array[Unit] = []
	var escorts: Array[Unit] = []
	for unit: Unit in selected_units:
		if is_instance_valid(unit) and unit.can_salvage_core():
			extractors.append(unit)
		elif is_instance_valid(unit):
			escorts.append(unit)
	if extractors.is_empty():
		return false
	for ext_u: Unit in extractors:
		ext_u.command_salvage(salvage_core, shift_queued)
	if not escorts.is_empty():
		var escort_pts: Array[Vector2] = assign_group_destinations(escorts, salvage_core.global_position)
		for i: int in range(escorts.size()):
			escorts[i].command_move(escort_pts[i], shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_gather", -3.5, 0.04)
		if AudioManager.has_method("play_unit_bark_for_units"):
			AudioManager.call("play_unit_bark_for_units", extractors, &"order")
	spawn_move_marker(salvage_core.global_position, MoveMarker.MarkerStyle.INTERACT)
	return true


func issue_staff_order(selected_units: Array[Unit], building: Building, shift_queued: bool = false, fallback_pos: Vector2 = Vector2.ZERO) -> bool:
	if selected_units.is_empty() or building == null or not is_instance_valid(building):
		return false
	var engineers: Array[Unit] = []
	var others: Array[Unit] = []
	for unit: Unit in selected_units:
		if unit.can_staff_compute() and building.can_accept_staff(unit):
			engineers.append(unit)
		else:
			others.append(unit)
	if engineers.is_empty():
		return false
	for eng: Unit in engineers:
		eng.command_staff_building(building, shift_queued)
	if not others.is_empty():
		var move_targets: Array[Vector2] = _assign_building_perimeter_destinations(others, building) if fallback_pos == Vector2.ZERO else assign_group_destinations(others, fallback_pos)
		for i: int in range(others.size()):
			others[i].command_move(move_targets[i], shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_gather", -4.0, 0.04)
	spawn_move_marker(building.global_position, MoveMarker.MarkerStyle.INTERACT)
	return true


func _assign_building_perimeter_destinations(units: Array[Unit], building: Building) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if units.is_empty() or building == null or not is_instance_valid(building):
		return out
	var map_rid: RID = _get_navigation_map(units[0])
	var has_map: bool = map_rid.is_valid() and NavigationServer2D.map_get_iteration_id(map_rid) > 0
	for i: int in range(units.size()):
		var u: Unit = units[i]
		var unit_r: float = u.data.collision_radius if u.data != null else DEFAULT_UNIT_RADIUS
		var from_b: Vector2 = u.global_position - building.global_position
		var base_dir: Vector2 = from_b.normalized() if from_b.length_squared() > 4.0 else Vector2.RIGHT
		var spread: float = (float(i) - float(units.size() - 1) * 0.5) * 0.35
		var stand_dist: float = building.footprint_radius + unit_r + 14.0
		var pt: Vector2 = building.global_position + base_dir.rotated(spread) * stand_dist
		if has_map:
			pt = NavigationServer2D.map_get_closest_point(map_rid, pt)
		out.append(pt)
	return out


func _handle_multi_building_rally_right_click(buildings: Array[Building], world_pos: Vector2) -> void:
	var clicked_res: ResourceNode = find_resource_node_at_point(world_pos)
	var clicked_friendly_unit: Unit = find_unit_at_point(world_pos, Unit.Team.PLAYER)

	# Economy-only hubs keep resource-node priority even if a worker is standing right on the node.
	var all_econ_only: bool = true
	for b_chk: Building in buildings:
		if not b_chk.is_resource_dropoff:
			all_econ_only = false
			break

	if all_econ_only and clicked_res != null and not clicked_res.is_vent:
		for b: Building in buildings:
			b.set_rally_target(clicked_res)
		if AudioManager != null:
			AudioManager.play_sfx(&"order_gather", -4.5, 0.04)
		spawn_move_marker(clicked_res.global_position, MoveMarker.MarkerStyle.GATHER)
		return

	if clicked_friendly_unit != null:
		for b: Building in buildings:
			b.set_rally_target_unit(clicked_friendly_unit)
		if AudioManager != null:
			AudioManager.play_sfx(&"order_move", -4.0, 0.05)
		spawn_move_marker(clicked_friendly_unit.global_position, MoveMarker.MarkerStyle.INTERACT)
		return

	if clicked_res != null and not clicked_res.is_vent:
		for b: Building in buildings:
			b.set_rally_target(clicked_res)
		if AudioManager != null:
			AudioManager.play_sfx(&"order_gather", -4.5, 0.04)
		spawn_move_marker(clicked_res.global_position, MoveMarker.MarkerStyle.GATHER)
		return

	var clicked_friendly_building: Building = find_building_at_point(world_pos, Unit.Team.PLAYER)
	if clicked_friendly_building != null and clicked_friendly_building.max_staff_slots > 0:
		var applied_any: bool = false
		for b: Building in buildings:
			if b != clicked_friendly_building:
				b.set_rally_target(clicked_friendly_building)
				applied_any = true
		if applied_any:
			if AudioManager != null:
				AudioManager.play_sfx(&"order_gather", -4.5, 0.04)
			spawn_move_marker(clicked_friendly_building.global_position, MoveMarker.MarkerStyle.INTERACT)
			return

	for b: Building in buildings:
		b.set_rally_position(world_pos)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_move", -4.5, 0.04)
	spawn_move_marker(world_pos, MoveMarker.MarkerStyle.MOVE)


func _handle_building_rally_right_click(building: Building, world_pos: Vector2) -> void:
	_handle_multi_building_rally_right_click([building], world_pos)


func issue_patrol_order(selected_units: Array[Unit], world_pos: Vector2, shift_queued: bool = false) -> void:
	if selected_units.is_empty():
		return
	var targets: Array[Vector2] = assign_group_destinations(selected_units, world_pos)
	for i: int in range(selected_units.size()):
		selected_units[i].command_patrol(targets[i], shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_move", -3.5, 0.05)
	spawn_move_marker(world_pos, MoveMarker.MarkerStyle.PATROL)


func issue_attack_move(world_pos: Vector2, selected_units: Array[Unit], shift_queued: bool = false) -> void:
	issue_attack_move_order(selected_units, world_pos, shift_queued)


func issue_attack_move_order(selected_units: Array[Unit], world_pos: Vector2, shift_queued: bool = false) -> void:
	if selected_units.is_empty():
		return
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var clicked_enemy: Unit = find_hostile_unit_at_point(world_pos, local_team)
	if clicked_enemy != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy, shift_queued)
		spawn_move_marker(clicked_enemy.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	var clicked_enemy_building: Building = find_hostile_building_at_point(world_pos, local_team)
	if clicked_enemy_building != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_enemy_building, shift_queued)
		spawn_move_marker(clicked_enemy_building.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	var clicked_barricade: Node2D = find_barricade_at_point(world_pos)
	if clicked_barricade != null:
		for unit: Unit in selected_units:
			unit.command_attack_target(clicked_barricade, shift_queued)
		if AudioManager != null:
			AudioManager.play_sfx(&"order_attack", -3.5, 0.04)
		spawn_move_marker(clicked_barricade.global_position, MoveMarker.MarkerStyle.ATTACK)
		return

	var targets: Array[Vector2] = assign_group_destinations(selected_units, world_pos)
	for i: int in range(selected_units.size()):
		selected_units[i].command_attack_move(targets[i], shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_attack", -3.5, 0.04)
	spawn_move_marker(world_pos, MoveMarker.MarkerStyle.ATTACK)


func issue_stop(selected_units: Array[Unit]) -> void:
	for unit: Unit in selected_units:
		unit.command_stop()


func issue_hold(selected_units: Array[Unit]) -> void:
	var living: Array[Unit] = []
	var all_holding: bool = true
	for unit: Unit in selected_units:
		if not is_instance_valid(unit) or unit.is_dead or unit.is_staffed:
			continue
		living.append(unit)
		if unit.stance != Unit.Stance.HOLD_POSITION:
			all_holding = false
	if living.is_empty():
		return
	var target_stance: Unit.Stance = Unit.Stance.AGGRESSIVE if all_holding else Unit.Stance.HOLD_POSITION
	for unit: Unit in living:
		unit.set_stance(target_stance)


func issue_ability_order(
	subgroup_units: Array[Unit],
	ability: AbilityData,
	target_pos: Vector2,
	target_enemy: Unit = null,
	append_to_queue: bool = false
) -> bool:
	if subgroup_units.is_empty() or ability == null:
		return false

	if ability.target_type == AbilityData.TargetType.INSTANT:
		if ability.cast_on_all_ready:
			var cast_any: bool = false
			for u: Unit in subgroup_units:
				if is_instance_valid(u) and not u.is_dead and not u.is_staffed and u.is_ability_ready(ability):
					if u.command_cast_ability(ability, u.global_position, u, append_to_queue):
						cast_any = true
			return cast_any
		var instant_caster: Unit = SubgroupHelper.find_closest_ready_caster(subgroup_units, ability, target_pos)
		if instant_caster != null:
			return instant_caster.command_cast_ability(ability, instant_caster.global_position, instant_caster, append_to_queue)
		return false

	if ability.target_type == AbilityData.TargetType.UNIT_TARGET:
		if target_enemy == null or not is_instance_valid(target_enemy) or target_enemy.is_dead:
			return false

	var caster: Unit = SubgroupHelper.find_closest_ready_caster(subgroup_units, ability, target_pos)
	if caster == null:
		return false

	var cast_point: Vector2 = target_enemy.global_position if (target_enemy != null and is_instance_valid(target_enemy)) else target_pos
	var accepted: bool = caster.command_cast_ability(ability, cast_point, target_enemy, append_to_queue)
	if accepted:
		spawn_move_marker(cast_point, MoveMarker.MarkerStyle.ATTACK)
	return accepted


func evaluate_build_placement(building_data: BuildingData, cursor_world: Vector2, target_team: Unit.Team = Unit.Team.PLAYER) -> Dictionary:
	var result: Dictionary = {
		"pos": cursor_world,
		"valid": false,
		"reason": "",
		"vent": null,
	}
	if building_data == null or building_data.resolve_scene() == null:
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

	# Block placement inside or overlapping static terrain obstacles or solid map landmarks.
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.overlaps_circle(place_pos, new_radius + 8.0):
				result["reason"] = "Blocked by terrain"
				return result

	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.overlaps_circle(place_pos, new_radius + 8.0):
				result["reason"] = "Blocked by landmark"
				return result

	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", place_pos, new_radius + 8.0)):
				result["reason"] = "Blocked by barricade"
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
	if building_data.required_building_id != &"":
		if econ == null or not econ.has_constructed_building(target_team, building_data.required_building_id):
			var req_name: String = String(building_data.required_building_id).replace("_", " ").capitalize()
			result["reason"] = "Requires %s" % req_name
			return result

	if econ != null and not econ.can_afford(target_team, building_data.get_cost_dict()):
		result["reason"] = "Need %s" % building_data.get_cost_label()
		return result

	result["valid"] = true
	result["reason"] = "%s (%s)" % [building_data.display_name, building_data.get_cost_label()]
	return result


func confirm_build_placement(ability: AbilityData, world_pos: Vector2, subgroup_units: Array[Unit], shift_queued: bool = false) -> bool:
	var building_data: BuildingData = ability.building_to_build
	var building_scene: PackedScene = building_data.resolve_scene() if building_data != null else null
	if building_data == null or building_scene == null:
		return false

	var eval: Dictionary = evaluate_build_placement(building_data, world_pos)
	if not bool(eval["valid"]):
		var econ_fail: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
		if econ_fail != null and not econ_fail.can_afford(Unit.Team.PLAYER, building_data.get_cost_dict()):
			var missing: StringName = econ_fail.find_missing_resource(Unit.Team.PLAYER, building_data.get_cost_dict(), 0)
			if missing != &"":
				econ_fail.notify_insufficient(Unit.Team.PLAYER, missing)
		elif AudioManager != null:
			AudioManager.play_error()
		return false

	var builder: Unit = find_closest_builder(subgroup_units, eval["pos"])
	if builder == null:
		return false

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null and not econ.spend_resources(Unit.Team.PLAYER, building_data.get_cost_dict()):
		var missing2: StringName = econ.find_missing_resource(Unit.Team.PLAYER, building_data.get_cost_dict(), 0)
		if missing2 != &"":
			econ.notify_insufficient(Unit.Team.PLAYER, missing2)
		return false

	var scene_root: Node = get_tree().current_scene
	var buildings_container: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if buildings_container == null:
		buildings_container = get_parent().get_parent() if get_parent() != null else null
	if buildings_container == null:
		return false

	var instance: Node = building_scene.instantiate()
	if not (instance is Building):
		instance.queue_free()
		return false

	var new_building: Building = instance
	new_building.global_position = eval["pos"]
	new_building.is_constructed = false
	buildings_container.add_child(new_building)
	new_building.begin_construction(building_data, Unit.Team.PLAYER, eval["vent"] as ResourceNode)
	_nudge_units_out_of_building(new_building)

	builder.command_construct_building(new_building, shift_queued)
	if AudioManager != null:
		AudioManager.play_sfx(&"order_gather", -3.5, 0.04)
	spawn_move_marker(new_building.global_position, MoveMarker.MarkerStyle.INTERACT)
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


func find_salvage_core_at_point(world_point: Vector2) -> Node2D:
	var closest: Node2D = null
	var closest_dist_sq: float = INF
	var candidates: Array = SpatialGrid.query_salvage_in_radius(world_point, 48.0) if SpatialGrid != null else get_tree().get_nodes_in_group("salvage_cores")
	for node: Variant in candidates:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var sc: Node2D = node as Node2D
		if bool(sc.get("is_claimed")) or sc.is_queued_for_deletion() or not sc.visible:
			continue
		if sc.has_method("contains_point") and bool(sc.call("contains_point", world_point)):
			var d_sq: float = sc.global_position.distance_squared_to(world_point)
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest = sc
	return closest


func find_barricade_at_point(world_point: Vector2) -> Node2D:
	var closest: Node2D = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if bool(node.get("is_destroyed")) or node.is_queued_for_deletion():
			continue
		if node.has_method("contains_point") and bool(node.call("contains_point", world_point)):
			var d_sq: float = (node as Node2D).global_position.distance_squared_to(world_point)
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest = node as Node2D
	return closest


func find_hostile_unit_at_point(world_point: Vector2, viewer_team: int) -> Unit:
	var closest: Unit = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or not unit.visible:
			continue
		var is_hostile: bool = TeamManager.are_enemies(viewer_team, int(unit.team)) if (TeamManager != null and viewer_team >= 0) else (unit.team != Unit.Team.PLAYER)
		if not is_hostile:
			continue
		if unit.contains_point(world_point):
			var d_sq: float = unit.global_position.distance_squared_to(world_point)
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest = unit
	return closest


func find_hostile_building_at_point(world_point: Vector2, viewer_team: int) -> Building:
	var closest: Building = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_buildings"):
		if not (node is Building):
			continue
		var b: Building = node
		if not is_instance_valid(b) or b.is_destroyed or not b.visible:
			continue
		var is_hostile: bool = TeamManager.are_enemies(viewer_team, int(b.team)) if (TeamManager != null and viewer_team >= 0) else (b.team != Unit.Team.PLAYER)
		if not is_hostile:
			continue
		if b.contains_point(world_point):
			var d_sq: float = b.global_position.distance_squared_to(world_point)
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest = b
	return closest


func find_any_unit_at_point(world_point: Vector2) -> Unit:
	var closest: Unit = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var u: Unit = node
		if not is_instance_valid(u) or u.is_dead or not u.visible:
			continue
		if u.contains_point(world_point):
			var d_sq: float = u.global_position.distance_squared_to(world_point)
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest = u
	return closest


func find_any_building_at_point(world_point: Vector2) -> Building:
	var closest: Building = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_buildings"):
		if not (node is Building):
			continue
		var b: Building = node
		if not is_instance_valid(b) or b.is_destroyed or not b.visible:
			continue
		if b.contains_point(world_point):
			var d_sq: float = b.global_position.distance_squared_to(world_point)
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest = b
	return closest


func find_unit_at_point(world_point: Vector2, target_team: Unit.Team) -> Unit:
	var closest: Unit = null
	var closest_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("selectable_units"):
		if not (node is Unit):
			continue
		var unit: Unit = node
		if not is_instance_valid(unit) or unit.is_dead or unit.team != target_team:
			continue
		# Block targeting or inspecting hostile units hidden in Fog of War.
		if target_team == Unit.Team.ENEMY and not unit.visible:
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
		# Block targeting or inspecting hostile buildings hidden in unexplored Fog of War.
		if target_team == Unit.Team.ENEMY and not building.visible:
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
	CommandRouter.nudge_units_out_of_building(building, buildable_bounds)


static func nudge_units_out_of_building(building: Building, bounds: Rect2) -> void:
	if building == null or not is_instance_valid(building) or not building.is_inside_tree():
		return
	var tree: SceneTree = building.get_tree()
	for node: Node in tree.get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed:
			continue
		var unit_r: float = unit.data.collision_radius if unit.data != null else 14.0
		var min_dist: float = building.footprint_radius + unit_r + 6.0
		var diff: Vector2 = unit.global_position - building.global_position
		if diff.length_squared() >= min_dist * min_dist:
			continue
		var base_angle: float = diff.angle() if diff.length_squared() > 0.01 else 0.0
		var ejected: Vector2 = _find_safe_ejection_spot(tree, building, unit_r, base_angle, bounds)
		unit.global_position = ejected
		unit.invalidate_nav_path()


static func _find_safe_ejection_spot(
	tree: SceneTree,
	building: Building,
	unit_r: float,
	base_angle: float,
	bounds: Rect2
) -> Vector2:
	var safe_bounds: Rect2 = Rect2(
		bounds.position + Vector2(unit_r + 8.0, unit_r + 8.0),
		bounds.size - Vector2((unit_r + 8.0) * 2.0, (unit_r + 8.0) * 2.0)
	)
	var rings: PackedFloat32Array = PackedFloat32Array([
		building.footprint_radius + unit_r + 10.0,
		building.footprint_radius + unit_r * 3.0 + 14.0,
	])
	var steps: int = 24
	var step_angle: float = TAU / float(steps)

	for ring_dist: float in rings:
		for i: int in range(steps):
			var ring_offset: int = 0 if i == 0 else ((i + 1) >> 1)
			var sign_mult: float = 1.0 if (i % 2) == 1 else -1.0
			var ang: float = base_angle + float(ring_offset) * step_angle * sign_mult
			var cand: Vector2 = building.global_position + Vector2.RIGHT.rotated(ang) * ring_dist
			if _is_ejection_spot_clear(tree, cand, unit_r + 4.0, safe_bounds, building):
				return cand

	var fallback: Vector2 = building.global_position + Vector2.RIGHT.rotated(base_angle) * (building.footprint_radius + unit_r + 10.0)
	if safe_bounds.has_area():
		fallback.x = clampf(fallback.x, safe_bounds.position.x, safe_bounds.end.x)
		fallback.y = clampf(fallback.y, safe_bounds.position.y, safe_bounds.end.y)
	return fallback


static func _is_ejection_spot_clear(
	tree: SceneTree,
	world_pos: Vector2,
	clearance_r: float,
	safe_bounds: Rect2,
	ignore_building: Building
) -> bool:
	if safe_bounds.has_area() and not safe_bounds.has_point(world_pos):
		return false
	for node: Node in tree.get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.call("overlaps_circle", world_pos, clearance_r):
				return false
	for node: Node in tree.get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.call("overlaps_circle", world_pos, clearance_r):
				return false
	for node: Node in tree.get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b == ignore_building:
			continue
		var min_d: float = b.footprint_radius + clearance_r
		if b.global_position.distance_squared_to(world_pos) < min_d * min_d:
			return false
	for node: Node in tree.get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted() or rn.is_vent:
			continue
		var min_d: float = rn.collision_radius + clearance_r
		if rn.global_position.distance_squared_to(world_pos) < min_d * min_d:
			return false
	return true
