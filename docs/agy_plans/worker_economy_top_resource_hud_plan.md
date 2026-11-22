# Milestone 0.8 Plan: Worker Gathering Loop, Command Core & Top Resource HUD

**Target Directory:** `docs/agy_plans/04_worker_economy_and_top_hud.md`
**Primary Scene:** `res://scenes/test/milestone_0_test.tscn`
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/abilities_tab_cycling_and_hud.md`

## 1. Objective & Scope

Begin building the Milestone 1 economy foundation directly inside our playable sandbox by implementing **one resource (Biomass)**, **one Worker unit**, **one drop-off structure (Command Core)**, and a **top-bar Resource HUD** that tracks **Biomass**, **Silica**, **Compute**, and **Bandwidth** (with Silica and Compute displayed at `0` for now so the top HUD layout is future-proof).

Starting with the **Biomass** loop (StarCraft-style direct worker gather → 3.0s harvest timer → shuttle back to nearest Command Core → deposit & repeat) validates the resource manager, building selection/drop-off logic, and top HUD before adding Automated Harvesters (Silica) or staffed vents (Compute).

### In Scope

1. **Central Economy & Resource Manager (`scripts/systems/economy_manager.gd`):**

   * Tracks per-team stockpiles for `biomass`, `silica`, `compute`, and population (`bandwidth_used` / `bandwidth_cap`).

   * Exposes clean methods (`add_resource`, `can_afford`, `spend_resources`, `register_bandwidth_provider`, `update_bandwidth_used`) and signals (`resources_changed`, `bandwidth_changed`) so UI and production never poll state manually.

2. **Top Resource HUD (`ui/hud/resource_hud.tscn` & `.gd`):**

   * Clean Technozen/Y2K top-right (or top-full-width) bar anchored to the viewport showing:

     * **Biomass** count (live-updating as workers deposit)

     * **Silica** count (`0` placeholder, wired to `EconomyManager`)

     * **Compute** count (`0` placeholder, wired to `EconomyManager`)

     * **Bandwidth** (`used / cap`, e.g., `4 / 10`)

3. **Biomass Resource Node (`scenes/world/biomass_node.tscn` & `scripts/world/resource_node.gd`):**

   * Harvestable map deposit with remaining resource pool (e.g., `1500` Biomass), collision body for right-click targeting and navigation avoidance, and visual depletion/highlight state.

4. **Command Core Drop-Off Structure (`scenes/buildings/command_core.tscn` & `scripts/buildings/building.gd`):**

   * Selectable player headquarters building (`Team.PLAYER`) that acts as a **Biomass drop-off point**, provides base **Bandwidth** capacity (e.g., `+10 Bandwidth`), and displays its name/HP in `selection_hud.gd` when clicked.

5. **Worker Unit & 3.0-Second Gathering State Machine (`scenes/units/worker_unit.tscn`, `resources/units/worker_unit_data.tres`):**

   * Worker unit with explicit gathering states (`GATHER_MOVING_TO_NODE`, `GATHERING`, `GATHER_RETURNING_TO_BASE`):

     * **Right-Click on Biomass Node:** Moves into gather range, spends **3.0 seconds** harvesting (`gather_duration = 3.0`), picks up `carry_capacity` (e.g., `10` Biomass) with a visible carried-cargo indicator, automatically paths to the nearest `Team.PLAYER` drop-off building (`Command Core`), deposits into `EconomyManager`, and loops back to the Biomass node automatically.

     * **Right-Click on Command Core while carrying Biomass:** Immediately returns cargo and resumes gathering from its last remembered node.

### Out of Scope (Next Phase)

* Automated Silica Harvesters & Silica Refineries.

* Worker-staffed Compute Facilities over vents.

* Building construction placement previews or worker build menus.

* Unit training queues on the Command Core (will follow right after worker gathering is verified).

## 2. File & Architecture Plan

### New Files to Create

* `scripts/systems/economy_manager.gd` (`class_name EconomyManager extends Node`)

  * Scene-level or autoloaded economy state manager for `milestone_0_test.tscn`.

  * Initializes starting values (e.g., `Biomass: 50`, `Silica: 0`, `Compute: 0`, `Bandwidth: 0 / 10`).

* `scripts/world/resource_node.gd` & `scenes/world/biomass_node.tscn`

  * `ResourceNode` (`StaticBody2D` or `Area2D` + obstacle collider) with `@export var resource_type: StringName = &"biomass"`, `@export var remaining_amount: int = 1500`, and `extract(amount: int) -> int` returning actual harvested yield (and freeing/depleting when `0`).

* `scripts/buildings/building.gd` & `scenes/buildings/command_core.tscn`

  * Base `Building` class (`StaticBody2D`) supporting `team`, `max_hp` / `hp`, `is_resource_dropoff: bool = true`, `accepted_resources: Array[StringName] = [&"biomass"]`, `bandwidth_provided: int = 10`, selection ring/highlight, and basic metadata so `selection_hud.gd` can display selected buildings cleanly.

* `resources/units/worker_unit_data.tres` & `scenes/units/worker_unit.tscn`

  * Worker stats (`unit_type_id = &"worker"`, `is_worker = true`, `gather_duration = 3.0`, `carry_capacity = 10`, `gather_range = 48.0`, `dropoff_range = 64.0`, light melee/laser self-defense or zero attack).

* `ui/hud/resource_hud.tscn` & `ui/hud/resource_hud.gd`

  * Top-anchored `CanvasLayer` UI bar displaying Biomass, Silica, Compute, and Bandwidth with clean styling matching `selection_hud.tscn`.

### Existing Files to Extend

* `scripts/data/unit_data.gd`

  * Add worker capability fields: `@export var can_gather: bool = false`, `@export var gather_duration: float = 3.0`, `@export var carry_capacity: int = 10`, `@export var gather_range: float = 48.0`.

* `scripts/units/unit.gd` (or a dedicated `scripts/units/gather_component.gd` child node to keep `unit.gd` modular)

  * **Recommended:** Create `scripts/units/gather_component.gd` attached to `worker_unit.tscn` so gathering timers, `carried_amount`, `target_node`, and `dropoff_building` stay isolated from combat state logic in `unit.gd`.

  * Any explicit non-gather command (`Move`, `Attack-Move`, `Stop`, `Hold Position`, or `Attack Enemy`) cleanly interrupts the active gather loop.

* `scripts/controllers/selection_controller.gd`

  * **Right-Click Context Routing:**

    * If selected units include workers (`can_gather == true`) and the player right-clicks a `ResourceNode` → issue `command_gather(resource_node)` (with a distinct cyan/green resource marker).

    * If selected workers are currently carrying cargo and the player right-clicks a friendly drop-off `Building` → issue `command_return_cargo(building)`.

  * **Building Selection:** Allow left-clicking a friendly `Building` (when no units are box-selected) to display the `Command Core` info in `selection_hud.gd`.

* `ui/hud/selection_hud.gd`

  * Handle displaying a selected `Building` (name, HP bar, Bandwidth provided) when a building is selected instead of units.

* `scripts/controllers/sandbox_spawner.gd` & `ui/hud/sandbox_debug_panel.tscn`

  * Add a quick sandbox button/hotkey to spawn a `worker_unit` near the Command Core.

* `scenes/test/milestone_0_test.tscn`

  * Place a starting `CommandCore` (`Team.PLAYER`), a cluster of 2–3 `BiomassNode` deposits a short distance away (StarCraft mineral-line spacing), 1–2 starting `worker_unit` instances, `EconomyManager`, and `ResourceHUD`.

## 3. Detailed Behavior Specifications

### A. Worker Gather Cycle (`gather_component.gd`)

1. **`GATHER_MOVING_TO_NODE`:**

   * Worker navigates toward `target_node.global_position` (stopping at `gather_range` outside the node's collision radius).

   * Once within `gather_range`, velocity zeroes out and state transitions to `GATHERING` with `gather_timer = 0.0`.

2. **`GATHERING` (3.0 Seconds):**

   * Increment `gather_timer += delta` while displaying a subtle overhead progress bar or pulsing indicator on the worker.

   * At `gather_timer >= 3.0`, call `target_node.extract(carry_capacity)`, store `carried_amount` and `carried_type`, show a small visual cargo pip on the worker sprite, find the closest friendly `Building` with `is_resource_dropoff == true`, and transition to `GATHER_RETURNING_TO_BASE`.

3. **`GATHER_RETURNING_TO_BASE`:**

   * Worker navigates toward the drop-off building's perimeter (`dropoff_range`).

   * Upon reaching `dropoff_range`, call `economy_manager.add_resource(team, carried_type, carried_amount)`, reset `carried_amount = 0`, hide the cargo pip, and—if `is_instance_valid(target_node)` and `target_node.remaining_amount > 0`—automatically transition back to `GATHER_MOVING_TO_NODE` (or find the nearest non-depleted `BiomassNode` within search radius).

### B. Bandwidth Tracking (`economy_manager.gd`)

* Whenever a `PLAYER` unit spawns or dies, update `bandwidth_used` in `EconomyManager` (e.g., `1` Bandwidth per unit).

* Whenever a `PLAYER` `CommandCore` enters or leaves the scene, update `bandwidth_cap` (`+10` per Command Core).

* `ResourceHUD` listens to `resources_changed` and `bandwidth_changed` signals to update text labels immediately.

## 4. Verification Checklist for `agy`

Before concluding this task, verify in `milestone_0_test.tscn`:

* \[ \] Top `ResourceHUD` renders cleanly without blocking camera pan or overlapping `sandbox_debug_panel.tscn`, displaying initial `Biomass`, `Silica: 0`, `Compute: 0`, and `Bandwidth`.

* \[ \] Right-clicking a `BiomassNode` with one or more `worker_unit`s selected sends them to the node, holds them stationary for **3.0 seconds** while harvesting, displays a carried-cargo visual indicator, walks them back to the `CommandCore`, increments `Biomass` by `10` in the top HUD upon arrival, and automatically sends them back for the next trip.

* \[ \] Issuing a ground `Move` (`Right-Click` ground) or `Stop` (`S`) mid-gather cleanly cancels the gathering loop.

* \[ \] Clicking the `CommandCore` selects it and displays its name, HP, and `+10 Bandwidth` info in the bottom `SelectionHUD`.

* \[ \] Spawning additional units via `sandbox_debug_panel` increments `Bandwidth Used` in the top `ResourceHUD` in real time.