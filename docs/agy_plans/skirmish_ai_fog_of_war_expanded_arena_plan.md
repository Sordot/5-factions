# Milestone 1.1 Plan: Skirmish AI Opponent, Minimap, Fog of War & Expanded Arena

**Target Directory:** `docs/agy_plans/09_skirmish_ai_fog_of_war_and_arena.md`
**Primary Scene:** `res://scenes/maps/skirmish_arena_01.tscn`
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/vertical_slice_core_loop_refactor_plan.md`

## 1. Objective & Scope

Transform `skirmish_arena_01.tscn` from a single-sided mechanics testbed into a complete, playable **1v1 Skirmish Vertical Slice**. Specifically, expand the arena with an enemy base in the opposite corner and tactical terrain/obstacles in between, introduce a **Tactical Minimap** and **Fog of War** so scouting matters, implement a **Skirmish AI Commander** that plays using the exact same resource and production rules as the player, and close the match loop with **Victory / Defeat** conditions.

### In Scope

1. **Expanded Symmetric Skirmish Arena (`scenes/maps/skirmish_arena_01.tscn`):**
   * Enlarge the arena enough to make Fog of War and scouting meaningful, while keeping base-to-base travel brisk (~12–18 seconds of unit walk time) so AI behavior and attack waves can be observed quickly during playtesting.
   * **Player Base (Bottom-Left):** Starting `CommandCore`, nearby `BiomassNode` cluster, `SilicaVein`, `ComputeVent`, and starting `Worker`s.
   * **Enemy Base (Top-Right):** Mirrored `Team.ENEMY` `CommandCore`, resource deposits (`BiomassNode`, `SilicaVein`, `ComputeVent`), and starting `Team.ENEMY` workers/harvesters.
   * **Mid-Map Terrain, Chokepoints & Cover Obstacles:** Add static impassable terrain blockers (e.g., Technozen server monoliths, rocky ridges, ruin walls) baked cleanly into the `NavigationRegion2D` polygon so units path around chokepoints, flanked lanes, and a central contested plaza housing the **Data Hyper-Uplink**.
2. **Fog of War & Vision System (`scripts/systems/fog_of_war.gd` & `ui/overlays/fog_overlay.gd`):**
   * Give `UnitData` and `BuildingData` a `vision_range: float` property.
   * Track grid-based visibility states for `Team.PLAYER`:
     * `UNEXPLORED` (pitch dark shroud)
     * `EXPLORED` (dimmed fog memory—terrain and static resource nodes remain visible, enemy units are hidden)
     * `VISIBLE` (live vision circle around friendly units/buildings—reveals enemy units, enemy structures, and live Hyper-Uplink status)
   * Hide `Team.ENEMY` units (`visible = false`) when they are not inside an active `VISIBLE` cell, and block right-click target-locking on unseen enemies in Fog of War.
3. **Tactical Minimap (`ui/hud/minimap.tscn` & `ui/hud/minimap.gd`):**
   * Docked cleanly in the bottom-left (or top-left) HUD frame styled with `resources/themes/technozen_theme.tres`.
   * Displays map bounds, terrain obstacle silhouettes, resource nodes, the central `HyperUplink`, friendly units/buildings (cyan/green), visible enemy units/buildings (red), Fog of War shroud overlay, and a white camera viewport rectangle.
   * **Interactive Minimap Controls:**
     * **Left-Click / Drag on Minimap:** Instantly moves `RTSCamera` to that world coordinate.
     * **Right-Click on Minimap:** Issues a Move (or Attack-Move if holding `A`) order to selected player units at that world coordinate.
4. **Skirmish AI Commander (`scripts/systems/skirmish_ai.gd`):**
   * Drives `Team.ENEMY` using `EconomyManager` (no infinite resource cheating—uses real Biomass, Silica, Compute, and Bandwidth):
     * **Economy Loop:** Assigns idle enemy workers to gather Biomass, constructs a `SilicaRefinery` + `BandwidthRelay` + `BioLab`, and trains workers/harvesters up to a target worker count.
     * **Army & Wave Logic:** Trains squads of `enemy_trooper`s from its `BioLab` and dispatches periodic attack waves (e.g., every `45–60s` or once squad size reaches `4–5` units), alternating between contesting the central **Data Hyper-Uplink** and pushing toward the player's base.
     * **Base Defense:** Pulls nearby idle/patrolling AI combat units to defend if player units attack enemy structures or workers.
5. **Match Victory / Defeat Flow (`scripts/systems/match_manager.gd` & `ui/hud/match_end_overlay.tscn`):**
   * Tracks active `CommandCore` (and production structures) per team.
   * Triggers **VICTORY** when all `Team.ENEMY` Command Cores/structures are destroyed, or **DEFEAT** when all `Team.PLAYER` Command Cores/structures are destroyed.
   * Displays a clean Technozen summary modal (Match Duration, Winner, Hyper-Uplink Control %, Units Trained/Lost) with **Play Again** (`get_tree().reload_current_scene()`) and **Sandbox Mode** buttons.

### Out of Scope

* Multiple AI difficulty personalities or adaptive build-order counter-picking.
* Full 5-faction tech trees or Tier-3 superweapons.
* Audio voiceovers or animated minimap ping shaders.

## 2. File & Architecture Plan

### New Files to Create

* `scripts/systems/fog_of_war.gd` (`class_name FogOfWarSystem extends Node`)
  * Maintains a 2D visibility grid (`cell_size = 64.0px`) covering the arena bounds (`explored_grid` + `visible_grid`).
  * Updates visibility cells on a lightweight fixed interval (e.g., `0.15s` timer rather than every render frame) using all living `Team.PLAYER` `Unit`s and `Building`s.
  * Toggles `visible` on `Team.ENEMY` units/buildings based on whether their current cell is `VISIBLE` (buildings once scouted can optionally remain visible as last-known structures in `EXPLORED` fog, just like StarCraft).
* `ui/overlays/fog_overlay.gd`
  * Renders the world-space Fog of War shroud texture (`Image` / `ImageTexture` updated when visibility cells change, smoothly filtered) above terrain/units and below world UI reticles.
* `ui/hud/minimap.tscn` & `ui/hud/minimap.gd`
  * Renders terrain obstacles, resource nodes, Hyper-Uplink, fog state, unit/building blips, and the live camera frustum rectangle; routes minimap clicks to `RTSCamera` and `CommandRouter`.
* `scripts/systems/skirmish_ai.gd` (`class_name SkirmishAICommander extends Node`)
  * Modular decision-loop node (`decision_interval = 1.0s`) attached to `skirmish_arena_01.tscn` controlling `Team.ENEMY` economy, building placement near the enemy base, unit training, and attack waves.
* `scripts/systems/match_manager.gd` & `ui/hud/match_end_overlay.tscn`
  * Evaluates win/loss conditions whenever a building is destroyed and displays the end-of-match summary screen.

### Existing Files to Extend

* `scripts/data/unit_data.gd` & `scripts/data/building_data.gd`
  * Add `@export var vision_range: float = 360.0` (e.g., `480.0` on `scout_unit_data.tres`, `450.0` on `CommandCore`).
* `scripts/systems/economy_manager.gd`
  * Ensure all resource dictionaries, Bandwidth caps, and production speed multipliers are cleanly keyed by `team` (`Team.PLAYER` and `Team.ENEMY`) so the AI Commander uses the exact same `can_afford`, `spend_resources`, and `has_bandwidth` APIs as the player.
* `scripts/buildings/building.gd` & `scripts/buildings/production_component.gd`
  * Ensure enemy-owned buildings (`Team.ENEMY`) properly register with `EconomyManager`, spawn enemy-colored units, and execute rally points without requiring UI selection.
* `scripts/controllers/command_router.gd`
  * Prevent right-click enemy targeting on `Team.ENEMY` units that are currently hidden in Fog of War (`!target.visible`), falling back to a standard ground move order at that location.
* `scenes/maps/skirmish_arena_01.tscn`
  * Expand map dimensions (e.g., `2400 x 1800` or `2800 x 2000`), place mirrored Player (bottom-left) and Enemy (top-right) starting bases, add central `HyperUplink` and symmetric terrain obstacle walls/pillars creating a main center lane + two side flank paths, and bake the updated `NavigationRegion2D`.

## 3. Detailed Behavior Specifications

### A. Arena Layout & Pacing (`skirmish_arena_01.tscn`)

* **Map Size & Travel Time:** Sized around `2600 x 1900` pixels with bases tucked in opposite corners (`~(420, 1480)` for Player, `~(2180, 420)` for Enemy) and the **Data Hyper-Uplink** at the center `(1300, 950)`.
* **Terrain Architecture:**
  * Place impassable Technozen wall segments / rock formations (`StaticBody2D` on World collision layer + visual polygon fill) forming natural **base ramp chokepoints** and **central line-of-sight blockers** around the Hyper-Uplink.
  * Ensure `NavigationRegion2D` carves clean margins around all terrain obstacles and buildings so squads path smoothly through chokepoints without snagging on corners.

### B. Fog of War & Scouting Loop (`fog_of_war.gd`)

1. **Three Visibility States:**
   * `0 = UNEXPLORED`: Full dark shroud (`alpha ~0.92`) on both map and minimap.
   * `1 = EXPLORED`: Half-dimmed shroud (`alpha ~0.50`); terrain, resource nodes, and previously spotted enemy buildings remain visible, while enemy mobile units are hidden.
   * `2 = VISIBLE`: Fully clear (`alpha = 0.0`); live enemy units, projectiles/tracers, and Hyper-Uplink contest rings are visible.
2. **Scouting Value:** `ScoutUnit` (`vision_range = 480.0`) sees significantly farther than standard infantry (`340.0`), letting players spot enemy base expansion or incoming AI attack waves early.

### C. Skirmish AI Decision Loop (`skirmish_ai.gd`)

Every `1.0s` tick for `Team.ENEMY`:

1. **Worker Saturation:** Assign any idle `Team.ENEMY` workers to the nearest `BiomassNode`. If `EconomyManager` can afford a `Worker` and total enemy workers `< 6`, queue one at the enemy `CommandCore`.
2. **Tech & Supply Expansion:**
   * If enemy has no `SilicaRefinery` and can afford one, place and construct it near the enemy `SilicaVein` and train `1` `SilicaHarvester`.
   * If `bandwidth_used >= bandwidth_cap - 2` and enemy can afford a `BandwidthRelay`, build one near the enemy base perimeter.
   * If enemy has no `BioLab` and can afford one, build it along the forward base edge facing the center.
3. **Army Production & Attack Waves:**
   * Continuously queue `enemy_trooper`s at the `BioLab` whenever resources and Bandwidth allow.
   * Once `>= 4` idle combat units are rallied at the enemy base, dispatch them as a coordinated squad:
     * **Wave 1 (and odd waves):** Attack-Move to capture/hold the central **Data Hyper-Uplink**.
     * **Wave 2 (and even waves):** Attack-Move directly toward the player's `CommandCore` location.

## 4. Verification Checklist for `agy`

Before concluding this milestone, verify in `skirmish_arena_01.tscn`:

* [ ] **Arena Layout:** Player base (bottom-left) and Enemy base (top-right) are separated by symmetric terrain obstacles, chokepoints, and the central `Data Hyper-Uplink`, with `NavigationRegion2D` routing units cleanly around all walls.
* [ ] **Fog of War:** Starting map is shrouded except around the Player base; moving a `ScoutUnit` or `TestUnit` across the map permanently clears `UNEXPLORED` shroud to `EXPLORED` fog and reveals `Team.ENEMY` units only while inside active `vision_range`.
* [ ] **Tactical Minimap:** Minimap displays terrain walls, resource nodes, unit blips, Fog of War, and the camera viewport box; Left-Clicking moves the camera and Right-Clicking issues move orders to selected units.
* [ ] **Skirmish AI:** Within the first 1–2 minutes of play, the Enemy AI gathers Biomass, constructs a `BioLab` / `BandwidthRelay`, trains `enemy_trooper`s, and sends a squad to contest the central `HyperUplink` or attack the player base.
* [ ] **Win / Loss Loop:** Destroying the Enemy `CommandCore` (or losing the Player `CommandCore`) triggers the `MatchEndOverlay` with match stats and working **Play Again** restart.