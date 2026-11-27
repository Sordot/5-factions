# Milestone 4.11 — System Overhaul #8: Next-Gen Skirmish AI Commander Overhaul

**Prerequisite:** Milestone 4.10 (System Overhaul #7: Procedural Audio & Soundscape) verified and working cleanly.

**Root-Cause Diagnosis (`MONOLITH_OS` AI Stall):**

* `MONOLITH_OS` starts with **`200 Biomass / 50 Silica / 0 Compute`** and `0` Ore-Crawlers, while `Silica Smelter` costs **`100B / 60S`** and `Assembly Bay` costs **`140B / 95S`**.
* In `AIEconomyManager.manage_economy_and_production()`, **Priority 2** (`if refineries.is_empty()`) executes an unconditional `return` even when `econ.can_afford()` fails—permanently deadlocking the AI before **Priority 4** can ever train an `Ore-Crawler` from `Foundry Core` (which is a Universal Command Hub that accepts Silica drop-offs and trains `Ore-Crawlers` directly!).
* **Zero balance stat changes are needed:** Teaching the AI to bootstrap Silica harvesters from any Universal Command Hub and replacing brittle early `return` statements with non-blocking budget reservation fixes `MONOLITH_OS` permanently and future-proofs Factions #4 and #5.

**Goal:** Overhaul `SkirmishAICommander`, `AIEconomyManager`, `AIArmyController`, `AIScoutIntel`, and `AIBuildPlanner` into a deadlock-proof, fair (zero map-hacking), multi-squad RTS commander across all 3 factions (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`) and all match formats (1v1, 2v2, 3P FFA, 4P FFA):

1. **Deadlock-Proof Macro, Universal Hub Silica Bootstrapping & Adaptive Defense (`AIEconomyManager`, `AIBuildPlanner`, `FactionData`):** Eliminate all hard-`return` macro deadlocks with a non-blocking resource-reservation pass; bootstrap Silica harvesting directly from any Universal Command Hub whenever Silica is needed; widen build-placement spirals with throttled diagnostics; scale up to a 3rd Command Hub; construct **adaptive static defense turrets** (`1` per expansion + `1–2` extra under sustained attack/pressure); and add worker harassment evacuation + base/heavy-unit repair.
2. **Multi-Squad Tactics: Proportional Defense, Flank Raids & Relay Control (`AIArmyController`, `AIScoutIntel`):** Replace single-ball defense interrupts with proportional home defense (`~1.4×` threat strength), peel off opportunistic `2–3` unit flank raid squads on Standard/Brutal to harass opposite-lane mineral lines and capture neutral `SensorRelays`, and hold scouts inside neutral relays long enough (`0.6s`) to flip ownership.
3. **Shared Vision Cache, Fair Fog-Respecting Targeting, Combat Micro & 2v2 Cooperation (`AIScoutIntel`, `AIArmyController`):** Compute allied vision snapshots once per decision tick (closing the salvage fog-peek loophole and halving spatial scans), replace omniscient `select_wave_target()` scans with fair Fog-of-War scouting/targeting, add wounded ranged pull-back & retreat ability triggers, and reinforce 2v2 allied Command Hubs under siege.
4. **Faction-Agnostic Telemetry & Enriched Debug Readout (`SkirmishAICommander`, `AIEconomyManager`, `AIArmyController`):** Remove hardcoded T2 building IDs so `PRISMA_DEI` (`Cathedral Foundry`) and future factions fire T2 transmissions automatically, and expose live macro/squad status in `get_debug_status_line()`.

**Hard Design Guardrails (MUST PRESERVE):**

* **Zero AI Map-Hacking or Hidden Cheats:** AI commanders must strictly obey SC2 high-ground Fog of War rules (no peeking through fog for enemy bases, salvage safety, or deploy targets) and receive zero hidden resource/stat bonuses.
* **Zero Player Formation Automation:** All support-escort trailing, kiting, and raid squad logic stays strictly inside `scripts/systems/ai/`. Do **not** alter human player controls or `CommandRouter`.
* **Standard Worker Construction & Zero Balance Changes:** AI workers build every structure on-site; do **not** alter any unit/building HP, damage, speed, range, or resource costs in `.tres` files.
* **Zero Stealth / Zero Overkill Automation / Zero Auto-Production.**

## Phase A — `MONOLITH_OS` Deadlock Fix, Non-Blocking Macro & Adaptive Defense

### A.1 `String`/`StringName` Key Normalization & `&"turret"` Role (`scripts/data/faction_data.gd`, `scripts/systems/ai_build_planner.gd`)

1. **`scripts/data/faction_data.gd` (`get_ai_building_for_role`):**
   * Check both `ai_build_profile.has(role)` and `ai_build_profile.has(String(role))` so `.tres` manifests using either `StringName` or `String` keys always resolve cleanly.
2. **`scripts/systems/ai_build_planner.gd`:**
   * Add **`&"turret"`** semantic role fallback inside `get_building_for_role(role)` (`if b.has_turret: return b`) and `is_role_building(bldg, &"turret")` (`return bldg.has_turret`) — automatically resolving `Defense Turret`, `Bastion Emplacement`, `Solar Obelisk`, and any future faction's static defense without needing `.tres` edits!
   * Expand `&"counter_foundry"` fallback to accept `b != primary_t1 and b.is_military_production and b.tech_tier <= 2 and b != heavy_t2`.
   * Normalize `String` / `StringName` lookups in `choose_unit_for_building()` (`ai_playstyle_weights`, `ai_counter_units`) and `is_breach_capable()` (`BREACH`).

### A.2 Universal Hub Silica Bootstrapping & Non-Blocking Budget Reservation (`scripts/systems/ai/ai_economy_manager.gd`)

1. **Bind `turret_data` & Track Macro Pressure State:**
   * Add `var turret_data: BuildingData = null` (bound in `bind_from_planner()` via `planner.get_building_for_role(&"turret")`).
   * Add `var last_macro_goal: String = "BOOT"` (displayed in `get_debug_status_line()`), `var _last_block_warn_ms: Dictionary = {}`, and `var _under_pressure_until: float = 0.0` (refreshed to `ai.ai_elapsed + 75.0` whenever base defense triggers or an AI building is damaged/destroyed!).

2. **Rewrite `manage_economy_and_production(econ, core)` with Zero Hard-Return Deadlocks:**
   * Track soft budget reservations: `var res_bio: int = 0`, `var res_sil: int = 0`, `var res_comp: int = 0`, with helper `func _can_spend_unreserved(biomass, silica, compute, costs, res_b, res_s, res_c) -> bool`.
   * **Priority 0 — Emergency Supply Unblock (`bw_used >= bw_cap - 2`):** Always check supply **before** worker training when Bandwidth is at/near cap (`needs_supply and supply_data != null and bw_used >= bw_cap - 1`). If affordable, place `supply_data`; if not yet affordable, reserve `supply_data`'s cost and continue (never hard-returning if another non-conflicting action like Silica harvesting can run!).
   * **Priority 1 — Baseline Worker Core (`total_workers < early_workers`):** Queue workers at `core` if `core.can_train_unit_data(worker_data)` without hard-returning if `core` is busy or supply-capped.
   * **Priority 1.2 — Universal Hub Silica Bootstrapping (THE `MONOLITH_OS` FIX!):**
     * Determine if early Silica mining is needed:
       ```
       var early_silica_needed: bool = (
           (refinery_data != null and silica < refinery_data.silica_cost)
           or (barracks_t1_data != null and silica < barracks_t1_data.silica_cost)
           or (supply_data != null and silica < supply_data.silica_cost)
       )
       var core_trains_harvester: bool = (
           harvester_data != null
           and core.accepts_resource(&"silica")
           and core.can_train_unit_data(harvester_data)
       )
       ```
     * Whenever `total_harvesters < 1` and `core_trains_harvester` and (`early_silica_needed` or `total_workers >= early_workers`):
       * Immediately queue `harvester_data` (`Ore-Crawler` / `Silica Harvester` / `Prism Dredge`) directly at `core`!
       * Because all 3 factions' Command Hubs accept Silica drop-offs (4.0b), the freshly spawned `Ore-Crawler` immediately mines Silica back to `Foundry Core`, lifting `MONOLITH_OS` cleanly past `60S` (`Silica Smelter`) and `95S` (`Assembly Bay`) within seconds!
   * **Priority 1.5 — Proactive Power Lattice Recovery:** Unchanged, except non-blocking if placement fails (reserves `supply_data` cost cleanly).
   * **Priorities 2–5 (Refinery, Supply Buffer, Harvester Saturation, Primary Tier-1 Barracks):**
     * Remove all unconditional `return` traps!
     * For each unbuilt critical structure (`refinery_data` when `refineries.is_empty()`, `supply_data` when `needs_supply`, `barracks_t1_data` when `barracks_list.is_empty()`):
       * If affordable and prerequisites met: attempt `try_place_and_build(...)`.
       * If **not** yet affordable (e.g., waiting for Silica to tick up from `50 → 60` or `95`): reserve its `(biomass_cost, silica_cost, compute_cost)` in `(res_bio, res_sil, res_comp)` so lower priorities (extra workers, vents, extra barracks) cannot cannibalize its funds, while still allowing `Ore-Crawler` training and non-conflicting actions!
     * In **Priority 4 (Harvester Saturation):** Allow training `harvester_data` from `constructed_refinery` **or** `core` (whenever `core.accepts_resource(&"silica")`) so `MONOLITH_OS` reaches full `3/vein` Silica saturation smoothly even before its second Refinery completes!
   * **Priority 6.5 — 2nd & 3rd Expansion Command Hubs:**
     * Keep 2nd hub timing unchanged (`150s` Brutal / `195s` Standard / `270s` Relaxed or main Biomass `< 35%`).
     * Allow a **3rd Command Hub** on Standard/Brutal once `ai.ai_elapsed >= 390.0` (or main Biomass `< 25%`) and `command_hubs.size() < 3` with healthy surplus Biomass (`>= hub_data.biomass_cost + 140`).
   * **Priority 7.2 — Adaptive Static Defense Turrets (`turret_data`):**
     * Active on Standard & Brutal (and Relaxed only if under repeated attack) once `constructed_barracks.size() >= 1` and `turret_data != null` and prerequisites met.
     * Compute per-hub turret target:
       * **Expansion Command Hubs** (`hub != core`): `1` turret baseline (increasing to `2` if `ai.ai_elapsed < _under_pressure_until` or `active_posture == &"ANTI_SWARM"`).
       * **Main Command Hub** (`core`): `0` baseline unless under attack/pressure (`ai.ai_elapsed < _under_pressure_until` or `active_posture == &"ANTI_SWARM"`), in which case `1–2` turrets defending the forward approach / mineral line.
     * Cap total AI turrets at `mini(6, command_hubs.size() * 2)` so AI stays aggressive and never over-turtles.
     * Anchor each turret `165 px` forward from the hub toward the map center / nearest threat vector (inside Power Lattice if `turret_data.requires_power_grid`).

### A.3 Wider Placement Spirals, Returning-Worker Fallback & Throttled Diagnostics (`ai_economy_manager.gd`)

* In `find_valid_build_position()`: expand non-power search radii to `[0.0, 75.0, 125.0, 175.0, 230.0, 290.0, 355.0, 420.0]` with `16` angle steps so tight corners on `Triad Sanctum` or `Procedural Arena` never stall a build.
* In `find_available_worker(near_pos)`: if no idle or outbound gathering worker is found, fall back to the closest returning worker (`GATHER_RETURNING_TO_BASE`) rather than returning `null` and stalling construction!
* In `try_place_and_build()`: if placement fails (`spot == Vector2.INF`) for a critical structure, emit a throttled `push_warning(...)` (max once per 30s per building ID) with exact failure reason (`prereq`, `no_worker`, `no_spot`) for effortless Faction #4/#5 debugging.

### A.4 Worker Harassment Evacuation & Base / Heavy-Unit Repair (`ai_economy_manager.gd`)

1. **`evacuate_harassed_workers(core: Building) -> void`:**
   * Check each AI worker (`can_gather and not auto_gather_on_spawn`) that is `GATHERING` or `IDLE` and took recent damage (`current_hp < get_max_hp() * 0.85`) OR has a visible hostile combat unit within `170 px`:
     * Pull the worker `210 px` away from the nearest hostile toward the safest friendly Command Hub (with a `4.0s` cooldown per worker so it doesn't spam-jitter, then returns to harvesting once safe).
2. **`manage_base_repairs() -> void`:**
   * On Standard/Brutal (when Biomass `>= 60` and Silica `>= 30`): scan for the most damaged constructed friendly Command Hub, production building, turret (`< 80%` HP), or staged heavy mechanical/synthetic unit (`< 75%` HP) that has no hostile combat unit within `240 px` (safe to repair).
   * If no worker/Engineer is already repairing it, assign `1` idle worker/Engineer (or 1 gathering worker if `> 3` workers are gathering) via `unit.command_repair(target, false)`.

## Phase B — Multi-Squad Tactics: Proportional Defense, Flank Raids & Relay Control (`scripts/systems/ai/ai_army_controller.gd`, `scripts/systems/ai/ai_scout_intel.gd`)

### B.1 Proportional Home Defense (Stop Freezing Winning Pushes)

* Add dedicated squad tracking on `AIArmyController`:
  * `var defense_units: Array[Unit] = []`
  * `var raid_units: Array[Unit] = []`
  * `var _raid_target: Vector2 = Vector2.ZERO`
  * `var _raid_cooldown_timer: float = 0.0`
* Upgrade `find_base_perimeter_threat(core)` to return a Dictionary `{"pos": Vector2, "threat_power": float, "hub": Building}` (or `{}` if clear), summing `ai.get_unit_power_weight(hostile)` for all visible/attacking hostiles within the perimeter.
* **Proportional Dispatch:**
  * Notify `ai.economy.note_base_pressure()` whenever a perimeter threat is detected!
  * Compute `needed_power = maxf(2.5, threat_power * 1.45)`.
  * Pull responders from **staging / idle home units first** until assigned defense power reaches `needed_power`.
  * **Only** recall `wave_units` (and flip global `army_state` to `DEFENDING`) if home/staging units provide `< 65%` of `needed_power` OR a Command Hub is below `65%` HP!
  * *Result:* A single enemy scout harassing a natural expansion gets swatted cleanly by `2–3` local defenders while the AI's main 12-unit push keeps hammering the enemy base!

### B.2 Opportunistic Flank Raid Squad & Active Sensor Relay Capture

1. **Flank Raid Squad (`tick_raid_squad(core, tick_dt)` — Standard / Brutal):**
   * Prune dead/invalid `raid_units` each tick; exclude `raid_units` from `collect_staging_combat_units()` and `wave_units`.
   * Once `ai.ai_elapsed >= 135.0`, `_raid_cooldown_timer <= 0.0`, `raid_units.is_empty()`, and available staging combat units exceed `get_target_wave_size() + 2`:
     * Select `2–3` fast mobile units (preferring `&"flanker"` / `&"scout"` / speed `>= 220`: `Stinger`, `Picket Drone`, `Lumen Skiff`, `Votary`).
     * Pick a raid target:
       1. Unclaimed/hostile `SensorRelay` (if not allied), OR
       2. Opposite-lane flank corridor toward a scouted enemy expansion / `last_known_enemy_base` (avoiding intact barricades).
     * Dispatch the raid squad via `command_attack_move`; pull raiders back to `staging_point` if they drop below `40%` strength or encounter overwhelming resistance (`enemy_power > raid_power * 1.6`), then set `_raid_cooldown_timer = 55.0`.
2. **Active Sensor Relay Capture (`ai_scout_intel.gd`):**
   * Track `var _holding_relay: Node2D = null` and `var _relay_hold_timer: float = 0.0`.
   * When `active_scout` arrives within `95 px` of a neutral/hostile `SensorRelay` that is not yet allied-active: pause moving to the next waypoint for up to `1.0s` (until `relay.is_active()` flips to allied control), then resume its scout loop!

## Phase C — Shared Vision Cache, Fair Fog Targeting, Combat Micro & 2v2 Cooperation

### C.1 Shared Per-Tick Vision Snapshot Cache (`scripts/systems/ai/ai_scout_intel.gd`)

* Add cached per-tick dictionaries on `AIScoutIntel`:
  * `var visible_enemy_units: Dictionary = {}` (`instance_id -> Unit`)
  * `var visible_enemy_buildings: Dictionary = {}` (`instance_id -> Building`)
  * `var _vision_cache_elapsed: float = -1.0`
* Add `func refresh_vision_cache(force: bool = false) -> void`:
  * Skips if already computed this decision tick (`is_equal_approx(_vision_cache_elapsed, ai.ai_elapsed)` and not `force`).
  * Collects all allied units, buildings, and active allied `SensorRelays` once, populates `visible_enemy_units` and `visible_enemy_buildings` strictly via `SpatialGrid` + `is_entity_visible_to_ai()`.
* Update `update_scouted_intel()` and `AIArmyController.manage_deploy_micro()` to consume `ai.scout_intel.visible_enemy_units` / `visible_enemy_buildings` directly (eliminating duplicated full-map vision loops!).
* Fix `AIEconomyManager.collect_safe_salvage()`: pass **`respect_fog = true`** to `is_spot_safe()` so AI never peeks through Fog of War to check salvage safety.

### C.2 Fair Fog-Respecting Wave Targeting (`scripts/systems/ai/ai_army_controller.gd`)

* Upgrade `select_wave_target(wave_idx, core) -> Vector2`:
  1. **Active Public Objectives:** Urgent `HyperUplink` denial/capture (unchanged—Hyper-Uplink status is public map telemetry).
  2. **Visible & Scouted Enemy Bases (Zero Fog Cheating!):**
     * Check `ai.scout_intel.visible_enemy_buildings` for enemy Command Hubs / production buildings first.
     * Next check `ai.scout_intel.scouted_intel["last_known_enemy_base"]` (if valid and not already cleared while visible).
  3. **Unexplored Map Spawn Anchors / Quadrants:**
     * Query `spawn_anchors` group (or mirrored opposite arena quadrants if none) excluding friendly bases and recently cleared visible anchors—so the AI genuinely sweeps toward standard enemy base locations and scouts for hidden expansions instead of omnisciently homing in on a secret proxy pylon in unexplored fog!
  4. **Visible Enemy Units Fallback:** Only target enemy units present in `ai.scout_intel.visible_enemy_units`.

### C.3 Ranged Kiting Micro, Retreat Abilities & 2v2 Allied Defense (`ai_army_controller.gd`)

1. **Light Ranged Kiting & Escape Abilities (Standard / Brutal):**
   * During `tick_attacking_state()`: for non-deployed ranged units (`attack_range >= 150.0`, `not is_backline_support_unit`) whose `current_hp < get_max_hp() * 0.50` and `combat_component._attack_cooldown_timer > 0.20`: if a visible melee/short-range hostile is within `90 px`, issue a brief `95 px` step-back away from that hostile (throttled per unit every `2.0s` so they keep firing cleanly!).
   * During `RETREATING` transition: trigger ready escape/defensive self-abilities (`&"solar_step"`, `&"kinetic_barrier"`, `&"adrenal_surge"`) on retreating units so survivors escape cleanly.
2. **2v2 Allied Base Assistance:**
   * In `tick_staging_state()`: if `TeamManager != null` and the AI has an allied team, scan allied Command Hubs for visible hostile threats (`threat_power >= 3.0`) and dispatch up to `50%` of idle staging units to reinforce the ally's hub!

## Phase D — Faction-Agnostic Telemetry & Rich Debug Readout (`skirmish_ai.gd`, `ai_economy_manager.gd`, `ai_army_controller.gd`)

* In `AIEconomyManager.on_ai_building_completed()`: replace hardcoded `synthetics_fabricator` / `siege_gantry` check with **`building.get_tech_tier() >= 2 and building.is_military_production_building()`** (or `heavy_t2_data != null and building.building_type_id == heavy_t2_data.building_id`), fixing `PRISMA_DEI`'s `Cathedral Foundry` and future Faction #4/#5 T2 radio transmissions automatically!
* In `AIArmyController.get_debug_status_line()`: format:
  `"AI [%s]: %s%s | R:%d D:%d | INTEL:%s | ECON:%s"`
  showing Main wave state, Raid squad count (`R`), Home Defense count (`D`), counter posture, and current `ai.economy.last_macro_goal` for instant visibility in Spectator Mode & `SandboxDebugPanel`.

## Phase E — Verification & Playtest Checklist

1. **Zero Errors & Clean Boot Audit:**
   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.
2. **`MONOLITH_OS` AI Deadlock Verification (Primary Fix!):**
   * Launch an **AI-vs-AI Spectator Match** with **`MONOLITH_OS` (AI-01, Standard/Brutal) vs. `GENESIS_V2` (AI-02)** on `skirmish_arena_01` at `2x` speed:
     * Within the first `20–45s`, confirm `MONOLITH_OS` trains `Servo-Drones`, immediately trains an **`Ore-Crawler` directly from `Foundry Core`** to mine Silica past `60S`, builds `Silica Smelter`, `Capacitor Pylon`, and `Assembly Bay`, uses **Core Overclock**, expands to a 2nd `Foundry Core`, builds `Logic Monolith` + `Ballistics Lab` + `Siege Gantry`, deploys `Anvil Siege-Walkers`, and launches coordinated multi-wave pushes!
3. **3-Faction FFA Parity Stress Test (`Triad Sanctum`):**
   * Run a **3P FFA AI Spectator Match** (`GENESIS_V2` vs. `MONOLITH_OS` vs. `PRISMA_DEI`, Brutal) on `skirmish_arena_04.tscn` at `2x` speed for 8–10 minutes:
     * Confirm **all 3 factions** scale workers, Silica, Compute, natural + 3rd expansions, T2 tech (including `PRISMA_DEI` `Cathedral Foundry` T2 radio transmission), and competitive army sizes with zero stalled commanders.
     * Confirm expansions receive **1 defensive turret** (`Defense Turret`, `Bastion Emplacement`, `Solar Obelisk`), and bases under sustained pressure add `1–2` extra defensive turrets without turtling passively.
4. **Multi-Squad Tactics, Worker Survival, Repair & Fair Fog:**
   * Harass an AI mineral line with `2× Stinger` / `Lumen Skiff`: confirm harassed AI workers pull back briefly to safety, a **proportional** local defense squad intercepts (without recalling an entire attacking wave across the map), and an idle worker/Engineer repairs damaged structures afterward.
   * Watch Standard/Brutal AI flank raids and scouts: confirm scouts hold inside neutral `SensorRelays` until captured, flank raiders harass opposite lanes, and hidden proxy structures in unexplored fog are **not** omnisciently targeted until scouted.
   * Run a quick **2v2** (`Player + AI Ally vs. 2 AI`): confirm allied AI sends reinforcements when your Command Hub comes under heavy attack.