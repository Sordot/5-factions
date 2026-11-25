# Plan 08: RTS Camera Mouse Edge-Panning (Windowed & Fullscreen Safe)

## Objective
Add responsive mouse edge-panning to `scripts/camera/rts_camera.gd` that feels natural in both windowed debug runs and fullscreen play, without causing runaway scrolling when the cursor leaves the game window.

---

## 1. Camera Edge-Panning Logic (`scripts/camera/rts_camera.gd`)
- **Exported Tuning Parameters:**
  - `@export var edge_pan_enabled: bool = true`
  - `@export var edge_margin_px: float = 24.0`
  - `@export var edge_pan_speed: float = 800.0`
  - `@export var scale_speed_with_zoom: bool = true`
- **Window Focus & Viewport Bounds Safety:**
  - Track `_mouse_in_window: bool = true` using `_notification(what)` (`NOTIFICATION_WM_MOUSE_ENTER` and `NOTIFICATION_WM_MOUSE_EXIT`).
  - Only compute edge-pan vectors when `edge_pan_enabled`, `_mouse_in_window`, and `get_window().has_focus()` are all `true`.
  - Compare `get_viewport().get_mouse_position()` against `get_viewport_rect().size`:
    - Left edge (`mouse_pos.x <= edge_margin_px`) -> `dir.x -= 1.0`
    - Right edge (`mouse_pos.x >= viewport_size.x - edge_margin_px`) -> `dir.x += 1.0`
    - Top edge (`mouse_pos.y <= edge_margin_px`) -> `dir.y -= 1.0`
    - Bottom edge (`mouse_pos.y >= viewport_size.y - edge_margin_px`) -> `dir.y += 1.0`
  - Normalize diagonal `dir` so corner scrolling isn't $\sqrt{2}$ faster than cardinal scrolling.
- **Input Blending & Clamping:**
  - Combine keyboard pan (`WASD` / Arrow keys) and mouse edge-pan cleanly (clamped to max speed `1.0` vector length so holding `W` while cursor is at top edge doesn't double speed).
  - Clamp `global_position` directly to configured map bounds so the camera never drifts past limits and delays reversing direction.

---

## 2. Sandbox Toggle & Fullscreen Convenience (`ui/hud/sandbox_debug_panel.gd` & `project.godot`)
- Add a quick toggle in `ui/hud/sandbox_debug_panel.tscn` / `.gd` (and/or `F9` shortcut) for **Edge Pan On/Off** so windowed debugging remains effortless.
- Optional: Add an `Alt+Enter` or `F11` fullscreen toggle in `rts_camera.gd` (or global input) to switch seamlessly between windowed and borderless fullscreen during testing.

---

## 3. Acceptance Criteria
1. Moving the cursor within 24px of any viewport edge smoothly pans the camera in both `milestone_0_test.tscn` and `skirmish_arena_01.tscn`.
2. Moving the mouse completely outside the game window (or Alt-Tabbing out) immediately stops camera movement instead of drifting indefinitely.
3. Diagonal corner panning moves at the same speed as horizontal/vertical edge panning, and holding `WASD` simultaneously does not double the pan speed.