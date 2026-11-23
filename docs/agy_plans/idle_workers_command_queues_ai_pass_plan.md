# Milestone 1.4b Plan: Shift Build/Ability Queuing, Shift Selection, Unit Stances & Queue/AI/Pathing Hardening

**Target Directory:** `docs/agy_plans/12_idle_worker_command_queues_and_ai_pass.md`
**Primary Scene:** `res://scenes/maps/skirmish_arena_01.tscn` (and `res://scenes/test/milestone_0_test.tscn`)
**Reference Docs:** `docs/agy_plans/idle_workers_command_queues_ai_pass_plan.md`, `docs/agy_plans/faction_01_genesis_v2_the_vat_born_plan.md`, `docs/technical_glossary_and_specs.md`

## 1. Current Baseline (Already Implemented in Repo)

Your latest push (`idle_workers_command_queues_ai_pass_plan.md`) has already landed the core foundation for idle workers, `Shift + Right-Click` command queuing, and the initial AI pass:

* **Idle Worker Detection & HUD (`unit.gd`, `selection_controller.gd`, `resource_hud.gd`):** `is_idle_worker()` tracking, `F1` / HUD button cycling, and camera focus are implemented.
* **Core `Shift + Right-Click` Command Queue (`unit.gd`, `command_router.gd`, `ui/overlays/command_queue_overlay.gd`):** `command_queue` storage, sequential execution of right-click move/attack/gather/build-assist orders, and the `CommandQueueOverlay` path visualizer are already in place.
* **Initial Skirmish AI Worker/Pathing Pass (`scripts/systems/skirmish_ai.gd`):** Worker idle recovery and obstacle navigation updates have been integrated.

## 2. Objective & Remaining Scope (Delta Only)

Build directly on top of the existing `command_queue`, `CommandQueueOverlay`, and `SelectionController` infrastructure to add the remaining control modifiers, tactical stance mechanics, and fluid worker pathing/avoidance—without duplicating or overwriting existing `Shift + Right-Click` or `F1` idle-worker systems:

1. **`Shift + Left-Click` Multi-Building Construction Queuing (`selection_controller.gd`, `command_router.gd`, `build_ghost_preview.gd`, `unit.gd`):**
   * When placing a building via `BuildGhostPreview` while holding `Shift`, deduct resources, place the building scaffold, **append** the `BUILD` task to the selected worker's existing `command_queue` (instead of clearing/interrupting its current job), and **keep `BuildGhostPreview` active** so the player can immediately chain-place additional structures (e.g., multiple **Synapse Pylons** or a **Cloning Vat** + **Silica Condenser**) until `Esc` or `Right-Click` exits placement mode—or until resources run out.

2. **`Shift` Ability Queuing (`command_router.gd`, `selection_controller.gd`, `ability_component.gd`, `unit.gd`):**
   * When confirming a targeted ability (e.g., **Spore Barrage**, **Seismic Slam**, **Static Pulse**) or triggering an instant ability (e.g., **Adrenal Surge**) while holding `Shift`:
     * If the unit is busy or already has queued waypoints, **append** a `CAST_ABILITY` step to `command_queue` so the ability executes sequentially at the end of its flanking/movement route.
     * Render a distinct violet/magenta waypoint marker in `CommandQueueOverlay` for queued `CAST_ABILITY` steps.

3. **`Shift + Left-Click` Selection Add / Remove (`selection_controller.gd`):**
   * **`Shift + Left-Click` on a `Team.PLAYER` Unit:** If the unit is not currently in `selected_units`, add it to the selection; if it is already in `selected_units`, **remove** it from the selection (allowing quick single-worker peel-offs from a group).
   * **`Shift + Drag-Box`:** Appends all boxed `Team.PLAYER` units to `selected_units` without duplicating existing entries (and without wiping selection if the drag box catches empty ground while `Shift` is held).

4. **Unit Combat Stances — `Aggressive` vs. `Hold Position` (`unit.gd`, `combat_component.gd`, `command_router.gd`, `selection_hud.gd`):**
   * Add `enum Stance { AGGRESSIVE, HOLD_POSITION }` (`var stance: Stance = Stance.AGGRESSIVE`) on `Unit` with `set_stance(new_stance: Stance)`.
   * **`AGGRESSIVE` (Default):** Units acquire targets in `aggro_range` and pursue enemies within leash range (when global `Aggro AI` is enabled).
   * **`HOLD_POSITION` (Hotkey `H` or Command Card button):**
     * Immediately halts current movement and clears movement orders.
     * Unit will **not** move or chase enemies that enter `aggro_range` (preventing queued flankers like **Stingers** or **Chrysalis Mortars** from breaking formation early), while still firing at enemies that step directly inside its weapon `attack_range`.
     * Issuing an explicit `A`-Move or `AGGRESSIVE` command restores `Stance.AGGRESSIVE`.

5. **Fluid Worker Pathfinding & Collision/Obstacle Avoidance (`unit.gd`, `gather_component.gd`, `building.gd`, `arena_nav_region.gd`):**
   * **Eliminate Corner Snagging on Terrain & Placed Buildings:**
     * When new buildings or construction scaffolds are placed at runtime (`building.gd`), ensure they dynamically carve into the `NavigationRegion2D` polygon (or register with `arena_nav_region.gd` to trigger a clean rebake) with sufficient `agent_radius` margin so `NavigationAgent2D` plots paths *around* structures rather than straight through their `StaticBody2D` colliders.
     * Tune `NavigationAgent2D` `path_desired_distance` and `target_desired_distance` on workers (`Worker`, `Harvester`, `Engineer`) and enable RVO `avoidance_enabled = true` (or soft steering separation impulses) so workers smoothly slide past each other on busy **BiomassNode ↔ Nexus Vat** and **SilicaVein ↔ Silica Condenser** mineral lines instead of deadlocking head-on.
   * **Anti-Stuck Slide & Detour Recovery (`unit.gd` / `gather_component.gd`):**
     * Track short-window displacement progress while a unit is in a moving/gathering/building state; if a worker's actual movement speed drops below a threshold (`< 15%` of `move_speed` for `> 0.6s`) while blocked by another unit or collider corner, apply a tangential perpendicular steering nudge and force a `NavigationAgent2D` path refresh so it glides around the obstruction instead of vibrating in place.
     * During active `GATHER` / `RETURN_CARGO` trips (`gather_component.gd`), temporarily soften or ignore collision between friendly harvesting workers (or use dedicated RVO avoidance layers) so two workers crossing paths at a `BiomassNode` or `Nexus Vat` never block each other.

6. **Queue & AI Edge-Case Hardening (`unit.gd`, `command_queue_overlay.gd`, `skirmish_ai.gd`):**
   * Ensure `is_idle_worker()` returns `false` whenever a worker has pending `BUILD` or `MOVE` items in `command_queue`.
   * Guard all queued target references (`target_node` inside `command_queue` dictionaries) with `is_instance_valid()` so if a queued enemy unit, resource node, or construction scaffold is destroyed before the unit reaches that step, the unit cleanly skips that entry and advances to the next queued command.

### Out of Scope

* Re-implementing `F1` idle-worker detection/cycling, `Shift + Right-Click` ground/gather queuing, or `CommandQueueOverlay` from scratch (extend the existing implementations).
* New factions, units, or upgrades beyond `GENESIS_V2`.
* `Shift + 1..9` control group appending or AI Fog-of-War scouting changes.

## 3. File & Architecture Delta Plan

### Existing Files to Extend (No New Files Required)

* **`scripts/units/unit.gd`**
  * Add `enum Stance { AGGRESSIVE, HOLD_POSITION }`, `var stance: Stance = Stance.AGGRESSIVE`, and `set_stance(new_stance: Stance) -> void`.
  * Extend `command_queue` step execution to handle `"BUILD"` (moving to the placed scaffold and initiating construction) and `"CAST_ABILITY"` (triggering `AbilityComponent` at the queued target point/entity, then calling `_advance_command_queue()`).
  * Validate `is_instance_valid(cmd.get("target"))` when popping queued steps so destroyed targets are safely skipped.
  * Add anti-stuck displacement monitoring and tangential steering/repath recovery (`_apply_anti_stuck_steering(delta)`) plus RVO `avoidance_enabled` velocity blending so units/workers route smoothly around terrain corners, buildings, and crossing allies.

* **`scripts/units/gather_component.gd`**
  * Enable smooth passing between friendly workers during `GATHER` / `RETURN_CARGO` cycles (soft separation / avoidance priority rather than hard `CharacterBody2D` head-on collision deadlocks) and ensure interaction/drop-off arrival radii account for building collision margins so workers don't try to walk inside a `Nexus Vat` or `Silica Condenser` hitbox.

* **`scripts/buildings/building.gd` & `scripts/world/arena_nav_region.gd`**
  * Ensure newly placed buildings/scaffolds trigger a `NavigationRegion2D` geometry update (and remove their footprint on destruction) with proper navigation agent margin so workers immediately path around newly constructed structures.

* **`scripts/units/combat_component.gd`**
  * In idle/auto-acquire target checks, respect `unit.stance == Unit.Stance.HOLD_POSITION`: allow stationary attacks against targets already inside `attack_range`, but suppress pursuit/chase movement toward targets only inside `aggro_range`.

* **`scripts/controllers/selection_controller.gd`**
  * Update single-click and drag-box selection handlers to check `Input.is_key_pressed(KEY_SHIFT)`:
    * Toggle membership (add if absent, remove if present) when `Shift + Left-Clicking` a friendly unit.
    * Merge newly drag-boxed friendly units into `selected_units` without clearing existing members when `Shift` is held.
  * In building placement confirmation, check `shift_held`: if `true`, pass `append_to_queue = true` to `CommandRouter` and keep `BuildGhostPreview` active (exiting automatically only if the player can no longer afford another building of that type).
  * In ability target confirmation, forward `shift_held` to `CommandRouter`.

* **`scripts/controllers/command_router.gd`**
  * Update build placement routing and ability execution routing to accept `append_to_queue: bool = false`, appending `"BUILD"` or `"CAST_ABILITY"` commands onto selected units when `true`.
  * Wire hotkey `H` (`KEY_H`) to toggle/apply `Unit.Stance.HOLD_POSITION` on selected `Team.PLAYER` units.

* **`ui/overlays/command_queue_overlay.gd`**
  * Add color/icon differentiation for `"BUILD"` (emerald square/ring) and `"CAST_ABILITY"` (violet reticle ring) waypoints alongside existing move/attack waypoints.

* **`ui/hud/selection_hud.gd`**
  * Highlight the **`[H] Hold Position`** Command Card button whenever the inspected/selected unit group is in `Stance.HOLD_POSITION`.

## 4. Verification Checklist for `agy`

Before concluding this pass, verify in `skirmish_arena_01.tscn`:

* [ ] **`Shift + Left-Click` Multi-Building Queue:** Select a `Worker`, choose **Synapse Pylon** (or **Cloning Vat**), hold `Shift`, and `Left-Click` 2–3 valid locations; verify the build ghost stays active after each placement, all waypoints appear in `CommandQueueOverlay`, and the worker constructs them sequentially without being counted as an idle worker mid-chain.
* [ ] **`Shift` Ability Queuing:** Select a **Clone Trooper** or **Chrysalis Mortar**, issue a move waypoint, hold `Shift` and queue **Adrenal Surge** or **Spore Barrage**; verify the ability triggers sequentially after reaching the waypoint.
* [ ] **`Shift + Left-Click` Selection Toggle:** Drag-select a group of workers or infantry, `Shift + Left-Click` one selected unit to remove it from the group, and `Shift + Left-Click` an unselected unit to add it back.
* [ ] **Hold Position Stance (`H`):** Press `H` on combat units; verify they stop moving, ignore enemies outside `attack_range`, still shoot enemies that enter `attack_range`, and highlight the `Hold Position` button in `SelectionHUD`.
* [ ] **Fluid Worker Pathing & Obstacle Avoidance:** Send 4–6 `Worker`s / `Harvester`s across terrain pillars, newly placed buildings, and each other on busy resource lines; verify they path cleanly around structures and slide past crossing workers without getting stuck or vibrating on corners.
* [ ] **Queued Target Destruction Safety:** Queue a unit to attack/build/gather a target that gets destroyed beforehand; verify the unit cleanly skips the invalidated step and advances to the next queued command with zero errors.