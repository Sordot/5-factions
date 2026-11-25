# Milestone 1.3 Plan: Aggro AI Toggle & Core RTS Polish Bundle

**Target Directory:** `docs/agy_plans/11_aggro_toggle_and_polish_bundle.md`
**Primary Scene:** `res://scenes/maps/skirmish_arena_01.tscn` (and `res://scenes/test/milestone_0_test.tscn`)
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/skirmish_ai_fog_of_war_expanded_arena_plan.md`

## 1. Objective & Scope

Introduce a runtime **Aggro AI Toggle** so you can pause or resume automated enemy AI behavior and idle unit auto-acquisition during playtesting, bundled with four high-impact quality-of-life and polish upgrades that elevate game feel, visual clarity, and lifecycle stability across `skirmish_arena_01.tscn`.

### In Scope

1. **Aggro AI Toggle (Debug Panel, Hotkey & State Isolation):**
   * Add a global/match-level `aggro_ai_enabled: bool = true` switch accessible via `sandbox_debug_panel.tscn` and a dedicated hotkey (`F10`, avoiding `F6`/`F8` Godot editor shortcuts).
   * When toggled **OFF**:
     * `SkirmishAICommander` pauses attack wave dispatches and aggressive target-seeking.
     * Idle units (`IDLE` / `GUARD`) do **not** automatically acquire or chase nearby targets in `aggro_range`.
     * Explicit player-issued orders (`Right-Click` target attack, `A`-Move, and manual `Q` ability casts) continue to function normally so combat mechanics can be tested on demand in a controlled environment.
   * Display a clear status indicator on `sandbox_debug_panel` (and optional subtle HUD badge when disabled) so you always know whether Aggro AI is active or paused.

2. **Combat Visuals, Hit Feedback & Freed-Instance Lifecycle Cleanup:**
   * Ensure all standard attacks and active abilities spawn crisp `attack_tracer.gd` / `ability_effect.gd` visuals and a brief white/cyan hit-flash shader/modulate pulse on damaged units and buildings.
   * Harden all unit/building death cleanup across `Unit`, `Building`, `CombatComponent`, `SelectionController`, `FogOfWarSystem`, and `EconomyManager`:
     * Guard all stored target references with `is_instance_valid()` before method calls or typed argument passing.
     * On entity death/destruction, immediately prune from active selections, control groups (`1–9`), production/staffing slots, and release reserved/used **Bandwidth**.

3. **Rally Point Visuals & Production Queue Readability:**
   * When a friendly production building (`Nexus Vat` / `CommandCore`, `Cloning Vat` / `BioLab`, `Calibration Foundry`, `Synthetics Fabricator`) is selected/inspected, render a clear world-space rally line and flag/reticle at `rally_position` (color-coded cyan for ground move, green/amber when rallied onto a `ResourceNode` or `Wetware Mainframe`).
   * Ensure `SelectionHUD` clearly displays active production progress bars, batch-cloning badges (`x2` for Cloning Vat), and allows clicking any queued slot (`1–5`) to cancel and refund resources + Bandwidth immediately.

4. **Selection & Context Order Feel (`selection_controller.gd` & `command_router.gd`):**
   * **Double-Click Same-Type Selection:** Double-clicking a friendly unit (or `Ctrl + Left-Click`) selects all living visible `Team.PLAYER` units of that same `unit_type_id` within the current camera viewport.
   * **Distinct Context Markers (`move_marker.gd`):** Color-code right-click confirmation rings by order type—cyan for ground move, red for direct attack/A-move, emerald/amber for resource gather or building staffing/drop-off.

5. **HUD & Arena Objective Readability Pass:**
   * Audit `resource_hud.tscn`, `selection_hud.tscn`, `minimap.tscn`, and `sandbox_debug_panel.tscn` at standard `1280x720` and `1920x1080` resolutions to eliminate any overlapping panels or clipped text.
   * Improve visual readability of the central **Data Hyper-Uplink** (clear capture progress ring + ownership color + `+5% SPEED` status label) and the **Encroaching Zone** (high-contrast warning perimeter ring + countdown/phase banner).

### Out of Scope

* New unit types, buildings, or tech-tree additions beyond `GENESIS_V2` specifications.
* Custom audio tracks or voiceovers.
* Multi-player networking or replay recording.

---

## 2. File & Architecture Plan

### New Files to Create

* `ui/overlays/rally_point_overlay.gd`
  * Lightweight world-space `Node2D` overlay driven by `SelectionController.inspection_changed`: draws a dashed/glowing Technozen line from the inspected friendly production building to its `rally_position` (or `rally_target.global_position`) with an endpoint flag/ring.

### Existing Files to Extend

* `scripts/systems/match_manager.gd` (or `scripts/systems/skirmish_ai.gd` + `scripts/units/combat_component.gd`)
  * Host `@export var aggro_ai_enabled: bool = true` and `signal aggro_ai_toggled(enabled: bool)`.
  * In `SkirmishAICommander._on_decision_tick()`: skip attack wave dispatch and aggressive push logic when `!aggro_ai_enabled`.
  * In `Unit` / `CombatComponent` idle target scanning: skip passive enemy acquisition when `!aggro_ai_enabled` (while preserving `ATTACK_MOVING` and explicit `ATTACKING_TARGET` execution).

* `ui/hud/sandbox_debug_panel.gd` & `ui/hud/sandbox_debug_panel.tscn`
  * Add an **Aggro AI: ON / OFF (`F10`)** toggle button wired to `MatchManager.set_aggro_ai_enabled(...)`, updating button color/text immediately on toggle.

* `scripts/units/unit.gd`, `scripts/units/combat_component.gd`, & `scripts/buildings/building.gd`
  * Audit every target reference (`current_target`, `attack_target`, `attacker`) to enforce `is_instance_valid()` checks before accessing properties or calling typed functions.
  * Add a brief `0.08s` modulate hit-flash on `take_damage()` so combat exchanges read crisply at zoom.

* `scripts/controllers/selection_controller.gd`
  * Implement viewport-bounded same-type selection on **Double-Click** (`event.double_click` on a `Team.PLAYER` unit) or **`Ctrl + Left-Click`**, respecting `Shift` additive selection if held.

* `scripts/controllers/command_router.gd` & `ui/overlays/move_marker.gd`
  * Pass order category (`MOVE`, `ATTACK`, `GATHER`, `INTERACT`) when spawning `MoveMarker` so visual feedback matches the action immediately.

* `scripts/world/hyper_uplink.gd` & `scripts/systems/encroaching_zone.gd`
  * Polish world-space ring drawing (`_draw()`) with crisp capture progress arcs on `HyperUplink` and a clear warning dash/pulse on `EncroachingZone`, plus clean HUD status text.

* `ui/hud/resource_hud.tscn`, `ui/hud/selection_hud.tscn`, & `ui/hud/minimap.tscn`
  * Verify anchor presets, margins, and z-index layering so the Minimap, Selection HUD, Resource HUD, and Sandbox Debug Panel never overlap or block edge-panning corners unintentionally.

---

## 3. Detailed Behavior Specifications

### A. Aggro AI Toggle Behavior Matrix

| State | `Aggro AI = ON` (Default) | `Aggro AI = OFF` (Sandbox / Test Mode) |
| :--- | :--- | :--- |
| **Enemy AI Commander** | Gathers, builds, trains, and dispatches attack waves on schedule. | Pauses attack wave dispatches (optional: keeps passive gathering or pauses all AI commands cleanly). |
| **Idle / Guard Units** | Automatically acquire and engage enemies entering `aggro_range`. | Remain stationary in `IDLE` even if enemies walk within `aggro_range`. |
| **Explicit `A`-Move / Attack** | Acquires and engages targets along path or focused target. | **Still works normally**—allows manual combat testing at any time. |
| **Manual Abilities (`Q`)** | Casts normally. | **Still works normally**. |

### B. Double-Click Same-Type Selection (`selection_controller.gd`)

1. When a single `Left-Click` hits a `Team.PLAYER` `Unit` with `event.double_click == true` (or `Input.is_key_pressed(KEY_CTRL)`):
   * Read `target_type_id = clicked_unit.unit_data.unit_type_id`.
   * Compute the camera's visible world `Rect2` from `RTSCamera`.
   * Gather all living `Team.PLAYER` units inside that visible rect whose `unit_data.unit_type_id == target_type_id`.
   * Replace (or append if `Shift` is held) `selected_units` and emit `selection_changed`.

### C. Rally Point Visualization (`rally_point_overlay.gd`)

1. Listens to `SelectionController.inspection_changed(entity)`.
2. If `is_instance_valid(entity)` and `entity is Building` and `entity.team == Team.PLAYER` and `entity.can_set_rally`:
   * Draws a line from `entity.global_position` to `entity.get_rally_world_position()`.
   * Colors the line & destination marker:
     * **Emerald/Green** if `rally_target` is a `ResourceNode` (`BiomassNode` / `SilicaVein`).
     * **Cyan** if `rally_target` is a friendly `Wetware Mainframe` / `ComputeNode` or ground move point.
3. Hides automatically when inspection switches to a unit, enemy, or empty ground.

---

## 4. Verification Checklist for `agy`

Before concluding this pass, verify in `skirmish_arena_01.tscn`:

* [ ] **Aggro AI Toggle:** Pressing `F10` (or clicking the toggle in `SandboxDebugPanel`) flips `Aggro AI` between `ON` and `OFF`; when `OFF`, idle player and enemy units ignore each other in range and AI waves hold fire, while explicit `A`-move and right-click attacks still execute normally.
* [ ] **Zero Freed-Instance Errors:** Killing units/buildings with overlapping auto-attacks and AoE abilities produces zero `previously freed` runtime errors in the Godot Debugger, and freed Bandwidth updates immediately in `ResourceHUD`.
* [ ] **Rally Point Overlay:** Selecting any friendly production building draws its live rally line and destination marker; right-clicking ground or a `BiomassNode` updates the rally line color and endpoint immediately.
* [ ] **Double-Click Selection & Context Markers:** Double-clicking a `Clone Trooper` or `Worker` selects all matching units visible on screen; right-clicking ground, enemies, and resource nodes spawns color-coded confirmation markers.
* [ ] **HUD & Arena Clarity:** `ResourceHUD`, `SelectionHUD`, `Minimap`, and `SandboxDebugPanel` render cleanly without overlap, and `HyperUplink` / `EncroachingZone` boundaries and states are easy to read during live play.