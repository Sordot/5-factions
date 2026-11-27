class_name SynthPrimitives
extends RefCounted

const SAMPLE_RATE: int = 22050


static func soft_clip(sample: float, drive: float = 1.0) -> float:
	var d: float = maxf(0.05, drive)
	return tanh(sample * d) / maxf(0.001, tanh(d))


static func remove_dc_offset(samples: PackedFloat32Array) -> void:
	var n: int = samples.size()
	if n <= 0:
		return
	var sum: float = 0.0
	for i: int in range(n):
		sum += samples[i]
	var mean: float = sum / float(n)
	if absf(mean) <= 0.00001:
		return
	for i: int in range(n):
		samples[i] -= mean


static func apply_biquad_lowpass(samples: PackedFloat32Array, cutoff_hz: float, q: float = 0.707) -> void:
	var n: int = samples.size()
	if n <= 0:
		return
	var fc: float = clampf(cutoff_hz, 20.0, float(SAMPLE_RATE) * 0.45)
	var safe_q: float = maxf(0.1, q)
	var w0: float = TAU * fc / float(SAMPLE_RATE)
	var cos_w0: float = cos(w0)
	var alpha: float = sin(w0) / (2.0 * safe_q)
	var inv_a0: float = 1.0 / (1.0 + alpha)
	var b0: float = ((1.0 - cos_w0) * 0.5) * inv_a0
	var b1: float = (1.0 - cos_w0) * inv_a0
	var b2: float = b0
	var a1: float = (-2.0 * cos_w0) * inv_a0
	var a2: float = (1.0 - alpha) * inv_a0
	var x1: float = 0.0
	var x2: float = 0.0
	var y1: float = 0.0
	var y2: float = 0.0
	for i: int in range(n):
		var x0: float = samples[i]
		var y0: float = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
		samples[i] = y0


static func apply_biquad_bandpass(samples: PackedFloat32Array, center_hz: float, q: float = 1.4) -> void:
	var n: int = samples.size()
	if n <= 0:
		return
	var fc: float = clampf(center_hz, 20.0, float(SAMPLE_RATE) * 0.45)
	var safe_q: float = maxf(0.1, q)
	var w0: float = TAU * fc / float(SAMPLE_RATE)
	var cos_w0: float = cos(w0)
	var alpha: float = sin(w0) / (2.0 * safe_q)
	var inv_a0: float = 1.0 / (1.0 + alpha)
	var b0: float = alpha * inv_a0
	var b1: float = 0.0
	var b2: float = -alpha * inv_a0
	var a1: float = (-2.0 * cos_w0) * inv_a0
	var a2: float = (1.0 - alpha) * inv_a0
	var x1: float = 0.0
	var x2: float = 0.0
	var y1: float = 0.0
	var y2: float = 0.0
	for i: int in range(n):
		var x0: float = samples[i]
		var y0: float = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
		samples[i] = y0


static func make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		var shaped: float = clampf(soft_clip(samples[i], 1.15) * 0.95, -0.98, 0.98)
		var pcm: int = int(round(shaped * 32767.0))
		if pcm < 0:
			pcm += 65536
		bytes[i * 2] = pcm & 0xFF
		bytes[i * 2 + 1] = (pcm >> 8) & 0xFF
	wav.data = bytes
	return wav


static func _crossfade_loop_buffer(samples: PackedFloat32Array, crossfade_sec: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = samples.duplicate()
	remove_dc_offset(buf)
	var n: int = buf.size()
	if n < 256:
		return buf
	var fade_len: int = clampi(int(round(float(SAMPLE_RATE) * crossfade_sec)), 64, n / 4)
	var out_len: int = n - fade_len
	var looped: PackedFloat32Array = PackedFloat32Array()
	looped.resize(out_len)
	for i: int in range(fade_len):
		var u: float = float(i) / float(fade_len)
		var w_head: float = sin(u * PI * 0.5)
		var w_tail: float = cos(u * PI * 0.5)
		looped[i] = buf[i] * w_head + buf[out_len + i] * w_tail
	for i: int in range(fade_len, out_len):
		looped[i] = buf[i]
	return looped


static func make_seamless_loop_wav(samples: PackedFloat32Array, crossfade_sec: float = 0.14) -> AudioStreamWAV:
	var looped: PackedFloat32Array = _crossfade_loop_buffer(samples, crossfade_sec)
	var wav: AudioStreamWAV = make_wav(looped)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = looped.size()
	return wav


static func make_stereo_loop_wav(left: PackedFloat32Array, right: PackedFloat32Array, crossfade_sec: float = 0.14) -> AudioStreamWAV:
	var l_loop: PackedFloat32Array = _crossfade_loop_buffer(left, crossfade_sec)
	var r_loop: PackedFloat32Array = _crossfade_loop_buffer(right, crossfade_sec)
	var frame_count: int = mini(l_loop.size(), r_loop.size())
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = true
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(frame_count * 4)
	for i: int in range(frame_count):
		var sl: float = clampf(soft_clip(l_loop[i], 1.15) * 0.95, -0.98, 0.98)
		var sr: float = clampf(soft_clip(r_loop[i], 1.15) * 0.95, -0.98, 0.98)
		var pcm_l: int = int(round(sl * 32767.0))
		if pcm_l < 0:
			pcm_l += 65536
		var pcm_r: int = int(round(sr * 32767.0))
		if pcm_r < 0:
			pcm_r += 65536
		var base: int = i * 4
		bytes[base] = pcm_l & 0xFF
		bytes[base + 1] = (pcm_l >> 8) & 0xFF
		bytes[base + 2] = pcm_r & 0xFF
		bytes[base + 3] = (pcm_r >> 8) & 0xFF
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frame_count
	return wav


static func make_stereo_widened_loop_wav(mono_samples: PackedFloat32Array, delay_ms: float = 9.0, crossfade_sec: float = 0.14) -> AudioStreamWAV:
	var n: int = mono_samples.size()
	if n < 256:
		return make_seamless_loop_wav(mono_samples, crossfade_sec)
	var delay_samples: int = clampi(int(round(float(SAMPLE_RATE) * maxf(0.0, delay_ms) * 0.001)), 1, maxi(1, n / 8))
	var left: PackedFloat32Array = PackedFloat32Array()
	var right: PackedFloat32Array = PackedFloat32Array()
	left.resize(n)
	right.resize(n)
	var inv_sr: float = 1.0 / float(SAMPLE_RATE)
	for i: int in range(n):
		var s0: float = mono_samples[i]
		var s_del: float = mono_samples[(i - delay_samples + n) % n]
		var breath: float = 0.055 * sin(TAU * 0.06 * (float(i) * inv_sr))
		left[i] = s0 * (0.94 + breath) + s_del * 0.08
		right[i] = s_del * (0.94 - breath) + s0 * 0.08
	return make_stereo_loop_wav(left, right, crossfade_sec)


static func make_loop_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	return make_seamless_loop_wav(samples, 0.12)


static func synth_glass_click() -> AudioStreamWAV:
	var count: int = int(SAMPLE_RATE * 0.055)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.002) * exp(-t * 68.0)
		var s: float = sin(TAU * 1380.0 * t) * 0.6 + sin(TAU * 2760.0 * t) * 0.32 + sin(TAU * 4140.0 * t) * 0.08
		out[i] = s * env * 0.32
	return make_wav(out)


static func synth_chime(freqs: PackedFloat32Array, step_dur: float, amp: float) -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_chord_swell(freqs: PackedFloat32Array, duration: float, amp: float) -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_chirp(f0: float, f1: float, duration: float, amp: float) -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_double_chirp(f0: float, f1: float, duration: float, amp: float) -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_error_buzz() -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_destruction_boom() -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_explosion_heavy() -> AudioStreamWAV:
	# Deep Tier 2 heavy unit / structure detonation with layered 48-84Hz sub-bass drop
	var dur: float = 0.44
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var phase_sub: float = 0.0
	var seed_val: int = 60214
	var lp: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var freq: float = lerpf(118.0, 28.0, pow(u, 0.52))
		phase += TAU * freq / float(SAMPLE_RATE)
		var sub_f: float = lerpf(84.0, 44.0, minf(1.0, t / 0.12))
		phase_sub += TAU * sub_f / float(SAMPLE_RATE)
		var sub_env: float = minf(1.0, t / 0.003) * exp(-t * 17.5)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var noise: float = (float(seed_val) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.14)
		var env: float = minf(1.0, t / 0.004) * exp(-u * 3.8)
		out[i] = clampf((sin(phase) * 0.54 + lp * 0.62) * env * 0.36 + sin(phase_sub) * sub_env * 0.28, -0.92, 0.92)
	return make_wav(out)


static func synth_shield_shatter() -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_alert_under_attack() -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_alert_uplink() -> AudioStreamWAV:
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
	return make_wav(out)


static func synth_alert_complete() -> AudioStreamWAV:
	return synth_chime(PackedFloat32Array([587.33, 880.0, 1174.66]), 0.065, 0.23)


static func synth_rank_up_chime() -> AudioStreamWAV:
	return synth_chime(PackedFloat32Array([659.25, 880.0, 1318.5]), 0.055, 0.22)


static func synth_prism_beam() -> AudioStreamWAV:
	# Clean resonant crystalline beam pulse (harmonic fifth + octave shimmer, ~0.16s)
	var dur: float = 0.16
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var ph1: float = 0.0
	var ph2: float = 0.0
	var ph3: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var f1: float = lerpf(440.0, 493.88, u)
		ph1 += TAU * f1 / float(SAMPLE_RATE)
		ph2 += TAU * (f1 * 1.5) / float(SAMPLE_RATE)
		ph3 += TAU * (f1 * 3.0) / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.008) * exp(-u * 2.6) * (1.0 - 0.35 * u)
		var sig: float = sin(ph1) * 0.52 + sin(ph2) * 0.30 + sin(ph3) * 0.18
		out[i] = clampf(sig * env * 0.24, -0.92, 0.92)
	return make_wav(out)


static func synth_prism_refract() -> AudioStreamWAV:
	# Crisp glass-prism harmonic snap & split shimmer (~0.13s)
	var dur: float = 0.13
	var count: int = int(SAMPLE_RATE * dur)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var ph_a: float = 0.0
	var ph_b: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var f_a: float = lerpf(1568.0, 2349.32, pow(u, 0.4))
		var f_b: float = lerpf(1174.66, 1760.0, u)
		ph_a += TAU * f_a / float(SAMPLE_RATE)
		ph_b += TAU * f_b / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.002) * exp(-u * 6.0)
		var sig: float = sin(ph_a) * 0.58 + sin(ph_b) * 0.42
		out[i] = clampf(sig * env * 0.22, -0.92, 0.92)
	return make_wav(out)
