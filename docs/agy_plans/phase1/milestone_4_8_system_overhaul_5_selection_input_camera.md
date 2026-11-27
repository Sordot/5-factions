# Milestone 4.8 — System Overhaul #5: Next-Gen Selection, Input & Camera

**Prerequisite:** Milestone 4.7 (System Overhaul #4: Economy, Harvesting & Structures) verified and working cleanly.

**Goal:** Harden camera responsiveness, battlefield hit-testing, control groups, multi-cast/multi-worker ergonomics, and wireframe selection UX to crisp, zero-friction *StarCraft II* standards across all game speeds (`0.5x–2.0x`), 1v1, 3P FFA, and 4P matches:

1. **Unscaled, Pixel-Locked `RTSCamera` & Instant Bookmarks (`RTSCamera`, `SettingsManager`, `TacticalMinimap`):** Decouple camera pan/zoom/shake from `Engine.time_scale`, eliminate zoom-to-cursor wobble via exact world-anchor locking, fix sticky middle-mouse drags over HUD panels, block edge-panning behind non-pausing overlays, add dynamic viewport/zoom-aware arena clamping with southern HUD clearance, expand camera bookmarks to `1–8` with **instant SC2 snap recall** + minimap ping, and stop Base Cam cycling from wasting a press on an already-centered hub.

2. **Hardened `SelectionController` & 10-Slot `ControlGroupManager` (`SelectionController`, `ControlGroupManager`, `BoxSelectionResolver`, `SelectionTelemetryRenderer`, `Unit`):** Unify targeting cancellation (fixing Core Overclock leaks on unit-group recall), add Alt-Tab focus-loss marquee safety, upgrade double-tap centering to **largest-cluster centroid** (so 1 stray reinforcement never drags the camera off the main fight), add Group `10` (`0` key) + Engineer staffing sync + clickable pill Shift-append/RMB-clear, fix non-Team-0 inspection bugs, seamlessly hand off fogged enemy buildings to their 4.6 `FogGhostInspectHandle`, fix building `Ctrl+Shift+Click` parity, and register rebindable `cmd_ability_g`.

3. **Spatial-Accelerated `CommandRouter`, Shift-Chain Multi-Cast & Parallel Builders (`SpatialGrid`, `CommandRouter`, `BoxSelectionResolver`, `SelectionController`):** Add `SpatialGrid` rect queries and route all hover/click/build-placement checks through `SpatialGrid` (eliminating per-frame full-scene scans), validate full `get_prerequisite_ids()`, support Shift-chain rapid multi-cast on targeted abilities, dispatch parallel builders across multiple Shift-placed scaffolds, and compute radius-averaged, wall-deduplicated group ring slots (strictly zero role-sorting).

4. **Wireframe Grid Right-Click Focus, Auto-Paging & Wheel Paging (`SelectionWireframeTile`, `SelectionWireframeGrid`, `SelectionHUD`, `SelectionController`):** Add **Right-Click on any wireframe tile to snap the camera onto that exact unit/building without changing selection**, auto-flip pages when `Tab`-cycling subgroups in `>24`-entity armies, support mouse-wheel paging over the wireframe grid, and merge idle-worker/army polling into a single pass.

**Hard Design Guardrails (MUST PRESERVE):**

* **Zero Auto-Formations / Role-Sorted Squads:** `CommandRouter.assign_group_destinations()` must remain purely organic concentric rings—do **not** sort units by combat role, range, or frontline/backline.

* **Zero Skill-Cap Automation:** No stealth/cloaking, no overkill-prevention targeting automation, no auto-loop production, standard worker construction only.

* **Zero Balance Stat Changes:** Do **not** alter any unit or building combat/economy stat numbers.

* **Strict `1280×720` UI Discipline & 100% Procedural Pipeline:** All updated Control Group pills (up to 10 groups), wireframe tooltips, and keybind settings rows must remain 100% procedural and unclipped in Windowed `1280×720` and Fullscreen (`F11`).

## Phase A — Unscaled, Pixel-Locked `RTSCamera` & Instant Camera Bookmarks

### A.1 Unscaled Real-Time Camera Physics & Pixel-Locked Zoom (`scripts/camera/rts_camera.gd`)

1. **Game-Speed-Independent Real Delta:**

   * In `_process(delta)`: compute `var real_dt: float = minf(delta / maxf(0.1, Engine.time_scale), MAX_FRAME_DELTA)` and drive keyboard pan, edge pan, exponential pan smoothing, zoom smoothing, and camera shake strictly with `real_dt`.

   * *Result:* Camera feel stays 100% identical at `0.5x`, `1.0x`, `1.5x`, and `2.0x` game speeds!

2. **Pixel-Locked Zoom-to-Cursor (Zero Wobble):**

   * Add zoom-anchor state:

     * `var _zoom_anchor_active: bool = false`

     * `var _zoom_anchor_world: Vector2 = Vector2.ZERO`

     * `var _zoom_anchor_screen_offset: Vector2 = Vector2.ZERO`

   * In `_apply_zoom_delta(zoom_delta)`:

     * When `zoom_to_cursor` is enabled and cursor is not over a `MOUSE_FILTER_STOP` HUD control:

       * Capture `var mouse_offset: Vector2 = vp.get_mouse_position() - vp_size * 0.5`.

       * Capture `var world_under_mouse: Vector2 = global_position + mouse_offset / maxf(0.05, zoom.x)`.

       * Store `_zoom_anchor_world = world_under_mouse`, `_zoom_anchor_screen_offset = mouse_offset`, `_zoom_anchor_active = true` (removing the mismatched one-shot `_target_position` jump).

   * Cancel `_zoom_anchor_active = false` whenever the player starts keyboard panning, edge panning, middle-dragging, `center_on()`, or `smooth_center_on()`.

   * In `_process()`: right after updating `zoom = Vector2(next_zoom, next_zoom)`, if `_zoom_anchor_active`:

     * Solve `global_position = _clamp_point(_zoom_anchor_world - _zoom_anchor_screen_offset / maxf(0.05, zoom.x))` and sync `_target_position = global_position`.

     * Once `absf(zoom.x - _target_zoom) < 0.0005`: set `_zoom_anchor_active = false`.

   * *Result:* Rapid mouse-wheel zooming locks the exact world pixel beneath your cursor rock-steady from start to finish!

3. **Sticky-Free Middle-Mouse Drag & Modal-Safe Edge Panning:**

   * In `_input(event)`: catch `InputEventMouseButton` where `button_index == MOUSE_BUTTON_MIDDLE and not pressed` and immediately clear `_is_middle_dragging = false` (even if released while hovering `SelectionHUD` or `TacticalMinimap`!).

   * In `_get_edge_pan_vector()`: add a lightweight `_is_modal_or_overlay_open()` guard (checking `pause_menu`, `settings_menu`, `tech_tree_overlay`, `controls_reference_overlay`, `match_end_overlay`, or `get_tree().paused` outside post-match inspection) so edge-panning never moves the camera behind non-pausing overlays.

4. **Dynamic Viewport & Bottom-HUD-Aware Arena Clamping:**

   * Add `var _arena_bounds: Rect2 = Rect2()` lazily resolved from `ArenaNavRegion.arena_bounds` / `FogOfWarSystem.arena_bounds` (with a public `func set_arena_bounds(bounds: Rect2) -> void` helper).

   * In `_clamp_point(pos)`: when `_arena_bounds.has_area()`, compute effective clamping bounds from `_arena_bounds`, inset cleanly on left/right/top while granting a modest bottom allowance (`minf(150.0 / maxf(0.35, zoom.x), 240.0)`) so the bottom `SelectionHUD` never permanently blocks selecting or commanding units along the southern map border (falling back to `pan_bounds` if no arena bounds exist).

### A.2 Instant SC2 Camera Bookmarks (`1–8`) & Smart Base Hub Cycling (`rts_camera.gd`, `settings_manager.gd`)

1. **Instant Snap Bookmark Recall (`F1–F4` Default, `F5–F8` Optional Rebindable):**

   * In `SettingsManager`: register `cam_bookmark_5`, `cam_bookmark_6`, `cam_bookmark_7`, `cam_bookmark_8` alongside `cam_bookmark_1..4` (unbound by default so zero F5–F8 debug/system conflicts occur unless the player chooses to bind them in Settings).

   * In `RTSCamera._unhandled_input()`: loop `slot in range(1, 9)` checking `cam_bookmark_%d`.

   * In `RTSCamera.save_camera_bookmark(slot)` (allowing `1..8`): save `global_position`, emit `camera_toast`, and flash a subtle crisp minimap ring (`minimap.flash_ping(global_position, Color(0.45, 0.96, 1.0, 0.90), 0.75)`).

   * In `RTSCamera.recall_camera_bookmark(slot)`: call **`center_on(target_pos)`** for **instantaneous SC2 snap recall** (clearing `_zoom_anchor_active`), play subtle UI feedback, and flash a brief minimap indicator!

2. **Smart `jump_to_next_base_hub()`:**

   * When the player owns `>= 2` hubs: if `hubs[next_idx].global_position.distance_squared_to(global_position) <= 120.0 * 120.0`, advance `next_idx = (next_idx + 1) % hubs.size()` so pressing Base Cam always jumps to another base instead of re-centering on the hub already on screen.

## Phase B — Hardened `SelectionController` & 10-Slot `ControlGroupManager`

### B.1 Unified Targeting Cancel, Alt-Tab Safety & Team-Agnostic Fixes (`selection_controller.gd`, `unit.gd`)

1. **Unified `cancel_all_targeting()`:**

   * Add `func cancel_all_targeting() -> void` on `SelectionController` calling `cancel_ability_targeting()`, `cancel_overclock_targeting()`, `cancel_attack_move_targeting()`, and `cancel_patrol_targeting()`.

   * Call `cancel_all_targeting()` in every selection replacement/recall path (including `ControlGroupManager.recall()` so recalling a unit group cleanly exits Core Overclock targeting!).

2. **Window Focus-Loss (`Alt+Tab`) Safety:**

   * Add `func _notification(what: int) -> void` on `SelectionController`: on `NOTIFICATION_WM_WINDOW_FOCUS_OUT` or `NOTIFICATION_APPLICATION_FOCUS_OUT`, immediately call `_cancel_drag_box()` and `_clear_custom_cursor()`.

3. **Team-Agnostic Local Player Checks (`selection_controller.gd`, `unit.gd`):**

   * In `SelectionController.select_single_entity()`: replace `b.team == Unit.Team.PLAYER` / `u.team == Unit.Team.PLAYER` with `b.team == _get_local_human_team_enum()` / `u.team == _get_local_human_team_enum()`.

   * In `SelectionController._set_inspected_entity()`: compute `inspected_enemy` using `TeamManager.are_enemies(int(_get_local_human_team_enum()), int(u.team))` instead of hardcoded `== Unit.Team.ENEMY`.

   * In `Unit.is_idle_worker()`: compare `int(team) == TeamManager.get_local_human_team()` (returning `false` in Spectator Mode) instead of hardcoded `team != Team.PLAYER`.

4. **Seamless Fog-Ghost Inspection Handoff (`selection_controller.gd`):**

   * In `SelectionController._process()` when an inspected non-local `Building` (`ib`) goes `not ib.visible`:

     * Before calling `_set_inspected_entity(null)`, check `fog_ghost_overlay` (`get_tree().get_first_node_in_group("fog_ghost_overlay")`): if it exposes an active frozen ghost handle at `ib.global_position` (matching `ib.get_instance_id()`), smoothly hand off `_set_inspected_entity(ghost_handle, false)` so the HUD transitions directly into the SC2 frozen last-known intel panel without flickering closed!

5. **Building `Ctrl+Shift+Click` Merge Parity & Rebindable `cmd_ability_g`:**

   * In `SelectionController._select_at_point()` (friendly building branch): when `is_double_click or ctrl_pressed`, if `shift_pressed and not selected_buildings.is_empty()`, merge `same_b` into `selected_buildings` (matching the exact unit `Ctrl+Shift+Click` behavior!).

   * Register `cmd_ability_g` (default `KEY_G`, label `"Build / Ability [G]"`) in `SettingsManager` and `project.godot` InputMap; replace the raw `KEY_G` check in `SelectionController._unhandled_input()` with `_try_handle_ability_hotkey_event(event, "cmd_ability_g", "G")`, and add `"G": return &"cmd_ability_g"` in `SelectionHUD._get_ability_action_name()`.

### B.2 Largest-Cluster Double-Tap Centering (`selection_controller.gd`)

* Upgrade `_center_camera_on_nodes(nodes: Array) -> void`:

  * Collect valid `Node2D` world positions from `nodes`.

  * If `<= 2` nodes: center on simple average.

  * If `>= 3` nodes: group positions into spatial clusters (`CLUSTER_RADIUS = 420.0 px` — greedy BFS/connected-components grouping), select the cluster with the **highest member count** (breaking ties by closest cluster centroid to `cam.global_position`), and call `cam.center_on(best_centroid)`.

  * *Result:* Double-tapping Control Group `1` or Select-All-Army always snaps directly to your main fighting force even if 1–2 fresh reinforcements are rallying out of your base across the map!

### B.3 Full 10 Control Groups (`1–9, 0`), Staffing Sync & Pill Interactions (`control_group_manager.gd`, `selection_telemetry_renderer.gd`)

1. **Group 10 (`0` Key) Support:**

   * Update `ControlGroupManager.get_key_group_num(key_event)` to map `KEY_0` → `10`.

   * Update all `1..9` bounds/loops in `ControlGroupManager` (`assign`, `append`, `remove`, `steal_assign`, `steal_append`, `recall`, `_strip_from_other_groups`, `get_summary`, `get_rich_summaries`) to `1..10` (iterating display order `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]` so `[0]` appears neatly at the right end of the bar, matching keyboard layout!).

2. **Engineer Staffing Sync:**

   * In `ControlGroupManager._watch_units()`: also connect `u.staffed_state_changed` to `_on_unit_staffed_changed(_unit, _staffed)` so staffing or ejecting Engineers immediately refreshes control-group counts.

3. **Interactive Control Group Pills (`ui/hud/selection_telemetry_renderer.gd`):**

   * Render `[0]` for `num == 10` (and keep pill font/padding compact so up to 10 pills stay unclipped at `1280×720`).

   * Support `Shift + Left-Click` on a pill → `append_control_group(num)` and `Right-Click` on a pill → clear that group (`control_groups.erase(num)` + emit changed) with updated tooltip hint (`LMB Select • Shift+LMB Add • RMB Clear`).

## Phase C — Spatial-Accelerated `CommandRouter`, Shift-Chain Multi-Cast & Parallel Builders

### C.1 `SpatialGrid` Rect Queries (`scripts/systems/spatial_grid.gd`, `scripts/controllers/box_selection_resolver.gd`)

1. **Add Fast Rect Queries on `SpatialGrid`:**

   * `func query_units_in_rect(world_rect: Rect2, filter_team: int = -99) -> Array[Unit]`: expands `world_rect` by `pad = 36.0` for cell iteration, skipping dead/staffed/invalid units cleanly.

   * `func query_buildings_in_rect(world_rect: Rect2, filter_team: int = -99) -> Array[Building]`: expands `world_rect` by `pad = 72.0` for cell iteration, skipping destroyed/invalid buildings cleanly.

2. **Upgrade `BoxSelectionResolver` (`scripts/controllers/box_selection_resolver.gd`):**

   * Route `collect_box_candidates()` through `SpatialGrid.query_units_in_rect()` and `SpatialGrid.query_buildings_in_rect()` (with safe group fallback if `SpatialGrid == null`).

   * Pad `view_rect` by `.grow(24.0)` in `find_visible_units_of_type()` and `find_visible_buildings_of_type()` and route both through `SpatialGrid.query_units_in_rect(view_rect, int(target_team))` / `query_buildings_in_rect(view_rect, int(target_team))` so viewport-edge entities are never missed!

### C.2 O(1) SpatialGrid Hit-Testing & Multi-Prerequisite Build Checks (`scripts/controllers/command_router.gd`, `scripts/controllers/selection_controller.gd`)

* Route every point-hit query in `CommandRouter` through `SpatialGrid`:

  * `find_unit_at_point`, `find_hostile_unit_at_point`, `find_any_unit_at_point` → `SpatialGrid.query_units_in_radius(world_point, 48.0, ...)`

  * `find_building_at_point`, `find_hostile_building_at_point`, `find_any_building_at_point` → `SpatialGrid.query_buildings_in_radius(world_point, 76.0, ...)`

  * `find_resource_node_at_point` → `SpatialGrid.query_resources_in_radius(world_point, 56.0, true)`

  * `find_barricade_at_point` → `SpatialGrid.query_barricades_in_radius(world_point, 80.0)`

  * `find_nearest_unoccupied_vent` → `SpatialGrid.query_resources_in_radius(world_point, max_radius, true)`

* Route `evaluate_build_placement()`'s building, resource, and barricade overlap loops through `SpatialGrid.query_buildings_in_radius(...)`, `query_resources_in_radius(...)`, and `query_barricades_in_radius(...)`.

* Validate **every** prerequisite in `building_data.get_prerequisite_ids()` inside both `CommandRouter.evaluate_build_placement()` and `SelectionController.request_ability_slot()` (now backed by 4.7's O(1) `EconomyManager.has_constructed_building()`!).

### C.3 Shift-Chain Rapid Ability Multi-Cast & Parallel Multi-Worker Builders

1. **Shift-Chain Rapid Multi-Cast & `TargetFilter` Support (`selection_controller.gd`):**

   * In `SelectionController.confirm_ability_target_at(world_pos, shift_queued)`:

     * For `AbilityData.TargetType.UNIT_TARGET`: inspect `ability.target_filter`:

       * `ALLY`: resolve via `command_router.find_unit_at_point(world_pos, _get_local_human_team_enum())` (and allied units in 2v2).

       * `ANY`: check friendly or hostile unit at `world_pos`.

       * `ENEMY` (default): resolve via `command_router.find_hostile_unit_at_point(world_pos, local_int)`.

     * After `var accepted: bool = command_router.issue_ability_order(...)`:

       * If `shift_queued and accepted` and `SubgroupHelper.has_any_ready_caster(subgroup_units, ability)`: **keep `active_targeting_ability` active** so players can rapidly Shift-click `Spore Barrage`, `Grav-Pulse`, `Radiant Mark`, or `Solar Convergence` across all ready casters in the subgroup!

       * Otherwise call `cancel_ability_targeting()`.

2. **Parallel Multi-Worker Build Dispatch (`command_router.gd`):**

   * Upgrade `find_closest_builder(units: Array[Unit], target_pos: Vector2) -> Unit`:

     * For each valid builder `u` in `units`, count pending build tasks: `var build_load: int = (1 if u.command_state == Unit.CommandState.CONSTRUCTING else 0)` + count of `&"build"` entries in `u.command_queue`.

     * Score each builder by `var score: float = float(build_load) * 1200.0 + u.global_position.distance_to(target_pos)` and pick the lowest-score builder!

     * *Result:* Selecting 1 worker behaves identically (queues all Shift-placed buildings cleanly onto that worker). Selecting 3 workers and Shift-placing 3 structures assigns 1 scaffold to each worker in parallel—matching SC2 macro ergonomics!

3. **Radius-Aware, Wall-Deduplicated Group Ring Destinations (`command_router.gd`):**

   * In `assign_group_destinations(units, center_pos)`:

     * Compute `avg_radius` across all `units` (clamped `[12.0, 26.0]`) instead of using only `units[0].data.collision_radius`—strictly keeping pure concentric rings with zero role-sorting!

     * In `_generate_ring_slots(...)`: when `has_map` snaps a ring candidate onto a cliff wall or arena edge, check if `candidate` collapsed within `(spacing * 0.45)^2` of an already-added slot; if so, nudge slightly inward toward `first_pos` (or skip to the next valid ring slot, up to `ring <= 10` safety cap) so squads ordered near walls fan cleanly along the wall instead of stacking on a single corner pixel.

## Phase D — Wireframe Grid Right-Click Focus, Auto-Paging & Wheel Paging

### D.1 Right-Click Wireframe Tile → Instant Camera Focus (`selection_wireframe_tile.gd`, `selection_wireframe_grid.gd`, `selection_hud.gd`, `selection_controller.gd`, `selection_telemetry_renderer.gd`)

1. **`ui/hud/selection_wireframe_tile.gd`:**

   * Add `signal tile_right_clicked(entity: Node)`.

   * In `_gui_input(event)`:

     * On `InputEventMouseButton` with `button_index == MOUSE_BUTTON_RIGHT and pressed`: call `accept_event()` immediately and emit `tile_right_clicked.emit(entity_ref)`.

     * Note: do **not** consume `MOUSE_BUTTON_WHEEL_UP` / `WHEEL_DOWN` on the tile itself so wheel events bubble cleanly up to `SelectionWireframeGrid` for paging!

2. **`ui/hud/selection_wireframe_grid.gd`:**

   * Add `signal entity_tile_right_clicked(entity: Node)` and forward every tile's `tile_right_clicked` signal.

   * **Mouse-Wheel Paging:** Implement `_gui_input(event)` on `SelectionWireframeGrid`: when `visible and _ordered_entries.size() > SLOTS_PER_PAGE`, intercept `MOUSE_BUTTON_WHEEL_UP` (`_on_prev_page()`) and `MOUSE_BUTTON_WHEEL_DOWN` (`_on_next_page()`) and call `accept_event()` so wheel-scrolling over the grid flips pages without zooming the camera!

   * **Auto-Jump to Active Subgroup Page:**

     * Track `var _last_active_subgroup_key: StringName = &""`.

     * In `set_unit_subgroups(subgroups, active_subgroup_index)` and `set_building_subgroups(...)`: compute `var active_key: StringName` (the active subgroup's `type_id`). If `active_key != _last_active_subgroup_key` and `active_key != &""`: find the first entry in `entries` with `entry["is_active"] == true` and set `_current_page = first_active_idx / SLOTS_PER_PAGE` before binding!

     * Reset `_last_active_subgroup_key = &""` in `clear_grid()`.

3. **`ui/hud/selection_hud.gd`, `ui/hud/selection_telemetry_renderer.gd` & `scripts/controllers/selection_controller.gd`:**

   * Connect `_wireframe_grid.entity_tile_right_clicked` to `_on_wireframe_tile_right_clicked(entity)` → calls `_selection_controller.focus_camera_on_entity(entity)`.

   * Add `func focus_camera_on_entity(entity: Node) -> void` on `SelectionController`:

     * Validates `entity is Node2D and is_instance_valid(entity)` (and alive/non-destroyed).

     * Snaps `RTSCamera.center_on(entity.global_position)` **without altering selection**!

     * Flashes a brief focus ping on `TacticalMinimap` (`Color(0.95, 0.99, 1.0, 0.90)`, `0.65s`) and plays subtle UI click.

   * Update `SelectionTelemetryRenderer.show_wireframe_hover_tooltip()` footer line to:
     `"LMB Isolate • RMB Focus • Shift Remove • Ctrl Type"`.

### D.2 Single-Pass `_refresh_idle_workers()` (`selection_controller.gd`)

* Inside `_refresh_idle_workers(force_emit)`: collect `idle_list` and `cur_army_count` in a **single** pass over `get_tree().get_nodes_in_group("units")` (preserving public `get_idle_workers()` and `get_army_units()` methods cleanly for external callers).

## Phase E — Verification & Stress-Test Checklist

1. **Zero Errors & Clean Boot Audit:**

   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.

2. **Unscaled `RTSCamera`, Pixel-Locked Zoom & Instant Bookmarks:**

   * Toggle game speed between `0.5x`, `1.0x`, and `2.0x`: confirm keyboard pan, edge pan, and zoom feel **100% identical** across all speeds.

   * Scroll mouse-wheel rapidly in and out while aiming at a Command Hub corner: confirm the exact world point under the cursor stays **pixel-locked** with zero wobble.

   * Hold Middle-Mouse to drag-pan, move cursor onto `SelectionHUD`, and release Middle-Mouse: confirm drag releases cleanly (zero sticky pan!).

   * Open `TechTreeOverlay` (`U`) or `ControlsReferenceOverlay` and move mouse to screen edge: confirm edge-panning stays paused behind overlays.

   * Save bookmarks with `Ctrl+F1` / `Ctrl+F2` / `Ctrl+F3` and recall with `F1` / `F2` / `F3`: confirm **instantaneous SC2 snap** (no glide lag) + brief minimap ping without dropping current unit selection.

   * Own 2+ Command Hubs and press Base Cam hotkey: confirm it cycles cleanly to your *other* hub on the very first press.

3. **10 Control Groups, Largest-Cluster Double-Tap & Fog-Ghost Handoff:**

   * Assign a group to **`0` (`Ctrl+0`)** alongside `1–9`: confirm `[0]` pill renders cleanly unclipped at `1280×720`, `Shift+Click` pill appends selection, and `Right-Click` pill clears the group.

   * Put `15×` units in Control Group `1` across the map and `1×` unit back at base, then double-tap `1`: confirm camera snaps straight onto the `15×` frontline cluster (not halfway into empty space).

   * Recall a unit group while `Core Overclock` targeting is armed: confirm Overclock targeting cancels cleanly.

   * Inspect an enemy building, then pull your scout back so it enters `EXPLORED` fog: confirm `SelectionHUD` transitions smoothly to its frozen 4.6 `FogGhostInspectHandle` instead of closing.

   * Start dragging a selection box and `Alt+Tab` out of the game window: confirm marquee cancels cleanly on return.

   * Rebind `cmd_ability_g` in Settings and select an `Acolyte` / `Worker Drone` / `Servo-Drone`: confirm Slot 11 displays the new bound hotkey and triggers T2 building placement cleanly.

4. **Shift-Chain Multi-Cast, Parallel Builders & Wireframe Grid UX:**

   * Select `4×` `Chrysalis Mortar` / `Lumen Skiff` / `Solstice Lance` / `Prism Weaver`, press `Q` (`Radiant Mark` / `Solar Convergence` / `Blinding Glare`), and **`Shift + Left-Click`** 3 different targets in a row: confirm the targeting reticle stays armed until all ready casters are dispatched!

   * Select `3×` workers and `Shift`-place `3×` `Halo Spires` / `Synapse Pylons`: confirm all 3 workers dispatch **in parallel** (1 scaffold each).

   * Select `32×` mixed units (`20× Votary`, `6× Cantor`, `6× Lens Adjudicator`):

     * Press `Tab` to switch to `Lens Adjudicator` (on Page 2): confirm `SelectionWireframeGrid` **auto-flips to Page 2** immediately.

     * Scroll mouse wheel over the wireframe grid: confirm pages flip cleanly without zooming the camera.

     * **Right-Click** a specific wounded unit's wireframe tile: confirm the camera **snaps directly to that unit** while keeping all 32 units selected!