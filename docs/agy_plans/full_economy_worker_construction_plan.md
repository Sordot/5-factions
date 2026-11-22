# Milestone 0.9 Plan: Complete 3-Resource Economy (Silica & Compute), Bandwidth Structures & Worker Build-Abilities

**Target Directory:** `docs/agy_plans/05_full_economy_and_worker_construction.md`
**Primary Scene:** `res://scenes/test/milestone_0_test.tscn`
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/worker_economy_top_resource_hud_plan.md`

## 1. Objective & Scope

Complete the full three-resource economy loop (**Biomass**, **Silica**, **Compute**) plus **Bandwidth** expansion, and implement **worker construction as data-driven build abilities** on the Command Card (mirroring how combat units trigger targeted abilities).

### In Scope

1. **Worker Build-Abilities (Command Card Construction):**
   * Treat building placement as a specialized ability category (`AbilityData` / `BuildAbilityData`) on `worker_unit` (`Q`, `W`, `E` hotkeys) so selecting a worker populates the Command Card with build slots, costs, tooltips, and ghost-footprint placement previews.
   * Selecting a build slot enters **Build Placement Mode** with a translucent building footprint ghost that snaps/validates placement (checks `EconomyManager.can_afford(...)`, clear terrain/building overlap, and vent proximity for Compute facilities).
   * Confirming placement (`Left-Click`) spends resources, spawns the building scaffold (or constructs it after the worker walks into build range and completes a build timer), and returns cleanly to normal selection.

2. **Three Core Economic & Population Structures (Placeholder Technozen Names):**
   * **Silica Refinery (`silica_refinery.tscn`):** Drop-off facility for **Silica**; can optionally spawn or pair with an **Automated Silica Harvester** (`silica_harvester.tscn`) that autonomously shuttles between nearby `SilicaVein` nodes and the Refinery without requiring manual micromanagement once assigned or spawned.
   * **Compute Node (`compute_node.tscn`):** Specialized processing facility built directly over (or adjacent to) a **Thermal/Data Vent** (`compute_vent.tscn`). Generates **Compute** when staffed by **Engineer** units (`engineer_unit.tscn`) stationed inside/at the facility.
   * **Bandwidth Relay (`bandwidth_relay.tscn`):** Lightweight infrastructure pylon/node that increases the player's **Bandwidth** cap (e.g., `+8 Bandwidth` per Relay) and displays live cap updates in `ResourceHUD`.

3. **Silica Harvester & Engineer Units:**
   * **Automated Silica Harvester (`silica_harvester.tscn`):** Vehicle/drone unit (`unit_type_id = &"silica_harvester"`) that automatically locates the nearest `SilicaVein`, harvests Silica (`gather_duration = 3.5s`, `carry_capacity = 25`), returns to the nearest `SilicaRefinery`, deposits into `EconomyManager`, and loops indefinitely.
   * **Engineer (`engineer_unit.tscn`):** Specialist unit (`unit_type_id = &"engineer"`) that can be right-clicked onto a friendly `ComputeNode` to garrison/staff it (up to e.g. `2` Engineers per Compute Node), ticking steady **Compute** income (`+5 Compute` every `3.0s` per assigned Engineer) with a clear staffed-slot indicator on the building.

4. **Command Core Basic Unit Training (Optional/Lightweight Queue or Sandbox + Core):**
   * Allow the `CommandCore` (or `SilicaRefinery`) to train `Worker`, `Engineer`, and `SilicaHarvester` units using **Biomass / Silica** and **Bandwidth** checks (`can_afford` + `has_bandwidth`), while keeping `sandbox_debug_panel.gd` available for instant zero-cost testing.

### Out of Scope

* Military production buildings (Barracks/Mech Bay) and tech-tree unlocks (next milestone).
* Multi-worker repair/assist on a single building in progress.
* Faction-specific visual variants across all 5 AI Lords.

## 2. File & Architecture Plan

### New Data & Resource Files

* `scripts/data/building_data.gd` (`class_name BuildingData extends Resource`)
  * Exports: `building_id: StringName`, `display_name: String`, `scene: PackedScene`, `biomass_cost: int`, `silica_cost: int`, `compute_cost: int`, `build_time: float`, `footprint_size: Vector2`, `max_hp: float`, `bandwidth_provided: int`, `is_dropoff: bool`, `accepted_resources: Array[StringName]`, `requires_vent: bool`, `max_staff_slots: int`.
* `resources/buildings/silica_refinery_data.tres` (`100 Biomass`, `build_time = 4.0s`, `accepted_resources = [&"silica"]`)
* `resources/buildings/compute_node_data.tres` (`100 Biomass, 50 Silica`, `build_time = 5.0s`, `requires_vent = true`, `max_staff_slots = 2`)
* `resources/buildings/bandwidth_relay_data.tres` (`75 Biomass`, `build_time = 3.0s`, `bandwidth_provided = 8`)
* `resources/abilities/build_silica_refinery.tres` (`Hotkey: Q`), `resources/abilities/build_compute_node.tres` (`Hotkey: W`), `resources/abilities/build_bandwidth_relay.tres` (`Hotkey: E`)
  * Extend `AbilityData` (or add `@export var build_building_data: BuildingData`) so `selection_hud.gd` renders worker build buttons using the exact same Command Card slot pipeline as unit abilities!
* `resources/units/silica_harvester_data.tres` (`can_gather = true`, `allowed_resource = &"silica"`, `auto_gather_on_spawn = true`, `carry_capacity = 25`, `gather_duration = 3.5`)
* `resources/units/engineer_data.tres` (`unit_type_id = &"engineer"`, `can_staff_compute = true`)

### New Scenes & Scripts

* `scenes/world/silica_vein.tscn` & `scenes/world/compute_vent.tscn` (reusing `ResourceNode` with `resource_type = &"silica"` and `resource_type = &"compute"`).
* `scenes/buildings/silica_refinery.tscn`, `scenes/buildings/compute_node.tscn`, `scenes/buildings/bandwidth_relay.tscn`
  * All inherit/use `scripts/buildings/building.gd` (extended to support construction progress `under_construction` state, `ComputeNode` engineer staffing slots & passive tick generation, and `SilicaRefinery` drop-off).
* `scenes/units/silica_harvester.tscn` & `scenes/units/engineer_unit.tscn`
  * `silica_harvester.tscn` uses `GatherComponent` configured for `&"silica"` and auto-starts harvesting the nearest `SilicaVein` on `_ready()`.
  * `engineer_unit.tscn` includes a lightweight `staff_component.gd` (or method on `GatherComponent` / `Unit`) to walk to a `ComputeNode`, enter/attach to a staffing slot, and contribute to periodic Compute generation (with an "Unstaff / Eject" button on the `ComputeNode` Command Card).
* `ui/overlays/build_ghost_preview.gd`
  * World-space placement ghost rendered while a worker build ability is active: draws building footprint rectangle, green/cyan tint when valid (`can_afford` + no collision overlap + snapped to `ComputeVent` if `requires_vent`), red tint when invalid, and cost/requirement tooltip text near the cursor.

### Existing Files to Extend

* `scripts/data/ability_data.gd`
  * Add `TargetType.BUILD_PLACEMENT` and `@export var building_to_build: BuildingData`.
* `scripts/controllers/selection_controller.gd`
  * Support `BUILD_PLACEMENT` targeting mode when a worker's `Q`/`W`/`E` build ability is triggered:
    * Updates `BuildGhostPreview` position & validity every frame.
    * On `Left-Click` (if valid): deducts resources via `EconomyManager.spend_resources(...)`, spawns the building in `under_construction` state (or immediately if `build_time <= 0`), and commands the closest selected worker to move to the site and construct it.
    * On `Right-Click` or `Esc`: cancels `BUILD_PLACEMENT` mode cleanly.
  * Route right-click from selected `Engineer` units onto a friendly `ComputeNode` → `command_staff_building(compute_node)`.
  * Route right-click from selected `SilicaHarvester` units onto a `SilicaVein` or `SilicaRefinery` → gather/return loop.
* `scripts/buildings/building.gd`
  * Add construction progress (`is_constructed: bool`, `construction_progress: float`), Bandwidth registration only once construction completes, and `ComputeNode` staffing slots (`assigned_engineers: Array[Unit]`, `compute_tick_interval = 3.0`, `compute_per_engineer = 5`).
* `ui/hud/selection_hud.gd`
  * Display resource costs (`[Q] Silica Refinery (100B)`, `[W] Compute Node (100B / 50S)`, `[E] Bandwidth Relay (75B)`) on worker Command Card buttons, graying out buttons if the player cannot afford the cost.
  * When a `ComputeNode` is selected, show assigned Engineer slots (`Engineers: 1 / 2`) and an `Eject Engineers` command button.
* `scenes/test/milestone_0_test.tscn` & `scripts/controllers/sandbox_spawner.gd`
  * Place a `SilicaVein` cluster and 1–2 `ComputeVent` geysers on the test map, plus sandbox spawn buttons for `Silica Harvester` and `Engineer` so every resource loop can be tested both organically (via worker construction) and instantaneously (via debug spawn).

## 3. Detailed Behavior Specifications

### A. Worker Build-Ability Flow
1. Player selects one or more `worker_unit`s; `SelectionHUD` reads `worker_unit_data.abilities` (`build_silica_refinery`, `build_compute_node`, `build_bandwidth_relay`) and displays them on the Command Card.
2. Player presses `Q`, `W`, or `E` (or clicks the Command Card button):
   * `SelectionController` enters `BUILD_PLACEMENT` mode and activates `BuildGhostPreview` with the chosen `BuildingData`.
   * If `building_data.requires_vent` is true (`ComputeNode`), `BuildGhostPreview` checks for an unoccupied `ComputeVent` within snap radius (`64px`) and snaps onto the vent center; if no unoccupied vent is near the cursor, the ghost turns red (`"Must be built on a Compute Vent"`).
3. On `Left-Click` when placement is valid:
   * `EconomyManager` checks `can_afford(biomass_cost, silica_cost, compute_cost)` and deducts resources.
   * Building instantiates at the target location at `10%` HP in `under_construction` state; the nearest selected worker moves within build range and channels construction until `construction_progress >= build_time`, at which point the building reaches `100%` HP, registers its Bandwidth/drop-off/staffing functionality, and the worker becomes `IDLE`.

### B. Automated Silica Harvester Loop
* Unlike manual Biomass workers, a `SilicaHarvester` automatically scans for the closest non-depleted `SilicaVein` upon spawning (or after finishing a manual move order), harvests for `3.5s`, delivers `25` Silica to the nearest constructed `SilicaRefinery`, and repeats continuously without player intervention.

### C. Engineer & Compute Node Staffing Loop
* Right-clicking an `Engineer` onto a constructed friendly `ComputeNode` with open slots (`assigned_engineers.size() < max_staff_slots`) orders the Engineer to walk to the node.
* Upon arrival, the Engineer enters the node (hidden or docked at a visible terminal slot on the building sprite, removed from active map collision while staffed) and generates `+5 Compute` every `3.0s` directly into `EconomyManager`.
* Clicking `Eject Engineers` on the `ComputeNode`'s Command Card releases staffed Engineers back around the building perimeter.

## 4. Verification Checklist for `agy`

Before concluding this task, verify in `milestone_0_test.tscn`:

* \[ \] Selecting a `worker_unit` displays `[Q] Silica Refinery`, `[W] Compute Node`, and `[E] Bandwidth Relay` with resource costs on the Command Card.
* \[ \] Pressing `E` shows the `Bandwidth Relay` placement ghost; left-clicking deducts `75 Biomass`, sends the worker to construct the Relay, and increases `Bandwidth Cap` by `+8` in the top `ResourceHUD` upon completion.
* \[ \] Constructing a `Silica Refinery` near a `Silica Vein` and spawning/ordering a `Silica Harvester` results in an automated harvest-and-deposit loop that increments `Silica` in the top HUD.
* \[ \] Pressing `W` (`Compute Node`) snaps the placement ghost onto a `Compute Vent` (and blocks placement off-vent); once built, right-clicking 1–2 `Engineer` units onto the `Compute Node` staffs them inside and steadily ticks `Compute` upward in the top HUD.
* \[ \] Pressing `Right-Click` or `Esc` during `BUILD_PLACEMENT` cancels placement without spending resources.