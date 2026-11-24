extends Node

signal mute_changed(is_muted: bool)
signal volume_changed(volume_linear: float)

const SAMPLE_RATE: int = 22050
const POOL_SIZE: int = 16

const UI_SFX_IDS: Array = [
	&"ui_click",
	&"unit_select",
	&"order_move",
	&"order_attack",
	&"order_gather",
	&"build_complete",
	&"upgrade_complete",
	&"unit_ready",
	&"error_insufficient",
	&"alert_under_attack",
	&"alert_uplink",
	&"alert_complete",
	&"veterancy_rank_up",
	&"match_victory",
	&"match_defeat",
]

var is_muted: bool = false
var master_volume_linear: float = 0.72
var sfx_volume_linear: float = 0.85
var ui_volume_linear: float = 0.85

var _unfocused_muted: bool = false
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0
var _last_play_ms: Dictionary = {}
var _cooldowns_ms: Dictionary = {
	&"ui_click": 30,
	&"unit_select": 45,
	&"order_move": 50,
	&"order_attack": 50,
	&"order_gather": 50,
	&"build_complete": 120,
	&"upgrade_complete": 180,
	&"unit_ready": 90,
	&"error_insufficient": 160,
	&"weapon_rifle": 68,
	&"weapon_slash": 72,
	&"weapon_rail": 82,
	&"weapon_mortar": 96,
	&"ability_adrenal": 80,
	&"ability_static": 90,
	&"ability_slam": 100,
	&"ability_barrage": 100,
	&"entity_destroyed": 85,
	&"alert_under_attack": 1800,
	&"alert_uplink": 1400,
	&"alert_complete": 700,
	&"veterancy_rank_up": 350,
	&"match_victory": 500,
	&"match_defeat": 500,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "SFXPlayer_%d" % i
		player.bus = &"Master"
		add_child(player)
		_players.append(player)
	_generate_procedural_library()
	_sync_from_settings()
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	_apply_master_bus_settings()


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
	is_muted = SettingsManager.muted
	_apply_master_bus_settings()
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


func play_sfx(sfx_id: StringName, volume_db_offset: float = 0.0, pitch_jitter: float = 0.0) -> void:
	if is_effectively_muted() or master_volume_linear <= 0.001:
		return
	var channel_linear: float = ui_volume_linear if UI_SFX_IDS.has(sfx_id) else sfx_volume_linear
	if channel_linear <= 0.001:
		return
	if not _streams.has(sfx_id):
		return
	var now_ms: int = Time.get_ticks_msec()
	var min_gap: int = int(_cooldowns_ms.get(sfx_id, 40))
	var prev_ms: int = int(_last_play_ms.get(sfx_id, -9999))
	if now_ms - prev_ms < min_gap:
		return
	_last_play_ms[sfx_id] = now_ms

	var player: AudioStreamPlayer = _acquire_player()
	if player == null:
		return
	player.stream = _streams[sfx_id] as AudioStreamWAV
	player.volume_db = volume_db_offset + linear_to_db(channel_linear)
	if pitch_jitter > 0.0:
		player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	else:
		player.pitch_scale = 1.0
	player.play()


func play_ui_click() -> void:
	play_sfx(&"ui_click", -3.0, 0.03)


func play_error() -> void:
	play_sfx(&"error_insufficient", -2.0, 0.0)


func play_weapon_for_unit(unit_type_id: StringName) -> void:
	match unit_type_id:
		&"stinger", &"symbiote":
			play_sfx(&"weapon_slash", -6.5, 0.06)
		&"lance_rig", &"arc_lancer":
			play_sfx(&"weapon_rail", -5.0, 0.06)
		&"chrysalis_mortar":
			play_sfx(&"weapon_mortar", -3.5, 0.06)
		&"goliath_frame":
			play_sfx(&"weapon_mortar", -6.0, 0.06)
		_:
			play_sfx(&"weapon_rifle", -7.5, 0.06)


func play_ability_sfx(ability_id: StringName) -> void:
	match ability_id:
		&"adrenal_surge", &"nanite_surge":
			play_sfx(&"ability_adrenal", -3.5, 0.04)
		&"static_pulse":
			play_sfx(&"ability_static", -3.0, 0.03)
		&"seismic_slam":
			play_sfx(&"ability_slam", -2.0, 0.04)
		&"spore_barrage", &"overcharge_pulse":
			play_sfx(&"ability_barrage", -2.5, 0.04)
		_:
			play_sfx(&"ability_adrenal", -4.0, 0.04)


func play_tactical_alert(alert_type: StringName) -> void:
	if SettingsManager != null and not SettingsManager.show_alert_toasts:
		return
	match alert_type:
		&"under_attack", &"damage":
			play_sfx(&"alert_under_attack", -3.5, 0.02)
		&"uplink_contested", &"uplink":
			play_sfx(&"alert_uplink", -3.0, 0.02)
		&"tech_complete", &"upgrade", &"construction":
			play_sfx(&"alert_complete", -3.5, 0.01)
		_:
			play_sfx(&"alert_complete", -4.5, 0.02)


func _acquire_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			return p
	var fallback: AudioStreamPlayer = _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % _players.size()
	fallback.stop()
	return fallback


func _apply_master_bus_settings() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	AudioServer.set_bus_mute(master_idx, is_effectively_muted())
	var db: float = linear_to_db(maxf(0.0001, master_volume_linear))
	AudioServer.set_bus_volume_db(master_idx, db)


func _generate_procedural_library() -> void:
	# UI & Command Feedback
	_streams[&"ui_click"] = _synth_glass_click()
	_streams[&"unit_select"] = _synth_chime(PackedFloat32Array([740.0, 1110.0]), 0.055, 0.24)
	_streams[&"order_move"] = _synth_chirp(520.0, 780.0, 0.085, 0.24)
	_streams[&"order_attack"] = _synth_double_chirp(660.0, 440.0, 0.095, 0.28)
	_streams[&"order_gather"] = _synth_chime(PackedFloat32Array([440.0, 660.0]), 0.065, 0.24)

	# Completion & Economy Alerts
	_streams[&"build_complete"] = _synth_chime(PackedFloat32Array([523.25, 659.25, 783.99, 1046.5]), 0.075, 0.28)
	_streams[&"upgrade_complete"] = _synth_chord_swell(PackedFloat32Array([440.0, 554.37, 659.25, 880.0]), 0.42, 0.26)
	_streams[&"unit_ready"] = _synth_chime(PackedFloat32Array([622.25, 932.33]), 0.065, 0.23)
	_streams[&"error_insufficient"] = _synth_error_buzz()

	# Combat & Ability SFX
	_streams[&"weapon_rifle"] = _synth_rifle_burst()
	_streams[&"weapon_slash"] = _synth_acid_snap()
	_streams[&"weapon_rail"] = _synth_rail_zap()
	_streams[&"weapon_mortar"] = _synth_mortar_thud()
	_streams[&"ability_adrenal"] = _synth_adrenal_hum()
	_streams[&"ability_static"] = _synth_static_pulse()
	_streams[&"ability_slam"] = _synth_seismic_slam()
	_streams[&"ability_barrage"] = _synth_mortar_thud()
	_streams[&"entity_destroyed"] = _synth_destruction_boom()

	# Tactical Alerts & Veterancy
	_streams[&"alert_under_attack"] = _synth_alert_under_attack()
	_streams[&"alert_uplink"] = _synth_alert_uplink()
	_streams[&"alert_complete"] = _synth_alert_complete()
	_streams[&"veterancy_rank_up"] = _synth_rank_up_chime()

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
