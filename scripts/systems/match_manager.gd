class_name MatchManager
extends Node

const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
const SKIRMISH_AI_SCRIPT_PATH: String = "res://scripts/systems/skirmish_ai.gd"
const SPEED_PRESETS: Array = [0.5, 1.0, 1.5, 2.0]
const ALERT_REGION_RADIUS: float = 300.0
const ALERT_DAMAGE_THROTTLE_S: float = 4.0
const MAX_RECENT_ALERTS: int = 3
const TIMELINE_SAMPLE_INTERVAL: float = 5.0

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

var match_elapsed: float = 0.0
var player_uplink_time: float = 0.0
var enemy_uplink_time: float = 0.0
var alliance_uplink_times: Dictionary = {}
var _uplink_milestones_announced: Dictionary = {}
var _alliance_uplink_rep_team: Dictionary = {}
var player_units_trained: int = 0
var enemy_units_trained: int = 0
var player_units_lost: int = 0
var enemy_units_destroyed: int = 0
var player_buildings_built: int = 0
var enemy_buildings_built: int = 0
var player_buildings_lost: int = 0
var enemy_structures_destroyed: int = 0
var player_peak_bandwidth: int = 0
var enemy_peak_bandwidth: int = 0

var is_match_over: bool = false
var is_inspecting_post_match: bool = false
@export var sandbox_mode_active: bool = false

var _eval_timer: float = 0.0
var _tracked_buildings: Dictionary = {}
var _tracked_units: Dictionary = {}
var _tracked_prod: Dictionary = {}
var _team_stats: Dictionary = {}
var _team_last_core_pos: Dictionary = {}
var _spawn_anchors: Dictionary = {}
var _eliminated_teams: Dictionary = {}
var _recent_alerts: Array[Dictionary] = []
var _damage_alert_log: Array[Dictionary] = []
var _event_dedupe_times: Dictionary = {}
var _pause_menu: PauseMenu = null
var current_game_speed: float = 1.0
var timeline_samples: Array[Dictionary] = []
var _timeline_sample_timer: float = 0.0
var combat_heatmap_events: Array[Dictionary] = []
var _heatmap_damage_throttle: Dictionary = {}
var _macro_sample_timer: float = 0.0
var _battle_heatmap_overlay: Node2D = null
var _spectator_comparison_bar: CanvasLayer = null
var _special_mode_controller: Node = null

const BATTLE_HEATMAP_OVERLAY_SCRIPT: GDScript = preload("res://ui/overlays/battle_heatmap_overlay.gd")
const SPECTATOR_BAR_SCENE_PATH: String = "res://ui/hud/spectator_comparison_bar.tscn"
const MATCH_END_OVERLAY_SCENE_PATH: String = "res://ui/hud/match_end_overlay.tscn"
const HOLDOUT_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/holdout_mode_controller.gd")
const GAUNTLET_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/gauntlet_mode_controller.gd")
const MAX_HEATMAP_EVENTS: int = 800


func _ready() -> void:
	add_to_group("match_manager")
	Engine.time_scale = 1.0
	current_game_speed = 1.0
	timeline_samples.clear()
	_timeline_sample_timer = 0.0
	_eliminated_teams.clear()
	_team_last_core_pos.clear()
	_event_dedupe_times.clear()
	if GameConfig != null and GameConfig.configured_from_menu:
		if GameConfig.is_special_mode():
			sandbox_mode_active = false
		aggro_ai_enabled = GameConfig.aggro_ai_enabled
		if TeamManager != null:
			TeamManager.configure_from_game_config()
	_init_team_stats()
	_global_aggro_ai_enabled = aggro_ai_enabled
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(true)
	call_deferred("_initialize_match_runtime")
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _init_team_stats() -> void:
	_team_stats.clear()
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	for tid: int in active_teams:
		_ensure_team_stat_bucket(tid)


func _ensure_team_stat_bucket(tid: int) -> Dictionary:
	if not _team_stats.has(tid):
		_team_stats[tid] = {
			"units_trained": 0,
			"units_lost": 0,
			"enemies_destroyed": 0,
			"buildings_built": 0,
			"buildings_lost": 0,
			"peak_bandwidth": 0,
			"uplink_seconds": 0.0,
			"supply_blocked_seconds": 0.0,
			"resource_float_sum": 0.0,
			"resource_float_samples": 0,
			"resources_lost_value": 0,
			"resources_destroyed_value": 0,
		}
	return _team_stats[tid] as Dictionary


func _initialize_match_runtime() -> void:
	if not is_inside_tree():
		return
	_ensure_pause_menu()
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
	_record_timeline_sample()
	if is_holdout or is_boom_drill or not is_gauntlet:
		_schedule_starting_worker_dispatch()
	if not is_gauntlet:
		_play_match_start_boot_sequence()


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
	if not _team_stats.has(tid):
		return 0.0
	return float((_team_stats[tid] as Dictionary).get("supply_blocked_seconds", 0.0))


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
	var veil: MatchBootVeil = MatchBootVeil.new()
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
	return _format_duration(match_elapsed)


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
		var bw: int = econ.get_bandwidth_used(tid)
		var bucket: Dictionary = _ensure_team_stat_bucket(tid)
		bucket["peak_bandwidth"] = maxi(int(bucket["peak_bandwidth"]), bw)
	player_peak_bandwidth = maxi(player_peak_bandwidth, econ.get_bandwidth_used(Unit.Team.PLAYER))
	enemy_peak_bandwidth = maxi(enemy_peak_bandwidth, econ.get_bandwidth_used(Unit.Team.ENEMY))


func _on_bandwidth_changed(team: int, used: int, _cap: int) -> void:
	if is_match_over:
		return
	var bucket: Dictionary = _ensure_team_stat_bucket(team)
	bucket["peak_bandwidth"] = maxi(int(bucket["peak_bandwidth"]), used)
	if team == int(Unit.Team.PLAYER):
		player_peak_bandwidth = maxi(player_peak_bandwidth, used)
	elif team == int(Unit.Team.ENEMY):
		enemy_peak_bandwidth = maxi(enemy_peak_bandwidth, used)


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
	if is_match_over or message.strip_edges().is_empty():
		return
	if not dedupe_key.is_empty():
		var now_s: float = float(Time.get_ticks_msec()) * 0.001
		if _event_dedupe_times.has(dedupe_key) and (now_s - float(_event_dedupe_times[dedupe_key])) < 2.2:
			return
		_event_dedupe_times[dedupe_key] = now_s
	tactical_event_logged.emit(category, message, world_pos, accent_color)


func push_tactical_alert(world_pos: Vector2, alert_type: StringName, message: String = "") -> void:
	if is_match_over:
		return
	var normalized_type: StringName = alert_type
	match alert_type:
		&"damage", &"under_attack":
			normalized_type = &"under_attack"
		&"uplink", &"uplink_contested":
			normalized_type = &"uplink_contested"
		&"construction", &"upgrade", &"tech_complete":
			normalized_type = &"tech_complete"

	var now_s: float = float(Time.get_ticks_msec()) * 0.001
	if normalized_type == &"under_attack" or normalized_type == &"uplink_contested":
		# Spatial + temporal throttling: suppress duplicate alerts of same type within 300px for 4.0s
		var kept: Array[Dictionary] = []
		var r_sq: float = ALERT_REGION_RADIUS * ALERT_REGION_RADIUS
		for item: Dictionary in _damage_alert_log:
			if now_s - float(item["time"]) < ALERT_DAMAGE_THROTTLE_S:
				kept.append(item)
				if item.get("type", &"") == normalized_type and (item["pos"] as Vector2).distance_squared_to(world_pos) <= r_sq:
					_damage_alert_log = kept
					return
		kept.append({"pos": world_pos, "type": normalized_type, "time": now_s})
		_damage_alert_log = kept

	var label: String = message
	if label.is_empty():
		match normalized_type:
			&"under_attack":
				label = "Forces Under Attack"
			&"uplink_contested":
				label = "Hyper-Uplink Alert"
			&"tech_complete":
				label = "Production / Tech Complete"
			_:
				label = "Tactical Alert"

	_recent_alerts.push_front({
		"pos": world_pos,
		"category": normalized_type,
		"message": label,
		"time": now_s,
	})
	while _recent_alerts.size() > MAX_RECENT_ALERTS:
		_recent_alerts.pop_back()

	if AudioManager != null and AudioManager.has_method("play_tactical_alert"):
		AudioManager.play_tactical_alert(normalized_type)
		if normalized_type == &"under_attack" and AudioManager.has_method("notify_combat_activity"):
			AudioManager.call("notify_combat_activity", 0.85)

	tactical_alert_triggered.emit(world_pos, normalized_type, label)
	tactical_alert_recorded.emit(world_pos, label)


func record_tactical_alert(world_pos: Vector2, category: StringName, message: String = "") -> void:
	push_tactical_alert(world_pos, category, message)


func get_recent_alerts() -> Array[Dictionary]:
	return _recent_alerts


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
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if uplink != null and uplink.controlling_team >= 0 and not uplink.is_contested:
		var ctrl_tid: int = uplink.controlling_team
		var bucket: Dictionary = _ensure_team_stat_bucket(ctrl_tid)
		bucket["uplink_seconds"] = float(bucket["uplink_seconds"]) + delta
		if ctrl_tid == int(Unit.Team.PLAYER):
			player_uplink_time += delta
		elif ctrl_tid == int(Unit.Team.ENEMY):
			enemy_uplink_time += delta

		var ally_id: int = uplink.controlling_alliance if uplink.controlling_alliance >= 0 else (TeamManager.get_team_alliance(ctrl_tid) if TeamManager != null else ctrl_tid)
		_alliance_uplink_rep_team[ally_id] = ctrl_tid
		var cur_ally_sec: float = float(alliance_uplink_times.get(ally_id, 0.0)) + delta
		alliance_uplink_times[ally_id] = cur_ally_sec
		if is_uplink_victory_enabled():
			_check_uplink_victory_progress(ally_id, ctrl_tid, cur_ally_sec, uplink.global_position)

	_timeline_sample_timer += delta
	if _timeline_sample_timer >= TIMELINE_SAMPLE_INTERVAL:
		_timeline_sample_timer -= TIMELINE_SAMPLE_INTERVAL
		_record_timeline_sample()

	_macro_sample_timer += delta
	if _macro_sample_timer >= 1.0:
		_macro_sample_timer -= 1.0
		_sample_macro_efficiency()

	_eval_timer += delta
	if _eval_timer >= 0.5:
		_eval_timer = 0.0
		evaluate_match_state()


func _record_timeline_sample(force_append: bool = false) -> void:
	if not is_inside_tree():
		return
	if not force_append and not timeline_samples.is_empty():
		var last_t: float = float(timeline_samples[timeline_samples.size() - 1].get("time", -1.0))
		if absf(match_elapsed - last_t) < 0.25:
			return
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var army_values: Dictionary = {}
	var unit_counts: Dictionary = {}
	for tid: int in active_teams:
		army_values[tid] = 0
		unit_counts[tid] = 0

	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var u: Unit = node
		if u.is_dead or u.is_queued_for_deletion():
			continue
		var tid: int = int(u.team)
		if not unit_counts.has(tid):
			unit_counts[tid] = 0
			army_values[tid] = 0
		unit_counts[tid] = int(unit_counts[tid]) + 1
		if u.data != null and u.data.is_combat_unit():
			var val: int = maxi(0, u.data.biomass_cost) + maxi(0, u.data.silica_cost) + maxi(0, u.data.compute_cost)
			army_values[tid] = int(army_values[tid]) + val

	var teams_snapshot: Dictionary = {}
	for tid: int in active_teams:
		var inc_rate: float = 0.0
		if econ != null:
			inc_rate = float(
				econ.get_income_rate_per_minute(tid, EconomyManager.RESOURCE_BIOMASS)
				+ econ.get_income_rate_per_minute(tid, EconomyManager.RESOURCE_SILICA)
				+ econ.get_income_rate_per_minute(tid, EconomyManager.RESOURCE_COMPUTE)
			)
		teams_snapshot[tid] = {
			"income_rate": inc_rate,
			"army_value": int(army_values.get(tid, 0)),
			"unit_count": int(unit_counts.get(tid, 0)),
		}

	timeline_samples.append({
		"time": match_elapsed,
		"teams": teams_snapshot,
	})


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
	var mask: int = int(_uplink_milestones_announced.get(ally_id, 0))
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
			_uplink_milestones_announced[ally_id] = mask
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
	for raw_a: Variant in alliance_uplink_times.keys():
		var a_id: int = int(raw_a)
		var sec_val: float = float(alliance_uplink_times[raw_a])
		if sec_val > lead_sec:
			lead_sec = sec_val
			lead_ally = a_id
			lead_team = int(_alliance_uplink_rep_team.get(a_id, a_id))

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
		"controlling_seconds": float(alliance_uplink_times.get(ctrl_ally, 0.0)) if ctrl_ally >= 0 else 0.0,
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
	_record_timeline_sample(true)
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
	var is_spectator: bool = TeamManager != null and TeamManager.is_spectator_mode()
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_local_win: bool = true if is_spectator else (
		TeamManager.are_allies(local_team, int(winner_team)) if (TeamManager != null and local_team >= 0) else (int(winner_team) == local_team)
	)

	var safe_duration: float = maxf(1.0, match_elapsed)
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var active_teams: Array[int] = TeamManager.get_active_teams() if TeamManager != null else [0, 1]
	var teams_stats_out: Dictionary = {}
	for tid: int in active_teams:
		var bucket: Dictionary = _ensure_team_stat_bucket(tid)
		var totals: Dictionary = econ.get_all_totals_gathered(tid) if econ != null else {}
		var up_s: float = float(bucket.get("uplink_seconds", 0.0))
		var up_pct: float = clampf((up_s / safe_duration) * 100.0, 0.0, 100.0)
		var sb_s: float = float(bucket.get("supply_blocked_seconds", 0.0))
		var flt_n: int = maxi(1, int(bucket.get("resource_float_samples", 0)))
		var avg_flt: int = int(round(float(bucket.get("resource_float_sum", 0.0)) / float(flt_n)))
		var lost_v: int = int(bucket.get("resources_lost_value", 0))
		var dest_v: int = int(bucket.get("resources_destroyed_value", 0))
		var trade_r: float = float(dest_v) / float(maxi(1, lost_v)) if (dest_v > 0 or lost_v > 0) else 1.0
		var m_grade: String = _compute_macro_grade(sb_s, safe_duration, avg_flt, trade_r)
		teams_stats_out[tid] = {
			"team_id": tid,
			"alliance_id": TeamManager.get_team_alliance(tid) if TeamManager != null else tid,
			"short_label": TeamManager.get_team_short_label(tid, true) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1)),
			"display_name": TeamManager.get_team_display_name(tid) if TeamManager != null else ("TEAM %d" % (tid + 1)),
			"color": TeamManager.get_team_color(tid) if TeamManager != null else Color(0.24, 0.96, 0.88, 1.0),
			"biomass_gathered": int(totals.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			"silica_gathered": int(totals.get(EconomyManager.RESOURCE_SILICA, 0)),
			"compute_gathered": int(totals.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			"units_trained": int(bucket.get("units_trained", 0)),
			"units_lost": int(bucket.get("units_lost", 0)),
			"enemies_destroyed": int(bucket.get("enemies_destroyed", 0)),
			"buildings_built": int(bucket.get("buildings_built", 0)),
			"buildings_lost": int(bucket.get("buildings_lost", 0)),
			"peak_bandwidth": int(bucket.get("peak_bandwidth", 0)),
			"uplink_seconds": up_s,
			"uplink_formatted": _format_duration(up_s),
			"uplink_pct": up_pct,
			"supply_blocked_seconds": sb_s,
			"supply_blocked_formatted": _format_duration(sb_s),
			"avg_unspent_float": avg_flt,
			"resources_lost_value": lost_v,
			"resources_destroyed_value": dest_v,
			"trade_ratio": trade_r,
			"macro_grade": m_grade,
		}

	var player_uplink_pct: float = clampf((player_uplink_time / safe_duration) * 100.0, 0.0, 100.0)
	var enemy_uplink_pct: float = clampf((enemy_uplink_time / safe_duration) * 100.0, 0.0, 100.0)
	var p_totals: Dictionary = econ.get_all_totals_gathered(Unit.Team.PLAYER) if econ != null else {}
	var e_totals: Dictionary = econ.get_all_totals_gathered(Unit.Team.ENEMY) if econ != null else {}

	var stats: Dictionary = {
		"winner_team": int(winner_team),
		"winner_label": winner_label,
		"is_victory": is_local_win,
		"is_spectator": is_spectator,
		"reason": reason,
		"duration_seconds": match_elapsed,
		"duration_formatted": _format_duration(match_elapsed),
		"uplink_control_pct": player_uplink_pct,
		"units_trained": player_units_trained,
		"units_lost": player_units_lost,
		"enemies_destroyed": enemy_units_destroyed,
		"structures_destroyed": enemy_structures_destroyed,
		"timeline_samples": timeline_samples.duplicate(true),
		"combat_heatmap_events": combat_heatmap_events.duplicate(true),
		"active_mutators": GameConfig.get_active_mutator_labels() if (GameConfig != null and GameConfig.has_method("get_active_mutator_labels")) else PackedStringArray(),
		"active_teams": active_teams,
		"teams": teams_stats_out,
		"player": {
			"biomass_gathered": int(p_totals.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			"silica_gathered": int(p_totals.get(EconomyManager.RESOURCE_SILICA, 0)),
			"compute_gathered": int(p_totals.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			"units_trained": player_units_trained,
			"units_lost": player_units_lost,
			"enemies_destroyed": enemy_units_destroyed,
			"buildings_built": player_buildings_built,
			"buildings_lost": player_buildings_lost,
			"peak_bandwidth": player_peak_bandwidth,
			"uplink_seconds": player_uplink_time,
			"uplink_formatted": _format_duration(player_uplink_time),
			"uplink_pct": player_uplink_pct,
		},
		"enemy": {
			"biomass_gathered": int(e_totals.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			"silica_gathered": int(e_totals.get(EconomyManager.RESOURCE_SILICA, 0)),
			"compute_gathered": int(e_totals.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			"units_trained": enemy_units_trained,
			"units_lost": enemy_units_destroyed,
			"enemies_destroyed": player_units_lost,
			"buildings_built": enemy_buildings_built,
			"buildings_lost": enemy_structures_destroyed,
			"peak_bandwidth": enemy_peak_bandwidth,
			"uplink_seconds": enemy_uplink_time,
			"uplink_formatted": _format_duration(enemy_uplink_time),
			"uplink_pct": enemy_uplink_pct,
		},
	}

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
	var tid: int = int(building.team)
	var bucket: Dictionary = _ensure_team_stat_bucket(tid)
	bucket["buildings_built"] = int(bucket["buildings_built"]) + 1
	if tid == int(Unit.Team.PLAYER):
		player_buildings_built += 1
	elif tid == int(Unit.Team.ENEMY):
		enemy_buildings_built += 1

	var is_notable_tech: bool = building.get_tech_tier() >= 2 or building.max_staff_slots > 0 or (building.is_military_production_building() and building.batch_production_count <= 1)
	if is_notable_tech:
		var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		var is_visible_to_feed: bool = viewer < 0 or (TeamManager.are_allies(viewer, tid) if TeamManager != null else (tid == viewer))
		if is_visible_to_feed:
			var tag: String = TeamManager.get_team_short_label(tid, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1))
			emit_tactical_event(&"economy", "%s %s Online" % [tag, building.display_name], building.global_position, Color(0.28, 0.96, 0.92, 1.0))


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
	var tid: int = int(unit.team)
	var bucket: Dictionary = _ensure_team_stat_bucket(tid)
	bucket["units_trained"] = int(bucket["units_trained"]) + 1
	if tid == int(Unit.Team.PLAYER):
		player_units_trained += 1
	elif tid == int(Unit.Team.ENEMY):
		enemy_units_trained += 1


func _on_unit_died(unit: Unit) -> void:
	if is_match_over or unit == null:
		return
	var tid: int = int(unit.team)
	var bucket: Dictionary = _ensure_team_stat_bucket(tid)
	bucket["units_lost"] = int(bucket["units_lost"]) + 1
	var u_val: int = 0
	if unit.data != null:
		u_val = maxi(0, unit.data.biomass_cost) + maxi(0, unit.data.silica_cost) + maxi(0, unit.data.compute_cost)
	bucket["resources_lost_value"] = int(bucket["resources_lost_value"]) + u_val
	var is_heavy_u: bool = unit.data != null and unit.data.is_heavy_unit()
	_push_heatmap_event(unit.global_position, 2.4 if is_heavy_u else 1.0, tid, &"heavy_unit_death" if is_heavy_u else &"unit_death")

	# Credit kill count & trade value to killer team (or opponent in 2-team matches)
	var active_teams: Array[int] = [0, 1]
	if TeamManager != null:
		active_teams = TeamManager.get_active_teams()
	var killer_tid: int = unit.last_attacker_team
	if killer_tid < 0 and active_teams.size() == 2:
		killer_tid = active_teams[1] if tid == active_teams[0] else active_teams[0]
	if killer_tid >= 0 and killer_tid != tid:
		var killer_b: Dictionary = _ensure_team_stat_bucket(killer_tid)
		killer_b["enemies_destroyed"] = int(killer_b["enemies_destroyed"]) + 1
		killer_b["resources_destroyed_value"] = int(killer_b["resources_destroyed_value"]) + u_val
	if tid == int(Unit.Team.PLAYER):
		player_units_lost += 1
	elif tid == int(Unit.Team.ENEMY):
		enemy_units_destroyed += 1

	# Log heavy unit losses in Tactical Event Feed
	if unit.data != null and unit.data.is_heavy_unit():
		var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
		var is_ally: bool = viewer >= 0 and (TeamManager.are_allies(viewer, tid) if TeamManager != null else (tid == viewer))
		if is_ally or viewer < 0 or unit.visible:
			var tag: String = TeamManager.get_team_short_label(tid, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1))
			var u_name: String = unit.data.display_name
			var col: Color = Color(1.0, 0.34, 0.28, 1.0) if is_ally else Color(1.0, 0.72, 0.28, 1.0)
			emit_tactical_event(&"combat", "%s %s Destroyed" % [tag, u_name], unit.global_position, col)


func _on_building_destroyed(building: Building) -> void:
	if building != null and not is_match_over:
		var tid: int = int(building.team)
		var bucket: Dictionary = _ensure_team_stat_bucket(tid)
		bucket["buildings_lost"] = int(bucket["buildings_lost"]) + 1
		var b_val: int = 150
		if building.building_data != null:
			b_val = maxi(0, building.building_data.biomass_cost) + maxi(0, building.building_data.silica_cost) + maxi(0, building.building_data.compute_cost)
		bucket["resources_lost_value"] = int(bucket["resources_lost_value"]) + b_val
		var active_teams_b: Array[int] = [0, 1]
		if TeamManager != null:
			active_teams_b = TeamManager.get_active_teams()
		var b_killer: int = building.last_attacker_team
		if b_killer < 0 and active_teams_b.size() == 2:
			b_killer = active_teams_b[1] if tid == active_teams_b[0] else active_teams_b[0]
		if b_killer >= 0 and b_killer != tid:
			var kb: Dictionary = _ensure_team_stat_bucket(b_killer)
			kb["resources_destroyed_value"] = int(kb["resources_destroyed_value"]) + b_val
		var is_hub_b: bool = building.is_command_hub()
		_push_heatmap_event(building.global_position, 4.5 if is_hub_b else 3.0, tid, &"hub_destroyed" if is_hub_b else &"building_destroyed")
		if tid == int(Unit.Team.ENEMY):
			enemy_structures_destroyed += 1
		elif tid == int(Unit.Team.PLAYER):
			player_buildings_lost += 1

		var is_major_bldg: bool = building.is_command_hub() or building.is_military_production_building() or building.max_staff_slots > 0 or building.has_turret
		if is_major_bldg:
			var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
			var is_ally: bool = viewer >= 0 and (TeamManager.are_allies(viewer, tid) if TeamManager != null else (tid == viewer))
			if is_ally or viewer < 0 or building.visible or building.is_command_hub():
				var tag: String = TeamManager.get_team_short_label(tid, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (tid + 1))
				var col: Color = Color(1.0, 0.30, 0.26, 1.0) if is_ally else Color(1.0, 0.72, 0.28, 1.0)
				emit_tactical_event(&"combat", "%s %s Destroyed!" % [tag, building.display_name], building.global_position, col)
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


func _format_duration(seconds: float) -> String:
	var total_s: int = maxi(0, int(floor(seconds)))
	var mins: int = total_s / 60
	var secs: int = total_s % 60
	return "%02d:%02d" % [mins, secs]


func record_combat_heatmap_damage(world_pos: Vector2, victim_team: int) -> void:
	if is_match_over or sandbox_mode_active:
		return
	var cx: int = int(floor(world_pos.x / 180.0))
	var cy: int = int(floor(world_pos.y / 180.0))
	var key: int = (cx + 2048) * 4096 + (cy + 2048)
	var last_t: float = float(_heatmap_damage_throttle.get(key, -10.0))
	if (match_elapsed - last_t) < 1.5:
		return
	_heatmap_damage_throttle[key] = match_elapsed
	_push_heatmap_event(world_pos, 0.45, victim_team, &"damage")


func _push_heatmap_event(world_pos: Vector2, weight: float, team_id: int, kind: StringName) -> void:
	if combat_heatmap_events.size() >= MAX_HEATMAP_EVENTS:
		# Merge into nearest low-weight damage sample to preserve memory cap cleanly
		for ev: Dictionary in combat_heatmap_events:
			if (ev.get("kind", &"") as StringName) == &"damage":
				var ep: Vector2 = ev.get("pos", Vector2.ZERO) as Vector2
				if ep.distance_squared_to(world_pos) <= 180.0 * 180.0:
					ev["weight"] = minf(3.0, float(ev["weight"]) + weight * 0.5)
					return
		if kind == &"damage":
			return
		combat_heatmap_events.pop_front()
	combat_heatmap_events.append({
		"pos": world_pos,
		"weight": weight,
		"team": team_id,
		"kind": kind,
	})


func _sample_macro_efficiency() -> void:
	if not is_inside_tree() or is_match_over or sandbox_mode_active:
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ == null:
		return
	var active_teams: Array[int] = [0, 1]
	if TeamManager != null:
		active_teams = TeamManager.get_active_teams()
	for tid: int in active_teams:
		if _eliminated_teams.has(tid):
			continue
		var bucket: Dictionary = _ensure_team_stat_bucket(tid)
		var bw_used: int = econ.get_bandwidth_used(tid)
		var bw_cap: int = econ.get_bandwidth_cap(tid)
		if bw_cap > 0 and bw_cap < 200 and bw_used >= bw_cap:
			bucket["supply_blocked_seconds"] = float(bucket["supply_blocked_seconds"]) + 1.0
		var res: Dictionary = econ.get_resources(tid)
		var total_flt: float = (
			float(res.get(EconomyManager.RESOURCE_BIOMASS, 0))
			+ float(res.get(EconomyManager.RESOURCE_SILICA, 0))
			+ float(res.get(EconomyManager.RESOURCE_COMPUTE, 0))
		)
		bucket["resource_float_sum"] = float(bucket["resource_float_sum"]) + total_flt
		bucket["resource_float_samples"] = int(bucket["resource_float_samples"]) + 1


func _compute_macro_grade(supply_blocked_s: float, match_dur_s: float, avg_float: int, trade_ratio: float) -> String:
	var blocked_pct: float = clampf(supply_blocked_s / maxf(1.0, match_dur_s), 0.0, 1.0)
	var supply_score: float = clampf(40.0 - blocked_pct * 200.0, 0.0, 40.0)
	var float_score: float = clampf(30.0 * (1.0 - maxf(0.0, float(avg_float - 350)) / 1250.0), 0.0, 30.0)
	var trade_score: float = clampf((trade_ratio / 1.45) * 30.0, 0.0, 30.0)
	var total: float = supply_score + float_score + trade_score
	if total >= 84.0:
		return "S"
	if total >= 72.0:
		return "A"
	if total >= 58.0:
		return "B"
	if total >= 42.0:
		return "C"
	return "D"


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
		_battle_heatmap_overlay.call("set_heatmap_events", combat_heatmap_events)
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


class MatchBootVeil extends Control:
	const TOTAL_DURATION: float = 1.20
	const VEIL_FADE_DURATION: float = 1.10
	const INPUT_UNLOCK_TIME: float = 0.25

	var banner_text: String = "// NEURAL LINK ONLINE"
	var accent_color: Color = Color(0.204, 0.827, 0.600, 1.0)
	var host_layer: CanvasLayer = null
	var _elapsed: float = 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		process_mode = Node.PROCESS_MODE_ALWAYS
		queue_redraw()

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= INPUT_UNLOCK_TIME and mouse_filter != Control.MOUSE_FILTER_IGNORE:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _elapsed >= TOTAL_DURATION:
			if host_layer != null and is_instance_valid(host_layer):
				host_layer.queue_free()
			else:
				queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var sz: Vector2 = size
		if sz.x <= 2.0 or sz.y <= 2.0:
			return
		var veil_t: float = clampf(_elapsed / VEIL_FADE_DURATION, 0.0, 1.0)
		var veil_alpha: float = 0.85 * pow(1.0 - veil_t, 2.2)
		if veil_alpha > 0.005:
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.06, 0.10, veil_alpha), true)

		# Crisp horizontal Technozen scanline sweep
		var scan_t: float = clampf(_elapsed / 0.88, 0.0, 1.0)
		if scan_t < 1.0:
			var scan_y: float = lerpf(-12.0, sz.y + 12.0, 1.0 - pow(1.0 - scan_t, 2.0))
			var scan_a: float = sin(scan_t * PI) * 0.68
			draw_rect(Rect2(0.0, scan_y - 10.0, sz.x, 12.0), Color(accent_color.r, accent_color.g, accent_color.b, scan_a * 0.14), true)
			draw_line(Vector2(0.0, scan_y), Vector2(sz.x, scan_y), Color(accent_color.r, accent_color.g, accent_color.b, scan_a), 1.6, true)

		# Slim centered terminal banner fading smoothly out over 1.2s
		var banner_fade: float = 1.0
		if _elapsed < 0.12:
			banner_fade = _elapsed / 0.12
		elif _elapsed > 0.72:
			banner_fade = clampf(1.0 - (_elapsed - 0.72) / (TOTAL_DURATION - 0.72), 0.0, 1.0)
		if banner_fade > 0.01:
			var font: Font = ThemeDB.fallback_font
			var font_size: int = 14
			var txt_sz: Vector2 = font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var pad_x: float = 28.0
			var box_w: float = txt_sz.x + pad_x * 2.0
			var box_h: float = 34.0
			var cx: float = sz.x * 0.5
			var cy: float = sz.y * 0.24
			var rect: Rect2 = Rect2(cx - box_w * 0.5, cy - box_h * 0.5, box_w, box_h)
			draw_rect(rect, Color(0.04, 0.08, 0.13, 0.82 * banner_fade), true)
			draw_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Color(accent_color.r, accent_color.g, accent_color.b, 0.92 * banner_fade), 1.6, true)
			draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Color(accent_color.r, accent_color.g, accent_color.b, 0.72 * banner_fade), 1.2, true)
			draw_string(font, Vector2(cx - txt_sz.x * 0.5, cy + txt_sz.y * 0.34), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.86, 0.98, 1.0, 0.96 * banner_fade))
