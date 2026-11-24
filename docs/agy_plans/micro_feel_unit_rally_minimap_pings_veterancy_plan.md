# Milestone 2.1 Plan: Attack Range Settings, Stutter-Step Combat Feel, Unit-Follow Rally, Minimap Pings & Veterancy

**Target Directory:** `docs/agy_plans/22_micro_feel_rally_pings_and_veterancy.md`
**Primary Files:** `scripts/systems/settings_manager.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd`, `scripts/units/combat_component.gd`, `scripts/units/unit.gd`, `scripts/data/unit_data.gd`, `scripts/buildings/building.gd`, `scripts/buildings/production_component.gd`, `scripts/controllers/command_router.gd`, `scripts/controllers/selection_controller.gd`, `ui/overlays/rally_point_overlay.gd`, `ui/overlays/entity_visuals.gd`, `ui/hud/minimap.gd`, `ui/hud/selection_hud.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/audio_manager.gd`
**Reference Docs:** `docs/agy_plans/combat_feel_telegraphing_smart_targeting_plan.md`, `docs/agy_plans/keybinds_mouse_buttons_settings_polish_plan.md`, `docs/agy_plans/macro_hud_scoreboard_main_menu_polish_plan.md`

## 1. Objective & Scope

Build on top of the Milestone 2.0 combat telegraphing pass to elevate moment-to-moment **micro responsiveness**, **macro reinforcement flow**, and **battlefield awareness** before introducing Faction #2.

### In Scope

1. **Attack Range Display Mode Dropdown (`SettingsMenu` → `Gameplay` Tab):**
   * Replace any always-on attack-range ring behavior with a persistent 3-option dropdown in `SettingsManager` and `SettingsMenu`:
     * `0 = Always Show` — Renders subtle dashed `attack_range` (and `min_attack_range` for mortars) rings whenever friendly combat units are selected.
     * `1 = Show While Targeting` *(Default)* — Renders attack-range rings only while actively in `Attack-Move`, `Patrol`, or `Ability Target` cursor mode (keeps normal selection visually clean).
     * `2 = Don't Show` — Suppresses passive attack-range rings completely (while still showing explicit AoE ability targeting reticles).

2. **Attack-Move & Stutter-Step ("Kiting") Combat Feel (`combat_component.gd`, `unit.gd`, `unit_data.gd`):**
   * Split weapon firing into crisp **Windup (`fire_point`) → Cancelable Backswing → Cooldown** phases so microing **Clone Troopers**, **Stingers**, **Lance-Rigs**, and **Goliath Frames** feels snappy like classic competitive RTS games.
   * Issuing a Move order immediately after a shot fires cancels backswing instantaneously while `attack_cooldown` continues ticking down during movement.
   * Issuing a Move order *before* windup finishes cancels the windup cleanly without wasting `attack_cooldown`.
   * Issuing an explicit `Attack-Move` command triggers an **immediate** target acquisition check on the same physics tick (zero `0.25s` scan lag) so rapid `Move → A-Click → Move` kiting feels instant.

3. **Military Building Unit-Follow Rally Points (`building.gd`, `production_component.gd`, `command_router.gd`, `rally_point_overlay.gd`):**
   * Allow selecting any military production building (`Cloning Vat`, `Calibration Foundry`, `Synthetics Fabricator`, or `Nexus Vat`) and right-clicking a **friendly unit** to set a live **Unit-Follow Rally**.
   * `RallyPointOverlay` dynamically tracks the rallied unit's position with a crisp Technozen follow-tether and ring.
   * Newly spawned units automatically `Attack-Move` toward the rallied unit's live position (falling back cleanly to the unit's last known position if the target unit dies before spawn).

4. **Tactical Minimap Pings & Audio Alerts (`match_manager.gd`, `ui/hud/minimap.gd`, `audio_manager.gd`):**
   * Route combat/objective/completion alerts through a unified tactical alert pipeline with per-region throttling (`4.0s`) to prevent spam.
   * Render expanding, color-coded concentric ping rings (`~2.4s` decay) directly on `Minimap`:
     * **Crimson:** Unit or structure under attack.
     * **Amber / Gold:** **Data Hyper-Uplink** contested or captured.
     * **Cyan / Emerald:** Upgrade complete or heavy structure completed.
   * Pair each alert category with a distinct, non-intrusive procedural Technozen audio cue in `AudioManager`, synced directly with `Space` (`jump_last_alert`).

5. **Unit Kill Counts & Veterancy (`unit.gd`, `combat_component.gd`, `entity_visuals.gd`, `selection_hud.gd`):**
   * Track `kill_count: int` and `veterancy_rank: int` (`0..3`) on every combat unit, crediting kills from direct attacks, splash mortar shells, and damaging abilities.
   * Apply clean, readable 3-tier Veterancy progression (`Veteran` at 3 kills, `Elite` at 6 kills, `Apex` at 10 kills) with subtle stat scaling, diegetic rank chevron pips beside the unit's health bar, a brief rank-up visual/audio cue, and a `Kills / Rank` readout inside `SelectionHUD`.

### Out of Scope
* New factions, units, structures, or upgrades beyond `GENESIS_V2`.
* Squad formation/concave pathing rewrites.
* Capturable Sensor Relays or Engineer repair mechanics.

---

## 2. Detailed Technical Specifications

### 2.1 Attack Range Display Dropdown (`settings_manager.gd`, `settings_menu.tscn/.gd`, `entity_visuals.gd`)
* **`SettingsManager`:**
  * Add `enum AttackRangeMode { ALWAYS_SHOW, SHOW_WHILE_TARGETING, DONT_SHOW }` and `var attack_range_mode: int = AttackRangeMode.SHOW_WHILE_TARGETING`.
  * Persist under `[gameplay]` (`attack_range_mode`) in `user://settings.cfg`, include in `reset_defaults()`, and emit `settings_changed.emit(&"gameplay")` on change.
* **`SettingsMenu` (`Gameplay` Tab):**
  * Add an `OptionButton` labeled **"Attack Range Indicator"** with options:
    * `Always Show`
    * `Show While Targeting`
    * `Don't Show`
  * Keep the `Gameplay` tab layout cleanly within `ModalPanel` at `1280×720` and Fullscreen.
* **`SelectionController` & `Unit` / `EntityVisuals`:**
  * Expose a lightweight helper `SelectionController.is_targeting_command_active() -> bool` (returns `true` while `Attack-Move`, `Patrol`, or `Ability Target` cursor mode is active) and trigger `queue_redraw()` on selected units when entering/exiting targeting mode.
  * In `unit.gd` / `entity_visuals.gd`, gate the dashed `attack_range` and `min_attack_range` ring drawing on `SettingsManager.attack_range_mode`:
    * `ALWAYS_SHOW`: draw whenever `is_selected` and unit has `attack_range > 0`.
    * `SHOW_WHILE_TARGETING`: draw only when `is_selected` and `is_targeting_command_active()` is `true`.
    * `DONT_SHOW`: never draw passive attack-range rings.

### 2.2 Stutter-Step ("Kiting") & Attack-Move Responsiveness (`combat_component.gd`, `unit.gd`, `unit_data.gd`)
* **Windup & Cancelable Backswing (`unit_data.gd` & `combat_component.gd`):**
  * Add `@export var attack_windup: float = 0.08` to `UnitData` (sensible defaults per role if unset: fast infantry `0.06s`, heavy walkers `0.12s`, artillery/beams `0.16s`).
  * Track `enum AttackPhase { IDLE, WINDUP, BACKSWING }` and `_windup_timer: float` / `_backswing_timer: float` (`~0.10s` visual follow-through) in `CombatComponent`:
    * When a valid target is in range and `attack_cooldown <= 0.0`: face the target, enter `WINDUP`, and count down `_windup_timer`.
    * When `_windup_timer <= 0.0`: fire the weapon (apply damage / spawn tracer / mortar shell / SFX), start `attack_cooldown = effective_attack_interval`, and enter `BACKSWING`.
    * **Cancelable Backswing:** Any `Move` order immediately clears `BACKSWING` and allows full movement speed on that exact frame, while `attack_cooldown` continues ticking down in `_physics_process()`.
    * **Cancelable Windup:** If a `Move` order arrives *during* `WINDUP` (before the fire point), cancel `WINDUP` cleanly without resetting `attack_cooldown`.
* **Instant Attack-Move Acquisition (`unit.gd` & `combat_component.gd`):**
  * Add `force_immediate_target_scan()` on `CombatComponent` and invoke it whenever a unit receives a fresh `ATTACK_MOVE` command. If an enemy is already within `attack_range` and `attack_cooldown <= 0.0`, the unit skips waiting for the periodic `0.25s` scan timer and begins `WINDUP` immediately.
  * Keep unit facing smoothly aligned toward the attack target during `WINDUP` so stutter-step shots read crisply.

### 2.3 Military Building Unit-Follow Rally Points (`building.gd`, `production_component.gd`, `command_router.gd`, `rally_point_overlay.gd`)
* **Rally Target Storage (`building.gd`):**
  * Add `var rally_target_unit: Unit = null` alongside `rally_point: Vector2`.
  * Add `set_rally_target_unit(target_unit: Unit)` (clears any resource-node rally and stores `rally_target_unit`, updating `rally_point = target_unit.global_position` as a live fallback) and clear `rally_target_unit = null` whenever a ground or resource-node rally is set.
* **Command Routing (`command_router.gd`):**
  * When right-clicking a **friendly `Unit`** while one or more friendly production buildings are selected, call `building.set_rally_target_unit(clicked_unit)` (ignoring self-clicks on buildings and preserving existing worker rally-to-resource behavior on `Nexus Vat` / `Silica Condenser`).
  * Trigger a crisp confirmation ping/marker on the target unit and play `AudioManager` order SFX.
* **Dynamic Spawn Routing (`production_component.gd`):**
  * When a newly produced unit exits a building:
    * If `is_instance_valid(building.rally_target_unit)` and `building.rally_target_unit.is_alive()`:
      * Update `building.rally_point = building.rally_target_unit.global_position`.
      * Issue `unit.issue_attack_move(building.rally_target_unit.global_position)` for combat units (or `issue_move_to(...)` for non-combat support units like `Symbiote` so they catch up to the rallied squad cleanly).
    * If `rally_target_unit` was destroyed, clear `rally_target_unit = null` and route the spawned unit to the last recorded `building.rally_point`.
* **Visual Tether (`rally_point_overlay.gd`):**
  * When a selected building has a valid `rally_target_unit`, draw the dashed Technozen rally line dynamically to `rally_target_unit.global_position` (tinted bright cyan/emerald) with a subtle orbiting chevron/ring around the rallied unit.

### 2.4 Tactical Minimap Pings & Audio Alerts (`match_manager.gd`, `ui/hud/minimap.gd`, `audio_manager.gd`)
* **Unified Alert Pipeline (`match_manager.gd`):**
  * Emit signal `tactical_alert_triggered(world_pos: Vector2, alert_type: StringName, message: String)`.
  * Provide `push_tactical_alert(world_pos: Vector2, alert_type: StringName, message: String = "")` with spatial + temporal throttling (e.g., ignore duplicate `under_attack` alerts within `300px` for `4.0s`).
  * Forward every pushed alert's `world_pos` into the existing `Last Alert Jump (Space)` ring buffer in `RTSCamera` / `MatchManager`.
  * Trigger alerts from:
    * `Team.PLAYER` unit or building taking damage (`&"under_attack"`).
    * **Data Hyper-Uplink** contested or captured (`&"uplink_contested"`).
    * Research upgrade or Tier-2/military structure completion (`&"tech_complete"`).
* **Minimap Ping Rendering (`ui/hud/minimap.gd`):**
  * Connect to `MatchManager.tactical_alert_triggered` and store active pings (`pos`, `color`, `age`, `duration = 2.4`).
  * Draw two staggered expanding rings + a bright center diamond in `_draw()`, fading smoothly to alpha `0` over `2.4s`, ensuring pings stay clearly visible above Fog of War and terrain layers.
* **Distinct Alert SFX (`audio_manager.gd`):**
  * Add procedural Y2K cues for `alert_under_attack` (urgent two-tone low-mid pulse), `alert_uplink` (resonant ascending sonar ping), and `alert_complete` (crisp harmonic chime), respecting `SettingsManager` UI volume and `show_alert_toasts` / mute settings.

### 2.5 Unit Kill Counts & Veterancy (`unit.gd`, `combat_component.gd`, `entity_visuals.gd`, `selection_hud.gd`)
* **Kill Attribution (`unit.gd` & `combat_component.gd`):**
  * Add `var kill_count: int = 0` and `var veterancy_rank: int = 0` on `Unit`.
  * Pass optional `attacker: Node = null` into `take_damage(amount: float, attacker: Node = null)` on `Unit` and `Building` (backward-compatible default `null`).
  * When an entity's HP drops to `<= 0`, if `is_instance_valid(attacker)` and `attacker is Unit` and `attacker.team != team`, call `attacker.register_kill(self)`.
* **Veterancy Tiers (`unit.gd`):**
  * `Rank 0 (Standard)`: `0–2` kills.
  * `Rank 1 (Veteran)`: `3+` kills → `+8%` attack speed (`0.92x` interval), `+5%` max HP.
  * `Rank 2 (Elite)`: `6+` kills → `+15%` attack speed (`0.85x` interval), `+10%` max HP.
  * `Rank 3 (Apex)`: `10+` kills → `+22%` attack speed (`0.78x` interval), `+15%` max HP.
  * When crossing a rank threshold: increase `max_hp` cleanly and heal `current_hp` by the HP delta, spawn a subtle gold promotion pulse in `combat_vfx.gd` (or `entity_visuals.gd`), and play a light rank-up chime for `Team.PLAYER` units.
* **Diegetic Chevrons & HUD Readout (`entity_visuals.gd` & `selection_hud.gd`):**
  * Draw 1–3 crisp miniature chevron pips (silver/cyan for Rank 1–2, luminous gold for Rank 3) beside the unit's health bar / badge when `veterancy_rank > 0`.
  * In `SelectionHUD`'s single-unit inspector panel, show `RANK: VETERAN (4 KILLS)` (or `KILLS: 2` for Rank 0 combat units) cleanly without overflowing the card at `1280×720`.

---

## 3. File & Architecture Summary

### Existing Files to Extend
* `scripts/systems/settings_manager.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd` (Add `AttackRangeMode` enum, persistence, and `Gameplay` tab dropdown).
* `scripts/data/unit_data.gd`, `scripts/units/combat_component.gd`, `scripts/units/unit.gd` (Windup/backswing stutter-step phases, instant `Attack-Move` scan, `kill_count`, `veterancy_rank`, and `attacker` attribution in `take_damage()`).
* `scripts/buildings/building.gd`, `scripts/buildings/production_component.gd`, `scripts/controllers/command_router.gd`, `ui/overlays/rally_point_overlay.gd` (Dynamic `rally_target_unit` follow-rally, fallback to last position on death, and live visual tether).
* `scripts/systems/match_manager.gd`, `ui/hud/minimap.gd`, `scripts/systems/audio_manager.gd` (Throttled tactical alert pipeline, pulsing color-coded minimap ping rings, and procedural alert SFX synced with `Space` alert jump).
* `scripts/controllers/selection_controller.gd`, `ui/overlays/entity_visuals.gd`, `ui/hud/selection_hud.gd` (Targeting-mode check for attack-range rings, veterancy chevron pips, and kill/rank inspector readout).

---

## 4. Verification Checklist for `agy`

Before concluding Milestone 2.1, verify in `scenes/test/milestone_0_test.tscn` and `scenes/maps/skirmish_arena_01.tscn`:

* [ ] **Attack Range Dropdown:** Open **Settings → Gameplay**, switch **Attack Range Indicator** between `Always Show`, `Show While Targeting`, and `Don't Show`; confirm rings update live on selected units (including **Chrysalis Mortar** dual rings), appear during `A` (`Attack-Move`) / `P` (`Patrol`) / ability targeting in `Show While Targeting` mode, and persist across restarts in `user://settings.cfg`.
* [ ] **Stutter-Step / Kiting Feel:** Micro a small squad of **Clone Troopers** or **Lance-Rigs** against pursuing **Stingers** using rapid `Right-Click → A-Click → Right-Click`; confirm units shoot immediately upon `A-Click` when cooldown is ready, move instantaneously after the shot fires without sluggish backswing lock, and cancel pre-fire windups cleanly without losing their shot cooldown.
* [ ] **Unit-Follow Rally Points:** Select 2 **Cloning Vats**, right-click a friendly **Goliath Frame** (or **Clone Trooper**), and walk that unit across the map; verify the rally line dynamically follows the unit, newly trained clones `Attack-Move` straight to its live position, and destroying the rallied unit falls back smoothly to its last position.
* [ ] **Tactical Minimap Pings & Alerts:** Trigger combat damage, contest the **Data Hyper-Uplink**, and complete an upgrade; verify color-coded pulsing rings render on `Minimap`, distinct alert SFX play without spamming, and pressing `Space` snaps the camera directly to the latest ping.
* [ ] **Kill Counts & Veterancy:** Let a **Goliath Frame** or **Clone Trooper** score 3, 6, and 10 kills (testable rapidly in `SandboxDebugPanel`); verify `SelectionHUD` increments `Kills` and updates rank (`Veteran` → `Elite` → `Apex`), chevron pips appear on the unit, attack speed & max HP scale cleanly, and zero Godot Debugger errors occur.