extends Node

signal mute_changed(is_muted: bool)
signal volume_changed(volume_linear: float)

const SAMPLE_RATE: int = SynthPrimitives.SAMPLE_RATE
const COMBAT_POOL_SIZE: int = 10
const UI_POOL_SIZE: int = 8
const BARK_SELECT_DEBOUNCE_MS: int = 120
const BARK_ORDER_DEBOUNCE_MS: int = 450
const DEFAULT_AUDIO_PROFILE: StringName = &"technozen_bio"

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
var _audio_profiles: Dictionary = {} # StringName -> FactionAudioProfile
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
var _amb_profile_cache: Dictionary = {}
var _active_amb_profile: StringName = DEFAULT_AUDIO_PROFILE
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
	&"entity_destroyed": 95,
	&"shield_shatter": 85,
	&"alert_under_attack": 1800,
	&"alert_uplink": 1400,
	&"alert_complete": 700,
	&"veterancy_rank_up": 350,
	&"salvage_claimed": 180,
	&"autocast_toggle": 60,
	&"relay_captured": 450,
	&"deploy_lock": 90,
	&"deploy_release": 90,
	&"weapon_prism_beam": 80,
	&"weapon_prism_refract": 75,
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

	_register_builtin_profiles()
	_generate_procedural_library()
	_setup_ambience_players()
	_sync_from_settings()
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(refresh_faction_ambience_profile):
		TeamManager.teams_reconfigured.connect(refresh_faction_ambience_profile)
	_apply_master_bus_settings()


func _register_builtin_profiles() -> void:
	register_audio_profile(GenesisAudioProfile.new(), false)
	register_audio_profile(MonolithAudioProfile.new(), false)


func register_audio_profile(profile: FactionAudioProfile, populate_immediately: bool = true) -> void:
	if profile == null:
		return
	var pid: StringName = profile.get_profile_id()
	if pid == &"":
		return
	_audio_profiles[pid] = profile
	_amb_profile_cache.erase(pid)
	if populate_immediately:
		profile.register_cooldowns(_cooldowns_ms)
		profile.build_weapon_and_ability_sfx(_streams)
		profile.build_bark_sfx(_streams)


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
		refresh_faction_ambience_profile()
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


func _resolve_desired_ambience_profile() -> StringName:
	if not is_inside_tree():
		return DEFAULT_AUDIO_PROFILE
	var in_match: bool = get_tree().get_first_node_in_group("match_manager") != null
	if not in_match:
		return DEFAULT_AUDIO_PROFILE
	if TeamManager != null and TeamManager.has_method("is_spectator_mode") and TeamManager.is_spectator_mode():
		return DEFAULT_AUDIO_PROFILE
	var prof: StringName = _get_local_faction_timbre_profile()
	return prof if _audio_profiles.has(prof) else DEFAULT_AUDIO_PROFILE


func _get_or_build_ambience_profile(profile_id: StringName) -> Dictionary:
	var resolved_id: StringName = profile_id if _audio_profiles.has(profile_id) else DEFAULT_AUDIO_PROFILE
	if _amb_profile_cache.has(resolved_id):
		return _amb_profile_cache[resolved_id] as Dictionary
	var profile: FactionAudioProfile = _audio_profiles.get(resolved_id, null) as FactionAudioProfile
	var pack: Dictionary = profile.build_ambient_layers() if profile != null else {}
	_amb_profile_cache[resolved_id] = pack
	return pack


func refresh_faction_ambience_profile() -> void:
	if _amb_base_player == null:
		return
	var desired: StringName = _resolve_desired_ambience_profile()
	if desired == _active_amb_profile:
		return
	_active_amb_profile = desired
	var pack: Dictionary = _get_or_build_ambience_profile(desired)
	if pack.is_empty():
		return
	_amb_base_player.stream = pack["base"] as AudioStreamWAV
	_amb_combat_player.stream = pack["combat"] as AudioStreamWAV
	_amb_uplink_player.stream = pack["uplink"] as AudioStreamWAV
	_amb_base_player.play()
	_amb_combat_player.play()
	_amb_uplink_player.play()
	_update_ambience_mix(is_inside_tree() and get_tree().paused)


func _setup_ambience_players() -> void:
	_active_amb_profile = DEFAULT_AUDIO_PROFILE
	var initial_pack: Dictionary = _get_or_build_ambience_profile(_active_amb_profile)
	_amb_base_player = AudioStreamPlayer.new()
	_amb_base_player.name = "AmbBasePlayer"
	_amb_base_player.bus = &"Master"
	_amb_base_player.stream = initial_pack.get("base", null) as AudioStreamWAV
	_amb_base_player.volume_db = -80.0
	add_child(_amb_base_player)
	_amb_base_player.play()

	_amb_combat_player = AudioStreamPlayer.new()
	_amb_combat_player.name = "AmbCombatPlayer"
	_amb_combat_player.bus = &"Master"
	_amb_combat_player.stream = initial_pack.get("combat", null) as AudioStreamWAV
	_amb_combat_player.volume_db = -80.0
	add_child(_amb_combat_player)
	_amb_combat_player.play()

	_amb_uplink_player = AudioStreamPlayer.new()
	_amb_uplink_player.name = "AmbUplinkPlayer"
	_amb_uplink_player.bus = &"Master"
	_amb_uplink_player.stream = initial_pack.get("uplink", null) as AudioStreamWAV
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
	allow_offscreen_cull: bool = true,
	base_pitch: float = 1.0
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
		player.pitch_scale = maxf(0.25, base_pitch + randf_range(-pitch_jitter, pitch_jitter))
	else:
		player.pitch_scale = maxf(0.25, base_pitch)
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
		return DEFAULT_AUDIO_PROFILE
	var local_team: int = TeamManager.get_local_human_team()
	if local_team < 0:
		return DEFAULT_AUDIO_PROFILE
	var fdata: FactionData = TeamManager.get_team_faction_data(local_team)
	if fdata != null and fdata.audio_timbre_profile != &"":
		return fdata.audio_timbre_profile
	return DEFAULT_AUDIO_PROFILE


func _resolve_timbre_stream_key(base_key: StringName) -> StringName:
	var prof_id: StringName = _get_local_faction_timbre_profile()
	var profile: FactionAudioProfile = _audio_profiles.get(prof_id, null) as FactionAudioProfile
	if profile != null:
		var prefix: String = profile.get_stream_prefix()
		if not prefix.is_empty():
			var prefixed_key: StringName = StringName("%s%s" % [prefix, String(base_key)])
			if _streams.has(prefixed_key):
				return prefixed_key
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
		&"clone_trooper", &"stinger", &"picket_drone":
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
	for profile_val: Variant in _audio_profiles.values():
		var profile: FactionAudioProfile = profile_val as FactionAudioProfile
		if profile != null:
			var resolved: Dictionary = profile.resolve_weapon_sfx(sfx, &"")
			if not resolved.is_empty():
				play_sfx(resolved["sfx_id"] as StringName, float(resolved["db"]), float(resolved["jitter"]), world_pos, true)
				return
	if sfx != &"" and _streams.has(sfx):
		play_sfx(sfx, -6.5, 0.06, world_pos, true)
	else:
		play_weapon_for_unit(unit_data.unit_type_id, world_pos)


func play_weapon_for_unit(unit_type_id: StringName, world_pos: Vector2 = Vector2.INF) -> void:
	for profile_val: Variant in _audio_profiles.values():
		var profile: FactionAudioProfile = profile_val as FactionAudioProfile
		if profile != null:
			var resolved: Dictionary = profile.resolve_weapon_sfx(&"", unit_type_id)
			if not resolved.is_empty():
				play_sfx(resolved["sfx_id"] as StringName, float(resolved["db"]), float(resolved["jitter"]), world_pos, true)
				return
	play_sfx(&"weapon_rifle", -7.5, 0.06, world_pos, true)


func play_explosion_sfx(world_pos: Vector2 = Vector2.INF, volume_db_offset: float = -5.0, is_major_global: bool = false) -> void:
	if is_major_global:
		play_sfx(&"explosion_heavy", volume_db_offset, 0.05, world_pos, false)
	else:
		play_sfx(&"entity_destroyed", volume_db_offset, 0.08, world_pos, true)


func play_build_sfx(sfx_id: StringName = &"build_complete", world_pos: Vector2 = Vector2.INF) -> void:
	play_sfx(sfx_id, -2.5, 0.02, world_pos, false)


func play_ability_sfx(ability_id: StringName, world_pos: Vector2 = Vector2.INF) -> void:
	for profile_val: Variant in _audio_profiles.values():
		var profile: FactionAudioProfile = profile_val as FactionAudioProfile
		if profile != null:
			var resolved: Dictionary = profile.resolve_ability_sfx(ability_id)
			if not resolved.is_empty():
				play_sfx(resolved["sfx_id"] as StringName, float(resolved["db"]), float(resolved["jitter"]), world_pos, true)
				return
	var direct_key: StringName = StringName("ability_%s" % String(ability_id))
	if _streams.has(direct_key):
		play_sfx(direct_key, -3.0, 0.04, world_pos, true)
	else:
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
	# Shared UI & Command Feedback
	_streams[&"ui_click"] = SynthPrimitives.synth_glass_click()
	_streams[&"unit_select"] = SynthPrimitives.synth_chime(PackedFloat32Array([740.0, 1110.0]), 0.055, 0.24)
	_streams[&"inspect_tick"] = SynthPrimitives.synth_chime(PackedFloat32Array([920.0]), 0.035, 0.18)
	_streams[&"order_move"] = SynthPrimitives.synth_chirp(520.0, 780.0, 0.085, 0.24)
	_streams[&"order_attack"] = SynthPrimitives.synth_double_chirp(660.0, 440.0, 0.095, 0.28)
	_streams[&"order_gather"] = SynthPrimitives.synth_chime(PackedFloat32Array([440.0, 660.0]), 0.065, 0.24)

	# Shared Completion & Economy Alerts
	_streams[&"build_complete"] = SynthPrimitives.synth_chime(PackedFloat32Array([523.25, 659.25, 783.99, 1046.5]), 0.075, 0.28)
	_streams[&"upgrade_complete"] = SynthPrimitives.synth_chord_swell(PackedFloat32Array([440.0, 554.37, 659.25, 880.0]), 0.42, 0.26)
	_streams[&"unit_ready"] = SynthPrimitives.synth_chime(PackedFloat32Array([622.25, 932.33]), 0.065, 0.23)
	_streams[&"error_insufficient"] = SynthPrimitives.synth_error_buzz()
	_streams[&"bandwidth_near_cap"] = SynthPrimitives.synth_chime(PackedFloat32Array([587.33, 523.25]), 0.075, 0.19)

	# Shared Destruction, Alerts, Veterancy, Salvage & Match Flow
	_streams[&"entity_destroyed"] = SynthPrimitives.synth_destruction_boom()
	_streams[&"explosion_heavy"] = SynthPrimitives.synth_explosion_heavy()
	_streams[&"shield_shatter"] = SynthPrimitives.synth_shield_shatter()
	_streams[&"alert_under_attack"] = SynthPrimitives.synth_alert_under_attack()
	_streams[&"alert_uplink"] = SynthPrimitives.synth_alert_uplink()
	_streams[&"alert_complete"] = SynthPrimitives.synth_alert_complete()
	_streams[&"veterancy_rank_up"] = SynthPrimitives.synth_rank_up_chime()
	_streams[&"salvage_claimed"] = SynthPrimitives.synth_chime(PackedFloat32Array([587.33, 783.99, 1174.66, 1567.98]), 0.045, 0.25)
	_streams[&"autocast_toggle"] = SynthPrimitives.synth_chime(PackedFloat32Array([880.0, 1318.5]), 0.04, 0.20)
	_streams[&"relay_captured"] = SynthPrimitives.synth_chime(PackedFloat32Array([659.25, 987.77, 1318.51]), 0.06, 0.22)
	_streams[&"deploy_lock"] = SynthPrimitives.synth_double_chirp(320.0, 145.0, 0.14, 0.28)
	_streams[&"deploy_release"] = SynthPrimitives.synth_double_chirp(185.0, 380.0, 0.13, 0.24)
	_streams[&"weapon_prism_beam"] = SynthPrimitives.synth_prism_beam()
	_streams[&"weapon_prism_refract"] = SynthPrimitives.synth_prism_refract()
	_streams[&"ai_transmission"] = SynthPrimitives.synth_chime(PackedFloat32Array([740.0, 1110.0]), 0.042, 0.16)
	_streams[&"match_victory"] = SynthPrimitives.synth_chime(PackedFloat32Array([523.25, 659.25, 783.99, 1046.5, 1318.5]), 0.11, 0.30)
	_streams[&"match_defeat"] = SynthPrimitives.synth_chime(PackedFloat32Array([440.0, 392.0, 329.63, 246.94]), 0.14, 0.30)

	# Pluggable Faction Audio Profiles (weapons, abilities, barks, cooldowns)
	for profile_val: Variant in _audio_profiles.values():
		var profile: FactionAudioProfile = profile_val as FactionAudioProfile
		if profile == null:
			continue
		profile.register_cooldowns(_cooldowns_ms)
		profile.build_weapon_and_ability_sfx(_streams)
		profile.build_bark_sfx(_streams)
