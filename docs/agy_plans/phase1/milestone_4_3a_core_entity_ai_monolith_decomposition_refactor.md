# Milestone 4.3a — Core Entity & AI Monolith Decomposition Refactor

**Prerequisite:** Milestones 4.0b, 4.1, and 4.2 verified and working cleanly.

**Goal:** Decompose the three largest gameplay/simulation monoliths (`scripts/units/unit.gd` at ~108 KB, `scripts/systems/skirmish_ai.gd` at ~97 KB, and `scripts/buildings/building.gd` at ~84 KB) into clean, single-responsibility `RefCounted` helper modules—cutting each core script roughly in half so adding Factions #4 and #5 is fast, safe, and low-regression.

**Non-Negotiable Constraints:**

* **Zero Behavioral or Visual Regressions:** Every combat tick, deploy transition, recoil kick, SC2 high-ground Fog of War retaliation rule, Power Lattice dormancy state, Geothermal Compute Surge multiplier, natural expansion hub build, high-ground AI staging, and AI support escort trailing offset must behave **100% identically** after this refactor.
* **Zero Balance Changes:** Do **not** alter any stat numbers, formulas (including existing damage/shield absorption order), costs, cooldowns, or AI thresholds.
* **100% Public API & Signal Preservation:** Keep all existing `@export` properties, `signal` declarations, group memberships, and public/static method signatures on `Unit`, `Building`, and `SkirmishAICommander` intact (forwarding to extracted helpers) so zero external callers break.
* **Zero Scene `.tscn` Node-Path Breakage:** All extracted helpers are lightweight `RefCounted` classes instantiated in script (not extra scene-tree child nodes that could shift node paths or `@onready` bindings).
* **Hard Guardrails (MUST PRESERVE):** No stealth/cloaking, no role-sorted player formations, no overkill-prevention automation, no auto-loop production, standard worker construction only.

## Target Decomposition Map (4.3a)

| Monolith Script | Extracted `RefCounted` Modules | Slim Coordinator Responsibilities Kept |
| :--- | :--- | :--- |
| `scripts/units/unit.gd` | • `scripts/units/unit_command_queue.gd`<br>• `scripts/units/unit_deploy_controller.gd`<br>• `scripts/units/unit_inspection_builder.gd`<br>• `scripts/units/unit_world_overlay.gd` | Lifecycle (`_ready`, `_physics_process`, `_exit_tree`), damage/healing/shields, stat getters, component wiring, public command facade, and signal emission. |
| `scripts/buildings/building.gd` | • `scripts/buildings/building_power_lattice.gd`<br>• `scripts/buildings/building_world_overlay.gd`<br>• `scripts/buildings/building_inspection_builder.gd`<br>• `scripts/buildings/building_rally_controller.gd` | Lifecycle (`_ready`, `_process`, `begin_construction`, `_complete_construction`, `_destroy`), damage/shield/overclock/salvage, staffing, training facades, and signal emission. |
| `scripts/systems/skirmish_ai.gd` | • `scripts/systems/ai/ai_scout_intel.gd`<br>• `scripts/systems/ai/ai_economy_manager.gd`<br>• `scripts/systems/ai/ai_army_controller.gd` | Lightweight `Node` shell owning `@export` settings, `_planner`, decision tick timer, difficulty/playstyle profile loading, radio transmissions, and shared team/entity query helpers. |

## Phase A — `Unit` Decomposition (`scripts/units/unit.gd`)

### A.1 `scripts/units/unit_command_queue.gd` (`class_name UnitCommandQueue extends RefCounted`)

Extract the command-queue execution and active-destination query pipeline out of `unit.gd`:

* Move logic for:
  * `has_queued_commands(unit: Unit) -> bool`
  * `clear(unit: Unit) -> void`
  * `issue_command(unit: Unit, cmd: Dictionary, append_to_queue: bool) -> bool` *(preserve deploy-lock filtering for `move`/`attack_move`/`patrol`, duplicate `attack_target` queue suppression, and cargo-drop gather cancellation on non-queued interrupt commands)*
  * `advance(unit: Unit) -> bool`
  * `execute_command(unit: Unit, cmd: Dictionary) -> int` *(preserve `CMD_EXEC_FAILED`, `CMD_EXEC_ACTIVE`, `CMD_EXEC_IMMEDIATE_DONE` constants and all 11 command types: `move`, `attack_move`, `attack_target`, `gather`, `return_cargo`, `build`, `staff`, `cast_ability`, `patrol`, `repair`, `salvage`)*
  * `get_active_destination(unit: Unit) -> Variant`
* Keep `var command_queue: Array[Dictionary] = []` and `var active_command: Dictionary = {}` directly on `Unit` (so `CommandQueueOverlay`, `SkirmishAICommander`, and `Unit.is_idle_worker()` continue reading `unit.command_queue` and `unit.active_command` with zero API changes), while `Unit.issue_command()`, `Unit.clear_command_queue()`, `Unit.advance_command_queue()`, and `Unit.get_active_command_destination()` delegate cleanly to `UnitCommandQueue`.

### A.2 `scripts/units/unit_deploy_controller.gd` (`class_name UnitDeployController extends RefCounted`)

Extract the Deploy / Anchor stance state machine and anchor-impact feedback:

* Move logic for:
  * `can_toggle_deploy(unit: Unit) -> bool`
  * `get_deploy_progress(unit: Unit) -> float`
  * `request_deploy(unit: Unit) -> void` *(preserving mid-transition timer reversal, queue/task cancellation, `&"deploy_lock"` SFX, and signal emissions)*
  * `request_undeploy(unit: Unit) -> void` *(preserving windup cancel, `&"deploy_release"` SFX, and signal emissions)*
  * `toggle_deploy(unit: Unit) -> void`
  * `tick(unit: Unit, delta: float) -> void`
  * `trigger_anchor_impact(unit: Unit) -> void` *(pooled `CombatVFX.setup_anchor_thud`, `&"deploy_anchor_lock"` SFX, `1.6 px` camera micro-shake, strictly visibility-gated)*
* Keep `Unit.deploy_state`, `Unit.is_deployed()`, `Unit.is_deploy_transitioning()`, `Unit.is_movement_locked_by_deploy()`, `Unit.request_deploy()`, `Unit.request_undeploy()`, `Unit.toggle_deploy()`, and `Unit.get_deploy_progress()` as thin delegators so external callers and `EntityVisuals` remain untouched.

### A.3 `scripts/units/unit_inspection_builder.gd` (`class_name UnitInspectionBuilder extends RefCounted`)

Extract all HUD inspection telemetry formatting:

* Move `build_inspection_data(unit: Unit) -> Dictionary`, `get_armor_class_label(unit: Unit) -> String`, and `get_command_state_label(unit: Unit) -> String` verbatim—preserving gather cargo bars, damage/range/min-range/AoE/line-pierce strings, deploy status tint, armor mitigation, veterancy rank/kill telemetry, `Lattice Link` stacks, `Tether Anchor` stats, and live `Beam Charge` ramp percentages.
* `Unit.get_inspection_data()` and `Unit.get_armor_class_label()` become one-line delegates.

### A.4 `scripts/units/unit_world_overlay.gd` (`class_name UnitWorldOverlay extends RefCounted`)

Extract the entire ~160-line `Unit._draw()` world-space indicator renderer into static/helper draw calls executing on `canvas: Unit` (preserving `Unit`'s exact local coordinate space, `to_local()`, and `z_index`):

* Move drawing for:
  * Attack-range & min-range dashed rings (mobile and deployed variants)
  * Deployed 4-corner amber/steel stabilizer clamps
  * Shield-hit flash ripple ring
  * `PRISMA_DEI` `radiant_mark` golden reticle & `blinding_glare` ring
  * `rail_lance` windup targeting lock-line telegraph
  * Deploy / Undeploy transition progress bar
  * Colossus Stride elevated ground shadow
  * Fast flanker motion trail (`_trail_points`)
  * Status effect rings (`adrenal_surge`, `static_slow`, `grav_pulse`)
  * Defensive stance leash ring & shield pip
  * Veterancy rank chevron badge beside `HealthBar`
  * `draw_dashed_ring(...)` helper
* `Unit._draw()` reduces to a single call: `UnitWorldOverlay.draw_unit_overlays(self)`.

## Phase B — `Building` Decomposition (`scripts/buildings/building.gd`)

### B.1 `scripts/buildings/building_power_lattice.gd` (`class_name BuildingPowerLattice extends RefCounted`)

Extract the spatial Power Lattice and Capacitor Pylon aura query helpers:

* Move static queries & transition logic:
  * `is_position_powered_for_team(tree: SceneTree, world_pos: Vector2, target_team: int, exclude_building: Building = null) -> bool`
  * `refresh_team_power_grid(tree: SceneTree, target_team: int, exclude_building: Building = null) -> void`
  * `apply_powered_state(building: Building, powered: bool) -> void` *(preserving turret target clearing, 6000 ms throttled local `"%s Unpowered!"` tactical alert, visual dimming refresh, and `status_changed` emission)*
  * `get_shield_regen_delay_speedup_at(tree: SceneTree, world_pos: Vector2, target_team: int) -> float`
* Keep `Building.is_position_powered_for_team(...)`, `Building.refresh_team_power_grid(...)`, `Building.set_powered_state(...)`, and `Building.get_shield_regen_delay_speedup_at(...)` as thin static/instance forwards so `CommandRouter`, `BuildGhostPreview`, `SkirmishAICommander`, and `Unit` require zero changes.

### B.2 `scripts/buildings/building_world_overlay.gd` (`class_name BuildingWorldOverlay extends RefCounted`)

Extract `Building._draw()` into `BuildingWorldOverlay.draw_building_overlays(building: Building)`:

* Move drawing for:
  * Selected Power Lattice radius ring + diamond cardinal nodes
  * Pulsing `UNPOWERED` slash-diamond warning badge
  * Selected Capacitor Pylon shield-regen aura ring + halftone dots
  * Selected turret attack-range / min-range rings & explicit focus-fire target line
  * Active salvage progress bar & perimeter arc
  * Shield-hit flash ripple ring
  * Core Overclock pulsing Hazard Amber perimeter frame, 4 corner chevrons, progress bar & `2x` multiplier tag
  * Fallback rally line & flag when `RallyPointOverlay` is absent
* `Building._draw()` becomes a single call: `BuildingWorldOverlay.draw_building_overlays(self)`.

### B.3 `scripts/buildings/building_inspection_builder.gd` (`class_name BuildingInspectionBuilder extends RefCounted`)

Extract building inspection telemetry and saturation queries:

* Move `build_inspection_data(building: Building) -> Dictionary`, `get_rally_summary(building: Building) -> String`, and `get_cluster_saturation(building: Building) -> Dictionary` verbatim—preserving under-construction stats, Compute Facility Geothermal Surge `2x` telemetry, turret stats, universal Command Hub drop-off readouts (`Biomass / Silica`), production speed/batch readouts, Power Lattice & Optical Tether readouts, Unpowered warning, Overclock countdown, and Salvage timer.

### B.4 `scripts/buildings/building_rally_controller.gd` (`class_name BuildingRallyController extends RefCounted`)

Extract rally target state & spawned-unit dispatch:

* Move rally state (`has_rally`, `rally_position`, `rally_target`, `rally_resource_type`, `rally_target_unit`), unit-death signal tracking, fallback cluster spill-over on depleted rallied nodes, and `apply_rally_to_unit(building: Building, unit: Unit)` cleanly into `BuildingRallyController`.
* Keep `Building`'s public rally methods (`set_rally_position`, `set_rally_target`, `set_rally_target_unit`, `has_rally`, `get_rally_world_position`, `get_rally_target`, `apply_rally_to_unit`) and `rally_changed` signal untouched (and keep `building.rally_target_unit` readable via property getter or synced mirror so `RallyPointOverlay` works identically!).

## Phase C — `SkirmishAICommander` Decomposition (`scripts/systems/skirmish_ai.gd`)

Create `scripts/systems/ai/` (mirroring `scripts/systems/audio/`) and split `SkirmishAICommander` into three clean, focused `RefCounted` modules that hold a weak/direct reference to their owning `ai: SkirmishAICommander`:

### C.1 `scripts/systems/ai/ai_scout_intel.gd` (`class_name AIScoutIntel extends RefCounted`)

* **Owned State:** `active_scout: Unit`, `next_scout_dispatch_time: float`, `scout_quadrant_index: int`, `scouted_intel: Dictionary`, `active_counter_posture: StringName`.
* **Moved Methods:**
  * `manage_early_scouting(core: Building) -> void`
  * `update_scouted_intel() -> void` *(strictly vision-respecting via `FogOfWarSystem.is_entity_visible_to_team`, 90s TTL decay, counter posture selection)*
  * `scan_vision_circle_for_intel(center: Vector2, radius: float, seen_units: Dictionary, seen_buildings: Dictionary) -> void`
  * `is_entity_visible_to_ai(entity: Node2D) -> bool`
  * `is_spot_safe(world_pos: Vector2, radius: float, respect_fog: bool) -> bool` *(unifies `_is_salvage_core_safe` and `_is_expansion_spot_safe` cleanly with a single `respect_fog` flag while preserving exact `1.15×` power ratio logic!)*
  * `find_nearest_neutral_sensor_relay_pos(origin: Vector2) -> Variant`
  * `pick_scout_quadrant_waypoint(core: Building) -> Vector2`
  * `get_counter_reaction_strength() -> float`

### C.2 `scripts/systems/ai/ai_economy_manager.gd` (`class_name AIEconomyManager extends RefCounted`)

* **Owned State:** Building/unit role refs (`hub_data`, `refinery_data`, `supply_data`, `compute_hub_data`, `barracks_t1_data`, `counter_foundry_data`, `heavy_t2_data`, `worker_data`, `harvester_data`, `engineer_data`), production rotation counters (`vat_production_counter`, `foundry_production_counter`, `fab_production_counter`).
* **Moved Methods:**
  * `bind_from_planner(planner: AIBuildPlanner) -> void`
  * `manage_economy_and_production(econ: EconomyManager, core: Building) -> void` *(preserving all priorities 1–14, including Priority 1.5 proactive Power Lattice recovery, Priority 6 multi-hub worker scaling, Priority 6.5 Natural Expansion Command Hub, Priority 7 Geothermal Surge vent priority, and reactive counter foundry)*
  * `manage_overclock_macro() -> void`
  * `assign_idle_workers(core: Building) -> void` *(multi-hub Biomass saturation)*
  * `assign_idle_harvesters() -> void`
  * `assign_idle_engineers() -> void`
  * `resume_unfinished_buildings() -> void`
  * `collect_safe_salvage(core: Building) -> void`
  * `find_natural_expansion_hub_spot(core: Building, hub_data: BuildingData) -> Vector2`
  * `find_nearest_surging_safe_vent(...)`, `find_nearest_unoccupied_vent(...)`, `find_expansion_silica_vein(...)`
  * `try_place_and_build(...)`, `try_place_and_build_on_vent(...)`, `instantiate_ai_building(...)`, `find_valid_build_position(...)`, `is_build_spot_valid(...)`
  * `get_main_biomass_ratio(core: Building) -> float`

### C.3 `scripts/systems/ai/ai_army_controller.gd` (`class_name AIArmyController extends RefCounted`)

* **Owned State:** `army_state: SkirmishAICommander.ArmyState`, `staging_point: Vector2`, `staging_point_valid: bool`, `staging_snapped_to_nav: bool`, `last_core_count: int`, `wave_units: Array[Unit]`, `wave_launch_strength: float`, `current_attack_target: Vector2`, `regroup_timer: float`, `defense_clear_timer: float`, `breach_target: Node2D`, `last_staging_count: int`, `wave_number: int`, `wave_timer: float`, `wave_cooldown_timer: float`, `unit_last_pos: Dictionary`, `unit_stall_ticks: Dictionary`, `deploy_idle_timers: Dictionary`.
* **Moved Methods:**
  * `compute_staging_point(core: Building) -> Vector2` *(preserving 4.2 High-Ground Plateau Staging preference + fallback corridor staging)*
  * `sync_military_rallies() -> void`
  * `tick_army_state_machine(core: Building, tick_dt: float) -> void`
  * `find_base_perimeter_threat(core: Building) -> Variant`
  * `dispatch_base_defense(threat_pos: Vector2, core: Building) -> void`
  * `tick_retreating_state(tick_dt: float)`, `tick_breaching_state(core: Building)`, `tick_attacking_state(core: Building)`, `tick_staging_state(core: Building)`
  * `launch_wave_from_units(squad: Array[Unit], core: Building, allow_flank: bool) -> void`
  * `is_backline_support_unit(u: Unit) -> bool` & `compute_support_trailing_pos(...)` *(strictly AI-only, preserving 4.2 support escort trailing)*
  * `recover_stalled_combat_units() -> void`
  * `trigger_combat_abilities() -> void` + `find_highest_hp_visible_hostile_unit(...)` + `find_solar_convergence_target(...)` + `count_hostile_combat_near(...)`
  * `manage_deploy_micro(tick_dt: float) -> void`
  * `select_wave_target(wave_idx: int, core: Building) -> Vector2`
  * `get_debug_status_line(core: Building) -> String`

### C.4 Slim `SkirmishAICommander` Coordinator (`scripts/systems/skirmish_ai.gd`)

* Retains `@export` fields (`ai_team`, `enabled`, `decision_interval`, `target_worker_count`, `max_cloning_vats`, `max_bandwidth_cap`, `wave_squad_size`, `max_wave_interval`, `base_defense_radius`, `arena_bounds`), `enum ArmyState`, `_planner`, `_scout_intel`, `_economy`, `_army`, radio transmission throttling (`try_emit_ai_transmission`, `sanitize_transmission_pos`), and shared scene/team helper queries (`get_team_buildings`, `get_team_units`, `is_enemy_team`, `is_allied_team`, `is_combat_unit`, `find_ai_command_core`, `count_constructed_command_cores`, `get_economy_manager`, `get_command_router`).
* Preserves `army_state` property getter/setter forwarding to `_army.army_state`, `get_debug_status_line()`, `_load_faction_rosters()`, and `_apply_lobby_ai_profile()` so `MatchManager` and `SandboxDebugPanel` stay 100% compatible.

## Phase D — Verification & Zero-Regression Audit Checklist (4.3a)

1. **Startup & Parse Hygiene:**
   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 warnings** across all scenes.
   * Confirm line/file size reductions: `unit.gd`, `building.gd`, and `skirmish_ai.gd` are each cleanly slimmed down with zero circular `preload()` cycles.
2. **`Unit` & `Building` Full Behavior Sweep (`milestone_0_test.tscn` & Skirmish):**
   * Test `Shift`-queued command chains (`Move → Attack-Move → Patrol → Cast Ability → Gather → Build → Salvage`) and confirm `CommandQueueOverlay` draws active destinations identically.
   * Test `Anvil Siege-Walker` `Deploy / Anchor` (`E`): confirm transition progress bar, 4 stabilizer clamps, anchor thud VFX/SFX, camera micro-shake, and move-lock while deployed.
   * Test `MONOLITH_OS` `Core Overclock`, `Capacitor Pylon` shield aura, and shield-shatter feedback.
   * Test `PRISMA_DEI` Power Lattice rings, `UNPOWERED` pulsing badge + dormancy when destroying a `Halo Spire`, Optical Tether inspection rows, and `Beam Charge` inspection rows.
   * Test universal Biomass + Silica drop-off at all 3 Command Hubs and Geothermal Compute Surge `2x` output + inspection telemetry.
   * Verify SC2 high-ground Fog of War unseen-fire retaliation (low-ground idle units advance up ramps instead of shooting through fog).
3. **3-Faction AI Spectator Stress Test (`Triad Sanctum` + `Procedural Arena`):**
   * Run a **3P FFA AI Spectator Match** (`GENESIS_V2` vs. `MONOLITH_OS` vs. `PRISMA_DEI`, Standard/Brutal) on `skirmish_arena_04.tscn` at `2x` speed for 5+ minutes:
     * Verify AI scouting, counter postures (`SandboxDebugPanel` / debug status line), Natural Expansion Command Hubs, high-ground plateau staging, support escort trailing (`Cantor`/`Symbiote`/`Aegis Relay`), Power Lattice recovery, Deploy micro, Geothermal Surge vent contesting, and radio transmissions all work identically to pre-4.3a with zero errors.