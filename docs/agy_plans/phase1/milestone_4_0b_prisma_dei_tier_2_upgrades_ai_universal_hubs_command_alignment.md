# Milestone 4.0b — `PRISMA_DEI` Tier 2, Upgrades & AI + Universal Command Hubs & Cross-Faction Command Alignment

**Prerequisite:** Milestone 4.0a (`milestone_4_0a_prisma_dei_core_roster_visuals_audio.md`) verified and working cleanly.

**Goal:** Bring **Faction #3 (`03 // PRISMA_DEI — The Divine Lattice`)** to 100% end-to-end skirmish parity with `GENESIS_V2` and `MONOLITH_OS` while simultaneously standardizing **cross-faction Command Card / hotkey role alignment** and making **all Command Hubs universal Biomass + Silica drop-off points**:

1. **Cross-Faction Command Card & Hotkey Role Alignment:** Audit and standardize worker build grids (`Q/W/E/R/T/Y/F/G`), Command Hub training (`Q = Worker`, `W = Harvester`, `E = Engineer`), T1/T1.5/T2 production unit slots, upgrade slots (`R/T`), facility specials (`F`), and combat ability hotkeys (`Q` primary, `E` deploy) across all three factions so muscle memory transfers seamlessly.
2. **Universal Resource Drop-Off on All Command Hubs:** Update `Nexus Vat`, `Foundry Core`, and `Sanctum Core` (and future hubs) to accept both **Biomass** and **Silica**, resolving the `Prism Dredge` drop-off UX gap while keeping Refineries valuable as forward drop-offs and extra harvester queues.
3. **`PRISMA_DEI` Tier 2 Roster (`Cathedral Foundry`, `Seraph Cruiser`, `Solstice Lance`):** Complete the Divine Lattice tech tree with high-skill glass-cannon beam and orbital-siege craft.
4. **Three `PRISMA_DEI` Upgrades + Scoutable Visual Telltales:** Implement `Harmonic Communion`, `Specular Focusing`, and `Solar Apotheosis` with live stat hooks and procedural Bauhaus telltales.
5. **Full `SkirmishAI` Lattice & Tether Mastery:** Ensure AI commanders proactively maintain Power Lattice coverage, replace destroyed Halo Spires when buildings lose power, tech to `Cathedral Foundry`, cast all `PRISMA_DEI` abilities, and broadcast liturgical radio transmissions.

**Hard Design Guardrails (MUST PRESERVE):**

* **Standard Worker Construction Only:** `Acolyte` physically constructs every building on-site (no remote warp-in).
* **Zero Passive Shields on `PRISMA_DEI`:** Keep `max_shield = 0.0` on all `PRISMA_DEI` units and buildings (pure alabaster hull HP).
* **Zero Skill-Cap Automation:** No stealth/cloaking, no role-sorted squad formations, no overkill-prevention targeting automation, no auto-loop production.
* **Preserve Existing Balance Numbers:** Do not alter existing `GENESIS_V2` or `MONOLITH_OS` combat stat numbers (only reorder their Command Card / training slot arrays and add universal hub Silica drop-off).
* **Strict `1280×720` UI Discipline:** All HUD grids, `TechTreeOverlay`, `MainMenu` (`3 / 5 ACTIVE`), and tooltips must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).

---

## Phase A — Cross-Faction Command Card & Hotkey Role Alignment Audit

Standardize every faction's Command Card slot ordering and hotkeys by **functional role** so players never relearn macro muscle memory when switching between `GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`, and future Factions #4–#5.

### A.1 Command Hub Training & Facility Actions (`Q / W / E` + `F`)

| Slot / Hotkey | Canonical Role | `GENESIS_V2` (`Nexus Vat`) | `MONOLITH_OS` (`Foundry Core`) | `PRISMA_DEI` (`Sanctum Core`) |
| :--- | :--- | :--- | :--- | :--- |
| **`Q`** (Slot 0) | Primary Worker | `Worker Drone` | `Servo-Drone` | `Acolyte` |
| **`W`** (Slot 1) | Silica Harvester | **`Silica Harvester`** *(SWAPPED from E)* | `Ore Crawler` | `Prism Dredge` |
| **`E`** (Slot 2) | Compute Specialist | **`Systems Engineer`** *(SWAPPED from W)* | `Grid-Tech` | `Luminant` |
| **`F`** (Slot 8) | Hub Special | *(Empty)* | `Core Overclock` | *(Empty)* |

* **Required Edits:**
  * Swap `silica_harvester_data.tres` and `engineer_data.tres` in **`resources/buildings/nexus_vat_data.tres`** (`trainable_units` / `trainable_unit_paths`) **and** in **`scenes/buildings/nexus_vat.tscn`** (`trainable_unit_data` / `trainable_unit_scenes` if overridden on the root node!).
  * Verify `monolith_foundry_core_data.tres` / `.tscn` and `prisma_sanctum_core_data.tres` / `.tscn` match `[Worker, Harvester, Engineer]` identically.

### A.2 Worker Build Grid (`4×3` Layout — Exact 12-Slot Role Parity)

Update `SelectionHUD` for unarmed worker units (`not data.is_combat_unit()` with build abilities) so all 3 factions' workers render in an identical, razor-clean **3-row grid**:
* **Row 1 (Slots 0–3 — Worker Controls):** `Move (RMB)`, `Stop (S)`, `Hold (H)`, **`Auto-Repair`** *(moved into Slot 3 so Rows 2 & 3 are dedicated purely to the 8-building build matrix!)*.
* **Row 2 (Slots 4–7 — Tier 0 Economy & Infrastructure):** `Q`, `W`, `E`, `R`
* **Row 3 (Slots 8–11 — Tier 1–2 Military, Tech & Defense):** `T`, `Y`, `F`, `G`

| Grid Slot & Hotkey | Canonical Building Role | `GENESIS_V2` (`Worker Drone`) | `MONOLITH_OS` (`Servo-Drone`) | `PRISMA_DEI` (`Acolyte`) |
| :--- | :--- | :--- | :--- | :--- |
| **Row 2, Col 1 — `Q`** | T0 Command Hub | `Nexus Vat` | `Foundry Core` | `Sanctum Core` |
| **Row 2, Col 2 — `W`** | T0 Supply / Lattice | `Synapse Pylon` | `Capacitor Pylon` | `Halo Spire` |
| **Row 2, Col 3 — `E`** | T0 Silica Refinery | `Silica Condenser` | `Silica Smelter` | `Alabaster Kiln` |
| **Row 2, Col 4 — `R`** | T0 Compute Facility (Vent) | `Wetware Mainframe` | `Logic Monolith` | `Oracle Reliquary` |
| **Row 3, Col 1 — `T`** | T1 Core Production | `Cloning Vat` | `Assembly Bay` | `Choir Basilica` |
| **Row 3, Col 2 — `Y`** | T1.5 Tech / Counter | `Calibration Foundry` | `Ballistics Lab` | `Refraction Cloister` |
| **Row 3, Col 3 — `F`** | T1 Static Defense | **`Defense Turret`** *(audit/create `build_defense_turret.tres`)* | `Bastion Emplacement` | `Solar Obelisk` |
| **Row 3, Col 4 — `G`** | T2 Heavy / Elite Production | `Synthetics Fabricator` | `Siege Gantry` | `Cathedral Foundry` |

* **Required Edits:**
  * Audit `resources/abilities/`: **`GENESIS_V2`** has `resources/buildings/defense_turret_data.tres` and `scenes/buildings/defense_turret.tscn` in the repo, but is currently missing `resources/abilities/build_defense_turret.tres`. Create `resources/abilities/build_defense_turret.tres` (`target_type = BUILD_PLACEMENT`, `building_to_build = defense_turret_data.tres`, `hotkey_label = "F"`) so all 3 factions have full 8/8 build parity!
  * Update `hotkey_label` on every `build_*.tres` ability across all 3 factions to match the exact `Q / W / E / R / T / Y / F / G` table above.
  * Reorder the `abilities` array in **`worker_unit_data.tres`**, **`monolith_servo_drone_data.tres`**, and **`prisma_acolyte_data.tres`** to the exact order `[Q:Hub, W:Supply, E:Refinery, R:Compute, T:T1Prod, Y:T1.5Tech, F:Defense, G:T2Elite]`.
  * Verify `SelectionController._unhandled_input` routes `KEY_G` (or a dedicated `cmd_ability_g` check) cleanly alongside `cmd_ability_q/w/e/r/t/y/f`, and verify `SelectionHUD` displays the live `[G]` badge on Slot 11.

### A.3 Military Production, Refinery & Compute Facility Role Alignment

| Structure Role | `Q` (Slot 0) | `W` (Slot 1) | `E` (Slot 2) | `R` / `T` (Row 2 Upgrades) | `F` (Slot 8 Special) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Silica Refinery** | `Silica Harvester` / `Ore Crawler` / `Prism Dredge` | — | — | — | — |
| **Compute Facility** | — | — | — | — | `Eject Specialists` *(also `E` fallback)* |
| **T1 Production** *(Core / Scout / Support)* | `Clone Trooper` / `Bulwark Automaton` / `Votary` | `Stinger` / `Picket Drone` / `Lumen Skiff` | `Symbiote` / *—* / `Cantor` | `GEN`: `Batch Eff.` (`R`), `Adrenal Pot.` (`T`) • `MONO`: *—* • `PRIS`: `Harmonic Comm.` (`R`) | — |
| **T1.5 Tech / Counter** *(Anti-Armor / Utility)* | `Lance-Rig` / `Rail-Sentinel` / `Lens Adjudicator` | `Signal Jammer` / `Aegis Relay` / `Prism Weaver` | — | `GEN`: *—* • `MONO`: `Hardened Plating` (`R`), `Rapid Capacitors` (`T`) • `PRIS`: `Specular Focusing` (`R`) | — |
| **T2 Heavy / Elite** *(Flagship / Siege / Specialist)* | **`Goliath Frame`** / **`Monolith Dreadnought`** *(swapped to Q)* / **`Seraph Cruiser`** | **`Chrysalis Mortar`** *(swapped to W)* / **`Anvil Siege-Walker`** *(swapped to W)* / **`Solstice Lance`** | **`Arc-Lancer`** *(swapped to E)* / **`Null-Grid Projector`** / *—* | `Compute Overdrive` (`R`) / `Hyper-Velocity Rails` (`R`) / `Solar Apotheosis` (`R`) | — |

* **Required Edits:**
  * **`synthetics_fabricator_data.tres` & `synthetics_fabricator.tscn`:** Reorder trainable units to **`[Goliath Frame (Q), Chrysalis Mortar (W), Arc-Lancer (E)]`**.
  * **`monolith_siege_gantry_data.tres` & `monolith_siege_gantry.tscn`:** Reorder trainable units to **`[Monolith Dreadnought (Q), Anvil Siege-Walker (W), Null-Grid Projector (E)]`**.
  * **Verify All Unit Active Abilities:** Confirm every combat unit's primary active ability uses **`hotkey_label = "Q"`**, and `Deploy / Anchor` remains uniformly **`E`**.
  * **Scene Override Audit:** Check every `scenes/buildings/*.tscn` file to verify no stale `trainable_unit_data` array on a `.tscn` root overrides the updated `.tres` ordering (or update both identically).

---

## Phase B — Universal Resource Drop-Off on All Command Hubs

Make every Command Hub across all factions accept both **Biomass** and **Silica**:

1. **Data & Scene Updates:**
   * **`resources/buildings/nexus_vat_data.tres`** & **`scenes/buildings/nexus_vat.tscn`**
   * **`resources/buildings/monolith_foundry_core_data.tres`** & **`scenes/buildings/monolith_foundry_core.tscn`**
   * **`resources/buildings/prisma_sanctum_core_data.tres`** & **`scenes/buildings/prisma_sanctum_core.tscn`**
   * Set `is_dropoff = true`, `accepted_resources = Array[StringName]([&"biomass", &"silica"])`, and `accepted_dropoff_resources = Array[StringName]([&"biomass", &"silica"])` on all three `.tres` files, and update `accepted_resources = Array[StringName]([&"biomass", &"silica"])` on the root node of all three `.tscn` scenes.
2. **Runtime Sync Guard (`scripts/buildings/building.gd`):**
   * In `Building._ready()`, when `building_data != null`, sync `is_resource_dropoff = building_data.is_dropoff` and `accepted_resources = building_data.get_dropoff_resources().duplicate()` (matching `begin_construction()`) so pre-placed starting hubs and worker-built expansion hubs always share identical drop-off behavior.
   * Confirm `Building.get_cluster_saturation()` continues reporting the hub's local Biomass saturation cleanly (since hubs have `is_core_hub == true` checked before the silica-dropoff branch), and `BuildGhostPreview` renders both Biomass (emerald) and Silica (gold) tether lines near hubs automatically.

---

## Phase C — `PRISMA_DEI` Tier 2 Structure & Units

Create scenes in `scenes/buildings/` & `scenes/units/`, data resources in `resources/buildings/` & `resources/units/`, and abilities in `resources/abilities/`. All Tier 2 `PRISMA_DEI` entities have **`max_shield = 0.0`**, `minimap_icon_shape = &"triangle_heavy"`, and drop `SalvageCore`s on death.

### C.1 Tier 2 Structure: `Cathedral Foundry`

Create `scenes/buildings/prisma_cathedral_foundry.tscn`, `resources/buildings/prisma_cathedral_foundry_data.tres`, and `resources/abilities/build_prisma_cathedral_foundry.tres` (`hotkey_label = "G"`, appended as Slot 8 of `prisma_acolyte_data.tres`):

* **Identity & Lattice Wiring:**
  * `building_id = &"cathedral_foundry"`, `display_name = "Cathedral Foundry"`, `short_display_name = "Cathedral"`
  * `hud_accent_color = Color(0.85, 0.27, 0.94, 1.0)`
  * `tech_tier = 2`, `is_military_production = true`, `audio_select_class = &"production"`
  * `requires_power_grid = true`, `provides_power_grid = false`
  * `required_building_id = &"refraction_cloister"`, `prerequisite_building_ids = [&"refraction_cloister"]`
  * `tech_tree_summary = "Tier-2 Elite Lattice • Seraph Cruiser, Solstice Lance • Requires Power"`
* **Stats & Costs:**
  * `biomass_cost = 140`, `silica_cost = 170`, `compute_cost = 65`, `build_time = 11.5`
  * `footprint_size = Vector2(88, 88)` (`footprint_radius = 44.0`, `selection_radius = 52.0`)
  * `max_hp = 880.0`, `max_shield = 0.0`, `damage_reduction = 0.12`, `vision_range = 420.0`
  * `trainable_unit_paths` → `[prisma_seraph_cruiser_data.tres (Q), prisma_solstice_lance_data.tres (W)]`
  * `researchable_upgrades` → `[prisma_solar_apotheosis.tres (R)]`
  * Assign `building_data = ExtResource("...prisma_cathedral_foundry_data.tres")` directly on the `.tscn` root node.

### C.2 Tier 2 Flagship (`Q`): `Seraph Cruiser` (`seraph_cruiser`)

* **Role:** High-skill glass-cannon beam frigate—leaner than `Goliath Frame` or `Monolith Dreadnought`, with devastating escalating + refracting beam DPS when kept alive and tethered (`unit_tags = [&"synthetic", &"armored", &"heavy", &"beam"]`, `role_tags_display = "Elite Beam Frigate • Escalating + Refract"`).
* **Stats & Durability:**
  * `max_hp = 290.0`, `max_shield = 0.0`, `damage_reduction = 0.12`, `is_armored = true`
  * `move_speed = 190.0`, `acceleration = 1500.0`, `turn_speed = 10.5`, `collision_radius = 20.0`, `selection_radius = 26.0`, `vision_range = 400.0`
  * `biomass_cost = 125`, `silica_cost = 180`, `compute_cost = 60`, `bandwidth_cost = 4`, `train_time = 12.0`
  * `salvage_silica = 50`, `salvage_compute = 25`
* **Weapon (Escalating + Refracting Dual Beam):**
  * `is_continuous_beam = true`, `attack_damage = 16.0`, `bonus_vs_armored = 5.0`, `attack_cooldown = 0.35`, `attack_windup = 0.08`, `attack_range = 250.0`
  * `beam_ramp_max_multiplier = 2.4`, `beam_ramp_duration = 3.2`, `beam_ramp_decay_delay = 0.55`, `beam_ramp_decay_rate = 1.4`
  * `refract_max_bounces = 1`, `refract_radius = 125.0`, `refract_damage_ratio = 0.50`
  * `weapon_tracer_style = &"prism_beam"`, `weapon_tracer_color = Color(0.98, 0.80, 0.14, 1.0)`, `weapon_tracer_width = 3.2`, `weapon_sfx_id = &"weapon_prism_beam"`
* **Signature Ability (`Q`) — `Aureole Surge` (`resources/abilities/prisma_aureole_surge.tres`):**
  * `ability_id = &"aureole_surge"`, `display_name = "Aureole Surge"`, `hotkey_label = "Q"`, `target_type = TargetType.INSTANT`, `cast_on_all_ready = true`, `allow_autocast = false`
  * `cooldown_duration = 16.0`, `effect_duration = 4.0`
  * **Effect (`scripts/units/ability_component.gd` & `status_effect_component.gd`):** Applies `&"aureole_surge"` for `4.0s` granting **`+35%` beam ramp speed** (`beam_ramp_speed_mult = 1.35`) and **`+1` bonus refraction bounce** (`bonus_refract_bounces = 1`), while increasing incoming damage taken by **`+15%`** (`damage_taken_mult = 1.15`). High-skill risk/reward burst window!

### C.3 Tier 2 Siege Breaker (`W`): `Solstice Lance` (`solstice_lance`)

* **Role:** Fragile, long-range orbital prism artillery & barricade breaker (`unit_tags = [&"synthetic", &"armored", &"heavy", &"siege", &"artillery"]`, `role_tags_display = "Siege Prism • Anti-Armor • Solar Convergence"`).
* **Stats & Durability:**
  * `max_hp = 235.0`, `max_shield = 0.0`, `damage_reduction = 0.08`, `is_armored = true`
  * `move_speed = 155.0`, `acceleration = 1250.0`, `turn_speed = 9.0`, `collision_radius = 19.0`, `selection_radius = 25.0`, `vision_range = 410.0`
  * `biomass_cost = 110`, `silica_cost = 165`, `compute_cost = 55`, `bandwidth_cost = 4`, `train_time = 11.5`
  * `salvage_silica = 45`, `salvage_compute = 25`
* **Weapon (Long-Range Orbital Prism Lance):**
  * `is_continuous_beam = false`, `attack_damage = 54.0`, `bonus_vs_armored = 36.0`, `attack_range = 390.0`, `min_attack_range = 115.0`, `attack_cooldown = 2.6`, `attack_windup = 0.18`
  * `weapon_tracer_style = &"prism_beam"` *(single crisp high-intensity gold/magenta lance via `PRISM_BEAM` at `intensity = 0.95` or `RAIL_BEAM` tinted gold/magenta)*, `weapon_tracer_color = Color(0.98, 0.80, 0.14, 1.0)`, `weapon_tracer_width = 3.6`, `weapon_sfx_id = &"weapon_prisma_lance"`
* **Signature Ability (`Q`) — `Solar Convergence` (`resources/abilities/prisma_solar_convergence.tres`):**
  * `ability_id = &"solar_convergence"`, `display_name = "Solar Convergence"`, `hotkey_label = "Q"`, `target_type = TargetType.POINT_AOE`, `allow_autocast = false`
  * `cast_range = 410.0`, `aoe_radius = 95.0`, `cooldown_duration = 18.0`, `effect_duration = 1.4`
  * **Effect (`scripts/units/ability_component.gd` & `ui/overlays/combat_vfx.gd`):** Locks an unmistakable **`1.4s` telegraphed** converging liturgical-gold & ultraviolet-magenta lens reticle on the target ground point (visible to both sides if in vision, rewarding enemy micro-dodges while punishing immobile turrets, barricades, and deployed `Anvil Siege-Walker`s). After `1.4s`, fires a blinding vertical light column dealing **`75` base damage + `45` bonus damage vs. Armored / Buildings / DestructibleBarricades** in `95 px` radius, plus restrained distance-attenuated camera micro-shake (`2.6 px`).

---

## Phase D — Three `PRISMA_DEI` Faction Upgrades & System Hooks

Create three `UpgradeData` `.tres` files in `resources/upgrades/` and wire them into `UpgradeManager`, `EconomyManager`, `OpticalTetherSystem`, `Unit`, and `CombatComponent`:

| Upgrade ID & File | Researched At (Hotkey `R`) | Cost & Time | Mechanical Effect |
| :--- | :--- | :--- | :--- |
| `prisma_harmonic_communion` (`prisma_harmonic_communion.tres`) | **Choir Basilica** *(T1)* | `90B / 120S / 30C` • `18s` | **`+1` max Optical Tether link** and **`+35 px` tether emit radius** on all `PRISMA_DEI` emitters (`Halo Spire`, `Cantor`, `Prism Weaver`). |
| `prisma_specular_focusing` (`prisma_specular_focusing.tres`) | **Refraction Cloister** *(T1.5)* | `100B / 145S / 45C` • `20s` | **`+25%` continuous beam ramp-up rate** across all `PRISMA_DEI` beam units, plus **`+1` refraction bounce** on `Votary` and `Prism Weaver`. |
| `prisma_solar_apotheosis` (`prisma_solar_apotheosis.tres`) | **Cathedral Foundry** *(T2)* | `120B / 175S / 65C` • `24s` | **`+12%` movement speed** for all `PRISMA_DEI` combat units and **`+25 px` attack range** on T1.5–T2 beam craft (`Lens Adjudicator`, `Prism Weaver`, `Seraph Cruiser`, `Solstice Lance`). |

### Implementation Hooks
* **`scripts/systems/upgrade_manager.gd`:** Add constants `UPGRADE_HARMONIC_COMMUNION`, `UPGRADE_SPECULAR_FOCUSING`, `UPGRADE_SOLAR_APOTHEOSIS`.
* **`scripts/systems/economy_manager.gd`:** Add clean helpers:
  * `get_bonus_tether_links(team) -> int` (`1` if `UPGRADE_HARMONIC_COMMUNION` else `0`)
  * `get_bonus_tether_radius(team) -> float` (`35.0` if `UPGRADE_HARMONIC_COMMUNION` else `0.0`)
  * `get_beam_ramp_upgrade_multiplier(team) -> float` (`1.25` if `UPGRADE_SPECULAR_FOCUSING` else `1.0`)
  * `get_bonus_refract_bounces(team, unit_type_id) -> int` (`1` if `UPGRADE_SPECULAR_FOCUSING` and `unit_type_id in [&"votary", &"prism_weaver"]` else `0`)
  * `get_prisma_move_speed_multiplier(team) -> float` (`1.12` if `UPGRADE_SOLAR_APOTHEOSIS` else `1.0`)
  * `get_prisma_beam_range_bonus(team, unit_type_id) -> float` (`25.0` if `UPGRADE_SOLAR_APOTHEOSIS` and `unit_type_id in [&"lens_adjudicator", &"prism_weaver", &"seraph_cruiser", &"solstice_lance"]` else `0.0`)
* **`scripts/systems/optical_tether_system.gd`:** Add `econ.get_bonus_tether_links(emitter_team)` to `max_links` and `econ.get_bonus_tether_radius(emitter_team)` to `emit_r`.
* **`scripts/units/status_effect_component.gd`:** Add `get_bonus_refract_bounces() -> int` (reading `&"aureole_surge"`) and verify `get_damage_taken_multiplier()` supports `damage_taken_mult` (e.g., `1.15` for `Aureole Surge` and `Radiant Mark`).
* **`scripts/units/unit.gd` & `scripts/units/combat_component.gd`:**
  * Multiply `get_effective_beam_ramp_speed_multiplier()` by `econ.get_beam_ramp_upgrade_multiplier(team)`.
  * Apply `econ.get_prisma_move_speed_multiplier(team)` for `PRISMA_DEI` combat units inside `Unit`'s effective move speed getter.
  * Apply `econ.get_prisma_beam_range_bonus(team, get_unit_type_id())` inside `Unit.get_effective_attack_range()`.
  * In `CombatComponent._apply_refract_split_damage()`, sum `data.refract_max_bounces + econ.get_bonus_refract_bounces(...) + status_effect_component.get_bonus_refract_bounces()`.
* Attach each upgrade `.tres` to its building's `researchable_upgrades` array (`prisma_choir_basilica_data.tres`, `prisma_refraction_cloister_data.tres`, `prisma_cathedral_foundry_data.tres`) and add all 3 to `prisma_dei_faction.tres` `upgrade_roster`.

---

## Phase E — Bauhaus Tier 2 Visuals, Upgrade Telltales, Cathedral Audio & Glyphs

### E.1 `ui/overlays/renderers/prisma_visual_renderer.gd`
* Register `&"cathedral_foundry"` in building IDs and `&"seraph_cruiser"`, `&"solstice_lance"` in unit IDs (and animated units).
* Draw unmistakable Bauhaus Sacred Geometry silhouettes (alabaster bone-white `#F6F4EE`, obsidian glass `#14111D`, liturgical gold `#FACC15`, ultraviolet magenta `#D946EF`):
  * **`cathedral_foundry`:** Grand 88×88 octagonal rose-window cathedral bay with twin gilded apse wings, obsidian central altar glass, rotating golden astrolabe ring while actively producing, and subtle crimson/magenta unpowered dim state when outside the Power Lattice.
  * **`seraph_cruiser`:** Swept angelic-geometric delta frigate with twin split alabaster wing-vanes, obsidian dorsal prism spine, golden double-halo focus ring, and a radiant pulsing gold-magenta corona when `has_status_effect(&"aureole_surge")`.
  * **`solstice_lance`:** Elongated diamond-cathedral siege skiff with split gilded focus-rails framing a floating ultraviolet-magenta lens crystal.
* **Scoutable Visual Upgrade Telltales (`draw_unit_upgrade_telltales` & `draw_building_upgrade_telltales`):**
  1. **`Harmonic Communion`:** Crisp concentric **Liturgical Gold** halo ring + 4 tiny cardinal diamond nodes around `Halo Spire`, `Cantor`, and `Prism Weaver`.
  2. **`Specular Focusing`:** Glowing **Ultraviolet Magenta** faceted wing/lens pips along the forward emitters of `Votary`, `Lens Adjudicator`, `Prism Weaver`, and `Seraph Cruiser`.
  3. **`Solar Apotheosis`:** Sharp **Solar Gold** dorsal chevron crown trim on all `PRISMA_DEI` combat units.

### E.2 `Solar Convergence` VFX, Audio & Command Glyphs
* **`ui/overlays/combat_vfx.gd`:** Add pooled `setup_solar_convergence(target_pos, radius, telegraph_time, on_impact)` rendering a crisp `1.4s` shrinking sacred-geometry lens ring + crosshairs followed by a high-contrast vertical gold/white/magenta beam column detonation (strictly visibility-gated for visuals/SFX while always invoking `on_impact` reliably).
* **`scripts/systems/audio/prisma_audio_profile.gd`:** Add `&"weapon_prisma_lance"` (deep resonant cathedral bell + focused prism crack), `&"ability_aureole_surge"` (ascending crystalline choir chord), `&"ability_solar_convergence_charge"` (rising glass-harmonic focus hum), and `&"ability_solar_convergence_impact"` (bright harmonic blast + tight sub-bass thump).
* **`ui/hud/command_icon_glyphs.gd`:** Add clean `28×28 px` procedural Bauhaus vector glyphs for `cathedral_foundry`, `seraph_cruiser`, `solstice_lance`, `aureole_surge`, `solar_convergence`, `prisma_harmonic_communion`, `prisma_specular_focusing`, and `prisma_solar_apotheosis`.

---

## Phase F — Faction Manifest, Sandbox Lab & Full `SkirmishAI` Support

### F.1 Complete `resources/factions/prisma_dei_faction.tres`
* Add `prisma_cathedral_foundry_data.tres` to `building_roster` (now **8** structures).
* Add `prisma_seraph_cruiser_data.tres` and `prisma_solstice_lance_data.tres` to `unit_roster` (now **10** units).
* Add all **3** upgrade `.tres` files to `upgrade_roster`.
* Set `ai_build_profile[&"heavy_t2"] = &"cathedral_foundry"`.
* Populate `ai_counter_units`, `ai_playstyle_weights`, updated `signature_badges`, and liturgical `ai_transmissions`:
  * `&"wave_launch"`: `"// PRISMA_DEI: The Choir advances in harmonic convergence. Witness the Light."`
  * `&"barricade_breach"`: `"// PRISMA_DEI: Shadowed barrier dissolved. The sacred lattice expands."`
  * `&"tier2_online"`: `"// PRISMA_DEI: Cathedral Foundry consecrated. Seraphs and Lances descend."`
  * `&"uplink_contest"`: `"// PRISMA_DEI: Reclaiming the Central Lens. All geometry bends to the Lattice."`
  * `&"under_attack"`: `"// PRISMA_DEI: Profane incursion detected at the perimeter. Purging."`
* Confirm `FactionData.validate()` returns **0 warnings**.

### F.2 Full `SkirmishAI` Lattice, Tether & Ability Mastery (`scripts/systems/skirmish_ai.gd`)
Keep all logic **faction-agnostic and data-driven** (zero map-hacking):
1. **Proactive Power Lattice Recovery:**
   * On each economy decision tick, check if any constructed friendly building has `requires_power_grid and not is_powered`.
   * If any structure is unpowered and `_supply_data != null and _supply_data.provides_power_grid` (and no replacement power provider is already under construction nearby), immediately prioritize placing a `Halo Spire` (`_supply_data`) within `power_radius * 0.72` of the unpowered building to restore power!
2. **Tier 2 Progression & Upgrades:**
   * Verify `SkirmishAI` builds `Choir Basilica` → `Refraction Cloister` → `Cathedral Foundry` inside its Power Lattice, researches all 3 upgrades via `_planner.choose_next_upgrade_for_building()`, and trains `Seraph Cruiser` + `Solstice Lance` cleanly.
3. **`PRISMA_DEI` Combat Ability Intelligence (`_trigger_combat_abilities()`):**
   * `solar_step`: Cast when `Votary` is moving toward an enemy or below `70%` HP in combat.
   * `radiant_mark`: Cast on the highest-HP visible hostile unit in `cast_range`.
   * `luminous_mend`: Handled cleanly via `AbilityComponent` auto-cast (verify default ON for AI).
   * `focus_alignment`: Cast when `Lens Adjudicator` is firing on an armored unit or building within range.
   * `blinding_glare`: Cast when `>= 2` hostile combat units are clustered within `cast_range`.
   * `aureole_surge`: Cast when `Seraph Cruiser` is engaged in combat with `HP >= 50%`.
   * `solar_convergence`: Cast on visible hostile buildings, intact breach barricades, deployed siege units, or `>= 2` clustered hostile units within `cast_range`.
4. **Support Escort & Sandbox Lab:**
   * Verify `Cantor` (`attack_damage == 0.0`, `has_tag(&"support")`) moves cleanly with AI waves during `ATTACKING`, `DEFENDING`, and `BREACHING` without getting abandoned at staging or diving ahead of frontline `Votary`s.
   * Update `ui/hud/sandbox_debug_panel.gd` so all 10 `PRISMA_DEI` units and 8 structures spawn cleanly, and add a **Combat Lab** preset pitting `PRISMA_DEI` (*Votary + Cantor + Lens Adjudicator + Seraph Cruiser*) against `MONOLITH_OS` and `GENESIS_V2`.

---

## Phase G — Verification & Playtest Checklist

1. **Zero Errors & Validation:**
   * Launch Godot (`F5`): verify **0 errors**, **0 missing-resource warnings**, and **0 `FactionData.validate()` warnings** across all 3 active factions (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`).
2. **Cross-Faction Command Card & Hotkey Alignment (`1280×720` Windowed & `F11` Fullscreen):**
   * Select `Worker Drone`, `Servo-Drone`, and `Acolyte` back-to-back: confirm identical 4×3 Command Card layout — Row 1 = `Move / Stop / Hold / Auto-Repair`, Row 2 = `Q(Hub) W(Supply) E(Refinery) R(Compute)`, Row 3 = `T(T1) Y(T1.5) F(Defense) G(T2)` — with zero clipping.
   * Select `Nexus Vat`, `Foundry Core`, and `Sanctum Core`: confirm **`Q = Worker`, `W = Harvester`, `E = Engineer`** across all three (specifically verifying `GENESIS_V2`'s swapped `Silica Harvester` and `Systems Engineer`).
   * Select `Synthetics Fabricator`, `Siege Gantry`, and `Cathedral Foundry`: confirm **`Q = Flagship` (`Goliath` / `Dreadnought` / `Seraph`), `W = Siege` (`Mortar` / `Anvil` / `Solstice`), `E = Specialist` (`Arc-Lancer` / `Null-Grid`)**, and **`R = T2 Upgrade`**.
3. **Universal Command Hub Drop-Off:**
   * Train a `Prism Dredge` (at `Sanctum Core`), `Ore Crawler` (at `Foundry Core`), and `Silica Harvester` (at `Nexus Vat`) with **no Refinery built**: confirm all three harvest Silica and deposit directly into their Command Hub, then automatically switch to a closer Refinery once one is built nearby.
4. **`PRISMA_DEI` Tier 2 & Upgrades:**
   * Build `Choir Basilica` → `Refraction Cloister` → `Cathedral Foundry` inside `Halo Spire` lattice (verifying manual `Acolyte` construction and power-loss dormancy if the Spire is salvaged/destroyed).
   * Train `Seraph Cruiser` and `Solstice Lance`; test `Aureole Surge` (`+35%` ramp, `+1` bounce, `+15%` damage taken) and `Solar Convergence` (`1.4s` visible telegraph + orbital light column blast).
   * Research `Harmonic Communion`, `Specular Focusing`, and `Solar Apotheosis`: verify mechanical buffs and all 3 Bauhaus visual telltales appear immediately.
   * Open `TechTreeOverlay` (`U`) as `PRISMA_DEI`: confirm all 8 buildings, 10 units, and 3 upgrades populate cleanly.
5. **3-Faction AI-vs-AI Spectator Stress Test:**
   * Run a **3P FFA** (`GEN-V2` vs. `MONO-OS` vs. `PRIS-DEI`) on `skirmish_arena_03.tscn` (and a seeded **Procedural Arena**) at `2x` speed for 5+ minutes:
     * Confirm the `PRISMA_DEI` AI maintains its Power Lattice, rebuilds lost `Halo Spire`s to repower dormant factories, deploys `Cathedral Foundry`, casts `Solar Convergence` & `Aureole Surge`, broadcasts liturgical radio lines, and maintains smooth frame pacing.