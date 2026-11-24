# Milestone 2.3 Plan: Engine Hardening, Salvage Cores, Auto-Cast, LOS Shadowing & Adaptive Audio

**Target Directory:** `docs/agy_plans/24_hardening_salvage_los_and_audio_polish.md`
**Primary New Files:** `scripts/units/movement_component.gd`, `scripts/units/status_effect_component.gd`, `scripts/systems/spatial_grid.gd`, `scripts/data/faction_data.gd`, `resources/factions/genesis_v2_faction.tres`, `scripts/world/salvage_core.gd`, `scenes/world/salvage_core.tscn`
**Primary Extended Files:** `project.godot`, `scripts/units/unit.gd`, `scripts/units/combat_component.gd`, `scripts/units/ability_component.gd`, `scripts/units/heal_aura_component.gd`, `scripts/units/repair_component.gd`, `scripts/data/unit_data.gd`, `scripts/data/ability_data.gd`, `scripts/systems/team_manager.gd`, `scripts/systems/fog_of_war.gd`, `scripts/systems/audio_manager.gd`, `scripts/systems/settings_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/ui/main_menu.gd`, `scripts/ui/tech_tree_overlay.gd`, `scripts/ui/settings_menu.gd`, `scripts/controllers/command_router.gd`, `scripts/controllers/selection_controller.gd`, `ui/hud/selection_hud.gd`, `ui/hud/minimap.gd`, `ui/overlays/entity_visuals.gd`, `ui/overlays/combat_vfx.gd`
**Reference Docs:** `docs/agy_plans/engine_depth_multi_team_map_2_tools_bundle.md`, `docs/agy_plans/micro_feel_unit_rally_minimap_pings_veterancy_plan.md`, `docs/agy_plans/worker_rvo_and_multi_worker_task_fix.md`

---

## 1. Codebase Audit & Sequencing Strategy

Following Milestone 2.2, several core scripts have grown significantly (`unit.gd` is now **91.8 KB**, `selection_hud.gd` is **54.2 KB**, `selection_controller.gd` is **52.5 KB**, and `skirmish_ai.gd` is **45.5 KB**). Before adding Faction #2—or layering Salvage Cores, Auto-Cast, and LOS onto the simulation—we need to harden the foundation in a strict dependency order:

1. **Phase A (Engine Hardening First):** Extract `MovementComponent` and `StatusEffectComponent` from `unit.gd`, introduce the `SpatialGrid` broadphase accelerator, and formalize `FactionData` `.tres` manifests so every subsequent feature plugs into clean, modular APIs instead of bloating `unit.gd` past 100 KB.
2. **Phase B (Heavy Wreckage & Data Salvage):** Drop interactive `SalvageCore` pickups from high-tier units (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`) driven by `UnitData` exports.
3. **Phase C (Auto-Cast & True LOS Fog of War):** Add right-click Auto-Cast toggles on eligible abilities/repair and upgrade `FogOfWar` with obstacle-occluded Line-of-Sight shadowing.
4. **Phase D (Adaptive Procedural Ambience & Unit Synth Barks):** Give the Technozen world reactive ambient audio and distinct unit-class procedural synth acknowledgments.

---

## 2. Phase A: Engine Hardening (Pre-Faction #2 Foundation)

### A.1 Decompose `unit.gd` into Modular Components

Preserve 100% of existing behavior—especially the **Milestone 1.6.3 worker RVO-disabled transit, multi-worker approach slot spreading, and Milestone 2.1 stutter-step kiting**—while delegating responsibilities out of `unit.gd`:

* **`scripts/units/movement_component.gd` (`MovementComponent`):**
  * Encapsulates `NavigationAgent2D` target requests (`request_nav_toward_point`, `stop_navigation`), worker RVO-avoidance toggling (`update_worker_collision_passing`), anti-stuck detour steering, overlap separation (powered by `SpatialGrid`), and `find_clear_approach_point()` slot spreading.
  * Exposes clean methods for `Unit`, `GatherComponent`, `RepairComponent`, and `StaffComponent` so `unit.gd` acts as a crisp state coordinator rather than a 2,000+ line physics script.
* **`scripts/units/status_effect_component.gd` (`StatusEffectComponent`):**
  * Centralizes all temporary buffs, debuffs, and future faction mechanics (`Adrenal Surge`, `Static Pulse` slow/disruption, `Compute Overdrive`, plus extensible slots for future Faction #2–#5 shields, DoTs, or stealth/cloak).
  * Exposes unified stat multipliers (`get_move_speed_multiplier()`, `get_attack_speed_multiplier()`, `get_damage_taken_multiplier()`) and active effect lists for `EntityVisuals` status pips and `SelectionHUD` tooltips.

### A.2 2D Spatial Hash Grid (`scripts/systems/spatial_grid.gd`)

Register `SpatialGrid` as an autoload (or match-scoped singleton managed by `MatchManager`) with **`128.0` px cell size**:

* **Dynamic Tracking:** Units register on `_ready()`, update their cell bucket only when crossing a `128px` boundary during movement, and unregister on `_exit_tree()` / death. Buildings, `ResourceNode`s, `DestructibleBarricade`s, and `SalvageCore`s register once on spawn and unregister on destruction.
* **Fast Query API:**
  * `query_units_in_radius(center: Vector2, radius: float, filter_team: int = -99) -> Array[Unit]`
  * `query_entities_in_radius(center: Vector2, radius: float, include_buildings: bool = true, include_barricades: bool = false) -> Array[Node2D]`
  * `query_salvage_in_radius(center: Vector2, radius: float) -> Array[Node2D]`
* **High-Impact Call Sites to Migrate:**
  * `MovementComponent` overlap separation (biggest CPU win in large swarms).
  * `CombatComponent` threat-priority target scans and AoE splash queries (`Chrysalis Mortar`, `Arc-Lancer`).
  * `HealAuraComponent` (`Symbiote` nearby ally scan).
  * `AbilityComponent` AoE spells (`Seismic Slam`, `Static Pulse`, `Spore Barrage`).
  * `RepairComponent` auto-repair nearby target scans.

### A.3 Faction Data Registry (`scripts/data/faction_data.gd` & `resources/factions/genesis_v2_faction.tres`)

Create a clean, Inspector-editable `FactionData extends Resource` manifest so Faction #2 drops in with zero hardcoded scene paths:

* **Exported Fields on `FactionData`:**
  * `faction_id: StringName` (`&"genesis_v2"`)
  * `display_name: String` (`"GENESIS_V2 — The Vat-Born"`)
  * `tagline: String`
  * `is_playable: bool = true`
  * `starting_hub_scene: PackedScene` (`nexus_vat.tscn`)
  * `worker_scene: PackedScene` (`worker_unit.tscn`)
  * `harvester_scene: PackedScene` (`silica_harvester.tscn`)
  * `engineer_scene: PackedScene` (`engineer_unit.tscn`)
  * `building_roster: Array[BuildingData]` & `unit_roster: Array[UnitData]` & `upgrade_roster: Array[UpgradeData]`
  * `ai_build_profile: Dictionary` (maps logical AI roles like `&"hub"`, `&"supply"`, `&"barracks_t1"`, `&"counter_foundry"`, `&"heavy_t2"`, `&"refinery"`, `&"compute_hub"` to the faction's `BuildingData` / scene paths).
* **Registry Integration:**
  * `TeamManager` loads available `FactionData` resources on startup and exposes `get_faction_data(faction_id: StringName) -> FactionData`.
  * Refactor `TechTreeOverlay`, `MainMenu` faction dossier display, and `SkirmishAICommander` building/unit lookups to read dynamically from `TeamManager.get_faction_data(...)` instead of hardcoded `res://scenes/buildings/...` strings.

---

## 3. Phase B: Heavy Wreckage & Data Salvage (`SalvageCore`)

### B.1 Data-Driven Drop Configuration (`scripts/data/unit_data.gd`)

* Add `@export var salvage_silica: int = 0` and `@export var salvage_compute: int = 0` to `UnitData`.
* Configure high-tier `GENESIS_V2` units (`.tres` files):
  * `goliath_frame_data.tres`: `salvage_silica = 45`, `salvage_compute = 15`
  * `arc_lancer_data.tres`: `salvage_silica = 40`, `salvage_compute = 25`
  * `chrysalis_mortar_data.tres`: `salvage_silica = 35`, `salvage_compute = 20`

### B.2 `SalvageCore` World Entity (`scripts/world/salvage_core.gd` & `scenes/world/salvage_core.tscn`)

* **Spawn & Decay:** When a unit with `salvage_silica > 0 or salvage_compute > 0` dies, spawn a `SalvageCore` at its death position with a **`28.0s` lifetime** (progressively flickering/dimming during the final `6.0s` before dissolving cleanly).
* **Visuals & Minimap:**
  * Procedural Technozen `_draw()` rendering a fractured glowing hexagonal core with a subtle radial decay arc and floating resource hint on hover/selection.
  * Renders as a small pulsing amber/cyan diamond on `Minimap` (visible when within explored/active LOS).
  * Inspectable in `SelectionHUD` showing remaining decay timer and Silica/Compute payload.
* **Extraction Mechanics (`CommandRouter`, `GatherComponent` / `RepairComponent`):**
  * **Any team's** `Worker` or `Engineer` can right-click (or `Shift`-queue) a `SalvageCore` to extract it.
  * Extraction takes **`2.5s`** (`1.8s` for `Engineer`, or faster with multiple workers channeling simultaneously) with a crisp cyan/amber extraction tether beam via `combat_vfx.gd`.
  * Upon completion, immediately credits `EconomyManager` with the Silica + Compute burst, triggers a floating `+45 S / +15 C` pop-up feedback cue and crisp audio chime, frees the `SalvageCore`, and advances the worker's `command_queue`.
  * `SkirmishAI` optionally dispatches a nearby idle worker/engineer to claim uncontested `SalvageCore`s within safe range of its base.

---

## 4. Phase C: Ability Auto-Cast Toggles & True Line-of-Sight (LOS) Shadowing

### C.1 Ability Auto-Cast Toggles (`ability_data.gd`, `ability_component.gd`, `repair_component.gd`, `selection_hud.gd`)

* **Data & Component Support:**
  * Add `@export var allow_autocast: bool = false` and `@export var default_autocast: bool = false` to `AbilityData`.
  * Enable `allow_autocast = true` on `adrenal_surge.tres` (and future self-buff/utility abilities) plus expose an **Auto-Repair** toggle on `Worker` (`worker_unit`) and `Engineer` (`engineer_unit`) command cards (`default_autocast = true` optional or `false` by default for player control—default `false` so workers don't abandon manual holds unexpectedly, or `true` only while `IDLE`).
  * In `AbilityComponent`: maintain `autocast_enabled: Dictionary` (`ability_id -> bool`). On a lightweight `0.35s` tick, if an ability has `autocast_enabled == true`, is off cooldown, and meets its trigger condition (e.g., for `Adrenal Surge`: unit is actively in combat with a valid target in range), cast it automatically.
  * In `RepairComponent`: when `auto_repair_enabled == true` and the Worker/Engineer is `IDLE`, query `SpatialGrid` within `220px` for the most damaged eligible friendly building (or synthetic unit for Engineers) and begin repairing automatically.
* **Command Card UI (`ui/hud/selection_hud.gd`):**
  * Right-clicking an auto-castable ability button on `SelectionHUD` toggles auto-cast across all selected units in the active subgroup (with a crisp toggle SFX).
  * Render an animated corner-chasing cyan/gold Technozen border around active auto-cast buttons and append `[Right-Click: Auto-Cast ON/OFF]` to `CommandTooltip`.

### C.2 True Line-of-Sight (LOS) Shadowing (`scripts/systems/fog_of_war.gd`)

Upgrade `FogOfWar` so solid `TerrainObstacle` monoliths, blocking `MapLandmark` pillars (`has_collision == true`), and intact `DestructibleBarricade`s cast realistic visibility shadows:

* **Opaque Grid Cache (`_blocker_grid: PackedByteArray`):**
  * Build a fast byte-grid matching `FogOfWar`'s existing tile resolution marking which fog cells overlap `TerrainObstacle`, blocking `MapLandmark`, or intact `DestructibleBarricade` footprints.
  * Expose `rebuild_blocker_grid()` and call it on map start and whenever a `DestructibleBarricade` is destroyed so breaching a gate immediately lets vision spill through the opening!
* **Fast Per-Cell LOS Check:**
  * When stamping a vision circle for a unit/building onto the fog grid, run a lightweight integer Bresenham / DDA grid-ray check from the observer's cell to candidate cells within `vision_radius`.
  * If the ray hits an opaque blocker cell *before* reaching the target cell, leave the target cell shrouded (while still revealing the blocker cell itself so walls/barricades remain visible when approached).
  * **Performance Guard:** Cache static building vision stamps (only recomputing when buildings are built/destroyed or a barricade breaks) and throttle dynamic unit LOS updates to `FogOfWar`'s existing update cadence (`~0.12s–0.15s`) so frame rate stays locked at 60+ FPS even on `skirmish_arena_02`.
  * Keep **Spectator Mode** full-map reveal toggle working seamlessly above the LOS layer.

---

## 5. Phase D: Adaptive Procedural Ambience & Unit-Class Synth Barks

### D.1 Adaptive Procedural Ambience (`scripts/systems/audio_manager.gd`, `settings_manager.gd`, `settings_menu.gd`)

* **Procedural Technozen Soundscape (`AudioManager`):**
  * Synthesize a lightweight, seamless ambient soundbed (using `AudioStreamGenerator` or pre-baked looping `AudioStreamWAV` buffers generated at startup to keep CPU cost near zero) with 3 blendable intensity layers:
    1. **Base Macro Layer:** Warm, subtle Y2K/Technozen low-pass synth pad + soft crystalline pulse.
    2. **Combat Intensity Layer:** Subtle rhythmic sub-bass pulse and filtered arpeggio that smoothly fades in (`attack 1.5s`, `decay 5.0s`) when `MatchManager` reports active combat or `under_attack` alerts.
    3. **Hyper-Uplink Tension Layer:** Subtle harmonic shimmer when the **Data Hyper-Uplink** is actively contested or above `65%` capture progress.
  * Automatically ducks softly during `PauseMenu` and transitions to a calm ambient bed on `MainMenu`.
* **Settings Integration:**
  * Add `ambience_volume: float = 0.55` to `SettingsManager` (`[audio]` section in `user://settings.cfg`) and an **Ambience Volume** slider in **Settings → Audio**, respecting Master Volume, Mute, and Mute-When-Unfocused.

### D.2 Unit-Class Procedural Synth "Barks" (`scripts/systems/audio_manager.gd`, `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`)

* Add `play_unit_bark(unit_class: StringName, bark_type: StringName)` (`&"select"` vs `&"order"`) in `AudioManager` using short (`150–240ms`), crisp procedural synth motifs with slight pitch variation (`±5%`) and a **`0.6s` global bark cooldown** so rapid clicking never feels noisy:
  * **`&"worker"`** (`Worker`, `Silica Harvester`, `Engineer`): Clean, nimble dual-tone telemetry beep.
  * **`&"swarm"`** (`Clone Trooper`, `Stinger`): Tight, high-energy metallic chirp / pulse cadence.
  * **`&"counter"`** (`Lance-Rig`, `Signal Jammer`): Crisp ionized harmonic lock-on tone.
  * **`&"support"`** (`Symbiote`): Warm, airy bio-synth chime.
  * **`&"heavy"`** (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`): Deep, resonant sub-bass servo thrum + metallic confirmation ping.
* Trigger on primary subgroup selection in `SelectionController` and on move/attack/repair/salvage order confirmation in `CommandRouter` (skipped in Spectator Mode).

---

## 6. File & Architecture Summary

### New Files to Create
* `scripts/units/movement_component.gd` (Extracted nav, worker RVO-pass, anti-stuck, approach slots, and `SpatialGrid` separation)
* `scripts/units/status_effect_component.gd` (Centralized buffs/debuffs/stat multipliers for current and future factions)
* `scripts/systems/spatial_grid.gd` (128px 2D spatial hash broadphase singleton)
* `scripts/data/faction_data.gd` & `resources/factions/genesis_v2_faction.tres` (Data-driven faction manifest)
* `scripts/world/salvage_core.gd` & `scenes/world/salvage_core.tscn` (Timed Silica/Compute wreckage pickup)

### Existing Files to Extend
* `project.godot` (Register `SpatialGrid` autoload if autoloaded)
* `scripts/units/unit.gd`, `scripts/units/combat_component.gd`, `scripts/units/ability_component.gd`, `scripts/units/heal_aura_component.gd`, `scripts/units/repair_component.gd`, `scripts/units/gather_component.gd` (Delegate movement/status to new components, query `SpatialGrid`, drop `SalvageCore`, support Auto-Cast & Salvage extraction)
* `scripts/data/unit_data.gd`, `scripts/data/ability_data.gd`, `resources/units/{goliath_frame,arc_lancer,chrysalis_mortar}_data.tres`, `resources/abilities/adrenal_surge.tres`
* `scripts/systems/team_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/ui/main_menu.gd`, `scripts/ui/tech_tree_overlay.gd` (Consume `FactionData` registry)
* `scripts/systems/fog_of_war.gd` & `scripts/world/destructible_barricade.gd` (Opaque blocker grid + 2D LOS ray shadowing + instant LOS rebuild on barricade breach)
* `scripts/systems/audio_manager.gd`, `scripts/systems/settings_manager.gd`, `scripts/ui/settings_menu.gd`, `scenes/ui/settings_menu.tscn` (Adaptive procedural ambience, Ambience Volume slider, and unit-class synth barks)
* `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`, `ui/hud/selection_hud.gd`, `ui/hud/minimap.gd`, `ui/overlays/entity_visuals.gd`, `ui/overlays/combat_vfx.gd`

---

## 7. Verification Checklist for `agy`

Before concluding Milestone 2.3, verify in Godot (`skirmish_arena_01.tscn` and `skirmish_arena_02.tscn`):

* [ ] **Refactored Movement & Worker Regression Check:** Run 3+ workers on 1 Biomass node, multi-worker building construction, and stutter-step kiting with Clone Troopers; verify zero regressions after extracting `MovementComponent` and `StatusEffectComponent`, and confirm `unit.gd` is substantially leaner and cleaner.
* [ ] **Spatial Grid Performance Stress Test:** Launch an `AI vs AI (Spectator)` match at `2x` speed (or spawn 40v40 units in `SandboxDebugPanel`); verify smooth frame pacing via the Corner FPS Counter, accurate targeting/heal auras/separation, and zero freed-instance errors.
* [ ] **`FactionData` Registry:** Confirm `MainMenu`, `TechTreeOverlay`, and `SkirmishAI` load `GENESIS_V2` rosters and building roles cleanly from `genesis_v2_faction.tres`.
* [ ] **Heavy Wreckage & Data Salvage:** Destroy a `Goliath Frame`, `Arc-Lancer`, or `Chrysalis Mortar`; verify a glowing `SalvageCore` drops with a 28s decay ring and minimap marker, right-clicking it with a Worker or Engineer channels an extraction beam and awards Silica + Compute, and untouched cores dissolve cleanly at 0s.
* [ ] **Ability Auto-Cast:** Right-click `Adrenal Surge` on selected Clone Troopers and `Auto-Repair` on a Worker/Engineer; verify the animated auto-cast border toggles on/off, Clone Troopers automatically trigger `Adrenal Surge` upon engaging enemies, and idle Workers/Engineers automatically repair nearby damaged friendlies.
* [ ] **True Line-of-Sight (LOS) Shadowing:** Move a unit beside a `TerrainObstacle` or intact `DestructibleBarricade` on `skirmish_arena_02.tscn`; verify enemy units behind the wall stay hidden in Fog of War until the unit rounds the corner—and verify destroying the barricade immediately opens vision through the breach.
* [ ] **Adaptive Ambience & Unit Synth Barks:** Verify the Technozen ambient bed plays smoothly, ramps up subtly during combat/Hyper-Uplink contests, respects the new **Settings → Audio → Ambience Volume** slider and Mute-on-Unfocus, and confirm selecting/ordering Workers, Clone Troopers, Symbiotes, and Goliath Frames triggers distinct, throttled synth barks with zero audio clipping or Godot Debugger errors.