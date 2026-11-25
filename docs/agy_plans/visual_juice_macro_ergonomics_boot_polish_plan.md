# Milestone 2.5.3 Plan: Input Crispness, Visual Juice, Macro Ergonomics & Match-Start Boot Polish

**Target Directory:** `docs/agy_plans/31_visual_juice_macro_ergonomics_and_boot_polish.md`
**Primary Extended Files:** `project.godot`, `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`, `scripts/units/unit.gd`, `scripts/units/movement_component.gd`, `scripts/buildings/building.gd`, `scripts/buildings/production_component.gd`, `scripts/world/resource_node.gd`, `scripts/world/destructible_barricade.gd`, `scripts/world/salvage_core.gd`, `scripts/systems/settings_manager.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/audio_manager.gd`, `ui/overlays/entity_visuals.gd`, `ui/overlays/command_queue_overlay.gd`, `ui/overlays/combat_vfx.gd`, `ui/overlays/rally_point_overlay.gd`, `ui/hud/selection_hud.gd`, `ui/hud/production_ticker.gd`, `ui/hud/resource_hud.tscn`, `ui/hud/resource_hud.gd`, `ui/hud/minimap.gd`
**Reference Docs:** `docs/agy_plans/30_worker_saturation_and_harvest_polish.md`, `docs/agy_plans/29_drag_box_feel_debug_hud_silo_and_auto_harvest.md`, `docs/agy_plans/27_audio_mix_priority_and_polish_pass.md`

## 1. Objective & Scope

Deliver a high-impact visual, macro, and input-feel polish pass before transitioning into Faction #2. Every UI and HUD addition must stay cleanly proportioned inside the `1280×720` (`canvas_items` + `expand`) base viewport in both Windowed and Fullscreen modes without overlapping existing panels.

### In Scope

1. **Input Crispness & Production Ergonomics:**

   * **Hover Pre-Highlight Outlines:** Render a subtle, color-coded Technozen hover ring/outline on whichever unit, building, `ResourceNode`, `DestructibleBarricade`, or `SalvageCore` is directly under the cursor before clicking.

   * **Shift-Click ×5 Production & Ticker Cancel:** Allow `Shift + Left-Click` on unit training buttons in `SelectionHUD` to queue 5 units at once (distributed evenly across all selected compatible production buildings), and allow `Right-Click` on any row in `ProductionTicker` to cancel and refund the last queued (or active) item directly.

   * **Color-Coded Shift-Queue Waypoints:** Differentiate `CommandQueueOverlay` path segments by order type (cyan for Move, crimson for Attack-Move/Attack, emerald for Gather/Repair/Salvage, amber for Build/Ability, azure for Patrol) with crisp directional chevrons along each leg.

2. **Visual Juice & Diegetic Base Readability:**

   * **Active vs. Idle Building States:** Animate glowing conduits, core pulses, and soft telemetry sparks on `Cloning Vat`, `Calibration Foundry`, `Synthetics Fabricator`, and `Wetware Mainframe` while actively training or researching, contrasted against a dimmer cool standby state when idle.

   * **Spawn-In & Completion Transitions:** Play a crisp `0.25s` Technozen materialization flash + subtle scale-pop (`0.72 → 1.0`) when units spawn or scaffolds finish constructing, plus a brief expanding ground ripple ring whenever a building's rally point is set or updated.

   * **Minimap Iconography Pass:** Upgrade `TacticalMinimap` markers from uniform dots into distinct silhouettes: bordered large squares for Command Hubs (`Nexus Vat`), medium squares for other structures, upward triangles for heavy units (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`), compact dots for infantry/workers, pulsing amber diamonds for `SalvageCore`s, and hashed bars for `DestructibleBarricade`s.

3. **Macro Ergonomics & Squad Settling:**

   * **Idle Production Building Cycler:** Add a compact clickable HUD pill (`IDLE PROD: N`) beside the Idle Worker / Army badges in `ResourceHUD` plus a rebindable hotkey (`cmd_select_idle_production`) that cycles through constructed friendly military production buildings with empty queues.

   * **Bandwidth Near-Cap Warning:** Add an early amber pulse state + single throttled telemetry chime when Bandwidth reaches within `2` of capacity (`used >= cap - 2` and `used < cap`), ahead of the existing crimson at-cap warning.

   * **Unit Arrival Soft-Settling:** Prevent large squads from micro-jostling around a shared Move destination by smoothly settling units that arrive within a tight formation tolerance of already-settled allies.

4. **Crisp Match-Start Boot Sequence:**

   * Play a sleek, lightweight `~1.2s` Technozen viewport fade-in centered smoothly on the player's starting `Nexus Vat` (or arena center in Spectator Mode) as the 3 starting workers fan out to harvest Biomass (skipped on `milestone_0_test.tscn`).

### Out of Scope

* Smart building placement range overlays / grid-snapping.

* AI wave staging / retreat logic or Post-Match "Inspect Map" mode.

* Faction #2 units, buildings, or rosters.

## 2. Phase A: Micro & Input Crispness

### A.1 Hover Pre-Highlight Outlines (`selection_controller.gd`, `entity_visuals.gd`, world entities)

* **Unified Hover Tracker (`SelectionController`):**

  * In `_process()`, when the mouse is over the playable world (not over HUD panels and not actively drag-boxing), resolve the top-most hovered entity (`Unit`, `Building`, `ResourceNode`, `DestructibleBarricade`, or `SalvageCore`) using each entity's selection/footprint radius.

  * Only update `_hovered_entity` when the target actually changes—calling `set_hovered(false)` on the previous entity and `set_hovered(true)` on the new entity (avoiding unnecessary per-frame redraws).

  * Clear `_hovered_entity` cleanly when entering a drag-box, opening `PauseMenu`/`SettingsMenu`/`TechTreeOverlay`, or when the hovered entity is freed.

* **Diegetic Hover Ring (`entity_visuals.gd` & world entities):**

  * Draw a crisp, subtle outer ring (`1.4px`, zoom-invariant, slightly pulsing) around hovered entities (skipping redundant full rings if already selected, or rendering a faint outer highlight halo):

    * **Friendly Unit / Building:** Soft Technozen cyan (`#38BDF8`, alpha `0.55`).

    * **Hostile Unit / Building:** Sharp crimson (`#FF4D6D`, alpha `0.65`).

    * **Neutral Resource / Salvage / Barricade:** Warm emerald (`#34D399`) for `ResourceNode`, amber (`#F59E0B`) for `SalvageCore` and `DestructibleBarricade`.

### A.2 Shift-Click ×5 Production & Ticker Cancel (`selection_hud.gd`, `production_component.gd`, `production_ticker.gd`)

* **Shift-Click ×5 Queueing (`SelectionHUD`):**

  * When clicking a unit training button in `SelectionHUD` while `Input.is_key_pressed(KEY_SHIFT)` is `true`, attempt to queue **`5`** instances instead of `1`.

  * **Multi-Building Load Balancing:** When multiple compatible production buildings are selected (e.g., 3 `Cloning Vats`), distribute each of the 5 queued units to whichever selected building currently has the shortest queue—stopping gracefully if resources or queue slots run out (and playing one crisp confirmation sound rather than 5 stacked sounds).

  * Append `[Shift+Click: Queue x5]` to unit production button tooltips in `CommandTooltip`.

* **Right-Click Cancel in `ProductionTicker` (`ui/hud/production_ticker.gd`):**

  * Handle `MOUSE_BUTTON_RIGHT` presses on any active `ProductionTicker` row:

    * For unit production rows: call `production_component.cancel_last_queued()` (or cancel active item if queue length is 1), refunding `100%` of resource cost cleanly to `EconomyManager` and playing a subtle cancel SFX.

    * For active upgrade rows: cancel the active research if supported by `UpgradeManager` (refunding 100%) or ignore cleanly if already complete.

  * Keep existing Left-Click (select building) and Double-Click (focus camera) intact, and add a brief tooltip hint (`LMB: Select • RMB: Cancel`).

### A.3 Color-Coded Shift-Queue Waypoints (`ui/overlays/command_queue_overlay.gd`)

* Map each queued command type in `CommandQueueOverlay` to a distinct Technozen palette:

  * **Move:** Cyan (`#38BDF8`)

  * **Attack-Move / Attack:** Crimson (`#FF4D6D`)

  * **Gather / Repair / Salvage:** Bioluminescent Emerald (`#34D399`)

  * **Build / Ability Cast:** Luminous Amber (`#F59E0B`)

  * **Patrol:** Azure / Gold (`#60A5FA`)

* Render tiny directional chevrons (`>` spaced along each segment or at the midpoint) and a matching colored waypoint node diamond at each vertex so multi-step worker build chains and scout patrol loops read cleanly at a glance.

## 3. Phase B: Visual Juice & Diegetic Base Readability

### B.1 Active vs. Idle Building States (`scripts/buildings/building.gd`, `ui/overlays/entity_visuals.gd`)

* Expose a lightweight helper `building.is_actively_producing() -> bool` returning `true` when `ProductionComponent` has an active queue item or when `UpgradeManager` is actively researching an upgrade tied to that building (or when a `Wetware Mainframe` has staffed Engineers actively generating Compute).

* In `entity_visuals.gd` / `building.gd`:

  * **Active State:** Drive a smooth sine-wave conduit pulse (`~2.2 Hz`) along the structure's inner Technozen accent lines/core ring, boosting emissive brightness and emitting subtle rising vector energy motes (throttled lightweight `_draw()` sparks—zero heavy particle nodes).

  * **Idle State:** Dim the inner core/conduit lines to a cool, low-contrast standby slate/cyan (`~45%` brightness, no pulse) so players can immediately spot idle `Cloning Vats`, `Calibration Foundries`, and `Synthetics Fabricators` just by glancing at their base.

### B.2 Spawn-In, Completion & Rally Ripple Transitions (`unit.gd`, `building.gd`, `combat_vfx.gd`, `rally_point_overlay.gd`)

* **Unit Materialization (`unit.gd` & `entity_visuals.gd`):**

  * Add `var spawn_anim_timer: float = 0.25` initialized on newly produced units (`production_component.gd` sets/triggers it on spawn, skipping pre-placed map units at match start).

  * Over `0.25s`, ease visual draw scale from `0.72 → 1.0` (cubic ease-out) with a brief bright cyan/emerald Technozen rim flash (`alpha 0.85 → 0.0`) so units pop crisply out of vats and fabricators.

* **Building Completion Flash (`building.gd` & `combat_vfx.gd`):**

  * When `is_constructed` flips from `false` to `true`, trigger a clean expanding perimeter ring pulse and brief `0.22s` bright frame flash around the completed structure footprint.

* **Rally Point Update Ripple (`command_router.gd`, `rally_point_overlay.gd` / `combat_vfx.gd`):**

  * Whenever a player sets or updates a building's rally point (ground, resource node, or follow-unit), spawn a crisp `0.35s` expanding concentric ground ripple at the target position in cyan/emerald.

### B.3 Minimap Iconography Pass (`ui/hud/minimap.gd`)

Upgrade entity rendering in `TacticalMinimap._draw()` while keeping Fog of War visibility and team color coding (`TeamManager.get_team_color()`) 100% intact:

* **Command Hubs (`Nexus Vat` / `Command Core`):** Larger bordered square (`7×7 px` with a `1px` bright white/accent border).

* **Standard Structures:** Medium solid square (`4.5×4.5 px`).

* **Heavy Combat Units (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`):** Crisp upward triangle (`5.5 px` base) with a subtle dark outline so heavy pushes stand out immediately from swarm infantry.

* **Infantry, Support & Workers:** Clean compact dots/squares (`2.5–3.0 px`; slightly smaller/softer for workers so combat blobs read clearly).

* **`SalvageCore`s:** Pulsing small amber/cyan diamond (`4.0 px`).

* **`DestructibleBarricade`s:** Distinct hashed amber/slate rectangular block matching barricade orientation.

* **`Data Hyper-Uplink`:** Crisp concentric gold/white beacon ring at center.

## 4. Phase C: Macro Ergonomics & Squad Settling

### C.1 Idle Production Building Cycler (`project.godot`, `settings_manager.gd`, `selection_controller.gd`, `resource_hud.tscn/.gd`)

* **Rebindable Hotkey (`project.godot` & `SettingsManager`):**

  * Register `cmd_select_idle_production` in `project.godot` (default **`KEY_SEMICOLON` (`;`)** or **`KEY_PERIOD` (`.`)**—verify zero conflict with existing bindings) and add it to `SettingsManager.KEYBIND_DEFS` under **Selection / Macro** (full keyboard + `Mouse 3 / 4 / 5` + Clear support).

* **Cycler Logic (`SelectionController`):**

  * Collect all living, constructed (`is_constructed == true`, `not is_salvaging`) friendly military production structures (`Cloning Vat`, `Calibration Foundry`, `Synthetics Fabricator`) belonging to `TeamManager.get_local_human_team()` whose `ProductionComponent` queue is empty.

  * Pressing `cmd_select_idle_production` (or clicking the HUD pill) cycles through the list deterministically, selecting the next idle structure and playing the single-winner building audio cue; pressing again quickly (or double-clicking the HUD pill) centers `RTSCamera` on that building.

  * Holding `Shift` while pressing `cmd_select_idle_production` selects **all** idle military production buildings at once so you can immediately queue units across all of them!

* **Compact HUD Pill (`ui/hud/resource_hud.tscn` & `.gd`):**

  * Place a sleek clickable button (`IDLE PROD: 2`) beside the Idle Worker and Army Count badges in `ResourceHUD` (automatically hidden when count is `0` or in Spectator Mode, and styled in warm amber/cyan so it never crowds `1280×720`).

### C.2 Bandwidth Near-Cap Warning (`ui/hud/resource_hud.gd`, `scripts/systems/audio_manager.gd`)

* Upgrade the Bandwidth counter in `ResourceHUD` to a clean 3-state visual indicator:

  * **Normal (`used < cap - 2`):** Standard Technozen white/cyan.

  * **Near-Cap (`used >= cap - 2` and `used < cap`, with `cap > 0`):** Soft warm amber pulse (`#F59E0B`) + a single subtle, non-intrusive telemetry warning chime in `AudioManager` when crossing into Near-Cap (throttled with a `20.0s` cooldown and reset once `used < cap - 2` again).

  * **At / Over-Cap (`used >= cap`):** Existing crimson pulse highlight.

### C.3 Unit Arrival Soft-Settling (`scripts/units/movement_component.gd`)

* **Eliminate Destination Micro-Jostling:**

  * Track a lightweight `_settle_timer: float = 0.0` on `MovementComponent` during `MOVING` (non-attack-move / non-gather arrival).

  * When a unit is within a generous settling band (`distance_to_destination <= maxf(arrival_radius * 2.5, unit_radius * 3.5)`) and its net displacement over the last `0.25s` is minimal (`< 8.0 px`) because friendly settled units (`IDLE` / `HOLD_POSITION`) are occupying the exact target center via `SpatialGrid`:

    * Increment `_settle_timer`; once `_settle_timer >= 0.30s`, cleanly finalize the move order (`stop_navigation()`, clear `_settle_timer`, and advance `command_queue` or enter `IDLE`).

  * Reset `_settle_timer = 0.0` immediately whenever a new command is issued, so units remain 100% responsive to fresh micro orders while large squads settle smoothly into tight, calm formations without jittering.

## 5. Phase D: Crisp Match-Start Boot Sequence (`scripts/systems/match_manager.gd`, `scripts/camera/rts_camera.gd`)

* **Skirmish-Only Presentation:** Skip completely on `milestone_0_test.tscn` so sandbox testing remains instantaneous.

* **Lightweight Procedural Boot Overlay (`MatchManager` / `CanvasLayer`):**

  * On skirmish map launch (`skirmish_arena_01`, `02`, `03`):

    * Immediately snap `RTSCamera` smoothly to the local player's starting `Nexus Vat` (or the central `Data Hyper-Uplink` in Spectator Mode) before the first visible frame.

    * Render a sleek, non-blocking `CanvasLayer` overlay (`mouse_filter = MOUSE_FILTER_IGNORE` after `0.25s` so early APM clicks are never eaten):

      * Starts with a brief deep-slate Technozen veil (`alpha 0.85 → 0.0` over `1.1s`) and a crisp horizontal scanline sweep + slim centered terminal banner (`// NEURAL LINK ONLINE — GENESIS_V2` or `// SPECTATOR LINK ONLINE`) that fades out smoothly over `1.2s` and frees itself cleanly.

      * Coincides with the 3 starting workers fanning out to their local `BiomassNode`s, making every match opening feel polished and intentional.

## 6. File & Architecture Summary

### Existing Files to Extend

* `project.godot` & `scripts/systems/settings_manager.gd`: Register `cmd_select_idle_production` (rebindable keyboard + Mouse 3/4/5).

* `scripts/controllers/selection_controller.gd`, `scripts/units/unit.gd`, `scripts/buildings/building.gd`, `scripts/world/resource_node.gd`, `scripts/world/destructible_barricade.gd`, `scripts/world/salvage_core.gd`, `ui/overlays/entity_visuals.gd`: Unified hover pre-highlight tracking & color-coded rings, active vs. idle building conduit animations, and `0.25s` unit spawn-in materialization transitions.

* `ui/hud/selection_hud.gd`, `scripts/buildings/production_component.gd`, `ui/hud/production_ticker.gd`: `Shift + Click` ×5 load-balanced queueing and `Right-Click` direct cancel/refund on `ProductionTicker`.

* `ui/overlays/command_queue_overlay.gd`: Order-type color-coded waypoint segments + directional chevrons.

* `ui/overlays/combat_vfx.gd`, `ui/overlays/rally_point_overlay.gd`, `scripts/controllers/command_router.gd`: Building completion perimeter flash & rally-point ground ripple ring.

* `ui/hud/minimap.gd`: Distinct iconography for Command Hubs, structures, heavy units (triangles), infantry/workers, `SalvageCore`s, and `DestructibleBarricade`s.

* `ui/hud/resource_hud.tscn`, `ui/hud/resource_hud.gd`, `scripts/systems/audio_manager.gd`: Clickable `IDLE PROD` cycler pill & Bandwidth Near-Cap amber pulse + throttled warning chime.

* `scripts/units/movement_component.gd`: Smooth squad arrival soft-settling without destination micro-jostling.

* `scripts/systems/match_manager.gd` & `scripts/camera/rts_camera.gd`: Crisp `~1.2s` Technozen match-start boot fade centered on the starting `Nexus Vat`.

## 7. Verification Checklist for `agy`

Before concluding Milestone 2.5.3, verify in Godot (`skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, `skirmish_arena_03.tscn`, and `milestone_0_test.tscn`):

* \[ \] **Hover Pre-Highlights:** Sweep the cursor over friendly units, enemy units, buildings, `BiomassNode`s, `DestructibleBarricade`s, and `SalvageCore`s; verify crisp color-coded hover rings appear immediately and clear cleanly when moving off, drag-boxing, or opening menus.

* \[ \] **Shift-Click ×5 & Ticker Cancel:** Select 2 `Cloning Vats`, `Shift + Left-Click` **Clone Trooper**, and verify 5 batches distribute evenly across both vats; then `Right-Click` a row in `ProductionTicker` and confirm it cancels the queued item with a 100% resource refund.

* \[ \] **Color-Coded Shift-Queue Waypoints:** Queue a worker to Move → Build → Gather and a squad to Move → Attack-Move → Patrol; verify distinct cyan/amber/emerald/crimson/azure segments with crisp directional chevrons.

* \[ \] **Active vs. Idle Buildings & Transitions:** Observe a `Cloning Vat` and `Synthetics Fabricator` while idle vs. actively training; confirm unmistakable conduit pulsing/sparks while active vs. dim standby when idle. Verify newly spawned units play the `0.25s` scale-pop/flash, finished buildings flash on completion, and updating a rally point spawns a crisp ground ripple.

* \[ \] **Minimap Iconography:** Spawn a `Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`, `Clone Trooper`, `SalvageCore`, and `DestructibleBarricade`; verify Command Hubs show bordered squares, heavy units show crisp triangles, and barricades/salvage read clearly on `TacticalMinimap`.

* \[ \] **Idle Production Cycler & Bandwidth Near-Cap:** Build 2 idle `Cloning Vats`, verify the `IDLE PROD: 2` badge appears, test clicking and pressing the hotkey (plus `Shift + Hotkey` to select all idle production buildings). Train units until within `2` of Bandwidth cap and confirm the amber Near-Cap pulse + single soft chime trigger before hitting crimson cap.

* \[ \] **Squad Soft-Settling & Boot Sequence:** Move a 16-unit squad to a single point and confirm units settle smoothly without jittering/jostling; launch a fresh skirmish and verify the `~1.2s` Technozen boot fade opens smoothly on your starting `Nexus Vat` as your 3 workers fan out, with zero Godot Debugger errors.