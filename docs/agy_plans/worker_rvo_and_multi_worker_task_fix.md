# Milestone 1.6.3 — Worker RVO Deadlock & Multi-Worker Task Engagement Fix

## 1. Objective
Eliminate the regression where only one worker engages a resource node or construction site while additional workers stall or become unresponsive. Restore crisp, reliable multi-worker gathering, construction, and staffing (like StarCraft II worker mineral-walking) by disabling RVO avoidance deadlocks on workers during task transit and spreading multi-worker approach slots around targets.

---

## 2. Targeted Fixes

### 2.1 Disable RVO Avoidance Deadlock for Workers in Task Transit (`scripts/units/unit.gd`)
* **Root Cause:** `_update_worker_collision_passing()` disabled physics collision between friendly workers, but left `nav_agent.avoidance_enabled = true`, causing stationary harvesting/constructing workers and `NavigationObstacle2D` nodes to zero-out `safe_velocity` for approaching teammates.
* **Fix in `_update_worker_collision_passing()`:**
  * When `is_worker_role` is true and `is_task_transit` is true (or while stationary harvesting/constructing/staffing):
    * Set `nav_agent.avoidance_enabled = false` so workers use `NavigationAgent2D` **pathfinding** (`get_next_path_position()`) + direct motion (`_apply_direct_motion()`) + soft `_compute_overlap_separation()` without RVO freezing them behind a teammate.
  * When a worker is **not** in task transit (e.g., idle, combat-moving, or standard ground move), re-enable `nav_agent.avoidance_enabled = true` (unless `data.ignore_friendly_unit_collision` is true).
  * In `unit.gd` `_physics_process()`, ensure `_apply_direct_motion()` runs immediately whenever `not nav_agent.avoidance_enabled`, so anti-stuck steering and task-approach movement are never overridden by RVO.

### 2.2 Multi-Worker Slot Spreading & Stable Approach Points (`scripts/units/unit.gd`, `scripts/units/gather_component.gd`, `scripts/units/staff_component.gd`)
* **Unit-Aware Approach Slots in `find_clear_approach_point()`:**
  * Accept an optional `avoid_friendly_workers: bool = true` check (or deterministic per-unit angular slot bias using `get_instance_id()`) so multiple workers assigned to the same `ResourceNode` or `Building` naturally fan out around the perimeter instead of stacking on the exact same angle.
  * When scoring the 16 candidate angles around `target_center`, penalize or skip angles that are already occupied within `unit_r * 1.8` by another stationary/working friendly worker, falling back to the closest clear angle if all slots are busy.
* **Stop Per-Frame Nav Target Thrashing:**
  * Cache the chosen approach point on the worker/component when starting a `gather`, `return_cargo`, `construct`, or `staff` leg, and only recompute `find_clear_approach_point()` if the target moves, the cached point becomes blocked, or `_apply_anti_stuck_steering()` invalidates the path (`_last_nav_target == Vector2.INF`).

### 2.3 Generous Task-Engagement Reach & Clean Stop (`scripts/units/gather_component.gd`, `scripts/units/unit.gd`)
* Slightly increase `gather_reach` buffer (`node.collision_radius + unit_r + 22.0`, min `54.0`), `dropoff_reach` (`building.footprint_radius + unit_r + 22.0`), and `build_reach` (`footprint_radius + unit_r + 28.0`) so a second or third worker standing neatly beside Worker 1 always engages reliably without needing to overlap Worker 1's center.
* Ensure `_compute_overlap_separation()` continues to skip pushing workers that are already within task reach (`self_near_task`) against stationary harvesting/constructing teammates.

### 2.4 Remove Redundant `NavigationObstacle2D` Avoidance Block on Resource Nodes (`scenes/world/biomass_node.tscn`, `scenes/world/silica_vein.tscn`)
* Keep the `StaticBody2D` physics collider (`collision_layer = 1`) on resource nodes, and verify `NavigationObstacle2D.avoidance_enabled` does not create an oversized RVO exclusion zone larger than `collision_radius` that blocks workers from entering `gather_reach`.

---

## 3. Verification Checklist
1. **3+ Workers on 1 Biomass Node:** Select all 3 starting workers and right-click a single `BiomassNode`. Verify **all 3** walk smoothly to the node, fan out around its perimeter, harvest simultaneously, return cargo to the `Nexus Vat`, and loop continuously without a single worker freezing.
2. **Multi-Worker Construction:** Place a `Cloning Vat` or `Synapse Pylon`, select 3 workers, and right-click the scaffold. Verify all 3 reach build range and advance construction together, then cleanly transition to any `Shift`-queued follow-up order.
3. **Obstacle Crossing:** Order 3 workers from one side of a `TerrainObstacle` / `MapLandmark` / `Nexus Vat` to a resource node or build site on the opposite side. Verify all 3 path around cleanly without corner-snagging or becoming unresponsive.
4. **Responsiveness Override:** While workers are gathering or constructing, issue a new Move, Gather, Stop (`S`), or Build order to all of them at once. Verify every worker immediately responds.