# Patch 3.0b.1 — `MONOLITH_OS` Spawn, Visuals, Command Cards & Main Menu Integration Fix

**Prerequisite:** Milestone 3.0b (`37_milestone_3_0b_monolith_os_core_roster_and_visuals.md`)  
**Goal:** Eliminate all Godot Debugger errors/warnings on `MONOLITH_OS` startup, fix the instant Victory/Defeat bug when `MONOLITH_OS` is in a match, ensure `MONOLITH_OS` units/buildings spawn with their Neo-Brutalist Halftone visuals and correct Command Cards, and replace the Slot 2 placeholder on the left side of `MainMenu` with a live, selectable `MONOLITH_OS` dossier.

**Non-Negotiable Constraints:**
* **Zero Regression on `GENESIS_V2`:** All `GENESIS_V2` matches, visuals, and command cards must remain intact.
* **Strict `1280×720` UI Discipline:** All Main Menu and in-game HUD updates must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).
* **Hard Exclusions:** No stealth/cloaking mechanics (also scrub the stale stealth teaser text from `LockedSlot4` in `MainMenu`).

---

## Phase A — Root-Cause Diagnostic & Resource Integrity Audit (Fixes Instant Win/Loss, Visuals & Command Cards)

Before editing, run a complete load/parse check across every `MONOLITH_OS` file in the workspace (via Godot CLI `godot --headless --quit` or full static inspection) and fix every error/warning found:

### A.1 Full Resource & Scene Load Audit
Inspect and validate every file referenced by `resources/factions/monolith_os_faction.tres`:
1. **Faction Manifest (`resources/factions/monolith_os_faction.tres`):**
   * Confirm `FactionData.validate()` returns **0 warnings** at startup in `TeamManager._ready()`.
   * Confirm `starting_hub_scene`, `worker_scene`, `harvester_scene`, `engineer_scene`, and `extra_starting_units` all load as valid non-null `PackedScene`s with zero console/debugger errors.
2. **All 7 `MONOLITH_OS` Building Scenes (`scenes/buildings/monolith_*.tscn`) & Data (`resources/buildings/monolith_*_data.tres`):**
   * Explicitly assign `building_data = ExtResource(...)` directly on the root node of each `scenes/buildings/monolith_*.tscn` (including `monolith_foundry_core.tscn`) so buildings never depend on deferred `TeamManager` lookup in `_ready()`.
   * Verify `monolith_foundry_core.tscn` has `is_core_hub = true`, `is_constructed = true`, `building_type_id = &"foundry_core"`, and `building_data` pointing to `monolith_foundry_core_data.tres` (`is_command_hub = true`, `is_core_hub = true`).
   * Verify `trainable_unit_data` / `trainable_unit_paths` on `Foundry Core`, `Silica Smelter`, `Assembly Bay`, and `Ballistics Lab` resolve to **only** `monolith_*_data.tres` units—zero `GENESIS_V2` unit references.
   * Add all 7 `MONOLITH_OS` building IDs (`&"foundry_core"`, `&"capacitor_pylon"`, `&"silica_smelter"`, `&"logic_monolith"`, `&"assembly_bay"`, `&"ballistics_lab"`, `&"bastion_emplacement"`) to `Building.DEFAULT_BUILDING_COSTS` in `scripts/buildings/building.gd` as safe fallbacks for Cancel/Salvage refunds.
3. **All 7 `MONOLITH_OS` Unit Scenes (`scenes/units/monolith_*.tscn`) & Data (`resources/units/monolith_*_data.tres`):**
   * Verify every `monolith_*.tscn` root node has `script = res://scripts/units/unit.gd`, valid `data = ExtResource("...monolith_*_data.tres")`, and `unit_type_id` matching the exact IDs expected by `EntityVisuals._is_monolith_unit()` (`&"servo_drone"`, `&"ore_crawler"`, `&"grid_tech"`, `&"bulwark_automaton"`, `&"picket_drone"`, `&"rail_sentinel"`, `&"aegis_relay"`).
   * Verify `monolith_servo_drone_data.tres` has `abilities` pointing **exclusively** to `MONOLITH_OS` build abilities (`build_monolith_foundry_core.tres`, `build_monolith_capacitor_pylon.tres`, `build_monolith_silica_smelter.tres`, `build_monolith_logic_monolith.tres`, `build_monolith_assembly_bay.tres`, `build_monolith_ballistics_lab.tres`, `build_monolith_bastion_emplacement.tres`)—verify each of those `AbilityData` `.tres` files exists, loads cleanly, has `target_type = TargetType.BUILD_PLACEMENT`, and references the matching `monolith_*_data.tres` `BuildingData`.
   * Verify `monolith_picket_drone_data.tres` (`monolith_suppressive_lock.tres`) and `monolith_aegis_relay_data.tres` (`monolith_shield_overcharge.tres`) load with zero missing properties or type errors.

### A.2 MatchManager Spawn & Instant-Elimination Fix (`scripts/systems/match_manager.gd`)
Audit `_bootstrap_skirmish_teams()` and `_swap_team_starting_loadout()` for why `MONOLITH_OS` was immediately eliminated at `0.5s`:
1. **Inspect & Guard `_swap_team_starting_loadout()`:**
   * Verify `fac = TeamManager.get_team_faction_data(tid)` actually returns `monolith_os_faction.tres` (not falling back to `genesis_v2`).
   * Verify `hub_inst = fac.starting_hub_scene.instantiate()` succeeds and `hub_inst is Building` is `true`. If `hub_inst == null` or not `Building`, emit a loud `push_error(...)` and do **not** silently leave the team with 0 hubs.
   * Ensure `hub` is added to `bldgs_parent` (`bldgs_parent.add_child(hub)`), verify `hub.is_in_group("buildings") == true`, `hub.is_command_hub() == true`, `hub.is_destroyed == false`, and `hub.current_hp > 0.0` immediately after `add_child(hub)`.
   * Ensure `_remove_spawn_building()` does not accidentally free the newly spawned `hub` or trigger a premature `evaluate_match_state()` via signal callbacks before the replacement hub is in the tree.
2. **Verify `skirmish_arena_01.tscn`, `02.tscn`, and `03.tscn` Pre-Placed Anchors:**
   * Confirm every team's pre-placed hub in all three skirmish arenas has `is_command_hub() == true` when `_bootstrap_skirmish_teams()` scans `_spawn_anchors`, so `_spawn_anchors.has(tid)` is always `true` for every active team.
3. **Verify `Unit._setup_procedural_visuals()` & `EntityVisuals`:**
   * Confirm `unit.gd` attaches `EntityVisuals`, hides any static placeholder `Polygon2D` children under `BodyVisual` (just like `building.gd` does), and calls `_entity_visuals.bind_unit(self)` so `MONOLITH_OS` units render their Neo-Brutalist Halftone silhouettes rather than fallback/placeholder polygons.
   * Confirm `EntityVisuals._draw_monolith_unit_silhouette()` and `_draw_monolith_building_completed()` actually execute when `MONOLITH_OS` entities are spawned.

---

## Phase B — Main Menu Left-Side Faction Dossier Integration (`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`)

Replace the hardcoded `GENESIS_V2`-only left panel with a dynamic multi-faction dossier selector that integrates `MONOLITH_OS` cleanly inside `1280×720`:

### B.1 Dynamic Left-Side Faction Dossier (`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`)
1. **Header & Build Tag:**
   * Update `SubtitleLabel` text in `main_menu.tscn` to:
     `"TECHNOZEN REAL-TIME STRATEGY  •  MILESTONE 3.0 FACTION EXPANSION  •  BUILD 0.3.0"`
   * Expose `FactionSectionHeader` (`%FactionSectionHeader`) to `main_menu.gd` and dynamically set it to:
     `"AI LORD FACTION DOSSIERS (%d / 5 ACTIVE)" % _playable_factions.size()` *(displays `2 / 5 ACTIVE`)*.
2. **Make the Featured Top Card Dynamic (`GenesisActiveCard` → still works by node path or `%ActiveFactionCard`):**
   * Wire the labels/containers inside the featured top card (`ColorSwatch`, `FactionName`, `FactionTagline`, `FactionDesc`, `BadgeRow`, and card border `StyleBoxFlat`) so `main_menu.gd` can switch the featured dossier smoothly between **`GENESIS_V2`** and **`MONOLITH_OS`**:
     * **`01 // GENESIS_V2 — THE VAT-BORN`** (Cyan/Emerald `#33F5DB` accent): existing description + signature unit badges.
     * **`02 // MONOLITH_OS — THE IRON AXIOM`** (Hazard Amber `#FF9F1C` accent):
       * *Tagline:* `"Neo-Brutalist Machine-State  •  3x Silica & +1 Compute Cap  •  Core Overclock & Shields"`
       * *Description:* `"Deploys slow, heavily armored robotics layered with unmitigated regenerating shields. Overclocks production facilities from its Foundry Core and extracts superior Silica and Compute yields."`
       * *Signature Badges:* `Core Overclock (2x)`, `3x Silica Saturation`, `Regen Shields + Armor`, `Bulwark Automaton`, `Picket Drone`, `Rail-Sentinel`, `Aegis Relay`, `Bastion Emplacement`.
3. **Convert Slot 2 (`LockedSlot2`) into a Playable Faction Switcher + Keep Slots 3–5 Locked:**
   * In the 2×2 `LockedGrid` below the featured card, make **Slot 1 (`GENESIS_V2`)** and **Slot 2 (`MONOLITH_OS`)** both selectable from the left panel without bloating vertical height at `1280×720`:
     * Cleanest layout: replace `LockedSlot2` with a live playable button that toggles/selects the *other* playable faction (or turn `LockedSlot2` into **`02 // MONOLITH_OS — The Iron Axiom | PLAYABLE — CLICK TO SELECT`** when `GENESIS_V2` is featured, and **`01 // GENESIS_V2 — The Vat-Born | PLAYABLE — CLICK TO SELECT`** when `MONOLITH_OS` is featured—or add a crisp `[01 // GENESIS_V2]` / `[02 // MONOLITH_OS]` pill bar right above the featured card and replace `LockedSlot2` with `MONOLITH_OS` status card).
     * Whichever pattern is cleaner in `main_menu.tscn`, clicking **`MONOLITH_OS`** on the left must:
       1. Switch the featured dossier card to `MONOLITH_OS` with Hazard Amber styling.
       2. Update the local Human player's slot (`_slot_configs[human_idx]["faction_id"] = &"monolith_os"`) and sync the right-panel faction dropdown immediately.
     * Conversely, changing the local Human player's faction dropdown on the right panel (`_on_slot_faction_changed`) must immediately update the left-side featured dossier card to match.
   * **Scrub Stealth Text on `LockedSlot4` (`NULL_VECTOR`):** Replace `"Stealth & Algorithmic Subversion — Cloaked infiltrators..."` in both `main_menu.tscn` and `main_menu.gd` with a non-stealth identity (e.g., `"Electronic Warfare & Disruption — Signal-spoofing arrays & EMP disruptors designed to sever enemy Compute networks."`).

### B.2 Fix Hardcoded `&"genesis_v2"` on Match Launch & Summary (`scripts/ui/main_menu.gd`)
1. **`_on_launch_pressed()`:**
   * Resolve `var primary_faction_id: StringName = _get_local_human_faction_id()` (reading the active Human slot's `faction_id` from `_slot_configs`, falling back to `_slot_configs[0]["faction_id"]` in Spectator Mode) and pass `primary_faction_id` into `GameConfig.set_lobby_config(...)` instead of hardcoded `&"genesis_v2"`.
2. **`_refresh_ui()` (`summary_label`):**
   * Replace the hardcoded `"GENESIS_V2"` mode tag with the local human player's active faction `short_code` / `display_name` (or `"GEN-V2 vs MONO-OS"` matchup summary).
3. **`_ready()` (`dossier_notice_label`):**
   * Sync the initial featured dossier card and `dossier_notice_label` with the saved `GameConfig.selected_faction_id` / `_slot_configs` so returning from a `MONOLITH_OS` match to Main Menu preserves your selection.

---

## Phase C — Verification Checklist (Verify in Godot Before Closing 3.0b.1)

1. **Zero Console / Debugger Errors:**
   * Launch the project (`F5`). Confirm **0 errors** and **0 `FactionData.validate()` warnings** in the Godot Output & Debugger panels.
2. **Main Menu Left-Panel & Lobby Sync (`1280×720` Windowed & `F11` Fullscreen):**
   * Confirm header shows `AI LORD FACTION DOSSIERS (2 / 5 ACTIVE)`.
   * Click `MONOLITH_OS` on the left panel; confirm the featured dossier switches to `02 // MONOLITH_OS — THE IRON AXIOM` (Hazard Amber styling) and `P1`'s right-panel faction dropdown switches to `MONO-OS`.
   * Switch `P1`'s dropdown back to `GEN-V2` and confirm the left dossier switches back to `GENESIS_V2`.
   * Confirm zero horizontal or vertical clipping at `1280×720`.
3. **Skirmish Launch — Both Matchup Directions (`skirmish_arena_01.tscn`):**
   * Launch **P1 = `MONO-OS` vs AI = `GEN-V2`**: confirm **no instant defeat**, boot banner reads `// AXIOM KERNEL LOCKED — MONOLITH_OS` in Hazard Amber, and camera centers on the `Foundry Core` + 3 `Servo-Drones` + `Bulwark Automaton` + `Picket Drone`.
   * Launch **P1 = `GEN-V2` vs AI = `MONO-OS`**: confirm **no instant victory** and match plays normally.
4. **Visuals & Command Cards:**
   * Verify `Foundry Core`, `Servo-Drone`, `Bulwark Automaton`, and `Picket Drone` render in distinct **Neo-Brutalist Gunmetal + Hazard Amber Halftone** silhouettes (visually unmistakable from `GENESIS_V2`) with cyan shield bars above HP bars.
   * Select `Foundry Core`: Command Card displays `[E] Core Overclock`, `Servo-Drone`, `Ore-Crawler`, `Grid-Tech`, and `Salvage`.
   * Select `Servo-Drone`: Command Card displays the 7 `MONOLITH_OS` structures (`Foundry Core`, `Capacitor Pylon`, `Silica Smelter`, `Logic Monolith`, `Assembly Bay`, `Ballistics Lab`, `Bastion Emplacement`) + `Auto-Repair`.
   * Build an `Assembly Bay`, cast `Core Overclock` on it from `Foundry Core`, and train a `Bulwark Automaton` to confirm end-to-end production and `2.0×` Overclock speed.