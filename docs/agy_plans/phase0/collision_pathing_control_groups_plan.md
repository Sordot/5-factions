# Milestone 0.6 Plan: Unit Collision, Individual Pathing, Control Groups & Smart-Cast Attack-Move

**Target Directory:** `docs/agy_plans/02_collision_pathing_and_control_groups.md`
**Primary Scene:** `res://scenes/test/milestone_0_test.tscn`
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/sandbox_combat_controls_plan.md`

---

## 1. Objective & Scope

Refine core RTS responsiveness and squad control in the sandbox before building economy or production systems. Specifically, eliminate unit overlapping, ensure each unit computes and follows its own path cleanly around peers and obstacles, add standard `1–9` control groups, and streamline Attack-Move into an immediate cursor-targeted hotkey (`A` without requiring a secondary left-click).

### In Scope
1. **Unit-to-Unit Collision & Separation:** Prevent player units and target dummies from stacking on the exact same coordinates.
2. **Individual Pathfinding, Local Avoidance & Group Destination Spread:** Ensure each unit queries its own `NavigationAgent2D` path, steers around neighboring units via local avoidance, and fans out cleanly around group move/attack-move destinations without endless jitter.
3. **Control Groups (`1–9`):**
   * **`Ctrl + [1–9]`:** Assign currently selected player unit(s) to group `N` (overwriting previous group `N`).
   * **`Shift + [1–9]`:** Append currently selected player unit(s) to group `N` (avoiding duplicates).
   * **`Alt + [1–9]`:** Remove currently selected player unit(s) from group `N`.
   * **`[1–9]` (Plain Press):** Select all living units in group `N` (optional quality-of-life: double-tapping `[1–9]` centers camera on the group).
4. **Smart-Cast Attack-Move (`A` at Cursor):** Pressing `A` immediately issues an Attack-Move (or direct Attack if cursor is over an enemy) at the current mouse world position for all selected player units—no left-click confirmation needed.

### Out of Scope
* Automated formation shapes or auto-splitting algorithms (per GDD, unit splitting remains manual player skill).
* Economy, buildings, or AI opponent behavior.

---

## 2. File & Architecture Plan

### Existing Files to Extend
* `scenes/units/test_unit.tscn` & `scenes/units/target_dummy.tscn`
  * Ensure root bodies use `CharacterBody2D` with properly sized `CollisionShape2D` (circle/capsule radius matching unit footprint) and consistent Physics Layers/Masks (e.g., Layer 1: World/Obstacles, Layer 2: Units).
  * Configure `NavigationAgent2D` on `test_unit.tscn` with `avoidance_enabled = true`, appropriate `radius`, `neighbor_distance`, `max_neighbors`, and `time_horizon`.
* `scripts/units/unit.gd`
  * Wire `NavigationAgent2D` local avoidance (`navigation_agent.set_velocity(desired_velocity)` → `_on_velocity_computed(safe_velocity)` → `velocity = safe_velocity` → `move_and_slide()`).
  * Ensure each unit maintains its own independent navigation target and path recalculation rather than sharing a single path or destination point.
  * Add arrival settling logic: when near destination (or blocked by already-settled allies around the destination), transition cleanly to `IDLE` so squads don't endlessly push or orbit a single point.
  * Add soft separation nudge or obstacle handling against static `target_dummy` bodies so units path around dummies rather than getting stuck on corners.
* `scripts/controllers/selection_controller.gd`
  * **Control Group Management:** Maintain a dictionary mapping group numbers `1..9` to arrays of valid `Unit` references (`var control_groups: Dictionary = {}`). Automatically prune freed/dead units (`!is_instance_valid(u)`) when recalling or modifying groups.
  * **Smart-Cast `A` Key:** Remove the two-step "armed attack-move waiting for left-click" state. On `A` key press (when not holding `Ctrl`/`Shift`/`Alt`), convert mouse screen position to world coordinates:
    * If an `ENEMY` entity is under the cursor → issue `command_attack_target(enemy)` to selected units.
    * Otherwise → issue group `command_attack_move` around the cursor world position and spawn the Attack-Move visual marker at the cursor.
  * **Group Destination Offsets:** When issuing a `Move` or `Attack-Move` order to $N > 1$ selected units, compute small, deterministic radial/ring offsets around the target click point (scaled by unit collision radius) so each unit navigates to its own nearby slot rather than converging on one pixel.
* `ui/hud/sandbox_debug_panel.gd` & `ui/hud/sandbox_debug_panel.tscn` (Optional Lightweight Feedback)
  * Display active control group badges/counts (`[1]: 4`, `[2]: 2`) or brief HUD feedback so group assignments are easy to verify during sandbox testing.

---

## 3. Detailed Behavior Specifications

### A. Collision, Individual Pathing & Arrival Settling (`unit.gd`)
1. **Physics Layers:**
   * Place `test_unit` and `target_dummy` on the `Units` physics layer and mask against both `World` and `Units` so `move_and_slide()` resolves physical overlap cleanly.
2. **Independent Navigation & RVO Avoidance:**
   * Each `Unit` instance owns its own `NavigationAgent2D` node (`avoidance_enabled = true`).
   * During `MOVING`, `ATTACK_MOVING`, and `ATTACKING_TARGET` (while closing distance), compute `desired_velocity` toward `navigation_agent.get_next_path_position()`, pass it to `navigation_agent.set_velocity(desired_velocity)`, and apply `safe_velocity` inside the `velocity_computed` signal callback before calling `move_and_slide()`.
3. **Preventing Destination Pile-Ups:**
   * **Step 1 (Order Distribution):** In `selection_controller.gd`, when $N$ units receive a ground Move or Attack-Move at `center_pos`, assign each unit an offset target (`center_pos + offset_i`) arranged in concentric rings spaced by `~2.2 * unit_radius` (clamped/projected onto the valid navigation mesh via `NavigationServer2D.map_get_closest_point()`).
   * **Step 2 (Arrival Threshold):** Increase `target_desired_distance` slightly (or check if distance to assigned target is within threshold while colliding with a friendly unit already in `IDLE`) so arriving units settle immediately instead of vibrating.

### B. Control Group Hotkeys (`selection_controller.gd`)
Handle keys `KEY_1` through `KEY_9` in `_unhandled_input(event)` (filtering out echo events):
* **`Ctrl + [1–9]`:** If `selected_units` is non-empty, set `control_groups[num] = selected_units.duplicate()`. (Optional: if `selected_units` is empty, either clear group `num` or ignore—keep behavior explicit and consistent.)
* **`Shift + [1–9]`:** For each unit in `selected_units`, append to `control_groups[num]` if not already present.
* **`Alt + [1–9]`:** Remove any units present in `selected_units` from `control_groups[num]`.
* **`[1–9]` (No modifiers):** Prune invalid/dead instances from `control_groups[num]`. If non-empty, replace current selection with `control_groups[num]` and update selection visuals. *(Check modifier order so `Ctrl+1`, `Shift+1`, and `Alt+1` are evaluated before plain `1`.)*

### C. Smart-Cast Attack-Move (`A` Key)
* Pressing `A` (with no modifier keys held and at least one `PLAYER` unit selected):
  1. Queries the world point under the mouse cursor (`get_global_mouse_position()`).
  2. Checks if an `ENEMY` collider exists at the cursor point (using the same point-query helper used for right-click enemy targeting).
  3. If an enemy is under the cursor, commands all selected units to focus-fire that enemy (`ATTACKING_TARGET`) and spawns the target-lock marker.
  4. Otherwise, distributes group destination offsets around `cursor_world_pos`, commands selected units to `ATTACK_MOVING` to their respective offsets, and spawns the Attack-Move marker at `cursor_world_pos`.

---

## 4. Verification Checklist for `agy`

Before concluding this task, verify in `milestone_0_test.tscn`:
- [ ] Spawning 10+ player units in the same area pushes them apart cleanly without stacking sprites on top of one another.
- [ ] Ordering 10+ selected units to move or attack-move to a single location causes them to fan out smoothly around the destination and settle into `IDLE` without endless jittering.
- [ ] Units route around stationary `target_dummy` obstacles rather than getting stuck trying to walk through them.
- [ ] Selecting units and pressing `Ctrl+1` assigns them to group 1; selecting additional units and pressing `Shift+1` appends them; selecting a subset and pressing `Alt+1` removes only that subset; pressing `1` selects the remaining group members cleanly even after a unit in the group is destroyed.
- [ ] Moving the mouse over an open area and pressing `A` immediately triggers Attack-Move toward the cursor without needing a left-click; hovering over a target dummy and pressing `A` immediately orders selected units to attack that dummy.