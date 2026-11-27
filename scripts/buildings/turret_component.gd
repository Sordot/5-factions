class_name TurretComponent
extends Node

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")
const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")

const SCAN_INTERVAL: float = 0.22
const FIRE_ALIGN_TOLERANCE: float = 0.24
const TIER_COMBAT_UNIT: int = CombatTargeting.TIER_COMBAT_UNIT
const TIER_SUPPORT_OR_ECON: int = CombatTargeting.TIER_SUPPORT_OR_ECON
const TIER_BUILDING: int = CombatTargeting.TIER_BUILDING

var owner_building: Building = null
var turret_angle: float = 0.0
var recoil_offset: float = 0.0
var cooldown: float = 0.0
var current_target: Node2D = null
var explicit_target: Node2D = null

var _scan_timer: float = 0.0
var _fog_cache: FogOfWarSystem = null
var _scratch_units: Array = []


func bind_building(building: Building) -> void:
	owner_building = building
	if owner_building != null:
		turret_angle = 0.0 if int(owner_building.team) == 0 else PI


func set_explicit_target(target: Node2D) -> bool:
	if owner_building == null or owner_building.is_destroyed or not owner_building.is_constructed or not owner_building.is_powered or owner_building.is_salvaging:
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

	if not owner_building.is_constructed or not owner_building.is_powered or owner_building.is_salvaging:
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


func _get_fog() -> FogOfWarSystem:
	if _fog_cache != null and is_instance_valid(_fog_cache):
		return _fog_cache
	if owner_building != null and owner_building.is_inside_tree():
		_fog_cache = owner_building.get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
		return _fog_cache
	return null


func _are_teams_hostile(team_a: int, team_b: int) -> bool:
	return CombatTargeting.are_teams_hostile(team_a, team_b)


func can_target_entity(target: Node2D) -> bool:
	if owner_building == null or not is_instance_valid(owner_building) or target == null or not is_instance_valid(target):
		return false
	return CombatTargeting.can_team_target_entity(int(owner_building.team), target, _get_fog())


func is_valid_target(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Node2D):
		return false
	return can_target_entity(candidate as Node2D)


func distance_to_target_edge(target: Node2D) -> float:
	if owner_building == null or not is_instance_valid(owner_building) or target == null or not is_instance_valid(target):
		return INF
	return CombatTargeting.distance_between_edges(owner_building.global_position, owner_building.footprint_radius, target)


func _get_effective_turret_range() -> float:
	if owner_building == null:
		return 0.0
	return owner_building.get_effective_turret_attack_range()


func _get_effective_turret_damage() -> float:
	if owner_building == null:
		return 0.0
	return owner_building.get_effective_turret_damage()


func is_in_attack_range(target: Node2D) -> bool:
	if owner_building == null or target == null or not is_instance_valid(target):
		return false
	var dist: float = distance_to_target_edge(target)
	return dist <= _get_effective_turret_range() and dist >= owner_building.turret_min_range


func _get_priority_tier(candidate: Node2D) -> int:
	return CombatTargeting.get_priority_tier(candidate)


func _score_candidate(candidate: Node2D, dist: float, max_range: float) -> float:
	var prefers_armored: bool = owner_building != null and owner_building.turret_bonus_vs_armored > 1.0
	return CombatTargeting.score_target_candidate(owner_building, int(owner_building.team), candidate, dist, max_range, prefers_armored)


func _find_best_target() -> Node2D:
	if owner_building == null or not owner_building.is_inside_tree():
		return null
	var fog: FogOfWarSystem = _get_fog()
	var obs_team: int = int(owner_building.team)
	var prefers_armored: bool = owner_building.turret_bonus_vs_armored > 1.0
	var max_range: float = _get_effective_turret_range()
	var min_range: float = owner_building.turret_min_range
	var my_r: float = owner_building.footprint_radius
	var query_r: float = max_range + my_r + 20.0
	var best_target: Node2D = null
	var best_score: float = -INF

	if SpatialGrid != null:
		SpatialGrid.query_units_into(owner_building.global_position, query_r, _scratch_units)
	else:
		_scratch_units.clear()
		for n_u: Node in owner_building.get_tree().get_nodes_in_group("units"):
			_scratch_units.append(n_u)

	for node: Variant in _scratch_units:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var u: Unit = node as Unit
		if not CombatTargeting.can_team_target_entity(obs_team, u, fog):
			continue
		var dist: float = CombatTargeting.distance_between_edges(owner_building.global_position, my_r, u)
		if dist < min_range or dist > max_range:
			continue
		var s: float = CombatTargeting.score_target_candidate(owner_building, obs_team, u, dist, max_range, prefers_armored)
		if s > best_score:
			best_score = s
			best_target = u

	if best_target != null:
		return best_target

	var bldg_candidates: Array = SpatialGrid.query_buildings_in_radius(owner_building.global_position, query_r) if SpatialGrid != null else owner_building.get_tree().get_nodes_in_group("buildings")
	for node: Variant in bldg_candidates:
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if not CombatTargeting.can_team_target_entity(obs_team, b, fog):
			continue
		var dist: float = CombatTargeting.distance_between_edges(owner_building.global_position, my_r, b)
		if dist < min_range or dist > max_range:
			continue
		var s: float = CombatTargeting.score_target_candidate(owner_building, obs_team, b, dist, max_range, prefers_armored)
		if s > best_score:
			best_score = s
			best_target = b

	return best_target


func _is_armored_target(target: Variant) -> bool:
	return CombatTargeting.is_armored_target(target)


func _compute_damage(target: Variant) -> float:
	var dmg: float = maxf(0.0, _get_effective_turret_damage())
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
		var sfx_pos: Vector2 = owner_building.global_position if _is_point_visible_local(origin) else end_pos
		match style:
			&"rail":
				AudioManager.play_weapon_for_unit(&"lance_rig", sfx_pos)
			&"mortar":
				AudioManager.play_weapon_for_unit(&"chrysalis_mortar", sfx_pos)
			&"heavy":
				AudioManager.play_weapon_for_unit(&"goliath_frame", sfx_pos)
			&"heavy_slug":
				AudioManager.play_sfx(&"weapon_mono_bastion", -4.0, 0.05, sfx_pos, true)
			&"prism_beam":
				AudioManager.play_sfx(&"weapon_prism_refract", -4.5, 0.05, sfx_pos, true)
			_:
				AudioManager.play_weapon_for_unit(&"clone_trooper", sfx_pos)
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
		var base_dmg: float = _get_effective_turret_damage()
		var armor_mult: float = owner_building.turret_bonus_vs_armored
		var inner_r: float = owner_building.turret_splash_inner_ratio
		var edge_r: float = owner_building.turret_splash_edge_damage_ratio
		var impact_pos: Vector2 = end_pos
		var ord_mgr: CombatOrdnanceManager = tree.get_first_node_in_group("combat_ordnance_manager") as CombatOrdnanceManager if tree != null else null
		if ord_mgr != null:
			ord_mgr.schedule_ground_detonation({
				"delay": flight_time,
				"attacker_ref": weakref(atk_bldg),
				"attacker_team": atk_team,
				"center": impact_pos,
				"radius": splash_r,
				"inner_ratio": inner_r,
				"edge_ratio": edge_r,
				"base_dmg": base_dmg,
				"bonus_armored": 0.0,
				"armor_mult": armor_mult,
				"shake_intensity": 2.2,
				"shake_duration": 0.12,
				"scar_kind": &"scorch_large" if splash_r >= 50.0 else &"scorch_small",
				"vfx_color": team_col,
			})
			_spawn_mortar_vfx(origin, impact_pos, splash_r, flight_time, arc_h, team_col, Callable(), inner_r)
		else:
			var on_impact: Callable = func() -> void:
				var valid_atk: Building = atk_bldg if (is_instance_valid(atk_bldg) and not atk_bldg.is_destroyed) else null
				CombatOrdnanceManager.apply_aoe_damage(tree, valid_atk, atk_team, impact_pos, splash_r, base_dmg, 0.0, armor_mult, inner_r, edge_r)
			_spawn_mortar_vfx(origin, impact_pos, splash_r, flight_time, arc_h, team_col, on_impact, inner_r)
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
			_spawn_heavy_muzzle_shock(origin, end_pos, slug_col, true)
			if _is_armored_target(target) and owner_building.turret_bonus_vs_armored > 1.0:
				var shot_dir_hs: Vector2 = (end_pos - origin).normalized() if end_pos.distance_squared_to(origin) > 1.0 else Vector2.RIGHT
				_spawn_armor_spark(end_pos, shot_dir_hs, Color(1.0, 0.72, 0.20, 1.0))
		&"heavy":
			_spawn_tracer(origin, end_pos, team_col, 3.0, 0.14, AttackTracer.TracerStyle.TWIN_SLUG)
		&"prism_beam":
			var is_local_ob: bool = TeamManager.is_team_controlled_by_local_human(int(owner_building.team)) if TeamManager != null else (owner_building.team == Unit.Team.PLAYER)
			var base_gold: Color = Color(0.98, 0.80, 0.14, 0.96)
			var ob_col: Color = base_gold if is_local_ob else base_gold.lerp(team_col, 0.55)
			_spawn_tracer(origin, end_pos, ob_col, 3.1, 0.20, AttackTracer.TracerStyle.PRISM_BEAM)
			if _is_armored_target(target) and owner_building.turret_bonus_vs_armored > 1.0:
				var shot_dir_pb: Vector2 = (end_pos - origin).normalized() if end_pos.distance_squared_to(origin) > 1.0 else Vector2.RIGHT
				_spawn_armor_spark(end_pos, shot_dir_pb, Color(0.98, 0.84, 0.24, 1.0))
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


func _is_point_visible_local(world_pos: Vector2) -> bool:
	if owner_building == null or not owner_building.is_inside_tree():
		return false
	var fog: FogOfWarSystem = _get_fog()
	if fog != null and fog.fog_enabled:
		return fog.is_world_pos_visible_strict(world_pos)
	return true


func _is_audible(origin: Vector2, target_pos: Vector2) -> bool:
	if owner_building == null or not owner_building.is_inside_tree():
		return false
	if TeamManager != null and TeamManager.is_team_controlled_by_local_human(int(owner_building.team)):
		return true
	return _is_point_visible_local(origin) or _is_point_visible_local(target_pos)


func _spawn_tracer(origin: Vector2, end_pos: Vector2, col: Color, width: float, duration: float, style: int) -> void:
	if owner_building == null or not owner_building.is_inside_tree():
		return
	var host: Node = owner_building.get_parent()
	if host == null:
		return
	var from_vis: bool = _is_point_visible_local(origin)
	var to_vis: bool = _is_point_visible_local(end_pos)
	if not from_vis and not to_vis:
		return
	var tracer: AttackTracer = VFXPool.acquire_attack_tracer(45) if VFXPool != null else null
	if tracer == null:
		tracer = ATTACK_TRACER_SCRIPT.new() as AttackTracer
		tracer.z_index = 45
		host.add_child(tracer)
	tracer.setup(origin, end_pos, col, width, duration, 0.0, style, not from_vis)


func _spawn_heavy_muzzle_shock(origin: Vector2, end_pos: Vector2, col: Color, is_brutalist: bool) -> void:
	if VFXPool != null and VFXPool.is_high_vfx_load():
		return
	if owner_building == null or not owner_building.is_inside_tree() or owner_building.get_parent() == null:
		return
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_vis: bool = viewer < 0 or (TeamManager.are_allies(viewer, int(owner_building.team)) if TeamManager != null else (owner_building.team == Unit.Team.PLAYER)) or owner_building.visible
	if not is_vis:
		return
	var aim_d: Vector2 = (end_pos - origin).normalized() if end_pos.distance_squared_to(origin) > 1.0 else Vector2.RIGHT.rotated(turret_angle)
	var fx: CombatVFX = VFXPool.acquire_combat_vfx(54) if VFXPool != null else null
	if fx == null:
		fx = COMBAT_VFX_SCRIPT.new() as CombatVFX
		fx.z_index = 54
		owner_building.get_parent().add_child(fx)
	fx.setup_muzzle_shock(origin, aim_d, 28.0, col, is_brutalist)


func _spawn_armor_spark(world_pos: Vector2, shot_dir: Vector2, col: Color) -> void:
	if VFXPool != null and VFXPool.is_high_vfx_load():
		return
	if owner_building == null or not owner_building.is_inside_tree():
		return
	if not _is_point_visible_local(world_pos):
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
	on_impact: Callable,
	inner_core_ratio: float = 0.35
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
	fx.setup_mortar_shell(origin, impact_pos, splash_r, flight_time, arc_h, col, on_impact, inner_core_ratio)
