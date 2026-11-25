# Milestone 2.9 Plan: Post-Match Battlefield Inspection, Dynamic Hotkey UX & VFX Pooling Polish

**Target Directory:** `docs/agy_plans/35_match_flow_dynamic_hotkeys_and_pooling_polish.md`
**Primary New Files:** `scenes/ui/controls_reference_overlay.tscn`, `scripts/ui/controls_reference_overlay.gd`, `scripts/systems/vfx_pool.gd`
**Primary Extended Files:** `project.godot`, `ui/hud/match_end_overlay.tscn`, `ui/hud/match_end_overlay.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/fog_of_war.gd`, `scripts/systems/settings_manager.gd`, `ui/hud/selection_hud.gd`, `ui/hud/resource_hud.tscn`, `ui/hud/resource_hud.gd`, `ui/hud/command_tooltip.gd`, `scenes/ui/pause_menu.tscn`, `scripts/ui/pause_menu.gd`, `ui/overlays/attack_tracer.gd`, `ui/overlays/combat_vfx.gd`, `ui/overlays/move_marker.gd`, `ui/overlays/ability_effect.gd`, `scripts/units/combat_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/controllers/command_router.gd`
**Reference Docs:** `docs/agy_plans/34_faction_data_driven_gatekeeper_and_hardening.md`, `docs/agy_plans/28_ffa_arena_lobby_teams_decals_and_camera_feel.md`, `docs/agy_plans/keybinds_mouse_buttons_settings_polish_plan.md`

## 1. Objective & Scope

Execute the final pre-3.0 stability, UX, and performance polish pass so the engine enters **Milestone 3.0 (Faction #2)** rock-solid, responsive, and locked at 60+ FPS even in 4-player late-game battles.

### In Scope

1. **Post-Match "Inspect Battlefield" & One-Click Rematch (`MatchEndOverlay`, `MatchManager`, `FogOfWar`):**

   * Add a **"View Battlefield"** button on `MatchEndOverlay` that dismisses the scoreboard modal into a compact floating top-center banner (`[ Return to Scoreboard ]` | `[ Rematch ]` | `[ Main Menu ]`), pauses simulation cleanly, lifts Fog of War across the entire arena, and unlocks free `RTSCamera` panning/zooming + read-only entity inspection so you can study enemy bases, economy saturation, and battle scars.

   * Add a clean one-click **Rematch** button that resets `Engine.time_scale = 1.0`, clears pooled VFX/state cleanly, and reloads the active skirmish scene while preserving `GameConfig` (`map_id`, `player_count`, `team_preset`, `slot_configs`, factions, and mutators).

2. **Dynamic Hotkey Labels & Quick-Reference Controls Overlay (`SettingsManager`, `SelectionHUD`, `ResourceHUD`, `ControlsReferenceOverlay`):**

   * Audit and unify all HUD badges, command-card key hints, and `CommandTooltip` strings to query a single `SettingsManager.get_action_short_label(action_name)` helper so custom rebinds (including `Mouse 3 / 4 / 5` displayed cleanly as `M3 / M4 / M5`, or empty if cleared) update live the instant Settings change.

   * Create a sleek, `1280×720`-safe **Quick-Reference Controls Card** (`scenes/ui/controls_reference_overlay.tscn`) accessible via `PauseMenu`, a compact `?` icon in `ResourceHUD`, and a rebindable hotkey (`ui_toggle_controls_help`, default **`?` / `KEY_SLASH`** to avoid `F1–F4` camera bookmarks), dynamically displaying the player's current active bindings grouped by category.

3. **VFX & Tracer Object Pooling + 4-Player FFA Stress Hardening (`VFXPool`, `AttackTracer`, `CombatVFX`, `MoveMarker`, `AbilityEffect`):**

   * Introduce a lightweight match-scoped/autoloaded **`VFXPool`** (`scripts/systems/vfx_pool.gd`) that recycles high-frequency ephemeral visual nodes (`AttackTracer`, `MoveMarker`, `AbilityEffect`, and `CombatVFX` bursts/rings) instead of instantiating and `queue_free()`-ing hundreds of nodes per second during 4-team clashes on *Quad Nexus* (`skirmish_arena_03.tscn`) at `2x` speed.

   * Audit and harden cleanup on scene reload / Rematch / return to `MainMenu` so zero freed-instance errors, stuck custom cursors, or leaked timers/tweens occur.

### Out of Scope

* Adding Faction #2 units, buildings, or rosters (begins in Milestone 3.0).

* Replay recording / deterministic lockstep playback.

* Changing core balance numbers or AI tactical rules.

## 2. Phase A: Post-Match "Inspect Battlefield" & One-Click Rematch

### A.1 Post-Match Inspection State (`scripts/systems/match_manager.gd`, `scripts/systems/fog_of_war.gd`)

* Add `var is_inspecting_post_match: bool = false` on `MatchManager`.

* Expose `enter_post_match_inspection() -> void` and `exit_post_match_inspection() -> void`:

  * **On Enter:**

    * Keep match simulation paused (`get_tree().paused = true` or simulation frozen) while setting `RTSCamera`, `TacticalMinimap`, and read-only entity inspection (`SelectionController` left-click inspect only—all unit/building commands blocked) to `PROCESS_MODE_ALWAYS` or cleanly active during post-match inspection.

    * Set `FogOfWar.set_post_match_reveal(true)` so the entire arena (all bases, structures, units, and battle scars) is immediately visible.

    * Reset any active custom targeting cursor (`Input.set_custom_mouse_cursor(null)`).

  * **On Exit (Return to Scoreboard):**

    * Re-open `MatchEndOverlay` cleanly without losing `timeline_samples` or summary statistics.

### A.2 `MatchEndOverlay` Inspection Banner & Rematch (`ui/hud/match_end_overlay.tscn` & `.gd`)

* **Modal Footer Buttons (`1280×720` Safe):**

  * **`View Battlefield`**: Hides the central scoreboard panel, calls `MatchManager.enter_post_match_inspection()`, and shows a slim, non-intrusive floating top-center Technozen bar (`POST-MATCH INSPECTION` • `[ Scoreboard ]` • `[ Rematch ]` • `[ Main Menu ]`).

  * **`Rematch`**: Guarantees `Engine.time_scale = 1.0`, `get_tree().paused = false`, clears `VFXPool`, resets `MatchManager` / `EconomyManager` / `UpgradeManager` / `SpatialGrid`, and calls `get_tree().reload_current_scene()` with all `GameConfig` settings preserved verbatim.

  * **`Main Menu`**: Performs the same clean state/time-scale/pool reset and transitions to `scenes/ui/main_menu.tscn`.

* Pressing `Esc` while in **View Battlefield** mode cleanly toggles back to the Scoreboard modal rather than opening `PauseMenu`.

## 3. Phase B: Dynamic Hotkey Tooltips & Quick-Reference Controls Overlay

### B.1 Canonical Short-Label Formatter (`scripts/systems/settings_manager.gd`)

* Add `func get_action_short_label(action_name: StringName) -> String`:

  * Reads the active `InputMap.action_get_events(action_name)` primary binding and formats it concisely for tight HUD pills and command-card corners:

    * Standard keys: `"A"`, `"S"`, `"F9"`, `"Tab"`, `"Space"`, `"["`, `"]"`, `"?"`

    * Mouse buttons: `"M3"`, `"M4"`, `"M5"` (with full names `"Mouse 4"` / `"Mouse 5"` available via `get_action_display_label(action_name)` for tooltips and the Controls Card).

    * Unbound actions: returns `""` (so HUD buttons cleanly omit empty `[]` brackets).

* Emit `settings_changed.emit(&"controls")` whenever any keybind is updated, cleared, or reset to defaults.

### B.2 Live HUD & Tooltip Synchronization (`selection_hud.gd`, `resource_hud.gd`, `command_tooltip.gd`)

* Connect `SelectionHUD` and `ResourceHUD` to `SettingsManager.settings_changed` (`&"controls"`):

  * Dynamically update all command-card button key badges (`Attack-Move`, `Patrol`, `Defensive`, `Hold Position`, `Stop`, `Cancel/Salvage`, and unit/building abilities) and `CommandTooltip` text—removing any remaining hardcoded `[A]`, `[F9]`, `[U]`, or `[;]` strings.

  * Dynamically update `ResourceHUD` badge labels (`ARMY [F9]`, `IDLE WORKER`, `IDLE PROD`, `TECH [U]`, `HELP [?]`) so rebinding e.g. `Select All Army` to `Mouse 4` immediately displays `ARMY [M4]`.

### B.3 Quick-Reference Controls Overlay (`scenes/ui/controls_reference_overlay.tscn` & `.gd`)

* **Access Points:**

  * Register `ui_toggle_controls_help` in `project.godot` and `SettingsManager.KEYBIND_DEFS` (default **`KEY_SLASH` (`?`)**, fully rebindable).

  * Add a compact `?` button beside `TECH [U]` in `ResourceHUD` and a **"Controls Reference"** button in `PauseMenu`.

  * Pressing `Esc` or `ui_toggle_controls_help` closes the modal cleanly (auto-closing `TechTreeOverlay` if open so modals never stack).

* **Clean 2-Column Layout (`1280×720` Safe):**

  * Centered Technozen modal auto-populated live from `SettingsManager` (zero hardcoded keybind text!) organized into compact, scannable groups:

    1. **Selection & Control Groups** (`Ctrl+1–9`, `Alt+1–9` Steal, `Tab` Subgroups, `Select All Army`, `Idle Worker`, `Idle Production`, `Smart Box-Select Toggle`).

    2. **Combat & Orders** (`Attack-Move` + current `Quick-Cast / Click-to-Confirm` mode note, `Patrol`, `Defensive`, `Hold Position`, `Stop`, `Shift` Queue, `Shift+Click ×5` Train).

    3. **Camera & Interface** (`WASD` / Edge-Pan, `F1–F4` Bookmarks, `Space` Last Alert, `[` / `]` Speed, `U` Tech Tree, `Alt` Snap Invert).

  * Include a bottom-right **`Open Full Keybind Settings →`** shortcut button that jumps directly to **Settings → Controls**.

## 4. Phase C: VFX & Tracer Object Pooling + 4-Player FFA Stress Hardening

### C.1 Lightweight `VFXPool` (`scripts/systems/vfx_pool.gd`)

Register `VFXPool` as an autoload (or match-scoped singleton cleared automatically on scene change) to eliminate repetitive `Node.new()` / `queue_free()` GC churn during large battles:

* **Pooled Ephemeral Types (with sensible caps so memory stays flat):**

  * **`AttackTracer` (`ui/overlays/attack_tracer.gd`):** Pool up to `96` tracer instances. Add `reset_for_pool(...)` and `recycle()` methods; when a tracer finishes its fade/travel, it hides (`visible = false`, `set_process(false)`) and returns to `VFXPool` instead of calling `queue_free()`.

  * **`CombatVFX` (`ui/overlays/combat_vfx.gd`):** Pool explosion bursts, splash telegraphs, repair/salvage sparks, and completion ripples (up to `64` active; oldest recycled gracefully if saturated).

  * **`MoveMarker` (`ui/overlays/move_marker.gd`):** Pool up to `24` ground command markers.

  * **`AbilityEffect` (`ui/overlays/ability_effect.gd`):** Pool up to `24` AoE ability rings/pulses.

* **Scene-Transition Safety:**

  * Connect `VFXPool` to tree/scene cleanup (`clear_pool()` called before scene reload, Rematch, or returning to `MainMenu`) so zero orphaned or freed-parent nodes ever carry over between matches.

  * Reparent/attach active pooled nodes to a single dedicated `VFXLayer` container in the active match scene (falling back gracefully if not present on `milestone_0_test.tscn`).

### C.2 4-Player FFA Performance & Hygiene Audit

Verify and tighten high-frequency loops under a **4-Way FFA (`skirmish_arena_03.tscn`) at `2x` speed**:

* **`SpatialGrid` & `FogOfWar`:** Confirm zero per-frame large array allocations in hot paths and verify `FogOfWar` cleanly ignores freed units/buildings without warnings.

* **`BattleScarsOverlay`:** Confirm ring-buffer decal cap (`max_decals = 110`) recycles cleanly with zero unbounded array growth in 15+ minute matches.

* **`SelectionController` & `AudioManager`:** Confirm custom mouse cursors always reset to `null` on match end, Rematch, and Main Menu return, and verify `AudioManager`'s 10-voice combat pool and Master limiter stay clean at `2x` speed.

## 5. File & Architecture Summary

### New Files to Create

* `scenes/ui/controls_reference_overlay.tscn` & `scripts/ui/controls_reference_overlay.gd` (Dynamic, 2-column Technozen quick-reference card reflecting live `SettingsManager` keybinds)

* `scripts/systems/vfx_pool.gd` (Reusable object pool for `AttackTracer`, `CombatVFX`, `MoveMarker`, and `AbilityEffect` with safe scene-change teardown)

### Existing Files to Extend

* `project.godot`: Register `VFXPool` autoload (if autoloaded) and `ui_toggle_controls_help` (`?` / `KEY_SLASH`) input action.

* `ui/hud/match_end_overlay.tscn`, `ui/hud/match_end_overlay.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/fog_of_war.gd`: **View Battlefield** post-match inspection mode, floating inspection banner, full Fog-of-War lift, and clean one-click **Rematch**.

* `scripts/systems/settings_manager.gd`, `ui/hud/selection_hud.gd`, `ui/hud/resource_hud.tscn`, `ui/hud/resource_hud.gd`, `ui/hud/command_tooltip.gd`, `scenes/ui/pause_menu.tscn`, `scripts/ui/pause_menu.gd`: `get_action_short_label()`, live dynamic HUD/tooltip keybind refresh, and `?` / Pause Menu controls-card entry points.

* `ui/overlays/attack_tracer.gd`, `ui/overlays/combat_vfx.gd`, `ui/overlays/move_marker.gd`, `ui/overlays/ability_effect.gd`, `scripts/units/combat_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/controllers/command_router.gd`: Route ephemeral visual effects through `VFXPool` with clean `reset_for_pool()` / `recycle()` lifecycles.

## 6. Verification Checklist for `agy`

Before concluding Milestone 2.9 (and opening Milestone 3.0), verify in Godot (`skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, `skirmish_arena_03.tscn`, and `milestone_0_test.tscn`):

* \[ \] **Post-Match "View Battlefield" & One-Click Rematch:** Finish a quick skirmish (or `2x` Spectator match); click **`View Battlefield`** on `MatchEndOverlay`, confirm Fog of War lifts completely, pan/zoom freely across all bases, left-click enemy buildings/units to inspect stats cleanly (while confirming no orders can be issued), press `Esc` or **`Scoreboard`** to return to the Summary/Timeline modal, then click **`Rematch`** and verify the exact same map, player count, teams, and mutators reload cleanly at `1.0x` speed with zero stale VFX or errors.

* \[ \] **Dynamic Hotkey Labels & Quick-Reference Card (`?`):** Rebind `Select All Army` to `Mouse 4` and `Attack-Move` to `Q` in **Settings → Controls**; confirm `ResourceHUD` immediately updates to `ARMY [M4]`, `SelectionHUD` command cards and tooltips update live to `[Q]`, and pressing `?` (or clicking the HUD `?` button) opens the cleanly formatted **Controls Reference** card reflecting the exact custom bindings with zero clipping at `1280×720` and Fullscreen.

* \[ \] **VFX Pooling & 4-Player FFA Stress Test:** Launch a **4-Way FFA (`AI vs AI Spectator`)** on *Quad Nexus* (`skirmish_arena_03.tscn`) at `2x` speed and let it run into late-game heavy clashes (plus a 40v40 Combat Lab stress test); confirm via the Corner FPS Counter that frame pacing stays smooth with zero GC hitches, tracers/explosions/markers recycle cleanly without visual artifacts, and zero freed-instance errors appear in the Godot Debugger across a Rematch and return to `MainMenu`.