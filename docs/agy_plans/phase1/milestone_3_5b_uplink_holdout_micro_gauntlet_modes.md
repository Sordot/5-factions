# Milestone 3.5b — Alternate Game Modes: Uplink Holdout & Micro Gauntlet

**Prerequisite:** Milestone 3.5a (`43_milestone_3_5a_micro_clarity_audio_and_analytics.md`) verified and working cleanly.

**Goal:** Expand *5 Factions* beyond standard Skirmish with two high-replayability, lightweight solo modes built directly on top of the existing procedural maps, `FactionData` pipeline, and RTS micro systems—zero map duplication bloat:

1. **Uplink Holdout (Wave-Survival Defense Mode):** Defend your Command Hub and the central **Data Hyper-Uplink** on `skirmish_arena_01.tscn` against escalating, faction-themed assault waves (10 Waves + Endless option) with brief inter-wave breather timers, bonus Salvage/Compute drops, and live wave telemetry.
2. **Micro Gauntlet (Curated Tactical Drills with Live Timer Medals):** Three bite-sized, repeatable 60–180 second RTS skill challenges (*Stutter-Step vs. Bulwarks*, *Siege-Line Breach*, *Optimal 3-Minute Boom*) featuring deterministic squad spawns, live Bronze / Silver / Gold medal timers, instant **Retry Drill (`R`)**, and persistent personal-best records.

**Non-Negotiable Constraints:**
* **Full Faction Support:** Both `GENESIS_V2` and `MONOLITH_OS` must be playable in Uplink Holdout and supported cleanly in the Micro Gauntlet.
* **100% Procedural Pipeline & Zero Scene Bloat:** Reuse existing arena scenes (`skirmish_arena_01.tscn` for Uplink Holdout; `milestone_0_test.tscn` or clean arena slice for Micro Gauntlet) driven by lightweight mode controller scripts—no duplicate map copies.
* **Strict `1280×720` UI Discipline:** The Main Menu mode selector, in-game Holdout/Gauntlet HUD banners, and Medal Result Modal must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).
* **Zero Regression on Standard Skirmish:** Default launch mode remains **Skirmish**; all 1v1, 2v2, 3P/4P FFA, AI Spectator, and Hyper-Uplink Countdown rules remain 100% unchanged.

---

## Phase A — Game Mode Framework & Main Menu Integration

### A.1 `GameConfig` Mode State (`scripts/systems/game_config.gd`)
Add clean mode metadata without breaking existing skirmish methods:
* `enum GameMode { SKIRMISH = 0, UPLINK_HOLDOUT = 1, MICRO_GAUNTLET = 2 }`
* `var active_game_mode: GameMode = GameMode.SKIRMISH`
* `var holdout_enemy_faction_id: StringName = &"monolith_os"` (or opposing faction to player's choice)
* `var holdout_difficulty: AIDifficulty = AIDifficulty.STANDARD`
* `var selected_gauntlet_drill_id: StringName = &"stutter_step_bulwarks"`
* Helper methods: `set_holdout_config(player_faction_id, enemy_faction_id, difficulty)` and `set_gauntlet_config(drill_id, player_faction_id)` (both configure `TeamManager` cleanly for Player Team 0 vs. Hostile Team 1, disabling standard `SkirmishAICommander` macro building when in Holdout or Gauntlet mode).

### A.2 Persistent Medal & High-Score Records (`scripts/systems/settings_manager.gd` or `scripts/systems/mode_records.gd`)
Persist solo mode achievements cleanly in `user://mode_records.cfg` (or under `[records]` in `user://settings.cfg`):
* **Uplink Holdout:** Highest wave cleared per faction & difficulty (`holdout_best_wave`).
* **Micro Gauntlet:** Best medal (`NONE`, `BRONZE`, `SILVER`, `GOLD`) and best score/completion time per `drill_id`.

### A.3 Compact Mode Switcher in `MainMenu` (`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`)
Keep the exact `448 px` `ConfigPanel` width and zero vertical overflow at `1280×720`:
* Add a sleek 3-pill tab strip right beneath `ConfigHeader`: **`[SKIRMISH]` | `[HOLDOUT]` | `[GAUNTLET]`**.
* **Left Panel (`FactionColumn`):** Remains active and interactive across all 3 modes (selecting `GENESIS_V2` or `MONOLITH_OS` sets the player's faction for Skirmish, Holdout, or the Boom drill!).
* **Right Panel (`ConfigPanel`) Swaps Contextually:**
  * **`SKIRMISH`:** Existing Skirmish Match Setup (unchanged).
  * **`HOLDOUT`:**
    * Concise briefing (*"Defend your base & Hyper-Uplink against 10 escalating hostile waves. Holding the Uplink boosts production +10% and grants inter-wave Compute dividends."*).
    * Opposing Wave Faction selector (`GEN-V2` / `MONO-OS` / `MIXED ASSAULT`), Difficulty (`Relaxed` / `Standard` / `Brutal`), and Best Wave Cleared readout.
    * Launch button: **`LAUNCH UPLINK HOLDOUT`**.
  * **`GAUNTLET`:**
    * 3 clickable Drill Cards showing drill name, objective summary, Gold/Silver/Bronze thresholds, and your saved **Best Medal / Best Time**:
      1. **`Stutter-Step vs. Bulwarks`** *(60s Tactical Micro)*
      2. **`Siege-Line Breach`** *(90s Assault Micro)*
      3. **`Optimal 3-Minute Boom`** *(180s Macro Economy Drill)*
    * Launch button: **`LAUNCH DRILL`**.

---

## Phase B — Uplink Holdout (Wave-Survival Defense Mode)

### B.1 Mode Controller (`scripts/systems/holdout_mode_controller.gd`)
Attached dynamically by `MatchManager` when `GameConfig.active_game_mode == GameConfig.GameMode.UPLINK_HOLDOUT`:
* **Match Setup on `skirmish_arena_01.tscn`:**
  * Keep Player (Team 0) starting base, workers, and full economy/tech tree at the Bottom-Left Vat Basin.
  * Remove Team 1's pre-placed enemy Command Hub and disable `SkirmishAICommander` so Team 1 acts purely as a wave-spawning invasion force (preventing premature Victory on frame 1!).
  * Disable standard `victory_on_command_core_loss` for Team 1 while keeping **Defeat** active if all Player Command Hubs are destroyed.
  * Give the Player a crisp `35s` opening preparation timer before Wave 1 arrives (`25s` between subsequent waves; add a clickable **"Call Wave Early (+35B / +20S)"** bonus button on the Holdout HUD banner!).
* **10 Escalating Faction-Themed Waves (Spawned from Top-Right Basin & Flank Corridors):**
  * **Waves 1–3 (Early Skirmish):** Light probes (`Clone Trooper` + `Stinger` or `Picket Drone` + `Bulwark Automaton`) approaching down the main lane.
  * **Waves 4–6 (Dual-Lane Pressure):** Mixed Tier 1 squads splitting between the central Hyper-Uplink Plaza and North/South flanking corridors, introducing `Lance-Rig` / `Signal Jammer` or `Rail-Sentinel` / `Aegis Relay`.
  * **Waves 7–9 (Heavy Siege Assaults):** Tier 2 spearheads (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar` or `Monolith Dreadnought`, `Anvil Siege-Walker` that deploys outside turret range, `Null-Grid Projector`) dropping juicy `SalvageCore`s on death.
  * **Wave 10 (Sovereign Apex Wave):** Multi-pronged boss assault from all flank corridors + center lane; clearing all Wave 10 units triggers **HOLDOUT VICTORY** (with an optional **"Continue Endless"** button alongside **Rematch** and **Main Menu**!).
* **Hyper-Uplink Holdout Synergy:**
  * Holding the central `Data Hyper-Uplink` when a wave clears grants a **Wave-Clear Dividend** (`+60 Biomass / +40 Silica / +25 Compute`) + toast/chime, rewarding players for defending forward rather than turtling passively in their corner.
* **Compact Holdout HUD Banner (`ui/hud/mode_objective_banner.gd`):**
  * Docked cleanly top-center below `ResourceHUD` (`<= 440 px` wide, themed via `FactionHudTheme`), displaying:
    * `WAVE 4 / 10  •  HOSTILES: 12` (during active wave) OR `NEXT WAVE IN 00:19  [CALL EARLY]` (during prep)
    * Red pulsing minimap warning pings 5 seconds before each wave enters so players can see which lane(s) are incoming.

---

## Phase C — Micro Gauntlet (3 Curated Tactical Drills)

### C.1 Drill Controller (`scripts/systems/gauntlet_mode_controller.gd`)
Attached dynamically by `MatchManager` when `GameConfig.active_game_mode == GameConfig.GameMode.MICRO_GAUNTLET` (running on `scenes/test/milestone_0_test.tscn` with `SandboxDebugPanel` hidden, Fog of War OFF, and zero enemy AI macro):
* **Clean Arena Isolation:** Clears default sandbox dummies/units, centers `RTSCamera` on the drill arena, displays a concise 1.5s countdown/objective header on `ModeObjectiveBanner` (with live timer, objective progress bar, live Medal target indicator `GOLD / SILVER / BRONZE`, and instant **`[R] Retry`** button).

### C.2 Three Hand-Crafted Drills

1. **Drill 1 — `stutter_step_bulwarks` (*Stutter-Step vs. Bulwarks* — 60s Micro):**
   * **Player Squad (`GENESIS_V2`):** `6× Clone Trooper` (with `Adrenal Surge` ready) + `2× Symbiote` + `2× Lance-Rig`.
   * **Enemy Wave (`MONOLITH_OS`):** `5× Bulwark Automaton` advancing relentlessly toward the player squad.
   * **Objective:** Eliminate all `Bulwark Automatons` using stutter-step kiting, `Adrenal Surge`, and focus-fire before `60s` expires.
   * **Medals:**
     * **Gold:** Clear in `<= 32s` with `>= 7` player units surviving.
     * **Silver:** Clear in `<= 45s` with `>= 4` player units surviving.
     * **Bronze:** Clear within `60s`.

2. **Drill 2 — `siege_line_breach` (*Siege-Line Breach* — 90s Assault Micro):**
   * **Player Squad (`MONOLITH_OS`):** `2× Monolith Dreadnought` (with `Kinetic Barrier`) + `2× Anvil Siege-Walker` (deployable) + `2× Rail-Sentinel` + `2× Aegis Relay`.
   * **Enemy Fortification (`GENESIS_V2`):** `2× DestructibleBarricade` choke + `2× Defense Turret` + `2× Chrysalis Mortar` + `2× Goliath Frame` + `6× Clone Trooper` guarding a target `Nexus Vat`.
   * **Objective:** Breach the barricades, absorb mortar/turret fire with `Kinetic Barrier` + `Aegis Relay` shield overcharges, deploy `Anvil Siege-Walkers` at range, and neutralize the defending `Nexus Vat` within `90s`.
   * **Medals:**
     * **Gold:** Destroy `Nexus Vat` in `<= 50s` with `>= 5` units surviving.
     * **Silver:** Destroy `Nexus Vat` in `<= 70s` with `>= 3` units surviving.
     * **Bronze:** Destroy `Nexus Vat` within `90s`.

3. **Drill 3 — `optimal_3min_boom` (*Optimal 3-Minute Boom* — 180s Macro Economy Drill):**
   * **Player Setup:** Runs on `skirmish_arena_01.tscn` (peaceful macro—enemy team removed) using whichever playable faction the player selected (`GENESIS_V2` or `MONOLITH_OS`), standard starting resources (`200B / 50S`), and 3 starting workers.
   * **Objective:** Reach the highest combined **Active Economy & Army Benchmark** within `03:00` (tracking `Workers + Harvesters + Engineers Trained`, `Tier 1 + Tier 2 Structures Online`, `Army Supply Built`, and `Zero Supply-Block Bonus`).
   * **Medals (Live Score Formula = `Total Resources Gathered + Army Value × 1.5 - Supply Blocked Secs × 15`):**
     * **Gold:** Score `>= 4,200` (with Tier 2 structure completed before `03:00`).
     * **Silver:** Score `>= 3,000`.
     * **Bronze:** Score `>= 1,800`.

### C.3 Crisp Drill / Holdout Result Modal
* Reuse/extend `MatchEndOverlay` (or a slim companion mode-result state inside `MatchEndOverlay`) showing:
  * **Medal Earned** (`GOLD`, `SILVER`, `BRONZE`, or `FAILED`) rendered as a crisp procedural vector emblem with `"NEW PERSONAL BEST!"` badge when beaten.
  * Key drill stats (Completion Time, Survivors, Macro Score / Wave Reached).
  * 3 clean buttons: **`RETRY / REMATCH`**, **`NEXT DRILL`** (for Gauntlet), and **`MAIN MENU`**.

---

## Phase D — Verification & Playtest Checklist

1. **Main Menu Mode Switcher (`1280×720` Windowed & `F11` Fullscreen):**
   * Toggle between `SKIRMISH`, `HOLDOUT`, and `GAUNTLET` tabs in `ConfigPanel`: confirm zero vertical or horizontal clipping, smooth left-panel faction selection sync, and saved records displaying cleanly.
2. **Uplink Holdout End-to-End:**
   * Launch Holdout as `GENESIS_V2` vs. `MONOLITH_OS` waves and as `MONOLITH_OS` vs. `GENESIS_V2` waves.
   * Confirm zero premature Victory at `0.5s`, prep countdown works, **"Call Wave Early"** awards bonus resources and spawns immediately, minimap pings telegraph incoming wave lanes, holding the Hyper-Uplink awards the wave-clear dividend, and losing your last Command Hub triggers Defeat cleanly.
   * Test clearing Wave 10 (at `2x` speed or with Fast-Tech debug assist) to verify Victory modal + Endless option + `holdout_best_wave` persistence across restarts.
3. **Micro Gauntlet Drills:**
   * Play and complete all 3 drills (`Stutter-Step vs. Bulwarks`, `Siege-Line Breach`, `Optimal 3-Minute Boom` as both `GENESIS_V2` and `MONOLITH_OS`).
   * Verify instant **`Retry`** resets cleanly with zero leaked VFX/SpatialGrid entities, medals compute and persist accurately in `MainMenu`, and returning to Standard Skirmish restores normal 1v1/FFA AI behavior with zero regressions.