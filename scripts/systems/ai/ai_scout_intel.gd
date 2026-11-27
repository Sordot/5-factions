class_name AIScoutIntel
extends RefCounted

const INTEL_TTL_SECONDS: float = 90.0

var ai: SkirmishAICommander = null
var active_scout: Unit = null
var next_scout_dispatch_time: float = 75.0
var scout_quadrant_index: int = 0
var visible_enemy_units: Dictionary = {} # instance_id -> Unit
var visible_enemy_buildings: Dictionary = {} # instance_id -> Building
var _vision_cache_elapsed: float = -1.0
var _holding_relay: Node2D = null
var _relay_hold_timer: float = 0.0
var _scout_resume_waypoints: Array[Vector2] = []
var scouted_intel: Dictionary = {
	"saw_heavy_armor": false,
	"saw_infantry_swarm": false,
	"saw_artillery": false,
	"saw_turrets": false,
	"heavy_armor_at": -999.0,
	"infantry_swarm_at": -999.0,
	"artillery_at": -999.0,
	"turrets_at": -999.0,
	"last_known_enemy_base": Vector2.INF,
}
var active_counter_posture: StringName = &"NONE"


func setup(owner_ai: SkirmishAICommander) -> void:
	ai = owner_ai


func is_entity_visible_to_ai(entity: Node2D) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if ai == null or not ai.is_inside_tree():
		return true
	var fog: FogOfWarSystem = ai.get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog == null or not fog.fog_enabled:
		return true
	return fog.is_entity_visible_to_team(int(ai.ai_team), entity)


func is_spot_safe(world_pos: Vector2, radius: float, respect_fog: bool) -> bool:
	if ai == null or SpatialGrid == null:
		return true
	var enemy_power: float = 0.0
	var ally_power: float = 0.0
	var r_sq: float = radius * radius
	for u: Unit in SpatialGrid.query_units_in_radius(world_pos, radius):
		if not is_instance_valid(u) or u.is_dead or u.is_staffed:
			continue
		if not ai.is_combat_unit(u):
			continue
		if respect_fog and world_pos.distance_squared_to(u.global_position) > r_sq:
			continue
		var w: float = ai.get_unit_power_weight(u)
		if ai.is_enemy_team(int(u.team)):
			if not respect_fog or is_entity_visible_to_ai(u):
				enemy_power += w
		elif ai.is_allied_team(int(u.team)):
			ally_power += w
	if enemy_power <= 0.01:
		return true
	return ally_power >= enemy_power * 1.15


func refresh_vision_cache(force: bool = false) -> void:
	if ai == null or not ai.is_inside_tree():
		return
	if not force and is_equal_approx(_vision_cache_elapsed, ai.ai_elapsed):
		return
	_vision_cache_elapsed = ai.ai_elapsed
	visible_enemy_units.clear()
	visible_enemy_buildings.clear()

	for node: Node in ai.get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node as Unit
			if not u.is_dead and not u.is_staffed and ai.is_allied_team(int(u.team)):
				var vr: float = u.data.vision_range if u.data != null else 320.0
				scan_vision_circle_for_intel(u.global_position, vr, visible_enemy_units, visible_enemy_buildings)
	for node: Node in ai.get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node as Building
			if not b.is_destroyed and ai.is_allied_team(int(b.team)):
				scan_vision_circle_for_intel(b.global_position, b.get_vision_range(), visible_enemy_units, visible_enemy_buildings)
	for node: Node in ai.get_tree().get_nodes_in_group("sensor_relays"):
		if is_instance_valid(node) and node is Node2D and node.has_method("is_active") and bool(node.call("is_active")):
			var ctrl_t: int = int(node.get("controlling_team"))
			if ctrl_t >= 0 and ai.is_allied_team(ctrl_t):
				scan_vision_circle_for_intel((node as Node2D).global_position, float(node.get("vision_radius")), visible_enemy_units, visible_enemy_buildings)


func is_world_pos_visible_to_ai(world_pos: Vector2) -> bool:
	if ai == null or not ai.is_inside_tree():
		return true
	var fog: FogOfWarSystem = ai.get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog == null or not fog.fog_enabled:
		return true
	return fog.is_world_pos_visible_to_team(int(ai.ai_team), world_pos)


func manage_early_scouting(core: Building, tick_dt: float = 1.0) -> void:
	if ai == null:
		return
	if active_scout != null:
		if not is_instance_valid(active_scout) or active_scout.is_dead or active_scout.is_staffed:
			active_scout = null
			_holding_relay = null
			_relay_hold_timer = 0.0
			_scout_resume_waypoints.clear()
			var rescout_cd: float = 140.0 if ai.is_relaxed_difficulty() else (65.0 if ai.is_brutal_difficulty() else 95.0)
			next_scout_dispatch_time = ai.ai_elapsed + rescout_cd
			return

		# Active SensorRelay capture hold: pause inside neutral/hostile relay up to 1.0s until flipped to allied control
		if _holding_relay != null:
			var relay_valid: bool = is_instance_valid(_holding_relay)
			var relay_flipped: bool = relay_valid and _holding_relay.has_method("is_active") and bool(_holding_relay.call("is_active")) and ai.is_allied_team(int(_holding_relay.get("controlling_team")))
			_relay_hold_timer -= tick_dt
			if not relay_valid or relay_flipped or _relay_hold_timer <= 0.0:
				_holding_relay = null
				_relay_hold_timer = 0.0
				var first_wp: bool = true
				for wp: Vector2 in _scout_resume_waypoints:
					active_scout.command_move(wp, not first_wp)
					first_wp = false
				_scout_resume_waypoints.clear()
			else:
				if active_scout.global_position.distance_squared_to(_holding_relay.global_position) > 48.0 * 48.0 and active_scout.command_state == Unit.CommandState.IDLE:
					active_scout.command_move(_holding_relay.global_position, false)
			return

		# Detect arrival near an uncaptured SensorRelay and hold briefly to flip ownership
		for r_node: Node in ai.get_tree().get_nodes_in_group("sensor_relays"):
			if not is_instance_valid(r_node) or not (r_node is Node2D):
				continue
			var r_active: bool = r_node.has_method("is_active") and bool(r_node.call("is_active"))
			var r_ctrl: int = int(r_node.get("controlling_team"))
			if r_active and ai.is_allied_team(r_ctrl):
				continue
			var r_2d: Node2D = r_node as Node2D
			if active_scout.global_position.distance_squared_to(r_2d.global_position) <= 95.0 * 95.0:
				_scout_resume_waypoints.clear()
				for q_cmd: Dictionary in active_scout.command_queue:
					var pt_v: Variant = q_cmd.get("pos", null)
					if pt_v is Vector2:
						_scout_resume_waypoints.append(pt_v as Vector2)
				_holding_relay = r_2d
				_relay_hold_timer = 1.0
				active_scout.command_move(r_2d.global_position, false)
				return

		if active_scout.command_state == Unit.CommandState.IDLE and active_scout.command_queue.is_empty():
			# Scout finished its loop cleanly; release it back to army pool
			active_scout = null
			_holding_relay = null
			_relay_hold_timer = 0.0
			_scout_resume_waypoints.clear()
			var loop_cd: float = 135.0 if ai.is_relaxed_difficulty() else (65.0 if ai.is_brutal_difficulty() else 90.0)
			next_scout_dispatch_time = ai.ai_elapsed + loop_cd
		return

	if ai.ai_elapsed < next_scout_dispatch_time:
		return

	# Pick the faction's designated fast scout first; fall back to any light mobile combatant
	var preferred_scout_id: StringName = ai.planner.get_scout_unit_id()
	var best_scout: Unit = null
	var fallback_scout: Unit = null
	for u: Unit in ai.get_team_units(ai.ai_team):
		if ai.army.wave_units.has(u) and ai.army.army_state == SkirmishAICommander.ArmyState.ATTACKING:
			continue
		if ai.army.raid_units.has(u) or ai.army.defense_units.has(u):
			continue
		if u.data == null or not u.data.is_combat_unit() or u.data.move_speed <= 0.0:
			continue
		var uid: StringName = u.get_unit_type_id()
		if (preferred_scout_id != &"" and uid == preferred_scout_id) or u.data.has_tag(&"scout") or u.data.has_tag(&"flanker"):
			if best_scout == null:
				best_scout = u
		elif not u.data.is_heavy_unit() and fallback_scout == null:
			fallback_scout = u

	var scout: Unit = best_scout if best_scout != null else fallback_scout
	if scout == null:
		return

	active_scout = scout
	ai.army.wave_units.erase(scout)

	var uplink: HyperUplink = ai.get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	var mid_pt: Vector2 = uplink.global_position if (uplink != null and is_instance_valid(uplink)) else Vector2.ZERO
	var relay_pt: Variant = find_nearest_neutral_sensor_relay_pos(core.global_position)
	var quadrant_pt: Vector2 = pick_scout_quadrant_waypoint(core)
	var return_pt: Vector2 = ai.army.staging_point if ai.army.staging_point_valid else core.global_position

	if relay_pt is Vector2:
		scout.command_move(relay_pt as Vector2, false)
		scout.command_move(mid_pt, true)
		scout.command_move(quadrant_pt, true)
		scout.command_move(return_pt, true)
	else:
		scout.command_move(mid_pt, false)
		scout.command_move(quadrant_pt, true)
		scout.command_move(return_pt, true)


func find_nearest_neutral_sensor_relay_pos(origin: Vector2) -> Variant:
	var best_pos: Variant = null
	var best_d_sq: float = INF
	for node: Node in ai.get_tree().get_nodes_in_group("sensor_relays"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var is_active_r: bool = node.has_method("is_active") and bool(node.call("is_active"))
		var ctrl_t: int = int(node.get("controlling_team"))
		if is_active_r and ai.is_allied_team(ctrl_t):
			continue
		var r_pos: Vector2 = (node as Node2D).global_position
		var d_sq: float = origin.distance_squared_to(r_pos)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_pos = r_pos
	return best_pos


func pick_scout_quadrant_waypoint(core: Building) -> Vector2:
	# Choose an unexplored/opposing map quadrant without map-hacking exact hidden buildings
	var half: Vector2 = ai.arena_bounds.size * 0.34
	var center: Vector2 = ai.arena_bounds.get_center()
	var corners: Array[Vector2] = [
		center + Vector2(-half.x, -half.y),
		center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y),
		center + Vector2(-half.x, half.y),
	]
	var candidates: Array[Vector2] = []
	for pt: Vector2 in corners:
		if pt.distance_to(core.global_position) > 650.0:
			candidates.append(pt)
	if candidates.is_empty():
		return center - (core.global_position - center) * 0.6
	var chosen: Vector2 = candidates[scout_quadrant_index % candidates.size()]
	scout_quadrant_index += 1
	# Pull slightly inward from outer corner so scout skirts the outer flank rather than suiciding into turrets
	return chosen.lerp(center, 0.24)


func update_scouted_intel() -> void:
	if ai == null or not ai.is_inside_tree():
		return

	refresh_vision_cache(false)
	var seen_enemy_units: Dictionary = visible_enemy_units
	var seen_enemy_buildings: Dictionary = visible_enemy_buildings

	var infantry_count: int = 0
	var vat_count: int = 0
	var now: float = ai.ai_elapsed

	for eu_var: Variant in seen_enemy_units.values():
		var eu: Unit = eu_var as Unit
		if not is_instance_valid(eu) or eu.is_dead or eu.data == null:
			continue
		if eu.data.has_tag(&"artillery") or eu.data.has_tag(&"siege"):
			scouted_intel["artillery_at"] = now
		elif eu.data.is_heavy_unit():
			scouted_intel["heavy_armor_at"] = now
		elif eu.data.has_tag(&"swarm") or eu.data.has_tag(&"infantry") or eu.data.has_tag(&"flanker"):
			infantry_count += 1

	for eb_var: Variant in seen_enemy_buildings.values():
		var eb: Building = eb_var as Building
		if not is_instance_valid(eb) or eb.is_destroyed:
			continue
		if eb.is_military_production_building() and eb.get_tech_tier() >= 2:
			scouted_intel["heavy_armor_at"] = now
			scouted_intel["last_known_enemy_base"] = eb.global_position
		elif eb.is_military_production_building() and eb.get_tech_tier() == 1:
			vat_count += 1
			scouted_intel["last_known_enemy_base"] = eb.global_position
		elif eb.is_command_hub():
			scouted_intel["last_known_enemy_base"] = eb.global_position
		if eb.has_turret:
			scouted_intel["turrets_at"] = now

	# Clear stale last_known_enemy_base if we currently have vision over it and no enemy buildings remain there
	var lkeb: Vector2 = scouted_intel.get("last_known_enemy_base", Vector2.INF) as Vector2
	if lkeb != Vector2.INF and is_world_pos_visible_to_ai(lkeb):
		var still_occupied: bool = false
		for eb_chk_var: Variant in seen_enemy_buildings.values():
			var eb_chk: Building = eb_chk_var as Building
			if is_instance_valid(eb_chk) and not eb_chk.is_destroyed and eb_chk.global_position.distance_squared_to(lkeb) <= 320.0 * 320.0:
				still_occupied = true
				break
		if not still_occupied:
			scouted_intel["last_known_enemy_base"] = Vector2.INF

	if vat_count >= 2 or infantry_count >= 6:
		scouted_intel["infantry_swarm_at"] = now

	# Apply 90s intel decay TTL
	scouted_intel["saw_heavy_armor"] = (now - float(scouted_intel["heavy_armor_at"])) <= INTEL_TTL_SECONDS
	scouted_intel["saw_infantry_swarm"] = (now - float(scouted_intel["infantry_swarm_at"])) <= INTEL_TTL_SECONDS
	scouted_intel["saw_artillery"] = (now - float(scouted_intel["artillery_at"])) <= INTEL_TTL_SECONDS
	scouted_intel["saw_turrets"] = (now - float(scouted_intel["turrets_at"])) <= INTEL_TTL_SECONDS

	# Determine active counter posture (freshest / highest-priority spotted threat)
	var best_posture: StringName = &"NONE"
	var best_time: float = -1.0
	if bool(scouted_intel["saw_heavy_armor"]):
		var t_ha: float = float(scouted_intel["heavy_armor_at"]) + 6.0
		if t_ha > best_time:
			best_time = t_ha
			best_posture = &"ANTI_ARMOR"
	if bool(scouted_intel["saw_artillery"]):
		var t_art: float = float(scouted_intel["artillery_at"]) + 4.0
		if t_art > best_time:
			best_time = t_art
			best_posture = &"ANTI_SIEGE"
	if bool(scouted_intel["saw_infantry_swarm"]):
		var t_sw: float = float(scouted_intel["infantry_swarm_at"])
		if t_sw > best_time:
			best_time = t_sw
			best_posture = &"ANTI_SWARM"
	active_counter_posture = best_posture


func scan_vision_circle_for_intel(center: Vector2, radius: float, seen_units: Dictionary, seen_buildings: Dictionary) -> void:
	if ai == null or SpatialGrid == null:
		return
	var r_sq: float = radius * radius
	for u: Unit in SpatialGrid.query_units_in_radius(center, radius):
		if not is_instance_valid(u) or u.is_dead or u.is_staffed:
			continue
		if not ai.is_enemy_team(int(u.team)):
			continue
		if center.distance_squared_to(u.global_position) <= r_sq and is_entity_visible_to_ai(u):
			seen_units[u.get_instance_id()] = u
	for b: Building in SpatialGrid.query_buildings_in_radius(center, radius):
		if not is_instance_valid(b) or b.is_destroyed:
			continue
		if not ai.is_enemy_team(int(b.team)):
			continue
		var eff_r: float = radius + b.footprint_radius
		if center.distance_squared_to(b.global_position) <= eff_r * eff_r and is_entity_visible_to_ai(b):
			seen_buildings[b.get_instance_id()] = b


func get_counter_reaction_strength() -> float:
	if ai == null:
		return 0.75
	if ai.is_relaxed_difficulty():
		return 0.35
	if ai.is_brutal_difficulty():
		return 1.0
	return 0.75
