class_name CombatComponent
extends Node

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")
const ABILITY_EFFECT_SCRIPT: GDScript = preload("res://ui/overlays/ability_effect.gd")
const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")

enum AttackPhase {
	IDLE = 0,
	WINDUP = 1,
	BACKSWING = 2,
}

const TIER_COMBAT_UNIT: int = 1
const TIER_SUPPORT_OR_ECON: int = 2
const TIER_BUILDING: int = 3
const BACKSWING_DURATION: float = 0.10

var _attack_cooldown_timer: float = 0.0
var attack_phase: AttackPhase = AttackPhase.IDLE
var _windup_timer: float = 0.0
var _backswing_timer: float = 0.0
var _windup_target: Node2D = null


func tick_cooldown(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)
	if attack_phase == AttackPhase.BACKSWING:
		_backswing_timer = maxf(0.0, _backswing_timer - delta)
		if _backswing_timer <= 0.0:
			attack_phase = AttackPhase.IDLE


func cancel_attack_animation() -> void:
	# Instant cancel of windup (without wasting cooldown) or backswing (while cooldown continues ticking)
	attack_phase = AttackPhase.IDLE
	_windup_timer = 0.0
	_backswing_timer = 0.0
	_windup_target = null


func is_in_windup() -> bool:
	return attack_phase == AttackPhase.WINDUP


func is_in_backswing() -> bool:
	return attack_phase == AttackPhase.BACKSWING


func get_effective_windup(owner_unit: Unit) -> float:
	if owner_unit == null or owner_unit.data == null:
		return 0.08
	var base_w: float = owner_unit.data.attack_windup
	if base_w < 0.0:
		var uid: StringName = owner_unit.get_unit_type_id()
		match uid:
			&"clone_trooper", &"stinger", &"scout_unit":
				base_w = 0.06
			&"goliath_frame", &"lance_rig":
				base_w = 0.11
			&"chrysalis_mortar", &"arc_lancer":
				base_w = 0.15
			_:
				base_w = 0.08
	var base_cd: float = maxf(0.05, owner_unit.data.attack_cooldown)
	var eff_cd: float = owner_unit.get_effective_attack_cooldown()
	var scale: float = clampf(eff_cd / base_cd, 0.55, 1.35)
	return clampf(base_w * scale, 0.0, eff_cd * 0.45)


func force_immediate_target_scan(owner_unit: Unit, max_range: float) -> Node2D:
	if attack_phase == AttackPhase.BACKSWING:
		cancel_attack_animation()
	return find_nearest_enemy(owner_unit, max_range)


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


func _are_teams_hostile(team_a: int, team_b: int) -> bool:
	if TeamManager != null:
		return TeamManager.are_enemies(team_a, team_b)
	return team_a != team_b


func can_target_entity(owner_unit: Unit, target: Node2D) -> bool:
	if owner_unit == null or not is_instance_valid(owner_unit) or target == null or not is_instance_valid(target):
		return false
	if target is Unit:
		var u: Unit = target as Unit
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			return false
		if not _are_teams_hostile(int(owner_unit.team), int(u.team)):
			return false
		if u.has_method("has_unit_tag"):
			if bool(u.call("has_unit_tag", &"untargetable")) or bool(u.call("has_unit_tag", &"phase_invulnerable")):
				return false
		return true
	if target is Building:
		var b: Building = target as Building
		return not b.is_destroyed and not b.is_queued_for_deletion() and _are_teams_hostile(int(owner_unit.team), int(b.team))
	if target.is_in_group("destructible_barricades"):
		return not bool(target.get("is_destroyed")) and not target.is_queued_for_deletion()
	return false


func is_valid_target(owner_unit: Unit, candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Node2D):
		return false
	return can_target_entity(owner_unit, candidate as Node2D)


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
	elif target_node.is_in_group("destructible_barricades") and target_node.has_method("get_footprint_radius"):
		other_r = float(target_node.call("get_footprint_radius"))
	return maxf(0.0, center_dist - my_r - other_r)


func get_target_priority_tier(candidate: Variant) -> int:
	if candidate == null or not is_instance_valid(candidate):
		return TIER_BUILDING
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


func _score_auto_target(owner_unit: Unit, candidate: Node2D, dist: float, max_range: float) -> float:
	var tier: int = get_target_priority_tier(candidate)
	var score: float = 100.0
	if tier == TIER_COMBAT_UNIT:
		score = 1000.0
	elif tier == TIER_SUPPORT_OR_ECON:
		score = 500.0

	if candidate is Unit:
		var u: Unit = candidate
		# Prioritize enemies actively attacking this unit or nearby friendly units
		if u.current_target != null and is_instance_valid(u.current_target):
			if u.current_target == owner_unit:
				score += 180.0
			elif u.current_target is Unit and (u.current_target as Unit).team == owner_unit.team:
				if (u.current_target as Unit).global_position.distance_squared_to(owner_unit.global_position) <= 260.0 * 260.0:
					score += 95.0

		# Anti-armor affinity: Lance-Rig prefers armored heavy targets (Goliath, Arc-Lancer, Chrysalis Mortar)
		if owner_unit.data != null and owner_unit.data.bonus_vs_armored > 0.0 and u.data != null and u.data.is_armored:
			score += 240.0

		# Slight finish-off bias toward damaged units so squads focus down wounded enemies cleanly
		if u.data != null and u.data.max_hp > 0.0:
			var hp_ratio: float = clampf(u.current_hp / u.data.max_hp, 0.0, 1.0)
			score += (1.0 - hp_ratio) * 35.0

	# Closer equal-tier threats always win cleanly
	var norm_dist: float = clampf(dist / maxf(1.0, max_range), 0.0, 1.5)
	score -= norm_dist * 220.0
	return score


func find_best_target(owner_unit: Unit, max_range: float) -> Node2D:
	return find_nearest_enemy(owner_unit, max_range)


func find_nearest_enemy(owner_unit: Unit, max_range: float) -> Node2D:
	if owner_unit == null or not is_instance_valid(owner_unit) or not owner_unit.is_inside_tree():
		return null

	var min_range: float = owner_unit.data.min_attack_range if owner_unit.data != null else 0.0
	var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
	var query_r: float = max_range + my_r + 16.0
	var best_target: Node2D = null
	var best_score: float = -INF

	var unit_candidates: Array = SpatialGrid.query_units_in_radius(owner_unit.global_position, query_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
	for node: Variant in unit_candidates:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var candidate: Unit = node
		if not can_target_entity(owner_unit, candidate):
			continue
		var dist: float = distance_to_target_edge(owner_unit, candidate)
		if dist < min_range or dist > max_range:
			continue
		var s: float = _score_auto_target(owner_unit, candidate, dist, max_range)
		if s > best_score:
			best_score = s
			best_target = candidate

	var bldg_candidates: Array = SpatialGrid.query_buildings_in_radius(owner_unit.global_position, query_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("buildings")
	for node: Variant in bldg_candidates:
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node
		if not can_target_entity(owner_unit, b):
			continue
		var dist: float = distance_to_target_edge(owner_unit, b)
		if dist < min_range or dist > max_range:
			continue
		var s: float = _score_auto_target(owner_unit, b, dist, max_range)
		if s > best_score:
			best_score = s
			best_target = b

	return best_target


func find_higher_priority_threat(owner_unit: Unit, current_target: Node2D, scan_range: float) -> Node2D:
	if owner_unit == null or not is_instance_valid(owner_unit) or owner_unit.data == null:
		return current_target
	if current_target == null or not is_instance_valid(current_target) or not is_valid_target(owner_unit, current_target):
		return find_nearest_enemy(owner_unit, scan_range)

	var cur_tier: int = get_target_priority_tier(current_target)
	var anti_armor_wants_swap: bool = (
		owner_unit.data.bonus_vs_armored > 0.0
		and current_target is Unit
		and (current_target as Unit).data != null
		and not (current_target as Unit).data.is_armored
	)
	if cur_tier <= TIER_COMBAT_UNIT and not anti_armor_wants_swap:
		return current_target

	var candidate: Node2D = find_nearest_enemy(owner_unit, scan_range)
	if candidate == null or candidate == current_target:
		return current_target

	var cand_tier: int = get_target_priority_tier(candidate)
	if cand_tier < cur_tier:
		return candidate
	if anti_armor_wants_swap and cand_tier == TIER_COMBAT_UNIT and candidate is Unit:
		var cand_u: Unit = candidate
		if cand_u.data != null and cand_u.data.is_armored:
			return candidate
	return current_target


func process_attack_at(owner_unit: Unit, target: Variant, delta: float) -> bool:
	if target == null or not is_instance_valid(target) or not is_within_attack_envelope(owner_unit, target):
		if attack_phase == AttackPhase.WINDUP:
			cancel_attack_animation()
		return false
	var target_node: Node2D = target as Node2D

	if attack_phase == AttackPhase.WINDUP:
		_windup_target = target_node
		_windup_timer = maxf(0.0, _windup_timer - delta)
		if _windup_timer <= 0.0:
			attack_phase = AttackPhase.BACKSWING
			_backswing_timer = BACKSWING_DURATION
			_windup_target = null
			return _execute_weapon_shot(owner_unit, target_node)
		return false

	if _attack_cooldown_timer > 0.0:
		return false

	var windup: float = get_effective_windup(owner_unit)
	if windup <= 0.001:
		attack_phase = AttackPhase.BACKSWING
		_backswing_timer = BACKSWING_DURATION
		return _execute_weapon_shot(owner_unit, target_node)

	attack_phase = AttackPhase.WINDUP
	_windup_timer = windup
	_windup_target = target_node
	return false


func try_fire_at(owner_unit: Unit, target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _attack_cooldown_timer > 0.0 or not is_within_attack_envelope(owner_unit, target):
		return false
	attack_phase = AttackPhase.BACKSWING
	_backswing_timer = BACKSWING_DURATION
	return _execute_weapon_shot(owner_unit, target as Node2D)


func _execute_weapon_shot(owner_unit: Unit, target_node: Node2D) -> bool:
	if target_node == null or not is_instance_valid(target_node) or not is_within_attack_envelope(owner_unit, target_node):
		return false
	_attack_cooldown_timer = owner_unit.get_effective_attack_cooldown()
	var muzzle_offset: Vector2 = Vector2.RIGHT.rotated(owner_unit.body_visual.rotation) * owner_unit.data.collision_radius
	var tracer_origin: Vector2 = owner_unit.global_position + muzzle_offset
	var tracer_end: Vector2 = target_node.global_position

	var unit_id: StringName = owner_unit.get_unit_type_id()
	var dmg_dealt_mult: float = float(owner_unit.status_effect_component.call("get_damage_dealt_multiplier")) if owner_unit.status_effect_component != null else 1.0
	var base_dmg: float = owner_unit.data.attack_damage * dmg_dealt_mult
	var bonus_armored: float = owner_unit.data.bonus_vs_armored * dmg_dealt_mult
	var aoe_radius: float = owner_unit.data.aoe_attack_radius
	var pierce_width: float = owner_unit.data.line_pierce_width

	if AudioManager != null and _is_pos_audible(owner_unit, tracer_origin, tracer_end):
		AudioManager.play_weapon_for_unit(unit_id, owner_unit.global_position)
		if AudioManager.has_method("notify_combat_activity"):
			AudioManager.call("notify_combat_activity", 0.35)

	if aoe_radius > 0.0:
		# Chrysalis Mortar: lobbed parabolic caustic shell with ground impact telegraph ring & delayed splash
		var mortar_col: Color = Color(0.46, 1.0, 0.54, 0.96) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.44, 0.24, 0.96)
		var flight_dist: float = tracer_origin.distance_to(tracer_end)
		var flight_time: float = clampf(flight_dist / 560.0, 0.36, 0.54)
		var arc_h: float = clampf(flight_dist * 0.26, 48.0, 86.0)
		var tree: SceneTree = owner_unit.get_tree()
		var attacker_team: Unit.Team = owner_unit.team
		var impact_pos: Vector2 = tracer_end
		var on_impact: Callable = func() -> void:
			var valid_attacker: Unit = owner_unit if (is_instance_valid(owner_unit) and not owner_unit.is_dead) else null
			_apply_aoe_damage_for_team(tree, valid_attacker, attacker_team, impact_pos, aoe_radius, base_dmg, bonus_armored)
			_trigger_camera_shake(tree, 2.8, 0.14, impact_pos)
		_spawn_mortar_shell_vfx(owner_unit, tracer_origin, impact_pos, aoe_radius, flight_time, arc_h, mortar_col, on_impact)
		return true

	if pierce_width > 0.0:
		# High-energy Arc-Lancer piercing plasma lance beam with sweep flash
		var dir: Vector2 = (tracer_end - tracer_origin).normalized() if tracer_end.distance_squared_to(tracer_origin) > 1.0 else Vector2.RIGHT
		var beam_end: Vector2 = tracer_end + dir * 56.0
		var lance_col: Color = Color(0.46, 0.96, 1.0, 0.98) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.36, 0.30, 0.98)
		_spawn_attack_tracer(owner_unit, tracer_origin, beam_end, lance_col, 5.0, 0.21, 0.0, AttackTracer.TracerStyle.ARC_LANCE)
		_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)
		_apply_line_pierce_damage(owner_unit, tracer_origin, beam_end, pierce_width, base_dmg * 0.65, bonus_armored, target_node)
		return true

	if unit_id == &"stinger":
		# Stinger: fast directional melee acid cleave arc
		var cleave_col: Color = Color(0.98, 0.84, 0.26, 0.96) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.44, 0.24, 0.96)
		_spawn_melee_cleave_vfx(owner_unit, owner_unit.global_position, tracer_end, cleave_col)
		_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)
		return true

	if unit_id == &"lance_rig" or bonus_armored > 0.0:
		# Lance-Rig: focused high-voltage rail beam + distinct anti-armor spark on armored targets/buildings
		var rail_col: Color = Color(1.0, 0.80, 0.32, 0.98) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.42, 0.26, 0.98)
		_spawn_attack_tracer(owner_unit, tracer_origin, tracer_end, rail_col, 3.4, 0.16, 0.0, AttackTracer.TracerStyle.RAIL_BEAM)
		if _is_armored_target(target_node):
			var shot_dir: Vector2 = (tracer_end - tracer_origin).normalized() if tracer_end.distance_squared_to(tracer_origin) > 1.0 else Vector2.RIGHT
			_spawn_armor_pierce_spark_vfx(owner_unit, tracer_end, shot_dir, Color(1.0, 0.88, 0.36, 1.0))
		_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)
		return true

	if unit_id == &"goliath_frame":
		# Goliath Frame: heavy twin-slug parallel autocannon tracers
		var slug_col: Color = Color(0.42, 0.94, 1.0, 0.96) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.40, 0.28, 0.96)
		_spawn_attack_tracer(owner_unit, tracer_origin, tracer_end, slug_col, 3.0, 0.14, 0.0, AttackTracer.TracerStyle.TWIN_SLUG)
		_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)
		return true

	# Clone Trooper / standard pulse bolt
	var tracer_color: Color = Color(0.32, 0.98, 0.90, 0.95) if owner_unit.team == Unit.Team.PLAYER else Color(1.0, 0.35, 0.25, 0.95)
	_spawn_attack_tracer(owner_unit, tracer_origin, tracer_end, tracer_color, 2.4, 0.11, 0.0, AttackTracer.TracerStyle.PULSE_BOLT)
	_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)
	return true


func _is_armored_target(target: Variant) -> bool:
	if target is Building:
		return true
	if target is Node and (target as Node).is_in_group("destructible_barricades"):
		return bool((target as Node).get("is_armored"))
	if target is Unit:
		var u: Unit = target
		return u.data != null and u.data.is_armored
	return false


func _apply_damage_to_target(owner_unit: Unit, target: Variant, base_dmg: float, bonus_vs_armored: float) -> void:
	if not is_valid_target(owner_unit, target):
		return
	var total_dmg: float = base_dmg
	if target is Building:
		total_dmg += bonus_vs_armored
		(target as Building).take_damage(total_dmg, owner_unit)
	elif target is Unit:
		var u: Unit = target
		if u.data != null and u.data.is_armored:
			total_dmg += bonus_vs_armored
		u.take_damage(total_dmg, owner_unit)
	elif target is Node and (target as Node).is_in_group("destructible_barricades"):
		if bool((target as Node).get("is_armored")):
			total_dmg += bonus_vs_armored
		(target as Node).call("take_damage", total_dmg, owner_unit)


func _apply_aoe_damage(owner_unit: Unit, center: Vector2, radius: float, base_dmg: float, bonus_vs_armored: float) -> void:
	if not is_instance_valid(owner_unit) or not owner_unit.is_inside_tree():
		return
	_apply_aoe_damage_for_team(owner_unit.get_tree(), owner_unit, owner_unit.team, center, radius, base_dmg, bonus_vs_armored)


func _apply_aoe_damage_for_team(
	tree: SceneTree,
	attacker: Unit,
	attacker_team: Unit.Team,
	center: Vector2,
	radius: float,
	base_dmg: float,
	bonus_vs_armored: float
) -> void:
	if tree == null:
		return
	var entities: Array = SpatialGrid.query_entities_in_radius(center, radius, true, true) if SpatialGrid != null else []
	if SpatialGrid != null:
		for node: Variant in entities:
			if not is_instance_valid(node):
				continue
			if node is Unit:
				var candidate: Unit = node
				if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion() or not _are_teams_hostile(int(attacker_team), int(candidate.team)):
					continue
				var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
				if candidate.global_position.distance_to(center) <= radius + enemy_r:
					var dmg: float = base_dmg + (bonus_vs_armored if (candidate.data != null and candidate.data.is_armored) else 0.0)
					candidate.take_damage(dmg, attacker)
			elif node is Building:
				var b: Building = node
				if b.is_destroyed or b.is_queued_for_deletion() or not _are_teams_hostile(int(attacker_team), int(b.team)):
					continue
				if b.global_position.distance_to(center) <= radius + b.footprint_radius:
					b.take_damage(base_dmg + bonus_vs_armored, attacker)
			elif node is Node2D and (node as Node).is_in_group("destructible_barricades"):
				var bar: Node2D = node as Node2D
				if bool(bar.get("is_destroyed")) or bar.is_queued_for_deletion():
					continue
				var bar_r: float = float(bar.call("get_footprint_radius")) if bar.has_method("get_footprint_radius") else 40.0
				if bar.global_position.distance_to(center) <= radius + bar_r:
					var bar_dmg: float = base_dmg + (bonus_vs_armored if bool(bar.get("is_armored")) else 0.0)
					bar.call("take_damage", bar_dmg, attacker)
		return

	for node: Node in tree.get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var candidate: Unit = node
		if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion() or not _are_teams_hostile(int(attacker_team), int(candidate.team)):
			continue
		var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
		if candidate.global_position.distance_to(center) <= radius + enemy_r:
			var dmg: float = base_dmg + (bonus_vs_armored if (candidate.data != null and candidate.data.is_armored) else 0.0)
			candidate.take_damage(dmg, attacker)

	for node: Node in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or not _are_teams_hostile(int(attacker_team), int(b.team)):
			continue
		if b.global_position.distance_to(center) <= radius + b.footprint_radius:
			b.take_damage(base_dmg + bonus_vs_armored, attacker)

	for node: Node in tree.get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if bool(node.get("is_destroyed")) or node.is_queued_for_deletion():
			continue
		var bar_r: float = float(node.call("get_footprint_radius")) if node.has_method("get_footprint_radius") else 40.0
		if (node as Node2D).global_position.distance_to(center) <= radius + bar_r:
			var bar_dmg: float = base_dmg + (bonus_vs_armored if bool(node.get("is_armored")) else 0.0)
			node.call("take_damage", bar_dmg, attacker)


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
	var seg_mid: Vector2 = (seg_start + seg_end) * 0.5
	var seg_r: float = seg_start.distance_to(seg_end) * 0.5 + half_width + 24.0
	var unit_list: Array = SpatialGrid.query_units_in_radius(seg_mid, seg_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
	for node: Variant in unit_list:
		if not is_instance_valid(node) or not (node is Unit) or node == primary_target:
			continue
		var candidate: Unit = node
		if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion() or not _are_teams_hostile(int(owner_unit.team), int(candidate.team)):
			continue
		var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(candidate.global_position, seg_start, seg_end)
		if candidate.global_position.distance_to(closest) <= half_width + enemy_r:
			_apply_damage_to_target(owner_unit, candidate, pierce_dmg, bonus_vs_armored)

	var bldg_list: Array = SpatialGrid.query_buildings_in_radius(seg_mid, seg_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("buildings")
	for node: Variant in bldg_list:
		if not is_instance_valid(node) or not (node is Building) or node == primary_target:
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or not _are_teams_hostile(int(owner_unit.team), int(b.team)):
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
	arc_height: float = 0.0,
	style: int = 0
) -> void:
	if owner_unit.get_parent() == null:
		return
	if not _is_vfx_visible(owner_unit, from_pos, to_pos):
		return
	var tracer: AttackTracer = ATTACK_TRACER_SCRIPT.new()
	tracer.z_index = 50
	owner_unit.get_parent().add_child(tracer)
	tracer.setup(from_pos, to_pos, tracer_color, width, tracer_duration, arc_height, style)


func _spawn_mortar_shell_vfx(
	owner_unit: Unit,
	from_pos: Vector2,
	target_pos: Vector2,
	splash_radius: float,
	flight_time: float,
	arc_height: float,
	vfx_color: Color,
	on_impact: Callable
) -> void:
	if owner_unit.get_parent() == null:
		if on_impact.is_valid():
			on_impact.call()
		return
	# Always spawn mortar node so delayed splash damage always fires reliably even through Fog of War
	var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
	fx.z_index = 52
	owner_unit.get_parent().add_child(fx)
	fx.call("setup_mortar_shell", from_pos, target_pos, splash_radius, flight_time, arc_height, vfx_color, on_impact)


func _spawn_melee_cleave_vfx(owner_unit: Unit, origin_pos: Vector2, target_pos: Vector2, vfx_color: Color) -> void:
	if owner_unit.get_parent() == null or not _is_vfx_visible(owner_unit, origin_pos, target_pos):
		return
	var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
	fx.z_index = 51
	owner_unit.get_parent().add_child(fx)
	fx.call("setup_melee_cleave", origin_pos, target_pos, vfx_color)


func _spawn_armor_pierce_spark_vfx(owner_unit: Unit, world_pos: Vector2, dir: Vector2, vfx_color: Color) -> void:
	if owner_unit.get_parent() == null or not _is_vfx_visible(owner_unit, world_pos, world_pos):
		return
	var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
	fx.z_index = 52
	owner_unit.get_parent().add_child(fx)
	fx.call("setup_armor_pierce_spark", world_pos, dir, vfx_color)


func _spawn_aoe_blast(owner_unit: Unit, center: Vector2, radius: float, blast_color: Color) -> void:
	if owner_unit.get_parent() == null or not _is_vfx_visible(owner_unit, center, center):
		return
	var fx: AbilityEffect = ABILITY_EFFECT_SCRIPT.new()
	fx.z_index = 52
	owner_unit.get_parent().add_child(fx)
	fx.setup_self_pulse(center, radius, blast_color)


func _trigger_camera_shake(tree: SceneTree, intensity: float, duration: float, world_pos: Vector2) -> void:
	if tree == null:
		return
	var cam: Node = tree.get_first_node_in_group("rts_camera")
	if cam != null and cam.has_method("add_camera_shake"):
		cam.call("add_camera_shake", intensity, duration, world_pos)


func _is_vfx_visible(owner_unit: Unit, from_pos: Vector2, to_pos: Vector2) -> bool:
	if owner_unit == null or not owner_unit.is_inside_tree():
		return false
	var fog: Node = owner_unit.get_tree().get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
		return bool(fog.call("is_world_pos_visible", from_pos)) or bool(fog.call("is_world_pos_visible", to_pos))
	return true


func _is_pos_audible(owner_unit: Unit, from_pos: Vector2, to_pos: Vector2) -> bool:
	if owner_unit == null or not owner_unit.is_inside_tree():
		return false
	if owner_unit.team == Unit.Team.PLAYER:
		return true
	var fog: Node = owner_unit.get_tree().get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("is_world_pos_visible") and fog.get("fog_enabled"):
		return bool(fog.call("is_world_pos_visible", from_pos)) or bool(fog.call("is_world_pos_visible", to_pos))
	return true
