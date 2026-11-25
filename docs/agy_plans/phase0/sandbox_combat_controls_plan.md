# Milestone 0.5 Plan: Sandbox Combat, Target Dummies & Tactile Unit Commands

**Target Directory:** `docs/agy_plans/01_sandbox_combat_and_controls.md`
**Primary Scene:** `res://scenes/test/milestone_0_test.tscn`
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`

---

## 1. Objective & Scope
Expand the current Milestone 0 test scene into a responsive **combat & micro sandbox** before introducing economy, buildings, or AI behavior. This phase validates that selection, movement, target acquisition, and RTS command hotkeys feel snappy and predictable.

### In Scope
1. **Debug Spawning Tools:** Spawn player `test_unit` instances and static enemy **Target Dummies** on demand inside `milestone_0_test.tscn`.
2. **Faction / Team Ownership:** Distinguish `PLAYER` vs. `ENEMY` entities cleanly so selection and targeting respect team ownership.
3. **Core Combat & Health Loop:** Basic weapon range, attack cooldown, projectile or instant-hit damage feedback, health tracking, and death cleanup.
4. **Standard RTS Command Set:**
   * **Right-Click Ground:** Move to position (clears current attack target).
   * **Right-Click Enemy:** Focus-fire specific target (pursues until within weapon range, then attacks).
   * **`A` + Left-Click (Attack-Move):** Move toward target point while automatically engaging any enemy entering aggro/weapon range along the way; resumes moving toward destination once nearby enemies are cleared.
   * **`S` (Stop):** Immediately halts movement and clears current orders/targets.
   * **`H` (Hold Position):** Halts movement and locks position; attacks enemies entering weapon range without chasing.

### Out of Scope (Do Not Build Yet)
* Enemy AI movement or return fire (dummies remain stationary targets).
* Economy resources (Biomass, Silica, Compute, Bandwidth) or production queues.
* Automated unit formations or splitting algorithms.

---

## 2. File & Architecture Plan
Keep existing project conventions intact (`scripts/data/`, `scripts/units/`, `scripts/controllers/`, `ui/overlays/`, `scenes/`):

### Existing Files to Extend
* `scripts/data/unit_data.gd` & `resources/units/test_unit_data.tres`
  * Add combat & ownership fields: `max_hp: float`, `attack_damage: float`, `attack_range: float`, `aggro_range: float`, `attack_cooldown: float`.
* `scripts/units/unit.gd` & `scenes/units/test_unit.tscn`
  * Add `team` export/property (`enum Team { PLAYER, ENEMY }`).
  * Implement an explicit command state machine (`IDLE`, `MOVING`, `ATTACK_MOVING`, `ATTACKING_TARGET`, `HOLD_POSITION`).
  * Add health bar or visual hit-flash feedback and clean `queue_free()` on `hp <= 0`.
* `scripts/controllers/selection_controller.gd`
  * Restrict drag-box and multi-select to `Team.PLAYER` units (allow single-clicking an `ENEMY` dummy only for inspection if desired, never issuing move/attack commands to enemies).
  * Support command modes: default cursor vs. armed `attack_move` targeting cursor (`A` pressed, awaiting Left-Click; Right-Click or `Escape` cancels armed `attack_move`).
  * Route `Right-Click` on enemy collider → `command_attack_target(enemy)` vs. ground → `command_move(pos)`.
  * Route `S` → `command_stop()` and `H` → `command_hold_position()` across all currently selected player units.
* `ui/overlays/move_marker.gd`
  * Differentiate visual feedback for standard Move (cyan/green Technozen pulse) vs. Attack-Move / Target Lock (amber/red pulse).

### New Files to Create
* `scenes/units/target_dummy.tscn`
  * Stationary enemy unit (`Team.ENEMY`) with distinct silhouette/color, visible HP bar, collision shape for click/box targeting, and hit flash on taking damage.
* `scripts/controllers/sandbox_spawner.gd` & `ui/hud/sandbox_debug_panel.tscn`
  * Lightweight on-screen sandbox overlay (hotkeys + clickable buttons) in `milestone_0_test.tscn` to:
    * Spawn 1 or 5 `PLAYER` test units near cursor / spawn point.
    * Spawn 1 or 3 `ENEMY` target dummies at cursor or preset cluster.
    * Clear all dummies / reset sandbox entities.

---

## 3. Detailed Behavior Specifications

### A. Unit Command State Machine (`unit.gd`)
1. **`IDLE`:** Unit stands still; auto-engages enemies entering `attack_range` while idle (unless explicitly placed in `HOLD_POSITION`, where it will never step forward to chase).
2. **`MOVING`:** Navigates via `NavigationAgent2D` to destination; ignores enemies until arriving (`IDLE`).
3. **`ATTACK_MOVING`:** Navigates toward destination; every physics tick, scans for nearest `ENEMY` within `aggro_range`. If found, pursues and attacks until target dies or leaves leash/aggro range, then resumes navigation to original destination.
4. **`ATTACKING_TARGET`:** Focuses a specific target reference (`is_instance_valid(target)`). Moves into `attack_range` if out of range, stops and fires on `attack_cooldown` when in range, and transitions to `IDLE` if target dies.
5. **`HOLD_POSITION`:** `velocity = Vector2.ZERO` (never pathfinds). Scans for enemies strictly within `attack_range` and attacks them while stationary.

### B. Input & Targeting Edge Cases
* **Armed Attack-Move (`A` key):** Pressing `A` with player units selected arms Attack-Move mode (shows subtle targeting cursor/reticle). Left-clicking ground issues `ATTACK_MOVING` to cursor; left-clicking an enemy issues `ATTACKING_TARGET` on that enemy; Right-Click or `Esc` cancels armed mode without issuing an order.
* **Dead Target Cleanup:** Always guard target references with `is_instance_valid(current_target)` before reading position or dealing damage so destroyed dummies never cause null-reference errors.
* **Input Map (`project.godot`):** Register explicit InputMap actions (`cmd_attack_move`, `cmd_stop`, `cmd_hold`) rather than hardcoding raw keycodes in `_unhandled_input`.

---

## 4. Verification Checklist for `agy`
Before finishing this task, verify in `milestone_0_test.tscn`:
- [ ] Spawning multiple player units and multiple target dummies works cleanly via sandbox controls.
- [ ] Drag-selecting across mixed player units and enemy dummies selects **only** player units.
- [ ] Right-clicking a specific dummy causes selected units to walk into range, fire until the dummy is destroyed, and stop cleanly without errors.
- [ ] Pressing `A` + Left-Click behind a group of dummies causes units to walk forward, engage dummies sequentially along the path, and continue to the destination once all dummies in range are destroyed.
- [ ] Pressing `S` immediately halts moving/attacking units; pressing `H` locks units in place so they fire at dummies inside weapon range without stepping toward out-of-range dummies.