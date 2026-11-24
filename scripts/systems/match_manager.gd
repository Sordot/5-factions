class_name MatchManager
extends Node

const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
const ALERT_REGION_RADIUS: float = 300.0
const ALERT_DAMAGE_THROTTLE_S: float = 4.0
const MAX_RECENT_ALERTS: int = 3

signal match_ended(winner_team: int, stats: Dictionary)
signal aggro_ai_toggled(enabled: bool)
signal tactical_alert_recorded(world_pos: Vector2, message: String)
signal tactical_alert_triggered(world_pos: Vector2, alert_type: StringName, message: String)

static var _global_aggro_ai_enabled: bool = true

@export var victory_on_command_core_loss: bool = true
@export var match_end_overlay_path: NodePath
@export var aggro_ai_enabled: bool = true

var match_elapsed: float = 0.0
var player_uplink_time: float = 0.0
var enemy_uplink_time: float = 0.0
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
@export var sandbox_mode_active: bool = false

var _eval_timer: float = 0.0
var _tracked_buildings: Dictionary = {}
var _tracked_units: Dictionary = {}
var _tracked_prod: Dictionary = {}
var _recent_alerts: Array[Dictionary] = []
var _damage_alert_log: Array[Dictionary] = []
var _pause_menu: PauseMenu = null


func _ready() -> void:
	add_to_group("match_manager")
	if GameConfig != null and GameConfig.configured_from_menu:
		aggro_ai_enabled = GameConfig.aggro_ai_enabled
	_global_aggro_ai_enabled = aggro_ai_enabled
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(true)
	call_deferred("_ensure_pause_menu")
	call_deferred("_hook_initial_entities")
	call_deferred("_hook_economy_manager")
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


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
	player_peak_bandwidth = maxi(player_peak_bandwidth, econ.get_bandwidth_used(Unit.Team.PLAYER))
	enemy_peak_bandwidth = maxi(enemy_peak_bandwidth, econ.get_bandwidth_used(Unit.Team.ENEMY))


func _on_bandwidth_changed(team: int, used: int, _cap: int) -> void:
	if is_match_over:
		return
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
		if u.command_state == Unit.CommandState.IDLE:
			u.current_target = null
		elif u.team == Unit.Team.ENEMY and (u.command_state == Unit.CommandState.ATTACK_MOVING or u.command_state == Unit.CommandState.ATTACKING_TARGET):
			u.command_stop()


func _exit_tree() -> void:
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(false)
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)


func _process(delta: float) -> void:
	if is_match_over or sandbox_mode_active:
		return

	match_elapsed += delta
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if uplink != null:
		if uplink.controlling_team == int(Unit.Team.PLAYER):
			player_uplink_time += delta
		elif uplink.controlling_team == int(Unit.Team.ENEMY):
			enemy_uplink_time += delta

	_eval_timer += delta
	if _eval_timer >= 0.5:
		_eval_timer = 0.0
		evaluate_match_state()


func enter_sandbox_mode() -> void:
	sandbox_mode_active = true
	is_match_over = false
	var overlay: Node = _get_end_overlay()
	if overlay != null and overlay.has_method("hide_summary"):
		overlay.hide_summary()
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(true)


func evaluate_match_state() -> void:
	if is_match_over or sandbox_mode_active or not is_inside_tree():
		return

	var player_cores: int = 0
	var player_buildings: int = 0
	var enemy_cores: int = 0
	var enemy_buildings: int = 0

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion():
			continue
		if b.team == Unit.Team.PLAYER:
			player_buildings += 1
			if b.is_core_hub or b.building_type_id == &"nexus_vat":
				player_cores += 1
		elif b.team == Unit.Team.ENEMY:
			enemy_buildings += 1
			if b.is_core_hub or b.building_type_id == &"nexus_vat":
				enemy_cores += 1

	var enemy_defeated: bool = (enemy_cores == 0) if victory_on_command_core_loss else (enemy_buildings == 0)
	if enemy_buildings == 0:
		enemy_defeated = true

	var player_defeated: bool = (player_cores == 0) if victory_on_command_core_loss else (player_buildings == 0)
	if player_buildings == 0:
		player_defeated = true

	if enemy_defeated:
		_finish_match(Unit.Team.PLAYER, "Hostile Nexus Vat Neutralized")
	elif player_defeated:
		_finish_match(Unit.Team.ENEMY, "Player Nexus Vat Destroyed")


func _finish_match(winner_team: Unit.Team, reason: String) -> void:
	if is_match_over:
		return
	is_match_over = true

	# Reveal the battlefield and pause active AI/zone pressure behind the summary modal.
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog != null:
		fog.set_fog_enabled(false)

	var ai: SkirmishAICommander = get_tree().get_first_node_in_group("skirmish_ai") as SkirmishAICommander
	if ai != null:
		ai.enabled = false

	var safe_duration: float = maxf(1.0, match_elapsed)
	var player_uplink_pct: float = clampf((player_uplink_time / safe_duration) * 100.0, 0.0, 100.0)
	var enemy_uplink_pct: float = clampf((enemy_uplink_time / safe_duration) * 100.0, 0.0, 100.0)
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var p_totals: Dictionary = econ.get_all_totals_gathered(Unit.Team.PLAYER) if econ != null else {}
	var e_totals: Dictionary = econ.get_all_totals_gathered(Unit.Team.ENEMY) if econ != null else {}
	var stats: Dictionary = {
		"winner_team": int(winner_team),
		"winner_label": "PLAYER COMMANDER" if winner_team == Unit.Team.PLAYER else "HOSTILE AI",
		"is_victory": winner_team == Unit.Team.PLAYER,
		"reason": reason,
		"duration_seconds": match_elapsed,
		"duration_formatted": _format_duration(match_elapsed),
		"uplink_control_pct": player_uplink_pct,
		"units_trained": player_units_trained,
		"units_lost": player_units_lost,
		"enemies_destroyed": enemy_units_destroyed,
		"structures_destroyed": enemy_structures_destroyed,
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
	if building.team == Unit.Team.PLAYER:
		player_buildings_built += 1
	elif building.team == Unit.Team.ENEMY:
		enemy_buildings_built += 1


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
	if unit.team == Unit.Team.PLAYER:
		player_units_trained += 1
	elif unit.team == Unit.Team.ENEMY:
		enemy_units_trained += 1


func _on_unit_died(unit: Unit) -> void:
	if is_match_over or unit == null:
		return
	if unit.team == Unit.Team.PLAYER:
		player_units_lost += 1
	elif unit.team == Unit.Team.ENEMY:
		enemy_units_destroyed += 1


func _on_building_destroyed(building: Building) -> void:
	if building != null and not is_match_over:
		if building.team == Unit.Team.ENEMY:
			enemy_structures_destroyed += 1
		elif building.team == Unit.Team.PLAYER:
			player_buildings_lost += 1
	evaluate_match_state()


func _get_end_overlay() -> Node:
	if not match_end_overlay_path.is_empty():
		var direct: Node = get_node_or_null(match_end_overlay_path)
		if direct != null:
			return direct
	if is_inside_tree():
		return get_tree().get_first_node_in_group("match_end_overlay")
	return null


func _format_duration(seconds: float) -> String:
	var total_s: int = maxi(0, int(floor(seconds)))
	var mins: int = total_s / 60
	var secs: int = total_s % 60
	return "%02d:%02d" % [mins, secs]
