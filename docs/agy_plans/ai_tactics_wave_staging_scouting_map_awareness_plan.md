# Milestone 2.6 Plan: AI Tactics, Wave Staging, Reactive Scouting & Map Awareness

**Target Directory:** `docs/agy_plans/32_ai_tactics_staging_scouting_and_map_awareness.md`
**Primary Extended Files:** `scripts/systems/skirmish_ai.gd`, `scripts/buildings/building.gd`, `scripts/buildings/production_component.gd`, `scripts/world/destructible_barricade.gd`, `scripts/world/salvage_core.gd`, `ui/hud/sandbox_debug_panel.gd`
**Reference Docs:** `docs/agy_plans/engine_depth_multi_team_map_2_tools_bundle.md`, `docs/agy_plans/28_ffa_arena_lobby_teams_decals_and_camera_feel.md`, `docs/agy_plans/30_worker_saturation_and_harvest_polish.md`

## 1. Objective & Scope

Upgrade `SkirmishAICommander` (`scripts/systems/skirmish_ai.gd`) from a basic macro-and-trickle opponent into a readable, reactive RTS tactical commander across all three skirmish maps (`Vat Basin`, `Twin Causeway`, and `Quad Nexus`) and all match configurations (`1v1`, `2v2`, `3P/4P FFA`, and `AI vs AI Spectator`).

### In Scope

1. **Wave Staging, Cohesive Assaults & Retreat Thresholds:**

   * Compute a dynamic **Staging Rally Point** outside the AI's base/natural expansion oriented toward the map center / `Data Hyper-Uplink`, and route newly produced military units there via building rally points so armies form cohesive waves instead of trickling into enemy fire 1–2 units at a time.

   * Add an explicit **Army State Machine** (`STAGING`, `ATTACKING`, `DEFENDING`, `RETREATING`, `BREACHING`) with strength-ratio retreat logic: when an attacking wave drops below **`25%`** of its launch strength (and isn't finishing off a critical low-HP enemy `Nexus Vat`), pull survivors back to the staging point to regroup with fresh reinforcements.

   * Prioritize immediate **Base Defense** if an enemy force enters the AI's home perimeter (`~650 px` of any owned `Nexus Vat` or economy cluster).

2. **Early Scouting & Reactive Counter-Production:**

   * Dispatch a fast early scout (`Stinger`, or a `Clone Trooper` fallback if no `Stinger` is trained) around `60–90s` (scaled by `AIDifficulty`) to patrol toward enemy base quadrants and the `Data Hyper-Uplink`.

   * Record a per-AI **Intel Snapshot** (`_scouted_intel: Dictionary`) whenever friendly AI units see enemy tech structures or heavy army compositions (no map-hacking: reads only enemies within actual unit/building vision range via `SpatialGrid`).

   * Dynamically bias mid-game production weights based on scouted intel while preserving `AIPlaystyle` (`Balanced`, `Swarm Rush`, `Synthetics Tech`) identity:

     * Spotting `Synthetics Fabricator` or `Goliath Frame` / `Arc-Lancer` → boosts **Lance-Rig** (anti-armor) and **Calibration Foundry** priority.

     * Spotting heavy `Cloning Vat` infantry swarms (`Clone Trooper` / `Stinger`) → boosts **Chrysalis Mortar** (splash), **Signal Jammer** (disruption), and **Symbiote** sustain.

     * Spotting `Chrysalis Mortar` artillery → boosts fast flanking **Stingers** and **Goliath Frame** frontline pressure.

3. **Map #2 & Map #3 Tactical Awareness (Barricades & Salvage Cores):**

   * **Destructible Barricade Breaching:** Detect intact `DestructibleBarricade`s blocking nearby flank corridors or rich side expansion pockets on `skirmish_arena_02` (*Twin Causeway*) and `skirmish_arena_03` (*Quad Nexus*). Once the AI reaches mid-game (or fields anti-armor/siege units like `Lance-Rig`, `Chrysalis Mortar`, or `Goliath Frame`), dispatch a breaching squad to explicitly focus-fire and open the gate before pushing through or expanding.

   * **Safe `SalvageCore` Contesting:** Scan for uncontested `SalvageCore` drops within safe operating distance of the AI's base or victorious army, dispatching an available `Engineer` or `Worker` to extract the Silica/Compute burst only when no overwhelming enemy force is guarding the wreck.

4. **Multi-Team / FFA & Difficulty Hygiene:**

   * Ensure all staging, scouting, breaching, and target selection logic uses `TeamManager.are_enemies()` / `TeamManager.are_allies()` so 2v2 AI teammates coordinate cleanly without friendly fire and 4-player FFA AIs select sensible targets (favoring nearest active enemy or the current `Hyper-Uplink` holder).

   * Add an optional compact AI status line inside `SandboxDebugPanel` (e.g., `AI-1: STAGING (7/8) | Counter: ANTI_ARMOR`) to make live testing and tuning effortless.

### Out of Scope

* Cheating resource income or Fog-of-War map-hacking (the AI must only react to enemy units/buildings observed within its own/allied vision).

* Micro-splitting individual units against mortar shells or manual stutter-step kiting per unit.

* Faction #2 specific build orders (keep role lookups routed through `TeamManager.get_faction_data()`).

## 2. Phase A: Wave Staging, Cohesive Assaults & Retreat Thresholds

### A.1 Dynamic Staging Point & Production Rallying (`scripts/systems/skirmish_ai.gd`)

* **Compute `_staging_point: Vector2`:**

  * On `_ready()` (and whenever a new expansion `Nexus Vat` completes), locate the AI's primary `Nexus Vat` and the central `Data Hyper-Uplink` (or map center `(0, 0)`).

  * Project `~360–440 px` from the primary hub toward the center, then verify the point is clear of `TerrainObstacle`s and `DestructibleBarricade`s (nudge/clamp to nearest valid navigable point via `NavigationServer2D.map_get_closest_point()`).

* **Automatic Military Rallying:**

  * Whenever the AI finishes constructing a military production structure (`Cloning Vat`, `Calibration Foundry`, `Synthetics Fabricator`), set its `rally_point = _staging_point` so fresh reinforcements automatically gather at the staging anchor instead of cluttering inside the mineral line.

### A.2 Explicit Army State Machine (`scripts/systems/skirmish_ai.gd`)

Replace ad-hoc attack triggers with a clean state machine evaluated on the AI's tactical tick:

* `enum ArmyState { STAGING, ATTACKING, DEFENDING, RETREATING, BREACHING }`

* **Wave Launch Thresholds (Scaled by `AIDifficulty` & `AIPlaystyle`):**

  * `RELAXED`: waits for `~6–7` combat units (or `~5` on `SWARM_RUSH`), longer cooldown between waves (`~30s`).

  * `STANDARD`: launches wave 1 at `~6` combat units (`~5` on `SWARM_RUSH`, `~8` with heavy units on `SYNTHETICS_TECH`), scaling wave size slightly as match time progresses.

  * `BRUTAL`: launches crisp coordinated waves (`~7–10` combat units with support/counters included) and regroups rapidly.

* **Cohesive Wave Launch (`STAGING → ATTACKING`):**

  * Record `_wave_launch_strength: float` (sum of living combat unit power/supply weights in the wave) and `_wave_units: Array[Unit]`.

  * Issue a unified `Attack-Move` order to `_current_attack_target` (prioritizing contested `Data Hyper-Uplink` when opponent hold progress `> 35%`, nearest enemy expansion/army, or enemy `Nexus Vat`).

  * Keep units spawned *during* an active `ATTACKING` wave holding at `_staging_point` to form the next wave (or rally onto the wave lead unit only if the wave is still `> 70%` strength and winning).

* **Retreat Threshold (`ATTACKING → RETREATING → STAGING`):**

  * Prune dead units from `_wave_units` each tactical tick and compute `remaining_ratio = current_wave_strength / maxf(_wave_launch_strength, 1.0)`.

  * **Retreat Trigger:** If `remaining_ratio < 0.25` (or `< 0.30` on `BRUTAL` to preserve expensive heavies like `Goliath Frame` / `Arc-Lancer`), **unless** the wave is within `320 px` of an enemy `Nexus Vat` below `35% HP`:

    * Transition to `RETREATING`, issue a clean `Move` order back to `_staging_point` for surviving wave units, and set a brief regroup timer (`8.0s`) before transitioning back to `STAGING`.

* **Base Defense Interrupt (`ANY → DEFENDING`):**

  * Query `SpatialGrid.query_units_in_radius(hub.global_position, 650.0)` for hostile combat units (`TeamManager.are_enemies()`).

  * If enemies threaten the base, immediately pull `STAGING` / `RETREATING` / `BREACHING` units (and `ATTACKING` units if no home defenders remain) to intercept the threat via `Attack-Move`, returning to `STAGING` once the perimeter is clear for `3.0s`.

## 3. Phase B: Early Scouting & Reactive Counter-Production

### B.1 Early Scout Dispatch (`scripts/systems/skirmish_ai.gd`)

* **Scout Timing & Selection:**

  * `RELAXED`: optional late scout (`~130s`).

  * `STANDARD`: dispatches 1 scout at `~75s` (re-scouting every `~95s` if previous scout dies).

  * `BRUTAL`: dispatches 1 fast `Stinger` scout at `~55s` (re-scouting every `~65s`).

* **Scout Route:**

  * Pick an active enemy team's likely base quadrant (using enemy starting hub quadrant or unexplored map corners on `skirmish_arena_03`) and queue a `Move` loop: `Data Hyper-Uplink` → outer flank approach near enemy base → safe return toward `_staging_point`.

  * Exclude the designated `_active_scout: Unit` from `STAGING` / `ATTACKING` wave orders until its scout loop finishes or it dies.

### B.2 Vision-Respecting Intel & Counter Weights (`scripts/systems/skirmish_ai.gd`)

* **Fair Intel Gathering (`_update_scouted_intel()`):**

  * Every `1.5s`, scan enemies within the vision radius of the AI's living units and buildings (using `SpatialGrid`, strictly honoring actual line-of-sight / vision range—never reading unrevealed enemy bases).

  * Update a decaying intel table (`intel_ttl = 90.0s`):

    * `saw_heavy_armor: bool` (spotted `Synthetics Fabricator`, `Goliath Frame`, or `Arc-Lancer`)

    * `saw_infantry_swarm: bool` (spotted `>= 2` `Cloning Vats` or `>= 6` enemy `Clone Troopers` / `Stingers`)

    * `saw_artillery: bool` (spotted `Chrysalis Mortar`)

    * `saw_turrets: bool` (spotted `Sentry Pylon` / `has_turret` buildings)

    * `last_known_enemy_base: Vector2`

* **Reactive Production Biasing:**

  * Compute an active counter posture (`&"NONE"`, `&"ANTI_ARMOR"`, `&"ANTI_SWARM"`, `&"ANTI_SIEGE"`) from `_scouted_intel`:

    * **`ANTI_ARMOR`:** Prioritize constructing a `Calibration Foundry` (if not owned) and shift production weight `+35%` toward `Lance-Rig` (and `Arc-Lancer` if Tier 2 is online).

    * **`ANTI_SWARM`:** Shift production weight `+30%` toward `Chrysalis Mortar` (if `Synthetics Fabricator` is online), `Signal Jammer`, and `Symbiote` support.

    * **`ANTI_SIEGE`:** Boost `Stinger` flanking ratio and `Goliath Frame` frontline durability (`Seismic Slam` / push through mortar `min_attack_range`).

  * Scale counter-reaction strength by `AIDifficulty` (`RELAXED: 0.35x`, `STANDARD: 0.75x`, `BRUTAL: 1.0x`) so lower difficulties stay approachable while `BRUTAL` adapts sharply.

## 4. Phase C: Map #2 & Map #3 Tactical Awareness

### C.1 Destructible Barricade Breaching (`scripts/systems/skirmish_ai.gd`)

* **Barricade Discovery:**

  * Query group `"destructible_barricades"` for intact barricades within `~1100 px` of the AI's primary hub or lying along a flank/expansion lane.

  * Ignore barricades during the opening `2.5` minutes so the AI never delays its core economy or early defense.

* **Breaching Logic (`STAGING → BREACHING`):**

  * On `skirmish_arena_02` (*Twin Causeway*) and `skirmish_arena_03` (*Quad Nexus*), once the AI has either `>= 4` combat units with at least 1 anti-armor/siege unit (`Lance-Rig`, `Chrysalis Mortar`, `Goliath Frame`) **or** wants to claim a barricade-blocked expansion pocket:

    * Select the nearest intact flank barricade, enter `BREACHING`, and issue an **explicit attack order** (`unit.issue_attack_target(barricade)`) since auto-aggro ignores neutral barricades by design.

    * Interrupt `BREACHING` immediately if an enemy combat force engages the breaching squad or threatens the AI's base.

    * Once the barricade shatters (and `ArenaNavRegion` rebakes), mark the lane open and transition cleanly to `ATTACKING` (flank raid) or `STAGING` / expansion dispatch.

### C.2 Safe `SalvageCore` Contesting (`scripts/systems/skirmish_ai.gd`)

* Every `3.0s` (on `STANDARD` and `BRUTAL`; `6.0s` on `RELAXED`), query active `SalvageCore` nodes within `~950 px` of the AI's base or `_staging_point` (or within `450 px` of a victorious AI army).

* **Safety Check:** Use `SpatialGrid.query_units_in_radius(core.global_position, 360.0)` to ensure the wreck is not guarded by enemy combat units outnumbering nearby friendly combat units.

* **Dispatch:** Pick 1 available `Engineer` (preferred for faster `1.8s` extraction) or 1 `Worker` (never pulling below 3 Biomass harvesters), and issue a direct salvage extraction order. Avoid sending duplicate workers to a `SalvageCore` already claimed by an allied extractor.

## 5. Phase D: Multi-Team Target Priority & Debug Readout

* **Smart Target Selection in 3P / 4P FFA (`skirmish_ai.gd`):**

  * When multiple enemy alliances are alive, score potential attack targets by:

    1. Enemy currently holding/progressing the `Data Hyper-Uplink` (`> 40%` capture) — high urgency to prevent an Uplink victory.

    2. Closest active enemy base/expansion to this AI's primary hub (prevents walking past an immediate neighbor across the whole map).

    3. Never target allied teams (`TeamManager.are_allies()`).

* **Optional Debug Inspection (`ui/hud/sandbox_debug_panel.gd`):**

  * When `SandboxDebugPanel` is toggled open, show a compact 1-line readout per active `SkirmishAICommander` (`AI [T1]: STAGING (5/7) | INTEL: ANTI_ARMOR | BARRICADES: 2`) so you can verify wave launches, retreats, scouting, and breaching in real time during `AI vs AI (Spectator)` matches.

## 6. File & Architecture Summary

### Existing Files to Extend

* `scripts/systems/skirmish_ai.gd`: Dynamic `_staging_point` + military rally wiring, `ArmyState` machine (`STAGING`, `ATTACKING`, `DEFENDING`, `RETREATING`, `BREACHING`), `25%` wave retreat threshold, early scout routine, vision-respecting `_scouted_intel` counter weights, `DestructibleBarricade` breaching orders, safe `SalvageCore` extraction dispatch, and FFA target scoring.

* `ui/hud/sandbox_debug_panel.gd`: Compact read-only AI tactical telemetry line when Debug HUD is open (zero impact on clean skirmish HUD when hidden).

* *(Verify read-only helpers if needed)* `scripts/world/destructible_barricade.gd`, `scripts/world/salvage_core.gd`, `scripts/units/unit.gd`: Ensure explicit `issue_attack_target(barricade)` and `issue_salvage(core)` calls work identically for AI-controlled units as they do for player commands.

## 7. Verification Checklist for `agy`

Before concluding Milestone 2.6, verify in Godot (`skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, and `skirmish_arena_03.tscn`):

* \[ \] **Wave Staging & Cohesive Assaults:** Watch an `AI vs AI (Spectator)` match at `2x` speed (with Fog of War off and Debug HUD toggled on via `Esc`); confirm military units rally cleanly to each AI's `_staging_point`, assemble into cohesive squads (`5–10` units depending on Difficulty/Playstyle), and attack together rather than trickling in 1-by-1.

* \[ \] **Retreat Threshold & Base Defense:** Engage an attacking AI wave until it loses `> 75%` of its strength; confirm surviving units cleanly transition to `RETREATING` and fall back to `_staging_point` to regroup rather than suiciding one at a time. Then raid an AI's base with `Stingers` and confirm its staging army immediately switches to `DEFENDING`.

* \[ \] **Early Scouting & Reactive Counters:** Launch a `Player vs AI` (`Standard` or `Brutal`) match and rush a `Synthetics Fabricator` + `Goliath Frame`s; verify an early AI scout checks your base and the AI's debug intel flips to `ANTI_ARMOR`, visibly increasing `Lance-Rig` production. Repeat with heavy `Cloning Vat` infantry spam and confirm `ANTI_SWARM` response.

* \[ \] **Destructible Barricade Breaching (`Twin Causeway` & `Quad Nexus`):** Run a `2x` Spectator match on `skirmish_arena_02.tscn` and a `4-Way FFA` on `skirmish_arena_03.tscn`; confirm mid-game AI squads explicitly target and destroy flank `DestructibleBarricade`s, immediately path through the breached lane after navmesh rebake, and never freeze or get stuck on intact gates.

* \[ \] **Safe `SalvageCore` Contesting & Debugger Hygiene:** Destroy a `Goliath Frame` or `Arc-Lancer` near an AI's perimeter; confirm the AI dispatches an `Engineer` or `Worker` to claim the `SalvageCore` when safe (and skips it when heavily guarded), with zero Godot Debugger errors across a full 4-player match.