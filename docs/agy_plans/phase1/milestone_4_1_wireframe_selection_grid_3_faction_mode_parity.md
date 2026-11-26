# Milestone 4.1 — Clickable Wireframe Selection Grid & 3-Faction Alternate Mode Parity

**Prerequisite:** Milestone 4.0b (`milestone_4_0b_prisma_dei_tier2_upgrades_ai_and_command_alignment.md`) verified and working cleanly.

**Goal:** Deliver two focused, high-leverage upgrades across micro ergonomics and solo replayability without introducing mechanic bloat:

1. **Clickable 24-Slot Wireframe Selection Grid (`SelectionWireframeGrid`, `SelectionHUD`, `SelectionController`):** Replace the legacy 12-label text badge grid in `SelectionHUD` with a responsive, pooled **24-slot procedural vector wireframe/icon grid** (with clean pagination for selections `> 24`), color-coded live by HP and Shield status, supporting full SC2-grade click modifiers:
   * **Left-Click:** Isolate that single unit or building.
   * **Shift + Left-Click:** Remove that single entity from the active selection.
   * **Ctrl + Left-Click** *(or **Double-Left-Click**)*: Filter the active selection down to all selected entities of that type.
   * **Ctrl + Shift + Left-Click:** Remove all entities of that type from the active selection.
2. **3-Faction Parity for Uplink Holdout & Micro Gauntlet (`HoldoutModeController`, `GauntletModeController`, `MainMenu`, `ModeRecords`):** Bring both solo modes fully up to speed with **`03 // PRISMA_DEI` (*The Divine Lattice*)**:
   * Full playable & opposing-wave `PRISMA_DEI` support (plus 3-faction `MIXED ASSAULT` waves) in **Uplink Holdout**.
   * Full `PRISMA_DEI` support in **Optimal 3-Minute Boom**, plus two new curated `PRISMA_DEI` **Micro Gauntlet** tactical drills (*Tether Weaving vs. Mortar Splash* and *Escalating Beam Focus-Fire*), bringing Gauntlet to 5 drills with clean `1280×720` scrolling/layout.

**Hard Design Guardrails (MUST PRESERVE):**

* **Zero Skill-Cap Automation:** No stealth/cloaking, no role-sorted squad formations, no overkill-prevention targeting automation, no auto-loop production.
* **Zero Balance Changes:** Do **not** alter any unit or building combat stats on `GENESIS_V2`, `MONOLITH_OS`, or `PRISMA_DEI`.
* **100% Procedural Pipeline:** All wireframe tile icons, HP/shield micro-bars, status pips, and HUD theming must use Godot 2D `_draw()`, `CommandIconGlyphs`, and `StyleBoxFlat` (zero external image assets).
* **Strict `1280×720` UI Discipline:** `SelectionHUD` (with the 24-slot wireframe grid active) and `MainMenu` (`ConfigPanel` at `448 px` width on both Holdout and Gauntlet tabs with 5 drills) must remain **100% unclipped** in both Windowed `1280×720` and Fullscreen (`F11`).

---

## Phase A — Clickable 24-Slot Wireframe Selection Grid

### A.1 Clean Selection Mutation API (`scripts/controllers/selection_controller.gd`)

Add four dedicated, public selection-manipulation methods on `SelectionController` so wireframe clicks share the exact same subgroup-focus, `SelectionRing`, HUD-refresh, and single-voice `AudioManager` paths as normal world clicks:

1. **`func select_only_entity(entity: Node) -> void`** *(Left-Click on wireframe tile)*:
   * Validates `is_instance_valid(entity)` and that the entity is still alive/non-destroyed (`Unit` or `Building`).
   * Replaces the active selection cleanly with `[entity]`, resets subgroup index to `0`, updates `SelectionRing`s, emits selection-changed signals to `SelectionHUD`, and plays `AudioManager.play_selection_audio([entity])`.
2. **`func deselect_entity(entity: Node) -> void`** *(Shift + Left-Click)*:
   * Removes `entity` from `selected_units` or `selected_buildings` (calling `entity.set_selected(false)`).
   * Re-clamps active subgroup index (or cleanly clears selection if `0` entities remain), refreshes `SelectionHUD`, and plays a light `AudioManager.play_ui_click()`.
3. **`func filter_selection_to_entity_type(entity: Node) -> void`** *(Ctrl + Left-Click or Double-Left-Click)*:
   * Resolves `target_type_id` (`u.get_unit_type_id()` for `Unit`, `b.building_type_id` for `Building`).
   * Filters the currently selected list strictly to entities matching `target_type_id` (deselecting all non-matching entities cleanly).
   * Resets subgroup index to `0`, refreshes `SelectionHUD`, and plays `AudioManager.play_selection_audio(...)`.
4. **`func remove_entity_type_from_selection(entity: Node) -> void`** *(Ctrl + Shift + Left-Click)*:
   * Resolves `target_type_id` and removes every entity in the current selection matching `target_type_id` (calling `set_selected(false)` on each removed entity).
   * Re-clamps active subgroup index (or clears selection if empty), refreshes `SelectionHUD`, and plays `AudioManager.play_ui_click()`.

*(Safety Check: When `SelectionController` has an active targeting reticle or build ghost—e.g. `active_targeting_ability != null`—ensure wireframe tiles consume mouse input via `MOUSE_FILTER_STOP` so clicking a tile never casts an ability or places a building onto the arena underneath the HUD.)*

### A.2 Procedural Wireframe Tile (`ui/hud/selection_wireframe_tile.gd`)

Create a lightweight, pooled `class_name SelectionWireframeTile extends Control` (`custom_minimum_size = Vector2(34.0, 32.0)`, `mouse_filter = Control.MOUSE_FILTER_STOP`):

* **Signals:**
  * `signal tile_clicked(entity: Node, shift_held: bool, ctrl_held: bool, is_double_click: bool)`
  * `signal tile_hovered(entity: Node, tile_global_rect: Rect2)`
  * `signal tile_unhovered(entity: Node)`
* **Bound State (Zero Per-Frame Node Churn):**
  * `var entity_ref: Node = null`
  * `var is_active_subgroup: bool = false`
  * `var is_hovered: bool = false`
  * `var _faction_accent: Color = Color(0.20, 0.83, 0.60, 1.0)`
  * `var _bg_color: Color = Color(0.06, 0.09, 0.13, 0.92)`
* **Input Handling (`_gui_input(event: InputEvent)`):**
  * On `InputEventMouseButton` (`button_index == MOUSE_BUTTON_LEFT` and `pressed`):
    * Call `accept_event()` immediately so clicks never fall through to the camera or world selection box.
    * Forward `tile_clicked.emit(entity_ref, event.shift_pressed, event.ctrl_pressed or event.meta_pressed, event.double_click)`.
  * Connect `mouse_entered` / `mouse_exited` to toggle `is_hovered`, call `queue_redraw()`, and emit hover tooltip signals.
* **100% Procedural Vector Rendering (`_draw()`):**
  1. **Tile Frame & Subgroup Highlight:**
     * Draw sleek dark panel background matching `FactionHudTheme` (`GENESIS_V2` rounded chamfered technozen, `MONOLITH_OS` stark brutalist 0–2 px sharp corners, `PRISMA_DEI` crisp gold-hairline Bauhaus frame).
     * Active `Tab` subgroup tiles draw a bright `1.6 px` `_faction_accent` border + subtle `0.12` alpha interior wash; non-active subgroup tiles draw a muted `1.0 px` border; hover lightens border cleanly.
  2. **HP-Colorized Vector Wireframe Icon:**
     * Compute `hp_ratio = clampf(cur_hp / maxf(1.0, max_hp), 0.0, 1.0)`:
       * `hp_ratio > 0.66`: Healthy Emerald (`Color(0.22, 0.92, 0.56, 0.96)`)
       * `hp_ratio > 0.33`: Damaged Amber (`Color(0.98, 0.78, 0.16, 0.98)`)
       * `hp_ratio <= 0.33`: Critical Crimson (`Color(1.0, 0.28, 0.38, 1.0)`)
     * Render the entity's crisp procedural glyph inside a centered `20×20 px` inset via `CommandIconGlyphs.draw_glyph(...)` (passing the HP health color as the primary stroke/wireframe tint!) so every `Votary`, `Cantor`, `Bulwark Automaton`, `Goliath Frame`, `Choir Basilica`, etc. is immediately recognizable at a glance.
  3. **Bottom Micro-Bars (HP + Shield):**
     * **HP Micro-Bar (`28×2.5 px` at bottom edge):** Dark track + filled bar in the exact HP tier color.
     * **Shield Micro-Bar (`28×2.0 px` directly above HP bar, only when `max_shield > 0` or temporary barrier `> 0`):** Crisp Shield Cyan (`#38BDF8`) filled by `(current_shield + barrier) / max(1.0, max_shield + barrier)`.
  4. **Crisp Corner Status Micro-Pips (Max 2–3 px, Zero Clutter):**
     * **Top-Left (Veterancy Rank `1–3`):** `1–3` tiny bright gold (`#FACC15`) 2 px pips if `unit.veterancy_rank > 0`.
     * **Top-Right (State Tag):**
       * `Optical Tether` active (`unit.get_optical_tether_stacks() > 0`): tiny glowing Ultraviolet Magenta / Gold diamond pip.
       * `Deployed` (`unit.is_deployed()`): tiny Hazard Amber square pip.
       * `Unpowered` (`building.requires_power_grid and not building.is_powered`): subtle pulsing crimson diagonal slash across the tile.
       * `Producing / Overclocked` (for multi-selected buildings): tiny cyan or amber active progress dot.

### A.3 Pooled 24-Slot Grid & Pagination (`ui/hud/selection_wireframe_grid.gd`)

Create `class_name SelectionWireframeGrid extends VBoxContainer` to keep `selection_hud.gd` lean and modular:

* **Structure:**
  * Top child: `GridContainer` (`columns = 8`, `h_separation = 3`, `v_separation = 3`) pre-populated **once** in `_ready()` with **24 pooled `SelectionWireframeTile` children** (zero runtime instantiate/free churn!).
  * Bottom child (visible **only** when `entities.size() > 24`): ultra-compact `18 px` tall pagination strip (`[<]  PAGE 1 / 2  (32 SELECTED)  [>]`) with clickable page pills so large armies (e.g., 36 `Clone Troopers` or `Votaries`) remain 100% accessible without clipping `1280×720`.
* **Deterministic Entity Ordering:**
  * Display entities grouped cleanly by subgroup order (matching `SubgroupHelper` / `Tab` cycling order so the active subgroup appears cleanly clustered together and consistent with the Command Card!), sorted within each type by **HP ratio ascending or instance ID** (keep stable order by `instance_id` inside each type so tiles never jump under the player's cursor mid-fight while clicking to pull back a wounded unit!).
* **Lightweight Live Refresh (`0.15s` cadence):**
  * While visible, call `queue_redraw()` on active visible tiles every `0.15s` (and immediately on selection change) so taking damage, shield breaks, Optical Tether links, and veterancy rank-ups update smoothly with minimal CPU cost.

### A.4 Integration into `SelectionHUD` (`ui/hud/selection_hud.gd` & `.tscn`)

* Replace the legacy 12-slot text `unit_badges_grid` in multi-entity mode (`selected_units.size() > 1` or `selected_buildings.size() > 1`) with `SelectionWireframeGrid` (keep single-entity rich inspection telemetry intact when exactly `1` entity is selected!).
* Bind `SelectionWireframeGrid`'s click signals directly to `SelectionController`'s 4 new methods (`select_only_entity`, `deselect_entity`, `filter_selection_to_entity_type`, `remove_entity_type_from_selection`).
* Wire tile hover signals to the existing `CommandTooltip` (displaying `Display Name`, `HP: cur/max`, optional `SHD: cur/max`, `Rank` / `Lattice Link` / `Unpowered` status, and a subtle footer line: `LMB Isolate • Shift Remove • Ctrl Type`).
* Apply `FactionHudTheme` styling whenever the active faction or spectator theme updates.
* **Verify `1280×720` Footprint:** Confirm that `8 × 34 px + 7 × 3 px = 293 px` wide and `3 × 32 px + 2 × 3 px = 102 px` tall (+ `18 px` optional page bar) fits comfortably inside `SelectionHUD`'s center column without pushing the HUD upward or clipping `CommandCard` / `TacticalMinimap` at `1280×720` Windowed or `F11` Fullscreen.

---

## Phase B — 3-Faction Parity for Uplink Holdout

### B.1 `GameConfig`, `ModeRecords` & `MainMenu` Holdout UI

1. **`scripts/systems/game_config.gd` & `scripts/systems/mode_records.gd`:**
   * Verify `holdout_enemy_faction_id` accepts `&"genesis_v2"`, `&"monolith_os"`, `&"prisma_dei"`, and `&"mixed"`.
   * Verify `ModeRecords` persists and retrieves `holdout_best_wave` cleanly for all 3 playable factions (`genesis_v2`, `monolith_os`, `prisma_dei`) × all 3 difficulties (`Relaxed`, `Standard`, `Brutal`).
2. **`scripts/ui/main_menu.gd` & `scenes/ui/main_menu.tscn` (Holdout Tab):**
   * Add **`PRISMA_DEI` (`PRIS-DEI`)** to the Opposing Wave Faction selector alongside `GEN-V2`, `MONO-OS`, and `MIXED ASSAULT`.
   * Confirm selecting `PRISMA_DEI` on the left Faction Dossier column sets the player's defending faction for Holdout and refreshes the saved Best Wave readout cleanly.

### B.2 `PRISMA_DEI` Wave Compositions & Combat Ability Triggers (`scripts/systems/holdout_mode_controller.gd`)

1. **10 Escalating `PRISMA_DEI` Assault Waves (plus Endless Scaling for Wave 11+):**
   Design distinct, high-readability Divine Lattice waves that test target priority (sniping `Cantor` tether anchors, dodging `Solar Convergence`, focusing down `Lens Adjudicators` and `Seraph Cruisers` before beams hit max ramp):
   * **Wave 1:** `4× Votary` + `2× Lumen Skiff` *(Main lane radiant probe)*.
   * **Wave 2:** `5× Votary` + `2× Lumen Skiff` + `1× Cantor` *(Introduces Optical Tether anchor)*.
   * **Wave 3:** `6× Votary` + `2× Lens Adjudicator` + `1× Cantor` *(Introduces escalating anti-armor beams)*.
   * **Wave 4 (Dual-Lane):** `6× Votary` + `3× Lumen Skiff` + `2× Prism Weaver` + `1× Cantor` *(Refracting AoE & Blinding Glare flanks)*.
   * **Wave 5:** `6× Votary` + `3× Lens Adjudicator` + `2× Prism Weaver` + `2× Cantor`.
   * **Wave 6 (Multi-Angle Pressure):** `8× Votary` + `4× Lumen Skiff` + `3× Lens Adjudicator` + `2× Cantor` + `1× Seraph Cruiser` *(First Tier 2 flagship appearance)*.
   * **Wave 7:** `6× Votary` + `3× Prism Weaver` + `2× Seraph Cruiser` + `1× Solstice Lance` + `2× Cantor`.
   * **Wave 8:** `8× Votary` + `4× Lens Adjudicator` + `2× Seraph Cruiser` + `2× Solstice Lance` + `2× Cantor`.
   * **Wave 9:** `8× Votary` + `4× Prism Weaver` + `3× Seraph Cruiser` + `2× Solstice Lance` + `3× Cantor`.
   * **Wave 10 (Divine Convergence Apex Wave):** Multi-pronged assault across Center + North/South corridors: `10× Votary` + `4× Lens Adjudicator` + `3× Prism Weaver` + `4× Seraph Cruiser` + `3× Solstice Lance` + `3× Cantor`.
   * **Endless Waves (11+):** Scale Wave 10 composition deterministically by `+15–20%` per wave while rotating spawn corridors cleanly.
2. **Updated 3-Faction `MIXED ASSAULT` Pool:**
   * Update `MIXED ASSAULT` wave generation so waves rotate and blend all 3 factions (`GENESIS_V2`, `MONOLITH_OS`, and `PRISMA_DEI`) across Waves 1–10 and Endless Mode (e.g., `Bulwark` frontlines backed by `Cantor`-tethered `Lens Adjudicators`, or `Clone Trooper` swarms paired with `Prism Weavers` and `Anvil Siege-Walkers`).
3. **Lightweight Holdout Ability & Support Micro:**
   * Ensure Holdout-spawned `PRISMA_DEI` wave units fire their signature combat abilities on a clean `1.0s` timer (`solar_step`, `radiant_mark`, `focus_alignment`, `blinding_glare`, `aureole_surge`, `solar_convergence`; `luminous_mend` via autocast) and keep `Cantors` advancing cleanly alongside their wave squad rather than stalling behind.
   * Emit brief in-character `PRISMA_DEI` terminal radio lines on Waves 1, 5, and 10 via `TacticalEventFeed` when facing `PRISMA_DEI` waves (honoring `SettingsManager.show_ai_transmissions`).
4. **Playable `PRISMA_DEI` Defending Base Verification:**
   * Confirm that launching Uplink Holdout as `PRISMA_DEI` spawns `Sanctum Core` (with its built-in `290 px` Power Lattice and universal Biomass + Silica drop-off) + `3× Acolyte` cleanly with zero premature Victory/Defeat triggers, and that Wave-Clear Hyper-Uplink dividends award cleanly to `PRISMA_DEI`.

---

## Phase C — 3-Faction Parity for Micro Gauntlet

### C.1 Full `PRISMA_DEI` Support in `Optimal 3-Minute Boom` (Drill 3)

Audit `scripts/systems/gauntlet_mode_controller.gd` for Drill 3 (`optimal_3min_boom`):
* Confirm selecting `PRISMA_DEI` on the Main Menu launches `skirmish_arena_01.tscn` with `Sanctum Core` + `3× Acolyte` and `200B / 50S`.
* Confirm economy worker/harvester/specialist counting uses data-driven `unit.data.is_worker_class()` (counting `Acolyte`, `Prism Dredge`, and `Luminant`).
* Confirm Tier 2 completion detection for the **Gold Medal** check uses data-driven `building.is_military_production_building() and building.get_tech_tier() >= 2` (so `Synthetics Fabricator`, `Siege Gantry`, and **`Cathedral Foundry`** all qualify equally!).

### C.2 Two New Curated `PRISMA_DEI` Tactical Drills (Drills 4 & 5)

Add two deterministic, high-skill `PRISMA_DEI` drills to `GauntletModeController` (running on `scenes/test/milestone_0_test.tscn` with `SandboxDebugPanel` hidden, Fog of War OFF, and instant `[R] Retry`):

#### Drill 4 — `&"tether_weaving_mortars"` (*Tether Weaving vs. Mortar Splash* — `75s` Micro)
* **Theme:** Split-micro and tether geometry under live artillery pressure.
* **Player Squad (`PRISMA_DEI`, Team 0):**
  * `5× Votary` (`Solar Step` ready)
  * `2× Cantor` (Optical Tether anchors + `Luminous Mend`)
  * `2× Prism Weaver` (`Blinding Glare` ready + forward 2-link tethers)
* **Hostile Force (`GENESIS_V2`, Team 1):**
  * `3× Chrysalis Mortar` (positioned on elevated/rear fire line, actively lobbing telegraphed splash shells)
  * `2× Goliath Frame` (frontline bruisers)
  * `6× Clone Trooper` (screen)
* **Objective:** Eliminate all hostile `GENESIS_V2` units within `75s` by dodging mortar splash with `Solar Step`, keeping `Votaries` tethered to `Cantors`/`Prism Weavers` without clumping into splash zones, and shutting down enemy fire with `Blinding Glare` + refracting beam bounces.
* **Medal Thresholds:**
  * **Gold:** Clear in `<= 42s` with `>= 6` player units surviving (and `>= 1` `Cantor` alive).
  * **Silver:** Clear in `<= 58s` with `>= 4` player units surviving.
  * **Bronze:** Clear within `75s`.

#### Drill 5 — `&"escalating_beam_focus"` (*Escalating Beam Focus-Fire* — `75s` Micro)
* **Theme:** Sustained beam ramp-up, `Shift + Right-Click` priority targeting, and burst ability timing against heavy shielded armor.
* **Player Squad (`PRISMA_DEI`, Team 0):**
  * `3× Lens Adjudicator` (`Focus Alignment` ready)
  * `2× Seraph Cruiser` (`Aureole Surge` ready)
  * `2× Cantor` (Optical Tether anchors + `Luminous Mend`)
  * `2× Lumen Skiff` (`Radiant Mark` ready)
* **Hostile Force (`MONOLITH_OS`, Team 1):**
  * `3× Monolith Dreadnought` (heavy armored spearhead)
  * `3× Bulwark Automaton` (frontline screen)
  * `2× Aegis Relay` (rear shield overchargers—high-priority snipe targets!)
* **Objective:** Destroy the advancing `MONOLITH_OS` armored column within `75s` by marking priority targets with `Radiant Mark`, chaining focus-fire so `Lens Adjudicators` and `Seraph Cruisers` hit maximum beam ramp-up, timing `Focus Alignment` + `Aureole Surge`, and protecting fragile `Cantors`.
* **Medal Thresholds:**
  * **Gold:** Clear in `<= 45s` with `>= 6` player units surviving.
  * **Silver:** Clear in `<= 60s` with `>= 4` player units surviving.
  * **Bronze:** Clear within `75s`.

### C.3 `MainMenu` 5-Drill Gauntlet List & `NEXT DRILL` Flow (`1280×720` Safe)

* **`scenes/ui/main_menu.tscn` & `scripts/ui/main_menu.gd`:**
  * Wrap the Gauntlet drill cards container inside a sleek, bounded `ScrollContainer` (`horizontal_scroll_mode = SCROLL_MODE_DISABLED`, compact `~54–58 px` card height with drill title, short role/faction tag `[GEN]` / `[MONO]` / `[PRIS]` / `[ANY]`, Gold threshold hint, and saved Medal badge) so all **5 drills** browse effortlessly inside `ConfigPanel` (`448 px` wide) with **zero vertical overflow** at `1280×720` Windowed or Fullscreen (`F11`).
  * Ensure clicking a drill card updates `GameConfig.selected_gauntlet_drill_id` and displays its full objective & Gold/Silver/Bronze breakdown cleanly in the compact briefing footer above **`LAUNCH DRILL`**.
* **`ui/hud/match_end_overlay.gd` & `scripts/systems/gauntlet_mode_controller.gd`:**
  * Verify the **`NEXT DRILL`** button on the Gauntlet Result Modal cycles cleanly across all 5 drills (`stutter_step_bulwarks → siege_line_breach → optimal_3min_boom → tether_weaving_mortars → escalating_beam_focus`) and persists personal-best medals & times for Drills 4 and 5 in `ModeRecords`.

---

## Phase D — Verification & Playtest Checklist

1. **Clickable 24-Slot Wireframe Selection Grid (`milestone_0_test.tscn` & Skirmish):**
   * Select a mixed army of **15–30 units** across `GENESIS_V2`, `MONOLITH_OS`, and `PRISMA_DEI` (e.g., `12× Votary`, `4× Cantor`, `6× Lens Adjudicator`, `4× Seraph Cruiser`, `4× Lumen Skiff`):
     * Confirm the 8×3 wireframe grid renders crisp procedural vector icons tinted live by HP tier (green → amber → crimson), cyan shield bars on `MONOLITH_OS` units, veterancy gold pips, Optical Tether pips, and active `Tab` subgroup highlight frames.
     * Confirm pagination (`PAGE 1 / 2`) activates cleanly when `> 24` units are selected and allows switching pages without dropping selection.
     * Verify **Left-Click** isolates that exact single unit.
     * Verify **Shift + Left-Click** removes that exact unit from selection without disturbing the rest.
     * Verify **Ctrl + Left-Click** (and **Double-Left-Click**) filters selection strictly to all selected units of that type.
     * Verify **Ctrl + Shift + Left-Click** removes all units of that type from selection cleanly.
     * Verify clicking a wireframe tile while targeting an ability or placing a building never misfires onto the arena underneath.
   * Multi-select `4× Choir Basilica` (including 1 unpowered): confirm multi-building wireframe tiles render cleanly, flag unpowered status, and respond to all 4 click modifiers.
   * Inspect `SelectionHUD` across all 3 faction OS themes (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`) in **Windowed `1280×720`** and **Fullscreen (`F11`)**: confirm zero clipping or overlap with Command Card or Minimap.

2. **Uplink Holdout 3-Faction Parity:**
   * Launch Holdout as **`PRISMA_DEI`** defending against **`MONOLITH_OS`** waves, and as **`GENESIS_V2`** defending against **`PRISMA_DEI`** waves (plus **`MIXED ASSAULT`**):
     * Confirm `PRISMA_DEI` defending base boots cleanly with Power Lattice + universal Biomass/Silica `Sanctum Core` drop-off.
     * Confirm `PRISMA_DEI` enemy waves deploy `Votary`, `Lumen Skiff`, `Cantor` (projecting live Optical Tethers!), `Lens Adjudicator`, `Prism Weaver`, `Seraph Cruiser`, and `Solstice Lance`, cast combat abilities, and trigger victory + Endless mode + `ModeRecords` persistence cleanly.

3. **Micro Gauntlet 3-Faction Parity (`1280×720` Safe):**
   * Open `MainMenu → GAUNTLET` at `1280×720` Windowed & `F11` Fullscreen: confirm all **5 drill cards** scroll/display cleanly inside `ConfigPanel` with zero clipping.
   * Launch **Drill 3 (`Optimal 3-Minute Boom`)** as **`PRISMA_DEI`**: confirm `Sanctum Core`, `Acolyte`/`Prism Dredge`/`Luminant`, and `Cathedral Foundry` T2 Gold check track accurately.
   * Play and complete **Drill 4 (`Tether Weaving vs. Mortar Splash`)** and **Drill 5 (`Escalating Beam Focus-Fire`)**: confirm deterministic spawns, live Bronze/Silver/Gold timer readout, instant **`[R] Retry`** with zero leaked VFX/tethers, **`NEXT DRILL`** progression across all 5 drills, and persistent medal records across restarts.