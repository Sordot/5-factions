# Milestone 0.10 Plan: Unified Entity Inspection & Technozen UI Polish

**Target Directory:** `docs/agy_plans/06_entity_inspection_and_ui_polish.md`
**Primary Scene:** `res://scenes/test/milestone_0_test.tscn`
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/full_economy_worker_construction_plan.md`

## 1. Objective & Scope

Bring StarCraft-style **single-click informational inspection** and **bottom-HUD clarity** to every interactive entity in the world—friendly units, enemy units/dummies, buildings (`CommandCore`, `SilicaRefinery`, `ComputeNode`, `BandwidthRelay`), and resource deposits (`BiomassNode`, `SilicaVein`, `ComputeVent`)—while keeping drag-box selection strictly reserved for commandable player units.

> **Architectural Guardrail:** `selection_controller.gd` (~35.3 KB), `unit.gd` (~31.8 KB), and `selection_hud.gd` (~23.0 KB) have grown significantly across recent milestones. Rather than writing `if/else` type-checking branches inside `selection_hud.gd` or `selection_controller.gd`, introduce a **standardized inspection contract** (`get_inspection_data() -> Dictionary` or lightweight `InspectableData` adapter) so any entity in the game exposes its title, subtitle/category, health/capacity bars, dynamic status lines, and optional Command Card actions cleanly.

### In Scope

1. **Strict Separation of "Selection" vs. "Inspection":**

   * **Drag-Box Selection:** Selects **only** `Team.PLAYER` mobile units (`Unit` nodes). Never sweeps up buildings, resource nodes, vents, or enemy units.

   * **Single Left-Click Selection / Inspection:**

     * Clicking a `Team.PLAYER` unit selects it (and `Shift`-clicking adds/removes it from the active unit selection, `Double-Clicking` selects all visible units of the same `unit_type_id`).

     * Clicking a **non-unit or non-player entity**—a friendly `Building`, an `ENEMY` unit/dummy, or a `ResourceNode` (`BiomassNode`, `SilicaVein`, `ComputeVent`)—clears the unit selection and sets it as the **Inspected Entity** (`inspected_entity`), displaying a distinct **neutral/informational selection ring** (e.g., yellow/amber for neutral resources, red for enemies, cyan/teal for friendly buildings) and populating the bottom HUD.

2. **Standardized Entity Inspection Interface (`get_inspection_data()`):**

   * Implement a uniform inspection payload method across `Unit`, `Building`, and `ResourceNode` so `selection_hud.gd` renders any inspected entity consistently without coupling to entity internals:

     * **Resource Nodes (`BiomassNode`, `SilicaVein`):** Resource Name, Type badge (`BIOMASS DEPOSIT` / `SILICA VEIN`), Remaining Capacity bar + numeric readout (`1,240 / 1,500`), depletion percentage, and active gatherer count if tracked.

     * **Compute Vent (`ComputeVent`):** Vent Name (`THERMAL DATA VENT`), Status (`UNOCCUPIED — Ready for Compute Node` vs. `CAPPED — Occupied by Compute Node`), and yield rate info.

     * **Buildings (`CommandCore`, `SilicaRefinery`, `ComputeNode`, `BandwidthRelay`):**

       * Under-construction state: Construction progress bar (`62% — Under Construction`), current/max HP, and builder status.

       * Completed state: Building Name, HP bar, role-specific telemetry:

         * `CommandCore`: Drop-off types (`Biomass`), Bandwidth provided (`+10`).

         * `SilicaRefinery`: Drop-off types (`Silica`), active/linked harvester status.

         * `ComputeNode`: **Staffed Engineer slots** (`1 / 2 Engineers Staffed`), live **Compute generation rate** (`+5 Compute / 3.0s` or `+10 Compute / 3.0s`), and **remaining vent/node capacity** (if finite) or active vent telemetry, plus the `[Eject Engineers]` Command Card button.

         * `BandwidthRelay`: Bandwidth provided (`+8 Bandwidth`), total network status.

     * **Enemy Units / Target Dummies (`Team.ENEMY`):** Unit Name, `HOSTILE` badge, current/max HP bar, attack damage, and armor/speed stats—with **no Command Card buttons** (read-only inspection).

3. **Live HUD Refresh for Inspected Entities:**

   * Connect entity state-change signals (`hp_changed`, `amount_changed` on `ResourceNode`, `construction_progressed` / `staff_changed` on `Building`) to `SelectionHUD` so watching a worker mine a `BiomassNode` or an `Engineer` generate Compute in a `ComputeNode` updates the bottom HUD numbers and progress bars in real time without needing to re-click.

4. **Shared Technozen / Y2K UI Theme & Visual Polish (`resources/themes/technozen_theme.tres`):**

   * Populate the currently empty `resources/themes/` directory with a reusable Godot `Theme` resource (`StyleBoxFlat` panels with crisp `1px` cyan/slate borders, subtle dark translucent backgrounds, monospace/clean numeric typography, consistent hover/pressed/disabled button states, and custom progress bar fills).

   * Apply the theme consistently across `SelectionHUD`, `ResourceHUD`, and `SandboxDebugPanel` so the entire interface looks cohesive rather than default Godot gray controls.

   * Add **Command Card hover tooltips** (showing ability/building name, resource cost, cooldown, and description) and **control group pills** (`[1]`, `[2]`, etc.) docked cleanly above `SelectionHUD`.

### Out of Scope

* Minimap rendering or fog-of-war shrouded entity memory.

* Production queue progress bars for multi-unit training queues (keep focus on inspection, telemetry, and UI polish).

* Custom sound effects or animated 3D portraits.

## 2. File & Architecture Plan

### New Files to Create

* `resources/themes/technozen_theme.tres`

  * Shared Godot `Theme` defining dark obsidian/slate panels (`#0D1117` at ~90% alpha), `1px` Technozen cyan/teal borders (`#00E5FF` / `#2A3B4C`), styled `Button` states (Normal, Hover, Pressed, Disabled), and `ProgressBar` background/fill styles.

* `scripts/controllers/inspection_helper.gd` (`class_name InspectionHelper`)

  * Static helper/adapter that queries `entity.get_inspection_data()` (with safe fallbacks) and standardizes the dictionary schema (`title`, `subtitle`, `affiliation`, `ring_color`, `hp_current`, `hp_max`, `primary_bar_label`, `primary_bar_value`, `primary_bar_max`, `stats: Array[Dictionary]`, `status_lines: Array[String]`, `is_commandable: bool`).

* `ui/hud/command_tooltip.tscn` & `ui/hud/command_tooltip.gd`

  * Lightweight floating tooltip panel anchored cleanly above the Command Card when hovering over any ability, build action, or standard command button (displaying Name, Hotkey, Resource Costs, Cooldown, and Description).

### Existing Files to Extend

* `scripts/world/resource_node.gd`

  * Add `signal amount_changed(remaining: int, max_amount: int)` emitted whenever `extract()` reduces `remaining_amount`.

  * Store `@export var max_amount: int = 1500` alongside `remaining_amount` so percentage and capacity bars (`1,150 / 1,500`) render accurately.

  * Add selection/inspection ring visual (`set_inspected(active: bool)`) and `get_inspection_data() -> Dictionary` returning remaining capacity, resource type, and depletion status (or vent availability for `ComputeVent`).

* `scripts/buildings/building.gd`

  * Add signals `status_changed` (emitted on HP change, construction progress tick, or engineer staffing change) so `SelectionHUD` updates live while inspecting a building.

  * Add `get_inspection_data() -> Dictionary` exposing HP, construction progress, Bandwidth contribution, drop-off resource types, and—for `ComputeNode`—staffed Engineer count (`assigned_engineers.size() / max_staff_slots`), active Compute output per tick, and underlying `ComputeVent` status/capacity.

* `scripts/units/unit.gd`

  * Add `get_inspection_data() -> Dictionary` exposing unit name, team affiliation (`PLAYER` vs. `ENEMY`), HP, attack damage, range, speed, and active state/cargo (e.g., `"Carrying: 10 Biomass"` on workers or `"Carrying: 25 Silica"` on harvesters).

* `scripts/controllers/selection_controller.gd`

  * Add `var inspected_entity: Node = null` and `signal inspection_changed(entity: Node)`.

  * Enforce selection rules:

    * **Drag-box (`_finish_box_select`):** Queries `Team.PLAYER` `Unit`s only. Clears `inspected_entity` if >= 1 player unit is boxed.

    * **Single Left-Click (`_handle_single_click`):**

      1. Check for `Team.PLAYER` `Unit` under cursor → select unit(s), clear `inspected_entity`.

      2. Else check for friendly `Building`, `ENEMY` `Unit`, or `ResourceNode` under cursor → clear `selected_units`, set `inspected_entity = hit_entity`, toggle its inspection ring, and emit `inspection_changed(inspected_entity)`.

      3. Else (clicked empty ground) → clear both `selected_units` and `inspected_entity`.

* `ui/hud/selection_hud.gd` & `ui/hud/selection_hud.tscn`

  * Subscribe to `SelectionController.inspection_changed` and connect dynamically to the active `inspected_entity`'s update signal (`status_changed` / `amount_changed` / `hp_changed`), disconnecting cleanly when selection changes.

  * Render a clean 3-column layout:

    1. **Left Column (Entity Identity & Vitals):** Entity icon/color badge, Name, Affiliation/Type subtitle (`FRIENDLY STRUCTURE`, `HOSTILE UNIT`, `RESOURCE DEPOSIT`), HP bar, and—when inspecting a `ResourceNode` or `ComputeNode`—a dedicated **Capacity / Staffing Gauge** (`Remaining: 1,250 / 1,500` or `Staffed: 2 / 2 Engineers`).

    2. **Center Column (Squad Grid / Detailed Telemetry):**

       * When multiple player units are selected: Subgroup pills (`Tab` indicator) + individual unit health mini-cards.

       * When a single unit, building, or resource node is inspected: Structured 2-column key-value readout (e.g., `Damage`, `Range`, `Speed`, `Cargo`, `Output Rate`, `Bandwidth`, `Remaining Yield`).

    3. **Right Column (Command Card):**

       * Populated for `Team.PLAYER` units and commandable player buildings (`CommandCore`, `ComputeNode` with `[Eject Engineers]`).

       * Cleared/dimmed with a clean `"READ-ONLY TELEMETRY"` status label when inspecting `ENEMY` units or neutral `ResourceNode`s.

  * Integrate `CommandTooltip` on button `mouse_entered` / `mouse_exited`.

* `ui/hud/resource_hud.tscn` & `ui/hud/sandbox_debug_panel.tscn`

  * Apply `resources/themes/technozen_theme.tres` and refine spacing/color coding (e.g., green accent for Biomass, amber/orange for Silica, cyan for Compute, violet/white for Bandwidth) so resource types are scannable at a glance.

## 3. Detailed Behavior Specifications

### A. Click & Drag Priority Rules (`selection_controller.gd`)

1. **Drag-Box Threshold (`drag_distance >= 8px`):**

   * Always filters exclusively for `Unit` nodes where `unit.team == Team.PLAYER`.

   * Never selects buildings, target dummies, or resource nodes, even if the drag box overlaps them.

2. **Single Left-Click (`drag_distance < 8px`):**

   * Priority order at cursor point:

     1. `Team.PLAYER` `Unit` (supports `Shift+Click` toggle and `Double-Click` type-select).

     2. `Team.PLAYER` `Building` (sets `inspected_entity`, shows teal selection ring + building commands like `Eject Engineers`).

     3. `Team.ENEMY` `Unit` / `TargetDummy` (sets `inspected_entity`, shows red selection ring, read-only stats).

     4. `ResourceNode` (`BiomassNode`, `SilicaVein`, `ComputeVent`) (sets `inspected_entity`, shows amber/cyan ring, live remaining capacity).

3. **Right-Click While Inspecting Non-Commandable Entity:**

   * If `selected_units` is empty and the player is only inspecting a `ResourceNode`, `Enemy`, or `Building`, `Right-Click` does not throw errors or issue stray unit orders.

### B. Compute Node & Resource Node Inspection Details

* **Clicking a `ComputeNode`:**

  * Left Column shows `Compute Node` (`FRIENDLY FACILITY`), HP (`400 / 400`), and a primary **Staffing / Output Bar** (`Engineers: 2 / 2`).

  * Center Column shows:

    * `Compute Rate: +10 / 3.0s` (or `0 / 3.0s — Assign Engineers` when `0 / 2`)

    * `Vent Status: Active Thermal Vent` (and remaining vent capacity if finite)

    * `Construction: Operational` (or `Building: 45%` if still under construction)

  * Right Column shows `[E] Eject Engineers` (enabled when `assigned_engineers.size() > 0`).

* **Clicking a `BiomassNode` or `SilicaVein`:**

  * Left Column shows `Biomass Cluster` or `Silica Vein` (`RESOURCE DEPOSIT`) and a **Remaining Capacity Bar** (`1,320 / 1,500`).

  * Center Column shows `Resource Type`, `Remaining Yield`, and `Harvest Method` (`Direct Worker Gather` vs. `Automated Silica Harvester`).

## 4. Verification Checklist for `agy`

Before concluding this task, verify in `milestone_0_test.tscn`:

* \[ \] Drag-selecting a box across player units, a `CommandCore`, a `BiomassNode`, and a `TargetDummy` selects **only** the player units.

* \[ \] Single left-clicking a `BiomassNode` or `SilicaVein` displays a ground selection ring around the deposit and shows its live `Remaining / Max` capacity bar in the bottom HUD; as a worker harvests from it, the number ticks down live in the HUD.

* \[ \] Single left-clicking a `ComputeNode` displays its HP, staffed Engineer count (`0/2`, `1/2`, `2/2`), live Compute output rate, and `[Eject Engineers]` button in the Command Card.

* \[ \] Single left-clicking an enemy `TargetDummy` displays a red inspection ring and its HP/stats in the bottom HUD with no Command Card actions.

* \[ \] Hovering over any Command Card button (abilities, worker build buildings, or unit commands) displays a clean tooltip with name, hotkey, resource cost, and description.

* \[ \] `ResourceHUD`, `SelectionHUD`, and `SandboxDebugPanel` all share `technozen_theme.tres` with consistent borders, colors, and readable hierarchy.