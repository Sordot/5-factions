# Milestone 4.3b — Controller, HUD & MatchManager Decomposition + Boot-Time Faction Audit Validator

**Prerequisite:** Milestone 4.3a (`milestone_4_3a_core_entity_and_ai_decomposition.md`) verified and working cleanly.

**Goal:** Complete the pre-Faction-#4 hygiene pass by decomposing the remaining three large core scripts (`scripts/controllers/selection_controller.gd` at ~107 KB, `ui/hud/selection_hud.gd` at ~90 KB, and `scripts/systems/match_manager.gd` at ~71 KB) into modular `RefCounted` helpers and adding an automated **Boot-Time Faction & Command-Alignment Audit Validator** so Factions #4 and #5 plug in with instant diagnostic verification and zero silent wiring bugs.

**Non-Negotiable Constraints:**

* **Zero Behavioral or Visual Regressions:** Every selection shortcut, 4.1 wireframe click modifier (`LMB` / `Shift` / `Ctrl` / `Ctrl+Shift` / Double-Click), multi-building subgroup `Tab` cycling, 4×3 Icon Command Card hotkey/tooltip, Faction HUD Theme, Geothermal Compute Surge, Uplink Holdout, Micro Gauntlet, Post-Match Inspection, and Battle Heatmap must behave **100% identically** after this refactor.
* **Zero Balance Changes & Zero Layout Clipping:** All HUD elements must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).
* **100% Signal & Public API Preservation:** Keep all existing `@export` properties, `signal` declarations, `@onready` paths, and public methods on `SelectionController`, `SelectionHUD`, `MatchManager`, and `TeamManager` intact.
* **Zero Scene `.tscn` Node-Path Breakage:** Extracted helpers are `RefCounted` classes (plus optional extracted `MatchBootVeil` script) requiring zero `.tscn` node re-parenting.
* **Hard Guardrails (MUST PRESERVE):** No stealth/cloaking, no role-sorted player formations, no overkill-prevention automation, no auto-loop production, standard worker construction only.

## Target Decomposition Map (4.3b)

| Monolith Script | Extracted Modules | Slim Coordinator Responsibilities Kept |
| :--- | :--- | :--- |
| `scripts/controllers/selection_controller.gd` | • `scripts/controllers/control_group_manager.gd`<br>• `scripts/controllers/command_cursor_manager.gd`<br>• `scripts/controllers/box_selection_resolver.gd` | Input routing (`_input`, `_unhandled_input`), targeting state flags, selection state arrays & signals, 4.1 wireframe mutation API, idle-worker / idle-production / hub cycling, and distributed queueing. |
| `ui/hud/selection_hud.gd` | • `ui/hud/command_card_builder.gd`<br>• `ui/hud/selection_telemetry_renderer.gd` | `@onready` UI bindings, `SelectionController` / `EconomyManager` signal wiring, `FactionHudTheme` application, `SelectionWireframeGrid` bridge, and layout adjustment for minimap. |
| `scripts/systems/match_manager.gd` | • `scripts/systems/match_stats_tracker.gd`<br>• `scripts/systems/match_alert_bus.gd`<br>• `scripts/systems/match_surge_director.gd`<br>• `ui/overlays/match_boot_veil.gd` | Match lifecycle (`_ready`, `_process`, win/loss evaluation, Uplink victory checks), team loadout bootstrapping, AI spawning, special-mode controllers (Holdout/Gauntlet), speed controls, and scene transitions. |
| `scripts/systems/team_manager.gd` & `scripts/data/faction_data.gd` | • `scripts/data/faction_audit_validator.gd` | Boot-time cross-faction Command Alignment, Universal Hub drop-off, visual/audio coverage, and guardrail compliance diagnostics. |

## Phase A — `SelectionController` Decomposition (`scripts/controllers/selection_controller.gd`)

### A.1 `scripts/controllers/control_group_manager.gd` (`class_name ControlGroupManager extends RefCounted`)

Extract all `1–9` control group state and operations:

* **Owned State:** `control_groups: Dictionary`, `_last_recall_group: int`, `_last_recall_time_ms: int`.
* **Moved Methods:**
  * `assign(sc: SelectionController, group_num: int)`
  * `append(sc: SelectionController, group_num: int)`
  * `remove(sc: SelectionController, group_num: int)`
  * `steal_assign(sc: SelectionController, group_num: int)`
  * `steal_append(sc: SelectionController, group_num: int)`
  * `recall(sc: SelectionController, group_num: int, allow_double_tap_center: bool)`
  * `handle_key(sc: SelectionController, group_num: int, key_event: InputEventKey)`
  * `get_key_group_num(key_event: InputEventKey) -> int`
  * `get_pruned_units(sc: SelectionController, group_num: int) -> Array[Unit]`
  * `get_pruned_buildings(sc: SelectionController, group_num: int) -> Array[Building]`
  * `get_summary(sc: SelectionController) -> Dictionary`
  * `get_rich_summaries(sc: SelectionController) -> Dictionary`
  * `clear(sc: SelectionController) -> void`
  * `_strip_from_other_groups(...)`, `_watch_units(...)`, `_watch_buildings(...)`
* Keep `SelectionController.control_groups` synced/exposed and retain all public control-group methods on `SelectionController` as clean delegators (`assign_control_group`, `recall_control_group`, `get_control_groups_summary`, `get_control_group_summaries`, etc.).

### A.2 `scripts/controllers/command_cursor_manager.gd` (`class_name CommandCursorManager extends RefCounted`)

Extract procedural 32×32 cursor generation and contextual cursor/modal state resolution:

* **Owned State:** `_command_cursors: Dictionary`, `_active_cursor_state: StringName`.
* **Moved Methods:**
  * `build_cursors() -> void` & `_make_reticle_cursor(style: StringName) -> ImageTexture` *(preserving all 6 procedural cursors: `attack_move`, `patrol`, `repair`, `ability_target`, `overclock_valid`, `overclock_invalid`)*
  * `clear_cursor() -> void`
  * `apply_cursor(state: StringName) -> void`
  * `update_cursor(sc: SelectionController) -> void`
  * `is_any_modal_open(sc: SelectionController) -> bool`
  * `is_hovering_repairable_target(sc: SelectionController) -> bool`

### A.3 `scripts/controllers/box_selection_resolver.gd` (`class_name BoxSelectionResolver extends RefCounted`)

Extract marquee box candidate collection, hover resolution, double-click type queries, and building subgroup sorting:

* **Moved Methods:**
  * `circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool`
  * `collect_box_candidates(sc: SelectionController, world_rect: Rect2) -> Dictionary` *(preserving Smart Combat-Only Box Select toggle & friendly building fallback)*
  * `find_top_hover_entity(sc: SelectionController, world_point: Vector2) -> Node` *(preserving spectator / post-match / friendly / hostile / barricade / relay / uplink / salvage / resource priority order)*
  * `find_visible_units_of_type(sc: SelectionController, type_id: StringName, target_team: Unit.Team) -> Array[Unit]`
  * `find_visible_buildings_of_type(sc: SelectionController, type_id: StringName, target_team: Unit.Team) -> Array[Building]`
  * `rebuild_building_subgroups(selected_buildings: Array[Building], preserve_type_id: StringName) -> Dictionary` *(returns `{"subgroups": Array[Dictionary], "active_index": int}`, preserving `_get_building_subgroup_sort_rank` ordering: Hub → Military Production → Tech/Research → Utility)*
* Preserve `SelectionController`'s 4.1 Wireframe Mutation API (`select_only_entity`, `deselect_entity`, `filter_selection_to_entity_type`, `remove_entity_type_from_selection`) intact with zero behavioral changes.

## Phase B — `SelectionHUD` Decomposition (`ui/hud/selection_hud.gd`)

### B.1 `ui/hud/command_card_builder.gd` (`class_name CommandCardBuilder extends RefCounted`)

Extract the entire 4×3 Icon Command Card construction and live state-refresh subsystem out of `selection_hud.gd`:

* **Owned State (managed cleanly by builder & bound to `hud: SelectionHUD`):** `unit_cmd_tiles: Dictionary`, `ability_buttons: Dictionary`, `building_action_buttons: Array[Dictionary]`, `active_abilities: Array[AbilityData]`.
* **Moved Methods:**
  * `clear_command_grid(hud: SelectionHUD) -> void`
  * `rebuild_building_card(hud: SelectionHUD, building: Building) -> void` *(preserving unfinished 75% cancel, Row 1 `Q/W/E` training + Shift×5 batch queueing, Row 2 `R/T` upgrades, Row 3 `F` Core Overclock / Eject Engineers, and Slot 11 click-only Salvage)*
  * `refresh_building_card(hud: SelectionHUD, building: Building) -> void`
  * `rebuild_unit_card(hud: SelectionHUD, active_group: Dictionary) -> void` *(preserving 4.0b Worker 4×3 layout: Row 1 `Move/Stop/Hold/Auto-Repair`, Row 2–3 `Q/W/E/R/T/Y/F/G`, and standard Combat/Specialist layout)*
  * `refresh_all_ability_states(hud: SelectionHUD) -> void`, `refresh_single_ability_button(hud: SelectionHUD, ability_id: StringName) -> void`
  * `refresh_dynamic_command_labels(hud: SelectionHUD) -> void`, `refresh_stance_button(hud: SelectionHUD) -> void`, `refresh_deploy_button(hud: SelectionHUD) -> void`, `refresh_auto_repair_button(hud: SelectionHUD) -> void`
  * `build_ability_tooltip_meta(hud: SelectionHUD, ability: AbilityData) -> String`
  * `build_unit_class_traits_label(u_data: UnitData) -> String`
  * `get_unit_icon_accent(...)`, `get_building_icon_accent(...)`, `apply_theme_to_grid(...)`

### B.2 `ui/hud/selection_telemetry_renderer.gd` (`class_name SelectionTelemetryRenderer extends RefCounted`)

Extract non-Command-Card HUD panel rendering & data-driven name shortening:

* **Moved Methods:**
  * `apply_left_column(hud: SelectionHUD, info: Dictionary) -> void` *(portrait swatch, title, subtitle, HP + Shield bars, primary gauge bar)*
  * `rebuild_telemetry_grid(hud: SelectionHUD, stats: Variant) -> void`
  * `refresh_production_queue_ui(hud: SelectionHUD, entity: Node) -> void` *(including overclock amber bar styling & clickable 100%-refund queue cancellation slots)*
  * `rebuild_subgroup_tabs(hud: SelectionHUD, subgroups: Array[Dictionary], active_index: int) -> void`
  * `rebuild_building_subgroup_tabs(hud: SelectionHUD, b_subgroups: Array[Dictionary], active_index: int) -> void`
  * `rebuild_control_group_row(hud: SelectionHUD, summary: Dictionary) -> void`
  * `show_wireframe_hover_tooltip(hud: SelectionHUD, entity: Node) -> void`
  * `shorten_name(full_name: String) -> String`: Replace the legacy 24-chain `.replace()` hack in `_shorten_building_name()` with the unified data-driven `_short_name_cache` populated from `FactionData` (`UnitData.get_short_name()`, `BuildingData.get_short_name()`, `UpgradeData.get_short_name()`), automatically supporting Factions #4 and #5!

## Phase C — `MatchManager` Decomposition (`scripts/systems/match_manager.gd`)

### C.1 `scripts/systems/match_stats_tracker.gd` (`class_name MatchStatsTracker extends RefCounted`)

Extract all per-team match telemetry, timeline sampling, macro grading, and combat heatmap tracking:

* **Owned State:** `team_stats: Dictionary`, `timeline_samples: Array[Dictionary]`, `combat_heatmap_events: Array[Dictionary]`, `heatmap_damage_throttle: Dictionary`, `alliance_uplink_times: Dictionary`, `uplink_milestones_announced: Dictionary`, `alliance_uplink_rep_team: Dictionary`, plus legacy `player_*` / `enemy_*` summary counters.
* **Moved Methods:**
  * `init_teams(active_teams: Array[int]) -> void`, `ensure_bucket(tid: int) -> Dictionary`
  * `record_timeline_sample(mm: MatchManager, force_append: bool = false) -> void`
  * `sample_macro_efficiency(mm: MatchManager) -> void`
  * `record_combat_heatmap_damage(mm: MatchManager, world_pos: Vector2, victim_team: int) -> void`
  * `push_heatmap_event(world_pos: Vector2, weight: float, team_id: int, kind: StringName) -> void`
  * `on_bandwidth_changed(tid: int, used: int) -> void`
  * `on_unit_produced(unit: Unit) -> void`, `on_unit_died(mm: MatchManager, unit: Unit) -> void`
  * `on_building_completed(mm: MatchManager, building: Building) -> void`, `on_building_destroyed(mm: MatchManager, building: Building) -> void`
  * `compute_macro_grade(supply_blocked_s: float, match_dur_s: float, avg_float: int, trade_ratio: float) -> String`
  * `build_match_end_stats(mm: MatchManager, winner_team: Unit.Team, winner_label: String, reason: String) -> Dictionary`
  * `format_duration(seconds: float) -> String`

### C.2 `scripts/systems/match_alert_bus.gd` (`class_name MatchAlertBus extends RefCounted`)

Extract tactical alerts and event-feed throttling:

* **Owned State:** `recent_alerts: Array[Dictionary]`, `damage_alert_log: Array[Dictionary]`, `event_dedupe_times: Dictionary`.
* **Moved Methods:**
  * `emit_tactical_event(mm: MatchManager, category: StringName, message: String, world_pos: Vector2, accent_color: Color, dedupe_key: String) -> void`
  * `push_tactical_alert(mm: MatchManager, world_pos: Vector2, alert_type: StringName, message: String) -> void` *(preserving 300 px / 4.0s spatial-temporal deduplication, `AudioManager.play_tactical_alert` + combat activity boost, and `MAX_RECENT_ALERTS = 3` ring buffer)*

### C.3 `scripts/systems/match_surge_director.gd` & `ui/overlays/match_boot_veil.gd`

* **`scripts/systems/match_surge_director.gd` (`class_name MatchSurgeDirector extends RefCounted`):** Move 4.2's Geothermal Compute Surge timer (`_next_surge_time`, `_last_surged_vent`, `reset()`, `tick(mm: MatchManager)`) cleanly out of `match_manager.gd`, preserving exact constants (`SURGE_FIRST_DELAY = 165.0`, `SURGE_INTERVAL = 180.0`, `SURGE_DURATION = 45.0`, `SURGE_MULTIPLIER = 2.0`), Skirmish-only gating, and `> 440 px` main-base exclusion.
* **`ui/overlays/match_boot_veil.gd` (`class_name MatchBootVeil extends Control`):** Move the inner `class MatchBootVeil` out of the bottom of `match_manager.gd` into its own clean overlay script.

## Phase D — Automated Boot-Time Faction & Command-Alignment Audit Validator

### D.1 `scripts/data/faction_audit_validator.gd` (`class_name FactionAuditValidator extends RefCounted`)

Create a pure-diagnostic validator invoked automatically in `TeamManager._validate_registered_factions()` right after `FactionData.validate()` (zero gameplay mutations—emits crisp `push_warning(...)` lines only when a contract is violated):

1. **Universal Command Hub Drop-Off Contract:**
   * Locate each playable faction's `hub` building (`fac.get_ai_building_for_role(&"hub")`).
   * Verify `hub.is_dropoff == true` and `hub.get_dropoff_resources()` contains both `&"biomass"` and `&"silica"`.
2. **Command Hub Training Role Parity (`Q = Worker`, `W = Harvester`, `E = Engineer`):**
   * Inspect `hub.resolve_trainable_units()`:
     * Slot 0 (`Q`): `can_gather and not auto_gather_on_spawn`
     * Slot 1 (`W`): `can_gather and auto_gather_on_spawn`
     * Slot 2 (`E`): `can_staff_compute`
3. **Worker 8-Building Command Alignment (`Q / W / E / R / T / Y / F / G`):**
   * Inspect the faction's primary worker `UnitData` (Slot 0 of hub).
   * Extract all `BUILD_PLACEMENT` abilities and verify:
     * Exactly `8` build abilities exist with hotkeys matching `["Q", "W", "E", "R", "T", "Y", "F", "G"]` in order (zero duplicates).
     * Every ability's `building_to_build` is non-null and registered in `fac.building_roster`.
4. **Full AI Role & Metadata Coverage:**
   * Verify `ai_build_profile` resolves all **7** canonical roles (`&"hub"`, `&"supply"`, `&"refinery"`, `&"compute_hub"`, `&"barracks_t1"`, `&"counter_foundry"`, `&"heavy_t2"`).
   * Verify every `UnitData`, `BuildingData`, and `UpgradeData` in the rosters has a non-empty `short_display_name` (preventing fallback name overflow in HUD tabs and queue slots).
   * Verify every playable faction has a unique `dossier_slot_number` and non-empty `audio_timbre_profile`.
5. **Visual Renderer Coverage Check:**
   * Query `EntityVisuals` (via a lightweight static helper `EntityVisuals.has_renderer_for(type_id: StringName, is_building: bool) -> bool`) to verify every unit ID in `unit_roster` and building ID in `building_roster` has a registered `FactionVisualRenderer`.
6. **Hard Design Guardrail Check:**
   * Flag a warning if any unit or ability contains forbidden tags (`&"stealth"`, `&"cloaked"`, `&"cloak"`).

### D.2 Wire into `TeamManager` (`scripts/systems/team_manager.gd`)

* In `_validate_registered_factions()`:
  * After running `res.validate()`, run `FactionAuditValidator.audit_playable_factions(get_playable_factions())` and print any returned warnings cleanly via `push_warning("FactionAudit: %s" % w)`.
  * Verify all 3 existing factions (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`) pass the new boot audit with **0 warnings**! (If any minor missing `short_display_name` or hotkey label turns up on an existing `.tres`, fix that metadata cleanly so boot output stays spotless.)

## Phase E — Verification & Zero-Regression Audit Checklist (4.3b)

1. **Zero Errors & Spotless Boot Audit:**
   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, **0 `FactionData.validate()` warnings**, and **0 `FactionAudit:` warnings** across all 3 active factions!
   * Confirm `selection_controller.gd`, `selection_hud.gd`, and `match_manager.gd` are each cleanly slimmed down with zero circular `preload()` cycles.
2. **Selection, Wireframe Grid, Cursors & Control Groups (`milestone_0_test.tscn` & Skirmish):**
   * Test box-select (both All Units and Smart Combat-Only toggle), double-click / Ctrl-click same-type selection, hover rings, and all 6 procedural cursors (`attack_move`, `patrol`, `repair`, `ability_target`, `overclock_valid`, `overclock_invalid`).
   * Test Control Groups `1–9`: `Ctrl` assign, `Shift` append, `Alt` steal, `Alt+Shift` steal-append, double-tap camera center, and clickable HUD control-group pills.
   * Test 4.1 Clickable 24-Slot Wireframe Grid: `LMB` isolate, `Shift+LMB` remove, `Ctrl+LMB` / double-click type filter, `Ctrl+Shift+LMB` drop type, pagination (`> 24`), and hover tooltips.
   * Test multi-building selection + `Tab` building-subgroup cycling across all 3 factions (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`) and confirm `SelectionHUD` stays 100% unclipped at **Windowed `1280×720`** and **Fullscreen (`F11`)**.
3. **Match Flow, Surges, Post-Match Inspection & Modes:**
   * Play a fast skirmish (or 2x Spectator match on `Triad Sanctum`) through a **Geothermal Compute Surge** (`02:45`), **Uplink Victory / Command Hub elimination**, **MatchEndOverlay** (Timeline Graph + Macro Grades), **Inspect Battlefield** + **Combat Heatmap**, and **Rematch / Return to Main Menu** (confirming zero leaked VFX or broken cursors).
   * Quick smoke-test of **Uplink Holdout** (as `PRISMA_DEI`) and **Micro Gauntlet** (Drill 4 or 5 + `[R] Retry`) to confirm `MatchManager` special-mode hooks are 100% intact.