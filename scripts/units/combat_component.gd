class_name CombatComponent
extends Node

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")

var _attack_cooldown_timer: float = 0.0


func tick_cooldown(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)


func can_attack(owner_unit: Unit) -> bool:
	return owner_unit != null and owner_unit.data != null and owner_unit.data.attack_damage > 0.0 and owner_unit.data.attack_range > 0.0


func is_valid_target(owner_unit: Unit, candidate: Variant) -> bool:
	if owner_unit == null or candidate == null or not is_instance_valid(candidate):
		return false
	if candidate is Unit:
		var u: Unit = candidate
		return not u.is_dead and not u.is_staffed and u.team != owner_unit.team
	if candidate is Building:
		var b: Building = candidate
		return not b.is_destroyed and b.team != owner_unit.team
	return false


func is_valid_target_in_range(owner_unit: Unit, candidate: Variant, max_range: float) -> bool:
	if not is_valid_target(owner_unit, candidate):
		return false
	var target_node: Node2D = candidate as Node2D
	return distance_to_target_edge(owner_unit, target_node) <= max_range


func distance_to_target_edge(owner_unit: Unit, target: Node2D) -> float:
	if owner_unit == null or target == null or not is_instance_valid(target):
		return INF
	var center_dist: float = owner_unit.global_position.distance_to(target.global_position)
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
	var other_r: float = 16.0
	if target is Unit:
		var u: Unit = target
		other_r = u.data.collision_radius if u.data != null else 16.0
	elif target is Building:
		other_r = (target as Building).footprint_radius
	return maxf(0.0, center_dist - my_r - other_r)


func find_nearest_enemy(owner_unit: Unit, max_range: float) -> Node2D:
	if owner_unit == null or not owner_unit.is_inside_tree():
		return null

	# Prioritize hostile units over structures when both are within range.
	var best_unit: Node2D = null
	var best_unit_dist: float = max_range
	for node: Node in owner_unit.get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var candidate: Unit = node
		if candidate.is_dead or candidate.is_staffed or candidate.team == owner_unit.team:
			continue
		var dist: float = distance_to_target_edge(owner_unit, candidate)
		if dist <= best_unit_dist:
			best_unit_dist = dist
			best_unit = candidate
	if best_unit != null:
		return best_unit

	var best_building: Node2D = null
	var best_building_dist: float = max_range
	for node: Node in owner_unit.get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.team == owner_unit.team:
			continue
		var dist: float = distance_to_target_edge(owner_unit, b)
		if dist <= best_building_dist:
			best_building_dist = dist
			best_building = b
	return best_building


func try_fire_at(owner_unit: Unit, target: Node2D) -> bool:
	if _attack_cooldown_timer > 0.0 or not is_valid_target(owner_unit, target):
		return false
	_attack_cooldown_timer = owner_unit.data.attack_cooldown
	var muzzle_offset: Vector2 = Vector2.RIGHT.rotated(owner_unit.body_visual.rotation) * owner_unit.data.collision_radius
	var tracer_origin: Vector2 = owner_unit.global_position + muzzle_offset
	var tracer_end: Vector2 = target.global_position
	_spawn_attack_tracer(owner_unit, tracer_origin, tracer_end)

	if target is Unit:
		(target as Unit).take_damage(owner_unit.data.attack_damage, owner_unit)
	elif target is Building:
		(target as Building).take_damage(owner_unit.data.attack_damage)
	return true


func _spawn_attack_tracer(owner_unit: Unit, from_pos: Vector2, to_pos: Vector2) -> void:
	if owner_unit.get_parent() == null:
		return
	if owner_unit.is_inside_tree():
		var fog: Node = owner_unit.get_tree().get_first_node_in_group("fog_of_war")
		if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
			if not fog.is_world_pos_visible(from_pos) and not fog.is_world_pos_visible(to_pos):
				return
	var tracer: AttackTracer = ATTACK_TRACER_SCRIPT.new()
	tracer.z_index = 50
	owner_unit.get_parent().add_child(tracer)
	var tracer_color: Color = Color(0.32, 0.98, 0.90, 0.95) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.35, 0.25, 0.95)
	tracer.setup(from_pos, to_pos, tracer_color)
