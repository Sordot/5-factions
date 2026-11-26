# Milestone 4.0a — `PRISMA_DEI` (*The Divine Lattice*) Core Rollout (T0–T1.5 Roster, Visuals, Audio & HUD)

**Prerequisite:** Milestones 3.7 (Modular Faction Architecture Refactor), 3.8 (SC2 High-Ground FoW & Wide Ramps), and 3.9 (`PRISMA_DEI` Engine Foundations: Power Lattice, Optical Tethers, Continuous & Refracting Beams) verified and working cleanly.

**Goal:** Ship **Faction #3 (`03 // PRISMA_DEI — The Divine Lattice`)** as a fully playable skirmish faction through Tier 1.5—bringing the Main Menu to **`3 / 5 ACTIVE`**—with 7 structures, 8 units, 5 active abilities, Bauhaus Sacred Geometry procedural visuals (`PrismaVisualRenderer`), crystalline/cathedral synth audio (`PrismaAudioProfile`), a gold-and-magenta Bauhaus HUD OS theme (`FactionHudTheme`), procedural Command Card glyphs (`CommandIconGlyphs`), and full `FactionData` validation. *(Tier 2 `Cathedral Foundry`, `Seraph Cruiser`, `Solstice Lance`, the 3 faction upgrades + telltales, and deep AI lattice/tether tuning follow cleanly in Milestone 4.0b.)*

**Hard Design Guardrails (MUST PRESERVE):**
* **Standard Worker Construction Only:** `Acolyte` physically travels to and constructs every `PRISMA_DEI` structure on-site (no remote Protoss-style warp-in).
* **Zero Passive Shields:** All `PRISMA_DEI` units and buildings have `max_shield = 0.0` (pure alabaster hull HP, keeping `MONOLITH_OS`'s regenerating shield layer unique). Hull HP is modest-to-average—bulky enough for reliable beam ramp-up uptime, never tanky, rewarding crisp positioning and tether geometry.
* **Zero Skill-Cap Automation:** No stealth/cloaking, no role-sorted squad formations, no overkill-prevention targeting automation, no auto-loop production.
* **Zero Regression on Factions #1 & #2:** Do **not** alter any `GENESIS_V2` or `MONOLITH_OS` unit/building stats, visuals, audio, or AI behaviors.
* **Strict `1280×720` UI Discipline:** `MainMenu` (`3 / 5 ACTIVE` dossier grid), `SelectionHUD` (4×3 Icon Command Card), `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, `TacticalEventFeed`, and `TechTreeOverlay` must remain 100% unclipped in Windowed `1280×720` and Fullscreen (`F11`).

---

## Phase A — Core Structures (7 Buildings: T0 – T1.5)

Create scenes in `scenes/buildings/prisma_*.tscn`, `BuildingData` resources in `resources/buildings/prisma_*_data.tres`, and worker build abilities in `resources/abilities/build_prisma_*.tres`.

**Critical Scene Wiring Rule (Match `MONOLITH_OS` Pattern):**
* Assign `building_data = ExtResource("...prisma_*_data.tres")` directly on the root node of every `scenes/buildings/prisma_*.tscn` scene (alongside matching `building_type_id`, `display_name`, `footprint_radius`, `selection_radius`, and `CollisionShape2D` size) so both starting-loadout instancing and worker-placed construction share identical stats, power-grid flags, and trainable rosters.
* Set `max_shield = 0.0` on all 7 structures.

### A.1 Structure Specs

| Building ID & Display Name | Short Name | Tier / Role | Cost (`B/S/C`) & Build Time | Footprint / HP / Armor / Vision | Power Lattice & Tether Properties | Trainable Units (`Q/W/E`) & Notes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `&"sanctum_core"`<br>**Sanctum Core** | `Sanctum` | T0 Hub (`is_command_hub = true`, `is_core_hub = true`, `audio_select_class = &"hub"`) | `300B / 80S`<br>`14.0s` | `96×96` (`r=48`, `sel=56`)<br>`1350 HP`, `0.05 DR`, `460px` | `provides_power_grid = true`<br>`power_radius = 290.0`<br>`bandwidth_provided = 10` | Drop-off: `[&"biomass"]`.<br>Trains: `acolyte`, `prism_dredge`, `luminant`. |
| `&"halo_spire"`<br>**Halo Spire** | `Halo Spire` | T0 Supply (`is_supply_provider = true`, `audio_select_class = &"utility"`) | `95B / 30S`<br>`5.5s` | `58×58` (`r=29`, `sel=36`)<br>`420 HP`, `0.05 DR`, `380px` | `provides_power_grid = true`<br>`power_radius = 265.0`<br>`bandwidth_provided = 10`<br>`tether_emit_radius = 200.0`, `tether_max_links = 2`, `tether_fire_rate_bonus = 0.10` | `can_set_rally = false`.<br>Provides both Consecrated Power Lattice and defensive Optical Tethers. |
| `&"alabaster_kiln"`<br>**Alabaster Kiln** | `Kiln` | T0 Refinery (`is_dropoff = true`, `audio_select_class = &"utility"`) | `100B / 20S`<br>`6.0s` | `72×72` (`r=36`, `sel=44`)<br>`640 HP`, `0.05 DR`, `360px` | Independent (`requires_power_grid = false`) | Drop-off: `[&"silica"]`.<br>Trains: `prism_dredge`. |
| `&"oracle_reliquary"`<br>**Oracle Reliquary** | `Reliquary` | T0 Compute (`requires_vent = true`, `max_staff_slots = 3`, `audio_select_class = &"tech"`) | `80B / 100S`<br>`7.5s` | `76×76` (`r=38`, `sel=46`)<br>`680 HP`, `0.05 DR`, `390px` | Independent (`requires_power_grid = false`) | Staffs up to `3` `Luminant`s (`compute_tick_interval = 3.0`, `compute_per_engineer = 5`). `can_set_rally = false`. |
| `&"choir_basilica"`<br>**Choir Basilica** | `Basilica` | T1 Prod (`is_military_production = true`, `tech_tier = 1`, `audio_select_class = &"production"`) | `135B / 75S`<br>`8.0s` | `84×84` (`r=42`, `sel=50`)<br>`860 HP`, `0.08 DR`, `400px` | **`requires_power_grid = true`** | Trains: `votary`, `lumen_skiff`, `cantor`. |
| `&"refraction_cloister"`<br>**Refraction Cloister** | `Cloister` | T1.5 Tech (`is_military_production = true`, `tech_tier = 1`, `audio_select_class = &"production"`) | `120B / 125S / 25C`<br>`9.5s` | `84×84` (`r=42`, `sel=50`)<br>`840 HP`, `0.08 DR`, `410px` | **`requires_power_grid = true`**<br>Prereq: `&"choir_basilica"` | Trains: `lens_adjudicator`, `prism_weaver`. |
| `&"solar_obelisk"`<br>**Solar Obelisk** | `Obelisk` | T1 Defense (`has_turret = true`, `tech_tier = 1`, `audio_select_class = &"defense"`) | `85B / 95S`<br>`6.5s` | `64×64` (`r=32`, `sel=40`)<br>`660 HP`, `0.15 DR`, `410px` | **`requires_power_grid = true`**<br>Prereq: `&"choir_basilica"` | `can_set_rally = false`.<br>Turret: `turret_damage = 30.0`, `turret_attack_interval = 0.95`, `turret_attack_range = 295.0`, `turret_bonus_vs_armored = 1.25`, `turret_tracer_style = &"prism_beam"`, `turret_turn_speed = 9.0`. Goes dormant automatically when unpowered. |

### A.2 Worker Build Abilities (`resources/abilities/build_prisma_*.tres`)
Assign clean, non-colliding hotkeys on `Acolyte` (leaving `G` open for Tier 2 `Cathedral Foundry` in 4.0b):
* `Q`: `build_prisma_halo_spire.tres` (*Halo Spire*)
* `W`: `build_prisma_alabaster_kiln.tres` (*Alabaster Kiln*)
* `E`: `build_prisma_oracle_reliquary.tres` (*Oracle Reliquary*)
* `R`: `build_prisma_choir_basilica.tres` (*Choir Basilica*)
* `T`: `build_prisma_refraction_cloister.tres` (*Refraction Cloister*)
* `Y`: `build_prisma_solar_obelisk.tres` (*Solar Obelisk*)
* `F`: `build_prisma_sanctum_core.tres` (*Sanctum Core*)

### A.3 Turret Prism Beam Hook (`scripts/buildings/turret_component.gd`)
* Verify `TurretComponent` handles `turret_tracer_style == &"prism_beam"`:
  * Spawn `AttackTracer.TracerStyle.PRISM_BEAM` in Liturgical Gold / Ultraviolet Magenta (`Color(0.98, 0.80, 0.14, 0.96)` blended with team color for non-local teams) and play `&"weapon_prism_refract"` (or `&"weapon_prism_beam"`) on fire.
  * Confirm `Building._process()` already gates `turret_component.tick(delta)` on `is_powered` (implemented in 3.9).

---

## Phase B — Core & Tier 1.5 Units (8 Units) + 5 Active Abilities

Create scenes in `scenes/units/prisma_*.tscn` (assigning `data = ExtResource(...)` on every unit root node) and `UnitData` `.tres` files in `resources/units/prisma_*_data.tres`. All `PRISMA_DEI` units have **`max_shield = 0.0`**.

### B.1 Economy & Specialist Units (3 Units)

1. **`acolyte`** (*Acolyte*, short: `Acolyte`) — `Sanctum Core` (`Q`)
   * `max_hp = 55.0`, `move_speed = 235.0`, `collision_radius = 13.0`, `selection_radius = 18.0`, `vision_range = 330.0`
   * `attack_damage = 6.0`, `attack_range = 95.0`, `attack_cooldown = 1.0`, `weapon_tracer_style = &"prism_bolt"`, `weapon_tracer_color = Color(0.98, 0.82, 0.24, 1.0)`, `weapon_sfx_id = &"weapon_prism_bolt"`, `audio_bark_class = &"worker"`, `minimap_icon_shape = &"worker"`
   * `can_gather = true`, `allowed_resource = &"biomass"`, `gather_duration = 3.0`, `carry_capacity = 10`
   * `unit_tags = [&"worker", &"biological"]`, `role_tags_display = "Worker • Lattice Builder"`
   * `biomass_cost = 50`, `bandwidth_cost = 1`, `train_time = 4.0`
   * `abilities`: all 7 `build_prisma_*.tres` abilities (standard manual worker construction).

2. **`prism_dredge`** (*Prism Dredge*, short: `Dredge`) — `Sanctum Core` (`W`) / `Alabaster Kiln` (`Q`)
   * `max_hp = 95.0`, `damage_reduction = 0.05`, `move_speed = 205.0`, `collision_radius = 15.0`, `selection_radius = 20.0`, `vision_range = 320.0`
   * `can_gather = true`, `auto_gather_on_spawn = true`, `allowed_resource = &"silica"`, `gather_duration = 3.2`, `carry_capacity = 25`
   * `unit_tags = [&"harvester", &"synthetic"]`, `audio_bark_class = &"worker"`, `minimap_icon_shape = &"worker"`, `role_tags_display = "Automated Silica Harvester"`
   * `biomass_cost = 55`, `silica_cost = 25`, `bandwidth_cost = 1`, `train_time = 4.5`

3. **`luminant`** (*Luminant*, short: `Luminant`) — `Sanctum Core` (`E`)
   * `max_hp = 70.0`, `move_speed = 240.0`, `collision_radius = 13.5`, `selection_radius = 18.5`, `vision_range = 350.0`
   * `can_staff_compute = true`, `unit_tags = [&"engineer", &"biological"]`, `audio_bark_class = &"worker"`, `minimap_icon_shape = &"worker"`, `role_tags_display = "Compute Specialist • Repair"`
   * `biomass_cost = 60`, `silica_cost = 20`, `bandwidth_cost = 1`, `train_time = 4.5`

### B.2 Tier 1 Combat & Tether Units — `Choir Basilica` (3 Units)

4. **`votary`** (*Votary*, short: `Votary`) — `Choir Basilica` (`Q`)
   * **Role:** Agile core skirmisher with refracting split-beam; fragile if caught out, deadly in tethered arcs (`unit_tags = [&"infantry", &"biological", &"skirmisher"]`, `role_tags_display = "Light • Refracting Beam • Solar Step"`).
   * **Stats:** `max_hp = 92.0`, `damage_reduction = 0.0`, `move_speed = 250.0`, `collision_radius = 14.0`, `selection_radius = 19.0`, `vision_range = 365.0`, `aggro_range = 290.0`
   * **Weapon:** `attack_damage = 17.0`, `attack_range = 195.0`, `attack_cooldown = 0.92`, `attack_windup = 0.08`, `refract_max_bounces = 1`, `refract_radius = 95.0`, `refract_damage_ratio = 0.45`, `weapon_tracer_style = &"prism_refract"`, `weapon_tracer_color = Color(0.98, 0.80, 0.18, 1.0)`, `weapon_tracer_width = 2.2`, `weapon_sfx_id = &"weapon_prism_refract"`, `audio_bark_class = &"swarm"`
   * **Cost:** `biomass_cost = 55`, `silica_cost = 20`, `bandwidth_cost = 1`, `train_time = 4.5`
   * **Ability (`Q`):** `prisma_solar_step.tres` (*Solar Step* — instant self-buff: `+35%` move speed for `2.5s`, `10.0s` cooldown).

5. **`lumen_skiff`** (*Lumen Skiff*, short: `Skiff`) — `Choir Basilica` (`W`)
   * **Role:** High-speed hover scout & flanker (`ai_scout_unit_id`, `unit_tags = [&"scout", &"flanker", &"synthetic"]`, `role_tags_display = "Fast Scout • Radiant Mark"`).
   * **Stats:** `max_hp = 85.0`, `damage_reduction = 0.0`, `move_speed = 325.0`, `collision_radius = 13.5`, `selection_radius = 19.0`, `vision_range = 435.0`, `aggro_range = 300.0`
   * **Weapon:** `attack_damage = 12.0`, `attack_range = 165.0`, `attack_cooldown = 0.62`, `attack_windup = 0.06`, `weapon_tracer_style = &"prism_bolt"`, `weapon_tracer_color = Color(0.85, 0.27, 0.94, 1.0)`, `weapon_tracer_width = 2.0`, `weapon_sfx_id = &"weapon_prism_bolt"`, `audio_bark_class = &"swarm"`
   * **Cost:** `biomass_cost = 40`, `silica_cost = 35`, `bandwidth_cost = 1`, `train_time = 4.0`
   * **Ability (`Q`):** `prisma_radiant_mark.tres` (*Radiant Mark* — `UNIT_TARGET` enemy within `260 px`: target takes **`+15%` amplified damage** from all sources for `4.0s`, `12.0s` cooldown; visible golden target halo VFX).

6. **`cantor`** (*Cantor*, short: `Cantor`) — `Choir Basilica` (`E`)
   * **Role:** High-priority Optical Tether anchor & field mender (`unit_tags = [&"support", &"biological"]`, `role_tags_display = "Tether Anchor (x4) • Luminous Mend"`).
   * **Stats:** `max_hp = 105.0`, `damage_reduction = 0.0`, `move_speed = 230.0`, `collision_radius = 15.0`, `selection_radius = 21.0`, `vision_range = 390.0`
   * **Weapon:** Non-combat support (`attack_damage = 0.0`, `attack_range = 0.0`, `audio_bark_class = &"support"`).
   * **Optical Tether Emitter:** `tether_emit_radius = 215.0`, `tether_max_links = 4`, `tether_fire_rate_bonus = 0.18`, `tether_range_bonus = 28.0`, `tether_beam_ramp_bonus = 0.25`.
   * **Cost:** `biomass_cost = 55`, `silica_cost = 50`, `compute_cost = 15`, `bandwidth_cost = 2`, `train_time = 6.5`
   * **Ability (`Q`):** `prisma_luminous_mend.tres` (*Luminous Mend* — `POINT_AOE`, `cast_range = 220.0`, `aoe_radius = 115.0`, `cooldown_duration = 9.0`, `allow_autocast = true`, `default_autocast = true`: restores `+45 HP` to all wounded allied units in radius with a golden sunburst chime).

### B.3 Tier 1.5 Beam & Control Units — `Refraction Cloister` (2 Units)

7. **`lens_adjudicator`** (*Lens Adjudicator*, short: `Adjudicator`) — `Refraction Cloister` (`Q`)
   * **Role:** Surgical anti-armor escalating beam craft—modest-average HP so it can survive initial ramp-up, melts heavy armor (`Bulwark`, `Goliath`, `Dreadnought`) when kept tethered and protected (`unit_tags = [&"anti_armor", &"synthetic", &"beam"]`, `role_tags_display = "Escalating Beam • +vs Armored"`).
   * **Stats:** `max_hp = 175.0`, `is_armored = false`, `damage_reduction = 0.05`, `move_speed = 210.0`, `collision_radius = 16.5`, `selection_radius = 22.0`, `vision_range = 390.0`, `aggro_range = 320.0`
   * **Escalating Beam Weapon:** `is_continuous_beam = true`, `attack_damage = 11.0`, `bonus_vs_armored = 5.0`, `attack_range = 245.0`, `attack_cooldown = 0.35`, `attack_windup = 0.06`, `beam_ramp_max_multiplier = 2.6`, `beam_ramp_duration = 3.2`, `beam_ramp_decay_delay = 0.55`, `beam_ramp_decay_rate = 1.4`, `weapon_tracer_style = &"prism_beam"`, `weapon_tracer_color = Color(0.85, 0.27, 0.94, 1.0)`, `weapon_tracer_width = 2.6`, `weapon_sfx_id = &"weapon_prism_beam"`, `audio_bark_class = &"counter"`
   * **Cost & Salvage:** `biomass_cost = 65`, `silica_cost = 95`, `compute_cost = 30`, `bandwidth_cost = 2`, `train_time = 7.5`, `salvage_silica = 25`, `salvage_compute = 10`
   * **Ability (`Q`):** `prisma_focus_alignment.tres` (*Focus Alignment* — `INSTANT` self-buff, `cooldown_duration = 14.0`, `effect_duration = 4.0`: immediately jumps beam ramp elapsed by `+50%` of `beam_ramp_duration`, grants `+40 px` attack range, and slows self movement by `-20%` for `4.0s`).

8. **`prism_weaver`** (*Prism Weaver*, short: `Weaver`) — `Refraction Cloister` (`W`)
   * **Role:** Anti-swarm refracting disruptor & forward mini-tether node (`unit_tags = [&"disruptor", &"synthetic", &"beam"]`, `role_tags_display = "Chain Refract (x2) • Tether (x2) • Glare"`).
   * **Stats:** `max_hp = 165.0`, `is_armored = false`, `damage_reduction = 0.05`, `move_speed = 225.0`, `collision_radius = 16.0`, `selection_radius = 22.0`, `vision_range = 395.0`, `aggro_range = 320.0`
   * **Refracting Weapon:** `attack_damage = 22.0`, `attack_range = 230.0`, `attack_cooldown = 1.05`, `attack_windup = 0.10`, `refract_max_bounces = 2`, `refract_radius = 125.0`, `refract_damage_ratio = 0.55`, `weapon_tracer_style = &"prism_refract"`, `weapon_tracer_color = Color(0.98, 0.80, 0.14, 1.0)`, `weapon_tracer_width = 2.4`, `weapon_sfx_id = &"weapon_prism_refract"`, `audio_bark_class = &"counter"`
   * **Optical Tether Emitter:** `tether_emit_radius = 180.0`, `tether_max_links = 2`, `tether_fire_rate_bonus = 0.12`, `tether_range_bonus = 20.0`, `tether_beam_ramp_bonus = 0.18`.
   * **Cost & Salvage:** `biomass_cost = 60`, `silica_cost = 85`, `compute_cost = 35`, `bandwidth_cost = 2`, `train_time = 7.5`, `salvage_silica = 25`, `salvage_compute = 12`
   * **Ability (`Q`):** `prisma_blinding_glare.tres` (*Blinding Glare* — `POINT_AOE`, `cast_range = 280.0`, `aoe_radius = 115.0`, `cooldown_duration = 13.0`, `effect_duration = 3.5`, `allow_autocast = true`, `default_autocast = true`: flashes hostile units in radius with `-25%` attack speed and `-20%` move speed for `3.5s`).

### B.4 Ability & Status Effect Implementation Hooks
* **`scripts/units/status_effect_component.gd` & `scripts/units/unit.gd`:**
  * Add `get_damage_taken_multiplier() -> float` on `StatusEffectComponent` (default `1.0`, multiplying by any active `"damage_taken_mult"` such as `Radiant Mark`'s `1.15`) and apply it in `Unit.take_damage()` cleanly before Layer 1–3 mitigation.
  * Support `bonus_attack_range` stacking from both `&"optical_tether"` and `&"focus_alignment"` (`+40 px`).
* **`scripts/units/combat_component.gd`:**
  * Add `func boost_beam_ramp_fraction(owner_unit: Unit, fraction: float) -> void` so `Focus Alignment` cleanly jumps `_beam_ramp_elapsed` by `+0.50 * beam_ramp_duration` (clamped to `beam_ramp_duration`) and refreshes `_beam_grace_timer`.
  * Verify non-continuous `weapon_tracer_style == &"prism_bolt"` and `&"prism_refract"` spawn crisp prism tracers (`AttackTracer.TracerStyle.PRISM_REFRACT` or `PRISM_BEAM` pulse) and trigger `_apply_refract_split_damage(...)` when `refract_max_bounces > 0`.
* **`scripts/units/ability_component.gd` & `ui/overlays/ability_effect.gd`:**
  * Implement handlers + auto-cast conditions + crisp Bauhaus gold/magenta `AbilityEffect` bursts for `&"solar_step"`, `&"radiant_mark"`, `&"luminous_mend"`, `&"focus_alignment"`, and `&"blinding_glare"`.

---

## Phase C — Bauhaus Sacred Geometry Procedural Visuals (`PrismaVisualRenderer`)

Create **`ui/overlays/renderers/prisma_visual_renderer.gd`** (`class_name PrismaVisualRenderer extends FactionVisualRenderer`) and register `PrismaVisualRenderer.new()` in `EntityVisuals._ensure_renderers()` (`ui/overlays/entity_visuals.gd`).

### C.1 Visual Grammar & Palette
* **Alabaster Ceramic Hulls:** `#F6F4EE` (`Color(0.965, 0.957, 0.933, 0.98)`) — clean architectural white planes.
* **Obsidian Glass Cores:** `#14111D` (`Color(0.078, 0.067, 0.114, 0.98)`) — deep dark refraction chambers.
* **Liturgical Gold Filigree:** `#FACC15` (`Color(0.980, 0.800, 0.082, 1.0)`) — razor-thin `1.2–1.6 px` concentric halo arcs, triangular reliquary bevels, and rose-window spoke hairlines.
* **Ultraviolet Magenta Energy:** `#D946EF` (`Color(0.851, 0.275, 0.937, 1.0)`) — radiant prism focal lenses and active production glows.
* **Team Color Readability:** Integrate `ctx["team_color"]` cleanly into dual dorsal ribbon bands / cathedral wing pennants and inner sanctum trim so mirror matches (`PRISMA_DEI` vs. `PRISMA_DEI`) read instantaneously.

### C.2 Distinct Silhouettes (7 Buildings + 8 Units)
* **Buildings (`get_building_outer_poly()`):** Crisp regular octagons / rose-window chamfered diamonds:
  * **`sanctum_core`:** Grand 8-sided alabaster cathedral-rotunda with concentric gold halo rings, 4 radial stained-glass buttress spires, obsidian central nave, and pulsing magenta-gold sun core when training.
  * **`halo_spire`:** Tall narrow alabaster obelisk-ring with twin rotating gold halo arcs and an ultraviolet diamond floating at center.
  * **`alabaster_kiln`:** Twin trapezoidal ceramic crucibles bridged by a golden prism conduit glowing warm amber-gold.
  * **`oracle_reliquary`:** Symmetrical triangular reliquary spire over the vent with 3 recessed gold/magenta diamond staffing pips (lighting up as `Luminant`s staff it).
  * **`choir_basilica`:** Twin nave-wing cathedral hall with an arched gold rose-window centerpiece that pulses magenta during training.
  * **`refraction_cloister`:** Precision triangular lens gallery with 3 mirrored gold focal prisms framing a central magenta beam chamber.
  * **`solar_obelisk` + `draw_building_turret()`:** Octagonal alabaster plinth crowned by a rotating golden twin-prong focusing lens turret that aims at targets and recoils cleanly on beam fire.
* **Units:**
  * **`acolyte`:** Compact robed/triangular alabaster hover-disc with twin golden tuning prongs and a small magenta core.
  * **`prism_dredge`:** Broad geometric diamond barge with obsidian ore hopper and golden collector wings.
  * **`luminant`:** Sleek floating crescent-ring reliquary craft with bright gold-white halo crown.
  * **`votary`:** Crisp forward-swept alabaster dart/chevron frame with twin golden needle vanes and magenta central focus slit.
  * **`lumen_skiff`:** Razor-thin elongated diamond interceptor with wide swept hairline wing arcs and trailing solar-gold thruster pip.
  * **`cantor`:** Distinctive circular alabaster halo-ring vessel with a slowly rotating inner golden triangle and radiant magenta chalice core (instantly recognizable priority target!).
  * **`lens_adjudicator`:** Longer hexagonal prism-frigate with an open front twin-rail focusing crystal that glows brighter from magenta → solar-white as `combat_component.get_beam_ramp_ratio(unit)` rises!
  * **`prism_weaver`:** Wide tri-wing geometric star-prism with 3 golden outer mirror nodes and pulsing ultraviolet core.

---

## Phase D — Crystalline & Cathedral Audio (`PrismaAudioProfile`)

Create **`scripts/systems/audio/prisma_audio_profile.gd`** (`class_name PrismaAudioProfile extends FactionAudioProfile`) and register `PrismaAudioProfile.new()` in `AudioManager._register_builtin_profiles()`.

* **`get_profile_id() -> StringName`:** `&"prisma_cathedral"`
* **`get_stream_prefix() -> String`:** `"prisma_"`
* **Weapon & Ability SFX (via `SynthPrimitives`):**
  * `&"weapon_prism_bolt"`: crisp high-harmonic crystal focus snap (`~0.09s`).
  * `&"weapon_prism_beam"` / `&"weapon_prism_refract"`: resolve cleanly to existing crystalline beam/refract synth streams (plus pitch scaling on beam ramp if desired).
  * `&"ability_solar_step"`: shimmering upward glass-harp glissando.
  * `&"ability_radiant_mark"`: bright liturgical bell-ping lock chime.
  * `&"ability_luminous_mend"`: warm harmonic major-fifth choral chime.
  * `&"ability_focus_alignment"`: rising high-Q resonant lens hum.
  * `&"ability_blinding_glare"`: crystalline flash-burst with airy shimmer tail.
* **Unit & Building Barks (`prisma_bark_*`, `prisma_bldg_select_*`):** Ethereal, clean bell-harmonic selection and order acknowledgments (matching `audio_bark_pitch_bias = 1.12`) routed strictly through `AudioManager`'s single-voice `_bark_player`.
* **3-Layer Adaptive Ambient Soundbed (`build_ambient_layers()`):**
  * **`base` (Macro):** Serene airy cathedral-synth fifth pad + distant crystalline glass shimmer (`-16 dB` ceiling).
  * **`combat`:** Rhythmic liturgical arpeggio pulse + tense high-harmonic prism shimmer (`-14 dB` ceiling).
  * **`uplink`:** Resonant orbital-choir harmonic swell + crisp geometric beacon chime (`-15 dB` ceiling).

---

## Phase E — Bauhaus Faction HUD Theme & Command Icon Glyphs

1. **`scripts/ui/faction_hud_theme.gd`:**
   * Register a dedicated **`&"prisma_dei"`** theme provider (`style = &"bauhaus_sacred"`):
     * **Panel:** Deep obsidian-violet matte glass (`Color(0.075, 0.065, 0.115, 0.94)`), crisp `2 px` corners, `1.5 px` **Liturgical Gold (`#FACC15`)** outer border with a hairline alabaster (`#F6F4EE`) inner inset rule.
     * **Frame Overlay (`_draw()`):** Delicate geometric corner diamonds (rotated 45° squares), twin hairline gold divider accents, and subtle ultraviolet-magenta (`#D946EF`) active pulse pips—instantly distinct from `GENESIS_V2`'s rounded cyan curves and `MONOLITH_OS`'s thick ink-and-halftone concrete!
     * **Command Icon Tiles:** Dark obsidian sockets (`#161224`) with thin alabaster/gold frames, Ultraviolet Magenta hover glow, and crisp Liturgical Gold corner hotkey badges.
2. **`ui/hud/command_icon_glyphs.gd`:**
   * Add clean `28×28 px` procedural Bauhaus vector glyphs for all 7 `PRISMA_DEI` structures, all 8 units, and all 5 abilities (`solar_step`, `radiant_mark`, `luminous_mend`, `focus_alignment`, `blinding_glare`) so every tile on the 4×3 Command Card has a bespoke silhouette icon.

---

## Phase F — Faction Manifest, Main Menu `3 / 5 ACTIVE` & Basic Skirmish/Sandbox Parity

1. **Create `resources/factions/prisma_dei_faction.tres` (`FactionData`):**
   * `faction_id = &"prisma_dei"`, `display_name = "PRISMA_DEI — The Divine Lattice"`, `short_code = "PRIS-DEI"`, `is_playable = true`, `dossier_slot_number = 3`
   * `primary_color = Color(0.965, 0.957, 0.933, 1.0)`, `accent_color = Color(0.851, 0.275, 0.937, 1.0)`, `hud_accent_color = Color(0.980, 0.800, 0.082, 1.0)`
   * `boot_banner_text = "// DIVINE LATTICE CONSECRATED — PRISMA_DEI"`
   * `audio_bark_pitch_bias = 1.12`, `audio_timbre_profile = &"prisma_cathedral"`
   * `dossier_subtitle = "Solar Theocracy  •  Consecrated Power Lattice  •  Optical Tethers & Prism Beams"`
   * `dossier_description = "Devoted human acolytes worshiping a radiant orbital AI. Channels visible Optical Tethers between agile glass-ceramic beam craft whose weapons escalate or refract across enemy lines."`
   * `signature_badges = PackedStringArray("Consecrated Power Lattice", "Optical Tethers", "Votary / Lumen Skiff", "Cantor (x4 Tether)", "Lens Adjudicator (Beam)", "Prism Weaver (Refract)", "Solar Obelisk")`
   * `ai_transmissions`:
     * `&"wave_launch"`: `"// PRISMA_DEI: The Choir advances in harmonic convergence. Behold the Lattice."`
     * `&"barricade_breach"`: `"// PRISMA_DEI: Mundane barrier refracted to ash. Proceeding along the radiant path."`
     * `&"tier2_online"`: `"// PRISMA_DEI: High sanctum illumination achieved. Preparing apex vessels."`
     * `&"uplink_contest"`: `"// PRISMA_DEI: Consecrating the Data Hyper-Uplink in the Light's name."`
     * `&"under_attack"`: `"// PRISMA_DEI: Heretical incursion upon the Lattice. Redirecting the Choir."`
   * `starting_biomass = 200`, `starting_silica = 50`, `starting_compute = 0`, `starting_worker_count = 3`
   * `starting_hub_scene = prisma_sanctum_core.tscn`, `worker_scene = prisma_acolyte.tscn`, `harvester_scene = prisma_prism_dredge.tscn`, `engineer_scene = prisma_luminant.tscn`
   * `extra_starting_units = [prisma_votary.tscn, prisma_lumen_skiff.tscn]`
   * `building_roster` (all 7 4.0a buildings), `unit_roster` (all 8 4.0a units), `upgrade_roster = []` *(populated in 4.0b)*
   * `ai_build_profile`: `&"hub": &"sanctum_core"`, `&"supply": &"halo_spire"`, `&"refinery": &"alabaster_kiln"`, `&"compute_hub": &"oracle_reliquary"`, `&"barracks_t1": &"choir_basilica"`, `&"counter_foundry": &"refraction_cloister"`
   * `ai_scout_unit_id = &"lumen_skiff"`, `ai_salvage_unit_ids = [&"luminant", &"acolyte"]`
   * `ai_counter_units` & `ai_playstyle_weights` populated cleanly using the 8 4.0a units so `FactionData.validate()` returns **0 warnings** and AI teams selecting `PRISMA_DEI` can already macro and fight cleanly through Tier 1.5!
2. **Verify `MainMenu` (`scripts/ui/main_menu.gd`) & `SandboxDebugPanel` (`ui/hud/sandbox_debug_panel.gd`):**
   * Confirm `TeamManager._load_faction_registry()` auto-discovers `prisma_dei_faction.tres` and `MainMenu` automatically updates to **`AI LORD FACTION DOSSIERS (3 / 5 ACTIVE)`** with zero clipping at `1280×720` Windowed & `F11` Fullscreen.
   * Verify `PRISMA_DEI` is selectable for both Human and AI slots in Skirmish, Uplink Holdout, Optimal 3-Minute Boom, and `SandboxDebugPanel` spawner.
   * Cleanly remove or keep tucked away the temporary 3.9 Engine Lab debug buttons in `SandboxDebugPanel` if no longer needed (keeping real `PRISMA_DEI` spawning clean).

---

## Phase G — Verification & Playtest Checklist

1. **Zero Errors & Validation:**
   * Launch Godot (`F5`): confirm **0 parse/runtime errors** and **0 `FactionData.validate()` warnings**.
   * Confirm `MainMenu` displays **`3 / 5 ACTIVE`** (`GENESIS_V2`, `MONOLITH_OS`, `PRISMA_DEI`), switching dossiers smoothly with zero clipping at `1280×720` Windowed & Fullscreen (`F11`).
2. **Power Lattice & Manual Worker Construction:**
   * Launch a skirmish as `PRISMA_DEI`: confirm `Sanctum Core`, `3× Acolyte`, `1× Votary`, and `1× Lumen Skiff` spawn cleanly.
   * Select `Acolyte`: confirm all 7 build icons (`Q–F`) + `Auto-Repair` fit cleanly in the Bauhaus-styled 4×3 Command Card with crisp custom glyphs and tooltips.
   * Try placing `Choir Basilica` outside `Sanctum Core`'s `290 px` gold/magenta lattice ring → rejected (`"Requires Power Lattice"`). Place inside the ring → confirm `Acolyte` **physically walks over and constructs it** (no remote warp-in).
   * Build `Halo Spire` → confirm it extends the Power Lattice (`265 px`) and emits defensive Optical Tethers to nearby combat units. Destroy/salvage a load-bearing `Halo Spire` → confirm orphaned `Choir Basilica` / `Solar Obelisk` flips to `"UNPOWERED"` dormancy and resumes automatically once a replacement `Halo Spire` completes.
3. **Optical Tethers, Beam Ramp & Refraction Micro:**
   * Train `Votary`, `Lumen Skiff`, `Cantor`, `Lens Adjudicator`, and `Prism Weaver`:
     * Verify `Cantor` (`×4` links) and `Prism Weaver` (`×2` links) project glowing gold/magenta Optical Tethers via `OpticalTetherOverlay` and boost fire rate, range, and beam ramp.
     * Verify `Votary` refracts `1` bounce (`95 px`) and `Prism Weaver` refracts `2` bounces (`125 px`) into enemy clusters.
     * Verify `Lens Adjudicator` ramps its continuous `PRISM_BEAM` up to `2.6×` against armored targets and jumps `+50%` ramp instantly when triggering `Focus Alignment`.
     * Verify `Solar Step`, `Radiant Mark` (`+15%` dmg taken), `Luminous Mend` (Auto-Cast), and `Blinding Glare` (Auto-Cast) all execute cleanly with distinct VFX and crystalline audio.
4. **Full-HUD OS Theme & 3-Way Match Sanity Check:**
   * Confirm all 5 HUD panels (`SelectionHUD`, `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, `TacticalEventFeed`) switch cleanly to `PRISMA_DEI`'s obsidian-and-gold Bauhaus Sacred Geometry theme, and the 3-layer cathedral ambient soundbed plays smoothly at `-14` to `-18 dB` headroom.
   * Run a 3-minute **3P FFA (`GEN-V2` vs. `MONO-OS` vs. `PRIS-DEI`)** AI Spectator match on `skirmish_arena_03.tscn` (or `Procedural Arena`) at `2x` speed to confirm all three factions build, tech, fight, and render cleanly with zero console errors.