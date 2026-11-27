class_name UnitCommandQueue
extends RefCounted

const CMD_EXEC_FAILED: int = 0
const CMD_EXEC_ACTIVE: int = 1
const CMD_EXEC_IMMEDIATE_DONE: int = 2


static func has_queued_commands(unit: Unit) -> bool:
	return not unit.command_queue.is_empty()


static func clear(unit: Unit) -> void:
	var had_items: bool = not unit.command_queue.is_empty() or not unit.active_command.is_empty()
	unit.command_queue.clear()
	unit.active_command.clear()
	if had_items:
		unit.command_queue_changed.emit(unit)


static func issue_command(unit: Unit, cmd: Dictionary, append_to_queue: bool = false) -> bool:
	if unit.is_dead or unit.is_staffed or cmd.is_empty():
		return false
	var cmd_type_check: StringName = cmd.get("type", &"")
	# Anchored/deploying units ignore Move/Attack-Move/Patrol without accidentally undeploying or breaking focus-fire.
	if unit.is_movement_locked_by_deploy() and (cmd_type_check == &"move" or cmd_type_check == &"attack_move" or cmd_type_check == &"patrol"):
		return false
	if append_to_queue:
		var is_idle_now: bool = (
			(unit.command_state == Unit.CommandState.IDLE or unit.command_state == Unit.CommandState.HOLD_POSITION)
			and unit.active_command.is_empty()
			and unit.command_queue.is_empty()
		)
		if not is_idle_now:
			if cmd_type_check == &"attack_target":
				var new_atk_t: Variant = cmd.get("target", null)
				if not unit.command_queue.is_empty():
					var last_cmd: Dictionary = unit.command_queue[unit.command_queue.size() - 1]
					if last_cmd.get("type", &"") == &"attack_target" and last_cmd.get("target", null) == new_atk_t:
						return true
				elif unit.command_state == Unit.CommandState.ATTACKING_TARGET and unit.current_target == new_atk_t:
					return true
			unit.command_queue.append(cmd.duplicate())
			unit.command_queue_changed.emit(unit)
			unit.status_changed.emit(unit)
			return true
	else:
		clear(unit)
		if unit.gather_component != null:
			var cmd_type: StringName = cmd.get("type", &"")
			if (
				cmd_type == &"move"
				or cmd_type == &"attack_move"
				or cmd_type == &"attack_target"
				or cmd_type == &"patrol"
				or cmd_type == &"build"
				or cmd_type == &"repair"
				or cmd_type == &"salvage"
				or cmd_type == &"staff"
			):
				unit.gather_component.cancel(unit, true)
	return execute_command(unit, cmd) != CMD_EXEC_FAILED


static func advance(unit: Unit) -> bool:
	unit.active_command.clear()
	while not unit.command_queue.is_empty():
		var next_cmd: Dictionary = unit.command_queue.pop_front()
		unit.command_queue_changed.emit(unit)
		var result: int = execute_command(unit, next_cmd)
		if result == CMD_EXEC_ACTIVE:
			return true
		if result == CMD_EXEC_IMMEDIATE_DONE:
			continue
	unit.command_state = Unit.CommandState.HOLD_POSITION if unit.stance == Unit.Stance.HOLD_POSITION else Unit.CommandState.IDLE
	unit.velocity = Vector2.ZERO
	unit.command_queue_changed.emit(unit)
	unit.status_changed.emit(unit)
	return false


static func execute_command(unit: Unit, cmd: Dictionary) -> int:
	var cmd_type: StringName = cmd.get("type", &"")
	var result: int = CMD_EXEC_FAILED
	match cmd_type:
		&"move":
			result = CMD_EXEC_ACTIVE if unit._start_move(cmd.get("pos", unit.global_position) as Vector2) else CMD_EXEC_FAILED
		&"attack_move":
			result = CMD_EXEC_ACTIVE if unit._start_attack_move(cmd.get("pos", unit.global_position) as Vector2) else CMD_EXEC_FAILED
		&"attack_target":
			var atk_t: Variant = cmd.get("target", null)
			if atk_t != null and is_instance_valid(atk_t) and atk_t is Node2D and not (atk_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if unit._start_attack_target(atk_t as Node2D) else CMD_EXEC_FAILED
		&"gather":
			var rn: Variant = cmd.get("target", null)
			if rn != null and is_instance_valid(rn) and rn is ResourceNode and not (rn as Node).is_queued_for_deletion() and not (rn as ResourceNode).is_depleted():
				result = CMD_EXEC_ACTIVE if unit._start_gather(rn as ResourceNode) else CMD_EXEC_FAILED
		&"return_cargo":
			var drop_b: Variant = cmd.get("target", null)
			var drop_building: Building = drop_b as Building if (drop_b != null and is_instance_valid(drop_b) and drop_b is Building and not (drop_b as Building).is_destroyed) else null
			result = CMD_EXEC_ACTIVE if unit._start_return_cargo(drop_building) else CMD_EXEC_FAILED
		&"build":
			var build_t: Variant = cmd.get("target", null)
			if build_t != null and is_instance_valid(build_t) and build_t is Building and not (build_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if unit._start_construct_building(build_t as Building) else CMD_EXEC_FAILED
		&"staff":
			var staff_t: Variant = cmd.get("target", null)
			if staff_t != null and is_instance_valid(staff_t) and staff_t is Building and not (staff_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if unit._start_staff_building(staff_t as Building) else CMD_EXEC_FAILED
		&"cast_ability":
			var ab: AbilityData = cmd.get("ability", null) as AbilityData
			var raw_t: Variant = cmd.get("target", null)
			var t_unit: Unit = raw_t as Unit if (raw_t != null and is_instance_valid(raw_t) and raw_t is Unit) else null
			result = unit._start_cast_ability(ab, cmd.get("pos", unit.global_position) as Vector2, t_unit)
		&"patrol":
			result = CMD_EXEC_ACTIVE if unit._start_patrol(cmd.get("pos", unit.global_position) as Vector2) else CMD_EXEC_FAILED
		&"repair":
			var rep_t: Variant = cmd.get("target", null)
			if rep_t != null and is_instance_valid(rep_t) and rep_t is Node2D and not (rep_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if unit._start_repair(rep_t as Node2D) else CMD_EXEC_FAILED
		&"salvage":
			var salv_t: Variant = cmd.get("target", null)
			if salv_t != null and is_instance_valid(salv_t) and salv_t is Node2D and not (salv_t as Node).is_queued_for_deletion():
				result = CMD_EXEC_ACTIVE if unit._start_salvage(salv_t as Node2D) else CMD_EXEC_FAILED
	if result == CMD_EXEC_ACTIVE:
		unit.active_command = cmd.duplicate()
		unit.command_queue_changed.emit(unit)
	return result


static func get_active_destination(unit: Unit) -> Variant:
	match unit.command_state:
		Unit.CommandState.MOVING:
			return unit._move_destination
		Unit.CommandState.ATTACK_MOVING:
			return unit._attack_move_destination
		Unit.CommandState.ATTACKING_TARGET:
			if unit.current_target != null and is_instance_valid(unit.current_target):
				return unit.current_target.global_position
		Unit.CommandState.CASTING_ABILITY:
			if unit.ability_component != null and unit.ability_component.has_pending_cast():
				return unit.ability_component.get_pending_destination()
		Unit.CommandState.CONSTRUCTING:
			if unit._construction_target != null and is_instance_valid(unit._construction_target):
				return unit._construction_target.global_position
		Unit.CommandState.GATHERING:
			if unit.gather_component != null:
				if unit.gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and is_instance_valid(unit.gather_component.dropoff_building):
					return unit.gather_component.dropoff_building.global_position
				if is_instance_valid(unit.gather_component.target_node):
					return unit.gather_component.target_node.global_position
		Unit.CommandState.STAFFING_BUILDING:
			if unit.staff_component != null and is_instance_valid(unit.staff_component.target_building):
				return unit.staff_component.target_building.global_position
		Unit.CommandState.PATROLLING:
			if not unit.patrol_waypoints.is_empty():
				return unit.patrol_waypoints[clampi(unit.patrol_index, 0, unit.patrol_waypoints.size() - 1)]
		Unit.CommandState.REPAIRING:
			if unit.repair_component != null:
				var rep_node: Variant = unit.repair_component.get("target_entity")
				if rep_node is Node2D and is_instance_valid(rep_node):
					return (rep_node as Node2D).global_position
		Unit.CommandState.SALVAGING:
			if unit._salvage_target != null and is_instance_valid(unit._salvage_target):
				return unit._salvage_target.global_position
	return null
