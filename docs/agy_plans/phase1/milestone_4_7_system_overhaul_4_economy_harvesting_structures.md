# Milestone 4.7 — System Overhaul #4: Next-Gen Economy, Harvesting & Structures

**Prerequisite:** Milestone 4.6 (System Overhaul #3: Vision, Fog of War & Elevation) verified and working cleanly.

**Goal:** Overhaul resource harvesting, economic accounting, production queues, structure lifecycles, and Power Lattice evaluation to eliminate 60 Hz UI churn, bandwidth desync risks, spectator audio leaks, and harvesting micro friction across 1v1, 3P FFA, and 4P late-game economies:

1. **Crisp SC2 Harvesting, Same-Type Cargo Preservation & Self-Balancing Mineral Lines (`GatherComponent`, `ResourceNode`):** Preserve carried resources when manually reassigning a worker between nodes of the same resource type, route cargo returns straight to the nearest drop-off rim edge, align harvest slots cleanly outside Overhaul #1's baked NavMesh resource cutouts, auto-bounce workers onto unsaturated sibling patches in the same cluster, throttle drop-off re-evaluation cleanly, and viewport-cull saturation badges with dynamic Compute Vent telemetry.

2. **O(1) Desync-Proof `EconomyManager` (`EconomyManager`, `Building`, `Unit`):** Replace full-scene unit/building loops on every spawn/death/queue with incremental O(1) bandwidth accounting, keyed per-building reservation tracking (zero supply-reservation drift), an O(1) constructed-tech building cache that excludes salvaging structures, and a zero-shift rolling 30s income buffer.

3. **Zero-Churn `ProductionComponent`, Immediate Salvage Refunds, Safe Spawning & Smart Hub Rallies (`ProductionComponent`, `Building`, `BuildingRallyController`, `SelectionHUD`, `SelectionTelemetryRenderer`):** Split discrete `queue_changed` from `0.10s` `progress_updated` ticks (stopping 60 Hz HUD button destruction/recreation), carry fractional production overshoot, gate queueing strictly on `is_powered` and `not is_salvaging`, fix Spectator Mode Team-0 audio leaks, immediately refund queues and eject staffed Engineers on Salvage start, add NavMesh-validated perimeter spawning, and make universal Command Hub rallies capability-aware for Silica harvesters.

4. **Single-Pass `BuildingPowerLattice` & Hardened Scaffold Push-Out (`BuildingPowerLattice`, `CommandRouter`):** Replace O(N²) power-grid refresh queries and hardcoded `480 px` / `320 px` radius caps with a single-pass dynamic-radius solver, surface `"UNPOWERED — PAUSED"` production telemetry, and harden scaffold unit push-out against cliffs and arena bounds.

**Hard Design Guardrails (MUST PRESERVE):**

* **Standard Worker Construction Only:** Workers physically construct every structure on-site across all factions.
* **Zero Auto-Production / Zero Skill-Cap Automation:** No auto-looping unit queues, no stealth/cloaking, no auto-formations, no overkill-prevention automation.
* **Zero Balance Stat Changes:** Do **not** alter resource node reserves, harvest durations, carry capacities, unit/building costs, train times, or bandwidth caps.
* **Strict `1280×720` UI Discipline & 100% Procedural Pipeline:** All updated Compute Vent inspection rows, `"UNPOWERED — PAUSED"` production labels, and saturation pills must remain 100% procedural and unclipped in Windowed `1280×720` and Fullscreen (`F11`).

## Phase A — Crisp SC2 Harvesting, Same-Type Cargo Preservation & Self-Balancing Mineral Lines

### A.1 Preserve Cargo Between Same-Type Nodes (`scripts/units/gather_component.gd`)

* In `start_gather(owner_unit, resource_node, is_auto_migration)`:
  * Change the cargo-wipe condition from dropping on any `target_node != resource_node` switch to dropping **only** when switching resource types:
    ```
    var switched_resource_type: bool = (carried_type != &"" and carried_type != resource_node.resource_type)
    if switched_resource_type and carried_amount > 0:
        clear_carried_cargo(owner_unit)
    ```
  * Keep non-gather interrupt commands (`move`, `attack_move`, `build`, `repair`, `salvage`, `staff`, etc.) dropping cargo cleanly as before (`UnitCommandQueue`).
  * Verify that if a worker carrying a full load of Biomass (`carried_amount >= effective_cap`) is manually right-clicked onto a different Biomass node, it immediately transitions to `GATHER_RETURNING_TO_BASE` and returns to the newly chosen node afterward (matching SC2).

### A.2 Direct Rim-Point Drop-Offs & Throttled Mid-Trip Refinery Upgrades (`scripts/units/gather_component.gd`)

1. **Direct Nearest-Rim Drop-Off Pathing:**
   * Replace `_get_approach_point(owner_unit, dropoff_building, ...)` inside `_tick_returning_to_base()` with a lightweight direct rim target:
     * Compute `var to_worker: Vector2 = owner_unit.global_position - dropoff_building.global_position`.
     * Let `var dir: Vector2 = to_worker.normalized() if to_worker.length_squared() > 1.0 else Vector2.RIGHT`.
     * Target `var rim_pt: Vector2 = dropoff_building.global_position + dir * (dropoff_building.footprint_radius + unit_r + 4.0)` (clamped cleanly to arena bounds).
     * *Result:* Because workers mineral-walk frictionlessly in Overhaul #1, they fly straight in and out of the closest Command Hub / Refinery edge instead of looping around the back side to avoid other workers!
2. **Throttled Drop-Off Re-Evaluation (Zero 60 Hz Group Scans):**
   * Add `var _dropoff_recheck_timer: float = 0.0` (reset on state transitions).
   * When `dropoff_building == null` (waiting automated harvester with full cargo): only re-call `_find_nearest_dropoff()` every **`0.50s`** instead of every physics tick!
   * While actively returning cargo (`dropoff_building != null`): every **`0.60s`**, re-check `_find_nearest_dropoff()` and smoothly switch if a newly completed Refinery / Hub is `> 48.0 px` closer than the current drop-off.
   * Update `_find_nearest_dropoff()` to cache the nearest valid drop-off efficiently (skipping unconstructed, destroyed, and salvaging structures).

### A.3 SC2 Mineral-Line Saturation Bouncing (`scripts/units/gather_component.gd`)

Add automatic local-cluster saturation bouncing so excess workers naturally fan across sibling patches without stalling:

* Add helper `func _try_bounce_to_unsaturated_sibling(owner_unit: Unit) -> bool`:
  * Valid when `is_instance_valid(target_node)` and `not target_node.is_depleted()`.
  * Check if `target_node` is currently **over-saturated** for `owner_unit.team` (`target_node.get_assigned_count(int(owner_unit.team)) > target_node.get_effective_max_harvesters(int(owner_unit.team))`).
  * If over-saturated, query `ResourceNode.pick_best_cluster_node(target_node, owner_unit, int(owner_unit.team), 420.0, 420.0, target_node)`.
  * If a sibling node exists inside the same local cluster (`<= 420 px`) and has a free slot (`candidate.has_free_slot(int(owner_unit.team))`):
    * Release `owner_unit` from old `target_node`, assign to `candidate`, update `target_node`, `last_node_position`, and `_claim_slot_on_target(owner_unit)`.
    * Return `true`.
* Invoke `_try_bounce_to_unsaturated_sibling(owner_unit)` right after depositing cargo (before heading back out) and once when entering `_tick_moving_to_node()` if `_claimed_slot_pos` was an overflow slot.

### A.4 NavMesh-Aligned Harvest Slots, SpatialGrid Queries & Viewport-Culled Telemetry (`scripts/world/resource_node.gd`)

1. **NavMesh-Aligned Harvest Slots (`claim_harvest_slot`):**
   * Read the active navmesh `agent_radius` lazily (default `24.0` from `ArenaNavRegion`), and set:
     * `var stand_r: float = maxf(collision_radius + unit_r + 8.0, collision_radius + nav_agent_radius + 4.0)`
   * When scoring each primary/overflow candidate slot `pt` around the hub-facing arc, verify `pt` does not overlap a cliff wall (`HighGroundPlateau.overlaps_cliff_wall`) or another building/resource (skipping blocked slots cleanly so workers never target unreachable corners behind a mineral patch).
2. **`SpatialGrid`-Backed Cluster Selection (`pick_best_cluster_node_from_pos`):**
   * Replace the full `tree.get_nodes_in_group("resource_nodes")` scan with `SpatialGrid.query_resources_in_radius(origin, overflow_radius, false)` (falling back to scene group only if `SpatialGrid == null`).
3. **Viewport-Culled Saturation Badge Polling (`_refresh_saturation_badge_state`):**
   * Before polling mouse position, selection controller, or `get_assigned_count()`, check if `not is_inspected and not _is_highlighted and not is_hovered`:
     * Query the active `Camera2D` world rect (`vp_size / cam.zoom`, padded by `+80 px`).
     * If `global_position` is outside the camera rect: hide badge if shown and return immediately (zero off-screen polling across 30+ map nodes!).
4. **Dynamic Compute Vent Inspection Telemetry (`get_inspection_data`):**
   * For `is_vent == true`:
     * Resolve the local player's faction Compute Hub display name (`FactionData.get_ai_building_for_role(&"compute_hub")`, fallback `"Compute Hub"`) and live bound hotkey (`SettingsManager.get_action_short_label(&"cmd_ability_r")`, fallback `"R"`) instead of hardcoded `"Compute Node [E]"`.
     * Multiply displayed Compute output by `GameConfig.get_yield_multiplier()` (and `surge_multiplier` when surging) so the inspection readout always matches actual economy deposits 1:1.

## Phase B — O(1) Desync-Proof `EconomyManager` (`scripts/systems/economy_manager.gd`)

### B.1 Incremental O(1) Bandwidth Accounting & Keyed Per-Building Reservations

* Add incremental backing dictionaries:
  * `var _team_unit_bw: Dictionary = {}` (`team -> int`)
  * `var _team_provider_bw: Dictionary = {}` (`team -> int`)
  * `var _reserved_by_source: Dictionary = {}` (`source_instance_id: int -> {"team": int, "amount": int}`)
  * `var _reserved_unkeyed: Dictionary = {}` (`team -> int`, backward-compatibility fallback if a caller omits `source_node`)
* **Incremental Registration:**
  * `register_bandwidth_provider(provider, team, amount)`: if already registered, subtract previous amount first; add `amount` to `_team_provider_bw[team]`, update `_bandwidth_providers[id]`, and call `_emit_bandwidth_if_changed(team)` — **O(1), zero scene scans!**
  * `unregister_bandwidth_provider(provider)`: subtract stored amount from `_team_provider_bw[team]`, erase entry, and emit if changed.
  * `register_unit_bandwidth(unit, team, cost)` / `unregister_unit_bandwidth(unit)`: same O(1) delta maintenance on `_team_unit_bw[team]`.
* **Keyed Queue Reservations:**
  * Update `reserve_bandwidth(team: int, amount: int, source_node: Node = null)` and `release_bandwidth(team: int, amount: int, source_node: Node = null)`:
    * When `source_node != null`: accumulate/decrement inside `_reserved_by_source[source_node.get_instance_id()]` and `_bandwidth_reserved[team]`.
    * Add `func clear_source_reservations(source_node: Node) -> void`: immediately releases any remaining reserved bandwidth belonging to `source_node` and erases its key (invoked in `ProductionComponent.cancel_all_and_refund()` and `Building._exit_tree()` so reserved supply can **never** leak or go negative!).
* **Reconciliation Safety Net:**
  * Keep `recalculate_bandwidth(team, excluded_node = null)` as an explicit full-scene reconciliation pass (called only at match init, `reset_economy()`, and post-bootstrap team swaps) that cleanly resyncs `_team_unit_bw`, `_team_provider_bw`, and `_bandwidth_providers` / `_bandwidth_units`.

### B.2 O(1) Constructed-Tech Cache (`_constructed_building_counts`)

* Add `var _constructed_building_counts: Dictionary = {}` (`team: int -> Dictionary[StringName, int]`) and `var _registered_tech_buildings: Dictionary = {}` (`building_id: int -> {"team": int, "type_id": StringName}`).
* Add methods:
  * `func register_constructed_building(building: Building) -> void`: ignores destroyed, unconstructed, or salvaging buildings; increments `_constructed_building_counts[team][building_type_id]` idempotently (guarded by `_registered_tech_buildings`).
  * `func unregister_constructed_building(building: Building) -> void`: decrements count cleanly (erasing at `0`) and removes from `_registered_tech_buildings`.
* Wire `register_constructed_building(self)` in `Building._register_with_economy()` and `Building.cancel_salvage()`, and `unregister_constructed_building(self)` in `Building.start_salvage()`, `Building._destroy()`, and `Building._exit_tree()`.
* Rewrite `has_constructed_building(team, required_building_id) -> bool`:
  * Check `int((_constructed_building_counts.get(team, {}) as Dictionary).get(required_building_id, 0)) > 0` in **O(1)** (automatically excluding salvaging structures so you cannot unlock Tier 2 off a structure being salvaged!).
  * Reset `_constructed_building_counts` and `_registered_tech_buildings` cleanly in `reset_economy()` and rebuild during `_sync_initial_scene_state()`.

### B.3 Zero-Shift Rolling 30s Income Buffer

* Add `var _income_heads: Dictionary = {}` (`team -> { res_type -> int }`).
* In `_prune_income_samples(team, resource_type)`: advance `head` integer index past expired entries (`time < _elapsed_time - INCOME_WINDOW_SEC`) instead of calling `Array.pop_front()` in a loop; compact the array (`arr = arr.slice(head)`) only when `head >= 64` or `head == arr.size()`.
* Update `get_income_rate_per_minute()` to sum from `head` to `arr.size() - 1` cleanly.

## Phase C — Zero-Churn `ProductionComponent`, Immediate Salvage Refunds, Safe Spawning & Smart Hub Rallies

### C.1 Separate Discrete `queue_changed` from Throttled `progress_updated` & Carry Overshoot

1. **`scripts/buildings/production_component.gd`:**
   * Add `const PROGRESS_EMIT_INTERVAL: float = 0.10`, `var _progress_emit_acc: float = 0.0`, and `signal progress_updated(progress: float, duration: float)`.
   * In `tick(owner_building, delta)`:
     * Advance `_elapsed += delta * speed_mult`.
     * If `_elapsed < duration`: accumulate `_progress_emit_acc += delta`; only emit `progress_updated.emit(get_active_progress(), duration)` when `_progress_emit_acc >= PROGRESS_EMIT_INTERVAL` (never emitting `queue_changed` during plain progress ticks!).
     * On completion (`_elapsed >= duration`): carry overshoot (`var overshoot: float = _elapsed - duration`) into `_elapsed = overshoot if not _queue.is_empty() else 0.0` (clamped safely to `< next_duration * 0.95` so rapid fast-tech ticks stay orderly), reset `_progress_emit_acc = 0.0`, and emit `queue_changed` once!
   * Pass `owner_building` as `source_node` into `econ.reserve_bandwidth(...)` and `econ.release_bandwidth(...)`, and call `econ.clear_source_reservations(owner_building)` at the end of `cancel_all_and_refund()`.

2. **`scripts/buildings/building.gd` & `ui/hud/selection_hud.gd` / `ui/hud/selection_telemetry_renderer.gd`:**
   * Add `signal training_progress_updated(building: Building)` on `Building` connected to `production_component.progress_updated` (without firing `status_changed`!).
   * In `SelectionHUD`: connect to `building.training_progress_updated` for the inspected building and call a lightweight `SelectionTelemetryRenderer.update_production_progress_bar(self, building)` that updates **only** `production_label.text` and `production_bar.value` (zero button freeing/rebuilding during active production!).
   * When `building.requires_power_grid and not building.is_powered` and `building.get_training_queue_size() > 0`: format `production_label.text` as `"UNPOWERED — PAUSED (%d%%)" % pct` and tint `_prod_fill_style.bg_color` muted warning amber/crimson so players immediately see their queue is paused, not lost.

### C.2 Strict Power/Salvage Gates & Spectator-Safe Audio (`scripts/buildings/production_component.gd`)

* In `can_queue_unit(...)` and `can_queue_upgrade(...)`: explicitly require `owner_building.is_powered and not owner_building.is_salvaging`.
* Add helper `func _is_local_human_building(owner_building: Building) -> bool`:
  * Returns `TeamManager.is_team_controlled_by_local_human(int(owner_building.team))` if `TeamManager != null` else `(owner_building.team == Unit.Team.PLAYER)`.
* Replace every hardcoded `owner_building.team == Unit.Team.PLAYER` audio/insufficient-resource check in `enqueue_unit`, `enqueue_upgrade`, and `tick` with `_is_local_human_building(owner_building)` so AI-vs-AI Spectator matches never trigger Team-0 click/error/unit-ready SFX!

### C.3 Immediate Salvage Queue Refund & Engineer Ejection (`scripts/buildings/building.gd`)

* In `Building.start_salvage()`:
  * Immediately refund all queued units/upgrades and free reserved Bandwidth:
    ```
    if production_component != null:
        production_component.cancel_all_and_refund(self)
    ```
  * Immediately release any staffed Compute Specialists / Engineers (`eject_engineers()`) so players can evacuate them right away instead of losing them during the 4.0s salvage window.
  * Unregister the building from `EconomyManager`'s constructed-tech cache (`econ.unregister_constructed_building(self)`).
* In `Building.cancel_salvage()`:
  * Re-register in `EconomyManager`'s constructed-tech cache (`econ.register_constructed_building(self)`) and refresh the Power Lattice if `provides_power_grid`.
* Update Salvage tooltip text in `CommandCardBuilder` (`ui/hud/command_card_builder.gd`) to note: `"Immediately refunds queued production and ejects staffed Engineers; refunds 50% structure cost after 4.0s."`

### C.4 NavMesh-Validated Perimeter Spawn Solver (`scripts/buildings/production_component.gd`)

* Upgrade `_spawn_unit_batch(owner_building, unit_scene, batch_count)` with a dedicated `_find_safe_spawn_point(owner_building, preferred_dir, unit_radius, lateral_offset_px, used_points) -> Vector2`:
  1. Read `arena_bounds` from `ArenaNavRegion` (padded inward by `unit_radius + 8.0`).
  2. Test candidate angles starting from `preferred_dir.angle()` and fanning outward in alternating steps (`0, +1, -1, +2, -2, ...` across 16 perimeter directions) at `spawn_dist = owner_building.footprint_radius + unit_radius + 10.0` (and a secondary outer ring `+24.0` if tightly walled).
  3. Reject candidates outside `safe_bounds` or overlapping `terrain_obstacles`, `map_landmarks` with collision, `high_ground_plateaus` cliff walls (`overlaps_cliff_wall`), intact `destructible_barricades`, other `buildings`, non-vent `resource_nodes`, or `used_points` from the same batch.
  4. Snap the winning point gently onto the live NavigationMesh via `NavigationServer2D.map_get_closest_point(nav_map, cand)` (only accepting the snapped point if it stays within `36.0 px` of `cand` and on the same elevation side as `owner_building`, preventing cliff-skipping spawns!).
* *Result:* Even if a player tucks a `Cloning Vat`, `Assembly Bay`, or `Choir Basilica` tightly against a cliff face or mineral line, trained units always emerge cleanly onto open navigable ground.

### C.5 Capability-Aware Universal Command Hub Rallies (`scripts/buildings/building_rally_controller.gd`)

* In `BuildingRallyController.apply_rally_to_unit(building, unit)`:
  * When `building.is_command_hub()` and the spawned `unit` is an automated Silica harvester (`unit.data != null and unit.data.auto_gather_on_spawn and unit.data.allowed_resource == &"silica"`):
    * If the hub is rallied to a **Biomass** `ResourceNode` (or depleted Biomass `_rally_resource_type == &"biomass"`): **do not** send the Silica harvester to walk into the Biomass patch—return early and let `Unit._try_start_auto_gather()` route it directly to the nearest Silica vein!
    * If the hub is explicitly rallied to a **Silica** vein, another compatible target, or a ground point: honor the rally normally.

## Phase D — Single-Pass `BuildingPowerLattice` & Hardened Scaffold Unit Push-Out

### D.1 Single-Pass Power Grid & Dynamic Radius Tracking (`scripts/buildings/building_power_lattice.gd`)

1. **Dynamic Max Radius Tracking (Zero Hardcoded Caps):**
   * Add static fields `static var max_known_power_radius: float = 480.0` and `static var max_known_shield_aura_radius: float = 320.0`.
   * Add `static func note_provider_radius(power_r: float, shield_aura_r: float) -> void` called from `Building._ready()` and `Building.begin_construction()` to expand caps automatically if any structure/upgrade exceeds `480 px` / `320 px`.
   * Use `max_known_power_radius + 64.0` in `is_position_powered_for_team()` and `max_known_shield_aura_radius + 64.0` in `get_shield_regen_delay_speedup_at()`.
2. **Single-Pass O(P + B) `refresh_team_power_grid()`:**
   * Replace nested per-building `SpatialGrid` queries with two clean passes over `tree.get_nodes_in_group("buildings")`:
     * **Pass 1:** Collect all constructed, non-destroyed, non-salvaging buildings for `target_team` where `provides_power_grid and power_radius > 0.0` (excluding `exclude_building`) into a compact local `providers: Array[Building]`, and all `requires_power_grid` constructed buildings for `target_team` into `consumers: Array[Building]`.
     * **Pass 2:** For each consumer `c`, check squared distance directly against `providers` (`d_sq <= prov.power_radius * prov.power_radius`) and call `c.set_powered_state(powered)` if changed.
   * *Result:* Destroying or placing a `Halo Spire` updates an entire 40-building base in microseconds with zero redundant spatial lookups.

### D.2 Hardened Scaffold Unit Push-Out (`scripts/controllers/command_router.gd`)

* Upgrade `CommandRouter.nudge_units_out_of_building(building: Building, bounds: Rect2)`:
  * Skip `is_dead`, `is_staffed`, or `is_movement_locked_by_deploy()` units.
  * For each overlapping unit inside `building.footprint_radius + unit_r + 6.0`:
    * Compute preferred radial outward angle from `building.global_position` to `u.global_position` (deterministic fallback by `u.get_instance_id()` if centered).
    * Test `12` outward perimeter angles (`0, ±30°, ±60°, ...`) at `building.footprint_radius + unit_r + 10.0` to find the first spot inside `bounds` that is clear of `terrain_obstacles`, `high_ground_plateaus` cliffs, other `buildings`, and non-vent `resource_nodes`.
    * Snap gently to NavMesh if valid and within `32.0 px`, move `u.global_position`, and immediately call `SpatialGrid.update_unit(u)` so spatial queries stay 100% synced on the exact placement frame.

## Phase E — Verification & Stress-Test Checklist

1. **Zero Errors & Clean Boot Audit:**
   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.

2. **SC2 Harvesting, Same-Type Cargo Preservation & Mineral-Line Bouncing:**
   * Grab a worker carrying `10` Biomass and right-click a **different Biomass node**: confirm it **keeps its 10 Biomass**, deposits it immediately, and returns to the newly clicked Biomass node.
   * Order a worker carrying Biomass to `Move` or `Build`: confirm it still clears cargo cleanly on non-gather commands.
   * Rally a Command Hub to one Biomass patch and train `8×` workers: confirm returning workers take straight rim-to-rim paths (no looping behind the hub), harvest cleanly at NavMesh-aligned perimeter slots outside the baked resource cutout, and **auto-bounce** onto unsaturated sibling Biomass nodes in the cluster!
   * Build a closer `Alabaster Kiln` / `Silica Condenser` while a `Prism Dredge` / `Silica Harvester` is mid-trip returning to a distant Command Hub: confirm it redirects to the closer Refinery within `0.6s`.

3. **Universal Command Hub Rally Parity & Compute Vent Telemetry:**
   * Rally `Sanctum Core`, `Foundry Core`, and `Nexus Vat` to a Biomass cluster, then train both a **Worker** (`Q`) and a **Silica Harvester / Ore Crawler / Prism Dredge** (`W`): confirm Workers gather Biomass while Silica harvesters route straight to the nearest Silica vein without walking into Biomass.
   * Click a neutral `Compute Vent` as `GENESIS_V2`, `MONOLITH_OS`, and `PRISMA_DEI` (with Normal and High-Yield presets): confirm telemetry shows the player's actual faction Compute facility name, live bound hotkey (`R`), and accurate yield rate.

4. **Immediate Salvage Refund, Unpowered Paused Telemetry & Safe Spawning:**
   * Queue `4×` units + `1×` upgrade in a production building (and staff `2×` Engineers in a Compute facility), then click **Salvage**: confirm **100% of queued resources and reserved Bandwidth refund immediately** on salvage start and staffed Engineers eject immediately (before the 4.0s deconstruction timer finishes).
   * Destroy a `Halo Spire` while a `Choir Basilica` is mid-training: confirm training pauses cleanly, HUD shows **`UNPOWERED — PAUSED (XX%)`**, new queueing is rejected while unpowered, and building a new `Halo Spire` resumes production smoothly from its exact saved percentage.
   * Place a production building tucked tightly against a cliff wall and train a batch of units: confirm every unit spawns on valid walkable ground without clipping into cliffs or buildings.

5. **Zero-Churn Production HUD, O(1) Bandwidth & Spectator Audio Check:**
   * Select an actively producing building and watch queue slot buttons while training progresses: confirm smooth progress bar updates with **zero flicker/re-hover resets** on the cancel buttons.
   * Launch an **AI-vs-AI Spectator Match** (`3P FFA` on `Triad Sanctum` at `2x` speed): confirm **zero** Team-0 click/error/`unit_ready` SFX leaks, rock-solid Bandwidth accounting with zero negative or drifting supply across 5+ minutes of combat and building losses, and smooth frame pacing.