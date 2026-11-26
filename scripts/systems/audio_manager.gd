extends Node

signal mute_changed(is_muted: bool)
signal volume_changed(volume_linear: float)

const SAMPLE_RATE: int = 22050
const COMBAT_POOL_SIZE: int = 10
const UI_POOL_SIZE: int = 8
const BARK_SELECT_DEBOUNCE_MS: int = 120
const BARK_ORDER_DEBOUNCE_MS: int = 450

const AMB_BASE_CEILING_DB: float = -16.0
const AMB_COMBAT_CEILING_DB: float = -14.0
const AMB_UPLINK_CEILING_DB: float = -15.0
const AMB_DUCK_TARGET_DB: float = -5.0
const AMB_DUCK_ATTACK_DB_PER_S: float = 25.0 # 0.2s attack to -5 dB
const AMB_DUCK_RELEASE_DB_PER_S: float = 4.2 # ~1.2s release from -5 dB

const UNIT_CLASS_PRIORITY: Dictionary = {
	&"heavy": 5,
	&"counter": 4,
	&"support": 3,
	&"swarm": 2,
	&"worker": 1,
}

const BUILDING_CLASS_PRIORITY: Dictionary = {
	&"production": 5,
	&"hub": 4,
	&"tech": 3,
	&"defense": 2,
	&"utility": 1,
}

const UI_SFX_IDS: Array = [
	&"ui_click",
	&"unit_select",
	&"inspect_tick",
	&"bldg_select_production",
	&"bldg_select_hub",
	&"bldg_select_tech",
	&"bldg_select_defense",
	&"bldg_select_utility",
	&"order_move",
	&"order_attack",
	&"order_gather",
	&"build_complete",
	&"upgrade_complete",
	&"unit_ready",
	&"error_insufficient",
	&"bandwidth_near_cap",
	&"alert_under_attack",
	&"alert_uplink",
	&"alert_complete",
	&"veterancy_rank_up",
	&"salvage_claimed",
	&"autocast_toggle",
	&"relay_captured",
	&"match_victory",
	&"match_defeat",
]

var is_muted: bool = false
var master_volume_linear: float = 0.72
var sfx_volume_linear: float = 0.85
var ui_volume_linear: float = 0.85
var ambience_volume_linear: float = 0.35

var _unfocused_muted: bool = false
var _streams: Dictionary = {}
var _combat_players: Array[AudioStreamPlayer] = []
var _combat_start_ms: Array[int] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _next_ui_idx: int = 0
var _bark_player: AudioStreamPlayer = null
var _last_play_ms: Dictionary = {}
var _last_bark_select_ms: int = -9999
var _last_bark_order_ms: int = -9999
var _amb_base_player: AudioStreamPlayer = null
var _amb_combat_player: AudioStreamPlayer = null
var _amb_uplink_player: AudioStreamPlayer = null
var _combat_intensity: float = 0.0
var _combat_target: float = 0.0
var _combat_hold_until_ms: int = 0
var _uplink_tension: float = 0.0
var _amb_duck_db: float = 0.0
var _amb_duck_until_ms: int = 0
var _last_tick_ms: int = 0
var _amb_poll_acc_s: float = 0.0
var _cooldowns_ms: Dictionary = {
	&"ui_click": 30,
	&"unit_select": 45,
	&"inspect_tick": 80,
	&"order_move": 60,
	&"order_attack": 60,
	&"order_gather": 60,
	&"build_complete": 120,
	&"upgrade_complete": 180,
	&"unit_ready": 90,
	&"error_insufficient": 160,
	&"bandwidth_near_cap": 1000,
	&"weapon_rifle": 75,
	&"weapon_slash": 80,
	&"weapon_rail": 90,
	&"weapon_mortar": 105,
	&"weapon_mono_slug": 85,
	&"weapon_mono_rail": 100,
	&"weapon_mono_tether": 75,
	&"weapon_mono_bastion": 105,
	&"weapon_mono_siege": 120,
	&"ability_adrenal": 90,
	&"ability_static": 100,
	&"ability_slam": 110,
	&"ability_barrage": 110,
	&"ability_shield_overcharge": 110,
	&"ability_suppressive_lock": 95,
	&"ability_kinetic_barrier": 110,
	&"ability_grav_pulse": 120,
	&"entity_destroyed": 95,
	&"shield_shatter": 85,
	&"alert_under_attack": 1800,
	&"alert_uplink": 1400,
	&"alert_complete": 700,
	&"veterancy_rank_up": 350,
	&"salvage_claimed": 180,
	&"autocast_toggle": 60,
	&"relay_captured": 450,
	&"overclock_activate": 180,
	&"deploy_lock": 90,
	&"deploy_release": 90,
	&"match_victory": 500,
	&"match_defeat": 500,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tick_ms = Time.get_ticks_msec()
	_ensure_master_bus_limiter()

	for i: int in range(COMBAT_POOL_SIZE):
		var cp: AudioStreamPlayer = AudioStreamPlayer.new()
		cp.name = "CombatSFXPlayer_%d" % i
		cp.bus = &"Master"
		add_child(cp)
		_combat_players.append(cp)
		_combat_start_ms.append(0)

	for i: int in range(UI_POOL_SIZE):
		var up: AudioStreamPlayer = AudioStreamPlayer.new()
		up.name = "UISFXPlayer_%d" % i
		up.bus = &"Master"
		add_child(up)
		_ui_players.append(up)

	_bark_player = AudioStreamPlayer.new()
	_bark_player.name = "BarkChannelPlayer"
	_bark_player.bus = &"Master"
	add_child(_bark_player)

	_generate_procedural_library()
	_setup_ambience_players()
	_sync_from_settings()
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	_apply_master_bus_settings()


func _ensure_master_bus_limiter() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	var fx_count: int = AudioServer.get_bus_effect_count(master_idx)
	for i: int in range(fx_count):
		if AudioServer.get_bus_effect(master_idx, i) is AudioEffectLimiter:
			return
	var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -3.0
	AudioServer.add_bus_effect(master_idx, limiter)


func _process(_delta: float) -> void:
	if _amb_base_player == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	var real_dt: float = clampf(float(now_ms - _last_tick_ms) * 0.001, 0.0, 0.1)
	_last_tick_ms = now_ms

	if now_ms >= _combat_hold_until_ms:
		_combat_target = 0.0

	if _combat_intensity < _combat_target:
		_combat_intensity = minf(_combat_target, _combat_intensity + real_dt / 1.5)
	elif _combat_intensity > _combat_target:
		_combat_intensity = maxf(_combat_target, _combat_intensity - real_dt / 5.0)

	var is_paused: bool = is_inside_tree() and get_tree().paused
	var want_duck: bool = is_paused or (now_ms < _amb_duck_until_ms)
	var duck_target: float = AMB_DUCK_TARGET_DB if want_duck else 0.0
	if _amb_duck_db > duck_target:
		_amb_duck_db = maxf(duck_target, _amb_duck_db - AMB_DUCK_ATTACK_DB_PER_S * real_dt)
	elif _amb_duck_db < duck_target:
		_amb_duck_db = minf(duck_target, _amb_duck_db + AMB_DUCK_RELEASE_DB_PER_S * real_dt)

	_amb_poll_acc_s += real_dt
	var uplink_target: float = 0.0
	if _amb_poll_acc_s >= 0.35 and is_inside_tree():
		_amb_poll_acc_s = 0.0
		var mm: Node = get_tree().get_first_node_in_group("match_manager")
		var in_match: bool = mm != null and is_instance_valid(mm)
		if not in_match:
			_combat_target = 0.0
			_combat_hold_until_ms = 0
		else:
			for node: Node in get_tree().get_nodes_in_group("hyper_uplinks"):
				if is_instance_valid(node) and node is HyperUplink:
					var up: HyperUplink = node as HyperUplink
					if up.is_contested:
						uplink_target = 1.0
					elif absf(up.capture_progress) >= 0.65 and up.controlling_team < 0:
						uplink_target = maxf(uplink_target, 0.75)
		_uplink_tension = move_toward(_uplink_tension, uplink_target, 0.25)

	_update_ambience_mix(is_paused)


func notify_combat_activity(weight: float = 0.45) -> void:
	_combat_target = clampf(maxf(_combat_target, weight), 0.0, 1.0)
	var hold_until: int = Time.get_ticks_msec() + 2500
	if hold_until > _combat_hold_until_ms:
		_combat_hold_until_ms = hold_until


func trigger_ambience_duck(duration_sec: float = 1.8) -> void:
	var until_ms: int = Time.get_ticks_msec() + int(round(maxf(0.2, duration_sec) * 1000.0))
	if until_ms > _amb_duck_until_ms:
		_amb_duck_until_ms = until_ms


func _slider_to_db(linear_val: float) -> float:
	var v: float = clampf(linear_val, 0.0, 1.0)
	if v <= 0.005:
		return -80.0
	return linear_to_db(pow(v, 1.6))


func _setup_ambience_players() -> void:
	_amb_base_player = AudioStreamPlayer.new()
	_amb_base_player.name = "AmbBasePlayer"
	_amb_base_player.bus = &"Master"
	_amb_base_player.stream = _synth_ambience_base_loop()
	_amb_base_player.volume_db = -80.0
	add_child(_amb_base_player)
	_amb_base_player.play()

	_amb_combat_player = AudioStreamPlayer.new()
	_amb_combat_player.name = "AmbCombatPlayer"
	_amb_combat_player.bus = &"Master"
	_amb_combat_player.stream = _synth_ambience_combat_loop()
	_amb_combat_player.volume_db = -80.0
	add_child(_amb_combat_player)
	_amb_combat_player.play()

	_amb_uplink_player = AudioStreamPlayer.new()
	_amb_uplink_player.name = "AmbUplinkPlayer"
	_amb_uplink_player.bus = &"Master"
	_amb_uplink_player.stream = _synth_ambience_uplink_loop()
	_amb_uplink_player.volume_db = -80.0
	add_child(_amb_uplink_player)
	_amb_uplink_player.play()


func _update_ambience_mix(_is_paused: bool) -> void:
	var muted_now: bool = is_effectively_muted() or master_volume_linear <= 0.005 or ambience_volume_linear <= 0.005
	if muted_now:
		if _amb_base_player != null:
			_amb_base_player.volume_db = -80.0
		if _amb_combat_player != null:
			_amb_combat_player.volume_db = -80.0
		if _amb_uplink_player != null:
			_amb_uplink_player.volume_db = -80.0
		return

	var user_amb_db: float = _slider_to_db(ambience_volume_linear)
	if _amb_base_player != null:
		_amb_base_player.volume_db = maxf(-80.0, user_amb_db + AMB_BASE_CEILING_DB + _amb_duck_db)
	if _amb_combat_player != null:
		if _combat_intensity <= 0.005:
			_amb_combat_player.volume_db = -80.0
		else:
			_amb_combat_player.volume_db = maxf(-80.0, user_amb_db + AMB_COMBAT_CEILING_DB + linear_to_db(_combat_intensity) + _amb_duck_db)
	if _amb_uplink_player != null:
		if _uplink_tension <= 0.005:
			_amb_uplink_player.volume_db = -80.0
		else:
			_amb_uplink_player.volume_db = maxf(-80.0, user_amb_db + AMB_UPLINK_CEILING_DB + linear_to_db(_uplink_tension) + _amb_duck_db)


func _on_settings_changed(category: StringName) -> void:
	if category == &"audio" or category == &"all":
		_sync_from_settings()


func _sync_from_settings() -> void:
	if SettingsManager == null:
		return
	var prev_muted: bool = is_muted
	var prev_master: float = master_volume_linear
	master_volume_linear = clampf(SettingsManager.master_volume, 0.0, 1.0)
	sfx_volume_linear = clampf(SettingsManager.sfx_volume, 0.0, 1.0)
	ui_volume_linear = clampf(SettingsManager.ui_volume, 0.0, 1.0)
	ambience_volume_linear = clampf(SettingsManager.ambience_volume, 0.0, 1.0)
	is_muted = SettingsManager.muted
	_apply_master_bus_settings()
	_update_ambience_mix(is_inside_tree() and get_tree().paused)
	if prev_muted != is_muted:
		mute_changed.emit(is_muted)
	if not is_equal_approx(prev_master, master_volume_linear):
		volume_changed.emit(master_volume_linear)


func set_unfocused_mute(unfocused_muted: bool) -> void:
	if _unfocused_muted == unfocused_muted:
		return
	_unfocused_muted = unfocused_muted
	_apply_master_bus_settings()


func is_effectively_muted() -> bool:
	return is_muted or _unfocused_muted


func set_muted(muted: bool) -> void:
	if is_muted == muted:
		return
	is_muted = muted
	if SettingsManager != null and SettingsManager.muted != is_muted:
		SettingsManager.set_audio_settings(master_volume_linear, sfx_volume_linear, ui_volume_linear, is_muted)
	_apply_master_bus_settings()
	mute_changed.emit(is_muted)


func toggle_mute() -> bool:
	set_muted(not is_muted)
	if not is_muted:
		play_sfx(&"ui_click")
	return is_muted


func set_volume(linear: float) -> void:
	master_volume_linear = clampf(linear, 0.0, 1.0)
	if SettingsManager != null:
		SettingsManager.set_audio_settings(master_volume_linear, sfx_volume_linear, ui_volume_linear, is_muted)
	_apply_master_bus_settings()
	volume_changed.emit(master_volume_linear)


func _compute_spatial_attenuation(world_pos: Vector2, allow_cull: bool) -> Dictionary:
	if world_pos == Vector2.INF or not is_inside_tree():
		return {"culled": false, "db_offset": 0.0}
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		cam = get_tree().get_first_node_in_group("rts_camera") as Camera2D
	if cam == null or not is_instance_valid(cam):
		return {"culled": false, "db_offset": 0.0}
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom_vec: Vector2 = Vector2(maxf(0.1, cam.zoom.x), maxf(0.1, cam.zoom.y))
	var half_world: Vector2 = (vp_size / zoom_vec) * 0.5
	var view_radius: float = maxf(240.0, half_world.length())
	var dist: float = cam.global_position.distance_to(world_pos)
	var norm: float = dist / view_radius
	if norm <= 0.85:
		return {"culled": false, "db_offset": 0.0}
	if norm > 1.55:
		if allow_cull:
			return {"culled": true, "db_offset": -80.0}
		return {"culled": false, "db_offset": -16.0}
	var t: float = clampf((norm - 0.85) / 0.70, 0.0, 1.0)
	return {"culled": false, "db_offset": lerpf(0.0, -16.0, t)}


func play_sfx(
	sfx_id: StringName,
	volume_db_offset: float = 0.0,
	pitch_jitter: float = 0.0,
	world_pos: Vector2 = Vector2.INF,
	allow_offscreen_cull: bool = true
) -> void:
	if is_effectively_muted() or master_volume_linear <= 0.005:
		return
	var is_ui_sfx: bool = UI_SFX_IDS.has(sfx_id)
	var channel_linear: float = ui_volume_linear if is_ui_sfx else sfx_volume_linear
	if channel_linear <= 0.005:
		return
	if not _streams.has(sfx_id):
		return

	var spatial_db: float = 0.0
	if world_pos != Vector2.INF:
		var atten: Dictionary = _compute_spatial_attenuation(world_pos, allow_offscreen_cull)
		if bool(atten["culled"]):
			return
		spatial_db = float(atten["db_offset"])

	var now_ms: int = Time.get_ticks_msec()
	var min_gap: int = int(_cooldowns_ms.get(sfx_id, 40))
	var prev_ms: int = int(_last_play_ms.get(sfx_id, -9999))
	if now_ms - prev_ms < min_gap:
		return
	_last_play_ms[sfx_id] = now_ms

	if sfx_id == &"match_victory" or sfx_id == &"match_defeat":
		trigger_ambience_duck(2.4)

	var player: AudioStreamPlayer = _acquire_ui_player() if is_ui_sfx else _acquire_combat_player(now_ms)
	if player == null:
		return
	player.stream = _streams[sfx_id] as AudioStreamWAV
	player.volume_db = volume_db_offset + spatial_db + _slider_to_db(channel_linear)
	if pitch_jitter > 0.0:
		player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	else:
		player.pitch_scale = 1.0
	player.play()


func resolve_selection_audio_class(entities: Array) -> Dictionary:
	var best_unit_class: StringName = &""
	var best_unit_prio: int = -1
	var best_bldg_class: StringName = &""
	var best_bldg_prio: int = -1
	var has_inspectable: bool = false
	var local_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)

	for item: Variant in entities:
		if not is_instance_valid(item):
			continue
		if item is Unit:
			var u: Unit = item as Unit
			if u.is_dead:
				continue
			if local_team >= 0 and int(u.team) == local_team:
				var u_cls: StringName = u.data.audio_bark_class if (u.data != null and u.data.audio_bark_class != &"") else classify_unit_bark_class(u.get_unit_type_id())
				var u_prio: int = int(UNIT_CLASS_PRIORITY.get(u_cls, 1))
				if u_prio > best_unit_prio:
					best_unit_prio = u_prio
					best_unit_class = u_cls
			else:
				has_inspectable = true
		elif item is Building:
			var b: Building = item as Building
			if b.is_destroyed:
				continue
			if local_team >= 0 and int(b.team) == local_team:
				var b_cls: StringName = classify_building_audio_class(b)
				var b_prio: int = int(BUILDING_CLASS_PRIORITY.get(b_cls, 1))
				if b_prio > best_bldg_prio:
					best_bldg_prio = b_prio
					best_bldg_class = b_cls
			else:
				has_inspectable = true
		else:
			has_inspectable = true

	if best_unit_class != &"":
		return {"kind": &"unit", "audio_class": best_unit_class}
	if best_bldg_class != &"":
		return {"kind": &"building", "audio_class": best_bldg_class}
	if has_inspectable:
		return {"kind": &"inspect", "audio_class": &"inspect"}
	return {"kind": &"", "audio_class": &""}


func classify_building_audio_class(building: Building) -> StringName:
	if building == null:
		return &"utility"
	return building.get_audio_select_class()


func _get_local_faction_pitch_bias() -> float:
	if TeamManager == null:
		return 1.0
	var local_team: int = TeamManager.get_local_human_team()
	if local_team < 0:
		return 1.0
	var fdata: FactionData = TeamManager.get_team_faction_data(local_team)
	if fdata != null:
		return clampf(fdata.audio_bark_pitch_bias, 0.75, 1.35)
	return 1.0


func _get_local_faction_timbre_profile() -> StringName:
	if TeamManager == null:
		return &"technozen_bio"
	var local_team: int = TeamManager.get_local_human_team()
	if local_team < 0:
		return &"technozen_bio"
	var fdata: FactionData = TeamManager.get_team_faction_data(local_team)
	if fdata != null and fdata.audio_timbre_profile != &"":
		return fdata.audio_timbre_profile
	return &"technozen_bio"


func _resolve_timbre_stream_key(base_key: StringName) -> StringName:
	if _get_local_faction_timbre_profile() == &"monolith_industrial":
		var mono_key: StringName = StringName("mono_%s" % String(base_key))
		if _streams.has(mono_key):
			return mono_key
	return base_key


func _play_on_bark_channel(
	stream_key: StringName,
	volume_db_offset: float,
	pitch_jitter: float,
	debounce_ms: int,
	is_order: bool
) -> void:
	if is_effectively_muted() or master_volume_linear <= 0.005 or ui_volume_linear <= 0.005:
		return
	var resolved_key: StringName = _resolve_timbre_stream_key(stream_key)
	if _bark_player == null or not _streams.has(resolved_key):
		return
	var now_ms: int = Time.get_ticks_msec()
	var prev_ms: int = _last_bark_order_ms if is_order else _last_bark_select_ms
	if now_ms - prev_ms < debounce_ms:
		return
	if is_order:
		_last_bark_order_ms = now_ms
	else:
		_last_bark_select_ms = now_ms

	# Single-voice channel: stop any active bark cleanly so selections/orders never overlap.
	if _bark_player.playing:
		_bark_player.stop()
	_bark_player.stream = _streams[resolved_key] as AudioStreamWAV
	_bark_player.volume_db = volume_db_offset + _slider_to_db(ui_volume_linear)
	var pitch_bias: float = _get_local_faction_pitch_bias()
	if pitch_jitter > 0.0:
		_bark_player.pitch_scale = pitch_bias * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	else:
		_bark_player.pitch_scale = pitch_bias
	_bark_player.play()


func play_selection_audio(entities: Array, preferred_unit_class: StringName = &"") -> void:
	if preferred_unit_class != &"":
		if TeamManager != null and TeamManager.is_spectator_mode():
			return
		var pref_key: StringName = StringName("bark_%s_select" % String(preferred_unit_class))
		_play_on_bark_channel(pref_key, -4.5, 0.04, BARK_SELECT_DEBOUNCE_MS, false)
		return

	if entities.is_empty():
		return
	var resolved: Dictionary = resolve_selection_audio_class(entities)
	var kind: StringName = resolved.get("kind", &"") as StringName
	var cls: StringName = resolved.get("audio_class", &"") as StringName
	match kind:
		&"unit":
			var u_key: StringName = StringName("bark_%s_select" % String(cls))
			_play_on_bark_channel(u_key, -4.5, 0.04, BARK_SELECT_DEBOUNCE_MS, false)
		&"building":
			var b_key: StringName = StringName("bldg_select_%s" % String(cls))
			_play_on_bark_channel(b_key, -5.0, 0.02, BARK_SELECT_DEBOUNCE_MS, false)
		&"inspect":
			_play_on_bark_channel(&"inspect_tick", -10.5, 0.03, BARK_SELECT_DEBOUNCE_MS, false)


func play_order_audio(units: Array, fallback_sfx: StringName = &"order_move") -> void:
	if TeamManager != null and TeamManager.is_spectator_mode():
		return
	var best_cls: StringName = &""
	var best_prio: int = -1
	for item: Variant in units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead:
				var u_cls: StringName = u.data.audio_bark_class if (u.data != null and u.data.audio_bark_class != &"") else classify_unit_bark_class(u.get_unit_type_id())
				var u_prio: int = int(UNIT_CLASS_PRIORITY.get(u_cls, 1))
				if u_prio > best_prio:
					best_prio = u_prio
					best_cls = u_cls
	if best_cls != &"":
		var key: StringName = StringName("bark_%s_order" % String(best_cls))
		_play_on_bark_channel(key, -4.5, 0.05, BARK_ORDER_DEBOUNCE_MS, true)
		return
	if fallback_sfx != &"":
		play_sfx(fallback_sfx, -4.5, 0.04)


func play_unit_bark_for_units(units: Array, bark_type: StringName) -> void:
	if units.is_empty():
		return
	if TeamManager != null and TeamManager.is_spectator_mode():
		return
	if bark_type == &"order":
		play_order_audio(units, &"")
	else:
		play_selection_audio(units)


func classify_unit_bark_class(unit_type_id: StringName) -> StringName:
	match unit_type_id:
		&"worker", &"silica_harvester", &"engineer", &"servo_drone", &"ore_crawler", &"grid_tech":
			return &"worker"
		&"clone_trooper", &"stinger", &"scout_unit", &"picket_drone":
			return &"swarm"
		&"lance_rig", &"signal_jammer", &"rail_sentinel", &"null_grid_projector":
			return &"counter"
		&"symbiote", &"aegis_relay":
			return &"support"
		&"goliath_frame", &"arc_lancer", &"chrysalis_mortar", &"bulwark_automaton", &"anvil_siege_walker", &"monolith_dreadnought":
			return &"heavy"
		_:
			return &"swarm"


func play_unit_bark(unit_class: StringName, bark_type: StringName) -> void:
	if TeamManager != null and TeamManager.is_spectator_mode():
		return
	var key: StringName = StringName("bark_%s_%s" % [String(unit_class), String(bark_type)])
	var is_order: bool = (bark_type == &"order")
	var debounce: int = BARK_ORDER_DEBOUNCE_MS if is_order else BARK_SELECT_DEBOUNCE_MS
	_play_on_bark_channel(key, -4.5, 0.05, debounce, is_order)


func play_ui_click() -> void:
	play_sfx(&"ui_click", -3.0, 0.03)


func play_error() -> void:
	play_sfx(&"error_insufficient", -2.0, 0.0)


func play_bandwidth_near_cap_warning() -> void:
	play_sfx(&"bandwidth_near_cap", -6.0, 0.01)


func play_slider_preview(channel: StringName) -> void:
	match channel:
		&"sfx":
			play_sfx(&"weapon_rifle", -5.5, 0.04)
		&"master", &"ui":
			play_sfx(&"ui_click", -2.5, 0.02)


func play_weapon_sfx(unit_type_id: StringName, world_pos: Vector2 = Vector2.INF) -> void:
	play_weapon_for_unit(unit_type_id, world_pos)


func play_weapon_for_unit_data(unit_data: UnitData, world_pos: Vector2 = Vector2.INF) -> void:
	if unit_data == null:
		play_sfx(&"weapon_rifle", -7.5, 0.06, world_pos, true)
		return
	var sfx: StringName = unit_data.weapon_sfx_id
	match sfx:
		&"weapon_mono_slug":
			play_sfx(&"weapon_mono_slug", -5.0, 0.05, world_pos, true)
		&"weapon_mono_rail":
			play_sfx(&"weapon_mono_rail", -4.2, 0.04, world_pos, true)
		&"weapon_mono_tether":
			play_sfx(&"weapon_mono_tether", -6.2, 0.05, world_pos, true)
		&"weapon_mono_bastion":
			play_sfx(&"weapon_mono_bastion", -4.0, 0.05, world_pos, true)
		&"weapon_mono_siege":
			play_sfx(&"weapon_mono_siege", -3.0, 0.04, world_pos, true)
		&"weapon_slash", &"acid_slash", &"melee_slash", &"bio_slash":
			play_sfx(&"weapon_slash", -6.5, 0.06, world_pos, true)
		&"weapon_rail", &"rail_shot", &"rail_beam", &"arc_lance":
			play_sfx(&"weapon_rail", -5.0, 0.06, world_pos, true)
		&"weapon_mortar", &"mortar_thud", &"siege_mortar":
			play_sfx(&"weapon_mortar", -3.5, 0.06, world_pos, true)
		&"heavy_cannon", &"twin_cannon", &"autocannon":
			play_sfx(&"weapon_mortar", -6.0, 0.06, world_pos, true)
		&"weapon_rifle", &"pulse_rifle", &"pulse_bolt":
			play_sfx(&"weapon_rifle", -7.5, 0.06, world_pos, true)
		_:
			if _streams.has(sfx):
				play_sfx(sfx, -6.5, 0.06, world_pos, true)
			else:
				play_weapon_for_unit(unit_data.unit_type_id, world_pos)


func play_weapon_for_unit(unit_type_id: StringName, world_pos: Vector2 = Vector2.INF) -> void:
	match unit_type_id:
		&"bulwark_automaton", &"monolith_dreadnought":
			play_sfx(&"weapon_mono_slug", -5.0, 0.05, world_pos, true)
		&"anvil_siege_walker":
			play_sfx(&"weapon_mono_siege", -3.2, 0.04, world_pos, true)
		&"rail_sentinel":
			play_sfx(&"weapon_mono_rail", -4.2, 0.04, world_pos, true)
		&"picket_drone", &"null_grid_projector":
			play_sfx(&"weapon_mono_tether", -6.2, 0.05, world_pos, true)
		&"stinger", &"symbiote":
			play_sfx(&"weapon_slash", -6.5, 0.06, world_pos, true)
		&"lance_rig", &"arc_lancer":
			play_sfx(&"weapon_rail", -5.0, 0.06, world_pos, true)
		&"chrysalis_mortar":
			play_sfx(&"weapon_mortar", -3.5, 0.06, world_pos, true)
		&"goliath_frame":
			play_sfx(&"weapon_mortar", -6.0, 0.06, world_pos, true)
		_:
			play_sfx(&"weapon_rifle", -7.5, 0.06, world_pos, true)


func play_explosion_sfx(world_pos: Vector2 = Vector2.INF, volume_db_offset: float = -5.0, is_major_global: bool = false) -> void:
	if is_major_global:
		play_sfx(&"entity_destroyed", volume_db_offset, 0.05, world_pos, false)
	else:
		play_sfx(&"entity_destroyed", volume_db_offset, 0.08, world_pos, true)


func play_build_sfx(sfx_id: StringName = &"build_complete", world_pos: Vector2 = Vector2.INF) -> void:
	play_sfx(sfx_id, -2.5, 0.02, world_pos, false)


func play_ability_sfx(ability_id: StringName, world_pos: Vector2 = Vector2.INF) -> void:
	match ability_id:
		&"adrenal_surge", &"nanite_surge":
			play_sfx(&"ability_adrenal", -3.5, 0.04, world_pos, true)
		&"static_pulse":
			play_sfx(&"ability_static", -3.0, 0.03, world_pos, true)
		&"monolith_suppressive_lock":
			play_sfx(&"ability_suppressive_lock", -3.2, 0.04, world_pos, true)
		&"monolith_shield_overcharge":
			play_sfx(&"ability_shield_overcharge", -2.8, 0.03, world_pos, true)
		&"kinetic_barrier":
			play_sfx(&"ability_kinetic_barrier", -2.4, 0.03, world_pos, true)
		&"grav_pulse":
			play_sfx(&"ability_grav_pulse", -2.2, 0.04, world_pos, true)
		&"seismic_slam":
			play_sfx(&"ability_slam", -2.0, 0.04, world_pos, true)
		&"spore_barrage", &"overcharge_pulse":
			play_sfx(&"ability_barrage", -2.5, 0.04, world_pos, true)
		_:
			play_sfx(&"ability_adrenal", -4.0, 0.04, world_pos, true)


func play_tactical_alert(alert_type: StringName) -> void:
	if SettingsManager != null and not SettingsManager.show_alert_toasts:
		return
	trigger_ambience_duck(1.8)
	match alert_type:
		&"under_attack", &"damage":
			play_sfx(&"alert_under_attack", -3.5, 0.02)
		&"uplink_contested", &"uplink":
			play_sfx(&"alert_uplink", -3.0, 0.02)
		&"tech_complete", &"upgrade", &"construction":
			play_sfx(&"alert_complete", -3.5, 0.01)
		_:
			play_sfx(&"alert_complete", -4.5, 0.02)


func _acquire_combat_player(now_ms: int) -> AudioStreamPlayer:
	for i: int in range(_combat_players.size()):
		if not _combat_players[i].playing:
			_combat_start_ms[i] = now_ms
			return _combat_players[i]
	# Steal the oldest active combat voice so the pool stays strictly capped at COMBAT_POOL_SIZE.
	var oldest_idx: int = 0
	var oldest_ms: int = _combat_start_ms[0]
	for i: int in range(1, _combat_players.size()):
		if _combat_start_ms[i] < oldest_ms:
			oldest_ms = _combat_start_ms[i]
			oldest_idx = i
	var stolen: AudioStreamPlayer = _combat_players[oldest_idx]
	stolen.stop()
	_combat_start_ms[oldest_idx] = now_ms
	return stolen


func _acquire_ui_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _ui_players:
		if not p.playing:
			return p
	var fallback: AudioStreamPlayer = _ui_players[_next_ui_idx]
	_next_ui_idx = (_next_ui_idx + 1) % _ui_players.size()
	fallback.stop()
	return fallback


func _apply_master_bus_settings() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	AudioServer.set_bus_mute(master_idx, is_effectively_muted() or master_volume_linear <= 0.005)
	AudioServer.set_bus_volume_db(master_idx, _slider_to_db(master_volume_linear))


func _generate_procedural_library() -> void:
	# UI & Command Feedback
	_streams[&"ui_click"] = _synth_glass_click()
	_streams[&"unit_select"] = _synth_chime(PackedFloat32Array([740.0, 1110.0]), 0.055, 0.24)
	_streams[&"inspect_tick"] = _synth_chime(PackedFloat32Array([920.0]), 0.035, 0.18)
	_streams[&"bldg_select_production"] = _synth_chord_swell(PackedFloat32Array([261.63, 392.0, 523.25]), 0.20, 0.24)
	_streams[&"bldg_select_hub"] = _synth_chord_swell(PackedFloat32Array([146.83, 220.0, 329.63]), 0.24, 0.28)
	_streams[&"bldg_select_tech"] = _synth_chime(PackedFloat32Array([587.33, 880.0]), 0.05, 0.20)
	_streams[&"bldg_select_defense"] = _synth_chirp(420.0, 680.0, 0.12, 0.22)
	_streams[&"bldg_select_utility"] = _synth_chime(PackedFloat32Array([493.88, 739.99]), 0.045, 0.18)
	_streams[&"order_move"] = _synth_chirp(520.0, 780.0, 0.085, 0.24)
	_streams[&"order_attack"] = _synth_double_chirp(660.0, 440.0, 0.095, 0.28)
	_streams[&"order_gather"] = _synth_chime(PackedFloat32Array([440.0, 660.0]), 0.065, 0.24)

	# Completion & Economy Alerts
	_streams[&"build_complete"] = _synth_chime(PackedFloat32Array([523.25, 659.25, 783.99, 1046.5]), 0.075, 0.28)
	_streams[&"upgrade_complete"] = _synth_chord_swell(PackedFloat32Array([440.0, 554.37, 659.25, 880.0]), 0.42, 0.26)
	_streams[&"unit_ready"] = _synth_chime(PackedFloat32Array([622.25, 932.33]), 0.065, 0.23)
	_streams[&"error_insufficient"] = _synth_error_buzz()
	_streams[&"bandwidth_near_cap"] = _synth_chime(PackedFloat32Array([587.33, 523.25]), 0.075, 0.19)

	# Combat & Ability SFX
	_streams[&"weapon_rifle"] = _synth_rifle_burst()
	_streams[&"weapon_slash"] = _synth_acid_snap()
	_streams[&"weapon_rail"] = _synth_rail_zap()
	_streams[&"weapon_mortar"] = _synth_mortar_thud()
	_streams[&"weapon_mono_slug"] = _synth_mono_slug()
	_streams[&"weapon_mono_rail"] = _synth_mono_rail()
	_streams[&"weapon_mono_tether"] = _synth_mono_tether()
	_streams[&"weapon_mono_bastion"] = _synth_mono_bastion()
	_streams[&"weapon_mono_siege"] = _synth_mono_siege()
	_streams[&"ability_adrenal"] = _synth_adrenal_hum()
	_streams[&"ability_static"] = _synth_static_pulse()
	_streams[&"ability_slam"] = _synth_seismic_slam()
	_streams[&"ability_barrage"] = _synth_mortar_thud()
	_streams[&"ability_shield_overcharge"] = _synth_mono_shield_overcharge()
	_streams[&"ability_suppressive_lock"] = _synth_mono_suppressive_lock()
	_streams[&"ability_kinetic_barrier"] = _synth_mono_kinetic_barrier()
	_streams[&"ability_grav_pulse"] = _synth_mono_grav_pulse()
	_streams[&"entity_destroyed"] = _synth_destruction_boom()
	_streams[&"shield_shatter"] = _synth_shield_shatter()

	# Tactical Alerts, Veterancy, Salvage & Auto-Cast
	_streams[&"alert_under_attack"] = _synth_alert_under_attack()
	_streams[&"alert_uplink"] = _synth_alert_uplink()
	_streams[&"alert_complete"] = _synth_alert_complete()
	_streams[&"veterancy_rank_up"] = _synth_rank_up_chime()
	_streams[&"salvage_claimed"] = _synth_chime(PackedFloat32Array([587.33, 783.99, 1174.66, 1567.98]), 0.045, 0.25)
	_streams[&"autocast_toggle"] = _synth_chime(PackedFloat32Array([880.0, 1318.5]), 0.04, 0.20)
	_streams[&"relay_captured"] = _synth_chime(PackedFloat32Array([659.25, 987.77, 1318.51]), 0.06, 0.22)
	_streams[&"overclock_activate"] = _synth_mono_overclock()
	_streams[&"deploy_lock"] = _synth_double_chirp(320.0, 145.0, 0.14, 0.28)
	_streams[&"deploy_release"] = _synth_double_chirp(185.0, 380.0, 0.13, 0.24)

	# Unit-Class Procedural Synth Barks (150–240ms) — GENESIS_V2 baseline
	_streams[&"bark_worker_select"] = _synth_bark_worker(false)
	_streams[&"bark_worker_order"] = _synth_bark_worker(true)
	_streams[&"bark_swarm_select"] = _synth_bark_swarm(false)
	_streams[&"bark_swarm_order"] = _synth_bark_swarm(true)
	_streams[&"bark_counter_select"] = _synth_bark_counter(false)
	_streams[&"bark_counter_order"] = _synth_bark_counter(true)
	_streams[&"bark_support_select"] = _synth_bark_support(false)
	_streams[&"bark_support_order"] = _synth_bark_support(true)
	_streams[&"bark_heavy_select"] = _synth_bark_heavy(false)
	_streams[&"bark_heavy_order"] = _synth_bark_heavy(true)

	# MONOLITH_OS Industrial Timbre Barks & Building Selects (&"monolith_industrial")
	_streams[&"mono_bark_worker_select"] = _synth_mono_bark(PackedFloat32Array([311.13, 466.16]), false)
	_streams[&"mono_bark_worker_order"] = _synth_mono_bark(PackedFloat32Array([349.23, 523.25]), true)
	_streams[&"mono_bark_swarm_select"] = _synth_mono_bark(PackedFloat32Array([392.0, 587.33]), false)
	_streams[&"mono_bark_swarm_order"] = _synth_mono_bark(PackedFloat32Array([440.0, 659.25]), true)
	_streams[&"mono_bark_counter_select"] = _synth_mono_bark(PackedFloat32Array([261.63, 392.0, 523.25]), false)
	_streams[&"mono_bark_counter_order"] = _synth_mono_bark(PackedFloat32Array([293.66, 440.0, 587.33]), true)
	_streams[&"mono_bark_support_select"] = _synth_mono_bark(PackedFloat32Array([329.63, 493.88, 659.25]), false)
	_streams[&"mono_bark_support_order"] = _synth_mono_bark(PackedFloat32Array([392.0, 587.33, 783.99]), true)
	_streams[&"mono_bark_heavy_select"] = _synth_mono_bark(PackedFloat32Array([146.83, 220.0]), false)
	_streams[&"mono_bark_heavy_order"] = _synth_mono_bark(PackedFloat32Array([164.81, 246.94]), true)
	_streams[&"mono_bldg_select_hub"] = _synth_mono_bark(PackedFloat32Array([110.0, 164.81, 220.0]), false)
	_streams[&"mono_bldg_select_production"] = _synth_mono_bark(PackedFloat32Array([146.83, 220.0, 293.66]), false)
	_streams[&"mono_bldg_select_tech"] = _synth_mono_bark(PackedFloat32Array([220.0, 329.63, 440.0]), false)
	_streams[&"mono_bldg_select_defense"] = _synth_mono_bark(PackedFloat32Array([174.61, 261.63]), true)
	_streams[&"mono_bldg_select_utility"] = _synth_mono_bark(PackedFloat32Array([196.0, 293.66]), false)

	# Match Flow
	_streams[&"match_victory"] = _synth_chime(PackedFloat32Array([523.25, 659.25, 783.99, 1046.5, 1318.5]), 0.11, 0.30)
	_streams[&"match_defeat"] = _synth_chime(PackedFloat32Array([440.0, 392.0, 329.63, 246.94]), 0.14, 0.30)


func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		var clamped: float = clampf(samples[i], -0.95, 0.95)
		var pcm: int = int(round(clamped * 32767.0))
		if pcm < 0:
			pcm += 65536
		bytes[i * 2] = pcm & 0xFF
		bytes[i * 2 + 1] = (pcm >> 8) & 0xFF
	wav.data = bytes
	return wav


func _synth_glass_click() -> AudioStreamWAV:
	var count: int = int(SAMPLE_RATE * 0.055)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.002) * exp(-t * 68.0)
		var s: float = sin(TAU * 1380.0 * t) * 0.6 + sin(TAU * 2760.0 * t) * 0.32 + sin(TAU * 4140.0 * t) * 0.08
		out[i] = s * env * 0.32
	return _make_wav(out)


func _synth_chime(freqs: PackedFloat32Array, step_dur: float, amp: float) -> AudioStreamWAV:
	var tail: float = 0.16
	var total_dur: float = step_dur * float(freqs.size()) + tail
	var count: int = int(SAMPLE_RATE * total_dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	out.fill(0.0)
	for idx: int in range(freqs.size()):
		var f: float = freqs[idx]
		var start_t: float = float(idx) * step_dur
		var start_i: int = int(start_t * float(SAMPLE_RATE))
		var note_len: int = int((step_dur + tail) * float(SAMPLE_RATE))
		for j: int in range(note_len):
			var pos: int = start_i + j
			if pos >= count:
				break
			var lt: float = float(j) / float(SAMPLE_RATE)
			var env: float = minf(1.0, lt / 0.005) * exp(-lt * 14.0)
			var wave: float = sin(TAU * f * lt) * 0.75 + sin(TAU * f * 2.0 * lt) * 0.25
			out[pos] += wave * env * amp
	return _make_wav(out)


func _synth_chord_swell(freqs: PackedFloat32Array, duration: float, amp: float) -> AudioStreamWAV:
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var inv_n: float = 1.0 / maxf(1.0, float(freqs.size()))
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var norm: float = t / duration
		var env: float = sin(PI * norm) * exp(-norm * 1.4)
		var sum: float = 0.0
		for f: float in freqs:
			sum += sin(TAU * f * t) * 0.8 + sin(TAU * f * 2.0 * t) * 0.2
		out[i] = sum * inv_n * env * amp
	return _make_wav(out)


func _synth_chirp(f0: float, f1: float, duration: float, amp: float) -> AudioStreamWAV:
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(f0, f1, u)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.004) * exp(-u * 4.5)
		out[i] = (sin(phase) * 0.78 + sin(phase * 2.0) * 0.22) * env * amp
	return _make_wav(out)


func _synth_double_chirp(f0: float, f1: float, duration: float, amp: float) -> AudioStreamWAV:
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var pulse_u: float = fmod(u * 2.0, 1.0)
		var freq: float = lerpf(f0, f1, pulse_u)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env: float = minf(1.0, pulse_u / 0.08) * exp(-pulse_u * 4.2) * (1.0 - 0.25 * u)
		out[i] = (sin(phase) * 0.7 + clampf(sin(phase * 1.5) * 1.3, -1.0, 1.0) * 0.3) * env * amp
	return _make_wav(out)


func _synth_error_buzz() -> AudioStreamWAV:
	var duration: float = 0.22
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var second_half: bool = t >= 0.105
		var lt: float = (t - 0.105) if second_half else t
		var f: float = 175.0 if second_half else 220.0
		var env: float = minf(1.0, lt / 0.005) * exp(-lt * 16.0)
		if t > 0.088 and t < 0.105:
			env = 0.0
		var saw: float = 2.0 * fmod(lt * f, 1.0) - 1.0
		var soft_wave: float = sin(TAU * f * lt) * 0.65 + saw * 0.35
		out[i] = soft_wave * env * 0.30
	return _make_wav(out)


func _synth_rifle_burst() -> AudioStreamWAV:
	var duration: float = 0.09
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 1337
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(420.0, 110.0, u)
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.35)
		var env: float = minf(1.0, t / 0.002) * exp(-u * 6.5)
		out[i] = (sin(phase) * 0.55 + lp * 0.45) * env * 0.30
	return _make_wav(out)


func _synth_acid_snap() -> AudioStreamWAV:
	var duration: float = 0.095
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 4242
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(1180.0, 260.0, u * u)
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		var env: float = minf(1.0, t / 0.002) * exp(-u * 7.0)
		out[i] = (sin(phase) * 0.62 + noise * 0.38) * env * 0.28
	return _make_wav(out)


func _synth_rail_zap() -> AudioStreamWAV:
	var duration: float = 0.17
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(1680.0, 190.0, pow(u, 0.65))
		var mod: float = sin(TAU * 95.0 * t) * 180.0
		phase += TAU * (freq + mod) / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.003) * exp(-u * 4.8)
		out[i] = clampf(sin(phase) * 1.4, -1.0, 1.0) * env * 0.30
	return _make_wav(out)


func _synth_mortar_thud() -> AudioStreamWAV:
	var duration: float = 0.28
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 9001
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(155.0, 38.0, pow(u, 0.55))
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.16)
		var env: float = minf(1.0, t / 0.004) * exp(-u * 4.6)
		out[i] = (sin(phase) * 0.68 + lp * 0.52) * env * 0.36
	return _make_wav(out)


func _synth_adrenal_hum() -> AudioStreamWAV:
	var duration: float = 0.26
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(280.0, 680.0, u)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env: float = sin(PI * u)
		out[i] = (sin(phase) * 0.65 + sin(phase * 1.5) * 0.35) * env * 0.28
	return _make_wav(out)


func _synth_static_pulse() -> AudioStreamWAV:
	var duration: float = 0.30
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 7711
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(720.0, 210.0, u) + sin(TAU * 42.0 * t) * 120.0
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		var env: float = minf(1.0, t / 0.008) * exp(-u * 3.6)
		out[i] = (sin(phase) * 0.6 + noise * 0.25) * env * 0.28
	return _make_wav(out)


func _synth_seismic_slam() -> AudioStreamWAV:
	var duration: float = 0.36
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 5150
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(135.0, 28.0, pow(u, 0.5))
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.12)
		var env: float = minf(1.0, t / 0.003) * exp(-u * 4.0)
		out[i] = clampf((sin(phase) * 0.8 + lp * 0.65) * 1.15, -1.0, 1.0) * env * 0.38
	return _make_wav(out)


func _synth_destruction_boom() -> AudioStreamWAV:
	var duration: float = 0.34
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 2026
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(120.0, 32.0, u)
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.18)
		var env: float = minf(1.0, t / 0.005) * exp(-u * 4.5)
		out[i] = (sin(phase) * 0.5 + lp * 0.65) * env * 0.32
	return _make_wav(out)


func _synth_alert_under_attack() -> AudioStreamWAV:
	# Urgent two-tone low-mid pulse (non-shrill Technozen warning)
	var duration: float = 0.28
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var second: bool = t >= 0.135
		var lt: float = (t - 0.135) if second else t
		var freq: float = 340.0 if second else 440.0
		var env: float = minf(1.0, lt / 0.006) * exp(-lt * 15.0)
		if t > 0.105 and t < 0.135:
			env = 0.0
		var wave: float = sin(TAU * freq * lt) * 0.72 + sin(TAU * freq * 1.5 * lt) * 0.28
		out[i] = wave * env * 0.28
	return _make_wav(out)


func _synth_alert_uplink() -> AudioStreamWAV:
	# Resonant ascending sonar ping
	var duration: float = 0.34
	var count: int = int(SAMPLE_RATE * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / duration
		var freq: float = lerpf(520.0, 980.0, pow(u, 0.7))
		phase += TAU * freq / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.01) * exp(-u * 3.8)
		out[i] = (sin(phase) * 0.76 + sin(phase * 2.0) * 0.24) * env * 0.26
	return _make_wav(out)


func _synth_alert_complete() -> AudioStreamWAV:
	return _synth_chime(PackedFloat32Array([587.33, 880.0, 1174.66]), 0.065, 0.23)


func _synth_rank_up_chime() -> AudioStreamWAV:
	return _synth_chime(PackedFloat32Array([659.25, 880.0, 1318.5]), 0.055, 0.22)


func _make_loop_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav: AudioStreamWAV = _make_wav(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav


func _synth_ambience_base_loop() -> AudioStreamWAV:
	# 4.0s exact harmonic cycle: warm Y2K/Technozen D-minor9 low-pass pad + soft crystalline pulse
	var dur: float = 4.0
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var freqs: PackedFloat32Array = PackedFloat32Array([73.5, 110.25, 147.0, 220.5, 294.0])
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var lfo: float = 0.72 + 0.28 * sin(TAU * 0.25 * t)
		var pulse: float = 0.5 + 0.5 * sin(TAU * 0.5 * t)
		var pad: float = 0.0
		for f: float in freqs:
			pad += sin(TAU * f * t)
		pad *= 0.16 * lfo
		var shimmer: float = sin(TAU * 588.0 * t) * (0.045 * pulse * pulse)
		lp = lerpf(lp, pad + shimmer, 0.12)
		out[i] = lp * 0.65
	return _make_loop_wav(out)


func _synth_ambience_combat_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: subtle rhythmic sub-bass pulse + filtered Technozen 16th-note arpeggio
	var dur: float = 4.0
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var arp_notes: PackedFloat32Array = PackedFloat32Array([147.0, 174.5, 220.5, 261.5, 220.5, 174.5, 147.0, 130.75])
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var beat_u: float = fmod(t * 2.0, 1.0)
		var sub_env: float = exp(-beat_u * 4.2)
		var sub: float = sin(TAU * 55.0 * t) * sub_env * 0.34
		var step_idx: int = int(floor(t * 4.0)) % arp_notes.size()
		var step_u: float = fmod(t * 4.0, 1.0)
		var arp_env: float = minf(1.0, step_u / 0.06) * exp(-step_u * 5.0)
		var arp_f: float = arp_notes[step_idx]
		var arp: float = (sin(TAU * arp_f * t) * 0.7 + sin(TAU * arp_f * 2.0 * t) * 0.3) * arp_env * 0.18
		lp = lerpf(lp, sub + arp, 0.22)
		out[i] = lp * 0.72
	return _make_loop_wav(out)


func _synth_ambience_uplink_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: ethereal crystalline harmonic shimmer for Data Hyper-Uplink tension
	var dur: float = 4.0
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var swell: float = 0.55 + 0.45 * sin(TAU * 0.5 * t)
		var s: float = sin(TAU * 441.0 * t) * 0.35 + sin(TAU * 661.5 * t) * 0.30 + sin(TAU * 882.0 * t) * 0.20
		out[i] = s * swell * 0.26
	return _make_loop_wav(out)


func _synth_bark_worker(is_order: bool) -> AudioStreamWAV:
	# Nimble dual-tone telemetry beep (160ms)
	var f0: float = 780.0 if is_order else 660.0
	var f1: float = 1170.0 if is_order else 990.0
	return _synth_chime(PackedFloat32Array([f0, f1]), 0.055, 0.20)


func _synth_bark_swarm(is_order: bool) -> AudioStreamWAV:
	# Tight high-energy metallic chirp cadence (165ms)
	var dur: float = 0.165
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var f_start: float = 640.0 if is_order else 520.0
		var f_end: float = 1080.0 if is_order else 820.0
		var pulse_u: float = fmod(u * 2.0, 1.0)
		var freq: float = lerpf(f_start, f_end, pulse_u)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env: float = minf(1.0, pulse_u / 0.08) * exp(-pulse_u * 4.8)
		out[i] = (sin(phase) * 0.68 + sin(phase * 2.5) * 0.32) * env * 0.22
	return _make_wav(out)


func _synth_bark_counter(is_order: bool) -> AudioStreamWAV:
	# Crisp ionized harmonic lock-on tone (190ms)
	var dur: float = 0.19
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var freq: float = lerpf(920.0, 1380.0, u) if is_order else lerpf(1240.0, 860.0, u)
		phase += TAU * (freq + sin(TAU * 55.0 * t) * 45.0) / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.008) * exp(-u * 3.8)
		out[i] = (sin(phase) * 0.72 + sin(phase * 1.5) * 0.28) * env * 0.22
	return _make_wav(out)


func _synth_bark_support(is_order: bool) -> AudioStreamWAV:
	# Warm airy bio-synth chime (210ms)
	var notes: PackedFloat32Array = PackedFloat32Array([523.25, 659.25, 987.77]) if is_order else PackedFloat32Array([440.0, 659.25])
	return _synth_chime(notes, 0.055, 0.20)


func _synth_bark_heavy(is_order: bool) -> AudioStreamWAV:
	# Deep resonant sub-bass servo thrum + metallic confirmation ping (230ms)
	var dur: float = 0.23
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var base_f: float = lerpf(115.0, 82.0, u) if is_order else lerpf(92.0, 128.0, u)
		phase += TAU * base_f / float(SAMPLE_RATE)
		var sub_env: float = minf(1.0, t / 0.012) * exp(-u * 3.2)
		var ping_t: float = maxf(0.0, t - 0.065)
		var ping_env: float = (minf(1.0, ping_t / 0.004) * exp(-ping_t * 20.0)) if t >= 0.065 else 0.0
		var ping_f: float = 620.0 if is_order else 490.0
		var ping: float = sin(TAU * ping_f * ping_t) * ping_env * 0.35
		out[i] = (sin(phase) * 0.65 + sin(phase * 2.0) * 0.20) * sub_env * 0.32 + ping * 0.28
	return _make_wav(out)


# =============================================================================
# MONOLITH_OS — INDUSTRIAL PROCEDURAL SYNTHS
# =============================================================================

func _synth_mono_slug() -> AudioStreamWAV:
	# Heavy low-mid mechanical thump + crisp metallic bolt clack
	var dur: float = 0.15
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 31337
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var freq: float = lerpf(210.0, 58.0, pow(u, 0.55))
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.28)
		var thump_env: float = minf(1.0, t / 0.002) * exp(-u * 6.0)
		var clack_t: float = maxf(0.0, t - 0.042)
		var clack_env: float = (minf(1.0, clack_t / 0.0015) * exp(-clack_t * 62.0)) if t >= 0.042 else 0.0
		var clack: float = (sin(TAU * 1420.0 * clack_t) * 0.5 + sin(TAU * 2380.0 * clack_t) * 0.35 + noise * 0.25) * clack_env
		out[i] = clampf((sin(phase) * 0.72 + lp * 0.40) * thump_env * 0.36 + clack * 0.22, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_rail() -> AudioStreamWAV:
	# Rising high-voltage capacitor whine -> crisp sub-bass crack + metallic ring
	var dur: float = 0.24
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase_whine: float = 0.0
	var phase_crack: float = 0.0
	var seed_val: int = 8088
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var sample: float = 0.0
		if t < 0.045:
			var uw: float = t / 0.045
			var fw: float = lerpf(620.0, 2100.0, uw * uw)
			phase_whine += TAU * fw / float(SAMPLE_RATE)
			sample += sin(phase_whine) * (0.14 * uw)
		else:
			var lt: float = t - 0.045
			var uc: float = lt / (dur - 0.045)
			var fc: float = lerpf(260.0, 46.0, pow(uc, 0.45))
			phase_crack += TAU * fc / float(SAMPLE_RATE)
			seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
			var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
			var crack_env: float = minf(1.0, lt / 0.0015) * exp(-uc * 5.2)
			var ring_env: float = exp(-lt * 16.0)
			var ring: float = (sin(TAU * 1180.0 * lt) * 0.55 + sin(TAU * 1770.0 * lt) * 0.45) * ring_env * 0.16
			sample += (clampf(sin(phase_crack) * 1.35, -1.0, 1.0) * 0.65 + noise * 0.35 * exp(-lt * 40.0)) * crack_env * 0.36 + ring
		out[i] = clampf(sample, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_tether() -> AudioStreamWAV:
	# Tight rhythmic electrical zap / stun pulse (Picket Drone)
	var dur: float = 0.12
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var pulse_u: float = fmod(u * 3.0, 1.0)
		var freq: float = lerpf(1260.0, 440.0, pulse_u) + sin(TAU * 120.0 * t) * 110.0
		phase += TAU * freq / float(SAMPLE_RATE)
		var env: float = minf(1.0, pulse_u / 0.08) * exp(-pulse_u * 4.5) * (1.0 - 0.35 * u)
		var sq: float = clampf(sin(phase) * 1.6, -1.0, 1.0)
		out[i] = sq * env * 0.25
	return _make_wav(out)


func _synth_mono_bastion() -> AudioStreamWAV:
	# Deep pneumatic autocannon boom (Bastion Emplacement)
	var dur: float = 0.26
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 55101
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var freq: float = lerpf(165.0, 42.0, pow(u, 0.48))
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.20)
		var boom_env: float = minf(1.0, t / 0.0025) * exp(-u * 4.8)
		var hiss_t: float = maxf(0.0, t - 0.07)
		var hiss_env: float = (minf(1.0, hiss_t / 0.01) * exp(-hiss_t * 22.0)) if t >= 0.07 else 0.0
		var hiss: float = (noise - lp) * hiss_env * 0.14
		out[i] = clampf((sin(phase) * 0.78 + lp * 0.48) * boom_env * 0.38 + hiss, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_overclock() -> AudioStreamWAV:
	# Deep industrial turbine spin-up + resonant quantized Axiom chime
	var dur: float = 0.42
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase_turb: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var turb_f: float = lerpf(95.0, 340.0, pow(u, 0.72))
		phase_turb += TAU * turb_f / float(SAMPLE_RATE)
		var turb_env: float = sin(PI * u) * 0.75
		var turb: float = (sin(phase_turb) * 0.65 + sin(phase_turb * 2.0) * 0.25) * turb_env * 0.26
		var chime: float = 0.0
		if t >= 0.14:
			var ct: float = t - 0.14
			var c_env: float = minf(1.0, ct / 0.006) * exp(-ct * 7.5)
			chime = (sin(TAU * 440.0 * ct) * 0.5 + sin(TAU * 659.25 * ct) * 0.35 + sin(TAU * 880.0 * ct) * 0.15) * c_env * 0.24
		out[i] = clampf(turb + chime, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_shield_overcharge() -> AudioStreamWAV:
	# Resonant harmonic shield-capacitor surge + crisp barrier lock chime (Aegis Relay)
	var dur: float = 0.32
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var f_sweep: float = lerpf(260.0, 780.0, pow(u, 0.6))
		phase += TAU * f_sweep / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.012) * exp(-u * 3.2)
		var lock: float = 0.0
		if t >= 0.10:
			var lt: float = t - 0.10
			var l_env: float = minf(1.0, lt / 0.004) * exp(-lt * 11.0)
			lock = (sin(TAU * 587.33 * lt) * 0.55 + sin(TAU * 880.0 * lt) * 0.45) * l_env * 0.22
		out[i] = clampf((sin(phase) * 0.65 + sin(phase * 1.5) * 0.35) * env * 0.24 + lock, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_suppressive_lock() -> AudioStreamWAV:
	# Quantized downward clamp-lock stun pulse (Picket Drone)
	var dur: float = 0.22
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var step_f: float = 780.0 if u < 0.33 else (520.0 if u < 0.66 else 260.0)
		phase += TAU * (step_f + sin(TAU * 64.0 * t) * 55.0) / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.004) * exp(-u * 4.2)
		out[i] = clampf(sin(phase) * 1.3, -1.0, 1.0) * env * 0.26
	return _make_wav(out)


func _synth_mono_bark(notes: PackedFloat32Array, is_order: bool) -> AudioStreamWAV:
	# Lower-pitched quantized harmonic tones + crisp mechanical relay click (170-220ms)
	var step_dur: float = 0.050 if is_order else 0.058
	var tail: float = 0.095
	var total_dur: float = step_dur * float(notes.size()) + tail
	var count: int = int(SAMPLE_RATE * total_dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	out.fill(0.0)
	var seed_val: int = 4409
	# Initial crisp mechanical relay click (first 16ms)
	var click_len: int = mini(count, int(SAMPLE_RATE * 0.016))
	for c: int in range(click_len):
		var ct: float = float(c) / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var n: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		var c_env: float = exp(-ct * 190.0)
		out[c] += (sin(TAU * 1650.0 * ct) * 0.55 + n * 0.45) * c_env * 0.22
	# Quantized harmonic industrial steps
	for idx: int in range(notes.size()):
		var f: float = notes[idx]
		var start_i: int = int((0.012 + float(idx) * step_dur) * float(SAMPLE_RATE))
		var note_len: int = int((step_dur + tail) * float(SAMPLE_RATE))
		for j: int in range(note_len):
			var pos: int = start_i + j
			if pos >= count:
				break
			var lt: float = float(j) / float(SAMPLE_RATE)
			var env: float = minf(1.0, lt / 0.004) * exp(-lt * 18.0)
			var wave: float = sin(TAU * f * lt) * 0.68 + clampf(sin(TAU * f * 2.0 * lt) * 1.2, -1.0, 1.0) * 0.22 + sin(TAU * f * 0.5 * lt) * 0.10
			out[pos] = clampf(out[pos] + wave * env * 0.22, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_siege() -> AudioStreamWAV:
	# Deep heavy deployed artillery boom + metallic breech clang (Anvil Siege-Walker)
	var dur: float = 0.38
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 88321
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var freq: float = lerpf(135.0, 32.0, pow(u, 0.42))
		phase += TAU * freq / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.15)
		var boom_env: float = minf(1.0, t / 0.003) * exp(-u * 3.8)
		var clang: float = 0.0
		if t >= 0.06:
			var ct: float = t - 0.06
			var c_env: float = minf(1.0, ct / 0.004) * exp(-ct * 16.0)
			clang = (sin(TAU * 480.0 * ct) * 0.5 + sin(TAU * 725.0 * ct) * 0.35 + (noise - lp) * 0.25) * c_env * 0.16
		out[i] = clampf((sin(phase) * 0.82 + lp * 0.52) * boom_env * 0.44 + clang, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_kinetic_barrier() -> AudioStreamWAV:
	# Heavy metallic hydraulic lock + harmonic cyan barrier hum (Monolith Dreadnought)
	var dur: float = 0.36
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var clank: float = 0.0
		if t < 0.055:
			var c_env: float = exp(-t * 58.0)
			clank = (sin(TAU * 190.0 * t) * 0.6 + sin(TAU * 620.0 * t) * 0.4) * c_env * 0.34
		var sweep_f: float = lerpf(210.0, 520.0, pow(u, 0.55))
		phase += TAU * sweep_f / float(SAMPLE_RATE)
		var hum_env: float = minf(1.0, t / 0.020) * exp(-u * 2.9)
		var hum: float = (sin(phase) * 0.58 + sin(phase * 1.5) * 0.28 + sin(phase * 2.0) * 0.14) * hum_env * 0.26
		out[i] = clampf(clank + hum, -0.95, 0.95)
	return _make_wav(out)


func _synth_mono_grav_pulse() -> AudioStreamWAV:
	# Resonant downward gravity-well compression wave + sub-bass thump (Null-Grid Projector)
	var dur: float = 0.42
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var phase_sub: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var f_drop: float = lerpf(640.0, 88.0, pow(u, 0.58)) + sin(TAU * 28.0 * t) * 42.0
		var f_sub: float = lerpf(110.0, 38.0, u)
		phase += TAU * f_drop / float(SAMPLE_RATE)
		phase_sub += TAU * f_sub / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.015) * exp(-u * 3.1)
		var wave: float = (sin(phase) * 0.55 + clampf(sin(phase * 1.5) * 1.3, -1.0, 1.0) * 0.20 + sin(phase_sub) * 0.45) * env * 0.34
		out[i] = clampf(wave, -0.95, 0.95)
	return _make_wav(out)


func _synth_shield_shatter() -> AudioStreamWAV:
	# Crisp crystalline high-frequency shield snap + rapid downward sweep + brief electric crackle (~0.22s)
	var dur: float = 0.22
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase_hi: float = 0.0
	var phase_sw: float = 0.0
	var seed_val: int = 91827
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var f_hi: float = lerpf(2450.0, 1180.0, pow(u, 0.45))
		var f_sw: float = lerpf(1320.0, 290.0, pow(u, 0.52))
		phase_hi += TAU * f_hi / float(SAMPLE_RATE)
		phase_sw += TAU * f_sw / float(SAMPLE_RATE)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.35)
		var hp_crackle: float = noise - lp
		var snap_env: float = minf(1.0, t / 0.0018) * exp(-u * 6.2)
		var crackle_env: float = minf(1.0, t / 0.004) * exp(-u * 8.5)
		var sig: float = (sin(phase_hi) * 0.45 + sin(phase_sw) * 0.55) * snap_env * 0.32 + hp_crackle * crackle_env * 0.24
		out[i] = clampf(sig, -0.95, 0.95)
	return _make_wav(out)
