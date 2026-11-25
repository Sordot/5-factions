# Milestone 3.1 — Building Macro Hotkeys, Compact Icon Command Card & Faction-Themed HUD Flair

**Goal:**
1. Give friendly **buildings** full keyboard macro hotkeys (`Q/W/E` train, `Shift+Q/W/E` ×5 batch, `R/T` upgrades, `F` facility specials like `Core Overclock` and `Eject Engineers`) so players can macro without clicking buttons.
2. Overhaul `SelectionHUD` from oversized text buttons into a compact, StarCraft-style **4×3 procedural vector icon Command Card** (`44×44 px` tiles) with live corner hotkey badges and rich `CommandTooltip` hover readouts—eliminating all `1280×720` horizontal overflow permanently.
3. Add **faction-specific HUD & Command Card theming** so `GENESIS_V2` (*Technozen Bio-Synth*) and `MONOLITH_OS` (*Neo-Brutalist Halftone*) each have distinct border flair, corner geometry, colors, and button styling.

**Non-Negotiable Constraints:**
* **Strict `1280×720` UI Discipline:** `SelectionHUD` must lock to **`<= 750 px` total width** so it sits cleanly between the `244 px` `TacticalMinimap` (bottom-left) and `TacticalEventFeed` (bottom-right) with zero clipping in both Windowed `1280×720` and Fullscreen (`F11`).
* **100% Procedural Pipeline:** All command icons and faction border flair are drawn procedurally via Godot 2D `_draw()` / `StyleBoxFlat` (zero external image assets).
* **Zero Regression:** Preserve all unit selection, `Tab` subgroup cycling, `Shift`-queuing, Auto-Cast right-click toggling, and Spectator/Post-Match read-only inspection.

---

## Phase A — Building Macro Hotkeys (`scripts/controllers/selection_controller.gd`)

Extend `SelectionController` so pressing `cmd_ability_q / w / e / r / t / f` while friendly constructed building(s) are selected executes building actions cleanly:

### A.1 Canonical Building Hotkey Map
* **`Q`, `W`, `E`** (`cmd_ability_q`, `cmd_ability_w`, `cmd_ability_e`) → Trainable unit slots **`0`, `1`, `2`** on the selected building(s).
  * **Normal Press:** Calls `queue_unit_distributed(u_data)` (load-balances across all selected compatible buildings, or queues on the single selected building).
  * **`Shift + Q/W/E`:** Calls `queue_unit_distributed_batch(u_data, 5, lead_building)` (queues ×5 distributed across selected compatible buildings, matching existing `Shift+Click` behavior).
* **`R`, `T`** (`cmd_ability_r`, `cmd_ability_t`) → Researchable upgrade slots **`0`, `1`** on the lead selected building (or first selected compatible building that can research it).
* **`F`** (`cmd_ability_f`) → **Facility Special** action:
  * If `has_selected_overclock_hub()`: toggles/starts `Core Overclock` targeting (`begin_overclock_targeting()` / `cancel_overclock_targeting()`). *(Moving `Core Overclock` from `E` to `F` eliminates the hotkey collision with `Foundry Core`'s 3rd unit slot `E` = `Grid-Tech`!)*
  * Else if selected building(s) have `max_staff_slots > 0`: calls `eject_engineers_from_selected_buildings()`.
* **Cancel Build / Salvage:** Remains **click-only** (no hotkey) to prevent accidental mid-macro structure deletion.

### A.2 Input Routing (`SelectionController._unhandled_input`)
* Add helper `func _try_handle_building_hotkey_event(event: InputEvent, action_name: StringName, slot_kind: StringName, slot_index: int) -> bool`:
  * Only triggers when `selected_units.is_empty()` and (`not selected_buildings.is_empty()` or (`selected_building != null` and owned by local human)).
  * Ignores events with `ctrl_pressed`, `alt_pressed`, or `echo`.
  * Reads `shift_queued = Input.is_key_pressed(KEY_SHIFT) or key_ev.shift_pressed`.
  * For `slot_kind == &"train"`: resolves `u_data` from lead building's `trainable_unit_data[slot_index]` and queues 1 (or 5 if `shift_queued`).
  * For `slot_kind == &"upgrade"`: resolves `upg` from lead building's `researchable_upgrades[slot_index]` and queues research on the first selected building where `can_research_upgrade(...)` is true (or calls `queue_upgrade_research` on lead to surface insufficient-resource feedback).
  * For `slot_kind == &"facility_special"`: runs Overclock targeting or Eject Engineers.
  * Calls `get_viewport().set_input_as_handled()` when matched.
* Update the existing `cmd_ability_e` Overclock/Eject block so `E` no longer steals `Foundry Core`'s `Grid-Tech` training slot (keep `E` working for `Eject Engineers` *only* on buildings with `trainable_unit_data.is_empty()`, while `F` always works for both Overclock and Eject).

---

## Phase B — Procedural Icon Tile Widget (`ui/hud/command_icon_button.gd`)

Create a lightweight, reusable `class_name CommandIconButton extends Button` (`44×44 px` fixed square tile, `focus_mode = FOCUS_NONE`) that replaces all wide text buttons in `SelectionHUD`:

### B.1 Tile Anatomy (`44×44 px`)
* **Background & Border:** Styled dynamically by the active faction theme (see Phase D).
* **Center Procedural Vector Icon (`28×28 px` centered):** Drawn in `_draw()` based on `icon_id: StringName` and `icon_category: StringName`:
  * **Standard Unit Commands:**
    * `&"cmd_move"` (directional chevron arrow)
    * `&"cmd_stop"` (crisp octagon / stop square)
    * `&"cmd_hold"` (shield-anchor / crossed-post)
    * `&"cmd_defensive"` (shield with dashed leash arc)
    * `&"cmd_patrol"` (looping bidirectional arrows)
    * `&"cmd_amove"` (crimson target crosshair)
  * **Facility & Utility Actions:**
    * `&"overclock"` (amber lightning bolt inside gear/frame)
    * `&"deploy"` (4 outward/inward anchor clamps + cannon barrel)
    * `&"auto_repair"` (wrench + plus cross)
    * `&"eject_engineers"` (upward eject arrow out of monolith frame)
    * `&"salvage"` / `&"cancel_build"` (crisp red/amber `×` / recycle-break icon)
  * **Units, Buildings, Abilities & Upgrades:**
    * Compact, high-contrast vector glyphs matching each archetype's visual identity (e.g., `worker`/`servo_drone` claw/block, `harvester`/`ore_crawler` scoop, `engineer`/`grid_tech` hex/clamp, `clone_trooper` rifle/visor, `stinger` speed-dart, `symbiote` bio-cross orb, `bulwark_automaton` bulkhead shield, `picket_drone` wedge/tether, `rail_sentinel` rail lance, `aegis_relay` shield prism, `anvil_siege_walker` quadruped cannon, `monolith_dreadnought` heavy fortress mech, `null_grid_projector` grav dish; building outlines with role pips; upgrade upward chevrons; ability bursts).
* **Top-Left Hotkey Badge:** Crisp `9 px` bold corner tag (`Q`, `W`, `E`, `R`, `T`, `F`, `S`, `H`, `D`, `P`, `A`, or rebound short label from `SettingsManager.get_action_short_label()`).
* **Bottom-Right Status Pill (when applicable):**
  * `×2` for batch-cloning units (`Cloning Vat`).
  * `ON` / `OFF` tiny dot or highlight for `Hold`, `Defend`, `Deploy`, `Auto-Repair`.
  * `DONE` (emerald) or `ACT` (amber) for upgrades.
  * `LOCK` (crimson) when prerequisite building is missing.
* **Cooldown / Unaffordable Overlay:**
  * Dark translucent fill sweep when on cooldown + centered `4.2s` / `34s` numeric countdown.
  * Muted desaturation tint when unaffordable (still clickable so clicking triggers the insufficient-resource toast/SFX).
* **Auto-Cast Border:** Reuse `_AutoCastBorderOverlay` as a child of `CommandIconButton` when `allow_autocast == true` (right-click toggles Auto-Cast).

---

## Phase C — Compact 4×3 Command Card & `SelectionHUD` Layout Overhaul (`ui/hud/selection_hud.tscn` & `ui/hud/selection_hud.gd`)

### C.1 Fixed Compact Panel Dimensions (`1280×720` Safe)
* Update `BottomStack` and `BottomPanel` in `ui/hud/selection_hud.tscn` and `_adjust_layout_for_minimap()` in `ui/hud/selection_hud.gd`:
  * Target total panel width: **`740 px`** (`desired_half_w = 370.0`), height **`~164 px`**.
  * **Left Column (`custom_minimum_size.x = 176 px`):** Compact portrait swatch, unit/building name (clipped with ellipsis if long), subtitle, HP + Shield bars, and primary gauge.
  * **Center Column (`size_flags_horizontal = SIZE_EXPAND_FILL`, `~320 px`):**
    * Multi-unit selection: Subgroup tabs (compact `10 px` pills) + `UnitBadgesGrid`.
    * Single-entity / Building: Compact 2-column `TelemetryGrid` + `ProductionQueueBox` (progress bar + clickable `[1..5]` cancel slots).
  * **Right Column (`custom_minimum_size.x = 204 px`):**
    * Replace the separate wide `StandardCommandsRow` + `AbilityRow` text grids with a **single unified 4-column `CommandGrid` (`columns = 4`, `h_separation = 4`, `v_separation = 4`)** holding up to **12 `CommandIconButton` (`44×44 px`) tiles** (`4×44 + 3×4 = 188 px` wide, `3×44 + 2×4 = 140 px` tall).
* **Grid Slot Mapping:**
  * **For Selected Units:**
    * Row 1 (Slots 0–3): `Move (RMB)`, `Stop (S)`, `Hold (H)`, `Defend (D)`
    * Row 2 (Slots 4–5): `Patrol (P)`, `Atk-Move (A)` + unit's first 2 abilities/build slots
    * Row 3 (Slots 8–11): Remaining abilities / build slots / `Deploy (E)` / `Auto-Repair`
    * *(For `Servo-Drone` with 8 build abilities + Auto-Repair = 9 slots, hide `Patrol` & `Atk-Move` on unarmed workers so `Move / Stop / Hold` + 8 buildings + `Auto-Repair` = **12 exact slots** in the 4×3 grid!)*
  * **For Selected Friendly Buildings:**
    * Row 1 (Slots 0–2): Trainable units `0..2` (`Q`, `W`, `E`)
    * Row 2 (Slots 4–5): Researchable upgrades `0..1` (`R`, `T`)
    * Row 3: `Facility Special (F)` (`Core Overclock` or `Eject Engineers`) in Slot 8; `Salvage (50%)` or `Cancel Build (75%)` pinned cleanly to bottom-right Slot 11.
  * **Empty Slots:** Render subtle dark recessed placeholder sockets so the 4×3 Command Card silhouette stays rock-solid and never jumps in size when switching selections.
* **Hover Tooltips (`CommandTooltip`):**
  * Keep all existing rich tooltip data (full name, live rebound hotkey, resource/BW cost, build/research time, traits, cooldown, `[Shift+Q/Click: Queue x5]`, `[Right-Click: Auto-Cast]`, and full description) on hover over every `CommandIconButton`.

---

## Phase D — Faction-Themed Command Card & Selection HUD Flair (`ui/hud/selection_hud.gd` & `scripts/data/faction_data.gd`)

Give `SelectionHUD` a dynamic faction visual skin that automatically adapts to the local human player's `FactionData` (or the inspected entity's team faction in Spectator Mode):

### D.1 Theme Resolution
* Add a helper `_resolve_active_hud_faction_id() -> StringName` in `SelectionHUD`:
  * In normal play: reads `TeamManager.get_team_faction(TeamManager.get_local_human_team())`.
  * In Spectator Mode: reads the inspected entity's team faction (`&"genesis_v2"` fallback).
* Re-apply the faction theme in `_ready()` and whenever `TeamManager.teams_reconfigured` fires (or inspected faction changes in Spectator Mode).

### D.2 Distinct Faction Visual Styles
Attach a lightweight `mouse_filter = MOUSE_FILTER_IGNORE` procedural `_FactionHudFrameOverlay` (`Control` covering `BottomPanel`) plus dynamic `StyleBoxFlat` overrides for `BottomPanel` and `CommandIconButton`:

1. **`GENESIS_V2` (*Technozen / Y2K Bio-Synth*):**
   * **Panel:** Deep translucent slate-teal (`Color(0.04, 0.08, 0.12, 0.92)`), smooth `6 px` rounded corners, crisp `1.5 px` glowing cyan/emerald border (`#20F5DC`).
   * **Border Flair (`_draw()`):** Thin glowing top/bottom telemetry scanline accents, small circular bioluminescent corner nodes (`3 px` dots with soft outer rings), and subtle vertical circuit divider lines separating Left / Center / Command Card columns.
   * **Icon Tiles:** `4 px` rounded dark-teal glass sockets with cyan border on hover, emerald-cyan active glow, and soft cyan hotkey badges.

2. **`MONOLITH_OS` (*Neo-Brutalist Halftone*):**
   * **Panel:** Matte concrete/gunmetal (`Color(0.15, 0.165, 0.185, 0.96)`), sharp **`0 px` / `2 px` corners**, thick `3 px` stark dark-ink (`#0A0D12`) outer border with a crisp `1.5 px` inner off-white (`#F2EFE9`) frame and a hard offset drop-shadow.
   * **Border Flair (`_draw()`):** Bold **Hazard Amber (`#FF9F1C`)** top-left & bottom-right L-brackets, subtle diagonal hazard-stripe header bar above the Command Card, and a crisp **procedural halftone dot-matrix band** along the panel's lower-right corner and behind empty command sockets.
   * **Icon Tiles:** Sharp `0 px` brutalist dark-slab tiles (`#23262B`) with `2 px` dark-ink borders, hard `2 px` inner shadow, stark off-white / Hazard Amber hover border, and bold amber corner hotkey badges.

3. **Future Factions (#3–#5 Fallback):**
   * Automatically tints the clean Technozen panel border, divider lines, and hotkey badges using `FactionData.hud_accent_color` and `FactionData.primary_color` so future factions inherit themed HUDs out of the box.

---

## Phase E — Verification Checklist

1. **Building Hotkeys:**
   * Select `Nexus Vat` / `Foundry Core`: press `Q`, `W`, `E` to train Workers/Harvesters/Engineers; press `Shift+Q` to queue ×5; verify zero mouse clicks required.
   * Select `Foundry Core`: press `F` to enter `Core Overclock` targeting and verify `E` trains `Grid-Tech` without collision.
   * Select `Wetware Mainframe` / `Logic Monolith` with staffed Engineers: press `F` (or `E`) to eject Engineers.
   * Select `Cloning Vat` / `Ballistics Lab` / `Siege Gantry`: press `R` / `T` to start upgrades.
   * Multi-select 2–3 `Cloning Vats` / `Assembly Bays`: press `Q` and `Shift+Q` to verify load-balanced queuing across all selected structures.
2. **Compact Icon Command Card & `1280×720` Audit:**
   * Test in **Windowed `1280×720`** and **Fullscreen (`F11`)**: select `Worker`, `Servo-Drone` (all 8 buildings + Auto-Repair), `Clone Trooper`, `Anvil Siege-Walker`, `Foundry Core`, `Siege Gantry`, and a mixed multi-unit squad.
   * Confirm `SelectionHUD` stays strictly `<= 750 px` wide, never clips off-screen, never overlaps `TacticalMinimap` or `TacticalEventFeed`, and displays rich `CommandTooltip` details on hover for every icon tile.
3. **Faction HUD Flair:**
   * Launch a match as `GENESIS_V2`: verify rounded Technozen cyan/emerald glass framing and corner bio-nodes.
   * Launch a match as `MONOLITH_OS`: verify sharp Neo-Brutalist gunmetal framing, thick ink borders, Hazard Amber brackets, and procedural halftone corner dots.