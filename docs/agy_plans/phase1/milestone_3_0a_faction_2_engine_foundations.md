# Milestone 3.0a — Engine Foundations for Faction #2 (`MONOLITH_OS`)

**Target Workflow:** Implement reusable, **faction-agnostic** engine mechanics required by Faction #2 (`MONOLITH_OS — The Iron Axiom`) without breaking or altering `GENESIS_V2` behavior.  
**Zero-Regression Mandate:** All new `FactionData`, `UnitData`, and `BuildingData` fields default to `0` / `false` / `{}` so existing `GENESIS_V2` resources behave identically to Phase 0.  
**UI Discipline:** Maintain 100% unclipped layout at `1280×720` (Windowed & Fullscreen).  
**Hard Exclusions:** No stealth/cloaking mechanics; no role-sorted squad formations.

---

## Overview of 4 Core Deliverables

1. **Dual-Layer Durability (Unmitigated Regenerating Shields + Hull Armor):** Native regenerating shields on `Unit` and `Building` that absorb **raw, unmitigated damage** before hull armor/mitigation applies, plus world-space & `SelectionHUD` shield bars and `EconomyManager` upgrade hooks.
2. **Faction-Specific Resource Saturation Caps:** `FactionData` bonus harvester overrides per resource type (enabling `MONOLITH_OS` to run **3 Harvesters per `SilicaVein`** while `GENESIS_V2` stays at **2**), integrated into `ResourceNode` slot assignment, perimeter positioning, saturation badges, and inspection telemetry.
3. **Command Hub `Core Overclock` Targeting Ability:** Data-driven building-targeted buff allowing a Command Hub (e.g., `Foundry Core`) to overclock any friendly production/research facility (`2.0×` speed for `15s`, `50s` hub cooldown) with targeting UX, visual pulse/timer, and `ProductionComponent` integration.
4. **Unit `Deploy / Anchor` Stance System:** Data-driven mobile/anchored weapon-swap state machine (`MOBILE` → `DEPLOYING` → `DEPLOYED` → `UNDEPLOYING`) for siege/heavy units, with transition bar, movement lock, stat overrides, and multi-unit command button support.

---

## 1. Dual-Layer Durability: Unmitigated Regenerating Shields

### 1.1 Data Schema Extensions
* **`scripts/data/unit_data.gd` (`UnitData`):** Add exported fields:
  * `@export var max_shield: float = 0.0`
  * `@export var shield_regen_rate: float = 0.0` (shield/sec once out-of-combat delay elapses)
  * `@export var shield_regen_delay: float = 6.0` (seconds after taking any damage before regen starts)
* **`scripts/data/building_data.gd` (`BuildingData`):** Add exported fields:
  * `@export var max_shield: float = 0.0`
  * `@export var shield_regen_rate: float = 0.0`
  * `@export var shield_regen_delay: float = 7.0`
  * `@export var damage_reduction: float = 0.0` (flat or fractional hull mitigation matching `UnitData.damage_reduction` convention—inspect `unit.gd` to keep the exact same formula!)

### 1.2 Upgrade-Ready Hooks in `EconomyManager`
* **`scripts/systems/economy_manager.gd`:** Add three lightweight getters (defaulting to neutral values for now; Plan 3.0c upgrades will hook into them):
  * `get_shield_regen_delay_multiplier(team: int) -> float` (default `1.0`)
  * `get_shield_regen_rate_multiplier(team: int) -> float` (default `1.0`)
  * `get_bonus_armor(team: int) -> float` (default `0.0`)

### 1.3 Runtime Shield & Damage Pipeline (`unit.gd` & `building.gd`)
* Add runtime state on both `Unit` and `Building`:
  * `var max_shield: float = 0.0`
  * `var current_shield: float = 0.0`
  * `var _shield_regen_timer: float = 0.0`
  * Initialize `max_shield = maxf(0.0, data.max_shield)` and `current_shield = max_shield` on spawn/construction completion (for buildings under construction, keep `current_shield = 0.0` until construction completes, or scale up on completion).
* **Exact Damage Resolution Order in `take_damage(raw_amount, attacker, ...)`:**
  1. If `raw_amount <= 0.0`, return early.
  2. **Reset Shield Regen Delay:** Whenever any positive damage is received and `max_shield > 0.0`, set `_shield_regen_timer = data.shield_regen_delay * econ_delay_mult`.
  3. **Layer 1 — Temporary Bonus Barrier (Unmitigated):** If `status_effects != null`, run `remaining = status_effects.absorb_damage_shield(remaining)` first (so temporary abilities like `Kinetic Barrier` / `Aegis Relay` stack cleanly on top of native shields without overwriting `current_shield`).
  4. **Layer 2 — Native Regenerating Shield (Unmitigated):** If `remaining > 0.0` and `current_shield > 0.0`:
     * Subtract `absorbed = minf(current_shield, remaining)` directly from **raw** `remaining`—**do NOT apply `damage_reduction` or armor mitigation to shield damage**.
     * `current_shield = maxf(0.0, current_shield - absorbed)`
     * `remaining = maxf(0.0, remaining - absorbed)`
     * Trigger subtle cyan/amber shield-hit flash feedback (distinct from hull damage flash) if `absorbed > 0.0`.
  5. **Layer 3 — Hull HP (Mitigated):** Only if `remaining > 0.0` after shields are exhausted, apply existing hull mitigation (`damage_reduction` + `EconomyManager.get_bonus_armor(team)` + `deployed_damage_reduction_bonus` if deployed + `StatusEffectComponent.get_damage_taken_multiplier()`) and subtract from `current_hp`.
* **Regeneration Tick (in `_physics_process` / `_process`):**
  * Only run when alive (and constructed, for buildings) and `max_shield > 0.0` and `current_shield < max_shield`.
  * Decrement `_shield_regen_timer = maxf(0.0, _shield_regen_timer - delta)`.
  * When `_shield_regen_timer <= 0.0`, increase `current_shield = minf(max_shield, current_shield + data.shield_regen_rate * econ_rate_mult * delta)`.
* **Helper API (for support units like `Aegis Relay` in Plan 3.0b):**
  * `restore_shield(amount: float) -> float` on `Unit` and `Building` (restores native `current_shield` up to `max_shield`, returns actual restored amount, does not require `_shield_regen_timer <= 0.0`).
  * `has_shields() -> bool` returning `max_shield > 0.0`.

### 1.4 Shield Visuals & HUD
* **World-Space Bars (`unit.gd` / `building.gd` / `entity_visuals.gd`):**
  * When `max_shield > 0.0` and the entity's health bar is visible (or `current_shield < max_shield`), draw a crisp **3 px cyan-blue (`#38BDF8`) shield bar** directly stacked 1 px above the HP bar with the same width.
  * When `current_shield == 0.0` and regenerating delay is active, keep the dark background trough visible if damaged so players can read shield-break state at a glance.
* **`SelectionHUD` (`ui/hud/selection_hud.gd`):**
  * For single-selected units/buildings with `max_shield > 0.0`, display a compact **Shield bar / readout** (`SHD: 40 / 40`) stacked neatly with the existing HP bar without increasing `SelectionHUD` panel height or overflowing `1280×720`.
  * For multi-selection unit portrait tiles, draw a thin 2 px shield pip strip above the HP strip on shielded units.

---

## 2. Faction-Specific Resource Saturation Caps

### 2.1 `FactionData` Extension (`scripts/data/faction_data.gd`)
* Add exported field:
  * `@export var bonus_harvesters_by_resource: Dictionary = {}` *(Maps `StringName` resource type, e.g., `&"silica": 1`, to an integer bonus slot count; empty `{}` for `GENESIS_V2`.)*
* Add helper method:
  ```gdscript
  func get_bonus_harvesters(res_type: StringName) -> int:
      if res_type == &"" or not bonus_harvesters_by_resource.has(res_type):
          return 0
      return maxi(0, int(bonus_harvesters_by_resource[res_type]))
  ```
* *Note on Compute Vent staffing:* `BuildingData.max_staff_slots` already controls how many Engineers/Techs can staff a Compute structure. No extra engine hack is needed for `Logic Monolith`—it will simply configure `max_staff_slots` directly in Plan 3.0b. Verify `building.gd` and `staff_component.gd` honor `data.max_staff_slots` dynamically (no hardcoded `2` or `3` caps).

### 2.2 `ResourceNode` Integration (`scripts/world/resource_node.gd`)
* Add `func get_effective_max_harvesters(team_filter: int = -1) -> int`:
  * Starts with `var cap: int = maxi(1, max_harvesters)`.
  * If `team_filter >= 0` and `TeamManager != null`: resolve that team's `FactionData` (using `TeamManager`'s existing team-faction getter) and add `faction.get_bonus_harvesters(resource_type)`.
  * Return `cap`.
* Update all saturation-aware methods in `resource_node.gd` to use `get_effective_max_harvesters(...)`:
  1. `has_free_slot(team_filter: int = -1)` → compare `get_assigned_count(team_filter) < get_effective_max_harvesters(team_filter)`.
  2. `claim_harvest_slot(worker: Unit, dropoff_pos: Vector2)` → compute `var cap: int = get_effective_max_harvesters(int(worker.team) if worker != null else -1)`. Use the 3-slot hub-facing arc (`[0.0, -0.8378, 0.8378, ...]`) whenever `cap >= 3`, and the 2-slot arc when `cap <= 2`, so a 3rd `MONOLITH_OS` Harvester claims a clean primary perimeter slot on a `SilicaVein`.
  3. `_draw()` saturation pill → compute `cap = get_effective_max_harvesters(viewer_team)` (where `viewer_team` is `TeamManager.get_local_human_team()`) so `MONOLITH_OS` sees `X/3` on Silica Veins while `GENESIS_V2` sees `X/2`.
  4. `get_inspection_data()` → use `get_effective_max_harvesters(viewer_t)` for both the `Saturation` stat string and `get_saturation_color(active_gatherers, cap)`.
* Audit `skirmish_ai.gd` and `gather_component.gd` for any hardcoded `max_harvesters` reads on `ResourceNode` and switch them to `rn.get_effective_max_harvesters(team)`.

---

## 3. Command Hub `Core Overclock` Ability

### 3.1 `BuildingData` Schema (`scripts/data/building_data.gd`)
* Add exported fields:
  * `@export var can_overclock_buildings: bool = false`
  * `@export var overclock_speed_multiplier: float = 2.0`
  * `@export var overclock_duration: float = 15.0`
  * `@export var overclock_cooldown: float = 50.0`

### 3.2 Building & Production Runtime (`building.gd` & `production_component.gd`)
* **On `Building` (`scripts/buildings/building.gd`):**
  * Add state:
    * `var overclock_remaining: float = 0.0`
    * `var overclock_duration_total: float = 0.0`
    * `var overclock_speed_mult: float = 1.0`
    * `var overclock_ability_cooldown: float = 0.0` *(cooldown on the casting hub)*
  * Tick both `overclock_remaining` and `overclock_ability_cooldown` down toward `0.0` in `_process(delta)` / `_physics_process(delta)`. Reset `overclock_speed_mult = 1.0` when `overclock_remaining <= 0.0`.
  * Add methods:
    * `can_cast_overclock() -> bool`: returns `is_constructed and not is_destroyed and data != null and data.can_overclock_buildings and overclock_ability_cooldown <= 0.0`.
    * `is_valid_overclock_target(caster_team: int) -> bool`: returns `is_constructed and not is_destroyed and int(team) == caster_team and (not get_trainable_units().is_empty() or not get_researchable_upgrades().is_empty())`. *(Allows targeting any friendly production or research building—including the Hub itself if desired, or military/tech structures.)*
    * `cast_overclock_on(target_building: Building) -> bool`: validates `can_cast_overclock()` and `target_building.is_valid_overclock_target(int(team))`, applies `target_building.apply_overclock(data.overclock_duration, data.overclock_speed_multiplier)`, sets `overclock_ability_cooldown = data.overclock_cooldown`, plays SFX, and returns `true`.
    * `apply_overclock(duration: float, speed_mult: float) -> void`: sets `overclock_remaining = maxf(overclock_remaining, duration)`, `overclock_duration_total = maxf(overclock_duration_total, duration)`, `overclock_speed_mult = maxf(overclock_speed_mult, speed_mult)`.
    * `is_overclocked() -> bool` and `get_local_production_speed_multiplier() -> float` (returns `overclock_speed_mult` if `overclock_remaining > 0.0` else `1.0`).
* **On `ProductionComponent` (`scripts/buildings/production_component.gd`):**
  * In `tick(owner_building, delta)`: multiply `speed_mult *= owner_building.get_local_production_speed_multiplier()`.
  * Both unit training and upgrade research automatically accelerate by `2.0×` while Overclocked.

### 3.3 Targeting UX, Visuals & HUD
* **`SelectionHUD` (`ui/hud/selection_hud.gd`):**
  * When a friendly constructed building with `data.can_overclock_buildings` is selected, show an **Overclock Facility** command button (hotkey `[E]` or dedicated slot that doesn't collide with unit training hotkeys on the hub).
  * Show remaining cooldown (`CD: 34s`) and disable button while `overclock_ability_cooldown > 0.0`.
  * When inspecting an Overclocked building, display an active status badge (`OVERCLOCKED 2.0× — 11.4s`).
* **`SelectionController` / `CommandRouter`:**
  * Clicking the Overclock button (or pressing its hotkey) enters a lightweight `OVERCLOCK_TARGETING` mode (same cancel semantics as ability targeting: RMB or `Esc` cancels).
  * Hovering over a valid friendly production/research building highlights it with a pulsing **Hazard Amber (`#FF9F1C`)** ring; invalid targets show a muted red cursor/reticle.
  * Left-clicking a valid target executes `caster_hub.cast_overclock_on(target)` (if multiple hubs are selected, pick the first ready hub with `can_cast_overclock()`), exits targeting mode, and plays a tactile capacitor-charge audio cue.
* **World-Space Overclock VFX (`building.gd` / `entity_visuals.gd`):**
  * While `is_overclocked()`, render a pulsing amber perimeter frame/chevrons around the building and a compact amber progress bar or `2×` tag above it so players can track the buff at a glance.

---

## 4. Unit `Deploy / Anchor` Stance System

### 4.1 `UnitData` Schema (`scripts/data/unit_data.gd`)
* Add exported fields:
  * `@export var can_deploy: bool = false`
  * `@export var deploy_duration: float = 1.2`
  * `@export var deployed_attack_damage: float = 0.0` (`> 0.0` overrides `attack_damage`)
  * `@export var deployed_attack_range: float = 0.0` (`> 0.0` overrides `attack_range`)
  * `@export var deployed_min_attack_range: float = 0.0`
  * `@export var deployed_attack_cooldown: float = 0.0` (`> 0.0` overrides `attack_cooldown`)
  * `@export var deployed_aoe_radius: float = 0.0`
  * `@export var deployed_damage_reduction_bonus: float = 0.0`
  * `@export var deployed_weapon_tracer_style: StringName = &""`

### 4.2 State Machine (`scripts/units/unit.gd`)
* Add enum and state:
  ```gdscript
  enum DeployState { MOBILE, DEPLOYING, DEPLOYED, UNDEPLOYING }
  var deploy_state: DeployState = DeployState.MOBILE
  var _deploy_timer: float = 0.0
  ```
* Add API methods on `Unit`:
  * `can_toggle_deploy() -> bool` (`data != null and data.can_deploy and not is_dead`)
  * `is_deployed() -> bool` (`deploy_state == DeployState.DEPLOYED`)
  * `is_deploy_transitioning() -> bool` (`deploy_state == DeployState.DEPLOYING or deploy_state == DeployState.UNDEPLOYING`)
  * `is_movement_locked_by_deploy() -> bool` (`deploy_state != DeployState.MOBILE`)
  * `request_deploy() -> void` / `request_undeploy() -> void` / `toggle_deploy() -> void`:
    * `MOBILE` → `DEPLOYING` (clears active move path, sets `_deploy_timer = maxf(0.1, data.deploy_duration)`, plays pneumatic lock SFX).
    * `DEPLOYED` → `UNDEPLOYING` (sets `_deploy_timer = maxf(0.1, data.deploy_duration)`, plays pneumatic release SFX).
    * Calling `request_undeploy()` while `DEPLOYING` cleanly reverses back to `MOBILE` (and vice versa).
* **Tick transition in `_physics_process(delta)`:**
  * Decrement `_deploy_timer`; on reaching `0.0`, transition `DEPLOYING → DEPLOYED` or `UNDEPLOYING → MOBILE` and `queue_redraw()`.

### 4.3 Movement, Combat & Visual Integration
* **`MovementComponent` (`scripts/units/movement_component.gd`):**
  * If `owner_unit.is_movement_locked_by_deploy()`, zero out velocity and skip navigation steering/separation pushback (anchored units hold ground firmly).
  * **RTS Ergonomics Rule:** Issuing a regular `Move` or `Attack-Move` command to a `DEPLOYED` unit must **NOT** accidentally undeploy it; it remains anchored and ignores movement until explicitly undeployed. (Right-clicking an enemy target within deployed range still sets focus-fire target.)
* **`CombatComponent` (`scripts/units/combat_component.gd`):**
  * Block firing while `owner_unit.is_deploy_transitioning()`.
  * Read weapon stats through helper methods on `Unit`:
    * `get_effective_attack_damage()`, `get_effective_attack_range()`, `get_effective_min_attack_range()`, `get_effective_attack_cooldown()`, `get_effective_aoe_radius()`, `get_effective_weapon_tracer_style()`.
    * When `is_deployed()`, return the `deployed_*` override if `> 0.0` (or non-empty `StringName`), else fall back to base `UnitData` value.
* **World-Space Visuals (`unit.gd` / `entity_visuals.gd`):**
  * While `is_deploy_transitioning()`, draw a compact amber transition progress bar above the unit.
  * While `is_deployed()`, draw 4 corner stabilizer anchors/clamps around the chassis; when selected and deployed, draw a subtle dashed deployed-range ring.
* **`SelectionHUD` (`ui/hud/selection_hud.gd`) & Hotkey:**
  * When selected units include `can_deploy == true` units (matching the active `Tab` subgroup), display a **Deploy / Undeploy** command button (hotkey `[E]` or dedicated ability slot).
  * Multi-select behavior: if any unit in the active subgroup is `MOBILE`, pressing Deploy deploys all mobile ones; if all are `DEPLOYED`, pressing it undeploys all of them.

---

## 5. Verification & Regression Checklist

Run all checks in Godot before marking Milestone 3.0a complete:

1. **Zero Regression (`GENESIS_V2`):**
   * Launch a standard `GENESIS_V2` vs `GENESIS_V2` skirmish on `skirmish_arena_01.tscn` and `skirmish_arena_03.tscn`.
   * Confirm no `GENESIS_V2` units or buildings show shield bars, Biomass caps remain `3`, Silica caps remain `2`, and `Nexus Vat` does *not* display an Overclock button.
2. **Shield Pipeline Test (Sandbox `milestone_0_test.tscn`):**
   * Temporarily test a unit with `max_shield = 40`, `shield_regen_rate = 10`, `shield_regen_delay = 5`, `damage_reduction = 0.5` (or flat equivalent).
   * Verify incoming hits deal **full unmitigated damage** to the shield bar, overflow damage is mitigated on HP, and after 5s out of combat the shield smoothly regenerates to full.
3. **Saturation Cap Test:**
   * Temporarily set `bonus_harvesters_by_resource = { &"silica": 1 }` on a test faction; verify Silica Veins show `0/3`, `pick_best_cluster_node()` assigns 3 harvesters before spilling over, and all 3 claim distinct perimeter slots without colliding.
4. **Core Overclock Test:**
   * Temporarily enable `can_overclock_buildings = true` on a test hub; cast Overclock on a production building queueing a unit and an upgrade; verify `2.0×` speed progression, amber VFX + HUD badge, and `50s` cooldown enforcement on the hub.
5. **Deploy / Anchor Test:**
   * Temporarily enable `can_deploy = true` on a test unit; verify `DEPLOYING` transition bar, movement lock, overridden range/damage/AoE while `DEPLOYED`, non-accidental undeploy on Move click, and clean `UNDEPLOYING` return to mobility.
6. **Layout Check (`1280×720`):**
   * Inspect `SelectionHUD` (single shielded unit, multi-select shielded units, Overclocked building, Deployable unit) in both Windowed `1280×720` and Fullscreen (`F11`) to confirm zero clipping or overflow.