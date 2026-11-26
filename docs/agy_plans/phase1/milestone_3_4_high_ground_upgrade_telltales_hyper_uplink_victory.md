# Milestone 3.4 — 2D High-Ground Plateaus, Scoutable Upgrade Telltales & Hyper-Uplink Victory

**Prerequisite:** Milestones 3.1, 3.2, and 3.3 verified and working cleanly.

**Goal:** Deepen map tactics, visual scouting clarity, and objective-driven match pacing across three systems:

1. **2D Elevation / High-Ground Plateaus (`HighGroundPlateau` + `FogOfWar`):** Add procedural elevated terraces connected by wide navigable ramps. High-ground units see freely down into low ground, while low-ground units cannot see *up* onto a plateau without a spotter on the plateau or a flanking `SensorRelay` (**pure vision asymmetry—zero RNG miss-chances**).

2. **Scoutable Visual Upgrade Telltales (`EntityVisuals`):** Extend `Goliath Frame`'s `Compute Overdrive` gold trim pattern across **all 6 faction upgrades** (`GENESIS_V2` & `MONOLITH_OS`) so scouting an enemy army or production structure visually reveals their researched tech on sight.

3. **Hyper-Uplink Map Audit & Countdown Victory Condition:** Audit and ensure `scenes/world/hyper_uplink.tscn` is cleanly placed, multi-team/alliance-aware, and active across **`skirmish_arena_01.tscn`**, **`skirmish_arena_02.tscn`**, and **`skirmish_arena_03.tscn`**, and add a lobby-configurable **Hyper-Uplink Countdown Victory** (`3:00` cumulative alliance hold) with HUD timer, milestone alerts, and AI contest urgency.

**Non-Negotiable Constraints:**

* **100% Procedural Pipeline:** All plateaus, cliff walls, ramps, upgrade telltales, and Hyper-Uplink visuals/SFX must use Godot 2D `_draw()` and procedural synth audio—zero external image or audio assets.

* **Strict `1280×720` UI Discipline:** `MainMenu` (`ConfigPanel`) and `ResourceHUD` (Uplink countdown pill) must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).

* **No AI Map-Hacking:** `SkirmishAI` must respect high-ground Fog of War vision identically to human players.

* **Hard Exclusions:** No stealth/cloaking mechanics; no role-sorted squad formations; no RNG high-ground attack miss-chances.

## Phase A — 2D Elevation / High-Ground Plateaus & Vision Asymmetry

### A.1 Reusable `HighGroundPlateau` World Entity (`scripts/world/high_ground_plateau.gd` & `scenes/world/high_ground_plateau.tscn`)

Create `class_name HighGroundPlateau extends Node2D` added to groups `"high_ground_plateaus"` and `"nav_bake_obstacles"` (via its cliff wall segments):

* **Exported Geometry:**

  * `@export var plateau_polygon: PackedVector2Array` *(convex or clean chamfered polygon in local coordinates defining the elevated Level 1 surface)*.

  * `@export var ramp_edge_indices: PackedInt32Array` *(indices of polygon edges that act as open, walkable ramps—minimum ramp width **`>= 124 px`** so `Goliath Frame` and `Monolith Dreadnought` pass smoothly without snagging)*.

  * `@export var elevation_level: int = 1`

  * `@export var biome_tint: Color = Color(0.14, 0.20, 0.26, 1.0)` *(tinted per arena to blend naturally with Milestone 3.2 `MapBiomeBackdrop`)*.

* **Automatic Cliff Colliders & Navmesh Baking:**

  * On `_ready()`, iterate every edge `(v0, v1)` of `plateau_polygon`:

    * If the edge index is **not** in `ramp_edge_indices`, spawn a thin impassable cliff barrier (`StaticBody2D` + `CollisionShape2D` / `SegmentShape2D` or `RectangleShape2D` thickness `12 px`, collision layer `1`) along that edge and add it to `"nav_bake_obstacles"` and `"terrain_obstacles"` (or expose `overlaps_cliff_edge(world_pos, radius)` so `CommandRouter.evaluate_build_placement()` blocks building scaffolds straddling a cliff lip while allowing valid placement cleanly on top of the plateau or cleanly below it!).

    * Open ramp edges generate **zero** collision walls so `ArenaNavRegion` automatically bakes continuous walkable ramps connecting Level 0 and Level 1.

  * Expose helpers:

    * `contains_world_point(world_pos: Vector2) -> bool` using `Geometry2D.is_point_in_polygon(to_local(world_pos), plateau_polygon)`.

    * `get_world_polygon() -> PackedVector2Array`.

    * `overlaps_cliff_wall(world_pos: Vector2, radius: float) -> bool` (blocks building placement straddling cliff drops).

* **Procedural Elevation Visuals (`z_index = -50`, strictly above `MapBiomeBackdrop` and below `BattleScarsOverlay` / units):**

  * Render a crisp dropped cliff-wall extrusion (`Vector2(0, 14)` downward bevel in dark slate/charcoal with subtle vertical cliff striations) along bottom-facing non-ramp edges so elevation height reads instantaneously in top-down 2D.

  * Render the raised plateau deck fill (slightly brighter/cleaner than the low-ground floor so high ground pops softly without competing with units) + crisp 2 px bevel outline on cliff edges.

  * On each open ramp edge, draw subtle **parallel ramp-step chevrons / guide rails** sloping from Level 0 up to Level 1 so players can spot every ramp entrance at a glance.

* **Minimap Integration (`ui/hud/minimap.gd`):**

  * Draw all `"high_ground_plateaus"` polygons as subtle raised-contrast terraces (slightly lighter than map floor, with faint rim lines) beneath unit/building blips and Fog of War.

### A.2 Elevation-Aware LOS Shadowing (`scripts/systems/fog_of_war.gd`)

Integrate elevation directly into the existing LOS `FogOfWarSystem` grid without breaking `TerrainObstacle`, `MapLandmark`, or `DestructibleBarricade` blocking:

1. **Static Elevation Grid (`_elevation_grid: PackedByteArray`):**

   * Match the exact dimensions of the existing visibility/blocker grid.

   * Build once in `_ready()` (and on map reload): for each cell center `world_pos`, set `_elevation_grid[idx] = 1` if any `HighGroundPlateau.contains_world_point(world_pos)` is true, else `0`.

   * Expose `func get_elevation_at(world_pos: Vector2) -> int`.

2. **One-Way High-Ground Vision Rule in LOS Raycast:**

   * For each friendly vision source (Unit or Building), resolve `var viewer_elev: int = get_elevation_at(source.global_position)`.

   * When casting LOS rays from the viewer cell to target cell `(cx, cy)`:

     * If any step along the ray (including the target cell itself) has `_elevation_grid[step_idx] > viewer_elev`, **stop the ray immediately** (low ground cannot see up onto or past a high-ground plateau).

     * If `_elevation_grid[step_idx] <= viewer_elev`, elevation does **not** block sight—high-ground units see cleanly down into low ground and across same-level high ground (solid `TerrainObstacle` / `DestructibleBarricade` blockers still occlude normally).

   * **`SensorRelay` Exception:** Active allied `SensorRelay` pads continue stamping their full unobstructed vision circle across both low and high ground, giving flank relays huge tactical value for scouting enemy high-ground artillery (`Anvil Siege-Walker` / `Chrysalis Mortar`).

3. **Zero RNG Miss-Chances & Readable High-Ground Fire:**

   * Combat accuracy remains **100% deterministic** (no high-ground miss rolls).

   * Ensure weapon tracers (`AttackTracer`) and artillery arcs (`CombatVFX`) fired from a high-ground unit down at a visible low-ground target still render cleanly from the firing origin toward the target so the victim can see where fire is coming from and decide to push the ramp, flank, or bring a spotter.

4. **Placement Safety (`scripts/controllers/command_router.gd`):**

   * Update `evaluate_build_placement()` to reject placement if `plateau.overlaps_cliff_wall(place_pos, new_radius + 4.0)` (`reason = "Blocked by cliff edge"`), while allowing structures like `Defense Turret`, `Bastion Emplacement`, or `Capacitor Pylon` to be built cleanly on top of open high-ground plateaus!

### A.3 Symmetric Plateau Placement Across All 3 Skirmish Arenas

Add clean, symmetric `HighGroundPlateau` terraces to each skirmish arena while verifying **zero overlap** with pre-placed starting Command Hubs, `ResourceNode` clusters, `ComputeVent`s, `MapLandmark`s, or `HyperUplink` (`(0, 0)`):

1. **`scenes/maps/skirmish_arena_01.tscn` (*Vat Basin*):**

   * Add **2 symmetric tactical overlook plateaus** flanking the central Hyper-Uplink Plaza (e.g., SW-mid and NE-mid overlooks, each with a generous `>= 130 px` base-facing ramp and a side ramp)—creating prime high-ground positions for `Rail-Sentinel`s, `Chrysalis Mortar`s, and deployed `Anvil Siege-Walker`s overlooking the center objective.

2. **`scenes/maps/skirmish_arena_02.tscn` (*Twin Causeway*):**

   * Add **2 symmetric elevated bastion terraces** flanking the central causeway choke (accessible via wide ramps on each team's side), rewarding high-ground ramp control over the bridge approach.

3. **`scenes/maps/skirmish_arena_03.tscn` (*Quad Nexus*):**

   * Add **4 rotationally symmetric inner-ring high-ground terraces** (one per quadrant between each corner base and the central Hyper-Uplink Plaza, each with dual wide ramps), creating natural forward defensive strongpoints in 2v2 and 4P FFA matches.

* Verify `ArenaNavRegion` bakes cleanly on all 3 maps and units path up/down every ramp smoothly without stalls.

## Phase B — Scoutable Visual Upgrade Telltales (`ui/overlays/entity_visuals.gd`)

Extend `goliath_frame`'s existing `Compute Overdrive` visual telltale pattern across **all 6 faction upgrades** so scouting an enemy army or factory immediately communicates their researched tech without inspecting tooltips.

### B.1 Lightweight Cached Upgrade Lookup (`ui/overlays/entity_visuals.gd`)

Avoid per-frame `get_tree().get_first_node_in_group("economy_manager")` calls across dozens of units:

* Cache a weak/valid reference to `_economy_manager: EconomyManager` (resolved lazily once when `is_inside_tree()`) and maintain a lightweight `var _upgrade_flags: int = 0` bitmask (or small `Dictionary`) refreshed when `EconomyManager.tech_changed` emits for `team` (and once on `bind_unit` / `bind_building`).

* Add helper `func _has_team_upgrade(upgrade_id: StringName) -> bool` backed by the cached state.

### B.2 Distinct Procedural Telltales for All 6 Upgrades (`<= 4` Primitives Each)

1. **`GENESIS_V2` — `UPGRADE_BATCH_EFFICIENCY`:**

   * **On `cloning_vat`:** Twin bright emerald-cyan (`#34D399`) chevron ribs along the central divider bridge + brighter twin-chamber top rim pips.

   * **On `clone_trooper`, `stinger`, `symbiote`:** Subtle crisp emerald-mint collar/wingtip chevrons (2 small vector ticks) so even a scouted bio-squad signals upgraded cloning economy.

2. **`GENESIS_V2` — `UPGRADE_ADRENAL_POTENCY`:**

   * **On `clone_trooper`:** Add a glowing twin-cell crimson/gold dorsal stim-pack bar behind the helmet and an intensified bright visor ridge (distinct from the full-body pulsing flash during active `Adrenal Surge`).

3. **`GENESIS_V2` — `UPGRADE_COMPUTE_OVERDRIVE`:**

   * **On `goliath_frame`:** Preserve the existing gold shoulder trim and pulsing reactor halo cleanly (refactor to use `_has_team_upgrade(UpgradeManager.UPGRADE_COMPUTE_OVERDRIVE)` for consistency).

4. **`MONOLITH_OS` — `UPGRADE_HARDENED_PLATING`:**

   * **On `bulwark_automaton`, `picket_drone`, `rail_sentinel`, `aegis_relay`, `anvil_siege_walker`, `monolith_dreadnought`, `null_grid_projector`, and `bastion_emplacement`:**

     * Draw bold stark off-white (`#F2EFE9`) reinforced chamfered corner armor brackets / bolted front-slab strips with dark ink seam ticks—visually thickening the chassis silhouette on sight.

5. **`MONOLITH_OS` — `UPGRADE_RAPID_CAPACITORS`:**

   * **On all shielded `MONOLITH_OS` combat units (`bulwark_automaton`, `picket_drone`, `rail_sentinel`, `aegis_relay`, `anvil_siege_walker`, `monolith_dreadnought`, `null_grid_projector`) and `capacitor_pylon`:**

     * Draw twin bright Shield-Cyan (`#38BDF8`) dorsal capacitor pips + a faint segmented cyan outer energy arc shimmering gently around the core (`pulse` driven).

6. **`MONOLITH_OS` — `UPGRADE_HYPER_VELOCITY_RAILS`:**

   * **On `rail_sentinel`, `anvil_siege_walker`, and `bastion_emplacement`:**

     * Draw glowing **Hazard Amber (`#FF9F1C`)** twin accelerator induction rings/coils along the barrel assembly + bright off-white muzzle tip highlights so scouts immediately spot long-range upgraded rails/artillery.

## Phase C — Hyper-Uplink Map Audit & Countdown Victory Condition

### C.1 Full `HyperUplink` Audit & Multi-Team Upgrade (`scripts/world/hyper_uplink.gd` & `scenes/world/hyper_uplink.tscn`)

Inspect `scripts/world/hyper_uplink.gd` and `scenes/world/hyper_uplink.tscn`, and verify/upgrade them so the central **Data Hyper-Uplink** works flawlessly in 1v1, 2v2, and 3P/4P FFA:

1. **Guaranteed Placement on All 3 Skirmish Maps:**

   * Audit `scenes/maps/skirmish_arena_01.tscn`, `scenes/maps/skirmish_arena_02.tscn`, and `scenes/maps/skirmish_arena_03.tscn`.

   * If `HyperUplink` (`scenes/world/hyper_uplink.tscn`) is missing from any of those three maps—or mispositioned/unregistered—instance it cleanly at **`Vector2(0, 0)`** inside the central Hyper-Uplink Plaza (verifying `>= 90 px` clearance from surrounding cover pylons and plateaus so units can comfortably stand inside its `capture_radius = 140.0`).

   * Verify it is added to group `"hyper_uplinks"` in `_ready()`.

2. **Multi-Team & Alliance-Aware Capture Logic (`scripts/world/hyper_uplink.gd`):**

   * Ensure capture detection uses `TeamManager.get_team_alliance(int(u.team))` (not hardcoded `Team.PLAYER` vs `Team.ENEMY`):

     * Scan living, non-staffed units within `capture_radius` (use `SpatialGrid.query_units_in_radius(global_position, capture_radius)` if available).

     * Group occupying units by `alliance_id`.

     * **0 alliances inside:** Hold current ownership cleanly (slowly decay partial uncaptured progress back toward current owner).

     * **2+ opposing alliances inside:** Set `is_contested = true`, pause capture shift, pulse amber/crimson contested ring, and trigger throttled `uplink_contested` tactical alert when a local alliance's uplink is contested.

     * **Exactly 1 alliance inside:** Shift capture progress smoothly over `capture_time` (`~8.0s`). Once captured, set `controlling_alliance` and `controlling_team` (the primary capturing team), tint the central beacon + minimap diamond to that team/alliance's color, and emit `owner_changed` / `TacticalEventFeed` announcement (*"P1 [A] Captured Data Hyper-Uplink!"*).

3. **Alliance-Wide `+5%` Production Bonus (`scripts/systems/economy_manager.gd`):**

   * Verify `EconomyManager.get_production_speed_multiplier(team)` checks `TeamManager.are_allies(team, uplink.controlling_team)` (or `TeamManager.get_team_alliance(team) == uplink.controlling_alliance`) so allied teammates in 2v2 both receive the `+5%` Hyper-Uplink speed bonus.

4. **Diegetic Visuals, Minimap & Inspection:**

   * Verify `HyperUplink._draw()` renders a clean Technozen/Y2K capture ring (`140 px`), progress fill arc, central glowing spire/diamond, and crisp `"CONTESTED"` or team-colored status halo.

   * Verify clicking the `HyperUplink` populates read-only telemetry in `SelectionHUD` (`get_inspection_data()`: Controlling Alliance, Capture %, `+5% Prod Speed`, and Countdown progress if Uplink Victory is enabled).

   * Verify `ui/hud/minimap.gd` renders the `HyperUplink` diamond cleanly in the controlling team's color (pulsing white/gold when contested).

### C.2 Alternate Win Condition — Hyper-Uplink Countdown (`GameConfig`, `MainMenu`, `MatchManager`, `ResourceHUD`, `SkirmishAI`)

1. **Lobby Configuration (`scripts/systems/game_config.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`):**

   * In `GameConfig`:

     * Add `const UPLINK_VICTORY_DURATION: float = 180.0` (`3:00` cumulative alliance hold).

     * Add `var mutator_uplink_victory: bool = true` *(or `uplink_victory_enabled: bool = true` — default ON so players immediately experience the central objective, toggleable OFF for pure Domination/Annihilation matches)*.

     * Include `"UPLINK WIN (3m)"` in `get_active_mutator_labels()` (or display `"Domination + Uplink (3:00)"` vs `"Domination Only"` in `MainMenu`'s `MatchSummaryLabel`).

     * Persist/pass `uplink_victory_enabled` through `GameConfig.set_lobby_config(...)`.

   * In `scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`:

     * Add a compact `CheckBox` (`%ChkUplinkVictory`, text `"Uplink Win (3m)"`, tooltip `"Hold the central Data Hyper-Uplink for 3:00 total to win the match (in addition to Command Hub elimination)."`) cleanly inside `ConfigPanel`'s `MutatorsRow` (or a compact 2×2 grid for the 4 checkboxes: `2x Yield`, `No Fog`, `Fast Build`, `Uplink Win (3m)`) so **`ConfigPanel` stays 100% unclipped at `1280×720` Windowed & Fullscreen**.

2. **Cumulative Countdown & Milestone Alerts (`scripts/systems/match_manager.gd`):**

   * Track `var alliance_uplink_times: Dictionary = {}` (`alliance_id -> float`) and `var _uplink_milestones_announced: Dictionary = {}` (`alliance_id -> int` bitmask for 50% / 75% / 90%).

   * In `_process(delta)`, while `uplink != null and uplink.controlling_alliance >= 0 and not uplink.is_contested`:

     * Increment `alliance_uplink_times[ally_id] += delta` (alongside existing per-team `uplink_seconds` telemetry).

     * If `is_uplink_victory_enabled()`:

       * At **50% (`1:30` remaining)**, **75% (`0:45` remaining)**, and **90% (`0:18` remaining)**: emit a high-visibility gold/crimson `TacticalEventFeed` alert (click-to-jump to `uplink.global_position`) and play `uplink_contested` / warning chime.

       * When `alliance_uplink_times[ally_id] >= GameConfig.UPLINK_VICTORY_DURATION`: trigger `_finish_match(uplink.controlling_team, "%s Achieved Data Hyper-Uplink Sovereignty (03:00)" % _format_winner_label(uplink.controlling_team))`!

   * Expose clean helper `get_uplink_victory_status() -> Dictionary` (`enabled`, `target_seconds`, `leading_alliance`, `leading_team`, `leading_seconds`, `controlling_alliance`, `controlling_team`, `is_contested`, `uplink_pos`) for `ResourceHUD` and `SkirmishAI`.

3. **Top HUD Uplink Countdown Pill (`ui/hud/resource_hud.gd` & `.tscn`):**

   * Update the existing compact Uplink indicator in `ResourceHUD` (making it clickable to snap camera to `(0, 0)`):

     * When **Uplink Victory is ON**: show live leading/controlling status and countdown/hold timer, e.g.:

       * Neutral & 0s: `UPLINK: NEUTRAL`

       * Held by Team: `UPLINK [P1]: 01:24 / 03:00` (tinted to controlling team's color; pulses warning amber/crimson when an enemy alliance exceeds `75%`!)

       * Contested: `UPLINK: CONTESTED` (pulsing gold/crimson)

     * When **Uplink Victory is OFF (Domination Only)**: show compact `UPLINK: +5%` / `UPLINK: NEUTRAL` / `UPLINK: CONTESTED`.

   * Keep pill width strictly compact so `ResourceHUD` never crowds or wraps at `1280×720`.

4. **AI Objective Urgency (`scripts/systems/skirmish_ai.gd`):**

   * Query `MatchManager.get_uplink_victory_status()` on AI tactical decisions:

     * If `enabled == true` and an opposing alliance currently holds the Hyper-Uplink (especially once `leading_seconds >= target_seconds * 0.40`), prioritize dispatching the AI's staged combat wave to contest `(0, 0)` rather than ignoring the timer—while still obeying all Fog of War vision rules (no map-hacking enemy army positions).

## Phase D — Verification & Playtest Checklist

1. **High-Ground Plateaus & Vision Asymmetry:**

   * Load `skirmish_arena_01.tscn`, `02.tscn`, and `03.tscn`: confirm symmetric procedural plateaus render cleanly above the biome floor with clear cliff drop walls, visible ramp steps, and zero overlap with bases or resource nodes.

   * Walk `Goliath Frame` and `Monolith Dreadnought` up and down every ramp: confirm smooth navigation with zero snags, and confirm units cannot walk through sheer cliff edges.

   * Place an enemy unit on a plateau and approach from low ground (with Fog of War ON): confirm the high-ground unit remains hidden until a friendly unit climbs onto the plateau OR captures a flanking `SensorRelay`, while a friendly unit on the plateau sees freely down into low ground.

   * Confirm workers cannot place buildings straddling a cliff edge, but *can* build turrets/pylons cleanly on top of the plateau.

2. **Scoutable Visual Upgrade Telltales:**

   * In `milestone_0_test.tscn` or a Fast-Tech skirmish, research all 3 `GENESIS_V2` upgrades (`Batch Efficiency`, `Adrenal Potency`, `Compute Overdrive`) and all 3 `MONOLITH_OS` upgrades (`Hardened Plating`, `Rapid Capacitors`, `Hyper-Velocity Rails`).

   * Verify each upgrade visibly transforms the corresponding units/buildings immediately upon completion with crisp, readable silhouettes at normal RTS camera zoom.

3. **Hyper-Uplink Presence & Countdown Victory:**

   * Verify the central **Data Hyper-Uplink** is present at `(0, 0)` on **`skirmish_arena_01`**, **`skirmish_arena_02`**, and **`skirmish_arena_03`**, renders its capture ring and minimap diamond, and grants `+5%` production speed when held.

   * With `Uplink Win (3m)` checked in `MainMenu`, capture the Hyper-Uplink and verify the `ResourceHUD` timer ticks smoothly (`MM:SS / 03:00`), pauses immediately when an enemy enters the ring (`CONTESTED`), fires `50% / 75% / 90%` `TacticalEventFeed` click-to-jump alerts, and declares victory cleanly at `03:00` (test at `2x` speed to verify quickly!).

   * Uncheck `Uplink Win (3m)` in `MainMenu` and confirm the match plays as pure Domination (no countdown victory).

4. **Layout & Performance Check (`1280×720`):**

   * Check `MainMenu` (`ConfigPanel`) and `ResourceHUD` in both Windowed `1280×720` and Fullscreen (`F11`) for zero clipping.

   * Run a 4P FFA AI Spectator match on `skirmish_arena_03.tscn` at `2x` speed to confirm AI teams actively contest the Hyper-Uplink, climb high-ground ramps cleanly, and maintain smooth FPS with zero console errors.