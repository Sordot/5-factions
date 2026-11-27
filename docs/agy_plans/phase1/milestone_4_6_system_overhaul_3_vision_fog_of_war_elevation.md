# Milestone 4.6 — System Overhaul #3: Next-Gen Vision, Fog of War & Elevation

**Prerequisite:** Milestone 4.5 (System Overhaul #2: Combat Simulation & Abilities) verified and working cleanly.

**Goal:** Overhaul battlefield vision, Fog of War rendering, scouted intel persistence, Sensor Relays, and High-Ground Plateau readability into a crisp, zero-leak, *StarCraft II*-grade vision system:

1. **32 px Dual-Texture Fog Grid + GPU-Smoothed Shroud Shader (`FogOfWarSystem`, `FogOverlay`, `assets/shaders/fog_of_war.gdshader`):** Upgrade from the coarse `64 px` grid to a `32 px` grid (`4×` spatial precision), replace pixel-by-pixel `set_pixel()` loops with fast bulk `PackedByteArray` uploads, interpolate visibility smoothly at 60 FPS, and render soft-feathered GPU fog with a subtle Technozen architectural grid strictly inside `UNEXPLORED` shroud (keeping `EXPLORED` and `VISIBLE` ultra-clean).

2. **Authentic *StarCraft II* Frozen Building Ghosts (`FogOfWarSystem`, `FogGhostOverlay`, `EntityVisuals`, `FactionVisualRenderer`, `SelectionController`, `TacticalMinimap`):** Stop leaking live enemy building state inside `EXPLORED` fog. Capture frozen snapshots of scouted hostile buildings (including exact construction blueprint progress and frozen turret orientation), hide the real building node when vision drops, render dimmed/desaturated authentic faction silhouettes beneath the fog veil and on the minimap, persist ghosts even if destroyed/salvaged unseen until re-scouted, and make frozen ghosts **left-clickable for last-known intel inspection**.

3. **Cached Elevation, Exact Ramp Crests, Dynamic Vision Cap & Instant Barricade LOS (`FogOfWarSystem`, `DestructibleBarricade`):** Eliminate per-call scene-tree plateau scans via world-AABB caching, remove `64 px` sub-quadrant shroud overhang onto low-ground ramp approaches while preserving strict sub-cell ramp-crest spotter precision, dynamically track `_max_vision_radius`, and trigger immediate visibility refreshes when barricades are breached.

4. **Fog-Safe `SensorRelay` & Inspection Crash Fix (`SensorRelay`, `TacticalMinimap`):** Fix the runtime crash in `SensorRelay.get_inspection_data()` (`get_team_name` → `get_team_display_name`), cache last-known relay state so enemy relay captures never leak through fog, and skip idle redraws when hidden.

5. **360° High-Ground Cliff Readability (`HighGroundPlateau`, `EntityVisuals`):** Strengthen north-facing impassable cliff edges with dark upper drop-lips, recessed inner bevels, and directional trim ticks so every cliff orientation reads instantly as impassable, and add a subtle elevation drop-shadow grounding cue on Elevation 1 units.

**Hard Design Guardrails (MUST PRESERVE):**

* **Strict SC2 High-Ground Rules:** Low-ground units (`Elevation 0`) never see uphill onto `Elevation 1` plateaus without an elevated allied spotter or unobstructed `SensorRelay`, and low-ground units cannot target or shoot uphill through fog.

* **Zero Stealth / Zero Skill-Cap Automation:** No cloaking, no auto-formations, no overkill-prevention targeting automation, no auto-production.

* **Zero Balance Stat Changes:** Do **not** alter unit/building vision ranges, HP, damage, speeds, or costs.

* **100% Procedural Pipeline & Strict `1280×720` UI Discipline:** All fog shaders, ghost desaturation shaders, plateau bevels, and ghost inspection readouts remain 100% procedural and unclipped in Windowed `1280×720` and Fullscreen (`F11`).

## Phase A — 32 px Fog Grid, Bulk Uploads & Cached Elevation (`scripts/systems/fog_of_war.gd`)

### A.1 Higher-Resolution Grid, Fast Buffer Uploads & Smooth Temporal Blending

1. **Default `32 px` Cell Precision:**

   * Change `@export var cell_size: float = 32.0` (note: check all map `.tscn` files `skirmish_arena_01..04.tscn`, `skirmish_arena_procedural.tscn`, and `milestone_0_test.tscn` to ensure no stale `cell_size = 64.0` scene override blocks the new `32.0` default!).

   * Add `signal building_ghosts_changed`.

2. **Dual-Texture Architecture (60 FPS World Shader + Crisp Minimap Texture):**

   * Keep `var fog_texture: ImageTexture` (`Image.FORMAT_RGBA8`) for `TacticalMinimap` backward compatibility, updated via a reusable `var _minimap_bytes: PackedByteArray` (`total * 4` bytes) and `fog_image.set_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, _minimap_bytes)` + `fog_texture.update(fog_image)` (replacing slow cell-by-cell `set_pixel()` calls!).

   * Add `var world_fog_image: Image` and `var world_fog_texture: ImageTexture` (`Image.FORMAT_RG8`, `total * 2` bytes via `var _world_fog_bytes: PackedByteArray`):

     * **Channel R (`0..255`):** Smoothly interpolated visibility (`0` = `UNEXPLORED`, `128` = `EXPLORED`, `255` = `VISIBLE`).

     * **Channel G (`0..255`):** Smoothly interpolated explored mask (`0` = `UNEXPLORED`, `255` = `EXPLORED` or `VISIBLE`), allowing the GPU shader to cleanly isolate the subtle Technozen scan-grid strictly to `UNEXPLORED` shroud!

   * Maintain `var _display_vis: PackedFloat32Array` and `var _display_exp: PackedFloat32Array` interpolated smoothly in `_process(delta)` toward `_grid`:

     * Fast reveal speed (`11.0 / sec`) when cells become `VISIBLE` or `EXPLORED`; smooth decay speed (`5.5 / sec`) when `VISIBLE` cells fade back to `EXPLORED`.

     * Track `_world_fog_dirty: bool` and only upload `world_fog_texture.update(world_fog_image)` while at least one cell is actively transitioning (zero idle GPU uploads when the army is stationary!).

   * In `set_post_match_reveal(true)` or `not fog_enabled`: snap `_display_vis` and `_display_exp` immediately to `1.0` so post-match reveal is instantaneous.

### A.2 O(1) Cached Plateau Elevation, Exact Ramp Crests & Dynamic Vision Radius

1. **Cached Plateau World AABBs:**

   * Add `var _cached_plateaus: Array[Dictionary] = []` (`{"node": Node, "aabb": Rect2}`).

   * Populate `_cached_plateaus` inside `rebuild_blocker_grid()` by scanning `"high_ground_plateaus"` once and computing each plateau's world-space `Rect2` bounding box from `get_world_polygon()` (expanded by `4.0 px`).

   * Rewrite `get_elevation_at(world_pos: Vector2) -> int`:

     * Iterate `_cached_plateaus` (zero `get_tree().get_nodes_in_group()` calls!).

     * Reject immediately if `not (entry["aabb"] as Rect2).has_point(world_pos)` before calling `_sample_plateau_elev(entry["node"], world_pos)`.

2. **Eliminate Ramp-Approach Shroud Overhang:**

   * In `rebuild_blocker_grid()`: at `32 px` cell resolution, sample **only the cell center `pt`** for `_elevation_grid[idx]` (removing the 4-subquadrant expansion that previously bled dark shroud `16–32 px` down onto low-ground ramp approaches).

   * Keep `_viewer_elevated_sources` and `is_world_pos_visible_strict()` intact so combat targeting and entity reveals still enforce sub-cell ramp-crest precision right at the exact plateau polygon lip!

3. **Dynamic `_max_vision_radius` & Immediate Barricade Refresh:**

   * Track `var _max_vision_radius: float = 560.0` updated during `refresh_visibility()` to `clampf(max_seen_vr + 48.0, 560.0, 1200.0)` and use `_max_vision_radius` inside `is_world_pos_visible_to_team()` instead of hardcoded `560.0`.

   * Add `func mark_blockers_dirty() -> void` and have `rebuild_blocker_grid()` call `refresh_visibility()` immediately when `_has_initial_refresh == true` so breaching a `DestructibleBarricade` opens LOS on the exact same frame.

## Phase B — GPU-Smoothed Fog Shader & `FogOverlay` (`assets/shaders/fog_of_war.gdshader`, `ui/overlays/fog_overlay.gd`)

### B.1 Procedural Fog Shader (`assets/shaders/fog_of_war.gdshader`)

Create `assets/shaders/fog_of_war.gdshader` (`shader_type canvas_item;`):

* **Uniforms:**

  * `uniform vec2 grid_size = vec2(82.0, 60.0);`

  * `uniform vec2 arena_size = vec2(2600.0, 1900.0);`

  * `uniform vec4 color_unexplored : source_color = vec4(0.020, 0.032, 0.052, 0.93);`

  * `uniform vec4 color_explored : source_color = vec4(0.025, 0.045, 0.075, 0.50);`

  * `uniform vec4 grid_line_color : source_color = vec4(0.14, 0.42, 0.52, 0.14);`

* **Fragment Pipeline:**

  1. **9-Tap Tent/Gaussian Smooth Filter:** Sample `TEXTURE` at `UV` (weight `0.28`), 4 cardinal neighbors `±texel` (weight `0.12` each), and 4 diagonal neighbors `±texel` (weight `0.06` each) where `texel = 1.0 / max(grid_size, vec2(1.0))` — completely eliminating blocky grid edges and diagonal staircases!

  2. **Clean 3-State Smooth Color Ramp:**

     * `float vis_val = smoothed.r;` (`0.0` Unexplored → `0.5` Explored → `1.0` Visible)

     * Blend `color_unexplored → color_explored` across `smoothstep(0.08, 0.46, vis_val)`.

     * Blend `→ vec4(0.0)` across `smoothstep(0.54, 0.92, vis_val)`.

     * Result: `VISIBLE` is 100% transparent, `EXPLORED` is ultra-clean darkened tint with zero pattern noise, and edges are silky smooth.

  3. **Subtle Technozen Scan-Grid Strictly in `UNEXPLORED` Shroud:**

     * Compute `float unexplored_mask = 1.0 - smoothstep(0.05, 0.36, smoothed.g);`

     * Compute world-scaled coordinates `vec2 wpos = UV * arena_size;`

     * Draw hairline `96 px` major grid lines + faint micro-crosshair dots at intersections, multiplied strictly by `unexplored_mask * grid_line_color.a`, giving unexplored territory refined Y2K Technozen atmosphere while keeping combat and explored areas razor-clean.

### B.2 Upgrade `FogOverlay` (`ui/overlays/fog_overlay.gd`)

* Preload `assets/shaders/fog_of_war.gdshader` and assign a `ShaderMaterial` onto `FogOverlay`.

* Bind `grid_size = Vector2(_fog_system.grid_width, _fog_system.grid_height)` and `arena_size = _fog_system.arena_bounds.size` whenever `_fog_system` initializes or `arena_bounds` changes.

* Draw `_fog_system.world_fog_texture` across `_fog_system.arena_bounds` (falling back gracefully to `_fog_system.fog_texture` if shader fails to compile).

* Connect cleanly so `_draw()` updates when `world_fog_texture` transitions without unnecessary work when `not _fog_system.fog_enabled`.

## Phase C — Authentic *StarCraft II* Frozen Building Ghosts (Battlefield, Minimap & Left-Click Inspection)

### C.1 Frozen Snapshot Registry in `FogOfWarSystem` (`scripts/systems/fog_of_war.gd`)

Replace the leaking `_spotted_buildings` visibility hack with true SC2 frozen snapshots:

* Add `var _building_ghosts: Dictionary = {}` (`building_id: int -> Dictionary`).

* **Snapshot Schema (captured ONLY while a hostile building is in live `is_world_pos_visible_strict()` vision):**

  ```
  {
      "id": b_id,
      "building_type_id": b.building_type_id,
      "display_name": b.display_name,
      "team": int(b.team),
      "pos": b.global_position,
      "footprint_radius": b.footprint_radius,
      "selection_radius": b.selection_radius,
      "is_command_hub": b.is_command_hub(),
      "is_constructed": b.is_constructed,
      "construction_progress": b.construction_progress,
      "max_hp": b.max_hp,
      "current_hp": b.current_hp,
      "max_shield": b.max_shield,
      "current_shield": b.current_shield,
      "has_turret": b.has_turret,
      "turret_angle": b.get_turret_angle(),
      "turret_tracer_style": b.turret_tracer_style,
      "max_staff_slots": b.max_staff_slots,
      "staffed_count": b.get_assigned_engineer_count(),
      "is_powered": b.is_powered,
      "is_active_ghost": false,
      "scouted_time_str": mm.get_match_elapsed_formatted() if mm != null else "00:00",
      "inspection_snapshot": b.get_inspection_data().duplicate(true),
  }
  
  ```

* **Exact SC2 Update Rules inside `_apply_enemy_visibility(force_reveal_all: bool)`:**

  1. **If `force_reveal_all` (spectator, post-match reveal, or Fog OFF):**

     * Show all living hostile buildings (`b.visible = true`).

     * Set `is_active_ghost = false` on all ghosts (do not render ghosts over live buildings).

  2. **Otherwise (active Fog of War):**

     * Track `seen_live_ids: Dictionary = {}` while iterating living hostile buildings:

       * If `is_world_pos_visible_strict(b.global_position)`:

         * `b.visible = true`, `b.has_been_spotted = true`, `seen_live_ids[b_id] = true`.

         * Create/refresh `_building_ghosts[b_id]` with the building's current live state and `is_active_ghost = false`.

       * Else (building is in `EXPLORED` or `UNEXPLORED` fog):

         * **Hide the real building node (`b.visible = false`)!** *(Permanently stops leaking live construction bars, turret rotation, production glow, or instant salvage disappearance!)*

         * If `_building_ghosts.has(b_id)` and `is_world_pos_explored(b.global_position)`: mark `_building_ghosts[b_id]["is_active_ghost"] = true`.

     * **Re-Scout Verification Pass over `_building_ghosts.keys()`:**

       * For every `gid` in `_building_ghosts` that is **not** in `seen_live_ids`:

         * Let `g = _building_ghosts[gid]` and `g_pos = g["pos"] as Vector2`.

         * If `is_world_pos_visible_strict(g_pos)`:

           * The player has re-scouted this tile and the building is no longer there (destroyed/salvaged while in fog) → **erase `_building_ghosts[gid]`**!

         * Else if `is_world_pos_explored(g_pos)`:

           * Keep the frozen ghost active (`g["is_active_ghost"] = true`)!

  3. Emit `building_ghosts_changed` whenever any ghost is added, activated, deactivated, or cleared.

* **Public Query API on `FogOfWarSystem`:**

  * `func get_active_building_ghosts() -> Array[Dictionary]`

  * `func get_building_ghost_by_id(ghost_id: int) -> Dictionary`

  * `func find_building_ghost_at_point(world_point: Vector2) -> Dictionary` *(checks active ghosts within `selection_radius`)*

  * Clear `_building_ghosts` cleanly in `reset_fog()`.

### C.2 Reuse Pluggable Faction Renderers for Zero-Duplication Ghost Drawing

1. **Make `FactionVisualRenderer` Ghost-Safe (`ui/overlays/renderers/faction_visual_renderer.gd` + `genesis_visual_renderer.gd`, `monolith_visual_renderer.gd`, `prisma_visual_renderer.gd`):**

   * Update `draw_building(...)` and `draw_building_turret(...)` in the 3 renderers so if `building == null`, they safely read frozen fallback values from `ctx` (`float(ctx.get("footprint_radius", 36.0))`, `bool(ctx.get("is_active_prod", false))`, `bool(ctx.get("is_training", false))`, `int(ctx.get("staffed_count", 0))`, `int(ctx.get("max_staff_slots", 0))`, `bool(ctx.get("is_powered", true))`, `float(ctx.get("turret_angle", 0.0))`, `ctx.get("turret_tracer_style", &"pulse")`).

   * Add `static func draw_frozen_building_ghost(canvas: CanvasItem, ghost: Dictionary) -> void` on **`EntityVisuals`** (`ui/overlays/entity_visuals.gd`):

     * Resolves the faction renderer via `_resolve_renderer(type_id, true)`.

     * Builds a static (`anim_time = 0.0`, `pulse = 0.25`, `is_active_prod = false`, `is_training = false`) context dictionary from `ghost`.

     * If `not bool(ghost["is_constructed"])`: renders the static blueprint silhouette at its exact frozen `construction_progress` (without animated scanline motion).

     * Else: invokes `renderer.draw_building(canvas, type_id, null, hull_poly, ctx)` and (if `has_turret`) renders the frozen turret at `ghost["turret_angle"]`!

2. **`FogGhostOverlay` (`ui/overlays/fog_ghost_overlay.gd` + `assets/shaders/ghost_desaturate.gdshader`):**

   * Create a lightweight 10-line canvas shader `assets/shaders/ghost_desaturate.gdshader` that desaturates colors (`mix(vec3(luma), col.rgb, 0.28)`) and dims brightness (`* 0.74`) with `alpha * 0.88` — giving every faction's frozen structures (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`, and future factions) the unmistakable muted *StarCraft II* ghost look automatically!

   * Create `class_name FogGhostOverlay extends Node2D` (`z_index = 6` — above terrain/plateaus, strictly beneath `FogOverlay` at `z_index = 35`, added to group `"fog_ghost_overlay"`):

     * Automatically instantiated by `FogOfWarSystem._post_ready_init()` (added as a sibling/child of the scene root if no `"fog_ghost_overlay"` exists) so every skirmish, procedural, and holdout map gets it automatically with zero `.tscn` edits!

     * Connects to `_fog_system.building_ghosts_changed` and redraws all active ghosts cleanly at their frozen `pos` using `draw_set_transform(ghost_pos)` + `EntityVisuals.draw_frozen_building_ghost(self, ghost)`.

     * Draws a crisp muted selection/hover ring around the currently hovered or inspected ghost (using `selected_ghost_id` / `hovered_ghost_id`).

### C.3 Left-Clickable Frozen Ghost Inspection (`FogGhostInspectHandle`, `SelectionController`, `BoxSelectionResolver`)

1. **Lightweight Inspect Proxy (`FogGhostInspectHandle` inside `ui/overlays/fog_ghost_overlay.gd` or `scripts/world/fog_ghost_handle.gd`):**

   * `class_name FogGhostInspectHandle extends Node2D` (owned as a single reusable child node of `FogGhostOverlay`, in group `"fog_ghost_handles"`):

     * Stores `var ghost_id: int = -1` and `var snapshot: Dictionary = {}`.

     * Implements `set_selected(selected: bool)` and `set_hovered(hovered: bool)` (forwarding highlight state to `FogGhostOverlay.queue_redraw()`).

     * Implements `get_inspection_data() -> Dictionary`:

       * Clones `snapshot["inspection_snapshot"]`, updates:

         * `"subtitle"`: `"LAST KNOWN INTEL — IN FOG"`

         * `"accent_color"`: desaturated slate-red `Color(0.76, 0.48, 0.50, 1.0)`

         * `"is_commandable"`: `false`

         * `"readonly_label"`: `"LAST SCOUTED AT %s  —  RE-SCOUT TO VERIFY" % snapshot["scouted_time_str"]`

       * Appends a telemetry stat row `{"label": "Intel Age", "value": "Scouted %s" % snapshot["scouted_time_str"], "color": Color(0.74, 0.82, 0.90, 0.92)}`.

     * When `FogOfWarSystem` clears or deactivates `ghost_id` (player re-scouts that tile), `FogGhostOverlay` emits `ghost_invalidated(ghost_id)` so `SelectionController` cleanly clears inspection (or smoothly selects the live building if it is still standing!).

2. **Wire into `SelectionController` & `BoxSelectionResolver`:**

   * In `SelectionController._select_at_point()` (right after `clicked_enemy_building` returns `null`, before barricades/relays/resources) and in `BoxSelectionResolver.find_top_hover_entity()`:

     * Query `fog_ghost_overlay.get_ghost_handle_at_point(world_point)`.

     * If a frozen ghost is clicked, call `_set_inspected_entity(ghost_handle)` — bringing up its frozen last-known intel panel in `SelectionHUD` cleanly!

   * In `SelectionController._set_inspected_entity()`: handle `entity.is_in_group("fog_ghost_handles")` cleanly (connect/disconnect `ghost_invalidated`, call `set_selected(true/false)`).

### C.4 Minimap Frozen Ghost Parity (`ui/hud/minimap.gd`)

* In `TacticalMinimap._on_map_viewport_draw()` Step 6 (Buildings):

  * Continue rendering all live friendly buildings and live visible hostile buildings (`b.visible == true`) brightly as before.

  * Immediately after, iterate `_fog_system.get_active_building_ghosts()` and render each frozen ghost at `_world_to_minimap(ghost["pos"])` with the exact same `7×7` (hub) or `4.5×4.5` (standard) footprint, tinted with desaturated team color (`col.lerp(Color(0.50, 0.56, 0.62), 0.52)`, `alpha = 0.58`) — matching the battlefield 1:1 without leaking hidden destructions or live expansions!

## Phase D — Fog-Safe `SensorRelay` & Crash Fix (`scripts/world/sensor_relay.gd`, `ui/hud/minimap.gd`)

1. **Fix Runtime Inspection Crash (`sensor_relay.gd`):**

   * In `get_inspection_data()`: replace `TeamManager.get_team_name(controlling_team)` with **`TeamManager.get_team_display_name(controlling_team)`**.

2. **Zero-Leak Last-Known Relay State (`sensor_relay.gd`):**

   * Add viewer-memory fields:

     * `var _last_known_state: RelayState = RelayState.IDLE`

     * `var _last_known_team: int = -1`

     * `var _last_known_occupants: int = 0`

     * `var _fog_cache: FogOfWarSystem = null`

   * Add `func is_live_visible_to_viewer() -> bool`:

     * Returns `true` if `_is_allied_to_viewer()`, spectator mode, `_fog_cache == null`, `not _fog_cache.fog_enabled`, or `_fog_cache.is_world_pos_visible_strict(global_position)`.

   * Add `func get_viewer_display_state() -> Dictionary`:

     * If `is_live_visible_to_viewer()`: sync `_last_known_state = relay_state`, `_last_known_team = controlling_team`, `_last_known_occupants = _occupant_count`, and return live values (`"is_live": true`).

     * Else: return frozen `_last_known_state`, `_last_known_team`, `_last_known_occupants`, `"is_live": false`!

   * In `_process(delta)`:

     * If not `is_live_visible_to_viewer()` and `_fog_cache != null and _fog_cache.fog_enabled and not _fog_cache.is_world_pos_explored(global_position)`: skip `queue_redraw()` completely!

   * In `_draw()` and `get_inspection_data()`:

     * Render colors, sweep speed, lock-on pulse (only if `is_live`), and inspection telemetry strictly from `get_viewer_display_state()`! When `not is_live`, subtitle/status appends `(LAST KNOWN)` so inspecting a fogged relay never leaks live enemy captures or unit counts.

   * In `TacticalMinimap._on_map_viewport_draw()` Step 4.5 (Sensor Relays): call `relay.get_viewer_display_state()` so minimap relay colors also reflect last-known fog intel cleanly.

## Phase E — 360° High-Ground Cliff Readability (`scripts/world/high_ground_plateau.gd`, `ui/overlays/entity_visuals.gd`)

1. **All-Angle Cliff Rim Treatment (`scripts/world/high_ground_plateau.gd`):**

   * In `_draw()`, after Step 2 (south/side cliff drop extrusions) and during Step 5 (cliff bevel outlines):

   * For north-facing cliff segments (`out_n.y <= -0.25`):

     * Draw a crisp **`5.0 px` dark outer shadow lip** (`Color(0.02, 0.03, 0.05, 0.65)`) offset outward along `out_n` so the top ridge casts an unmistakable wall separation against the lower ground.

     * Draw a **`4.5 px` recessed inner bevel ledge** just inside the plateau rim (`biome_tint.lightened(0.24)`) with crisp perpendicular stone/metal buttress ticks spaced every `26 px` along the cliff edge.

     * Result: North-facing impassable cliffs read with the same immediate clarity as south-facing cliffs, while walkable ramp edges remain visually wide open with their bright crest threshold line and uphill chevrons.

2. **Subtle High-Ground Elevation Grounding Cue (`ui/overlays/entity_visuals.gd`):**

   * Cache `var _fog_cache: FogOfWarSystem = null`, `var _elev_poll_timer: float = 0.0`, and `var _unit_elevation: int = 0` on `EntityVisuals`.

   * For `Mode.UNIT`, refresh `_unit_elevation = _fog_cache.get_elevation_at(_owner_unit.global_position)` every `0.20s` (now an O(1) AABB-cached query!).

   * When `_unit_elevation > 0` and the unit is not already a Colossus Stride unit (`not _owner_unit.data.ignore_friendly_unit_collision`): draw a crisp, grounded soft dark elevation drop-shadow (`draw_circle(Vector2(2.0, 5.0), rad * 0.92, Color(0.02, 0.03, 0.05, 0.34))`) right beneath the unit silhouette so high-ground units visually pop off the terrace in mid-map fights.

## Phase F — Verification & Stress-Test Checklist

1. **Zero Errors & Boot Audit:**

   * Launch Godot (`F5`): confirm **0 parse errors**, **0 shader compile errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.

2. **32 px GPU-Smoothed Fog & Subtle Unexplored Grid:**

   * Move a scout (`Stinger`, `Picket Drone`, `Lumen Skiff`) across open terrain, around a monolith obstacle, and up a `HighGroundPlateau` ramp on `skirmish_arena_01–04` and `Procedural Arena`:

     * Confirm fog edges glide smoothly at 60 FPS with **zero staircase stepping** and **zero `0.14s` snap-popping**.

     * Confirm `UNEXPLORED` shroud displays the subtle low-contrast Technozen architectural grid, while `EXPLORED` and `VISIBLE` areas remain 100% clean.

     * Confirm standing at the foot of a ramp does **not** bleed dark shroud overhang onto the low-ground approach and still strictly hides `Elevation 1` enemies past the crest lip.

3. **Authentic *StarCraft II* Frozen Building Ghosts & Left-Click Inspection:**

   * Scout an enemy base (including a partially constructed building and a turret) across `GENESIS_V2`, `MONOLITH_OS`, and `PRISMA_DEI`, then pull your scout back so the enemy base drops into `EXPLORED` fog:

     * Confirm the live enemy building hides and a **dimmed, desaturated authentic faction silhouette** remains frozen in place (at its exact last-scouted construction % and turret angle) on both the battlefield and `TacticalMinimap`.

     * **Left-click a frozen ghost in `EXPLORED` fog:** confirm `SelectionHUD` displays its frozen last-known intel (`LAST KNOWN INTEL — IN FOG`, last-scouted HP/shield/status, and `LAST SCOUTED AT MM:SS — RE-SCOUT TO VERIFY`), cleanly unclipped at `1280×720`.

     * Have the enemy salvage/destroy or finish constructing that building while still in fog: confirm the ghost stays frozen (zero leak!). Then re-scout the tile: confirm a destroyed building's ghost vanishes cleanly upon re-sighting, and a finished building updates seamlessly to its live completed state!

4. **`SensorRelay` Crash Fix, Fog Safety & Barricade LOS:**

   * Capture a `SensorRelay` and **left-click to inspect it**: confirm zero runtime crash and accurate controller display name.

   * Let an enemy capture a `SensorRelay` inside `EXPLORED` or `UNEXPLORED` fog: confirm neither the battlefield relay nor the minimap leaks the enemy's capture color or lock-on pulse until scouted.

   * Breach a `DestructibleBarricade`: confirm LOS shadow behind the gate clears **immediately** on the breach frame.

5. **360° High-Ground Cliff Readability & 4P Performance Check:**

   * Inspect north-, south-, east-, and west-facing cliff edges on `skirmish_arena_01–04` and `Procedural Arena`: confirm all four cliff orientations read unmistakably as impassable walls while ramp approaches read cleanly open, and high-ground units display a crisp subtle elevation grounding shadow.

   * Run a **4P FFA** (`Quad Nexus`) or **3P FFA** (`Triad Sanctum`) at `2x` speed for 3+ minutes: confirm smooth frame pacing with zero fog-upload stutters.