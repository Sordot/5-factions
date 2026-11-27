# Milestone 4.5 — System Overhaul #2: Next-Gen Combat Simulation & Abilities

**Prerequisite:** Milestone 4.4 (System Overhaul #1: Movement, Steering & Pathing) verified and working cleanly.

**Goal:** Overhaul combat resolution, ordnance simulation, status effects, abilities, turrets, and Optical Tethers into a deterministic, zero-cheat, faction-agnostic combat engine ready for 1v1, 3P FFA, 4P late-game battles, and Factions #4–#5:

1. **Unified `CombatTargeting`, Crisp Cadence, Continuous Beam Lock & Fire-on-the-Move Foundation (`CombatTargeting`, `CombatComponent`, `Unit`, `UnitData`):** Deduplicate target validation/scoring across units, turrets, and abilities; fix 2v2 alliance threat scoring; carry fractional `delta` overshoot across windup -> cooldown; add `+12 px` windup completion grace; allow continuous beams to tick smoothly after initial lock-on without windup stutter; preserve `Focus Alignment` pre-charge onto the first locked target; and lay down opt-in `can_fire_while_moving` engine support for future factions.

2. **Deterministic Simulation Ordnance & Radial AoE Damage Falloff (`CombatOrdnanceManager`, `CombatVFX`, `CombatComponent`, `TurretComponent`, `AbilityComponent`):** Decouple mortar shell and `Solar Convergence` damage resolution out of render-thread pooled `CombatVFX` nodes into a dedicated `_physics_process` `CombatOrdnanceManager` with smooth radial distance falloff (100% inner lethal core tapering cleanly to an outer edge floor) and diegetic inner-core telegraph rings.

3. **Hardened `StatusEffectComponent` & Double-Multiplier Bugfix (`StatusEffectComponent`, `Unit`):** Fix `Unit.take_damage()` applying `damage_taken_mult` twice to unshielded hull HP; upgrade temporary shields to a multi-barrier stack (shortest-duration absorbs first); add dirty-flag modifier caching; and add `category`, `stack_policy`, and `dispel()` hooks.

4. **Hardened `AbilityComponent` & Data-Driven `AbilityData` (`AbilityComponent`, `AbilityData`):** Gate all offensive autocasts and pending `UNIT_TARGET` casts on real Fog-of-War vision, `TeamManager.are_enemies()`, and `is_abilities_blocked()`; include `destructible_barricades` in offensive AoE abilities; and add explicit `target_filter` and `can_cast_while_moving` fields.

5. **Zero-Idle-Cost, Flicker-Free `OpticalTetherSystem` & Faction-Agnostic `TurretComponent`:** Track emitters via an explicit `"tether_emitters"` group (O(1) exit when zero emitters exist), add `24 px` link hysteresis to eliminate kiting flicker, and strip hardcoded `GENESIS_V2` unit IDs out of `TurretComponent`.

**Hard Design Guardrails (MUST PRESERVE):**

* **Zero Overkill-Prevention Automation:** Do **not** add incoming-lethal-damage reservation or smart overkill skipping. Manual target splitting remains a core player skill.

* **Zero Skill-Cap Automation:** No stealth/cloaking, no auto-formations/role-sorted formations, no auto-loop production, standard worker construction only.

* **No Unintended Stat Rebalancing:** Do **not** alter base unit/building HP, shields, armor, direct weapon damage, ranges, speeds, or costs. *(Only the unintended double `damage_taken_mult` bug is fixed, and AoE splash gains the intentional radial falloff curve.)*

* **100% Procedural Pipeline & 4P Performance Guard:** Reuse scratch arrays with `SpatialGrid.query_units_into(...)`, cache `FogOfWarSystem` references cleanly instead of calling `get_first_node_in_group()` per candidate, and ensure zero leaked ordnance entries on rematch/scene change.

## Phase A — Unified `CombatTargeting`, Crisp Cadence, Continuous Beam Lock & Fire-on-the-Move

### A.1 Shared `CombatTargeting` Helper (`scripts/units/combat_targeting.gd`)

Create `class_name CombatTargeting extends RefCounted` to eliminate duplicated targeting, priority, and Fog-of-War logic across `CombatComponent`, `TurretComponent`, and `AbilityComponent`:

* **Constants:** `TIER_COMBAT_UNIT = 1`, `TIER_SUPPORT_OR_ECON = 2`, `TIER_BUILDING = 3`.

* **Shared Methods:**

  * `static func are_teams_hostile(team_a: int, team_b: int) -> bool`

  * `static func are_teams_allied(team_a: int, team_b: int) -> bool`

  * `static func is_world_pos_visible_to_team(fog: FogOfWarSystem, observer_team: int, world_pos: Vector2) -> bool` *(accepts a pre-resolved `fog` ref so hot target scans never call `get_first_node_in_group("fog_of_war")` inside inner loops!)*

  * `static func get_entity_radius(entity: Node2D) -> float` *(handles `Unit`, `Building`, and `destructible_barricades`)*

  * `static func distance_between_edges(origin_pos: Vector2, origin_radius: float, target: Node2D) -> float`

  * `static func is_armored_target(target: Variant) -> bool`

  * `static func get_priority_tier(candidate: Variant) -> int` *(100% data-driven via `u.data.is_worker_class()`, `u.data.has_tag(&"support")`, `u.data.has_tag(&"dummy")`, and `u.data.attack_damage > 0.0` — permanently removing hardcoded `GENESIS_V2` IDs!)*

  * `static func can_team_target_entity(observer_team: int, target: Node2D, fog: FogOfWarSystem) -> bool` *(validates alive/not-staffed/not-destroyed, hostility via `are_teams_hostile`, `&"untargetable"` / `&"phase_invulnerable"` tags, and strict high-ground/fog vision via `is_world_pos_visible_to_team`)*

  * `static func score_target_candidate(observer_node: Node2D, observer_team: int, candidate: Node2D, dist: float, max_range: float, prefers_armored: bool) -> float` *(fixes 2v2 allied defense scoring by using `are_teams_allied(observer_team, target_team)` instead of `==`!)*

### A.2 Crisp Attack Cadence, Windup Grace & Seamless Beam Lock (`scripts/units/combat_component.gd`)

1. **Cached References & Scratch Array:**

   * Cache `var _fog_cache: FogOfWarSystem = null` lazily (refreshing only if `not is_instance_valid(_fog_cache)`), and hold a reusable `var _scratch_units: Array = []` for `SpatialGrid.query_units_into(...)` inside `find_nearest_enemy(...)` and `_apply_line_pierce_damage(...)`.

2. **Zero-Frame-Loss Overshoot & `+12 px` Windup Completion Grace:**

   * Add `const WINDUP_RANGE_SLOP: float = 12.0`.

   * Add `func is_within_windup_completion_envelope(owner_unit: Unit, target: Variant) -> bool`: validates `is_valid_target(owner_unit, target)` and checks `dist <= owner_unit.get_effective_attack_range() + WINDUP_RANGE_SLOP` and `dist >= maxf(0.0, owner_unit.get_effective_min_attack_range() - 4.0)`.

   * Starting an attack still requires strict `is_within_attack_envelope()`, while an already-started `WINDUP` uses `is_within_windup_completion_envelope()` so kiting targets stepping 1-10 px out of range mid-swing do not cause frustrating canceled shots.

   * In `process_attack_at(owner_unit, target, delta)`:

     * Track leftover `overshoot = maxf(0.0, delta - _windup_timer)` when `WINDUP` finishes and subtract `overshoot` directly from the newly assigned `_attack_cooldown_timer` inside `_execute_weapon_shot(...)` so weapon cadence is exact regardless of physics tick alignment!

3. **Seamless Post-Lock Continuous Beam Ticking & `Focus Alignment` Pre-Charge Fix:**

   * Add `var _beam_precharge_pending: bool = false`.

   * In `boost_beam_ramp_fraction(owner_unit, fraction)`:

     * Add the ramp boost to `_beam_ramp_elapsed` and refresh `_beam_grace_timer`.

     * If `_beam_lock_target == null`: set `_beam_precharge_pending = true`.

   * In `process_attack_at(owner_unit, target, delta)`:

     * When `owner_unit.data.is_continuous_beam`, `_attack_cooldown_timer <= 0.0`, and `attack_phase != AttackPhase.WINDUP`:

       * Check if already continuously locked onto this exact target (`_beam_lock_target == target_node and _beam_ramp_elapsed > 0.0`).

       * If **already locked**: skip `WINDUP` completely and call `_execute_weapon_shot(owner_unit, target_node)` immediately (carrying any cooldown overshoot) so continuous beams tick seamlessly without stuttering!

       * If **first lock-on** (new target or fresh engagement): run the normal initial `WINDUP` once, then tick smoothly on every subsequent pulse while locked.

   * In `_execute_weapon_shot(owner_unit, target_node)` (continuous beam branch):

     * When `_beam_lock_target != target_node`:

       * `_beam_lock_target = target_node`

       * If `_beam_precharge_pending`: keep the pre-charged `_beam_ramp_elapsed` and set `_beam_precharge_pending = false` (fixing `Focus Alignment` being wiped on first lock-on!).

       * Else: reset `_beam_ramp_elapsed = 0.0`.

   * In `tick_beam_decay()`: if `_beam_ramp_elapsed <= 0.001`, also clear `_beam_precharge_pending = false`.

### A.3 Opt-In Fire-on-the-Move Foundation (`scripts/data/unit_data.gd`, `scripts/units/unit.gd`)

Lay down clean, zero-overhead engine support for future mobile hover/skirmisher units (Factions #4–#5) without changing any existing unit's stutter-step feel:

1. **`scripts/data/unit_data.gd`:**

   * Add under `# Data-driven Weapon, VFX, Audio & UI Profile`:

     * `@export var can_fire_while_moving: bool = false` *(strictly `false` on all current `GENESIS_V2`, `MONOLITH_OS`, and `PRISMA_DEI` units!)*

     * `@export var splash_inner_radius_ratio: float = 0.35` *(100% damage core radius as a fraction of AoE radius)*

     * `@export var splash_edge_damage_ratio: float = 0.45` *(minimum damage multiplier at the outer edge of the AoE splash circle)*

2. **`scripts/units/unit.gd`:**

   * Add `var weapon_aim_angle: float = 0.0` (synced to `body_visual.rotation` for standard units; independently aimed toward `current_target` when `data.can_fire_while_moving == true`).

   * Add helper `func _tick_fire_on_the_move(delta: float) -> void` invoked during `_process_moving()`, `_process_attack_moving()`, and `_process_patrolling()` **only** when `data != null and data.can_fire_while_moving and _can_attack() and combat_component != null`:

     * Acquires/retains an enemy strictly inside `get_effective_attack_range()`, updates `weapon_aim_angle` toward target, and calls `combat_component.process_attack_at(self, current_target, delta)` without halting movement or canceling navigation!

   * In `CombatComponent._execute_weapon_shot()`: compute muzzle direction from `owner_unit.weapon_aim_angle` when `owner_unit.data.can_fire_while_moving` else `owner_unit.body_visual.rotation`.

## Phase B — Deterministic Simulation Ordnance & Radial AoE Falloff

### B.1 `CombatOrdnanceManager` (`scripts/systems/combat_ordnance_manager.gd`)

Create `class_name CombatOrdnanceManager extends Node` (added to group `"combat_ordnance_manager"`, instantiated cleanly by `MatchManager._initialize_match_runtime()` alongside `OpticalTetherSystem`, and cleared cleanly in `MatchManager._prepare_clean_scene_transition()`):

* **Why:** Moves all delayed explosive/artillery/orbital hit resolution into deterministic `_physics_process(delta)` ticks—completely decoupled from render framerate or pooled `CombatVFX` nodes.

* **Shared Radial Falloff Calculation (`static func compute_radial_falloff(edge_dist: float, radius: float, inner_ratio: float, edge_ratio: float) -> float`):**

  ```
  if edge_dist > radius:
      return 0.0
  var inner_r: float = radius * clampf(inner_ratio, 0.0, 1.0)
  if edge_dist <= inner_r or inner_ratio >= 0.999 or edge_ratio >= 0.999:
      return 1.0
  var t: float = clampf((edge_dist - inner_r) / maxf(1.0, radius - inner_r), 0.0, 1.0)
  return lerpf(1.0, clampf(edge_ratio, 0.05, 1.0), t)
  ```

  * *Result:* Direct center hits (inside `inner_r`, default `35%` of radius) deal **100% damage**; units that micro/split outward toward the blast rim take smoothly reduced damage down to **`45%`** (mortars/artillery) or **`50%`** (`Solar Convergence` / offensive AoE abilities), powerfully rewarding dodge and split micro!

* **Shared AoE Damage Resolver (`static func apply_aoe_damage(tree: SceneTree, attacker: Node, attacker_team: int, center: Vector2, radius: float, base_dmg: float, bonus_vs_armored_flat: float, armored_dmg_mult: float, inner_ratio: float, edge_ratio: float) -> void`):**

  * Queries `SpatialGrid.query_entities_in_radius(center, radius, true, true)`.

  * Resolves hostile `Unit`s, hostile `Building`s, and intact `destructible_barricades` uniformly!

  * Computes `edge_dist = maxf(0.0, node.global_position.distance_to(center) - entity_radius)`.

  * Skips if `edge_dist > radius`; scales final damage by `falloff = compute_radial_falloff(edge_dist, radius, inner_ratio, edge_ratio)`.

  * Supports both flat anti-armor bonus (`base_dmg + bonus_vs_armored_flat`, used by units & `Solar Convergence`) and multiplicative anti-armor bonus (`base_dmg * armored_dmg_mult`, used by static turrets).

  * Emits `HitFeedbackOverlay.KIND_ANTI_ARMOR` pips on visible armored targets when anti-armor bonus triggers!

* **Scheduled Ordnance API:**

  * `func schedule_ground_detonation(spec: Dictionary) -> void`:

    * Registers `{ "remaining": delay, "attacker_ref": weakref(attacker), "attacker_team": team, "center": impact_pos, "radius": radius, "inner_ratio": inner_r, "edge_ratio": edge_r, "base_dmg": dmg, "bonus_armored": flat_bonus, "armor_mult": mult, "shake_intensity": shake, "shake_duration": shake_dur, "impact_sfx": sfx_id, "scar_kind": scar_kind, "vfx_color": col }`.

    * In `_physics_process(delta)`: ticks every entry deterministically; when `remaining <= 0.0`, invokes `apply_aoe_damage(...)`, applies battle scar (`battle_scars`), triggers visibility-gated impact SFX & camera micro-shake, and removes the entry via swap-pop.

  * Add a clean `func clear_all() -> void` called during scene reset/rematch and Gauntlet `[R]` retry so no stale shells detonate across retries!

### B.2 Pure-Visual `CombatVFX` & Inner Core Telegraph Ring (`ui/overlays/combat_vfx.gd`)

1. **Decouple Damage Callbacks from `CombatVFX`:**

   * Update `CombatComponent`, `TurretComponent`, and `AbilityComponent` (`Solar Convergence`) to schedule damage strictly via `CombatOrdnanceManager.schedule_ground_detonation(...)` and pass an empty `Callable()` to `CombatVFX.setup_mortar_shell(...)` / `setup_solar_convergence(...)`.

   * Keep `CombatVFX._on_impact` safely functional as a fallback *only* if `CombatOrdnanceManager` is missing from a standalone test scene, and avoid duplicating battle scars when `CombatOrdnanceManager` handles detonation.

2. **Diegetic Inner Lethal-Core Telegraph (`_draw_mortar_shell` & `_draw_solar_convergence`):**

   * Add optional `inner_core_ratio: float = 0.35` parameter (default `0.35`) to `setup_mortar_shell(...)` and `setup_solar_convergence(...)` (`0.40`).

   * While in flight / telegraphing, draw a subtle crisp inner circle at `_radius * _inner_core_ratio` (low-alpha solid fill + thin highlight arc) inside the outer dashed splash ring so players can immediately read the **100% direct-hit core** vs. the **tapered outer falloff ring**!

3. **Data Exports on `BuildingData` & `AbilityData`:**

   * Add `@export var turret_splash_inner_ratio: float = 0.35` and `@export var turret_splash_edge_damage_ratio: float = 0.45` on `BuildingData` (mirrored on `Building` alongside `turret_splash_radius`).

   * Add `@export var splash_inner_radius_ratio: float = 0.40` and `@export var splash_edge_damage_ratio: float = 0.50` on `AbilityData`.

## Phase C — Hardened `StatusEffectComponent` & Double-Multiplier Bugfix

### C.1 Fix Double `damage_taken_mult` Bug (`scripts/units/unit.gd`)

* In `Unit.take_damage(amount, attacker)`:

  * Layer 0 already computes `var remaining: float = amount * maxf(0.0, dmg_taken_mult)`.

  * At **Layer 3 — Hull HP (Mitigated)**: remove the second `dmg_mult` multiplication (`var effective_damage: float = remaining * (1.0 - mitigation)` instead of `remaining * (1.0 - mitigation) * dmg_mult`).

  * *Result:* `Radiant Mark` (`+15%`) and `Aureole Surge` (`+15%`) now deal exact `+15%` amplified damage across barriers, shields, and hull HP instead of `+32.25%` on hull!

### C.2 Multi-Barrier Shield Stack & Dirty-Flag Modifier Cache (`scripts/units/status_effect_component.gd`)

1. **Multi-Barrier Shield Stack:**

   * Replace single `_shield_amount` / `_shield_remaining` / `_shield_label` fields with `var _shields: Array[Dictionary] = []` where each entry has `{"id": StringName, "amount": float, "remaining": float, "duration": float, "label": String}`.

   * Update `add_damage_shield(amount: float, duration: float = -1.0, label: String = "Barrier", source_id: StringName = &"")`:

     * If `source_id` (or `label`) already exists in `_shields`, refresh its amount (`maxf`) and duration cleanly; otherwise append a new independent barrier entry (so `Shield Overcharge` and `Kinetic Barrier` coexist cleanly!).

   * Update `absorb_damage_shield(amount: float, _damage_type: StringName = &"generic") -> float`:

     * Sort/iterate active barriers so **shortest remaining timed barrier absorbs first** (permanent barriers `< 0.0` absorb last), pruning depleted entries cleanly.

   * Update `get_shield_amount() -> float` to return the sum of all active barriers, and `get_active_effects_summary()` to list each active barrier cleanly.

2. **Dirty-Flag Cached Aggregated Modifiers:**

   * Add cached scalars: `_modifiers_dirty: bool = true`, `_c_move_mult`, `_c_attack_mult`, `_c_dmg_dealt`, `_c_dmg_taken`, `_c_bonus_range`, `_c_beam_ramp_mult`, `_c_bonus_refract`, `_c_blocks_abilities`, `_c_armor_delta`, `_c_heal_received_mult`.

   * Recompute once in `_recompute_modifiers_if_dirty()` whenever `_modifiers_dirty == true` (marked dirty on `apply_effect`, `remove_effect`, `clear_all`, or expiration in `tick()`). All hot-path stat getters become O(1) field reads!

3. **Composable Stacking Policies & Dispel API (Ready for Factions #4–#5):**

   * Support optional config keys in `apply_effect(effect_id, config)`:

     * `"category"`: `&"buff"`, `&"debuff"`, or `&"aura"` (inferred cleanly if omitted).

     * `"stack_policy"`: `&"refresh"` (default — replaces/refreshes max duration), `&"strongest"` (keeps stronger magnitude if active), or `&"stack"` (increments `stacks` up to `max_stacks`, scaling additive/multiplicative delta cleanly).

     * `"armor_delta"`: `float` (optional armor buff/shred hook wired cleanly into `Unit.get_effective_damage_reduction()`).

     * `"heal_received_mult"`: `float` (optional anti-heal / heal-amp hook wired cleanly into `Unit.heal()`).

   * Add `func dispel(category: StringName, max_count: int = 99) -> int` removing up to `max_count` matching non-aura effects and marking `_modifiers_dirty = true`.

## Phase D — Hardened `AbilityComponent` & `AbilityData`

### D.1 Data-Driven Filter & Movement Flags (`scripts/data/ability_data.gd`)

Add optional backward-compatible exports:

* `enum TargetFilter { ENEMY, ALLY, ANY, GROUND, SELF }`

* `@export var target_filter: TargetFilter = TargetFilter.ENEMY`

* `@export var can_cast_while_moving: bool = false`

* `@export var splash_inner_radius_ratio: float = 0.40`

* `@export var splash_edge_damage_ratio: float = 0.50`

### D.2 Hardened Autocast, Alliance & Fog Gating (`scripts/units/ability_component.gd`)

1. **Respect Ability Lockouts & Fog of War in `tick_autocast()`:**

   * Use `owner_unit.is_ability_ready(ab)` (which checks `status_effect_component.is_abilities_blocked()`) instead of raw `is_ability_ready(ab)`.

   * Resolve `var fog: FogOfWarSystem = _get_fog_cached(owner_unit)` once per autocast tick.

   * Gate **every** offensive autocast scan (`monolith_suppressive_lock`, `grav_pulse`, `blinding_glare`) through `CombatTargeting.can_team_target_entity(int(owner_unit.team), candidate, fog)` so units **never** auto-cast uphill into fogged high ground!

2. **Fix 2v2 Alliance & Target-Loss Validation in `request_cast()` and `try_complete_pending_cast()`:**

   * Replace `target_unit.team == owner_unit.team` with `TargetFilter`-aware checks using `CombatTargeting.are_teams_hostile(...)` (for `ENEMY`, e.g., `Radiant Mark`) or `CombatTargeting.are_teams_allied(...)` (for `ALLY`) plus strict `CombatTargeting.is_world_pos_visible_to_team(...)` visibility checks!

   * In `try_complete_pending_cast(owner_unit)`: cancel pending `UNIT_TARGET` casts immediately if `pending_target_unit` is dead, staffed, untargetable, or vanished into Fog of War!

   * In `request_cast()`: if `ability.can_cast_while_moving` and already in cast range, execute cleanly without interrupting active movement.

3. **Unified AoE + Radial Falloff + Barricade Support in `_execute_point_aoe()` & `_execute_instant()`:**

   * Route `solar_convergence` detonation through `CombatOrdnanceManager.schedule_ground_detonation(...)` (`inner_ratio = ability.splash_inner_radius_ratio`, `edge_ratio = ability.splash_edge_damage_ratio`).

   * For instant/point offensive AoE damage abilities (`spore_barrage`, `seismic_slam`, `static_pulse`, `grav_pulse`), apply damage via `CombatOrdnanceManager.apply_aoe_damage(...)` so **`destructible_barricades`** take damage consistently and splash damage tapers cleanly with radial falloff—while status debuffs (`grav_pulse`, `blinding_glare`, `static_slow`) still apply across the full AoE radius for crisp tactical reliability!

   * Pass distinct `source_id` keys when applying temporary barriers (`&"shield_overcharge"`, `&"kinetic_barrier"`) so barriers stack independently cleanly.

## Phase E — Zero-Idle-Cost, Flicker-Free `OpticalTetherSystem` & Faction-Agnostic `TurretComponent`

### E.1 `OpticalTetherSystem` (`scripts/systems/optical_tether_system.gd`, `scripts/units/unit.gd`, `scripts/buildings/building.gd`)

1. **Explicit `"tether_emitters"` Group Registration:**

   * In `Unit._ready()`: if `data != null and data.tether_emit_radius > 0.0 and data.tether_max_links > 0`, call `add_to_group("tether_emitters")`.

   * In `Building._ready()` and `Building.begin_construction()`: if `tether_emit_radius > 0.0 and tether_max_links > 0`, call `add_to_group("tether_emitters")`.

   * In `OpticalTetherSystem._recompute_tethers()`: query `get_tree().get_nodes_in_group("tether_emitters")` directly! If empty, clear `active_links` and return immediately in **O(1)** (zero unit/building group iteration in `GENESIS_V2` vs. `MONOLITH_OS` matches!).

2. **`24 px` Link Hysteresis & Zero-Alloc Scratch Queries:**

   * Maintain `var _prev_links_by_emitter: Dictionary = {}` (`emitter_id -> Dictionary of recipient_id -> true`) and reusable `var _scratch_nearby: Array = []` via `SpatialGrid.query_units_into(...)`.

   * Add `const LINK_HYSTERESIS_PX: float = 24.0`.

   * When sorting eligible candidates for an emitter, compute `effective_dist = sqrt(d_sq) - (LINK_HYSTERESIS_PX if was_linked_last_tick else 0.0)` and sort by `(cur_stacks ascending, effective_dist ascending, id ascending)` so links hold rock-steady during kiting instead of ping-ponging between equidistant units!

   * Also allow **2v2 allied combat units** (`TeamManager.are_allies(em_team, int(cand.team))`) to receive tethers if desired, or keep strictly same-team `int(cand.team) == em_team` (preserve current same-team `int(cand.team) == em_team` rule for clean faction identity).

### E.2 Faction-Agnostic `TurretComponent` (`scripts/buildings/turret_component.gd`)

* Delegate `can_target_entity`, `distance_to_target_edge`, `_get_priority_tier`, `_score_candidate`, and `_is_armored_target` to **`CombatTargeting`** (with a lazily cached `_fog_cache` and reusable `_scratch_units` array).

* Permanently eliminate the hardcoded `GENESIS_V2` ID check (`symbiote`, `signal_jammer`, `worker`, etc.) so `Cantor`, `Aegis Relay`, `Servo-Drone`, `Acolyte`, and future Faction #4–#5 workers/supports all classify with 100% accuracy.

* Route mortar turret splash shots through `CombatOrdnanceManager.schedule_ground_detonation(...)` with radial AoE falloff (`turret_splash_inner_ratio`, `turret_splash_edge_damage_ratio`).

## Phase F — Verification & Stress-Test Checklist

1. **Zero Errors & Boot Audit:**

   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.

2. **Double-Multiplier Fix & Multi-Barrier Stack (`milestone_0_test.tscn`):**

   * Cast `Radiant Mark` (`+15%`) on an unshielded `Clone Trooper` / `Votary` and hit it with a known-damage attack: confirm damage increases by **exact `+15%`** (not `+32.25%`).

   * Cast `Kinetic Barrier` (`180`, `7s`) on a `Monolith Dreadnought` and `Shield Overcharge` (`+30`, `6s`) from an `Aegis Relay`: confirm total barrier stacks cleanly (`210`), shortest-duration barrier absorbs damage first, and both labels appear cleanly in inspection telemetry.

3. **Continuous Beam Lock & `Focus Alignment` Pre-Charge:**

   * Lock a `Lens Adjudicator` or `Seraph Cruiser` onto a `Monolith Dreadnought`: confirm initial lock-on runs normal windup once, then subsequent continuous beam ticks fire smoothly with zero windup stutter while locked.

   * Cast `Focus Alignment` on an idle `Lens Adjudicator` *right before* ordering it to attack a target: confirm the `+50%` beam ramp boost carries onto the first locked target instead of wiping to `0%`.

4. **Deterministic Ordnance & Radial AoE Falloff:**

   * Fire `Chrysalis Mortar`, Deployed `Anvil Siege-Walker`, and `Solar Convergence` against a spread line of enemy `TargetDummy`s (one dead center, one mid-ring, one near the outer splash edge):

     * Confirm ground telegraphs display both the outer dashed splash boundary and the subtle inner 100%-core ring.

     * Confirm center dummy takes **100%** damage, mid-ring takes intermediate tapered damage, and outer-edge dummy takes the **`~45-50%`** edge-floor damage.

     * Confirm `Spore Barrage`, `Seismic Slam`, `Static Pulse`, and `Solar Convergence` all damage intact `DestructibleBarricade`s properly.

     * Retry a Micro Gauntlet drill (`[R]`) while mortar shells / `Solar Convergence` are mid-air: confirm `CombatOrdnanceManager.clear_all()` prevents any phantom detonation after reset.

5. **Fog-Aware Autocast, 2v2 Alliance Safety & Flicker-Free Optical Tethers:**

   * Place an enemy squad on a fogged `HighGroundPlateau` above friendly `Null-Grid Projectors`, `Picket Drones`, and `Prism Weavers` with autocast ON: confirm **zero** autocasts fire uphill through Fog of War.

   * In a **2v2** skirmish, attempt to cast `Radiant Mark` on an allied AI unit: confirm it is cleanly rejected.

   * Kite `6x Votary` around `2x Cantor`: confirm Optical Tether lines stay rock-steady without rapid back-and-forth flickering (`24 px` hysteresis), and confirm zero tether overhead in a `GENESIS_V2` vs. `MONOLITH_OS` match.