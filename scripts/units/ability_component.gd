class_name AbilityComponent
extends Node

const ABILITY_EFFECT_SCRIPT: GDScript = preload("res://ui/overlays/ability_effect.gd")
const AUTOCAST_TICK_INTERVAL: float = 0.35

signal ability_cooldown_updated(ability_id: StringName, remaining: float, duration: float)
signal ability_executed(ability_id: StringName, target_pos: Vector2)
signal autocast_changed(ability_id: StringName, enabled: bool)

var cooldowns: Dictionary = {}
var _durations: Dictionary = {}
var autocast_enabled: Dictionary = {}
var _autocast_timer: float = 0.0

var pending_ability: AbilityData = null
var pending_target_pos: Vector2 = Vector2.ZERO
var pending_target_unit: Unit = null

var _fog_cache: FogOfWarSystem = null
var _scratch_units: Array = []


func _get_fog_cached(owner_unit: Unit) -> FogOfWarSystem:
	if _fog_cache != null and is_instance_valid(_fog_cache):
		return _fog_cache
	if owner_unit != null and owner_unit.is_inside_tree():
		_fog_cache = owner_unit.get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
		return _fog_cache
	return null


func _query_units_into_scratch(owner_unit: Unit, center: Vector2, radius: float) -> void:
	if SpatialGrid != null:
		SpatialGrid.query_units_into(center, radius, _scratch_units)
		return
	_scratch_units.clear()
	if owner_unit != null and owner_unit.is_inside_tree():
		for node: Node in owner_unit.get_tree().get_nodes_in_group("units"):
			_scratch_units.append(node)


func init_autocast_defaults(owner_unit: Unit) -> void:
	if owner_unit == null or owner_unit.data == null:
		return
	for ab: AbilityData in owner_unit.data.abilities:
		if ab != null and ab.allow_autocast and not autocast_enabled.has(ab.ability_id):
			autocast_enabled[ab.ability_id] = ab.default_autocast


func is_autocast_enabled(ability_id: StringName) -> bool:
	return bool(autocast_enabled.get(ability_id, false))


func set_autocast_enabled(ability_id: StringName, enabled: bool) -> void:
	if is_autocast_enabled(ability_id) == enabled:
		return
	autocast_enabled[ability_id] = enabled
	autocast_changed.emit(ability_id, enabled)


func toggle_autocast(ability_id: StringName) -> bool:
	var next_val: bool = not is_autocast_enabled(ability_id)
	set_autocast_enabled(ability_id, next_val)
	return next_val


func tick_autocast(owner_unit: Unit, delta: float) -> void:
	if owner_unit == null or owner_unit.is_dead or owner_unit.is_staffed or owner_unit.data == null:
		return
	if autocast_enabled.is_empty():
		return
	_autocast_timer += delta
	if _autocast_timer < AUTOCAST_TICK_INTERVAL:
		return
	_autocast_timer = 0.0

	var fog: FogOfWarSystem = _get_fog_cached(owner_unit)
	for ab: AbilityData in owner_unit.data.abilities:
		if ab == null or not ab.allow_autocast:
			continue
		if not is_autocast_enabled(ab.ability_id) or not owner_unit.is_ability_ready(ab):
			continue
		if ab.target_type == AbilityData.TargetType.INSTANT:
			if _should_trigger_autocast(owner_unit, ab):
				request_cast(owner_unit, ab, owner_unit.global_position, owner_unit)
				return
		elif ab.target_type == AbilityData.TargetType.POINT_AOE:
			var auto_pos: Vector2 = _find_autocast_point_target(owner_unit, ab, fog)
			if auto_pos != Vector2.INF:
				request_cast(owner_unit, ab, auto_pos, null)
				return


func _find_autocast_point_target(owner_unit: Unit, ability: AbilityData, fog: FogOfWarSystem) -> Vector2:
	var ab_id: StringName = ability.ability_id
	var cast_r: float = maxf(60.0, ability.cast_range)
	var obs_team: int = int(owner_unit.team)

	if ab_id == &"monolith_shield_overcharge":
		_query_units_into_scratch(owner_unit, owner_unit.global_position, cast_r)
		var best_pos: Vector2 = Vector2.INF
		var best_score: float = 0.0
		for node: Variant in _scratch_units:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var u: Unit = node as Unit
			if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
				continue
			if not CombatTargeting.are_teams_allied(obs_team, int(u.team)):
				continue
			if u.global_position.distance_to(owner_unit.global_position) > cast_r:
				continue
			var is_combat: bool = u.data != null and (not u.data.can_gather and not u.data.can_staff_compute)
			if not is_combat:
				continue
			var shield_low: bool = u.max_shield > 0.0 and (u.current_shield / maxf(1.0, u.max_shield)) < 0.50
			var hull_damaged: bool = u.current_hp < u.get_max_hp() * 0.98
			if not shield_low and not hull_damaged:
				continue
			var score: float = 10.0
			if shield_low:
				score += (1.0 - (u.current_shield / maxf(1.0, u.max_shield))) * 35.0
			if hull_damaged:
				score += (1.0 - (u.current_hp / maxf(1.0, u.get_max_hp()))) * 45.0
			if u == owner_unit:
				score *= 0.80
			if score > best_score:
				best_score = score
				best_pos = u.global_position
		return best_pos

	if ab_id == &"monolith_suppressive_lock":
		# Only auto-cast suppressive lock against visible hostile enemies within cast range
		if owner_unit.current_target != null and is_instance_valid(owner_unit.current_target) and owner_unit.current_target is Unit:
			var cur_u: Unit = owner_unit.current_target as Unit
			if CombatTargeting.can_team_target_entity(obs_team, cur_u, fog) and cur_u.global_position.distance_to(owner_unit.global_position) <= cast_r:
				if not cur_u.has_status_effect(&"static_slow"):
					return cur_u.global_position
		_query_units_into_scratch(owner_unit, owner_unit.global_position, cast_r)
		var best_enemy_pos: Vector2 = Vector2.INF
		var best_enemy_score: float = 0.0
		for node: Variant in _scratch_units:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var e: Unit = node as Unit
			if not CombatTargeting.can_team_target_entity(obs_team, e, fog):
				continue
			if e.global_position.distance_to(owner_unit.global_position) > cast_r:
				continue
			if e.has_status_effect(&"static_slow"):
				continue
			var score_e: float = 10.0
			if e.data != null:
				if e.data.has_tag(&"flanker") or e.data.has_tag(&"swarm") or e.data.move_speed >= 260.0:
					score_e += 30.0
				elif e.data.attack_damage > 0.0:
					score_e += 18.0
			score_e -= (e.global_position.distance_to(owner_unit.global_position) / maxf(1.0, cast_r)) * 5.0
			if score_e > best_enemy_score:
				best_enemy_score = score_e
				best_enemy_pos = e.global_position
		return best_enemy_pos

	if ab_id == &"grav_pulse":
		var gp_r: float = maxf(60.0, ability.aoe_radius)
		_query_units_into_scratch(owner_unit, owner_unit.global_position, cast_r + gp_r)
		var hostile_combat: Array[Unit] = []
		for node: Variant in _scratch_units:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var e: Unit = node as Unit
			if not CombatTargeting.can_team_target_entity(obs_team, e, fog):
				continue
			if e.data != null and (e.data.can_gather or e.data.can_staff_compute):
				continue
			hostile_combat.append(e)
		if hostile_combat.size() < 2:
			return Vector2.INF
		var best_gp_pos: Vector2 = Vector2.INF
		var best_gp_score: float = 0.0
		for cand: Unit in hostile_combat:
			if cand.global_position.distance_to(owner_unit.global_position) > cast_r:
				continue
			var cluster_count: int = 0
			var un_slowed_count: int = 0
			var center_sum: Vector2 = Vector2.ZERO
			for other: Unit in hostile_combat:
				if other.global_position.distance_to(cand.global_position) <= gp_r:
					cluster_count += 1
					center_sum += other.global_position
					if not other.has_status_effect(&"grav_pulse"):
						un_slowed_count += 1
			if cluster_count < 2 or un_slowed_count <= 0:
				continue
			var centroid: Vector2 = center_sum / float(cluster_count)
			if centroid.distance_to(owner_unit.global_position) > cast_r or not CombatTargeting.is_world_pos_visible_to_team(fog, obs_team, centroid):
				centroid = cand.global_position
			var gp_score: float = float(cluster_count) * 18.0 + float(un_slowed_count) * 12.0
			if gp_score > best_gp_score:
				best_gp_score = gp_score
				best_gp_pos = centroid
		return best_gp_pos

	if ab_id == &"luminous_mend":
		var lm_r: float = maxf(60.0, ability.aoe_radius)
		_query_units_into_scratch(owner_unit, owner_unit.global_position, cast_r + lm_r)
		var wounded_allies: Array[Unit] = []
		for node: Variant in _scratch_units:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var u: Unit = node as Unit
			if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
				continue
			if not CombatTargeting.are_teams_allied(obs_team, int(u.team)):
				continue
			if u.current_hp < u.get_max_hp() * 0.85:
				wounded_allies.append(u)
		if wounded_allies.is_empty():
			return Vector2.INF
		var best_lm_pos: Vector2 = Vector2.INF
		var best_lm_score: float = 0.0
		for cand: Unit in wounded_allies:
			if cand.global_position.distance_to(owner_unit.global_position) > cast_r:
				continue
			var sum_pos: Vector2 = Vector2.ZERO
			var cnt: int = 0
			var missing_hp_sum: float = 0.0
			for other: Unit in wounded_allies:
				if other.global_position.distance_to(cand.global_position) <= lm_r:
					sum_pos += other.global_position
					cnt += 1
					missing_hp_sum += maxf(0.0, other.get_max_hp() - other.current_hp)
			var sc: float = float(cnt) * 20.0 + missing_hp_sum * 0.45
			if sc > best_lm_score:
				best_lm_score = sc
				var c_pt: Vector2 = sum_pos / float(maxi(1, cnt))
				best_lm_pos = c_pt if c_pt.distance_to(owner_unit.global_position) <= cast_r else cand.global_position
		return best_lm_pos

	if ab_id == &"blinding_glare":
		var bg_r: float = maxf(60.0, ability.aoe_radius)
		_query_units_into_scratch(owner_unit, owner_unit.global_position, cast_r + bg_r)
		var hostiles_bg: Array[Unit] = []
		for node: Variant in _scratch_units:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var e: Unit = node as Unit
			if not CombatTargeting.can_team_target_entity(obs_team, e, fog):
				continue
			if e.data != null and (e.data.can_gather or e.data.can_staff_compute):
				continue
			hostiles_bg.append(e)
		if hostiles_bg.is_empty():
			return Vector2.INF
		var best_bg_pos: Vector2 = Vector2.INF
		var best_bg_score: float = 0.0
		for cand: Unit in hostiles_bg:
			if cand.global_position.distance_to(owner_unit.global_position) > cast_r:
				continue
			var cnt: int = 0
			var fresh: int = 0
			var sum_p: Vector2 = Vector2.ZERO
			for other: Unit in hostiles_bg:
				if other.global_position.distance_to(cand.global_position) <= bg_r:
					cnt += 1
					sum_p += other.global_position
					if not other.has_status_effect(&"blinding_glare"):
						fresh += 1
			if fresh <= 0:
				continue
			var sc_bg: float = float(cnt) * 16.0 + float(fresh) * 14.0
			if sc_bg > best_bg_score:
				best_bg_score = sc_bg
				var c_pt2: Vector2 = sum_p / float(maxi(1, cnt))
				best_bg_pos = c_pt2 if (c_pt2.distance_to(owner_unit.global_position) <= cast_r and CombatTargeting.is_world_pos_visible_to_team(fog, obs_team, c_pt2)) else cand.global_position
		return best_bg_pos

	return Vector2.INF


func _should_trigger_autocast(owner_unit: Unit, ability: AbilityData) -> bool:
	if ability.ability_id == &"adrenal_surge":
		if owner_unit.combat_component == null:
			return false
		if owner_unit.current_target != null and is_instance_valid(owner_unit.current_target):
			if owner_unit.combat_component.is_within_attack_envelope(owner_unit, owner_unit.current_target):
				return true
		return false
	if ability.ability_id == &"kinetic_barrier":
		var in_combat: bool = owner_unit.current_target != null and is_instance_valid(owner_unit.current_target)
		if not in_combat:
			return false
		var low_shield: bool = owner_unit.max_shield > 0.0 and owner_unit.current_shield <= owner_unit.max_shield * 0.25
		var low_hull: bool = owner_unit.current_hp < owner_unit.get_max_hp() * 0.80
		return low_shield or low_hull
	return false


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


func _is_valid_unit_target_for_ability(owner_unit: Unit, ability: AbilityData, target_unit: Unit) -> bool:
	if owner_unit == null or ability == null or target_unit == null or not is_instance_valid(target_unit):
		return false
	if target_unit.is_dead or target_unit.is_staffed or target_unit.is_queued_for_deletion():
		return false
	var obs_team: int = int(owner_unit.team)
	var fog: FogOfWarSystem = _get_fog_cached(owner_unit)
	match ability.target_filter:
		AbilityData.TargetFilter.ENEMY:
			return CombatTargeting.can_team_target_entity(obs_team, target_unit, fog)
		AbilityData.TargetFilter.ALLY:
			return CombatTargeting.are_teams_allied(obs_team, int(target_unit.team))
		AbilityData.TargetFilter.SELF:
			return target_unit == owner_unit
		_:
			if target_unit.has_method("has_unit_tag"):
				if bool(target_unit.call("has_unit_tag", &"untargetable")) or bool(target_unit.call("has_unit_tag", &"phase_invulnerable")):
					return false
			if CombatTargeting.are_teams_hostile(obs_team, int(target_unit.team)):
				return CombatTargeting.is_world_pos_visible_to_team(fog, obs_team, target_unit.global_position)
			return true


func request_cast(owner_unit: Unit, ability: AbilityData, target_pos: Vector2, target_unit: Unit = null) -> bool:
	if owner_unit == null or owner_unit.is_dead or not owner_unit.is_ability_ready(ability):
		return false

	if ability.target_type == AbilityData.TargetType.INSTANT:
		cancel_pending_cast()
		execute_ability(owner_unit, ability, owner_unit.global_position, owner_unit)
		return true

	if ability.target_type == AbilityData.TargetType.UNIT_TARGET:
		if not _is_valid_unit_target_for_ability(owner_unit, ability, target_unit):
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
		var my_r: float = owner_unit.data.collision_radius if owner_unit.data != null else 16.0
		return CombatTargeting.distance_between_edges(owner_unit.global_position, my_r, target_unit) <= ability.cast_range
	return owner_unit.global_position.distance_to(target_pos) <= ability.cast_range


func get_pending_destination() -> Vector2:
	if pending_target_unit != null and is_instance_valid(pending_target_unit):
		return pending_target_unit.global_position
	return pending_target_pos


func try_complete_pending_cast(owner_unit: Unit) -> bool:
	if pending_ability == null:
		return false
	if owner_unit == null or not owner_unit.is_ability_ready(pending_ability):
		cancel_pending_cast()
		return true
	if pending_ability.target_type == AbilityData.TargetType.UNIT_TARGET:
		if not _is_valid_unit_target_for_ability(owner_unit, pending_ability, pending_target_unit):
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

	if AudioManager != null:
		var sfx_pos: Vector2 = target_pos if ability.ability_id == &"solar_convergence" else owner_unit.global_position
		var is_local_caster: bool = TeamManager.is_team_controlled_by_local_human(int(owner_unit.team)) if TeamManager != null else (owner_unit.team == Unit.Team.PLAYER)
		var sfx_visible: bool = is_local_caster or owner_unit.visible
		if not sfx_visible and ability.ability_id == &"solar_convergence" and owner_unit.is_inside_tree():
			var fog: FogOfWarSystem = _get_fog_cached(owner_unit)
			sfx_visible = fog == null or not fog.fog_enabled or fog.is_world_pos_visible_strict(target_pos)
		if sfx_visible:
			AudioManager.play_ability_sfx(ability.ability_id, sfx_pos)

	ability_executed.emit(ability.ability_id, target_pos)


func _execute_point_aoe(owner_unit: Unit, ability: AbilityData, target_pos: Vector2) -> void:
	if ability.ability_id == &"solar_convergence":
		var telegraph_time: float = ability.effect_duration if ability.effect_duration > 0.0 else 1.4
		var base_dmg: float = ability.damage_or_value if ability.damage_or_value > 0.0 else 75.0
		var bonus_armored: float = 45.0
		var blast_radius: float = ability.aoe_radius if ability.aoe_radius > 0.0 else 95.0
		var inner_r: float = ability.splash_inner_radius_ratio
		var edge_r: float = ability.splash_edge_damage_ratio
		var tree: SceneTree = owner_unit.get_tree()
		var caster_team: int = int(owner_unit.team)
		var caster_ref: WeakRef = weakref(owner_unit)
		var ord_mgr: CombatOrdnanceManager = tree.get_first_node_in_group("combat_ordnance_manager") as CombatOrdnanceManager if tree != null else null
		var fx: CombatVFX = VFXPool.acquire_combat_vfx(55) if VFXPool != null else null
		if fx == null and owner_unit.get_parent() != null:
			fx = load("res://ui/overlays/combat_vfx.gd").new() as CombatVFX
			fx.z_index = 55
			owner_unit.get_parent().add_child(fx)
		if ord_mgr != null:
			ord_mgr.schedule_ground_detonation({
				"delay": telegraph_time,
				"attacker_ref": caster_ref,
				"attacker_team": caster_team,
				"center": target_pos,
				"radius": blast_radius,
				"inner_ratio": inner_r,
				"edge_ratio": edge_r,
				"base_dmg": base_dmg,
				"bonus_armored": bonus_armored,
				"armor_mult": 1.0,
				"shake_intensity": 2.6,
				"shake_duration": 0.20,
				"impact_sfx": &"ability_solar_convergence_impact",
				"scar_kind": &"scorch_large",
				"vfx_color": Color(0.98, 0.80, 0.14, 1.0),
			})
			if fx != null:
				fx.setup_solar_convergence(target_pos, blast_radius, telegraph_time, Callable(), inner_r)
		else:
			var on_impact: Callable = func() -> void:
				_detonate_solar_convergence(tree, caster_team, caster_ref, target_pos, blast_radius, base_dmg, bonus_armored, inner_r, edge_r)
			if fx != null:
				fx.setup_solar_convergence(target_pos, blast_radius, telegraph_time, on_impact, inner_r)
			else:
				on_impact.call()
		return

	if ability.ability_id == &"grav_pulse":
		_spawn_grav_pulse_effect(owner_unit, target_pos, ability.aoe_radius, ability.effect_color)
	elif ability.ability_id == &"luminous_mend" or ability.ability_id == &"blinding_glare":
		_spawn_prism_burst_effect(owner_unit, target_pos, ability.aoe_radius, ability.effect_color)
	else:
		_spawn_aoe_effect(owner_unit, target_pos, ability.aoe_radius, ability.effect_color)

	var obs_team: int = int(owner_unit.team)
	_query_units_into_scratch(owner_unit, target_pos, ability.aoe_radius)

	# Allied Luminous Mend (PRISMA_DEI Cantor)
	if ability.ability_id == &"luminous_mend":
		var heal_amt: float = ability.damage_or_value if ability.damage_or_value > 0.0 else 45.0
		for node: Variant in _scratch_units:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var ally: Unit = node as Unit
			if ally.is_dead or ally.is_staffed or ally.is_queued_for_deletion():
				continue
			if not CombatTargeting.are_teams_allied(obs_team, int(ally.team)):
				continue
			var ally_r: float = ally.data.collision_radius if ally.data != null else 16.0
			if ally.global_position.distance_to(target_pos) <= ability.aoe_radius + ally_r:
				ally.heal(heal_amt)
		return

	# Allied Shield Overcharge (Aegis Relay)
	if ability.ability_id == &"monolith_shield_overcharge":
		var restore_amt: float = ability.damage_or_value if ability.damage_or_value > 0.0 else 45.0
		var barrier_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 6.0
		for node: Variant in _scratch_units:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var ally: Unit = node as Unit
			if ally.is_dead or ally.is_staffed or ally.is_queued_for_deletion():
				continue
			if not CombatTargeting.are_teams_allied(obs_team, int(ally.team)):
				continue
			var ally_r: float = ally.data.collision_radius if ally.data != null else 16.0
			if ally.global_position.distance_to(target_pos) <= ability.aoe_radius + ally_r:
				if ally.has_shields():
					ally.restore_shield(restore_amt)
				ally.add_damage_shield(30.0, barrier_dur, "Shield Overcharge", &"shield_overcharge")
		return

	# Offensive Point AoE: unified damage with radial falloff + destructible barricade support
	if ability.damage_or_value > 0.0:
		CombatOrdnanceManager.apply_aoe_damage(
			owner_unit.get_tree(),
			owner_unit,
			obs_team,
			target_pos,
			ability.aoe_radius,
			ability.damage_or_value,
			0.0,
			1.0,
			ability.splash_inner_radius_ratio,
			ability.splash_edge_damage_ratio
		)

	# Status debuffs apply reliably across the full AoE radius
	for node: Variant in _scratch_units:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var candidate: Unit = node as Unit
		if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion():
			continue
		if not CombatTargeting.are_teams_hostile(obs_team, int(candidate.team)):
			continue
		var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
		if candidate.global_position.distance_to(target_pos) <= ability.aoe_radius + enemy_r:
			if ability.ability_id == &"grav_pulse":
				var gp_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 5.0
				var mv_mult: float = clampf(1.0 + ability.move_speed_modifier, 0.25, 1.0) if ability.move_speed_modifier < 0.0 else 0.50
				var atk_mult: float = clampf(1.0 + ability.attack_speed_modifier, 0.25, 1.0) if ability.attack_speed_modifier < 0.0 else 0.65
				candidate.apply_status_effect(&"grav_pulse", {
					"duration": gp_dur,
					"label": "Grav-Pulse",
					"category": &"debuff",
					"move_speed_mult": mv_mult,
					"attack_speed_mult": atk_mult,
				})
			elif ability.ability_id == &"blinding_glare":
				var bg_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 3.5
				var bg_mv: float = clampf(1.0 + ability.move_speed_modifier, 0.25, 1.0) if ability.move_speed_modifier < 0.0 else 0.80
				var bg_atk: float = clampf(1.0 + ability.attack_speed_modifier, 0.25, 1.0) if ability.attack_speed_modifier < 0.0 else 0.75
				candidate.apply_status_effect(&"blinding_glare", {
					"duration": bg_dur,
					"label": "Blinding Glare",
					"category": &"debuff",
					"move_speed_mult": bg_mv,
					"attack_speed_mult": bg_atk,
				})
			elif ability.effect_duration > 0.0 and (ability.move_speed_modifier < 0.0 or ability.attack_speed_modifier < 0.0):
				candidate.apply_slow_debuff(ability.effect_duration, absf(ability.move_speed_modifier), absf(ability.attack_speed_modifier))


func _execute_unit_target(owner_unit: Unit, ability: AbilityData, target_unit: Unit) -> void:
	if target_unit == null or not is_instance_valid(target_unit) or target_unit.is_dead:
		return
	if ability.ability_id == &"radiant_mark":
		var rm_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 4.0
		var amp_mult: float = ability.damage_or_value if ability.damage_or_value > 1.0 else 1.15
		target_unit.apply_status_effect(&"radiant_mark", {
			"duration": rm_dur,
			"label": "Radiant Mark (+15% Dmg)",
			"category": &"debuff",
			"damage_taken_mult": amp_mult,
		})
		_spawn_prism_burst_effect(owner_unit, target_unit.global_position, maxf(30.0, ability.aoe_radius), ability.effect_color)
		return
	_spawn_aoe_effect(owner_unit, target_unit.global_position, maxf(24.0, ability.aoe_radius), ability.effect_color)
	target_unit.take_damage(ability.damage_or_value, owner_unit)


func _execute_instant(owner_unit: Unit, ability: AbilityData) -> void:
	var ab_id: StringName = ability.ability_id

	if ab_id == &"solar_step":
		var ss_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 2.5
		var ss_mv: float = 1.0 + (ability.move_speed_modifier if ability.move_speed_modifier > 0.0 else 0.35)
		owner_unit.apply_status_effect(&"solar_step", {
			"duration": ss_dur,
			"label": "Solar Step",
			"category": &"buff",
			"move_speed_mult": ss_mv,
		})
		_spawn_prism_burst_effect(owner_unit, owner_unit.global_position, maxf(34.0, ability.aoe_radius), ability.effect_color)
		return

	if ab_id == &"aureole_surge":
		var as_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 4.0
		var as_ramp: float = ability.damage_or_value if ability.damage_or_value > 1.0 else 1.35
		owner_unit.apply_status_effect(&"aureole_surge", {
			"duration": as_dur,
			"label": "Aureole Surge",
			"category": &"buff",
			"beam_ramp_speed_mult": as_ramp,
			"bonus_refract_bounces": 1,
			"damage_taken_mult": 1.15,
		})
		_spawn_prism_burst_effect(owner_unit, owner_unit.global_position, maxf(44.0, ability.aoe_radius), ability.effect_color)
		return

	if ab_id == &"focus_alignment":
		var fa_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 4.0
		var fa_rng: float = ability.damage_or_value if ability.damage_or_value > 0.0 else 40.0
		var fa_mv: float = clampf(1.0 + ability.move_speed_modifier, 0.25, 1.0) if ability.move_speed_modifier < 0.0 else 0.80
		if owner_unit.combat_component != null:
			owner_unit.combat_component.boost_beam_ramp_fraction(owner_unit, 0.50)
		owner_unit.apply_status_effect(&"focus_alignment", {
			"duration": fa_dur,
			"label": "Focus Alignment",
			"category": &"buff",
			"bonus_attack_range": fa_rng,
			"move_speed_mult": fa_mv,
		})
		_spawn_prism_burst_effect(owner_unit, owner_unit.global_position, maxf(38.0, ability.aoe_radius), ability.effect_color)
		return

	if ab_id == &"adrenal_surge":
		var econ: EconomyManager = owner_unit.get_tree().get_first_node_in_group("economy_manager") as EconomyManager
		var base_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 4.0
		var base_atk: float = ability.attack_speed_modifier if ability.attack_speed_modifier > 0.0 else 0.30
		var move_bonus: float = ability.move_speed_modifier if ability.move_speed_modifier > 0.0 else 0.35
		var duration: float = econ.get_adrenal_duration(owner_unit.team, base_dur) if econ != null else base_dur
		var atk_bonus: float = econ.get_adrenal_attack_speed_bonus(owner_unit.team, base_atk) if econ != null else base_atk
		owner_unit.apply_adrenal_surge(duration, move_bonus, atk_bonus)
		_spawn_self_pulse(owner_unit, maxf(32.0, ability.aoe_radius), ability.effect_color)
		return

	if ab_id == &"kinetic_barrier":
		var kb_amt: float = ability.damage_or_value if ability.damage_or_value > 0.0 else 180.0
		var kb_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 7.0
		owner_unit.add_damage_shield(kb_amt, kb_dur, "Kinetic Barrier", &"kinetic_barrier")
		if owner_unit.has_shields():
			owner_unit.restore_shield(40.0)
		_spawn_hex_barrier_effect(owner_unit, maxf(36.0, ability.aoe_radius), ability.effect_color)
		return

	if ab_id == &"static_pulse" or ab_id == &"seismic_slam":
		var radius: float = maxf(32.0, ability.aoe_radius)
		var origin: Vector2 = owner_unit.global_position
		var obs_team: int = int(owner_unit.team)
		if ab_id == &"seismic_slam":
			_spawn_seismic_slam(owner_unit, radius, ability.effect_color)
			var cam: Node = owner_unit.get_tree().get_first_node_in_group("rts_camera")
			if cam != null and cam.has_method("add_camera_shake"):
				cam.call("add_camera_shake", 4.2, 0.16, origin)
			var scars: Node = owner_unit.get_tree().get_first_node_in_group("battle_scars")
			if scars != null and scars.has_method("add_scar"):
				scars.call("add_scar", &"scorch_large", origin, clampf(radius * 0.56, 28.0, 62.0), ability.effect_color)
		else:
			_spawn_self_pulse(owner_unit, radius, ability.effect_color)

		if ability.damage_or_value > 0.0:
			CombatOrdnanceManager.apply_aoe_damage(
				owner_unit.get_tree(),
				owner_unit,
				obs_team,
				origin,
				radius,
				ability.damage_or_value,
				0.0,
				1.0,
				ability.splash_inner_radius_ratio,
				ability.splash_edge_damage_ratio
			)

		if ability.effect_duration > 0.0 and (ability.move_speed_modifier < 0.0 or ability.attack_speed_modifier < 0.0):
			_query_units_into_scratch(owner_unit, origin, radius)
			for node: Variant in _scratch_units:
				if not is_instance_valid(node) or not (node is Unit):
					continue
				var enemy: Unit = node as Unit
				if enemy.is_dead or enemy.is_staffed or enemy.is_queued_for_deletion():
					continue
				if not CombatTargeting.are_teams_hostile(obs_team, int(enemy.team)):
					continue
				var enemy_r: float = enemy.data.collision_radius if enemy.data != null else 16.0
				if enemy.global_position.distance_to(origin) <= radius + enemy_r:
					enemy.apply_slow_debuff(
						ability.effect_duration,
						absf(ability.move_speed_modifier),
						absf(ability.attack_speed_modifier)
					)
		return

	# Default instant heal (e.g. Nanite Surge)
	if ability.damage_or_value > 0.0:
		owner_unit.heal(ability.damage_or_value)
	_spawn_self_pulse(owner_unit, maxf(32.0, ability.aoe_radius), ability.effect_color)


func _spawn_self_pulse(owner_unit: Unit, radius: float, effect_color: Color) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = VFXPool.acquire_ability_effect(55) if VFXPool != null else null
	if fx == null:
		fx = ABILITY_EFFECT_SCRIPT.new()
		fx.z_index = 55
		owner_unit.get_parent().add_child(fx)
	fx.setup_self_pulse(owner_unit.global_position, radius, effect_color)


func _spawn_seismic_slam(owner_unit: Unit, radius: float, effect_color: Color) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = VFXPool.acquire_ability_effect(55) if VFXPool != null else null
	if fx == null:
		fx = ABILITY_EFFECT_SCRIPT.new()
		fx.z_index = 55
		owner_unit.get_parent().add_child(fx)
	fx.setup_seismic_slam(owner_unit.global_position, radius, effect_color)


func _spawn_aoe_effect(owner_unit: Unit, target_pos: Vector2, radius: float, effect_color: Color = Color(0.42, 0.88, 1.0, 0.95)) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = VFXPool.acquire_ability_effect(55) if VFXPool != null else null
	if fx == null:
		fx = ABILITY_EFFECT_SCRIPT.new()
		fx.z_index = 55
		owner_unit.get_parent().add_child(fx)
	fx.setup_aoe(owner_unit.global_position, target_pos, radius, effect_color)


func _spawn_hex_barrier_effect(owner_unit: Unit, radius: float, effect_color: Color) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = VFXPool.acquire_ability_effect(55) if VFXPool != null else null
	if fx == null:
		fx = ABILITY_EFFECT_SCRIPT.new()
		fx.z_index = 55
		owner_unit.get_parent().add_child(fx)
	fx.setup_hex_barrier(owner_unit.global_position, radius, effect_color)


func _spawn_grav_pulse_effect(owner_unit: Unit, target_pos: Vector2, radius: float, effect_color: Color) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = VFXPool.acquire_ability_effect(55) if VFXPool != null else null
	if fx == null:
		fx = ABILITY_EFFECT_SCRIPT.new()
		fx.z_index = 55
		owner_unit.get_parent().add_child(fx)
	fx.setup_grav_pulse(owner_unit.global_position, target_pos, radius, effect_color)


func _spawn_prism_burst_effect(owner_unit: Unit, target_pos: Vector2, radius: float, effect_color: Color) -> void:
	if owner_unit.get_parent() == null:
		return
	var fx: AbilityEffect = VFXPool.acquire_ability_effect(55) if VFXPool != null else null
	if fx == null:
		fx = ABILITY_EFFECT_SCRIPT.new()
		fx.z_index = 55
		owner_unit.get_parent().add_child(fx)
	fx.setup_prism_burst(owner_unit.global_position, target_pos, radius, effect_color)


func _detonate_solar_convergence(
	tree: SceneTree,
	caster_team: int,
	caster_ref: WeakRef,
	center: Vector2,
	radius: float,
	base_dmg: float,
	bonus_armored: float,
	inner_ratio: float = 0.40,
	edge_ratio: float = 0.50
) -> void:
	if tree == null:
		return
	var caster_obj: Variant = caster_ref.get_ref() if caster_ref != null else null
	var attacker: Unit = caster_obj as Unit if (caster_obj != null and is_instance_valid(caster_obj) and caster_obj is Unit) else null

	CombatOrdnanceManager.apply_aoe_damage(tree, attacker, caster_team, center, radius, base_dmg, bonus_armored, 1.0, inner_ratio, edge_ratio)

	var fog: FogOfWarSystem = tree.get_first_node_in_group("fog_of_war") as FogOfWarSystem
	var is_local: bool = TeamManager.is_team_controlled_by_local_human(caster_team) if TeamManager != null else (caster_team == int(Unit.Team.PLAYER))
	var visible_to_local: bool = is_local or fog == null or not fog.fog_enabled or fog.is_world_pos_visible_strict(center)
	if visible_to_local:
		if AudioManager != null:
			AudioManager.play_sfx(&"ability_solar_convergence_impact", -2.0, 0.04, center, true)
		var cam: Node = tree.get_first_node_in_group("rts_camera")
		if cam != null and cam.has_method("add_camera_shake"):
			cam.call("add_camera_shake", 2.6, 0.20, center)
