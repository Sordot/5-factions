# Milestone 4.2 — 3-Way Battlefields, Contested Flashpoints & Macro AI Overhaul

**Prerequisite:** Milestones 4.0b and 4.1 verified and working cleanly.

**Goal:** Elevate 3-faction skirmishes (`GENESIS_V2` vs. `MONOLITH_OS` vs. `PRISMA_DEI`) with true 3-way map geometry, mid-map economic flashpoints that reward map control over turtling, and smarter macro/tactical AI commanders:

1. **3-Player Triangular Battlefield (`skirmish_arena_04.tscn` — *Triad Sanctum* & 120° Procedural Symmetry):** Ship a dedicated 3-corner equilateral arena with a new Bauhaus/Obsidian biome (`&"triad_sanctum"`), wide `180–220 px` high-ground ramps, and a matching **3-Way 120° Rotational Symmetry** engine inside `ProceduralArenaGenerator` whenever `player_count == 3`.
2. **High-Yield Expansion Nodes & Geothermal Compute Surges:**
   * Introduce exposed mid-map **Dense Biomass** and **Rich Silica** nodes (`+35%` harvest load per trip, larger reserve, radiant procedural gleam) across `skirmish_arena_01–04` and procedural seeds.
   * Trigger periodic **45-second Geothermal Compute Surges (`2.0×` output)** on contested expansion `ComputeVent`s every `~3 minutes`, broadcast via `TacticalEventFeed` + pulsing minimap ping.
3. **Macro & Tactical AI Overhaul (`SkirmishAICommander` & `AIBuildPlanner`):**
   * **Natural Expansion Command Hubs:** Teach the AI to claim a second Biomass expansion with a constructed Command Hub (`Nexus Vat` / `Foundry Core` / `Sanctum Core`) and distribute workers across all owned hubs.
   * **High-Ground Plateau Staging:** Prefer staging defending/assembling squads on friendly-side elevated plateaus to leverage Patch 3.8's SC2 high-ground vision rules cleanly.
   * **AI Support & Tether Escort Positioning:** Keep fragile AI support/tether units (`Cantor`, `Symbiote`, `Aegis Relay`, `Prism Weaver`) trailing ~`95–110 px` behind their AI combat wave centroid rather than charging into frontlines or getting left behind.

**Hard Design Guardrails (MUST PRESERVE):**
* **Zero Player Formation Automation:** Support trailing offsets must exist **exclusively inside `SkirmishAICommander`**. Do **not** alter `CommandRouter.assign_group_destinations()` or introduce role-sorted squad formations for human players.
* **Zero Skill-Cap Automation & Zero AI Map-Hacking:** No stealth/cloaking, no overkill-prevention targeting automation, no auto-loop production, and `SkirmishAICommander` must obey identical SC2 high-ground Fog of War rules as humans.
* **Standard Worker Construction & Universal Hub Drop-Offs:** AI expansion hubs are built manually by workers (`Worker Drone` / `Servo-Drone` / `Acolyte`) and retain universal Biomass + Silica drop-off behavior from 4.0b.
* **Zero Unit/Building Combat Stat Balance Changes:** Do not alter existing unit/building HP, shield, armor, damage, range, speed, or cost values.
* **100% Procedural Pipeline & Strict `1280×720` UI Discipline:** All new biome backdrops, high-yield gleams, surge rings, and lobby map dropdown entries must remain 100% procedural and unclipped in Windowed `1280×720` and Fullscreen (`F11`).

---

## Phase A — 3-Player Triangular FFA Arena (`Triad Sanctum`) & 120° Procedural Symmetry

### A.1 New Procedural Biome (`scripts/world/map_biome_backdrop.gd`)
Add a fourth procedural biome preset **`&"triad_sanctum"`** inspired by `PRISMA_DEI`'s solar observatory aesthetic (while keeping high contrast against all 3 factions' units and team colors):
* **Palette:** Deep obsidian-slate floor (`Color(0.065, 0.068, 0.095, 1.0)`), subtle alabaster-gray geometric triangulation grid (`60° / 120°` isometric-triangular lattice hairlines at low alpha `0.06–0.09`), faint concentric liturgical-gold & slate astrolabe rings centered on `(0, 0)`, and three crisp `120°` radial meridian lines pointing toward the three corner sanctum basins.
* Ensure `HighGroundPlateau` tinting integrates cleanly with `&"triad_sanctum"` (subtle warm-slate obsidian plateau face with crisp alabaster-gold cliff edge highlights).

### A.2 Hand-Crafted 3-Corner Arena (`scenes/maps/skirmish_arena_04.tscn`)
Clone the clean runtime skeleton of `skirmish_arena_03.tscn` (`ArenaNavRegion`, `MapBiomeBackdrop`, `BattleScarsOverlay`, `Buildings`, `Units`, `Resources`, `Terrain`, `Objectives`, `FogOfWar`, `EconomyManager`, `MatchManager`, `SelectionController`, `RTSCamera`, HUD `CanvasLayer`):
* **Bounds & Exact 120° Equilateral Symmetry:**
  * `arena_bounds = Rect2(-1450.0, -1250.0, 2900.0, 2500.0)` synced across `MapBiomeBackdrop`, `ArenaNavRegion`, `FogOfWar`, `RTSCamera`, `CommandRouter.buildable_bounds`, and `TacticalMinimap`.
  * **3 Equidistant Spawn Anchors (`Marker2D` in group `"spawn_anchors"`, radius `900 px` from `(0, 0)`):**
    * Team 0 (Bottom-Left, `150°`): `Vector2(-779.0, 450.0)`
    * Team 1 (Bottom-Right, `30°`): `Vector2(779.0, 450.0)`
    * Team 2 (Top-Center, `-90°`): `Vector2(0.0, -900.0)`
    * *(Pairwise distance between every base is exactly `~1,558 px`; every base is `900 px` from `(0, 0)` and has `>= 350 px` clearance behind it for starter mineral lines and base infrastructure.)*
* **Central Objective & Mid-Map Geometry (All Mirrored by `0°`, `120°`, `240°`):**
  * **Center `(0, 0)`:** `HyperUplink` inside a clean `220 px` open circular plaza.
  * **3 Starting Base Resource Clusters:** Behind each spawn anchor (`205–255 px` arc outward from center): `3× BiomassNode`, `2× SilicaVein`, `1× ComputeVent`.
  * **3 Safe Natural Expansions:** Offset `~38°` clockwise along the outer ring (`~790 px` from center, `~530 px` from main hub): `3× BiomassNode`, `2× SilicaVein`, `1× ComputeVent` (ideal for AI and player natural Command Hub expansion!).
  * **3 Contested High-Yield Mid-Flank Pockets:** Positioned at the exact midpoints between each pair of players (`-30°`, `90°`, `-150°`, radius `~940 px`): `2× Dense Biomass` (`is_high_yield = true`), `2× Rich Silica` (`is_high_yield = true`), and `1× Contested ComputeVent` (prime Geothermal Surge targets!).
  * **3 Wide-Ramp High-Ground Plateaus (`HighGroundPlateau`):** Positioned at `120°` intervals overlooking the central `HyperUplink` plaza (`>= 540 px` from every starting Command Hub, spacious `~380×280 px` polygons, each with **2 wide assault ramps `190–210 px`**—one facing the nearby base/natural and one facing the central plaza/flank).
  * **3 Flank `SensorRelay` Pads & 3 `DestructibleBarricade` Flank Shortcuts:** Symmetric along the outer perimeter corridors (`>= 135 px` clearance from obstacles and ramp mouths).

### A.3 Lobby & `GameConfig` Registration (`scripts/systems/game_config.gd`, `scripts/ui/main_menu.gd`)
1. Add `const MAP_SKIRMISH_04: String = "res://scenes/maps/skirmish_arena_04.tscn"` and append to `MAP_CATALOG`:
   `{"path": MAP_SKIRMISH_04, "label": "Triad Sanctum (3P FFA)", "max_players": 3}` (place right after `Quad Nexus` and before `Procedural Arena`).
2. Add `"Triad Sanctum"` (`&"triad_sanctum"`) to `%OptProcBiome` in `MainMenu` and to `ProceduralArenaGenerator`'s `&"auto"` biome pool.
3. Verify `MainMenu` clamps player count cleanly to `2–3` when `Triad Sanctum` is selected (defaulting cleanly to `3P` if switching from a 4P map, and keeping `ConfigPanel` 100% unclipped at `1280×720`).

### A.4 Procedural 3-Way 120° Rotational Symmetry (`scripts/world/procedural_arena_generator.gd`)
Upgrade `ProceduralArenaGenerator` so 3-player procedural games generate true triangular arenas instead of leaving an empty 4th quadrant:
* **Symmetry Branching:**
  * `player_count <= 2`: 180° Rotational Symmetry (`Rect2(-1300, -950, 2600, 1900)` — unchanged).
  * **`player_count == 3`: 120° 3-Way Rotational Symmetry** (`Rect2(-1450, -1250, 2900, 2500)`):
    * Place 3 spawn anchors at `R = 900 px` (`150°`, `30°`, `-90°`) with `team_id = 0, 1, 2`.
    * Author every feature once in Sector 0 (bases, natural expansions, contested high-yield midpoint pockets, `HighGroundPlateau`s, `TerrainObstacle`s, flank `DestructibleBarricade`s, `SensorRelay`s) and clone cleanly by rotating `Vector2` positions & polygon vertices by **`0°`, `120°` (`TAU / 3.0`), and `240°` (`2.0 * TAU / 3.0`)** around `(0, 0)`.
    * Preserve all Patch 3.8 guarantees: **`>= 560 px`** minimum plateau clearance from starting hubs, **`360×270` to `460×320 px`** plateau footprints, **`180–220 px`** wide assault ramps, and **`>= 135 px`** unobstructed ramp approach zones.
  * `player_count >= 4`: 4-Way Quadrant Symmetry (`Rect2(-1400, -1050, 2800, 2100)` — unchanged).

---

## Phase B — High-Yield Expansion Nodes & Geothermal Compute Surges

### B.1 High-Yield Expansion Nodes (`scripts/world/resource_node.gd`, `scripts/units/gather_component.gd`)
Implement clean *StarCraft II*-style Rich Resource Nodes (`+35%` load per trip, zero resource-duplication exploits):
1. **`scripts/world/resource_node.gd`:**
   * Add exports:
     * `@export var is_high_yield: bool = false`
     * `@export var high_yield_multiplier: float = 1.35`
   * In `_ready()`: if `is_high_yield` and `not is_vent`:
     * Automatically scale `max_amount` & `remaining_amount` by `1.25×` (unless already explicitly overridden higher in `.tscn`), and set default `display_name` to `"Dense Biomass Cluster"` (if `&"biomass"`) or `"Rich Silica Vein"` (if `&"silica"`).
   * Add helper:
     * `func get_effective_carry_capacity(base_capacity: int) -> int`: returns `maxi(base_capacity + 1, int(round(float(base_capacity) * high_yield_multiplier)))` when `is_high_yield and not is_vent`, else `base_capacity` (e.g., `10 → 14 Biomass` per trip, `25 → 34 Silica` per trip).
   * **Procedural Visual Gleam (`_draw()`):**
     * When `is_high_yield and not is_depleted()`:
       * **Dense Biomass:** Vibrant radiant mint-emerald crystal veins + subtle pulsing golden-emerald aura ring + `3` crisp diamond glint ticks.
       * **Rich Silica:** High-contrast molten solar-gold / amber faceted crystal prism + shimmering warm gold outer halo + crisp specular highlight facets.
     * In `get_inspection_data()`: badge subtitle `"HIGH-YIELD RESOURCE (+35%)"` with a gold/emerald telemetry row `{"label": "Yield Rate", "value": "+35% Load / Trip"}`.
2. **`scripts/units/gather_component.gd`:**
   * In `start_gather(...)` and `_tick_gathering(...)`, compute `var capacity: int = target_node.get_effective_carry_capacity(owner_unit.data.carry_capacity)` instead of raw `owner_unit.data.carry_capacity` so workers and harvesters naturally extract and deliver `+35%` larger loads per trip from high-yield nodes (and properly deduct the exact extracted amount from `remaining_amount`).
3. **Map & Proc-Gen Placement:**
   * Mark exposed, contested mid-map expansion clusters (`is_high_yield = true`) symmetrically on **`skirmish_arena_01.tscn`**, **`skirmish_arena_02.tscn`**, **`skirmish_arena_03.tscn`**, **`skirmish_arena_04.tscn`**, and contested side-pocket expansions in **`ProceduralArenaGenerator`** (never on starting-base mineral lines!).
   * Update `TacticalMinimap` (`ui/hud/minimap.gd`) to render high-yield nodes with a tiny crisp gold/white outer gleam ring so players can immediately spot rich expansions on the minimap.

### B.2 Geothermal Compute Surges (`scripts/world/resource_node.gd`, `scripts/buildings/building.gd`, `scripts/systems/match_manager.gd`, `ui/hud/minimap.gd`)
1. **Vent Surge State (`scripts/world/resource_node.gd`):**
   * Add runtime fields on `ResourceNode` (for `is_vent == true`):
     * `var surge_remaining: float = 0.0`
     * `var surge_duration_total: float = 45.0`
     * `var surge_multiplier: float = 2.0`
   * Add methods:
     * `func is_surging() -> bool`: returns `is_vent and surge_remaining > 0.0`.
     * `func get_compute_surge_multiplier() -> float`: returns `surge_multiplier` if `is_surging()` else `1.0`.
     * `func start_overpressure_surge(duration: float = 45.0, mult: float = 2.0) -> void`: sets timers and triggers `queue_redraw()`.
   * Tick `surge_remaining` cleanly in `_process(delta)` (skip idle redraws when not surging).
   * **Procedural World Telegraph (`_draw()`):** While `is_surging()`, draw pulsing double cyan/solar-gold thermal pressure rings expanding outward from the vent, plus a clean `45s` radial countdown arc around the vent perimeter (visible even under an occupying Compute facility!).
   * In `get_inspection_data()`: when `is_surging()`, append `{"label": "Thermal State", "value": "OVERPRESSURE SURGE (2x) — %ds" % int(ceil(surge_remaining)), "color": Color(0.28, 0.96, 1.0, 1.0)}`.
2. **Compute Facility Yield Integration (`scripts/buildings/building.gd`):**
   * In `_tick_compute_generation(delta)`: multiply `yield_amount` by `claimed_vent.get_compute_surge_multiplier()` when `claimed_vent != null and is_instance_valid(claimed_vent) and claimed_vent.is_surging()`, and emit a brighter cyan deposit pulse.
   * In `get_inspection_data()` (Compute Facility branch): show live doubled Compute rate and `"OVERPRESSURE SURGE (2x) — %ds"` status row while its `claimed_vent` is surging.
3. **Match Surge Director (`scripts/systems/match_manager.gd`):**
   * Active **strictly** in `GameConfig.GameMode.SKIRMISH` (disabled in `UPLINK_HOLDOUT` and `MICRO_GAUNTLET`).
   * Constants: `SURGE_FIRST_DELAY = 165.0` (`02:45`), `SURGE_INTERVAL = 180.0` (`03:00`), `SURGE_DURATION = 45.0`, `SURGE_MULTIPLIER = 2.0`.
   * Candidate filter: collect all `ResourceNode`s where `is_vent == true` and distance to every initial team `_spawn_anchors` entry is `> 440.0 px` (strictly contested expansion vents—never a player's safe main-base vent!).
   * Avoid repeating the exact same vent twice in a row when `>= 2` contested vents exist.
   * On trigger:
     * Call `chosen_vent.start_overpressure_surge(SURGE_DURATION, SURGE_MULTIPLIER)`.
     * Broadcast via `emit_tactical_event(&"surge", "Geothermal Compute Surge! Contested Vent 2x Output (45s)", chosen_vent.global_position, Color(0.28, 0.94, 1.0, 1.0))` (clickable event jumps camera to the surging vent!).
     * Trigger a subtle pulsing cyan ping on `TacticalMinimap` (`minimap.gd`: render a pulsing cyan diamond ring around any currently surging `ComputeVent`).
     * Play a clean non-intrusive telemetry chime (`&"alert_uplink"` at `-6.5 dB` or `&"relay_captured"`).

---

## Phase C — Macro & Tactical AI Overhaul (`SkirmishAICommander`)

### C.1 Natural Expansion Command Hubs (`scripts/systems/skirmish_ai.gd`)
Upgrade `SkirmishAICommander` so AI factions naturally expand to a second Command Hub (`Nexus Vat` / `Foundry Core` / `Sanctum Core`) and scale multi-base economy cleanly:
1. **Expansion Discovery (`_find_natural_expansion_hub_spot(core: Building, hub_data: BuildingData) -> Vector2`):**
   * Scan all non-depleted `biomass` `ResourceNode`s (`not is_vent`) across the map.
   * Exclude any node within `460 px` of any existing **friendly** Command Hub or within `520 px` of any **visible enemy** Command Hub.
   * Group candidate nodes into local clusters (`320 px` radius, favoring clusters with `>= 2` Biomass nodes—preferring High-Yield clusters as a modest tie-breaker once safe) and score by closest distance to the AI's primary `core` while requiring `_is_expansion_spot_safe(cluster_center)` (zero dominant visible enemy combat army within `440 px`—respecting Fog of War!).
   * Compute a clean hub anchor offset `~185 px` from the cluster centroid toward the map interior / main base, validated via `_find_valid_build_position(hub_data, anchor, cluster_center)`.
2. **Expansion Timing & Construction (`_manage_economy_and_production`):**
   * Track `var _hub_data: BuildingData = _planner.get_building_for_role(&"hub")`.
   * Count total owned Command Hubs (`constructed + under_construction`).
   * Target `2` Command Hubs once:
     * At least `1` Tier-1 Barracks (`barracks_t1`) and `1` Refinery (`refinery`) exist,
     * Match time `>= 150s` (`Brutal`), `>= 195s` (`Standard`), or `>= 270s` (`Relaxed`) — OR main Biomass cluster has `< 35%` remaining resources,
     * `econ.can_afford(ai_team, _hub_data.get_cost_dict())` and `biomass >= _hub_data.biomass_cost + (40 if is_brutal else 90)`.
   * Build the expansion Command Hub using a normal worker (`_try_place_and_build(_hub_data, exp_spot, exp_spot)`) — standard on-site construction for all 3 factions (note: `PRISMA_DEI`'s `Sanctum Core` automatically brings its own `290 px` Power Lattice to the expansion!).
3. **Multi-Hub Worker Saturation & Training:**
   * Update `_manage_economy_and_production` so worker training scales smoothly with constructed hub count (`eff_target_workers = mini(max_workers_cap, target_worker_count + 4 * (core_count - 1))`, capped at `8` Relaxed / `11` Standard / `14` Brutal) and queues workers across any constructed owned Command Hub with `< 2` queued items.
   * Update `_assign_idle_workers` to consider **all** constructed owned Command Hubs' local Biomass clusters (using `ResourceNode.pick_best_cluster_node` with saturation checks) so fresh workers at the natural hub harvest the natural cluster and excess main-base workers migrate cleanly to the expansion!
   * When a contested `ComputeVent` enters **Overpressure Surge** and is unoccupied & safe (checked via `_is_salvage_core_safe`-style visible-army check), bias `_find_nearest_unoccupied_vent` toward claiming that surging vent if the AI has `< 3` Compute Hubs.

### C.2 High-Ground Plateau Staging & Ambush Posture (`scripts/systems/skirmish_ai.gd`)
Upgrade `_compute_staging_point(core: Building)` so AI commanders proactively stage on friendly-side `HighGroundPlateau` overlooks when maps offer them:
* Collect all `HighGroundPlateau` nodes in group `"high_ground_plateaus"`.
* Score candidate plateaus whose center lies `340–820 px` from `core.global_position`, is closer to `(0, 0)` than `core` is (friendly-side mid-field overlook), and has a clear navigable point inside its polygon (`plateau.contains_world_point(cand)` + `_is_staging_spot_clear(cand, 44.0)` + navmesh-snapped point still at Elevation `1`).
* Prefer the best qualifying high-ground overlook as `_staging_point` (falling back seamlessly to the existing forward-corridor staging logic on flat maps like `Procedural Arena` with `Flat Ground`).
* Result: AI defending and assembling armies naturally hold high ground, gaining SC2 one-way vision over approaching low-ground waves without cheating!

### C.3 AI Support & Tether Anchor Escort Positioning (`scripts/systems/skirmish_ai.gd`)
Keep fragile support and Optical Tether units (`Cantor`, `Symbiote`, `Aegis Relay`, `Prism Weaver`) alive and effective inside AI armies **without** adding any player formation system:
* Add helper `func _is_backline_support_unit(u: Unit) -> bool`:
  * Returns `true` when `u.data != null and (u.data.has_tag(&"support") or u.data.tether_emit_radius > 0.0 or u.data.heal_aura_rate > 0.0)`.
* **Staging, Wave Launch & Breaching Offset:**
  * In `_launch_wave_from_units`, `_tick_attacking_state`, `_dispatch_base_defense`, `_tick_breaching_state`, and `_rally_idle_combat_to_staging`:
    * For normal frontline/ranged combat units: issue standard destinations unchanged.
    * For `_is_backline_support_unit(u)`: offset their destination `100 px` rearward along the normalized vector from `dest` back toward `_staging_point` / `core.global_position` (clamped cleanly inside `arena_bounds`).
* **Live Support Follow-Up During `ATTACKING`:**
  * On each `_tick_attacking_state` decision tick, compute the live centroid of living non-support combat units in `_wave_units`.
  * For any `attack_damage <= 0.0` pure support in `_wave_units` (`Cantor`, `Symbiote`, `Aegis Relay`): if it has drifted `> 165 px` away from the combat centroid OR drifted closer to `_current_attack_target` than the frontline centroid, smoothly move it to `combat_centroid + back_dir * 95.0`—keeping it right inside its `180–215 px` Optical Tether / Heal Aura / Shield Overcharge radius while shielded behind the frontline!

---

## Phase D — Verification & Playtest Checklist

1. **Triad Sanctum (`skirmish_arena_04.tscn`) & 3P Procedural Symmetry:**
   * Open `MainMenu` (`1280×720` Windowed & `F11` Fullscreen): select **`Triad Sanctum (3P FFA)`**: confirm player count cleanly supports `2–3P`, `ConfigPanel` has zero clipping, and launch a 3P FFA (`GEN-V2` vs. `MONO-OS` vs. `PRIS-DEI`).
   * Verify `&"triad_sanctum"` procedural biome renders cleanly with crisp contrast, all 3 bases sit equidistant at 120° around `(0, 0)`, all 3 high-ground plateaus have wide `180–220 px` ramps, and `TacticalMinimap` & `FogOfWar` align 100%.
   * Select **`Procedural Arena (Seeded 2–4P)`** with **3 Players**: roll 3+ seeds across `Balanced` / `High Ground+` and verify true **120° 3-way rotational symmetry** (zero empty 4th quadrant, `>= 520 px` base-to-plateau clearance, `180–220 px` ramps, symmetric High-Yield mid-pockets).
2. **High-Yield Nodes & Geothermal Compute Surges:**
   * Send a `Worker Drone` / `Acolyte` and a `Silica Harvester` / `Prism Dredge` to a **Dense Biomass** and **Rich Silica** mid-map node: confirm radiant visual gleam, inspection label `(+35%)`, and `+35%` bigger cargo loads (`14 Biomass` / `34 Silica` per trip) cleanly deducted from node reserves.
   * Run a skirmish at `2x` speed past `02:45`: confirm a contested expansion `ComputeVent` enters a **45s Overpressure Surge**, renders pulsing thermal rings + countdown arc, emits a clickable `TacticalEventFeed` event + minimap ping, doubles Compute output (`2x`) on an occupying Compute facility, and expires cleanly after `45s`.
   * Confirm Geothermal Surges do **not** trigger during **Micro Gauntlet** drills or **Uplink Holdout**.
3. **AI Natural Expansion, High-Ground Staging & Support Positioning:**
   * Run a **3P FFA AI Spectator Match** (`GEN-V2` vs. `MONO-OS` vs. `PRIS-DEI`, Standard/Brutal) on **`Triad Sanctum`** at `2x` speed for 6–8 minutes:
     * Confirm AI commanders construct a **second Command Hub** at their natural Biomass expansion (via manual worker construction), spread workers across both hubs, and maintain Power Lattice on `PRISMA_DEI` expansions.
     * Confirm AI staging armies proactively utilize friendly-side **high-ground plateaus** when available without violating SC2 Fog of War rules.
     * Watch `Cantor`, `Symbiote`, and `Aegis Relay` during AI pushes: confirm they trail ~`95–105 px` behind the frontline while maintaining active Optical Tethers / Heal Auras / Shield Overcharges—and confirm **human player** move/attack-move orders in `CommandRouter` remain 100% untouched (zero role-sorted player formations).