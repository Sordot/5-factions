extends Node

signal mute_changed(is_muted: bool)
signal volume_changed(volume_linear: float)

enum SFXPriority {
	SMALL_ARMS = 1,
	HEAVY_WEAPON = 2,
	TACTICAL_ABILITY = 3,
	STRATEGIC_IMPACT = 4,
}

const SAMPLE_RATE: int = SynthPrimitives.SAMPLE_RATE
const COMBAT_POOL_SIZE: int = 16
const UI_POOL_SIZE: int = 8
const STEREO_PAN_WIDTH: float = 0.75
const FAR_BUS_NORM_THRESHOLD: float = 0.72
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

const UI_SFX_MAP: Dictionary = {
	&"ui_click": true,
	&"unit_select": true,
	&"inspect_tick": true,
	&"bldg_select_production": true,
	&"bldg_select_hub": true,
	&"bldg_select_tech": true,
	&"bldg_select_defense": true,
	&"bldg_select_utility": true,
	&"order_move": true,
	&"order_attack": true,
	&"order_gather": true,
	&"build_complete": true,
	&"upgrade_complete": true,
	&"unit_ready": true,
	&"error_insufficient": true,
	&"bandwidth_near_cap": true,
	&"alert_under_attack": true,
	&"alert_uplink": true,
	&"alert_complete": true,
	&"veterancy_rank_up": true,
	&"salvage_claimed": true,
	&"autocast_toggle": true,
	&"relay_captured": true,
	&"ai_transmission": true,
	&"match_victory": true,
	&"match_defeat": true,
}

var is_muted: bool = false
var master_volume_linear: float = 0.72
var sfx_volume_linear: float = 0.85
var ui_volume_linear: float = 0.85
var ambience_volume_linear: float = 0.35

var _unfocused_muted: bool = false
var _audio_profiles: Dictionary = {} # StringName -> FactionAudioProfile
var _streams: Dictionary = {}
var _combat_players: Array[AudioStreamPlayer2D] = []
var _combat_start_ms: Array[int] = []
var _combat_priority: Array[int] = []
var _combat_volume_db: Array[float] = []
var _combat_world_pos: Array[Vector2] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _next_ui_idx: int = 0
var _bark_player: AudioStreamPlayer = null
var _last_play_ms: Dictionary = {}
var _last_play_db: Dictionary = {}
var _last_bark_select_ms: int = -9999
var _last_bark_order_ms: int = -9999

var _amb_lpf: AudioEffectLowPassFilter = null
var _amb_base_player: AudioStreamPlayer = null
var _amb_combat_player: AudioStreamPlayer = null
var _amb_uplink_player: AudioStreamPlayer = null
var _amb_profile_cache: Dictionary = {}
var _active_amb_profile: StringName = &""
var _desired_amb_profile: StringName = DEFAULT_AUDIO_PROFILE
var _amb_pending_swap_profile: StringName = &""
var _amb_xfade_gain: float = 0.0
var _amb_mutex: Mutex = Mutex.new()
var _amb_pending_tasks: Dictionary = {} # StringName -> int(task_id)
var _amb_completed_packs: Dictionary = {} # StringName -> Dictionary

var _combat_intensity: float = 0.0
var _combat_target: float = 0.0
var _combat_hold_until_ms: int = 0
var _uplink_tension: float = 0.0
var _uplink_target: float = 0.0
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
	&"ai_transmission": 160,
	&"deploy_lock": 90,
	&"deploy_release": 90,
	&"deploy_anchor_lock": 90,
	&"match_victory": 500,
	&"match_defeat": 500,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tick_ms = Time.get_ticks_msec()
	_ensure_audio_buses()

	for i: int in range(COMBAT_POOL_SIZE):
		var cp: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		cp.name = "CombatSFXPlayer_%d" % i
		cp.bus = &"SFX_Near"
		cp.max_distance = 100000.0
		cp.attenuation = 0.0
		cp.panning_strength = STEREO_PAN_WIDTH
		add_child(cp)
		_combat_players.append(cp)
		_combat_start_ms.append(0)
		_combat_priority.append(SFXPriority.SMALL_ARMS)
		_combat_volume_db.append(-80.0)
		_combat_world_pos.append(Vector2.INF)

	for i: int in range(UI_POOL_SIZE):
		var up: AudioStreamPlayer = AudioStreamPlayer.new()
		up.name = "UISFXPlayer_%d" % i
		up.bus = &"UI"
		add_child(up)
		_ui_players.append(up)

	_bark_player = AudioStreamPlayer.new()
	_bark_player.name = "BarkChannelPlayer"
	_bark_player.bus = &"Barks"
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


func _exit_tree() -> void:
	var task_ids: Array[int] = []
	for tid: Variant in _amb_pending_tasks.values():
		task_ids.append(int(tid))
	_amb_pending_tasks.clear()
	for task_id: int in task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_amb_mutex.lock()
	_amb_completed_packs.clear()
	_amb_mutex.unlock()


func _register_builtin_profiles() -> void:
	register_audio_profile(GenesisAudioProfile.new(), false)
	register_audio_profile(MonolithAudioProfile.new(), false)
	register_audio_profile(PrismaAudioProfile.new(), false)


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


func _ensure_bus(bus_name: String, send_to: String = "Master") -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus(AudioServer.bus_count)
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	if bus_name != "Master" and AudioServer.get_bus_index(send_to) >= 0:
		AudioServer.set_bus_send(idx, send_to)
	return idx


func _ensure_audio_buses() -> void:
	# 1. Master bus safety limiter
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		var has_limiter: bool = false
		for i: int in range(AudioServer.get_bus_effect_count(master_idx)):
			if AudioServer.get_bus_effect(master_idx, i) is AudioEffectLimiter:
				has_limiter = true
				break
		if not has_limiter:
			var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
			limiter.ceiling_db = -1.0
			limiter.threshold_db = -3.0
			AudioServer.add_bus_effect(master_idx, limiter)

	# 2. SFX bus -> Master with gentle combat glue compressor
	var sfx_idx: int = _ensure_bus("SFX", "Master")
	if sfx_idx >= 0:
		var has_comp: bool = false
		for i: int in range(AudioServer.get_bus_effect_count(sfx_idx)):
			if AudioServer.get_bus_effect(sfx_idx, i) is AudioEffectCompressor:
				has_comp = true
				break
		if not has_comp:
			var comp: AudioEffectCompressor = AudioEffectCompressor.new()
			comp.threshold = -12.0
			comp.ratio = 2.6
			comp.attack_us = 2500.0
			comp.release_ms = 140.0
			comp.gain = 0.0
			AudioServer.add_bus_effect(sfx_idx, comp)

	# 3. SFX_Near -> SFX (clean direct combat bus)
	_ensure_bus("SFX_Near", "SFX")

	# 4. SFX_Far -> SFX (2400 Hz air-absorption low-pass filter)
	var far_idx: int = _ensure_bus("SFX_Far", "SFX")
	if far_idx >= 0:
		var has_far_lpf: bool = false
		for i: int in range(AudioServer.get_bus_effect_count(far_idx)):
			if AudioServer.get_bus_effect(far_idx, i) is AudioEffectLowPassFilter:
				has_far_lpf = true
				break
		if not has_far_lpf:
			var far_lpf: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
			far_lpf.cutoff_hz = 2400.0
			far_lpf.resonance = 0.55
			AudioServer.add_bus_effect(far_idx, far_lpf)

	# 5. UI -> Master (clean uncompressed clicks, chimes, alerts, radio transmissions)
	_ensure_bus("UI", "Master")

	# 6. Barks -> Master (dedicated single-voice acknowledgment channel)
	_ensure_bus("Barks", "Master")

	# 7. Ambience -> Master (dynamic low-pass filter modulated by combat/uplink tension & pause)
	var amb_idx: int = _ensure_bus("Ambience", "Master")
	if amb_idx >= 0:
		_amb_lpf = null
		for i: int in range(AudioServer.get_bus_effect_count(amb_idx)):
			var eff: AudioEffect = AudioServer.get_bus_effect(amb_idx, i)
			if eff is AudioEffectLowPassFilter:
				_amb_lpf = eff as AudioEffectLowPassFilter
				break
		if _amb_lpf == null:
			_amb_lpf = AudioEffectLowPassFilter.new()
			_amb_lpf.cutoff_hz = 3800.0
			_amb_lpf.resonance = 0.45
			AudioServer.add_bus_effect(amb_idx, _amb_lpf)


func _process(_delta: float) -> void:
	if _amb_base_player == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	var real_dt: float = clampf(float(now_ms - _last_tick_ms) * 0.001, 0.0, 0.1)
	_last_tick_ms = now_ms

	# Drain finished background ambience synthesis tasks cleanly on main thread
	_drain_completed_ambience_tasks()

	# Keep active spatial combat voices smoothly camera-tracked mid-pan
	var active_cam: Camera2D = _get_active_camera()
	if active_cam != null:
		for i: int in range(_combat_players.size()):
			var cp: AudioStreamPlayer2D = _combat_players[i]
			if cp.playing:
				cp.global_position = _project_pan_world_pos(_combat_world_pos[i], active_cam)

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

	# Smooth 0.65s ambience profile crossfade (0.30s fade-out -> stream swap -> 0.35s fade-in)
	if _amb_pending_swap_profile != &"":
		_amb_xfade_gain = move_toward(_amb_xfade_gain, 0.0, real_dt / 0.30)
		if _amb_xfade_gain <= 0.005:
			_apply_ambience_pack_now(_amb_pending_swap_profile)
			_amb_pending_swap_profile = &""
	elif _amb_base_player.playing:
		_amb_xfade_gain = move_toward(_amb_xfade_gain, 1.0, real_dt / 0.35)

	_amb_poll_acc_s += real_dt
	if _amb_poll_acc_s >= 0.35 and is_inside_tree():
		_amb_poll_acc_s = 0.0
		refresh_faction_ambience_profile()
		var mm: Node = get_tree().get_first_node_in_group("match_manager")
		var in_match: bool = mm != null and is_instance_valid(mm)
		var next_uplink_target: float = 0.0
		if not in_match:
			_combat_target = 0.0
			_combat_hold_until_ms = 0
		else:
			for node: Node in get_tree().get_nodes_in_group("hyper_uplinks"):
				if is_instance_valid(node) and node is HyperUplink:
					var up: HyperUplink = node as HyperUplink
					if up.is_contested:
						next_uplink_target = 1.0
					elif absf(up.capture_progress) >= 0.65 and up.controlling_team < 0:
						next_uplink_target = maxf(next_uplink_target, 0.75)
		_uplink_target = next_uplink_target

	# Smooth per-frame uplink tension & dynamic Ambience low-pass filter
	_uplink_tension = move_toward(_uplink_tension, _uplink_target, real_dt * 0.65)
	if _amb_lpf != null:
		var energy: float = clampf(maxf(_combat_intensity, _uplink_tension * 0.85), 0.0, 1.0)
		var target_cutoff: float = 1450.0 if want_duck else lerpf(3800.0, 9600.0, energy)
		_amb_lpf.cutoff_hz = lerpf(_amb_lpf.cutoff_hz, target_cutoff, clampf(real_dt * 4.0, 0.0, 1.0))

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
		var active_teams: Array[int] = TeamManager.get_active_teams()
		var t1_id: int = active_teams[0] if not active_teams.is_empty() else 0
		var fdata_t1: FactionData = TeamManager.get_team_faction_data(t1_id)
		if fdata_t1 != null and fdata_t1.audio_timbre_profile != &"" and _audio_profiles.has(fdata_t1.audio_timbre_profile):
			return fdata_t1.audio_timbre_profile
		return DEFAULT_AUDIO_PROFILE
	var prof: StringName = _get_local_faction_timbre_profile()
	return prof if _audio_profiles.has(prof) else DEFAULT_AUDIO_PROFILE


func _request_ambience_profile_async(profile_id: StringName) -> void:
	var resolved_id: StringName = profile_id if _audio_profiles.has(profile_id) else DEFAULT_AUDIO_PROFILE
	if _amb_profile_cache.has(resolved_id) or _amb_pending_tasks.has(resolved_id):
		return
	var profile: FactionAudioProfile = _audio_profiles.get(resolved_id, null) as FactionAudioProfile
	if profile == null:
		return
	var task_id: int = WorkerThreadPool.add_task(func() -> void:
		var pack: Dictionary = profile.build_ambient_layers()
		_amb_mutex.lock()
		_amb_completed_packs[resolved_id] = pack
		_amb_mutex.unlock()
	)
	_amb_pending_tasks[resolved_id] = task_id


func _drain_completed_ambience_tasks() -> void:
	var finished: Dictionary = {}
	_amb_mutex.lock()
	if not _amb_completed_packs.is_empty():
		finished = _amb_completed_packs.duplicate()
		_amb_completed_packs.clear()
	_amb_mutex.unlock()
	if finished.is_empty():
		return

	for key: Variant in finished.keys():
		var pid: StringName = key as StringName
		if _amb_pending_tasks.has(pid):
			WorkerThreadPool.wait_for_task_completion(int(_amb_pending_tasks[pid]))
			_amb_pending_tasks.erase(pid)
		_amb_profile_cache[pid] = finished[key] as Dictionary
		if pid == _desired_amb_profile:
			if _amb_base_player != null and not _amb_base_player.playing:
				_apply_ambience_pack_now(pid)
			elif pid != _active_amb_profile:
				_amb_pending_swap_profile = pid


func _apply_ambience_pack_now(profile_id: StringName) -> void:
	if _amb_base_player == null or not _amb_profile_cache.has(profile_id):
		return
	var pack: Dictionary = _amb_profile_cache[profile_id] as Dictionary
	if pack.is_empty():
		return
	_active_amb_profile = profile_id
	_amb_base_player.stream = pack.get("base", null) as AudioStreamWAV
	_amb_combat_player.stream = pack.get("combat", null) as AudioStreamWAV
	_amb_uplink_player.stream = pack.get("uplink", null) as AudioStreamWAV
	_amb_base_player.play()
	_amb_combat_player.play()
	_amb_uplink_player.play()
	_update_ambience_mix(is_inside_tree() and get_tree().paused)


func refresh_faction_ambience_profile(_mode: StringName = &"") -> void:
	if _amb_base_player == null:
		return
	_desired_amb_profile = _resolve_desired_ambience_profile()
	if _desired_amb_profile == _active_amb_profile and _amb_base_player.playing:
		_amb_pending_swap_profile = &""
		return
	if not _amb_profile_cache.has(_desired_amb_profile):
		_request_ambience_profile_async(_desired_amb_profile)
		return
	if not _amb_base_player.playing:
		_amb_xfade_gain = 0.0
		_apply_ambience_pack_now(_desired_amb_profile)
	else:
		_amb_pending_swap_profile = _desired_amb_profile


func _setup_ambience_players() -> void:
	_active_amb_profile = &""
	_desired_amb_profile = DEFAULT_AUDIO_PROFILE
	_amb_xfade_gain = 0.0

	_amb_base_player = AudioStreamPlayer.new()
	_amb_base_player.name = "AmbBasePlayer"
	_amb_base_player.bus = &"Ambience"
	_amb_base_player.volume_db = -80.0
	add_child(_amb_base_player)

	_amb_combat_player = AudioStreamPlayer.new()
	_amb_combat_player.name = "AmbCombatPlayer"
	_amb_combat_player.bus = &"Ambience"
	_amb_combat_player.volume_db = -80.0
	add_child(_amb_combat_player)

	_amb_uplink_player = AudioStreamPlayer.new()
	_amb_uplink_player.name = "AmbUplinkPlayer"
	_amb_uplink_player.bus = &"Ambience"
	_amb_uplink_player.volume_db = -80.0
	add_child(_amb_uplink_player)

	# Zero synchronous 4.0s synthesis on boot: bake initial ambience asynchronously.
	_request_ambience_profile_async(DEFAULT_AUDIO_PROFILE)


func _update_ambience_mix(_is_paused: bool) -> void:
	var muted_now: bool = is_effectively_muted() or master_volume_linear <= 0.005 or ambience_volume_linear <= 0.005 or _amb_xfade_gain <= 0.002
	if muted_now:
		if _amb_base_player != null:
			_amb_base_player.volume_db = -80.0
		if _amb_combat_player != null:
			_amb_combat_player.volume_db = -80.0
		if _amb_uplink_player != null:
			_amb_uplink_player.volume_db = -80.0
		return

	var user_amb_db: float = _slider_to_db(ambience_volume_linear)
	var xfade_db: float = linear_to_db(maxf(0.001, _amb_xfade_gain))
	if _amb_base_player != null:
		_amb_base_player.volume_db = maxf(-80.0, user_amb_db + AMB_BASE_CEILING_DB + _amb_duck_db + xfade_db)
	if _amb_combat_player != null:
		if _combat_intensity <= 0.005:
			_amb_combat_player.volume_db = -80.0
		else:
			_amb_combat_player.volume_db = maxf(-80.0, user_amb_db + AMB_COMBAT_CEILING_DB + linear_to_db(_combat_intensity) + _amb_duck_db + xfade_db)
	if _amb_uplink_player != null:
		if _uplink_tension <= 0.005:
			_amb_uplink_player.volume_db = -80.0
		else:
			_amb_uplink_player.volume_db = maxf(-80.0, user_amb_db + AMB_UPLINK_CEILING_DB + linear_to_db(_uplink_tension) + _amb_duck_db + xfade_db)


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


func _get_active_camera() -> Camera2D:
	if not is_inside_tree():
		return null
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	if cam == null:
		cam = get_tree().get_first_node_in_group("rts_camera") as Camera2D
	if cam != null and is_instance_valid(cam):
		return cam
	return null


func _project_pan_world_pos(world_pos: Vector2, cam: Camera2D) -> Vector2:
	if cam == null or not is_instance_valid(cam):
		return Vector2.ZERO
	if world_pos == Vector2.INF:
		return cam.global_position
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom_x: float = maxf(0.1, cam.zoom.x)
	var half_w: float = maxf(240.0, (vp_size.x / zoom_x) * 0.5)
	var pan_x: float = clampf((world_pos.x - cam.global_position.x) / half_w, -1.0, 1.0)
	return Vector2(cam.global_position.x + pan_x * half_w, cam.global_position.y)


func _compute_spatial_attenuation(world_pos: Vector2, allow_cull: bool) -> Dictionary:
	var cam: Camera2D = _get_active_camera()
	if world_pos == Vector2.INF or cam == null:
		var center_pos: Vector2 = cam.global_position if cam != null else Vector2.ZERO
		return {
			"culled": false,
			"db_offset": 0.0,
			"norm_dist": 0.0,
			"pan_world_pos": center_pos,
			"is_far": false,
		}
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom_vec: Vector2 = Vector2(maxf(0.1, cam.zoom.x), maxf(0.1, cam.zoom.y))
	var half_world: Vector2 = (vp_size / zoom_vec) * 0.5
	var view_radius: float = maxf(240.0, half_world.length())
	var dist: float = cam.global_position.distance_to(world_pos)
	var norm: float = dist / view_radius
	var pan_pos: Vector2 = _project_pan_world_pos(world_pos, cam)
	var is_far: bool = norm > FAR_BUS_NORM_THRESHOLD
	if norm <= 0.85:
		return {
			"culled": false,
			"db_offset": 0.0,
			"norm_dist": norm,
			"pan_world_pos": pan_pos,
			"is_far": is_far,
		}
	if norm > 1.55:
		if allow_cull:
			return {
				"culled": true,
				"db_offset": -80.0,
				"norm_dist": norm,
				"pan_world_pos": pan_pos,
				"is_far": true,
			}
		return {
			"culled": false,
			"db_offset": -16.0,
			"norm_dist": norm,
			"pan_world_pos": pan_pos,
			"is_far": true,
		}
	var t: float = clampf((norm - 0.85) / 0.70, 0.0, 1.0)
	return {
		"culled": false,
		"db_offset": lerpf(0.0, -16.0, t),
		"norm_dist": norm,
		"pan_world_pos": pan_pos,
		"is_far": is_far,
	}


func _resolve_sfx_priority(sfx_id: StringName) -> int:
	match sfx_id:
		&"explosion_heavy", &"ability_solar_convergence_impact", &"ability_solar_convergence_charge", &"ability_seismic_slam", &"ability_slam":
			return SFXPriority.STRATEGIC_IMPACT
		&"shield_shatter", &"deploy_lock", &"deploy_release", &"deploy_anchor_lock", &"overclock_activate":
			return SFXPriority.TACTICAL_ABILITY
		&"entity_destroyed", &"weapon_prisma_lance", &"weapon_mono_siege", &"weapon_mono_bastion", &"weapon_mortar", &"weapon_arc_lancer", &"weapon_rail", &"weapon_mono_rail", &"weapon_heavy", &"weapon_goliath":
			return SFXPriority.HEAVY_WEAPON
	if String(sfx_id).begins_with("ability_"):
		return SFXPriority.TACTICAL_ABILITY
	return SFXPriority.SMALL_ARMS


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
	var is_ui_sfx: bool = UI_SFX_MAP.has(sfx_id)
	var channel_linear: float = ui_volume_linear if is_ui_sfx else sfx_volume_linear
	if channel_linear <= 0.005:
		return
	if not _streams.has(sfx_id):
		return

	var atten: Dictionary = _compute_spatial_attenuation(world_pos, allow_offscreen_cull)
	if not is_ui_sfx and world_pos != Vector2.INF and bool(atten["culled"]):
		return
	var spatial_db: float = float(atten["db_offset"]) if (not is_ui_sfx and world_pos != Vector2.INF) else 0.0
	var final_db: float = volume_db_offset + spatial_db + _slider_to_db(channel_linear)

	var now_ms: int = Time.get_ticks_msec()
	var min_gap: int = int(_cooldowns_ms.get(sfx_id, 40))
	var prev_ms: int = int(_last_play_ms.get(sfx_id, -9999))
	if (now_ms - prev_ms) < min_gap:
		var prev_db: float = float(_last_play_db.get(sfx_id, -80.0))
		var prox_override: bool = (not is_ui_sfx) and (now_ms - prev_ms) >= 25 and (final_db - prev_db) >= 4.0
		if not prox_override:
			return
	_last_play_ms[sfx_id] = now_ms
	_last_play_db[sfx_id] = final_db

	if sfx_id == &"match_victory" or sfx_id == &"match_defeat":
		trigger_ambience_duck(2.4)

	var pitch: float = maxf(0.25, base_pitch + randf_range(-pitch_jitter, pitch_jitter)) if pitch_jitter > 0.0 else maxf(0.25, base_pitch)
	if is_ui_sfx:
		var ui_p: AudioStreamPlayer = _acquire_ui_player()
		if ui_p == null:
			return
		ui_p.bus = &"UI"
		ui_p.stream = _streams[sfx_id] as AudioStreamWAV
		ui_p.volume_db = final_db
		ui_p.pitch_scale = pitch
		ui_p.play()
		return

	var incoming_prio: int = _resolve_sfx_priority(sfx_id)
	var voice_idx: int = _acquire_combat_player(now_ms, incoming_prio, final_db)
	if voice_idx < 0:
		return
	var cp: AudioStreamPlayer2D = _combat_players[voice_idx]
	cp.bus = &"SFX_Far" if bool(atten["is_far"]) else &"SFX_Near"
	cp.global_position = atten["pan_world_pos"] as Vector2
	cp.stream = _streams[sfx_id] as AudioStreamWAV
	cp.volume_db = final_db
	cp.pitch_scale = pitch
	_combat_start_ms[voice_idx] = now_ms
	_combat_priority[voice_idx] = incoming_prio
	_combat_volume_db[voice_idx] = final_db
	_combat_world_pos[voice_idx] = world_pos
	cp.play()


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
				var u_cls: StringName = classify_unit_bark_class(u.get_unit_type_id(), u.data)
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
				var u_cls: StringName = classify_unit_bark_class(u.get_unit_type_id(), u.data)
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


func classify_unit_bark_class(unit_type_id: StringName, unit_data: UnitData = null) -> StringName:
	if unit_data != null:
		if unit_data.audio_bark_class != &"":
			return unit_data.audio_bark_class
		if unit_data.is_worker_class():
			return &"worker"
		if unit_data.has_tag(&"support") or unit_data.heal_aura_rate > 0.0 or unit_data.tether_emit_radius > 0.0:
			return &"support"
		if unit_data.is_heavy_unit() or unit_data.has_tag(&"siege") or unit_data.has_tag(&"artillery"):
			return &"heavy"
		if unit_data.has_tag(&"anti_armor") or unit_data.has_tag(&"disruptor"):
			return &"counter"
		return &"swarm"

	match unit_type_id:
		&"worker", &"silica_harvester", &"engineer", &"servo_drone", &"ore_crawler", &"grid_tech", &"acolyte", &"prism_dredge", &"cantor":
			return &"worker"
		&"clone_trooper", &"stinger", &"picket_drone", &"votary", &"lumen_skiff":
			return &"swarm"
		&"lance_rig", &"signal_jammer", &"rail_sentinel", &"null_grid_projector", &"lens_adjudicator":
			return &"counter"
		&"symbiote", &"aegis_relay", &"prism_weaver":
			return &"support"
		&"goliath_frame", &"arc_lancer", &"chrysalis_mortar", &"bulwark_automaton", &"anvil_siege_walker", &"monolith_dreadnought", &"solstice_lance", &"seraph_cruiser":
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
		&"ambience":
			if is_effectively_muted() or master_volume_linear <= 0.005 or ambience_volume_linear <= 0.005:
				return
			var preview_stream: AudioStreamWAV = _streams.get(&"ambience_preview", _streams.get(&"alert_complete", null)) as AudioStreamWAV
			if preview_stream == null:
				return
			var ui_p: AudioStreamPlayer = _acquire_ui_player()
			if ui_p == null:
				return
			ui_p.bus = &"Ambience"
			ui_p.stream = preview_stream
			ui_p.volume_db = -7.5 + _slider_to_db(ambience_volume_linear)
			ui_p.pitch_scale = 1.0
			ui_p.play()


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


func _acquire_combat_player(_now_ms: int, incoming_priority: int, _incoming_db: float) -> int:
	# 1. Prefer any free voice immediately
	for i: int in range(_combat_players.size()):
		if not _combat_players[i].playing:
			return i

	# 2. All 16 voices busy: steal only from voices with priority <= incoming_priority
	var best_idx: int = -1
	var best_prio: int = 999
	var best_db: float = 999.0
	var best_ms: int = 2147483647
	for i: int in range(_combat_players.size()):
		var p_i: int = _combat_priority[i]
		if p_i > incoming_priority:
			continue
		var db_i: float = _combat_volume_db[i]
		var ms_i: int = _combat_start_ms[i]
		if best_idx < 0:
			best_idx = i
			best_prio = p_i
			best_db = db_i
			best_ms = ms_i
			continue
		if p_i < best_prio:
			best_idx = i
			best_prio = p_i
			best_db = db_i
			best_ms = ms_i
		elif p_i == best_prio:
			if (best_db - db_i) >= 3.0:
				best_idx = i
				best_db = db_i
				best_ms = ms_i
			elif absf(best_db - db_i) < 3.0 and ms_i < best_ms:
				best_idx = i
				best_db = db_i
				best_ms = ms_i

	if best_idx < 0:
		return -1
	_combat_players[best_idx].stop()
	return best_idx


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
	_streams[&"ambience_preview"] = SynthPrimitives.synth_chord_swell(PackedFloat32Array([220.0, 329.63, 440.0, 587.33]), 0.36, 0.24)

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

	# Fallback guarantee for deploy_anchor_lock if Monolith profile was removed/replaced
	if not _streams.has(&"deploy_anchor_lock"):
		_streams[&"deploy_anchor_lock"] = SynthPrimitives.synth_destruction_boom()
