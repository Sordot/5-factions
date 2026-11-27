# Milestone 4.10 — System Overhaul #7: Next-Gen Procedural Audio & Soundscape

**Prerequisite:** Milestone 4.9 (System Overhaul #6: HUD, Rendering & Battlefield Clarity) verified and working cleanly.

**Goal:** Overhaul the 100% procedural audio engine (`AudioManager`, `SynthPrimitives`, and pluggable `FactionAudioProfile`s) into a spacious, broadcast-clean RTS soundscape with zero loop clicks, zero match-launch synthesis hitches, and zero drowned-out tactical audio during 100+ unit clashes:

1. **Procedural Audio Bus Rack, `±75%` Camera-Relative Stereo Panning & Distance Low-Pass (`AudioManager`):** Build an idempotent multi-bus mixer (`Master`, `SFX`, `SFX_Near`, `SFX_Far`, `UI`, `Barks`, `Ambience`) with bus-level dynamics and air-absorption filtering (`2400 Hz` low-pass on distant skirmishes), and upgrade combat voices to camera-projected `AudioStreamPlayer2D` nodes delivering smooth `±75%` stereo width across the viewport.

2. **16-Voice Priority-Weighted Combat Pool, Proximity Override & Data-Driven Barks (`AudioManager`):** Expand combat polyphony from `10` to `16` voices with 4-tier priority voice stealing so small-arms fire never cuts off heavy explosions, shield shatters, or `Solar Convergence` strikes; add `+4 dB` proximity cooldown overrides; route `ai_transmission` to `UI`; add `&"ambience"` slider preview; and make `classify_unit_bark_class()` fully data-driven across all factions.

3. **Click-Free Stereo DSP Primitives & De-Duplication (`SynthPrimitives`, `GenesisAudioProfile`, `MonolithAudioProfile`, `PrismaAudioProfile`, `AudioManager`):** Replace hard clipping in `make_wav()` with warm `tanh` soft-saturation, add equal-power seamless loop crossfading + DC-offset removal + subtle stereo widening (`make_stereo_widened_loop_wav`) to eliminate all 4.0s ambient loop clicks, add reusable biquad filter primitives for Factions #4–#5, and remove duplicate `PRISMA_DEI` stream synthesis from `AudioManager`.

4. **Async Background Ambience Synthesis, Smooth Crossfades & Spectator Team 1 Ambience (`AudioManager`):** Move `4.0s` ambient stem synthesis onto `WorkerThreadPool` (zero main-thread hitches on boot or match launch), replace hard stream cuts with smooth `0.65s` crossfades, smooth `_uplink_tension` per frame with dynamic `Ambience` filter opening, and configure **Spectator Mode** to inherit **Team 1's faction ambient profile**.

**Hard Design Guardrails (MUST PRESERVE):**

* **100% Procedural Audio Pipeline:** Zero external `.ogg`, `.wav`, or `.mp3` assets—all waveforms, stereo stems, and DSP effects remain 100% generated in GDScript and Godot's built-in `AudioServer` effects.
* **Zero Gameplay or Balance Changes:** Do **not** alter any unit, building, ability, or combat stat values.
* **Pluggable Faction Extensibility:** Every bus, priority tier, bark classifier, and async stem loader must work seamlessly with future Factions #4 and #5 registered via `register_audio_profile()`.
* **Respect All Existing `SettingsManager` Sliders & Focus Mute:** Preserve Master, SFX, UI, Ambience, Mute, and Unfocused Mute behavior identically.

## Phase A — Procedural Audio Bus Rack, `±75%` Stereo Panning & Distance Filtering (`scripts/systems/audio_manager.gd`)

### A.1 Idempotent Sub-Bus Mixer Rack (`_ensure_audio_buses()`)

Replace `_ensure_master_bus_limiter()` with a clean, idempotent `_ensure_audio_buses()` helper invoked at the top of `_ready()`:

* **Bus Layout (created via `AudioServer.add_bus()` only if `AudioServer.get_bus_index(name) < 0`):**
  1. **`Master`:** Safety `AudioEffectLimiter` (`ceiling_db = -1.0`, `threshold_db = -3.0`).
  2. **`SFX` → `Master`:** Gentle `AudioEffectCompressor` (`threshold = -12.0`, `ratio = 2.6`, `attack_us = 2500.0`, `release_ms = 140.0`, `gain = 0.0`) keeping massive 4P battles punchy without pumping UI alerts or barks.
  3. **`SFX_Near` → `SFX`:** Clean direct combat bus for center/mid-viewport events.
  4. **`SFX_Far` → `SFX`:** `AudioEffectLowPassFilter` (`cutoff_hz = 2400.0`, `resonance = 0.55`) giving peripheral and edge-of-screen skirmishes natural air-absorption warmth instead of harsh high-frequency buzz.
  5. **`UI` → `Master`:** Clean uncompressed bus for clicks, economy chimes, tactical alerts, and AI radio transmissions.
  6. **`Barks` → `Master`:** Clean dedicated bus for the single-voice unit/building acknowledgment channel.
  7. **`Ambience` → `Master`:** Dynamic `AudioEffectLowPassFilter` (`cutoff_hz = 3800.0`, `resonance = 0.45`) whose reference is cached in `var _amb_lpf: AudioEffectLowPassFilter` so `_process()` can smoothly open the filter during combat/uplink tension and warm it down when paused or ducked!

* Route players cleanly:
  * `_combat_players[i].bus` dynamically assigned to `&"SFX_Near"` or `&"SFX_Far"` per shot.
  * `_ui_players[i].bus = &"UI"`.
  * `_bark_player.bus = &"Barks"`.
  * `_amb_base_player.bus = &"Ambience"`, `_amb_combat_player.bus = &"Ambience"`, `_amb_uplink_player.bus = &"Ambience"`.

### A.2 Camera-Relative `±75%` Stereo Panning (`AudioStreamPlayer2D` Combat Pool)

* Add constant: `const STEREO_PAN_WIDTH: float = 0.75` and `const FAR_BUS_NORM_THRESHOLD: float = 0.72`.
* Change `_combat_players` from `Array[AudioStreamPlayer]` to **`Array[AudioStreamPlayer2D]`**:
  * Configure every voice on creation:
    * `cp.max_distance = 100000.0` *(prevents Godot's built-in distance cutoff from fighting our zoom-aware RTS attenuation)*
    * `cp.attenuation = 0.0` *(keeps volume strictly driven by `_compute_spatial_attenuation()`)*
    * `cp.panning_strength = STEREO_PAN_WIDTH` *(exact `±75%` maximum stereo spread—crisp left/right tactical clarity on headphones without fatiguing 100% single-ear isolation!)*
* Upgrade `_compute_spatial_attenuation(world_pos: Vector2, allow_cull: bool) -> Dictionary`:
  * Return `{"culled": bool, "db_offset": float, "norm_dist": float, "pan_world_pos": Vector2, "is_far": bool}`.
  * Compute camera viewport half-width `half_w = maxf(240.0, (vp_size.x / zoom_vec.x) * 0.5)`.
  * Compute normalized horizontal offset `var pan_x: float = clampf((world_pos.x - cam.global_position.x) / half_w, -1.0, 1.0)`.
  * Compute `pan_world_pos = Vector2(cam.global_position.x + pan_x * half_w, cam.global_position.y)` so Godot's 2D stereo panner produces smooth, zoom-invariant L/R panning proportional to screen position!
  * Set `"is_far": norm > FAR_BUS_NORM_THRESHOLD` (routing distant sounds to `&"SFX_Far"` for warm low-pass air absorption).
  * When `world_pos == Vector2.INF` (non-spatial combat SFX): center at `cam.global_position` (exact `0.0` center pan) on `&"SFX_Near"`.
* Track `var _combat_world_pos: Array[Vector2]` per voice and in `_process()`: for any playing spatial combat voice, refresh its projected `global_position` relative to the active camera so sustained sounds (like `ability_solar_convergence_charge` or `explosion_heavy`) track smoothly if the player pans the camera mid-sound!

## Phase B — 16-Voice Priority-Weighted Combat Pool, Proximity Override & Data-Driven Barks (`scripts/systems/audio_manager.gd`)

### B.1 4-Tier Priority Voice Stealing (`COMBAT_POOL_SIZE = 16`)

* Increase `const COMBAT_POOL_SIZE: int = 16`.
* Add priority enum & per-voice metadata arrays:

```gdscript
enum SFXPriority {
	SMALL_ARMS = 1,
	HEAVY_WEAPON = 2,
	TACTICAL_ABILITY = 3,
	STRATEGIC_IMPACT = 4,
}
```

* Add parallel arrays sized to `COMBAT_POOL_SIZE`:
  * `var _combat_priority: Array[int] = []`
  * `var _combat_volume_db: Array[float] = []`
  * `var _combat_world_pos: Array[Vector2] = []`
* Add `func _resolve_sfx_priority(sfx_id: StringName) -> int`:
  * **Tier 4 (`STRATEGIC_IMPACT`):** `&"explosion_heavy"`, `&"ability_solar_convergence_impact"`, `&"ability_solar_convergence_charge"`, `&"ability_seismic_slam"`.
  * **Tier 3 (`TACTICAL_ABILITY`):** `&"shield_shatter"`, `&"deploy_lock"`, `&"deploy_release"`, `&"deploy_anchor_lock"`, `&"overclock_activate"`, or any `String(sfx_id).begins_with("ability_")`.
  * **Tier 2 (`HEAVY_WEAPON`):** `&"entity_destroyed"`, `&"weapon_prisma_lance"`, `&"weapon_mono_siege"`, `&"weapon_mono_bastion"`, `&"weapon_mortar"`, `&"weapon_arc_lancer"`, `&"weapon_rail"`, `&"weapon_heavy"`, `&"weapon_goliath"`.
  * **Tier 1 (`SMALL_ARMS`):** Everything else (`weapon_rifle`, `weapon_prism_bolt`, `weapon_prism_beam`, `weapon_prism_refract`, `weapon_stinger`, etc.).
* Upgrade `_acquire_combat_player(now_ms: int, incoming_priority: int, incoming_db: float) -> int` (returns voice index or `-1` if dropped):
  1. First return any voice where `not _combat_players[i].playing`.
  2. If all 16 voices are busy: scan all 16 slots for candidates where `_combat_priority[i] <= incoming_priority`.
  3. Among eligible candidates, pick the **lowest priority** first; break ties by **quietest `_combat_volume_db[i]`** (margin `3.0 dB`), then **oldest `_combat_start_ms[i]`**.
  4. If **no** active voice has priority `<= incoming_priority` (all 16 voices are higher-priority strategic/ability sounds): return `-1` so low-priority rifle fire drops cleanly instead of cutting off a major explosion!

### B.2 Proximity Cooldown Override & Routing Fixes

1. **Proximity-Aware Cooldown Override (`play_sfx`):**
   * Track `var _last_play_db: Dictionary = {}` alongside `_last_play_ms`.
   * Compute `var final_db: float = volume_db_offset + spatial_db + _slider_to_db(channel_linear)`.
   * When `(now_ms - prev_ms) < min_gap`:
     * Allow override if `not is_ui_sfx` AND `(now_ms - prev_ms) >= 25` AND `(final_db - float(_last_play_db.get(sfx_id, -80.0))) >= 4.0`.
     * *Result:* A quiet shot at the edge of the screen can never mute an identical weapon firing dead-center `30 ms` later!
   * Store `_last_play_ms[sfx_id] = now_ms` and `_last_play_db[sfx_id] = final_db`.

2. **Fast `UI_SFX_MAP`, Missing IDs & Slider Preview:**
   * Convert `UI_SFX_IDS` linear Array scan into a fast `const UI_SFX_MAP: Dictionary` and add **`&"ai_transmission": true`** (fixing radio transmissions stealing combat voices and obeying the SFX slider instead of UI!) and **`&"overclock_activate"`** (staying on Combat/Tactical Tier 3 so spatial world-position panning works cleanly!).
   * Ensure `&"deploy_anchor_lock"` has a clean fallback stream if not already generated by a profile (synthesized via `SynthPrimitives.synth_destruction_boom()` / tight low thump or mapped cleanly in `MonolithAudioProfile` so zero missing-stream drops occur).
   * Update `play_slider_preview(channel: StringName)`: add **`&"ambience"`** branch playing a gentle soft harmonic pad chime (`&"alert_complete"` at `-9.0 dB` or soft chord swell) so adjusting the Ambience slider in Settings gives immediate audible feedback even on the Main Menu.

3. **Data-Driven `classify_unit_bark_class()`:**
   * Update signature to `func classify_unit_bark_class(unit_type_id: StringName, unit_data: UnitData = null) -> StringName` (100% backward-compatible default `null`).
   * If `unit_data != null`:
     * If `unit_data.audio_bark_class != &""`: return `unit_data.audio_bark_class`.
     * If `unit_data.is_worker_class()`: return `&"worker"`.
     * If `unit_data.has_tag(&"support") or unit_data.heal_aura_rate > 0.0 or unit_data.tether_emit_radius > 0.0`: return `&"support"`.
     * If `unit_data.is_heavy_unit() or unit_data.has_tag(&"siege") or unit_data.has_tag(&"artillery")`: return `&"heavy"`.
     * If `unit_data.has_tag(&"anti_armor") or unit_data.has_tag(&"disruptor")`: return `&"counter"`.
     * Return `&"swarm"`.
   * Add all `PRISMA_DEI` unit IDs (`acolyte`, `prism_dredge`, `cantor`, `votary`, `lumen_skiff`, `lens_adjudicator`, `prism_weaver`, `solstice_lance`, `seraph_cruiser`) to the legacy ID `match` fallback as well, and pass `u.data` into `classify_unit_bark_class(u.get_unit_type_id(), u.data)` inside `resolve_selection_audio_class()` and `play_order_audio()`.

## Phase C — Click-Free Stereo DSP Primitives & De-Duplication (`scripts/systems/audio/`)

### C.1 Upgrade `SynthPrimitives` (`scripts/systems/audio/synth_primitives.gd`)

1. **Warm Soft-Saturation (`soft_clip`) & DC Removal (`remove_dc_offset`):**
   * Add `static func soft_clip(sample: float, drive: float = 1.0) -> float`: returns `tanh(sample * drive) / maxf(0.001, tanh(drive))` (smooth analog-style saturation preventing harsh digital flat-top clipping).
   * Add `static func remove_dc_offset(samples: PackedFloat32Array) -> void`: computes mean sample value and subtracts it across the buffer.
   * Update `make_wav(samples)` to pass samples through `soft_clip(samples[i], 1.15) * 0.95` before 16-bit PCM encoding.

2. **Zero-Click Seamless Loop & Stereo Widening Builders:**
   * `static func make_seamless_loop_wav(samples: PackedFloat32Array, crossfade_sec: float = 0.14) -> AudioStreamWAV`:
     * Removes DC offset first.
     * Takes the last `fade_len = clampi(int(SAMPLE_RATE * crossfade_sec), 64, samples.size() / 4)` samples and equal-power crossfades them smoothly into the first `fade_len` samples (`w_head = sin(u * PI * 0.5)`, `w_tail = cos(u * PI * 0.5)`), returning a slightly trimmed seamless buffer (`samples.size() - fade_len`) with `loop_mode = LOOP_FORWARD` and **guaranteed zero discontinuity at the wrap boundary**!
   * `static func make_stereo_loop_wav(left: PackedFloat32Array, right: PackedFloat32Array, crossfade_sec: float = 0.14) -> AudioStreamWAV`:
     * Applies identical equal-power loop-wrap crossfading + DC-offset removal to both `left` and `right`, interleaves 16-bit L/R PCM (`wav.stereo = true`), and sets `loop_begin = 0`, `loop_end = frame_count`.
   * `static func make_stereo_widened_loop_wav(mono_samples: PackedFloat32Array, delay_ms: float = 9.0, crossfade_sec: float = 0.14) -> AudioStreamWAV`:
     * Builds a rich, wide stereo ambient bed from any mono ambient synthesis buffer by creating `left` and `right` channels with a gentle circular Haas micro-delay (`~9 ms` on Right, subtle complementary `0.06 Hz` gentle phase breath, and slight stereo decorrelation) before calling `make_stereo_loop_wav(...)`!
   * Update legacy `make_loop_wav(samples)` to delegate directly to `make_seamless_loop_wav(samples, 0.12)` so **every** loop in the codebase automatically becomes click-free!

3. **Reusable Biquad Filter Primitives (Foundation for Factions #4–#5):**
   * Add `static func apply_biquad_lowpass(samples: PackedFloat32Array, cutoff_hz: float, q: float = 0.707) -> void` and `static func apply_biquad_bandpass(samples: PackedFloat32Array, center_hz: float, q: float = 1.4) -> void` (Audio EQ Cookbook biquad difference equations—in-place, zero allocations).

### C.2 Stereo Ambient Beds & Stream De-Duplication (`genesis_audio_profile.gd`, `monolith_audio_profile.gd`, `prisma_audio_profile.gd`, `audio_manager.gd`)

* Update all 3 faction audio profiles' `build_ambient_layers()` loops (`base`, `combat`, `uplink`) to finalize with `SynthPrimitives.make_stereo_widened_loop_wav(out, 9.0, 0.14)` (using slightly narrower `6.0 ms` on punchy combat pulse layers and lush `11.0 ms` on base/uplink pads).
* Remove the redundant `_streams[&"weapon_prism_beam"]` and `_streams[&"weapon_prism_refract"]` assignments in `AudioManager._generate_procedural_library()` (since `PrismaAudioProfile.build_weapon_and_ability_sfx()` already registers and owns them cleanly!).

## Phase D — Async Background Ambience Synthesis, Smooth Crossfades & Spectator Team 1 Profile (`scripts/systems/audio_manager.gd`)

### D.1 Spectator Mode Inherits Team 1's Faction Ambience (`_resolve_desired_ambience_profile`)

* Update `_resolve_desired_ambience_profile() -> StringName`:
  * If not inside tree or no `"match_manager"` node exists (Main Menu): return `DEFAULT_AUDIO_PROFILE`.
  * If `TeamManager != null and TeamManager.is_spectator_mode()`:
    * Resolve Team 1's team ID: `var active_teams: Array[int] = TeamManager.get_active_teams(); var t1_id: int = active_teams[0] if not active_teams.is_empty() else 0`.
    * Query `var fdata_t1: FactionData = TeamManager.get_team_faction_data(t1_id)`.
    * If `fdata_t1 != null and fdata_t1.audio_timbre_profile != &"" and _audio_profiles.has(fdata_t1.audio_timbre_profile)`: return `fdata_t1.audio_timbre_profile`!
    * Fallback: `DEFAULT_AUDIO_PROFILE`.
  * Otherwise (human match): return local human faction's `audio_timbre_profile` as before.

### D.2 Zero-Hitch `WorkerThreadPool` Ambient Stem Baking

* Add thread-safe async cache state on `AudioManager`:
  * `var _amb_mutex: Mutex = Mutex.new()`
  * `var _amb_pending_tasks: Dictionary = {}` (`profile_id: StringName -> int(task_id)`)
  * `var _amb_completed_packs: Dictionary = {}` (`profile_id: StringName -> Dictionary`)
* Add `func _request_ambience_profile_async(profile_id: StringName) -> void`:
  * Resolves `resolved_id = profile_id if _audio_profiles.has(profile_id) else DEFAULT_AUDIO_PROFILE`.
  * If `_amb_profile_cache.has(resolved_id)` or `_amb_pending_tasks.has(resolved_id)`: return immediately.
  * Captures `var profile: FactionAudioProfile = _audio_profiles[resolved_id]` and schedules a `WorkerThreadPool.add_task(...)` callable that computes `var pack: Dictionary = profile.build_ambient_layers()`, acquires `_amb_mutex`, stores `_amb_completed_packs[resolved_id] = pack`, and unlocks.
* In `_setup_ambience_players()`: create the 3 `AudioStreamPlayer` nodes (`bus = &"Ambience"`, `volume_db = -80.0`) with **zero synchronous 4.0s synthesis on `_ready()`**, and immediately kick off `_request_ambience_profile_async(DEFAULT_AUDIO_PROFILE)` so boot time drops noticeably!
* In `_process()`:
  * Drain `_amb_completed_packs` safely under `_amb_mutex`: for each finished `pid`, call `WorkerThreadPool.wait_for_task_completion(task_id)` cleanly, move the pack into `_amb_profile_cache[pid]`, erase from `_amb_pending_tasks`, and if `pid == _desired_amb_profile`: start/crossfade into it immediately!
* In `_exit_tree()`: cleanly wait on any in-flight `_amb_pending_tasks` so Godot shuts down with zero orphaned worker tasks.

### D.3 Smooth `0.65s` Profile Crossfade, Per-Frame Uplink Smoothing & Dynamic Ambience Filter

1. **Click-Free Profile Crossfade (`_amb_xfade_gain`):**
   * Add state:
     * `var _desired_amb_profile: StringName = DEFAULT_AUDIO_PROFILE`
     * `var _amb_xfade_gain: float = 0.0` *(starts at `0.0` and smoothly fades in over `0.35s` once the first async pack arrives!)*
     * `var _amb_pending_swap_profile: StringName = &""`
   * In `refresh_faction_ambience_profile()`:
     * Set `_desired_amb_profile = _resolve_desired_ambience_profile()`.
     * If `_desired_amb_profile == _active_amb_profile` and `_amb_base_player.playing`: return.
     * If not cached yet: call `_request_ambience_profile_async(_desired_amb_profile)` and keep current bed playing smoothly until ready.
     * Once cached: set `_amb_pending_swap_profile = _desired_amb_profile`.
   * In `_process()`:
     * If `_amb_pending_swap_profile != &""`:
       * Ramp `_amb_xfade_gain = move_toward(_amb_xfade_gain, 0.0, real_dt / 0.30)`.
       * When `_amb_xfade_gain <= 0.005`: swap `stream` on `_amb_base_player`, `_amb_combat_player`, `_amb_uplink_player` from `_amb_profile_cache[_amb_pending_swap_profile]`, call `.play()` on all 3, set `_active_amb_profile = _amb_pending_swap_profile`, and clear `_amb_pending_swap_profile = &""`.
     * Else if `_amb_base_player.playing`:
       * Ramp `_amb_xfade_gain = move_toward(_amb_xfade_gain, 1.0, real_dt / 0.35)`.
   * Apply `_amb_xfade_gain` smoothly inside `_update_ambience_mix()` (turning `linear_to_db(maxf(0.001, _amb_xfade_gain))` into a clean dB fade).

2. **Per-Frame `_uplink_tension` Smoothing & Dynamic `Ambience` Low-Pass Filter:**
   * Store `var _uplink_target: float = 0.0` during the `0.35s` uplink poll (instead of stepping `_uplink_tension` inside the `0.35s` poll!).
   * Every frame in `_process()`: smoothly interpolate `_uplink_tension = move_toward(_uplink_tension, _uplink_target, real_dt * 0.65)`.
   * Smoothly drive `_amb_lpf.cutoff_hz`:
     * Compute `var target_cutoff: float = 1450.0` when `is_paused or now_ms < _amb_duck_until_ms`, else `lerpf(3800.0, 9600.0, clampf(maxf(_combat_intensity, _uplink_tension * 0.85), 0.0, 1.0))`.
     * Smoothly approach `_amb_lpf.cutoff_hz = lerpf(_amb_lpf.cutoff_hz, target_cutoff, clampf(real_dt * 4.0, 0.0, 1.0))`.

## Phase E — Verification & Listening Checklist

1. **Zero Errors, Bus Rack & Clean Shutdown:**
   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, **0 `FactionAudit:` warnings**, and faster boot with background ambient synthesis.
   * Confirm all 7 buses (`Master`, `SFX`, `SFX_Near`, `SFX_Far`, `UI`, `Barks`, `Ambience`) initialize cleanly and shutting down mid-load leaves zero orphaned threads.

2. **`±75%` Stereo Panning & `SFX_Far` Distance Low-Pass:**
   * Wear headphones in `milestone_0_test.tscn` and trigger weapons / abilities on the **far left**, **center**, and **far right** of the camera viewport:
     * Confirm crisp left/right stereo localization capped smoothly at `±75%` width (never harsh 100% hard-pan).
     * Pan the camera away from an active skirmish toward the viewport rim: confirm distant gunfire smoothly drops onto `SFX_Far` with warm air-absorption low-pass filtering while center-screen combat stays bright and punchy.

3. **16-Voice Priority Stealing & Proximity Override:**
   * Run a **100+ unit battle** (`GENESIS_V2` vs. `MONOLITH_OS` vs. `PRISMA_DEI`) and fire `Solar Convergence`, `Seismic Slam`, and heavy deaths amidst mass rifle/prism-bolt fire:
     * Confirm Tier 4 impacts and Tier 3 shield shatters/abilities **never** get cut off by Tier 1 small-arms spam.
     * Confirm center-screen shots play cleanly even while peripheral squads are firing the same weapon type.

4. **Click-Free Stereo Loops, Async Crossfades & Spectator Team 1 Ambience:**
   * Listen across at least `12 seconds` (`3 full 4.0s cycles`) of each faction's ambient bed (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`) in quiet early-game and active combat:
     * Confirm **zero audible clicks or pops** at every `4.0s` loop wrap and lush stereo width.
   * Launch a match as `PRISMA_DEI` and as `MONOLITH_OS`: confirm **zero frame-hitch freeze** on match start and a silky `0.65s` ambient crossfade from menu ambience into the faction soundscape.
   * Launch **AI-vs-AI Spectator Mode** with **AI-01 (`Team 1`) set to `PRISMA_DEI`** (vs. `GENESIS_V2`), then again with **AI-01 set to `MONOLITH_OS`**: confirm Spectator Mode cleanly adopts Team 1's faction ambient profile!

5. **UI Routing, Slider Previews & `PRISMA_DEI` Bark Parity:**
   * Open Settings → drag **Master**, **SFX**, **UI**, and **Ambience** sliders: confirm every slider (including **Ambience**) provides clean audio preview feedback, and confirm `ai_transmission` radio chimes respect the **UI** volume slider rather than **SFX**.
   * Select and command every `PRISMA_DEI` unit class (`Acolyte`, `Votary`, `Cantor`, `Prism Weaver`, `Seraph Cruiser`): confirm every unit resolves its intended ethereal bell-harmonic bark class cleanly.