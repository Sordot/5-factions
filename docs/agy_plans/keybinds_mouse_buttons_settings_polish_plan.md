# Milestone 1.8 Plan: Mouse Side-Button Keybinds & Settings / Menu Polish Pass

**Target Directory:** `docs/agy_plans/19_keybinds_mouse_buttons_and_settings_polish.md`
**Primary Files:** `scripts/systems/settings_manager.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd`, `scripts/camera/rts_camera.gd`, `scripts/controllers/selection_controller.gd`, `scripts/systems/audio_manager.gd`
**Reference Docs:** `docs/agy_plans/rts_micro_shortcuts_settings_menu_plan.md`, `docs/agy_plans/fullscreen_scaling_and_technical_cleanup.md`, `docs/technical_glossary_and_specs.md`

---

## 1. Objective & Scope

Upgrade the `SettingsManager` and `SettingsMenu` architecture from keyboard-only bindings to a full RTS-grade input and configuration suite. This pass adds native **Mouse 4 / Mouse 5 (and Mouse 3)** rebinding support, exposes remaining command-card/subgroup hotkeys, introduces cursor confinement and camera ergonomics for multi-monitor play, adds a dedicated **Gameplay / HUD** settings tab, and polishes **Display** and **Audio** controls—while keeping all UI cleanly sized for the `1280×720` `canvas_items` viewport in both Windowed and Fullscreen modes.

### In Scope

1. **Mouse Side-Button Keybind Support (`Mouse 4`, `Mouse 5`, `Mouse 3`):**
   * Upgrade `SettingsManager` to store and apply both `InputEventKey` and `InputEventMouseButton` bindings (`MOUSE_BUTTON_XBUTTON1` → **Mouse 4**, `MOUSE_BUTTON_XBUTTON2` → **Mouse 5**, `MOUSE_BUTTON_MIDDLE` → **Mouse 3**), while remaining backward-compatible with existing integer keycodes saved in `user://settings.cfg`.
   * Update `SettingsMenu` keybind capture to accept `Mouse 4`, `Mouse 5`, and `Mouse 3` clicks while explicitly blocking `MOUSE_BUTTON_LEFT`, `MOUSE_BUTTON_RIGHT`, and scroll-wheel ticks so core RTS selection and right-click smart orders can never be accidentally overwritten.
   * Audit all gameplay input handlers (`selection_controller.gd`, `rts_camera.gd`, `command_router.gd`, `settings_manager.gd`, `minimap.gd`, `pause_menu.gd`) so rebound actions work identically whether triggered by a keyboard key or a mouse side button.
2. **Controls Tab Quality-of-Life:**
   * Expose the full **Ability / Command Card Grid** (`Q / W / E / R / T / Y / F` or equivalent `project.godot` actions) and **Cycle Subgroup** (`Tab`) inside `SettingsManager.KEYBIND_DEFS` so every active match hotkey is rebindable in one place.
   * Add an **Unbind / Clear** button (`X` or pressing `Delete`/`Backspace` during capture—with a clear prompt) per keybind row, plus clean **Conflict Resolution** (automatically clearing or swapping a duplicate binding and highlighting the change).
3. **Camera & Multi-Monitor Ergonomics (`Camera` Tab):**
   * **Confine Cursor to Window (`confine_cursor: bool`):** Locks the cursor inside the game window (`Input.MOUSE_MODE_CONFINED`) during active match play for smooth edge-panning on multi-monitor setups, and automatically releases to `Input.MOUSE_MODE_VISIBLE` whenever `MainMenu`, `PauseMenu`, `SettingsMenu`, or `MatchEndOverlay` is open—or when the application loses OS focus.
   * **Invert Zoom (`invert_zoom: bool`):** Flips mouse-wheel zoom in/out direction.
   * **Middle-Mouse Drag Speed (`middle_drag_speed: float`):** Adjustable sensitivity multiplier for middle-click camera panning.
4. **New `Gameplay` Tab in `SettingsMenu`:**
   * **Health Bar Display Mode (`health_bar_mode: int`):** `0 = Damaged / Selected` (default), `1 = Always On`, `2 = Selected Only`—wired directly into `unit.gd` and `building.gd` rendering.
   * **Tactical Alert Toasts (`show_alert_toasts: bool`):** Toggle on-screen HUD toast popups for camera bookmark saves and tactical alert jumps.
5. **Display & Audio Polish (`Display` & `Audio` Tabs):**
   * **V-Sync (`vsync_enabled: bool`):** Toggles `DisplayServer.VSYNC_ENABLED` vs. `DisplayServer.VSYNC_DISABLED`.
   * **FPS Cap (`fps_cap: int`):** Dropdown for `60`, `120`, `144`, or `Unlimited` (`0`), applied via `Engine.max_fps`.
   * **Corner FPS Counter (`show_fps_counter: bool`):** Lightweight, non-intrusive Technozen FPS readout pinned to the top-right/corner when enabled.
   * **Mute Audio When Unfocused (`mute_when_unfocused: bool`):** Automatically mutes `AudioManager` on `NOTIFICATION_APPLICATION_FOCUS_OUT` and restores previous volume/mute state on `NOTIFICATION_APPLICATION_FOCUS_IN`.

### Out of Scope
* Gamepad/controller bindings or mouse-button chord combinations (e.g., `Mouse 4 + Mouse 5`).
* Rebinding Left-Click (Select) or Right-Click (Context Order).
* Gameplay balance or faction content changes.

---

## 2. Detailed Technical Specifications

### 2.1 Unified Keyboard & Mouse-Button Binding Format (`scripts/systems/settings_manager.gd`)
* **Typed Binding Encoding (`user://settings.cfg`):**
  * Store each binding as a string in `[keybinds]`:
    * Keyboard: `"key:80"` (using `Key` enum value)
    * Mouse Button: `"mouse:8"` (`MOUSE_BUTTON_XBUTTON1`), `"mouse:9"` (`MOUSE_BUTTON_XBUTTON2`), `"mouse:3"` (`MOUSE_BUTTON_MIDDLE`)
    * Unbound: `"none"`
  * **Backward Compatibility:** When loading `user://settings.cfg`, if a saved value is a raw integer (from Milestone 1.6), automatically parse it as `"key:<int>"` without crashing or wiping user settings.
* **Helper API on `SettingsManager`:**
  * `set_action_keybind(action_name: StringName, keycode: Key) -> void`
  * `set_action_mouse_bind(action_name: StringName, button_index: MouseButton) -> void`
  * `clear_action_bind(action_name: StringName) -> void`
  * `get_action_display_label(action_name: StringName, compact: bool = false) -> String`:
    * Full labels for `SettingsMenu`: `"Mouse 4"`, `"Mouse 5"`, `"Mouse 3"`, `"Space"`, `"Unbound"`, etc.
    * Compact labels for `SelectionHUD` command card badges: `"M4"`, `"M5"`, `"M3"`, `"SPC"`, `""`.
  * `apply_input_map()`: Clears and rebuilds `InputMap` events for each managed action using `InputEventKey` or `InputEventMouseButton` (preserving any secondary static fallback only where intended, and respecting `"none"` as truly unbound).
* **Action Listener Audit (CRITICAL):**
  * Inspect every script that checks rebindable actions (`selection_controller.gd`, `rts_camera.gd`, `command_router.gd`, `settings_manager.gd`, `minimap.gd`, `pause_menu.gd`).
  * Ensure `event.is_action_pressed(...)` checks are **never** nested inside `if event is InputEventKey:`. If an action like `cmd_select_idle_worker`, `cmd_attack_move`, `cmd_patrol`, `cmd_stop`, `cmd_hold_position`, `jump_base_hub`, `jump_last_alert`, or `cam_bookmark_1..4` is bound to `Mouse 4` or `Mouse 5`, pressing that mouse side button must trigger the action cleanly and call `get_viewport().set_input_as_handled()` so it doesn't leak into ground click handlers.
  * For `cam_bookmark_1..4` bound to `Mouse 4` / `Mouse 5`, ensure `Input.is_key_pressed(KEY_CTRL)` still allows `Ctrl + Mouse 4` to save the bookmark and plain `Mouse 4` to recall it.

### 2.2 Controls Tab Capture, Ability Grid & Conflict Handling (`scripts/ui/settings_menu.gd`)
* **Mouse Button Capture:**
  * While `_capturing_action != &""` inside `_input(event)`:
    * `InputEventKey` (pressed, not echo): `KEY_ESCAPE` cancels capture; `KEY_DELETE` unbinds the action; any other valid non-modifier key binds it.
    * `InputEventMouseButton` (pressed):
      * Allow `MOUSE_BUTTON_XBUTTON1` (`Mouse 4`), `MOUSE_BUTTON_XBUTTON2` (`Mouse 5`), and `MOUSE_BUTTON_MIDDLE` (`Mouse 3`).
      * Explicitly ignore/reject `MOUSE_BUTTON_LEFT`, `MOUSE_BUTTON_RIGHT`, and `MOUSE_BUTTON_WHEEL_*` (showing a brief status hint like `"Left/Right Click and Scroll Wheel are reserved"` while staying in capture mode or cleanly consuming the event).
* **Expanded `KEYBIND_DEFS`:**
  * Group controls cleanly in the Controls scroll list (e.g., **Unit Commands**, **Abilities & Selection**, **Camera & Navigation**, **System**), adding **Cycle Subgroup (`Tab`)** and the **Command Card / Ability Grid** hotkeys (`Q`, `W`, `E`, `R`, `T`, `Y`, `F`) if present in `project.godot` / `SelectionHUD`.
* **Per-Row Clear & Conflict Resolution:**
  * Add a compact `Clear` (`×`) button next to each rebind button so players can unbind any shortcut in one click.
  * If a newly bound key or mouse button is already assigned to another action, automatically unbind (or swap with) the conflicting action and display a subtle Technozen notice (e.g., `"Reassigned [Mouse 4] from Patrol to Idle Worker"`).

### 2.3 Camera Confinement & Ergonomics (`scripts/camera/rts_camera.gd`, `scripts/systems/settings_manager.gd`)
* **Cursor Confinement Lifecycle:**
  * Expose `SettingsManager.set_gameplay_cursor_active(active: bool)` (or centralize cursor mode updates in `SettingsManager`).
  * Set active when entering `skirmish_arena_01.tscn` / `milestone_0_test.tscn`; set inactive whenever `MainMenu`, `PauseMenu`, `SettingsMenu`, or `MatchEndOverlay` is visible, or on `NOTIFICATION_APPLICATION_FOCUS_OUT`.
  * When `confine_cursor == true` and gameplay cursor is active, apply `Input.mouse_mode = Input.MOUSE_MODE_CONFINED`; otherwise apply `Input.mouse_mode = Input.MOUSE_MODE_VISIBLE`.
* **Zoom & Middle-Mouse Pan:**
  * Multiply wheel zoom delta by `-1.0` when `SettingsManager.invert_zoom` is enabled.
  * Scale middle-mouse drag panning in `rts_camera.gd` by `SettingsManager.middle_drag_speed` (default `1.0`, range `0.4`–`2.5`).
  * Note: If the player binds a gameplay action to `Mouse 3` (`MOUSE_BUTTON_MIDDLE`), skip middle-mouse camera dragging so the two don't conflict.

### 2.4 Gameplay / HUD Tab (`scripts/units/unit.gd`, `scripts/buildings/building.gd`, `ui/hud/resource_hud.gd`)
* **Health Bar Display Mode:**
  * `0 (Damaged / Selected)`: Existing behavior—show bar when `is_selected` or `current_hp < max_hp`.
  * `1 (Always On)`: Always draw health bars for visible units and buildings (respecting Fog of War for enemy entities).
  * `2 (Selected Only)`: Only draw health bars for currently selected/inspected entities.
  * When `SettingsManager.settings_changed(&"gameplay")` emits, call `queue_redraw()` on active units/buildings so the change previews immediately mid-match.
* **Tactical Alert Toasts:**
  * Gate bookmark-saved and alert-jump HUD toast banners behind `SettingsManager.show_alert_toasts`.

### 2.5 Display & Audio Polish (`scripts/systems/settings_manager.gd`, `scripts/systems/audio_manager.gd`, `ui/hud/fps_counter.gd`)
* **Display Controls:**
  * Apply `DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)` in `SettingsManager.apply_display_settings()`.
  * Apply `Engine.max_fps = fps_cap` (`60`, `120`, `144`, or `0` for Unlimited).
  * Instantiate or toggle a lightweight `CanvasLayer` corner FPS label (managed by `SettingsManager` so it works on both `MainMenu` and in-match without duplicating nodes in every scene), updating `Engine.get_frames_per_second()` at `0.25s` intervals.
* **Audio Focus Handling:**
  * In `SettingsManager._notification(what)` (or `AudioManager._notification(what)`):
    * On `NOTIFICATION_APPLICATION_FOCUS_OUT`: if `SettingsManager.mute_when_unfocused` is true, set an internal `_unfocused_muted = true` flag on `AudioManager` and mute audio output without overwriting the user's saved `muted` preference.
    * On `NOTIFICATION_APPLICATION_FOCUS_IN`: clear `_unfocused_muted = false` and restore normal volume/mute state (and re-apply `MOUSE_MODE_CONFINED` if in active match gameplay).

---

## 3. File & Architecture Plan

### Existing Files to Extend
* **`scripts/systems/settings_manager.gd`**:
  * Unified keyboard + mouse button (`Mouse 3/4/5`) binding serialization, backward-compatible `user://settings.cfg` loader, `get_action_display_label()`, expanded `KEYBIND_DEFS`, conflict resolution helper, cursor confinement controller, V-Sync / FPS cap / corner FPS counter management, and focus-out/focus-in notification handling.
* **`scenes/ui/settings_menu.tscn` & `scripts/ui/settings_menu.gd`**:
  * Add the 5th tab (`Gameplay`) while keeping all 5 tab buttons cleanly proportioned inside `ModalPanel` at `1280×720`.
  * Upgrade keybind capture to accept `Mouse 3/4/5` and reject LMB/RMB/Wheel, add per-row `Clear (×)` buttons, add **Confine Cursor**, **Invert Zoom**, **Middle-Drag Speed** in `Camera`, **Health Bar Mode** & **Alert Toasts** in `Gameplay`, **V-Sync**, **FPS Cap**, **Show FPS Counter** in `Display`, and **Mute When Unfocused** in `Audio`.
* **`scripts/controllers/selection_controller.gd`, `scripts/camera/rts_camera.gd`, `scripts/controllers/command_router.gd`, `ui/hud/minimap.gd`, `scripts/ui/pause_menu.gd`**:
  * Ensure zero `InputEventKey`-only guards block mouse-button-bound `InputMap` actions; wire cursor confinement hooks on match enter/exit and pause/menu open/close; apply `invert_zoom` and `middle_drag_speed`.
* **`scripts/units/unit.gd` & `scripts/buildings/building.gd`**:
  * Read `SettingsManager.health_bar_mode` when deciding whether to draw HP bars and trigger `queue_redraw()` on `settings_changed(&"gameplay")`.
* **`ui/hud/selection_hud.gd` & `ui/hud/resource_hud.gd`**:
  * Render compact mouse labels (`M4`, `M5`, `M3`) on Command Card / HUD badges via `SettingsManager.get_action_display_label(..., true)` and respect `show_alert_toasts`.
* **`scripts/systems/audio_manager.gd`**:
  * Support temporary focus-loss muting (`set_unfocused_mute(bool)`) cleanly layered over the user's saved mute/volume settings.

---

## 4. Verification Checklist for `agy`

Before concluding Milestone 1.8, verify in Godot (both Windowed `1280×720` and Fullscreen `F11`):

* [ ] **Mouse 4 & Mouse 5 Rebinding:** Open **Settings → Controls**, bind **Select Idle Worker** to `Mouse 4` and **Attack-Move** (or **Jump to Last Alert**) to `Mouse 5`; confirm the UI displays `Mouse 4` / `Mouse 5`, `SelectionHUD` shows `M4` / `M5`, pressing those side buttons mid-match triggers the actions cleanly without leaking clicks to the map, and bindings persist after restarting the game.
* [ ] **Reserved Mouse Input Safety:** While capturing a keybind, click `Left Mouse`, `Right Mouse`, or scroll the wheel; verify none of them overwrite the binding.
* [ ] **Unbind & Conflict Resolution:** Clear a binding with `×` (or `Delete`), then bind two actions to the same key/mouse button; verify the conflict is resolved cleanly with a clear status message.
* [ ] **Cursor Confinement & Camera Ergonomics:** Enable **Confine Cursor to Window**, enter `skirmish_arena_01.tscn`, and verify the mouse stays inside the window for edge-panning—then press `Esc` (`PauseMenu`) or `Alt+Tab` and confirm the cursor immediately releases; verify **Invert Zoom** and **Middle-Mouse Drag Speed** take effect live.
* [ ] **Gameplay, Display & Audio Settings:** Switch **Health Bar Display Mode** between `Always On`, `Selected Only`, and `Damaged / Selected` mid-match and confirm immediate visual updates; toggle **Corner FPS Counter**, **FPS Cap**, **V-Sync**, and **Mute Audio When Unfocused** (test by clicking another desktop window) with zero Godot Debugger errors.