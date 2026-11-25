# Milestone 1.6.2 — Worker Pathing & Task Engagement Bugfix Plan

## 1. Objective
Diagnose and fix the recent worker pathing stalls, obstacle snags, and task-engagement/queue edge cases across `unit.gd`, `gather_component.gd`, `staff_component.gd`, `command_router.gd`, `arena_nav_region.gd`, and `skirmish_ai.gd` so workers glide smoothly around terrain, landmarks, structures, and teammates while reliably executing single and `Shift`-queued tasks.

---

## 2. Root Causes & Targeted Fixes

### 2.1 Unify Component Navigation & Prevent Premature Path Completion (`scripts/units/unit.gd`)
* **Audit `request_component_navigation()` and `_request_nav_toward_point()`:**
  * Ensure `_request_nav_toward_point()` sets `_wants_nav_movement = true` whenever `_is_nav_map_ready()` and the worker is still outside the task's reach/arrival radius—even if `nav_agent.is_navigation_finished()` reports true due to navmesh boundary offset or an updated `NavigationPolygon`.
  * Only allow `_request_nav_toward_point()` to stop moving when the worker is actually within the task/destination reach or when `_is_nav_map_ready()` is false.
  * When falling back to direct steering (e.g., nav map not yet ready on frame 1), always route through obstacle/unit avoidance rather than raw unsteered `to_target.normalized()`.
* **Fix Anti-Stuck Oscillation Against Obstacles & Units (`_apply_anti_stuck_steering()`):**
  * Stop flipping `_stuck_side_sign` blindly every `0.6s` while still blocked against the same obstacle; lock a consistent tangential side (`+1.0` or `-1.0`) for a full detour window (`0.55s–0.75s`) and force a fresh nav target query (`_last_nav_target = Vector2.INF`) so workers commit to going around corners instead of jittering left/right.
  * Exclude stationary/harvesting/constructing workers from pushing moving workers off their approach corridor when `dist` is near task reach (`_compute_overlap_separation()`).

### 2.2 Safe Building-Placement Nudge & Worker Collision Passing (`scripts/controllers/command_router.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/units/unit.gd`)
* **Safe Unit Ejection on Building Spawn (`_nudge_units_out_of_building()`):**
  * When nudging units outside a newly placed building footprint, check that the candidate ejected position does not collide with `TerrainObstacle` / `MapLandmark` / other `Building` footprints or `arena_bounds`. Test candidate angles around the building perimeter (`0` to `2*PI` in small steps) and pick the nearest unobstructed spot instead of blindly setting `global_position = building.global_position + dir * min_dist`.
* **Consistent Worker Passing During Task Transit:**
  * In `_update_worker_collision_passing()`, allow workers actively heading to a task (`GATHERING`, `CONSTRUCTING`, `STAFFING_BUILDING`, or `MOVING` with `active_command` targeting a `gather`/`build`/`staff` order) to slide past friendly units cleanly without deadlocking in narrow lanes, while still colliding with `World` (Layer 1) and hostile units.

### 2.3 Obstacle-Aware Approach Points & Task Engagement (`scripts/units/gather_component.gd`, `scripts/units/staff_component.gd`, `scripts/units/unit.gd`)
* **Smarter Approach Point Selection:**
  * In `GatherComponent._get_approach_point()`, `Unit._process_constructing()`, and `StaffComponent.tick()`, compute approach points that stay within `arena_bounds` and respect `gather_reach` / `build_reach` / `staff_reach` without snapping to a point embedded inside a `StaticBody2D` obstacle (`TerrainObstacle`, `MapLandmark`, or `Building`).
  * Allow workers to begin gathering/constructing/staffing as soon as `dist <= reach` even if `nav_agent` hasn't snapped to the exact sub-pixel point, and immediately call `stop_component_navigation()` + `_reset_progress_tracker()` upon engaging the task so `_apply_anti_stuck_steering()` never triggers while stationary at the node or scaffold.
* **Command Queue & Cargo Edge Cases:**
  * In `GatherComponent._tick_returning_to_base()`, if no valid drop-off building exists and the worker is *not* `auto_gather_on_spawn`, check `if owner_unit.has_queued_commands():` before going `IDLE` so queued follow-up orders still run.
  * When a worker is already `is_staffed == true` and enters a `Wetware Mainframe`, emit clear status/queue updates so `CommandQueueOverlay` and `SelectionHUD` immediately clear stale queued lines for that staffed engineer.

### 2.4 AI Worker Assignment Hygiene (`scripts/systems/skirmish_ai.gd`)
* In `_find_available_worker()` and `_resume_unfinished_buildings()`:
  * Prefer truly `IDLE` workers first (`command_state == Unit.CommandState.IDLE and command_queue.is_empty()`).
  * Only pull a `GATHERING` worker onto a new construction site if it is not currently in `GATHER_RETURNING_TO_BASE` with cargo (or deposit/clear cleanly) and does not have a `Shift`-queued player/AI chain it is mid-way through.
  * Ensure `_nudge_units_out_of_building()` in `skirmish_ai.gd` uses the same obstacle-safe ejection check as `command_router.gd`.

### 2.5 NavMesh Rebake Pacing (`scripts/world/arena_nav_region.gd`, `scripts/buildings/building.gd`)
* Coalesce rapid `request_rebake()` calls with a short debounce (`0.15s` timer or frame coalesce) so placing multiple buildings or completing construction on several structures batches into a single navmesh bake rather than rebaking every frame/tick.

---

## 3. Verification Checklist
1. **Multi-Building & Corner Pathing:** Queue 3–4 buildings (`Synapse Pylon`, `Silica Condenser`, `Cloning Vat`) or move workers across the arena past `TerrainObstacle` and `MapLandmark` colliders; verify zero workers get wedged or oscillate on corners.
2. **Gather → Return → Next Task:** Have a worker gather resources, return cargo to a `Nexus Vat` or `Silica Condenser`, and chain a `Shift + Right-Click` move or build order; verify smooth transition with no stuck `GATHER_MOVING_TO_NODE` or `GATHER_RETURNING_TO_BASE` states.
3. **Construction & Wetware Mainframe Staffing:** Assign multiple workers to construct a building and engineers to staff a `Wetware Mainframe` near obstacles/other units; verify all reach build/staff range cleanly and progress bars/staffing pips update immediately.
4. **Idle Worker Cycling & AI Economy:** Trigger idle worker cycling (`~` / `cmd_select_idle_worker`), assign tasks to idle workers, and observe `SkirmishAICommander` workers/harvesters/engineers for 2+ minutes with zero stalls or Godot Debugger errors.