# Milestone 1.5 Plan: `GENESIS_V2` Vertical Slice Completion Bundle (Skirmish Integration, Visual/Audio Juice & Match Flow)

**Target Directory:** `docs/agy_plans/13_genesis_v2_full_skirmish_integration_and_tuning.md`
**Primary Scenes:** `res://scenes/ui/main_menu.tscn`, `res://scenes/maps/skirmish_arena_01.tscn`, `res://scenes/test/milestone_0_test.tscn`
**Reference Docs:** `docs/agy_plans/faction_01_genesis_v2_the_vat_born_plan.md`, `docs/agy_plans/skirmish_ai_fog_of_war_expanded_arena_plan.md`, `docs/technical_glossary_and_specs.md`

## 1. Objective & Scope

Bundle the three remaining pillars of the **Milestone 1 Vertical Slice** into a single cohesive implementation pass so the game plays, looks, sounds, and flows like a complete self-contained RTS vertical slice:

1. **Phase 1 — Full `GENESIS_V2` Skirmish Integration & Tuning:** Transition `skirmish_arena_01.tscn` and `SkirmishAICommander` off legacy prototype units/buildings onto `GENESIS_V2` (*The Vat-Born*) end-to-end (`Nexus Vat`, `1.75x` parallel-batch `Cloning Vat`, `Calibration Foundry`, `Synthetics Fabricator`, and all upgrades).
2. **Phase 2 — Technozen / Y2K Visual Identity & Audio Juice:** Give every `GENESIS_V2` unit and structure distinct, readable vector/procedural silhouettes, construction scaffolding states, and team-color accents, paired with a lightweight procedural/synthesized `AudioManager` (`assets/audio/`) so clicks, orders, combat, abilities, and alerts feel crisp and tactile.
3. **Phase 3 — Main Menu, Skirmish Lobby & Replay Flow:** Create a clean Technozen title & skirmish setup screen (`main_menu.tscn`) as the project's main entry point (`project.godot`), featuring faction selection (`GENESIS_V2` playable + Factions #2–#5 locked dossier previews), AI / Aggro toggles, and seamless return-to-menu / play-again flow from `MatchEndOverlay`.

### Out of Scope
* Playable rosters or build orders for Factions #2–#5 (display them as locked AI Lord preview cards in the skirmish setup screen only).
* External third-party `.wav`/`.ogg` asset imports if procedural `AudioStreamGenerator` / generated `.wav` buffers in `AudioManager` can provide crisp Y2K/Technozen SFX out of the box without binary asset dependencies.
* Multiplayer networking or campaign missions.

---

## 2. Phase 1: Full `GENESIS_V2` Skirmish Integration & Tuning

### A. Arena Starting Loadouts (`scenes/maps/skirmish_arena_01.tscn`)
* **Player Base (Bottom-Left):** Replace starting `CommandCore` with `res://scenes/buildings/nexus_vat.tscn` (`Team.PLAYER`) and `3x` `worker_unit.tscn` positioned cleanly near the starting `BiomassNode` cluster.
* **Enemy Base (Top-Right):** Replace starting `CommandCore` with `res://scenes/buildings/nexus_vat.tscn` (`Team.ENEMY`) and `3x` `Team.ENEMY` `worker_unit.tscn` units.
* **Match Victory / Defeat Conditions (`scripts/systems/match_manager.gd`):** Ensure `MatchManager` recognizes `nexus_vat` (and any `BuildingData` marked as a core command hub) so destroying the enemy `Nexus Vat` triggers the Victory overlay reliably.

### B. Worker Build Cards & Tech Prerequisites (`worker_unit_data.tres`, `ability_component.gd`, `selection_hud.gd`)
* Wire `worker_unit_data.tres` to all `GENESIS_V2` structure build abilities:
  * `build_nexus_vat`, `build_synapse_pylon`, `build_silica_condenser`, `build_wetware_mainframe`, `build_cloning_vat`, `build_calibration_foundry`, and `build_synthetics_fabricator` (locked/dimmed with `"Requires: Cloning Vat"` in `CommandTooltip` until the team owns a completed `Cloning Vat`).
* Ensure `SelectionHUD` Command Card accommodates all 7 Worker build abilities cleanly (e.g., 4x2 grid layout) without overlapping or clipping.

### C. Full `GENESIS_V2` Skirmish AI Progression (`scripts/systems/skirmish_ai.gd`)
Replace legacy prototype IDs (`bio_lab`, `silica_refinery`, `bandwidth_relay`, `compute_node`, `enemy_trooper`) with `GENESIS_V2`'s actual progression curve:
* **Early Game (`0:00 – 2:30`):** Saturate `BiomassNode`s (`4–6` Workers), build a **Silica Condenser** + `1–2` **Harvesters**, place **Synapse Pylons** proactively before Bandwidth caps, construct a **Cloning Vat**, and train `1.75x` parallel batches of **Clone Troopers** (`~65%`), **Stingers** (`~25%`), and **Symbiotes** (`~10%`) to contest the **Data Hyper-Uplink**.
* **Mid Game (`2:30 – 5:00`):** Build a **Wetware Mainframe** on the base `ComputeVent`, staff `1–2` **Engineers** for **Compute**, research **Batch Efficiency** and **Adrenal Potency**, and optionally construct a **Calibration Foundry** to mix in **Lance-Rigs** or **Signal Jammers**.
* **Late Game (`5:00+`):** Construct a **Synthetics Fabricator**, research **Compute Overdrive**, and add **Goliath Frames**, **Arc-Lancers**, and **Chrysalis Mortars** to coordinated attack waves.

### D. Roster Mechanics & Sandbox Parity (`production_component.gd`, `sandbox_debug_panel.gd`, `resources/units/*.tres`)
* Offset `Cloning Vat` batch spawns perpendicularly (`±18px`) from the exit marker so paired clones never overlap on spawn; display `x2` batch cost (`88 B` / `2 BW`, updating to `75 B` after **Batch Efficiency**) in `CommandTooltip`.
* Verify and tune **Symbiote** stacking heal aura, **Arc-Lancer** Colossus-stride friendly collision bypass, **Chrysalis Mortar** `min_attack_range` + AoE shelling, and **Lance-Rig** anti-armor bonus damage.
* Update `SandboxDebugPanel` spawner lists to include all `GENESIS_V2` units and structures for both teams.

---

## 3. Phase 2: Technozen / Y2K Visual Identity & Audio Juice

### A. Distinct Unit & Building Silhouettes (`ui/overlays/entity_visuals.gd` or `_draw()` on `Unit` / `Building`)
Instead of uniform placeholder boxes/circles, give every `GENESIS_V2` archetype a distinct, high-contrast procedural/vector silhouette drawn cleanly in `_draw()` (or lightweight child visual nodes) with translucent white/silver Y2K shells and bioluminescent team cores (`Cyan/Emerald` for `Team.PLAYER`, `Crimson/Amber` for `Team.ENEMY`):
* **Economy & Tech Structures:**
  * **Nexus Vat:** Wide octagonal Y2K server base with a central pulsing bioluminescent culture core and docking bays.
  * **Synapse Pylon:** Tall diamond/needle spire with an orbiting signal ring.
  * **Silica Condenser:** Dual-tank geometric extractor with crystalline prism accents.
  * **Wetware Mainframe:** Brutalist server monolith with glowing neural-grid circuit lines and staffing indicator pips (`0/2`, `1/2`, `2/2` Engineers).
* **Military Structures & Construction Scaffolding:**
  * **Cloning Vat:** Twin-chambered translucent bio-tank with animated dual-pulse indicators while training a batch.
  * **Calibration Foundry:** Angular industrial chassis bay with gantry arms.
  * **Synthetics Fabricator:** Heavy reinforced mega-bay with glowing high-Compute capacitor coils.
  * **Construction State:** Unfinished buildings render as wireframe/holographic blueprints that progressively fill in from bottom to top as `build_progress` advances from `0%` to `100%`.
* **Unit Archetype Silhouettes:**
  * **Worker / Harvester / Engineer:** Compact utility chassis with distinct tool prongs (bio-claw, wide crystal scoop, neural wrench).
  * **Clone Trooper:** Crisp infantry silhouette with rifle barrel + glowing cyan/crimson visor core (flashes bright green/gold during **Adrenal Surge**).
  * **Stinger:** Sleek, swept-back triangular speed-dart silhouette with subtle motion trail.
  * **Symbiote:** Floating orb-drone with a soft translucent healing aura ring (`130px` radius, subtle pulse).
  * **Lance-Rig:** Heavy bipedal/tracked rail-walker with an elongated anti-armor lance barrel.
  * **Signal Jammer:** Dish-topped support walker that emits an expanding interference ring on **Static Pulse**.
  * **Goliath Frame:** Broad, imposing heavy mech silhouette with layered shoulder plates (gains glowing overdrive trim after **Compute Overdrive**).
  * **Arc-Lancer:** Tall, slender tripod/strider silhouette elevated with a subtle ground shadow offset so its Colossus-stride over smaller units reads immediately.
  * **Chrysalis Mortar:** Wide, low-slung artillery carapace with a central dorsal mortar tube.

### B. Procedural Y2K / Technozen Audio System (`scripts/systems/audio_manager.gd`)
Register an autoload singleton `AudioManager` (`project.godot`) using Godot's built-in `AudioStreamWAV` / procedural waveform synthesis (or lightweight generated PCM buffers at startup—zero external audio file dependencies required) with polyphonic `AudioStreamPlayer` pooling and volume/mute controls:
* **UI & Command Feedback:** Crisp Y2K glass/sine click on button press, subtle chime on unit selection, low-pass digital chirp on move/attack/gather order confirmation, and distinct completion tones when a building or upgrade finishes.
* **Economy & Error Alerts:** Soft warning buzz + HUD flash when attempting to queue/build with insufficient **Biomass**, **Silica**, **Compute**, or **Bandwidth**.
* **Combat & Ability SFX:** Punchy synthesized rifle bursts (**Clone Trooper**), slash/acid snap (**Stinger**), high-voltage rail zap (**Lance-Rig** / **Arc-Lancer**), deep thud + splash (**Chrysalis Mortar** / **Seismic Slam**), and synth hum (**Adrenal Surge** / **Static Pulse**).
* **Audio Controls:** Add a **Mute / Volume** toggle button in `ResourceHUD` (and `MainMenu`) so sound can be toggled in one click during testing.

---

## 4. Phase 3: Main Menu, Skirmish Lobby & Match Replay Flow

### A. Technozen Title & Skirmish Setup Scene (`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`)
Set `res://scenes/ui/main_menu.tscn` as `run/main_scene` in `project.godot` (while keeping `F6` direct-scene launch working seamlessly for `skirmish_arena_01.tscn` and `milestone_0_test.tscn`):
* **Aesthetic:** Styled with `resources/themes/technozen_theme.tres`—clean Y2K terminal framing, animated subtle grid/scanline backdrop, bold title header (**5 FACTIONS // SOVEREIGN KERNEL**), and version/vertical-slice status tag.
* **Faction Dossier Selector:**
  * **Slot 1 (Unlocked — Active):** `GENESIS_V2` (*The Vat-Born*) — displays faction summary (*Bio-Synth Swarm • 1.75x Batch Cloning • Heavy Synthetics Pivot*), signature unit badges, and color swatch.
  * **Slots 2–5 (Locked Preview Cards):** Four classified AI Lord dossiers (`LOCKED — IN DEVELOPMENT`) showing silhouette/codename teasers so the 5-faction premise is immediately clear on launch.
* **Skirmish Match Configuration Panel:**
  * **Map Selector:** `Skirmish Arena 01 (1v1 Symmetric)` (with `Sandbox Testbed` option pointing to `milestone_0_test.tscn` for quick dev access).
  * **AI Opponent Mode:** Toggle between `Standard Skirmish AI` (`Aggro AI: ON`) and `Passive / Sandbox AI` (`Aggro AI: OFF`).
  * **Starting Resource Preset:** `Standard (200 B / 50 S)` or `Fast-Tech Test (1000 B / 500 S / 200 C)` so you can jump straight into testing Tier-2 Synthetics Fabricator battles whenever you want.
* **Launch & Exit Actions:** **LAUNCH SKIRMISH** transitions cleanly to the selected scene and applies the chosen AI/resource config via a lightweight `GameConfig` autoload/metadata dictionary; **QUIT** exits cleanly.

### B. End-of-Match Flow (`ui/hud/match_end_overlay.gd` & `.tscn`)
* Update `MatchEndOverlay` so players can click **PLAY AGAIN** (reloads `skirmish_arena_01.tscn` with current match settings) or **MAIN MENU** (returns to `res://scenes/ui/main_menu.tscn`).

---

## 5. File & Architecture Summary

### New Files to Create
* `scripts/systems/audio_manager.gd` (Autoload singleton for procedural Y2K/Technozen UI, command, combat, and alert SFX + mute/volume state)
* `scripts/systems/game_config.gd` (Lightweight autoload holding selected map, starting resource preset, and initial `aggro_ai_enabled` state between `MainMenu` and `skirmish_arena_01.tscn`)
* `scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd` (Title screen, 5-faction dossier selector, skirmish settings, and sandbox shortcut)

### Existing Files to Extend
* `project.godot` (Register `AudioManager` and `GameConfig` autoloads; set `run/main_scene="res://scenes/ui/main_menu.tscn"`)
* `scenes/maps/skirmish_arena_01.tscn` (Replace starting `CommandCore`s with `NexusVat`s and starting `Worker`s; read `GameConfig` starting resources and AI mode on `_ready()`)
* `resources/units/worker_unit_data.tres`, `scripts/units/ability_component.gd`, `scripts/buildings/production_component.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/systems/match_manager.gd` (Full `GENESIS_V2` integration & prerequisite enforcement)
* `scripts/units/unit.gd` & `scripts/buildings/building.gd` (Archetype-specific procedural `_draw()` silhouettes, construction blueprint fill visuals, and `AudioManager` SFX triggers on selection, orders, attacks, damage, and completion)
* `ui/hud/selection_hud.gd`, `ui/hud/resource_hud.gd`, `ui/hud/sandbox_debug_panel.gd`, `ui/hud/match_end_overlay.gd` (4x2 Worker build grid, batch cost tooltips, mute toggle in `ResourceHUD`, `GENESIS_V2` sandbox spawner parity, and **Main Menu** return button on `MatchEndOverlay`)

---

## 6. Verification Checklist for `agy`

Before concluding this milestone, verify in Godot:
* [ ] **Main Menu & Match Flow (`F5`):** Pressing `F5` opens `main_menu.tscn` showing `GENESIS_V2` active alongside 4 locked faction dossiers; choosing **Standard** or **Fast-Tech Test** resources and clicking **Launch Skirmish** loads `skirmish_arena_01.tscn` with those exact starting resources and AI Aggro state, and `MatchEndOverlay` returns cleanly to `Main Menu` or restarts.
* [ ] **Full `GENESIS_V2` Loop (`F6` on `skirmish_arena_01.tscn`):** Both Player and Enemy start with a `Nexus Vat` and `Worker`s; Workers construct all `GENESIS_V2` buildings (`Synthetics Fabricator` locked until `Cloning Vat` completes); `Cloning Vat` spawns `2` non-overlapping units at `1.75x` cost (`1.50x` with `Batch Efficiency`).
* [ ] **Distinct Visual Silhouettes & Blueprints:** Every `GENESIS_V2` unit (`Worker`, `Harvester`, `Engineer`, `Clone Trooper`, `Stinger`, `Symbiote`, `Lance-Rig`, `Signal Jammer`, `Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`) and structure has a distinct, recognizable Y2K/Technozen silhouette, team color accents, and progressive construction fill.
* [ ] **Procedural Audio Feedback:** Clicking UI buttons, selecting units, issuing move/attack/gather orders, firing weapons, casting abilities, completing structures/upgrades, and hitting insufficient-resource limits all trigger crisp, non-clipping procedural SFX with a working Mute toggle in `ResourceHUD`.
* [ ] **Full AI Progression:** With `Aggro AI: ON`, the Enemy AI expands from `Nexus Vat` → `Cloning Vat` batch swarms → `Wetware Mainframe` + upgrades → `Synthetics Fabricator` heavy units.