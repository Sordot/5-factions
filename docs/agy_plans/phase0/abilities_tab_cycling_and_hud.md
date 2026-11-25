# Plan 03: Unit Abilities, Cooldowns, Subgroup `Tab` Cycling, and Selection HUD

## Objective
Implement a data-driven unit ability and cooldown system, subgroup `Tab` cycling for mixed selections, and a minimal bottom-bar Selection & Command Card HUD in the Milestone 0 sandbox (`scenes/test/milestone_0_test.tscn`).

---

## Architecture & Modularity Guardrails
- **`unit.gd` (~17.8 KB) and `selection_controller.gd` (~14.8 KB) are already sizable.** Keep new ability execution, cooldown tracking, and UI rendering decoupled via `Resource` definitions, signals, and dedicated UI scripts rather than bloating `unit.gd` or `selection_controller.gd`.
- **Signal-driven HUD:** The HUD must subscribe to signals from `selection_controller.gd` and the active subgroup's units—never poll unit internals inside `_process()` across all scene nodes.

---

## 1. Data-Driven Ability Definition (`scripts/data/ability_data.gd`)
Create a custom `Resource` class (`class_name AbilityData`) to define unit abilities cleanly:
- **Properties (`@export`):**
  - `ability_id: StringName`
  - `display_name: String`
  - `hotkey_label: String = "Q"`
  - `cooldown_duration: float = 5.0`
  - `cast_range: float = 250.0`
  - `target_type: TargetType` (`enum TargetType { POINT_AOE, UNIT_TARGET, INSTANT }`)
  - `damage_or_value: float = 35.0`
  - `aoe_radius: float = 64.0`
  - `description: String`
- Create a concrete test resource `resources/abilities/overcharge_pulse.tres` (e.g., `Q` hotkey, 6.0s cooldown, `POINT_AOE` or `UNIT_TARGET`, deals burst damage with a clear visual flash/tracer).
- Extend `scripts/data/unit_data.gd` with:
  - `@export var unit_type_id: StringName = &"test_unit"` (used for grouping in `Tab` cycling)
  - `@export var abilities: Array[AbilityData] = []`

---

## 2. Unit Ability Execution & Cooldowns (`scripts/units/unit.gd` / helper)
- Maintain per-unit cooldown timers keyed by `ability_id` (`Dictionary` mapping `StringName -> float` remaining seconds), decremented cleanly in `_physics_process(delta)`.
- Emit signals when state changes:
  - `signal ability_cooldown_updated(ability_id: StringName, remaining: float, duration: float)`
  - `signal ability_executed(ability_id: StringName, target_pos: Vector2)`
- **Casting Rules:**
  - When a unit receives an ability cast order:
    1. Reject if `remaining_cooldown > 0.0`.
    2. If target is outside `cast_range`, move into `cast_range` first, then execute upon arrival (canceling if a new move/stop order interrupts).
    3. Start cooldown immediately on execution and spawn a lightweight visual effect (reusing or extending `ui/overlays/attack_tracer.gd` or a simple ring pulse).

---

## 3. Mixed-Unit Subgroup & `Tab` Cycling (`scripts/controllers/selection_controller.gd`)
- **Subgroup Ordering:**
  - Group currently selected friendly units by `unit_data.unit_type_id` in deterministic priority/selection order.
  - Track `active_subgroup_index: int = 0` (reset to `0` whenever the selection set changes).
- **`Tab` Input Action:**
  - Add an `ui_cycle_subgroup` input action mapped to `Tab` in `project.godot`.
  - Pressing `Tab` while multiple unit types are selected increments `active_subgroup_index` modulo subgroup count and emits `signal selection_changed(selected_units, subgroups, active_subgroup_index)`.
- **Ability Targeting Flow (`Q`):**
  - Pressing `Q` (or clicking the command card slot) checks the **active subgroup** for an ability bound to `Q` where at least one unit in that subgroup is off cooldown.
  - Enter `TARGETING_ABILITY` cursor mode (showing a range/AoE indicator).
  - Left-clicking confirms the target and issues the ability cast command to the ready unit(s) in the active subgroup (smart-cast style: issuing to the closest ready unit in the subgroup so one press = one cast, rather than blowing every unit's cooldown simultaneously).
  - Right-click or `Esc` cancels targeting mode without clearing selection.

---

## 4. Minimal Selection & Command Card HUD (`ui/hud/selection_hud.tscn` & `.gd`)
Build a clean bottom-screen HUD (`CanvasLayer` / `Control` anchored to bottom) matching the Technozen / Y2K aesthetic:
1. **Left Panel — Unit Portrait & Stats:**
   - Displays active subgroup unit name, count (`xN`), current/max HP, attack damage, and move speed.
2. **Center Panel — Selected Units & Subgroup Tabs:**
   - Displays compact badges/buttons for each selected unit (or subgroup tabs when mixed types are selected), visually highlighting the currently active `Tab` subgroup. Clicking a subgroup tab also switches `active_subgroup_index`.
3. **Right Panel — Command Card Grid (3x2 or 4x2):**
   - Standard command slots (`Move`, `Stop/Hold`, `Attack-Move`, `Patrol`) plus active ability slots (`Q`, etc.) populated from the active subgroup's `UnitData.abilities`.
   - Ability buttons display hotkey label, ability name, and a live cooldown countdown overlay + disabled tint while on cooldown.

---

## 5. Sandbox Spawner Verification (`scripts/controllers/sandbox_spawner.gd`)
- Add a second spawnable friendly unit variant (`resources/units/scout_unit_data.tres` with a distinct `unit_type_id`, faster speed, and either no ability or a different cooldown) bound to a sandbox spawn hotkey/button.
- **Acceptance Criteria:**
  1. Spawning mixed units, box-selecting both types, and pressing `Tab` visibly cycles the highlighted subgroup in the HUD and swaps the Command Card abilities.
  2. Pressing `Q` and clicking a target dummy fires the ability, damages the dummy, triggers the visual effect, and shows a live cooldown countdown in the HUD that blocks recasting until expired.
  3. Canceling targeting with `Esc` or Right-Click exits targeting cleanly.