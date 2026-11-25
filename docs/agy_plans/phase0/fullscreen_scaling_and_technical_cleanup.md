# Milestone 1.6.1 — Fullscreen Scaling Fix & Codebase Technical Cleanup

## 1. Objective
Resolve the fullscreen edge-cutoff and Windows taskbar overlap bug observed on `MainMenu` and in-game HUDs, unify fullscreen toggling through `SettingsManager`, and clean up verified input/layout/legacy regressions uncovered during the Milestone 1.6 code audit before proceeding to Milestone 1.7 (`15_map_landmarks_depth_and_zone_removal.md`).

---

## 2. Verified Fixes & Scope

### 2.1 Base Viewport & Stretch Configuration (`project.godot`)
* Add explicit base viewport dimensions under `[display]` so `canvas_items` stretch mode scales from `1280×720` instead of Godot's default `1152×648`:
  * `window/size/viewport_width=1280`
  * `window/size/viewport_height=720`
  * `window/stretch/mode="canvas_items"`
  * `window/stretch/aspect="expand"`
* Register the three runtime-only `InputMap` actions in `project.godot` `[input]` so scenes launched directly in the editor never hit missing-action errors:
  * `cmd_patrol` (`P`)
  * `jump_base_hub` (`Backspace` + `Home`)
  * `jump_last_alert` (`Space`)

### 2.2 Clean Window Mode Switching (`scripts/systems/settings_manager.gd`)
* Refactor `apply_display_settings()` to avoid double-setting `Window.mode` and `DisplayServer.window_set_mode()` in the same frame, and stop setting `win.borderless = true` on `MODE_FULLSCREEN` (which triggers Windows 11 DWM overscan and taskbar overlap):
  * **Windowed (`window_mode == 0`):**
    * Set `win.mode = Window.MODE_WINDOWED`
    * Set `win.borderless = false`
    * Set `win.size = window_resolution`
    * Center the window cleanly on the active monitor (`DisplayServer.screen_get_usable_rect()`).
  * **Borderless Fullscreen (`window_mode == 1`):**
    * Set `win.borderless = false`
    * Set `win.mode = Window.MODE_FULLSCREEN` (Godot 4's native borderless fullscreen).
  * **Exclusive Fullscreen (`window_mode == 2`):**
    * Set `win.borderless = false`
    * Set `win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN`.
* Add a helper `toggle_fullscreen() -> void` on `SettingsManager` that toggles between `window_mode == 0` (Windowed) and `window_mode == 1` (Borderless Fullscreen), applies display settings, saves `user://settings.cfg`, and emits `settings_changed.emit(&"display")`.
* Handle `camera_toggle_fullscreen` (`F11`) and `Alt+Enter` inside `SettingsManager._input(event)` (skipping when `SettingsMenu` is actively capturing a keybind) so fullscreen toggling works consistently on `MainMenu`, `SettingsMenu`, `PauseMenu`, and during skirmishes.

### 2.3 Sync `RTSCamera` With `SettingsManager` (`scripts/camera/rts_camera.gd`)
* Remove duplicate `DisplayServer.window_set_mode()` logic in `RTSCamera.set_fullscreen()` / `toggle_fullscreen()` and delegate directly to `SettingsManager.toggle_fullscreen()` / `SettingsManager.set_display_settings(...)`.
* Listen for `SettingsManager.settings_changed(&"display")` so `fullscreen_toggled` signals and camera bounds/edge-pan coordinates stay synchronized after any display mode switch.

### 2.4 Responsive UI Margin & Overflow Audit (`scenes/ui/main_menu.tscn`, `scenes/ui/settings_menu.tscn`, `ui/hud/*.tscn`)
* **`scenes/ui/main_menu.tscn`:**
  * Verify `RootMargin` fits cleanly inside `1280×720` with comfortable breathing room (tighten `RootMargin` from `32/24` to `24/18` and `RootVBox`/`ConfigVBox` separations slightly so `BtnQuit` and `HeaderPanel` never clip at `1280×720`, `1920×1080`, or `2560×1440`).
  * Ensure `MainMenu` and `RootMargin` use `Full Rect` anchors (`anchor_right = 1.0`, `anchor_bottom = 1.0`) with zero hardcoded positive offsets.
* **`scenes/ui/settings_menu.tscn`:**
  * Ensure `ModalPanel` (`760×540`) stays centered and readable at `1280×720` and fullscreen without clipping buttons or tabs.
* **In-Game HUD (`resource_hud.tscn`, `selection_hud.tscn`, `minimap.tscn`, `sandbox_debug_panel.tscn`):**
  * Confirm top/bottom/corner anchors hold their screen edges cleanly across Windowed (`1280×720`), Borderless Fullscreen, and Exclusive Fullscreen, and that `TacticalMinimap` and `SelectionHUD` never overlap.

### 2.5 Input & Codebase Cleanup Pass
* **`ui/hud/minimap.gd` (Line 116):** Remove the hardcoded `or Input.is_key_pressed(KEY_A)` fallback so minimap Attack-Move strictly respects the player's rebound `cmd_attack_move` action.
* **`scripts/ui/pause_menu.gd` (Line 78):** Replace `key_ev.keycode == KEY_ESCAPE` with `event.is_action_pressed("cmd_cancel")` for consistency with `SelectionController`.
* **Legacy Prototype Audit:** Review remaining references to `command_core`, `bio_lab`, `silica_refinery`, `compute_node`, `bandwidth_relay`, `test_unit`, and `enemy_trooper` across `building.gd`, `rts_camera.gd`, `sandbox_spawner.gd`, `subgroup_helper.gd`, `unit_data.gd`, `economy_manager.gd`, `match_manager.gd`, `skirmish_ai.gd`, and `unit.gd`. Keep only what `milestone_0_test.tscn` requires and ensure `GENESIS_V2` (`nexus_vat`, `cloning_vat`, etc.) is always the primary path without dead/redundant checks.
* **Freed-Instance & Signal Safety Spot-Check:** Verify `unit.gd`, `combat_component.gd`, `selection_controller.gd`, and `skirmish_ai.gd` guard all cached node references with `is_instance_valid(...)` across patrol, hold position, and queued orders.

---

## 3. Verification Checklist
1. Launch `scenes/ui/main_menu.tscn` in a **Separate Window** (not embedded in the Godot Editor).
2. Confirm `MainMenu` displays all header elements, all 5 faction dossiers, and `LAUNCH SKIRMISH` / `SETTINGS & KEYBINDS` / `EXIT TO DESKTOP` with zero edge clipping at `1280×720`.
3. Press **`F11`** (and test **Borderless Fullscreen** + **Fullscreen** in Settings): confirm all four edges fit inside the monitor, the Windows taskbar is covered properly, and the Settings dropdown stays synced with `F11`.
4. Rebind `Attack-Move` away from `A` in Settings and verify `A` no longer triggers minimap Attack-Move while the new key does.
5. Launch `skirmish_arena_01.tscn`, toggle fullscreen mid-match, verify HUD anchoring and edge-panning on all four monitor edges, and confirm zero Godot Debugger errors.