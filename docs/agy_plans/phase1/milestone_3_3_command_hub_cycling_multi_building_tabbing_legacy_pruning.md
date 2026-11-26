# Milestone 3.3 — Command Hub Cycling, Multi-Building Tab Cycling & Legacy Prototype Pruning

**Prerequisite:** Milestones 3.1 (`39_milestone_3_1_building_hotkeys_and_icon_command_card.md`) and 3.2 (`40_milestone_3_2_full_hud_theming_battlefield_juice_and_biomes.md`) verified.

**Goal:** Deliver three high-impact macro ergonomics and codebase hygiene upgrades before starting Faction #3 (Milestone 4.0):

1. **Command Hub Cycle & Select Hotkey (`Backspace`):** Cycle through all friendly Command Hubs (`Nexus Vat`, `Foundry Core`, and future faction hubs)—**selecting** the hub and centering the camera on it (mirroring `select_next_idle_worker`), so players can immediately queue workers (`Q/W/E`) or fire `Core Overclock` (`F`) across bases without touching the mouse.

2. **Multi-Building `Tab` Subgroup Cycling:** When multiple building types are selected together (via box-select or Control Groups `1–9`, e.g., `Assembly Bay` + `Ballistics Lab` + `Siege Gantry`), allow `Tab` (`ui_cycle_subgroup`) to cycle active building subgroups—updating the 4×3 Icon Command Card, `Q/W/E/R/T/F` building hotkeys, and clickable subgroup tabs in `SelectionHUD` just like mixed unit squads.

3. **Safe Legacy Prototype Pruning:** Migrate any remaining pre-Genesis references in `milestone_0_test.tscn` and core scripts, then cleanly remove obsolete prototype scenes, `.tres` data, `.uid` sidecars, and `encroaching_zone.gd` so the repository is clean ahead of Faction #3.

**Non-Negotiable Constraints:**

* **Strict `1280×720` UI Discipline:** All HUD updates (`SelectionHUD` building subgroup tabs, `SettingsMenu` keybind row, `ControlsReferenceOverlay`) must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).

* **Zero Regression:** Preserve all `GENESIS_V2` and `MONOLITH_OS` gameplay, building hotkeys, icon Command Cards, faction HUD themes, and `milestone_0_test.tscn` Combat Lab functionality.

* **Hard Exclusions:** No stealth/cloaking mechanics; no role-sorted squad formations.

---

## Phase A — Command Hub Select & Focus Cycler (`cmd_select_next_hub`)

### A.1 Rebindable Action & Settings Integration

1. **`project.godot`:** Register new InputMap action `cmd_select_next_hub` with default key **`KEY_BACKSPACE`**.

2. **`scripts/systems/settings_manager.gd`:**
   * Add `cmd_select_next_hub` to `KEYBIND_DEFS` under **Selection / Macro** (`"Cycle Command Hub"`, default `KEY_BACKSPACE`), supporting full keyboard + `Mouse 3 / 4 / 5` + Clear rebinding and `user://settings.cfg` persistence.

3. **`scripts/ui/controls_reference_overlay.gd`:**
   * Surface the live dynamic hotkey for `cmd_select_next_hub` (*"Cycle & Select Command Hub / Shift: Select All Hubs"*) in the `?` Controls Reference Overlay.

### A.2 Hub Cycling & Selection Logic (`scripts/controllers/selection_controller.gd`)

Add deterministic, faction-agnostic Command Hub cycling modeled directly on `select_next_idle_worker()` and `select_next_idle_production()`:

* Add state variable `var _hub_cycle_index: int = -1`.

* Add `func get_friendly_command_hubs() -> Array[Building]`:
  * Returns empty array in Spectator Mode (`TeamManager.is_spectator_mode()`).
  * Iterates `get_tree().get_nodes_in_group("buildings")` for living, non-queued-for-deletion, `is_constructed == true`, `not is_salvaging`, locally owned (`int(b.team) == local_team`) structures where `b.is_command_hub() == true`.
  * Sorts deterministically by `a.get_instance_id() < b.get_instance_id()`.

* Add `func select_next_command_hub(focus_camera: bool = true, select_all: bool = false) -> Building`:
  * Fetch `var hubs: Array[Building] = get_friendly_command_hubs()`. If empty, reset `_hub_cycle_index = -1` and return `null`.
  * Cancel any active targeting modes (`cancel_ability_targeting()`, `cancel_overclock_targeting()`, `cancel_attack_move_targeting()`, `cancel_patrol_targeting()`).
  * Clear unit selection (`_set_selected_units([])`).
  * **If `select_all == true` (`Shift + Backspace`):**
    * Call `_set_selected_buildings(hubs)` so all friendly Command Hubs are selected simultaneously (ideal for mass-queuing workers across all bases with `Q` / `Shift+Q`), and return `hubs[0]`.
  * **Normal Press (`Backspace`):**
    * Compute `next_idx = (_hub_cycle_index + 1) % hubs.size()`.
    * If a single hub is already selected (`selected_buildings.size() == 1` and `hubs.has(selected_buildings[0])`), advance directly from `(cur_idx + 1) % hubs.size()` so repeated presses never double-land on the same base.
    * Update `_hub_cycle_index = next_idx`, pick `chosen = hubs[next_idx]`, and call `_set_selected_buildings([chosen])`.
    * **Camera Focus (matching `select_next_idle_worker`):** When `focus_camera == true`, if `cam != null`, center on `chosen.global_position` whenever `hubs.size() == 1` or `chosen.global_position` is outside the camera's inner viewport rect (`Rect2(cam.global_position - vp_size * 0.5, vp_size).grow(-64.0)`). *(Or smoothly center whenever switching between distinct hubs so expanding across the map snaps immediately to the newly selected base.)*
    * Return `chosen`.

* **Input Wiring (`_unhandled_input`):**
  * Listen for `event.is_action_pressed("cmd_select_next_hub") and not event.is_echo()`.
  * Ignore if `ctrl_pressed` or `alt_pressed`.
  * Read `shift_held = Input.is_key_pressed(KEY_SHIFT) or (event is InputEventKey and event.shift_pressed)`.
  * Call `select_next_command_hub(true, shift_held)` and call `get_viewport().set_input_as_handled()`.

---

## Phase B — Multi-Building `Tab` Subgroup Cycling

### B.1 Building Subgroup State (`scripts/controllers/selection_controller.gd`)

Mirror the unit subgroup pipeline (`subgroups` / `active_subgroup_index`) cleanly for mixed multi-building selections:

* Add signal: `signal building_subgroups_changed(building_subgroups: Array[Dictionary], active_index: int)` (or extend existing listeners cleanly).
* Add state:
  * `var building_subgroups: Array[Dictionary] = []`
  * `var active_building_subgroup_index: int = 0`
* Add helper `func _rebuild_building_subgroups(preserve_type_id: StringName = &"") -> void`:
  * Group all valid `selected_buildings` by `b.building_type_id` into dictionaries:
    ```gdscript
    {
        "type_id": b.building_type_id,
        "display_name": b.display_name,
        "tech_tier": b.get_tech_tier(),
        "is_hub": b.is_command_hub(),
        "buildings": Array[Building],
    }
    ```
  * Sort subgroups deterministically: Command Hubs first → Military Production (by `tech_tier` ascending, then `type_id`) → Tech/Compute → Economy/Defense/Other.
  * If `preserve_type_id != &""`, keep `active_building_subgroup_index` on that `type_id` if still present; otherwise clamp to `0`.
  * Update `selected_building` and `inspected_entity` to the first building in the active subgroup **without deselecting the other selected buildings** (every building in `selected_buildings` remains visibly ringed on the map).

* Add public API:
  * `func get_active_building_subgroup() -> Dictionary`
  * `func get_active_building_subgroup_buildings() -> Array[Building]`
  * `func cycle_building_subgroup(step: int = 1) -> void`:
    * Advances `active_building_subgroup_index = posmod(active_building_subgroup_index + step, building_subgroups.size())`.
    * Cancels `is_overclock_targeting` if switching away from an Overclock-capable hub subgroup.
    * Syncs `selected_building` / `inspected_entity` to the new active subgroup's lead building (keeping all `selected_buildings` selected).
    * Plays a subtle building selection audio cue (`AudioManager.play_selection_audio(active_buildings)`).
    * Emits `building_subgroups_changed` and `buildings_selection_changed`.
  * `func set_active_building_subgroup(index: int) -> void` (for clicking subgroup tab buttons in `SelectionHUD`).

* **Wire `Tab` Input (`_unhandled_input`):**
  * In the existing `event.is_action_pressed("ui_cycle_subgroup")` block:
    * If `subgroups.size() > 1` → `cycle_subgroup()` (existing unit behavior).
    * Else if `selected_units.is_empty()` and `building_subgroups.size() > 1` → `cycle_building_subgroup(-1 if shift_held else 1)` and mark input handled.

* **Scope Building Hotkeys & Distributed Queuing to Active Subgroup:**
  * Update `_try_handle_building_hotkey_event()`, `queue_unit_distributed()`, `queue_unit_distributed_batch()`, `find_ready_overclock_hub()`, `has_selected_overclock_hub()`, and `eject_engineers_from_selected_buildings()` so that when `building_subgroups.size() > 1`, they read the active subgroup's buildings (`get_active_building_subgroup_buildings()`) first!
  * Example workflow: Player assigns `Assembly Bay ×2` + `Ballistics Lab ×1` + `Siege Gantry ×1` to Control Group `4`.
    * Press `4` → active subgroup is `Assembly Bay (x2)` → press `Q` twice (queues `Bulwark` on each `Assembly Bay`).
    * Press `Tab` → active subgroup switches to `Ballistics Lab (x1)` → press `Q` (`Rail-Sentinel`) / `R` (`Hardened Plating`).
    * Press `Tab` → active subgroup switches to `Siege Gantry (x1)` → press `Q` (`Anvil Siege-Walker`).
  * Ensure right-click rally-point setting (`CommandRouter.handle_right_click`) still sets rally points cleanly across all `selected_buildings` (or active subgroup if preferred—setting across all selected rally-capable buildings matches SC2 macro-group rallying).

### B.2 `SelectionHUD` Building Subgroup Tabs (`ui/hud/selection_hud.gd`)

* Connect to `_selection_controller.building_subgroups_changed` (or read `_selection_controller.building_subgroups` & `active_building_subgroup_index` inside `_render_inspected_entity()`).
* When rendering a multi-building selection with `building_subgroups.size() > 1`:
  * Show `subgroup_tabs_row` above the building telemetry/production area (reusing the exact same compact clickable tab pill style as mixed unit subgroups, plus the live `[Tab]` badge).
  * Highlight the active building subgroup tab in the active faction's HUD accent color (`#20F5DC` for `GENESIS_V2`, `#FF9F1C` for `MONOLITH_OS`).
  * Clicking a building subgroup tab calls `_selection_controller.set_active_building_subgroup(idx)` and immediately rebuilds the 4×3 Icon Command Card, left-column stats, and `ProductionQueueBox` for that building type.
  * Update the left-column title to show the active subgroup count cleanly (e.g., `"Assembly Bay  x2"` with subtitle `"SUBGROUP 1/3 • 4 BUILDINGS SELECTED"`), keeping total `SelectionHUD` width locked inside `<= 750 px` at `1280×720`.

---

## Phase C — Safe Legacy Prototype Pruning

Clean out obsolete Milestone 0–1.0 prototype assets so `agy` and future Faction #3–#5 plans never accidentally reference stale scenes or scripts.

### C.1 Mandatory Pre-Deletion Audit & `milestone_0_test.tscn` Migration

**Before deleting any file**, grep the entire project (`scenes/`, `scripts/`, `resources/`, `project.godot`) for every target filename and ID below:

1. **Migrate `scenes/test/milestone_0_test.tscn` (if it still references legacy prototypes):**
   * Replace any pre-placed `command_core.tscn` with `scenes/buildings/nexus_vat.tscn`.
   * Replace any pre-placed `test_unit.tscn`, `scout_unit.tscn`, or `enemy_trooper.tscn` with `GENESIS_V2` units (`clone_trooper.tscn`, `stinger.tscn`, `worker_unit.tscn`).
   * **KEEP** `scenes/units/target_dummy.tscn` and `resources/units/target_dummy_data.tres` (actively useful for DPS/shield testing in the sandbox).
   * Verify `milestone_0_test.tscn` opens and runs cleanly in Godot with zero missing resource warnings.

2. **Scrub Stale Code References:**
   * Check `scripts/controllers/sandbox_spawner.gd`, `ui/hud/sandbox_debug_panel.gd`, `scripts/buildings/building.gd`, `scripts/units/unit.gd`, `scripts/controllers/subgroup_helper.gd`, `ui/hud/selection_hud.gd`, `scripts/systems/economy_manager.gd`, `scripts/systems/match_manager.gd`, and `scripts/systems/skirmish_ai.gd` for any dead `preload(...)`, `load(...)`, or string checks targeting the legacy prototype IDs (`command_core`, `bio_lab`, `silica_refinery`, `bandwidth_relay`, `compute_node`, `test_unit`, `enemy_trooper`, `scout_unit`, `encroaching_zone`).
   * Remove only dead legacy branches/preloads; do **not** touch any `GENESIS_V2`, `MONOLITH_OS`, or `target_dummy` code paths.

### C.2 Legacy Files to Delete (Plus Their `.uid` Sidecars)

Only delete each file after confirming **0 remaining references** in `scenes/`, `resources/`, `scripts/`, `ui/`, and `project.godot`:

* **Legacy System Script:**
  * `scripts/systems/encroaching_zone.gd` (+ `.uid`)
* **Legacy Prototype Building Scenes & Data:**
  * `scenes/buildings/command_core.tscn`
  * `scenes/buildings/bio_lab.tscn` & `resources/buildings/bio_lab_data.tres`
  * `scenes/buildings/silica_refinery.tscn` & `resources/buildings/silica_refinery_data.tres`
  * `scenes/buildings/bandwidth_relay.tscn` & `resources/buildings/bandwidth_relay_data.tres`
  * `scenes/buildings/compute_node.tscn` & `resources/buildings/compute_node_data.tres`
* **Legacy Prototype Build Abilities:**
  * `resources/abilities/build_bio_lab.tres`
  * `resources/abilities/build_silica_refinery.tres`
  * `resources/abilities/build_bandwidth_relay.tres`
  * `resources/abilities/build_compute_node.tres`
  * *(Audit `resources/abilities/nanite_surge.tres` and `resources/abilities/overcharge_pulse.tres`: delete ONLY if zero `.tres` or `.gd` files reference them; keep if still used by any `GENESIS_V2` unit.)*
* **Legacy Prototype Unit Scenes & Data:**
  * `scenes/units/test_unit.tscn` & `resources/units/test_unit_data.tres`
  * `scenes/units/enemy_trooper.tscn` & `resources/units/enemy_trooper_data.tres`
  * `scenes/units/scout_unit.tscn` & `resources/units/scout_unit_data.tres`

### C.3 Headless Integrity Check

* Run a project-wide load/parse check (e.g., `godot --headless --quit` and inspect all scene dependencies) to confirm **zero broken `ExtResource` paths, zero parse errors, and zero `FactionData.validate()` warnings**.

---

## Phase D — Verification & Playtest Checklist

1. **Command Hub Select & Focus Cycling:**
   * Launch a skirmish as `GENESIS_V2` and as `MONOLITH_OS`, build a 2nd expansion hub (`Nexus Vat` / `Foundry Core`).
   * Press `Backspace` repeatedly: confirm it selects Hub #1 → centers camera → selects Hub #2 → centers camera → loops cleanly back to Hub #1.
   * Immediately after pressing `Backspace`, press `Q` (train Worker/Servo-Drone) and `F` (Core Overclock on `Foundry Core`) without clicking: confirm zero-click macro works smoothly across both bases.
   * Press `Shift + Backspace`: confirm all constructed friendly Command Hubs select together and `Q` load-balances worker training across them.
   * Rebind `Cycle Command Hub` in **Settings → Keybinds** (including testing a Mouse 4/5 side button) and verify `?` Controls Reference Overlay displays the live binding.

2. **Multi-Building `Tab` Subgroup Cycling:**
   * Box-select or bind a Control Group (`Ctrl+4`) containing mixed buildings (e.g., `Assembly Bay ×2` + `Ballistics Lab ×1` + `Siege Gantry ×1`, or `Cloning Vat ×2` + `Calibration Foundry ×1` + `Synthetics Fabricator ×1`).
   * Confirm `SelectionHUD` displays clickable building subgroup tabs (`[Tab]`) cleanly inside `1280×720` (Windowed and `F11` Fullscreen) with zero clipping.
   * Press `Tab` (and `Shift+Tab`) to cycle subgroups: confirm the 4×3 Icon Command Card updates immediately, all buildings in the group stay ringed, and pressing `Q/W/E/R/T` queues units/upgrades strictly on the active subgroup's buildings.
   * Destroy one building type in the mixed selection and confirm subgroup cycling recovers cleanly with zero null-reference errors.

3. **Legacy Pruning Verification:**
   * Confirm `MainMenu`, `skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, `skirmish_arena_03.tscn`, and `milestone_0_test.tscn` all load and run with **0 errors and 0 missing-resource warnings** in the Godot Output & Debugger panels.
   * Run a quick Combat Lab preset in `milestone_0_test.tscn` (`GENESIS_V2` vs `MONOLITH_OS`) to confirm Sandbox spawning remains 100% functional.