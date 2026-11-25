class_name SkirmishAICommander
extends Node

const MapLandmarkScript = preload("res://scripts/world/map_landmark.gd")

const CONDENSER_DATA_PATH: String = "res://resources/buildings/silica_condenser_data.tres"
const PYLON_DATA_PATH: String = "res://resources/buildings/synapse_pylon_data.tres"
const MAINFRAME_DATA_PATH: String = "res://resources/buildings/wetware_mainframe_data.tres"
const CLONING_VAT_DATA_PATH: String = "res://resources/buildings/cloning_vat_data.tres"
const FOUNDRY_DATA_PATH: String = "res://resources/buildings/calibration_foundry_data.tres"
const FABRICATOR_DATA_PATH: String = "res://resources/buildings/synthetics_fabricator_data.tres"

const WORKER_DATA_PATH: String = "res://resources/units/worker_unit_data.tres"
const HARVESTER_DATA_PATH: String = "res://resources/units/silica_harvester_data.tres"
const ENGINEER_DATA_PATH: String = "res://resources/units/engineer_data.tres"
const CLONE_TROOPER_DATA_PATH: String = "res://resources/units/clone_trooper_data.tres"
const STINGER_DATA_PATH: String = "res://resources/units/stinger_data.tres"
const SYMBIOTE_DATA_PATH: String = "res://resources/units/symbiote_data.tres"
const LANCE_RIG_DATA_PATH: String = "res://resources/units/lance_rig_data.tres"
const SIGNAL_JAMMER_DATA_PATH: String = "res://resources/units/signal_jammer_data.tres"
const GOLIATH_DATA_PATH: String = "res://resources/units/goliath_frame_data.tres"
const ARC_LANCER_DATA_PATH: String = "res://resources/units/arc_lancer_data.tres"
const MORTAR_DATA_PATH: String = "res://resources/units/chrysalis_mortar_data.tres"

const UPG_BATCH_EFFICIENCY_PATH: String = "res://resources/upgrades/batch_efficiency.tres"
const UPG_ADRENAL_POTENCY_PATH: String = "res://resources/upgrades/adrenal_potency.tres"
const UPG_COMPUTE_OVERDRIVE_PATH: String = "res://resources/upgrades/compute_overdrive.tres"

const INTEL_SCAN_INTERVAL: float = 1.5
const INTEL_TTL_SECONDS: float = 90.0
const BARRICADE_MIN_MATCH_TIME: float = 150.0
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

var _condenser_data: BuildingData = null
var _pylon_data: BuildingData = null
var _mainframe_data: BuildingData = null
var _cloning_vat_data: BuildingData = null
var _foundry_data: BuildingData = null
var _fabricator_data: BuildingData = null
var _worker_data: UnitData = null
var _harvester_data: UnitData = null
var _engineer_data: UnitData = null
var _clone_trooper_data: UnitData = null
var _stinger_data: UnitData = null
var _symbiote_data: UnitData = null
var _lance_rig_data: UnitData = null
var _signal_jammer_data: UnitData = null
var _goliath_data: UnitData = null
var _arc_lancer_data: UnitData = null
var _mortar_data: UnitData = null
var _upg_batch_efficiency: UpgradeData = null
var _upg_adrenal_potency: UpgradeData = null
var _upg_compute_overdrive: UpgradeData = null

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


func _ready() -> void:
	add_to_group("skirmish_ai")
	_load_faction_rosters()
	_apply_lobby_ai_profile()
	call_deferred("_setup_initial_rallies")


func _load_faction_rosters() -> void:
	var faction_id: StringName = TeamManager.get_team_faction(int(ai_team)) if TeamManager != null else &"genesis_v2"
	var faction_res: Resource = TeamManager.get_faction_data(faction_id) if (TeamManager != null and TeamManager.has_method("get_faction_data")) else null
	if faction_res != null:
		_condenser_data = faction_res.call("get_ai_building_for_role", &"refinery") as BuildingData
		_pylon_data = faction_res.call("get_ai_building_for_role", &"supply") as BuildingData
		_mainframe_data = faction_res.call("get_ai_building_for_role", &"compute_hub") as BuildingData
		_cloning_vat_data = faction_res.call("get_ai_building_for_role", &"barracks_t1") as BuildingData
		_foundry_data = faction_res.call("get_ai_building_for_role", &"counter_foundry") as BuildingData
		_fabricator_data = faction_res.call("get_ai_building_for_role", &"heavy_t2") as BuildingData
		_worker_data = faction_res.call("get_unit_by_id", &"worker") as UnitData
		_harvester_data = faction_res.call("get_unit_by_id", &"silica_harvester") as UnitData
		_engineer_data = faction_res.call("get_unit_by_id", &"engineer") as UnitData
		_clone_trooper_data = faction_res.call("get_unit_by_id", &"clone_trooper") as UnitData
		_stinger_data = faction_res.call("get_unit_by_id", &"stinger") as UnitData
		_symbiote_data = faction_res.call("get_unit_by_id", &"symbiote") as UnitData
		_lance_rig_data = faction_res.call("get_unit_by_id", &"lance_rig") as UnitData
		_signal_jammer_data = faction_res.call("get_unit_by_id", &"signal_jammer") as UnitData
		_goliath_data = faction_res.call("get_unit_by_id", &"goliath_frame") as UnitData
		_arc_lancer_data = faction_res.call("get_unit_by_id", &"arc_lancer") as UnitData
		_mortar_data = faction_res.call("get_unit_by_id", &"chrysalis_mortar") as UnitData
		_upg_batch_efficiency = faction_res.call("get_upgrade_by_id", &"batch_efficiency") as UpgradeData
		_upg_adrenal_potency = faction_res.call("get_upgrade_by_id", &"adrenal_potency") as UpgradeData
		_upg_compute_overdrive = faction_res.call("get_upgrade_by_id", &"compute_overdrive") as UpgradeData

	# Fallback to direct resource paths if any entry is absent
	if _condenser_data == null:
		_condenser_data = load(CONDENSER_DATA_PATH) as BuildingData
	if _pylon_data == null:
		_pylon_data = load(PYLON_DATA_PATH) as BuildingData
	if _mainframe_data == null:
		_mainframe_data = load(MAINFRAME_DATA_PATH) as BuildingData
	if _cloning_vat_data == null:
		_cloning_vat_data = load(CLONING_VAT_DATA_PATH) as BuildingData
	if _foundry_data == null:
		_foundry_data = load(FOUNDRY_DATA_PATH) as BuildingData
	if _fabricator_data == null:
		_fabricator_data = load(FABRICATOR_DATA_PATH) as BuildingData
	if _worker_data == null:
		_worker_data = load(WORKER_DATA_PATH) as UnitData
	if _harvester_data == null:
		_harvester_data = load(HARVESTER_DATA_PATH) as UnitData
	if _engineer_data == null:
		_engineer_data = load(ENGINEER_DATA_PATH) as UnitData
	if _clone_trooper_data == null:
		_clone_trooper_data = load(CLONE_TROOPER_DATA_PATH) as UnitData
	if _stinger_data == null:
		_stinger_data = load(STINGER_DATA_PATH) as UnitData
	if _symbiote_data == null:
		_symbiote_data = load(SYMBIOTE_DATA_PATH) as UnitData
	if _lance_rig_data == null:
		_lance_rig_data = load(LANCE_RIG_DATA_PATH) as UnitData
	if _signal_jammer_data == null:
		_signal_jammer_data = load(SIGNAL_JAMMER_DATA_PATH) as UnitData
	if _goliath_data == null:
		_goliath_data = load(GOLIATH_DATA_PATH) as UnitData
	if _arc_lancer_data == null:
		_arc_lancer_data = load(ARC_LANCER_DATA_PATH) as UnitData
	if _mortar_data == null:
		_mortar_data = load(MORTAR_DATA_PATH) as UnitData
	if _upg_batch_efficiency == null:
		_upg_batch_efficiency = load(UPG_BATCH_EFFICIENCY_PATH) as UpgradeData
	if _upg_adrenal_potency == null:
		_upg_adrenal_potency = load(UPG_ADRENAL_POTENCY_PATH) as UpgradeData
	if _upg_compute_overdrive == null:
		_upg_compute_overdrive = load(UPG_COMPUTE_OVERDRIVE_PATH) as UpgradeData


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
	if b == null:
		return false
	var bid: StringName = b.building_type_id
	return bid == &"cloning_vat" or bid == &"calibration_foundry" or bid == &"synthetics_fabricator"


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

	# 5. Economy, infrastructure, and reactive GENESIS_V2 production loop
	_manage_economy_and_production(econ, core)

	# 6. Early scouting dispatch
	_manage_early_scouting(core)

	# 7. Explicit Army State Machine (DEFENDING / RETREATING / BREACHING / ATTACKING / STAGING)
	_tick_army_state_machine(core, tick_dt)


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


func _find_base_perimeter_threat(core: Building) -> Variant:
	var ai_buildings: Array[Building] = _get_team_buildings(ai_team)
	var threat_unit: Unit = null
	var best_d_sq: float = INF

	# Check ~650px perimeter around every owned Nexus Vat and economy hub via SpatialGrid
	for b: Building in ai_buildings:
		var check_r: float = base_defense_radius if (b.is_core_hub or b.building_type_id == &"nexus_vat" or b.is_resource_dropoff) else 380.0
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
					if u.global_position.distance_to(core.global_position) <= base_defense_radius:
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
	if unit == null or not is_instance_valid(unit):
		return 0.0
	match unit.get_unit_type_id():
		&"goliath_frame", &"arc_lancer", &"chrysalis_mortar":
			return 3.0
		&"lance_rig", &"signal_jammer":
			return 2.0
		&"symbiote":
			return 1.5
		_:
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
			if not b.is_destroyed and _is_enemy_team(int(b.team)) and (b.is_core_hub or b.building_type_id == &"nexus_vat"):
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
					if u.global_position.distance_squared_to(h.global_position) <= r_sq:
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

	# Pick a fast Stinger first; fall back to Clone Trooper if no Stinger is fielded
	var best_stinger: Unit = null
	var best_clone: Unit = null
	for u: Unit in _get_team_units(ai_team):
		if _wave_units.has(u) and army_state == ArmyState.ATTACKING:
			continue
		var uid: StringName = u.get_unit_type_id()
		if uid == &"stinger" and best_stinger == null:
			best_stinger = u
		elif uid == &"clone_trooper" and best_clone == null:
			best_clone = u

	var scout: Unit = best_stinger if best_stinger != null else best_clone
	if scout == null:
		return

	_active_scout = scout
	_wave_units.erase(scout)

	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	var mid_pt: Vector2 = uplink.global_position if (uplink != null and is_instance_valid(uplink)) else Vector2.ZERO
	var quadrant_pt: Vector2 = _pick_scout_quadrant_waypoint(core)
	var return_pt: Vector2 = _staging_point if _staging_point_valid else core.global_position

	scout.command_move(mid_pt, false)
	scout.command_move(quadrant_pt, true)
	scout.command_move(return_pt, true)


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

	var infantry_count: int = 0
	var vat_count: int = 0
	var now: float = _ai_elapsed

	for eu_var: Variant in seen_enemy_units.values():
		var eu: Unit = eu_var as Unit
		var uid: StringName = eu.get_unit_type_id()
		if uid == &"goliath_frame" or uid == &"arc_lancer":
			_scouted_intel["heavy_armor_at"] = now
		elif uid == &"chrysalis_mortar":
			_scouted_intel["artillery_at"] = now
		elif uid == &"clone_trooper" or uid == &"stinger":
			infantry_count += 1

	for eb_var: Variant in seen_enemy_buildings.values():
		var eb: Building = eb_var as Building
		var bid: StringName = eb.building_type_id
		if bid == &"synthetics_fabricator":
			_scouted_intel["heavy_armor_at"] = now
			_scouted_intel["last_known_enemy_base"] = eb.global_position
		elif bid == &"cloning_vat":
			vat_count += 1
			_scouted_intel["last_known_enemy_base"] = eb.global_position
		elif eb.is_core_hub or bid == &"nexus_vat":
			_scouted_intel["last_known_enemy_base"] = eb.global_position
		if eb.has_turret or bid == &"defense_turret":
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
		if center.distance_squared_to(u.global_position) <= r_sq:
			seen_units[u.get_instance_id()] = u
	for b: Building in SpatialGrid.query_buildings_in_radius(center, radius):
		if not is_instance_valid(b) or b.is_destroyed:
			continue
		if not _is_enemy_team(int(b.team)):
			continue
		var eff_r: float = radius + b.footprint_radius
		if center.distance_squared_to(b.global_position) <= eff_r * eff_r:
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
		if not is_instance_valid(u) or u.is_dead:
			continue
		var uid: StringName = u.get_unit_type_id()
		if uid == &"lance_rig" or uid == &"chrysalis_mortar" or uid == &"goliath_frame" or uid == &"arc_lancer":
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

	# Pick 1 available Engineer (faster 1.8s extraction) or 1 Worker (never pulling below 3 Biomass harvesters)
	var team_units: Array[Unit] = _get_team_units(ai_team)
	var biomass_workers: int = 0
	var best_engineer: Unit = null
	var best_eng_d_sq: float = INF
	var best_worker: Unit = null
	var best_wrk_d_sq: float = INF

	for u: Unit in team_units:
		if u.get_unit_type_id() == &"worker" and u.command_state == Unit.CommandState.GATHERING:
			biomass_workers += 1
		if not u.can_salvage_core():
			continue
		if u.command_state == Unit.CommandState.CONSTRUCTING or u.command_state == Unit.CommandState.SALVAGING or u.command_state == Unit.CommandState.STAFFING_BUILDING:
			continue
		if not u.command_queue.is_empty():
			continue
		var d_sq: float = u.global_position.distance_squared_to(target_core.global_position)
		if u.get_unit_type_id() == &"engineer" and u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_eng_d_sq:
				best_eng_d_sq = d_sq
				best_engineer = u
		elif u.get_unit_type_id() == &"worker":
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
		if best_worker.command_state == Unit.CommandState.IDLE or biomass_workers > 3:
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
		if unit.get_unit_type_id() != &"worker":
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
		if b.building_type_id == &"silica_condenser" and b.is_constructed:
			for rn: ResourceNode in _get_resources_near(b.global_position, &"silica", 520.0):
				if not silica_nodes.has(rn):
					silica_nodes.append(rn)
	for unit: Unit in _get_team_units(ai_team):
		if unit.get_unit_type_id() != &"silica_harvester":
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
		var uid: StringName = u.get_unit_type_id()
		if uid == &"worker":
			worker_count += 1
		elif uid == &"silica_harvester":
			harvester_count += 1
		elif uid == &"engineer":
			engineer_count += 1

	var condensers: Array[Building] = []
	var constructed_condensers: Array[Building] = []
	var constructed_condenser: Building = null
	var mainframes: Array[Building] = []
	var constructed_mainframes: Array[Building] = []
	var constructed_mainframe: Building = null
	var cloning_vats: Array[Building] = []
	var constructed_vats: Array[Building] = []
	var foundries: Array[Building] = []
	var constructed_foundries: Array[Building] = []
	var fabricators: Array[Building] = []
	var constructed_fabricators: Array[Building] = []
	var unfinished_pylons: int = 0
	var staffed_engineers: int = 0
	var total_mainframe_slots: int = 0

	for b: Building in buildings:
		if b.building_type_id == &"silica_condenser":
			condensers.append(b)
			if b.is_constructed:
				constructed_condensers.append(b)
				constructed_condenser = b
		elif b.building_type_id == &"wetware_mainframe":
			mainframes.append(b)
			if b.is_constructed:
				constructed_mainframes.append(b)
				constructed_mainframe = b
				staffed_engineers += b.get_assigned_engineer_count()
				total_mainframe_slots += b.max_staff_slots
		elif b.building_type_id == &"cloning_vat":
			cloning_vats.append(b)
			if b.is_constructed:
				constructed_vats.append(b)
		elif b.building_type_id == &"calibration_foundry":
			foundries.append(b)
			if b.is_constructed:
				constructed_foundries.append(b)
		elif b.building_type_id == &"synthetics_fabricator":
			fabricators.append(b)
			if b.is_constructed:
				constructed_fabricators.append(b)
		elif b.building_type_id == &"synapse_pylon" and not b.is_constructed:
			unfinished_pylons += 1

	var queued_workers: int = _count_queued_unit_type(buildings, &"worker")
	var queued_harvesters: int = _count_queued_unit_type(buildings, &"silica_harvester")
	var queued_engineers: int = _count_queued_unit_type(buildings, &"engineer")
	var total_workers: int = worker_count + queued_workers
	var total_harvesters: int = harvester_count + queued_harvesters
	var total_engineers: int = engineer_count + staffed_engineers + queued_engineers

	var bw_used: int = econ.get_bandwidth_used(ai_team)
	var bw_cap: int = econ.get_bandwidth_cap(ai_team)
	var needs_pylon: bool = (bw_used >= bw_cap - 4) and unfinished_pylons == 0 and bw_cap < max_bandwidth_cap
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

	# Swarm Rush builds its first Cloning Vat before the Silica Condenser for rapid infantry pressure.
	if is_swarm_rush and cloning_vats.is_empty() and _cloning_vat_data != null:
		if econ.can_afford(ai_team, _cloning_vat_data.get_cost_dict()):
			var to_c_rush: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var rush_vat: Building = _try_place_and_build(_cloning_vat_data, core.global_position + to_c_rush * 175.0, core.global_position)
			if rush_vat != null:
				rush_vat.set_rally_position(rally_pt)
			return
		if biomass < _cloning_vat_data.biomass_cost:
			return

	# Priority 2: Build Silica Condenser near Silica Vein.
	if condensers.is_empty():
		if _condenser_data != null and econ.can_afford(ai_team, _condenser_data.get_cost_dict()):
			var vein: ResourceNode = _find_nearest_resource(core.global_position, &"silica")
			var anchor: Vector2 = core.global_position.lerp(vein.global_position, 0.58) if vein != null else (core.global_position + Vector2(-120.0, 180.0))
			_try_place_and_build(_condenser_data, anchor, core.global_position)
		return

	# Priority 3: Expand Bandwidth cap via Synapse Pylon before hitting population block.
	if needs_pylon:
		if _pylon_data != null and econ.can_afford(ai_team, _pylon_data.get_cost_dict()):
			var away_dir: Vector2 = (core.global_position - Vector2.ZERO).normalized()
			var pylon_anchor: Vector2 = core.global_position + away_dir * 125.0
			_try_place_and_build(_pylon_data, pylon_anchor, core.global_position)
		return

	# Priority 4: Train automated Silica Harvesters once Condensers are online.
	var desired_harvesters: int = 3 if (constructed_condensers.size() >= 2 or is_brutal) else (2 if constructed_vats.size() >= 1 else 1)
	if _harvester_data != null and constructed_condenser != null and total_harvesters < desired_harvesters:
		var trainer: Building = constructed_condenser if constructed_condenser.can_train_unit_data(_harvester_data) else core
		if trainer.get_training_queue_size() < 2 and trainer.can_train_unit_data(_harvester_data):
			trainer.queue_unit_data(_harvester_data)
			return

	# Priority 5: Construct primary Tier-1 Cloning Vat on the forward edge facing the map center.
	if cloning_vats.is_empty() and _cloning_vat_data != null:
		if econ.can_afford(ai_team, _cloning_vat_data.get_cost_dict()):
			var to_center: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var vat_anchor: Vector2 = core.global_position + to_center * 175.0
			var built_vat: Building = _try_place_and_build(_cloning_vat_data, vat_anchor, core.global_position)
			if built_vat != null:
				built_vat.set_rally_position(rally_pt)
			return
		if biomass < _cloning_vat_data.biomass_cost:
			return

	# Priority 6: Saturate workers up to target_worker_count.
	if _worker_data != null and total_workers < target_worker_count:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)

	# Priority 7: Wetware Mainframes on natural & contested expansion Compute Vents + Engineers.
	var exp_vent_biomass: int = 160 if (is_synth_tech or is_brutal) else 220
	if (not constructed_vats.is_empty() or is_synth_tech) and _mainframe_data != null:
		if mainframes.is_empty():
			var vent: ResourceNode = _find_nearest_unoccupied_vent(core.global_position, 580.0)
			if vent != null and econ.can_afford(ai_team, _mainframe_data.get_cost_dict()):
				_try_place_and_build_on_vent(_mainframe_data, vent)
		elif mainframes.size() == 1 and constructed_mainframes.size() >= 1 and staffed_engineers >= 1 and biomass >= exp_vent_biomass:
			var exp_vent: ResourceNode = _find_nearest_unoccupied_vent(core.global_position, 1650.0)
			if exp_vent != null and econ.can_afford(ai_team, _mainframe_data.get_cost_dict()):
				_try_place_and_build_on_vent(_mainframe_data, exp_vent)

	var desired_engineers: int = mini(4, total_mainframe_slots)
	if constructed_mainframe != null and _engineer_data != null and total_engineers < desired_engineers:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_engineer_data):
			core.queue_unit_data(_engineer_data)

	# Priority 7.5: Expand Silica economy to expansion cluster once Tier-1 is established.
	var exp_cond_biomass: int = 180 if is_brutal else 240
	if condensers.size() < 2 and not constructed_condensers.is_empty() and not constructed_vats.is_empty() and biomass >= exp_cond_biomass and _condenser_data != null:
		if econ.can_afford(ai_team, _condenser_data.get_cost_dict()):
			var exp_vein: ResourceNode = _find_expansion_silica_vein(core.global_position, condensers)
			if exp_vein != null:
				var exp_anchor: Vector2 = exp_vein.global_position.lerp(core.global_position, 0.16)
				_try_place_and_build(_condenser_data, exp_anchor, exp_vein.global_position)

	# Priority 8: Mid-game Upgrades at Cloning Vat (Batch Efficiency -> Adrenal Potency).
	if not constructed_vats.is_empty():
		var primary_vat: Building = constructed_vats[0]
		if primary_vat.production_component != null and primary_vat.get_training_queue_size() < 2:
			if _upg_batch_efficiency != null and primary_vat.production_component.can_queue_upgrade(primary_vat, _upg_batch_efficiency):
				primary_vat.production_component.enqueue_upgrade(primary_vat, _upg_batch_efficiency)
			elif _upg_adrenal_potency != null and econ.has_upgrade(ai_team, UpgradeManager.UPGRADE_BATCH_EFFICIENCY) and primary_vat.production_component.can_queue_upgrade(primary_vat, _upg_adrenal_potency):
				primary_vat.production_component.enqueue_upgrade(primary_vat, _upg_adrenal_potency)

	# Reactive Foundry priority when ANTI_ARMOR intel is active
	var urgent_anti_armor_foundry: bool = (_active_counter_posture == &"ANTI_ARMOR" and counter_strength >= 0.70)
	if urgent_anti_armor_foundry and foundries.is_empty() and constructed_mainframe != null and _foundry_data != null and silica >= _foundry_data.silica_cost:
		if econ.can_afford(ai_team, _foundry_data.get_cost_dict()):
			var to_c_aa: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_aa: Vector2 = Vector2(-to_c_aa.y, to_c_aa.x)
			var built_aa: Building = _try_place_and_build(_foundry_data, core.global_position + to_c_aa * 160.0 + perp_aa * 145.0, core.global_position)
			if built_aa != null:
				built_aa.set_rally_position(rally_pt)

	# Priority 9: Late-game Tier-2 Synthetics Fabricator.
	if fabricators.is_empty() and not constructed_vats.is_empty() and _fabricator_data != null and compute >= _fabricator_data.compute_cost:
		if econ.can_afford(ai_team, _fabricator_data.get_cost_dict()):
			var to_center_f: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_f: Vector2 = Vector2(-to_center_f.y, to_center_f.x)
			var fab_anchor: Vector2 = core.global_position + to_center_f * 165.0 - perp_f * 145.0
			var built_fab: Building = _try_place_and_build(_fabricator_data, fab_anchor, core.global_position)
			if built_fab != null:
				built_fab.set_rally_position(rally_pt)

	# Priority 10: Mid-game Calibration Foundry for Lance-Rigs & Signal Jammers.
	var allow_foundry: bool = (not is_synth_tech or not fabricators.is_empty() or urgent_anti_armor_foundry)
	if allow_foundry and foundries.is_empty() and constructed_mainframe != null and _foundry_data != null and silica >= _foundry_data.silica_cost:
		if econ.can_afford(ai_team, _foundry_data.get_cost_dict()):
			var to_center_cf: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_cf: Vector2 = Vector2(-to_center_cf.y, to_center_cf.x)
			var cf_anchor: Vector2 = core.global_position + to_center_cf * 160.0 + perp_cf * 145.0
			var built_cf: Building = _try_place_and_build(_foundry_data, cf_anchor, core.global_position)
			if built_cf != null:
				built_cf.set_rally_position(rally_pt)

	# Priority 11: Synthetics Fabricator heavy mix (reactively biased by _active_counter_posture).
	for fab: Building in constructed_fabricators:
		if not fab.has_rally():
			fab.set_rally_position(rally_pt)
		if fab.get_training_queue_size() >= 2:
			continue
		if _upg_compute_overdrive != null and fab.production_component != null and fab.production_component.can_queue_upgrade(fab, _upg_compute_overdrive):
			fab.production_component.enqueue_upgrade(fab, _upg_compute_overdrive)
			continue
		var heavy_choice: UnitData = _choose_fabricator_unit(counter_strength)
		if heavy_choice != null and fab.can_train_unit_data(heavy_choice):
			fab.queue_unit_data(heavy_choice)
			_fab_production_counter += 1
		elif _goliath_data != null and fab.can_train_unit_data(_goliath_data):
			fab.queue_unit_data(_goliath_data)
			_fab_production_counter += 1

	# Priority 12: Calibration Foundry production (Lance-Rigs & Signal Jammers biased by intel).
	for foundry: Building in constructed_foundries:
		if not foundry.has_rally():
			foundry.set_rally_position(rally_pt)
		if foundry.get_training_queue_size() >= 2:
			continue
		var foundry_choice: UnitData = _choose_foundry_unit(foundry, counter_strength)
		if foundry_choice != null and foundry.can_train_unit_data(foundry_choice):
			foundry.queue_unit_data(foundry_choice)
			_foundry_production_counter += 1

	# Priority 13: Batch-clone GENESIS_V2 core swarm (weighted by playstyle + reactive intel).
	var hold_for_fab: bool = is_synth_tech and fabricators.is_empty() and constructed_mainframe != null and compute >= 15
	if not hold_for_fab:
		for vat: Building in constructed_vats:
			if not vat.has_rally():
				vat.set_rally_position(rally_pt)
			if vat.get_training_queue_size() >= 2:
				continue
			var chosen: UnitData = _choose_vat_unit(vat, is_swarm_rush, counter_strength)
			if chosen != null and vat.can_train_unit_data(chosen):
				vat.queue_unit_data(chosen)
				_vat_production_counter += 1

	# Priority 14: Additional Cloning Vat when floating surplus Biomass.
	var extra_vat_biomass: int = 200 if is_swarm_rush else (230 if is_brutal else 280)
	var extra_vat_silica: int = 40 if is_swarm_rush else 60
	if _cloning_vat_data != null and cloning_vats.size() < max_cloning_vats and biomass >= extra_vat_biomass and silica >= extra_vat_silica:
		if econ.can_afford(ai_team, _cloning_vat_data.get_cost_dict()):
			var to_center2: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp: Vector2 = Vector2(-to_center2.y, to_center2.x)
			var vat_anchor2: Vector2 = core.global_position + to_center2 * 180.0 + perp * 130.0
			var second_vat: Building = _try_place_and_build(_cloning_vat_data, vat_anchor2, core.global_position)
			if second_vat != null:
				second_vat.set_rally_position(rally_pt)


func _choose_fabricator_unit(counter_strength: float) -> UnitData:
	# Deterministic weighted cycle biased by scouted intel & difficulty counter_strength
	var slot: int = _fab_production_counter % 10
	if _active_counter_posture == &"ANTI_SWARM" and counter_strength >= 0.65 and _mortar_data != null:
		# +30% Chrysalis Mortar splash weight
		if slot < 6:
			return _mortar_data
		return _goliath_data if (slot % 2 == 0) else (_arc_lancer_data if _arc_lancer_data != null else _goliath_data)
	if _active_counter_posture == &"ANTI_ARMOR" and counter_strength >= 0.65 and _arc_lancer_data != null:
		# Boost Arc-Lancer anti-armor presence alongside Goliath frontline
		if slot < 5:
			return _arc_lancer_data
		return _goliath_data if slot < 8 else (_mortar_data if _mortar_data != null else _goliath_data)
	if _active_counter_posture == &"ANTI_SIEGE" and counter_strength >= 0.65 and _goliath_data != null:
		# Heavy Goliath frontline push to collapse inside mortar min_attack_range
		if slot < 6:
			return _goliath_data
		return _arc_lancer_data if (_arc_lancer_data != null and slot < 8) else (_mortar_data if _mortar_data != null else _goliath_data)

	var fab_roll: int = _fab_production_counter % 3
	if fab_roll == 1 and _arc_lancer_data != null:
		return _arc_lancer_data
	if fab_roll == 2 and _mortar_data != null:
		return _mortar_data
	return _goliath_data


func _choose_foundry_unit(foundry: Building, counter_strength: float) -> UnitData:
	var slot: int = _foundry_production_counter % 10
	if _active_counter_posture == &"ANTI_ARMOR" and counter_strength >= 0.50:
		# Strongly favor Lance-Rig anti-armor (+35% shift)
		var want_jam_aa: bool = (slot == 9) and _signal_jammer_data != null and foundry.can_train_unit_data(_signal_jammer_data)
		return _signal_jammer_data if want_jam_aa else _lance_rig_data
	if _active_counter_posture == &"ANTI_SWARM" and counter_strength >= 0.60:
		# Boost Signal Jammer disruption against infantry swarms
		var want_jam_sw: bool = (slot % 2 == 0) and _signal_jammer_data != null and foundry.can_train_unit_data(_signal_jammer_data)
		return _signal_jammer_data if want_jam_sw else _lance_rig_data
	var want_jammer: bool = (_foundry_production_counter % 3 == 2) and _signal_jammer_data != null and foundry.can_train_unit_data(_signal_jammer_data)
	return _signal_jammer_data if want_jammer else _lance_rig_data


func _choose_vat_unit(vat: Building, is_swarm_rush: bool, counter_strength: float) -> UnitData:
	var slot: int = _vat_production_counter % 10
	var want_symbiote: bool = (slot == 9)
	if _active_counter_posture == &"ANTI_SWARM" and counter_strength >= 0.65:
		want_symbiote = (slot == 4 or slot == 9)
	if want_symbiote and _symbiote_data != null and vat.can_train_unit_data(_symbiote_data):
		return _symbiote_data

	var want_stinger: bool = false
	if _active_counter_posture == &"ANTI_SIEGE" and counter_strength >= 0.60:
		# Boost fast flanking Stingers against Chrysalis Mortars
		want_stinger = (slot == 1 or slot == 3 or slot == 5 or slot == 7 or slot == 8)
	elif is_swarm_rush:
		want_stinger = (slot == 1 or slot == 4 or slot == 7)
	else:
		want_stinger = (slot == 2 or slot == 6)

	if want_stinger and _stinger_data != null and vat.can_train_unit_data(_stinger_data):
		return _stinger_data
	return _clone_trooper_data


func _trigger_combat_abilities() -> void:
	for u: Unit in _get_team_units(ai_team):
		if u.data == null or u.data.abilities.is_empty() or u.current_target == null or not is_instance_valid(u.current_target):
			continue
		var dist: float = u.global_position.distance_to(u.current_target.global_position)
		for ab: AbilityData in u.data.abilities:
			if ab == null or ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
				continue
			if not u.is_ability_ready(ab):
				continue
			if ab.ability_id == &"adrenal_surge" and dist <= u.data.attack_range + 45.0:
				u.command_cast_ability(ab, u.global_position, u)
				break
			elif (ab.ability_id == &"static_pulse" or ab.ability_id == &"seismic_slam") and dist <= maxf(80.0, ab.aoe_radius * 0.92):
				u.command_cast_ability(ab, u.global_position, u)
				break
			elif ab.ability_id == &"spore_barrage" and dist <= ab.cast_range and dist >= 100.0:
				u.command_cast_ability(ab, u.current_target.global_position)
				break


# =============================================================================
# PHASE D: FFA & MULTI-TEAM TARGET SCORING + DEBUG READOUT
# =============================================================================

func _select_wave_target(wave_idx: int, core: Building = null) -> Vector2:
	var origin: Vector2 = core.global_position if (core != null and is_instance_valid(core)) else (_staging_point if _staging_point_valid else Vector2.ZERO)

	# 1. Urgent Data Hyper-Uplink denial when an enemy controls it or progress > 35%
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
		if not (b.is_core_hub or b.building_type_id == &"nexus_vat"):
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
	if data.required_building_id != &"" and not econ.has_constructed_building(ai_team, data.required_building_id):
		return null
	if not econ.can_afford(ai_team, data.get_cost_dict()):
		return null

	var worker: Unit = _find_available_worker(preferred_pos)
	if worker == null:
		return null

	var spot: Vector2 = _find_valid_build_position(data, preferred_pos, fallback_origin)
	if spot == Vector2.INF:
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
	if building.is_core_hub or building.building_type_id == &"nexus_vat":
		_compute_staging_point(building)
		_sync_military_rallies()
	elif _is_military_production_building(building) and _staging_point_valid:
		building.set_rally_position(_staging_point)


func _find_valid_build_position(data: BuildingData, preferred_pos: Vector2, fallback_origin: Vector2) -> Vector2:
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
		if b.is_core_hub or b.building_type_id == &"nexus_vat":
			return b
	return null


func _count_constructed_command_cores() -> int:
	var c: int = 0
	for b: Building in _get_team_buildings(ai_team):
		if b.is_constructed and (b.is_core_hub or b.building_type_id == &"nexus_vat"):
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
	if unit.data.can_gather or unit.data.can_staff_compute:
		return false
	var uid: StringName = unit.get_unit_type_id()
	if uid == &"symbiote" or uid == &"signal_jammer":
		return unit.data.move_speed > 0.0
	return unit.data.attack_damage > 0.0 and unit.data.move_speed > 0.0


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
