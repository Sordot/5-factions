class_name SkirmishAICommander
extends Node

const AIBuildPlannerScript = preload("res://scripts/systems/ai_build_planner.gd")
const AI_SCOUT_INTEL_SCRIPT: GDScript = preload("res://scripts/systems/ai/ai_scout_intel.gd")
const AI_ECONOMY_MANAGER_SCRIPT: GDScript = preload("res://scripts/systems/ai/ai_economy_manager.gd")
const AI_ARMY_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/ai/ai_army_controller.gd")

const INTEL_SCAN_INTERVAL: float = 1.5
const TRANSMISSION_GLOBAL_COOLDOWN_MS: int = 45000
const TRANSMISSION_CATEGORY_COOLDOWN_MS: int = 90000

const DEFAULT_AI_TRANSMISSIONS: Dictionary = {
	&"wave_launch": "// AI COMMAND: Strike column deployed. Engaging hostile perimeter.",
	&"barricade_breach": "// AI COMMAND: Obstruction cleared. Advancing through flank corridor.",
	&"tier2_online": "// AI COMMAND: Tier-2 heavy production facility online.",
	&"uplink_contest": "// AI COMMAND: Converging on Data Hyper-Uplink coordinates.",
	&"under_attack": "// AI COMMAND: Outpost integrity compromised. Redirecting defense.",
}

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

var planner: AIBuildPlanner = AIBuildPlannerScript.new()
var scout_intel: AIScoutIntel = AI_SCOUT_INTEL_SCRIPT.new()
var economy: AIEconomyManager = AI_ECONOMY_MANAGER_SCRIPT.new()
var army: AIArmyController = AI_ARMY_CONTROLLER_SCRIPT.new()

var army_state: ArmyState:
	get:
		return army.army_state if army != null else ArmyState.STAGING
	set(value):
		if army != null:
			army.army_state = value

var ai_elapsed: float = 0.0
var ai_difficulty: int = 1
var ai_playstyle: int = 0

var _decision_timer: float = 0.0
var _intel_scan_timer: float = 0.0
var _salvage_scan_timer: float = 0.0
var _last_transmission_ms: int = -999999
var _last_transmission_by_cat: Dictionary = {}


func _init() -> void:
	scout_intel.setup(self)
	economy.setup(self)
	army.setup(self)


func _ready() -> void:
	add_to_group("skirmish_ai")
	_load_faction_rosters()
	_apply_lobby_ai_profile()
	call_deferred("_setup_initial_rallies")


func _exit_tree() -> void:
	if scout_intel != null:
		scout_intel.ai = null
	if economy != null:
		economy.ai = null
	if army != null:
		army.ai = null


func _load_faction_rosters() -> void:
	var faction_data: FactionData = TeamManager.get_team_faction_data(int(ai_team)) if TeamManager != null else null
	planner.bind_faction(faction_data)
	economy.bind_from_planner(planner)


func _apply_lobby_ai_profile() -> void:
	if GameConfig == null:
		return
	if TeamManager != null and TeamManager.is_active_team(int(ai_team)):
		ai_difficulty = TeamManager.get_team_ai_difficulty(int(ai_team))
		ai_playstyle = TeamManager.get_team_ai_playstyle(int(ai_team))
	else:
		ai_difficulty = int(GameConfig.ai_difficulty)
		ai_playstyle = int(GameConfig.ai_playstyle)

	match ai_difficulty:
		int(GameConfig.AIDifficulty.RELAXED):
			decision_interval = 1.5
			target_worker_count = 4
			wave_squad_size = 6
			max_wave_interval = 64.0
			max_cloning_vats = 1
			scout_intel.next_scout_dispatch_time = 130.0
		int(GameConfig.AIDifficulty.BRUTAL):
			decision_interval = 0.7
			target_worker_count = 8
			wave_squad_size = 7
			max_wave_interval = 36.0
			max_cloning_vats = 3
			scout_intel.next_scout_dispatch_time = 55.0
		_:
			decision_interval = 1.0
			target_worker_count = 6
			wave_squad_size = 6
			max_wave_interval = 48.0
			max_cloning_vats = 2
			scout_intel.next_scout_dispatch_time = 75.0

	if ai_playstyle == int(GameConfig.AIPlaystyle.SWARM_RUSH):
		wave_squad_size = 5 if ai_difficulty != int(GameConfig.AIDifficulty.BRUTAL) else 6
		max_wave_interval *= 0.80
		max_cloning_vats = maxi(max_cloning_vats, 2)
	elif ai_playstyle == int(GameConfig.AIPlaystyle.SYNTHETICS_TECH):
		wave_squad_size = maxi(wave_squad_size + 1, 8)
		max_wave_interval *= 1.12


func _process(delta: float) -> void:
	if not enabled:
		return
	ai_elapsed += delta
	army.tick_timers(delta)
	_intel_scan_timer += delta
	_salvage_scan_timer += delta
	_decision_timer += delta
	if _decision_timer < maxf(0.25, decision_interval):
		return
	var tick_dt: float = _decision_timer
	_decision_timer = 0.0
	_run_decision_tick(tick_dt)


func _setup_initial_rallies() -> void:
	var core: Building = find_ai_command_core()
	if core == null:
		return
	var nearest_bio: ResourceNode = find_nearest_resource(core.global_position, &"biomass")
	if nearest_bio != null:
		core.set_rally_target(nearest_bio)
	army.compute_staging_point(core)
	army.sync_military_rallies()


func _run_decision_tick(tick_dt: float) -> void:
	var econ: EconomyManager = get_economy_manager()
	if econ == null:
		return
	var core: Building = find_ai_command_core()
	if core == null:
		return

	# Ensure staging anchor is initialized & nav-snapped, and recompute when expansion Nexus Vats complete.
	army.ensure_staging_anchor(core, count_constructed_command_cores())

	# 1. Fair vision-respecting intel update (every 1.5s)
	if _intel_scan_timer >= INTEL_SCAN_INTERVAL:
		_intel_scan_timer = 0.0
		scout_intel.update_scouted_intel()

	# 2. Safe SalvageCore contesting (throttled by difficulty)
	var salvage_interval: float = 6.0 if is_relaxed_difficulty() else 3.0
	if _salvage_scan_timer >= salvage_interval:
		_salvage_scan_timer = 0.0
		economy.collect_safe_salvage(core)

	# 3. Assign idle workers, harvesters, engineers, and resume unfinished sites
	economy.assign_idle_workers(core)
	economy.assign_idle_harvesters()
	economy.assign_idle_engineers()
	economy.resume_unfinished_buildings()

	var aggro_enabled: bool = MatchManager.is_aggro_ai_enabled(get_tree())
	if not aggro_enabled:
		return

	# 4. Sync production rally points, recover stalled combat units & fire combat abilities
	army.sync_military_rallies()
	army.recover_stalled_combat_units()
	army.trigger_combat_abilities()

	# 5. Economy, infrastructure, reactive production & Core Overclock macro
	economy.manage_economy_and_production(econ, core)
	economy.manage_overclock_macro()

	# 6. Early scouting dispatch
	scout_intel.manage_early_scouting(core)

	# 7. Explicit Army State Machine (DEFENDING / RETREATING / BREACHING / ATTACKING / STAGING) & Deploy micro
	army.tick_army_state_machine(core, tick_dt)
	army.manage_deploy_micro(tick_dt)


func get_debug_status_line() -> String:
	return army.get_debug_status_line(find_ai_command_core())


func sanitize_transmission_pos(world_pos: Vector2, is_neutral_objective: bool) -> Vector2:
	if is_neutral_objective:
		return world_pos
	if not is_inside_tree():
		return Vector2.INF
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog == null or not fog.fog_enabled or fog.is_world_pos_explored(world_pos):
		return world_pos
	return Vector2.INF


func try_emit_ai_transmission(category: StringName, safe_world_pos: Vector2 = Vector2.INF) -> void:
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


# =============================================================================
# SHARED QUERY HELPERS FOR AI SUBSYSTEMS
# =============================================================================

func is_military_production_building(b: Building) -> bool:
	return b != null and b.is_military_production_building()


func get_unit_power_weight(unit: Unit) -> float:
	if unit == null or not is_instance_valid(unit) or unit.data == null:
		return 0.0
	if unit.data.is_heavy_unit() or unit.data.has_tag(&"artillery"):
		return 3.0
	if unit.data.has_tag(&"anti_armor") or unit.data.has_tag(&"disruptor"):
		return 2.0
	if unit.data.has_tag(&"support"):
		return 1.5
	return 1.0


func find_ai_command_core() -> Building:
	for b: Building in get_team_buildings(ai_team):
		if b.is_command_hub():
			return b
	return null


func count_constructed_command_cores() -> int:
	var c: int = 0
	for b: Building in get_team_buildings(ai_team):
		if b.is_constructed and b.is_command_hub():
			c += 1
	return c


func get_team_buildings(target_team: Unit.Team) -> Array[Building]:
	var out: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if not b.is_destroyed and b.team == target_team:
				out.append(b)
	return out


func get_team_units(target_team: Unit.Team) -> Array[Unit]:
	var out: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node
			if not u.is_dead and not u.is_staffed and u.team == target_team:
				out.append(u)
	return out


func is_enemy_team(other_team: int) -> bool:
	if TeamManager != null:
		return TeamManager.are_enemies(int(ai_team), other_team)
	return other_team != int(ai_team)


func is_allied_team(other_team: int) -> bool:
	if TeamManager != null:
		return TeamManager.are_allies(int(ai_team), other_team)
	return other_team == int(ai_team)


func is_relaxed_difficulty() -> bool:
	return GameConfig != null and ai_difficulty == int(GameConfig.AIDifficulty.RELAXED)


func is_brutal_difficulty() -> bool:
	return GameConfig != null and ai_difficulty == int(GameConfig.AIDifficulty.BRUTAL)


func is_combat_unit(unit: Unit) -> bool:
	if unit == null or unit.data == null:
		return false
	return unit.data.is_combat_unit() and unit.data.move_speed > 0.0


func count_queued_unit_type(buildings: Array[Building], type_id: StringName) -> int:
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


func find_nearest_resource(origin: Vector2, res_type: StringName) -> ResourceNode:
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


func get_resources_near(origin: Vector2, res_type: StringName, max_radius: float) -> Array[ResourceNode]:
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


func pick_least_crowded_resource(worker_pos: Vector2, nodes: Array[ResourceNode]) -> ResourceNode:
	var best: ResourceNode = null
	var best_score: float = INF
	for rn: ResourceNode in nodes:
		if not is_instance_valid(rn) or rn.is_depleted():
			continue
		var assigned: int = 0
		for u: Unit in get_team_units(ai_team):
			if u.gather_component != null and u.gather_component.is_active() and u.gather_component.target_node == rn:
				assigned += 1
		var dist: float = worker_pos.distance_to(rn.global_position)
		var score: float = float(assigned) * 180.0 + dist
		if score < best_score:
			best_score = score
			best = rn
	return best


func nudge_units_out_of_building(building: Building) -> void:
	CommandRouter.nudge_units_out_of_building(building, arena_bounds)


func get_economy_manager() -> EconomyManager:
	return get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func get_command_router() -> CommandRouter:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("SelectionController/CommandRouter") as CommandRouter
