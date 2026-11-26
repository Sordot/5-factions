class_name GenesisAudioProfile
extends FactionAudioProfile

## Procedural audio profile for GENESIS_V2 (&"technozen_bio").
## Houses Technozen bio-synth weapons, abilities, unit barks, and 3-layer ambient loops.

const SR: int = SynthPrimitives.SAMPLE_RATE


func get_profile_id() -> StringName:
	return &"technozen_bio"


func get_stream_prefix() -> String:
	return ""


func register_cooldowns(cooldowns_ms: Dictionary) -> void:
	cooldowns_ms[&"weapon_rifle"] = 75
	cooldowns_ms[&"weapon_slash"] = 80
	cooldowns_ms[&"weapon_rail"] = 90
	cooldowns_ms[&"weapon_mortar"] = 105
	cooldowns_ms[&"ability_adrenal"] = 90
	cooldowns_ms[&"ability_static"] = 100
	cooldowns_ms[&"ability_slam"] = 110
	cooldowns_ms[&"ability_barrage"] = 110


func build_weapon_and_ability_sfx(sfx_bank: Dictionary) -> void:
	sfx_bank[&"weapon_rifle"] = _synth_rifle_burst()
	sfx_bank[&"weapon_slash"] = _synth_acid_snap()
	sfx_bank[&"weapon_rail"] = _synth_rail_zap()
	sfx_bank[&"weapon_mortar"] = _synth_mortar_thud()
	sfx_bank[&"ability_adrenal"] = _synth_adrenal_hum()
	sfx_bank[&"ability_static"] = _synth_static_pulse()
	sfx_bank[&"ability_slam"] = _synth_seismic_slam()
	sfx_bank[&"ability_barrage"] = sfx_bank[&"weapon_mortar"]


func build_bark_sfx(sfx_bank: Dictionary) -> void:
	sfx_bank[&"bldg_select_production"] = SynthPrimitives.synth_chord_swell(PackedFloat32Array([261.63, 392.0, 523.25]), 0.20, 0.24)
	sfx_bank[&"bldg_select_hub"] = SynthPrimitives.synth_chord_swell(PackedFloat32Array([146.83, 220.0, 329.63]), 0.24, 0.28)
	sfx_bank[&"bldg_select_tech"] = SynthPrimitives.synth_chime(PackedFloat32Array([587.33, 880.0]), 0.05, 0.20)
	sfx_bank[&"bldg_select_defense"] = SynthPrimitives.synth_chirp(420.0, 680.0, 0.12, 0.22)
	sfx_bank[&"bldg_select_utility"] = SynthPrimitives.synth_chime(PackedFloat32Array([493.88, 739.99]), 0.045, 0.18)

	sfx_bank[&"bark_worker_select"] = _synth_bark_worker(false)
	sfx_bank[&"bark_worker_order"] = _synth_bark_worker(true)
	sfx_bank[&"bark_swarm_select"] = _synth_bark_swarm(false)
	sfx_bank[&"bark_swarm_order"] = _synth_bark_swarm(true)
	sfx_bank[&"bark_counter_select"] = _synth_bark_counter(false)
	sfx_bank[&"bark_counter_order"] = _synth_bark_counter(true)
	sfx_bank[&"bark_support_select"] = _synth_bark_support(false)
	sfx_bank[&"bark_support_order"] = _synth_bark_support(true)
	sfx_bank[&"bark_heavy_select"] = _synth_bark_heavy(false)
	sfx_bank[&"bark_heavy_order"] = _synth_bark_heavy(true)


func build_ambient_layers() -> Dictionary:
	return {
		"base": _synth_ambience_base_loop(),
		"combat": _synth_ambience_combat_loop(),
		"uplink": _synth_ambience_uplink_loop(),
	}


func resolve_weapon_sfx(sfx_id: StringName, unit_type_id: StringName) -> Dictionary:
	match sfx_id:
		&"weapon_slash", &"acid_slash", &"melee_slash", &"bio_slash":
			return {"sfx_id": &"weapon_slash", "db": -6.5, "jitter": 0.06}
		&"weapon_rail", &"rail_shot", &"rail_beam", &"arc_lance":
			return {"sfx_id": &"weapon_rail", "db": -5.0, "jitter": 0.06}
		&"weapon_mortar", &"mortar_thud", &"siege_mortar":
			return {"sfx_id": &"weapon_mortar", "db": -3.5, "jitter": 0.06}
		&"heavy_cannon", &"twin_cannon", &"autocannon":
			return {"sfx_id": &"weapon_mortar", "db": -6.0, "jitter": 0.06}
		&"weapon_rifle", &"pulse_rifle", &"pulse_bolt":
			return {"sfx_id": &"weapon_rifle", "db": -7.5, "jitter": 0.06}

	match unit_type_id:
		&"stinger", &"symbiote":
			return {"sfx_id": &"weapon_slash", "db": -6.5, "jitter": 0.06}
		&"lance_rig", &"arc_lancer":
			return {"sfx_id": &"weapon_rail", "db": -5.0, "jitter": 0.06}
		&"chrysalis_mortar":
			return {"sfx_id": &"weapon_mortar", "db": -3.5, "jitter": 0.06}
		&"goliath_frame":
			return {"sfx_id": &"weapon_mortar", "db": -6.0, "jitter": 0.06}
	return {}


func resolve_ability_sfx(ability_id: StringName) -> Dictionary:
	match ability_id:
		&"adrenal_surge":
			return {"sfx_id": &"ability_adrenal", "db": -3.5, "jitter": 0.04}
		&"static_pulse":
			return {"sfx_id": &"ability_static", "db": -3.0, "jitter": 0.03}
		&"seismic_slam":
			return {"sfx_id": &"ability_slam", "db": -2.0, "jitter": 0.04}
		&"spore_barrage":
			return {"sfx_id": &"ability_barrage", "db": -2.5, "jitter": 0.04}
	return {}


# =============================================================================
# WEAPON & ABILITY SYNTHS
# =============================================================================

func _synth_rifle_burst() -> AudioStreamWAV:
	var duration: float = 0.09
	var count: int = int(SR * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 1337
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / duration
		var freq: float = lerpf(420.0, 110.0, u)
		phase += TAU * freq / float(SR)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.35)
		var env: float = minf(1.0, t / 0.002) * exp(-u * 6.5)
		out[i] = (sin(phase) * 0.55 + lp * 0.45) * env * 0.30
	return SynthPrimitives.make_wav(out)


func _synth_acid_snap() -> AudioStreamWAV:
	var duration: float = 0.095
	var count: int = int(SR * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 4242
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / duration
		var freq: float = lerpf(1180.0, 260.0, u * u)
		phase += TAU * freq / float(SR)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		var env: float = minf(1.0, t / 0.002) * exp(-u * 7.0)
		out[i] = (sin(phase) * 0.62 + noise * 0.38) * env * 0.28
	return SynthPrimitives.make_wav(out)


func _synth_rail_zap() -> AudioStreamWAV:
	var duration: float = 0.18
	var count: int = int(SR * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var phase_sub: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / duration
		var freq: float = lerpf(1680.0, 190.0, pow(u, 0.65))
		var mod: float = sin(TAU * 95.0 * t) * 180.0
		phase += TAU * (freq + mod) / float(SR)
		var sub_f: float = lerpf(84.0, 48.0, minf(1.0, t / 0.085))
		phase_sub += TAU * sub_f / float(SR)
		var sub_env: float = minf(1.0, t / 0.0025) * exp(-t * 28.0)
		var env: float = minf(1.0, t / 0.003) * exp(-u * 4.8)
		out[i] = clampf(clampf(sin(phase) * 1.4, -1.0, 1.0) * env * 0.28 + sin(phase_sub) * sub_env * 0.22, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_mortar_thud() -> AudioStreamWAV:
	var duration: float = 0.29
	var count: int = int(SR * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var phase_sub: float = 0.0
	var seed_val: int = 9001
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / duration
		var freq: float = lerpf(155.0, 38.0, pow(u, 0.55))
		phase += TAU * freq / float(SR)
		var sub_f: float = lerpf(82.0, 46.0, minf(1.0, t / 0.105))
		phase_sub += TAU * sub_f / float(SR)
		var sub_env: float = minf(1.0, t / 0.003) * exp(-t * 22.0)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.16)
		var env: float = minf(1.0, t / 0.004) * exp(-u * 4.6)
		out[i] = clampf((sin(phase) * 0.62 + lp * 0.46) * env * 0.34 + sin(phase_sub) * sub_env * 0.24, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_adrenal_hum() -> AudioStreamWAV:
	var duration: float = 0.26
	var count: int = int(SR * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / duration
		var freq: float = lerpf(280.0, 680.0, u)
		phase += TAU * freq / float(SR)
		var env: float = sin(PI * u)
		out[i] = (sin(phase) * 0.65 + sin(phase * 1.5) * 0.35) * env * 0.28
	return SynthPrimitives.make_wav(out)


func _synth_static_pulse() -> AudioStreamWAV:
	var duration: float = 0.30
	var count: int = int(SR * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 7711
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / duration
		var freq: float = lerpf(720.0, 210.0, u) + sin(TAU * 42.0 * t) * 120.0
		phase += TAU * freq / float(SR)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		var env: float = minf(1.0, t / 0.008) * exp(-u * 3.6)
		out[i] = (sin(phase) * 0.6 + noise * 0.25) * env * 0.28
	return SynthPrimitives.make_wav(out)


func _synth_seismic_slam() -> AudioStreamWAV:
	var duration: float = 0.36
	var count: int = int(SR * duration)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 5150
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / duration
		var freq: float = lerpf(135.0, 28.0, pow(u, 0.5))
		phase += TAU * freq / float(SR)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.12)
		var env: float = minf(1.0, t / 0.003) * exp(-u * 4.0)
		out[i] = clampf((sin(phase) * 0.8 + lp * 0.65) * 1.15, -1.0, 1.0) * env * 0.38
	return SynthPrimitives.make_wav(out)


# =============================================================================
# UNIT BARK SYNTHS
# =============================================================================

func _synth_bark_worker(is_order: bool) -> AudioStreamWAV:
	var f0: float = 780.0 if is_order else 660.0
	var f1: float = 1170.0 if is_order else 990.0
	return SynthPrimitives.synth_chime(PackedFloat32Array([f0, f1]), 0.055, 0.20)


func _synth_bark_swarm(is_order: bool) -> AudioStreamWAV:
	var dur: float = 0.165
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var f_start: float = 640.0 if is_order else 520.0
		var f_end: float = 1080.0 if is_order else 820.0
		var pulse_u: float = fmod(u * 2.0, 1.0)
		var freq: float = lerpf(f_start, f_end, pulse_u)
		phase += TAU * freq / float(SR)
		var env: float = minf(1.0, pulse_u / 0.08) * exp(-pulse_u * 4.8)
		out[i] = (sin(phase) * 0.68 + sin(phase * 2.5) * 0.32) * env * 0.22
	return SynthPrimitives.make_wav(out)


func _synth_bark_counter(is_order: bool) -> AudioStreamWAV:
	var dur: float = 0.19
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var freq: float = lerpf(920.0, 1380.0, u) if is_order else lerpf(1240.0, 860.0, u)
		phase += TAU * (freq + sin(TAU * 55.0 * t) * 45.0) / float(SR)
		var env: float = minf(1.0, t / 0.008) * exp(-u * 3.8)
		out[i] = (sin(phase) * 0.72 + sin(phase * 1.5) * 0.28) * env * 0.22
	return SynthPrimitives.make_wav(out)


func _synth_bark_support(is_order: bool) -> AudioStreamWAV:
	var notes: PackedFloat32Array = PackedFloat32Array([523.25, 659.25, 987.77]) if is_order else PackedFloat32Array([440.0, 659.25])
	return SynthPrimitives.synth_chime(notes, 0.055, 0.20)


func _synth_bark_heavy(is_order: bool) -> AudioStreamWAV:
	var dur: float = 0.23
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var base_f: float = lerpf(115.0, 82.0, u) if is_order else lerpf(92.0, 128.0, u)
		phase += TAU * base_f / float(SR)
		var sub_env: float = minf(1.0, t / 0.012) * exp(-u * 3.2)
		var ping_t: float = maxf(0.0, t - 0.065)
		var ping_env: float = (minf(1.0, ping_t / 0.004) * exp(-ping_t * 20.0)) if t >= 0.065 else 0.0
		var ping_f: float = 620.0 if is_order else 490.0
		var ping: float = sin(TAU * ping_f * ping_t) * ping_env * 0.35
		out[i] = (sin(phase) * 0.65 + sin(phase * 2.0) * 0.20) * sub_env * 0.32 + ping * 0.28
	return SynthPrimitives.make_wav(out)


# =============================================================================
# DYNAMIC 3-LAYER AMBIENT LOOPS (4.0s EXACT CYCLES)
# =============================================================================

func _synth_ambience_base_loop() -> AudioStreamWAV:
	# 4.0s exact harmonic cycle: warm Y2K/Technozen D-minor9 low-pass pad + soft crystalline pulse
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var freqs: PackedFloat32Array = PackedFloat32Array([73.5, 110.25, 147.0, 220.5, 294.0])
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var lfo: float = 0.72 + 0.28 * sin(TAU * 0.25 * t)
		var pulse: float = 0.5 + 0.5 * sin(TAU * 0.5 * t)
		var pad: float = 0.0
		for f: float in freqs:
			pad += sin(TAU * f * t)
		pad *= 0.16 * lfo
		var shimmer: float = sin(TAU * 588.0 * t) * (0.045 * pulse * pulse)
		lp = lerpf(lp, pad + shimmer, 0.12)
		out[i] = lp * 0.65
	return SynthPrimitives.make_loop_wav(out)


func _synth_ambience_combat_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: subtle rhythmic sub-bass pulse + filtered Technozen 16th-note arpeggio
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var arp_notes: PackedFloat32Array = PackedFloat32Array([147.0, 174.5, 220.5, 261.5, 220.5, 174.5, 147.0, 130.75])
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
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
	return SynthPrimitives.make_loop_wav(out)


func _synth_ambience_uplink_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: ethereal crystalline harmonic shimmer for Data Hyper-Uplink tension
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var swell: float = 0.55 + 0.45 * sin(TAU * 0.5 * t)
		var s: float = sin(TAU * 441.0 * t) * 0.35 + sin(TAU * 661.5 * t) * 0.30 + sin(TAU * 882.0 * t) * 0.20
		out[i] = s * swell * 0.26
	return SynthPrimitives.make_loop_wav(out)
