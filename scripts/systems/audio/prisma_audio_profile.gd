class_name PrismaAudioProfile
extends FactionAudioProfile

## Procedural audio profile for PRISMA_DEI (&"prisma_cathedral").
## Houses crystalline prism weapons, liturgical ability chimes, ethereal bell-harmonic barks,
## and 3-layer adaptive cathedral ambient loops.

const SR: int = SynthPrimitives.SAMPLE_RATE


func get_profile_id() -> StringName:
	return &"prisma_cathedral"


func get_stream_prefix() -> String:
	return "prisma_"


func register_cooldowns(cooldowns_ms: Dictionary) -> void:
	cooldowns_ms[&"weapon_prism_bolt"] = 65
	cooldowns_ms[&"weapon_prism_beam"] = 80
	cooldowns_ms[&"weapon_prism_refract"] = 75
	cooldowns_ms[&"ability_solar_step"] = 100
	cooldowns_ms[&"ability_radiant_mark"] = 110
	cooldowns_ms[&"ability_luminous_mend"] = 120
	cooldowns_ms[&"ability_focus_alignment"] = 120
	cooldowns_ms[&"ability_blinding_glare"] = 120


func build_weapon_and_ability_sfx(sfx_bank: Dictionary) -> void:
	sfx_bank[&"weapon_prism_bolt"] = _synth_prism_bolt()
	if not sfx_bank.has(&"weapon_prism_beam"):
		sfx_bank[&"weapon_prism_beam"] = SynthPrimitives.synth_prism_beam()
	if not sfx_bank.has(&"weapon_prism_refract"):
		sfx_bank[&"weapon_prism_refract"] = SynthPrimitives.synth_prism_refract()
	sfx_bank[&"ability_solar_step"] = _synth_solar_step()
	sfx_bank[&"ability_radiant_mark"] = _synth_radiant_mark()
	sfx_bank[&"ability_luminous_mend"] = _synth_luminous_mend()
	sfx_bank[&"ability_focus_alignment"] = _synth_focus_alignment()
	sfx_bank[&"ability_blinding_glare"] = _synth_blinding_glare()


func build_bark_sfx(sfx_bank: Dictionary) -> void:
	# Ethereal bell-harmonic selection and order acknowledgments (clean fifths & octaves)
	sfx_bank[&"prisma_bark_worker_select"] = _synth_prisma_bark(PackedFloat32Array([587.33, 880.0]), false)
	sfx_bank[&"prisma_bark_worker_order"] = _synth_prisma_bark(PackedFloat32Array([659.25, 987.77]), true)
	sfx_bank[&"prisma_bark_swarm_select"] = _synth_prisma_bark(PackedFloat32Array([659.25, 987.77, 1318.51]), false)
	sfx_bank[&"prisma_bark_swarm_order"] = _synth_prisma_bark(PackedFloat32Array([783.99, 1174.66]), true)
	sfx_bank[&"prisma_bark_counter_select"] = _synth_prisma_bark(PackedFloat32Array([523.25, 783.99, 1046.50]), false)
	sfx_bank[&"prisma_bark_counter_order"] = _synth_prisma_bark(PackedFloat32Array([587.33, 880.0, 1174.66]), true)
	sfx_bank[&"prisma_bark_support_select"] = _synth_prisma_bark(PackedFloat32Array([659.25, 880.0, 1318.51]), false)
	sfx_bank[&"prisma_bark_support_order"] = _synth_prisma_bark(PackedFloat32Array([783.99, 1046.50, 1567.98]), true)
	sfx_bank[&"prisma_bark_heavy_select"] = _synth_prisma_bark(PackedFloat32Array([392.0, 587.33, 783.99]), false)
	sfx_bank[&"prisma_bark_heavy_order"] = _synth_prisma_bark(PackedFloat32Array([440.0, 659.25, 880.0]), true)
	sfx_bank[&"prisma_bldg_select_hub"] = _synth_prisma_bark(PackedFloat32Array([329.63, 493.88, 659.25, 987.77]), false)
	sfx_bank[&"prisma_bldg_select_production"] = _synth_prisma_bark(PackedFloat32Array([440.0, 659.25, 880.0]), false)
	sfx_bank[&"prisma_bldg_select_tech"] = _synth_prisma_bark(PackedFloat32Array([523.25, 783.99, 1174.66]), false)
	sfx_bank[&"prisma_bldg_select_defense"] = _synth_prisma_bark(PackedFloat32Array([493.88, 739.99, 987.77]), true)
	sfx_bank[&"prisma_bldg_select_utility"] = _synth_prisma_bark(PackedFloat32Array([587.33, 880.0]), false)


func build_ambient_layers() -> Dictionary:
	return {
		"base": _synth_ambience_prisma_base_loop(),
		"combat": _synth_ambience_prisma_combat_loop(),
		"uplink": _synth_ambience_prisma_uplink_loop(),
	}


func resolve_weapon_sfx(sfx_id: StringName, unit_type_id: StringName) -> Dictionary:
	match sfx_id:
		&"weapon_prism_bolt":
			return {"sfx_id": &"weapon_prism_bolt", "db": -6.2, "jitter": 0.05}
		&"weapon_prism_beam":
			return {"sfx_id": &"weapon_prism_beam", "db": -6.0, "jitter": 0.03}
		&"weapon_prism_refract":
			return {"sfx_id": &"weapon_prism_refract", "db": -5.5, "jitter": 0.05}

	match unit_type_id:
		&"acolyte", &"lumen_skiff":
			return {"sfx_id": &"weapon_prism_bolt", "db": -6.2, "jitter": 0.05}
		&"votary", &"prism_weaver":
			return {"sfx_id": &"weapon_prism_refract", "db": -5.5, "jitter": 0.05}
		&"lens_adjudicator":
			return {"sfx_id": &"weapon_prism_beam", "db": -6.0, "jitter": 0.03}
	return {}


func resolve_ability_sfx(ability_id: StringName) -> Dictionary:
	match ability_id:
		&"solar_step":
			return {"sfx_id": &"ability_solar_step", "db": -3.5, "jitter": 0.04}
		&"radiant_mark":
			return {"sfx_id": &"ability_radiant_mark", "db": -3.0, "jitter": 0.02}
		&"luminous_mend":
			return {"sfx_id": &"ability_luminous_mend", "db": -3.0, "jitter": 0.02}
		&"focus_alignment":
			return {"sfx_id": &"ability_focus_alignment", "db": -2.8, "jitter": 0.02}
		&"blinding_glare":
			return {"sfx_id": &"ability_blinding_glare", "db": -3.2, "jitter": 0.04}
	return {}


# =============================================================================
# CRYSTALLINE & CATHEDRAL SYNTHS
# =============================================================================

func _synth_prism_bolt() -> AudioStreamWAV:
	# Crisp high-harmonic crystal focus snap (~0.09s)
	var dur: float = 0.095
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var ph1: float = 0.0
	var ph2: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var f1: float = lerpf(1680.0, 740.0, pow(u, 0.55))
		var f2: float = lerpf(2520.0, 1480.0, pow(u, 0.45))
		ph1 += TAU * f1 / float(SR)
		ph2 += TAU * f2 / float(SR)
		var env: float = minf(1.0, t / 0.002) * exp(-u * 6.8)
		out[i] = clampf((sin(ph1) * 0.62 + sin(ph2) * 0.38) * env * 0.24, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_solar_step() -> AudioStreamWAV:
	# Shimmering upward glass-harp glissando
	return SynthPrimitives.synth_chime(PackedFloat32Array([659.25, 880.0, 1174.66, 1567.98]), 0.038, 0.22)


func _synth_radiant_mark() -> AudioStreamWAV:
	# Bright liturgical bell-ping lock chime (~0.30s)
	var dur: float = 0.30
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var env: float = minf(1.0, t / 0.003) * exp(-u * 4.5)
		var bell: float = sin(TAU * 1046.50 * t) * 0.50 + sin(TAU * 1567.98 * t) * 0.30 + sin(TAU * 2637.02 * t) * 0.20 * exp(-t * 16.0)
		out[i] = clampf(bell * env * 0.28, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_luminous_mend() -> AudioStreamWAV:
	# Warm harmonic major-fifth choral chime swell
	return SynthPrimitives.synth_chord_swell(PackedFloat32Array([523.25, 659.25, 783.99, 1046.50]), 0.40, 0.28)


func _synth_focus_alignment() -> AudioStreamWAV:
	# Rising high-Q resonant lens hum + golden lock harmonic (~0.34s)
	var dur: float = 0.34
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var ph: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var freq: float = lerpf(392.0, 880.0, pow(u, 0.65))
		ph += TAU * freq / float(SR)
		var env: float = minf(1.0, t / 0.015) * exp(-u * 2.8)
		var tone: float = (sin(ph) * 0.56 + sin(ph * 1.5) * 0.28 + sin(ph * 2.0) * 0.16) * env * 0.26
		var lock: float = 0.0
		if t >= 0.12:
			var lt: float = t - 0.12
			lock = sin(TAU * 1318.51 * lt) * minf(1.0, lt / 0.005) * exp(-lt * 10.0) * 0.16
		out[i] = clampf(tone + lock, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_blinding_glare() -> AudioStreamWAV:
	# Crystalline flash-burst with airy glass shimmer tail (~0.32s)
	var dur: float = 0.32
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var ph_a: float = 0.0
	var ph_b: float = 0.0
	var seed_val: int = 71903
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var fa: float = lerpf(2349.32, 987.77, pow(u, 0.45))
		var fb: float = lerpf(1760.0, 659.25, pow(u, 0.55))
		ph_a += TAU * fa / float(SR)
		ph_b += TAU * fb / float(SR)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.28)
		var hp: float = noise - lp
		var flash_env: float = minf(1.0, t / 0.002) * exp(-u * 4.6)
		var air_env: float = minf(1.0, t / 0.008) * exp(-u * 5.8)
		out[i] = clampf((sin(ph_a) * 0.48 + sin(ph_b) * 0.42) * flash_env * 0.26 + hp * air_env * 0.18, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


func _synth_prisma_bark(notes: PackedFloat32Array, is_order: bool) -> AudioStreamWAV:
	# Ethereal bell-harmonic tones with crisp glassy overtone decay
	var step_dur: float = 0.044 if is_order else 0.054
	var tail: float = 0.13
	var total_dur: float = step_dur * float(notes.size()) + tail
	var count: int = int(SR * total_dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	out.fill(0.0)
	for idx: int in range(notes.size()):
		var f: float = notes[idx]
		var start_i: int = int((float(idx) * step_dur) * float(SR))
		var note_len: int = int((step_dur + tail) * float(SR))
		for j: int in range(note_len):
			var pos: int = start_i + j
			if pos >= count:
				break
			var lt: float = float(j) / float(SR)
			var env: float = minf(1.0, lt / 0.004) * exp(-lt * 13.5)
			var shimmer: float = sin(TAU * f * 3.0 * lt) * exp(-lt * 26.0) * 0.18
			var wave: float = sin(TAU * f * lt) * 0.64 + sin(TAU * f * 2.0 * lt) * 0.22 + shimmer
			out[pos] = clampf(out[pos] + wave * env * 0.21, -0.92, 0.92)
	return SynthPrimitives.make_wav(out)


# =============================================================================
# DYNAMIC 3-LAYER CATHEDRAL AMBIENT LOOPS (4.0s EXACT CYCLES)
# =============================================================================

func _synth_ambience_prisma_base_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: serene airy cathedral-synth fifth pad (D3/A3/F#4) + distant crystalline shimmer
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var swell: float = 0.68 + 0.32 * sin(TAU * 0.25 * t)
		var pad: float = sin(TAU * 146.83 * t) * 0.38 + sin(TAU * 220.0 * t) * 0.28 + sin(TAU * 293.66 * t) * 0.18 + sin(TAU * 369.99 * t) * 0.10
		var shimmer_u: float = fmod(t * 0.5, 1.0)
		var shimmer: float = (sin(TAU * 880.0 * t) * 0.06 + sin(TAU * 1174.66 * t) * 0.04) * sin(PI * shimmer_u)
		lp = lerpf(lp, pad * swell + shimmer, 0.12)
		out[i] = lp * 0.44
	return SynthPrimitives.make_loop_wav(out)


func _synth_ambience_prisma_combat_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: rhythmic liturgical arpeggio pulse + tense high-harmonic prism shimmer
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var arp_notes: PackedFloat32Array = PackedFloat32Array([293.66, 369.99, 440.0, 587.33, 440.0, 369.99, 329.63, 440.0])
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var step_idx: int = int(floor(t * 2.0)) % arp_notes.size()
		var step_u: float = fmod(t * 2.0, 1.0)
		var f_arp: float = arp_notes[step_idx]
		var arp_env: float = minf(1.0, step_u / 0.04) * exp(-step_u * 4.8)
		var arp: float = (sin(TAU * f_arp * t) * 0.58 + sin(TAU * f_arp * 2.0 * t) * 0.24) * arp_env * 0.32
		var pulse_u: float = fmod(t * 1.0, 1.0)
		var bass: float = sin(TAU * 110.0 * t) * exp(-pulse_u * 4.5) * 0.24
		lp = lerpf(lp, arp + bass, 0.22)
		out[i] = lp * 0.56
	return SynthPrimitives.make_loop_wav(out)


func _synth_ambience_prisma_uplink_loop() -> AudioStreamWAV:
	# 4.0s exact cycle: resonant orbital-choir harmonic swell + crisp geometric beacon chime
	var dur: float = 4.0
	var count: int = int(SR * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SR)
		var swell: float = 0.58 + 0.42 * sin(TAU * 0.5 * t)
		var choir: float = (sin(TAU * 220.0 * t) * 0.22 + sin(TAU * 329.63 * t) * 0.18 + sin(TAU * 440.0 * t) * 0.14) * swell
		var chime_u: float = fmod(t * 0.5, 1.0)
		var chime_env: float = exp(-chime_u * 7.5)
		var chime: float = (sin(TAU * 880.0 * t) * 0.24 + sin(TAU * 1318.51 * t) * 0.14) * chime_env
		out[i] = (choir + chime) * 0.26
	return SynthPrimitives.make_loop_wav(out)
