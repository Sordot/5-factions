class_name SkirmishAICommander
extends Node

const MapLandmarkScript = preload("res://scripts/world/map_landmark.gd")
const AIBuildPlannerScript = preload("res://scripts/systems/ai_build_planner.gd")

const INTEL_SCAN_INTERVAL: float = 1.5
const INTEL_TTL_SECONDS: float = 90.0
const BARRICADE_MIN_MATCH_TIME: float = 150.0
const TRANSMISSION_GLOBAL_COOLDOWN_MS: int = 45000
const TRANSMISSION_CATEGORY_COOLDOWN_MS: int = 90000

const DEFAULT_AI_TRANSMISSIONS: Dictionary = {
	&"wave_launch": "// AI COMMAND: Strike column deployed. Engaging hostile perimeter.",
	&"barricade_breach": "// AI COMMAND: Obstruction cleared. Advancing through flank corridor.",
	&"tier2_online": "// AI COMMAND: Tier-2 heavy production facility online.",
	&"uplink_contest": "// AI COMMAND: Converging on Data Hyper-Uplink coordinates.",
	&"under_attack": "// AI COMMAND: Outpost integrity compromised. Redirecting defense.",
}

var _last_transmission_ms: int = -999999
var _last_transmission_by_cat: Dictionary = {}
var _tier2_transmission_sent: bool = false
const BASE_DEFENSE_CLEAR_TIME: float = 3.0
const RETREAT_REGROUP_DURATION: float = 8.0

enum ArmyState {
	STAGING,
	ATTACKING,
	DEFENDING,
	RETREATING,
	BREACHING,
}

@export var ai_team: Unit.Team = Unit.Team.ENEMY
@export var enabled: bool = true
@export var decision_interval: float = 1.0
@export var target_worker_count: int = 6
@export var max_cloning_vats: int = 2
@export var max_bandwidth_cap: int = 56
@export var wave_squad_size: int = 6
@export var max_wave_interval: float = 48.0
@export var base_defense_radius: float = 650.0
@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)

var _planner: AIBuildPlannerScript = AIBuildPlannerScript.new()
var _refinery_data: BuildingData = null
var _supply_data: BuildingData = null
var _compute_hub_data: BuildingData = null
var _barracks_t1_data: BuildingData = null
var _counter_foundry_data: BuildingData = null
var _heavy_t2_data: BuildingData = null
var _worker_data: UnitData = null
var _harvester_data: UnitData = null
var _engineer_data: UnitData = null

var _decision_timer: float = 0.0
var _ai_elapsed: float = 0.0
var _wave_timer: float = 0.0
var _wave_cooldown_timer: float = 0.0
var _wave_number: int = 0
var _vat_production_counter: int = 0
var _foundry_production_counter: int = 0
var _fab_production_counter: int = 0
var _ai_difficulty: int = 1
var _ai_playstyle: int = 0

# Phase A: Staging & Army State Machine
var army_state: ArmyState = ArmyState.STAGING
var _staging_point: Vector2 = Vector2.ZERO
var _staging_point_valid: bool = false
var _staging_snapped_to_nav: bool = false
var _last_core_count: int = 0
var _wave_units: Array[Unit] = []
var _wave_launch_strength: float = 0.0
var _current_attack_target: Vector2 = Vector2.ZERO
var _regroup_timer: float = 0.0
var _defense_clear_timer: float = 0.0
var _breach_target: Node2D = null
var _last_staging_count: int = 0

# Phase B: Early Scouting & Fair Vision-Respecting Intel
var _active_scout: Unit = null
var _next_scout_dispatch_time: float = 75.0
var _scout_quadrant_index: int = 0
var _intel_scan_timer: float = 0.0
var _scouted_intel: Dictionary = {
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
var _active_counter_posture: StringName = &"NONE"

# Phase C: Salvage throttling & stall recovery
var _salvage_scan_timer: float = 0.0
var _unit_last_pos: Dictionary = {}
var _unit_stall_ticks: Dictionary = {}
var _deploy_idle_timers: Dictionary = {}


func _ready() -> void:
	add_to_group("skirmish_ai")
	_load_faction_rosters()
	_apply_lobby_ai_profile()
	call_deferred("_setup_initial_rallies")


func _load_faction_rosters() -> void:
	var faction_data: FactionData = TeamManager.get_team_faction_data(int(ai_team)) if TeamManager != null else null
	_planner.bind_faction(faction_data)
	_refinery_data = _planner.get_building_for_role(&"refinery")
	_supply_data = _planner.get_building_for_role(&"supply")
	_compute_hub_data = _planner.get_building_for_role(&"compute_hub")
	_barracks_t1_data = _planner.get_building_for_role(&"barracks_t1")
	_counter_foundry_data = _planner.get_building_for_role(&"counter_foundry")
	_heavy_t2_data = _planner.get_building_for_role(&"heavy_t2")
	_worker_data = _planner.get_unit_for_role(&"worker")
	_harvester_data = _planner.get_unit_for_role(&"harvester")
	_engineer_data = _planner.get_unit_for_role(&"engineer")


func _apply_lobby_ai_profile() -> void:
	if GameConfig == null:
		return
	if TeamManager != null and TeamManager.is_active_team(int(ai_team)):
		_ai_difficulty = TeamManager.get_team_ai_difficulty(int(ai_team))
		_ai_playstyle = TeamManager.get_team_ai_playstyle(int(ai_team))
	else:
		_ai_difficulty = int(GameConfig.ai_difficulty)
		_ai_playstyle = int(GameConfig.ai_playstyle)

	match _ai_difficulty:
		int(GameConfig.AIDifficulty.RELAXED):
			decision_interval = 1.5
			target_worker_count = 4
			wave_squad_size = 6
			max_wave_interval = 64.0
			max_cloning_vats = 1
			_next_scout_dispatch_time = 130.0
		int(GameConfig.AIDifficulty.BRUTAL):
			decision_interval = 0.7
			target_worker_count = 8
			wave_squad_size = 7
			max_wave_interval = 36.0
			max_cloning_vats = 3
			_next_scout_dispatch_time = 55.0
		_:
			decision_interval = 1.0
			target_worker_count = 6
			wave_squad_size = 6
			max_wave_interval = 48.0
			max_cloning_vats = 2
			_next_scout_dispatch_time = 75.0

	if _ai_playstyle == int(GameConfig.AIPlaystyle.SWARM_RUSH):
		wave_squad_size = 5 if _ai_difficulty != int(GameConfig.AIDifficulty.BRUTAL) else 6
		max_wave_interval *= 0.80
		max_cloning_vats = maxi(max_cloning_vats, 2)
	elif _ai_playstyle == int(GameConfig.AIPlaystyle.SYNTHETICS_TECH):
		wave_squad_size = maxi(wave_squad_size + 1, 8)
		max_wave_interval *= 1.12


func _process(delta: float) -> void:
	if not enabled:
		return
	_ai_elapsed += delta
	_wave_timer += delta
	if _wave_cooldown_timer > 0.0:
		_wave_cooldown_timer = maxf(0.0, _wave_cooldown_timer - delta)
	_intel_scan_timer += delta
	_salvage_scan_timer += delta
	_decision_timer += delta
	if _decision_timer < maxf(0.25, decision_interval):
		return
	var tick_dt: float = _decision_timer
	_decision_timer = 0.0
	_run_decision_tick(tick_dt)


func _setup_initial_rallies() -> void:
	var core: Building = _find_ai_command_core()
	if core == null:
		return
	var nearest_bio: ResourceNode = _find_nearest_resource(core.global_position, &"biomass")
	if nearest_bio != null:
		core.set_rally_target(nearest_bio)
	_compute_staging_point(core)
	_sync_military_rallies()


func _compute_staging_point(core: Building) -> Vector2:
	if core == null or not is_instance_valid(core):
		return _staging_point

	var center_ref: Vector2 = Vector2.ZERO
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if uplink != null and is_instance_valid(uplink):
		center_ref = uplink.global_position

	var to_center: Vector2 = center_ref - core.global_position
	var base_dir: Vector2 = to_center.normalized() if to_center.length_squared() > 16.0 else Vector2.RIGHT

	var safe_bounds: Rect2 = arena_bounds.grow(-92.0)
	var distances: PackedFloat32Array = PackedFloat32Array([390.0, 355.0, 435.0, 310.0])
	var angles: PackedFloat32Array = PackedFloat32Array([0.0, 0.24, -0.24, 0.50, -0.50, 0.80, -0.80])

	var chosen: Vector2 = core.global_position + base_dir * 380.0
	var found_clear: bool = false
	for dist: float in distances:
		for ang: float in angles:
			var cand: Vector2 = core.global_position + base_dir.rotated(ang) * dist
			if safe_bounds.has_area():
				cand.x = clampf(cand.x, safe_bounds.position.x, safe_bounds.end.x)
				cand.y = clampf(cand.y, safe_bounds.position.y, safe_bounds.end.y)
			if _is_staging_spot_clear(cand, 44.0):
				chosen = cand
				found_clear = true
				break
		if found_clear:
			break

	var map_rid: RID = get_viewport().world_2d.navigation_map if get_viewport() != null else RID()
	if map_rid.is_valid() and NavigationServer2D.map_get_iteration_id(map_rid) > 0:
		chosen = NavigationServer2D.map_get_closest_point(map_rid, chosen)
		_staging_snapped_to_nav = true
	else:
		_staging_snapped_to_nav = false

	_staging_point = chosen
	_staging_point_valid = true
	return _staging_point


func _is_staging_spot_clear(world_pos: Vector2, clearance_r: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_r)):
				return false
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_r)):
				return false
	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(node) and not bool(node.get("is_destroyed")) and node.has_method("overlaps_circle"):
			if bool(node.call("overlaps_circle", world_pos, clearance_r)):
				return false
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node) and not (node as Building).is_destroyed:
			var min_d: float = (node as Building).footprint_radius + clearance_r
			if (node as Building).global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	return true


func _sync_military_rallies() -> void:
	if not _staging_point_valid:
		return
	var rally_lead: Unit = null
	if army_state == ArmyState.ATTACKING and _get_wave_strength_ratio() > 0.70:
		for u: Unit in _wave_units:
			if is_instance_valid(u) and not u.is_dead and not u.is_staffed:
				rally_lead = u
				break

	for b: Building in _get_team_buildings(ai_team):
		if not b.is_constructed or b.is_destroyed or not b.can_set_rally:
			continue
		if not _is_military_production_building(b):
			continue
		if rally_lead != null:
			if b.get_rally_target() != rally_lead:
				b.set_rally_target_unit(rally_lead)
		else:
			if b.get_rally_target() != null or b.get_rally_world_position().distance_squared_to(_staging_point) > 36.0:
				b.set_rally_position(_staging_point)


func _is_military_production_building(b: Building) -> bool:
	return b != null and b.is_military_production_building()


func _run_decision_tick(tick_dt: float) -> void:
	var econ: EconomyManager = _get_economy_manager()
	if econ == null:
		return
	var core: Building = _find_ai_command_core()
	if core == null:
		return

	# Ensure staging anchor is initialized & nav-snapped, and recompute when expansion Nexus Vats complete.
	var core_count: int = _count_constructed_command_cores()
	if not _staging_point_valid or not _staging_snapped_to_nav or core_count != _last_core_count:
		_last_core_count = core_count
		_compute_staging_point(core)

	# 1. Fair vision-respecting intel update (every 1.5s)
	if _intel_scan_timer >= INTEL_SCAN_INTERVAL:
		_intel_scan_timer = 0.0
		_update_scouted_intel()

	# 2. Safe SalvageCore contesting (throttled by difficulty)
	var salvage_interval: float = 6.0 if _is_relaxed_difficulty() else 3.0
	if _salvage_scan_timer >= salvage_interval:
		_salvage_scan_timer = 0.0
		_collect_safe_salvage(core)

	# 3. Assign idle workers, harvesters, engineers, and resume unfinished sites
	_assign_idle_workers(core)
	_assign_idle_harvesters()
	_assign_idle_engineers()
	_resume_unfinished_buildings()

	var aggro_enabled: bool = MatchManager.is_aggro_ai_enabled(get_tree())
	if not aggro_enabled:
		return

	# 4. Sync production rally points, recover stalled combat units & fire combat abilities
	_sync_military_rallies()
	_recover_stalled_combat_units()
	_trigger_combat_abilities()

	# 5. Economy, infrastructure, reactive production & Core Overclock macro
	_manage_economy_and_production(econ, core)
	_manage_overclock_macro()

	# 6. Early scouting dispatch
	_manage_early_scouting(core)

	# 7. Explicit Army State Machine (DEFENDING / RETREATING / BREACHING / ATTACKING / STAGING) & Deploy micro
	_tick_army_state_machine(core, tick_dt)
	_manage_deploy_micro(tick_dt)


# =============================================================================
# PHASE A & C: ARMY STATE MACHINE (STAGING / ATTACKING / DEFENDING / RETREATING / BREACHING)
# =============================================================================

func _tick_army_state_machine(core: Building, tick_dt: float) -> void:
	_prune_wave_units()

	# 1. Immediate Base Defense interrupt (highest priority)
	var threat_pos: Variant = _find_base_perimeter_threat(core)
	if threat_pos is Vector2:
		army_state = ArmyState.DEFENDING
		_defense_clear_timer = 0.0
		_dispatch_base_defense(threat_pos as Vector2, core)
		return
	elif army_state == ArmyState.DEFENDING:
		_defense_clear_timer += tick_dt
		if _defense_clear_timer >= BASE_DEFENSE_CLEAR_TIME:
			_defense_clear_timer = 0.0
			army_state = ArmyState.STAGING
			_rally_idle_combat_to_staging()
		return

	match army_state:
		ArmyState.RETREATING:
			_tick_retreating_state(tick_dt)
		ArmyState.BREACHING:
			_tick_breaching_state(core)
		ArmyState.ATTACKING:
			_tick_attacking_state(core)
		ArmyState.STAGING:
			_tick_staging_state(core)


func _is_entity_visible_to_ai(entity: Node2D) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if not is_inside_tree():
		return true
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog == null or not fog.fog_enabled:
		return true
	return fog.is_entity_visible_to_team(int(ai_team), entity)


func _find_base_perimeter_threat(core: Building) -> Variant:
	var ai_buildings: Array[Building] = _get_team_buildings(ai_team)
	var threat_unit: Unit = null
	var best_d_sq: float = INF

	# Check ~650px perimeter around every owned Command Hub and economy drop-off via SpatialGrid.
	# Obeys Fog of War / high-ground vision (only reacts to visible hostiles or those actively firing on AI assets).
	for b: Building in ai_buildings:
		var check_r: float = base_defense_radius if (b.is_command_hub() or b.is_resource_dropoff) else 380.0
		var nearby: Array = SpatialGrid.query_units_in_radius(b.global_position, check_r) if SpatialGrid != null else get_tree().get_nodes_in_group("units")
		var r_sq: float = check_r * check_r
		for item: Variant in nearby:
			if not is_instance_valid(item) or not (item is Unit):
				continue
			var hostile: Unit = item as Unit
			if hostile.is_dead or hostile.is_staffed or not _is_enemy_team(int(hostile.team)):
				continue
			if not _is_combat_unit(hostile) and hostile.command_state != Unit.CommandState.ATTACKING_TARGET:
				continue
			var attacking_ai_asset: bool = false
			if hostile.current_target != null and is_instance_valid(hostile.current_target):
				if hostile.current_target is Unit and _is_allied_team(int((hostile.current_target as Unit).team)):
					attacking_ai_asset = true
				elif hostile.current_target is Building and _is_allied_team(int((hostile.current_target as Building).team)):
					attacking_ai_asset = true
			if not attacking_ai_asset and not _is_entity_visible_to_ai(hostile):
				continue
			var d_sq: float = b.global_position.distance_squared_to(hostile.global_position)
			if d_sq <= r_sq and d_sq < best_d_sq:
				best_d_sq = d_sq
				threat_unit = hostile

	# Also protect workers under direct harassment
	if threat_unit == null and core != null:
		var near_core_workers: Array = SpatialGrid.query_units_in_radius(core.global_position, 720.0) if SpatialGrid != null else []
		for item: Variant in near_core_workers:
			if is_instance_valid(item) and item is Unit:
				var u: Unit = item as Unit
				if not u.is_dead and not u.is_staffed and _is_enemy_team(int(u.team)):
					if u.global_position.distance_to(core.global_position) <= base_defense_radius and _is_entity_visible_to_ai(u):
						threat_unit = u
						break

	return threat_unit.global_position if threat_unit != null else null


func _dispatch_base_defense(threat_pos: Vector2, core: Building) -> void:
	var home_defenders: Array[Unit] = []
	var distant_attackers: Array[Unit] = []
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u) or u == _active_scout:
			continue
		if _wave_units.has(u) and u.global_position.distance_to(core.global_position) > 950.0:
			distant_attackers.append(u)
		else:
			home_defenders.append(u)

	# Pull attacking army home only if fewer than 3 defenders remain near base
	var responders: Array[Unit] = home_defenders.duplicate()
	if home_defenders.size() < 3:
		for au: Unit in distant_attackers:
			responders.append(au)
		_wave_units.clear()
		_wave_launch_strength = 0.0

	_breach_target = null
	for u: Unit in responders:
		var needs_order: bool = (
			u.command_state == Unit.CommandState.IDLE
			or u.command_state == Unit.CommandState.MOVING
			or (u.command_state == Unit.CommandState.ATTACK_MOVING and u.current_target == null and u.global_position.distance_to(threat_pos) > 220.0)
			or (u.command_state == Unit.CommandState.ATTACKING_TARGET and u.current_target != null and u.current_target.is_in_group("destructible_barricades"))
		)
		if needs_order:
			u.command_attack_move(threat_pos, false)


func _tick_retreating_state(tick_dt: float) -> void:
	_regroup_timer = maxf(0.0, _regroup_timer - tick_dt)
	var all_arrived: bool = true
	for u: Unit in _wave_units:
		if u.global_position.distance_to(_staging_point) > 220.0:
			all_arrived = false
			if u.command_state != Unit.CommandState.MOVING:
				u.command_move(_staging_point, false)
	if _regroup_timer <= 0.0 or _wave_units.is_empty() or all_arrived:
		_wave_units.clear()
		_wave_launch_strength = 0.0
		_regroup_timer = 0.0
		army_state = ArmyState.STAGING


func _tick_breaching_state(core: Building) -> void:
	if _breach_target == null or not is_instance_valid(_breach_target) or bool(_breach_target.get("is_destroyed")) or _breach_target.is_queued_for_deletion():
		# Gate breached! Push through as a flank raid if squad is healthy, else regroup at staging
		_breach_target = null
		if _wave_units.size() >= 4:
			_launch_wave_from_units(_wave_units, core, false)
		else:
			_wave_units.clear()
			_wave_launch_strength = 0.0
			army_state = ArmyState.STAGING
		return

	if _wave_units.is_empty():
		_breach_target = null
		army_state = ArmyState.STAGING
		return

	# Interrupt breaching immediately if hostile combat units engage the breaching squad
	var intercept_pos: Variant = _find_hostile_near_squad(_wave_units, 340.0)
	if intercept_pos is Vector2:
		_breach_target = null
		_wave_launch_strength = _compute_units_strength(_wave_units)
		_current_attack_target = intercept_pos as Vector2
		army_state = ArmyState.ATTACKING
		for u: Unit in _wave_units:
			u.command_attack_move(_current_attack_target, false)
		return

	# Keep breaching squad explicitly focus-firing the DestructibleBarricade
	for u: Unit in _wave_units:
		if u.data != null and u.data.attack_damage <= 0.0:
			# Support units (Symbiote) escort slightly behind the barricade
			if u.global_position.distance_to(_breach_target.global_position) > 150.0 and u.command_state == Unit.CommandState.IDLE:
				u.command_move(_breach_target.global_position.lerp(_staging_point, 0.25), false)
			continue
		if u.command_state != Unit.CommandState.ATTACKING_TARGET or u.current_target != _breach_target:
			u.command_attack_target(_breach_target, false)


func _tick_attacking_state(core: Building) -> void:
	if _wave_units.is_empty():
		_wave_launch_strength = 0.0
		army_state = ArmyState.STAGING
		return

	var remaining_ratio: float = _get_wave_strength_ratio()
	var retreat_threshold: float = 0.30 if _is_brutal_difficulty() else 0.25
	if remaining_ratio < retreat_threshold and not _is_wave_finishing_enemy_core():
		# Pull survivors back to _staging_point to regroup with fresh reinforcements
		army_state = ArmyState.RETREATING
		_regroup_timer = RETREAT_REGROUP_DURATION
		_wave_cooldown_timer = 16.0 if _is_relaxed_difficulty() else 8.0
		for u: Unit in _wave_units:
			u.command_move(_staging_point, false)
		return

	# Keep non-wave newly spawned reinforcements calmly staged at _staging_point
	_rally_idle_combat_to_staging(true)

	# Re-push any wave units that went idle after clearing an enemy pocket
	var idle_wave: Array[Unit] = []
	for u: Unit in _wave_units:
		if u.command_state == Unit.CommandState.IDLE:
			idle_wave.append(u)
	if not idle_wave.is_empty():
		_current_attack_target = _select_wave_target(_wave_number, core)
		var router: CommandRouter = _get_command_router()
		var slots: Array[Vector2] = router.assign_group_destinations(idle_wave, _current_attack_target) if router != null else []
		for i: int in range(idle_wave.size()):
			var dest: Vector2 = slots[i] if i < slots.size() else _current_attack_target
			idle_wave[i].command_attack_move(dest, false)


func _tick_staging_state(core: Building) -> void:
	var staging_units: Array[Unit] = _collect_staging_combat_units()
	_last_staging_count = staging_units.size()

	# Form up idle/stray combat units cleanly around _staging_point
	_rally_idle_combat_to_staging(false)

	# Phase C.1: Mid-game DestructibleBarricade breaching on Twin Causeway / Quad Nexus
	if _ai_elapsed >= BARRICADE_MIN_MATCH_TIME and staging_units.size() >= 4:
		var breach_gate: Node2D = _find_nearby_intact_barricade(core.global_position, 1100.0)
		if breach_gate != null and (_squad_has_anti_armor_or_siege(staging_units) or staging_units.size() >= 6):
			army_state = ArmyState.BREACHING
			_breach_target = breach_gate
			_wave_units = staging_units.duplicate()
			_wave_launch_strength = _compute_units_strength(_wave_units)
			for u: Unit in _wave_units:
				if u.data != null and u.data.attack_damage > 0.0:
					u.command_attack_target(_breach_target, false)
				else:
					u.command_move(_breach_target.global_position.lerp(_staging_point, 0.25), false)
			_try_emit_ai_transmission(&"barricade_breach", _sanitize_transmission_pos(_breach_target.global_position, false))
			return

	if _wave_cooldown_timer > 0.0:
		return

	var target_size: int = _get_target_wave_size()
	var ready_by_size: bool = staging_units.size() >= target_size
	var ready_by_timer: bool = _wave_timer >= max_wave_interval and staging_units.size() >= maxi(3, target_size - 2)
	if not ready_by_size and not ready_by_timer:
		return

	_launch_wave_from_units(staging_units, core, true)


func _launch_wave_from_units(squad: Array[Unit], core: Building, allow_flank: bool) -> void:
	if squad.is_empty():
		return
	_wave_number += 1
	_wave_timer = 0.0
	_wave_cooldown_timer = 30.0 if _is_relaxed_difficulty() else (8.0 if _is_brutal_difficulty() else 12.0)

	_wave_units = squad.duplicate()
	_wave_launch_strength = _compute_units_strength(_wave_units)
	_current_attack_target = _select_wave_target(_wave_number, core)
	army_state = ArmyState.ATTACKING
	var uplink_node: Node2D = get_tree().get_first_node_in_group("hyper_uplinks") as Node2D
	if uplink_node != null and is_instance_valid(uplink_node) and _current_attack_target.distance_squared_to(uplink_node.global_position) <= 140.0 * 140.0:
		_try_emit_ai_transmission(&"uplink_contest", uplink_node.global_position)
	else:
		_try_emit_ai_transmission(&"wave_launch", Vector2.INF)

	var router: CommandRouter = _get_command_router()
	var destinations: Array[Vector2] = router.assign_group_destinations(_wave_units, _current_attack_target) if router != null else []

	var use_flank: bool = allow_flank and _wave_number >= 2 and (_wave_number % 2) == 0
	var flank_wp: Vector2 = Vector2.ZERO
	if use_flank:
		var north_lane: bool = ((_wave_number / 2) % 2) == 1
		flank_wp = _get_flank_corridor_waypoint(north_lane)
		# Don't route a flank wave into an intact barricade unless actively breaching it
		if _find_nearby_intact_barricade(flank_wp, 240.0) != null:
			use_flank = false

	var flank_slots: Array[Vector2] = []
	if use_flank and router != null:
		flank_slots = router.assign_group_destinations(_wave_units, flank_wp)

	for i: int in range(_wave_units.size()):
		var trooper: Unit = _wave_units[i]
		var dest: Vector2 = destinations[i] if i < destinations.size() else _current_attack_target
		if use_flank:
			var leg1: Vector2 = flank_slots[i] if i < flank_slots.size() else flank_wp
			trooper.command_attack_move(leg1, false)
			trooper.command_attack_move(dest, true)
		else:
			trooper.command_attack_move(dest, false)


func _collect_staging_combat_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u) or u == _active_scout:
			continue
		out.append(u)
	return out


func _rally_idle_combat_to_staging(exclude_active_wave: bool = false) -> void:
	if not _staging_point_valid:
		return
	var strays: Array[Unit] = []
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u) or u == _active_scout:
			continue
		if exclude_active_wave and _wave_units.has(u):
			continue
		if u.command_state == Unit.CommandState.IDLE and u.global_position.distance_to(_staging_point) > 220.0:
			strays.append(u)
	if strays.is_empty():
		return
	var router: CommandRouter = _get_command_router()
	var slots: Array[Vector2] = router.assign_group_destinations(strays, _staging_point) if router != null else []
	for i: int in range(strays.size()):
		var dest: Vector2 = slots[i] if i < slots.size() else _staging_point
		strays[i].command_move(dest, false)


func _get_target_wave_size() -> int:
	var base_sz: int = wave_squad_size
	if _is_brutal_difficulty():
		var scale_up: int = mini(3, int(floor(_ai_elapsed / 150.0)))
		return clampi(base_sz + scale_up, 6, 10)
	elif not _is_relaxed_difficulty():
		var scale_std: int = mini(2, int(floor(_ai_elapsed / 180.0)))
		return clampi(base_sz + scale_std, 5, 9)
	return base_sz


func _get_unit_power_weight(unit: Unit) -> float:
	if unit == null or not is_instance_valid(unit) or unit.data == null:
		return 0.0
	if unit.data.is_heavy_unit() or unit.data.has_tag(&"artillery"):
		return 3.0
	if unit.data.has_tag(&"anti_armor") or unit.data.has_tag(&"disruptor"):
		return 2.0
	if unit.data.has_tag(&"support"):
		return 1.5
	return 1.0


func _compute_units_strength(units: Array[Unit]) -> float:
	var total: float = 0.0
	for u: Unit in units:
		if is_instance_valid(u) and not u.is_dead and not u.is_staffed:
			total += _get_unit_power_weight(u)
	return total


func _get_wave_strength_ratio() -> float:
	if _wave_launch_strength <= 0.01:
		return 1.0
	return _compute_units_strength(_wave_units) / _wave_launch_strength


func _is_wave_finishing_enemy_core() -> bool:
	var enemy_cores: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node as Building
			if not b.is_destroyed and _is_enemy_team(int(b.team)) and b.is_command_hub():
				if (b.current_hp / maxf(1.0, b.max_hp)) < 0.35:
					enemy_cores.append(b)
	if enemy_cores.is_empty():
		return false
	for u: Unit in _wave_units:
		if not is_instance_valid(u) or u.is_dead:
			continue
		for ec: Building in enemy_cores:
			if u.global_position.distance_squared_to(ec.global_position) <= 320.0 * 320.0:
				return true
	return false


func _find_hostile_near_squad(squad: Array[Unit], radius: float) -> Variant:
	var r_sq: float = radius * radius
	for u: Unit in squad:
		if not is_instance_valid(u) or u.is_dead:
			continue
		var nearby: Array = SpatialGrid.query_units_in_radius(u.global_position, radius) if SpatialGrid != null else []
		for item: Variant in nearby:
			if is_instance_valid(item) and item is Unit:
				var h: Unit = item as Unit
				if not h.is_dead and not h.is_staffed and _is_enemy_team(int(h.team)) and _is_combat_unit(h):
					if u.global_position.distance_squared_to(h.global_position) <= r_sq and _is_entity_visible_to_ai(h):
						return h.global_position
	return null


func _prune_wave_units() -> void:
	var kept: Array[Unit] = []
	for u: Unit in _wave_units:
		if is_instance_valid(u) and not u.is_dead and not u.is_staffed and not u.is_queued_for_deletion():
			kept.append(u)
	_wave_units = kept


# =============================================================================
# PHASE B: EARLY SCOUTING & VISION-RESPECTING INTEL / COUNTER WEIGHTS
# =============================================================================

func _manage_early_scouting(core: Building) -> void:
	if _active_scout != null:
		if not is_instance_valid(_active_scout) or _active_scout.is_dead or _active_scout.is_staffed:
			_active_scout = null
			var rescout_cd: float = 140.0 if _is_relaxed_difficulty() else (65.0 if _is_brutal_difficulty() else 95.0)
			_next_scout_dispatch_time = _ai_elapsed + rescout_cd
		elif _active_scout.command_state == Unit.CommandState.IDLE and _active_scout.command_queue.is_empty():
			# Scout finished its loop cleanly; release it back to army pool
			_active_scout = null
			var loop_cd: float = 135.0 if _is_relaxed_difficulty() else (65.0 if _is_brutal_difficulty() else 90.0)
			_next_scout_dispatch_time = _ai_elapsed + loop_cd
		return

	if _ai_elapsed < _next_scout_dispatch_time:
		return

	# Pick the faction's designated fast scout first; fall back to any light mobile combatant
	var preferred_scout_id: StringName = _planner.get_scout_unit_id()
	var best_scout: Unit = null
	var fallback_scout: Unit = null
	for u: Unit in _get_team_units(ai_team):
		if _wave_units.has(u) and army_state == ArmyState.ATTACKING:
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

	_active_scout = scout
	_wave_units.erase(scout)

	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	var mid_pt: Vector2 = uplink.global_position if (uplink != null and is_instance_valid(uplink)) else Vector2.ZERO
	var relay_pt: Variant = _find_nearest_neutral_sensor_relay_pos(core.global_position)
	var quadrant_pt: Vector2 = _pick_scout_quadrant_waypoint(core)
	var return_pt: Vector2 = _staging_point if _staging_point_valid else core.global_position

	if relay_pt is Vector2:
		scout.command_move(relay_pt as Vector2, false)
		scout.command_move(mid_pt, true)
		scout.command_move(quadrant_pt, true)
		scout.command_move(return_pt, true)
	else:
		scout.command_move(mid_pt, false)
		scout.command_move(quadrant_pt, true)
		scout.command_move(return_pt, true)


func _find_nearest_neutral_sensor_relay_pos(origin: Vector2) -> Variant:
	var best_pos: Variant = null
	var best_d_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("sensor_relays"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var is_active_r: bool = node.has_method("is_active") and bool(node.call("is_active"))
		var ctrl_t: int = int(node.get("controlling_team"))
		if is_active_r and _is_allied_team(ctrl_t):
			continue
		var r_pos: Vector2 = (node as Node2D).global_position
		var d_sq: float = origin.distance_squared_to(r_pos)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_pos = r_pos
	return best_pos


func _pick_scout_quadrant_waypoint(core: Building) -> Vector2:
	# Choose an unexplored/opposing map quadrant without map-hacking exact hidden buildings
	var half: Vector2 = arena_bounds.size * 0.34
	var center: Vector2 = arena_bounds.get_center()
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
	var chosen: Vector2 = candidates[_scout_quadrant_index % candidates.size()]
	_scout_quadrant_index += 1
	# Pull slightly inward from outer corner so scout skirts the outer flank rather than suiciding into turrets
	return chosen.lerp(center, 0.24)


func _update_scouted_intel() -> void:
	if not is_inside_tree():
		return

	# Collect vision sources belonging to this AI (and allied teams in 2v2) — zero Fog-of-War cheating!
	var seen_enemy_units: Dictionary = {}
	var seen_enemy_buildings: Dictionary = {}
	var observers_units: Array[Unit] = []
	var observers_buildings: Array[Building] = []

	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node as Unit
			if not u.is_dead and not u.is_staffed and _is_allied_team(int(u.team)):
				observers_units.append(u)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node as Building
			if not b.is_destroyed and _is_allied_team(int(b.team)):
				observers_buildings.append(b)

	for obs_u: Unit in observers_units:
		var vr: float = obs_u.data.vision_range if obs_u.data != null else 320.0
		_scan_vision_circle_for_intel(obs_u.global_position, vr, seen_enemy_units, seen_enemy_buildings)
	for obs_b: Building in observers_buildings:
		var vr_b: float = obs_b.get_vision_range()
		_scan_vision_circle_for_intel(obs_b.global_position, vr_b, seen_enemy_units, seen_enemy_buildings)
	for node: Node in get_tree().get_nodes_in_group("sensor_relays"):
		if is_instance_valid(node) and node is Node2D and node.has_method("is_active") and bool(node.call("is_active")):
			var ctrl_t: int = int(node.get("controlling_team"))
			if ctrl_t >= 0 and _is_allied_team(ctrl_t):
				_scan_vision_circle_for_intel((node as Node2D).global_position, float(node.get("vision_radius")), seen_enemy_units, seen_enemy_buildings)

	var infantry_count: int = 0
	var vat_count: int = 0
	var now: float = _ai_elapsed

	for eu_var: Variant in seen_enemy_units.values():
		var eu: Unit = eu_var as Unit
		if eu.data == null:
			continue
		if eu.data.has_tag(&"artillery") or eu.data.has_tag(&"siege"):
			_scouted_intel["artillery_at"] = now
		elif eu.data.is_heavy_unit():
			_scouted_intel["heavy_armor_at"] = now
		elif eu.data.has_tag(&"swarm") or eu.data.has_tag(&"infantry") or eu.data.has_tag(&"flanker"):
			infantry_count += 1

	for eb_var: Variant in seen_enemy_buildings.values():
		var eb: Building = eb_var as Building
		if eb.is_military_production_building() and eb.get_tech_tier() >= 2:
			_scouted_intel["heavy_armor_at"] = now
			_scouted_intel["last_known_enemy_base"] = eb.global_position
		elif eb.is_military_production_building() and eb.get_tech_tier() == 1:
			vat_count += 1
			_scouted_intel["last_known_enemy_base"] = eb.global_position
		elif eb.is_command_hub():
			_scouted_intel["last_known_enemy_base"] = eb.global_position
		if eb.has_turret:
			_scouted_intel["turrets_at"] = now

	if vat_count >= 2 or infantry_count >= 6:
		_scouted_intel["infantry_swarm_at"] = now

	# Apply 90s intel decay TTL
	_scouted_intel["saw_heavy_armor"] = (now - float(_scouted_intel["heavy_armor_at"])) <= INTEL_TTL_SECONDS
	_scouted_intel["saw_infantry_swarm"] = (now - float(_scouted_intel["infantry_swarm_at"])) <= INTEL_TTL_SECONDS
	_scouted_intel["saw_artillery"] = (now - float(_scouted_intel["artillery_at"])) <= INTEL_TTL_SECONDS
	_scouted_intel["saw_turrets"] = (now - float(_scouted_intel["turrets_at"])) <= INTEL_TTL_SECONDS

	# Determine active counter posture (freshest / highest-priority spotted threat)
	var best_posture: StringName = &"NONE"
	var best_time: float = -1.0
	if bool(_scouted_intel["saw_heavy_armor"]):
		var t_ha: float = float(_scouted_intel["heavy_armor_at"]) + 6.0
		if t_ha > best_time:
			best_time = t_ha
			best_posture = &"ANTI_ARMOR"
	if bool(_scouted_intel["saw_artillery"]):
		var t_art: float = float(_scouted_intel["artillery_at"]) + 4.0
		if t_art > best_time:
			best_time = t_art
			best_posture = &"ANTI_SIEGE"
	if bool(_scouted_intel["saw_infantry_swarm"]):
		var t_sw: float = float(_scouted_intel["infantry_swarm_at"])
		if t_sw > best_time:
			best_time = t_sw
			best_posture = &"ANTI_SWARM"
	_active_counter_posture = best_posture


func _scan_vision_circle_for_intel(center: Vector2, radius: float, seen_units: Dictionary, seen_buildings: Dictionary) -> void:
	if SpatialGrid == null:
		return
	var r_sq: float = radius * radius
	for u: Unit in SpatialGrid.query_units_in_radius(center, radius):
		if not is_instance_valid(u) or u.is_dead or u.is_staffed:
			continue
		if not _is_enemy_team(int(u.team)):
			continue
		if center.distance_squared_to(u.global_position) <= r_sq and _is_entity_visible_to_ai(u):
			seen_units[u.get_instance_id()] = u
	for b: Building in SpatialGrid.query_buildings_in_radius(center, radius):
		if not is_instance_valid(b) or b.is_destroyed:
			continue
		if not _is_enemy_team(int(b.team)):
			continue
		var eff_r: float = radius + b.footprint_radius
		if center.distance_squared_to(b.global_position) <= eff_r * eff_r and _is_entity_visible_to_ai(b):
			seen_buildings[b.get_instance_id()] = b


func _get_counter_reaction_strength() -> float:
	if _is_relaxed_difficulty():
		return 0.35
	if _is_brutal_difficulty():
		return 1.0
	return 0.75


# =============================================================================
# PHASE C: BARRICADE DISCOVERY & SAFE SALVAGE CORE CONTESTING
# =============================================================================

func _find_nearby_intact_barricade(origin: Vector2, max_radius: float) -> Node2D:
	var best: Node2D = null
	var best_d_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if bool(node.get("is_destroyed")) or node.is_queued_for_deletion():
			continue
		var d_sq: float = origin.distance_squared_to((node as Node2D).global_position)
		if d_sq <= best_d_sq:
			best_d_sq = d_sq
			best = node as Node2D
	return best


func _count_nearby_intact_barricades(origin: Vector2, max_radius: float) -> int:
	var count: int = 0
	var max_r_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if bool(node.get("is_destroyed")) or node.is_queued_for_deletion():
			continue
		if origin.distance_squared_to((node as Node2D).global_position) <= max_r_sq:
			count += 1
	return count


func _squad_has_anti_armor_or_siege(squad: Array[Unit]) -> bool:
	for u: Unit in squad:
		if _planner.is_breach_capable(u):
			return true
	return false


func _collect_safe_salvage(core: Building) -> void:
	if core == null or not is_instance_valid(core) or not is_inside_tree():
		return

	var candidate_cores: Array[Node2D] = []
	var seen_ids: Dictionary = {}
	var search_anchors: Array[Dictionary] = [
		{"pos": core.global_position, "r": 950.0},
	]
	if _staging_point_valid:
		search_anchors.append({"pos": _staging_point, "r": 950.0})
	if not _wave_units.is_empty():
		var centroid: Vector2 = Vector2.ZERO
		var cnt: int = 0
		for wu: Unit in _wave_units:
			if is_instance_valid(wu) and not wu.is_dead:
				centroid += wu.global_position
				cnt += 1
		if cnt > 0:
			search_anchors.append({"pos": centroid / float(cnt), "r": 450.0})

	for anchor: Dictionary in search_anchors:
		var a_pos: Vector2 = anchor["pos"] as Vector2
		var a_r: float = float(anchor["r"])
		var found: Array = SpatialGrid.query_salvage_in_radius(a_pos, a_r) if SpatialGrid != null else get_tree().get_nodes_in_group("salvage_cores")
		for item: Variant in found:
			if not is_instance_valid(item) or not (item is Node2D):
				continue
			var sc: Node2D = item as Node2D
			if bool(sc.get("is_claimed")) or sc.is_queued_for_deletion():
				continue
			if sc.global_position.distance_squared_to(a_pos) > a_r * a_r:
				continue
			var sid: int = sc.get_instance_id()
			if not seen_ids.has(sid):
				seen_ids[sid] = true
				candidate_cores.append(sc)

	if candidate_cores.is_empty():
		return

	var target_core: Node2D = null
	var best_d_sq: float = INF
	for sc: Node2D in candidate_cores:
		if _is_salvage_already_claimed_by_ally(sc):
			continue
		if not _is_salvage_core_safe(sc):
			continue
		var d_sq: float = core.global_position.distance_squared_to(sc.global_position)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			target_core = sc

	if target_core == null:
		return

	# Pick 1 available fast specialist (engineer) or 1 worker (never pulling below 3 primary gatherers)
	var salvage_ids: Array[StringName] = _planner.get_salvage_unit_ids()
	var team_units: Array[Unit] = _get_team_units(ai_team)
	var primary_gatherers: int = 0
	var best_engineer: Unit = null
	var best_eng_d_sq: float = INF
	var best_worker: Unit = null
	var best_wrk_d_sq: float = INF

	for u: Unit in team_units:
		if u.data == null:
			continue
		var is_primary_worker: bool = u.data.can_gather and not u.data.auto_gather_on_spawn
		var is_specialist: bool = u.data.can_staff_compute or u.data.has_tag(&"engineer")
		if is_primary_worker and u.command_state == Unit.CommandState.GATHERING:
			primary_gatherers += 1
		if not u.can_salvage_core():
			continue
		if not salvage_ids.is_empty() and not salvage_ids.has(u.get_unit_type_id()):
			continue
		if u.command_state == Unit.CommandState.CONSTRUCTING or u.command_state == Unit.CommandState.SALVAGING or u.command_state == Unit.CommandState.STAFFING_BUILDING:
			continue
		if not u.command_queue.is_empty():
			continue
		var d_sq: float = u.global_position.distance_squared_to(target_core.global_position)
		if is_specialist and u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_eng_d_sq:
				best_eng_d_sq = d_sq
				best_engineer = u
		elif is_primary_worker:
			if u.command_state == Unit.CommandState.IDLE:
				if d_sq < best_wrk_d_sq:
					best_wrk_d_sq = d_sq
					best_worker = u
			elif u.command_state == Unit.CommandState.GATHERING:
				if u.gather_component != null and u.gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and u.is_carrying_cargo():
					continue
				if d_sq < best_wrk_d_sq:
					best_wrk_d_sq = d_sq
					best_worker = u

	if best_engineer != null:
		best_engineer.command_salvage(target_core)
		return
	if best_worker != null:
		if best_worker.command_state == Unit.CommandState.IDLE or primary_gatherers > 3:
			best_worker.command_salvage(target_core)


func _is_salvage_core_safe(sc: Node2D) -> bool:
	if SpatialGrid == null:
		return true
	var enemy_power: float = 0.0
	var ally_power: float = 0.0
	for u: Unit in SpatialGrid.query_units_in_radius(sc.global_position, 360.0):
		if not is_instance_valid(u) or u.is_dead or u.is_staffed:
			continue
		if not _is_combat_unit(u):
			continue
		var w: float = _get_unit_power_weight(u)
		if _is_enemy_team(int(u.team)):
			enemy_power += w
		elif _is_allied_team(int(u.team)):
			ally_power += w
	if enemy_power <= 0.01:
		return true
	return ally_power >= enemy_power * 1.15


func _is_salvage_already_claimed_by_ally(sc: Node2D) -> bool:
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node as Unit
		if u.is_dead or u.is_staffed or not _is_allied_team(int(u.team)):
			continue
		if u.command_state == Unit.CommandState.SALVAGING and u.active_command.get("target", null) == sc:
			return true
		for cmd: Dictionary in u.command_queue:
			if cmd.get("type", &"") == &"salvage" and cmd.get("target", null) == sc:
				return true
	return false


# =============================================================================
# WORKER / ECONOMY / REACTIVE PRODUCTION LOOP
# =============================================================================

func _assign_idle_workers(core: Building) -> void:
	var biomass_nodes: Array[ResourceNode] = _get_resources_near(core.global_position, &"biomass", 750.0)
	if biomass_nodes.is_empty():
		biomass_nodes = _get_resources_near(core.global_position, &"biomass", 3000.0)
	if biomass_nodes.is_empty():
		return

	var anchor_bio: ResourceNode = biomass_nodes[0]
	var anchor_d_sq: float = core.global_position.distance_squared_to(anchor_bio.global_position)
	for rn: ResourceNode in biomass_nodes:
		var d_sq: float = core.global_position.distance_squared_to(rn.global_position)
		if d_sq < anchor_d_sq:
			anchor_d_sq = d_sq
			anchor_bio = rn

	for unit: Unit in _get_team_units(ai_team):
		if unit.data == null or not unit.data.can_gather or unit.data.auto_gather_on_spawn:
			continue
		if unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo(core):
				continue
		var best_node: ResourceNode = ResourceNode.pick_best_cluster_node(anchor_bio, unit, int(ai_team), 520.0, 1200.0)
		if best_node == null:
			best_node = _pick_least_crowded_resource(unit.global_position, biomass_nodes)
		if best_node != null:
			best_node.assign_worker(unit)
			unit.command_gather(best_node)


func _assign_idle_harvesters() -> void:
	var silica_nodes: Array[ResourceNode] = []
	for b: Building in _get_team_buildings(ai_team):
		if b.is_constructed and not b.is_command_hub() and b.accepts_resource(&"silica"):
			for rn: ResourceNode in _get_resources_near(b.global_position, &"silica", 520.0):
				if not silica_nodes.has(rn):
					silica_nodes.append(rn)
	for unit: Unit in _get_team_units(ai_team):
		if unit.data == null or not unit.data.can_gather or not unit.data.auto_gather_on_spawn:
			continue
		if unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo():
				continue
		var anchor_vein: ResourceNode = silica_nodes[0] if not silica_nodes.is_empty() else _find_nearest_resource(unit.global_position, &"silica")
		var vein: ResourceNode = ResourceNode.pick_best_cluster_node(anchor_vein, unit, int(ai_team), 480.0, 1400.0) if anchor_vein != null else null
		if vein == null:
			vein = anchor_vein
		if vein != null:
			vein.assign_worker(unit)
			unit.command_gather(vein)


func _recover_stalled_combat_units() -> void:
	var live_ids: Dictionary = {}
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u):
			continue
		if u.is_movement_locked_by_deploy():
			continue
		var uid: int = u.get_instance_id()
		live_ids[uid] = true
		var is_traveling: bool = (
			u.command_state == Unit.CommandState.MOVING
			or (u.command_state == Unit.CommandState.ATTACK_MOVING and (u.current_target == null or not is_instance_valid(u.current_target)))
		)
		if not is_traveling:
			_unit_last_pos[uid] = u.global_position
			_unit_stall_ticks[uid] = 0
			continue
		if _unit_last_pos.has(uid):
			var prev_pos: Vector2 = _unit_last_pos[uid]
			if u.global_position.distance_to(prev_pos) < 18.0:
				var ticks: int = int(_unit_stall_ticks.get(uid, 0)) + 1
				_unit_stall_ticks[uid] = ticks
				if ticks >= 3:
					_unit_stall_ticks[uid] = 0
					var final_dest: Vector2 = _staging_point if (army_state == ArmyState.STAGING or army_state == ArmyState.RETREATING) else _current_attack_target
					if final_dest == Vector2.ZERO:
						final_dest = _select_wave_target(_wave_number, _find_ai_command_core())
					var to_dest: Vector2 = final_dest - u.global_position
					var dir: Vector2 = to_dest.normalized() if to_dest.length_squared() > 4.0 else Vector2.LEFT
					var side_sign: float = 1.0 if ((uid + _wave_number) % 2) == 0 else -1.0
					var detour: Vector2 = u.global_position + Vector2(-dir.y, dir.x) * (150.0 * side_sign) + dir * 75.0
					detour = Vector2(
						clampf(detour.x, arena_bounds.position.x + 80.0, arena_bounds.end.x - 80.0),
						clampf(detour.y, arena_bounds.position.y + 80.0, arena_bounds.end.y - 80.0)
					)
					u.command_move(detour, false)
					if army_state == ArmyState.ATTACKING:
						u.command_attack_move(final_dest, true)
					else:
						u.command_move(final_dest, true)
			else:
				_unit_stall_ticks[uid] = 0
		_unit_last_pos[uid] = u.global_position

	for k: Variant in _unit_last_pos.keys():
		if not live_ids.has(k):
			_unit_last_pos.erase(k)
			_unit_stall_ticks.erase(k)


func _assign_idle_engineers() -> void:
	var open_mainframes: Array[Building] = []
	for b: Building in _get_team_buildings(ai_team):
		if b.is_constructed and b.max_staff_slots > 0 and b.get_assigned_engineer_count() < b.max_staff_slots:
			open_mainframes.append(b)
	if open_mainframes.is_empty():
		return
	for unit: Unit in _get_team_units(ai_team):
		if not unit.can_staff_compute() or unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		for mf: Building in open_mainframes:
			if mf.can_accept_staff(unit):
				unit.command_staff_building(mf)
				break


func _resume_unfinished_buildings() -> void:
	for b: Building in _get_team_buildings(ai_team):
		if b.is_destroyed or b.is_constructed:
			continue
		if _has_worker_building(b):
			continue
		var worker: Unit = _find_available_worker(b.global_position)
		if worker != null:
			worker.command_construct_building(b)


func _manage_economy_and_production(econ: EconomyManager, core: Building) -> void:
	var buildings: Array[Building] = _get_team_buildings(ai_team)
	var units: Array[Unit] = _get_team_units(ai_team)

	var worker_count: int = 0
	var harvester_count: int = 0
	var engineer_count: int = 0
	for u: Unit in units:
		if u.data == null:
			continue
		if u.data.can_gather and not u.data.auto_gather_on_spawn:
			worker_count += 1
		elif u.data.can_gather and u.data.auto_gather_on_spawn:
			harvester_count += 1
		elif u.data.can_staff_compute:
			engineer_count += 1

	var refineries: Array[Building] = []
	var constructed_refineries: Array[Building] = []
	var constructed_refinery: Building = null
	var compute_hubs: Array[Building] = []
	var constructed_compute_hubs: Array[Building] = []
	var constructed_compute_hub: Building = null
	var barracks_list: Array[Building] = []
	var constructed_barracks: Array[Building] = []
	var foundries: Array[Building] = []
	var constructed_foundries: Array[Building] = []
	var heavy_plants: Array[Building] = []
	var constructed_heavy_plants: Array[Building] = []
	var unfinished_supply: int = 0
	var staffed_engineers: int = 0
	var total_compute_slots: int = 0

	for b: Building in buildings:
		if _planner.is_role_building(b, &"refinery"):
			refineries.append(b)
			if b.is_constructed:
				constructed_refineries.append(b)
				constructed_refinery = b
		elif _planner.is_role_building(b, &"compute_hub"):
			compute_hubs.append(b)
			if b.is_constructed:
				constructed_compute_hubs.append(b)
				constructed_compute_hub = b
				staffed_engineers += b.get_assigned_engineer_count()
				total_compute_slots += b.max_staff_slots
		elif _planner.is_role_building(b, &"barracks_t1"):
			barracks_list.append(b)
			if b.is_constructed:
				constructed_barracks.append(b)
		elif _planner.is_role_building(b, &"counter_foundry"):
			foundries.append(b)
			if b.is_constructed:
				constructed_foundries.append(b)
		elif _planner.is_role_building(b, &"heavy_t2"):
			heavy_plants.append(b)
			if b.is_constructed:
				constructed_heavy_plants.append(b)
		elif _planner.is_role_building(b, &"supply") and not b.is_constructed:
			unfinished_supply += 1

	var queued_workers: int = _count_queued_unit_type(buildings, _worker_data.unit_type_id) if _worker_data != null else 0
	var queued_harvesters: int = _count_queued_unit_type(buildings, _harvester_data.unit_type_id) if _harvester_data != null else 0
	var queued_engineers: int = _count_queued_unit_type(buildings, _engineer_data.unit_type_id) if _engineer_data != null else 0
	var total_workers: int = worker_count + queued_workers
	var total_harvesters: int = harvester_count + queued_harvesters
	var total_engineers: int = engineer_count + staffed_engineers + queued_engineers

	var bw_used: int = econ.get_bandwidth_used(ai_team)
	var bw_cap: int = econ.get_bandwidth_cap(ai_team)
	var needs_supply: bool = (bw_used >= bw_cap - 4) and unfinished_supply == 0 and bw_cap < max_bandwidth_cap
	var biomass: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_BIOMASS)
	var silica: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_SILICA)
	var compute: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_COMPUTE)

	var is_swarm_rush: bool = (_ai_playstyle == int(GameConfig.AIPlaystyle.SWARM_RUSH)) if GameConfig != null else false
	var is_synth_tech: bool = (_ai_playstyle == int(GameConfig.AIPlaystyle.SYNTHETICS_TECH)) if GameConfig != null else false
	var is_brutal: bool = _is_brutal_difficulty()
	var counter_strength: float = _get_counter_reaction_strength()
	var rally_pt: Vector2 = _staging_point if _staging_point_valid else core.global_position.lerp(Vector2.ZERO, 0.34)

	# Priority 1: Ensure baseline worker core (3 early on Swarm Rush, 4 baseline).
	var early_workers: int = 3 if is_swarm_rush else 4
	if total_workers < early_workers:
		if _worker_data != null and core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)
		return

	# Swarm Rush builds its first Tier-1 Barracks before the Refinery for rapid early pressure.
	if is_swarm_rush and barracks_list.is_empty() and _barracks_t1_data != null:
		if econ.can_afford(ai_team, _barracks_t1_data.get_cost_dict()):
			var to_c_rush: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var rush_b: Building = _try_place_and_build(_barracks_t1_data, core.global_position + to_c_rush * 175.0, core.global_position)
			if rush_b != null:
				rush_b.set_rally_position(rally_pt)
			return
		if biomass < _barracks_t1_data.biomass_cost:
			return

	# Priority 2: Build Silica Refinery near nearest Silica Vein.
	if refineries.is_empty() and _refinery_data != null:
		if econ.can_afford(ai_team, _refinery_data.get_cost_dict()):
			var vein: ResourceNode = _find_nearest_resource(core.global_position, &"silica")
			var anchor: Vector2 = core.global_position.lerp(vein.global_position, 0.58) if vein != null else (core.global_position + Vector2(-120.0, 180.0))
			_try_place_and_build(_refinery_data, anchor, core.global_position)
		return

	# Priority 3: Expand Bandwidth cap via Supply Provider before hitting population block.
	if needs_supply and _supply_data != null:
		if econ.can_afford(ai_team, _supply_data.get_cost_dict()):
			var away_dir: Vector2 = (core.global_position - Vector2.ZERO).normalized()
			var supply_anchor: Vector2 = core.global_position + away_dir * 125.0
			_try_place_and_build(_supply_data, supply_anchor, core.global_position)
		return

	# Priority 4: Train automated Harvesters once Refineries are online (respects faction per-vein saturation bonuses).
	var per_vein_cap: int = 2
	if constructed_refinery != null:
		var near_vein: ResourceNode = _find_nearest_resource(constructed_refinery.global_position, &"silica")
		if near_vein != null:
			per_vein_cap = maxi(2, near_vein.get_effective_max_harvesters(int(ai_team)))
	var desired_harvesters: int = 1
	if constructed_refineries.size() >= 2:
		desired_harvesters = mini(6, per_vein_cap * 2) if is_brutal else mini(5, per_vein_cap + 1)
	elif is_brutal:
		desired_harvesters = maxi(3, per_vein_cap)
	elif constructed_barracks.size() >= 1:
		desired_harvesters = per_vein_cap
	if _harvester_data != null and constructed_refinery != null and total_harvesters < desired_harvesters:
		var trainer: Building = constructed_refinery if constructed_refinery.can_train_unit_data(_harvester_data) else core
		if trainer.get_training_queue_size() < 2 and trainer.can_train_unit_data(_harvester_data):
			trainer.queue_unit_data(_harvester_data)
			return

	# Priority 5: Construct primary Tier-1 Barracks facing the map center.
	if barracks_list.is_empty() and _barracks_t1_data != null:
		if econ.can_afford(ai_team, _barracks_t1_data.get_cost_dict()):
			var to_center: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var vat_anchor: Vector2 = core.global_position + to_center * 175.0
			var built_vat: Building = _try_place_and_build(_barracks_t1_data, vat_anchor, core.global_position)
			if built_vat != null:
				built_vat.set_rally_position(rally_pt)
			return
		if biomass < _barracks_t1_data.biomass_cost:
			return

	# Priority 6: Saturate workers up to target_worker_count.
	if _worker_data != null and total_workers < target_worker_count:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)

	# Priority 7: Compute Hubs on natural & contested expansion Compute Vents + Engineers.
	var exp_vent_biomass: int = 160 if (is_synth_tech or is_brutal) else 220
	if (not constructed_barracks.is_empty() or is_synth_tech) and _compute_hub_data != null:
		if compute_hubs.is_empty():
			var vent: ResourceNode = _find_nearest_unoccupied_vent(core.global_position, 580.0)
			if vent != null and econ.can_afford(ai_team, _compute_hub_data.get_cost_dict()):
				_try_place_and_build_on_vent(_compute_hub_data, vent)
		elif compute_hubs.size() == 1 and constructed_compute_hubs.size() >= 1 and staffed_engineers >= 1 and biomass >= exp_vent_biomass:
			var exp_vent: ResourceNode = _find_nearest_unoccupied_vent(core.global_position, 1650.0)
			if exp_vent != null and econ.can_afford(ai_team, _compute_hub_data.get_cost_dict()):
				_try_place_and_build_on_vent(_compute_hub_data, exp_vent)

	var desired_engineers: int = mini(6, total_compute_slots)
	if constructed_compute_hub != null and _engineer_data != null and total_engineers < desired_engineers:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_engineer_data):
			core.queue_unit_data(_engineer_data)

	# Priority 7.5: Expand Silica economy to expansion cluster once Tier-1 is established.
	var exp_cond_biomass: int = 180 if is_brutal else 240
	if refineries.size() < 2 and not constructed_refineries.is_empty() and not constructed_barracks.is_empty() and biomass >= exp_cond_biomass and _refinery_data != null:
		if econ.can_afford(ai_team, _refinery_data.get_cost_dict()):
			var exp_vein: ResourceNode = _find_expansion_silica_vein(core.global_position, refineries)
			if exp_vein != null:
				var exp_anchor: Vector2 = exp_vein.global_position.lerp(core.global_position, 0.16)
				_try_place_and_build(_refinery_data, exp_anchor, exp_vein.global_position)

	# Priority 8: Mid-game Upgrades at Tier-1 Production (faction-driven upgrade order).
	if not constructed_barracks.is_empty():
		var primary_barracks: Building = constructed_barracks[0]
		if primary_barracks.production_component != null and primary_barracks.get_training_queue_size() < 2:
			var next_t1_upg: UpgradeData = _planner.choose_next_upgrade_for_building(primary_barracks)
			if next_t1_upg != null:
				primary_barracks.production_component.enqueue_upgrade(primary_barracks, next_t1_upg)

	# Reactive Counter Foundry priority when ANTI_ARMOR intel is active.
	var urgent_anti_armor_foundry: bool = (_active_counter_posture == &"ANTI_ARMOR" and counter_strength >= 0.70)
	if urgent_anti_armor_foundry and foundries.is_empty() and constructed_compute_hub != null and _counter_foundry_data != null and silica >= _counter_foundry_data.silica_cost:
		if econ.can_afford(ai_team, _counter_foundry_data.get_cost_dict()):
			var to_c_aa: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_aa: Vector2 = Vector2(-to_c_aa.y, to_c_aa.x)
			var built_aa: Building = _try_place_and_build(_counter_foundry_data, core.global_position + to_c_aa * 160.0 + perp_aa * 145.0, core.global_position)
			if built_aa != null:
				built_aa.set_rally_position(rally_pt)

	# Priority 9: Late-game Tier-2 Heavy Production.
	if heavy_plants.is_empty() and _heavy_t2_data != null and _planner.are_prerequisites_met(_heavy_t2_data, econ, int(ai_team)) and compute >= _heavy_t2_data.compute_cost:
		if econ.can_afford(ai_team, _heavy_t2_data.get_cost_dict()):
			var to_center_f: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_f: Vector2 = Vector2(-to_center_f.y, to_center_f.x)
			var fab_anchor: Vector2 = core.global_position + to_center_f * 165.0 - perp_f * 145.0
			var built_fab: Building = _try_place_and_build(_heavy_t2_data, fab_anchor, core.global_position)
			if built_fab != null:
				built_fab.set_rally_position(rally_pt)

	# Priority 10: Mid-game Counter Foundry for specialized counter tech (and Tier-2 prerequisites like Ballistics Lab -> Siege Gantry).
	var t2_needs_foundry: bool = (
		_heavy_t2_data != null
		and _counter_foundry_data != null
		and _heavy_t2_data.get_prerequisite_ids().has(_counter_foundry_data.building_id)
	)
	var allow_foundry: bool = (not is_synth_tech or not heavy_plants.is_empty() or urgent_anti_armor_foundry or t2_needs_foundry)
	if allow_foundry and foundries.is_empty() and constructed_compute_hub != null and _counter_foundry_data != null and silica >= _counter_foundry_data.silica_cost:
		if econ.can_afford(ai_team, _counter_foundry_data.get_cost_dict()):
			var to_center_cf: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_cf: Vector2 = Vector2(-to_center_cf.y, to_center_cf.x)
			var cf_anchor: Vector2 = core.global_position + to_center_cf * 160.0 + perp_cf * 145.0
			var built_cf: Building = _try_place_and_build(_counter_foundry_data, cf_anchor, core.global_position)
			if built_cf != null:
				built_cf.set_rally_position(rally_pt)

	# Priority 11: Tier-2 Heavy Production mix (faction-weighted + reactive intel).
	for heavy_b: Building in constructed_heavy_plants:
		if not heavy_b.has_rally():
			heavy_b.set_rally_position(rally_pt)
		if heavy_b.get_training_queue_size() >= 2:
			continue
		var t2_upg: UpgradeData = _planner.choose_next_upgrade_for_building(heavy_b)
		if t2_upg != null and heavy_b.production_component != null:
			heavy_b.production_component.enqueue_upgrade(heavy_b, t2_upg)
			continue
		var heavy_choice: UnitData = _planner.choose_unit_for_building(heavy_b, _ai_playstyle, _active_counter_posture, counter_strength, _fab_production_counter)
		if heavy_choice != null and heavy_b.can_train_unit_data(heavy_choice):
			heavy_b.queue_unit_data(heavy_choice)
			_fab_production_counter += 1

	# Priority 12: Counter Foundry production & tech upgrades (biased by intel & playstyle).
	for foundry: Building in constructed_foundries:
		if not foundry.has_rally():
			foundry.set_rally_position(rally_pt)
		if foundry.get_training_queue_size() >= 2:
			continue
		var foundry_upg: UpgradeData = _planner.choose_next_upgrade_for_building(foundry)
		if foundry_upg != null and foundry.production_component != null:
			foundry.production_component.enqueue_upgrade(foundry, foundry_upg)
			continue
		var foundry_choice: UnitData = _planner.choose_unit_for_building(foundry, _ai_playstyle, _active_counter_posture, counter_strength, _foundry_production_counter)
		if foundry_choice != null and foundry.can_train_unit_data(foundry_choice):
			foundry.queue_unit_data(foundry_choice)
			_foundry_production_counter += 1

	# Priority 13: Tier-1 core army production (weighted by playstyle + reactive intel).
	var hold_for_t2: bool = is_synth_tech and heavy_plants.is_empty() and constructed_compute_hub != null and compute >= 15
	if not hold_for_t2:
		for bar: Building in constructed_barracks:
			if not bar.has_rally():
				bar.set_rally_position(rally_pt)
			if bar.get_training_queue_size() >= 2:
				continue
			var chosen: UnitData = _planner.choose_unit_for_building(bar, _ai_playstyle, _active_counter_posture, counter_strength, _vat_production_counter)
			if chosen != null and bar.can_train_unit_data(chosen):
				bar.queue_unit_data(chosen)
				_vat_production_counter += 1

	# Priority 14: Additional Tier-1 Barracks when floating surplus Biomass.
	var extra_vat_biomass: int = 200 if is_swarm_rush else (230 if is_brutal else 280)
	var extra_vat_silica: int = 40 if is_swarm_rush else 60
	if _barracks_t1_data != null and barracks_list.size() < max_cloning_vats and biomass >= extra_vat_biomass and silica >= extra_vat_silica:
		if econ.can_afford(ai_team, _barracks_t1_data.get_cost_dict()):
			var to_center2: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp: Vector2 = Vector2(-to_center2.y, to_center2.x)
			var vat_anchor2: Vector2 = core.global_position + to_center2 * 180.0 + perp * 130.0
			var second_vat: Building = _try_place_and_build(_barracks_t1_data, vat_anchor2, core.global_position)
			if second_vat != null:
				second_vat.set_rally_position(rally_pt)


func _trigger_combat_abilities() -> void:
	for u: Unit in _get_team_units(ai_team):
		if u.data == null or u.data.abilities.is_empty() or u.current_target == null or not is_instance_valid(u.current_target):
			continue
		var dist: float = u.global_position.distance_to(u.current_target.global_position)
		for ab: AbilityData in u.data.abilities:
			if ab == null or ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
				continue
			# Allied-target AOE abilities (e.g., Shield Overcharge) are handled by AbilityComponent autocast.
			if ab.ability_id == &"monolith_shield_overcharge":
				continue
			if not u.is_ability_ready(ab):
				continue
			if ab.ability_id == &"kinetic_barrier":
				var low_shd: bool = u.max_shield > 0.0 and u.current_shield <= u.max_shield * 0.25
				var low_hp: bool = u.current_hp < u.get_max_hp() * 0.80
				if (low_shd or low_hp) and dist <= u.get_effective_attack_range() + 80.0:
					u.command_cast_ability(ab, u.global_position, u)
					break
				continue
			if ab.ability_id == &"grav_pulse":
				if dist <= ab.cast_range:
					var cluster_cnt: int = _count_hostile_combat_near(u.current_target.global_position, maxf(60.0, ab.aoe_radius))
					if cluster_cnt >= 2:
						u.command_cast_ability(ab, u.current_target.global_position)
						break
				continue
			if ab.target_type == AbilityData.TargetType.INSTANT:
				if ab.aoe_radius > 0.0:
					if dist <= maxf(80.0, ab.aoe_radius * 0.92):
						u.command_cast_ability(ab, u.global_position, u)
						break
				elif dist <= u.get_effective_attack_range() + 45.0:
					u.command_cast_ability(ab, u.global_position, u)
					break
			elif ab.target_type == AbilityData.TargetType.POINT_AOE:
				if dist <= ab.cast_range and dist >= 100.0:
					u.command_cast_ability(ab, u.current_target.global_position)
					break
			elif ab.target_type == AbilityData.TargetType.UNIT_TARGET:
				if dist <= ab.cast_range and u.current_target is Unit:
					u.command_cast_ability(ab, u.current_target.global_position, u.current_target as Unit)
					break


func _count_hostile_combat_near(center: Vector2, radius: float) -> int:
	var cnt: int = 0
	var list: Array = SpatialGrid.query_units_in_radius(center, radius) if SpatialGrid != null else get_tree().get_nodes_in_group("units")
	var r_sq: float = radius * radius
	for node: Variant in list:
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var e: Unit = node as Unit
		if e.is_dead or e.is_staffed or not _is_enemy_team(int(e.team)):
			continue
		if e.data != null and (e.data.can_gather or e.data.can_staff_compute):
			continue
		if e.global_position.distance_squared_to(center) <= r_sq:
			cnt += 1
	return cnt


func _manage_overclock_macro() -> void:
	# Faction-agnostic Core Overclock macro: any hub with can_cast_overclock() boosts the highest-priority active producer.
	var ai_buildings: Array[Building] = _get_team_buildings(ai_team)
	var ready_hubs: Array[Building] = []
	for b: Building in ai_buildings:
		if b.is_constructed and not b.is_destroyed and b.can_cast_overclock():
			ready_hubs.append(b)
	if ready_hubs.is_empty():
		return

	for hub: Building in ready_hubs:
		var best_target: Building = null
		var best_score: float = -1.0
		for cand: Building in ai_buildings:
			if not cand.is_constructed or cand.is_destroyed or cand.is_overclocked():
				continue
			if cand.production_component == null or cand.get_training_queue_size() <= 0:
				continue
			var score: float = 0.0
			if _planner.is_role_building(cand, &"heavy_t2") or (cand.is_military_production_building() and cand.get_tech_tier() >= 2):
				score = 400.0
			elif _planner.is_role_building(cand, &"counter_foundry"):
				score = 300.0
			elif _planner.is_role_building(cand, &"barracks_t1") or cand.is_military_production_building():
				score = 200.0
			elif cand.is_command_hub():
				score = 100.0
			else:
				score = 150.0
			var active_st: Dictionary = cand.get_active_training_status()
			if active_st.get("kind", ProductionComponent.KIND_UNIT) == ProductionComponent.KIND_UPGRADE:
				score += 65.0
			score += float(cand.get_training_queue_size()) * 12.0
			if score > best_score:
				best_score = score
				best_target = cand
		if best_target != null:
			hub.cast_overclock_on(best_target)


func _manage_deploy_micro(tick_dt: float) -> void:
	# Faction-agnostic Deploy/Anchor micro (e.g. Anvil Siege-Walker) using real vision only — zero map-hacking.
	var deployers: Array[Unit] = []
	for u: Unit in _get_team_units(ai_team):
		if u.can_toggle_deploy() and u.data != null:
			deployers.append(u)
	if deployers.is_empty():
		_deploy_idle_timers.clear()
		return

	# Collect real vision observers (allied units, buildings, active sensor relays)
	var seen_enemy_units: Dictionary = {}
	var seen_enemy_buildings: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var ally_u: Unit = node as Unit
			if not ally_u.is_dead and not ally_u.is_staffed and _is_allied_team(int(ally_u.team)):
				var vr: float = ally_u.data.vision_range if ally_u.data != null else 320.0
				_scan_vision_circle_for_intel(ally_u.global_position, vr, seen_enemy_units, seen_enemy_buildings)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var ally_b: Building = node as Building
			if not ally_b.is_destroyed and _is_allied_team(int(ally_b.team)):
				_scan_vision_circle_for_intel(ally_b.global_position, ally_b.get_vision_range(), seen_enemy_units, seen_enemy_buildings)
	for node: Node in get_tree().get_nodes_in_group("sensor_relays"):
		if is_instance_valid(node) and node is Node2D and node.has_method("is_active") and bool(node.call("is_active")):
			var ctrl_t: int = int(node.get("controlling_team"))
			if ctrl_t >= 0 and _is_allied_team(ctrl_t):
				_scan_vision_circle_for_intel((node as Node2D).global_position, float(node.get("vision_radius")), seen_enemy_units, seen_enemy_buildings)

	var econ: EconomyManager = _get_economy_manager()
	var rail_bonus: float = econ.get_rail_range_bonus(int(ai_team)) if econ != null else 0.0
	var live_dep_ids: Dictionary = {}

	for u: Unit in deployers:
		var uid: int = u.get_instance_id()
		live_dep_ids[uid] = true
		if u.is_deploy_transitioning():
			continue

		var dep_max_r: float = u.data.deployed_attack_range + (rail_bonus if u.data.unit_type_id == &"anvil_siege_walker" else 0.0)
		var dep_min_r: float = u.data.deployed_min_attack_range
		if dep_max_r <= 0.0:
			continue
		var my_r: float = u.data.collision_radius

		var has_close_threat: bool = false
		var has_deploy_target: bool = false
		var has_keep_target: bool = false
		var engage_max: float = dep_max_r * 0.92
		var keep_max: float = dep_max_r * 1.05

		for eu_var: Variant in seen_enemy_units.values():
			var eu: Unit = eu_var as Unit
			if not is_instance_valid(eu) or eu.is_dead or eu.is_staffed:
				continue
			var other_r: float = eu.data.collision_radius if eu.data != null else 16.0
			var edge_d: float = maxf(0.0, u.global_position.distance_to(eu.global_position) - my_r - other_r)
			if dep_min_r > 0.0 and edge_d < dep_min_r + 12.0:
				if eu.data == null or eu.data.attack_damage > 0.0:
					has_close_threat = true
			elif edge_d <= engage_max and edge_d >= dep_min_r + 8.0:
				has_deploy_target = true
				has_keep_target = true
			elif edge_d <= keep_max and edge_d >= dep_min_r:
				has_keep_target = true

		if not has_deploy_target or not has_keep_target:
			for eb_var: Variant in seen_enemy_buildings.values():
				var eb: Building = eb_var as Building
				if not is_instance_valid(eb) or eb.is_destroyed:
					continue
				var edge_db: float = maxf(0.0, u.global_position.distance_to(eb.global_position) - my_r - eb.footprint_radius)
				if edge_db <= engage_max and edge_db >= dep_min_r + 8.0:
					has_deploy_target = true
					has_keep_target = true
				elif edge_db <= keep_max and edge_db >= dep_min_r:
					has_keep_target = true

		if army_state == ArmyState.BREACHING and _breach_target != null and is_instance_valid(_breach_target) and not bool(_breach_target.get("is_destroyed")):
			var bar_r: float = float(_breach_target.call("get_footprint_radius")) if _breach_target.has_method("get_footprint_radius") else 40.0
			var edge_bar: float = maxf(0.0, u.global_position.distance_to(_breach_target.global_position) - my_r - bar_r)
			if edge_bar <= engage_max and edge_bar >= dep_min_r + 8.0:
				has_deploy_target = true
				has_keep_target = true
			elif edge_bar <= keep_max and edge_bar >= dep_min_r:
				has_keep_target = true

		if u.is_deployed():
			if army_state == ArmyState.RETREATING or has_close_threat:
				_deploy_idle_timers[uid] = 0.0
				u.request_undeploy()
			elif has_keep_target:
				_deploy_idle_timers[uid] = 0.0
			else:
				var idle_t: float = float(_deploy_idle_timers.get(uid, 0.0)) + tick_dt
				_deploy_idle_timers[uid] = idle_t
				if idle_t >= 2.5:
					_deploy_idle_timers[uid] = 0.0
					u.request_undeploy()
		else:
			_deploy_idle_timers[uid] = 0.0
			var combat_posture: bool = (
				army_state == ArmyState.ATTACKING
				or army_state == ArmyState.DEFENDING
				or army_state == ArmyState.BREACHING
			)
			if combat_posture and has_deploy_target and not has_close_threat:
				u.request_deploy()

	for key: Variant in _deploy_idle_timers.keys():
		if not live_dep_ids.has(key):
			_deploy_idle_timers.erase(key)


# =============================================================================
# PHASE D: FFA & MULTI-TEAM TARGET SCORING + DEBUG READOUT
# =============================================================================

func _select_wave_target(wave_idx: int, core: Building = null) -> Vector2:
	var origin: Vector2 = core.global_position if (core != null and is_instance_valid(core)) else (_staging_point if _staging_point_valid else Vector2.ZERO)

	# 1. Urgent Data Hyper-Uplink denial when Uplink Victory is active or an enemy holds/captures it
	var mm: Node = get_tree().get_first_node_in_group("match_manager")
	if mm != null and mm.has_method("get_uplink_victory_status"):
		var vst: Dictionary = mm.call("get_uplink_victory_status") as Dictionary
		if bool(vst.get("enabled", false)) and bool(vst.get("has_uplink", false)):
			var ctrl_t: int = int(vst.get("controlling_team", -1))
			var lead_t: int = int(vst.get("leading_team", -1))
			var lead_s: float = float(vst.get("leading_seconds", 0.0))
			var target_s: float = maxf(1.0, float(vst.get("target_seconds", 180.0)))
			var enemy_holds_now: bool = ctrl_t >= 0 and _is_enemy_team(ctrl_t)
			var enemy_timer_urgent: bool = lead_t >= 0 and _is_enemy_team(lead_t) and lead_s >= target_s * 0.40
			if enemy_holds_now or enemy_timer_urgent:
				return vst.get("uplink_pos", Vector2.ZERO) as Vector2

	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if uplink != null and is_instance_valid(uplink):
		var enemy_controls_uplink: bool = uplink.controlling_team >= 0 and _is_enemy_team(uplink.controlling_team)
		var enemy_capturing_uplink: bool = uplink.capturing_team >= 0 and _is_enemy_team(uplink.capturing_team) and uplink.capture_progress > 0.35
		var allied_controls_uplink: bool = uplink.controlling_team >= 0 and _is_allied_team(uplink.controlling_team)
		if enemy_controls_uplink or enemy_capturing_uplink:
			return uplink.global_position
		if (wave_idx % 2) == 1 and not allied_controls_uplink:
			return uplink.global_position

	# 2. Score opposing bases in 1v1 / 2v2 / 3P / 4P FFA: favor nearest active enemy core (never allies)
	var best_core: Building = null
	var best_core_score: float = INF
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node as Building
		if b.is_destroyed or not _is_enemy_team(int(b.team)):
			continue
		if not b.is_command_hub():
			continue
		var score: float = origin.distance_to(b.global_position)
		# Prioritize an enemy who currently holds or is capturing the Uplink
		if uplink != null and (uplink.controlling_team == int(b.team) or (uplink.capturing_team == int(b.team) and uplink.capture_progress > 0.40)):
			score -= 480.0
		if score < best_core_score:
			best_core_score = score
			best_core = b
	if best_core != null:
		return best_core.global_position

	# 3. Nearest remaining enemy building
	var nearest_b: Building = null
	var nearest_b_d_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node as Building
			if not b.is_destroyed and _is_enemy_team(int(b.team)):
				var d_sq: float = origin.distance_squared_to(b.global_position)
				if d_sq < nearest_b_d_sq:
					nearest_b_d_sq = d_sq
					nearest_b = b
	if nearest_b != null:
		return nearest_b.global_position

	# 4. Nearest remaining enemy unit
	var nearest_u: Unit = null
	var nearest_u_d_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node as Unit
			if not u.is_dead and not u.is_staffed and _is_enemy_team(int(u.team)):
				var d_sq: float = origin.distance_squared_to(u.global_position)
				if d_sq < nearest_u_d_sq:
					nearest_u_d_sq = d_sq
					nearest_u = u
	if nearest_u != null:
		return nearest_u.global_position

	return Vector2.ZERO


func get_debug_status_line() -> String:
	var tag: String = TeamManager.get_team_short_label(int(ai_team), false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("T%d" % (int(ai_team) + 1))
	var state_str: String = "STAGING"
	match army_state:
		ArmyState.ATTACKING:
			state_str = "ATTACKING"
		ArmyState.DEFENDING:
			state_str = "DEFENDING"
		ArmyState.RETREATING:
			state_str = "RETREATING"
		ArmyState.BREACHING:
			state_str = "BREACHING"
	var count_str: String = ""
	if army_state == ArmyState.STAGING:
		count_str = " (%d/%d)" % [_last_staging_count, _get_target_wave_size()]
	elif army_state == ArmyState.ATTACKING or army_state == ArmyState.RETREATING or army_state == ArmyState.BREACHING:
		var pct: int = int(round(_get_wave_strength_ratio() * 100.0))
		count_str = " (%d | %d%%)" % [_wave_units.size(), pct]
	var core: Building = _find_ai_command_core()
	var barr_count: int = _count_nearby_intact_barricades(core.global_position, 1400.0) if core != null else 0
	var barr_part: String = (" | BARR: %d" % barr_count) if barr_count > 0 else ""
	return "AI [%s]: %s%s | INTEL: %s%s" % [tag, state_str, count_str, String(_active_counter_posture), barr_part]


# =============================================================================
# BUILDING PLACEMENT & HELPERS
# =============================================================================

func _try_place_and_build(data: BuildingData, preferred_pos: Vector2, fallback_origin: Vector2) -> Building:
	var econ: EconomyManager = _get_economy_manager()
	if econ == null or data == null or data.resolve_scene() == null:
		return null
	if not _planner.are_prerequisites_met(data, econ, int(ai_team)):
		return null
	if not econ.can_afford(ai_team, data.get_cost_dict()):
		return null

	var worker: Unit = _find_available_worker(preferred_pos)
	if worker == null:
		return null

	var spot: Vector2 = _find_valid_build_position(data, preferred_pos, fallback_origin)
	if spot == Vector2.INF:
		if data.requires_power_grid and _planner != null:
			var power_data: BuildingData = _planner.get_power_provider_building()
			if power_data != null and power_data != data and econ.can_afford(ai_team, power_data.get_cost_dict()):
				var p_spot: Vector2 = _find_valid_build_position(power_data, preferred_pos, fallback_origin)
				if p_spot != Vector2.INF and econ.spend_resources(ai_team, power_data.get_cost_dict()):
					return _instantiate_ai_building(power_data, p_spot, worker, null)
		return null

	if not econ.spend_resources(ai_team, data.get_cost_dict()):
		return null

	return _instantiate_ai_building(data, spot, worker, null)


func _try_place_and_build_on_vent(data: BuildingData, vent: ResourceNode) -> Building:
	var econ: EconomyManager = _get_economy_manager()
	if econ == null or data == null or data.resolve_scene() == null or vent == null or not is_instance_valid(vent) or vent.is_occupied():
		return null
	if not econ.can_afford(ai_team, data.get_cost_dict()):
		return null
	var worker: Unit = _find_available_worker(vent.global_position)
	if worker == null:
		return null
	if not econ.spend_resources(ai_team, data.get_cost_dict()):
		return null
	return _instantiate_ai_building(data, vent.global_position, worker, vent)


func _instantiate_ai_building(data: BuildingData, spot: Vector2, worker: Unit, vent: ResourceNode) -> Building:
	var scene_root: Node = get_tree().current_scene
	var buildings_container: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if buildings_container == null:
		buildings_container = get_parent()
	if buildings_container == null:
		return null

	var building_scene: PackedScene = data.resolve_scene()
	if building_scene == null:
		return null
	var instance: Node = building_scene.instantiate()
	if not (instance is Building):
		instance.queue_free()
		return null

	var new_building: Building = instance
	new_building.global_position = spot
	new_building.is_constructed = false
	buildings_container.add_child(new_building)
	new_building.begin_construction(data, ai_team, vent)
	if not new_building.construction_completed.is_connected(_on_ai_building_completed):
		new_building.construction_completed.connect(_on_ai_building_completed)
	_nudge_units_out_of_building(new_building)

	worker.command_construct_building(new_building)
	return new_building


func _on_ai_building_completed(building: Building) -> void:
	if building == null or not is_instance_valid(building) or building.is_destroyed:
		return
	if not building.destroyed.is_connected(_on_ai_building_destroyed_radio):
		building.destroyed.connect(_on_ai_building_destroyed_radio)
	if building.is_command_hub():
		_compute_staging_point(building)
		_sync_military_rallies()
	elif _is_military_production_building(building) and _staging_point_valid:
		building.set_rally_position(_staging_point)
	var is_heavy_t2: bool = (_heavy_t2_data != null and building.building_type_id == _heavy_t2_data.building_id) or building.building_type_id == &"synthetics_fabricator" or building.building_type_id == &"siege_gantry"
	if not _tier2_transmission_sent and is_heavy_t2:
		_tier2_transmission_sent = true
		_try_emit_ai_transmission(&"tier2_online", Vector2.INF)


func _on_ai_building_destroyed_radio(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	_try_emit_ai_transmission(&"under_attack", _sanitize_transmission_pos(building.global_position, false))


func _sanitize_transmission_pos(world_pos: Vector2, is_neutral_objective: bool) -> Vector2:
	if is_neutral_objective:
		return world_pos
	if not is_inside_tree():
		return Vector2.INF
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog == null or not fog.fog_enabled or fog.is_world_pos_explored(world_pos):
		return world_pos
	return Vector2.INF


func _try_emit_ai_transmission(category: StringName, safe_world_pos: Vector2 = Vector2.INF) -> void:
	if not is_inside_tree() or not enabled:
		return
	if SettingsManager != null and not SettingsManager.show_ai_transmissions:
		return
	var now_ms: int = Time.get_ticks_msec()
	if (now_ms - _last_transmission_ms) < TRANSMISSION_GLOBAL_COOLDOWN_MS:
		return
	var last_cat_ms: int = int(_last_transmission_by_cat.get(category, -999999))
	if (now_ms - last_cat_ms) < TRANSMISSION_CATEGORY_COOLDOWN_MS:
		return

	var line: String = ""
	var fdata: FactionData = TeamManager.get_team_faction_data(int(ai_team)) if (TeamManager != null and TeamManager.has_method("get_team_faction_data")) else null
	if fdata != null:
		line = fdata.get_ai_transmission(category)
	if line.is_empty():
		line = String(DEFAULT_AI_TRANSMISSIONS.get(category, ""))
	if line.is_empty():
		return

	_last_transmission_ms = now_ms
	_last_transmission_by_cat[category] = now_ms
	var mm: Node = get_tree().get_first_node_in_group("match_manager")
	if mm != null and mm.has_method("emit_tactical_event"):
		var team_col: Color = TeamManager.get_team_color(int(ai_team)) if TeamManager != null else Color(1.0, 0.56, 0.36, 1.0)
		mm.call("emit_tactical_event", &"transmission", line, safe_world_pos, team_col)
	if AudioManager != null:
		AudioManager.play_sfx(&"ai_transmission", -8.0, 0.03)


func _find_valid_build_position(data: BuildingData, preferred_pos: Vector2, fallback_origin: Vector2) -> Vector2:
	if data != null and data.requires_power_grid and is_inside_tree():
		var footprint_r: float = data.get_footprint_radius()
		var providers: Array[Building] = []
		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if not (node is Building) or not is_instance_valid(node):
				continue
			var b: Building = node as Building
			if b.is_destroyed or not b.is_constructed or b.is_salvaging or int(b.team) != int(ai_team):
				continue
			if b.provides_power_grid and b.power_radius > footprint_r + 24.0:
				providers.append(b)
		if providers.is_empty():
			return Vector2.INF
		providers.sort_custom(func(a: Building, b: Building) -> bool:
			return a.global_position.distance_squared_to(preferred_pos) < b.global_position.distance_squared_to(preferred_pos)
		)
		var p_steps: int = 12
		for prov: Building in providers:
			var max_r: float = maxf(prov.footprint_radius + footprint_r + 18.0, prov.power_radius - footprint_r - 12.0)
			var min_r: float = prov.footprint_radius + footprint_r + 16.0
			var ring_radii: PackedFloat32Array = PackedFloat32Array([
				min_r,
				lerpf(min_r, max_r, 0.45),
				lerpf(min_r, max_r, 0.80),
				max_r,
			])
			for r: float in ring_radii:
				if r > prov.power_radius - 6.0:
					continue
				for k: int in range(p_steps):
					var angle: float = TAU * float(k) / float(p_steps)
					var candidate: Vector2 = prov.global_position + Vector2.RIGHT.rotated(angle) * r
					if _is_build_spot_valid(data, candidate):
						return candidate
		return Vector2.INF

	var anchors: Array[Vector2] = [preferred_pos, fallback_origin]
	var radii: PackedFloat32Array = PackedFloat32Array([0.0, 75.0, 125.0, 175.0, 230.0, 290.0])
	var angle_steps: int = 12

	for anchor: Vector2 in anchors:
		for r: float in radii:
			if r <= 0.1:
				if _is_build_spot_valid(data, anchor):
					return anchor
				continue
			for k: int in range(angle_steps):
				var angle: float = TAU * float(k) / float(angle_steps)
				var candidate: Vector2 = anchor + Vector2.RIGHT.rotated(angle) * r
				if _is_build_spot_valid(data, candidate):
					return candidate
	return Vector2.INF


func _is_build_spot_valid(data: BuildingData, world_pos: Vector2) -> bool:
	var router: CommandRouter = _get_command_router()
	if router != null:
		var eval: Dictionary = router.evaluate_build_placement(data, world_pos, ai_team)
		return bool(eval.get("valid", false))

	var half: Vector2 = data.footprint_size * 0.5
	var safe_bounds: Rect2 = Rect2(
		arena_bounds.position + half + Vector2(8.0, 8.0),
		arena_bounds.size - data.footprint_size - Vector2(16.0, 16.0)
	)
	if not safe_bounds.has_point(world_pos):
		return false
	var new_radius: float = data.get_footprint_radius()
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.overlaps_circle(world_pos, new_radius + 8.0):
				return false
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.overlaps_circle(world_pos, new_radius + 8.0):
				return false
	for node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(node) and not bool(node.get("is_destroyed")) and node.has_method("overlaps_circle"):
			if node.call("overlaps_circle", world_pos, new_radius + 8.0):
				return false
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node) and not (node as Building).is_destroyed:
			var min_d: float = (node as Building).footprint_radius + new_radius + 10.0
			if (node as Building).global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if rn.is_depleted() or rn.is_vent:
				continue
			var min_d: float = rn.collision_radius + new_radius + 8.0
			if rn.global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	if data.requires_power_grid and not Building.is_position_powered_for_team(get_tree(), world_pos, int(ai_team)):
		return false
	return true


func _find_nearest_unoccupied_vent(origin: Vector2, max_radius: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if not rn.is_vent or rn.is_occupied():
				continue
			var d_sq: float = origin.distance_squared_to(rn.global_position)
			if d_sq <= best_d_sq:
				best_d_sq = d_sq
				best = rn
	return best


func _find_expansion_silica_vein(core_pos: Vector2, existing_condensers: Array[Building]) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = INF
	var min_sep_sq: float = 420.0 * 420.0
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted() or rn.is_vent or rn.resource_type != &"silica":
			continue
		var too_close: bool = false
		for cond: Building in existing_condensers:
			if is_instance_valid(cond) and cond.global_position.distance_squared_to(rn.global_position) < min_sep_sq:
				too_close = true
				break
		if too_close:
			continue
		var d_sq: float = core_pos.distance_squared_to(rn.global_position)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best = rn
	return best


func _get_flank_corridor_waypoint(north_lane: bool) -> Vector2:
	var best_pos: Vector2 = Vector2(-80.0, -810.0) if north_lane else Vector2(80.0, 810.0)
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if not (node is MapLandmarkScript) or not is_instance_valid(node):
			continue
		var lm: MapLandmarkScript = node
		if lm.visual_style != MapLandmarkScript.VisualStyle.RELAY_ARCH:
			continue
		if north_lane and lm.global_position.y < -200.0:
			return lm.global_position
		if not north_lane and lm.global_position.y > 200.0:
			return lm.global_position
	return best_pos


func _find_available_worker(near_pos: Vector2) -> Unit:
	var best_idle: Unit = null
	var best_idle_d_sq: float = INF
	var best_gathering: Unit = null
	var best_gather_d_sq: float = INF

	for u: Unit in _get_team_units(ai_team):
		if not u.can_construct():
			continue
		if u.command_state == Unit.CommandState.CONSTRUCTING or u.command_state == Unit.CommandState.SALVAGING:
			continue
		if not u.command_queue.is_empty():
			continue
		var d_sq: float = u.global_position.distance_squared_to(near_pos)
		if u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_idle_d_sq:
				best_idle_d_sq = d_sq
				best_idle = u
		elif u.command_state == Unit.CommandState.GATHERING:
			if u.gather_component != null and u.gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and u.is_carrying_cargo():
				continue
			if d_sq < best_gather_d_sq:
				best_gather_d_sq = d_sq
				best_gathering = u

	return best_idle if best_idle != null else best_gathering


func _has_worker_building(target_b: Building) -> bool:
	for u: Unit in _get_team_units(ai_team):
		if u.command_state == Unit.CommandState.CONSTRUCTING and u._construction_target == target_b:
			return true
		for queued_cmd: Dictionary in u.command_queue:
			if queued_cmd.get("type", &"") == &"build" and queued_cmd.get("target", null) == target_b:
				return true
	return false


func _find_ai_command_core() -> Building:
	for b: Building in _get_team_buildings(ai_team):
		if b.is_command_hub():
			return b
	return null


func _count_constructed_command_cores() -> int:
	var c: int = 0
	for b: Building in _get_team_buildings(ai_team):
		if b.is_constructed and b.is_command_hub():
			c += 1
	return c


func _get_team_buildings(target_team: Unit.Team) -> Array[Building]:
	var out: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if not b.is_destroyed and b.team == target_team:
				out.append(b)
	return out


func _get_team_units(target_team: Unit.Team) -> Array[Unit]:
	var out: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node
			if not u.is_dead and not u.is_staffed and u.team == target_team:
				out.append(u)
	return out


func _is_enemy_team(other_team: int) -> bool:
	if TeamManager != null:
		return TeamManager.are_enemies(int(ai_team), other_team)
	return other_team != int(ai_team)


func _is_allied_team(other_team: int) -> bool:
	if TeamManager != null:
		return TeamManager.are_allies(int(ai_team), other_team)
	return other_team == int(ai_team)


func _is_relaxed_difficulty() -> bool:
	return GameConfig != null and _ai_difficulty == int(GameConfig.AIDifficulty.RELAXED)


func _is_brutal_difficulty() -> bool:
	return GameConfig != null and _ai_difficulty == int(GameConfig.AIDifficulty.BRUTAL)


func _is_combat_unit(unit: Unit) -> bool:
	if unit == null or unit.data == null:
		return false
	return unit.data.is_combat_unit() and unit.data.move_speed > 0.0


func _count_queued_unit_type(buildings: Array[Building], type_id: StringName) -> int:
	var count: int = 0
	for b: Building in buildings:
		if b.production_component == null:
			continue
		for entry: Dictionary in b.production_component.get_queue():
			if entry.get("kind", ProductionComponent.KIND_UNIT) != ProductionComponent.KIND_UNIT:
				continue
			var udata: UnitData = entry.get("data", null) as UnitData
			if udata != null and udata.unit_type_id == type_id:
				count += maxi(1, int(entry.get("batch_count", 1)))
	return count


func _find_nearest_resource(origin: Vector2, res_type: StringName) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if rn.is_depleted() or rn.is_vent or rn.resource_type != res_type:
				continue
			var d_sq: float = origin.distance_squared_to(rn.global_position)
			if d_sq < best_d_sq:
				best_d_sq = d_sq
				best = rn
	return best


func _get_resources_near(origin: Vector2, res_type: StringName, max_radius: float) -> Array[ResourceNode]:
	var out: Array[ResourceNode] = []
	var max_r_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if rn.is_depleted() or rn.is_vent or rn.resource_type != res_type:
				continue
			if origin.distance_squared_to(rn.global_position) <= max_r_sq:
				out.append(rn)
	return out


func _pick_least_crowded_resource(worker_pos: Vector2, nodes: Array[ResourceNode]) -> ResourceNode:
	var best: ResourceNode = null
	var best_score: float = INF
	for rn: ResourceNode in nodes:
		if not is_instance_valid(rn) or rn.is_depleted():
			continue
		var assigned: int = 0
		for u: Unit in _get_team_units(ai_team):
			if u.gather_component != null and u.gather_component.is_active() and u.gather_component.target_node == rn:
				assigned += 1
		var dist: float = worker_pos.distance_to(rn.global_position)
		var score: float = float(assigned) * 180.0 + dist
		if score < best_score:
			best_score = score
			best = rn
	return best


func _nudge_units_out_of_building(building: Building) -> void:
	CommandRouter.nudge_units_out_of_building(building, arena_bounds)


func _get_economy_manager() -> EconomyManager:
	return get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func _get_command_router() -> CommandRouter:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("SelectionController/CommandRouter") as CommandRouter
