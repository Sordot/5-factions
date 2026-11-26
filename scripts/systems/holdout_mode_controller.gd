class_name HoldoutModeController
extends Node

const BANNER_SCRIPT: GDScript = preload("res://ui/hud/mode_objective_banner.gd")
const SALVAGE_CORE_SCENE: PackedScene = preload("res://scenes/world/salvage_core.tscn")

const INITIAL_PREP_SECONDS: float = 35.0
const INTER_WAVE_PREP_SECONDS: float = 25.0
const PRE_WAVE_TELEGRAPH_SECONDS: float = 5.0
const TARGET_VICTORY_WAVE: int = 10

const EARLY_CALL_BIOMASS: int = 35
const EARLY_CALL_SILICA: int = 20

const UPLINK_DIVIDEND_BIOMASS: int = 60
const UPLINK_DIVIDEND_SILICA: int = 40
const UPLINK_DIVIDEND_COMPUTE: int = 25

const LANE_MAIN: Vector2 = Vector2(880.0, -530.0)
const LANE_NORTH: Vector2 = Vector2(-120.0, -820.0)
const LANE_SOUTH: Vector2 = Vector2(180.0, 810.0)

const UNIT_SCENES: Dictionary = {
	&"clone_trooper": "res://scenes/units/clone_trooper.tscn",
	&"stinger": "res://scenes/units/stinger.tscn",
	&"symbiote": "res://scenes/units/symbiote.tscn",
	&"lance_rig": "res://scenes/units/lance_rig.tscn",
	&"signal_jammer": "res://scenes/units/signal_jammer.tscn",
	&"goliath_frame": "res://scenes/units/goliath_frame.tscn",
	&"arc_lancer": "res://scenes/units/arc_lancer.tscn",
	&"chrysalis_mortar": "res://scenes/units/chrysalis_mortar.tscn",
	&"picket_drone": "res://scenes/units/monolith_picket_drone.tscn",
	&"bulwark": "res://scenes/units/monolith_bulwark_automaton.tscn",
	&"rail_sentinel": "res://scenes/units/monolith_rail_sentinel.tscn",
	&"aegis_relay": "res://scenes/units/monolith_aegis_relay.tscn",
	&"anvil_walker": "res://scenes/units/monolith_anvil_siege_walker.tscn",
	&"dreadnought": "res://scenes/units/monolith_monolith_dreadnought.tscn",
	&"null_grid": "res://scenes/units/monolith_null_grid_projector.tscn",
	&"votary": "res://scenes/units/prisma_votary.tscn",
	&"lumen_skiff": "res://scenes/units/prisma_lumen_skiff.tscn",
	&"cantor": "res://scenes/units/prisma_cantor.tscn",
	&"lens_adjudicator": "res://scenes/units/prisma_lens_adjudicator.tscn",
	&"prism_weaver": "res://scenes/units/prisma_prism_weaver.tscn",
	&"seraph_cruiser": "res://scenes/units/prisma_seraph_cruiser.tscn",
	&"solstice_lance": "res://scenes/units/prisma_solstice_lance.tscn",
}

enum State {
	PREP,
	ACTIVE_WAVE,
	VICTORY_PAUSED,
	ENDED,
}

var state: State = State.PREP
var current_wave: int = 0
var waves_cleared: int = 0
var endless_mode: bool = false

var _match_mgr: MatchManager = null
var _banner: ModeObjectiveBanner = null
var _prep_timer: float = INITIAL_PREP_SECONDS
var _prep_duration_max: float = INITIAL_PREP_SECONDS
var _telegraphed_wave: int = -1
var _wave_units: Array[Unit] = []
var _wave_initial_count: int = 0
var _ai_steer_timer: float = 0.0
var _ui_tick_timer: float = 0.0
var _defeat_check_timer: float = 0.0
var _scene_cache: Dictionary = {}
var _player_faction_id: StringName = &"genesis_v2"
var _enemy_faction_mode: StringName = &"monolith_os"
var _difficulty: int = int(GameConfig.AIDifficulty.STANDARD)
var _uplink_dividends_earned: int = 0
var _total_hostiles_defeated: int = 0


func setup(match_mgr: MatchManager) -> void:
	_match_mgr = match_mgr
	add_to_group("holdout_mode_controller")
	if GameConfig != null:
		_player_faction_id = GameConfig.selected_faction_id
		_enemy_faction_mode = GameConfig.holdout_enemy_faction_id
		_difficulty = int(GameConfig.holdout_difficulty)

	_strip_enemy_base_and_ai()
	_configure_holdout_uplink()
	_spawn_banner()

	state = State.PREP
	current_wave = 0
	waves_cleared = 0
	endless_mode = false
	_prep_timer = INITIAL_PREP_SECONDS
	_prep_duration_max = INITIAL_PREP_SECONDS
	_telegraphed_wave = -1
	_refresh_banner()

	if _match_mgr != null:
		_match_mgr.emit_tactical_event(
			&"objective",
			"UPLINK HOLDOUT: Fortify & Capture Hyper-Uplink! Wave 1 in 00:35.",
			Vector2.ZERO,
			Color(1.0, 0.80, 0.30, 1.0)
		)


func _exit_tree() -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
		_banner = null


func _strip_enemy_base_and_ai() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	for ai_node: Node in get_tree().get_nodes_in_group("skirmish_ai"):
		if is_instance_valid(ai_node):
			ai_node.set("enabled", false)
			ai_node.queue_free()

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


func _configure_holdout_uplink() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group("hyper_uplinks"):
		if node is HyperUplink and is_instance_valid(node):
			(node as HyperUplink).production_bonus_pct = 0.10


func _spawn_banner() -> void:
	if not is_inside_tree():
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	_banner = BANNER_SCRIPT.new() as ModeObjectiveBanner
	if _banner != null:
		_banner.name = "HoldoutObjectiveBanner"
		_banner.action_button_pressed.connect(call_wave_early)
		host.add_child(_banner)


func _process(delta: float) -> void:
	if _match_mgr == null or not is_inside_tree():
		return
	if state == State.ENDED or state == State.VICTORY_PAUSED or _match_mgr.is_match_over:
		if _banner != null:
			_banner.set_banner_visible(false)
		return
	if _banner != null:
		_banner.set_banner_visible(true)

	_defeat_check_timer += delta
	if _defeat_check_timer >= 0.35:
		_defeat_check_timer = 0.0
		if _is_player_defeated():
			_trigger_holdout_end(false)
			return

	match state:
		State.PREP:
			_prep_timer = maxf(0.0, _prep_timer - delta)
			var next_w: int = current_wave + 1
			if _prep_timer <= PRE_WAVE_TELEGRAPH_SECONDS and _telegraphed_wave != next_w:
				_telegraphed_wave = next_w
				_telegraph_incoming_wave(next_w)
			if _prep_timer <= 0.0:
				_spawn_next_wave()
		State.ACTIVE_WAVE:
			_prune_dead_wave_units()
			_ai_steer_timer += delta
			if _ai_steer_timer >= 1.0:
				_ai_steer_timer = 0.0
				_steer_wave_units()
			if _wave_units.is_empty():
				_on_wave_cleared()

	_ui_tick_timer += delta
	if _ui_tick_timer >= 0.15:
		_ui_tick_timer = 0.0
		_refresh_banner()


func call_wave_early() -> void:
	if state != State.PREP or _prep_timer <= 1.2:
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.add_resource(int(Unit.Team.PLAYER), EconomyManager.RESOURCE_BIOMASS, EARLY_CALL_BIOMASS, false)
		econ.add_resource(int(Unit.Team.PLAYER), EconomyManager.RESOURCE_SILICA, EARLY_CALL_SILICA, false)
	if AudioManager != null:
		AudioManager.play_sfx(&"build_complete", -4.0, 0.0)
	if _match_mgr != null:
		_match_mgr.emit_tactical_event(
			&"economy",
			"Early Wave Bonus: +%dB / +%dS" % [EARLY_CALL_BIOMASS, EARLY_CALL_SILICA],
			_get_player_hub_position(),
			Color(0.32, 0.98, 0.72, 1.0)
		)
	var next_w: int = current_wave + 1
	if _telegraphed_wave != next_w:
		_telegraphed_wave = next_w
		_telegraph_incoming_wave(next_w)
	_spawn_next_wave()


func continue_endless() -> void:
	if state != State.VICTORY_PAUSED or _match_mgr == null:
		return
	endless_mode = true
	_match_mgr.resume_from_special_mode_pause()
	state = State.PREP
	_prep_duration_max = INTER_WAVE_PREP_SECONDS
	_prep_timer = INTER_WAVE_PREP_SECONDS
	_telegraphed_wave = -1
	if _banner != null:
		_banner.set_banner_visible(true)
	_refresh_banner()
	_match_mgr.emit_tactical_event(
		&"objective",
		"ENDLESS PROTOCOL ENGAGED — Wave %d incoming in 00:%02d!" % [current_wave + 1, int(INTER_WAVE_PREP_SECONDS)],
		Vector2.ZERO,
		Color(1.0, 0.62, 0.24, 1.0)
	)


func _telegraph_incoming_wave(wave_num: int) -> void:
	if _match_mgr == null:
		return
	var lanes: Array[Dictionary] = _get_lanes_for_wave(wave_num)
	var lane_names: PackedStringArray = PackedStringArray()
	for lane_info: Dictionary in lanes:
		var lpos: Vector2 = lane_info["pos"] as Vector2
		var lname: String = String(lane_info["name"])
		lane_names.append(lname)
		_match_mgr.push_tactical_alert(lpos, &"under_attack", "Wave %d Inbound: %s!" % [wave_num, lname])
	var first_pos: Vector2 = (lanes[0]["pos"] as Vector2) if not lanes.is_empty() else LANE_MAIN
	_match_mgr.emit_tactical_event(
		&"combat",
		"WARNING: Wave %d inbound via %s!" % [wave_num, " + ".join(lane_names)],
		first_pos,
		Color(1.0, 0.36, 0.28, 1.0)
	)


func _spawn_next_wave() -> void:
	current_wave += 1
	state = State.ACTIVE_WAVE
	_wave_units.clear()

	var scene_root: Node = get_tree().current_scene
	var units_parent: Node = scene_root.get_node_or_null("Units") if scene_root != null else null
	if units_parent == null:
		units_parent = scene_root if scene_root != null else self

	var spec: Array[Dictionary] = _build_wave_composition(current_wave)
	var lanes: Array[Dictionary] = _get_lanes_for_wave(current_wave)
	if lanes.is_empty():
		lanes = [{"pos": LANE_MAIN, "name": "Omega Basin"}]

	var count_mult: float = 1.0
	var hp_mult: float = 1.0
	if _difficulty == int(GameConfig.AIDifficulty.RELAXED):
		count_mult = 0.78
		hp_mult = 0.88
	elif _difficulty == int(GameConfig.AIDifficulty.BRUTAL):
		count_mult = 1.28
		hp_mult = 1.12
	if current_wave > TARGET_VICTORY_WAVE:
		var extra: int = current_wave - TARGET_VICTORY_WAVE
		count_mult *= (1.0 + float(extra) * 0.14)
		hp_mult *= (1.0 + float(extra) * 0.12)

	var spawn_idx: int = 0
	for entry: Dictionary in spec:
		var u_key: StringName = entry["unit"] as StringName
		var base_cnt: int = int(entry["count"])
		var scaled_cnt: int = maxi(1, int(round(float(base_cnt) * count_mult)))
		var packed: PackedScene = _load_unit_scene(u_key)
		if packed == null:
			continue
		for k: int in range(scaled_cnt):
			var lane: Dictionary = lanes[spawn_idx % lanes.size()]
			var base_pos: Vector2 = lane["pos"] as Vector2
			var col_i: int = spawn_idx % 4
			var row_i: int = (spawn_idx / 4) % 4
			var offset: Vector2 = Vector2((float(col_i) - 1.5) * 44.0, (float(row_i) - 1.5) * 44.0)
			var spawn_pos: Vector2 = Vector2(
				clampf(base_pos.x + offset.x, -1210.0, 1210.0),
				clampf(base_pos.y + offset.y, -860.0, 860.0)
			)
			var inst: Node = packed.instantiate()
			if inst is Unit:
				var u: Unit = inst as Unit
				u.team = Unit.Team.ENEMY
				u.global_position = spawn_pos
				units_parent.add_child(u)
				if absf(hp_mult - 1.0) > 0.01:
					u.current_hp = maxf(1.0, u.current_hp * hp_mult)
				u.died.connect(_on_wave_unit_died)
				_wave_units.append(u)
			else:
				inst.queue_free()
			spawn_idx += 1

	_wave_initial_count = _wave_units.size()
	_ai_steer_timer = 0.0
	_steer_wave_units()
	_emit_prisma_wave_transmission(current_wave, lanes)
	if AudioManager != null:
		AudioManager.play_sfx(&"uplink_contested", -4.0, 0.0)
	_refresh_banner()


func _emit_prisma_wave_transmission(wave_num: int, lanes: Array[Dictionary]) -> void:
	if _match_mgr == null or _enemy_faction_mode != &"prisma_dei":
		return
	if SettingsManager != null and not SettingsManager.show_ai_transmissions:
		return
	var line: String = ""
	if wave_num == 1:
		line = "// PRISMA_DEI: The Choir advances in harmonic convergence. Surrender the Hyper-Uplink."
	elif wave_num == 5:
		line = "// PRISMA_DEI: Refraction Cloisters aligned. No armor endures our focusing lenses."
	elif wave_num == 10:
		line = "// PRISMA_DEI: DIVINE CONVERGENCE. Seraphs and Solstice Lances descend upon your sanctum."
	if not line.is_empty():
		var origin: Vector2 = (lanes[0]["pos"] as Vector2) if not lanes.is_empty() else LANE_MAIN
		_match_mgr.emit_tactical_event(&"ai_transmission", line, origin, Color(0.98, 0.80, 0.14, 1.0))


func _on_wave_unit_died(unit: Unit) -> void:
	_total_hostiles_defeated += 1
	if unit == null or not is_instance_valid(unit) or unit.data == null:
		return
	if not unit.data.is_heavy_unit():
		return
	# Guarantee juicy SalvageCore drop on heavy Holdout units (skip if one was already spawned nearby)
	if not is_inside_tree():
		return
	var pos: Vector2 = unit.global_position
	for sc_node: Node in get_tree().get_nodes_in_group("salvage_cores"):
		if sc_node is Node2D and is_instance_valid(sc_node):
			if (sc_node as Node2D).global_position.distance_squared_to(pos) <= 44.0 * 44.0:
				return
	var core: SalvageCore = SALVAGE_CORE_SCENE.instantiate() as SalvageCore
	if core != null:
		core.global_position = pos
		core.configure_payload(45, 20, unit.data.display_name)
		var host: Node = get_tree().current_scene
		if host != null:
			host.add_child(core)


func _on_wave_cleared() -> void:
	waves_cleared = current_wave
	ModeRecords.record_holdout_wave(_player_faction_id, _difficulty, waves_cleared)

	# Hyper-Uplink Holdout Synergy: holding central Uplink grants Wave-Clear Dividend
	var uplink_held: bool = _is_player_holding_uplink()
	if uplink_held:
		_uplink_dividends_earned += 1
		var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
		if econ != null:
			econ.add_resource(int(Unit.Team.PLAYER), EconomyManager.RESOURCE_BIOMASS, UPLINK_DIVIDEND_BIOMASS, true)
			econ.add_resource(int(Unit.Team.PLAYER), EconomyManager.RESOURCE_SILICA, UPLINK_DIVIDEND_SILICA, true)
			econ.add_resource(int(Unit.Team.PLAYER), EconomyManager.RESOURCE_COMPUTE, UPLINK_DIVIDEND_COMPUTE, true)
		if AudioManager != null:
			AudioManager.play_sfx(&"uplink_captured", -3.0, 0.0)
		if _match_mgr != null:
			_match_mgr.emit_tactical_event(
				&"economy",
				"Wave %d Cleared! Uplink Dividend: +%dB / +%dS / +%dC" % [
					waves_cleared,
					UPLINK_DIVIDEND_BIOMASS,
					UPLINK_DIVIDEND_SILICA,
					UPLINK_DIVIDEND_COMPUTE,
				],
				Vector2.ZERO,
				Color(0.28, 1.0, 0.86, 1.0)
			)
	else:
		if AudioManager != null:
			AudioManager.play_sfx(&"build_complete", -4.0, 0.0)
		if _match_mgr != null:
			_match_mgr.emit_tactical_event(
				&"objective",
				"Wave %d Cleared! Hold the Hyper-Uplink for inter-wave Compute dividends." % waves_cleared,
				Vector2.ZERO,
				Color(0.76, 0.90, 0.98, 1.0)
			)

	if waves_cleared == TARGET_VICTORY_WAVE and not endless_mode:
		_trigger_holdout_end(true)
		return

	state = State.PREP
	_prep_duration_max = INTER_WAVE_PREP_SECONDS
	_prep_timer = INTER_WAVE_PREP_SECONDS
	_telegraphed_wave = -1
	_refresh_banner()


func _trigger_holdout_end(is_victory: bool) -> void:
	if _match_mgr == null:
		return
	var is_new_best: bool = ModeRecords.record_holdout_wave(_player_faction_id, _difficulty, waves_cleared)
	var best_wave: int = ModeRecords.get_holdout_best_wave(_player_faction_id, _difficulty)
	state = State.VICTORY_PAUSED if is_victory else State.ENDED
	if _banner != null:
		_banner.set_banner_visible(false)

	var medal: int = ModeRecords.Medal.NONE
	if waves_cleared >= TARGET_VICTORY_WAVE:
		medal = ModeRecords.Medal.GOLD if _difficulty == int(GameConfig.AIDifficulty.BRUTAL) else (ModeRecords.Medal.SILVER if _difficulty == int(GameConfig.AIDifficulty.STANDARD) else ModeRecords.Medal.BRONZE)
		if waves_cleared >= TARGET_VICTORY_WAVE and _uplink_dividends_earned >= 6:
			medal = ModeRecords.Medal.GOLD
	elif waves_cleared >= 7:
		medal = ModeRecords.Medal.SILVER
	elif waves_cleared >= 4:
		medal = ModeRecords.Medal.BRONZE

	var title_txt: String = "HOLDOUT VICTORY" if is_victory else ("ENDLESS FALL" if endless_mode else "HOLDOUT DEFEAT")
	var sub_txt: String = "All 10 Sovereign Assault Waves Repelled!" if is_victory else ("Command Hub lost on Wave %d" % current_wave)
	var result: Dictionary = {
		"mode": &"holdout",
		"is_victory": is_victory,
		"title": title_txt,
		"subtitle": sub_txt,
		"medal": medal,
		"is_new_best": is_new_best,
		"can_continue_endless": is_victory and not endless_mode,
		"rows": [
			{"label": "Waves Cleared", "value": "%d / %d%s" % [waves_cleared, TARGET_VICTORY_WAVE, " (ENDLESS)" if endless_mode else ""]},
			{"label": "Personal Best", "value": "Wave %d" % best_wave},
			{"label": "Hostiles Neutralized", "value": InspectionHelper.format_number(_total_hostiles_defeated)},
			{"label": "Uplink Dividends Earned", "value": "%d Waves" % _uplink_dividends_earned},
			{"label": "Survival Duration", "value": _match_mgr.get_match_elapsed_formatted()},
		],
	}
	_match_mgr.finish_special_mode(is_victory, result, is_victory and not endless_mode)


func _prune_dead_wave_units() -> void:
	var alive: Array[Unit] = []
	for u: Unit in _wave_units:
		if is_instance_valid(u) and not u.is_dead and not u.is_queued_for_deletion():
			alive.append(u)
	_wave_units = alive


func _steer_wave_units() -> void:
	var hub_pos: Vector2 = _get_player_hub_position()
	var uplink_held: bool = _is_player_holding_uplink()
	var player_buildings: Array[Building] = []
	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if b_node is Building and is_instance_valid(b_node):
			var b: Building = b_node as Building
			if not b.is_destroyed and int(b.team) == int(Unit.Team.PLAYER):
				player_buildings.append(b)

	# Compute armed centroid so 0-damage support anchors (Cantor, Symbiote, Aegis Relay) escort cleanly
	var armed_sum: Vector2 = Vector2.ZERO
	var armed_cnt: int = 0
	for u_a: Unit in _wave_units:
		if is_instance_valid(u_a) and not u_a.is_dead and u_a.data != null and u_a.data.attack_damage > 0.0:
			armed_sum += u_a.global_position
			armed_cnt += 1
	var armed_centroid: Vector2 = (armed_sum / float(armed_cnt)) if armed_cnt > 0 else hub_pos

	for u: Unit in _wave_units:
		if not is_instance_valid(u) or u.is_dead:
			continue
		# Auto-deploy Anvil Siege-Walkers outside turret range
		if u.data != null and u.data.can_deploy:
			var near_bldg_d: float = INF
			for pb: Building in player_buildings:
				near_bldg_d = minf(near_bldg_d, u.global_position.distance_to(pb.global_position))
			if near_bldg_d <= 430.0 and u.deploy_state == Unit.DeployState.MOBILE:
				u.toggle_deploy_mode()
				continue
			elif near_bldg_d > 490.0 and u.deploy_state == Unit.DeployState.DEPLOYED:
				u.toggle_deploy_mode()
				continue

		# Keep 0-damage support units advancing tightly behind their armed wave cohort
		if u.data != null and u.data.attack_damage <= 0.0 and armed_cnt > 0:
			var back_dir: Vector2 = (LANE_MAIN - armed_centroid).normalized() if armed_centroid.distance_squared_to(LANE_MAIN) > 100.0 else Vector2.RIGHT
			var escort_pos: Vector2 = armed_centroid + back_dir * 62.0
			if u.global_position.distance_to(escort_pos) > 95.0 or u.command_state == Unit.CommandState.IDLE:
				u.command_move(escort_pos, false)
			continue

		if u.command_state == Unit.CommandState.IDLE:
			var target: Vector2 = hub_pos
			if uplink_held and u.global_position.distance_to(Vector2.ZERO) < u.global_position.distance_to(hub_pos) and u.global_position.distance_to(Vector2.ZERO) > 150.0:
				target = Vector2.ZERO
			u.command_attack_move(target, false)

		_try_trigger_wave_unit_abilities(u, player_buildings)


func _try_trigger_wave_unit_abilities(u: Unit, player_buildings: Array[Building]) -> void:
	if u.data == null or u.data.abilities.is_empty():
		return
	var has_target: bool = u.current_target != null and is_instance_valid(u.current_target)
	var dist: float = u.global_position.distance_to(u.current_target.global_position) if has_target else INF

	for ab: AbilityData in u.data.abilities:
		if ab == null or ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
			continue
		if ab.ability_id == &"luminous_mend" or ab.ability_id == &"monolith_shield_overcharge":
			continue
		if not u.is_ability_ready(ab):
			continue
		match ab.ability_id:
			&"solar_step":
				if has_target and (dist > u.get_effective_attack_range() * 0.85 or u.current_hp < u.get_max_hp() * 0.72):
					u.command_cast_ability(ab, u.global_position, u)
					return
			&"radiant_mark":
				if has_target and u.current_target is Unit and dist <= ab.cast_range:
					var tu: Unit = u.current_target as Unit
					if not tu.has_status_effect(&"radiant_mark"):
						u.command_cast_ability(ab, tu.global_position, tu)
						return
			&"focus_alignment":
				if has_target and dist <= u.get_effective_attack_range() + 45.0:
					var armored_or_b: bool = (u.current_target is Building) or (u.current_target is Unit and (u.current_target as Unit).data != null and (u.current_target as Unit).data.is_armored)
					if armored_or_b:
						u.command_cast_ability(ab, u.global_position, u)
						return
			&"blinding_glare":
				if has_target and dist <= ab.cast_range:
					u.command_cast_ability(ab, u.current_target.global_position)
					return
			&"aureole_surge":
				if has_target and dist <= u.get_effective_attack_range() + 45.0 and u.current_hp >= u.get_max_hp() * 0.45:
					u.command_cast_ability(ab, u.global_position, u)
					return
			&"solar_convergence":
				var conv_target: Variant = null
				if has_target and dist <= ab.cast_range:
					conv_target = u.current_target.global_position
				else:
					for pb: Building in player_buildings:
						if is_instance_valid(pb) and not pb.is_destroyed and u.global_position.distance_to(pb.global_position) <= ab.cast_range:
							conv_target = pb.global_position
							break
				if conv_target is Vector2:
					u.command_cast_ability(ab, conv_target as Vector2)
					return


func _is_player_defeated() -> bool:
	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if b_node is Building and is_instance_valid(b_node):
			var b: Building = b_node as Building
			if not b.is_destroyed and int(b.team) == int(Unit.Team.PLAYER) and b.is_command_hub():
				return false
	return true


func _is_player_holding_uplink() -> bool:
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	return uplink != null and is_instance_valid(uplink) and uplink.controlling_team == int(Unit.Team.PLAYER)


func _get_player_hub_position() -> Vector2:
	for b_node: Node in get_tree().get_nodes_in_group("buildings"):
		if b_node is Building and is_instance_valid(b_node):
			var b: Building = b_node as Building
			if not b.is_destroyed and int(b.team) == int(Unit.Team.PLAYER) and b.is_command_hub():
				return b.global_position
	return Vector2(-880.0, 530.0)


func _get_lanes_for_wave(wave_num: int) -> Array[Dictionary]:
	if wave_num <= 3:
		return [{"pos": LANE_MAIN, "name": "Omega Basin"}]
	if wave_num > TARGET_VICTORY_WAVE:
		var rot: int = (wave_num - TARGET_VICTORY_WAVE) % 3
		if rot == 1:
			return [{"pos": LANE_NORTH, "name": "North Conduit"}, {"pos": LANE_MAIN, "name": "Omega Basin"}, {"pos": LANE_SOUTH, "name": "South Trench"}]
		if rot == 2:
			return [{"pos": LANE_SOUTH, "name": "South Trench"}, {"pos": LANE_NORTH, "name": "North Conduit"}, {"pos": LANE_MAIN, "name": "Omega Basin"}]
	if wave_num == 4 or wave_num == 7:
		return [{"pos": LANE_MAIN, "name": "Omega Basin"}, {"pos": LANE_NORTH, "name": "North Conduit"}]
	if wave_num == 5 or wave_num == 8:
		return [{"pos": LANE_MAIN, "name": "Omega Basin"}, {"pos": LANE_SOUTH, "name": "South Trench"}]
	return [
		{"pos": LANE_MAIN, "name": "Omega Basin"},
		{"pos": LANE_NORTH, "name": "North Conduit"},
		{"pos": LANE_SOUTH, "name": "South Trench"},
	]


func _build_wave_composition(wave_num: int) -> Array[Dictionary]:
	var fac: StringName = _enemy_faction_mode
	var w: int = mini(wave_num, 10)
	if fac == GameConfig.HOLDOUT_ENEMY_MIXED:
		# 3-Faction Mixed Assault waves blending GENESIS_V2, MONOLITH_OS, and PRISMA_DEI
		match w:
			1:
				return [{"unit": &"clone_trooper", "count": 3}, {"unit": &"votary", "count": 2}, {"unit": &"bulwark", "count": 1}]
			2:
				return [{"unit": &"votary", "count": 3}, {"unit": &"bulwark", "count": 2}, {"unit": &"stinger", "count": 2}, {"unit": &"cantor", "count": 1}]
			3:
				return [{"unit": &"clone_trooper", "count": 4}, {"unit": &"bulwark", "count": 2}, {"unit": &"lens_adjudicator", "count": 2}, {"unit": &"cantor", "count": 1}]
			4:
				return [{"unit": &"bulwark", "count": 3}, {"unit": &"prism_weaver", "count": 2}, {"unit": &"lance_rig", "count": 2}, {"unit": &"aegis_relay", "count": 1}, {"unit": &"cantor", "count": 1}]
			5:
				return [{"unit": &"clone_trooper", "count": 5}, {"unit": &"rail_sentinel", "count": 2}, {"unit": &"lens_adjudicator", "count": 2}, {"unit": &"prism_weaver", "count": 2}, {"unit": &"cantor", "count": 1}, {"unit": &"symbiote", "count": 1}]
			6:
				return [{"unit": &"bulwark", "count": 4}, {"unit": &"votary", "count": 3}, {"unit": &"rail_sentinel", "count": 2}, {"unit": &"seraph_cruiser", "count": 1}, {"unit": &"goliath_frame", "count": 1}, {"unit": &"cantor", "count": 1}, {"unit": &"aegis_relay", "count": 1}]
			7:
				return [{"unit": &"clone_trooper", "count": 4}, {"unit": &"prism_weaver", "count": 2}, {"unit": &"anvil_walker", "count": 2}, {"unit": &"seraph_cruiser", "count": 1}, {"unit": &"solstice_lance", "count": 1}, {"unit": &"cantor", "count": 2}]
			8:
				return [{"unit": &"goliath_frame", "count": 2}, {"unit": &"dreadnought", "count": 1}, {"unit": &"seraph_cruiser", "count": 2}, {"unit": &"chrysalis_mortar", "count": 2}, {"unit": &"solstice_lance", "count": 1}, {"unit": &"aegis_relay", "count": 2}, {"unit": &"cantor", "count": 1}]
			9:
				return [{"unit": &"dreadnought", "count": 2}, {"unit": &"goliath_frame", "count": 2}, {"unit": &"seraph_cruiser", "count": 2}, {"unit": &"anvil_walker", "count": 2}, {"unit": &"solstice_lance", "count": 2}, {"unit": &"prism_weaver", "count": 2}, {"unit": &"cantor", "count": 2}, {"unit": &"aegis_relay", "count": 1}]
			_:
				return [
					{"unit": &"goliath_frame", "count": 2},
					{"unit": &"dreadnought", "count": 2},
					{"unit": &"seraph_cruiser", "count": 2},
					{"unit": &"arc_lancer", "count": 2},
					{"unit": &"anvil_walker", "count": 2},
					{"unit": &"solstice_lance", "count": 2},
					{"unit": &"chrysalis_mortar", "count": 2},
					{"unit": &"aegis_relay", "count": 2},
					{"unit": &"cantor", "count": 2},
					{"unit": &"votary", "count": 4},
					{"unit": &"clone_trooper", "count": 4},
				]

	if fac == &"prisma_dei":
		match w:
			1:
				return [{"unit": &"votary", "count": 4}, {"unit": &"lumen_skiff", "count": 2}]
			2:
				return [{"unit": &"votary", "count": 5}, {"unit": &"lumen_skiff", "count": 2}, {"unit": &"cantor", "count": 1}]
			3:
				return [{"unit": &"votary", "count": 6}, {"unit": &"lens_adjudicator", "count": 2}, {"unit": &"cantor", "count": 1}]
			4:
				return [{"unit": &"votary", "count": 6}, {"unit": &"lumen_skiff", "count": 3}, {"unit": &"prism_weaver", "count": 2}, {"unit": &"cantor", "count": 1}]
			5:
				return [{"unit": &"votary", "count": 6}, {"unit": &"lens_adjudicator", "count": 3}, {"unit": &"prism_weaver", "count": 2}, {"unit": &"cantor", "count": 2}]
			6:
				return [{"unit": &"votary", "count": 8}, {"unit": &"lumen_skiff", "count": 4}, {"unit": &"lens_adjudicator", "count": 3}, {"unit": &"cantor", "count": 2}, {"unit": &"seraph_cruiser", "count": 1}]
			7:
				return [{"unit": &"votary", "count": 6}, {"unit": &"prism_weaver", "count": 3}, {"unit": &"seraph_cruiser", "count": 2}, {"unit": &"solstice_lance", "count": 1}, {"unit": &"cantor", "count": 2}]
			8:
				return [{"unit": &"votary", "count": 8}, {"unit": &"lens_adjudicator", "count": 4}, {"unit": &"seraph_cruiser", "count": 2}, {"unit": &"solstice_lance", "count": 2}, {"unit": &"cantor", "count": 2}]
			9:
				return [{"unit": &"votary", "count": 8}, {"unit": &"prism_weaver", "count": 4}, {"unit": &"seraph_cruiser", "count": 3}, {"unit": &"solstice_lance", "count": 2}, {"unit": &"cantor", "count": 3}]
			_:
				return [{"unit": &"votary", "count": 10}, {"unit": &"lens_adjudicator", "count": 4}, {"unit": &"prism_weaver", "count": 3}, {"unit": &"seraph_cruiser", "count": 4}, {"unit": &"solstice_lance", "count": 3}, {"unit": &"cantor", "count": 3}]

	if fac == &"monolith_os":
		match w:
			1:
				return [{"unit": &"picket_drone", "count": 3}, {"unit": &"bulwark", "count": 1}]
			2:
				return [{"unit": &"picket_drone", "count": 4}, {"unit": &"bulwark", "count": 2}]
			3:
				return [{"unit": &"picket_drone", "count": 4}, {"unit": &"bulwark", "count": 3}]
			4:
				return [{"unit": &"bulwark", "count": 3}, {"unit": &"rail_sentinel", "count": 2}, {"unit": &"picket_drone", "count": 3}]
			5:
				return [{"unit": &"bulwark", "count": 3}, {"unit": &"rail_sentinel", "count": 3}, {"unit": &"aegis_relay", "count": 2}]
			6:
				return [{"unit": &"bulwark", "count": 4}, {"unit": &"rail_sentinel", "count": 4}, {"unit": &"aegis_relay", "count": 2}, {"unit": &"picket_drone", "count": 3}]
			7:
				return [{"unit": &"dreadnought", "count": 1}, {"unit": &"bulwark", "count": 4}, {"unit": &"rail_sentinel", "count": 3}, {"unit": &"aegis_relay", "count": 2}]
			8:
				return [{"unit": &"dreadnought", "count": 1}, {"unit": &"anvil_walker", "count": 2}, {"unit": &"null_grid", "count": 1}, {"unit": &"bulwark", "count": 4}]
			9:
				return [{"unit": &"dreadnought", "count": 2}, {"unit": &"anvil_walker", "count": 2}, {"unit": &"null_grid", "count": 2}, {"unit": &"rail_sentinel", "count": 4}, {"unit": &"aegis_relay", "count": 2}]
			_:
				return [{"unit": &"dreadnought", "count": 3}, {"unit": &"anvil_walker", "count": 3}, {"unit": &"null_grid", "count": 2}, {"unit": &"rail_sentinel", "count": 4}, {"unit": &"aegis_relay", "count": 3}]

	# GENESIS_V2 waves
	match w:
		1:
			return [{"unit": &"clone_trooper", "count": 4}, {"unit": &"stinger", "count": 1}]
		2:
			return [{"unit": &"clone_trooper", "count": 5}, {"unit": &"stinger", "count": 2}]
		3:
			return [{"unit": &"clone_trooper", "count": 6}, {"unit": &"stinger", "count": 3}, {"unit": &"symbiote", "count": 1}]
		4:
			return [{"unit": &"clone_trooper", "count": 6}, {"unit": &"lance_rig", "count": 2}, {"unit": &"symbiote", "count": 2}]
		5:
			return [{"unit": &"clone_trooper", "count": 7}, {"unit": &"lance_rig", "count": 3}, {"unit": &"signal_jammer", "count": 1}, {"unit": &"stinger", "count": 3}]
		6:
			return [{"unit": &"clone_trooper", "count": 8}, {"unit": &"lance_rig", "count": 4}, {"unit": &"signal_jammer", "count": 2}, {"unit": &"symbiote", "count": 2}]
		7:
			return [{"unit": &"goliath_frame", "count": 2}, {"unit": &"clone_trooper", "count": 6}, {"unit": &"lance_rig", "count": 3}, {"unit": &"symbiote", "count": 2}]
		8:
			return [{"unit": &"goliath_frame", "count": 2}, {"unit": &"arc_lancer", "count": 2}, {"unit": &"chrysalis_mortar", "count": 2}, {"unit": &"signal_jammer", "count": 2}]
		9:
			return [{"unit": &"goliath_frame", "count": 3}, {"unit": &"arc_lancer", "count": 2}, {"unit": &"chrysalis_mortar", "count": 3}, {"unit": &"lance_rig", "count": 4}, {"unit": &"symbiote", "count": 2}]
		_:
			return [{"unit": &"goliath_frame", "count": 4}, {"unit": &"arc_lancer", "count": 3}, {"unit": &"chrysalis_mortar", "count": 3}, {"unit": &"signal_jammer", "count": 2}, {"unit": &"clone_trooper", "count": 8}]


func _load_unit_scene(unit_key: StringName) -> PackedScene:
	if _scene_cache.has(unit_key):
		return _scene_cache[unit_key] as PackedScene
	var path: String = String(UNIT_SCENES.get(unit_key, ""))
	if path.is_empty():
		return null
	var packed: PackedScene = load(path) as PackedScene
	_scene_cache[unit_key] = packed
	return packed


func _refresh_banner() -> void:
	if _banner == null:
		return
	var uplink_tag: String = "UPLINK HELD (+10% & Dividend)" if _is_player_holding_uplink() else "Capture Hyper-Uplink for +10% & Dividends"
	var wave_cap_str: String = "ENDLESS" if endless_mode else str(TARGET_VICTORY_WAVE)
	if state == State.PREP:
		var secs: int = maxi(0, int(ceil(_prep_timer)))
		var next_w: int = current_wave + 1
		var accent: Color = Color(1.0, 0.44, 0.30, 1.0) if _prep_timer <= PRE_WAVE_TELEGRAPH_SECONDS else Color(1.0, 0.80, 0.32, 1.0)
		_banner.set_header(
			"WAVE %d / %s — NEXT IN 00:%02d" % [next_w, wave_cap_str, secs],
			"",
			accent
		)
		_banner.set_subtitle(uplink_tag, Color(0.32, 0.98, 0.82, 0.95) if _is_player_holding_uplink() else Color(0.78, 0.88, 0.96, 0.88))
		_banner.set_progress(1.0 - (_prep_timer / maxf(1.0, _prep_duration_max)), accent, true)
		_banner.set_action_button(
			_prep_timer > 1.2,
			"CALL EARLY (+%dB/+%dS)" % [EARLY_CALL_BIOMASS, EARLY_CALL_SILICA],
			Color(1.0, 0.84, 0.30, 1.0),
			"Spawn Wave %d immediately for +%d Biomass & +%d Silica" % [next_w, EARLY_CALL_BIOMASS, EARLY_CALL_SILICA]
		)
	elif state == State.ACTIVE_WAVE:
		var rem: int = _wave_units.size()
		var ratio: float = 1.0 - (float(rem) / float(maxi(1, _wave_initial_count)))
		_banner.set_header(
			"WAVE %d / %s" % [current_wave, wave_cap_str],
			"HOSTILES: %d" % rem,
			Color(1.0, 0.40, 0.32, 1.0)
		)
		_banner.set_subtitle(uplink_tag, Color(0.32, 0.98, 0.82, 0.95) if _is_player_holding_uplink() else Color(0.78, 0.88, 0.96, 0.88))
		_banner.set_progress(ratio, Color(1.0, 0.42, 0.30, 1.0), true)
		_banner.set_action_button(false)
