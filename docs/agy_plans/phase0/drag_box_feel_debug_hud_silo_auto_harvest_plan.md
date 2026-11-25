# Milestone 2.5.1 Plan: SC2-Grade Drag-Box Feel, Debug HUD Silo & Starting Worker Auto-Harvest

**Target Directory:** `docs/agy_plans/29_drag_box_feel_debug_hud_silo_and_auto_harvest.md`
**Primary Extended Files:** `scripts/controllers/selection_controller.gd`, `ui/overlays/selection_box.gd`, `ui/overlays/entity_visuals.gd`, `scripts/units/unit.gd`, `scripts/buildings/building.gd`, `ui/hud/sandbox_debug_panel.tscn`, `ui/hud/sandbox_debug_panel.gd`, `scenes/ui/pause_menu.tscn`, `scripts/ui/pause_menu.gd`, `scripts/systems/match_manager.gd`
**Reference Docs:** `docs/agy_plans/26_smart_box_select_and_attack_move_mode.md`, `docs/agy_plans/28_ffa_arena_lobby_teams_decals_and_camera_feel.md`, `docs/agy_plans/worker_rvo_and_multi_worker_task_fix.md`

## 1. Objective & Scope

Execute a focused gamefeel and UX polish pass across three high-impact areas before starting Faction #2:

1. **SC2-Grade Drag-Box Selection Feel:** Eliminate rigidity in marquee selection by switching to circle-vs-rect hit detection, adding live marquee preview rings as the box sweeps over units, updating the box continuously during camera panning, catching mouse-up releases cleanly even over HUD panels, tightening the drag threshold to `4.0 px`, and keeping box border thickness zoom-invariant.
2. **Sandbox / Debugger HUD Siloing & Minimize Toggle:** Keep the skirmish viewport clean by hiding `SandboxDebugPanel` by default on skirmish maps (`skirmish_arena_01`, `02`, `03`), surfacing a toggle for it inside `PauseMenu` (`Esc`), keeping it visible by default on `milestone_0_test.tscn`, and adding a compact `[ – ]` collapse button on its header.
3. **Starting Workers Auto-Harvesting Biomass:** Give every skirmish match an immediate, snappy StarCraft-style opening where each active team's 3 starting `Worker` units automatically fan out across their local `BiomassNode` cluster and begin harvesting at match start (while leaving `milestone_0_test.tscn` workers idle for manual testing).

### Out of Scope
* Changing `Alt + 1–9` control group stealing, `Ctrl + Click` same-type selection, or `Smart Box-Select` hotkey toggle behavior.
* Removing any existing buttons or Combat Lab presets from `SandboxDebugPanel`.
* Modifying `SkirmishAI` macro build orders beyond ensuring it respects already-gathering starter workers.

---

## 2. Phase A: SC2-Grade Drag-Box Selection Feel

### A.1 Circle-vs-Rect Hit Detection & Tighter Threshold (`scripts/controllers/selection_controller.gd`)
* **Lower Drag Threshold:** Reduce `drag_threshold` from `8.0` to **`4.0` px** so quick micro-boxes open instantaneously without feeling sluggish.
* **Circle-vs-Rect Intersection Helper:**
  * Replace center-point-only checks (`world_rect.has_point(entity.global_position)`) with a clean helper `_circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool`:
    * Clamp `center` to `[rect.position, rect.end]` and test `center.distance_squared_to(closest_point) <= radius * radius`.
  * Use each unit's visual/selection radius (`unit.get_selection_radius()` or `unit.data.collision_radius + 4.0`) and `building.footprint_radius * 0.75` for buildings so grazing any part of a unit's body or selection ring grabs it reliably.

### A.2 Live Marquee Preview Highlights (`selection_controller.gd`, `unit.gd`, `building.gd`, `entity_visuals.gd`)
* **Preview State on Entities:**
  * Add `var is_marquee_highlighted: bool = false` and `func set_marquee_highlighted(active: bool) -> void` on `Unit` and `Building` (only calling `queue_redraw()` when the value actually changes to avoid per-frame redraw churn).
  * In `entity_visuals.gd`, when `entity.is_marquee_highlighted` is `true` and `not entity.is_selected`, draw a crisp, lightweight translucent Technozen preview ring (`#38BDF8` in standard mode, `#F59E0B` when `SettingsManager.smart_box_select_enabled` is active).
* **Exact 1:1 Preview Matching (`selection_controller.gd`):**
  * Extract the drag-rect candidate filter into a shared helper `_collect_box_selection_candidates(world_rect: Rect2) -> Array` used by **both** live preview updates and final selection on mouse-up.
  * Because both paths share the exact same filter (including `SettingsManager.smart_box_select_enabled` combat-only filtering), the units highlighted inside the box always match the exact units selected on release.
  * Clear all `_marquee_preview_entities` immediately upon mouse-up, drag cancel, or scene exit.

### A.3 Continuous Pan Updates, Safe HUD Release & Drag Cancel (`selection_controller.gd`)
* **Pan-Synced Marquee in `_process()`:**
  * While `_is_dragging == true`, update the drag end point from `get_global_mouse_position()` every frame in `_process()` (not only on `InputEventMouseMotion`), updating `SelectionBox` and `_update_marquee_preview()` so edge-panning or WASD/arrow panning mid-drag smoothly stretches the selection box across the map.
* **HUD-Safe Mouse-Up Catch in `_input()`:**
  * Listen for `InputEventMouseButton` (`MOUSE_BUTTON_LEFT`, `not event.pressed`) inside `_input(event)` whenever `_is_dragging` (or `_mouse_down_for_drag`) is `true`. Finalize the box selection immediately even if the cursor was released over `TacticalMinimap`, `ResourceHUD`, `SelectionHUD`, or `ProductionTicker`—completely eliminating sticky boxes.
* **Clean Drag Cancellation:**
  * Pressing `Esc` (`cmd_cancel`) or `MOUSE_BUTTON_RIGHT` while `_is_dragging == true` cleanly cancels the drag box, clears marquee preview rings, and consumes the cancel input without issuing an unintended order.

### A.4 Zoom-Invariant Crisp Marquee Rendering (`ui/overlays/selection_box.gd`)
* Scale border stroke width dynamically by the active camera zoom (`var line_w := clampf(1.5 / maxf(cam_zoom_x, 0.25), 0.9, 3.0)`) so the drag box remains razor-thin and crisp whether zoomed all the way in or all the way out.
* Add subtle 6px Technozen corner bracket ticks (zoom-scaled) on the four corners of the marquee for sharper visual framing while preserving the existing cyan (standard) vs. amber (`Smart Box-Select ON`) color coding.

---

## 3. Phase B: Sandbox / Debugger HUD Siloing & Minimize Toggle

### B.1 Auto-Hide on Skirmish Maps & Collapse Pill (`ui/hud/sandbox_debug_panel.tscn` & `.gd`)
* **Group Registration & Scene Detection:**
  * Add `SandboxDebugPanel` to group `"sandbox_debug_panel"` in `_ready()`.
  * Detect whether the active scene is the Sandbox Testbed (`get_tree().current_scene.scene_file_path.ends_with("milestone_0_test.tscn")`).
  * **On Skirmish Maps (`skirmish_arena_01`, `02`, `03`):** Start with `visible = false` so skirmishes launch with a completely clean HUD.
  * **On `milestone_0_test.tscn`:** Keep `visible = true` by default so the sandbox testbed remains immediately usable.
* **Compact Header Minimize Button (`[ – ]` / `[ + ]`):**
  * Add a compact `Button` (`BtnCollapse`) in the top-right corner of the `SandboxDebugPanel` header bar.
  * Clicking `[ – ]` hides the panel's body content container (`BodyVBox` / `ScrollContainer`) and shrinks the panel to a slim corner header pill (`DEBUG HUD [ + ]`), freeing screen space without losing quick access.
  * Expose `toggle_panel_visible() -> bool` and `set_panel_visible(show: bool) -> void` for `PauseMenu`.

### B.2 Pause Menu (`Esc`) Toggle (`scenes/ui/pause_menu.tscn` & `scripts/ui/pause_menu.gd`)
* Add a clean Technozen button inside `PauseMenu` (below **Tech Tree** / **Settings & Keybinds**):
  * Dynamic label: **`Sandbox / Debug HUD: OFF`** or **`Sandbox / Debug HUD: ON`** (synced whenever `PauseMenu` opens by querying the `"sandbox_debug_panel"` node).
  * Clicking the button calls `panel.toggle_panel_visible()`, updates the label immediately, and plays a crisp UI click cue via `AudioManager`—allowing you to pop the Debug HUD / Combat Lab open mid-skirmish whenever needed and tuck it away again cleanly.
  * Hide the button automatically if no `"sandbox_debug_panel"` node exists in the current scene.

---

## 4. Phase C: Starting Workers Auto-Harvest Biomass

### C.1 Deferred Match-Start Worker Dispatch (`scripts/systems/match_manager.gd`)
* **Skirmish-Only Gate:**
  * Skip auto-dispatch completely on `milestone_0_test.tscn` so sandbox test workers remain idle until manually commanded.
* **Timing:**
  * Trigger `_dispatch_starting_workers_to_biomass()` via a short deferred handoff after match initialization (e.g., `await get_tree().process_frame` + `await get_tree().physics_frame` or `0.15s` timer after `ArenaNavRegion` initial bake) so `NavigationServer2D` maps and `TeamManager` active team cleanup (`skirmish_arena_03.tscn`) have already finalized.
* **Smart Cluster Spreading:**
  * For each active `team_id` in `TeamManager.get_active_teams()`:
    * Locate that team's starting `Nexus Vat` (or hub centroid) and all living `Worker` units (`data.unit_id == &"worker_unit"`) belonging to that team that are currently `IDLE` with an empty `command_queue`.
    * Collect all nearby `BiomassNode`s (`resource_type == &"biomass"`, `remaining_amount > 0`) within `~550 px` of that team's starting hub, sorted by distance.
    * Track a per-node assignment count (`assigned_count[node]`) and assign each starting worker to the **least-assigned nearest** `BiomassNode` via `worker.issue_gather(target_node, false)`.
    * Result: the 3 starting workers immediately fan out cleanly across the starter Biomass pods on second 0 instead of idling or piling onto a single node.
  * **Player & AI Safety:**
    * If the player issues any manual command before the deferred frame fires (`command_state != IDLE`), skip that worker so player input always wins.
    * `SkirmishAICommander` naturally recognizes already-`GATHERING` workers without double-assigning or interrupting them.

---

## 5. File & Architecture Summary

### Existing Files to Extend
* `scripts/controllers/selection_controller.gd`: `4.0 px` drag threshold, `_circle_intersects_rect()`, shared `_collect_box_selection_candidates()`, live marquee preview management, `_process()` pan-synced drag updates, `_input()` HUD-safe mouse-up catch, and `Esc`/RMB drag cancel.
* `ui/overlays/selection_box.gd`: Zoom-invariant crisp border thickness + corner bracket ticks.
* `scripts/units/unit.gd`, `scripts/buildings/building.gd`, `ui/overlays/entity_visuals.gd`: `is_marquee_highlighted` state & translucent live preview ring rendering.
* `ui/hud/sandbox_debug_panel.tscn` & `ui/hud/sandbox_debug_panel.gd`: `"sandbox_debug_panel"` group registration, auto-hide on skirmish maps vs. visible on `milestone_0_test.tscn`, and header `[ – ]` / `[ + ]` minimize toggle.
* `scenes/ui/pause_menu.tscn` & `scripts/ui/pause_menu.gd`: **`Sandbox / Debug HUD: OFF / ON`** toggle button synced with live panel state.
* `scripts/systems/match_manager.gd`: Deferred `_dispatch_starting_workers_to_biomass()` with smart local-cluster spreading on skirmish maps.

---

## 6. Verification Checklist for `agy`

Before concluding Milestone 2.5.1, verify in Godot (`milestone_0_test.tscn`, `skirmish_arena_01.tscn`, and `skirmish_arena_03.tscn`):

* [ ] **SC2-Grade Drag-Box Responsiveness:**
  * Drag a box that only grazes the outer ring/edge of a unit (not its center) and confirm it highlights live and selects cleanly on release.
  * Sweep a box over mixed Workers and Clone Troopers with `Smart Box-Select` **OFF** (all units preview-highlight in cyan and select) and **ON** (only combat units preview-highlight in amber and select).
  * Start a drag box, pan the camera with WASD/edge-pan mid-drag, and release Left-Click while the cursor is over `TacticalMinimap` or `SelectionHUD`; verify the marquee stretches smoothly during panning and finalizes cleanly without sticking.
  * Press `Esc` or Right-Click mid-drag and confirm the marquee cancels cleanly with zero preview rings left behind.
  * Zoom all the way in and all the way out while dragging to verify the marquee border stays crisp and thin.
* [ ] **Sandbox / Debug HUD Siloing & Minimize:**
  * Launch `skirmish_arena_01.tscn` and confirm `SandboxDebugPanel` is **hidden** by default.
  * Press `Esc` (`PauseMenu`), click **`Sandbox / Debug HUD: OFF`**, confirm it flips to `ON` and displays the panel, test the `[ – ]` / `[ + ]` header collapse pill, then toggle it back `OFF` cleanly.
  * Launch `milestone_0_test.tscn` and confirm `SandboxDebugPanel` starts **visible** by default with `[ – ]` collapse working.
* [ ] **Starting Workers Auto-Harvest:**
  * Launch a skirmish on `skirmish_arena_01.tscn` and a 4-player match on `skirmish_arena_03.tscn`; confirm all active teams' 3 starting workers immediately fan out across their local `BiomassNode` cluster and begin harvesting on second 0 with zero pathing stalls.
  * Launch `milestone_0_test.tscn` and confirm sandbox workers remain idle as before, with zero Godot Debugger errors.