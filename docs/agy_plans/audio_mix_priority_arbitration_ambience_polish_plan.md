# Milestone 2.4.2 Plan: Audio Mix, Priority Arbitration & Ambience Polish Pass

**Target Directory:** `docs/agy_plans/27_audio_mix_priority_and_polish_pass.md`
**Primary Files:** `scripts/systems/audio_manager.gd`, `scripts/systems/settings_manager.gd`, `scripts/ui/settings_menu.gd`, `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`, `scripts/units/combat_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/buildings/building.gd`, `scripts/camera/rts_camera.gd`
**Reference Docs:** `docs/agy_plans/engine_hardening_salvage_auto_cast_los_audio_polish.md`, `docs/agy_plans/keybinds_mouse_buttons_settings_polish_plan.md`, `docs/agy_plans/micro_feel_unit_rally_minimap_pings_veterancy_plan.md`

## 1. Objective & Scope

Polish the game's audio architecture so selection feedback, orders, combat, alerts, and ambient soundscapes sit together in a clean, fatigue-free Technozen mix. Specifically, this pass eliminates **simultaneous overlapping selection/order sounds**, brings the **ambience baseline volume** down to a comfortable background level, and adds **spatial camera-distance attenuation**, **real-time throttling under `2x` game speed**, **bus headroom protection**, and **live Settings slider previews**.

### In Scope

1. **Single-Winner Selection & Order Audio Arbitration (`AudioManager`, `SelectionController`, `CommandRouter`):**
   * Fix the bug where selecting mixed units/buildings—or clicking a unit/building that triggers both a generic UI select click and a unit/building synth bark—plays multiple sounds on top of each other.
   * Introduce a **dedicated single-voice Bark/Acknowledge Channel** (`_bark_player`) and a deterministic **Priority Resolver** so every selection change or order batch plays **one** authoritative, crisp audio cue (cleanly interrupting any previous bark with a micro-fade instead of layering dissonant chords).

2. **Ambience Baseline Gain Staging & Dynamic Ducking (`AudioManager`, `SettingsManager`):**
   * Drastically reduce the internal baseline gain ceiling of the procedural ambience layers (`Base Macro`, `Combat Intensity`, `Hyper-Uplink Tension`) by **`-14 dB` to `-18 dB`** so `100%` Ambience sits comfortably below combat/UI SFX, and calibrate the default `ambience_volume` in `SettingsManager` to **`0.35`** with a smooth perceptual dB curve.
   * Add gentle **automatic ambience ducking** (`-5 dB`, `0.2s` attack / `1.2s` release) when high-priority tactical alerts, victory/defeat stingers, or `PauseMenu` are active.

3. **Camera-Distance Attenuation & Off-Screen Combat Culling (`AudioManager`, `CombatComponent`, `TurretComponent`, `Building`):**
   * Allow world-space combat, turret, ability, and explosion SFX to pass an optional `world_pos: Vector2`.
   * Smoothly attenuate SFX based on distance from the active `RTSCamera` viewport center and cull routine off-screen weapon fire beyond `~1.35×` viewport radius (while keeping tactical alerts and player-owned major explosions audible) so off-screen skirmishes and `AI vs AI (Spectator)` matches never muddy the mix.

4. **Headroom Protection, Polyphony Cap & Unscaled Cooldowns (`AudioManager`):**
   * Route audio through a clean runtime bus/gain structure (or attach a lightweight `AudioEffectLimiter` on the `Master` bus if not already present) to guarantee zero digital clipping during 40v40 battles or Combat Lab stress tests.
   * Cap simultaneous combat SFX voices (e.g., `8–10` voices with oldest-voice stealing) and migrate all SFX/bark throttle timers to **real-time (`Time.get_ticks_msec()`)** so running matches at `1.5x` or `2x` game speed never causes rapid-fire audio spam.

5. **Live Volume Preview in `SettingsMenu` (`scripts/ui/settings_menu.gd`):**
   * Play a throttled (`0.25s`) preview chime when adjusting **Master**, **SFX**, or **UI** volume sliders in **Settings → Audio**, and reflect **Ambience** slider adjustments immediately in real time.

### Out of Scope
* Importing external `.ogg`/`.wav` music tracks or voice-over recordings (keep the lightweight procedural Technozen audio synthesis).
* Faction #2 audio palettes (this pass establishes the clean priority and mix architecture that Faction #2 barks will plug into).

---

## 2. Detailed Technical Specifications

### 2.1 Selection & Order Audio Priority Arbitrator (`scripts/systems/audio_manager.gd`, `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`)

* **Root Cause to Fix:** Currently, selecting units or buildings can fire a generic `play_ui_select()` / building chime *and* `play_unit_bark()` (or multiple barks across a selection/order loop) on the same frame.
* **Single-Voice Bark Channel (`AudioManager`):**
  * Dedicate a single `AudioStreamPlayer` (`_bark_player`) specifically for selection and order acknowledgments.
  * When a new bark/selection cue triggers, stop/replace any currently playing bark on `_bark_player` cleanly (zero simultaneous double-barks).
  * Enforce a short real-time debounce (`0.12s` for explicit clicks, `0.45s` for rapid repeated order spam) using `Time.get_ticks_msec()`.
* **Selection Priority Hierarchy (`resolve_selection_audio_class(entities: Array)`):**
  * When `SelectionController` finalizes any selection (single click, drag-box, `Ctrl+Click`, control group recall, `Tab` subgroup cycle, Idle Worker cycle, or Select All Army), emit **one** audio call after the final selection array is settled—**never** inside a per-entity loop and **never** paired with a redundant generic `ui_select` sound.
  * Priority order when multiple entity types are selected:
    1. **Active Subgroup Leader** (if `Tab`-cycling subgroups, always play the newly focused subgroup's class bark).
    2. Otherwise, highest-priority unit class present in the selection:
       * `heavy` (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`)
       * `counter` (`Lance-Rig`, `Signal Jammer`)
       * `support` (`Symbiote`)
       * `swarm` (`Clone Trooper`, `Stinger`)
       * `worker` (`Engineer`, `Silica Harvester`, `Worker`)
    3. **Buildings** (only when no friendly units are selected): prioritize `production` (`Cloning Vat`, `Synthetics Fabricator`, `Calibration Foundry`) > `hub` (`Nexus Vat`) > `tech` (`Wetware Mainframe`) > `defense` (`Sentry Pylon`) > `utility` (`Synapse Pylon`, `Silica Condenser`), playing a single distinct building-select synth hum/chime.
    4. **Neutral / Enemy Inspection** (e.g., `ResourceNode`, `DestructibleBarricade`, `SalvageCore`, enemy unit): play a single soft, subtle telemetry inspection tick (`-6 dB` quieter than friendly barks).
* **Order Confirmation Priority (`CommandRouter`):**
  * When issuing an order to a mixed group (Move, Attack-Move, Patrol, Repair, Salvage, Gather, Build), resolve **one** winning unit class from the units that actually accepted the order and trigger a single `play_unit_bark(winner_class, &"order")` call (never firing both a generic `order_confirm` ping and a unit bark on the exact same frame—or if a micro-click is desired, keep the click `-10 dB` subtle and staggered by `0.03s` so the two transients never clash).

### 2.2 Ambience Volume Calibration & Dynamic Ducking (`scripts/systems/audio_manager.gd`, `scripts/systems/settings_manager.gd`)

* **Perceptual Volume Curve (`AudioManager`):**
  * Convert all linear `[0.0..1.0]` volume sliders using a smooth perceptual curve (e.g., `linear_to_db(pow(clampf(vol, 0.0, 1.0), 1.6))`, muting cleanly below `0.005`) so lowering a slider to `30%–50%` produces an intuitive, comfortable volume drop instead of staying loud until `10%`.
* **Lower Ambience Baseline Ceiling:**
  * Apply a dedicated baseline attenuation offset on all procedural ambience layers inside `AudioManager`:
    * `Base Macro Pad`: **`-16 dB`** baseline offset (subtle atmospheric bed—present, never intrusive).
    * `Combat Intensity Layer`: **`-14 dB`** ceiling when fully ramped during active combat.
    * `Hyper-Uplink Tension Layer`: **`-15 dB`** ceiling when Uplink is contested.
  * Lower the default `ambience_volume` in `SettingsManager` from `0.55` to **`0.35`** (updating `reset_defaults()` as well; existing saved `user://settings.cfg` values remain respected, while still benefiting immediately from the `-16 dB` internal ceiling fix).
* **Dynamic Ambience Ducking:**
  * Track a smoothed `_ambience_duck_db: float` (`0.0` normal, `-5.0 dB` during `PauseMenu` or for `1.8s` after a tactical alert / victory stinger, smoothly interpolating back at `~4 dB/s`).

### 2.3 Camera-Distance Spatial Attenuation (`scripts/systems/audio_manager.gd`, `scripts/units/combat_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/buildings/building.gd`)

* Add an optional `world_pos: Vector2 = Vector2.INF` parameter to world combat/VFX audio helpers (`play_weapon_sfx`, `play_explosion_sfx`, `play_ability_sfx`, `play_build_sfx`)—keeping existing calls 100% backward-compatible.
* When `world_pos != Vector2.INF` and an active `Camera2D` (`RTSCamera`) exists:
  * Compute normalized distance from the camera's visible center relative to the viewport half-diagonal (`view_radius`).
  * Inside `0.85 * view_radius`: full mix gain (`0.0 dB`).
  * Between `0.85 * view_radius` and `1.55 * view_radius`: smooth rolloff down to `-16 dB`.
  * Beyond `1.55 * view_radius`: cull routine weapon tracers/impacts completely (returning early without consuming a voice), while allowing major global events (tactical alerts, `Nexus Vat` destruction, upgrade completion) to always play cleanly.
* Pass `owner_unit.global_position` / `building.global_position` from `CombatComponent`, `TurretComponent`, `AbilityComponent`, `SalvageCore`, and `DestructibleBarricade`.

### 2.4 Mix Headroom, Polyphony & Real-Time Throttling (`scripts/systems/audio_manager.gd`)

* **Unscaled Real-Time Throttling:**
  * Replace any `delta`-accumulated or scaled cooldown checks in `AudioManager` with `Time.get_ticks_msec()` so `1.5x` and `2x` game speed never double the firing rate of weapon/impact SFX or cause harsh buzzing.
* **Polyphony Cap & Limiter:**
  * Cap the pooled combat SFX players to `10` active voices (stealing the oldest/quietest voice if saturated).
  * On `AudioManager._ready()`, ensure an `AudioEffectLimiter` (`ceiling_db = -1.0`, `threshold_db = -3.0`) is present on the `Master` bus via `AudioServer` (checking first so it is never added twice), guaranteeing clean headroom during massive battles.

### 2.5 Live Volume Preview in `SettingsMenu` (`scripts/ui/settings_menu.gd`)

* When the player adjusts **Master Volume**, **SFX Volume**, or **UI Volume** sliders in **Settings → Audio**, trigger a lightweight throttled (`0.22s`) preview sound (e.g., a crisp UI pip for UI/Master, a soft pulse-rifle/chime preview for SFX) so they can hear the exact level live.
* Ensure **Ambience Volume** updates the playing ambient bed immediately on `value_changed` without waiting for menu close.

---

## 3. File & Architecture Summary

### Existing Files to Extend
* `scripts/systems/audio_manager.gd`: Single-voice `_bark_player` channel, `resolve_selection_audio_class()`, perceptual dB curve, `-14 dB` to `-18 dB` ambience baseline attenuation, dynamic alert/pause ducking, camera-distance attenuation & off-screen culling, `Time.get_ticks_msec()` real-time throttling, 10-voice combat pool cap, and Master bus `AudioEffectLimiter`.
* `scripts/systems/settings_manager.gd`: Calibrate default `ambience_volume = 0.35` (including `reset_defaults()`).
* `scripts/ui/settings_menu.gd`: Add throttled live audio preview pings when dragging audio sliders.
* `scripts/controllers/selection_controller.gd`: Route all selection changes (click, drag-box, `Tab` subgroup cycle, control group recall, Idle Worker, Select All Army) through a single prioritized selection audio call—removing duplicate simultaneous UI-click + bark calls.
* `scripts/controllers/command_router.gd`: Emit a single prioritized order bark per command batch rather than stacking multiple sound cues.
* `scripts/units/combat_component.gd`, `scripts/units/ability_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/buildings/building.gd`, `scripts/world/destructible_barricade.gd`, `scripts/world/salvage_core.gd`: Pass `global_position` into `AudioManager` world SFX calls for clean camera-distance attenuation.

---

## 4. Verification Checklist for `agy`

Before concluding Milestone 2.4.2, verify in Godot (`MainMenu`, `skirmish_arena_01.tscn`, and `skirmish_arena_02.tscn`):

* [ ] **Zero Simultaneous Selection Overlap:** Drag-select a mixed group of **Goliath Frames**, **Clone Troopers**, and **Workers**—confirm **only one** authoritative bark (`heavy`) plays cleanly with zero simultaneous double-sound clash. Click a **Cloning Vat**, then a **Nexus Vat**, then cycle subgroups with `Tab`; confirm each action plays a single crisp sound and cleanly replaces any prior bark.
* [ ] **Single Clean Order Audio:** Issue Move, Attack-Move, Gather, and Repair orders to mixed squads; confirm only one prioritized order acknowledgment plays per command.
* [ ] **Comfortable Ambience Baseline:** Launch `MainMenu` and `skirmish_arena_01.tscn` with default settings (and test `Reset Defaults` in Settings); confirm the ambient synth bed sits softly in the background well below UI clicks, barks, and combat SFX, and ducks gently during `PauseMenu` and tactical alerts.
* [ ] **Spatial Attenuation & `2x` Speed Hygiene:** Run an **AI vs AI (Spectator)** match or Combat Lab 40-unit clash at `1x` and `2x` speed; pan the camera away from the fight and confirm off-screen weapon fire smoothly fades out, then pan back over the fight and confirm zero clipping or speed-induced audio spam.
* [ ] **Live Settings Previews & Debugger Hygiene:** Drag **Master**, **SFX**, **UI**, and **Ambience** sliders in **Settings → Audio**; confirm live audio feedback works smoothly, Mute-When-Unfocused still behaves properly, and zero Godot Debugger errors occur.