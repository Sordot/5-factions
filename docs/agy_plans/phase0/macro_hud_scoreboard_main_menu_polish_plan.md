# Milestone 1.9 Plan: Macro HUD, Post-Match Telemetry & Main Menu Polish Pass

**Target Directory:** `docs/agy_plans/20_macro_hud_and_main_menu_polish.md`
**Primary Files:** `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`, `scripts/systems/game_config.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/skirmish_ai.gd`, `ui/hud/resource_hud.tscn`, `ui/hud/resource_hud.gd`, `ui/hud/selection_hud.gd`, `ui/hud/match_end_overlay.tscn`, `ui/hud/match_end_overlay.gd`
**Reference Docs:** `docs/agy_plans/genesis_v2_vertical_slice_completion_bundle.md`, `docs/agy_plans/rts_micro_shortcuts_settings_menu_plan.md`, `docs/agy_plans/19_keybinds_mouse_buttons_and_settings_polish.md`

## 1. Objective & Scope

Elevate the moment-to-moment macro readability, lobby configuration depth, and post-match feedback before moving into the Combat Feel & Telegraphing pass. Everything in this pass must fit cleanly inside the `1280×720` (`canvas_items` + `expand`) base viewport in both Windowed and Fullscreen modes without overlapping existing HUD elements (`ResourceHUD`, `SelectionHUD`, `Minimap`, `SandboxDebugPanel`, or the corner FPS counter).

### In Scope

1. **Macro HUD Upgrades (`ui/hud/`):**
   * **Global Production & Upgrade Ticker (`ui/hud/production_ticker.gd` + `.tscn`):**
     * A compact, collapsible vertical strip anchored to the top-left (below `ResourceHUD`) showing all active unit training batches and research upgrades across every owned `Team.PLAYER` structure (`Nexus Vat`, `Cloning Vat`, `Calibration Foundry`, `Synthetics Fabricator`).
     * Each entry displays: item name (with `x2` badge for Cloning Vat batches), total queued count across buildings (or per-building row), and a live horizontal progress bar.
     * **Interactive Clicks:** Left-clicking an entry selects that producing building; double-clicking centers `RTSCamera` on it.
   * **Active Control Group Ribbon (`ui/hud/selection_hud.gd` / `.tscn`):**
     * Render compact clickable tabs (`[1]`–`[9]`) directly above `SelectionHUD` for any currently populated control group, showing the hotkey number and live unit/building count.
     * Single-click selects the control group; double-click selects and centers the camera on it (respecting existing `SelectionController` control group state).
   * **Economy Income Rates, Match Timer & Bandwidth Warning (`ui/hud/resource_hud.gd` + `.tscn`):**
     * Display rolling income rates (`+XX/m`) beside **Biomass**, **Silica**, and **Compute** (averaged over a short sliding window in `EconomyManager` so numbers feel steady rather than jumpy).
     * Add a clean **`MM:SS` Match Timer** in the top HUD bar alongside the **Data Hyper-Uplink** status indicator.
     * Add a subtle amber/crimson pulse highlight on the **Bandwidth** counter whenever `bandwidth_used >= bandwidth_cap` (supply-capped warning).

2. **Main Menu & Skirmish Lobby Polish (`scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`, `scripts/systems/game_config.gd`, `scripts/systems/skirmish_ai.gd`):**
   * **AI Difficulty & Personality Presets:**
     * Expand the Skirmish Match Setup panel to include:
       * **AI Difficulty:** `Relaxed`, `Standard` (default), `Brutal` — tunes `SkirmishAICommander` decision tick cadence, worker saturation targets, and attack wave timing cleanly without cheating resources (or optional subtle macro efficiency tuning on `Brutal`).
       * **AI Playstyle:** `Balanced` (default), `Swarm Rush` (prioritizes early `Cloning Vat` + `Clone Trooper`/`Stinger` pressure), `Synthetics Tech` (fast `Wetware Mainframe` + `Synthetics Fabricator` heavies).
       * Retain the `Passive / Sandbox AI` option (`Aggro AI: OFF`) for stress-testing.
     * Persist selected lobby preferences in `GameConfig` so **Play Again** keeps the chosen difficulty, playstyle, map, and resource preset.
   * **Interactive Faction Dossier Cards:**
     * Allow clicking the locked Factions `#2–#5` cards (`AETHER_PRIME`, `IRON_CONSENSUS`, `NULL_VECTOR`, `VERDANT_OS`) to inspect a concise classified tactical teaser (planned archetype & future counter-identity) while keeping `GENESIS_V2` clearly highlighted as the active playable faction for **Launch Skirmish**.
   * **Menu Audio & Visual Polish:**
     * Trigger crisp `AudioManager` hover/click UI cues on all Main Menu buttons and dropdowns.
     * Add a subtle animated Technozen terminal grid / scanline accent in the `MainMenu` background `_draw()` (lightweight, zero impact on legibility).

3. **Post-Match Scoreboard & Telemetry (`scripts/systems/match_manager.gd`, `ui/hud/match_end_overlay.tscn`, `ui/hud/match_end_overlay.gd`):**
   * **Match Telemetry Tracking (`MatchManager`):**
     * Track lightweight match counters for both `Team.PLAYER` and `Team.ENEMY`:
       * `biomass_gathered`, `silica_gathered`, `compute_gathered`
       * `units_trained`, `units_lost`, `enemy_units_destroyed`
       * `buildings_built`, `buildings_lost`
       * `peak_bandwidth`, `uplink_control_seconds`, `match_duration_seconds`
   * **Scoreboard Overlay (`MatchEndOverlay`):**
     * Display a clean two-column **Player (`GENESIS_V2`) vs. AI (`GENESIS_V2`)** comparison table inside `MatchEndOverlay` alongside match duration, victory reason (*Nexus Vat Destroyed* or *Data Hyper-Uplink Mastery*), and the existing **Play Again** / **Main Menu** buttons.

### Out of Scope
* Combat targeting priority, weapon VFX, or status-effect telegraphing (scheduled for the next Combat Feel pass).
* Implementing playable units/buildings for Factions `#2–#5`.
* Second skirmish map scene (`skirmish_arena_02.tscn`).

---

## 2. Detailed Technical Specifications

### 2.1 Global Production & Upgrade Ticker (`ui/hud/production_ticker.gd` & `.tscn`)
* **Placement:** Anchor top-left below `ResourceHUD` (e.g., `offset_top = 56`, `offset_left = 12`, max width `220px`), with `mouse_filter = MOUSE_FILTER_PASS` on empty space so it never blocks map clicks or drag-box selection.
* **Data Polling:** Refresh every `0.2s` (or on production/upgrade signals) by scanning `Team.PLAYER` buildings in the `"buildings"` group that have active `ProductionComponent` queues or active `UpgradeManager` research.
* **Row Cap:** Display up to `5` active rows cleanly (with a compact `+N more` footer if more than 5 buildings are producing simultaneously) so it never collides with `SelectionHUD` or `Minimap`.
* **Click Routing:** Connect row clicks to `SelectionController.select_single_entity(building)` (and center `RTSCamera` on double-click).

### 2.2 Control Group Ribbon (`ui/hud/selection_hud.gd` & `scripts/controllers/selection_controller.gd`)
* Expose a read-only summary helper on `SelectionController`: `get_control_group_summaries() -> Dictionary` returning `{ group_index: { "count": int, "label": String, "is_active": bool } }` for non-empty groups `1–9`.
* Render a compact `HBoxContainer` ribbon just above `SelectionHUD`'s main panel (hidden automatically when zero control groups are assigned).
* Clicking a tab invokes `SelectionController.recall_control_group(group_index, false)`; double-clicking invokes `SelectionController.recall_control_group(group_index, true)`.

### 2.3 Economy Income Rates & Bandwidth Alert (`scripts/systems/economy_manager.gd`, `ui/hud/resource_hud.gd`)
* In `EconomyManager`, maintain a lightweight `30.0s` rolling sample ring/array of resource deposits per team (`biomass`, `silica`, `compute`) and expose `get_income_rate_per_minute(team: int, resource_type: StringName) -> int`.
* Also track cumulative totals (`total_gathered`) per team and forward/expose them to `MatchManager` for the post-match scoreboard.
* In `ResourceHUD`:
  * Show compact muted rate tags next to resource totals (e.g., `340 (+95/m)`).
  * Show `MM:SS` match time from `MatchManager.get_match_elapsed_seconds()`.
  * Pulse the Bandwidth label in warm amber/crimson when `used >= cap` and `cap > 0`.

### 2.4 AI Difficulty & Playstyle Wiring (`scripts/systems/game_config.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/ui/main_menu.gd`)
* Extend `GameConfig` with:
  * `enum AIDifficulty { RELAXED, STANDARD, BRUTAL }` (`var ai_difficulty: AIDifficulty = AIDifficulty.STANDARD`)
  * `enum AIPlaystyle { BALANCED, SWARM_RUSH, SYNTHETICS_TECH }` (`var ai_playstyle: AIPlaystyle = AIPlaystyle.BALANCED`)
* Apply these cleanly in `SkirmishAICommander._ready()`:
  * **Difficulty scaling:**
    * `RELAXED`: slower decision interval (`1.6x`), lower worker cap (`4`), smaller early wave size.
    * `STANDARD`: current baseline tuning (`1.0x`).
    * `BRUTAL`: sharper decision interval (`0.7x`), faster expansion/saturation, larger coordinated waves.
  * **Playstyle weights:**
    * `SWARM_RUSH`: builds `Cloning Vat` earlier, higher `Clone Trooper` / `Stinger` ratio, earlier first attack wave.
    * `SYNTHETICS_TECH`: prioritizes `Wetware Mainframe` + `Synthetics Fabricator` + `Compute Overdrive`, fields `Goliath Frame` / `Arc-Lancer` / `Chrysalis Mortar` earlier.
    * `BALANCED`: current all-round progression curve.

### 2.5 Post-Match Scoreboard (`scripts/systems/match_manager.gd`, `ui/hud/match_end_overlay.gd` + `.tscn`)
* Hook into existing unit/building spawn & death callbacks (`unit_died`, `building_destroyed`, `production_completed`) and `EconomyManager` cumulative totals so zero duplicate polling is required.
* Populate a clean `GridContainer` (3 columns: `Metric`, `Player`, `AI`) inside `MatchEndOverlay`, highlighting the higher value in each positive stat with Technozen cyan/emerald tinting.
* Ensure `MatchEndOverlay` stays cleanly centered within `1280×720` and fullscreen with comfortable margins.

---

## 3. File & Architecture Plan

### New Files to Create
* `ui/hud/production_ticker.tscn` & `ui/hud/production_ticker.gd` (Global player production & upgrade progress strip with click-to-select / double-click-to-focus).

### Existing Files to Extend
* `scripts/systems/economy_manager.gd` (Rolling 30s income-per-minute calculator + cumulative resource gathered counters per team).
* `scripts/systems/match_manager.gd` (Match elapsed timer + Player/AI telemetry dictionary for units, buildings, peak bandwidth, and Uplink hold time).
* `scripts/systems/game_config.gd` (`ai_difficulty` and `ai_playstyle` enums & state).
* `scripts/systems/skirmish_ai.gd` (Consume `GameConfig.ai_difficulty` and `GameConfig.ai_playstyle` to adjust cadence and build weights).
* `scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd` (AI Difficulty & Playstyle selectors, interactive locked-faction dossier teaser display, subtle animated background grid, and `AudioManager` hover/click SFX).
* `ui/hud/resource_hud.tscn` & `ui/hud/resource_hud.gd` (Income `/m` badges, `MM:SS` match timer, Bandwidth supply-cap warning highlight).
* `ui/hud/selection_hud.tscn`, `ui/hud/selection_hud.gd`, & `scripts/controllers/selection_controller.gd` (Clickable Control Group `1–9` ribbon above `SelectionHUD`).
* `ui/hud/match_end_overlay.tscn` & `ui/hud/match_end_overlay.gd` (Two-column Player vs. AI scoreboard table).
* `scenes/maps/skirmish_arena_01.tscn` & `scenes/test/milestone_0_test.tscn` (Instance `ProductionTicker` inside the HUD `CanvasLayer`).

---

## 4. Verification Checklist for `agy`

Before concluding Milestone 1.9, verify in Godot (both Windowed `1280×720` and Fullscreen `F11`):

* [ ] **Global Production & Upgrade Ticker:** Queue units at 2 **Cloning Vats** and an upgrade at a **Wetware Mainframe** or **Cloning Vat**; verify live progress bars appear in the top-left ticker, clicking a row selects that building, double-clicking jumps the camera to it, and the ticker hides cleanly when nothing is queued.
* [ ] **Control Group Ribbon:** Assign units/buildings to `Ctrl+1` and `Ctrl+2`; verify `[1]` and `[2]` badges appear above `SelectionHUD` with accurate live counts, single-clicking selects the group, double-clicking focuses the camera, and destroying all members removes the badge cleanly.
* [ ] **Income Rates, Timer & Bandwidth Warning:** Gather Biomass, Silica, and Compute; verify `+XX/m` rates and the `MM:SS` timer update smoothly, and confirm the Bandwidth indicator highlights when supply-capped.
* [ ] **Main Menu & AI Presets:** Click through locked Factions `#2–#5` dossiers to verify teaser previews without breaking `GENESIS_V2` launch; test launching with different **AI Difficulty** (`Relaxed` / `Standard` / `Brutal`) and **AI Playstyle** (`Balanced` / `Swarm Rush` / `Synthetics Tech`) presets and confirm zero UI clipping at `1280×720` and Fullscreen.
* [ ] **Post-Match Scoreboard:** Win or lose a quick skirmish (or destroy a `Nexus Vat` via `SandboxDebugPanel`); verify `MatchEndOverlay` displays accurate Player vs. AI resources gathered, units trained/lost, structures built/lost, Uplink hold time, and match duration, with **Play Again** preserving the chosen lobby settings.