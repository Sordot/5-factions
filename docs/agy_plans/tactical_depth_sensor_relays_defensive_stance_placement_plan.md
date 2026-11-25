# Milestone 2.7 Plan: Capturable Sensor Relays, Defensive Stance, Extensible Mechanics Hooks & Smart Placement

**Target Directory:** `docs/agy_plans/33_tactical_depth_relays_defensive_stance_and_placement.md`
**Primary New Files:** `scripts/world/sensor_relay.gd`, `scenes/world/sensor_relay.tscn`
**Primary Extended Files:** `project.godot`, `scripts/systems/fog_of_war.gd`, `scripts/systems/settings_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/systems/match_manager.gd`, `scripts/units/unit.gd`, `scripts/units/combat_component.gd`, `scripts/units/movement_component.gd`, `scripts/units/status_effect_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/data/unit_data.gd`, `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`, `ui/overlays/build_ghost_preview.gd`, `ui/overlays/entity_visuals.gd`, `ui/hud/selection_hud.gd`, `ui/hud/minimap.gd`, `scripts/ui/settings_menu.gd`, `scenes/ui/settings_menu.tscn`, `scenes/maps/skirmish_arena_01.tscn`, `scenes/maps/skirmish_arena_02.tscn`, `scenes/maps/skirmish_arena_03.tscn`
**Reference Docs:** `docs/agy_plans/32_ai_tactics_staging_scouting_and_map_awareness.md`, `docs/agy_plans/28_ffa_arena_lobby_teams_decals_and_camera_feel.md`, `docs/agy_plans/engine_hardening_salvage_auto_cast_los_audio_polish.md`

## 1. Objective & Scope

Add the remaining battlefield-control and micro-ergonomic systems before the Milestone 2.8 data-driven faction gatekeeper pass, while hardening `StatusEffectComponent` and `CombatComponent` with clean, **generic** extensibility hooks for future Faction #2–#5 mechanics (explicitly excluding stealth/cloaking).

### In Scope

1. **Capturable Sensor Relays (`SensorRelay`):**

   * Create a neutral capturable **Sensor Relay** world structure placed on flank lanes across `skirmish_arena_01`, `skirmish_arena_02`, and `skirmish_arena_03`.

   * Holding the pad with any unit (non-worker or worker) activates a wide, unobstructed Fog-of-War vision circle for the controlling **alliance** (`TeamManager.are_allies()`), immediately going neutral/contested if opposing alliances occupy the pad simultaneously or if the holding unit leaves.

   * Render a crisp Technozen rotating radar/dish visual, diegetic capture radius ring, minimap radar-eye icon, and subtle `SkirmishAI` scout awareness.

2. **Defensive Stance with Leash (`Unit`, `CombatComponent`, `MovementComponent`, `SelectionHUD`):**

   * Add a **Defensive Stance** (`DEFENSIVE`) alongside `AGGRESSIVE` (default) and `HOLD_POSITION`, accessible from the `SelectionHUD` command card and a rebindable hotkey (`cmd_defensive_stance`, default **`D`** if unused—verify zero conflict in `project.godot`, otherwise **`G`**).

   * Units in `DEFENSIVE` stance anchor to their current post (`_defensive_anchor: Vector2`), engage hostile targets that enter aggro range, pursue only up to a tight **leash radius** (`~260 px` from `_defensive_anchor`), and automatically disengage and return to their post if baited farther away or once the threat is cleared.

3. **Generic Extensible Mechanics Hooks (No Stealth/Cloaking):**

   * Keep `StatusEffectComponent`, `CombatComponent`, `TurretComponent`, and `UnitData` clean and extensible for future asymmetric faction mechanics (shields/barriers, DoTs, regen auras, EMP/silences, damage-reduction states, or faction-specific resource/tether mechanics) **without** implementing stealth, cloaking, or detector mechanics.

   * Standardize a lightweight **Gameplay Tag & Modifier Hook Pipeline** so future factions can attach custom behaviors via `StatusEffectComponent` without editing core combat loops.

4. **Smart Building Placement Overlays (`BuildGhostPreview`, `CommandRouter`, `SettingsManager`):**

   * While placing a building ghost, project contextual Technozen visual guides:

     * **Turret Structures (`has_turret == true`):** Dashed `turret_attack_range` (and `turret_min_range` if applicable) firing ring.

     * **Economy Hubs (`Nexus Vat`, `Silica Condenser`):** Subtle optimal drop-off tether lines + distance readouts to nearby `BiomassNode`s or `SilicaVein`s within cluster radius (`~450 px`), highlighting which patches the new hub will service.

     * **Supply / Tech Structures (`Synapse Pylon`, `Wetware Mainframe`):** Clean spacing/alignment guides relative to nearby friendly buildings.

   * Add an optional **Building Grid-Snap** toggle (`build_grid_snap_enabled: bool = false`, `32 px` snap increment, plus holding `Alt` while placing to temporarily invert snap) in **Settings → Gameplay**.

### Out of Scope

* Stealth, cloaking, invisibility shaders, or detector units/rings (explicitly excluded by design).

* Faction #2 unit/building rosters or `FactionData` manifest refactoring (scheduled for Patch 2.8).

* Post-match "Inspect Battlefield" mode (scheduled for Patch 2.9).

## 2. Phase A: Capturable Sensor Relays

### A.1 `SensorRelay` World Entity (`scripts/world/sensor_relay.gd` & `scenes/world/sensor_relay.tscn`)

* **Node Architecture:** `Node2D` added to group `"sensor_relays"` (non-blocking pad with a compact central Technozen spire/pedestal so units can stand directly inside the capture zone).

* **Exported Properties:**

  * `relay_name: String = "Sensor Relay"`

  * `capture_radius: float = 115.0`

  * `vision_radius: float = 520.0` (grants wide tactical awareness over flank lanes and approaches)

  * `ignores_los_blockers: bool = true` (elevated relay Dish sees cleanly over nearby `TerrainObstacle` shadows)

* **Alliance-Aware Control Logic (`_physics_process` throttled at `0.2s`):**

  * Query `SpatialGrid.query_units_in_radius(global_position, capture_radius)` for living units.

  * Group present units by `TeamManager.get_alliance_id(unit.team)`:

    * **0 alliances present:** `controlling_team = -1`, `controlling_alliance = -1`, `state = IDLE` (neutral).

    * **1 alliance present:** Activate immediately for that alliance (`controlling_team = lead_unit.team`, `controlling_alliance = alliance_id`, `state = ACTIVE`).

    * **2+ opposing alliances present:** `controlling_team = -1`, `controlling_alliance = -1`, `state = CONTESTED` (pulsing amber warning ring; neither side gets vision until the other is cleared).

* **Visuals, Audio & Minimap:**

  * Procedural `_draw()` renders a clean octagonal sensor pad, subtle rotating radar sweep arm when `ACTIVE`, and color-coded outer capture ring (`slate` neutral, `TeamManager.get_team_color(controlling_team)` when active, pulsing `amber` when contested).

  * Emit a subtle one-shot radar lock-on ping in `AudioManager` when the local player's alliance claims a relay.

  * Render a crisp radar-diamond/ring icon on `TacticalMinimap` (`ui/hud/minimap.gd`), and make the relay inspectable in `SelectionHUD` (showing status: `NEUTRAL / ACTIVE / CONTESTED` and vision radius).

### A.2 Fog of War & Map Placement (`fog_of_war.gd`, `skirmish_arena_01/02/03.tscn`, `skirmish_ai.gd`)

* **Fog of War Integration (`fog_of_war.gd`):**

  * During vision stamping, iterate `"sensor_relays"`; if a relay is `ACTIVE` and `TeamManager.are_allies(local_team, relay.controlling_team)` (or Spectator full-reveal), stamp a full `relay.vision_radius` circle (optionally bypassing obstacle LOS shadowing when `relay.ignores_los_blockers == true`).

* **Map Placement:**

  * `skirmish_arena_01.tscn` (*Vat Basin*): Place **2** symmetric flank Sensor Relays (North and South flank corridors).

  * `skirmish_arena_02.tscn` (*Twin Causeway*): Place **2** Sensor Relays overlooking the central causeway approaches / barricaded flank junctions.

  * `skirmish_arena_03.tscn` (*Quad Nexus*): Place **2** or **4** symmetric perimeter relays along the mid-lanes between quadrants.

* **Light AI Awareness (`skirmish_ai.gd`):**

  * Include nearby neutral Sensor Relays as optional waypoint stops for the AI's early scout routine so AI scouts naturally contest map vision without pulling combat waves out of position.

## 3. Phase B: Defensive Stance with Leash

### B.1 Stance Model & Leash Behavior (`scripts/units/unit.gd`, `scripts/units/combat_component.gd`, `scripts/units/movement_component.gd`)

* **Stance Enum (`Unit`):**

  * Standardize unit stance cleanly (preserving existing `HOLD_POSITION` behavior):

    * `enum CombatStance { AGGRESSIVE, DEFENSIVE, HOLD_POSITION }` (`var combat_stance: int = CombatStance.AGGRESSIVE`).

  * Store `var defensive_anchor: Vector2 = Vector2.ZERO` and `const DEFENSIVE_LEASH_RADIUS: float = 260.0`.

* **Setting Defensive Stance:**

  * Calling `unit.issue_defensive_stance()` sets `combat_stance = CombatStance.DEFENSIVE`, records `defensive_anchor = unit.global_position`, stops any prior movement, and transitions cleanly to defending that post.

  * Issuing a standard `Move` or `Attack-Move` order updates `defensive_anchor` to the new destination if the unit stays in `DEFENSIVE` stance (or resets stance to `AGGRESSIVE` on explicit `Attack-Move` / `Patrol`, while keeping `Move` cleanly resetting to `AGGRESSIVE` or retaining `DEFENSIVE` at the new post—**keep it intuitive:** `Defensive` works like `Hold Position` as an explicit stance command on the current post, and issuing a new `Move`/`Attack-Move`/`Patrol` returns the unit to normal `AGGRESSIVE` movement).

* **Leash Enforcement (`CombatComponent` & `Unit`):**

  * While `combat_stance == CombatStance.DEFENSIVE`:

    * Auto-acquire threats normally within aggro/weapon range using the existing weighted threat-priority scorer.

    * Allow chasing a target **only** while `unit.global_position.distance_to(defensive_anchor) <= DEFENSIVE_LEASH_RADIUS` (or if the target is already within weapon range from the current position without stepping past the leash).

    * If the target moves out of weapon range and pursuing would exceed `DEFENSIVE_LEASH_RADIUS` (or if no valid target remains inside the leash), immediately drop the chase target and smoothly `Move` back to `defensive_anchor`.

### B.2 Hotkey, Command Card & Diegetic Badge (`project.godot`, `settings_manager.gd`, `selection_controller.gd`, `selection_hud.gd`, `entity_visuals.gd`)

* Register `cmd_defensive_stance` in `project.godot` and `SettingsManager.KEYBIND_DEFS` (default **`KEY_G`** if `D` is used elsewhere, or **`KEY_D`** if free—verify zero conflict; full keyboard + `Mouse 3/4/5` support).

* Add a **Defensive Stance** button to `SelectionHUD`'s combat unit command card alongside `Attack-Move`, `Patrol`, `Hold Position`, and `Stop`, highlighting it when selected units are in `DEFENSIVE` stance.

* In `entity_visuals.gd`, render a tiny crisp shield/anchor pip next to the unit's health/status bar (or a faint dashed leash ring when selected in `DEFENSIVE` stance) so defending squads read unmistakably at a glance.

## 4. Phase C: Generic Extensible Mechanics Hooks (Zero Stealth)

Keep the codebase lean and ready for Faction #2–#5 asymmetric mechanics (shields, energy barriers, DoTs, HoTs, EMP/ability-silence, armor shred, link buffs) **without** adding any stealth or cloaking code:

### C.1 Unified Tag, Shield & Periodic Effect API (`scripts/units/status_effect_component.gd`)

* **Generic Gameplay Tags (`_tags: Dictionary`):**

  * Expose `add_tag(tag: StringName, duration: float = -1.0)`, `remove_tag(tag: StringName)`, `has_tag(tag: StringName) -> bool` (e.g., future `&"emp_silenced"`, `&"phase_shielded"`, `&"armor_shredded"`, `&"unstoppable"`).

* **Structured Effect Records & Modifiers:**

  * Support standardized optional fields on active status effects:

    * `move_speed_mult: float = 1.0`

    * `attack_speed_mult: float = 1.0`

    * `damage_dealt_mult: float = 1.0`

    * `damage_taken_mult: float = 1.0`

    * `hp_per_sec: float = 0.0` (supports both future DoTs `< 0` and HoTs `> 0`, ticking cleanly at `0.25s` intervals with optional `source_attacker` attribution for kill/veterancy credit)

    * `blocks_abilities: bool = false` (ready for future EMP/silence mechanics)

* **Damage Absorption / Shield Hook (`absorb_incoming_damage(amount: float, damage_type: StringName) -> float`):**

  * Expose a clean pre-HP mitigation hook called by `Unit.take_damage()` (and optionally `Building.take_damage()`):

    1. Applies `status_effect_component.get_damage_taken_multiplier()`.

    2. Passes remaining damage through `status_effect_component.absorb_damage_shield(amount)` (no-op returning `amount` when a unit has `0` shield, so existing `GENESIS_V2` units have zero overhead, while Faction #2 energy shields or temporary barriers plug in cleanly in 10 lines).

### C.2 Clean Targeting & Weapon Hook Points (`scripts/units/combat_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/data/unit_data.gd`)

* Add an optional `@export var unit_tags: Array[StringName] = []` on `UnitData` (e.g., `&"organic"`, `&"synthetic"`, `&"armored"`, `&"heavy"`, `&"worker"`) so future abilities, repair beams, heal auras, and counter-bonuses can query semantic tags cleanly instead of hardcoding `unit_id` string lists.

* Add a lightweight `can_target_entity(target: Node2D) -> bool` helper on `CombatComponent` and `TurretComponent` so future targeting rules (e.g., air/hover units or invulnerable phase states) have a single canonical gate—explicitly keeping zero stealth/detector logic in this pass.

## 5. Phase D: Smart Building Placement Overlays & Optional Grid-Snap

### D.1 Contextual Placement Guides (`ui/overlays/build_ghost_preview.gd`, `scripts/controllers/command_router.gd`)

Upgrade `BuildGhostPreview._draw()` to dynamically render helpful Technozen placement overlays based on the `BuildingData` currently being placed:

* **Turret Range Preview (`data.has_turret == true`):**

  * Draw a crisp dashed circle at `data.turret_attack_range` (tinted soft cyan when placement is valid, crimson when invalid) plus an inner `data.turret_min_range` dead-zone ring if `> 0`.

* **Economy Hub Drop-Off Tethers (`Nexus Vat`, `Silica Condenser`, `Command Core`):**

  * Query nearby non-depleted `ResourceNode`s matching the hub's accepted resource types (`BiomassNode` for `Nexus Vat`, `SilicaVein` for `Silica Condenser`) within `~480 px` of the ghost position.

  * Draw subtle dashed emerald/cyan tether lines from the ghost center to each serviced resource node, highlighting the linked nodes with a faint ring so players can place expansions at the exact sweet spot between patches.

* **Supply / Base Alignment Guides (`Synapse Pylon` and all structures):**

  * When near friendly structures (`< 240 px`), draw subtle faint clearance/alignment ticks so players can line up clean Technozen base grids effortlessly.

### D.2 Optional Grid-Snap (`scripts/systems/settings_manager.gd`, `scripts/ui/settings_menu.gd`, `scripts/controllers/command_router.gd`)

* Add `var build_grid_snap_enabled: bool = false` to `SettingsManager` (`[gameplay]` section in `user://settings.cfg`, exposed as **"Building Grid Snap (32px)"** in **Settings → Gameplay**).

* When placing a building:

  * Compute `var use_snap := SettingsManager.build_grid_snap_enabled != Input.is_key_pressed(KEY_ALT)` (holding `Alt` temporarily toggles snap on or off on the fly).

  * If `use_snap` is `true`, snap the ghost & placement world coordinates to a `32.0 px` grid (`pos.snapped(Vector2(32.0, 32.0))`) and draw a faint local `32px` placement grid reticle around the build ghost.

## 6. File & Architecture Summary

### New Files to Create

* `scripts/world/sensor_relay.gd` & `scenes/world/sensor_relay.tscn` (Capturable flank vision relay with alliance-aware activation, contested state, and unobstructed radar vision)

### Existing Files to Extend

* `project.godot` & `scripts/systems/settings_manager.gd`: Register `cmd_defensive_stance` (rebindable) and `build_grid_snap_enabled` persistence.

* `scripts/systems/fog_of_war.gd`, `ui/hud/minimap.gd`, `scripts/systems/skirmish_ai.gd`, `scenes/maps/skirmish_arena_01/02/03.tscn`: Sensor Relay vision stamping, minimap radar icon, flank placements, and AI scout waypoints.

* `scripts/units/unit.gd`, `scripts/units/combat_component.gd`, `scripts/units/movement_component.gd`, `scripts/controllers/selection_controller.gd`, `ui/hud/selection_hud.gd`, `ui/overlays/entity_visuals.gd`: `CombatStance.DEFENSIVE` with `260 px` leash & auto-return, command card button, and diegetic stance indicator.

* `scripts/units/status_effect_component.gd`, `scripts/buildings/turret_component.gd`, `scripts/data/unit_data.gd`: Generic tag/modifier/shield/DoT/HoT extensibility pipeline and `unit_tags` (zero stealth/cloaking).

* `ui/overlays/build_ghost_preview.gd`, `scripts/controllers/command_router.gd`, `scenes/ui/settings_menu.tscn`, `scripts/ui/settings_menu.gd`: Contextual turret range rings, resource drop-off tethers, alignment guides, and `32 px` grid-snap (`Alt` temporary invert).

## 7. Verification Checklist for `agy`

Before concluding Milestone 2.7, verify in Godot (`skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, `skirmish_arena_03.tscn`, and `milestone_0_test.tscn`):

* \[ \] **Capturable Sensor Relays:** Walk a `Stinger` onto a flank `SensorRelay`; confirm the relay turns team-colored, its radar dish spins, Fog of War opens cleanly across `520 px` (including over adjacent obstacle shadows), and `TacticalMinimap` shows the active relay. Walk an enemy unit onto the same pad and confirm it flips to `CONTESTED` (amber pulse, vision disabled) until one side is cleared; verify `2v2` allies share relay vision.

* \[ \] **Defensive Stance & Leash:** Put a squad of `Clone Troopers` into **Defensive Stance** (via command card or hotkey); bait them with an enemy `Stinger` and verify they engage and chase up to `~260 px`, then disengage and walk cleanly back to their anchored post once the enemy pulls beyond the leash. Confirm issuing a fresh Move/Attack-Move returns them to normal `AGGRESSIVE` control.

* \[ \] **Extensible Mechanics Hooks (No Stealth):** Verify `StatusEffectComponent` cleanly preserves existing `Adrenal Surge`, `Static Pulse`, and `Compute Overdrive` behavior while supporting `add_tag()`, `damage_taken_mult`, `absorb_damage_shield()`, and periodic `hp_per_sec` ticks—with zero stealth/cloaking code or regressions in combat.

* \[ \] **Smart Building Placement & Grid-Snap:** Start placing a `Nexus Vat` and `Silica Condenser` near resource clusters and confirm emerald/cyan drop-off tether lines connect to nearby `BiomassNode`s / `SilicaVein`s; preview a `Defense Turret` (`has_turret`) and confirm its dashed firing-range circle renders live; test **Settings → Gameplay → Building Grid Snap (32px)** and holding `Alt` mid-placement to snap/unsnap smoothly, with zero Godot Debugger errors.