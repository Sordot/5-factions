# Milestone 3.8 — SC2-Grade High-Ground Fog of War, Wide Assault Ramps & Procedural Plateau Refinement

**Prerequisite:** Milestones 3.4, 3.6, and 3.7 verified and working cleanly.

**Goal:** Refine the 2D elevation system so high ground plays with *StarCraft II*-accurate vision rules and clean, non-chokepoint ramp geometry across both hand-crafted arenas and the seeded Procedural Skirmish Generator:

1. **SC2-Accurate High-Ground Fog of War (`FogOfWar`, `CombatComponent`, `Unit`, `SkirmishAI`):** Enforce strict one-way elevation vision, **zero attack-reveal from high ground**, opaque plateau blocking for low-ground LOS rays, ramp-crest elevation split (foot of ramp = Level 0, crest = Level 1), fair visible incoming fire from fogged uphill attackers, and vision-respecting retaliation/AI ramp pushes.
2. **Decoupled Wide Assault Ramps (`HighGroundPlateau` & Skirmish Arenas 01–03):** Widen standard plateau ramps to **`180–220 px`** so high ground provides vision and positioning advantages *without* automatically acting as a tight chokepoint funnel, while supporting an explicit opt-in `is_choke_ramp` override (`105–125 px`) for specialized hand-crafted map chokes.
3. **Procedural Arena Plateau Refinement (`ProceduralArenaGenerator`):** Push generated plateaus further away from starting bases (**`520–600 px` minimum clearance** from Command Hub anchors), scale plateau footprints up (**`340×260 px` to `460×320 px`**) to comfortably host `180–220 px` wide ramps and real squad maneuvering space, and guarantee clean symmetric ramp clearances.

**Hard Design Guardrails (MUST PRESERVE):**
* **Zero RNG High-Ground Miss-Chances:** Weapon accuracy stays 100% deterministic; high ground is strictly a vision & spatial advantage.
* **Zero Skill-Cap Automation:** No overkill-prevention targeting; no auto-loop production; no role-sorted squad formations; no stealth/cloaking.
* **Zero Balance Changes:** Do not alter unit/building HP, shields, armor, damage, ranges, speeds, or costs.
* **100% Procedural Pipeline & No AI Map-Hacking:** All cliff/ramp visuals remain procedural Godot 2D `_draw()`, and `SkirmishAI` must obey identical high-ground Fog of War visibility rules as human players.

---

## Phase A — SC2-Accurate High-Ground Fog of War Mechanics

### A.1 Strict Elevation & Ramp-Crest Grid (`scripts/systems/fog_of_war.gd`, `scripts/world/high_ground_plateau.gd`)

1. **Ramp-Crest Elevation Threshold (`HighGroundPlateau`):**
   * On each open ramp edge `(v0, v1)` of `HighGroundPlateau`, define a crisp ramp transition zone spanning outward/inward along the edge normal:
     * **Lower Ramp Approach (outer half / foot of ramp):** Evaluates as **Elevation `0`**. Standing at the foot or lower slope of a ramp does **not** grant vision onto the plateau.
     * **Upper Ramp Crest & Plateau Surface (inward past the crest line):** Evaluates as **Elevation `1`**. Crossing the crest immediately opens full high-ground vision across the plateau and down the ramp.
   * Expose `func get_world_elevation_at(world_pos: Vector2) -> int` (or update `contains_world_point(world_pos)` so the plateau polygon boundary itself sits at the **upper crest line**, while the ramp's visual sloped tread extends ~`28–36 px` outward onto Level 0 ground). This ensures visual treads match the exact gameplay vision threshold cleanly!
2. **Opaque Plateau Blocking for Low-Ground LOS Rays (`FogOfWar`):**
   * In `FogOfWar`'s LOS raycaster (for every friendly vision source at `viewer_elev = get_elevation_at(source.global_position)`):
     * Step along the Bresenham / DDA grid ray from viewer cell to target cell `(cx, cy)`.
     * **Hard Rule:** If any cell along the ray (including intermediate cells AND the target cell) has `_elevation_grid[cell_idx] > viewer_elev`, **terminate the ray immediately** and do **not** mark that cell or any cell behind it as visible.
     * *Result:* A low-ground unit cannot see onto a plateau *and* cannot see **through** a plateau to reveal low ground on the opposite side.
     * When `viewer_elev >= _elevation_grid[cell_idx]`, elevation does not block sight—high-ground units see cleanly down the ramp and across all surrounding low ground (while still respecting opaque `TerrainObstacle`, blocking `MapLandmark`, and intact `DestructibleBarricade` cells).
   * **Allied `SensorRelay` & Spotter Rules:**
     * Any allied unit or constructed building physically at Elevation `1` (or an active allied `SensorRelay` whose unobstructed radar radius overlaps the plateau) reveals Elevation `1` cells normally for its alliance (`TeamManager.are_allies()`).
3. **Explored Building Memory vs. Live Units on High Ground:**
   * Verify that once a team has scouted a high-ground plateau (marking its cells `EXPLORED`), enemy structures on that plateau remain visible in Explored fog (consistent with existing `has_been_spotted` building behavior), while all enemy **units** on that plateau immediately hide (`visible = false`) the instant high-ground vision is lost.
   * Ensure `SelectionController` clears hover/inspection and blocks direct attack-targeting on enemy units that disappear into high-ground fog.

### A.2 Zero Attack-Reveal from High Ground & Fair Incoming Fire Telemetry

1. **Enforce Zero Uphill Attack-Reveal (`FogOfWar`, `Unit`, `CombatComponent`, `TurretComponent`):**
   * Audit `fog_of_war.gd`, `unit.gd`, `combat_component.gd`, and `turret_component.gd` to confirm there is **no temporary fog-reveal** or `reveal_on_attack` timer applied to a unit or turret when it fires from high ground onto a low-ground target.
   * When an Elevation `1` unit/turret shoots at a visible Elevation `0` target, the Elevation `1` shooter stays **100% hidden in Fog of War** (`visible == false`) unless the defending alliance has actual high-ground vision (spotter on the plateau or overlapping `SensorRelay`).
2. **Visible Incoming Tracers & Impact VFX (`CombatComponent`, `TurretComponent`, `AttackTracer`, `CombatVFX`):**
   * Gate tracer/projectile/impact spawning on **`shooter_visible OR target_visible`** (for the local human viewer's alliance, or always in Spectator Mode / `No Fog`), rather than hiding the entire projectile when only the shooter is fogged!
   * When the shooter is fogged (`not shooter.visible`) and the target IS visible (`target.visible`):
     * Render the incoming weapon tracer / artillery shell / beam cleanly along the firing trajectory toward the target (optionally starting its visible fade-in cleanly near the cliff/fog boundary so the exact fogged shooter silhouette stays concealed, while firing direction and impact VFX are unmistakable).
     * Play the weapon impact / hit SFX and trigger the normal throttled `under_attack` tactical alert at the defender's position.
   * When **neither** shooter nor target is visible to the local viewer, suppress all tracers, VFX, and combat SFX completely (zero Fog-of-War leaks).

### A.3 Vision-Respecting Low-Ground Retaliation & Anti-Cheat AI

1. **Player & AI Unit Retaliation (`scripts/units/combat_component.gd`, `scripts/units/unit.gd`):**
   * In `CombatComponent` target acquisition and active target validation:
     * Verify a unit can **never** acquire, maintain lock on, or fire at an enemy unit/building that is currently hidden from its team's real vision (for local human: `FogOfWar.is_world_pos_visible_to_team(team, target.global_position)` or `target.visible`; for AI teams: team-aware LOS/elevation visibility check via `FogOfWar` so AI obeys the exact same high-ground blind spots as humans!).
   * **Taking Unseen High-Ground Fire:**
     * When a unit in `AGGRESSIVE` or `ATTACK_MOVING` stance takes damage from an attacker that is currently **not visible** to the victim's team (e.g., fogged uphill shooter):
       * Do **not** set `current_target = attacker` and do **not** fire uphill through fog.
       * If the unit is `IDLE` (not manually commanded away and not in `HOLD_POSITION` or `DEFENSIVE` beyond its `260 px` leash), issue a reactive move/attack-move toward the attacker's approximate direction (clamped cleanly onto navigable ground) so idle squads naturally advance up the nearest ramp to gain high-ground vision and engage!
     * Units in `HOLD_POSITION` hold ground strictly; units in `DEFENSIVE` only step within their `260 px` leash.
2. **Team-Aware High-Ground Vision Helper (`scripts/systems/fog_of_war.gd` & `scripts/systems/skirmish_ai.gd`):**
   * Add a lightweight team-agnostic visibility query on `FogOfWar`:
     * `func is_entity_visible_to_team(observer_team: int, target_node: Node2D) -> bool`
     * For the local human's alliance, reads the cached `_visible_grid` directly in O(1).
     * For AI teams, checks `SpatialGrid` for any friendly unit/building (or allied `SensorRelay`) within vision range whose elevation is `>= target_elev` and has unobstructed LOS (fast raycheck against `_blocker_grid` and `_elevation_grid`, cached briefly if needed).
   * Update `SkirmishAI` threat/target scanning to call `FogOfWar.is_entity_visible_to_team(ai_team, candidate)` so AI squads never cheat by shooting uphill without a spotter, and when taking unspotted high-ground fire during `ATTACKING` / `DEFENDING`, push their wave up the ramp toward the firing sector to establish vision.

---

## Phase B — Widening Ramps (Decoupling High Ground from Chokepoints)

### B.1 Ramp Width Standards & Opt-In Choke Override (`scripts/world/high_ground_plateau.gd`)

1. **New Ramp Constants & Exports:**
   * `const DEFAULT_WIDE_RAMP_MIN_WIDTH: float = 180.0`
   * `const DEFAULT_WIDE_RAMP_MAX_WIDTH: float = 220.0`
   * `const CHOKE_RAMP_MIN_WIDTH: float = 105.0`
   * `const CHOKE_RAMP_MAX_WIDTH: float = 125.0`
   * Add optional export `@export var choke_ramp_edge_indices: PackedInt32Array = PackedInt32Array()` *(empty by default; only hand-crafted maps explicitly designed around a narrow high-ground choke tag specific edges here)*.
2. **Geometry, Navmesh & Visual Alignment (`HighGroundPlateau`):**
   * Audit cliff-wall collider generation along non-ramp edges: inset cliff collider endpoints by `4–6 px` at ramp corners (or chamfer corner posts slightly) so heavy walkers (`Monolith Dreadnought`, `Goliath Frame`, `Anvil Siege-Walker`) pushing up a `180–220 px` wide ramp 3–4 abreast never snag on corner collision edges.
   * Update procedural ramp tread/chevron rendering (`_draw()`) to span the **full width** of the open ramp edge cleanly, drawing subtle stepped visual slope bars extending `~30 px` outward from the Level 1 crest edge onto Level 0 ground—clearly communicating both the wide assault lane and the exact **crest line** where Elevation 1 vision begins.
   * Ensure `ArenaNavRegion` bakes clean, wide continuous navmesh openings matching every ramp's full visual width.
3. **Hand-Crafted Skirmish Arena Ramp Pass:**
   * **`scenes/maps/skirmish_arena_01.tscn` (*Vat Basin*):** Widen the ramp edges on both symmetric mid-field overlook plateaus to **`190–210 px`** (adjusting plateau polygon vertices symmetrically while keeping zero overlap with bases, resources, landmarks, or `(0, 0)` Hyper-Uplink).
   * **`scenes/maps/skirmish_arena_02.tscn` (*Twin Causeway*):** Widen the base-facing plateau access ramps to **`185–205 px`** so high-ground ridges play as open assault overlooks; keep any narrow choke strictly limited to the map's intentional central bridge/barricade causeway lanes.
   * **`scenes/maps/skirmish_arena_03.tscn` (*Quad Nexus*):** Widen dual ramps on all 4 rotationally symmetric inner-ring terraces to **`185–210 px`** so 2v2 and 4P FFA armies can push onto high-ground overlooks without single-file traffic jams.

---

## Phase C — Procedural Skirmish Generator Refinements (`scripts/world/procedural_arena_generator.gd`)

Update the Milestone 3.6 `ProceduralArenaGenerator` plateau generation rules so generated plateaus are spacious, well-separated from starting bases, and always have wide assault ramps:

### C.1 Greater Base Exclusion Clearance
* Enforce a strict **Base Exclusion Radius of `520–600 px`** (use **`560 px`** default, `>= 520 px` hard minimum) measured from every starting Command Hub spawn anchor to the **nearest vertex/edge** of any generated `HighGroundPlateau`.
* Also enforce **`>= 110 px` clearance** from every starter BiomassNode, SilicaVein, ComputeVent, and primary base exit corridor so players never spawn boxed against a cliff wall and always have clean room to build their opening base (`Synapse Pylon`, `Cloning Vat`, `Assembly Bay`, `Capacitor Pylon`, etc.).

### C.2 Larger Plateau Footprints & Guaranteed Wide Ramps
* **Expanded Plateau Sizing (Scaled by `proc_map_high_ground`):**
  * **Major Contested Mid-Field Ridges:** Generate spacious chamfered hexagonal/octagonal plateaus with dimensions in the **`360×270 px` to `460×320 px`** range (depending on `Mid Plateaus` vs. `High Ground+`), giving armies real tactical room to position, split, and maneuver on top of the plateau.
  * **Secondary Flank Lookout Ledges (when `High Ground+` is active):** Generate clean **`340×250 px`** ridges along outer flank approaches.
* **Explicit Wide Ramp Edge Construction (`180–220 px`):**
  * Construct plateau polygons deterministically so every edge designated as a ramp has an exact geometric length between **`180.0 px` and `220.0 px`** (strictly `>= 180.0 px`—never accidentally generating a narrow 90 px chamfer as a ramp!).
  * **Major Mid-Field Ridges:** Always include **2 wide ramps** (one angled toward the nearby base/natural side and one angled toward the center/flank lane), mirrored with exact 180° rotational (2P) or 4-way quadrant (3P/4P) symmetry.
  * **Secondary Flank Ledges:** Include **1 wide ramp (`185–215 px`)** facing directly toward clear navigable terrain.
* **Ramp Approach Clearance Guarantee:**
  * For every generated ramp edge, project an outward clear-zone rectangle (`width = ramp_width`, `depth = 135 px`) onto Level 0 and verify it has **zero overlap** with `TerrainObstacle`s, `MapLandmark`s, `ResourceNode`s, `DestructibleBarricade`s, arena walls, or other plateaus. Reject/nudge any obstacle or plateau candidate that violates ramp clearance.
* **Seed Compatibility:** Keep deterministic `RandomNumberGenerator` usage strictly keyed to `GameConfig.proc_map_active_seed` so identical seeds + settings always reproduce the exact same refined arena.

---

## Phase D — Verification & Playtest Checklist

1. **SC2 High-Ground Fog of War Verification (`skirmish_arena_01` & `milestone_0_test`):**
   * Place an enemy `Rail-Sentinel` or `Clone Trooper` squad on top of a `HighGroundPlateau` with Fog of War **ON**:
     * Move a friendly unit up to the **foot of the ramp** (Elevation 0): confirm the enemy on top remains **completely hidden**.
     * Let the enemy shoot downhill at your low-ground unit: confirm **zero attack-reveal** (the uphill shooter stays hidden in fog), while the incoming tracer/impact VFX and `under_attack` alert clearly show fire coming from the plateau.
     * Confirm your low-ground unit does **not** return fire through fog; if `IDLE` in `AGGRESSIVE` stance, confirm it advances up the ramp toward the fire, and the exact instant it crosses the **ramp crest**, full plateau vision snaps open and combat engages!
     * Test **opaque plateau blocking**: position a low-ground unit on one side of a plateau and an enemy unit on low ground directly behind the plateau—confirm the low-ground unit cannot see *through* the plateau.
     * Capture an overlapping `SensorRelay` (or move a spotter onto the plateau): confirm full allied vision onto the high ground opens immediately.
     * Scout an enemy building on high ground, then retreat off the plateau: confirm the building stays visible in Explored fog while live enemy units vanish.
2. **Wide Ramp Movement & Anti-Choke Feel:**
   * Box-select `4× Monolith Dreadnought` (or `4× Goliath Frame` / `10× Clone Trooper`) and issue Move / Attack-Move orders straight up ramps across **`skirmish_arena_01`**, **`02`**, and **`03`**: confirm squads push up **`180–220 px`** wide ramps smoothly abreast without single-file bottlenecking or corner snagging.
3. **Procedural Arena Refinement Check:**
   * Roll 5+ different seeds across **2P (`Balanced` / `Mid Plateaus` / `High Ground+`)** and **4P FFA (`Tight` / `High Ground+`)** in `MainMenu`:
     * Verify every generated plateau sits comfortably **`>= 520 px`** away from all starting Command Hubs and mineral lines.
     * Verify generated plateaus feel spacious (`340–460 px`), every ramp is visibly wide (`180–220 px`) with unobstructed `>= 130 px` entrances, and `TacticalMinimap` renders the enlarged plateaus accurately.
     * Run a 4P AI Spectator match on a `High Ground+` procedural seed at `2x` speed for 3+ minutes: confirm AI teams never shoot uphill through fog without a spotter, push ramps smoothly to contest high-ground fire, and never stall on corners.