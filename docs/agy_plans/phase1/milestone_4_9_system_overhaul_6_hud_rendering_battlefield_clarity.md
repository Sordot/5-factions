# Milestone 4.9 — System Overhaul #6: Next-Gen HUD, Rendering & Battlefield Clarity

**Prerequisite:** Milestone 4.8 (System Overhaul #5: Selection, Input & Camera) verified and working cleanly.

**Goal:** Eliminate live HUD/overlay crashes, 60 Hz building redraw storms, and per-hit UI node churn while upgrading battlefield readability for 100+ unit clashes, mirror matchups, 3P/4P spectator games, and rapid macro navigation:

1. **High-Density World Rendering & 100+ Unit Clarity (`EntityVisuals`, `HitFeedbackOverlay`, `VFXPool`, `CombatVFX`):** Stop unconditional 60 Hz redraws on idle/off-screen buildings, add subtle mirror-match / zoom-out team silhouette contrast halos, frustum-cull `HitFeedbackOverlay` pips with adaptive high-density throttling, and add soft micro-VFX budgeting under extreme 100+ unit load (never dropping critical telegraphs or explosions).

2. **Crash-Free, Tactical-Rich `TacticalGlanceOverlay` (`ui/overlays/tactical_glance_overlay.gd`):** Fix the live `Alt`-hold runtime crash (`get_active_harvester_count` → `get_assigned_count`), unify saturation badge colors, drive fade animations with unscaled real-time `dt`, and surface faction macro rings (`PRISMA_DEI` Power Lattice + unpowered pills, `MONOLITH_OS` Capacitor Shield Auras, High-Yield `+35%`, and active `2x` Geothermal Compute Surges).

3. **Zero-Churn `SelectionHUD`, `44×44` Procedural Entity Portrait & Cached `FactionHudTheme` (`SelectionHUD`, `SelectionTelemetryRenderer`, `SelectionEntityPortrait`, `FactionHudTheme`):** Replace per-hit `telemetry_grid` node destruction with pooled rows and `0.10s` dirty coalescing, upgrade `portrait_swatch` into a compact `44×44` procedural vector emblem (with Veterancy chevrons, squad count, and 4.6 frozen-ghost scanlines) strictly inside the existing `740×160` `BottomPanel` footprint, and cache `FactionHudTheme` `StyleBoxFlat` instances.

4. **Multi-Team `ResourceHUD`, Split Feedback Channels, Cached Minimap & Interactive `ProductionTicker` (`ResourceHUD`, `EconomyManager`, `TacticalMinimap`, `ProductionTicker`, `SelectionController`):** Support 2–4 active teams dynamically in the spectator strip, split critical combat/resource alerts from non-critical camera/system toasts on unscaled real-time timers, show live Uplink bonus %, theme speed buttons, cache static minimap terrain geometry + draw saved Camera Bookmark pips (`1–8`), and upgrade the top-left `ProductionTicker` with pooled rows, Left-Click select+center, Shift+Left-Click select-all-of-type, Right-Click focus-camera-only, and `"PAUSED"` unpowered badges.

**Hard Design Guardrails (MUST PRESERVE):**

* **Zero Skill-Cap Automation:** No stealth/cloaking, no auto-formations/role-sorted squads, no overkill-prevention targeting automation, no auto-loop production, standard worker construction only.

* **Zero Balance Stat Changes:** Do **not** alter any unit/building combat or economy stat numbers.

* **100% Procedural Pipeline:** Every entity portrait glyph, contrast halo, minimap terrain cache, and HUD style remains 100% procedural Godot 2D drawing / `StyleBoxFlat` (zero external art assets).

* **Strict `1280×720` UI Discipline:** Keep `SelectionHUD` strictly within its existing `740×160` `BottomPanel` footprint (preserving minimap clearance), and verify `ResourceHUD` (including 4P spectator strip + dual alert/toast lines) and `ProductionTicker` stay 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).

## Phase A — High-Density World Rendering & 100+ Unit Clarity

### A.1 Smart Building Redraw Gating & Mirror-Match Contrast (`ui/overlays/entity_visuals.gd`)

1. **Eliminate 60 Hz Unconditional Building Redraws (`_process`):**

   * Add lightweight fields:

     * `var _idle_redraw_acc: float = 0.0`

     * `var _mirror_check_cache: int = -1` *(lazily refreshed on `teams_reconfigured`: `1` if any opposing active team shares this entity's faction ID, else `0`)*

   * Add helper `func _is_in_camera_view(pad_px: float = 96.0) -> bool`: reads `get_viewport().get_camera_2d()` and checks `global_position` against the camera's world rect expanded by `pad_px` (returning `true` if no camera).

   * In `Mode.BUILDING` inside `_process(delta)`:

     * If `_owner_building` is not visible (`not _owner_building.visible`) or outside `_is_in_camera_view(120.0)`: **skip `queue_redraw()` completely!**

     * Determine if high-frequency animation is needed:

       ```
       var needs_fast_redraw: bool = (
           not _owner_building.is_constructed
           or _owner_building.is_actively_producing()
           or _owner_building.is_overclocked()
           or _owner_building.is_salvaging
           or _owner_building.completion_flash_timer > 0.0
           or _owner_building.is_hovered
           or (_owner_building.requires_power_grid and not _owner_building.is_powered)
           or (_owner_building.current_hp / maxf(1.0, _owner_building.max_hp)) <= 0.40
       )
       
       ```

     * If `needs_fast_redraw`: call `queue_redraw()`.

     * Else (calm idle visible building): throttle gentle ambient core pulse redraws to **`10 Hz`** (`_idle_redraw_acc >= 0.10`), cutting idle building draw overhead by ~85%!

2. **Mirror-Match & Zoom-Out Unit Silhouette Contrast (`_draw`):**

   * In `Mode.UNIT`, right before calling `_cached_renderer.draw_unit(...)`:

     * Check camera zoom (`var cam_zoom: float = cam.zoom.x if cam != null else 1.0`) and mirror-match status (`_is_mirror_matchup()`).

     * When `cam_zoom < 0.78` OR `_is_mirror_matchup()` (and `_owner_unit != null and not _owner_unit.is_dead`):

       * Draw a crisp, grounded subtle team-colored under-rim contrast halo beneath the unit silhouette:

         * Radius `r_halo = (unit.data.collision_radius if unit.data != null else 15.0) + 1.5`

         * Soft dark grounding ring (`Color(0.02, 0.03, 0.05, 0.42)`, `width = 2.6`) + crisp team-color rim (`Color(team_col.r, team_col.g, team_col.b, 0.48 if cam_zoom < 0.78 else 0.38)`, `width = 1.4`).

       * *Result:* `GENESIS_V2` vs. `GENESIS_V2`, `MONOLITH_OS` vs. `MONOLITH_OS`, and `PRISMA_DEI` vs. `PRISMA_DEI` mirror fights read unmistakably at a glance without cluttering silhouettes!

### A.2 Viewport-Culled `HitFeedbackOverlay` & Soft Micro-VFX Budgeting (`hit_feedback_overlay.gd`, `vfx_pool.gd`, `combat_component.gd`)

1. **`ui/overlays/hit_feedback_overlay.gd`:**

   * Cache the active camera world rect (`_cached_view_rect: Rect2`, padded by `+96 px`) once per `_process()` frame (and lazily if empty).

   * In `push_hit_pip(world_pos, kind, value, entity_id)`:

     * Reject immediately if `_cached_view_rect.has_area() and not _cached_view_rect.has_point(world_pos)` so off-screen skirmishes never evict live on-screen shield/armor pips from the 96-slot ring buffer!

     * Scale per-entity throttle dynamically under heavy load: `var eff_throttle: int = 240 if _active_count >= 64 else (185 if _active_count >= 40 else THROTTLE_MS)` so dense 100+ unit battles stay clean and readable.

2. **Soft Micro-VFX Density Budgeting (`scripts/systems/vfx_pool.gd`, `scripts/units/combat_component.gd`, `scripts/buildings/turret_component.gd`):**

   * Add `func is_high_vfx_load() -> bool` on `VFXPool` returning `true` when active checked-out `CombatVFX` + `AttackTracer` count exceeds `96`.

   * When `VFXPool.is_high_vfx_load()` is `true`: skip low-priority micro-flourishes (`setup_muzzle_shock`, `setup_armor_pierce_spark`, `setup_heal_tick`) to protect frame pacing in massive 4P clashes, while **always** spawning critical combat visuals (`MORTAR_SHELL`, `SOLAR_CONVERGENCE`, `SHIELD_SHATTER`, `DEATH_BURST`, `ANCHOR_THUD`, `RANK_UP_PULSE`, and primary `AttackTracer` beams).

## Phase B — Crash-Free, Tactical-Rich `TacticalGlanceOverlay` (`ui/overlays/tactical_glance_overlay.gd`)

1. **Fix Live `Alt`-Hold Runtime Crash & Unify Saturation Colors:**

   * Replace `var cur_h: int = rn.get_active_harvester_count()` (nonexistent method!) with **`var cur_h: int = rn.get_assigned_count(sat_team)`**.

   * Replace the custom saturation color ladder with **`ResourceNode.get_saturation_color(cur_h, max_h)`** (multiplied by `a` alpha) so `Alt`-hold badges match `ResourceNode` hover badges 1:1!

2. **Unscaled Real-Time Fade (`_process`):**

   * Compute `var real_dt: float = minf(delta / maxf(0.1, Engine.time_scale), 0.05)` and drive `_alpha` fade-in/fade-out and `_pulse_time` from `real_dt` so `Alt` responds crisply at `0.5x` and `2.0x` game speeds.

3. **Faction Macro Rings & Flashpoint Callouts on `Alt` Hold (`_draw`):**

   * **Unpowered & Paused Queue Badges (Section 1b):**

     * If `b.requires_power_grid and not b.is_powered`: render a bold warning pill `"UNPOWERED"` (`Color(1.0, 0.36, 0.30, 0.96 * a)`) — or `"PAUSED %d%%"` when `q_size > 0` — instead of an `"IDLE"` tag!

   * **Power Lattice & Capacitor Aura Rings (Section 1e):**

     * If `b.provides_power_grid and b.power_radius > 0.0`: draw a subtle liturgical-gold dashed ring (`Color(0.98, 0.80, 0.14, 0.24 * a)`) showing exact `PRISMA_DEI` lattice coverage across your whole base at a glance.

     * If `b.shield_regen_aura_radius > 0.0`: draw a subtle shield-cyan dashed ring (`Color(0.220, 0.741, 0.973, 0.22 * a)`) showing `MONOLITH_OS` Capacitor Pylon coverage.

   * **High-Yield & Surging Vent Callouts (Section 3):**

     * On explored `is_high_yield` resource nodes inside `view_rect`: append `+35%` to the pill (or draw a subtle gold micro-pill `HIGH YIELD` below the node).

     * On explored `is_vent and rn.is_surging()` nodes inside `view_rect`: draw a bright cyan pill `"2x SURGE %ds" % int(ceil(rn.surge_remaining))` so players spot contested surges immediately when holding `Alt`.

## Phase C — Zero-Churn `SelectionHUD`, `44×44` Procedural Entity Portrait & Cached `FactionHudTheme`

### C.1 Cached `FactionHudTheme` StyleBoxes (`ui/hud/faction_hud_theme.gd`)

* Add `static var _style_cache: Dictionary = {}`.

* Clear `_style_cache.clear()` inside `register_theme_provider(...)` whenever a faction provider is registered/overwritten.

* Cache `StyleBoxFlat` outputs in `make_panel_style(faction_id, compact)` (key `"panel:%s:%d"`) and `make_utility_button_style(faction_id, hovered)` (key `"ubtn:%s:%d"`), eliminating repeated `StyleBoxFlat.new()` allocations during HUD switches.

* Add `static func get_speed_active_color(faction_id: StringName) -> Color` returning the active faction's `accent` color (from `get_palette(faction_id)`).

### C.2 Procedural `44×44` Vector Entity Portrait (`ui/hud/selection_entity_portrait.gd`)

Create `class_name SelectionEntityPortrait extends Control` (`custom_minimum_size = Vector2(44.0, 44.0)`, `size_flags_vertical = Control.SIZE_SHRINK_CENTER`, `mouse_filter = Control.MOUSE_FILTER_IGNORE`):

* **Zero `BottomPanel` Width Bloat:** Mounted inside `SelectionHUD`'s left column in place of `portrait_swatch` (`portrait_swatch.visible = false`, inserted at `portrait_swatch.get_index()`), keeping `BottomPanel` strictly inside its existing `740×160` footprint on `1280×720`!

* **API:**

  * `func apply_faction_theme(faction_id: StringName, accent: Color) -> void`

  * `func bind_display(glyph_id: StringName, accent_color: Color, veterancy_rank: int = 0, squad_count: int = 1, is_ghost: bool = false, is_unpowered: bool = false) -> void`

* **100% Procedural `_draw()`:**

  1. Draws a dark framed `44×44` OS-themed portrait socket matching `_faction_id` (`Technozen` 4 px chamfered teal trim, `Brutalist` 0 px thick ink + amber corner L-brackets, `Bauhaus Sacred` 2 px gold border + corner diamond ticks).

  2. Draws the entity's centered `28×28` procedural vector glyph via `CommandIconGlyphs.draw_glyph(self, glyph_id, Rect2(8, 8, 28, 28), draw_col)` — automatically recognizing every unit, building, resource, relay, uplink, barricade, and future Faction #4/#5 glyph (gracefully falling back to a crisp geometric diamond emblem if an unknown neutral entity has no dedicated glyph).

  3. **Context Micro-Overlays:**

     * **`is_ghost == true` (4.6 Frozen Building Ghost):** Renders desaturated slate-tint glyph + subtle horizontal CRT scanlines + tiny `"FOG"` badge in the bottom-right corner.

     * **`veterancy_rank > 0`:** Draws `1–3` sharp gold (`#FACC15`) rank chevrons along the top-left corner.

     * **`squad_count > 1`:** Draws a crisp compact `"×%d"` micro-badge in the bottom-right corner.

     * **`is_unpowered == true`:** Draws a subtle pulsing warning amber/crimson diagonal badge along the top-right corner.

### C.3 Zero-Churn Telemetry Row Pooling & Coalesced Unit Refreshes (`ui/hud/selection_telemetry_renderer.gd`, `ui/hud/selection_hud.gd`)

1. **Pooled Telemetry Grid Rows (`selection_telemetry_renderer.gd`):**

   * Store a reusable row pool on `SelectionTelemetryRenderer` (`var _telemetry_rows: Array[Dictionary] = []`, each holding `{"box": HBoxContainer, "key": Label, "val": Label}`).

   * In `rebuild_telemetry_grid(hud, stats)`:

     * Reuse existing rows in `hud.telemetry_grid` (growing the pool only if `stats.size() > _telemetry_rows.size()`, hiding unused trailing rows with `box.visible = false`) and update `key.text`, `val.text`, and `val` color in place — **zero `queue_free()` / `Label.new()` churn on every unit hit!**

   * Update `apply_left_column(hud, info)` and `refresh_squad_left_column(hud, active_group)` to drive `hud._entity_portrait.bind_display(...)` with the inspected entity's `glyph_id` (unit `unit_type_id`, building `building_type_id`, ghost `building_type_id`, resource/relay/uplink/barricade icon), `veterancy_rank`, `squad_count`, `is_ghost`, and `is_unpowered`.

2. **Coalesced `0.10s` Dirty Refresh (`selection_hud.gd`):**

   * Add `var _unit_display_dirty: bool = false` and `var _unit_refresh_acc: float = 0.0`.

   * In `_on_unit_health_changed`, `_on_unit_cargo_changed`, and `_on_unit_status_changed`: set `_unit_display_dirty = true` instead of immediately rebuilding HUD controls on every single bullet hit!

   * In `SelectionHUD._process(delta)`: when `_unit_display_dirty`: accumulate `_unit_refresh_acc += delta`; every `0.10s`, reset both and call `_refresh_selected_units_display()` once (removing the redundant `_wireframe_grid.redraw_visible_tiles()` call there since `SelectionWireframeGrid` already ticks its own crisp `0.15s` redraw cadence!).

   * Keep `_on_selection_changed()` and `_on_inspection_changed()` synchronous and immediate so clicking/Tab-cycling still responds with 0 ms latency.

## Phase D — Multi-Team `ResourceHUD`, Split Feedback Channels, Cached Minimap & Interactive `ProductionTicker`

### D.1 Dynamic 2–4 Team Spectator Strip, Dual Alert/Toast Channels & Live Uplink Bonus (`ui/hud/resource_hud.gd`, `scripts/systems/economy_manager.gd`)

1. **Live Uplink Bonus Getter (`scripts/systems/economy_manager.gd`):**

   * Add `func get_uplink_bonus_percent() -> int`: returns `int(round(_uplink_bonus_pct * 100.0))` (e.g., `5` in Skirmish, `10` in Uplink Holdout).

   * In `ResourceHUD._refresh_uplink_pill()`: format `"UPLINK: +%d%%" % _economy_manager.get_uplink_bonus_percent()` instead of hardcoded `"+5%"`.

2. **Dynamic 2–4 Team Spectator Telemetry (`resource_hud.gd`):**

   * Add `var _extra_spec_labels: Dictionary = {}` (`team_id -> Label`) appended cleanly inside `spec_team1_label.get_parent()` when `active_teams.size() > 2`.

   * In `_refresh_spectator_telemetry()`: iterate `TeamManager.get_active_teams()` (mapping `idx 0 -> spec_team0_label`, `idx 1 -> spec_team1_label`, `idx >= 2 -> _extra_spec_labels[tid]`), showing `"%s [%s]: %dB %dS %dC | %d/%d"` colored cleanly with `TeamManager.get_team_color(tid).lightened(0.28)` (hiding unused extra labels on 2P matches).

3. **Split Non-Colliding Feedback Banners & Unscaled Real-Time Timers (`resource_hud.gd`):**

   * Keep `resource_alert_label` strictly for **Critical Tactical & Economy Alerts** (`UNDER ATTACK`, `INSUFFICIENT ...`, `BANDWIDTH LIMIT`).

   * Instantiate a slim secondary `var _system_toast_label: Label` right below `resource_alert_label` inside `TopRightVBox` (`font_size = 11`, `horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT`, `mouse_filter = MOUSE_FILTER_IGNORE`, `visible = false`) strictly for **Utility / Camera Toasts** (`CAMERA BOOKMARK 1 SAVED`, `COMBAT-ONLY BOX SELECT: ON`, `SPEED 2.0X`) via `_on_hud_toast()` — so saving a camera bookmark never erases an active combat warning!

   * Drive `_alert_timer`, `_toast_timer`, `_flash_timers`, `_bw_near_cap_cooldown`, `_bw_pulse_time`, and `_uplink_warn_pulse` using unscaled `real_dt = minf(delta / maxf(0.1, Engine.time_scale), 0.05)`.

4. **Theme Parity on Speed & Spectator Buttons (`resource_hud.gd`):**

   * Apply `FactionHudTheme.style_utility_button()` to `btn_speed_05`, `btn_speed_10`, `btn_speed_15`, `btn_speed_20`, and `btn_spectator_fog` inside `_apply_faction_hud_theme()`.

   * In `_refresh_speed_buttons()`: highlight the active speed preset using `FactionHudTheme.get_speed_active_color(FactionHudTheme.resolve_local_faction_id())` instead of hardcoded cyan.

### D.2 Minimap Static Terrain Cache & Camera Bookmark Pips (`ui/hud/minimap.gd`)

1. **Static Terrain Cache (Eliminates 20 Hz Polygon Re-Tessellation):**

   * Add an internal `SubViewport` (`_terrain_cache_vp`, `render_target_update_mode = UPDATE_ONCE`, `transparent_bg = false`) with a single `Node2D` drawer child (`_terrain_cache_canvas`) that renders Layers 1–2.5 **once** on map init and whenever `refresh_arena_bounds()` or `map_viewport.resized` fires:

     * Arena backdrop + 4×4 tactical grid

     * `high_ground_plateaus` raised terrace polygons + **crisp subtle ramp-lip highlights** (calling `plateau.get_ramp_segments_world()`) so players can read ramp entrances straight off the minimap!

     * `terrain_obstacles` silhouettes

     * Static `map_landmarks` pips

   * In `_on_map_viewport_draw()`: replace Layers 1, 1.5, 2, and 2.5 with a single `map_viewport.draw_texture_rect(_terrain_cache_vp.get_texture(), rect, false)` call (falling back gracefully to direct drawing if cache isn't ready yet), then draw only dynamic layers (`destructible_barricades`, `resource_nodes`, `hyper_uplinks`, `sensor_relays`, `fog_texture`, `salvage_cores`, `buildings` + 4.6 frozen ghosts, `units`, pings, bookmark pips, and camera rectangle)!

2. **Saved Camera Bookmark Pips (`1–8`):**

   * Right before Layer 10 (Camera Viewport Rectangle), inspect `_camera.camera_bookmarks`:

     * For each saved `slot` (`1..8`), draw a tiny crisp hollow diamond/bracket + numeral (`1`, `2`, `3`, `4`...) at `_world_to_minimap(pos)` in subtle cyan-white (`Color(0.76, 0.96, 1.0, 0.72)`) so players can visually verify their saved macro locations on the minimap.

### D.3 Interactive, Pooled `ProductionTicker` (`ui/hud/production_ticker.gd`, `scripts/controllers/selection_controller.gd`)

1. **Public Type-Selection Helper (`scripts/controllers/selection_controller.gd`):**

   * Add `func select_buildings_of_type(building_type_id: StringName, focus_camera: bool = false) -> int`: selects all constructed, non-destroyed, non-salvaging friendly buildings matching `building_type_id` (canceling active targeting cleanly), optionally focusing camera on their lead hub/cluster, and returns count selected.

2. **Enhanced Interactive `ProductionTicker` (`ui/hud/production_ticker.gd`):**

   * **Zero-Churn Row Pooling:** Pre-allocate/pool up to `MAX_VISIBLE_ROWS` (`6`) compact interactive ticker row buttons (each containing icon/label, progress bar, queue-count pill, and status badge) instead of calling `queue_free()` and rebuilding rows on every refresh tick. Ensure every row and panel belongs to group `"blocks_edge_pan"` and uses `FactionHudTheme.make_panel_style(fid, true)`.

   * **Interactive Click Actions on Every Ticker Row (Strictly Safe, Zero Accidental Cancels):**

     * **Left-Click:** Selects that active producing building (`_selection_controller.select_single_entity(building, true)`) and centers the camera on it. *(If a row represents multiple grouped buildings of the same type, cycles through them cleanly on repeated clicks!)*

     * **Shift + Left-Click:** Calls `_selection_controller.select_buildings_of_type(building.building_type_id, false)` so you can instantly select all of your `Cloning Vats` / `Assembly Bays` / `Choir Basilicas` and queue the next wave!

     * **Right-Click:** Focuses camera directly onto that producing building via `_selection_controller.focus_camera_on_entity(building)` **without changing your current army selection** (100% consistent with Milestone 4.8's Wireframe Tile Right-Click!).

   * **Unpowered Paused Badge:** When a producing `PRISMA_DEI` building in the ticker has `requires_power_grid and not is_powered`: tint its ticker progress bar warning amber/crimson and show a crisp `"PAUSED"` status tag instead of a frozen normal bar.

   * **Tooltip:** Add a clean concise hover tooltip (`LMB Select & Center • Shift+LMB All of Type • RMB Focus Camera`).

## Phase E — Verification & Stress-Test Checklist

1. **Zero Errors & Clean Boot Audit:**

   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.

2. **Crash-Free `Alt` Tactical Glance & Faction Macro Overlays:**

   * Hold **`Alt`** over a base containing Biomass/Silica nodes, `Halo Spires`, `Capacitor Pylons`, an unpowered `Choir Basilica`, a High-Yield node, and an active Geothermal Surge:

     * Confirm **zero runtime errors** (the `get_active_harvester_count` crash is fixed) and exact saturation color parity with `ResourceNode` badges.

     * Confirm `PRISMA_DEI` Power Lattice rings, `UNPOWERED` / `PAUSED` badges, `MONOLITH_OS` Capacitor Aura rings, High-Yield `+35%`, and `2x SURGE` pills appear smoothly and fade crisply at both `0.5x` and `2.0x` game speeds.

3. **Zero-Churn `SelectionHUD` & `44×44` Procedural Entity Portrait (`1280×720` Safe):**

   * Select single units, wounded squads under live fire, Veterancy Rank 1–3 units, buildings, unpowered `PRISMA_DEI` structures, and a **4.6 frozen enemy building ghost in `EXPLORED` fog**:

     * Confirm the `44×44` procedural vector emblem renders crisply inside the existing `740×160` `BottomPanel` footprint with **zero overlap with `TacticalMinimap`** at both Windowed `1280×720` and Fullscreen (`F11`).

     * Confirm Veterancy chevrons, squad count `×N`, `FOG` ghost scanlines, and faction OS framing (`GENESIS_V2` Technozen, `MONOLITH_OS` Brutalist, `PRISMA_DEI` Bauhaus Sacred) display cleanly.

4. **Multi-Team `ResourceHUD`, Split Alert/Toast Channels & Cached Minimap:**

   * Trigger an `"UNDER ATTACK"` or `"INSUFFICIENT BIOMASS"` alert and immediately save a Camera Bookmark (`Ctrl+F1`): confirm the bookmark toast appears in its own slim channel **without erasing** the active critical alert, and confirm timers run at real-time speed at `2.0x`.

   * Launch a **3P FFA** (`Triad Sanctum`) and **4P FFA** (`Quad Nexus`) **AI Spectator Match**: confirm all 3–4 teams display cleanly in the top-left spectator strip with faction short-codes, resources, and Bandwidth.

   * Inspect `TacticalMinimap`: confirm static terrain & high-ground ramp lips render crisply from cache, and saved Camera Bookmarks (`Ctrl+F1–F4`) appear as clean numbered pips on the minimap.

5. **Interactive `ProductionTicker` & 100+ Unit Performance Check:**

   * Queue units and upgrades across multiple production buildings (including an unpowered `Choir Basilica`):

     * **Left-Click** a ticker row → selects that building and jumps camera to it.

     * **Shift + Left-Click** a ticker row → selects all friendly buildings of that type.

     * **Right-Click** a ticker row while your army is selected → focuses camera on the building **without dropping your army selection**.

     * Confirm unpowered producing buildings display **`PAUSED`** cleanly in warning amber/crimson.

   * Spawn a **100+ unit mirror fight** in `milestone_0_test.tscn` (`GENESIS_V2` vs. `GENESIS_V2` and `PRISMA_DEI` vs. `PRISMA_DEI`): confirm crisp mirror-match team rim contrast, viewport-culled `HitFeedbackOverlay` pips, smooth frame pacing with idle building redraw gating + micro-VFX load budgeting, and zero dropped mortar/orbital telegraphs.