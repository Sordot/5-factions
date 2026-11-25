# Milestone 2.5 Plan: 4-Spawn FFA/2v2 Arena, Lobby Team Configuration, Battle Scars, Tactical Event Feed & Camera Polish

**Target Directory:** `docs/agy_plans/28_ffa_arena_lobby_teams_decals_and_camera_feel.md`
**Primary New Files:** `scenes/maps/skirmish_arena_03.tscn`, `ui/overlays/battle_scars_overlay.gd`, `ui/hud/tactical_event_feed.tscn`, `ui/hud/tactical_event_feed.gd`
**Primary Extended Files:** `scripts/systems/game_config.gd`, `scripts/systems/team_manager.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/systems/settings_manager.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd`, `scripts/camera/rts_camera.gd`, `ui/hud/minimap.gd`, `ui/hud/match_end_overlay.gd`, `ui/overlays/combat_vfx.gd`, `scripts/buildings/building.gd`, `scripts/units/unit.gd`, `scenes/maps/skirmish_arena_01.tscn`, `scenes/maps/skirmish_arena_02.tscn`
**Reference Docs:** `docs/agy_plans/engine_depth_multi_team_map_2_tools_bundle.md`, `docs/agy_plans/engine_hardening_salvage_auto_cast_los_audio_polish.md`, `docs/agy_plans/selection_ergonomics_turret_support_analytics_plan.md`

## 1. Objective & Scope

Bring the `TeamManager` multi-team architecture to life with a full **4-Spawn FFA / 2v2 Skirmish Map** and **Main Menu Player Count & Team/Alliance Configuration**, while adding high-impact battlefield polish (**Persistent Battle Scars & Ground Decals**, a **Tactical Event Feed**, and **Zoom-to-Cursor + Smooth Minimap Dragging**). All new UI elements must fit cleanly inside the `1280×720` (`canvas_items` + `expand`) base viewport in both Windowed and Fullscreen modes.

### In Scope

1. **Main Menu Player Count & Team Configuration (`MainMenu`, `GameConfig`, `TeamManager`, `MatchManager`):**

   * Allow configuring **Player Count (`2`, `3`, or `4`)** and **Team / Alliance Presets** (`1v1`, `FFA`, `2v2`, `1v2`, `1v3`, or `Custom`) directly inside the Skirmish Match Setup panel on `MainMenu`.

   * Expose compact per-slot controls for active slots `1..N`: Controller (`Human` / `AI`), Alliance (`Team A`, `Team B`, `Team C`, `Team D`), and AI Difficulty / Playstyle (respecting `Spectator Mode` when all slots are `AI`).

   * Enforce map slot capacity cleanly (`skirmish_arena_01` and `skirmish_arena_02` support `2` players; `skirmish_arena_03` supports `2`, `3`, or `4` players).

   * Ensure `MatchManager`, `SkirmishAICommander` spawning, `FogOfWar` (shared vision with allied teams), and `MatchEndOverlay` (Summary Table & Timeline Graphs) all scale cleanly to 2, 3, or 4 active teams.

2. **Skirmish Map #3 — *Quad Nexus* (`scenes/maps/skirmish_arena_03.tscn`):**

   * A 4-corner arena designed for `1v1`, `1v1v1 FFA`, `1v1v1v1 FFA`, `2v2`, and `AI vs AI` battles.

   * Features 4 symmetric corner base basins (each with starter `Biomass`, `Silica`, and `ComputeVent`), a contested central **Data Hyper-Uplink** plaza with 4 sightline pylons, 4 side expansion pockets, and **`DestructibleBarricade`** backdoor lanes between neighboring corners.

   * Dynamically activates only the spawn corners needed for the configured `player_count` (cleaning up unused corner starting `Nexus Vat`s / starter workers while keeping their resource nodes available as neutral expansions).

3. **Persistent Battle Scars & Ground Decals (`ui/overlays/battle_scars_overlay.gd`):**

   * A single pooled `Node2D` overlay (zero per-decal scene node overhead) rendering crisp, slowly fading Technozen ground scars beneath units and buildings:

     * **Mortar & Explosion Scorch Rings:** Darkened thermal scorch + faint ember ring when `Chrysalis Mortar` shells, `Seismic Slam`, `DestructibleBarricade`s, or buildings detonate.

     * **Heavy Wreckage / Bio-Oil Splatters:** Subtle geometric oil/ichor residue where heavy units (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`) or `SalvageCore`s fall.

     * **Structure Circuit-Pulse Pads:** Subtle translucent Technozen grounding grid/circuit halo drawn beneath completed buildings (fading away if salvaged or destroyed).

4. **Tactical Event Feed (`ui/hud/tactical_event_feed.tscn` & `.gd`):**

   * A clean, auto-fading **3-to-4 line** corner telemetry log displaying high-signal match events (*"Enemy Goliath Frame destroyed"*, *"Adrenal Potency complete"*, *"Hyper-Uplink contested"*, *"Barricade breached"*, *"Team 2 eliminated"*).

   * Each entry fades out after `6.5s`, carries a color-coded category pip, and **clicking an entry with a world coordinate snaps `RTSCamera` straight to that location** (complementing `Space` / `Last Alert Jump`).

5. **Zoom-to-Cursor & Smooth Minimap Dragging (`scripts/camera/rts_camera.gd`, `ui/hud/minimap.gd`):**

   * **Zoom-to-Cursor:** Mouse-wheel zooming anchors to the world point beneath the cursor instead of screen center (with a `Zoom to Cursor` toggle in **Settings → Camera**, enabled by default).

   * **Smooth Minimap Dragging:** Holding Left-Click on `TacticalMinimap` (outside Attack-Move/Patrol/Ability targeting) continuously drags and pans the camera viewport box in real time, releasing cleanly even if the cursor exits the minimap rect.

### Out of Scope

* Playable unit/building rosters for Factions `#2–#5`.

* Online networking / multiplayer sync (all non-local slots remain `SkirmishAICommander` instances).

* Stealth/cloaking or Defensive Stance mechanics.

## 2. Phase A: Main Menu Player Count & Team Configuration

### A.1 `GameConfig` & `TeamManager` Slot Pipeline (`scripts/systems/game_config.gd`, `scripts/systems/team_manager.gd`)

* **Map Metadata Registry (`GameConfig`):**

  * Store a clean `MAP_CATALOG` entry for each skirmish map:

    * `skirmish_arena_01` (*Vat Basin*): `max_players = 2`

    * `skirmish_arena_02` (*Twin Causeway*): `max_players = 2`

    * `skirmish_arena_03` (*Quad Nexus*): `max_players = 4`

* **Slot Configuration State (`GameConfig`):**

  * Add `var player_count: int = 2` (`2..4`) and `var team_preset: StringName = &"1v1"` (`&"1v1"`, `&"ffa"`, `&"2v2"`, `&"1v2"`, `&"1v3"`, `&"custom"`).

  * Maintain `var slot_configs: Array[Dictionary]` (length 4), each with:

    * `team_id: int` (`0..3`)

    * `alliance_id: int` (`0..3` — displayed as `Team A`, `Team B`, `Team C`, `Team D`)

    * `controller_type: int` (`HUMAN` or `AI`)

    * `faction_id: StringName` (`&"genesis_v2"`)

    * `ai_difficulty: int` (`RELAXED`, `STANDARD`, `BRUTAL`)

    * `ai_playstyle: int` (`BALANCED`, `SWARM_RUSH`, `SYNTHETICS_TECH`)

  * Enforce invariant: at most **one** `HUMAN` slot (local player); setting all active slots to `AI` automatically engages **Spectator Mode** (keeping the existing `Player vs AI` / `AI vs AI (Spectator)` quick toggle synced with Slot 1's controller).

  * Ensure **Play Again** preserves `player_count`, `team_preset`, and `slot_configs`.

### A.2 Main Menu Lobby UI (`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`)

* Inside the Skirmish Match Setup panel (tightly styled to avoid any overflow at `1280×720` or Fullscreen):

  * **Player Count Selector (`2P`, `3P`, `4P`):** Automatically clamps to `2P` (and disables `3P`/`4P` with a subtle tooltip) when a 2-player map is selected; unlocks `2P / 3P / 4P` when **Quad Nexus (`skirmish_arena_03`)** is selected.

  * **Team Preset Dropdown:** Dynamically populates valid presets for the selected `player_count` (`2P`: `1v1`; `3P`: `3-Way FFA`, `1v2`, `Custom`; `4P`: `4-Way FFA`, `2v2`, `1v3`, `Custom`).

  * **Compact Slot Roster (`VBoxContainer` of 2–4 rows):**

    * Each active slot displays its team color pip (`Cyan`, `Crimson`, `Violet`, `Gold`), slot label (`P1`..`P4`), Controller badge (`Human` / `AI`), Alliance dropdown (`Team A`..`Team D`), and compact AI Difficulty / Playstyle selectors (hidden for the `Human` row).

    * Validate before launch that at least **2 distinct `alliance_id`s** exist among active slots (disabling **Launch Skirmish** with a clear hint like `"Assign at least 2 opposing teams"` if everyone is on `Team A`).

### A.3 Multi-Team Runtime, Allied Vision & Scoreboard (`match_manager.gd`, `fog_of_war.gd`, `skirmish_ai.gd`, `match_end_overlay.gd`)

* **Dynamic Spawning & AI Instantiation (`MatchManager` / Map Bootstrap):**

  * Read `TeamManager.get_active_teams()` on match start. For any corner spawn point on `skirmish_arena_03` whose `team_id` is **not** active (e.g., a 2P or 3P game on Quad Nexus), cleanly remove its starting `Nexus Vat` and starter workers so only active teams spawn.

  * For every active slot with `controller_type == AI`, spawn/configure a `SkirmishAICommander` assigned to that slot's `team_id`, `ai_difficulty`, and `ai_playstyle`.

* **Allied Fog of War (`fog_of_war.gd`):**

  * When stamping friendly vision for the local human player, include all entities where `TeamManager.are_allies(local_team, entity.team)` so your `2v2` AI teammate shares vision with you cleanly.

* **Multi-Team `MatchEndOverlay` (`match_end_overlay.gd`):**

  * Render all active teams (`2`, `3`, or `4` columns in the Summary Table and `2–4` color-coded polylines in `TimelineGraph`) with each team's alliance tag (e.g., `P1 [A]`, `AI-2 [A]`, `AI-3 [B]`, `AI-4 [B]`).

  * Announce **Victory** when the local player's `alliance_id` is the last surviving alliance (or captures the **Data Hyper-Uplink**), and emit a tactical event whenever an individual team is eliminated in a 3P/4P match.

## 3. Phase B: Skirmish Map #3 — *Quad Nexus* (`scenes/maps/skirmish_arena_03.tscn`)

* **Arena Dimensions & Layout:** Expanded symmetric square arena (e.g., `~3200×3200` or scaled cleanly to match `skirmish_arena_01`/`02` proportions and camera bounds) with generous navigation clearances (`>= 120px`):

  * **4 Corner Spawn Basins:**

    * **Slot 0 (Bottom-Left):** *Alpha Quadrant*

    * **Slot 1 (Top-Right):** *Omega Quadrant* (ensuring a `2P` game on Quad Nexus spawns diagonally opposite)

    * **Slot 2 (Top-Left):** *Sigma Quadrant*

    * **Slot 3 (Bottom-Right):** *Delta Quadrant*

    * Each basin has a starting `Nexus Vat`, starter `BiomassNode` cluster, `SilicaVein`, and a `ComputeVent`.

  * **Central *Hyper-Uplink Core* `(0, 0)`:** Open octagonal plaza framed by 4 angled Technozen `MapLandmark` pylons creating crisp 4-way sightlines and LOS shadows.

  * **4 Barricaded Perimeter Corridors & Side Pockets:** Place **`DestructibleBarricade`** gates along the outer North/South/East/West lanes separating neighboring corners, guarding rich mid-map **Silica / Compute** expansion pockets. Early game funnels skirmishes toward the center; breaching a barricade opens direct cross-corner raids.

* **Scene Wiring:** Include `ArenaNavRegion`, `FogOfWar`, `RTSCamera`, `BattleScarsOverlay`, `TacticalEventFeed`, and all standard HUD overlays so `skirmish_arena_03.tscn` works identically in `Player vs AI`, `2v2`, `FFA`, and `AI vs AI (Spectator)` modes.

## 4. Phase C: Persistent Battle Scars & Ground Decals

### C.1 Pooled `BattleScarsOverlay` (`ui/overlays/battle_scars_overlay.gd`)

* **Single-Node Pooled Renderer:**

  * Place `BattleScarsOverlay` (`Node2D`, `z_index` set above arena floor/grid and below units, buildings, and VFX) inside `skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, `skirmish_arena_03.tscn`, and `milestone_0_test.tscn` (added to group `"battle_scars"`).

  * Maintain a ring buffer of lightweight decal dictionaries (`max_decals = 110`; oldest entry fades/recycles smoothly when full) and redraw only when decals exist and are actively fading (`~10 Hz` redraw throttle for fading decals so idle CPU cost is near zero).

* **Decal Archetypes:**

  * **`&"scorch_small"` / `&"scorch_large"`:** Triggered by `Chrysalis Mortar` splash, `Seismic Slam`, `DestructibleBarricade` breach, and building destruction. Draws a layered dark thermal crater + subtle jagged carbon rings (`lifetime = 35.0s`, smooth alpha fade over final `10.0s`).

  * **`&"wreck_splatter"`:** Triggered when heavy units (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`) or `SalvageCore`s die/expire. Draws subtle metallic/bio-oil residue + tiny geometric debris flecks (`lifetime = 40.0s`).

  * **`&"building_pad"`:** Drawn subtly beneath every constructed `Building` (via `building.gd` or `entity_visuals.gd` / `BattleScarsOverlay`) as a low-contrast Technozen grounding frame with soft pulsing corner circuit nodes—automatically leaving a brief scorch scar if the building is destroyed.

* **Performance Option (`SettingsManager`):**

  * Add `battle_scars_enabled: bool = true` under `[gameplay]` in `SettingsManager` (and a toggle in **Settings → Gameplay**) so players on lower-spec machines can disable ground scars cleanly.

## 5. Phase D: Tactical Event Feed (`ui/hud/tactical_event_feed.tscn` & `.gd`)

* **Visual Design & Placement (`1280×720` Safe):**

  * Anchor cleanly on the **bottom-right** (or just above `TacticalMinimap` on the left—**bottom-right** with `offset_right = -14`, `offset_bottom = -16`, max width `290px` is completely clear of `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, and `SelectionHUD`).

  * Uses `mouse_filter = MOUSE_FILTER_IGNORE` on the outer container so empty space never blocks map clicks or drag-boxes; only active visible event pills accept clicks.

* **Behavior & Event Sources:**

  * Displays up to **4** stacked translucent Technozen telemetry pills (newest at bottom or top consistently), each auto-fading out smoothly after `6.5s`.

  * Subscribe to `MatchManager` signals and emit concise, high-signal entries (with throttling so 10 dying Clone Troopers never flood the log):

    * **Combat / Heavy Kills (Crimson/Amber):** Heavy unit (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`) or major structure destroyed, or `DestructibleBarricade` breached.

    * **Objective / Elimination (Gold):** `Data Hyper-Uplink` contested/captured, or a team eliminated in 3P/4P matches.

    * **Economy / Tech (Cyan/Emerald):** Upgrade research completed, `SalvageCore` extracted, or Tier-2 structure finished.

  * **Click-to-Jump:** Left-clicking any event pill with a valid `world_pos` snaps `RTSCamera` straight to that location (and flashes a brief subtle ring on `Minimap`).

  * Gate visibility on `SettingsManager.show_alert_toasts` (or keep always readable as compact telemetry while respecting alert settings).

## 6. Phase E: Zoom-to-Cursor & Smooth Minimap Dragging

### E.1 Zoom-to-Cursor (`scripts/camera/rts_camera.gd`, `scripts/systems/settings_manager.gd`, `scripts/ui/settings_menu.gd`)

* Add `zoom_to_cursor: bool = true` to `SettingsManager` (`[camera]` section in `user://settings.cfg`) and a **"Zoom to Cursor"** checkbox in **Settings → Camera**.

* In `RTSCamera` wheel-zoom handling:

  * When `SettingsManager.zoom_to_cursor` is `true` and the mouse is over the playable viewport (not over HUD controls that consume wheel events):

    * Sample `var world_before := get_global_mouse_position()` before applying the new target zoom.

    * Apply the new zoom step (maintaining smooth interpolation cleanly without jitter—either applying the anchored offset proportionally each zoom lerp tick or computing the exact target camera position shift `world_before - world_after_at_target_zoom`).

    * Clamp the resulting camera position smoothly within `arena_bounds`.

  * Respect `SettingsManager.invert_zoom` seamlessly.

### E.2 Smooth Minimap Dragging (`ui/hud/minimap.gd`)

* Track `var _is_dragging_camera: bool = false` in `TacticalMinimap`.

* On Left-Click press inside the minimap:

  * If an Attack-Move, Patrol, or Ability targeting command is active, execute the existing minimap order behavior and do **not** start camera dragging.

  * Otherwise, set `_is_dragging_camera = true`, immediately pan `RTSCamera` to the clicked world position, and consume the event.

* On `InputEventMouseMotion` while `_is_dragging_camera == true`:

  * Continuously convert the clamped local mouse coordinate inside the minimap rect to world space and update `RTSCamera` position smoothly in real time.

* On Left-Click release (handled via `_input` or `_gui_input` so releasing outside the minimap bounds never leaves dragging stuck):

  * Set `_is_dragging_camera = false`.

## 7. File & Architecture Summary

### New Files to Create

* `scenes/maps/skirmish_arena_03.tscn` (**Quad Nexus** — 4-spawn FFA / 2v2 / 1v1 arena with central Hyper-Uplink and 4 barricaded outer corridors)

* `ui/overlays/battle_scars_overlay.gd` (Pooled procedural ground decals for scorch craters, wreckage splatters, and building pads)

* `ui/hud/tactical_event_feed.tscn` & `ui/hud/tactical_event_feed.gd` (Auto-fading, click-to-jump 3–4 line corner telemetry feed)

### Existing Files to Extend

* `scripts/systems/game_config.gd`, `scripts/systems/team_manager.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/systems/fog_of_war.gd` (Map max-player catalog, 2–4 player slot/alliance config, dynamic corner spawn cleanup, multi-AI spawning, allied vision sharing, and team elimination events)

* `scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd` (Player Count `2P/3P/4P`, Team Presets `1v1/FFA/2v2/1v2/1v3/Custom`, per-slot Controller/Alliance/AI controls, and launch validation)

* `ui/hud/match_end_overlay.gd` (Support 2, 3, or 4 active teams in Summary Table & Timeline Graphs)

* `scripts/camera/rts_camera.gd`, `ui/hud/minimap.gd`, `scripts/systems/settings_manager.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd` (Zoom-to-Cursor + setting, Battle Scars setting, and smooth LMB minimap dragging)

* `ui/overlays/combat_vfx.gd`, `scripts/units/unit.gd`, `scripts/buildings/building.gd`, `scripts/world/destructible_barricade.gd`, `scenes/maps/skirmish_arena_01.tscn`, `scenes/maps/skirmish_arena_02.tscn` (Emit battle scars & tactical event feed entries; instance `BattleScarsOverlay` and `TacticalEventFeed` in all skirmish maps)

## 8. Verification Checklist for `agy`

Before concluding Milestone 2.5, verify in Godot (Windowed `1280×720` and Fullscreen `F11`):

* \[ \] **Main Menu Player Count & Team Setup:** Select **Vat Basin (`skirmish_arena_01`)** and confirm Player Count clamps to `2P`; switch to **Quad Nexus (`skirmish_arena_03`)** and test `2P (1v1)`, `3P (FFA)`, `4P (FFA)`, and `4P (2v2)` presets plus custom alliance dropdowns. Verify `MainMenu` has zero edge clipping at `1280×720` and blocks launch if fewer than 2 opposing teams are configured.

* \[ \] **4-Spawn Arena (`skirmish_arena_03.tscn`) & Allied Play:** Launch a **`2v2`** match (`Player + AI [Team A]` vs `2 AI [Team B]`) and a **`4-Way FFA (Spectator)`** at `2x` speed; verify allied vision shares properly in `2v2`, unused corners cleanly clear in `2P`/`3P` matches, barricades open flanks when destroyed, and `MatchEndOverlay` displays all 4 teams cleanly in both Summary Table and Timeline Graphs.

* \[ \] **Persistent Battle Scars:** Fire **Chrysalis Mortars**, trigger **Seismic Slam**, destroy a **Goliath Frame** and a **DestructibleBarricade**, and complete a **Cloning Vat**; verify scorch rings, wreckage splatters, and subtle structure circuit pads appear beneath units, fade smoothly over time, respect the **Settings → Gameplay → Battle Scars** toggle, and maintain smooth FPS.

* \[ \] **Tactical Event Feed:** Destroy a heavy unit, complete an upgrade, contest the **Hyper-Uplink**, or extract a **SalvageCore**; verify crisp color-coded telemetry pills appear in the bottom-right, auto-fade after `~6.5s`, never block map clicks on empty space, and clicking a pill snaps the camera straight to the event location.

* \[ \] **Zoom-to-Cursor & Smooth Minimap Dragging:** Scroll the mouse wheel over a corner unit and confirm the camera zooms directly onto the cursor (and respects **Settings → Camera → Zoom to Cursor** + **Invert Zoom**); hold Left-Click and drag across `TacticalMinimap` to confirm smooth real-time panning with clean release outside the minimap rect and zero interference with minimap Attack-Move.