# Milestone 1.0 Plan: Production Queues, Active Combat Loop, Map Objectives & Architecture Refactor

**Target Directory:** `docs/agy_plans/07_production_skirmish_objectives_and_refactor.md`
**Primary Scene:** `res://scenes/test/milestone_0_test.tscn` (and initial symmetric skirmish map `res://scenes/maps/skirmish_arena_01.tscn`)
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/entity_inspection_ui_polish_plan.md`

---

## 1. Objective & Scope

Transition the project from an isolated sandbox into an end-to-end playable **Milestone 1 Vertical Slice** by:
1. **De-bloating core scripts** (`selection_controller.gd`, `unit.gd`, `selection_hud.gd`, `building.gd`) via clean component/router extraction before adding major new systems.
2. **Completing the Build-to-Army Loop** with **Building Production Queues**, resource + **Bandwidth** validation/deduction, and **Rally Points** (including auto-gather rallies for newly trained workers).
3. **Activating Two-Way Combat** so enemy units acquire targets, return fire, destroy player units/buildings, and properly free up **Bandwidth** on unit death.
4. **Introducing Core Match Pacing Objectives** from the GDD: the central **Data Hyper-Uplink** (`+5%` production speed while controlled) and the **Phased Encroaching Zone**.

### Out of Scope
* All 5 asymmetrical faction rosters and full tech trees (keep to 1 playable faction roster + mirror/bot opponent).
* Advanced multi-base macro AI or complex fog-of-war rendering.
* Final bespoke art assets, shaders, or audio mixing.

---

## 2. Phase A: Architecture Hygiene & Script De-Bloating (Do First)

Several core files have grown past 20–39 KB (`selection_controller.gd` ~39.7 KB, `unit.gd` ~36.2 KB, `selection_hud.gd` ~28.5 KB, `building.gd` ~20.9 KB). Extracting focused modules first prevents merge tangles and keeps `agy` edits fast and reliable.

### Refactoring Targets
* **Extract Command Router (`scripts/controllers/command_router.gd`):**
  * Move right-click context resolution (Ground Move, Enemy Attack, Resource Gather, Building Drop-off, Engineer Compute Staffing, Building Rally Point) and `A` / `S` / `H` / `Q` command dispatch out of `selection_controller.gd` into `CommandRouter`.
  * Keep `selection_controller.gd` strictly responsible for pointer hit-testing, drag-box filtering, control groups (`1–9`), subgroup `Tab` cycling, and emitting `selection_changed` / `inspection_changed`.
* **Extract Combat Component (`scripts/units/combat_component.gd`):**
  * Move weapon range checks, attack cooldown timers, target acquisition (`aggro_range`), `HOLD_POSITION` vs. `ATTACK_MOVING` target scanning, and attack tracer spawning out of `unit.gd` into a child `CombatComponent` node (matching the existing `AbilityComponent`, `GatherComponent`, and `StaffComponent` pattern).
* **Extract Production Component (`scripts/buildings/production_component.gd`):**
  * Rather than bloating `building.gd`, attach `ProductionComponent` to buildings capable of training units (`CommandCore`, `Barracks` / `BioLab`), emitting `queue_changed(queue, progress, duration)` and `unit_produced(unit)`.

---

## 3. Phase B: Building Production Queues & Rally Points

### Data Extensions
* **`scripts/data/unit_data.gd`:**
  * Add training cost & timing fields:
    * `@export var biomass_cost: int = 50`
    * `@export var silica_cost: int = 0`
    * `@export var compute_cost: int = 0`
    * `@export var bandwidth_cost: int = 1`
    * `@export var train_time: float = 4.0`
    * `@export var unit_scene: PackedScene`
* **`scripts/data/building_data.gd`:**
  * Add `@export var trainable_units: Array[UnitData] = []` and `@export var can_set_rally: bool = true`.
  * Configure `CommandCore` to train `Worker`, `Engineer`, and `SilicaHarvester`.
  * Create a basic military production building (`scenes/buildings/bio_lab.tscn` + `resources/buildings/bio_lab_data.tres`, constructible by Workers via `[R]` build ability) that trains `TestUnit` (Infantry) and `ScoutUnit`.

### Production Queue Rules (`production_component.gd`)
1. **Queue Cap:** Max `5` queued items per building.
2. **Upfront Reservation:** When a training button is clicked (or hotkey pressed on a selected production building), verify:
   * `EconomyManager.can_afford(team, biomass, silica, compute)`
   * `EconomyManager.has_bandwidth(team, bandwidth_cost)` (or reserve Bandwidth immediately upon queuing so players cannot over-queue past cap).
   * Deduct resources immediately; if the player cancels a queued item in `SelectionHUD`, refund `100%` of its resource cost and release reserved Bandwidth.
3. **Tick & Spawn:** Active front-of-queue item ticks `progress += delta` (multiplied by `1.05` if the team controls the **Data Hyper-Uplink**). When `progress >= train_time`, spawn `unit_scene` at the building's spawn exit marker and issue its rally command.

### Rally Point Behavior (`building.gd` & `command_router.gd`)
* When a friendly building with `can_set_rally == true` is inspected/selected and the player **Right-Clicks**:
  * **On Ground:** Sets `rally_position` and draws a subtle rally line + flag marker while the building is inspected. Newly spawned units execute `command_move(rally_position)` (or `attack_move`).
  * **On a Resource Node (`BiomassNode` / `SilicaVein`):** Sets `rally_target = resource_node`. Newly trained `Worker` or `SilicaHarvester` units immediately begin gathering from that node on spawn.
  * **On a Friendly `ComputeNode`:** Newly trained `Engineer` units automatically walk to and staff that `ComputeNode` if slots are available.

### HUD Integration (`selection_hud.gd`)
* When a production building is inspected:
  * **Command Card:** Displays trainable unit buttons with resource + Bandwidth cost badges and hover tooltips (`command_tooltip.tscn`).
  * **Center Telemetry Panel:** Renders a live **Production Progress Bar** for the active unit plus clickable queue slot icons `[1..5]` (clicking a queued icon cancels and refunds it).

---

## 4. Phase C: Two-Way Combat & Bandwidth Lifecycle

### Active Enemy Units (`scenes/units/enemy_trooper.tscn`)
* Create an active enemy combatant (`Team.ENEMY`) using `Unit` + `CombatComponent` (keeping `target_dummy.tscn` available in the sandbox spawner for DPS testing).
* **Enemy AI States:**
  * `GUARD` / `IDLE`: Automatically scans `aggro_range` for `Team.PLAYER` units or buildings, pursues into `attack_range`, and fires back.
  * `ATTACK_MOVING`: Supports wave/skirmish attack orders toward the player's base or the central Hyper-Uplink.
* **Damage, Death & Bandwidth Cleanup:**
  * Verify that when any `Team.PLAYER` unit is destroyed in combat, `EconomyManager` decrements `bandwidth_used` by `unit_data.bandwidth_cost` and emits `bandwidth_changed` so `ResourceHUD` reflects freed supply immediately.
  * Ensure destroyed buildings (`CommandCore`, `BandwidthRelay`, `ComputeNode`) cleanly unregister their `bandwidth_provided` and eject/clean up any staffed Engineers.

---

## 5. Phase D: Match Pacing Objectives (Hyper-Uplink & Encroaching Zone)

### 1. Central Data Hyper-Uplink (`scenes/world/hyper_uplink.tscn` & `scripts/world/hyper_uplink.gd`)
* Neutral capture point placed at the center of the arena (`capture_radius = 140.0`, `capture_time = 8.0s`).
* **Capture Logic:**
  * Counts nearby `PLAYER` vs. `ENEMY` units inside `capture_radius`.
  * If only one team has units in the ring, progress shifts toward that team (`-1.0` to `+1.0`). If both teams have units inside, progress is **Contested** (paused).
* **Controller Buff:**
  * While controlled by a team, `EconomyManager` grants a **+5% production & research speed multiplier** to that team's buildings and displays an `UPLINK: +5%` badge in `ResourceHUD`.

### 2. Phased Encroaching Zone (`scripts/systems/encroaching_zone.gd`)
* Configurable match timer (e.g., Phase 1 begins at `3:00` for fast sandbox/skirmish testing, shrinking toward the central Hyper-Uplink in 3 timed stages).
* Renders a visible warning perimeter ring on the map and deals periodic disruption/EMP damage (`dps` per tick) to units/structures remaining outside the safe zone, forcing late-game engagements around the center.

---

## 6. Verification Checklist for `agy`

Before concluding this milestone, verify in Godot:
- [ ] **Refactor Integrity:** `selection_controller.gd`, `unit.gd`, and `building.gd` delegate command routing, combat, and production cleanly without breaking existing control groups, `Tab` cycling, or worker gathering.
- [ ] **Production & Refunds:** Selecting `CommandCore` or `BioLab` shows trainable units on the Command Card; queuing units deducts Biomass/Silica/Compute and reserves Bandwidth; canceling a queued unit refunds 100% of resources and frees Bandwidth.
- [ ] **Smart Rally Points:** Right-clicking a `BiomassNode` while inspecting `CommandCore` sets a resource rally; newly trained `Worker`s automatically walk out and start gathering without manual input.
- [ ] **Two-Way Combat & Supply Freeing:** Spawning `enemy_trooper` units results in mutual combat; when player units die, `Bandwidth Used` decreases accurately in `ResourceHUD`.
- [ ] **Map Objectives:** Moving units into the central `Data Hyper-Uplink` captures it (pausing when contested by enemies) and applies the `+5%` production speed bonus; the `Encroaching Zone` displays its boundary and applies damage outside the safe radius when triggered.