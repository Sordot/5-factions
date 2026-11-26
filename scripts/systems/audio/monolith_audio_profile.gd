class_name MonolithAudioProfile
extends FactionAudioProfile

## Procedural audio profile for MONOLITH_OS (&"monolith_industrial").
## Houses Neo-Brutalist industrial weapons, abilities, quantized relay barks, and 3-layer ambient loops.

const SR: int = SynthPrimitives.SAMPLE_RATE


func get_profile_id() -> StringName:
	return &"monolith_industrial"


func get_stream_prefix() -> String:
	return "mono_"


func register_cooldowns(cooldowns_ms: Dictionary) -> void:
	cooldowns_ms[&"weapon_mono_slug"] = 85
	cooldowns_ms[&"weapon_mono_rail"] = 100
	cooldowns_ms[&"weapon_mono_tether"] = 75
	cooldowns_ms[&"weapon_mono_bastion"] = 105
	cooldowns_ms[&"weapon_mono_siege"] = 120
	cooldowns_ms[&"ability_shield_overcharge"] = 110
	cooldowns_ms[&"ability_suppressive_lock"] = 95
	cooldowns_ms[&"ability_kinetic_barrier"] = 110
	cooldowns_ms[&"ability_grav_pulse"] = 120
	cooldowns_ms[&"overclock_activate"] = 180


func build_weapon_and_ability_sfx(sfx_bank: Dictionary) -> void:
	sfx_bank[&"weapon_mono_slug"] = _synth_mono_slug()
	sfx_bank[&"weapon_mono_rail"] = _synth_mono_rail()
	sfx_bank[&"weapon_mono_tether"] = _synth_mono_tether()
	sfx_bank[&"weapon_mono_bastion"] = _synth_mono_bastion()
	sfx_bank[&"weapon_mono_siege"] = _synth_mono_siege()
	sfx_bank[&"ability_shield_overcharge"] = _synth_mono_shield_overcharge()
	sfx_bank[&"ability_suppressive_lock"] = _synth_mono_suppressive_lock()
	sfx_bank[&"ability_kinetic_barrier"] = _synth_mono_kinetic_barrier()
	sfx_bank[&"ability_grav_pulse"] = _synth_mono_grav_pulse()
	sfx_bank[&"overclock_activate"] = _synth_mono_overclock()
	sfx_bank[&"deploy_anchor_lock"] = _synth_deploy_anchor_lock()


func build_bark_sfx(sfx_bank: Dictionary) -> void:
	sfx_bank[&"mono_bark_worker_select"] = _synth_mono_bark(PackedFloat32Array([311.13, 466.16]), false)
	sfx_bank[&"mono_bark_worker_order"] = _synth_mono_bark(PackedFloat32Array([349.23, 523.25]), true)
	sfx_bank[&"mono_bark_swarm_select"] = _synth_mono_bark(PackedFloat32Array([392.0, 587.33]), false)
	sfx_bank[&"mono_bark_swarm_order"] = _synth_mono_bark(PackedFloat32Array([440.0, 659.25]), true)
	sfx_bank[&"mono_bark_counter_select"] = _synth_mono_bark(PackedFloat32Array([261.63, 392.0, 523.25]), false)
	sfx_bank[&"mono_bark_counter_order"] = _synth_mono_bark(PackedFloat32Array([293.66, 440.0, 587.33]), true)
	sfx_bank[&"mono_bark_support_select"] = _synth_mono_bark(PackedFloat32Array([329.63, 493.88, 659.25]), false)
	sfx_bank[&"mono_bark_support_order"] = _synth_mono_bark(PackedFloat32Array([392.0, 587.33, 783.99]), true)
	sfx_bank[&"mono_bark_heavy_select"] = _synth_mono_bark(PackedFloat32Array([146.83, 220.0]), false)
	sfx_bank[&"mono_bark_heavy_order"] = _synth_mono_bark(PackedFloat32Array([164.81, 246.94]), true)
	sfx_bank[&"mono_bldg_select_hub"] = _synth_mono_bark(PackedFloat32Array([110.0, 164.81, 220.0]), false)
	sfx_bank[&"mono_bldg_select_production"] = _synth_mono_bark(PackedFloat32Array([146.83, 220.0, 293.66]), false)
	sfx_bank[&"mono_bldg_select_tech"] = _synth_mono_bark(PackedFloat32Array([220.0, 329.63, 440.0]), false)
	sfx_bank[&"mono_bldg_select_defense"] = _synth_mono_bark(PackedFloat32Array([174.61, 261.63]), true)
	sfx_bank[&"mono_bldg_select_utility"] = _synth_mono_bark(PackedFloat32Array([196.0, 293.66]), false)


func build_ambient_layers() -> Dictionary:
	return {
		"base": _synth_ambience_monolith_base_loop(),
		"combat": _synth_ambience_monolith_combat_loop(),
		"uplink": _synth_ambience_monolith_uplink_loop(),
	}


func resolve_weapon_sfx(sfx_id: StringName, unit_type_id: StringName) -> Dictionary:
	match sfx_id:
		&"weapon_mono_slug":
			return {"sfx_id": &"weapon_mono_slug", "db": -5.0, "jitter": 0.05}
		&"weapon_mono_rail":
			return {"sfx_id": &"weapon_mono_rail", "db": -4.2, "jitter": 0.04}
		&"weapon_mono_tether":
			return {"sfx_id": &"weapon_mono_tether", "db": -6.2, "jitter": 0.05}
		&"weapon_mono_bastion":
			return {"sfx_id": &"weapon_mono_bastion", "db": -4.0, "jitter": 0.05}
		&"weapon_mono_siege":
			return {"sfx_id": &"weapon_mono_siege", "db": -3.0, "jitter": 0.04}

	match unit_type_id:
		&"bulwark_automaton", &"monolith_dreadnought":
			return {"sfx_id": &"weapon_mono_slug", "db": -5.0, "jitter": 0.05}
		&"anvil_siege_walker":
			return {"sfx_id": &"weapon_mono_siege", "db": -3.2, "jitter": 0.04}
		&"rail_sentinel":
			return {"sfx_id": &"weapon_mono_rail", "db": -4.2, "jitter": 0.04}
		&"picket_drone", &"null_grid_projector":
			return {"sfx_id": &"weapon_mono_tether", "db": -6.2, "jitter": 0.05}
	return {}


func resolve_ability_sfx(ability_id: StringName) -> Dictionary:
	match ability_id:
		&"monolith_suppressive_lock":
			return {"sfx_id": &"ability_suppressive_lock", "db": -3.2, "jitter": 0.04}
		&"monolith_shield_overcharge":
			return {"sfx_id": &"ability_shield_overcharge", "db": -2.8, "jitter": 0.03}
		&"kinetic_barrier":
			return {"sfx_id": &"ability_kinetic_barrier", "db": -2.4, "jitter": 0.03}
		&"grav_pulse":
			return {"sfx_id": &"ability_grav_pulse", "db": -2.2, "jitter": 0.04}
	return {}


# =============================================================================
# INDUSTRIAL WEAPON, ABILITY & BARK SYNTHS
# =============================================================================

func _synth_mono_slug() -> AudioStreamWAV:
	# Heavy low-mid mechanical thump + crisp metallic bolt clack
	var dur: float = 0.15
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var seed_val: int = 31337
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var freq: float = lerpf(210.0, 58.0, pow(u, 0.55))
		phase += TAU * freq / float(SR)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.28)
		var thump_env: float = minf(1.0, t / 0.002) * exp(-u * 6.0)
		var clack_t: float = maxf(0.0, t - 0.042)
		var clack_env: float = (minf(1.0, clack_t / 0.0015) * exp(-clack_t * 62.0)) if t >= 0.042 else 0.0
		var clack: float = (sin(TAU * 1420.0 * clack_t) * 0.5 + sin(TAU * 2380.0 * clack_t) * 0.35 + noise * 0.25) * clack_env
		out[i] = clampf((sin(phase) * 0.72 + lp * 0.40) * thump_env * 0.36 + clack * 0.22, -0.95, 0.95)
	return SynthPrimitives.make_wav(out)


func _synth_mono_rail() -> AudioStreamWAV:
	# Rising high-voltage capacitor whine -> crisp sub-bass crack + metallic ring
	var dur: float = 0.25
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase_whine: float = 0.0
	var phase_crack: float = 0.0
	var phase_sub: float = 0.0
	var seed_val: int = 8088
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var sample: float = 0.0
		if t < 0.045:
			var uw: float = t / 0.045
			var fw: float = lerpf(620.0, 2100.0, uw * uw)
			phase_whine += TAU * fw / float(SR)
			sample += sin(phase_whine) * (0.14 * uw)
		else:
			var lt: float = t - 0.045
			var uc: float = lt / (dur - 0.045)
			var fc: float = lerpf(260.0, 46.0, pow(uc, 0.45))
			phase_crack += TAU * fc / float(SR)
			var f_sub: float = lerpf(85.0, 48.0, minf(1.0, lt / 0.09))
			phase_sub += TAU * f_sub / float(SR)
			var sub_env: float = minf(1.0, lt / 0.002) * exp(-lt * 26.0)
			seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
			var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
			var crack_env: float = minf(1.0, lt / 0.0015) * exp(-uc * 5.2)
			var ring_env: float = exp(-lt * 16.0)
			var ring: float = (sin(TAU * 1180.0 * lt) * 0.55 + sin(TAU * 1770.0 * lt) * 0.45) * ring_env * 0.16
			sample += (clampf(sin(phase_crack) * 1.35, -1.0, 1.0) * 0.62 + noise * 0.34 * exp(-lt * 40.0)) * crack_env * 0.34 + sin(phase_sub) * sub_env * 0.24 + ring
		out[i] = clampf(sample, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_mono_tether() -> AudioStreamWAV:
	# Tight rhythmic electrical zap / stun pulse (Picket Drone)
	var dur: float = 0.12
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var pulse_u: float = fmod(u * 3.0, 1.0)
		var freq: float = lerpf(1260.0, 440.0, pulse_u) + sin(TAU * 120.0 * t) * 110.0
		phase += TAU * freq / float(SR)
		var env: float = minf(1.0, pulse_u / 0.08) * exp(-pulse_u * 4.5) * (1.0 - 0.35 * u)
		var sq: float = clampf(sin(phase) * 1.6, -1.0, 1.0)
		out[i] = sq * env * 0.25
	return SynthPrimitives.make_wav(out)


func _synth_mono_bastion() -> AudioStreamWAV:
	# Deep pneumatic autocannon boom + sub-bass transient punch (Bastion Emplacement)
	var dur: float = 0.27
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var phase_sub: float = 0.0
	var seed_val: int = 55101
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var freq: float = lerpf(165.0, 42.0, pow(u, 0.48))
		phase += TAU * freq / float(SR)
		var sub_f: float = lerpf(82.0, 48.0, minf(1.0, t / 0.095))
		phase_sub += TAU * sub_f / float(SR)
		var sub_env: float = minf(1.0, t / 0.0025) * exp(-t * 25.0)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.20)
		var boom_env: float = minf(1.0, t / 0.0025) * exp(-u * 4.8)
		var hiss_t: float = maxf(0.0, t - 0.07)
		var hiss_env: float = (minf(1.0, hiss_t / 0.01) * exp(-hiss_t * 22.0)) if t >= 0.07 else 0.0
		var hiss: float = (noise - lp) * hiss_env * 0.14
		out[i] = clampf((sin(phase) * 0.72 + lp * 0.44) * boom_env * 0.36 + sin(phase_sub) * sub_env * 0.24 + hiss, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_mono_overclock() -> AudioStreamWAV:
	# Deep industrial turbine spin-up + resonant quantized Axiom chime
	var dur: float = 0.42
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase_turb: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var turb_f: float = lerpf(95.0, 340.0, pow(u, 0.72))
		phase_turb += TAU * turb_f / float(SR)
		var turb_env: float = sin(PI * u) * 0.75
		var turb: float = (sin(phase_turb) * 0.65 + sin(phase_turb * 2.0) * 0.25) * turb_env * 0.26
		var chime: float = 0.0
		if t >= 0.14:
			var ct: float = t - 0.14
			var c_env: float = minf(1.0, ct / 0.006) * exp(-ct * 7.5)
			chime = (sin(TAU * 440.0 * ct) * 0.5 + sin(TAU * 659.25 * ct) * 0.35 + sin(TAU * 880.0 * ct) * 0.15) * c_env * 0.24
		out[i] = clampf(turb + chime, -0.95, 0.95)
	return SynthPrimitives.make_wav(out)


func _synth_mono_shield_overcharge() -> AudioStreamWAV:
	# Resonant harmonic shield-capacitor surge + crisp barrier lock chime (Aegis Relay)
	var dur: float = 0.32
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var f_sweep: float = lerpf(260.0, 780.0, pow(u, 0.6))
		phase += TAU * f_sweep / float(SR)
		var env: float = minf(1.0, t / 0.012) * exp(-u * 3.2)
		var lock: float = 0.0
		if t >= 0.10:
			var lt: float = t - 0.10
			var l_env: float = minf(1.0, lt / 0.004) * exp(-lt * 11.0)
			lock = (sin(TAU * 587.33 * lt) * 0.55 + sin(TAU * 880.0 * lt) * 0.45) * l_env * 0.22
		out[i] = clampf((sin(phase) * 0.65 + sin(phase * 1.5) * 0.35) * env * 0.24 + lock, -0.95, 0.95)
	return SynthPrimitives.make_wav(out)


func _synth_mono_suppressive_lock() -> AudioStreamWAV:
	# Quantized downward clamp-lock stun pulse (Picket Drone)
	var dur: float = 0.22
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var step_f: float = 780.0 if u < 0.33 else (520.0 if u < 0.66 else 260.0)
		phase += TAU * (step_f + sin(TAU * 64.0 * t) * 55.0) / float(SR)
		var env: float = minf(1.0, t / 0.004) * exp(-u * 4.2)
		out[i] = clampf(sin(phase) * 1.3, -1.0, 1.0) * env * 0.26
	return SynthPrimitives.make_wav(out)


func _synth_mono_bark(notes: PackedFloat32Array, is_order: bool) -> AudioStreamWAV:
	# Lower-pitched quantized harmonic tones + crisp mechanical relay click (170-220ms)
	var step_dur: float = 0.050 if is_order else 0.058
	var tail: float = 0.095
	var total_dur: float = step_dur * float(notes.size()) + tail
	var count: int = int(SR * total_dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	out.fill(0.0)
	var seed_val: int = 4409
	# Initial crisp mechanical relay click (first 16ms)
	var click_len: int = mini(count, int(SR * 0.016))
	for c: int in range(click_len):
		var ct: float = float(c) / float(SR)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var n: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		var c_env: float = exp(-ct * 190.0)
		out[c] += (sin(TAU * 1650.0 * ct) * 0.55 + n * 0.45) * c_env * 0.22
	# Quantized harmonic industrial steps
	for idx: int in range(notes.size()):
		var f: float = notes[idx]
		var start_i: int = int((0.012 + float(idx) * step_dur) * float(SR))
		var note_len: int = int((step_dur + tail) * float(SR))
		for j: int in range(note_len):
			var pos: int = start_i + j
			if pos >= count:
				break
			var lt: float = float(j) / float(SR)
			var env: float = minf(1.0, lt / 0.004) * exp(-lt * 18.0)
			var wave: float = sin(TAU * f * lt) * 0.68 + clampf(sin(TAU * f * 2.0 * lt) * 1.2, -1.0, 1.0) * 0.22 + sin(TAU * f * 0.5 * lt) * 0.10
			out[pos] = clampf(out[pos] + wave * env * 0.22, -0.95, 0.95)
	return SynthPrimitives.make_wav(out)


func _synth_mono_siege() -> AudioStreamWAV:
	# Deep heavy deployed artillery boom + sub-bass transient punch + metallic breech clang (Anvil Siege-Walker)
	var dur: float = 0.40
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var phase_sub: float = 0.0
	var seed_val: int = 88321
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var freq: float = lerpf(135.0, 32.0, pow(u, 0.42))
		phase += TAU * freq / float(SR)
		var sub_f: float = lerpf(80.0, 45.0, minf(1.0, t / 0.11))
		phase_sub += TAU * sub_f / float(SR)
		var sub_env: float = minf(1.0, t / 0.0025) * exp(-t * 20.0)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.15)
		var boom_env: float = minf(1.0, t / 0.003) * exp(-u * 3.8)
		var clang: float = 0.0
		if t >= 0.06:
			var ct: float = t - 0.06
			var c_env: float = minf(1.0, ct / 0.004) * exp(-ct * 16.0)
			clang = (sin(TAU * 480.0 * ct) * 0.5 + sin(TAU * 725.0 * ct) * 0.35 + (noise - lp) * 0.25) * c_env * 0.15
		out[i] = clampf((sin(phase) * 0.74 + lp * 0.46) * boom_env * 0.40 + sin(phase_sub) * sub_env * 0.26 + clang, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_deploy_anchor_lock() -> AudioStreamWAV:
	# Crisp pneumatic anchor lock-in thud + metallic clamp click (Anvil Siege-Walker DEPLOYED frame)
	var dur: float = 0.24
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase_sub: float = 0.0
	var seed_val: int = 33719
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var sub_f: float = lerpf(86.0, 46.0, minf(1.0, t / 0.095))
		phase_sub += TAU * sub_f / float(SR)
		var sub_env: float = minf(1.0, t / 0.002) * exp(-t * 24.0)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.22)
		var clamp_click: float = (sin(TAU * 680.0 * t) * 0.55 + sin(TAU * 1340.0 * t) * 0.30 + (noise - lp) * 0.25) * exp(-t * 48.0) * 0.24
		var air_hiss: float = (noise - lp) * (minf(1.0, maxf(0.0, t - 0.03) / 0.01) * exp(-maxf(0.0, t - 0.03) * 24.0) if t >= 0.03 else 0.0) * 0.12
		out[i] = clampf(sin(phase_sub) * sub_env * 0.34 + lp * exp(-u * 6.0) * 0.14 + clamp_click + air_hiss, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_mono_kinetic_barrier() -> AudioStreamWAV:
	# Heavy metallic hydraulic lock + harmonic cyan barrier hum (Monolith Dreadnought)
	var dur: float = 0.36
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var clank: float = 0.0
		if t < 0.055:
			var c_env: float = exp(-t * 58.0)
			clank = (sin(TAU * 190.0 * t) * 0.6 + sin(TAU * 620.0 * t) * 0.4) * c_env * 0.34
		var sweep_f: float = lerpf(210.0, 520.0, pow(u, 0.55))
		phase += TAU * sweep_f / float(SR)
		var hum_env: float = minf(1.0, t / 0.020) * exp(-u * 2.9)
		var hum: float = (sin(phase) * 0.58 + sin(phase * 1.5) * 0.28 + sin(phase * 2.0) * 0.14) * hum_env * 0.26
		out[i] = clampf(clank + hum, -0.95, 0.95)
	return SynthPrimitives.make_wav(out)


func _synth_mono_grav_pulse() -> AudioStreamWAV:
	# Resonant downward gravity-well compression wave + sub-bass thump (Null-Grid Projector)
	var dur: float = 0.42
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var phase_sub: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var f_drop: float = lerpf(640.0, 88.0, pow(u, 0.58)) + sin(TAU * 28.0 * t) * 42.0
		var f_sub: float = lerpf(110.0, 38.0, u)
		phase += TAU * f_drop / float(SR)
		phase_sub += TAU * f_sub / float(SR)
		var env: float = minf(1.0, t / 0.015) * exp(-u * 3.1)
		var wave: float = (sin(phase) * 0.55 + clampf(sin(phase * 1.5) * 1.3, -1.0, 1.0) * 0.20 + sin(phase_sub) * 0.45) * env * 0.34
		out[i] = clampf(wave, -0.95, 0.95)
	return SynthPrimitives.make_wav(out)


# =============================================================================
# DYNAMIC 3-LAYER INDUSTRIAL AMBIENT LOOPS (4.0s EXACT CYCLES)
# =============================================================================

func _synth_ambience_monolith_base_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: cold industrial sub-bass turbine hum (55/82.5 Hz fifths) + metallic filter swell + clock ticks
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var swell: float = 0.65 + 0.35 * sin(TAU * 0.25 * t)
		var turbine: float = sin(TAU * 55.0 * t) * 0.44 + sin(TAU * 82.5 * t) * 0.28 + sin(TAU * 110.0 * t) * 0.16
		var metal_ring: float = sin(TAU * 247.5 * t) * (0.055 * (0.5 + 0.5 * sin(TAU * 0.5 * t)))
		var tick_u: float = fmod(t * 2.0, 1.0)
		var clock_tick: float = sin(TAU * 880.0 * t) * exp(-tick_u * 48.0) * 0.06
		lp = lerpf(lp, turbine * swell + metal_ring + clock_tick, 0.10)
		out[i] = lp * 0.62
	return SynthPrimitives.make_loop_wav(out)


func _synth_ambience_monolith_combat_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: tight low-mid mechanical piston pulse + muted dark brass/anvil harmonic tension
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var piston_u: float = fmod(t * 2.0, 1.0)
		var piston_env: float = exp(-piston_u * 6.5)
		var piston: float = (sin(TAU * 55.0 * t) * 0.55 + sin(TAU * 110.0 * t) * 0.25) * piston_env * 0.42
		var anvil_u: float = fmod(t * 1.0 + 0.5, 1.0)
		var anvil_env: float = exp(-anvil_u * 10.0)
		var brass_f: float = 137.5 if (int(floor(t * 0.5)) % 2 == 0) else 123.75
		var anvil: float = (sin(TAU * brass_f * t) * 0.55 + sin(TAU * brass_f * 1.5 * t) * 0.28) * anvil_env * 0.22
		lp = lerpf(lp, piston + anvil, 0.18)
		out[i] = lp * 0.70
	return SynthPrimitives.make_loop_wav(out)


func _synth_ambience_monolith_uplink_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: cold high-voltage transformer hum + deliberate radar-ping overtones
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var xform: float = (sin(TAU * 120.0 * t) * 0.26 + sin(TAU * 240.0 * t) * 0.14) * (0.72 + 0.28 * sin(TAU * 0.5 * t))
		var ping_u: float = fmod(t * 0.5, 1.0)
		var ping_env: float = exp(-ping_u * 9.5)
		var ping: float = (sin(TAU * 528.0 * t) * 0.30 + sin(TAU * 792.0 * t) * 0.18) * ping_env
		out[i] = (xform + ping) * 0.26
	return SynthPrimitives.make_loop_wav(out)
