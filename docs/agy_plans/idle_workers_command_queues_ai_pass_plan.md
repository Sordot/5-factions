# Milestone 1.4 Plan: Idle Worker Detection, Shift-Click Command Queues & Selection/AI Pass

**Target Directory:** `docs/agy_plans/12_idle_worker_command_queues_and_ai_pass.md`
**Primary Scene:** `res://scenes/maps/skirmish_arena_01.tscn` (and `res://scenes/test/milestone_0_test.tscn`)
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/aggro_ai_toggle_polish_bundle_plan.md`

## 1. Objective & Scope

Perform a targeted gameplay-feel and systems pass across **selection logic**, **multi-step command queuing (`Shift + Right-Click`)**, and **Skirmish AI decision-making**, so players can:

1. **Detect & Select Idle Workers Effortlessly:** Spot idle workers (`Worker` / `Harvester` / `Engineer`) via a live HUD indicator/button and cycle or select them with a single click or hotkey (`F1` / `Tab` or dedicated HUD badge) to immediately assign tasks.

2. **Queue Sequential Commands with `Shift + Right-Click`:** Chain movement waypoints, attack/A-move orders, resource gathering, building construction/staffing, or multi-building waypoints onto any pilotable `Team.PLAYER` unit—enabling customized flanking routes for combat squads and multi-stop routines for workers.

3. **Refine Selection & Skirmish AI Polish:** Clean up selection/command edge cases in `selection_controller.gd` and `command_router.gd`, and make `skirmish_ai.gd` smarter about worker allocation, flanking/objective waves, and not getting stuck on idle or blocked states.

### In Scope

1. **Idle Worker Detection & Selection (`selection_controller.gd`, `unit.gd`, `resource_hud.gd` / `selection_hud.gd`):**

   * Define an explicit `is_idle_worker() -> bool` check on `Unit` (true for `Team.PLAYER` worker units that are alive, not mid-ability/channeling, have no queued commands, and are not actively gathering, constructing, staffing, or moving toward a task).

   * Track live `idle_worker_count: int` and emit `idle_workers_changed(idle_workers: Array[Unit])` from `SelectionController` (or a lightweight world/selection helper).

   * Add an **Idle Worker Badge / Button** (e.g., `Idle Workers: 2 [Space / F1]`—keep `Tab` for subgroup cycling so there is no hotkey collision!) in the HUD that:

     * Shows the count of idle workers and highlights when `> 0`.

     * **Left-Clicking** selects the next idle worker (cycling cleanly through all idle workers across repeated clicks) and optionally pans/focuses the camera onto it if off-screen.

2. **`Shift + Right-Click` Command Queuing for All Pilotable Units (`unit.gd`, `command_router.gd`, `selection_controller.gd`):**

   * Maintain an ordered `command_queue: Array[Dictionary]` on `Unit` alongside `active_command: Dictionary`.

   * **Non-Shift Right-Click (`shift_pressed == false`):** Clears `command_queue` and immediately executes the new order (`MOVE`, `ATTACK_MOVE`, `ATTACK_TARGET`, `GATHER`, `BUILD`, `STAFF`).

   * **Shift + Right-Click (`shift_pressed == true`):**

     * If the unit is currently idle (`active_command.is_empty()` and in `IDLE`), starts executing the new order immediately.

     * If the unit is already busy executing an order, **appends** the new order to `command_queue` without interrupting its current action.

     * When the active order completes (e.g., reaches move destination, finishes building/gathering task, or target dies/is reached), automatically pops and starts the next entry in `command_queue`.

   * **Supported Queued Actions:**

     * **Military / Combat Units:** Queued `MOVE` and `ATTACK_MOVE` waypoints to trace custom flanking routes around terrain obstacles or toward the **Data Hyper-Uplink** / enemy base, plus queued `ATTACK_TARGET` orders.

     * **Workers (`Worker` / `Harvester` / `Engineer`):** Queued `MOVE` orders between placed buildings (e.g., walking from `Nexus Vat` → `Silica Condenser` → `Wetware Mainframe`), queued `GATHER` orders on resource nodes, or queued `BUILD` / `STAFF` actions.

   * **Waypoint Path Preview (`ui/overlays/command_queue_overlay.gd`):** When `Team.PLAYER` units are selected and have a non-empty `command_queue`, draw connected lines and numbered/indexed waypoint markers from the unit's current position through each queued destination so flanking paths and multi-building routes are visually unmistakable.

3. **Selection & Skirmish AI Pass (`selection_controller.gd`, `command_router.gd`, `skirmish_ai.gd`):**

   * **Selection Polish:** Ensure `Shift + Left-Click` cleanly toggles/adds units, `Right-Click` on empty ground or non-actionable targets doesn't accidentally wipe an active `Shift`-queued path unexpectedly, and inspecting a building or resource node remains crisp and predictable.

   * **Skirmish AI Improvements (`skirmish_ai.gd`):**

     * Keep AI workers utilized (re-assigning idle AI workers to nearby `BiomassNode`s or `SilicaVein`s instead of leaving them idle).

     * Improve wave coordination & flanking/objective behavior so AI squads don't stall behind obstacles or get stuck on unreachable targets, while still respecting the `Aggro AI` toggle (`F10` / `SandboxDebugPanel`).

### Out of Scope

* New factions, buildings, or unit types beyond `GENESIS_V2`.

* Complex formation-offset math or multi-player/AI full micro-kiting trees.

* Save/load match state.

## 2. File & Architecture Plan

### New Files to Create

* `ui/overlays/command_queue_overlay.gd`

  * Lightweight world-space `Node2D` rendering polyline segments and small destination rings for selected units' `command_queue` waypoints (color-coded by queued action: cyan for move, amber/red for attack/A-move, emerald for gather/build/staff).

### Existing Files to Extend

* `scripts/units/unit.gd`

  * Add `var command_queue: Array[Dictionary] = []` and helper methods:

    * `issue_command(cmd: Dictionary, append_to_queue: bool = false) -> void`

    * `clear_command_queue() -> void`

    * `_advance_command_queue() -> void` (invoked automatically when the active movement/task/attack step finishes)

    * `is_idle_worker() -> bool`

* `scripts/units/gather_component.gd` & `scripts/units/combat_component.gd`

  * Emit or notify `Unit` when a `MOVE` arrival, `ATTACK_TARGET` completion, or one-shot task completes so `_advance_command_queue()` pops the next queued command cleanly (while continuous loops like `GATHER` keep looping unless a new command is queued after them).

* `scripts/controllers/command_router.gd`

  * Accept `shift_queued: bool = false` on right-click and command dispatch methods (`issue_move_order`, `issue_attack_move_order`, `issue_attack_target_order`, `issue_gather_order`, `issue_build_order`, `issue_staff_order`), forwarding `append_to_queue = shift_queued` to each unit in `selected_units`.

* `scripts/controllers/selection_controller.gd`

  * Detect `shift_pressed` (`event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT` → `event.shift_pressed` or `Input.is_key_pressed(KEY_SHIFT)`) and pass it to `CommandRouter`.

  * Add `select_next_idle_worker(focus_camera: bool = true) -> void` and emit `idle_workers_updated(count: int)` whenever units spawn, die, change state, or start/finish tasks.

  * Bind a dedicated idle-worker shortcut (e.g., `KEY_F1` or `KEY_PERIOD` / HUD button—leaving `KEY_TAB` untouched for subgroup cycling).

* `ui/hud/resource_hud.gd` & `ui/hud/resource_hud.tscn` (or `selection_hud.gd` / `.tscn`)

  * Add a compact **Idle Worker button** (`Idle: N`) that lights up when `N > 0` and triggers `SelectionController.select_next_idle_worker()`.

* `scripts/systems/skirmish_ai.gd`

  * Audit worker assignment, idle-worker recovery, and attack-wave pathing/target selection so AI forces actively harvest, expand, and push toward the **Data Hyper-Uplink** or player base without stalling.

## 3. Detailed Behavior Specifications

### A. Idle Worker Definition & Cycling

1. A unit qualifies as an **Idle Worker** when:

   * `team == Team.PLAYER` and `is_inside_tree()` and `hp > 0`

   * Its `UnitData` is a worker/economy role (e.g., `can_gather` or `can_staff_compute` or `unit_type_id` in `[&"worker", &"silica_harvester", &"engineer"]`)

   * `command_queue.is_empty()` and it is currently in `IDLE` state with no active gather, construction, staff, or move target.

2. Clicking the **Idle Worker** HUD button (or pressing `F1`):

   * Collects all current idle workers sorted deterministically (e.g., by `get_instance_id()`).

   * Cycles to the next idle worker in the list (`_idle_cycle_index = (_idle_cycle_index + 1) % idle_workers.size()`), selects that worker (`selected_units = [worker]`, clears `inspected_entity`), and gently pans `RTSCamera` toward it if outside the current view.

### B. `Shift + Right-Click` Command Queuing Rules

1. **Flanking Route Example (Military Units):**

   * Player selects a squad of `Clone Trooper`s / `Stinger`s.

   * Player `Right-Clicks` near a northern or southern flank lane (starts moving immediately).

   * Player holds `Shift` and `Right-Clicks` a second point behind enemy cover, then `Shift + Right-Clicks` onto an enemy target or `A`-moves into the flank.

   * `CommandQueueOverlay` draws the connected multi-leg path; each unit follows waypoint 1, then waypoint 2, then engages at the final point.

2. **Multi-Building / Task Chain Example (Workers):**

   * Player selects a `Worker` (or `Engineer`).

   * Player `Right-Clicks` a `Silica Condenser` (moves there), holds `Shift` and `Right-Clicks` a `Wetware Mainframe` (queues next stop), and optionally `Shift + Right-Clicks` a `BiomassNode` or `ComputeNode` (queues task after arrival).

   * The worker visits each building in order and executes the final task upon reaching it.

3. **Clearing vs. Appending:**

   * A plain `Right-Click` (without `Shift`) calls `clear_command_queue()` before starting the new order so accidental single right-clicks never leave hidden leftover waypoints.

## 4. Verification Checklist for `agy`

Before concluding this milestone, verify in `skirmish_arena_01.tscn`:

* \[ \] **Idle Worker Detection & Cycling:** When workers finish a task and become idle, the HUD **Idle Worker** button displays the accurate count and lights up; clicking it (or pressing `F1`) selects and cycles through idle workers cleanly.

* \[ \] **Military Flanking via `Shift + Right-Click`:** Selecting combat units, right-clicking a flank waypoint, and `Shift + Right-Click`ing 1–2 additional waypoints renders the queued path preview and moves the units sequentially along the custom flank route.

* \[ \] **Worker Multi-Building Queue via `Shift + Right-Click`:** Selecting a worker and using `Shift + Right-Click` across two placed buildings (and/or a resource node) moves the worker sequentially between them without dropping earlier queued stops.

* \[ \] **Plain Right-Click Reset:** Issuing a normal `Right-Click` (without `Shift`) clears any previously queued waypoints and immediately redirects the unit(s).

* \[ \] **Selection & Skirmish AI Pass:** Selection/inspection transitions work smoothly with no stray orders, and `skirmish_ai.gd` keeps its workers harvesting and sends cohesive waves without getting stuck on obstacles.