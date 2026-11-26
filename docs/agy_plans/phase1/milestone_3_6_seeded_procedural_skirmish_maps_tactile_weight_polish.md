# Milestone 3.6 — Seeded Procedural Skirmish Maps & Tactile "Weight & Punch" Polish

**Prerequisite:** Milestones 3.1–3.5b verified and working cleanly.

**Goal:** Deliver high replayability and visceral battlefield weight without adding new rules, HUD clutter, or automation:

1. **Seeded Procedural Symmetric Skirmish Generator (`ProceduralArenaGenerator`):** Add a playable **Procedural Arena (2–4P)** option in the Skirmish Lobby powered by deterministic seeds, rotational 2P / quadrant 4P symmetry, quick parameter selectors (*Chokes*, *High Ground*, *Richness*, *Biome*), guaranteed navigable base exits, and full compatibility with `HighGroundPlateau`, `HyperUplink`, `SensorRelay`, `DestructibleBarricade`, `FogOfWar`, `ArenaNavRegion`, and `SkirmishAI`.
2. **Tactile "Weight & Punch" Polish Pass:** Elevate combat feel across `GENESIS_V2` and `MONOLITH_OS` with procedural unit chassis recoil kickback, heavy muzzle shock/dust rings, `Anvil Siege-Walker` anchor-impact thuds, directional shield-shatter knock-sparks, enriched Tier 2 sub-bass synth punch, and restrained, distance-attenuated camera micro-shake.

**Hard Design Guardrails (MUST PRESERVE):**
* **Zero Skill-Cap Automation:** Do **NOT** add overkill-prevention targeting or auto-looping production queues. Manual target spreading and manual macro cadence remain core player skills.
* **100% Procedural Pipeline:** All map geometry, biome backdrops, recoil/shock VFX, and sub-bass SFX must be procedural (zero external image or audio assets).
* **Strict `1280×720` UI Discipline:** `MainMenu` (`ConfigPanel` at `448 px` width), `PauseMenu`, and `MatchEndOverlay` must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).
* **4P FFA Performance Guard:** Route all new transient VFX through `VFXPool`, gate all combat VFX/SFX on visibility (zero Fog-of-War leaks), and keep procedural recoil strictly visual (never mutating `CollisionShape2D` or physics positions).
* **Hard Exclusions:** No stealth/cloaking mechanics; no role-sorted squad formations.

---

## Phase A — Seeded Procedural Skirmish Map Generator

### A.1 Lobby Configuration & Seed Persistence (`scripts/systems/game_config.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`)

1. **`GameConfig` (`scripts/systems/game_config.gd`):**
   * Add constant `const MAP_SKIRMISH_PROCEDURAL: String = "res://scenes/maps/skirmish_arena_procedural.tscn"`.
   * Append to `MAP_CATALOG`:
     `{"path": MAP_SKIRMISH_PROCEDURAL, "label": "Procedural Arena (Seeded 2–4P)", "max_players": 4}`.
   * Add persisted lobby state fields:
     * `var proc_map_seed: int = 0` *(0 = auto-roll a clean 6-digit seed `100000..999999` on launch and store it in `proc_map_active_seed` so **Rematch** replays the exact same arena!)*.
     * `var proc_map_active_seed: int = 482915`
     * `var proc_map_chokes: int = 1` (`0 = Open`, `1 = Balanced`, `2 = Tight`)
     * `var proc_map_high_ground: int = 1` (`0 = Flat`, `1 = Moderate`, `2 = Elevated`)
     * `var proc_map_richness: int = 1` (`0 = Standard`, `1 = Rich`, `2 = Abundant`)
     * `var proc_map_biome: StringName = &"auto"` (`&"auto"`, `&"vat_basin"`, `&"twin_causeway"`, `&"quad_nexus"`)
   * Add helper `func resolve_procedural_seed() -> int` (returns `proc_map_seed` if `> 0`, otherwise rolls a deterministic-friendly `100000..999999` seed and caches it in `proc_map_active_seed`).
   * Add helper `func get_procedural_summary_tag() -> String` (e.g., `"SEED 482915 • Balanced • Elev • Rich"`).

2. **`MainMenu` (`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`):**
   * Inside `ConfigPanel`'s Skirmish section, add a compact `VBoxContainer` (`%ProcMapOptionsBox`, `visible = false` unless `Procedural Arena` is selected in `MapOption`):
     * **Row 1 (`HBoxContainer`, height `24 px`):**
       * Compact `Label` (`"SEED"`), `LineEdit` (`%ProcSeedInput`, numeric placeholder `"Random"`, `custom_minimum_size = Vector2(78, 24)`), `"RND"` button (`%BtnRollSeed`, rolls & displays a new 6-digit seed), and `OptionButton` (`%OptProcBiome`: `Auto Biome`, `Vat Basin`, `Causeway`, `Quad Nexus`).
     * **Row 2 (`HBoxContainer`, height `24 px`, `separation = 4`):**
       * Three compact `OptionButton`s (`clip_text = true`, `fit_to_longest_item = false`, `size_flags_horizontal = SIZE_EXPAND_FILL`, `font_size = 10`):
         * `%OptProcChokes`: `Open Lanes`, `Balanced`, `Tight Chokes`
         * `%OptProcHighGround`: `Flat Ground`, `Mid Plateaus`, `High Ground+`
         * `%OptProcRichness`: `Std Yield`, `Rich Yield`, `Abundant`
   * Verify `ConfigPanel` stays **100% unclipped vertically and horizontally at `1280×720`** when `%ProcMapOptionsBox` is visible (even with 4 player slots shown on `Procedural Arena`!). Tighten spacer/separation by 1–2 px if needed.
   * Show the active Seed in `MatchSummaryLabel`, `PauseMenu` (compact seed readout), and `MatchEndOverlay` header subtitle so players can note and replay favorite seeds.

### A.2 Base Scene & Deterministic Generator (`scenes/maps/skirmish_arena_procedural.tscn` & `scripts/world/procedural_arena_generator.gd`)

1. **Base Scene (`scenes/maps/skirmish_arena_procedural.tscn`):**
   * Clone the clean infrastructure skeleton of `skirmish_arena_03.tscn` (`ArenaNavRegion`, `MapBiomeBackdrop`, `BattleScarsOverlay`, `Buildings`, `Units`, `Resources`, `Terrain`, `Objectives`, `FogOfWar`, `EconomyManager`, `MatchManager`, `SelectionController`, `RTSCamera`, HUD `CanvasLayer`), removing all hand-placed obstacles, plateaus, resources, hubs, and units.
   * Add a `ProceduralArenaGenerator` node (`scripts/world/procedural_arena_generator.gd`) placed cleanly to execute **before** `MatchManager._initialize_match_runtime()` spawns starting loadouts.

2. **Deterministic Symmetry Engine (`scripts/world/procedural_arena_generator.gd`):**
   * Use a dedicated `RandomNumberGenerator.new()` seeded exclusively with `GameConfig.proc_map_active_seed` so identical seeds + settings generate the exact same battlefield every time.
   * **Arena Bounds & Symmetry Mode:**
     * `player_count <= 2`: `arena_bounds = Rect2(-1300.0, -950.0, 2600.0, 1900.0)`, **180° Rotational (Point) Symmetry** around `(0, 0)` — every object placed at `pos` is mirrored at `-pos`.
     * `player_count >= 3`: `arena_bounds = Rect2(-1400.0, -1050.0, 2800.0, 2100.0)`, **4-Way Quadrant Symmetry** around `(0, 0)` — every feature in Quadrant 0 `(x, y)` is mirrored cleanly across `(-x, -y)`, `(-x, y)`, and `(x, -y)` (matching `Quad Nexus`'s 2v2 / 4P FFA corner ordering: Slot 0 BL, Slot 1 TR, Slot 2 TL, Slot 3 BR).
   * **Biome Selection:**
     * Apply `GameConfig.proc_map_biome` to `MapBiomeBackdrop.biome_id` (if `&"auto"`, deterministically pick from `[&"vat_basin", &"twin_causeway", &"quad_nexus"]` via `rng`) and sync `arena_bounds` across `MapBiomeBackdrop`, `ArenaNavRegion`, `FogOfWar`, `RTSCamera`, `SelectionController` / `CommandRouter.buildable_bounds`, and `TacticalMinimap`.

3. **Guaranteed Fair & Navigable Layout Pipeline (Strict Placement Order):**
   * **Step 1 — Central Objective (`(0, 0)`):**
     * Instance `scenes/world/hyper_uplink.tscn` at `Vector2.ZERO`.
     * Reserve a clear `200 px` exclusion circle around `(0, 0)` so units can contest the uplink freely.
   * **Step 2 — Corner Spawn Anchors & Reserved Base Corridors:**
     * Place 2 (or 4) symmetric corner spawn anchors inset safely from walls (e.g., `±(960, 640)` for 2P; `±(1040, 720)` for 3P/4P) as `Marker2D` nodes in group `"spawn_anchors"` with `set_meta("team_id", tid)`.
     * **Lane Reservation Corridors (Anti-Trap Guarantee):** Record capsule/segment corridors (`width >= 150 px`) linking each spawn anchor to:
       1. Its local natural expansion,
       2. The central Hyper-Uplink `(0, 0)`, and
       3. The outer perimeter flank lane.
     * Every subsequent obstacle and cliff wall placement checks against all reserved corridors and spawn circles so **no seed can ever trap a base or block a main attack lane**.
   * **Step 3 — Starting Base Resource Clusters (Guaranteed Mirror):**
     * Around each spawn anchor (facing away from map center along a clean `110°` harvesting arc, `200–255 px` from hub center, `>= 74 px` spacing between nodes):
       * `3` (or `4` on `Abundant`) `biomass_node.tscn` deposits.
       * `2` `silica_vein.tscn` deposits.
       * `1` `compute_vent.tscn` geyser (`260–310 px` offset from hub, clear of base exits).
     * Scale node `max_amount` & `remaining_amount` by `Richness`: `Standard = 1.0×`, `Rich = 1.25×`, `Abundant = 1.55×`.
   * **Step 4 — Symmetric Natural & Contested Mid Expansions:**
     * Place `1` symmetric natural expansion per player (plus `1` contested side-pocket expansion per pair on `Rich` / `Abundant`) containing `2–3 BiomassNodes`, `1–2 SilicaVeins`, and `1 ComputeVent`.
   * **Step 5 — High-Ground Plateaus (`HighGroundPlateau`, when `proc_map_high_ground >= 1`):**
     * Generate `2` (2P) or `4` (4P) symmetric elevated overlooks (or `4` / `4` larger dual-ramp plateaus on `High Ground+`) positioned between the bases and the central Hyper-Uplink Plaza.
     * Generate clean chamfered hexagonal/octagonal polygons (`190–250 px` span) with `2` open ramp edges (`>= 136 px` wide each, one base-facing and one flank/center-facing).
     * Reject/nudge any candidate polygon that overlaps spawn circles, resource nodes, vents, or the central uplink plaza; mirror the validated polygon symmetrically across all corners.
     * Tint `biome_tint` to match the selected `MapBiomeBackdrop`.
   * **Step 6 — Symmetric Cover Monoliths (`TerrainObstacle`) & Barricaded Flanks (`DestructibleBarricade`):**
     * Place `2–6` symmetric obstacle clusters based on `proc_map_chokes` (`Open`: light corner/plaza cover; `Balanced`: standard cover pillars + flank dividers; `Tight`: pronounced tactical chokes with wider flank lanes).
     * Enforce `>= 128 px` minimum clearance between all obstacles, plateaus, and arena edges so `Monolith Dreadnought` and `Goliath Frame` never snag.
     * When `proc_map_chokes >= 1`, place `2` (2P) or `4` (4P) symmetric `destructible_barricade.tscn` blockers across secondary flank shortcut lanes (never blocking the main center lane).
   * **Step 7 — Flank `SensorRelay` Pads & Subtle `MapLandmark` Beacons:**
     * Place `2` (2P) or `4` (4P) symmetric `sensor_relay.tscn` pads along outer flank sightlines (verifying clear ground off cliff edges).

### A.3 Clean MatchManager, FogOfWar & Minimap Sync
* **`scripts/systems/match_manager.gd`:**
  * In `_initialize_match_runtime()`, if a `ProceduralArenaGenerator` node exists in the scene, invoke `generator.generate_arena()` synchronously **before** `_bootstrap_skirmish_teams()`.
  * In `_bootstrap_skirmish_teams()`, also scan nodes in group `"spawn_anchors"` (reading `get_meta("team_id")`) to populate `_spawn_anchors[tid]` when no pre-placed hub exists—so `_swap_team_starting_loadout()` cleanly instantiates each active team's exact `FactionData` starting hub, workers, and extra starting units directly on the generated anchors!
* **`scripts/systems/fog_of_war.gd`:**
  * Expose `rebuild_static_grids() -> void` to re-scan `terrain_obstacles`, `map_landmarks`, `destructible_barricades`, and `high_ground_plateaus` after procedural generation completes (and call it cleanly from `ProceduralArenaGenerator` / `MatchManager`).
* **`scripts/world/arena_nav_region.gd` & `ui/hud/minimap.gd`:**
  * Ensure `ArenaNavRegion` updates `arena_bounds` and rebakes immediately after generation, and `TacticalMinimap` refreshes its cached static terrain/plateau geometry and bounds.

---

## Phase B — Tactile "Weight & Punch" Polish Pass

Elevate moment-to-moment combat impact for both `GENESIS_V2` and `MONOLITH_OS` without altering unit DPS, targeting rules, or skill expression:

### B.1 Procedural Unit Chassis Recoil Kick (`scripts/units/unit.gd`, `scripts/units/combat_component.gd`)
* Add purely visual recoil state on `Unit`:
  * `var _recoil_offset: float = 0.0`
  * `var _recoil_decay_rate: float = 28.0`
  * `func trigger_weapon_recoil(kick_px: float) -> void`: sets `_recoil_offset = maxf(_recoil_offset, clampf(kick_px, 0.0, 7.5))`.
* In `Unit._process(delta)` (or `_physics_process(delta)`):
  * Smoothly decay `_recoil_offset = move_toward(_recoil_offset, 0.0, _recoil_decay_rate * delta)`.
  * Apply local offset strictly to `body_visual.position = Vector2(-cos(body_visual.rotation), -sin(body_visual.rotation)) * _recoil_offset` (leaving `Unit.global_position`, `CollisionShape2D`, `HealthBar`, and `SelectionRing` rock-steady!).
* In `CombatComponent` when a shot fires, trigger calibrated kickback derived from `UnitData`:
  * Fast light units (`attack_cooldown < 0.9s`, non-heavy): `1.2 px` crisp kick.
  * Medium/Armored (`Bulwark Automaton`, `Lance-Rig`, `Picket Drone`): `2.8 px` mechanical kick.
  * Heavy / Siege / Rail (`Rail-Sentinel`, `Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`, `Monolith Dreadnought`, `Anvil Siege-Walker`): `4.5–6.2 px` unmistakable heavy recoil (`6.2 px` on Deployed `Anvil Siege-Walker` shells).

### B.2 Heavy Muzzle Shock Rings, Anchor Thuds & Directional Shield Shatters (`ui/overlays/combat_vfx.gd`)
Extend `CombatVFX` (100% pooled via `VFXPool`, strictly visibility-gated on `is_friendly_view or visible`):
1. **`setup_muzzle_shock(origin: Vector2, aim_dir: Vector2, radius: float, accent_col: Color, is_brutalist: bool)`:**
   * Lightweight `0.18s` effect spawned when heavy/siege units or `Bastion Emplacement` fire:
     * Crisp directional muzzle flare wedge aligned with `aim_dir`.
     * Faint expanding ground pressure/dust ring (`radius * 0.55 → radius * 1.15`, low alpha `0.38 → 0.0`) so heavy ordnance physically displaces air/dust on the ground.
2. **`setup_anchor_thud(origin: Vector2, radius: float, accent_col: Color)`:**
   * Triggered in `Unit` at the exact frame `DEPLOYING → DEPLOYED` completes (e.g., `Anvil Siege-Walker` locking its 4 stabilizer legs):
     * Crisp `0.26s` expanding ground-impact shock ring + 4 radial dust/halftone kick ticks at the 4 diagonal leg clamps.
     * Plays a crisp low-frequency pneumatic lock-thud (`&"deploy_anchor_lock"` in `AudioManager`).
3. **Directional Shield-Shatter Knock-Sparks:**
   * Update `Unit.take_damage(...)` / `Building.take_damage(...)` to compute `impact_dir = (global_position - attacker.global_position).normalized()` (when `attacker is Node2D and is_instance_valid(attacker)`, else `Vector2.ZERO`) and pass it to `CombatVFX.setup_shield_shatter(global_position, radius, is_monolith_style, impact_dir)`.
   * When `impact_dir != Vector2.ZERO`, bias `50%` of the shatter shard vectors into a crisp directional spray cone along `impact_dir` (while keeping the fractured halo ring centered), giving railgun and siege hits unmistakable directional punch.

### B.3 Sub-Bass Heavy Ordnance Punch & Restrained Micro-Shake (`scripts/systems/audio_manager.gd`, `scripts/camera/rts_camera.gd`, `scripts/systems/settings_manager.gd`)
1. **Procedural Sub-Bass Transient Layer (`scripts/systems/audio_manager.gd`):**
   * Enhance heavy weapon & explosion synth waveforms (`&"weapon_mono_rail"`, `&"weapon_mono_siege"`, `&"weapon_mono_bastion"`, `&"weapon_mortar"`, `&"weapon_arc"`, `&"explosion_heavy"`, and new `&"deploy_anchor_lock"`) by layering a tight `48–85 Hz` exponential pitch-drop sub-bass thump (`~75–110 ms` decay) underneath the metallic/rail crack.
   * Keep peak amplitudes normalized well inside the existing Master `AudioEffectLimiter`, 10-voice combat cap, camera-distance attenuation, and real-time `2x` throttling.
2. **Restrained, Toggleable Combat Micro-Shake (`scripts/camera/rts_camera.gd`, `scripts/systems/settings_manager.gd`):**
   * Add `var screen_shake_enabled: bool = true` to `SettingsManager` (persisted under `[camera]` or `[gameplay]`, with a checkbox in **Settings → Camera**).
   * Ensure `RTSCamera.add_camera_shake(intensity, duration, world_pos)` checks `SettingsManager.screen_shake_enabled`, enforces a smooth cap (`max intensity <= 6.0 px`) so overlapping explosions never stack into nauseating jitter, and attenuates cleanly by distance from camera center.
   * Trigger subtle, crisp micro-shakes (`1.6–2.8 px`, `0.09–0.13s`) on high-impact battlefield events when near the viewport:
     * Deployed `Anvil Siege-Walker` and `Chrysalis Mortar` shell impacts,
     * `Anvil Siege-Walker` anchor lock-in (`1.6 px`),
     * `Goliath Frame` `Seismic Slam` (`2.8 px`),
     * Heavy Tier 2 unit deaths (`Monolith Dreadnought`, `Goliath Frame`, `Arc-Lancer`, `Anvil Siege-Walker`: `2.4 px`).

---

## Phase C — Verification & Playtest Checklist

1. **Procedural Arena Lobby & `1280×720` Layout Audit:**
   * Select `"Procedural Arena (Seeded 2–4P)"` in `MainMenu`: confirm `%ProcMapOptionsBox` appears cleanly inside `ConfigPanel` with zero vertical or horizontal clipping in both **Windowed `1280×720`** and **Fullscreen (`F11`)**, including with **4P** active.
   * Switch back to `Skirmish Arena 01`: confirm `%ProcMapOptionsBox` hides cleanly.
2. **Seed Determinism & Fair Symmetry:**
   * Enter a fixed seed (e.g., `123456`), launch a **2P** match (`MONOLITH_OS` vs `GENESIS_V2`), observe the layout, then click **Rematch** (and also return to Main Menu and relaunch with `123456`): confirm the exact same layout generates every time.
   * Test **4P FFA** and **2v2** on `Procedural Arena` across `Open`, `Balanced`, `Tight`, `Flat`, and `High Ground+` presets:
     * Verify all 4 bases have mirrored `Biomass`, `Silica`, and `ComputeVent` clusters, `HyperUplink` at `(0, 0)`, flank `SensorRelay`s, and wide unobstructed exits.
     * Verify `ArenaNavRegion` bakes cleanly, `FogOfWar` respects generated high-ground plateaus and barricades, and `TacticalMinimap` displays the generated terrain accurately.
   * Run a 4P AI Spectator match on a random seed at `2x` speed for 3+ minutes to confirm AI workers, harvesters, staging waves, and heavy walkers navigate cleanly without getting trapped.
3. **Tactile "Weight & Punch" Feel Check:**
   * Run a `MONOLITH_OS` vs `GENESIS_V2` battle in `milestone_0_test.tscn` or a skirmish:
     * Verify chassis recoil kicks visibly on fire (`Rail-Sentinel`, `Bulwark Automaton`, `Anvil Siege-Walker`, `Monolith Dreadnought`, `Goliath Frame`) while selection rings and HP bars remain rock-steady.
     * Verify ground dust/pressure rings on heavy shots, anchor shock-ring + hydraulic thud on `Anvil Siege-Walker` deploy, and directional shield-shatter sparks angled away from the attacker.
     * Verify heavy ordnance audio has satisfying sub-bass weight without distortion or clipping at `2x` speed.
     * Toggle **Screen Shake** OFF in **Settings → Camera** and confirm camera stays completely static during heavy blasts.