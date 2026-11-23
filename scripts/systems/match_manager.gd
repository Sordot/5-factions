class_name MatchManager
extends Node

signal match_ended(winner_team: int, stats: Dictionary)
signal aggro_ai_toggled(enabled: bool)

static var _global_aggro_ai_enabled: bool = true

@export var victory_on_command_core_loss: bool = true
@export var match_end_overlay_path: NodePath
@export var aggro_ai_enabled: bool = true

var match_elapsed: float = 0.0
var player_uplink_time: float = 0.0
var enemy_uplink_time: float = 0.0
var player_units_trained: int = 0
var player_units_lost: int = 0
var enemy_units_destroyed: int = 0
var enemy_structures_destroyed: int = 0

var is_match_over: bool = false
@export var sandbox_mode_active: bool = false

var _eval_timer: float = 0.0
var _tracked_buildings: Dictionary = {}
var _tracked_units: Dictionary = {}
var _tracked_prod: Dictionary = {}


func _ready() -> void:
	add_to_group("match_manager")
	if GameConfig != null and GameConfig.configured_from_menu:
		aggro_ai_enabled = GameConfig.aggro_ai_enabled
	_global_aggro_ai_enabled = aggro_ai_enabled
	call_deferred("_hook_initial_entities")
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev: InputEventKey = event
		if key_ev.pressed and not key_ev.echo and not key_ev.ctrl_pressed and not key_ev.alt_pressed and not key_ev.shift_pressed:
			if key_ev.keycode == KEY_F10 or key_ev.physical_keycode == KEY_F10 or event.is_action_pressed("debug_toggle_aggro_ai"):
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
			if b.is_core_hub or b.building_type_id == &"nexus_vat" or b.building_type_id == &"command_core":
				player_cores += 1
		elif b.team == Unit.Team.ENEMY:
			enemy_buildings += 1
			if b.is_core_hub or b.building_type_id == &"nexus_vat" or b.building_type_id == &"command_core":
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

	var zone: EncroachingZone = get_tree().get_first_node_in_group("encroaching_zone") as EncroachingZone
	if zone != null:
		zone.active = false

	var safe_duration: float = maxf(1.0, match_elapsed)
	var player_uplink_pct: float = clampf((player_uplink_time / safe_duration) * 100.0, 0.0, 100.0)
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
	}

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
	if b.production_component != null:
		_hook_production(b.production_component)


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


func _on_unit_died(unit: Unit) -> void:
	if is_match_over or unit == null:
		return
	if unit.team == Unit.Team.PLAYER:
		player_units_lost += 1
	elif unit.team == Unit.Team.ENEMY:
		enemy_units_destroyed += 1


func _on_building_destroyed(building: Building) -> void:
	if building != null and building.team == Unit.Team.ENEMY and not is_match_over:
		enemy_structures_destroyed += 1
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
