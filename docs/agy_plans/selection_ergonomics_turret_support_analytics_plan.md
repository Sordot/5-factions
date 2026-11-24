# Milestone 2.4 Plan: Selection Ergonomics, Turret Support & Balance Analytics Tools

**Target Directory:** `docs/agy_plans/25_selection_ergonomics_turrets_and_analytics.md`
**Primary New Files:** `scripts/buildings/turret_component.gd`, `scenes/buildings/defense_turret.tscn`, `resources/buildings/defense_turret_data.tres`, `ui/hud/timeline_graph.gd`
**Primary Extended Files:** `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`, `scripts/controllers/sandbox_spawner.gd`, `scripts/data/building_data.gd`, `scripts/buildings/building.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/game_config.gd`, `scripts/systems/economy_manager.gd`, `scripts/systems/fog_of_war.gd`, `scripts/buildings/production_component.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`, `ui/hud/match_end_overlay.tscn`, `ui/hud/match_end_overlay.gd`, `ui/hud/sandbox_debug_panel.tscn`, `ui/hud/sandbox_debug_panel.gd`, `ui/overlays/entity_visuals.gd`
**Reference Docs:** `docs/agy_plans/24_hardening_salvage_los_and_audio_polish.md`, `docs/agy_plans/engine_depth_multi_team_map_2_tools_bundle.md`, `docs/agy_plans/micro_feel_unit_rally_minimap_pings_veterancy_plan.md`

## 1. Objective & Scope

Finalize high-impact **micro ergonomics**, add **reusable defensive turret architecture** for upcoming factions, and equip the project with **empirical balance-testing tools** (Post-Match Timeline Graphs, a rapid Combat Lab unit tester, and Skirmish Lobby Mutators) so Faction #2 can be built and balanced rapidly against `GENESIS_V2`.

### In Scope

1. **Micro & Selection Ergonomics (`SelectionController`, Custom Command Cursors):**
   * **Control Group Stealing (`Alt + 1–9`):** Assigns the current selection to group `N` while stripping those entities out of all other control groups (`1–9`).
   * **Smart Box-Selection Priority & Same-Type Screen Selection:** Drag-selecting over mixed units prioritizes combat units over Workers/Harvesters/Engineers (falling back to economy units only if zero combat units are inside the box); `Ctrl + Left-Click` or rapid double-click on a friendly unit selects all visible friendly units of that exact `unit_id` currently inside the camera viewport.
   * **Tactile Command Cursor States:** Distinct procedural Technozen crosshair cursors for `Attack-Move` (crimson), `Patrol` (cyan/blue), `Repair` (emerald), and `Ability Target` (amber/violet), reverting cleanly on command completion, cancel (`Esc`/RMB), or menu/pause open.

2. **Static Defense / Turret Support (`TurretComponent`):**
   * Build a modular `TurretComponent` that attaches cleanly to any `Building` whose `BuildingData` enables weapon stats—using `SpatialGrid` + `TeamManager.are_enemies()`, weighted threat-priority targeting, explicit right-click focus-fire override, `AttackTracer`/`CombatVFX` firing, and `SettingsManager.attack_range_mode` ring previews.
   * Include a clean test asset (`defense_turret.tscn` / `defense_turret_data.tres`) spawnable via `SandboxDebugPanel` (and ready to be cloned/themed for Faction #2+ static defenses).

3. **Balance & Match Analytics Tools:**
   * **Post-Match Timeline Graphs:** Sample per-team Resource Income, Army Value, and Unit Count every `5.0s` in `MatchManager` and render interactive, color-coded procedural line charts inside `MatchEndOverlay` alongside the existing summary table.
   * **Combat Lab / Unit-Tester Preset (`SandboxDebugPanel` + `SandboxSpawner`):** Add curated 1-click "Squad A vs. Squad B & Fight" test presets plus a **Clear Combatants** button so counter math can be verified in seconds.
   * **Skirmish Lobby Mutators (`MainMenu` + `GameConfig`):** Optional lobby toggles for **High-Yield Economy (2x)**, **No Fog of War**, and **Fast-Build (2x)**.

### Out of Scope
* Stealth/cloaking mechanics or AI wave-staging rewrites.
* Playable rosters for Factions #2–#5.
* Modifying `GENESIS_V2`'s core build order or tech tree (keep `defense_turret.tscn` as a reusable engine building testable in Sandbox / Combat Lab unless explicitly added to a faction later).

---

## 2. Phase A: Micro & Selection Ergonomics

### A.1 Control Group Stealing (`scripts/controllers/selection_controller.gd`)
* Extend the existing `1–9` control group handler:
  * `Ctrl + 1–9`: Overwrite group `N` with current selection (existing behavior).
  * `Shift + 1–9`: Add current selection to group `N` (ensure existing behavior stays intact).
  * **`Alt + 1–9` (Steal & Assign):** Remove all currently selected entities from every other control group (`1..9`), then assign them exclusively to group `N`.
  * **`Alt + Shift + 1–9` (Steal & Append):** Remove selected entities from other groups and append them to group `N`.
* Immediately emit control-group summary updates so the `SelectionHUD` Control Group Ribbon reflects updated counts (and hides any group that just dropped to `0` members).

### A.2 Smart Box-Selection Priority & Same-Type Screen Selection (`scripts/controllers/selection_controller.gd`)
* **Smart Drag-Box Filtering:**
  * When finalizing a drag-box selection across friendly entities:
    * Partition captured friendly units into `combat_units` (non-worker/harvester/engineer combat units) and `utility_units` (`worker_unit`, `silica_harvester`, `engineer_unit`).
    * If `combat_units` is non-empty, select **only** `combat_units` (ignoring workers caught in the drag box).
    * If `combat_units` is empty, select `utility_units`.
    * If no friendly units are inside the box, fall back to selecting friendly buildings inside the box (existing behavior).
  * Holding `Shift` while box-selecting still appends cleanly (applying the same combat-priority rule when adding to an existing combat selection).
* **Screen-Wide Same-Type Selection (`Ctrl + Left-Click` & Double-Click):**
  * When the player `Ctrl + Left-Click`s or double-clicks (`< 0.35s` on the same unit) a friendly unit:
    * Query all living friendly units matching `unit.data.unit_id` whose `global_position` lies inside the active `RTSCamera` visible world rect.
    * Select all matching on-screen units (or append if `Shift` is also held).

### A.3 Tactile Command Cursor States (`scripts/controllers/selection_controller.gd`)
* Generate 4 crisp, lightweight procedural `32×32` Technozen crosshair `ImageTexture` cursors once at startup (hotspot centered at `Vector2(16, 16)`):
  * **`ATTACK_MOVE`:** Sharp crimson reticle (`#FF4D6D`) with four corner brackets.
  * **`PATROL`:** Crisp cyan/azure reticle (`#38BDF8`) with directional ticks.
  * **`REPAIR`:** Bioluminescent emerald reticle (`#34D399`) with inner cross.
  * **`ABILITY_TARGET`:** Luminous amber/violet reticle (`#F59E0B`) with concentric ring.
* Apply via `Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, Vector2(16, 16))` whenever entering a command/targeting mode, and reset (`Input.set_custom_mouse_cursor(null)`) immediately upon issuing the order, canceling with `Esc`/RMB, opening `PauseMenu`/`SettingsMenu`/`TechTreeOverlay`, or exiting the scene tree.

---

## 3. Phase B: Reusable Static Defense / Turret Support (`TurretComponent`)

### B.1 Weapon Exports on `BuildingData` (`scripts/data/building_data.gd`)
Add clean, opt-in weapon fields (defaulting to disabled so existing buildings are completely unaffected):
* `@export var has_turret: bool = false`
* `@export var turret_damage: float = 0.0`
* `@export var turret_attack_interval: float = 1.0`
* `@export var turret_attack_range: float = 260.0`
* `@export var turret_min_range: float = 0.0`
* `@export var turret_splash_radius: float = 0.0`
* `@export var turret_bonus_vs_armored: float = 1.0`
* `@export var turret_tracer_style: StringName = &"pulse"` (`&"pulse"`, `&"rail"`, `&"mortar"`, `&"heavy"`)
* `@export var turret_turn_speed: float = 7.0`

### B.2 Modular `TurretComponent` (`scripts/buildings/turret_component.gd`)
* Attached dynamically by `Building._ready()` whenever `data != null and data.has_turret`.
* **Activation Gate:** Remains dormant while `not building.is_constructed` or while `building.is_salvaging`.
* **SpatialGrid + TeamManager Targeting:**
  * Periodically scans (`0.22s` cadence) via `SpatialGrid.query_units_in_radius(building.global_position, data.turret_attack_range)` and filters using `TeamManager.are_enemies(building.team, candidate.team)`.
  * Uses the same weighted threat-priority scoring as `CombatComponent` (prioritizing hostile combat units in range, respecting `turret_min_range`, and preferring armored targets when `turret_bonus_vs_armored > 1.0`).
  * Supports **Explicit Focus-Fire Override:** Right-clicking an enemy unit/building while a turret building is selected locks `explicit_target` until it dies or leaves `turret_attack_range`.
* **Firing, Rotation & Feedback:**
  * Smoothly rotates `turret_angle: float` toward the active target; fires when aligned and `cooldown <= 0.0`.
  * Deals damage (passing `building` as `attacker` for telemetry), spawns `AttackTracer` / `CombatVFX` (including splash telegraphs if `turret_splash_radius > 0`), and plays throttled weapon SFX via `AudioManager`.
* **Visuals & Range Ring (`building.gd`, `entity_visuals.gd`, `selection_hud.gd`):**
  * Draw a rotating Technozen turret mount/barrel atop `has_turret` buildings oriented by `turret_angle`.
  * Respect `SettingsManager.attack_range_mode` (`Always Show` / `Show While Targeting` / `Don't Show`) to render the turret's dashed `turret_attack_range` ring when selected.
  * Show turret `DMG / RNG` stats in `SelectionHUD`'s building inspector card.

### B.3 Reusable Verification Asset (`scenes/buildings/defense_turret.tscn` & `resources/buildings/defense_turret_data.tres`)
* Create a clean, neutral/reusable **Sentry Pylon (`defense_turret`)** (`350 HP`, armored, `18 DMG`, `0.85s` interval, `280px` range, `1.35x` vs armored) so `TurretComponent` can be spawned and stress-tested immediately in `SandboxDebugPanel` and the **Combat Lab**, and serves as the blueprint for Faction #2's static defenses.

---

## 4. Phase C: Balance & Match Analytics Tools

### C.1 Post-Match Timeline Graphs (`scripts/systems/match_manager.gd`, `ui/hud/timeline_graph.gd`, `ui/hud/match_end_overlay.tscn/.gd`)
* **Periodic Telemetry Sampler (`MatchManager`):**
  * Every `5.0` match seconds (plus one final snapshot at match end), append a lightweight sample entry to `timeline_samples: Array[Dictionary]`:
    * `time: float`
    * Per active `team_id`:
      * `income_rate: float` (combined Biomass + Silica + Compute `/min` from `EconomyManager`)
      * `army_value: int` (sum of living combat units' total resource cost for that team)
      * `unit_count: int` (living unit count for that team)
  * Reset `timeline_samples` cleanly on new match / restart.
* **Procedural Chart Widget (`ui/hud/timeline_graph.gd`):**
  * Lightweight `Control` using `_draw()` to render crisp Technozen gridlines, time axis ticks (`0:00`, `2:00`, `4:00`...), Y-axis peak labels, and smooth anti-aliased polylines colored by `TeamManager.get_team_color(team_id)`.
  * Supports toggling between three metrics via compact pill buttons: **`Army Value`**, **`Resource Income`**, and **`Unit Count`**.
* **`MatchEndOverlay` Integration (`1280×720` Safe):**
  * Add a clean two-tab switcher at the top of the modal body: **`[ Summary Table ]`** | **`[ Timeline Graphs ]`**, keeping the modal centered and completely unclipped in both Windowed `1280×720` and Fullscreen modes.

### C.2 Combat Lab / Unit-Tester Preset (`ui/hud/sandbox_debug_panel.tscn/.gd`, `scripts/controllers/sandbox_spawner.gd`)
* Add a collapsible **"Combat Lab"** section inside `SandboxDebugPanel` (visible in `milestone_0_test.tscn` and skirmish maps when debug panel is open):
  * **Preset Selector (`OptionButton`):**
    1. `Clone Squad (8) vs. Stingers (8)`
    2. `Lance-Rigs (5) vs. Goliath Frames (2)`
    3. `Mortar Siege (3) vs. Turret Line (2) + Clones (6)`
    4. `Mixed Heavy Clash (Goliath + Arc-Lancer + Symbiote Mirror)`
  * **`Spawn & Fight` Button:** Spawns Team `0` squad on the left and Team `1` squad on the right of the current camera center (with clear spacing), immediately issuing opposing `Attack-Move` orders toward the center point so the test engagement begins instantly.
  * **`Clear Combatants` Button:** Removes spawned combat test units/turrets in the lab area cleanly (without destroying main `Nexus Vat`s or breaking match victory checks) so you can iterate back-to-back in seconds.
  * Also add a direct **`Spawn Sentry Pylon (Turret)`** button to `SandboxDebugPanel` for testing `TurretComponent` placement and focus-fire.

### C.3 Skirmish Lobby Mutators (`scripts/systems/game_config.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`)
* Add mutator flags to `GameConfig`:
  * `var mutator_high_yield: bool = false` (*High-Yield Economy — 2x Biomass, Silica, and Compute gather/generation rates*)
  * `var mutator_no_fog: bool = false` (*No Fog of War — full map visibility from second 0*)
  * `var mutator_fast_build: bool = false` (*Fast-Build — 2x construction speed, unit training speed, and upgrade research speed*)
* **System Wiring:**
  * `EconomyManager` / `GatherComponent` / `Building` (Compute tick): apply `2.0x` yield multiplier when `GameConfig.mutator_high_yield` is enabled.
  * `FogOfWar`: reveal full arena continuously when `GameConfig.mutator_no_fog` is enabled.
  * `Building` (construction progress), `ProductionComponent` (unit training), and `UpgradeManager` (research timer): apply `2.0x` progress speed when `GameConfig.mutator_fast_build` is enabled.
* **Main Menu UI (`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`):**
  * Add a compact **Mutators** row (3 clean Technozen checkboxes: `2x Yield`, `No Fog`, `Fast Build`) inside the Skirmish Match Setup panel, ensuring zero vertical overflow at `1280×720` and Fullscreen.
  * Display active mutator tags concisely in `MatchEndOverlay` (e.g., `MUTATORS: 2x YIELD • FAST BUILD`) so balance screenshots always record the exact match conditions.

---

## 5. File & Architecture Summary

### New Files to Create
* `scripts/buildings/turret_component.gd` (Reusable structure weapon/targeting/firing component powered by `SpatialGrid` and `TeamManager`)
* `scenes/buildings/defense_turret.tscn` & `resources/buildings/defense_turret_data.tres` (Verification/blueprint static defense structure)
* `ui/hud/timeline_graph.gd` (Procedural Technozen multi-team line chart `Control` for `MatchEndOverlay`)

### Existing Files to Extend
* `scripts/controllers/selection_controller.gd` (`Alt + 1–9` group stealing, smart combat-priority drag-box, `Ctrl + Click` / double-click screen same-type selection, and procedural custom command cursors)
* `scripts/controllers/command_router.gd` (Right-click explicit focus-fire routing for selected turret buildings)
* `scripts/data/building_data.gd`, `scripts/buildings/building.gd`, `ui/overlays/entity_visuals.gd`, `ui/hud/selection_hud.gd` (`TurretComponent` attachment, barrel rendering, range ring preview, and turret stats in inspector)
* `scripts/systems/match_manager.gd`, `ui/hud/match_end_overlay.tscn`, `ui/hud/match_end_overlay.gd` (5-second timeline sampling + Summary/Timeline tab switcher + active mutator tags)
* `scripts/controllers/sandbox_spawner.gd`, `ui/hud/sandbox_debug_panel.tscn`, `ui/hud/sandbox_debug_panel.gd` (Combat Lab presets, `Spawn & Fight`, `Clear Combatants`, and `Spawn Sentry Pylon`)
* `scripts/systems/game_config.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`, `scripts/systems/economy_manager.gd`, `scripts/units/gather_component.gd`, `scripts/buildings/production_component.gd`, `scripts/systems/upgrade_manager.gd`, `scripts/systems/fog_of_war.gd` (Skirmish Lobby Mutators)

---

## 6. Verification Checklist for `agy`

Before concluding Milestone 2.4, verify in Godot (Windowed `1280×720` and Fullscreen `F11`):

* [ ] **Control Group Stealing (`Alt + 1–9`):** Put 6 units in Group `1`, select 2 of them, and press `Alt + 2`; confirm Group `1` now has `4` units, Group `2` has `2` units, and the `SelectionHUD` Control Group Ribbon updates immediately.
* [ ] **Smart Box-Selection & Same-Type Selection:** Drag a box over mixed Workers and Clone Troopers and verify only Clone Troopers are selected; drag a box over only Workers and verify Workers are selected; `Ctrl + Click` (and double-click) a Clone Trooper and verify all visible friendly Clone Troopers on screen are selected.
* [ ] **Command Cursor States:** Press `A` (`Attack-Move`), `P` (`Patrol`), trigger an ability target, and hover/initiate `Repair`; verify crisp tinted Technozen crosshair cursors appear and cleanly revert to the default arrow on click, `Esc`, RMB, or `PauseMenu`.
* [ ] **Static Defense / `TurretComponent`:** Spawn a **Sentry Pylon (`defense_turret`)** via `SandboxDebugPanel`, send enemy units into range, and verify smooth barrel tracking, threat-priority firing, explicit right-click focus-fire override, `SettingsManager.attack_range_mode` ring display, and zero errors when destroyed.
* [ ] **Post-Match Timeline Graphs:** Run a quick skirmish or `2x` **AI vs AI (Spectator)** match to completion; switch to the **Timeline Graphs** tab in `MatchEndOverlay` and confirm `Army Value`, `Resource Income`, and `Unit Count` polylines render cleanly for both teams with zero UI clipping.
* [ ] **Combat Lab & Lobby Mutators:** Test all 4 **Combat Lab** presets (`Spawn & Fight` + `Clear Combatants`) in `SandboxDebugPanel`; then launch a skirmish from `MainMenu` with **2x Yield**, **No Fog**, and **Fast Build** enabled and confirm each mutator works cleanly and displays in `MatchEndOverlay` with zero Godot Debugger errors.