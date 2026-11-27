class_name MatchManager
extends Node

const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
const SKIRMISH_AI_SCRIPT_PATH: String = "res://scripts/systems/skirmish_ai.gd"
const SPEED_PRESETS: Array = [0.5, 1.0, 1.5, 2.0]
const ALERT_REGION_RADIUS: float = 300.0
const ALERT_DAMAGE_THROTTLE_S: float = 4.0
const MAX_RECENT_ALERTS: int = 3
const TIMELINE_SAMPLE_INTERVAL: float = 5.0
const SURGE_FIRST_DELAY: float = 165.0
const SURGE_INTERVAL: float = 180.0
const SURGE_DURATION: float = 45.0
const SURGE_MULTIPLIER: float = 2.0
const MAX_HEATMAP_EVENTS: int = 800

const MATCH_STATS_TRACKER_SCRIPT: GDScript = preload("res://scripts/systems/match_stats_tracker.gd")
const MATCH_ALERT_BUS_SCRIPT: GDScript = preload("res://scripts/systems/match_alert_bus.gd")
const MATCH_SURGE_DIRECTOR_SCRIPT: GDScript = preload("res://scripts/systems/match_surge_director.gd")
const MATCH_BOOT_VEIL_SCRIPT: GDScript = preload("res://ui/overlays/match_boot_veil.gd")
const BATTLE_HEATMAP_OVERLAY_SCRIPT: GDScript = preload("res://ui/overlays/battle_heatmap_overlay.gd")
const SPECTATOR_BAR_SCENE_PATH: String = "res://ui/hud/spectator_comparison_bar.tscn"
const MATCH_END_OVERLAY_SCENE_PATH: String = "res://ui/hud/match_end_overlay.tscn"
const HOLDOUT_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/holdout_mode_controller.gd")
const GAUNTLET_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/gauntlet_mode_controller.gd")
const OPTICAL_TETHER_SYSTEM_SCRIPT: GDScript = preload("res://scripts/systems/optical_tether_system.gd")
const OPTICAL_TETHER_OVERLAY_SCRIPT: GDScript = preload("res://ui/overlays/optical_tether_overlay.gd")

signal match_ended(winner_team: int, stats: Dictionary)
signal aggro_ai_toggled(enabled: bool)
signal tactical_alert_recorded(world_pos: Vector2, message: String)
signal tactical_alert_triggered(world_pos: Vector2, alert_type: StringName, message: String)
signal tactical_event_logged(category: StringName, message: String, world_pos: Vector2, accent_color: Color)
signal game_speed_changed(speed_scale: float)

static var _global_aggro_ai_enabled: bool = true

@export var victory_on_command_core_loss: bool = true
@export var match_end_overlay_path: NodePath
@export var aggro_ai_enabled: bool = true
@export var sandbox_mode_active: bool = false

var _stats: MatchStatsTracker = MATCH_STATS_TRACKER_SCRIPT.new()
var _alert_bus: MatchAlertBus = MATCH_ALERT_BUS_SCRIPT.new()
var _surge_director: MatchSurgeDirector = MATCH_SURGE_DIRECTOR_SCRIPT.new()

var match_elapsed: float = 0.0
var is_match_over: bool = false
var is_inspecting_post_match: bool = false
var current_game_speed: float = 1.0

var alliance_uplink_times: Dictionary:
	get:
		return _stats.alliance_uplink_times
	set(value):
		_stats.alliance_uplink_times = value

var timeline_samples: Array[Dictionary]:
	get:
		return _stats.timeline_samples
	set(value):
		_stats.timeline_samples = value

var combat_heatmap_events: Array[Dictionary]:
	get:
		return _stats.combat_heatmap_events
	set(value):
		_stats.combat_heatmap_events = value

var player_uplink_time: float:
	get:
		return _stats.player_uplink_time
	set(value):
		_stats.player_uplink_time = value

var enemy_uplink_time: float:
	get:
		return _stats.enemy_uplink_time
	set(value):
		_stats.enemy_uplink_time = value

var player_units_trained: int:
	get:
		return _stats.player_units_trained
	set(value):
		_stats.player_units_trained = value

var enemy_units_trained: int:
	get:
		return _stats.enemy_units_trained
	set(value):
		_stats.enemy_units_trained = value

var player_units_lost: int:
	get:
		return _stats.player_units_lost
	set(value):
		_stats.player_units_lost = value

var enemy_units_destroyed: int:
	get:
		return _stats.enemy_units_destroyed
	set(value):
		_stats.enemy_units_destroyed = value

var player_buildings_built: int:
	get:
		return _stats.player_buildings_built
	set(value):
		_stats.player_buildings_built = value

var enemy_buildings_built: int:
	get:
		return _stats.enemy_buildings_built
	set(value):
		_stats.enemy_buildings_built = value

var player_buildings_lost: int:
	get:
		return _stats.player_buildings_lost
	set(value):
		_stats.player_buildings_lost = value

var enemy_structures_destroyed: int:
	get:
		return _stats.enemy_structures_destroyed
	set(value):
		_stats.enemy_structures_destroyed = value

var player_peak_bandwidth: int:
	get:
		return _stats.player_peak_bandwidth
	set(value):
		_stats.player_peak_bandwidth = value

var enemy_peak_bandwidth: int:
	get:
		return _stats.enemy_peak_bandwidth
	set(value):
		_stats.enemy_peak_bandwidth = value

var _eval_timer: float = 0.0
var _timeline_sample_timer: float = 0.0
var _macro_sample_timer: float = 0.0
var _tracked_buildings: Dictionary = {}
var _tracked_units: Dictionary = {}
var _tracked_prod: Dictionary = {}
var _team_last_core_pos: Dictionary = {}
var _spawn_anchors: Dictionary = {}
var _eliminated_teams: Dictionary = {}
var _pause_menu: PauseMenu = null
var _battle_heatmap_overlay: Node2D = null
var _spectator_comparison_bar: CanvasLayer = null
var _special_mode_controller: Node = null


func _ready() -> void:
	add_to_group("match_manager")
	Engine.time_scale = 1.0
	current_game_speed = 1.0
	_timeline_sample_timer = 0.0
	_eliminated_teams.clear()
	_team_last_core_pos.clear()
	_alert_bus.reset()
	_surge_director.reset()
	if GameConfig != null and GameConfig.configured_from_menu:
		if GameConfig.is_special_mode():
			sandbox_mode_active = false
		aggro_ai_enabled = GameConfig.aggro_ai_enabled
		if TeamManager != null:
			TeamManager.configure_from_game_config()
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	_stats.init_teams(active_teams)
	_global_aggro_ai_enabled = aggro_ai_enabled
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(true)
	call_deferred("_initialize_match_runtime")
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _initialize_match_runtime() -> void:
	if not is_inside_tree():
		return
	_ensure_pause_menu()
	_ensure_optical_tether_system()
	var proc_gen: Node = get_tree().get_first_node_in_group("procedural_arena_generator")
	if proc_gen != null and is_instance_valid(proc_gen) and proc_gen.has_method("generate_arena"):
		proc_gen.call("generate_arena")
	var is_holdout: bool = GameConfig != null and GameConfig.is_holdout_mode()
	var is_gauntlet: bool = GameConfig != null and GameConfig.is_gauntlet_mode()
	var is_boom_drill: bool = is_gauntlet and GameConfig.selected_gauntlet_drill_id == GameConfig.DRILL_OPTIMAL_BOOM

	if is_holdout or is_boom_drill or not is_gauntlet:
		_bootstrap_skirmish_teams()
		_center_camera_on_local_base()

	if is_holdout:
		_start_holdout_controller()
	elif is_gauntlet:
		_start_gauntlet_controller()
	else:
		_ensure_ai_commanders()

	_hook_initial_entities()
	_hook_economy_manager()
	if not is_holdout and not is_gauntlet:
		_ensure_spectator_comparison_bar()
	_stats.record_timeline_sample(self)
	if is_holdout or is_boom_drill or not is_gauntlet:
		_schedule_starting_worker_dispatch()
	if not is_gauntlet:
		_play_match_start_boot_sequence()


func _ensure_optical_tether_system() -> void:
	if not is_inside_tree():
		return
	var host: Node = get_parent() if get_parent() != null else self
	if get_tree().get_first_node_in_group("optical_tether_system") == null:
		var sys: OpticalTetherSystem = OPTICAL_TETHER_SYSTEM_SCRIPT.new() as OpticalTetherSystem
		sys.name = "OpticalTetherSystem"
		host.add_child(sys)
	if get_tree().get_first_node_in_group("optical_tether_overlay") == null:
		var ov: OpticalTetherOverlay = OPTICAL_TETHER_OVERLAY_SCRIPT.new() as OpticalTetherOverlay
		ov.name = "OpticalTetherOverlay"
		host.add_child(ov)


func _start_holdout_controller() -> void:
	if _special_mode_controller != null and is_instance_valid(_special_mode_controller):
		_special_mode_controller.queue_free()
	var ctrl: HoldoutModeController = HOLDOUT_CONTROLLER_SCRIPT.new() as HoldoutModeController
	ctrl.name = "HoldoutModeController"
	add_child(ctrl)
	_special_mode_controller = ctrl
	ctrl.setup(self)


func _start_gauntlet_controller() -> void:
	if _special_mode_controller != null and is_instance_valid(_special_mode_controller):
		_special_mode_controller.queue_free()
	var ctrl: GauntletModeController = GAUNTLET_CONTROLLER_SCRIPT.new() as GauntletModeController
	ctrl.name = "GauntletModeController"
	add_child(ctrl)
	_special_mode_controller = ctrl
	ctrl.setup(self)


func is_special_mode_active() -> bool:
	return _special_mode_controller != null and is_instance_valid(_special_mode_controller)


func get_team_supply_blocked_seconds(tid: int) -> float:
	return _stats.get_team_supply_blocked_seconds(tid)


func finish_special_mode(is_victory: bool, result: Dictionary, pause_for_endless: bool = false) -> void:
	if is_match_over:
		return
	is_match_over = true
	reset_game_speed()
	if pause_for_endless and is_inside_tree():
		get_tree().paused = true
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(false)
	var sel_end: Node = get_tree().get_first_node_in_group("selection_controller") if is_inside_tree() else null
	if sel_end != null and is_instance_valid(sel_end) and sel_end.has_method("reset_command_cursors"):
		sel_end.call("reset_command_cursors")
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var overlay: Node = _get_end_overlay(true)
	if overlay != null and overlay.has_method("show_mode_summary"):
		overlay.call("show_mode_summary", result)


func resume_from_special_mode_pause() -> void:
	is_match_over = false
	if is_inside_tree():
		get_tree().paused = false
	var overlay: Node = _get_end_overlay(false)
	if overlay != null and overlay.has_method("hide_summary"):
		overlay.call("hide_summary")
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(true)


func continue_holdout_endless() -> void:
	if _special_mode_controller != null and is_instance_valid(_special_mode_controller) and _special_mode_controller.has_method("continue_endless"):
		_special_mode_controller.call("continue_endless")


func launch_next_gauntlet_drill() -> void:
	if GameConfig == null or not is_inside_tree():
		return
	var next_id: StringName = GameConfig.get_next_gauntlet_drill_id(GameConfig.selected_gauntlet_drill_id)
	var p_fac: StringName = GameConfig.selected_faction_id
	_prepare_clean_scene_transition()
	GameConfig.set_gauntlet_config(next_id, p_fac)
	get_tree().change_scene_to_file(GameConfig.selected_map_path)


func _is_sandbox_testbed_scene() -> bool:
	if sandbox_mode_active:
		return true
	if not is_inside_tree():
		return false
	var scene_path: String = ""
	if owner != null and not owner.scene_file_path.is_empty():
		scene_path = owner.scene_file_path
	elif get_tree().current_scene != null:
		scene_path = get_tree().current_scene.scene_file_path
	return scene_path.ends_with("milestone_0_test.tscn")


func _schedule_starting_worker_dispatch() -> void:
	if _is_sandbox_testbed_scene() or not is_inside_tree():
		return
	var timer: SceneTreeTimer = get_tree().create_timer(0.15)
	timer.timeout.connect(_dispatch_starting_workers_to_biomass, CONNECT_ONE_SHOT)


func _dispatch_starting_workers_to_biomass() -> void:
	if not is_inside_tree() or is_match_over or _is_sandbox_testbed_scene():
		return

	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	var all_biomass: Array[ResourceNode] = []
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if not rn.is_depleted() and not rn.is_vent and rn.resource_type == &"biomass":
				all_biomass.append(rn)
	if all_biomass.is_empty():
		return

	for tid: int in active_teams:
		var hub_pos: Vector2 = Vector2.INF
		if _team_last_core_pos.has(tid):
			hub_pos = _team_last_core_pos[tid] as Vector2
		else:
			for b_node: Node in get_tree().get_nodes_in_group("buildings"):
				if b_node is Building and is_instance_valid(b_node):
					var b: Building = b_node
					if not b.is_destroyed and int(b.team) == tid and b.is_command_hub():
						hub_pos = b.global_position
						break
		if hub_pos == Vector2.INF:
			continue

		var local_nodes: Array[ResourceNode] = []
		for rn: ResourceNode in all_biomass:
			if rn.global_position.distance_to(hub_pos) <= 560.0:
				local_nodes.append(rn)
		if local_nodes.is_empty():
			continue
		local_nodes.sort_custom(func(a: ResourceNode, b: ResourceNode) -> bool:
			return hub_pos.distance_squared_to(a.global_position) < hub_pos.distance_squared_to(b.global_position)
		)

		var idle_workers: Array[Unit] = []
		for u_node: Node in get_tree().get_nodes_in_group("units"):
			if not (u_node is Unit) or not is_instance_valid(u_node):
				continue
			var u: Unit = u_node
			if u.is_dead or u.is_staffed or u.is_queued_for_deletion() or u.data == null:
				continue
			var is_starting_worker: bool = u.data.has_tag(&"worker") or (u.data.can_gather and not u.data.auto_gather_on_spawn)
			if int(u.team) != tid or not is_starting_worker:
				continue
			if u.command_state != Unit.CommandState.IDLE or not u.command_queue.is_empty():
				continue
			idle_workers.append(u)
		if idle_workers.is_empty():
			continue

		var anchor_node: ResourceNode = local_nodes[0]
		for worker: Unit in idle_workers:
			var best_node: ResourceNode = ResourceNode.pick_best_cluster_node(anchor_node, worker, tid, 560.0, 950.0)
			if best_node == null:
				best_node = anchor_node
			best_node.assign_worker(worker)
			worker.command_gather(best_node, false)


func _bootstrap_skirmish_teams() -> void:
	if _is_sandbox_testbed_scene() or TeamManager == null or not is_inside_tree():
		return
	var active_teams: Array[int] = TeamManager.get_active_teams()
	var active_map: Dictionary = {}
	for tid: int in active_teams:
		active_map[tid] = true

	_spawn_anchors.clear()
	var preplaced_hubs: Dictionary = {} # tid -> Building
	var mutated_scene: bool = false

	# 1. Record corner anchors from pre-placed hubs and prune inactive teams' buildings.
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		var b_tid: int = int(b.team)
		if b.is_command_hub() and not _spawn_anchors.has(b_tid):
			_spawn_anchors[b_tid] = b.global_position
		if not active_map.has(b_tid):
			_remove_spawn_building(b)
			mutated_scene = true
		elif b.is_command_hub():
			_team_last_core_pos[b_tid] = b.global_position
			preplaced_hubs[b_tid] = b

	# 1b. Also scan procedural Marker2D spawn anchors when no pre-placed hubs exist.
	for anchor_node: Node in get_tree().get_nodes_in_group("spawn_anchors"):
		if anchor_node is Node2D and is_instance_valid(anchor_node) and anchor_node.has_meta("team_id"):
			var a_tid: int = int(anchor_node.get_meta("team_id"))
			if not _spawn_anchors.has(a_tid):
				_spawn_anchors[a_tid] = (anchor_node as Node2D).global_position

	# 2. Prune inactive teams' units.
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node
		if u.data != null and u.data.has_tag(&"dummy"):
			continue
		if not active_map.has(int(u.team)):
			_remove_spawn_unit(u)
			mutated_scene = true

	# 3. For each active team, ensure starting hub & loadout match its FactionData and seed resources.
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var is_fast_tech: bool = GameConfig != null and GameConfig.configured_from_menu and GameConfig.resource_preset == GameConfig.PRESET_FAST_TECH

	for tid: int in active_teams:
		var fac: FactionData = TeamManager.get_team_faction_data(tid)
		if fac == null:
			continue

		if econ != null and not is_fast_tech:
			econ.set_team_starting_resources(tid, fac.starting_biomass, fac.starting_silica, fac.starting_compute)

		var existing_hub: Building = preplaced_hubs.get(tid, null) as Building
		var desired_hub_path: String = fac.starting_hub_scene.resource_path if fac.starting_hub_scene != null else ""
		var hub_matches: bool = (
			existing_hub != null
			and is_instance_valid(existing_hub)
			and not desired_hub_path.is_empty()
			and existing_hub.scene_file_path == desired_hub_path
		)

		if not hub_matches and _spawn_anchors.has(tid):
			if fac.starting_hub_scene == null:
				push_error("MatchManager: Faction '%s' has null starting_hub_scene for team %d!" % [String(fac.faction_id), tid])
			else:
				var anchor: Vector2 = _spawn_anchors[tid] as Vector2
				_swap_team_starting_loadout(tid, anchor, fac)
				mutated_scene = true
		elif hub_matches and not fac.extra_starting_units.is_empty() and _spawn_anchors.has(tid):
			if not _team_has_combat_units(tid):
				var scene_root: Node = get_tree().current_scene
				var units_parent: Node = scene_root.get_node_or_null("Units") if scene_root != null else null
				if units_parent == null:
					units_parent = scene_root
				if units_parent != null:
					_spawn_extra_starting_units(tid, _spawn_anchors[tid] as Vector2, fac, units_parent)
					mutated_scene = true

	if mutated_scene:
		if econ != null:
			for tid: int in active_teams:
				econ.call_deferred("recalculate_bandwidth", tid)
		var nav_reg: Node = get_tree().get_first_node_in_group("arena_nav_region")
		if nav_reg != null and nav_reg.has_method("request_rebake"):
			nav_reg.call("request_rebake")
		var fog: Node = get_tree().get_first_node_in_group("fog_of_war")
		if fog != null and fog.has_method("invalidate_building_vision_cache"):
			fog.call("invalidate_building_vision_cache")


func _remove_spawn_building(b: Building) -> void:
	if SpatialGrid != null:
		SpatialGrid.unregister_building(b)
	b.is_destroyed = true
	if b.is_in_group("nav_bake_obstacles"):
		b.remove_from_group("nav_bake_obstacles")
	if b.is_in_group("buildings"):
		b.remove_from_group("buildings")
	b.queue_free()


func _remove_spawn_unit(u: Unit) -> void:
	if SpatialGrid != null:
		SpatialGrid.unregister_unit(u)
	u.is_dead = true
	if u.is_in_group("units"):
		u.remove_from_group("units")
	u.queue_free()


func _swap_team_starting_loadout(tid: int, anchor: Vector2, fac: FactionData) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		push_error("MatchManager: current_scene is null during _swap_team_starting_loadout for team %d." % tid)
		return
	if fac == null or fac.starting_hub_scene == null:
		push_error("MatchManager: Missing FactionData or starting_hub_scene for team %d." % tid)
		return

	# Instantiate replacement Command Hub BEFORE freeing pre-placed buildings so a load failure never leaves 0 hubs.
	var hub_inst: Node = fac.starting_hub_scene.instantiate()
	if hub_inst == null or not (hub_inst is Building):
		push_error("MatchManager: starting_hub_scene '%s' for faction '%s' failed to instantiate a Building!" % [fac.starting_hub_scene.resource_path, String(fac.faction_id)])
		if hub_inst != null:
			hub_inst.queue_free()
		return

	var bldgs_parent: Node = scene_root.get_node_or_null("Buildings")
	if bldgs_parent == null:
		bldgs_parent = scene_root
	var units_parent: Node = scene_root.get_node_or_null("Units")
	if units_parent == null:
		units_parent = scene_root

	# Snapshot & free placeholder pre-placed entities for this team before adding the new FactionData loadout.
	var old_buildings: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node) and int((node as Building).team) == tid:
			old_buildings.append(node as Building)
	for old_b: Building in old_buildings:
		_remove_spawn_building(old_b)

	var old_units: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node) and int((node as Unit).team) == tid:
			var u: Unit = node as Unit
			if u.data == null or not u.data.has_tag(&"dummy"):
				old_units.append(u)
	for old_u: Unit in old_units:
		_remove_spawn_unit(old_u)

	# Add replacement FactionData starting Command Hub
	var hub: Building = hub_inst as Building
	hub.team = tid as Unit.Team
	hub.is_constructed = true
	hub.is_core_hub = true
	hub.global_position = anchor
	bldgs_parent.add_child(hub)
	_team_last_core_pos[tid] = anchor
	if not hub.is_in_group("buildings") or not hub.is_command_hub() or hub.is_destroyed or hub.current_hp <= 0.0:
		push_error("MatchManager: Spawned hub '%s' for team %d failed post-add_child integrity check!" % [hub.display_name, tid])

	# Orient starting workers toward nearest Biomass cluster
	var bio_dir: Vector2 = (Vector2.ZERO - anchor).normalized()
	var best_bio_d_sq: float = INF
	for rn_node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if rn_node is ResourceNode and is_instance_valid(rn_node):
			var rn: ResourceNode = rn_node as ResourceNode
			if not rn.is_depleted() and not rn.is_vent and rn.resource_type == &"biomass":
				var d_sq: float = anchor.distance_squared_to(rn.global_position)
				if d_sq < best_bio_d_sq:
					best_bio_d_sq = d_sq
					bio_dir = (rn.global_position - anchor).normalized()
	var bio_perp: Vector2 = bio_dir.orthogonal()

	if fac.worker_scene != null and fac.starting_worker_count > 0:
		for i: int in range(fac.starting_worker_count):
			var w_inst: Node = fac.worker_scene.instantiate()
			if w_inst is Unit:
				var w: Unit = w_inst as Unit
				w.team = tid as Unit.Team
				var spread: float = (float(i) - float(fac.starting_worker_count - 1) * 0.5) * 52.0
				w.global_position = anchor + bio_dir * 96.0 + bio_perp * spread
				units_parent.add_child(w)
			else:
				w_inst.queue_free()

	# Instantiate optional extra_starting_units facing map center
	_spawn_extra_starting_units(tid, anchor, fac, units_parent)


func _team_has_combat_units(tid: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node as Unit
			if not u.is_dead and int(u.team) == tid and u.data != null and u.data.is_combat_unit():
				return true
	return false


func _spawn_extra_starting_units(tid: int, anchor: Vector2, fac: FactionData, units_parent: Node) -> void:
	var to_center: Vector2 = (Vector2.ZERO - anchor).normalized() if anchor.length_squared() > 1.0 else Vector2.RIGHT
	var c_perp: Vector2 = to_center.orthogonal()
	for idx: int in range(fac.extra_starting_units.size()):
		var extra_scene: PackedScene = fac.extra_starting_units[idx]
		if extra_scene == null:
			continue
		var u_inst: Node = extra_scene.instantiate()
		if u_inst is Unit:
			var eu: Unit = u_inst as Unit
			eu.team = tid as Unit.Team
			var lat: float = (float(idx) - float(fac.extra_starting_units.size() - 1) * 0.5) * 56.0
			eu.global_position = anchor + to_center * 175.0 + c_perp * lat
			units_parent.add_child(eu)
		else:
			u_inst.queue_free()


func _center_camera_on_local_base() -> void:
	if _is_sandbox_testbed_scene() or TeamManager == null or not is_inside_tree():
		return
	var cam: Node = get_tree().get_first_node_in_group("rts_camera")
	if cam == null or not cam.has_method("center_on"):
		return
	var local_team: int = TeamManager.get_local_human_team()
	if local_team < 0:
		var uplink: Node = get_tree().get_first_node_in_group("hyper_uplinks")
		var center_pt: Vector2 = (uplink as Node2D).global_position if (uplink is Node2D and is_instance_valid(uplink)) else Vector2.ZERO
		cam.call("center_on", center_pt)
		return
	if _team_last_core_pos.has(local_team):
		cam.call("center_on", _team_last_core_pos[local_team] as Vector2)


func _play_match_start_boot_sequence() -> void:
	if _is_sandbox_testbed_scene() or not is_inside_tree():
		return
	var host: Node = get_tree().current_scene
	if host == null:
		return
	if host.get_node_or_null("MatchBootOverlay") != null:
		return
	var is_spec: bool = TeamManager != null and TeamManager.is_spectator_mode()
	var banner: String = "// SPECTATOR LINK ONLINE"
	var accent_col: Color = Color(0.220, 0.741, 0.973, 1.0)
	if not is_spec:
		var local_tid: int = TeamManager.get_local_human_team() if TeamManager != null else 0
		var fac: FactionData = TeamManager.get_team_faction_data(local_tid) if (TeamManager != null and TeamManager.has_method("get_team_faction_data")) else null
		if fac != null:
			banner = fac.boot_banner_text if not fac.boot_banner_text.is_empty() else ("// NEURAL LINK ONLINE — %s" % fac.short_code)
			accent_col = fac.hud_accent_color
		else:
			banner = "// NEURAL LINK ONLINE"
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "MatchBootOverlay"
	layer.layer = 90
	var veil: MatchBootVeil = MATCH_BOOT_VEIL_SCRIPT.new() as MatchBootVeil
	veil.banner_text = banner
	veil.accent_color = accent_col
	veil.host_layer = layer
	layer.add_child(veil)
	host.add_child(layer)


func set_game_speed(speed_scale: float) -> void:
	if is_match_over:
		Engine.time_scale = 1.0
		current_game_speed = 1.0
		game_speed_changed.emit(1.0)
		return
	var clamped: float = clampf(speed_scale, 0.5, 2.0)
	current_game_speed = clamped
	if not get_tree().paused:
		Engine.time_scale = current_game_speed
	game_speed_changed.emit(current_game_speed)


func step_game_speed(delta_idx: int) -> void:
	var best_idx: int = 1
	var best_diff: float = INF
	for i: int in range(SPEED_PRESETS.size()):
		var d: float = absf(float(SPEED_PRESETS[i]) - current_game_speed)
		if d < best_diff:
			best_diff = d
			best_idx = i
	var next_idx: int = clampi(best_idx + delta_idx, 0, SPEED_PRESETS.size() - 1)
	set_game_speed(float(SPEED_PRESETS[next_idx]))


func reset_game_speed() -> void:
	current_game_speed = 1.0
	Engine.time_scale = 1.0
	game_speed_changed.emit(1.0)


func _ensure_ai_commanders() -> void:
	if sandbox_mode_active or TeamManager == null or not is_inside_tree():
		return
	var host: Node = get_tree().current_scene
	if host == null:
		return

	var ref_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)
	var nav: Node = get_tree().get_first_node_in_group("arena_nav_region")
	if nav != null and nav.get("arena_bounds") is Rect2:
		ref_bounds = nav.get("arena_bounds") as Rect2

	var existing_teams: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("skirmish_ai"):
		if not is_instance_valid(node):
			continue
		var tid: int = int(node.get("ai_team"))
		var b: Variant = node.get("arena_bounds")
		if b is Rect2 and nav == null:
			ref_bounds = b as Rect2
		var should_be_ai: bool = TeamManager.is_active_team(tid) and TeamManager.get_team_controller_type(tid) == TeamManager.ControllerType.AI
		if not should_be_ai or existing_teams.has(tid):
			node.set("enabled", false)
			node.queue_free()
			continue
		existing_teams[tid] = node
		node.set("arena_bounds", ref_bounds)
		if node.has_method("_load_faction_rosters"):
			node.call("_load_faction_rosters")
		if node.has_method("_apply_lobby_ai_profile"):
			node.call("_apply_lobby_ai_profile")

	var ai_script: GDScript = load(SKIRMISH_AI_SCRIPT_PATH) as GDScript
	if ai_script == null:
		return
	for tid: int in TeamManager.get_active_teams():
		if TeamManager.get_team_controller_type(tid) != TeamManager.ControllerType.AI:
			continue
		if existing_teams.has(tid):
			continue
		var ai_node: Node = ai_script.new()
		ai_node.name = "SkirmishAICommander_Team%d" % tid
		ai_node.set("ai_team", tid as Unit.Team)
		ai_node.set("arena_bounds", ref_bounds)
		host.add_child(ai_node)


func get_match_elapsed_seconds() -> float:
	return match_elapsed


func get_match_elapsed_formatted() -> String:
	return MatchStatsTracker.format_duration(match_elapsed)


func _hook_economy_manager() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ == null:
		return
	if not econ.bandwidth_changed.is_connected(_on_bandwidth_changed):
		econ.bandwidth_changed.connect(_on_bandwidth_changed)
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	for tid: int in active_teams:
		_stats.on_bandwidth_changed(tid, econ.get_bandwidth_used(tid))


func _on_bandwidth_changed(team: int, used: int, _cap: int) -> void:
	if is_match_over:
		return
	_stats.on_bandwidth_changed(team, used)


func _ensure_pause_menu() -> void:
	if not is_inside_tree():
		return
	var existing: Node = get_tree().get_first_node_in_group("pause_menu")
	if existing is PauseMenu:
		_pause_menu = existing as PauseMenu
		return
	var host: Node = get_tree().current_scene
	if host == null:
		return
	_pause_menu = PAUSE_MENU_SCENE.instantiate() as PauseMenu
	if _pause_menu != null:
		host.add_child(_pause_menu)


func emit_tactical_event(
	category: StringName,
	message: String,
	world_pos: Vector2,
	accent_color: Color = Color(0.28, 0.96, 0.92, 1.0),
	dedupe_key: String = ""
) -> void:
	_alert_bus.emit_tactical_event(self, category, message, world_pos, accent_color, dedupe_key)


func push_tactical_alert(world_pos: Vector2, alert_type: StringName, message: String = "") -> void:
	_alert_bus.push_tactical_alert(self, world_pos, alert_type, message)


func record_tactical_alert(world_pos: Vector2, category: StringName, message: String = "") -> void:
	_alert_bus.push_tactical_alert(self, world_pos, category, message)


func get_recent_alerts() -> Array[Dictionary]:
	return _alert_bus.get_recent_alerts()


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var ctrl_down: bool = Input.is_key_pressed(KEY_CTRL)
	var alt_down: bool = Input.is_key_pressed(KEY_ALT)
	var shift_down: bool = Input.is_key_pressed(KEY_SHIFT)
	if event is InputEventKey:
		var key_ev: InputEventKey = event
		if not key_ev.pressed:
			return
		ctrl_down = ctrl_down or key_ev.ctrl_pressed
		alt_down = alt_down or key_ev.alt_pressed
		shift_down = shift_down or key_ev.shift_pressed
	if not ctrl_down and not alt_down and not shift_down:
		if event.is_action_pressed("debug_toggle_aggro_ai"):
			toggle_aggro_ai()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("game_speed_down"):
			step_game_speed(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("game_speed_up"):
			step_game_speed(1)
			get_viewport().set_input_as_handled()
			return


static func is_aggro_ai_enabled(tree: SceneTree = null) -> bool:
	if tree != null:
		var mm: MatchManager = tree.get_first_node_in_group("match_manager") as MatchManager
		if mm != null and is_instance_valid(mm):
			return mm.aggro_ai_enabled
	return _global_aggro_ai_enabled


func set_aggro_ai_enabled(enabled: bool) -> void:
	if aggro_ai_enabled == enabled:
		_global_aggro_ai_enabled = enabled
		return
	aggro_ai_enabled = enabled
	_global_aggro_ai_enabled = enabled
	if not aggro_ai_enabled and is_inside_tree():
		_calm_idle_and_ai_units()
	aggro_ai_toggled.emit(aggro_ai_enabled)


func toggle_aggro_ai() -> bool:
	set_aggro_ai_enabled(not aggro_ai_enabled)
	return aggro_ai_enabled


func _calm_idle_and_ai_units() -> void:
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var u: Unit = node
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			continue
		var is_ai_unit: bool = TeamManager.get_team_controller_type(int(u.team)) == TeamManager.ControllerType.AI if TeamManager != null else (u.team == Unit.Team.ENEMY)
		if u.command_state == Unit.CommandState.IDLE:
			u.current_target = null
		elif is_ai_unit and (u.command_state == Unit.CommandState.ATTACK_MOVING or u.command_state == Unit.CommandState.ATTACKING_TARGET):
			u.command_stop()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(false)
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)


func _process(delta: float) -> void:
	if is_match_over or sandbox_mode_active:
		return

	match_elapsed += delta
	_surge_director.tick(self)
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if uplink != null and uplink.controlling_team >= 0 and not uplink.is_contested:
		var ctrl_tid: int = uplink.controlling_team
		var bucket: Dictionary = _stats.ensure_bucket(ctrl_tid)
		bucket["uplink_seconds"] = float(bucket["uplink_seconds"]) + delta
		if ctrl_tid == int(Unit.Team.PLAYER):
			_stats.player_uplink_time += delta
		elif ctrl_tid == int(Unit.Team.ENEMY):
			_stats.enemy_uplink_time += delta

		var ally_id: int = uplink.controlling_alliance if uplink.controlling_alliance >= 0 else (TeamManager.get_team_alliance(ctrl_tid) if TeamManager != null else ctrl_tid)
		_stats.alliance_uplink_rep_team[ally_id] = ctrl_tid
		var cur_ally_sec: float = float(_stats.alliance_uplink_times.get(ally_id, 0.0)) + delta
		_stats.alliance_uplink_times[ally_id] = cur_ally_sec
		if is_uplink_victory_enabled():
			_check_uplink_victory_progress(ally_id, ctrl_tid, cur_ally_sec, uplink.global_position)

	_timeline_sample_timer += delta
	if _timeline_sample_timer >= TIMELINE_SAMPLE_INTERVAL:
		_timeline_sample_timer -= TIMELINE_SAMPLE_INTERVAL
		_stats.record_timeline_sample(self)

	_macro_sample_timer += delta
	if _macro_sample_timer >= 1.0:
		_macro_sample_timer -= 1.0
		_stats.sample_macro_efficiency(self)

	_eval_timer += delta
	if _eval_timer >= 0.5:
		_eval_timer = 0.0
		evaluate_match_state()


func enter_sandbox_mode() -> void:
	if is_inspecting_post_match:
		_set_inspection_nodes_process_mode(Node.PROCESS_MODE_INHERIT)
		is_inspecting_post_match = false
	sandbox_mode_active = true
	is_match_over = false
	if is_inside_tree():
		get_tree().paused = false
		var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
		if fog != null:
			fog.set_post_match_reveal(false)
	var overlay: Node = _get_end_overlay()
	if overlay != null and overlay.has_method("hide_summary"):
		overlay.hide_summary()
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(true)


func enter_post_match_inspection() -> void:
	if not is_inside_tree():
		return
	is_inspecting_post_match = true
	Engine.time_scale = 1.0
	get_tree().paused = true

	var sel: SelectionController = get_tree().get_first_node_in_group("selection_controller") as SelectionController
	if sel != null:
		sel.clear_selection()
		sel.reset_command_cursors()
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	_set_inspection_nodes_process_mode(Node.PROCESS_MODE_ALWAYS)

	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog != null:
		fog.set_post_match_reveal(true)
	_ensure_battle_heatmap_overlay()
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(true)


func exit_post_match_inspection() -> void:
	if not is_inside_tree():
		return
	is_inspecting_post_match = false
	if _battle_heatmap_overlay != null and is_instance_valid(_battle_heatmap_overlay):
		_battle_heatmap_overlay.call("set_heatmap_visible", false)
	_set_inspection_nodes_process_mode(Node.PROCESS_MODE_INHERIT)
	var sel: SelectionController = get_tree().get_first_node_in_group("selection_controller") as SelectionController
	if sel != null:
		sel.clear_selection()
		sel.reset_command_cursors()
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(false)


func request_rematch() -> void:
	_prepare_clean_scene_transition()
	if is_inside_tree():
		get_tree().reload_current_scene()


func return_to_main_menu() -> void:
	_prepare_clean_scene_transition()
	if is_inside_tree():
		get_tree().change_scene_to_file(GameConfig.MAIN_MENU_SCENE)


func _prepare_clean_scene_transition() -> void:
	is_inspecting_post_match = false
	if _battle_heatmap_overlay != null and is_instance_valid(_battle_heatmap_overlay):
		_battle_heatmap_overlay.queue_free()
		_battle_heatmap_overlay = null
	if _spectator_comparison_bar != null and is_instance_valid(_spectator_comparison_bar):
		_spectator_comparison_bar.queue_free()
		_spectator_comparison_bar = null
	if _special_mode_controller != null and is_instance_valid(_special_mode_controller):
		_special_mode_controller.queue_free()
		_special_mode_controller = null
	_set_inspection_nodes_process_mode(Node.PROCESS_MODE_INHERIT)
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().paused = false
		var sel: Node = get_tree().get_first_node_in_group("selection_controller")
		if sel != null and is_instance_valid(sel) and sel.has_method("reset_command_cursors"):
			sel.call("reset_command_cursors")
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if VFXPool != null:
		VFXPool.clear_pool()
	if SpatialGrid != null and SpatialGrid.has_method("clear_all"):
		SpatialGrid.call("clear_all")


func _set_inspection_nodes_process_mode(mode: Node.ProcessMode) -> void:
	if not is_inside_tree():
		return
	var cam: Node = get_tree().get_first_node_in_group("rts_camera")
	if cam != null and is_instance_valid(cam):
		cam.process_mode = mode
	var minimap: Node = get_tree().get_first_node_in_group("tactical_minimap")
	if minimap != null and is_instance_valid(minimap):
		minimap.process_mode = mode
	var sel: Node = get_tree().get_first_node_in_group("selection_controller")
	if sel != null and is_instance_valid(sel):
		sel.process_mode = mode
	var root: Node = get_tree().current_scene
	if root != null:
		var sel_hud: Node = root.get_node_or_null("SelectionHUD")
		if sel_hud == null:
			sel_hud = root.find_child("SelectionHUD", true, false)
		if sel_hud != null and is_instance_valid(sel_hud):
			sel_hud.process_mode = mode
			if sel_hud.get_parent() is CanvasLayer:
				sel_hud.get_parent().process_mode = mode


func evaluate_match_state() -> void:
	if is_match_over or sandbox_mode_active or is_special_mode_active() or not is_inside_tree():
		return

	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	var team_cores: Dictionary = {}
	var team_buildings: Dictionary = {}
	for tid: int in active_teams:
		team_cores[tid] = 0
		team_buildings[tid] = 0

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion():
			continue
		var t: int = int(b.team)
		team_buildings[t] = int(team_buildings.get(t, 0)) + 1
		if b.is_command_hub():
			team_cores[t] = int(team_cores.get(t, 0)) + 1
			_team_last_core_pos[t] = b.global_position

	var surviving_alliances: Dictionary = {}
	for tid: int in active_teams:
		var b_cnt: int = int(team_buildings.get(tid, 0))
		var c_cnt: int = int(team_cores.get(tid, 0))
		var alive: bool = (c_cnt > 0 and b_cnt > 0) if victory_on_command_core_loss else (b_cnt > 0)
		if alive:
			var ally_id: int = TeamManager.get_team_alliance(tid) if TeamManager != null else tid
			if not surviving_alliances.has(ally_id):
				surviving_alliances[ally_id] = tid
		elif not _eliminated_teams.has(tid):
			_eliminated_teams[tid] = true
			if active_teams.size() > 2:
				var elim_pos: Vector2 = _team_last_core_pos.get(tid, Vector2.ZERO) as Vector2
				var elim_tag: String = TeamManager.get_team_short_label(tid, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("Team %d" % (tid + 1))
				emit_tactical_event(&"objective", "%s Eliminated!" % elim_tag, elim_pos, Color(1.0, 0.82, 0.28, 1.0))

	if surviving_alliances.size() <= 1:
		var winner_tid: int = 0
		if surviving_alliances.size() == 1:
			var first_key: Variant = surviving_alliances.keys()[0]
			winner_tid = int(surviving_alliances[first_key])
		var reason: String = "All Opposing Command Hubs Neutralized"
		if active_teams.size() <= 2:
			reason = "Hostile Command Hub Neutralized" if winner_tid == 0 else "Command Hub Destroyed"
		if TeamManager != null and TeamManager.is_spectator_mode():
			reason = "%s Achieved Total Domination" % _format_winner_label(winner_tid)
		_finish_match(winner_tid as Unit.Team, reason)


func is_uplink_victory_enabled() -> bool:
	if sandbox_mode_active or is_special_mode_active():
		return false
	if GameConfig != null:
		return GameConfig.uplink_victory_enabled
	return true


func get_uplink_victory_target_seconds() -> float:
	if GameConfig != null:
		return GameConfig.UPLINK_VICTORY_DURATION
	return 180.0


func _check_uplink_victory_progress(ally_id: int, ctrl_tid: int, cur_sec: float, uplink_pos: Vector2) -> void:
	var target_sec: float = maxf(10.0, get_uplink_victory_target_seconds())
	var ratio: float = cur_sec / target_sec
	var mask: int = int(_stats.uplink_milestones_announced.get(ally_id, 0))
	var local_t: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_local_ally: bool = local_t >= 0 and (TeamManager.are_allies(local_t, ctrl_tid) if TeamManager != null else (ctrl_tid == local_t))
	var team_tag: String = TeamManager.get_team_short_label(ctrl_tid, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (ctrl_tid + 1))
	var alert_col: Color = Color(1.0, 0.84, 0.24, 1.0) if is_local_ally else Color(1.0, 0.36, 0.28, 1.0)

	var thresholds: Array[Dictionary] = [
		{"bit": 1, "pct": 0.50, "rem": "1:30"},
		{"bit": 2, "pct": 0.75, "rem": "0:45"},
		{"bit": 4, "pct": 0.90, "rem": "0:18"},
	]
	for entry: Dictionary in thresholds:
		var bit: int = int(entry["bit"])
		if ratio >= float(entry["pct"]) and (mask & bit) == 0:
			mask |= bit
			_stats.uplink_milestones_announced[ally_id] = mask
			var rem_s: String = String(entry["rem"])
			var msg: String = "%s Uplink Victory in %s!" % [team_tag, rem_s]
			push_tactical_alert(uplink_pos, &"uplink_contested", msg)
			emit_tactical_event(&"objective", msg, uplink_pos, alert_col)

	if cur_sec >= target_sec:
		var reason: String = "%s Achieved Data Hyper-Uplink Sovereignty (03:00)" % _format_winner_label(ctrl_tid)
		_finish_match(ctrl_tid as Unit.Team, reason)


func get_uplink_victory_status() -> Dictionary:
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink if is_inside_tree() else null
	var target_s: float = get_uplink_victory_target_seconds()
	var lead_ally: int = -1
	var lead_team: int = -1
	var lead_sec: float = 0.0
	for raw_a: Variant in _stats.alliance_uplink_times.keys():
		var a_id: int = int(raw_a)
		var sec_val: float = float(_stats.alliance_uplink_times[raw_a])
		if sec_val > lead_sec:
			lead_sec = sec_val
			lead_ally = a_id
			lead_team = int(_stats.alliance_uplink_rep_team.get(a_id, a_id))

	var ctrl_team: int = uplink.controlling_team if (uplink != null and is_instance_valid(uplink)) else -1
	var ctrl_ally: int = uplink.controlling_alliance if (uplink != null and is_instance_valid(uplink)) else -1
	if ctrl_ally < 0 and ctrl_team >= 0:
		ctrl_ally = TeamManager.get_team_alliance(ctrl_team) if TeamManager != null else ctrl_team

	return {
		"has_uplink": uplink != null and is_instance_valid(uplink),
		"enabled": is_uplink_victory_enabled(),
		"target_seconds": target_s,
		"leading_alliance": lead_ally,
		"leading_team": lead_team,
		"leading_seconds": lead_sec,
		"controlling_alliance": ctrl_ally,
		"controlling_team": ctrl_team,
		"controlling_seconds": float(_stats.alliance_uplink_times.get(ctrl_ally, 0.0)) if ctrl_ally >= 0 else 0.0,
		"is_contested": uplink.is_contested if (uplink != null and is_instance_valid(uplink)) else false,
		"uplink_pos": uplink.global_position if (uplink != null and is_instance_valid(uplink)) else Vector2.ZERO,
	}


func _format_winner_label(winner_tid: int) -> String:
	if TeamManager == null:
		return "PLAYER COMMANDER" if winner_tid == 0 else "HOSTILE AI"
	var win_ally: int = TeamManager.get_team_alliance(winner_tid)
	var allies: PackedStringArray = PackedStringArray()
	for tid: int in TeamManager.get_active_teams():
		if TeamManager.get_team_alliance(tid) == win_ally:
			allies.append(TeamManager.get_team_short_label(tid, false))
	if allies.size() > 1:
		return "TEAM %s (%s)" % [TeamManager.get_alliance_letter(win_ally), " + ".join(allies)]
	return TeamManager.get_team_display_name(winner_tid)


func _finish_match(winner_team: Unit.Team, reason: String) -> void:
	if is_match_over:
		return
	_stats.record_timeline_sample(self, true)
	is_match_over = true
	reset_game_speed()

	# Reveal the battlefield and pause ALL active AI commanders behind the summary modal.
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog != null:
		fog.set_fog_enabled(false)

	for ai_node: Node in get_tree().get_nodes_in_group("skirmish_ai"):
		if is_instance_valid(ai_node):
			ai_node.set("enabled", false)

	var winner_label: String = _format_winner_label(int(winner_team))
	var stats: Dictionary = _stats.build_match_end_stats(self, winner_team, winner_label, reason)

	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(false)
	var sel_end: Node = get_tree().get_first_node_in_group("selection_controller") if is_inside_tree() else null
	if sel_end != null and is_instance_valid(sel_end) and sel_end.has_method("reset_command_cursors"):
		sel_end.call("reset_command_cursors")
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	match_ended.emit(int(winner_team), stats)

	var overlay: Node = _get_end_overlay()
	if overlay != null and overlay.has_method("show_summary"):
		overlay.show_summary(stats)


func _hook_initial_entities() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		_hook_building(node as Building)
	for node: Node in get_tree().get_nodes_in_group("units"):
		_hook_unit(node as Unit)


func _on_tree_node_added(node: Node) -> void:
	if node is Building:
		_hook_building(node as Building)
	elif node is Unit:
		_hook_unit(node as Unit)
	elif node is ProductionComponent:
		_hook_production(node as ProductionComponent)


func _hook_building(b: Building) -> void:
	if b == null:
		return
	var b_id: int = b.get_instance_id()
	if not _tracked_buildings.has(b_id):
		_tracked_buildings[b_id] = true
		if not b.destroyed.is_connected(_on_building_destroyed):
			b.destroyed.connect(_on_building_destroyed)
		if not b.construction_completed.is_connected(_on_building_construction_completed):
			b.construction_completed.connect(_on_building_construction_completed)
	if b.production_component != null:
		_hook_production(b.production_component)


func _on_building_construction_completed(building: Building) -> void:
	if is_match_over or building == null:
		return
	_stats.on_building_completed(self, building)


func _hook_production(prod: ProductionComponent) -> void:
	if prod == null:
		return
	var p_id: int = prod.get_instance_id()
	if _tracked_prod.has(p_id):
		return
	_tracked_prod[p_id] = true
	if not prod.unit_produced.is_connected(_on_unit_produced):
		prod.unit_produced.connect(_on_unit_produced)


func _hook_unit(u: Unit) -> void:
	if u == null:
		return
	var u_id: int = u.get_instance_id()
	if _tracked_units.has(u_id):
		return
	_tracked_units[u_id] = true
	if not u.died.is_connected(_on_unit_died):
		u.died.connect(_on_unit_died)


func _on_unit_produced(unit: Unit) -> void:
	if is_match_over or unit == null:
		return
	_stats.on_unit_produced(unit)


func _on_unit_died(unit: Unit) -> void:
	if is_match_over or unit == null:
		return
	_stats.on_unit_died(self, unit)


func _on_building_destroyed(building: Building) -> void:
	if building != null and not is_match_over:
		_stats.on_building_destroyed(self, building)
	evaluate_match_state()


func _get_end_overlay(create_if_missing: bool = false) -> Node:
	if not match_end_overlay_path.is_empty():
		var direct: Node = get_node_or_null(match_end_overlay_path)
		if direct != null:
			return direct
	if is_inside_tree():
		var found: Node = get_tree().get_first_node_in_group("match_end_overlay")
		if found != null:
			return found
		if create_if_missing:
			var packed: PackedScene = load(MATCH_END_OVERLAY_SCENE_PATH) as PackedScene
			if packed != null:
				var inst: Node = packed.instantiate()
				if inst != null:
					var scene_root: Node = get_tree().current_scene
					if scene_root != null:
						scene_root.add_child(inst)
					else:
						add_child(inst)
					return inst
	return null


func record_combat_heatmap_damage(world_pos: Vector2, victim_team: int) -> void:
	_stats.record_combat_heatmap_damage(self, world_pos, victim_team)


func _ensure_battle_heatmap_overlay() -> void:
	if not is_inside_tree():
		return
	if _battle_heatmap_overlay == null or not is_instance_valid(_battle_heatmap_overlay):
		var existing: Node2D = get_tree().get_first_node_in_group("battle_heatmap_overlay") as Node2D
		if existing != null:
			_battle_heatmap_overlay = existing
		else:
			_battle_heatmap_overlay = BATTLE_HEATMAP_OVERLAY_SCRIPT.new() as Node2D
			_battle_heatmap_overlay.name = "BattleHeatmapOverlay"
			var scene_root: Node = get_tree().current_scene
			if scene_root != null:
				scene_root.add_child(_battle_heatmap_overlay)
			else:
				add_child(_battle_heatmap_overlay)
	if _battle_heatmap_overlay != null and _battle_heatmap_overlay.has_method("set_heatmap_events"):
		_battle_heatmap_overlay.call("set_heatmap_events", _stats.combat_heatmap_events)
		_battle_heatmap_overlay.call("set_heatmap_visible", false)


func toggle_post_match_heatmap() -> bool:
	_ensure_battle_heatmap_overlay()
	if _battle_heatmap_overlay != null and _battle_heatmap_overlay.has_method("toggle_heatmap"):
		return bool(_battle_heatmap_overlay.call("toggle_heatmap"))
	return false


func is_post_match_heatmap_visible() -> bool:
	if _battle_heatmap_overlay != null and is_instance_valid(_battle_heatmap_overlay) and _battle_heatmap_overlay.has_method("is_heatmap_visible"):
		return bool(_battle_heatmap_overlay.call("is_heatmap_visible"))
	return false


func _ensure_spectator_comparison_bar() -> void:
	if not is_inside_tree() or sandbox_mode_active:
		return
	if TeamManager == null or not TeamManager.is_spectator_mode():
		return
	if _spectator_comparison_bar != null and is_instance_valid(_spectator_comparison_bar):
		return
	if get_tree().get_first_node_in_group("spectator_comparison_bar") != null:
		return
	var packed: PackedScene = load(SPECTATOR_BAR_SCENE_PATH) as PackedScene
	if packed == null:
		return
	_spectator_comparison_bar = packed.instantiate() as CanvasLayer
	if _spectator_comparison_bar != null:
		var scene_root: Node = get_tree().current_scene
		if scene_root != null:
			scene_root.add_child(_spectator_comparison_bar)
		else:
			add_child(_spectator_comparison_bar)
