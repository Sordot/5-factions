class_name GauntletModeController
extends Node

const BANNER_SCRIPT: GDScript = preload("res://ui/hud/mode_objective_banner.gd")

const INTRO_COUNTDOWN_SECONDS: float = 1.5

const SCENES: Dictionary = {
	&"clone_trooper": "res://scenes/units/clone_trooper.tscn",
	&"symbiote": "res://scenes/units/symbiote.tscn",
	&"lance_rig": "res://scenes/units/lance_rig.tscn",
	&"goliath_frame": "res://scenes/units/goliath_frame.tscn",
	&"chrysalis_mortar": "res://scenes/units/chrysalis_mortar.tscn",
	&"bulwark": "res://scenes/units/monolith_bulwark_automaton.tscn",
	&"rail_sentinel": "res://scenes/units/monolith_rail_sentinel.tscn",
	&"aegis_relay": "res://scenes/units/monolith_aegis_relay.tscn",
	&"anvil_walker": "res://scenes/units/monolith_anvil_siege_walker.tscn",
	&"dreadnought": "res://scenes/units/monolith_monolith_dreadnought.tscn",
	&"nexus_vat": "res://scenes/buildings/nexus_vat.tscn",
	&"defense_turret": "res://scenes/buildings/defense_turret.tscn",
	&"barricade": "res://scenes/world/destructible_barricade.tscn",
}

enum State {
	INTRO,
	RUNNING,
	ENDED,
}

var drill_id: StringName = GameConfig.DRILL_STUTTER_STEP
var state: State = State.INTRO

var _match_mgr: MatchManager = null
var _banner: ModeObjectiveBanner = null
var _intro_timer: float = INTRO_COUNTDOWN_SECONDS
var _elapsed: float = 0.0
var _time_limit: float = 60.0
var _ai_tick_timer: float = 0.0
var _ui_tick_timer: float = 0.0
var _player_units: Array[Unit] = []
var _enemy_units: Array[Unit] = []
var _target_building: Building = null
var _scene_cache: Dictionary = {}
var _drill_info: Dictionary = {}


func setup(match_mgr: MatchManager) -> void:
	_match_mgr = match_mgr
	add_to_group("gauntlet_mode_controller")
	if GameConfig != null:
		drill_id = GameConfig.selected_gauntlet_drill_id
		_drill_info = GameConfig.get_gauntlet_drill_info(drill_id)
		_time_limit = float(_drill_info.get("time_limit", 60.0))

	_disable_skirmish_ai_and_debug_panel()
	_spawn_banner()

	match drill_id:
		GameConfig.DRILL_STUTTER_STEP:
			_setup_stutter_step_drill()
		GameConfig.DRILL_SIEGE_BREACH:
			_setup_siege_breach_drill()
		_:
			_setup_optimal_boom_drill()

	state = State.INTRO
	_intro_timer = INTRO_COUNTDOWN_SECONDS
	_elapsed = 0.0
	_refresh_banner()


func _exit_tree() -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
		_banner = null


func _unhandled_input(event: InputEvent) -> void:
	if state == State.ENDED or event.is_echo():
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and kev.keycode == KEY_R:
			# In Drill 3 (Boom), require Ctrl+R so bare R never collides with Build Slot R.
			if drill_id == GameConfig.DRILL_OPTIMAL_BOOM:
				if kev.ctrl_pressed:
					get_viewport().set_input_as_handled()
					retry_drill()
			else:
				if not kev.alt_pressed:
					get_viewport().set_input_as_handled()
					retry_drill()


func retry_drill() -> void:
	if _match_mgr != null:
		_match_mgr.request_rematch()


func _disable_skirmish_ai_and_debug_panel() -> void:
	if not is_inside_tree():
		return
	for ai_node: Node in get_tree().get_nodes_in_group("skirmish_ai"):
		if is_instance_valid(ai_node):
			ai_node.set("enabled", false)
			ai_node.queue_free()
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var dbg: Node = scene_root.get_node_or_null("DebugHUD/SandboxDebugPanel")
		if dbg is Control:
			(dbg as Control).visible = false


func _clear_sandbox_arena_entities() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if b_node is Building and is_instance_valid(b_node):
			var b: Building = b_node as Building
			b.is_destroyed = true
			if SpatialGrid != null:
				SpatialGrid.unregister_building(b)
			if econ != null:
				econ.unregister_bandwidth_provider(b)
			b.queue_free()
	for u_node: Node in get_tree().get_nodes_in_group("units"):
		if u_node is Unit and is_instance_valid(u_node):
			var u: Unit = u_node as Unit
			u.is_dead = true
			if SpatialGrid != null:
				SpatialGrid.unregister_unit(u)
			if econ != null:
				econ.unregister_unit_bandwidth(u)
			u.queue_free()
	for bar_node: Node in get_tree().get_nodes_in_group("destructible_barricades"):
		if is_instance_valid(bar_node):
			if SpatialGrid != null:
				SpatialGrid.unregister_barricade(bar_node)
			bar_node.queue_free()

	# Hide sandbox resource nodes & hyper-uplink so combat drills are clean and readable
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var res_holder: Node = scene_root.get_node_or_null("ResourceNodes")
		if res_holder is Node2D:
			(res_holder as Node2D).visible = false
			for child: Node in res_holder.get_children():
				child.queue_free()
		var obj_holder: Node = scene_root.get_node_or_null("Objectives")
		if obj_holder is Node2D:
			(obj_holder as Node2D).visible = false
			for child: Node in obj_holder.get_children():
				child.queue_free()

	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog != null:
		fog.set_fog_enabled(false)

	if econ != null:
		econ.reset_economy()
		econ.set_team_starting_resources(int(Unit.Team.PLAYER), 0, 0, 0)


func _strip_enemy_only() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if b_node is Building and is_instance_valid(b_node):
			var b: Building = b_node as Building
			if int(b.team) != int(Unit.Team.PLAYER):
				b.is_destroyed = true
				if SpatialGrid != null:
					SpatialGrid.unregister_building(b)
				if econ != null:
					econ.unregister_bandwidth_provider(b)
				b.queue_free()
	for u_node: Node in get_tree().get_nodes_in_group("units"):
		if u_node is Unit and is_instance_valid(u_node):
			var u: Unit = u_node as Unit
			if int(u.team) != int(Unit.Team.PLAYER):
				u.is_dead = true
				if SpatialGrid != null:
					SpatialGrid.unregister_unit(u)
				if econ != null:
					econ.unregister_unit_bandwidth(u)
				u.queue_free()


func _setup_stutter_step_drill() -> void:
	_clear_sandbox_arena_entities()
	_player_units.clear()
	_enemy_units.clear()
	_target_building = null

	# Player GENESIS_V2 squad: 6x Clone Trooper + 2x Symbiote + 2x Lance-Rig
	var ct_positions: Array[Vector2] = [
		Vector2(-300.0, -72.0), Vector2(-300.0, 0.0), Vector2(-300.0, 72.0),
		Vector2(-350.0, -72.0), Vector2(-350.0, 0.0), Vector2(-350.0, 72.0),
	]
	for p: Vector2 in ct_positions:
		var u: Unit = _spawn_unit(&"clone_trooper", Unit.Team.PLAYER, p)
		if u != null:
			_player_units.append(u)
	for p: Vector2 in [Vector2(-410.0, -45.0), Vector2(-410.0, 45.0)]:
		var u: Unit = _spawn_unit(&"symbiote", Unit.Team.PLAYER, p)
		if u != null:
			_player_units.append(u)
	for p: Vector2 in [Vector2(-430.0, -115.0), Vector2(-430.0, 115.0)]:
		var u: Unit = _spawn_unit(&"lance_rig", Unit.Team.PLAYER, p)
		if u != null:
			_player_units.append(u)

	# Enemy MONOLITH_OS wave: 5x Bulwark Automaton
	for y_off: float in [-130.0, -65.0, 0.0, 65.0, 130.0]:
		var e: Unit = _spawn_unit(&"bulwark", Unit.Team.ENEMY, Vector2(320.0, y_off))
		if e != null:
			_enemy_units.append(e)

	_center_camera(Vector2.ZERO)
	call_deferred("_select_player_squad")


func _setup_siege_breach_drill() -> void:
	_clear_sandbox_arena_entities()
	_player_units.clear()
	_enemy_units.clear()
	_target_building = null

	# Player MONOLITH_OS breach force: 2x Dreadnought + 2x Anvil + 2x Rail-Sentinel + 2x Aegis Relay
	for p: Vector2 in [Vector2(-345.0, -44.0), Vector2(-345.0, 44.0)]:
		var u: Unit = _spawn_unit(&"dreadnought", Unit.Team.PLAYER, p)
		if u != null:
			_player_units.append(u)
	for p: Vector2 in [Vector2(-445.0, -78.0), Vector2(-445.0, 78.0)]:
		var u: Unit = _spawn_unit(&"anvil_walker", Unit.Team.PLAYER, p)
		if u != null:
			_player_units.append(u)
	for p: Vector2 in [Vector2(-415.0, -22.0), Vector2(-415.0, 22.0)]:
		var u: Unit = _spawn_unit(&"rail_sentinel", Unit.Team.PLAYER, p)
		if u != null:
			_player_units.append(u)
	for p: Vector2 in [Vector2(-495.0, -42.0), Vector2(-495.0, 42.0)]:
		var u: Unit = _spawn_unit(&"aegis_relay", Unit.Team.PLAYER, p)
		if u != null:
			_player_units.append(u)

	# Enemy GENESIS_V2 fortification
	_spawn_barricade(Vector2(-35.0, -70.0), PI * 0.5)
	_spawn_barricade(Vector2(-35.0, 70.0), PI * 0.5)

	_spawn_building(&"defense_turret", Unit.Team.ENEMY, Vector2(105.0, -105.0), false)
	_spawn_building(&"defense_turret", Unit.Team.ENEMY, Vector2(105.0, 105.0), false)
	_target_building = _spawn_building(&"nexus_vat", Unit.Team.ENEMY, Vector2(395.0, 0.0), true)

	for p: Vector2 in [Vector2(250.0, -115.0), Vector2(250.0, 115.0)]:
		var m: Unit = _spawn_unit(&"chrysalis_mortar", Unit.Team.ENEMY, p)
		if m != null:
			m.stance = Unit.Stance.HOLD_POSITION
			_enemy_units.append(m)
	for p: Vector2 in [Vector2(150.0, -38.0), Vector2(150.0, 38.0)]:
		var g: Unit = _spawn_unit(&"goliath_frame", Unit.Team.ENEMY, p)
		if g != null:
			g.stance = Unit.Stance.DEFENSIVE
			_enemy_units.append(g)
	for y_off: float in [-125.0, -75.0, -25.0, 25.0, 75.0, 125.0]:
		var ct: Unit = _spawn_unit(&"clone_trooper", Unit.Team.ENEMY, Vector2(55.0, y_off))
		if ct != null:
			ct.stance = Unit.Stance.DEFENSIVE
			_enemy_units.append(ct)

	var nav: Node = get_tree().get_first_node_in_group("arena_nav_region")
	if nav != null and nav.has_method("request_rebake"):
		nav.call("request_rebake")

	_center_camera(Vector2(-10.0, 0.0))
	call_deferred("_select_player_squad")


func _setup_optimal_boom_drill() -> void:
	_strip_enemy_only()
	_player_units.clear()
	_enemy_units.clear()
	_target_building = null


func _spawn_banner() -> void:
	if not is_inside_tree():
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	_banner = BANNER_SCRIPT.new() as ModeObjectiveBanner
	if _banner != null:
		_banner.name = "GauntletObjectiveBanner"
		_banner.action_button_pressed.connect(retry_drill)
		host.add_child(_banner)


func _select_player_squad() -> void:
	if not is_inside_tree() or _player_units.is_empty():
		return
	var sel: SelectionController = get_tree().get_first_node_in_group("selection_controller") as SelectionController
	if sel != null and sel.has_method("_set_selected_units"):
		var alive: Array[Unit] = []
		for u: Unit in _player_units:
			if is_instance_valid(u) and not u.is_dead:
				alive.append(u)
		if not alive.is_empty():
			sel.call("_set_selected_units", alive)


func _center_camera(world_pos: Vector2) -> void:
	if not is_inside_tree():
		return
	var cam: Node = get_tree().get_first_node_in_group("rts_camera")
	if cam != null and cam.has_method("center_on"):
		cam.call("center_on", world_pos)


func _process(delta: float) -> void:
	if _match_mgr == null or not is_inside_tree():
		return
	if state == State.ENDED or _match_mgr.is_match_over:
		if _banner != null:
			_banner.set_banner_visible(false)
		return
	if _banner != null:
		_banner.set_banner_visible(true)

	if state == State.INTRO:
		_intro_timer = maxf(0.0, _intro_timer - delta)
		if _intro_timer <= 0.0:
			state = State.RUNNING
			if AudioManager != null:
				AudioManager.play_sfx(&"uplink_captured", -5.0, 0.0)
			_tick_drill_enemy_ai()
		_refresh_banner()
		return

	_elapsed += delta

	match drill_id:
		GameConfig.DRILL_STUTTER_STEP:
			_process_stutter_step(delta)
		GameConfig.DRILL_SIEGE_BREACH:
			_process_siege_breach(delta)
		_:
			_process_optimal_boom()

	_ui_tick_timer += delta
	if _ui_tick_timer >= 0.12:
		_ui_tick_timer = 0.0
		_refresh_banner()


func _process_stutter_step(delta: float) -> void:
	_prune_squads()
	if _enemy_units.is_empty():
		_finish_combat_drill(true)
		return
	if _player_units.is_empty() or _elapsed >= _time_limit:
		_finish_combat_drill(false)
		return
	_ai_tick_timer += delta
	if _ai_tick_timer >= 0.65:
		_ai_tick_timer = 0.0
		_tick_drill_enemy_ai()


func _process_siege_breach(delta: float) -> void:
	_prune_squads()
	var vat_dead: bool = (_target_building == null or not is_instance_valid(_target_building) or _target_building.is_destroyed)
	if vat_dead:
		_finish_combat_drill(true)
		return
	if _player_units.is_empty() or _elapsed >= _time_limit:
		_finish_combat_drill(false)
		return
	_ai_tick_timer += delta
	if _ai_tick_timer >= 1.2:
		_ai_tick_timer = 0.0
		_tick_drill_enemy_ai()


func _process_optimal_boom() -> void:
	if _elapsed >= _time_limit:
		_finish_boom_drill()


func _tick_drill_enemy_ai() -> void:
	if drill_id == GameConfig.DRILL_STUTTER_STEP:
		if _player_units.is_empty():
			return
		var centroid: Vector2 = Vector2.ZERO
		for pu: Unit in _player_units:
			centroid += pu.global_position
		centroid /= float(_player_units.size())
		for eu: Unit in _enemy_units:
			if is_instance_valid(eu) and not eu.is_dead:
				eu.command_attack_move(centroid, false)
	elif drill_id == GameConfig.DRILL_SIEGE_BREACH:
		# Keep mortars engaging approaching siege force from range
		if _player_units.is_empty():
			return
		var closest_player: Unit = null
		var best_x: float = -INF
		for pu: Unit in _player_units:
			if pu.global_position.x > best_x:
				best_x = pu.global_position.x
				closest_player = pu
		if closest_player != null and best_x > -240.0:
			for eu: Unit in _enemy_units:
				if is_instance_valid(eu) and not eu.is_dead and eu.command_state == Unit.CommandState.IDLE:
					if eu.global_position.distance_to(closest_player.global_position) <= 460.0:
						eu.command_attack_target(closest_player, false)


func _prune_squads() -> void:
	var p_alive: Array[Unit] = []
	for u: Unit in _player_units:
		if is_instance_valid(u) and not u.is_dead and not u.is_queued_for_deletion():
			p_alive.append(u)
	_player_units = p_alive

	var e_alive: Array[Unit] = []
	for u: Unit in _enemy_units:
		if is_instance_valid(u) and not u.is_dead and not u.is_queued_for_deletion():
			e_alive.append(u)
	_enemy_units = e_alive


func _finish_combat_drill(succeeded: bool) -> void:
	state = State.ENDED
	if _banner != null:
		_banner.set_banner_visible(false)

	var survivors: int = _player_units.size()
	var medal: int = ModeRecords.Medal.NONE
	if succeeded:
		if drill_id == GameConfig.DRILL_STUTTER_STEP:
			if _elapsed <= 32.0 and survivors >= 7:
				medal = ModeRecords.Medal.GOLD
			elif _elapsed <= 45.0 and survivors >= 4:
				medal = ModeRecords.Medal.SILVER
			else:
				medal = ModeRecords.Medal.BRONZE
		else:
			if _elapsed <= 50.0 and survivors >= 5:
				medal = ModeRecords.Medal.GOLD
			elif _elapsed <= 70.0 and survivors >= 3:
				medal = ModeRecords.Medal.SILVER
			else:
				medal = ModeRecords.Medal.BRONZE

	var is_new_best: bool = false
	if succeeded:
		is_new_best = ModeRecords.record_gauntlet_result(drill_id, medal, _elapsed, true)

	var rec: Dictionary = ModeRecords.get_gauntlet_record(drill_id)
	var best_str: String = ("%.1fs (%s)" % [float(rec["best_value"]), ModeRecords.get_medal_label(int(rec["medal"]))]) if bool(rec.get("has_record", false)) else "--"
	var fail_reason: String = "Squad Eliminated" if _player_units.is_empty() else "Time Limit Expired"
	var result: Dictionary = {
		"mode": &"gauntlet",
		"drill_id": drill_id,
		"is_victory": succeeded,
		"title": "%s — %s" % [String(_drill_info.get("title", "DRILL")).to_upper(), ModeRecords.get_medal_label(medal) if succeeded else "FAILED"],
		"subtitle": ("Drill Completed!" if succeeded else fail_reason) + "  •  " + String(_drill_info.get("thresholds", "")),
		"medal": medal,
		"is_new_best": is_new_best,
		"can_continue_endless": false,
		"rows": [
			{"label": "Completion Time", "value": "%.1fs / %.0fs" % [_elapsed, _time_limit]},
			{"label": "Surviving Units", "value": str(survivors)},
			{"label": "Medal Earned", "value": ModeRecords.get_medal_label(medal) if succeeded else "FAILED"},
			{"label": "Personal Best", "value": best_str},
		],
	}
	_match_mgr.finish_special_mode(succeeded, result, false)


func _compute_boom_metrics() -> Dictionary:
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var total_gathered: int = 0
	if econ != null:
		var totals: Dictionary = econ.get_all_totals_gathered(int(Unit.Team.PLAYER))
		total_gathered = (
			int(totals.get(EconomyManager.RESOURCE_BIOMASS, 0))
			+ int(totals.get(EconomyManager.RESOURCE_SILICA, 0))
			+ int(totals.get(EconomyManager.RESOURCE_COMPUTE, 0))
		)

	var army_value: int = 0
	var worker_count: int = 0
	for u_node: Node in get_tree().get_nodes_in_group("units"):
		if not (u_node is Unit) or not is_instance_valid(u_node):
			continue
		var u: Unit = u_node as Unit
		if u.is_dead or u.is_queued_for_deletion() or int(u.team) != int(Unit.Team.PLAYER) or u.data == null:
			continue
		if u.data.is_combat_unit():
			army_value += maxi(0, u.data.biomass_cost) + maxi(0, u.data.silica_cost) + maxi(0, u.data.compute_cost)
		else:
			worker_count += 1

	var has_tier2: bool = false
	var t1_count: int = 0
	var t2_count: int = 0
	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (b_node is Building) or not is_instance_valid(b_node):
			continue
		var b: Building = b_node as Building
		if b.is_destroyed or b.is_queued_for_deletion() or int(b.team) != int(Unit.Team.PLAYER) or not b.is_constructed:
			continue
		if b.get_tech_tier() >= 2:
			has_tier2 = true
			t2_count += 1
		elif not b.is_command_hub():
			t1_count += 1

	var supply_blocked_s: float = 0.0
	if _match_mgr != null and _match_mgr.has_method("get_team_supply_blocked_seconds"):
		supply_blocked_s = float(_match_mgr.call("get_team_supply_blocked_seconds", int(Unit.Team.PLAYER)))

	var score: int = maxi(0, total_gathered + int(round(float(army_value) * 1.5)) - int(round(supply_blocked_s * 15.0)))
	var medal: int = ModeRecords.Medal.NONE
	if score >= 4200 and has_tier2:
		medal = ModeRecords.Medal.GOLD
	elif score >= 3000:
		medal = ModeRecords.Medal.SILVER
	elif score >= 1800:
		medal = ModeRecords.Medal.BRONZE

	return {
		"total_gathered": total_gathered,
		"army_value": army_value,
		"worker_count": worker_count,
		"t1_count": t1_count,
		"t2_count": t2_count,
		"has_tier2": has_tier2,
		"supply_blocked_s": supply_blocked_s,
		"score": score,
		"medal": medal,
	}


func _finish_boom_drill() -> void:
	state = State.ENDED
	if _banner != null:
		_banner.set_banner_visible(false)

	var m: Dictionary = _compute_boom_metrics()
	var score: int = int(m["score"])
	var medal: int = int(m["medal"])
	var succeeded: bool = medal > ModeRecords.Medal.NONE
	var is_new_best: bool = false
	if succeeded:
		is_new_best = ModeRecords.record_gauntlet_result(drill_id, medal, float(score), false)

	var rec: Dictionary = ModeRecords.get_gauntlet_record(drill_id)
	var best_str: String = ("%s pts (%s)" % [InspectionHelper.format_number(int(round(float(rec["best_value"])))), ModeRecords.get_medal_label(int(rec["medal"]))]) if bool(rec.get("has_record", false)) else "--"
	var result: Dictionary = {
		"mode": &"gauntlet",
		"drill_id": drill_id,
		"is_victory": succeeded,
		"title": "3-MINUTE BOOM — %s" % (ModeRecords.get_medal_label(medal) if succeeded else "BELOW BRONZE"),
		"subtitle": "GOLD >=4,200 + Tier 2  •  SILVER >=3,000  •  BRONZE >=1,800",
		"medal": medal,
		"is_new_best": is_new_best,
		"can_continue_endless": false,
		"rows": [
			{"label": "Macro Benchmark Score", "value": InspectionHelper.format_number(score)},
			{"label": "Resources Gathered", "value": InspectionHelper.format_number(int(m["total_gathered"]))},
			{"label": "Active Army Value (x1.5)", "value": InspectionHelper.format_number(int(m["army_value"]))},
			{"label": "Workers / T1 / T2 Online", "value": "%d / %d / %d%s" % [int(m["worker_count"]), int(m["t1_count"]), int(m["t2_count"]), " (T2 OK)" if bool(m["has_tier2"]) else " (No T2)"]},
			{"label": "Supply Blocked Penalty", "value": "-%d pts (%.0fs)" % [int(round(float(m["supply_blocked_s"]) * 15.0)), float(m["supply_blocked_s"])]},
			{"label": "Personal Best", "value": best_str},
		],
	}
	_match_mgr.finish_special_mode(succeeded, result, false)


func _refresh_banner() -> void:
	if _banner == null:
		return
	var retry_lbl: String = "[Ctrl+R] Retry" if drill_id == GameConfig.DRILL_OPTIMAL_BOOM else "[R] Retry"
	_banner.set_action_button(true, retry_lbl, Color(0.76, 0.90, 0.98, 0.95), "Restart this drill immediately")

	if state == State.INTRO:
		_banner.set_header(
			"DRILL: %s" % String(_drill_info.get("title", "GAUNTLET")).to_upper(),
			"READY %.1fs" % _intro_timer,
			Color(1.0, 0.84, 0.30, 1.0)
		)
		_banner.set_subtitle(String(_drill_info.get("summary", "")), Color(0.84, 0.94, 0.98, 0.94))
		_banner.set_progress(1.0 - (_intro_timer / INTRO_COUNTDOWN_SECONDS), Color(1.0, 0.84, 0.30, 1.0), true)
		return

	if drill_id == GameConfig.DRILL_STUTTER_STEP:
		var rem_t: float = maxf(0.0, _time_limit - _elapsed)
		var live_medal: int = ModeRecords.Medal.GOLD if (_elapsed <= 32.0 and _player_units.size() >= 7) else (ModeRecords.Medal.SILVER if (_elapsed <= 45.0 and _player_units.size() >= 4) else ModeRecords.Medal.BRONZE)
		var m_col: Color = ModeRecords.get_medal_color(live_medal)
		_banner.set_header(
			"STUTTER-STEP  •  BULWARKS: %d/5" % _enemy_units.size(),
			"%.1fs" % _elapsed,
			m_col
		)
		_banner.set_subtitle(
			"ALIVE: %d/10  •  TARGET: %s  •  LEFT: %.0fs" % [_player_units.size(), ModeRecords.get_medal_label(live_medal), rem_t],
			m_col.lerp(Color.WHITE, 0.25)
		)
		_banner.set_progress(1.0 - (_elapsed / _time_limit), m_col, true)
	elif drill_id == GameConfig.DRILL_SIEGE_BREACH:
		var rem_t2: float = maxf(0.0, _time_limit - _elapsed)
		var vat_pct: int = 0
		if _target_building != null and is_instance_valid(_target_building) and not _target_building.is_destroyed:
			vat_pct = int(round((_target_building.current_hp / maxf(1.0, _target_building.max_hp)) * 100.0))
		var live_m2: int = ModeRecords.Medal.GOLD if (_elapsed <= 50.0 and _player_units.size() >= 5) else (ModeRecords.Medal.SILVER if (_elapsed <= 70.0 and _player_units.size() >= 3) else ModeRecords.Medal.BRONZE)
		var m_col2: Color = ModeRecords.get_medal_color(live_m2)
		_banner.set_header(
			"SIEGE BREACH  •  NEXUS VAT: %d%%" % vat_pct,
			"%.1fs" % _elapsed,
			m_col2
		)
		_banner.set_subtitle(
			"ALIVE: %d/8  •  TARGET: %s  •  LEFT: %.0fs" % [_player_units.size(), ModeRecords.get_medal_label(live_m2), rem_t2],
			m_col2.lerp(Color.WHITE, 0.25)
		)
		_banner.set_progress(1.0 - (_elapsed / _time_limit), m_col2, true)
	else:
		var m: Dictionary = _compute_boom_metrics()
		var score: int = int(m["score"])
		var cur_medal: int = int(m["medal"])
		var m_col3: Color = ModeRecords.get_medal_color(cur_medal) if cur_medal > ModeRecords.Medal.NONE else Color(0.46, 0.88, 1.0, 1.0)
		var rem_s: int = maxi(0, int(ceil(_time_limit - _elapsed)))
		var mm: int = rem_s / 60
		var ss: int = rem_s % 60
		_banner.set_header(
			"3-MIN BOOM  •  SCORE: %s" % InspectionHelper.format_number(score),
			"%02d:%02d" % [mm, ss],
			m_col3
		)
		var t2_str: String = "T2: OK" if bool(m["has_tier2"]) else "T2: NEEDED"
		_banner.set_subtitle(
			"PACE: %s  •  %s  •  ARMY: %s  •  SB: %.0fs" % [
				ModeRecords.get_medal_label(cur_medal),
				t2_str,
				InspectionHelper.format_number(int(m["army_value"])),
				float(m["supply_blocked_s"]),
			],
			m_col3.lerp(Color.WHITE, 0.22)
		)
		_banner.set_progress(clampf(float(score) / 4200.0, 0.0, 1.0), m_col3, true)


func _spawn_unit(key: StringName, team_val: Unit.Team, pos: Vector2) -> Unit:
	var packed: PackedScene = _load_scene(key)
	if packed == null or not is_inside_tree():
		return null
	var scene_root: Node = get_tree().current_scene
	var parent_n: Node = scene_root.get_node_or_null("Units") if scene_root != null else null
	if parent_n == null:
		parent_n = scene_root if scene_root != null else self
	var inst: Node = packed.instantiate()
	if inst is Unit:
		var u: Unit = inst as Unit
		u.team = team_val
		u.global_position = pos
		parent_n.add_child(u)
		return u
	inst.queue_free()
	return null


func _spawn_building(key: StringName, team_val: Unit.Team, pos: Vector2, is_hub: bool) -> Building:
	var packed: PackedScene = _load_scene(key)
	if packed == null or not is_inside_tree():
		return null
	var scene_root: Node = get_tree().current_scene
	var parent_n: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if parent_n == null:
		parent_n = scene_root if scene_root != null else self
	var inst: Node = packed.instantiate()
	if inst is Building:
		var b: Building = inst as Building
		b.team = team_val
		b.is_constructed = true
		b.is_core_hub = is_hub
		b.global_position = pos
		parent_n.add_child(b)
		return b
	inst.queue_free()
	return null


func _spawn_barricade(pos: Vector2, rot_rad: float) -> void:
	var packed: PackedScene = _load_scene(&"barricade")
	if packed == null or not is_inside_tree():
		return
	var scene_root: Node = get_tree().current_scene
	var parent_n: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if parent_n == null:
		parent_n = scene_root if scene_root != null else self
	var inst: Node = packed.instantiate()
	if inst is DestructibleBarricade:
		var bar: DestructibleBarricade = inst as DestructibleBarricade
		bar.global_position = pos
		bar.rotation = rot_rad
		bar.max_hp = 520.0
		parent_n.add_child(bar)
	else:
		inst.queue_free()


func _load_scene(key: StringName) -> PackedScene:
	if _scene_cache.has(key):
		return _scene_cache[key] as PackedScene
	var path: String = String(SCENES.get(key, ""))
	if path.is_empty():
		return null
	var packed: PackedScene = load(path) as PackedScene
	_scene_cache[key] = packed
	return packed
