class_name CombatTargeting
extends RefCounted

## Unified, faction-agnostic targeting, threat-priority, hostility/alliance,
## and Fog-of-War vision helper shared by CombatComponent, TurretComponent,
## AbilityComponent, and CombatOrdnanceManager.

const TIER_COMBAT_UNIT: int = 1
const TIER_SUPPORT_OR_ECON: int = 2
const TIER_BUILDING: int = 3


static func are_teams_hostile(team_a: int, team_b: int) -> bool:
	if TeamManager != null:
		return TeamManager.are_enemies(team_a, team_b)
	return team_a != team_b


static func are_teams_allied(team_a: int, team_b: int) -> bool:
	if team_a == team_b:
		return true
	if TeamManager != null:
		return TeamManager.are_allies(team_a, team_b)
	return false


static func is_world_pos_visible_to_team(fog: FogOfWarSystem, observer_team: int, world_pos: Vector2) -> bool:
	if fog == null or not is_instance_valid(fog) or not fog.fog_enabled:
		return true
	return fog.is_world_pos_visible_to_team(observer_team, world_pos)


static func get_entity_radius(entity: Node2D) -> float:
	if entity == null or not is_instance_valid(entity):
		return 16.0
	if entity is Unit:
		var u: Unit = entity as Unit
		return u.data.collision_radius if u.data != null else 16.0
	if entity is Building:
		return (entity as Building).footprint_radius
	if entity.is_in_group("destructible_barricades") and entity.has_method("get_footprint_radius"):
		return float(entity.call("get_footprint_radius"))
	return 16.0


static func distance_between_edges(origin_pos: Vector2, origin_radius: float, target: Node2D) -> float:
	if target == null or not is_instance_valid(target):
		return INF
	var center_dist: float = origin_pos.distance_to(target.global_position)
	var other_r: float = get_entity_radius(target)
	return maxf(0.0, center_dist - origin_radius - other_r)


static func is_armored_target(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Building:
		return true
	if target is Node and (target as Node).is_in_group("destructible_barricades"):
		return bool((target as Node).get("is_armored"))
	if target is Unit:
		var u: Unit = target as Unit
		return u.data != null and u.data.is_armored
	return false


static func get_priority_tier(candidate: Variant) -> int:
	if candidate == null or not is_instance_valid(candidate):
		return TIER_BUILDING
	if candidate is Building:
		return TIER_BUILDING
	if candidate is Unit:
		var u: Unit = candidate as Unit
		if u.data == null:
			return TIER_SUPPORT_OR_ECON
		if u.data.is_worker_class() or u.data.has_tag(&"support") or u.data.has_tag(&"dummy"):
			return TIER_SUPPORT_OR_ECON
		if u.data.attack_damage > 0.0:
			return TIER_COMBAT_UNIT
		return TIER_SUPPORT_OR_ECON
	return TIER_BUILDING


static func can_team_target_entity(observer_team: int, target: Node2D, fog: FogOfWarSystem) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Unit:
		var u: Unit = target as Unit
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			return false
		if not are_teams_hostile(observer_team, int(u.team)):
			return false
		if u.has_method("has_unit_tag"):
			if bool(u.call("has_unit_tag", &"untargetable")) or bool(u.call("has_unit_tag", &"phase_invulnerable")):
				return false
		return is_world_pos_visible_to_team(fog, observer_team, u.global_position)
	if target is Building:
		var b: Building = target as Building
		if b.is_destroyed or b.is_queued_for_deletion():
			return false
		if not are_teams_hostile(observer_team, int(b.team)):
			return false
		return is_world_pos_visible_to_team(fog, observer_team, b.global_position)
	if target.is_in_group("destructible_barricades"):
		return not bool(target.get("is_destroyed")) and not target.is_queued_for_deletion()
	return false


static func score_target_candidate(
	observer_node: Node2D,
	observer_team: int,
	candidate: Node2D,
	dist: float,
	max_range: float,
	prefers_armored: bool
) -> float:
	var tier: int = get_priority_tier(candidate)
	var score: float = 100.0
	if tier == TIER_COMBAT_UNIT:
		score = 1000.0
	elif tier == TIER_SUPPORT_OR_ECON:
		score = 500.0

	var obs_pos: Vector2 = observer_node.global_position if (observer_node != null and is_instance_valid(observer_node)) else Vector2.ZERO
	var is_building_observer: bool = observer_node is Building
	var ally_defend_r_sq: float = (280.0 * 280.0) if is_building_observer else (260.0 * 260.0)

	if candidate is Unit:
		var u: Unit = candidate as Unit
		# Prioritize enemies actively attacking this observer or nearby allied units/buildings (2v2-safe)
		if u.current_target != null and is_instance_valid(u.current_target):
			if u.current_target == observer_node:
				score += 180.0
			elif u.current_target is Unit and are_teams_allied(observer_team, int((u.current_target as Unit).team)):
				if (u.current_target as Unit).global_position.distance_squared_to(obs_pos) <= ally_defend_r_sq:
					score += 95.0
			elif is_building_observer and u.current_target is Building and are_teams_allied(observer_team, int((u.current_target as Building).team)):
				score += 110.0

		if prefers_armored and u.data != null and u.data.is_armored:
			score += 240.0

		if u.data != null and u.data.max_hp > 0.0:
			var hp_ratio: float = clampf(u.current_hp / u.data.max_hp, 0.0, 1.0)
			score += (1.0 - hp_ratio) * 35.0
	elif is_building_observer and candidate is Building and prefers_armored:
		score += 80.0

	var norm_dist: float = clampf(dist / maxf(1.0, max_range), 0.0, 1.5)
	score -= norm_dist * 220.0
	return score
