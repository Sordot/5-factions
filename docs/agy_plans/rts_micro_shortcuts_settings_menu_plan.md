# Milestone 1.6 Plan: Classic RTS Micro Shortcuts & Persistent Settings / Keybind Menu

**Target Directory:** `docs/agy_plans/14_rts_micro_shortcuts_and_settings_menu.md`
**Primary Scenes:** `res://scenes/ui/main_menu.tscn`, `res://scenes/maps/skirmish_arena_01.tscn`, `res://scenes/ui/settings_menu.tscn`
**Reference Docs:** `docs/agy_plans/12_idle_worker_command_queues_and_ai_pass.md`, `docs/agy_plans/13_genesis_v2_full_skirmish_integration_and_tuning.md`, `docs/technical_glossary_and_specs.md`

## 1. Objective & Scope

Complete the underlying RTS control ergonomics and configuration architecture before expanding into Factions #2–#5. This pass pairs **Classic RTS Micro & Spatial Shortcuts** with a persistent, data-driven **`SettingsManager` & Settings/Keybind Menu** accessible from both the Main Menu and in-game (`Esc`), ensuring zero hotkey collisions with Godot Editor playtest shortcuts (`F5`, `F6`, `F7`, `F8`).

### In Scope

1. **Centralized `SettingsManager` Autoload (`user://settings.cfg`):**
   * Persist player preferences across sessions using Godot's `ConfigFile` (`user://settings.cfg`).
   * Register and manage all gameplay actions dynamically through Godot's `InputMap` so rebinding any key updates runtime behavior, tooltips, and HUD badges immediately.
   * Provide one-click **Reset to Defaults** per tab or globally.

2. **Technozen Settings & Keybind Menu (`scenes/ui/settings_menu.tscn`):**
   * Reusable modal/overlay styled with `resources/themes/technozen_theme.tres` with four clean tabs:
     * **Controls / Keybinds:** Interactive "Press any key..." rebind buttons for every RTS command, camera shortcut, and control modifier, with duplicate-conflict highlighting and default reset.
     * **Camera:** Edge-Pan Enabled toggle, Edge-Pan Speed slider, Edge-Pan Margin (px) slider, Keyboard Pan Speed slider, and Zoom Speed slider.
     * **Audio:** Master Volume slider, SFX / Combat Volume slider, UI / Alert Volume slider, and Mute All toggle (synced with `AudioManager`).
     * **Display:** Window Mode selector (`Windowed` vs. `Fullscreen` / `Borderless Fullscreen`) and Resolution preset selector when windowed.
   * **Entry Points:**
     * **Main Menu:** Add a **SETTINGS** button on `main_menu.tscn` that opens `settings_menu.tscn`.
     * **In-Match Pause Menu (`Esc`):** Pressing `Esc` during a match first cancels active `BuildGhostPreview` or `AbilityTargetingReticle` modes; if none are active, `Esc` toggles an in-game Pause/Options overlay with **Resume**, **Settings**, **Restart Skirmish**, and **Quit to Main Menu**.

3. **Classic RTS Micro & Spatial Shortcuts:**
   * **Patrol (`P`):** Issues a `PATROL` command (and supports `Shift + P` multi-waypoint patrol loops) where units move continuously between waypoints while engaging enemies encountered along the path.
   * **Stop (`S`):** Immediately halts movement, clears active attack targets, and flushes `command_queue` on selected `Team.PLAYER` units.
   * **Camera Bookmarks (`Ctrl + F1..F4` to Save, `F1..F4` to Recall):** Stores up to 4 world-space camera coordinates per match and jumps smoothly on recall (explicitly avoiding `F5`/`F6`/`F7`/`F8` so Godot Editor testing never collides).
   * **Base Hub Cycle (`Home` or `Backspace`):** Centers the camera on the player's **Nexus Vat** (cycling through multiple Nexus Vats if owned).
   * **Last Alert Jump (`Space`):** Tracks the world position of recent tactical alerts (unit/building attacked, building/upgrade completed, Uplink contested) and jumps the camera there on press (cycling through the last 3 alerts if tapped repeatedly).
   * **Multi-Building Production Distribution:** When multiple friendly production buildings of the same type (e.g., 2–3 **Cloning Vats** or **Synthetics Fabricators**) are selected together, clicking a unit training button automatically assigns the order to the selected building with the shortest active queue.

### Out of Scope
* New factions, units, structures, or upgrades beyond `GENESIS_V2`.
* Gamepad / controller remapping.
* Cloud save synchronization.

---

## 2. Godot-Safe Default Keybind Map

All defaults below avoid `F5` (Run Project), `F6` (Run Current Scene), `F7` (Step Over), and `F8` (Stop Running Project) in Godot 4:

| Action ID (`InputMap`) | Display Label | Default Keybind | Notes |
| :--- | :--- | :--- | :--- |
| `cmd_move` | Move / Smart Order | `Right Mouse` | Standard RTS context order (`Shift` queues). |
| `cmd_attack_move` | Attack-Move | `A` | Enters attack-move cursor mode (`Shift` queues). |
| `cmd_stop` | Stop | `S` | Halts movement, target, and command queue. |
| `cmd_hold_position` | Hold Position | `H` | Toggles `Stance.HOLD_POSITION`. |
| `cmd_patrol` | Patrol | `P` | Enters patrol target mode; loops waypoints (`Shift` queues). |
| `select_idle_worker` | Select Idle Worker | `` ` `` (Backtick) or `Tab` / `Alt+W` | Note: Move Idle Worker default off `F1` (or keep `Backtick` / `I` as default and let player rebind freely) so `F1–F4` are dedicated cleanly to Camera Bookmarks! |
| `jump_base_hub` | Jump to Nexus Vat | `Backspace` | Cycles through owned `Nexus Vat` hubs. |
| `jump_last_alert` | Jump to Last Alert | `Space` | Jumps camera to latest combat/completion alert. |
| `cam_bookmark_1` | Camera Bookmark 1 | `F1` | `Ctrl + F1` saves current camera position. |
| `cam_bookmark_2` | Camera Bookmark 2 | `F2` | `Ctrl + F2` saves current camera position. |
| `cam_bookmark_3` | Camera Bookmark 3 | `F3` | `Ctrl + F3` saves current camera position. |
| `cam_bookmark_4` | Camera Bookmark 4 | `F4` | `Ctrl + F4` saves current camera position. |
| `cam_pan_up` / `down` / `left` / `right` | Camera Pan | `Up/Down/Left/Right` | Rebindable camera pan directions. |
| `toggle_fullscreen` | Toggle Fullscreen | `F11` | Switches between Windowed and Fullscreen. |
| `toggle_aggro_ai` | Toggle Aggro AI (Debug) | `F10` | Preserves existing debug shortcut. |

---

## 3. File & Architecture Plan

### New Files to Create
* **`scripts/systems/settings_manager.gd`** (Autoload singleton registered in `project.godot`)
  * Manages `ConfigFile` load/save at `user://settings.cfg`.
  * Stores Camera settings (`edge_pan_enabled: bool`, `edge_pan_speed: float`, `edge_pan_margin: float`, `keyboard_pan_speed: float`, `zoom_speed: float`), Audio settings (`master_volume: float`, `sfx_volume: float`, `ui_volume: float`, `muted: bool`), Display settings (`fullscreen: bool`, `window_resolution: Vector2i`), and `InputMap` keybind overrides.
  * Emits `settings_changed(category: StringName)` and `keybind_changed(action_name: StringName)` so `RTSCamera`, `AudioManager`, and `SelectionHUD` hotkey labels update live.
* **`scenes/ui/settings_menu.tscn` & `scripts/ui/settings_menu.gd`**
  * Clean Technozen tabbed UI (`Controls`, `Camera`, `Audio`, `Display`) with scroll container for rebind rows, live key-capture modal prompt (`"Press any key (Esc to cancel)..."`), sliders with numeric value readouts, **Apply / Close**, and **Reset Defaults**.
* **`scenes/ui/pause_menu.tscn` & `scripts/ui/pause_menu.gd`**
  * Lightweight in-match overlay triggered by `Esc` (when no targeting reticle or build ghost is active) offering **Resume**, **Settings** (opens `settings_menu.tscn`), **Restart Skirmish**, and **Main Menu**.

### Existing Files to Extend
* **`project.godot`**
  * Register `SettingsManager` autoload before `AudioManager` and `RTSCamera` so saved audio/camera/keybind settings apply immediately on startup.
* **`scripts/camera/rts_camera.gd`**
  * Read `edge_pan_enabled`, `edge_pan_speed`, `edge_pan_margin`, `keyboard_pan_speed`, and `zoom_speed` live from `SettingsManager` (reacting to `settings_changed`).
  * Implement `camera_bookmarks: Dictionary` (`1..4 -> Vector2`): `Ctrl + cam_bookmark_1..4` saves `global_position` (with subtle HUD toast `"Camera Bookmark 1 Saved"`), and `cam_bookmark_1..4` snaps `global_position` to the saved coordinate.
  * Implement `jump_base_hub` (cycles through friendly `Nexus Vat` buildings) and `jump_last_alert` (cycles through the last 3 world positions pushed by an alert tracker).
* **`scripts/systems/audio_manager.gd`**
  * Sync `master_volume`, `sfx_volume`, `ui_volume`, and `muted` state with `SettingsManager`.
* **`scripts/units/unit.gd` & `scripts/controllers/command_router.gd` & `scripts/controllers/selection_controller.gd`**
  * **Stop (`cmd_stop`):** Clear `command_queue`, cancel active movement/build/gather/attack state, and set unit to `IDLE`.
  * **Patrol (`cmd_patrol`):** Add `PATROL` command type to `unit.gd` and `CommandRouter`: stores `patrol_points: Array[Vector2]` (starting from unit's current position + clicked waypoint, plus any `Shift + P` additional waypoints). While patrolling, unit advances through `patrol_points` in a loop, engages enemies entering `aggro_range` (respecting global `Aggro AI`), and resumes the patrol loop once enemies are cleared.
  * **Alert Position Tracking:** Whenever a `Team.PLAYER` unit/building takes damage (throttled per region every `4.0s` to avoid spam) or completes construction/research, record `alert_position` in `MatchManager` / `RTSCamera` for `jump_last_alert` (`Space`).
* **`ui/overlays/command_queue_overlay.gd` & `ui/overlays/move_marker.gd`**
  * Render `PATROL` waypoints with a distinct cyan/gold loop indicator in `CommandQueueOverlay` and `MoveMarker`.
* **`scripts/buildings/production_component.gd` & `ui/hud/selection_hud.gd`**
  * **Multi-Building Production Distribution:** When multiple production buildings are selected in `SelectionController`, route unit queue requests to the selected building capable of training that unit that currently has the fewest items in `production_queue`.
  * **Dynamic Hotkey Labels:** Read active `InputMap` key strings from `SettingsManager` so `SelectionHUD` command cards (`[S] Stop`, `[H] Hold`, `[P] Patrol`, `[A] Attack`) always display the player's rebound keys.
* **`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`**
  * Wire the **SETTINGS** button to instantiate and display `scenes/ui/settings_menu.tscn`.

---

## 4. Verification Checklist for `agy`

Before concluding this milestone, verify in Godot:
* [ ] **Settings Persistence & Rebinding:** Open **Settings** from `MainMenu` and mid-match (`Esc`), rebind `Patrol` or `Stop` to a new key, adjust **Edge-Pan Speed** and **Master Volume**, close and relaunch the game (`F5`), and verify all settings persist in `user://settings.cfg` and update `SelectionHUD` hotkey labels.
* [ ] **Godot Shortcut Safety:** Confirm `F5`, `F6`, `F7`, and `F8` trigger zero unintended in-game actions while testing in the Godot Editor, and that `Ctrl + F1..F4` / `F1..F4` save and recall camera bookmarks cleanly.
* [ ] **Patrol (`P`) & Stop (`S`):** Issue a `Patrol` route (`P` + click, and `Shift + P` multi-point loop) to **Clone Troopers** or **Stingers**; verify they loop continuously, engage enemies along the route, resume patrolling afterward, and halt immediately when `S` (`Stop`) is pressed.
* [ ] **Base & Alert Jumps (`Backspace` & `Space`):** Press `Backspace` to cycle camera focus across owned **Nexus Vats**, and press `Space` after a building completes or a unit takes damage to snap directly to that event's world coordinates.
* [ ] **Multi-Building Queueing:** Box-select 2–3 **Cloning Vats**, click **Clone Trooper** 3 times, and verify the batches distribute evenly across all selected Cloning Vats rather than stacking onto only the first one.