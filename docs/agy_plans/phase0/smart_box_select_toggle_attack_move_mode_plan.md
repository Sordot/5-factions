# Milestone 2.4.1 Plan: Opt-In Smart Box-Selection Toggle & Attack-Move Input Mode Setting

**Target Directory:** `docs/agy_plans/26_smart_box_select_and_attack_move_mode.md`
**Primary Files:** `project.godot`, `scripts/systems/settings_manager.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd`, `scripts/controllers/selection_controller.gd`, `ui/overlays/selection_box.gd`, `ui/hud/minimap.gd`, `ui/hud/resource_hud.gd`
**Reference Docs:** `docs/agy_plans/selection_ergonomics_turret_support_analytics_plan.md`, `docs/agy_plans/keybinds_mouse_buttons_settings_polish_plan.md`, `docs/agy_plans/micro_feel_unit_rally_minimap_pings_veterancy_plan.md`

## 1. Objective & Scope

Refine two Milestone 2.4 input behaviors so they never override player muscle memory unexpectedly:

1. **Opt-In Smart Box-Selection (Keybind Toggle + Setting):** Stop silently excluding workers/harvesters/engineers during normal drag-box selection. Default drag-box selection should capture **all** friendly units inside the rectangle, while allowing players to toggle **Combat-Only Box Select** on or off live in-game via a rebindable hotkey (with clear visual feedback on the drag box and a brief HUD toast) and configure the default state in **Settings → Gameplay**.
2. **Attack-Move Input Mode Setting (`Quick-Cast` vs. `Click-to-Confirm`):** Abstract Attack-Move behavior into a persistent setting in **Settings → Gameplay** so players can choose between **Quick-Cast (Instant at Cursor)** (pressing `A` / `cmd_attack_move` immediately Attack-Moves to the mouse cursor) and **Click-to-Confirm (Target Cursor)** (pressing `A` arms the crimson Technozen crosshair cursor and waits for Left-Click).

### In Scope

* **Smart Box-Selection Toggle:**
  * `SettingsManager` persisted boolean `smart_box_select_enabled` (default `false` — selects all friendly units).
  * Rebindable `InputMap` action `cmd_toggle_smart_box_select` (compatible with keyboard keys and `Mouse 3 / 4 / 5`) exposed in **Settings → Controls**.
  * Visual differentiation on `ui/overlays/selection_box.gd` when Combat-Only Box Select is active (distinct amber/crimson border tint vs. standard Technozen cyan) plus a throttled HUD toast (`Combat-Only Box Select: ON / OFF`).
* **Attack-Move Input Mode:**
  * `SettingsManager` enum `AttackMoveMode { QUICK_CAST, CLICK_TO_CONFIRM }` persisted under `[gameplay]` (`attack_move_mode`, default `QUICK_CAST` to preserve instant `A`-move muscle memory).
  * Dropdown in **Settings → Gameplay** labeled **"Attack-Move Input"**:
    * `Quick-Cast (Instant at Cursor)`
    * `Click-to-Confirm (Target Cursor)`
  * Full compatibility with `Shift` command queuing, `SettingsManager.attack_range_mode` (`Show While Targeting`), and minimap Attack-Move clicks.

### Out of Scope

* Changing `Ctrl + Click` / double-click same-type selection or `Alt + 1–9` control group stealing.
* Changing `Patrol (P)` or `Ability Target` cursor modes (keep their existing targeting cursors intact).

---

## 2. Detailed Technical Specifications

### 2.1 `SettingsManager` & `project.godot`

* **`project.godot` (`[input]`):**
  * Declare `cmd_toggle_smart_box_select` (default `KEY_B` or unbound—use **`KEY_B`** if unused by building/ability shortcuts, otherwise **`KEY_QUOTELEFT`** / **`KEY_V`**; verify zero conflict with existing `project.godot` actions before assigning default).
* **`scripts/systems/settings_manager.gd`:**
  * Add enum and properties:
    * `enum AttackMoveMode { QUICK_CAST, CLICK_TO_CONFIRM }`
    * `var attack_move_mode: int = AttackMoveMode.QUICK_CAST`
    * `var smart_box_select_enabled: bool = false`
  * Add `cmd_toggle_smart_box_select` to `KEYBIND_DEFS` under the **Selection / Controls** category so it appears in **Settings → Controls**, supports `Mouse 3 / 4 / 5`, supports `Clear (×)`, and participates in conflict resolution.
  * Persist `attack_move_mode` and `smart_box_select_enabled` under `[gameplay]` in `user://settings.cfg`, include both in `reset_defaults()`, and emit `settings_changed.emit(&"gameplay")` whenever either value changes.
  * Provide a convenience method `toggle_smart_box_select() -> bool` that flips `smart_box_select_enabled`, saves `user://settings.cfg`, emits `settings_changed.emit(&"gameplay")`, and returns the new state.

### 2.2 `SettingsMenu` (`scenes/ui/settings_menu.tscn` & `scripts/ui/settings_menu.gd`)

* Inside the **Gameplay** tab (keeping all rows cleanly inside `ModalPanel` at `1280×720` and Fullscreen):
  * Add an `OptionButton` row labeled **"Attack-Move Input"**:
    * `0`: `Quick-Cast (Instant at Cursor)`
    * `1`: `Click-to-Confirm (Target Cursor)`
  * Add a `CheckButton` / `CheckBox` row labeled **"Combat-Only Box Select"** (with tooltip: *"When ON, drag-box selection ignores workers/harvesters/engineers if combat units are inside the box. Can also be toggled in-game via hotkey."*).
* Sync both controls cleanly on menu open, on `Reset Defaults`, and if `smart_box_select_enabled` was toggled via hotkey during the match.

### 2.3 Opt-In Smart Box-Selection (`scripts/controllers/selection_controller.gd`, `ui/overlays/selection_box.gd`, `ui/hud/resource_hud.gd`)

* **In-Game Hotkey Toggle (`selection_controller.gd`):**
  * Listen for `event.is_action_pressed("cmd_toggle_smart_box_select")` (without an `InputEventKey`-only guard so `Mouse 4 / 5` bindings work identically).
  * Call `var enabled := SettingsManager.toggle_smart_box_select()`.
  * Show a brief HUD toast (`"Combat-Only Box Select: ON"` or `"Combat-Only Box Select: OFF (All Units)"`) if `SettingsManager.show_alert_toasts` is enabled, and play a light UI toggle SFX via `AudioManager`.
  * Call `get_viewport().set_input_as_handled()`.
* **Refined `_select_in_rect()` (`selection_controller.gd`):**
  * Collect all friendly units inside the drag rectangle (`all_unit_hits`) and partition into `combat_hits` and `utility_hits`.
  * **If `SettingsManager.smart_box_select_enabled` is `false` (Default):**
    * Select **`all_unit_hits`** (combat units + workers/harvesters/engineers together), falling back to friendly buildings only if `all_unit_hits` is empty.
  * **If `SettingsManager.smart_box_select_enabled` is `true`:**
    * Select **`combat_hits`** if non-empty; otherwise fall back to `utility_hits`, then friendly buildings.
* **Selection Box Visual Cue (`ui/overlays/selection_box.gd`):**
  * When `SettingsManager.smart_box_select_enabled` is `true`, tint the drag-selection box border/fill subtly warm amber/crimson (e.g., `#F59E0B` border with translucent amber fill) instead of the default Technozen cyan, so the player immediately sees before releasing LMB that Combat-Only filtering is active.

### 2.4 Attack-Move Input Mode (`scripts/controllers/selection_controller.gd`, `ui/hud/minimap.gd`)

* **Handling `cmd_attack_move` (`selection_controller.gd`):**
  * Guard: require at least one selected friendly combat-capable unit (ignore if only buildings/non-combat workers are selected, or preserve existing guard).
  * **When `SettingsManager.attack_move_mode == SettingsManager.AttackMoveMode.QUICK_CAST` (Default):**
    * Do **not** enter `is_attack_move_targeting` or lock the mouse into the red crosshair waiting for a click.
    * Immediately issue `Attack-Move` to `get_global_mouse_position()` (respecting `Shift` to append to the unit's command queue, and checking if the cursor is directly over an enemy unit/building/barricade to issue a smart attack/attack-move cleanly).
    * Trigger the brief `_amove_preview_timer` (e.g., `0.35s`) so `AttackRangeMode.SHOW_WHILE_TARGETING` still flashes the selected units' attack-range ring crisply on press, and spawn the crimson ground `MoveMarker` at the cursor.
  * **When `SettingsManager.attack_move_mode == SettingsManager.AttackMoveMode.CLICK_TO_CONFIRM`:**
    * Enter `is_attack_move_targeting = true`, apply the crimson Technozen crosshair cursor, display live attack-range rings (when `AttackRangeMode` is `SHOW_WHILE_TARGETING` or `ALWAYS_SHOW`), confirm on Left-Click (respecting `Shift` queuing), and cancel cleanly on Right-Click or `Esc`.
* **Safe Mode Switching Mid-Match:**
  * If `SettingsManager.settings_changed(&"gameplay")` fires while `is_attack_move_targeting` is active and the player switches to `QUICK_CAST`, immediately cancel targeting mode and restore the default mouse cursor (`Input.set_custom_mouse_cursor(null)`).
* **Minimap Attack-Move Consistency (`ui/hud/minimap.gd`):**
  * Verify holding/pressing `cmd_attack_move` while clicking on the minimap (or clicking the minimap while `is_attack_move_targeting` is armed in `CLICK_TO_CONFIRM` mode) issues a clean `Attack-Move` to the clicked world coordinate and cancels targeting mode afterward.

---

## 3. File & Architecture Summary

### Existing Files to Extend

* `project.godot`: Register `cmd_toggle_smart_box_select` input action.
* `scripts/systems/settings_manager.gd`: Add `AttackMoveMode` enum, `attack_move_mode` (default `QUICK_CAST`), `smart_box_select_enabled` (default `false`), `toggle_smart_box_select()`, `KEYBIND_DEFS` entry, and `user://settings.cfg` persistence.
* `scenes/ui/settings_menu.tscn` & `scripts/ui/settings_menu.gd`: Add **Attack-Move Input** dropdown and **Combat-Only Box Select** toggle to the **Gameplay** tab.
* `scripts/controllers/selection_controller.gd`: Gate `_select_in_rect()` combat filtering on `SettingsManager.smart_box_select_enabled`, handle `cmd_toggle_smart_box_select`, and branch `cmd_attack_move` cleanly between `QUICK_CAST` and `CLICK_TO_CONFIRM`.
* `ui/overlays/selection_box.gd`: Tint drag-box border/fill amber when `SettingsManager.smart_box_select_enabled` is active.
* `ui/hud/minimap.gd`: Ensure minimap Attack-Move works seamlessly under both `QUICK_CAST` and `CLICK_TO_CONFIRM` modes.

---

## 4. Verification Checklist for `agy`

Before concluding Milestone 2.4.1, verify in Godot (`skirmish_arena_01.tscn` and `milestone_0_test.tscn`):

* [ ] **Default Box Selection Selects Everything:** With default settings (`Combat-Only Box Select: OFF`), drag a box over mixed Workers and Clone Troopers; confirm **all** units inside the box (both Workers and Clone Troopers) are selected.
* [ ] **In-Game Smart Box-Select Toggle:** Press the `Toggle Combat-Only Box Select` keybind (and test rebinding it to `Mouse 4` / `Mouse 5` in **Settings → Controls**); confirm the HUD toast announces `ON`, the drag-selection box renders with its distinct amber tint, and dragging over mixed Workers + Clone Troopers selects only Clone Troopers (falling back to Workers only if no combat units are in the box). Press the keybind again and confirm it returns to selecting all units.
* [ ] **Attack-Move Quick-Cast (Default):** Select Clone Troopers, hover over a point on the map, and press `A` (and `Shift + A` to queue); confirm units immediately Attack-Move to the cursor with zero extra Left-Click required, a red ground marker spawns, and the cursor does not get stuck as a crosshair.
* [ ] **Attack-Move Click-to-Confirm:** Open **Settings → Gameplay**, switch **Attack-Move Input** to `Click-to-Confirm (Target Cursor)`; press `A` and confirm the crimson Technozen crosshair appears with live range rings, Left-Click confirms the Attack-Move, Right-Click/`Esc` cancels and restores the normal cursor, and both settings persist across restarts in `user://settings.cfg`.
* [ ] **Minimap & Debugger Hygiene:** Test minimap Attack-Move under both modes and verify zero Godot Debugger errors or stuck custom mouse cursors.