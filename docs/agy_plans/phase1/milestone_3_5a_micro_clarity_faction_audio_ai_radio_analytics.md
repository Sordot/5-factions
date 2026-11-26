# Milestone 3.5a — Ordered Focus-Fire Queue, Tactical `Alt` Glance, Hit Feedback, Faction Soundbeds, AI Transmissions & Analytics

**Prerequisite:** Milestones 3.1–3.4 verified and working cleanly.

**Goal:** Deliver seven cohesive tactical-clarity, audio-atmosphere, and analytics upgrades across core skirmish and Spectator gameplay:

1. **Ordered Focus-Fire Queue (`Shift + Right-Click` Kill List):** Paint a priority kill order across multiple hostile targets with numbered crimson crosshairs (`1`, `2`, `3`) rendered via `CommandQueueOverlay`.
2. **Tactical `Alt` Glance Overlay:** Holding `Alt` illuminates the viewport with diegetic macro telemetry (all friendly rally lines, `ResourceNode` saturation pills, active production/Overclock rings, and turret/siege range rings) and clears cleanly on release.
3. **Toggleable Diegetic Hit Feedback:** Lightweight, pooled/batched combat pips visualizing dual-layer armor and shield interactions (cyan shield-absorb ticks, muted gray armor-blunted pings, gold anti-armor hits), toggleable in **Settings → Gameplay**.
4. **Faction-Specific Adaptive Soundbeds:** Branch `AudioManager`'s 3-layer procedural ambient bed (Macro / Combat / Uplink tension) by the local player's `FactionData.audio_timbre_profile` (`&"technozen_bio"` vs. `&"monolith_industrial"`).
5. **AI Lord Terminal Transmissions:** Emit brief, in-character radio lines from `GENESIS_V2` and `MONOLITH_OS` AI commanders into `TacticalEventFeed` on real game-state milestones (toggleable in **Settings → Gameplay**).
6. **Post-Match Battle Heatmap & Macro Efficiency Grade:** Record engagement/casualty coordinates and macro efficiency metrics (`Supply-Blocked Time`, `Avg Resource Float`, `Resource Trade Ratio`, and letter grade) in `MatchManager`, with a toggleable **Battle Heatmap** overlay in `View Battlefield` and summary metrics in `MatchEndOverlay`.
7. **Live Spectator Comparison Bar:** Dock a crisp top-center head-to-head comparison bar in AI-vs-AI Spectator Mode showing each active team's live Biomass/Silica/Compute, Bandwidth, Army Value, and completed Upgrades side-by-side.

**Non-Negotiable Constraints:**
* **100% Procedural Pipeline:** All overlays, pips, heatmaps, and faction ambient soundbeds must use Godot 2D `_draw()`, `StyleBoxFlat`, and procedural synth synthesis—zero external image or audio assets.
* **Strict `1280×720` UI Discipline:** All new HUD elements (Spectator Comparison Bar, Heatmap toggle pill, `MatchEndOverlay` efficiency rows, `SettingsMenu` toggles) must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).
* **Zero Input Conflicts:** Holding `Alt` for the Tactical Glance Overlay must **never** consume `Alt + 1–9` Control Group Stealing or break `Alt` temporary Grid-Snap inversion during building placement.
* **No AI Map-Hacking & Hard Exclusions:** AI transmissions must only react to real AI state/vision; no stealth/cloaking mechanics; no role-sorted squad formations.

---

## Phase A — Ordered Focus-Fire Queue (`Shift + Right-Click` Kill List)

### A.1 Multi-Target Attack Queue Verification (`scripts/units/unit.gd`, `scripts/controllers/command_router.gd`)
1. Inspect `Unit.command_attack_target(target, shift_queued)` and `Unit._advance_command_queue()`:
   * Confirm that when `shift_queued == true` and the unit is already executing an `ATTACKING_TARGET` (or `MOVING` / `ATTACK_MOVING`) order, the new target is cleanly appended to `command_queue` as `{"type": &"attack_target", "target": target}` (skipping duplicate consecutive entries of the exact same target).
   * When the current target dies (or becomes invalid / hidden in Fog of War), immediately pop and engage the next valid `&"attack_target"` entry in `command_queue` without stalling or reverting to `IDLE` between kills.
   * If a queued target dies *before* the squad reaches it in the queue, skip it seamlessly on queue advance so the squad flows immediately to target `2` → `3`.
2. In `CommandRouter.issue_attack_target_order(selected_units, target, shift_queued)`:
   * Preserve existing `Shift` forwarding; when `shift_queued == true`, spawn a subtle crimson queued-target pulse via `MoveMarker` so chaining kills feels snappy.

### A.2 Numbered Crimson Target Crosshairs (`ui/overlays/command_queue_overlay.gd`)
* While any selected friendly unit has an active `ATTACKING_TARGET` plus 1+ queued `&"attack_target"` commands (or multiple queued `&"attack_target"` commands):
  * Deduplicate targets in execution order across the active selection into an ordered kill list `[T1, T2, T3, ...]`.
  * Connect `T1 → T2 → T3` with subtle dashed crimson sightlines (`Color(1.0, 0.30, 0.43, 0.55)`).
  * On each living visible target `Tk`, draw a crisp crimson corner-bracket crosshair ring and a high-contrast **`1`, `2`, `3`...** priority badge cleanly offset above-right of the target (`Color(0.06, 0.08, 0.12, 0.90)` pill + crimson border + crisp white digit).
  * Cap displayed numbers cleanly (e.g., up to `9`) and prune immediately on target death or new non-Shift order.

---

## Phase B — Tactical `Alt` Glance Overlay

### B.1 Non-Intrusive `Alt` State Query (`ui/overlays/tactical_glance_overlay.gd`)
Create a lightweight world-space `class_name TacticalGlanceOverlay extends Node2D` (`z_index = 62`, instanced dynamically by `SelectionController` or `MatchManager` on skirmish scenes):
* **Activation Rule (Zero Input Consumption):**
  * Never intercept `_input` or `_unhandled_input` (so `Alt + 1..9` group stealing and `Alt` grid-snap inversion remain 100% untouched).
  * Poll `var active: bool = Input.is_key_pressed(KEY_ALT)` in `_process(delta)` **only** when:
    * No modal overlay is open (`not sel._is_any_modal_open()`),
    * No build-placement ghost is active (`sel.active_targeting_ability == null` or not `BUILD_PLACEMENT`), and
    * Not in post-match summary modal.
  * Smoothly fade `_alpha` (`0.0 → 1.0` over `0.10s`, `1.0 → 0.0` over `0.12s`) so tapping/holding `Alt` feels crisp and intentional.
* **Diegetic Telemetry Rendered While `_alpha > 0.01`:**
  1. **All Friendly Production Rally Lines:** For every living, constructed friendly building belonging to the local human team (or all teams in Spectator Mode) with `has_rally()`, draw clean translucent dashed rally lines + endpoint flags.
  2. **All Visible `ResourceNode` Saturation Badges:** Force-draw `X/Y` color-coded saturation pills over every non-depleted, explored `ResourceNode` (and friendly hub aggregate cluster totals) currently inside the camera viewport, honoring `get_effective_max_harvesters(team)`.
  3. **Building Production, Staffing & Overclock Progress Rings:** On every friendly constructed structure:
     * Actively producing: crisp radial arc around the footprint showing live `%` progress (amber if Overclocked, faction accent otherwise).
     * Idle military production structure: subtle pulsing `"IDLE"` corner tag so unqueued factories jump out immediately.
     * Compute structures (`Wetware Mainframe` / `Logic Monolith`): crisp `staffed/max` pill (amber if `0/max`).
  4. **Friendly Static Defense & Deployed Siege Range Rings:** Subtle low-alpha (`0.22 * _alpha`) dashed firing-range rings around friendly `has_turret` buildings and `DEPLOYED` units (`Anvil Siege-Walker`).
* **Zero Idle Cost:** When `_alpha <= 0.001`, skip `queue_redraw()` completely.

---

## Phase C — Toggleable Diegetic Hit Feedback

### C.1 Settings Toggle (`scripts/systems/settings_manager.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd`)
* Add `@export` / persisted Gameplay setting: `var show_combat_hit_feedback: bool = true` (persisted under `[gameplay]` in `user://settings.cfg`).
* Add a compact **Combat Hit Feedback** checkbox in **Settings → Gameplay** (default `ON`, keeping all tabs unclipped at `1280×720`).

### C.2 Batched Lightweight Hit-Pip Overlay (`ui/overlays/hit_feedback_overlay.gd`)
Rather than instantiating a new `Node2D` per bullet impact (which could churn nodes in 4P FFA), create a **single batched world-space `HitFeedbackOverlay` (`Node2D`, `z_index = 64`, group `"hit_feedback_overlay"`)** holding a fixed ring-buffer of up to `96` lightweight struct Dictionaries:
* **API:** `push_hit_pip(world_pos: Vector2, kind: StringName, value: int = 0) -> void`
  * Skips immediately if `SettingsManager != null and not SettingsManager.show_combat_hit_feedback`.
  * **3 High-Readability Categories (No Damage-Number Clutter):**
    1. **`&"shield_absorb"` (Cyan `#38BDF8`):** Tiny crisp hexagonal/diamond shield-deflect glint + tiny `−` pip drifting upward `14 px` over `0.38s` when native or barrier shield absorbs damage.
    2. **`&"armor_blunted"` (Muted Steel/Slate `#94A3B8`):** Compact angled ricochet tick + subtle shield-chevron when hull `damage_reduction >= 0.25` significantly blunts a small rapid-fire hit (`raw_damage <= 24.0` and mitigated by `>= 25%`).
    3. **`&"anti_armor"` (Gold/Hazard Amber `#FFBE2E`):** Sharp 4-point armor-pierce diamond spark + brief `+ARM` / bold chevron when an attack with `bonus_vs_armored > 0` strikes an `is_armored` unit or structure.
  * **Per-Entity Throttling:** Rate-limit pips per target entity (`>= 140 ms` per kind via a tiny `entity_id -> last_ms` dict) so a swarm of 20 `Clone Troopers` doesn't stack overlapping icons on a single `Bulwark Automaton`.
* **Integration (`scripts/units/unit.gd`, `scripts/buildings/building.gd`, `scripts/units/combat_component.gd`):**
  * Only emit pips for visible targets (`is_friendly_view or target.visible`).
  * Trigger `&"shield_absorb"` when shields absorb damage, `&"armor_blunted"` when hull armor heavily reduces light chip damage, and `&"anti_armor"` when bonus vs. armored triggers.

---

## Phase D — Faction-Specific Adaptive Soundbeds (`scripts/systems/audio_manager.gd`)

Branch `AudioManager`'s existing 3-layer procedural ambient bed (**Macro / Combat / Uplink tension**) using `FactionData.audio_timbre_profile` while preserving exact calibrated `-14` to `-18 dB` headroom, dynamic combat ducking, and the Master `AudioEffectLimiter`:
1. **Profile Detection:**
   * Resolve active ambience profile on match start (and on `TeamManager.teams_reconfigured`):
     * Local human playing `GENESIS_V2` (or Spectator fallback) → `&"technozen_bio"`.
     * Local human playing `MONOLITH_OS` → `&"monolith_industrial"`.
2. **Two Distinct Procedural Soundbed Palettes:**
   * **`&"technozen_bio"` (`GENESIS_V2`):** Preserve the existing warm, airy, pulsing Y2K bio-synth drone pads, glassy harmonic shimmer on Macro, and rhythmic high-tech pulse on Combat/Uplink layers.
   * **`&"monolith_industrial"` (`MONOLITH_OS`):** Synthesize a distinct cold, architectural industrial 3-layer bed:
     * *Macro Layer:* Deep resonant sub-bass turbine hum (`~55 Hz` / `82 Hz` fifths) with slow metallic filter swells and subtle quantized clock ticks.
     * *Combat Layer:* Tight low-mid mechanical piston pulse + muted dark brass/anvil harmonic tension.
     * *Uplink Tension Layer:* Cold high-voltage transformer hum + deliberate radar-ping overtones.
3. **Clean Crossfade & Zero Reload Hitch:** Pre-generate/cache buffers lazily on first request per profile and switch cleanly when entering a skirmish or returning to Main Menu.

---

## Phase E — AI Lord Terminal Transmissions

### E.1 Settings Toggle & Transmission Tables (`scripts/systems/skirmish_ai.gd`, `scripts/systems/settings_manager.gd`)
* Add `var show_ai_transmissions: bool = true` to `SettingsManager` (persisted under `[gameplay]`, with a checkbox in **Settings → Gameplay**).
* Define concise, thematic, faction-specific transmission pools (1-line terminal dispatches, never spammy):
  * **`GENESIS_V2` (*The Vat-Born*):**
    * *Wave Launch:* `"// VAT-BORN: Bio-swarm vector locked. Overwhelming local resistance."`
    * *Barricade Breach:* `"// VAT-BORN: Structural obstruction dissolved. Flank corridor open."`
    * *Tier 2 Online (`Synthetics Fabricator`):* `"// VAT-BORN: Synthetics Fabricator online. Deploying heavy wetware frames."`
    * *Uplink Contest:* `"// VAT-BORN: Converging on Data Hyper-Uplink. Claiming neural priority."`
    * *Expansion Lost / Under Heavy Attack:* `"// VAT-BORN: Peripheral biomass node compromised. Redirecting swarm."`
  * **`MONOLITH_OS` (*The Iron Axiom*):**
    * *Wave Launch:* `"// AXIOM: Structural demolition column deployed. Proceeding at nominal cadence."`
    * *Barricade Breach:* `"// AXIOM: Corridor partition cleared. Advancing heavy armor."`
    * *Tier 2 Online (`Siege Gantry`):* `"// AXIOM: Siege Gantry operational. Initiating heavy ordnance assembly."`
    * *Uplink Contest:* `"// AXIOM: Securing Hyper-Uplink coordinates. Resistance is inefficient."`
    * *Expansion Lost / Under Heavy Attack:* `"// AXIOM: Outpost integrity breached. Recalculating defensive perimeter."`
* **Strict Anti-Spam & Fair-Vision Rules:**
  * Per-AI global transmission cooldown **`>= 45.0 seconds`** and per-category cooldown **`>= 90.0 seconds`**.
  * **Zero Fog-of-War Leaks:** Never jump the camera to an unseen enemy base from a transmission click—for hostile AI transmissions, either omit world-jump (`Vector2.INF`) or anchor the jump strictly to a **neutral objective** (like `(0, 0)` on Uplink Contest) or a **previously revealed/spotted position**.
  * Emit into `MatchManager.emit_tactical_event(&"transmission", text, safe_pos, team_color)` with a distinct subtle terminal-beep audio cue (`-8 dB` quiet telemetry chirp) and faction-colored pill border in `TacticalEventFeed`.

---

## Phase F — Post-Match Battle Heatmap & Macro Efficiency Grade

### F.1 Engagement Telemetry & Macro Efficiency Sampling (`scripts/systems/match_manager.gd`)
1. **Battle Heatmap Samples (`var combat_heatmap_events: Array[Dictionary] = []`):**
   * Record lightweight `{ "pos": Vector2, "weight": float, "team": int, "kind": StringName }` samples whenever:
     * Any unit dies (`weight = 1.0`, or `2.4` for `is_heavy_unit()`),
     * Any building is destroyed (`weight = 3.0`, or `4.5` for `is_command_hub()`),
     * Throttled skirmish damage ticks (max 1 sample per `1.5s` per `180 px` region when combat damage lands, `weight = 0.45`).
   * Cap array safely at `800` entries (merging nearby low-weight ticks if needed) so memory stays tiny.
2. **Macro Efficiency Metrics (Per Active Team):**
   * Sample every `1.0s` while match is active (excluding eliminated teams):
     * **`supply_blocked_seconds`:** Increment by `1.0` whenever `econ.get_bandwidth_used(tid) >= econ.get_bandwidth_cap(tid)` (and cap `< 200` / not at hard max).
     * **`resource_float_sum` & `resource_float_samples`:** Accumulate `(biomass + silica + compute)` to compute **`avg_unspent_float`**.
     * **`resources_lost_value` & `resources_destroyed_value`:** Accumulate total `(biomass_cost + silica_cost + compute_cost)` on unit deaths and building destructions to compute **`trade_efficiency_ratio`** (`destroyed / max(1, lost)`).
   * Compute a clean **Macro Grade (`S`, `A`, `B`, `C`, `D`)** per team blending low supply-block %, controlled resource float, and positive trade ratio.
   * Include `combat_heatmap_events` and per-team `supply_blocked_seconds`, `avg_unspent_float`, `trade_ratio`, and `macro_grade` inside the `stats` dictionary emitted to `MatchEndOverlay`.

### F.2 Post-Match UI & Toggleable World Heatmap (`ui/hud/match_end_overlay.gd`, `ui/overlays/battle_heatmap_overlay.gd`)
1. **`MatchEndOverlay` (`ui/hud/match_end_overlay.gd` / `.tscn`):**
   * Add a compact **Macro Efficiency** section (or 3 concise rows inside the existing Summary Table so height stays 100% unclipped at `1280×720`):
     * `Supply Blocked`: `00:18`
     * `Avg Float`: `410 Res`
     * `Trade Ratio / Grade`: `1.42x  [A]`
2. **Toggleable Battle Heatmap in `View Battlefield` (`ui/overlays/battle_heatmap_overlay.gd`):**
   * Create `class_name BattleHeatmapOverlay extends Node2D` (`z_index = 48`, `process_mode = Node.PROCESS_MODE_ALWAYS`, hidden during live play).
   * When the player clicks **"View Battlefield"** (`MatchManager.enter_post_match_inspection()`):
     * Display a compact floating button alongside the existing `"Return to Scoreboard"` pill: **`Heatmap: OFF / ON`** (`H` shortcut while inspecting).
     * When toggled **ON**, render `combat_heatmap_events` as layered, smooth additive-style radial heat blooms (cool cyan/amber low intensity → hot orange/crimson peak flashpoints) directly over the arena, plus small skull/diamond markers on Command Hub and heavy-unit death sites.
     * Cleanly hide/free on `exit_post_match_inspection()`, Rematch, or Return to Main Menu.

---

## Phase G — Live Spectator Comparison Bar (`ui/hud/spectator_comparison_bar.gd` & `.tscn`)

When `TeamManager.is_spectator_mode() == true`, provide broadcast-grade live head-to-head telemetry without overlapping `ResourceHUD`, `ProductionTicker`, or `TacticalMinimap` at `1280×720`:
* **Placement & `1280×720` Footprint:**
  * Dock cleanly at **top-center** (`offset_top = 48.0`, max width `<= 780 px`, compact height `<= 54 px` for 2P or `<= 64 px` for 3P/4P FFA), using `mouse_filter = MOUSE_FILTER_PASS` / `blocks_edge_pan` only on the panel itself.
  * Automatically hidden whenever `not TeamManager.is_spectator_mode()`.
* **2-Player Head-to-Head Layout (1v1 Spectator):**
  * Mirrored left (`Team 0`) vs. right (`Team 1`) telemetry wings with a central **Army Value Tug-of-War Bar** colored by each team's `TeamManager.get_team_color(tid)`.
  * Each wing displays:
    * Team Tag + Faction Short Code (`AI-01 // GEN-V2` vs `AI-02 // MONO-OS`)
    * Live `Biomass / Silica / Compute`
    * Live `Bandwidth` (`24/32`) & `Army Value` (`1,450`)
    * Compact completed-upgrade pips (e.g., `UPG: 2/3` with hover tooltip listing researched upgrade names)
    * Clicking a team wing smoothly centers `RTSCamera` on that team's primary Command Hub!
* **3–4 Player FFA / 2v2 Layout:**
  * Automatically switches to a sleek horizontal 3- or 4-column strip showing each active team's color bar, `Short Label + Faction`, `BW`, `Army Value`, total resources, and `UPG` count (dimming eliminated teams with `[ELIM]`)—guaranteed `<= 780 px` wide so it never clips at `1280×720`.
* **Refresh Cadence:** Update cleanly on a `0.35s` timer (zero per-frame allocations).

---

## Phase H — Verification & Playtest Checklist

1. **Ordered Focus-Fire Queue:**
   * Select a squad of `Rail-Sentinel`s or `Clone Trooper`s, right-click Enemy 1, then `Shift + Right-Click` Enemy 2 and Enemy 3.
   * Confirm numbered crimson crosshairs (`1`, `2`, `3`) and dashed sightlines appear via `CommandQueueOverlay`, and confirm the squad transitions immediately to Target `2` then `3` as each dies (skipping gracefully if Target `2` dies early).
2. **Tactical `Alt` Glance Overlay:**
   * Hold `Alt` in a live skirmish: verify all friendly rally lines, visible resource saturation pills, active production/Overclock rings, and turret/siege range rings fade in smoothly and disappear on release.
   * Verify `Alt + 1..9` Control Group Stealing and holding `Alt` during building placement (Grid-Snap invert) still work identically with zero regressions.
3. **Diegetic Hit Feedback:**
   * Pit `Clone Troopers` + `Lance-Rigs` against `Bulwark Automatons` in `milestone_0_test.tscn`: verify cyan shield-absorb ticks, muted gray armor-blunted pings on light fire vs. high-armor hulls, and gold anti-armor pips on `Lance-Rig` hits.
   * Toggle **Combat Hit Feedback** OFF in **Settings → Gameplay** and verify pips cease immediately.
4. **Faction Adaptive Soundbeds & AI Transmissions:**
   * Start a match as `GENESIS_V2`, then as `MONOLITH_OS`: verify the 3-layer ambient soundbed audibly shifts between organic Technozen synth pads and cold industrial sub-bass/metallic resonance at `-14` to `-18 dB` headroom.
   * Play or spectate a 3-minute skirmish and verify AI commanders emit occasional, non-spammy in-character radio lines into `TacticalEventFeed` without leaking Fog-of-War locations.
5. **Post-Match Heatmap, Macro Efficiency & Spectator Bar (`1280×720`):**
   * Finish a match (or fast-forward a 2P/4P AI Spectator match at `2x` speed):
     * Verify the **Live Spectator Comparison Bar** docks cleanly at top-center in both 2P and 4P modes with zero clipping at `1280×720` Windowed & Fullscreen (`F11`), and clicking a team wing jumps the camera to their base.
     * On `MatchEndOverlay`, verify `Supply Blocked`, `Avg Float`, `Trade Ratio`, and `Macro Grade` populate cleanly without overflowing `1280×720`.
     * Click **View Battlefield** → toggle **`Heatmap: ON`**: verify engagement/casualty hotspots render smoothly across the arena and clear cleanly on Rematch / Main Menu.