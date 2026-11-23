class_name CombatComponent
extends Node

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")
const ABILITY_EFFECT_SCRIPT: GDScript = preload("res://ui/overlays/ability_effect.gd")

var _attack_cooldown_timer: float = 0.0


func tick_cooldown(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)


func can_attack(owner_unit: Unit) -> bool:
	return owner_unit != null and owner_unit.data != null and owner_unit.data.attack_damage > 0.0 and owner_unit.data.attack_range > 0.0


func should_pursue_targets(owner_unit: Unit) -> bool:
	if owner_unit == null or not is_instance_valid(owner_unit):
		return false
	if owner_unit.stance == Unit.Stance.HOLD_POSITION:
		return false
	if owner_unit.data != null and (owner_unit.data.can_gather or owner_unit.data.can_staff_compute):
		return false
	return true


func is_valid_target(owner_unit: Unit, candidate: Variant) -> bool:
	if owner_unit == null or not is_instance_valid(owner_unit) or candidate == null or not is_instance_valid(candidate):
		return false
	if candidate is Unit:
		var u: Unit = candidate
		return not u.is_dead and not u.is_staffed and not u.is_queued_for_deletion() and u.team != owner_unit.team
	if candidate is Building:
		var b: Building = candidate
		return not b.is_destroyed and not b.is_queued_for_deletion() and b.team != owner_unit.team
	return false


func is_valid_target_in_range(owner_unit: Unit, candidate: Variant, max_range: float) -> bool:
	if not is_valid_target(owner_unit, candidate):
		return false
	var target_node: Node2D = candidate as Node2D
	var dist: float = distance_to_target_edge(owner_unit, target_node)
	var min_range: float = owner_unit.data.min_attack_range if owner_unit.data != null else 0.0
	return dist <= max_range and dist >= min_range


func is_within_attack_envelope(owner_unit: Unit, target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not is_valid_target(owner_unit, target) or owner_unit.data == null:
		return false
	var target_node: Node2D = target as Node2D
	var dist: float = distance_to_target_edge(owner_unit, target_node)
	return dist <= owner_unit.data.attack_range and dist >= owner_unit.data.min_attack_range


func is_target_inside_min_range(owner_unit: Unit, target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if owner_unit == null or owner_unit.data == null or owner_unit.data.min_attack_range <= 0.0:
		return false
	if not is_valid_target(owner_unit, target):
		return false
	return distance_to_target_edge(owner_unit, target as Node2D) < owner_unit.data.min_attack_range


func distance_to_target_edge(owner_unit: Unit, target: Variant) -> float:
	if owner_unit == null or not is_instance_valid(owner_unit) or target == null or not is_instance_valid(target) or not (target is Node2D):
		return INF
	var target_node: Node2D = target as Node2D
	var center_dist: float = owner_unit.global_position.distance_to(target_node.global_position)
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
	var other_r: float = 16.0
	if target_node is Unit:
		var u: Unit = target_node
		other_r = u.data.collision_radius if u.data != null else 16.0
	elif target_node is Building:
		other_r = (target_node as Building).footprint_radius
	return maxf(0.0, center_dist - my_r - other_r)


func find_nearest_enemy(owner_unit: Unit, max_range: float) -> Node2D:
	if owner_unit == null or not is_instance_valid(owner_unit) or not owner_unit.is_inside_tree():
		return null

	var min_range: float = owner_unit.data.min_attack_range if owner_unit.data != null else 0.0

	# Prioritize hostile units over structures when both are within valid attack envelope.
	var best_unit: Node2D = null
	var best_unit_dist: float = max_range
	for node: Node in owner_unit.get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var candidate: Unit = node
		if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion() or candidate.team == owner_unit.team:
			continue
		var dist: float = distance_to_target_edge(owner_unit, candidate)
		if dist >= min_range and dist <= best_unit_dist:
			best_unit_dist = dist
			best_unit = candidate
	if best_unit != null:
		return best_unit

	var best_building: Node2D = null
	var best_building_dist: float = max_range
	for node: Node in owner_unit.get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or b.team == owner_unit.team:
			continue
		var dist: float = distance_to_target_edge(owner_unit, b)
		if dist >= min_range and dist <= best_building_dist:
			best_building_dist = dist
			best_building = b
	return best_building


func try_fire_at(owner_unit: Unit, target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _attack_cooldown_timer > 0.0 or not is_within_attack_envelope(owner_unit, target):
		return false
	var target_node: Node2D = target as Node2D
	_attack_cooldown_timer = owner_unit.get_effective_attack_cooldown()
	var muzzle_offset: Vector2 = Vector2.RIGHT.rotated(owner_unit.body_visual.rotation) * owner_unit.data.collision_radius
	var tracer_origin: Vector2 = owner_unit.global_position + muzzle_offset
	var tracer_end: Vector2 = target_node.global_position

	var base_dmg: float = owner_unit.data.attack_damage
	var bonus_armored: float = owner_unit.data.bonus_vs_armored
	var aoe_radius: float = owner_unit.data.aoe_attack_radius
	var pierce_width: float = owner_unit.data.line_pierce_width

	if AudioManager != null and _is_pos_audible(owner_unit, tracer_origin, tracer_end):
		AudioManager.play_weapon_for_unit(owner_unit.get_unit_type_id())

	if aoe_radius > 0.0:
		# Arcing caustic mortar shell with splash AoE.
		var mortar_col: Color = Color(0.46, 1.0, 0.54, 0.95) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.44, 0.24, 0.95)
		_spawn_attack_tracer(owner_unit, tracer_origin, tracer_end, mortar_col, 3.2, 0.28, 46.0)
		_spawn_aoe_blast(owner_unit, tracer_end, aoe_radius, mortar_col)
		_apply_aoe_damage(owner_unit, tracer_end, aoe_radius, base_dmg, bonus_armored)
		return true

	if pierce_width > 0.0:
		# High-energy Arc-Lancer beam piercing/splashing in a tight line.
		var dir: Vector2 = (tracer_end - tracer_origin).normalized() if tracer_end.distance_squared_to(tracer_origin) > 1.0 else Vector2.RIGHT
		var beam_end: Vector2 = tracer_end + dir * 56.0
		var lance_col: Color = Color(0.48, 0.96, 1.0, 0.98) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.36, 0.30, 0.98)
		_spawn_attack_tracer(owner_unit, tracer_origin, beam_end, lance_col, 4.4, 0.18, 0.0)
		_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)
		_apply_line_pierce_damage(owner_unit, tracer_origin, beam_end, pierce_width, base_dmg * 0.65, bonus_armored, target_node)
		return true

	var tracer_color: Color = Color(0.32, 0.98, 0.90, 0.95) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.35, 0.25, 0.95)
	var width: float = 3.4 if bonus_armored > 0.0 else 2.5
	if bonus_armored > 0.0 and owner_unit.team == Unit.Team.PLAYER:
		tracer_color = Color(1.0, 0.78, 0.32, 0.96)
	_spawn_attack_tracer(owner_unit, tracer_origin, tracer_end, tracer_color, width, 0.12, 0.0)
	_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)
	return true


func _apply_damage_to_target(owner_unit: Unit, target: Variant, base_dmg: float, bonus_vs_armored: float) -> void:
	if not is_valid_target(owner_unit, target):
		return
	var total_dmg: float = base_dmg
	if target is Building:
		total_dmg += bonus_vs_armored
		(target as Building).take_damage(total_dmg)
	elif target is Unit:
		var u: Unit = target
		if u.data != null and u.data.is_armored:
			total_dmg += bonus_vs_armored
		u.take_damage(total_dmg, owner_unit)


func _apply_aoe_damage(owner_unit: Unit, center: Vector2, radius: float, base_dmg: float, bonus_vs_armored: float) -> void:
	if not is_instance_valid(owner_unit) or not owner_unit.is_inside_tree():
		return
	for node: Node in owner_unit.get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var candidate: Unit = node
		if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion() or candidate.team == owner_unit.team:
			continue
		var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
		if candidate.global_position.distance_to(center) <= radius + enemy_r:
			_apply_damage_to_target(owner_unit, candidate, base_dmg, bonus_vs_armored)

	for node: Node in owner_unit.get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or b.team == owner_unit.team:
			continue
		if b.global_position.distance_to(center) <= radius + b.footprint_radius:
			_apply_damage_to_target(owner_unit, b, base_dmg, bonus_vs_armored)


func _apply_line_pierce_damage(
	owner_unit: Unit,
	seg_start: Vector2,
	seg_end: Vector2,
	half_width: float,
	pierce_dmg: float,
	bonus_vs_armored: float,
	primary_target: Variant
) -> void:
	if not is_instance_valid(owner_unit) or not owner_unit.is_inside_tree():
		return
	for node: Node in owner_unit.get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit) or node == primary_target:
			continue
		var candidate: Unit = node
		if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion() or candidate.team == owner_unit.team:
			continue
		var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(candidate.global_position, seg_start, seg_end)
		if candidate.global_position.distance_to(closest) <= half_width + enemy_r:
			_apply_damage_to_target(owner_unit, candidate, pierce_dmg, bonus_vs_armored)

	for node: Node in owner_unit.get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building) or node == primary_target:
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or b.team == owner_unit.team:
			continue
		var closest_b: Vector2 = Geometry2D.get_closest_point_to_segment(b.global_position, seg_start, seg_end)
		if b.global_position.distance_to(closest_b) <= half_width + b.footprint_radius:
			_apply_damage_to_target(owner_unit, b, pierce_dmg, bonus_vs_armored)


func _spawn_attack_tracer(
	owner_unit: Unit,
	from_pos: Vector2,
	to_pos: Vector2,
	tracer_color: Color,
	width: float = 2.5,
	tracer_duration: float = 0.12,
	arc_height: float = 0.0
) -> void:
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
	tracer.setup(from_pos, to_pos, tracer_color, width, tracer_duration, arc_height)


func _spawn_aoe_blast(owner_unit: Unit, center: Vector2, radius: float, blast_color: Color) -> void:
	if owner_unit.get_parent() == null:
		return
	if owner_unit.is_inside_tree():
		var fog: Node = owner_unit.get_tree().get_first_node_in_group("fog_of_war")
		if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
			if not fog.is_world_pos_visible(center):
				return
	var fx: AbilityEffect = ABILITY_EFFECT_SCRIPT.new()
	fx.z_index = 52
	owner_unit.get_parent().add_child(fx)
	fx.setup_self_pulse(center, radius, blast_color)


func _is_pos_audible(owner_unit: Unit, from_pos: Vector2, to_pos: Vector2) -> bool:
	if owner_unit == null or not owner_unit.is_inside_tree():
		return false
	if owner_unit.team == Unit.Team.PLAYER:
		return true
	var fog: Node = owner_unit.get_tree().get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
		return fog.is_world_pos_visible(from_pos) or fog.is_world_pos_visible(to_pos)
	return true
