# Milestone 2.5.2 Plan: Worker Saturation Caps, Cluster Spreading & SC2-Style Harvest Positioning

**Target Directory:** `docs/agy_plans/30_worker_saturation_and_harvest_polish.md`
**Primary Extended Files:** `scripts/world/resource_node.gd`, `scenes/world/biomass_node.tscn`, `scenes/world/silica_vein.tscn`, `scripts/units/gather_component.gd`, `scripts/units/movement_component.gd`, `scripts/units/unit.gd`, `scripts/controllers/command_router.gd`, `scripts/buildings/production_component.gd`, `scripts/buildings/building.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/skirmish_ai.gd`, `ui/overlays/entity_visuals.gd`
**Reference Docs:** `docs/agy_plans/29_drag_box_feel_debug_hud_silo_and_auto_harvest.md`, `docs/agy_plans/worker_rvo_and_multi_worker_task_fix.md`, `docs/agy_plans/engine_hardening_salvage_auto_cast_los_audio_polish.md`

## 1. Objective & Scope

Upgrade worker economy mechanics to StarCraft-grade smoothness and readability by introducing hard **per-node harvester saturation caps**, a **unified cluster-spreading resolver** shared across manual orders, rally points, and depleted nodes, **non-overlapping harvest positioning paired with transit ghosting**, **dynamic nearest drop-off selection**, and **clean cargo dropping on reassignment**.

### In Scope

1. **Saturation Limits & Cluster-Aware Group Spreading:**

   * Enforce per-node saturation caps: **`max_harvesters = 3`** for `BiomassNode` and **`max_harvesters = 2`** for `SilicaVein`.

   * Track active assigned workers per `ResourceNode` with automatic pruning on death, reassignment, or depletion.

   * Right-clicking a `ResourceNode` with a group of workers distributes them evenly across non-depleted nodes of the same type in the local cluster (`~420 px` radius), prioritizing least-saturated nodes first.

   * Render diegetic saturation readouts (`2/3`, `3/3` in amber at cap, red if over-saturated) on hovered/selected `ResourceNode`s and aggregate cluster saturation badges (`6/9`) above friendly `Nexus Vat`s and `Silica Condenser`s.

2. **Smart Rally-Point Saturation (`ProductionComponent`):**

   * Newly trained Workers and Silica Harvesters spawned from a `Nexus Vat` or `Silica Condenser` rallied to a `ResourceNode` pass through the same cluster-spreading check so they automatically pick an open patch once the rallied node reaches its cap.

3. **Auto-Migrate on Node Depletion (`GatherComponent`):**

   * When a `BiomassNode` or `SilicaVein` depletes, its active workers immediately re-run the same cluster-spreading check to migrate to the nearest unsaturated node of the same resource type rather than dropping into `IDLE`.

4. **Dynamic Nearest Drop-Off (`GatherComponent`):**

   * Re-evaluate the closest completed friendly drop-off structure (`Nexus Vat`, `Silica Condenser`, `Command Core`) every time a worker's cargo fills up so newly completed expansion hubs immediately shorten return trips.

5. **Transit Ghosting & Non-Overlapping Harvest Positioning (`MovementComponent`, `GatherComponent`, `ResourceNode`):**

   * **While in Transit (`MOVING_TO_RESOURCE` / `RETURNING`):** Workers ghost cleanly through other gathering/returning workers (zero body-blocking or mineral-line traffic jams).

   * **While Actively Harvesting (`HARVESTING`):** Workers claim distinct perimeter harvest slots around the node (biased toward the nearest drop-off hub) and apply light soft-separation/slot-collision while parked so harvesters spread out cleanly around the patch instead of stacking on the same pixel.

6. **Drop Cargo on Reassignment (`GatherComponent`, `Unit`):**

   * Whenever a worker carrying cargo is manually reassigned to a different task or a different resource target (Move, Build, Repair, Salvage, or a new Gather order), immediately clear/drop its carried cargo and refresh its visual cargo indicator.

### Out of Scope

* Auto-resuming harvest after finishing building construction (workers continue obeying manual/Shift-queued orders or returning to idle after construction).

* Changing resource gather rates, cargo capacities, or `ComputeVent` / `Wetware Mainframe` Engineer staffing mechanics.

## 2. Phase A: Saturation Caps & Unified Cluster-Spread Resolver

### A.1 `ResourceNode` Slot & Harvester Tracking (`scripts/world/resource_node.gd`)

* **Exported Caps:**

  * Add `@export var max_harvesters: int = 3`.

  * Configure scene/resource defaults: `biomass_node.tscn` → `max_harvesters = 3`; `silica_vein.tscn` → `max_harvesters = 2`.

* **Assigned Worker Registry:**

  * Maintain `var _assigned_workers: Array[Unit] = []` and `var _harvest_slots: Dictionary = {}` (`slot_index: int -> Unit`).

  * Provide clean API:

    * `prune_assigned_workers() -> void`: Removes any invalid, dead, or no-longer-gathering-this-node units (and frees their harvest slot).

    * `get_assigned_count(team_filter: int = -1) -> int`: Prunes first, then returns active worker count (optionally filtered by team so enemy workers don't distort a player's local saturation readout).

    * `has_free_slot(team_filter: int = -1) -> bool`: Returns `get_assigned_count(team_filter) < max_harvesters`.

    * `assign_worker(worker: Unit) -> void`: Adds `worker` if not already registered.

    * `release_worker(worker: Unit) -> void`: Removes `worker` from `_assigned_workers` and releases any reserved slot in `_harvest_slots`.

### A.2 Shared Cluster-Spread Helper (`ResourceNode` Static Utility)

Create a single deterministic helper `ResourceNode.pick_best_cluster_node(anchor_node: ResourceNode, worker: Unit, team: int, cluster_radius: float = 420.0, overflow_radius: float = 950.0) -> ResourceNode`:

1. **Gather Local Cluster:** Find all non-depleted `ResourceNode`s in group `"resource_nodes"` matching `anchor_node.resource_type` within `cluster_radius` of `anchor_node.global_position`.

2. **Check Unsaturated Nodes First:**

   * Filter local candidates where `node.has_free_slot(team)` is `true`.

   * Score candidates by: `(assigned_count * 1000.0) + node.global_position.distance_to(anchor_node.global_position)` (with a small tie-break favoring `anchor_node` itself when counts are tied at `0`).

   * Return the lowest-scoring unsaturated node.

3. **Overflow Spillover (If Local Cluster Is Full):**

   * Search for the nearest unsaturated node of the same `resource_type` within `overflow_radius` (e.g., an adjacent natural expansion) that is safe/visible.

   * If no unsaturated node exists within `overflow_radius`, fall back to the least-assigned node in the local cluster (breaking ties by distance to `anchor_node`) so overflow workers distribute evenly instead of freezing or piling onto a single patch.

### A.3 Wiring All Entry Points to the Shared Resolver

* **Group Right-Click (`scripts/controllers/command_router.gd`):**

  * When right-clicking a `ResourceNode` with 1 or more compatible workers selected:

    * Release the selected workers' previous node assignments first (when not `Shift`-queuing) so re-clicking the same cluster rebalances them cleanly!

    * Iterate through the selected workers (sorted by proximity to the clicked node):

      * If only **1** worker is selected and `anchor_node.has_free_slot(team)` is `true`, send it straight to `anchor_node`.

      * Otherwise, call `var target := ResourceNode.pick_best_cluster_node(anchor_node, worker, team)`, immediately reserve `target.assign_worker(worker)` (so subsequent workers in the same loop see the updated count), and issue `worker.issue_gather(target, is_shift_queued)`.

* **Starting Worker Auto-Harvest (`scripts/systems/match_manager.gd`) & `SkirmishAICommander` (`scripts/systems/skirmish_ai.gd`):**

  * Route starting worker dispatch and AI worker assignment through `ResourceNode.pick_best_cluster_node()` so both Human and AI economies obey the exact same 3-Biomass / 2-Silica saturation rules.

## 3. Phase B: Smart Rally-Point Saturation & Auto-Migration on Depletion

### B.1 Smart Rally-Point Saturation (`scripts/buildings/production_component.gd`)

* When a newly produced `Worker` or `Silica Harvester` spawns from a `Nexus Vat` or `Silica Condenser` whose `rally_target_resource` is a valid `ResourceNode`:

  * Call `var target := ResourceNode.pick_best_cluster_node(building.rally_target_resource, unit, building.team)`.

  * Issue `unit.issue_gather(target, false)`.

  * If the original rallied node has already depleted, search from `building.rally_point` (or `building.global_position`) for the nearest unsaturated node of that worker's matching resource type.

### B.2 Auto-Migrate on Node Depletion (`scripts/units/gather_component.gd`)

* When a `ResourceNode` reaches `remaining_amount <= 0` (before freeing/marking depleted):

  * In `GatherComponent`, detect node depletion during `MOVING_TO_RESOURCE` or `HARVESTING`.

  * Call `ResourceNode.pick_best_cluster_node(depleted_node, owner_unit, owner_unit.team, 480.0, 1100.0)` (ignoring the depleted node).

  * If a valid node is found, reserve it and immediately transition to `MOVING_TO_RESOURCE` toward the new patch (preserving any partial cargo already gathered before depletion, or delivering first if cargo is already full).

  * Only fall back to `IDLE` if no non-depleted node of that resource type exists within search range.

## 4. Phase C: Dynamic Nearest Drop-Off & Cargo Drop on Reassignment

### C.1 Dynamic Nearest Drop-Off (`scripts/units/gather_component.gd`)

* Whenever `current_cargo >= carry_capacity` (transitioning from `HARVESTING` to `RETURNING`), dynamically query the closest completed (`is_constructed == true`, `not is_salvaging`) friendly drop-off building valid for the worker's `resource_type` (`Nexus Vat` / `Command Core` for Biomass; `Silica Condenser` / `Nexus Vat` for Silica).

* Never cache a stale initial drop-off building across the worker's lifetime—if a closer expansion hub finishes while a worker is harvesting, its very next return trip automatically routes to the closer hub.

### C.2 Drop Cargo on Reassignment (`scripts/units/gather_component.gd`, `scripts/units/unit.gd`)

* Add `func clear_carried_cargo() -> void` on `GatherComponent`:

  * Resets `current_cargo = 0` and `carried_resource_type = &""`.

  * Calls `owner_unit.queue_redraw()` so any visual cargo glow/pip disappears immediately.

* **Trigger Conditions:**

  * Whenever a worker receives a **non-Shift** manual reassignment that interrupts its current gather loop:

    * New `Move`, `Attack-Move`, `Patrol`, `Build`, `Repair`, or `Salvage` order → release current `ResourceNode` slot and call `clear_carried_cargo()`.

    * New `Gather` order targeting a **different** `ResourceNode` (or different `resource_type`) than its currently active node → release previous `ResourceNode` slot and call `clear_carried_cargo()`.

  * *Exception:* Do **not** drop cargo if the player right-clicks a friendly drop-off building to manually return cargo, or if the worker is auto-migrating because its node just depleted mid-trip.

## 5. Phase D: Transit Ghosting & Non-Overlapping Harvest Positioning

### D.1 Hub-Facing Perimeter Harvest Slots (`scripts/world/resource_node.gd`)

* Generate `max_harvesters` (plus 2 overflow fallback) evenly spaced angular harvest slots around each `ResourceNode`:

  * Compute the base angle `hub_angle` pointing from `node.global_position` toward the nearest friendly drop-off hub (or map center if none nearby).

  * Place slots along the hub-facing arc (e.g., for 3 Biomass slots: `hub_angle`, `hub_angle - 48°`, `hub_angle + 48°`; for 2 Silica slots: `hub_angle - 32°`, `hub_angle + 32°`; overflow slots further around the perimeter at `±95°`) at radius `node_collision_radius + worker_radius + 6.0`.

  * Expose `claim_harvest_slot(worker: Unit, dropoff_pos: Vector2) -> Vector2`:

    * Picks the closest unclaimed slot to `worker.global_position` (preferring the front arc slots), records `_harvest_slots[slot_idx] = worker`, and returns that exact world coordinate.

    * Automatically releases the slot when the worker transitions to `RETURNING`, leaves the node, or dies—allowing another waiting worker to slide cleanly into the open spot.

### D.2 Dual-Mode Movement & Collision (`scripts/units/movement_component.gd`, `scripts/units/gather_component.gd`)

* **Transit Ghosting (`MOVING_TO_RESOURCE` & `RETURNING`):**

  * Keep worker-vs-worker physical separation and RVO avoidance **disabled** while workers are moving to a resource or returning cargo to a drop-off hub, so workers glide smoothly past each other and past parked harvesters without stalling.

* **Non-Overlapping Active Harvesting (`HARVESTING`):**

  * When a worker arrives at its claimed harvest slot and enters `HARVESTING`:

    * Lock onto its claimed slot coordinate and apply a light **harvester-vs-harvester soft separation** check (via `SpatialGrid`, radius `worker_radius * 2.15`, ONLY against other workers currently in `HARVESTING` state on the same node).

    * If two workers ever end up within `worker_radius * 1.9` while harvesting (e.g., overflow workers above cap), nudge them tangentially along the node's perimeter arc so they visibly fan out and never overlap into a single sprite blob—while remaining immune to being pushed by passing transit workers.

## 6. Phase E: Diegetic Saturation Readouts (`ui/overlays/entity_visuals.gd`, `scripts/world/resource_node.gd`, `scripts/buildings/building.gd`)

* **Per-Node Saturation Tag (`ResourceNode`):**

  * When a `ResourceNode` is **hovered**, **selected**, or when a friendly `Worker` / `Silica Harvester` is currently selected:

    * Draw a crisp compact pill above/below the node showing `assigned / max` (e.g., `2/3`, `3/3`, `2/2`):

      * **Cyan / White:** Under-saturated (`assigned < max_harvesters`).

      * **Amber / Gold:** Optimal saturation (`assigned == max_harvesters`).

      * **Crimson:** Over-saturated (`assigned > max_harvesters`).

* **Base Hub Aggregate Saturation Badge (`Nexus Vat` & `Silica Condenser`):**

  * Compute local cluster totals for friendly `Nexus Vat`s (all non-depleted `BiomassNode`s within `~520 px`) and `Silica Condenser`s (all non-depleted `SilicaVein`s within `~420 px`): `total_assigned / total_cap` (e.g., `6/9` or `2/2`).

  * Render a tiny, clean Technozen pill (`6/9`) subtly above the building (visible when the building is selected, hovered, or when workers are selected; color-coded cyan / amber / crimson identically to individual nodes).

## 7. File & Architecture Summary

### Existing Files to Extend

* `scripts/world/resource_node.gd`, `scenes/world/biomass_node.tscn`, `scenes/world/silica_vein.tscn`: `max_harvesters` (`3` Biomass, `2` Silica), `_assigned_workers` & `_harvest_slots` tracking, `claim_harvest_slot()`, and shared static `pick_best_cluster_node()` resolver.

* `scripts/units/gather_component.gd`: Slot assignment/release lifecycle, auto-migration via `pick_best_cluster_node()` on depletion, dynamic nearest drop-off evaluation on cargo full, `clear_carried_cargo()` on reassignment, and `HARVESTING` slot targeting.

* `scripts/units/movement_component.gd` & `scripts/units/unit.gd`: Preserve transit ghosting during `MOVING_TO_RESOURCE`/`RETURNING` while applying tangential perimeter separation among actively `HARVESTING` workers; clear cargo on interrupting manual orders.

* `scripts/controllers/command_router.gd`: Group-click cluster spreading through `ResourceNode.pick_best_cluster_node()`.

* `scripts/buildings/production_component.gd` & `scripts/buildings/building.gd`: Smart rally-point saturation check on worker/harvester spawn + aggregate cluster saturation helper for `Nexus Vat` and `Silica Condenser`.

* `scripts/systems/match_manager.gd` & `scripts/systems/skirmish_ai.gd`: Route starting worker auto-harvest and AI worker dispatch through `ResourceNode.pick_best_cluster_node()`.

* `ui/overlays/entity_visuals.gd`: Render compact color-coded `X/Y` saturation pills on `ResourceNode`s and `Nexus Vat` / `Silica Condenser` hubs.

## 8. Verification Checklist for `agy`

Before concluding Milestone 2.5.2, verify in Godot (`skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, and `skirmish_arena_03.tscn`):

* [ ] **Group Harvest Spreading & Saturation Caps:** Select 9 Workers and right-click **one** `BiomassNode` in a 3-node cluster; confirm they spread evenly `3/3`, `3/3`, `3/3` across all three patches. Select 4 Silica Harvesters and right-click one `SilicaVein` in a 2-vein cluster; confirm they spread `2/2` and `2/2`.

* [ ] **Non-Overlapping Harvest Spots & Transit Ghosting:** Watch 9 Workers actively harvesting a 3-node Biomass line for 30 seconds; confirm workers fan out onto distinct spots around each node perimeter without stacking on top of each other, while returning/arriving workers glide smoothly through the mineral line with zero traffic jams or stuck workers.

* [ ] **Smart Rally-Point Saturation:** Rally a `Nexus Vat` to a single `BiomassNode` and queue 6 Workers; confirm the first 3 fill that node to `3/3` and Workers 4–6 automatically spill onto neighboring unsaturated `BiomassNode`s in the cluster.

* [ ] **Auto-Migration on Depletion:** Let a `BiomassNode` or `SilicaVein` deplete (or lower its amount in Sandbox); confirm its workers immediately migrate to the nearest unsaturated patch of the same type rather than going idle.

* [ ] **Dynamic Nearest Drop-Off:** Build a second `Nexus Vat` closer to a distant Biomass cluster while workers are harvesting there; confirm that as soon as construction finishes, workers immediately deliver their next full load to the closer `Nexus Vat`.

* [ ] **Drop Cargo on Reassignment:** Let a Worker harvest partial Biomass, then right-click to Move, Build, or Gather a different node; confirm its carried cargo immediately resets to `0` and its cargo visual clears cleanly.

* [ ] **Diegetic Saturation Badges & Debugger Hygiene:** Hover/select `ResourceNode`s, `Nexus Vat`s, and `Silica Condenser`s to verify crisp color-coded `X/Y` saturation badges (cyan under cap, amber at cap, crimson over cap) and zero Godot Debugger errors across a full match.