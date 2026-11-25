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

	for ab: AbilityData in owner_unit.data.abilities:
		if ab == null or not ab.allow_autocast:
			continue
		if not is_autocast_enabled(ab.ability_id) or not is_ability_ready(ab):
			continue
		if ab.target_type == AbilityData.TargetType.INSTANT:
			if _should_trigger_autocast(owner_unit, ab):
				request_cast(owner_unit, ab, owner_unit.global_position, owner_unit)
				return
		elif ab.target_type == AbilityData.TargetType.POINT_AOE:
			var auto_pos: Vector2 = _find_autocast_point_target(owner_unit, ab)
			if auto_pos != Vector2.INF:
				request_cast(owner_unit, ab, auto_pos, null)
				return


func _find_autocast_point_target(owner_unit: Unit, ability: AbilityData) -> Vector2:
	var ab_id: StringName = ability.ability_id
	var cast_r: float = maxf(60.0, ability.cast_range)

	if ab_id == &"monolith_shield_overcharge":
		var allies: Array = SpatialGrid.query_units_in_radius(owner_unit.global_position, cast_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
		var best_pos: Vector2 = Vector2.INF
		var best_score: float = 0.0
		for node: Variant in allies:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var u: Unit = node as Unit
			if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
				continue
			var is_ally: bool = (int(u.team) == int(owner_unit.team)) or (TeamManager != null and TeamManager.are_allies(int(owner_unit.team), int(u.team)))
			if not is_ally:
				continue
			if u.global_position.distance_to(owner_unit.global_position) > cast_r:
				continue
			# Trigger on friendly combat units (or self if under fire) whose shield < 50% or hull damaged
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
		# Only auto-cast suppressive lock against enemies within cast range (prefer current target or fast flankers)
		if owner_unit.current_target != null and is_instance_valid(owner_unit.current_target) and owner_unit.current_target is Unit:
			var cur_u: Unit = owner_unit.current_target as Unit
			if not cur_u.is_dead and not cur_u.is_staffed and cur_u.global_position.distance_to(owner_unit.global_position) <= cast_r:
				if not cur_u.has_status_effect(&"static_slow"):
					return cur_u.global_position
		var enemies: Array = SpatialGrid.query_units_in_radius(owner_unit.global_position, cast_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
		var best_enemy_pos: Vector2 = Vector2.INF
		var best_enemy_score: float = 0.0
		for node: Variant in enemies:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var e: Unit = node as Unit
			if e.is_dead or e.is_staffed or e.is_queued_for_deletion():
				continue
			var is_hostile: bool = TeamManager.are_enemies(int(owner_unit.team), int(e.team)) if TeamManager != null else (e.team != owner_unit.team)
			if not is_hostile or e.global_position.distance_to(owner_unit.global_position) > cast_r:
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
		var raw_enemies: Array = SpatialGrid.query_units_in_radius(owner_unit.global_position, cast_r + gp_r) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
		var hostile_combat: Array[Unit] = []
		for node: Variant in raw_enemies:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var e: Unit = node as Unit
			if e.is_dead or e.is_staffed or e.is_queued_for_deletion():
				continue
			var is_hostile: bool = TeamManager.are_enemies(int(owner_unit.team), int(e.team)) if TeamManager != null else (e.team != owner_unit.team)
			if not is_hostile:
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
			if centroid.distance_to(owner_unit.global_position) > cast_r:
				centroid = cand.global_position
			var gp_score: float = float(cluster_count) * 18.0 + float(un_slowed_count) * 12.0
			if gp_score > best_gp_score:
				best_gp_score = gp_score
				best_gp_pos = centroid
		return best_gp_pos

	return Vector2.INF


func _should_trigger_autocast(owner_unit: Unit, ability: AbilityData) -> bool:
	if ability.ability_id == &"adrenal_surge":
		if owner_unit.combat_component == null:
			return false
		if owner_unit.current_target != null and is_instance_valid(owner_unit.current_target):
			if owner_unit.combat_component.is_within_attack_envelope(owner_unit, owner_unit.current_target):
				return true
		return false
	if ability.ability_id == &"nanite_surge":
		return owner_unit.current_hp < owner_unit.get_max_hp() * 0.72
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

	if AudioManager != null and (owner_unit.team == Unit.Team.PLAYER or owner_unit.visible):
		AudioManager.play_ability_sfx(ability.ability_id, owner_unit.global_position)

	ability_executed.emit(ability.ability_id, target_pos)


func _execute_point_aoe(owner_unit: Unit, ability: AbilityData, target_pos: Vector2) -> void:
	if ability.ability_id == &"grav_pulse":
		_spawn_grav_pulse_effect(owner_unit, target_pos, ability.aoe_radius, ability.effect_color)
	else:
		_spawn_aoe_effect(owner_unit, target_pos, ability.aoe_radius, ability.effect_color)
	var unit_list: Array = SpatialGrid.query_units_in_radius(target_pos, ability.aoe_radius) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")

	# Allied Shield Overcharge (Aegis Relay)
	if ability.ability_id == &"monolith_shield_overcharge":
		var restore_amt: float = ability.damage_or_value if ability.damage_or_value > 0.0 else 45.0
		var barrier_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 6.0
		for node: Variant in unit_list:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var ally: Unit = node as Unit
			if ally.is_dead or ally.is_staffed or ally.is_queued_for_deletion():
				continue
			var is_ally: bool = (int(ally.team) == int(owner_unit.team)) or (TeamManager != null and TeamManager.are_allies(int(owner_unit.team), int(ally.team)))
			if not is_ally:
				continue
			var ally_r: float = ally.data.collision_radius if ally.data != null else 16.0
			if ally.global_position.distance_to(target_pos) <= ability.aoe_radius + ally_r:
				if ally.has_shields():
					ally.restore_shield(restore_amt)
				ally.add_damage_shield(30.0, barrier_dur, "Shield Overcharge")
		return

	for node: Variant in unit_list:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var candidate: Unit = node
		var is_hostile: bool = TeamManager.are_enemies(int(owner_unit.team), int(candidate.team)) if TeamManager != null else (candidate.team != owner_unit.team)
		if candidate.is_dead or candidate.is_staffed or candidate.is_queued_for_deletion() or not is_hostile:
			continue
		var enemy_r: float = candidate.data.collision_radius if candidate.data != null else 16.0
		if candidate.global_position.distance_to(target_pos) <= ability.aoe_radius + enemy_r:
			if ability.damage_or_value > 0.0:
				candidate.take_damage(ability.damage_or_value, owner_unit)
			if ability.ability_id == &"grav_pulse":
				var gp_dur: float = ability.effect_duration if ability.effect_duration > 0.0 else 5.0
				var mv_mult: float = clampf(1.0 + ability.move_speed_modifier, 0.25, 1.0) if ability.move_speed_modifier < 0.0 else 0.50
				var atk_mult: float = clampf(1.0 + ability.attack_speed_modifier, 0.25, 1.0) if ability.attack_speed_modifier < 0.0 else 0.65
				candidate.apply_status_effect(&"grav_pulse", {
					"duration": gp_dur,
					"label": "Grav-Pulse",
					"move_speed_mult": mv_mult,
					"attack_speed_mult": atk_mult,
				})
			elif ability.effect_duration > 0.0 and (ability.move_speed_modifier < 0.0 or ability.attack_speed_modifier < 0.0):
				candidate.apply_slow_debuff(ability.effect_duration, absf(ability.move_speed_modifier), absf(ability.attack_speed_modifier))

	if ability.damage_or_value > 0.0:
		var bldg_list: Array = SpatialGrid.query_buildings_in_radius(target_pos, ability.aoe_radius) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("buildings")
		for node: Variant in bldg_list:
			if not is_instance_valid(node) or not (node is Building):
				continue
			var b: Building = node
			var is_hostile_b: bool = TeamManager.are_enemies(int(owner_unit.team), int(b.team)) if TeamManager != null else (b.team != owner_unit.team)
			if b.is_destroyed or b.is_queued_for_deletion() or not is_hostile_b:
				continue
			if b.global_position.distance_to(target_pos) <= ability.aoe_radius + b.footprint_radius:
				b.take_damage(ability.damage_or_value, owner_unit)


func _execute_unit_target(owner_unit: Unit, ability: AbilityData, target_unit: Unit) -> void:
	if target_unit == null or not is_instance_valid(target_unit) or target_unit.is_dead:
		return
	_spawn_aoe_effect(owner_unit, target_unit.global_position, maxf(24.0, ability.aoe_radius), ability.effect_color)
	target_unit.take_damage(ability.damage_or_value, owner_unit)


func _execute_instant(owner_unit: Unit, ability: AbilityData) -> void:
	var ab_id: StringName = ability.ability_id

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
		owner_unit.add_damage_shield(kb_amt, kb_dur, "Kinetic Barrier")
		if owner_unit.has_shields():
			owner_unit.restore_shield(40.0)
		_spawn_hex_barrier_effect(owner_unit, maxf(36.0, ability.aoe_radius), ability.effect_color)
		return

	if ab_id == &"static_pulse" or ab_id == &"seismic_slam":
		var radius: float = maxf(32.0, ability.aoe_radius)
		var origin: Vector2 = owner_unit.global_position
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
		var unit_list2: Array = SpatialGrid.query_units_in_radius(origin, radius) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
		for node: Variant in unit_list2:
			if not is_instance_valid(node) or not (node is Unit):
				continue
			var enemy: Unit = node
			var is_hostile_e: bool = TeamManager.are_enemies(int(owner_unit.team), int(enemy.team)) if TeamManager != null else (enemy.team != owner_unit.team)
			if enemy.is_dead or enemy.is_staffed or enemy.is_queued_for_deletion() or not is_hostile_e:
				continue
			var enemy_r: float = enemy.data.collision_radius if enemy.data != null else 16.0
			if enemy.global_position.distance_to(origin) <= radius + enemy_r:
				if ability.damage_or_value > 0.0:
					enemy.take_damage(ability.damage_or_value, owner_unit)
				if ability.effect_duration > 0.0 and (ability.move_speed_modifier < 0.0 or ability.attack_speed_modifier < 0.0):
					enemy.apply_slow_debuff(
						ability.effect_duration,
						absf(ability.move_speed_modifier),
						absf(ability.attack_speed_modifier)
					)
		if ability.damage_or_value > 0.0:
			var bldg_list2: Array = SpatialGrid.query_buildings_in_radius(origin, radius) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("buildings")
			for node: Variant in bldg_list2:
				if not is_instance_valid(node) or not (node is Building):
					continue
				var b: Building = node
				var is_hostile_b2: bool = TeamManager.are_enemies(int(owner_unit.team), int(b.team)) if TeamManager != null else (b.team != owner_unit.team)
				if b.is_destroyed or b.is_queued_for_deletion() or not is_hostile_b2:
					continue
				if b.global_position.distance_to(origin) <= radius + b.footprint_radius:
					b.take_damage(ability.damage_or_value, owner_unit)
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
