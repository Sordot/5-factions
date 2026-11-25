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
		if _should_trigger_autocast(owner_unit, ab):
			request_cast(owner_unit, ab, owner_unit.global_position, owner_unit)
			return


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
	_spawn_aoe_effect(owner_unit, target_pos, ability.aoe_radius, ability.effect_color)
	var unit_list: Array = SpatialGrid.query_units_in_radius(target_pos, ability.aoe_radius) if SpatialGrid != null else owner_unit.get_tree().get_nodes_in_group("units")
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
			if ability.effect_duration > 0.0 and (ability.move_speed_modifier < 0.0 or ability.attack_speed_modifier < 0.0):
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
