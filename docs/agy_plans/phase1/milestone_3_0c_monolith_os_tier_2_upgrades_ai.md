# Milestone 3.0c — `MONOLITH_OS` Tier 2 Roster, Upgrades & Full Skirmish AI Parity

**Prerequisite:** Milestones 3.0a, 3.0b, and Patch 3.0b.1 verified and working cleanly.  
**Goal:** Bring **Faction #2 (`MONOLITH_OS — The Iron Axiom`)** to full end-to-end skirmish parity with `GENESIS_V2` by adding its Tier 2 production facility (`Siege Gantry`), three Tier 2 heavy/control units, three faction upgrades, Neo-Brutalist Halftone visuals/audio, and full `SkirmishAI` / `AIBuildPlanner` mastery (including AI **Core Overclock** and **Deploy/Anchor** tactics).

**Non-Negotiable Constraints:**
* **Preserve Current Tier 0–1 Balance:** Do **not** alter existing `MONOLITH_OS` Tier 0–1 or `GENESIS_V2` unit/building stat numbers in this pass.
* **Zero Regression on `GENESIS_V2`:** All `GENESIS_V2` units, buildings, upgrades, and AI behaviors must remain unchanged.
* **Strict `1280×720` UI Discipline:** All HUD grids (especially `Servo-Drone`'s 8-building + Auto-Repair Command Card), `TechTreeOverlay`, `MainMenu`, and tooltips must remain 100% unclipped in Windowed `1280×720` and Fullscreen (`F11`).
* **Hard Exclusions:** No stealth/cloaking; no role-sorted squad formations; no AI map-hacking (AI must only react to enemies observed in real vision).

---

## 1. Tier 2 Structure: `Siege Gantry`

Create `scenes/buildings/monolith_siege_gantry.tscn`, `resources/buildings/monolith_siege_gantry_data.tres`, and `resources/abilities/build_monolith_siege_gantry.tres`:

* **Identity & Role (`monolith_siege_gantry_data.tres`):**
  * `building_id = &"siege_gantry"`
  * `display_name = "Siege Gantry"`
  * `tech_tier = 2`
  * `is_military_production = true`
  * `audio_select_class = &"production"`
  * `required_building_id = &"assembly_bay"` and `prerequisite_building_ids = [&"assembly_bay"]`
  * `tech_tree_summary = "Tier-2 Heavy Robotics • Siege-Walker, Dreadnought, Null-Grid Projector"`
* **Stats & Costs:**
  * `biomass_cost = 150`, `silica_cost = 180`, `compute_cost = 60`, `build_time = 12.0`
  * `footprint_size = Vector2(90, 90)` (`footprint_radius = 45.0`, `selection_radius = 54.0`)
  * `max_hp = 1050.0`, `max_shield = 180.0`, `shield_regen_rate = 14.0`, `shield_regen_delay = 7.0`, `damage_reduction = 0.25`, `vision_range = 430.0`
  * `trainable_unit_paths` → `monolith_anvil_siege_walker_data.tres`, `monolith_monolith_dreadnought_data.tres`, `monolith_null_grid_projector_data.tres`
  * `researchable_upgrades` → `monolith_hyper_velocity_rails.tres`
* **Scene & Fallback Wiring:**
  * Assign `building_data = ExtResource("...monolith_siege_gantry_data.tres")` directly on the root node of `monolith_siege_gantry.tscn` (same pattern enforced in 3.0b.1).
  * Add `&"siege_gantry"` to `Building.DEFAULT_BUILDING_COSTS` and Hazard Amber accent mapping in `scripts/buildings/building.gd`.
* **Worker Build Ability (`build_monolith_siege_gantry.tres`):**
  * `target_type = TargetType.BUILD_PLACEMENT`, `building_to_build = monolith_siege_gantry_data.tres`, `hotkey_label` assigned cleanly without colliding with existing `Servo-Drone` hotkeys.
  * Append `build_monolith_siege_gantry.tres` to `resources/units/monolith_servo_drone_data.tres` `abilities`.
* **`SelectionHUD` 9-Slot Command Card Guard (`ui/hud/selection_hud.gd`):**
  * Adding `Siege Gantry` brings `Servo-Drone` to **8 build abilities + Auto-Repair = 9 buttons**.
  * Update `_rebuild_ability_buttons()` so when `total_slots > 8`, `ability_row.columns = 5` (compact 5×2 layout, `custom_minimum_size = Vector2(92.0, 26.0)`, `font_size = 9`) so the Command Card stays strictly **2 rows tall** and never overflows `SelectionHUD` height at `1280×720`.
  * Add concise display aliases in `_refresh_single_ability_button()` and `_shorten_unit_name()` (`"Siege Gantry" -> "Gantry"`, `"Anvil Siege-Walker" -> "Anvil"`, `"Monolith Dreadnought" -> "Dreadnought"`, `"Null-Grid Projector" -> "Null-Grid"`, `"Hardened Plating" -> "Plating"`, `"Rapid Capacitors" -> "Capacitors"`, `"Hyper-Velocity Rails" -> "HV Rails"`).

---

## 2. Tier 2 Combat & Control Units (3 Units)

Create `.tscn` scenes in `scenes/units/monolith_*.tscn` and `UnitData` `.tres` files in `resources/units/monolith_*_data.tres`. All three carry `&"mechanical"` and `&"heavy"` tags, `is_armored = true`, `minimap_icon_shape = &"triangle_heavy"`, and drop `SalvageCore`s on death.

### 2.1 `anvil_siege_walker` (*Anvil Siege-Walker*)
* **Role:** Heavy quadruped artillery walker utilizing the Milestone 3.0a **Deploy / Anchor** stance (`unit_tags = [&"mechanical", &"armored", &"heavy", &"siege"]`, `role_tags_display = "Armored • Deployable Siege • AoE"`).
* **Mobile Mode (Default):**
  * `move_speed = 135.0`, `collision_radius = 20.0`, `selection_radius = 26.0`
  * `attack_damage = 42.0`, `attack_range = 240.0`, `min_attack_range = 0.0`, `attack_cooldown = 2.0`, `attack_windup = 0.16`, `aoe_attack_radius = 0.0`
  * `weapon_tracer_style = &"heavy_slug"`, `weapon_sfx_id = &"weapon_mono_slug"`
* **Deployed / Anchored Mode (`can_deploy = true`, `deploy_duration = 1.4`):**
  * `deployed_attack_damage = 88.0`
  * `deployed_attack_range = 460.0`
  * `deployed_min_attack_range = 110.0`
  * `deployed_attack_cooldown = 3.2`
  * `deployed_aoe_radius = 78.0`
  * `deployed_damage_reduction_bonus = 0.15` *(extra hull armor while anchored)*
  * `deployed_weapon_tracer_style = &"mortar"` *(or dedicated `&"siege_shell"` concussive artillery arc in `combat_vfx.gd`)*
* **Durability, Cost & Salvage:**
  * `max_hp = 310.0`, `max_shield = 75.0`, `shield_regen_rate = 10.0`, `shield_regen_delay = 6.5`, `damage_reduction = 0.25`
  * `biomass_cost = 110`, `silica_cost = 160`, `compute_cost = 45`, `bandwidth_cost = 4`, `train_time = 11.5`
  * `salvage_silica = 45`, `salvage_compute = 20`

### 2.2 `monolith_dreadnought` (*Monolith Dreadnought*)
* **Role:** Ultra-durable centerpiece juggernaut built to anchor frontlines and break fortifications (`unit_tags = [&"mechanical", &"armored", &"heavy", &"frontline"]`, `role_tags_display = "Heavy Juggernaut • Kinetic Barrier"`).
* **Combat Feel:**
  * `move_speed = 125.0`, `collision_radius = 23.0`, `selection_radius = 30.0`, `vision_range = 400.0`
  * Dual heavy cannons: `attack_damage = 64.0`, `bonus_vs_armored = 24.0`, `attack_range = 245.0`, `aoe_attack_radius = 36.0`, `attack_cooldown = 1.9`, `attack_windup = 0.16`
  * `weapon_tracer_style = &"heavy_slug"`, `weapon_sfx_id = &"weapon_mono_bastion"`
* **Signature Ability — `Kinetic Barrier` (`resources/abilities/monolith_kinetic_barrier.tres`):**
  * `ability_id = &"kinetic_barrier"`, `hotkey_label = "Q"`, `target_type = TargetType.INSTANT_SELF`, `allow_autocast = true`, `default_autocast = false`
  * `cooldown_duration = 18.0`, `effect_duration = 7.0`
  * **Effect (`scripts/units/ability_component.gd`):** Grants a temporary `+180` unmitigated `Kinetic Barrier` via `status_effects.add_damage_shield(180.0, 7.0, "Kinetic Barrier")` and restores `+40` native shield via `owner_unit.restore_shield(40.0)`. Spawns a crisp hexagonal cyan/amber barrier pulse in `AbilityEffect`.
  * **Auto-Cast Condition (when toggled ON):** Triggers automatically when in combat and `current_shield <= max_shield * 0.25` (or hull HP `< 80%`).
* **Durability, Cost & Salvage:**
  * `max_hp = 520.0`, `max_shield = 130.0`, `shield_regen_rate = 14.0`, `shield_regen_delay = 6.5`, `damage_reduction = 0.35`
  * `biomass_cost = 150`, `silica_cost = 210`, `compute_cost = 65`, `bandwidth_cost = 5`, `train_time = 14.0`
  * `salvage_silica = 60`, `salvage_compute = 25`

### 2.3 `null_grid_projector` (*Null-Grid Projector*)
* **Role:** Area-denial and anti-swarm control platform (`unit_tags = [&"mechanical", &"armored", &"heavy", &"control"]`, `role_tags_display = "Area Denial • Grav-Pulse Slow"`).
* **Combat Feel:**
  * `move_speed = 145.0`, `collision_radius = 19.0`, `selection_radius = 25.0`
  * Slow concussive disruptor bolt: `attack_damage = 28.0`, `attack_range = 290.0`, `aoe_attack_radius = 60.0`, `attack_cooldown = 2.2`, `attack_windup = 0.18`
  * `weapon_tracer_style = &"arc_tether"`, `weapon_sfx_id = &"weapon_mono_tether"`
* **Signature Ability — `Grav-Pulse Field` (`resources/abilities/monolith_grav_pulse.tres`):**
  * `ability_id = &"grav_pulse"`, `hotkey_label = "Q"`, `target_type = TargetType.POINT_AOE`, `allow_autocast = true`, `default_autocast = true`
  * `cast_range = 310.0`, `aoe_radius = 135.0`, `cooldown_duration = 12.0`, `effect_duration = 5.0`
  * **Effect (`scripts/units/ability_component.gd`):** Emits a brutalist halftone amber/violet gravity shockwave at target point dealing `22` light disruption damage and applying a heavy **`50%` movement slow & `35%` attack-speed slow** for `5.0s` (`StatusEffectComponent.apply_effect(&"grav_pulse", { ... })`) to all hostile units in `135 px` radius—punishing `GENESIS_V2` `Clone Trooper` / `Stinger` surrounds.
  * **Auto-Cast Condition (default ON):** Triggers when `>= 2` hostile combat units are clustered within `cast_range`.
* **Durability, Cost & Salvage:**
  * `max_hp = 260.0`, `max_shield = 95.0`, `shield_regen_rate = 11.0`, `shield_regen_delay = 6.0`, `damage_reduction = 0.20`
  * `biomass_cost = 95`, `silica_cost = 145`, `compute_cost = 55`, `bandwidth_cost = 3`, `train_time = 10.5`
  * `salvage_silica = 40`, `salvage_compute = 25`

---

## 3. Three `MONOLITH_OS` Upgrades

Create three `UpgradeData` `.tres` files in `resources/upgrades/` and wire them through `UpgradeManager`, `EconomyManager`, and their respective research structures:

| Upgrade ID & File | Researched At | Cost & Time | Mechanical Effect |
| :--- | :--- | :--- | :--- |
| `monolith_hardened_plating` (`monolith_hardened_plating.tres`) | **Ballistics Lab** *(T1)* | `100B / 140S / 25C` • `18s` | **`+0.10` (+10%) flat hull damage reduction** across all `MONOLITH_OS` units & structures via `EconomyManager.get_bonus_armor(team)`. |
| `monolith_rapid_capacitors` (`monolith_rapid_capacitors.tres`) | **Ballistics Lab** *(T1)* | `80B / 130S / 40C` • `20s` | **`0.60×` shield regen delay** (e.g., 6.0s → 3.6s) and **`1.40×` shield regen rate** via `EconomyManager.get_shield_regen_delay_multiplier(team)` and `get_shield_regen_rate_multiplier(team)`. |
| `monolith_hyper_velocity_rails` (`monolith_hyper_velocity_rails.tres`) | **Siege Gantry** *(T2)* | `120B / 180S / 65C` • `24s` | **`+20%` weapon damage** and **`+45 px` attack range** on `Rail-Sentinel`, `Bastion Emplacement`, and `Anvil Siege-Walker` (both Mobile and Deployed). |

### Upgrade Implementation Hooks
* **`scripts/systems/upgrade_manager.gd`:** Add constants `UPGRADE_HARDENED_PLATING`, `UPGRADE_RAPID_CAPACITORS`, `UPGRADE_HYPER_VELOCITY_RAILS`.
* **`scripts/systems/economy_manager.gd`:**
  * Implement `get_bonus_armor(team)` → returns `0.10` if `has_upgrade(team, UPGRADE_HARDENED_PLATING)` else `0.0`.
  * Implement `get_shield_regen_delay_multiplier(team)` → returns `0.60` if `has_upgrade(team, UPGRADE_RAPID_CAPACITORS)` else `1.0`.
  * Implement `get_shield_regen_rate_multiplier(team)` → returns `1.40` if `has_upgrade(team, UPGRADE_RAPID_CAPACITORS)` else `1.0`.
  * Add `has_hyper_velocity_rails(team) -> bool` helper (or `get_rail_damage_multiplier(team)` / `get_rail_range_bonus(team)`).
* **`scripts/units/unit.gd` & `scripts/buildings/turret_component.gd`:**
  * Apply `Hyper-Velocity Rails` damage (`×1.20`) and range (`+45 px`) inside `Unit.get_effective_attack_damage()`, `Unit.get_effective_attack_range()` (for `&"rail_sentinel"` and `&"anvil_siege_walker"`), and `TurretComponent` (for `&"bastion_emplacement"`).
* Attach `monolith_hardened_plating.tres` and `monolith_rapid_capacitors.tres` to `resources/buildings/monolith_ballistics_lab_data.tres` `researchable_upgrades`, and `monolith_hyper_velocity_rails.tres` to `monolith_siege_gantry_data.tres` `researchable_upgrades`.

---

## 4. Neo-Brutalist Halftone Visuals & Industrial Audio

### 4.1 `ui/overlays/entity_visuals.gd`
* Register `&"anvil_siege_walker"`, `&"monolith_dreadnought"`, and `&"null_grid_projector"` in `_is_monolith_unit()` and `&"siege_gantry"` in `_is_monolith_building()` and `_get_building_outer_poly()`.
* Draw distinct, unmistakable Neo-Brutalist Halftone silhouettes using `_draw_brutalist_slab()`, `_draw_halftone_dots()`, and `_draw_team_corner_brackets()`:
  * **`siege_gantry`:** Heavy reinforced mega-bay (`90×90`) with 4 corner amber blast-buttresses, twin overhead crane bridges, halftone assembly floor, and pulsing amber forge core when producing.
  * **`anvil_siege_walker`:** Wide quadruped chassis with 4 articulated brutalist stabilizer legs, heavy dorsal artillery barrel; when `is_deployed()`, visually splay the 4 stabilizer feet outward with bolted amber ground clamps and elevate/extend the heavy siege barrel.
  * **`monolith_dreadnought`:** Imposing broad armored fortress-mech with stark off-white layered bulkhead slabs, halftone shoulder vents, twin heavy cannons, and a glowing cyan/amber central barrier core (add subtle pulsing outer hex halo when `Kinetic Barrier` is active).
  * **`null_grid_projector`:** Angular brutalist dish/monolith walker with twin side pylon prongs and a rotating/pulsing amber-violet grav-projector core ring.

### 4.2 `scripts/systems/audio_manager.gd`
* Add/verify crisp industrial SFX for Tier 2:
  * `&"weapon_mono_siege"` (deep heavy artillery thump + shell launch boom for Deployed `Anvil Siege-Walker`).
  * `&"ability_kinetic_barrier"` (resonant sub-bass shield lock-in chime).
  * `&"ability_grav_pulse"` (heavy low-frequency gravity drop + halftone static hum).
  * Pneumatic deploy/undeploy lock sounds (verify 3.0a hooks play cleanly with `MONOLITH_OS` timbre).

---

## 5. Faction Manifest, Main Menu, Tech Tree & Sandbox Integration

* **`resources/factions/monolith_os_faction.tres`:**
  * Add `monolith_siege_gantry_data.tres` to `building_roster` (now 8 total structures).
  * Add `monolith_anvil_siege_walker_data.tres`, `monolith_monolith_dreadnought_data.tres`, and `monolith_null_grid_projector_data.tres` to `unit_roster` (now 10 total units).
  * Add all 3 upgrade `.tres` files to `upgrade_roster`.
  * Set `ai_build_profile[&"heavy_t2"] = &"siege_gantry"`.
  * Update `ai_counter_units` and `ai_playstyle_weights` to incorporate `anvil_siege_walker`, `monolith_dreadnought`, and `null_grid_projector` (e.g., `SYNTHETICS_TECH` playstyle favors `monolith_dreadnought`, `anvil_siege_walker`, and `rail_sentinel`; `ANTI_SWARM` favors `null_grid_projector` and `bulwark_automaton`; `BREACH` favors `anvil_siege_walker` and `monolith_dreadnought`).
  * Confirm `FactionData.validate()` returns **0 warnings**.
* **`scripts/ui/main_menu.gd`:**
  * Update the `MONOLITH_OS` featured dossier signature badges to include `Anvil Siege-Walker (Deploy)`, `Monolith Dreadnought`, and `Null-Grid Projector` while staying 100% unclipped at `1280×720`.
* **`ui/hud/sandbox_debug_panel.gd`:**
  * Verify all 10 `MONOLITH_OS` units and `Siege Gantry` spawn cleanly from the faction-aware Sandbox spawner, and add a **Combat Lab** preset pitting `MONOLITH_OS` (e.g., `2× Bulwark + 1× Rail-Sentinel + 1× Anvil + 1× Aegis`) vs `GENESIS_V2` (`4× Clone Trooper + 2× Stinger + 1× Symbiote + 1× Goliath`) for rapid testing.

---

## 6. Full `SkirmishAI` Support for `MONOLITH_OS` (`scripts/systems/skirmish_ai.gd` & `ai_build_planner.gd`)

Keep all AI logic **faction-agnostic and data-driven** (querying capabilities like `has_overclock_ability()`, `can_toggle_deploy()`, `get_effective_max_harvesters()`, and `FactionData` rosters—no hardcoded `if faction_id == &"monolith_os"` hacks, and **zero map-hacking**):

1. **Tier 2 Progression & Upgrade Research:**
   * Verify `AIBuildPlanner` resolves `&"heavy_t2"` → `Siege Gantry` cleanly after `Assembly Bay` is built, constructs `Siege Gantry`, and trains Tier 2 units according to `ai_playstyle_weights` and vision-based `ai_counter_units`.
   * Verify the AI automatically queues faction upgrades from `FactionData.upgrade_roster` when its `Ballistics Lab` / `Siege Gantry` are built and resources permit.
2. **Silica & Compute Saturation Awareness:**
   * Verify `SkirmishAI` trains up to `rn.get_effective_max_harvesters(ai_team)` (`3` per `SilicaVein`) and staffs up to `building.max_staff_slots` (`3` `Grid-Tech`s on `Logic Monolith`).
3. **AI `Core Overclock` Macro Usage:**
   * On the AI decision tick, for any constructed friendly hub where `hub.can_cast_overclock()`:
     * Scan friendly constructed production/research buildings that are **actively producing** (`get_training_queue_size() > 0`) and not already overclocked (`not is_overclocked()`).
     * Prioritize military/tech structures (`Siege Gantry` > `Ballistics Lab` > `Assembly Bay` > `Foundry Core`).
     * Call `hub.cast_overclock_on(best_target)` cleanly through the exact same method the player uses.
4. **AI `Deploy / Anchor` Micro for `Anvil Siege-Walker`:**
   * Respecting real vision only (using visible/known enemy targets already queried by `SkirmishAI`):
     * When an `Anvil Siege-Walker` (`can_toggle_deploy()`) is in `ATTACKING`, `DEFENDING`, or `BREACHING` state and has a valid enemy target (or breach barricade) within `deployed_attack_range * 0.92` and outside `deployed_min_attack_range`: call `unit.request_deploy()`.
     * When the unit is `DEPLOYED` and either enters `RETREATING`, needs to reposition (no valid enemy target within `deployed_attack_range * 1.05` for `>= 2.5s`), or an enemy closes inside `deployed_min_attack_range`: call `unit.request_undeploy()` so it never gets permanently stranded in anchored mode.
5. **AI Ability Usage (`Kinetic Barrier` & `Grav-Pulse`):**
   * Ensure AI `Monolith Dreadnought`s trigger `Kinetic Barrier` when engaged in combat with depleted shields, and AI `Null-Grid Projector`s trigger `Grav-Pulse Field` (via Auto-Cast or AI combat ability check) on clustered visible enemies.

---

## 7. Verification & Playtest Checklist

1. **Zero Errors & Validation:**
   * Launch Godot (`F5`); verify **0 errors** and **0 `FactionData.validate()` warnings**.
2. **Tier 2 Build, Upgrades & Command Card (`1280×720` Windowed & `F11` Fullscreen):**
   * Select `Servo-Drone`: verify all **8 buildings + Auto-Repair (9 buttons)** fit cleanly in a 2-row Command Card with zero clipping.
   * Build `Assembly Bay` → `Ballistics Lab` → `Siege Gantry`. Research `Hardened Plating`, `Rapid Capacitors`, and `Hyper-Velocity Rails`; verify armor, shield regen delay/rate, and rail/siege damage+range visibly increase.
   * Open `TechTreeOverlay` (`U`) as `MONOLITH_OS`: verify Tier 0, Tier 1, and Tier 2 columns populate dynamically with all 8 buildings, 10 units, and 3 upgrades inside the `ScrollContainer`.
3. **Tier 2 Unit Mechanics (Sandbox / Skirmish):**
   * Deploy/undeploy `Anvil Siege-Walker`; confirm splayed anchor legs, extended range (`460 px`), high-explosive AoE shells, min-range deadzone, and non-accidental undeploy on Move clicks.
   * Trigger `Kinetic Barrier` on `Monolith Dreadnought`; verify `+180` unmitigated barrier absorbs damage before native shield and hull HP.
   * Cast/Auto-Cast `Grav-Pulse Field` with `Null-Grid Projector` onto a `GENESIS_V2` swarm; verify heavy slow VFX and debuff application.
4. **AI-vs-AI Spectator Stress Test (`MONO-OS` vs `GEN-V2`):**
   * Run a 4–6 minute AI-vs-AI Spectator match on `skirmish_arena_01.tscn` and a 4P FFA (`2× GEN-V2` vs `2× MONO-OS`) on `skirmish_arena_03.tscn` at `2x` speed.
   * Confirm the `MONOLITH_OS` AI builds `Siege Gantry`, researches upgrades, casts `Core Overclock` on active factories, deploys/undeploys `Anvil Siege-Walker`s in fights without stranding them, and maintains smooth frame pacing.