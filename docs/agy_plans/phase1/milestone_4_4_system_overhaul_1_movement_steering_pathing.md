# Milestone 4.4 — System Overhaul #1: Next-Gen Movement, Steering & Pathing

**Prerequisite:** Milestones 4.3a and 4.3b verified and working cleanly.

**Goal:** Overhaul ground navigation, unit collision resolution, crowd flow, and spatial queries to deliver crisp, *StarCraft II*-grade battlefield movement across 1v1, 3P FFA, and 4P late-game armies:

1. **Hardened, Zero-Alloc `SpatialGrid` (`scripts/systems/spatial_grid.gd`):** Fix the cell-boundary padding bug for large heavy units, add zero-allocation `query_units_into(...)`, expose `query_resources_in_radius(...)` & `query_barricades_in_radius(...)`, and switch bucket removal to O(1) swap-pop.
2. **Async NavMesh Baking & Resource Cutouts (`scripts/world/arena_nav_region.gd`, `scripts/world/resource_node.gd`, `scripts/units/gather_component.gd`):** Move runtime navmesh rebakes off the main thread (`bake_navigation_polygon(true)`) with zero frame hitches, bake living non-vent resource nodes into the navmesh so combat units route cleanly around mineral lines (reclaiming the space automatically on depletion), and widen worker gather-reach fallback by `+6 px` for smooth cutout-edge harvesting.
3. **World-Only Physics + SC2 Push-Priority Solver, Proactive Ally Yielding & Firm Hostile Body-Blocking (`scripts/units/unit.gd`, `scripts/units/movement_component.gd`):** Eliminate triple-layer collision fighting (Godot RVO2 + rigid unit-vs-unit + soft spring) and permanently fix the 3P/4P team bitmask bug by switching units to world-only physics (`collision_mask = 1`), disabling RVO2 on ground units, introducing a 4-tier SC2 push-priority + mass solver with proactive idle-ally parting ("parting the sea"), preserving frictionless worker mineral-walking, and enforcing firm hostile body-blocking.
4. **Group-Aware Contagious Settling, `MOVING` Repath Fix & Corner/Ramp Flow (`scripts/units/movement_component.gd`, `scripts/units/unit.gd`, `scripts/controllers/command_router.gd`):** Replace premature single-contact settling with `move_group_id`-aware contagious settling, fix stuck `MOVING` units never re-requesting paths, add 1-segment corner lookahead, and add wall-slide tangential assist for wide ramp and cliff-corner flow.

**Hard Design Guardrails (MUST PRESERVE):**

* **Zero Auto-Formations or Role-Sorted Formations:** Do **not** alter `CommandRouter`'s human player destination layout into role-sorted lines or automated formations. Contagious settling produces natural organic SC2 packing around clicked destinations.
* **Zero Skill-Cap Automation:** No stealth/cloaking, no overkill-prevention targeting automation, no auto-loop production, standard worker construction only.
* **Zero Combat Balance Stat Changes:** Do **not** alter unit/building HP, shields, armor, damage, attack ranges, move speeds, or costs. *(Only the physical fallback gather-reach margin in `GatherComponent._get_gather_reach()` is widened by `+6 px` to accommodate baked resource navmesh cutouts.)*
* **Preserve 4.3a / 4.3b Modular Architecture:** Respect extracted helpers (`UnitCommandQueue`, `UnitDeployController`, `AIArmyController`, etc.) with zero regressions.

---

## Phase A — Hardened, Zero-Alloc `SpatialGrid` (`scripts/systems/spatial_grid.gd`)

### A.1 Fix Cell-Boundary Padding Bug & O(1) Swap-Pop

1. **Fix `query_units_in_radius()` Cell Range:**
   * Currently `min_c` and `max_c` are computed from `safe_r` while the distance check uses `pad_r = safe_r + 36.0`, which can miss large heavy units (`Goliath Frame`, `Monolith Dreadnought`, `Seraph Cruiser`) whose centers sit just across a `128 px` cell seam.
   * Compute `min_c` and `max_c` using **`pad_r = safe_r + 36.0`** (matching the exact `query_buildings_in_radius()` pattern).
2. **O(1) Swap-Pop Bucket Removal (`_remove_from_bucket`):**
   * Replace `arr.erase(entity)` (O(n) shift) with index lookup + swap-pop:
     ```gdscript
     var idx: int = arr.find(entity)
     if idx >= 0:
         var last: int = arr.size() - 1
         if idx != last:
             arr[idx] = arr[last]
         arr.pop_back()
     ```
   * Use the same swap-pop pattern when pruning stale entries inside query loops instead of `bucket.remove_at(i)`.

### A.2 Zero-Allocation Hot-Path & Missing Spatial Queries

1. **`func query_units_into(center: Vector2, radius: float, out_results: Array, filter_team: int = -99) -> void`:**
   * Clears `out_results.clear()` and appends matching living, non-staffed `Unit`s directly into the caller's reusable scratch array (using the fixed `pad_r` cell bounds).
   * Keep `query_units_in_radius(...)` intact for existing callers (optionally delegating to `query_units_into`).
2. **`func query_resources_in_radius(center: Vector2, radius: float, include_vents: bool = false) -> Array[ResourceNode]`:**
   * Queries `_resource_buckets` with `search_r = maxf(0.0, radius) + 48.0`, skipping invalid/depleted nodes (and vents unless `include_vents == true`) and checking `eff_r = safe_r + rn.collision_radius + 8.0`.
3. **`func query_barricades_in_radius(center: Vector2, radius: float) -> Array[Node2D]`:**
   * Extracts the barricade spatial scan already duplicated inside `query_entities_in_radius(...)` into its own public helper (and have `query_entities_in_radius` call it cleanly).
4. **Resource Registration Audit (`scripts/world/resource_node.gd`):**
   * Verify `ResourceNode._ready()` calls `SpatialGrid.register_resource(self)` and `_exit_tree()` / depletion calls `SpatialGrid.unregister_resource(self)` cleanly so `_resource_buckets` is always 100% populated on hand-crafted and procedural maps.

---

## Phase B — Async NavMesh Baking & Resource Cutouts

### B.1 Background Async Baking (`scripts/world/arena_nav_region.gd`)

1. **Async Runtime Rebakes (Zero Frame Hitches):**
   * Add state flags:
     * `var _is_baking: bool = false`
     * `var _rebake_queued_during_bake: bool = false`
   * In `_ready()`, connect `if not bake_finished.is_connected(_on_bake_finished): bake_finished.connect(_on_bake_finished)`.
   * Add `func rebake_navmesh(on_thread: bool = true) -> void`:
     * In `_perform_initial_rebake()` (startup / Frame 1): call `rebake_navmesh(false)` synchronously so starting hubs, MatchManager's `0.15s` starting worker dispatch, and initial AI staging anchors immediately get a valid navmesh on Frame 1.
     * In `_process(delta)` (runtime building placements, building/barricade destructions, resource depletions): if `_is_baking`, set `_rebake_queued_during_bake = true` and return; otherwise call `rebake_navmesh(true)` asynchronously!
     * Inside `rebake_navmesh(on_thread: bool)`: set `_is_baking = on_thread` right before `bake_navigation_polygon(on_thread)`.
   * In `_on_bake_finished()`:
     * Set `_is_baking = false`.
     * If `_rebake_queued_during_bake`: reset `_rebake_queued_during_bake = false` and call `request_rebake()` so rapid sequential placements/explosions always converge to the final state without dropping updates.
   * **Important Guard:** Do **not** replace `navigation_polygon = NavigationPolygon.new()` while `_is_baking == true` (guarded cleanly by the `_is_baking` check above).

### B.2 Bake Living Non-Vent Resource Nodes & Cliff Bodies (`scripts/world/arena_nav_region.gd`, `scripts/world/resource_node.gd`, `scripts/units/gather_component.gd`)

1. **Include Living `resource_nodes` in `NAV_BAKE_GROUP` (`arena_nav_region.gd`):**
   * Inside `rebake_navmesh()`, iterate `get_tree().get_nodes_in_group("resource_nodes")`:
     * If `rn is ResourceNode and is_instance_valid(rn) and not rn.is_queued_for_deletion()`:
       * If `not rn.is_vent and not rn.is_depleted()`: add `rn` to `NAV_BAKE_GROUP` (so combat squads path cleanly around Biomass/Silica patches instead of slamming into mineral lines!).
       * Else: remove `rn` from `NAV_BAKE_GROUP`.
   * Also ensure any `high_ground_plateaus` cliff static bodies (`collision_layer & 1 != 0`) are present in `NAV_BAKE_GROUP`.
2. **Rebake on Resource Depletion (`scripts/world/resource_node.gd`):**
   * When a non-vent `ResourceNode` depletes:
     * Remove it from `nav_bake_obstacles` (`NAV_BAKE_GROUP`), unregister from `SpatialGrid`, disable its collision shape cleanly, and call `arena_nav_region.request_rebake()` so mined-out mineral lines immediately open up as walkable terrain.
3. **Cutout-Edge Worker Reach Adjustment (`scripts/units/gather_component.gd`):**
   * In `_get_gather_reach(owner_unit, node)`: widen `min_physical` by `+6.0 px` (`maxf(60.0, node.collision_radius + unit_r + 28.0)`) and ensure `_tick_moving_to_node()` triggers `GATHERING` smoothly when the worker reaches its perimeter harvest slot right outside the baked resource navmesh cutout (check `slot_dist <= 16.0 or (node_dist <= reach and slot_dist <= 26.0)`).

---

## Phase C — World-Only Physics, SC2 Push-Priority Solver, Proactive Ally Yielding & Firm Hostile Body-Blocking

### C.1 World-Only Physics & Disable Flaky RVO2 (`scripts/units/unit.gd`, `scripts/units/movement_component.gd`)

1. **`scripts/units/unit.gd` (`_ready()`):**
   * Replace the old 2-team bitmask (`collision_layer = 2 if team == Team.PLAYER else 4`, `collision_mask = 7`) with clean, team-count-agnostic physics layers:
     * `collision_layer = 0 if data.ignore_friendly_unit_collision else 2`
     * `collision_mask = 1` *(World static geometry ONLY: terrain obstacles, cliff walls, buildings, barricades, resource nodes. Permanently resolves the 3P/4P team-layer collision bug and eliminates rigid unit-vs-unit snagging!)*
   * Disable Godot RVO2 avoidance on ground units:
     * `if nav_agent != null: nav_agent.avoidance_enabled = false` *(keep `nav_agent.max_speed` and `nav_agent.radius` synced for clean pathfinding).*
2. **`scripts/units/movement_component.gd`:**
   * Remove `update_worker_collision_passing()`'s per-frame `collision_mask` and `avoidance_enabled` toggling (since `collision_mask` is now permanently `1` and `avoidance_enabled` is permanently `false`!).
   * Simplify `finish_physics_step(owner_unit, delta)` to always drive motion cleanly through `apply_direct_motion(owner_unit, desired_move_velocity, delta)` (keeping `on_nav_velocity_computed` as a safe no-op stub for backward signal compatibility).

### C.2 SC2 4-Tier Push Priority + Mass Solver & Firm Hostile Body-Blocking (`scripts/units/movement_component.gd`)

Define explicit priority tiers and chassis masses:

```gdscript
enum PushTier {
	YIELDING_IDLE = 1,
	ACTIVE_TRANSIT = 2,
	ENGAGED_COMBAT = 3,
	IMMOVABLE_ANCHOR = 4,
}
```

1. **Priority & Mass Helpers:**
   * `func get_push_priority(u: Unit) -> int`:
     * **Tier 4 (`IMMOVABLE_ANCHOR`):** `u.is_movement_locked_by_deploy()`, `u.command_state == Unit.CommandState.HOLD_POSITION`, harvesting in place (`gather_component.is_harvesting_in_place()`), repairing in place, salvaging in place (`u.is_salvaging_in_place()`), or constructing within build reach (`not u.is_nav_movement_active()`).
     * **Tier 3 (`ENGAGED_COMBAT`):** `u.current_target != null and is_instance_valid(u.current_target)` and (`u.combat_component != null and (u.combat_component.is_in_windup() or u.combat_component.is_within_attack_envelope(u, u.current_target))`) — or actively casting an ability in place.
     * **Tier 2 (`ACTIVE_TRANSIT`):** `u.is_nav_movement_active()` or in active transit commands (`MOVING`, `ATTACK_MOVING`, `PATROLLING`, `CASTING_ABILITY`, or non-stationary `GATHERING`/`CONSTRUCTING`/`STAFFING_BUILDING`/`REPAIRING`/`SALVAGING`).
     * **Tier 1 (`YIELDING_IDLE`):** `IDLE` (not actively firing) or `DEFENSIVE` resting at anchor.
   * `func get_unit_mass(u: Unit) -> float`:
     * If `u.data == null`: `1.0`.
     * If `u.data.is_heavy_unit()`: `2.6`.
     * Else if `u.data.is_armored`: `1.5`.
     * Else if `u.data.is_worker_class() or u.data.has_tag(&"flanker") or u.data.has_tag(&"scout")`: `0.75`.
     * Else: `1.0`.

2. **Rebuilt `compute_overlap_separation(owner_unit: Unit, extra_margin: float, out_hostile_block_normals: Array[Vector2] = []) -> Vector2`:**
   * Uses a reusable `var _scratch_sep_units: Array = []` via `SpatialGrid.query_units_into(owner_unit.global_position, query_r, _scratch_sep_units)` (zero per-frame array allocations!).
   * Determine relationship cleanly via `TeamManager.are_enemies(int(owner_unit.team), int(other.team))` (fallback `owner_unit.team != other.team`), properly supporting **2v2 allies** and **3P/4P FFA enemies**.
   * **Friendly / Allied Pair Rules:**
     * Skip if `_should_ignore_unit_collision(owner_unit, other)` *(Colossus Stride units gliding cleanly over non-heavy allies)*.
     * **SC2 Frictionless Mineral-Walking:** If `owner_unit` is a worker in active gathering transit (`GATHERING` and `not is_harvesting_in_place()`) OR `other` is a same-team worker in active gathering transit: **skip separation completely** so harvesting streams pass effortlessly through both fellow workers and idle combat units! *(Keep `_apply_harvester_perimeter_separation()` unchanged so workers actively mining the same patch still fan out cleanly around the mineral perimeter.)*
     * Compute `my_tier` and `other_tier`:
       * If `my_tier == PushTier.IMMOVABLE_ANCHOR`:
         * Against lower tiers: `weight = 0.0` (immovable anchors never get shoved off `HOLD_POSITION` or `DEPLOYED`!).
         * Against another `IMMOVABLE_ANCHOR`: `weight = 0.25` (gentle un-stacking only if physically spawned overlapping).
       * Else if `my_tier > other_tier`: `weight = 0.08` (higher-priority mover/attacker holds its lane smoothly while lower-priority ally yields).
       * Else if `my_tier < other_tier`: `weight = 1.20` (yielding ally quickly steps aside).
       * Else (`my_tier == other_tier`): `weight = clampf(other_mass / maxf(0.1, my_mass + other_mass), 0.20, 0.80) * 1.45` (equal tiers share displacement smoothly weighted by chassis mass).
     * Accumulate smooth push `dir * max_push * overlap_ratio * weight`.
   * **Hostile Pair Rules (Firm SC2 Body-Blocking):**
     * **Never** skip hostile separation for workers or lower-priority units (only respect `ignore_friendly_unit_collision` for Colossus Stride vs. small units if explicitly desired—wait: `ignore_friendly_unit_collision` is strictly *friendly* by design, so hostiles always collide firmly!).
     * Use firm stiffness (`hostile_weight = 1.65 * clampf(other_mass / maxf(0.1, my_mass + other_mass), 0.35, 0.85) * 1.4`, capped cleanly at `max_push * 1.35`) so enemies cannot phase through frontline walls.
     * Append the unit normal `(owner_unit.global_position - other.global_position).normalized()` into `out_hostile_block_normals`.
     * In `apply_direct_motion()`: for each hostile contact normal `n` where `target_velocity.dot(n) < 0.0`, project out `85%` of the inward velocity component (`target_velocity -= n * target_velocity.dot(n) * 0.85`). *Result:* Frontline `Bulwark Automatons`, `Stingers`, and `Votaries` can physically **surround and body-block** retreating enemy `Cantors`, `Anvils`, or workers while still sliding smoothly along their flanks!

### C.3 Proactive Ally Yielding ("Parting the Sea") (`scripts/units/movement_component.gd`)

* Add lightweight yield state on `MovementComponent`:
  * `var _yield_impulse: Vector2 = Vector2.ZERO`
  * `var _yield_timer: float = 0.0`
  * `var _scratch_yield_units: Array = []`
  * `func apply_yield_nudge(impulse: Vector2, duration: float = 0.22) -> void`:
    * Ignores nudge if `owner_unit` is not `PushTier.YIELDING_IDLE` (never disturbs `HOLD_POSITION`, `DEPLOYED`, firing units, or active workers!).
    * Blends `_yield_impulse = _yield_impulse.lerp(impulse, 0.65)` (or sets directly if `_yield_timer <= 0.0`) and refreshes `_yield_timer = maxf(_yield_timer, duration)`.
* **Emitter Pass (during `apply_direct_motion` when `wants_nav_movement` and `desired_move_velocity.length_squared() > 16.0`):**
  * Skip if `owner_unit` is a Colossus Stride unit (`ignore_friendly_unit_collision`) or a mineral-walking worker in gather transit.
  * Query `SpatialGrid.query_units_into(owner_unit.global_position, my_r + 44.0, _scratch_yield_units, int(owner_unit.team))`.
  * Let `move_dir = desired_move_velocity.normalized()`.
  * For each friendly `other` where `get_push_priority(other) == PushTier.YIELDING_IDLE` and `other.movement_component != null`:
    * Check forward cone: `to_other = other.global_position - owner_unit.global_position`, `dist = to_other.length()`, `trigger_r = my_r + other_r + 20.0`.
    * If `dist > 0.1 and dist < trigger_r` and `(to_other / dist).dot(move_dir) > 0.30`:
      * Choose lateral exit side: `cross_z = move_dir.cross(to_other / dist)`; `side = 1.0 if cross_z > 0.05 else (-1.0 if cross_z < -0.05 else (1.0 if (other.get_instance_id() % 2) == 0 else -1.0))`.
      * `tangent = Vector2(-move_dir.y, move_dir.x) * side`.
      * `strength = clampf((trigger_r - dist) / maxf(1.0, trigger_r), 0.25, 1.0)`.
      * `nudge_speed = minf(other.get_effective_move_speed() * 0.72, 165.0) * strength`.
      * Call `other.movement_component.apply_yield_nudge(tangent * nudge_speed, 0.22)`.
* **Receiver Pass (in `apply_stationary_separation`):**
  * When `_yield_timer > 0.0`:
    * If `get_push_priority(owner_unit) != PushTier.YIELDING_IDLE`: clear `_yield_timer = 0.0`, `_yield_impulse = Vector2.ZERO`.
    * Else: decrement `_yield_timer = maxf(0.0, _yield_timer - delta)`, combine `sep + _yield_impulse`, clamp to `owner_unit.get_effective_move_speed() * 0.80`, call `owner_unit.move_and_slide()`, and update `SpatialGrid`.
  * *Result:* Moving reinforcements and heavy walkers glide through idle staging crowds and ramp crests while idle allies smoothly step aside and settle cleanly once clear!

---

## Phase D — Group-Aware Contagious Settling, `MOVING` Repath Fix & Corner/Ramp Flow

### D.1 Shared `move_group_id` Tagging (`scripts/controllers/command_router.gd`, `scripts/units/unit.gd`, `scripts/units/unit_command_queue.gd`, `scripts/systems/ai/ai_army_controller.gd`)

1. **`scripts/controllers/command_router.gd`:**
   * Add `static var _next_move_group_id: int = 1` and `static func allocate_move_group_id() -> int` (increments and returns positive int; wraps safely back to `1` if `> 1_000_000_000`).
   * When issuing group Move (`selected_units.size() > 1`) or Attack-Move orders, allocate one `gid = CommandRouter.allocate_move_group_id()` for the batch and pass it on the command (`cmd["group_id"] = gid` or optional parameter on `unit.command_move(pos, append, gid)` / `unit.command_attack_move(pos, append, gid)` with default `0` so all existing callers stay 100% backward-compatible!).
   * Also allocate a shared `gid` in `AIArmyController` when launching AI waves or rallying multiple strays to `_staging_point`.
2. **`scripts/units/unit.gd` & `scripts/units/unit_command_queue.gd`:**
   * Add lightweight state fields on `Unit`:
     * `var move_group_id: int = 0`
     * `var last_settled_group_id: int = 0`
   * Sync `unit.move_group_id = int(cmd.get("group_id", 0))` when starting `&"move"` or `&"attack_move"` (and clear `last_settled_group_id = 0` whenever a new movement command starts; clear `move_group_id = 0` on stop/hold/idle).

### D.2 Contagious Group Settling (`scripts/units/movement_component.gd`)

1. **Remove Premature `_check_post_slide_settling()`:**
   * Delete `_check_post_slide_settling()` completely (it previously cancelled movement whenever a unit grazed *any* unrelated idle teammate within `160 px` of its goal).
2. **Upgrade `should_settle_at_destination(owner_unit: Unit, goal_pos: Vector2, delta: float) -> bool`:**
   * **Condition 1 (Direct Arrival):** `dist_to_goal <= arrive_dist` or `owner_unit.nav_agent.is_navigation_finished()`:
     * Set `owner_unit.last_settled_group_id = owner_unit.move_group_id` and return `true`.
   * **Condition 2 (Contagious Group / Goal-Anchor Settling):** When `owner_unit.command_state == Unit.CommandState.MOVING` (or `ATTACK_MOVING` with `current_target == null`):
     * Compute `settle_band = maxf(arrive_dist * 3.0, unit_r * 4.5)` (expanded up to `220.0 px` when `owner_unit.move_group_id > 0` so a 24-unit army converging on a point settles cleanly all the way to its outer ring!).
     * Inside `settle_band`, sample displacement every `0.20s` (`SOFT_SETTLE_SAMPLE_WINDOW = 0.20`, `SOFT_SETTLE_MAX_DISP_PX = 7.0`).
     * If making low progress (`_settle_low_motion` and `dist_to_goal >= _best_dist_to_goal - 3.5`):
       * Check `_is_blocked_by_settled_group_or_goal_anchor(owner_unit, goal_pos, unit_r)`:
         * Returns `true` if touching/within `my_r + other_r + 10.0` of a friendly `IDLE` ally that **shares `other.last_settled_group_id == owner_unit.move_group_id`** (`move_group_id > 0`) AND is closer to `goal_pos` than `owner_unit`, **OR**
         * Returns `true` if a Tier 4 immovable friendly anchor (`HOLD_POSITION` / `DEPLOYED`) occupies within `48.0 px` of `goal_pos` and `dist_to_goal <= my_r + 64.0`.
       * Confirm over `0.22s` (`SOFT_SETTLE_CONFIRM_TIME = 0.22`), then set `owner_unit.last_settled_group_id = owner_unit.move_group_id`, call `stop_navigation(owner_unit)`, and return `true`!
   * **Condition 3 (Fallback Safety Timeout):** Keep `_no_progress_timer` as an unreachable-pocket fallback strictly inside `110.0 px` with `SETTLE_NO_PROGRESS_TIME = 0.85s` so units never jitter indefinitely against an impassable cliff corner.

### D.3 Fix Stuck `MOVING` Repath, Corner Lookahead, Wall-Slide Assist & Bounds Caching

1. **Fix `Unit._process_moving()` Repath Bug (`scripts/units/unit.gd`):**
   * Mirror `_process_attack_moving()`: before calling `_compute_nav_desired_velocity()`, check:
     ```gdscript
     var last_m: Vector2 = movement_component.last_nav_target if movement_component != null else Vector2.INF
     if last_m == Vector2.INF or last_m.distance_squared_to(_move_destination) > 1.0:
         _set_nav_target(_move_destination)
     ```
   * Now when `apply_anti_stuck_steering()` invalidates the path, `MOVING` units immediately re-query a fresh path around the obstacle instead of walking off a stale path!
2. **1-Segment Path Corner Lookahead (`movement_component.gd`):**
   * In `compute_nav_desired_velocity(owner_unit)`:
     * Read `var next_point: Vector2 = owner_unit.nav_agent.get_next_path_position()`.
     * Check `var path: PackedVector2Array = owner_unit.nav_agent.get_current_navigation_path()` and `var p_idx: int = owner_unit.nav_agent.get_current_navigation_path_index()`.
     * If `p_idx + 1 < path.size()` and `owner_unit.global_position.distance_to(next_point) <= my_r * 1.65`:
       * Peek `var after_point: Vector2 = path[p_idx + 1]`.
       * Blend desired direction smoothly `dir = to_next.normalized().lerp((after_point - owner_unit.global_position).normalized(), 0.35).normalized()` so squads carve smooth arcs around building corners and wide ramp crests instead of hard-braking at every nav vertex.
3. **World Wall-Slide Tangential Assist (`movement_component.gd`):**
   * Add lightweight state: `var _wall_slide_dir: Vector2 = Vector2.ZERO`, `var _wall_slide_timer: float = 0.0`.
   * Inside `apply_direct_motion()` right after `owner_unit.move_and_slide()` when `wants_nav_movement`:
     * If `owner_unit.get_slide_collision_count() > 0`:
       * Inspect the first collision normal `n` against a World collider (`StaticBody2D`).
       * If `desired_move_velocity.normalized().dot(n) < -0.20` (pushing meaningfully into a wall/cliff corner):
         * Pick the two wall tangents `t1 = Vector2(-n.y, n.x)` and `t2 = -t1`, choose whichever aligns better with `desired_move_velocity` (breaking dead-center ties with `_stuck_side_sign`), and set `_wall_slide_dir = chosen_t`, `_wall_slide_timer = 0.14`.
   * Before computing `combined` velocity in `apply_direct_motion()`, if `_wall_slide_timer > 0.0`: decrement timer and blend `target_velocity = target_velocity.lerp(_wall_slide_dir * eff_speed, 0.38)` so heavy walkers glide smoothly past cliff bevels and ramp entrances.
4. **Eliminate Scene-Group Scans in `MovementComponent`:**
   * Cache `_cached_arena_bounds: Rect2` lazily on `MovementComponent` (refreshed only if empty).
   * Update `_is_point_clear_of_obstacles()` to query **`SpatialGrid.query_buildings_in_radius(...)`**, **`SpatialGrid.query_resources_in_radius(...)`**, and **`SpatialGrid.query_barricades_in_radius(...)`** instead of iterating full scene-tree groups on every approach probe.

---

## Phase E — Verification & Stress-Test Checklist

1. **Zero Errors & Boot Audit:**
   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.
2. **SC2 Push-Priority & "Parting the Sea" Feel (`milestone_0_test.tscn`):**
   * Park `10× Clone Trooper` (or `Votary`) `IDLE` in a clump in the center of the arena.
   * Order `2× Monolith Dreadnought` (or `Goliath Frame`) to `Move` straight through them: confirm idle allies smoothly **part to the sides** and settle cleanly once the Dreadnought passes—zero snagging or stalling.
   * Repeat with the `10×` squad set to **`Hold Position` (`H`)** or **`Anvil Siege-Walker` `Deployed` (`E`)**: confirm Tier 4 immovable anchors hold rock-steady while moving allies flow around them cleanly.
3. **Firm Hostile Body-Blocking & 3P/4P Collision Parity:**
   * Surround a retreating enemy `Cantor` or `Worker` with `4× Stinger` / `Bulwark Automaton`: confirm enemy units **cannot phase through** the surround (firm hostile body-blocking works cleanly).
   * Verify in a **3P FFA** (`Triad Sanctum`) and **4P FFA** (`Quad Nexus`) that Teams 1, 2, and 3 body-block each other properly (confirming the old 2-team bitmask bug is gone).
4. **Group Contagious Settling & Unrelated-Unit Pass-By:**
   * Box-select `24× Votary` / `Clone Trooper` and right-click a single point: confirm the army packs tightly and **stops cleanly with zero endless shoving/jittering**.
   * Place `2×` unrelated idle workers near a ramp, then order a combat squad to `Move` past them to a point `120 px` beyond: confirm the squad does **not** quit early upon brushing past the workers (confirming `_check_post_slide_settling` bug is gone).
5. **Resource NavMesh Cutouts, Async Rebakes & Mineral-Walking:**
   * Order a combat squad to `Move` across a base containing a `Biomass` / `Silica` mineral line: confirm they **path cleanly around** the resource cluster instead of walking into the patches.
   * Watch `8×` workers harvesting and returning cargo while combat units idle near the mineral line: confirm workers **mineral-walk frictionlessly** through both fellow workers and idle combat units, trigger harvesting reliably at the cutout edge, and reclaim walkable space immediately when a node depletes.
   * Build and salvage/destroy 3+ structures rapidly in a **4P FFA Spectator Match** at `2x` speed: confirm **zero frame-hitch spikes** during async navmesh rebakes and smooth army movement up `180–220 px` wide ramps.