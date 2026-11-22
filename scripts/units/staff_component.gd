class_name StaffComponent
extends Node

signal staffing_target_changed(building: Building)

var target_building: Building = null
var staffed_building: Building = null


func is_active() -> bool:
	return target_building != null


func is_staffed() -> bool:
	return staffed_building != null and is_instance_valid(staffed_building)


func start_staffing(owner_unit: Unit, building: Building) -> bool:
	if owner_unit == null or not owner_unit.can_staff_compute():
		return false
	if building == null or not is_instance_valid(building) or not building.can_accept_staff(owner_unit):
		return false
	target_building = building
	staffing_target_changed.emit(building)
	return true


func cancel() -> void:
	if target_building == null:
		return
	target_building = null
	staffing_target_changed.emit(null)


func tick(owner_unit: Unit, _delta: float) -> void:
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed:
		cancel()
		return
	if target_building == null or not is_instance_valid(target_building) or not target_building.can_accept_staff(owner_unit):
		cancel()
		owner_unit.stop_component_navigation()
		owner_unit.command_state = Unit.CommandState.IDLE
		return

	var unit_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 13.0
	var reach: float = target_building.footprint_radius + unit_r + 22.0
	var dist: float = owner_unit.global_position.distance_to(target_building.global_position)
	if dist <= reach:
		owner_unit.stop_component_navigation()
		var building: Building = target_building
		target_building = null
		if building.assign_engineer(owner_unit):
			staffed_building = building
		else:
			owner_unit.command_state = Unit.CommandState.IDLE
		staffing_target_changed.emit(null)
		return

	var offset: Vector2 = owner_unit.global_position - target_building.global_position
	var dir: Vector2 = offset.normalized() if offset.length_squared() > 0.01 else Vector2.RIGHT
	var approach: Vector2 = target_building.global_position + dir * (target_building.footprint_radius * 0.75)
	owner_unit.request_component_navigation(approach, 12.0)
