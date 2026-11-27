class_name BuildingRallyController
extends RefCounted

var _has_rally: bool = false
var _rally_position: Vector2 = Vector2.ZERO
var _rally_target: Node2D = null
var _rally_resource_type: StringName = &""
var rally_target_unit: Unit = null
var _owner_building: Building = null


func set_rally_position(building: Building, world_pos: Vector2) -> void:
	if building == null or not building.can_set_rally:
		return
	_owner_building = building
	disconnect_unit_signal()
	_has_rally = true
	_rally_position = world_pos
	_rally_target = null
	_rally_resource_type = &""
	rally_target_unit = null
	building.queue_redraw()
	building.rally_changed.emit(building)
	building.status_changed.emit(building)


func set_rally_target(building: Building, target: Node2D) -> void:
	if building == null or not building.can_set_rally or target == null or not is_instance_valid(target):
		return
	if target is Unit:
		set_rally_target_unit(building, target as Unit)
		return
	_owner_building = building
	disconnect_unit_signal()
	_has_rally = true
	_rally_target = target
	_rally_resource_type = (target as ResourceNode).resource_type if (target is ResourceNode and not (target as ResourceNode).is_vent) else &""
	rally_target_unit = null
	_rally_position = target.global_position
	building.queue_redraw()
	building.rally_changed.emit(building)
	building.status_changed.emit(building)


func set_rally_target_unit(building: Building, target_unit: Unit) -> void:
	if building == null or not building.can_set_rally or target_unit == null or not is_instance_valid(target_unit):
		return
	if target_unit.is_dead or target_unit.is_staffed or target_unit.team != building.team:
		return
	_owner_building = building
	disconnect_unit_signal()
	_has_rally = true
	rally_target_unit = target_unit
	_rally_target = target_unit
	_rally_resource_type = &""
	_rally_position = target_unit.global_position
	if not target_unit.died.is_connected(_on_rally_target_unit_died):
		target_unit.died.connect(_on_rally_target_unit_died)
	building.queue_redraw()
	building.rally_changed.emit(building)
	building.status_changed.emit(building)


func disconnect_unit_signal(clear_owner: bool = false) -> void:
	if rally_target_unit != null and is_instance_valid(rally_target_unit):
		if rally_target_unit.died.is_connected(_on_rally_target_unit_died):
			rally_target_unit.died.disconnect(_on_rally_target_unit_died)
	if clear_owner:
		_owner_building = null


func _on_rally_target_unit_died(unit: Unit) -> void:
	if unit != rally_target_unit:
		return
	if is_instance_valid(unit):
		_rally_position = unit.global_position
	rally_target_unit = null
	_rally_target = null
	if _owner_building != null and is_instance_valid(_owner_building):
		_owner_building.queue_redraw()
		_owner_building.rally_changed.emit(_owner_building)
		_owner_building.status_changed.emit(_owner_building)


func has_rally() -> bool:
	if rally_target_unit != null:
		if not is_instance_valid(rally_target_unit) or rally_target_unit.is_dead or rally_target_unit.is_staffed:
			if is_instance_valid(rally_target_unit):
				_rally_position = rally_target_unit.global_position
			rally_target_unit = null
			_rally_target = null
		else:
			_rally_position = rally_target_unit.global_position
	elif _rally_target != null and not is_instance_valid(_rally_target):
		_rally_target = null
	return _has_rally


func get_rally_world_position() -> Vector2:
	if rally_target_unit != null:
		if is_instance_valid(rally_target_unit) and not rally_target_unit.is_dead and not rally_target_unit.is_staffed:
			_rally_position = rally_target_unit.global_position
			return _rally_position
		if is_instance_valid(rally_target_unit):
			_rally_position = rally_target_unit.global_position
		rally_target_unit = null
		_rally_target = null
	if _rally_target != null and is_instance_valid(_rally_target):
		return _rally_target.global_position
	return _rally_position


func get_rally_target() -> Node2D:
	if rally_target_unit != null:
		if is_instance_valid(rally_target_unit) and not rally_target_unit.is_dead and not rally_target_unit.is_staffed:
			return rally_target_unit
		rally_target_unit = null
		_rally_target = null
	if _rally_target != null and is_instance_valid(_rally_target):
		return _rally_target
	return null


func apply_rally_to_unit(building: Building, unit: Unit) -> void:
	if building == null or unit == null or not is_instance_valid(unit) or unit.is_dead:
		return
	if not has_rally():
		return

	# Capability-aware universal Command Hub rallies: never walk automated Silica harvesters into Biomass patches.
	if building.is_command_hub() and unit.data != null and unit.data.auto_gather_on_spawn and unit.data.allowed_resource == &"silica":
		var rallied_to_biomass: bool = false
		if _rally_target != null and is_instance_valid(_rally_target) and _rally_target is ResourceNode:
			var r_rn: ResourceNode = _rally_target as ResourceNode
			if not r_rn.is_vent and r_rn.resource_type == &"biomass":
				rallied_to_biomass = true
		elif _rally_resource_type == &"biomass":
			rallied_to_biomass = true
		if rallied_to_biomass:
			return

	if rally_target_unit != null and is_instance_valid(rally_target_unit) and not rally_target_unit.is_dead and not rally_target_unit.is_staffed:
		_rally_position = rally_target_unit.global_position
		if unit.data != null and unit.data.attack_damage > 0.0 and not unit.data.can_gather:
			unit.command_attack_move(_rally_position)
		else:
			unit.command_move(_rally_position)
		return

	if _rally_target != null and is_instance_valid(_rally_target):
		if _rally_target is ResourceNode:
			var res_node: ResourceNode = _rally_target
			if not res_node.is_depleted() and unit.can_gather_resource(res_node.resource_type):
				var chosen: ResourceNode = ResourceNode.pick_best_cluster_node(res_node, unit, int(building.team))
				if chosen == null:
					chosen = res_node
				chosen.assign_worker(unit)
				unit.command_gather(chosen, false)
				return
		elif _rally_target is Building:
			var target_b: Building = _rally_target
			if not target_b.is_destroyed and target_b.max_staff_slots > 0 and unit.can_staff_compute():
				if unit.command_staff_building(target_b):
					return
	elif _rally_resource_type != &"" and unit.can_gather_resource(_rally_resource_type):
		# Original rallied resource node depleted; spill cleanly into surviving cluster near rally point
		var search_pos: Vector2 = _rally_position if _rally_position != Vector2.ZERO else building.global_position
		var fallback_rn: ResourceNode = ResourceNode.pick_best_cluster_node_from_pos(
			building.get_tree(),
			search_pos,
			_rally_resource_type,
			unit,
			int(building.team),
			480.0,
			1100.0
		)
		if fallback_rn != null:
			fallback_rn.assign_worker(unit)
			unit.command_gather(fallback_rn, false)
			return

	unit.command_move(get_rally_world_position())
