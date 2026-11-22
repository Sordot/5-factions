class_name AbilityComponent
extends Node

const ABILITY_EFFECT_SCRIPT: GDScript = preload("res://ui/overlays/ability_effect.gd")

signal ability_cooldown_updated(ability_id: StringName, remaining: float, duration: float)
signal ability_executed(ability_id: StringName, target_pos: Vector2)

var cooldowns: Dictionary = {}
var _durations: Dictionary = {}

var pending_ability: AbilityData = null
var pending_target_pos: Vector2 = Vector2.ZERO
var pending_target_unit: Unit = null


func get_remaining_cooldown(ability_id: StringName) -> float:
	if cooldowns.has(ability_id):
		return maxf(0.0, float(cooldowns[ability_id]))
	return 0.0


func is_ability_ready(ability: AbilityData) -> bool:
	if ability == null:
		return false
	return get_remaining_cooldown(ability.ability_id) <= 0.0


func has_pending_cast() -> bool:
	return pending_ability != null


func cancel_pending_cast() -> void:
	pending_ability = null
	pending_target_pos = Vector2.ZERO
	pending_target_unit = null


func tick_cooldowns(delta: float) -> void:
	if cooldowns.is_empty():
		return
	var keys: Array = cooldowns.keys()
	for raw_key: Variant in keys:
		var ability_id: StringName = raw_key
		var prev: float = float(cooldowns[ability_id])
		if prev <= 0.0:
			continue
		var next_val: float = maxf(0.0, prev - delta)
		cooldowns[ability_id] = next_val
		var duration: float = float(_durations.get(ability_id, 1.0))
		ability_cooldown_updated.emit(ability_id, next_val, duration)
		if next_val <= 0.0:
			cooldowns.erase(ability_id)


func request_cast(owner_unit: Unit, ability: AbilityData, target_pos: Vector2, target_unit: Unit = null) -> bool:
	if owner_unit == null or owner_unit.is_dead or not is_ability_ready(ability):
		return false

	if ability.target_type == AbilityData.TargetType.INSTANT:
		cancel_pending_cast()
		execute_ability(owner_unit, ability, owner_unit.global_position, owner_unit)
		return true

	if ability.target_type == AbilityData.TargetType.UNIT_TARGET:
		if target_unit == null or not is_instance_valid(target_unit) or target_unit.is_dead or target_unit.team == owner_unit.team:
			return false
		if is_in_cast_range(owner_unit, ability, target_unit.global_position, target_unit):
			cancel_pending_cast()
			execute_ability(owner_unit, ability, target_unit.global_position, target_unit)
			return true
		pending_ability = ability
		pending_target_pos = target_unit.global_position
		pending_target_unit = target_unit
		return true

	# POINT_AOE
	if is_in_cast_range(owner_unit, ability, target_pos, null):
		cancel_pending_cast()
		execute_ability(owner_unit, ability, target_pos, null)
		return true
	pending_ability = ability
	pending_target_pos = target_pos
	pending_target_unit = null
	return true


func is_in_cast_range(owner_unit: Unit, ability: AbilityData, target_pos: Vector2, target_unit: Unit = null) -> bool:
	if ability.cast_range <= 0.0 or ability.target_type == AbilityData.TargetType.INSTANT:
		return true
	if target_unit != null and is_instance_valid(target_unit):
		var center_dist: float = owner_unit.global_position.distance_to(target_unit.global_position)
		var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
		var other_r: float = target_unit.data.collision_radius if target_unit.data != null else 16.0
		return maxf(0.0, center_dist - my_r - other_r) <= ability.cast_range
	return owner_unit.global_position.distance_to(target_pos) <= ability.cast_range


func get_pending_destination() -> Vector2:
	if pending_target_unit != null and is_instance_valid(pending_target_unit):
		return pending_target_unit.global_position
	return pending_target_pos


func try_complete_pending_cast(owner_unit: Unit) -> bool:
	if pending_ability == null:
		return false
	if not is_ability_ready(pending_ability):
		cancel_pending_cast()
		return true
	if pending_ability.target_type == AbilityData.TargetType.UNIT_TARGET:
		if pending_target_unit == null or not is_instance_valid(pending_target_unit) or pending_target_unit.is_dead:
			cancel_pending_cast()
			return true

	var dest: Vector2 = get_pending_destination()
	if is_in_cast_range(owner_unit, pending_ability, dest, pending_target_unit):
		var ability_to_run: AbilityData = pending_ability
		var unit_target: Unit = pending_target_unit
		cancel_pending_cast()
		execute_ability(owner_unit, ability_to_run, dest, unit_target)
		return true
	return false


func execute_ability(owner_unit: Unit, ability: AbilityData, target_pos: Vector2, target_unit: Unit = null) -> void:
	var cd: float = maxf(0.0, ability.cooldown_duration)
	_durations[ability.ability_id] = maxf(0.01, cd)
	if cd > 0.0:
		cooldowns[ability.ability_id] = cd
		ability_cooldown_updated.emit(ability.ability_id, cd, cd)

	match ability.target_type:
		AbilityData.TargetType.POINT_AOE:
			_execute_point_aoe(owner_unit, ability, target_pos)
		AbilityData.TargetType.UNIT_TARGET:
			_execute_unit_target(owner_unit, ability, target_unit)
		AbilityData.TargetType.INSTANT:
			_execute_instant(owner_unit, ability)

	ability_executed.emit(ability.ability_id, target_pos)


func _execute_point_aoe(owner_unit: Unit, ability: AbilityData, target_pos: Vector2) -> void:
	_spawn_aoe_effect(owner_unit, target_pos, ability.aoe_radius)
	for node: Node in owner_unit.get_tree().get_nodes_in_group("units"):
		if not (node is Unit):
			continue
		var candidate: Unit = node
		if not is_instance_valid(candidate) or candidate.is_dead or candidate.team == owner_unit.team:
			continue
		var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
		if candidate.global_position.distance_to(target_pos) <= ability.aoe_radius + enemy_r:
			candidate.take_damage(ability.damage_or_value, owner_unit)


func _execute_unit_target(owner_unit: Unit, ability: AbilityData, target_unit: Unit) -> void:
	if target_unit == null or not is_instance_valid(target_unit) or target_unit.is_dead:
		return
	_spawn_aoe_effect(owner_unit, target_unit.global_position, maxf(24.0, ability.aoe_radius))
	target_unit.take_damage(ability.damage_or_value, owner_unit)


func _execute_instant(owner_unit: Unit, ability: AbilityData) -> void:
	owner_unit.heal(ability.damage_or_value)
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = ABILITY_EFFECT_SCRIPT.new()
	fx.z_index = 55
	owner_unit.get_parent().add_child(fx)
	fx.setup_self_pulse(owner_unit.global_position, maxf(32.0, ability.aoe_radius))


func _spawn_aoe_effect(owner_unit: Unit, target_pos: Vector2, radius: float) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = ABILITY_EFFECT_SCRIPT.new()
	fx.z_index = 55
	owner_unit.get_parent().add_child(fx)
	fx.setup_aoe(owner_unit.global_position, target_pos, radius)
