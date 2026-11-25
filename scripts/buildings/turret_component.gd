class_name TurretComponent
extends Node

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")
const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")

const SCAN_INTERVAL: float = 0.22
const FIRE_ALIGN_TOLERANCE: float = 0.24
const TIER_COMBAT_UNIT: int = 1
const TIER_SUPPORT_OR_ECON: int = 2
const TIER_BUILDING: int = 3

var owner_building: Building = null
var turret_angle: float = 0.0
var recoil_offset: float = 0.0
var cooldown: float = 0.0
var current_target: Node2D = null
var explicit_target: Node2D = null

var _scan_timer: float = 0.0


func bind_building(building: Building) -> void:
	owner_building = building
	if owner_building != null:
		turret_angle = 0.0 if int(owner_building.team) == 0 else PI


func set_explicit_target(target: Node2D) -> bool:
	if owner_building == null or owner_building.is_destroyed or not owner_building.is_constructed or owner_building.is_salvaging:
		return false
	if not is_valid_target(target) or not is_in_attack_range(target):
		return false
	explicit_target = target
	current_target = target
	return true


func clear_explicit_target() -> void:
	explicit_target = null


func tick(delta: float) -> void:
	if owner_building == null or not is_instance_valid(owner_building) or owner_building.is_destroyed:
		return
	if recoil_offset > 0.0:
		recoil_offset = maxf(0.0, recoil_offset - delta * 26.0)
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)

	if not owner_building.is_constructed or owner_building.is_salvaging:
		current_target = null
		explicit_target = null
		return

	# Validate explicit focus-fire target first
	if explicit_target != null:
		if not is_valid_target(explicit_target) or not is_in_attack_range(explicit_target):
			if current_target == explicit_target:
				current_target = null
			explicit_target = null

	if explicit_target != null:
		current_target = explicit_target
	else:
		if current_target != null and (not is_valid_target(current_target) or not is_in_attack_range(current_target)):
			current_target = null
		_scan_timer += delta
		if _scan_timer >= SCAN_INTERVAL or current_target == null:
			_scan_timer = 0.0
			var best: Node2D = _find_best_target()
			if best != null:
				current_target = best

	if current_target == null or not is_instance_valid(current_target):
		return

	var to_target: Vector2 = current_target.global_position - owner_building.global_position
	if to_target.length_squared() <= 0.01:
		return
	var desired_angle: float = to_target.angle()
	var turn_spd: float = maxf(1.0, owner_building.turret_turn_speed)
	var diff: float = angle_difference(turret_angle, desired_angle)
	var max_step: float = turn_spd * delta
	if absf(diff) <= max_step:
		turret_angle = desired_angle
	else:
		turret_angle = wrapf(turret_angle + signf(diff) * max_step, -PI, PI)

	if absf(angle_difference(turret_angle, desired_angle)) <= FIRE_ALIGN_TOLERANCE and cooldown <= 0.0:
		if is_in_attack_range(current_target):
			_fire_at(current_target)


func _are_teams_hostile(team_a: int, team_b: int) -> bool:
	if TeamManager != null:
		return TeamManager.are_enemies(team_a, team_b)
	return team_a != team_b


func can_target_entity(target: Node2D) -> bool:
	if owner_building == null or not is_instance_valid(owner_building) or target == null or not is_instance_valid(target):
		return false
	if target is Unit:
		var u: Unit = target as Unit
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			return false
		if not _are_teams_hostile(int(owner_building.team), int(u.team)):
			return false
		if u.has_method("has_unit_tag"):
			if bool(u.call("has_unit_tag", &"untargetable")) or bool(u.call("has_unit_tag", &"phase_invulnerable")):
				return false
		return true
	if target is Building:
		var b: Building = target as Building
		return not b.is_destroyed and not b.is_queued_for_deletion() and _are_teams_hostile(int(owner_building.team), int(b.team))
	if target.is_in_group("destructible_barricades"):
		return not bool(target.get("is_destroyed")) and not target.is_queued_for_deletion()
	return false


func is_valid_target(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Node2D):
		return false
	return can_target_entity(candidate as Node2D)


func distance_to_target_edge(target: Node2D) -> float:
	if owner_building == null or not is_instance_valid(owner_building) or target == null or not is_instance_valid(target):
		return INF
	var center_dist: float = owner_building.global_position.distance_to(target.global_position)
	var my_r: float = owner_building.footprint_radius
	var other_r: float = 16.0
	if target is Unit:
		var u: Unit = target
		other_r = u.data.collision_radius if u.data != null else 16.0
	elif target is Building:
		other_r = (target as Building).footprint_radius
	elif target.is_in_group("destructible_barricades") and target.has_method("get_footprint_radius"):
		other_r = float(target.call("get_footprint_radius"))
	return maxf(0.0, center_dist - my_r - other_r)


func is_in_attack_range(target: Node2D) -> bool:
	if owner_building == null or target == null or not is_instance_valid(target):
		return false
	var dist: float = distance_to_target_edge(target)
	return dist <= owner_building.turret_attack_range and dist >= owner_building.turret_min_range


func _get_priority_tier(candidate: Node2D) -> int:
	if candidate is Building:
		return TIER_BUILDING
	if candidate is Unit:
		var u: Unit = candidate
		if u.data == null:
			return TIER_SUPPORT_OR_ECON
		var uid: StringName = u.data.unit_type_id
		if u.data.can_gather or u.data.can_staff_compute:
			return TIER_SUPPORT_OR_ECON
		if uid == &"symbiote" or uid == &"signal_jammer" or uid == &"worker" or uid == &"silica_harvester" or uid == &"engineer" or uid == &"target_dummy":
			return TIER_SUPPORT_OR_ECON
		if u.data.attack_damage > 0.0:
			return TIER_COMBAT_UNIT
		return TIER_SUPPORT_OR_ECON
	return TIER_BUILDING


func _score_candidate(candidate: Node2D, dist: float, max_range: float) -> float:
	var tier: int = _get_priority_tier(candidate)
	var score: float = 100.0
	if tier == TIER_COMBAT_UNIT:
		score = 1000.0
	elif tier == TIER_SUPPORT_OR_ECON:
		score = 500.0

	if candidate is Unit:
		var u: Unit = candidate
		if u.current_target != null and is_instance_valid(u.current_target):
			if u.current_target == owner_building:
				score += 180.0
			elif u.current_target is Unit and (u.current_target as Unit).team == owner_building.team:
				if (u.current_target as Unit).global_position.distance_squared_to(owner_building.global_position) <= 280.0 * 280.0:
					score += 95.0
			elif u.current_target is Building and (u.current_target as Building).team == owner_building.team:
				score += 110.0

		if owner_building.turret_bonus_vs_armored > 1.0 and u.data != null and u.data.is_armored:
			score += 240.0

		if u.data != null and u.data.max_hp > 0.0:
			var hp_ratio: float = clampf(u.current_hp / u.data.max_hp, 0.0, 1.0)
			score += (1.0 - hp_ratio) * 35.0
	elif candidate is Building and owner_building.turret_bonus_vs_armored > 1.0:
		score += 80.0

	var norm_dist: float = clampf(dist / maxf(1.0, max_range), 0.0, 1.5)
	score -= norm_dist * 220.0
	return score


func _find_best_target() -> Node2D:
	if owner_building == null or not owner_building.is_inside_tree():
		return null
	var max_range: float = owner_building.turret_attack_range
	var min_range: float = owner_building.turret_min_range
	var query_r: float = max_range + owner_building.footprint_radius + 20.0
	var best_target: Node2D = null
	var best_score: float = -INF

	var unit_candidates: Array = SpatialGrid.query_units_in_radius(owner_building.global_position, query_r) if SpatialGrid != null else owner_building.get_tree().get_nodes_in_group("units")
	for node: Variant in unit_candidates:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var u: Unit = node
		if not can_target_entity(u):
			continue
		var dist: float = distance_to_target_edge(u)
		if dist < min_range or dist > max_range:
			continue
		var s: float = _score_candidate(u, dist, max_range)
		if s > best_score:
			best_score = s
			best_target = u

	if best_target != null:
		return best_target

	var bldg_candidates: Array = SpatialGrid.query_buildings_in_radius(owner_building.global_position, query_r) if SpatialGrid != null else owner_building.get_tree().get_nodes_in_group("buildings")
	for node: Variant in bldg_candidates:
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node
		if not can_target_entity(b):
			continue
		var dist: float = distance_to_target_edge(b)
		if dist < min_range or dist > max_range:
			continue
		var s: float = _score_candidate(b, dist, max_range)
		if s > best_score:
			best_score = s
			best_target = b

	return best_target


func _is_armored_target(target: Variant) -> bool:
	if target is Building:
		return true
	if target is Node and (target as Node).is_in_group("destructible_barricades"):
		return bool((target as Node).get("is_armored"))
	if target is Unit:
		var u: Unit = target
		return u.data != null and u.data.is_armored
	return false


func _compute_damage(target: Variant) -> float:
	var dmg: float = maxf(0.0, owner_building.turret_damage)
	if owner_building.turret_bonus_vs_armored > 1.0 and _is_armored_target(target):
		dmg *= owner_building.turret_bonus_vs_armored
	return dmg


func _fire_at(target: Node2D) -> void:
	if owner_building == null or not is_instance_valid(owner_building) or target == null or not is_instance_valid(target):
		return
	cooldown = maxf(0.12, owner_building.turret_attack_interval)
	recoil_offset = 4.5

	var muzzle_dist: float = maxf(18.0, owner_building.footprint_radius * 0.78)
	var origin: Vector2 = owner_building.global_position + Vector2.RIGHT.rotated(turret_angle) * muzzle_dist
	var end_pos: Vector2 = target.global_position
	var style: StringName = owner_building.turret_tracer_style
	var team_col: Color = TeamManager.get_team_color(int(owner_building.team)) if TeamManager != null else (Color(0.24, 0.96, 0.90, 1.0) if owner_building.team == Unit.Team.PLAYER else Color(1.0, 0.36, 0.28, 1.0))

	if AudioManager != null and _is_audible(origin, end_pos):
		match style:
			&"rail":
				AudioManager.play_weapon_for_unit(&"lance_rig", owner_building.global_position)
			&"mortar":
				AudioManager.play_weapon_for_unit(&"chrysalis_mortar", owner_building.global_position)
			&"heavy":
				AudioManager.play_weapon_for_unit(&"goliath_frame", owner_building.global_position)
			&"heavy_slug":
				AudioManager.play_sfx(&"weapon_mono_bastion", -4.0, 0.05, owner_building.global_position, true)
			_:
				AudioManager.play_weapon_for_unit(&"clone_trooper", owner_building.global_position)
		if AudioManager.has_method("notify_combat_activity"):
			AudioManager.call("notify_combat_activity", 0.25)

	if owner_building.turret_splash_radius > 0.0 or style == &"mortar":
		var splash_r: float = maxf(40.0, owner_building.turret_splash_radius)
		var flight_dist: float = origin.distance_to(end_pos)
		var flight_time: float = clampf(flight_dist / 560.0, 0.34, 0.52)
		var arc_h: float = clampf(flight_dist * 0.25, 44.0, 80.0)
		var tree: SceneTree = owner_building.get_tree()
		var atk_bldg: Building = owner_building
		var atk_team: int = int(owner_building.team)
		var base_dmg: float = owner_building.turret_damage
		var armor_mult: float = owner_building.turret_bonus_vs_armored
		var impact_pos: Vector2 = end_pos
		var on_impact: Callable = func() -> void:
			var valid_atk: Building = atk_bldg if (is_instance_valid(atk_bldg) and not atk_bldg.is_destroyed) else null
			_apply_splash_damage(tree, valid_atk, atk_team, impact_pos, splash_r, base_dmg, armor_mult)
		_spawn_mortar_vfx(origin, impact_pos, splash_r, flight_time, arc_h, team_col, on_impact)
		return

	match style:
		&"rail":
			var rail_col: Color = Color(1.0, 0.82, 0.34, 0.98) if int(owner_building.team) == 0 else team_col
			_spawn_tracer(origin, end_pos, rail_col, 3.2, 0.16, AttackTracer.TracerStyle.RAIL_BEAM)
			if _is_armored_target(target) and owner_building.turret_bonus_vs_armored > 1.0:
				var shot_dir: Vector2 = (end_pos - origin).normalized() if end_pos.distance_squared_to(origin) > 1.0 else Vector2.RIGHT
				_spawn_armor_spark(end_pos, shot_dir, Color(1.0, 0.88, 0.36, 1.0))
		&"heavy_slug":
			var slug_col: Color = Color(1.0, 0.68, 0.18, 0.98) if int(owner_building.team) == 0 else team_col
			_spawn_tracer(origin, end_pos, slug_col, 3.2, 0.15, AttackTracer.TracerStyle.HEAVY_SLUG)
			if _is_armored_target(target) and owner_building.turret_bonus_vs_armored > 1.0:
				var shot_dir_hs: Vector2 = (end_pos - origin).normalized() if end_pos.distance_squared_to(origin) > 1.0 else Vector2.RIGHT
				_spawn_armor_spark(end_pos, shot_dir_hs, Color(1.0, 0.72, 0.20, 1.0))
		&"heavy":
			_spawn_tracer(origin, end_pos, team_col, 3.0, 0.14, AttackTracer.TracerStyle.TWIN_SLUG)
		_:
			_spawn_tracer(origin, end_pos, team_col, 2.4, 0.12, AttackTracer.TracerStyle.PULSE_BOLT)

	_apply_direct_damage(target, _compute_damage(target))


func _apply_direct_damage(target: Node2D, dmg: float) -> void:
	if not is_valid_target(target) or dmg <= 0.0:
		return
	if target is Unit:
		(target as Unit).take_damage(dmg, owner_building)
	elif target is Building:
		(target as Building).take_damage(dmg, owner_building)
	elif target.is_in_group("destructible_barricades"):
		target.call("take_damage", dmg, owner_building)


func _apply_splash_damage(
	tree: SceneTree,
	attacker: Building,
	attacker_team: int,
	center: Vector2,
	radius: float,
	base_dmg: float,
	armor_mult: float
) -> void:
	if tree == null or base_dmg <= 0.0:
		return
	var entities: Array = SpatialGrid.query_entities_in_radius(center, radius, true, true) if SpatialGrid != null else tree.get_nodes_in_group("units")
	for node: Variant in entities:
		if not is_instance_valid(node):
			continue
		if node is Unit:
			var u: Unit = node
			if u.is_dead or u.is_staffed or u.is_queued_for_deletion() or not _are_teams_hostile(attacker_team, int(u.team)):
				continue
			var r: float = u.data.collision_radius if u.data != null else 16.0
			if u.global_position.distance_to(center) <= radius + r:
				var d: float = base_dmg * (armor_mult if (armor_mult > 1.0 and u.data != null and u.data.is_armored) else 1.0)
				u.take_damage(d, attacker)
		elif node is Building:
			var b: Building = node
			if b.is_destroyed or b.is_queued_for_deletion() or not _are_teams_hostile(attacker_team, int(b.team)):
				continue
			if b.global_position.distance_to(center) <= radius + b.footprint_radius:
				var db: float = base_dmg * (armor_mult if armor_mult > 1.0 else 1.0)
				b.take_damage(db, attacker)
		elif node is Node2D and (node as Node).is_in_group("destructible_barricades"):
			var bar: Node2D = node as Node2D
			if bool(bar.get("is_destroyed")) or bar.is_queued_for_deletion():
				continue
			var bar_r: float = float(bar.call("get_footprint_radius")) if bar.has_method("get_footprint_radius") else 40.0
			if bar.global_position.distance_to(center) <= radius + bar_r:
				var dbar: float = base_dmg * (armor_mult if (armor_mult > 1.0 and bool(bar.get("is_armored"))) else 1.0)
				bar.call("take_damage", dbar, attacker)


func _is_audible(origin: Vector2, target_pos: Vector2) -> bool:
	if owner_building == null or not owner_building.is_inside_tree():
		return false
	if TeamManager != null and TeamManager.is_team_controlled_by_local_human(int(owner_building.team)):
		return true
	var fog: Node = owner_building.get_tree().get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
		return bool(fog.call("is_world_pos_visible", origin)) or bool(fog.call("is_world_pos_visible", target_pos))
	return true


func _spawn_tracer(origin: Vector2, end_pos: Vector2, col: Color, width: float, duration: float, style: int) -> void:
	if owner_building == null or not owner_building.is_inside_tree():
		return
	var host: Node = owner_building.get_parent()
	if host == null:
		return
	var fog: Node = owner_building.get_tree().get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
		if not bool(fog.call("is_world_pos_visible", origin)) and not bool(fog.call("is_world_pos_visible", end_pos)):
			return
	var tracer: AttackTracer = VFXPool.acquire_attack_tracer(45) if VFXPool != null else null
	if tracer == null:
		tracer = ATTACK_TRACER_SCRIPT.new() as AttackTracer
		tracer.z_index = 45
		host.add_child(tracer)
	tracer.setup(origin, end_pos, col, width, duration, 0.0, style)


func _spawn_armor_spark(world_pos: Vector2, shot_dir: Vector2, col: Color) -> void:
	if owner_building == null or not owner_building.is_inside_tree():
		return
	var host: Node = owner_building.get_parent()
	if host == null:
		return
	var fx: CombatVFX = VFXPool.acquire_combat_vfx(48) if VFXPool != null else null
	if fx == null:
		fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
		fx.z_index = 48
		host.add_child(fx)
	fx.setup_armor_pierce_spark(world_pos, shot_dir, col)


func _spawn_mortar_vfx(
	origin: Vector2,
	impact_pos: Vector2,
	splash_r: float,
	flight_time: float,
	arc_h: float,
	col: Color,
	on_impact: Callable
) -> void:
	if owner_building == null or not owner_building.is_inside_tree():
		if on_impact.is_valid():
			on_impact.call()
		return
	var host: Node = owner_building.get_parent()
	if host == null:
		if on_impact.is_valid():
			on_impact.call()
		return
	var fx: CombatVFX = VFXPool.acquire_combat_vfx(50) if VFXPool != null else null
	if fx == null:
		fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
		fx.z_index = 50
		host.add_child(fx)
	fx.setup_mortar_shell(origin, impact_pos, splash_r, flight_time, arc_h, col, on_impact)
