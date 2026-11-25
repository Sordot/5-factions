# Milestone 3.0b — `MONOLITH_OS` Core Roster, Neo-Brutalist Visuals & Industrial Audio (Tier 0–1)

**Prerequisite:** Milestone 3.0a (`36_milestone_3_0a_engine_foundations.md`) must be implemented and verified.  
**Goal:** Bring **Faction #2 (`MONOLITH_OS — The Iron Axiom`)** online as a selectable, playable faction with its full Tier 0–1 economy, buildings, combat/support units, neo-brutalist halftone procedural visuals, and industrial audio identity.  
**Next Step (Out of Scope Here):** Tier 2 (`Siege Gantry`, `Anvil Siege-Walker`, `Monolith Dreadnought`, `Null-Grid Projector`), the 3 faction upgrades, and full `SkirmishAI` tactical tuning belong in **Milestone 3.0c**.

**Non-Negotiable Constraints:**
* **Zero Regression on `GENESIS_V2`:** All existing `GENESIS_V2` scenes, visuals, audio, and stats must remain unchanged.
* **100% Procedural Pipeline:** No external image/audio assets; all visuals are Godot 2D vector draws and all audio is procedural synth.
* **Strict `1280×720` UI Discipline:** All new buttons, tooltips, Tech Tree entries, and Lobby selectors must remain 100% unclipped in Windowed `1280×720` and Fullscreen (`F11`).
* **Hard Exclusions:** No stealth/cloaking; no role-sorted formations.

---

## 1. Pre-Implementation Calibration Step (Inspect `GENESIS_V2` Baseline)

Before authoring `.tres` stats, inspect these existing files so `MONOLITH_OS` numbers sit in the exact same scale and convention as `GENESIS_V2`:
1. `resources/factions/genesis_v2_faction.tres` (starting resources, `ai_build_profile` format, `audio_timbre_profile`).
2. `resources/buildings/wetware_mainframe_data.tres` (read its `max_staff_slots` so `Logic Monolith` is set to `wetware_mainframe.max_staff_slots + 1`).
3. `resources/units/worker_unit_data.tres` and `resources/abilities/build_*.tres` (confirm whether workers use static `build_*.tres` ability resources or dynamic `FactionData.building_roster` generation; mirror that exact pattern for `Servo-Drone`).
4. `scripts/units/unit.gd` (confirm whether `damage_reduction` is a **flat** reduction or a **0.0–1.0 percentage** multiplier, and calibrate `MONOLITH_OS` armor values accordingly).

---

## 2. Faction Manifest (`resources/factions/monolith_os_faction.tres`)

Create `resources/factions/monolith_os_faction.tres` (`FactionData`) so `TeamManager` auto-discovers it in the Main Menu Skirmish Lobby:

* **Identity:**
  * `faction_id = &"monolith_os"`
  * `display_name = "MONOLITH_OS — The Iron Axiom"`
  * `short_code = "MONO-OS"`
  * `tagline = "Neo-brutalist machine-state. Slow, shielded heavy robotics, superior Silica/Compute extraction, and Core Overclocked industry."`
  * `is_playable = true`
  * `primary_color = Color(0.95, 0.94, 0.91, 1.0)` *(Stark Off-White `#F2EFE9`)*
  * `accent_color = Color(1.0, 0.624, 0.110, 1.0)` *(Hazard Amber `#FF9F1C`)*
  * `hud_accent_color = Color(1.0, 0.624, 0.110, 1.0)`
  * `boot_banner_text = "// AXIOM KERNEL LOCKED — MONOLITH_OS"`
  * `audio_bark_pitch_bias = 0.82`
  * `audio_timbre_profile = &"monolith_industrial"`
* **Starting Loadout & Economy Passive:**
  * `starting_biomass = 200`, `starting_silica = 50`, `starting_compute = 0`, `starting_worker_count = 3` *(match `GENESIS_V2` baseline unless otherwise tuned)*
  * `bonus_harvesters_by_resource = { &"silica": 1 }` *(Grants **3 Harvesters per `SilicaVein`** vs `GENESIS_V2`'s 2.)*
  * `starting_hub_scene` → `res://scenes/buildings/monolith_foundry_core.tscn`
  * `worker_scene` → `res://scenes/units/monolith_servo_drone.tscn`
  * `harvester_scene` → `res://scenes/units/monolith_ore_crawler.tscn`
  * `engineer_scene` → `res://scenes/units/monolith_grid_tech.tscn`
* **Rosters & Validation Safety:**
  * Populate `building_roster` with all 7 Tier 0–1 `BuildingData` resources below.
  * Populate `unit_roster` with all 7 Eco + Tier 1 `UnitData` resources below.
  * Populate `ai_build_profile` with valid Tier 0–1 roles (`&"hub": &"foundry_core"`, `&"supply": &"capacitor_pylon"`, `&"refinery": &"silica_smelter"`, `&"compute_hub": &"logic_monolith"`, `&"barracks_t1": &"assembly_bay"`, `&"counter_foundry": &"ballistics_lab"`).
  * Set `ai_scout_unit_id = &"picket_drone"`, `ai_salvage_unit_ids = [&"grid_tech", &"servo_drone"]`, and `ai_counter_units` pointing to valid Tier 1 `monolith_*` unit IDs (`&"bulwark_automaton"`, `&"rail_sentinel"`, `&"picket_drone"`) so `FactionData.validate()` passes with **zero warnings**.

---

## 3. Procedural Visual Language (`ui/overlays/entity_visuals.gd`)

Avoid stacking `if` chains inside existing `GENESIS_V2` drawing functions. Add a clean faction/style helper section in `entity_visuals.gd` for the **Neo-Brutalist Halftone** aesthetic:

### 3.1 Reusable Neo-Brutalist Halftone Helpers
* `_draw_brutalist_slab(canvas, rect, fill_col, outline_col, shadow_offset := Vector2(3.0, 3.0), chamfer := 5.0)`:
  * Draws a hard, zero-blur dark-ink drop shadow (`Color(0.04, 0.05, 0.07, 0.85)`) offset by `shadow_offset`.
  * Draws a chamfered 8-point polygon (sharp 45° corners) in matte gunmetal/concrete (`#2B2E33` / `#3A3E45`) tinted subtly with team color.
  * Strokes a crisp, thick dark-ink outer border (`2.2 px`) + stark off-white (`#F2EFE9`) or Hazard Amber (`#FF9F1C`) inner trim stripe.
* `_draw_halftone_dots(canvas, bounds: Rect2, spacing: float, dot_radius: float, col: Color, clip_inset := 4.0)`:
  * Draws a clean, deterministic grid of small circles (procedural halftone dot-matrix shading) inside a slab's shadow-side band or energy core. Keep dot counts lean (e.g., `spacing = 6.0–9.0 px`, max ~12–24 dots per building, 4–8 dots per unit) so frame times stay locked at 60+ FPS in 4P FFA.
* **Distinct Silhouettes:**
  * Every `MONOLITH_OS` building and unit must read immediately as sharp, blocky, architectural, and mechanical—zero organic curves or bio-vats.
  * Use team-color hazard stripes / corner brackets so `MONOLITH_OS` vs `MONOLITH_OS` mirror matches remain 100% readable in FFA/2v2.

### 3.2 Weapon Tracers & Combat VFX (`attack_tracer.gd` / `combat_vfx.gd`)
* Add/verify support for `MONOLITH_OS` weapon profiles:
  * `&"heavy_slug"` (thick amber/white high-impact twin-slug tracer with chunky muzzle flash).
  * `&"rail_lance"` (brief thin targeting lock-line during `attack_windup`, followed by a stark white-core / amber-halo high-velocity rail beam that lingers `0.18s`).
  * `&"arc_tether"` (crisp jagged amber-cyan suppressive arc for `Picket Drone`).

---

## 4. Industrial Audio Identity (`scripts/systems/audio_manager.gd`)

Extend `AudioManager` cleanly using `FactionData.audio_timbre_profile` (`&"monolith_industrial"`) and new `weapon_sfx_id` entries:
* **Weapon SFX:**
  * `&"weapon_mono_slug"`: Heavy low-mid mechanical thump + metallic bolt clack.
  * `&"weapon_mono_rail"`: Rising high-voltage capacitor whine → crisp sub-bass crack + metallic ring.
  * `&"weapon_mono_tether"`: Tight rhythmic electrical zap / stun pulse.
  * `&"weapon_mono_bastion"`: Deep pneumatic autocannon boom.
* **Utility & Bark Profile (`&"monolith_industrial"`):**
  * Lower-pitched, quantized harmonic tones and mechanical relay clicks for unit selection, move/attack orders, Overclock activation (deep turbine spin-up + resonant chime), and `Aegis Relay` shield overcharge pulse.
  * Preserve all existing `AudioManager` safeguards: single-voice `_bark_player` priority arbitration, 10-voice combat cap, real-time `Time.get_ticks_msec()` throttling under `2x` speed, and `-14` to `-18 dB` ambience headroom.

---

## 5. Tier 0–1 Building Roster (7 Structures)

Create `.tscn` scenes in `scenes/buildings/monolith_*.tscn` and `BuildingData` `.tres` files in `resources/buildings/monolith_*_data.tres`. Every structure has native regenerating shields (`max_shield`, `shield_regen_rate`, `shield_regen_delay`) and solid hull armor (`damage_reduction`).

| Building ID & Name | Tier | Role & Special Mechanics | Key Stats (Calibrate vs `GENESIS_V2`) |
| :--- | :--- | :--- | :--- |
| `foundry_core` (**Foundry Core**) | T0 | Command Hub (`is_command_hub = true`, `is_dropoff = true`, `accepted_dropoff_resources = [&"biomass", &"silica"]`).<br>**Core Overclock:** `can_overclock_buildings = true`, `overclock_speed_multiplier = 2.0`, `overclock_duration = 15.0`, `overclock_cooldown = 50.0`.<br>Trains: `Servo-Drone`, `Ore-Crawler`, `Grid-Tech`. | High HP (`~1250`), Shield `180` (`14/s`, `7s` delay), high armor. Cost: `300B / 150S`. Footprint `92×92`. |
| `capacitor_pylon` (**Capacitor Pylon**) | T0 | Bandwidth supply (`is_supply_provider = true`, `bandwidth_provided = 10`).<br>**Passive Aura:** Friendly shielded units/buildings within `220 px` recover from shield regen delay `35%` faster (lightweight periodic check or aura query; show subtle halftone radius ring when placing/selected). | HP `380`, Shield `80` (`10/s`, `6s`). Cost: `75B / 40S`. Footprint `56×56`. |
| `silica_smelter` (**Silica Smelter**) | T0 | Silica drop-off (`is_dropoff = true`, `accepted_dropoff_resources = [&"silica"]`). Trains `Ore-Crawler`. | HP `550`, Shield `90` (`10/s`, `7s`). Cost: `100B / 60S`. Footprint `74×74`. |
| `logic_monolith` (**Logic Monolith**) | T0 | Compute extractor (`requires_vent = true`).<br>**Saturation Advantage:** `max_staff_slots = wetware_mainframe.max_staff_slots + 1` (e.g., `3` if Wetware is `2`, or `4` if Wetware is `3`). | HP `520`, Shield `100` (`10/s`, `7s`). Cost: `110B / 90S`. Footprint `74×74`. |
| `assembly_bay` (**Assembly Bay**) | T1 | Primary robotics factory (`is_military_production = true`, `batch_production_count = 1`).<br>Trains: `Bulwark Automaton`, `Picket Drone`. | HP `780`, Shield `120` (`12/s`, `7s`). Cost: `140B / 95S`. Footprint `82×82`. |
| `ballistics_lab` (**Ballistics Lab**) | T1 | Precision & support facility (`is_military_production = true`, `prerequisite_building_ids = [&"assembly_bay"]`).<br>Trains: `Rail-Sentinel`, `Aegis Relay`. *(Will also research T1 upgrades in 3.0c.)* | HP `720`, Shield `120` (`12/s`, `7s`). Cost: `120B / 130S / 25C`. Footprint `80×80`. |
| `bastion_emplacement` (**Bastion Emplacement**) | T1 | Heavy static defense (`has_turret = true`, `audio_select_class = &"defense"`, `prerequisite_building_ids = [&"assembly_bay"]`).<br>Slow, high-impact AP cannon (`turret_damage = 44`, `turret_attack_interval = 1.85s`, `turret_attack_range = 310`, `turret_bonus_vs_armored = 1.35`, `turret_tracer_style = &"heavy_slug"`). | HP `650`, Shield `110` (`10/s`, `7s`), heavy armor. Cost: `80B / 110S`. Footprint `64×64`. |

---

## 6. Tier 0–1 Unit Roster (7 Units)

Create `.tscn` scenes in `scenes/units/monolith_*.tscn` and `UnitData` `.tres` files in `resources/units/monolith_*_data.tres`. All `MONOLITH_OS` units carry the `&"mechanical"` tag (repairable by `Grid-Tech`) and follow the dual-layer durability rule: **small unmitigated regenerating shield + high HP + high hull armor**.

### 6.1 Economy & Utility Units (3)

1. **`servo_drone` (*Servo-Drone*)**
   * **Role:** Worker / Builder (`can_gather = true`, `allowed_resource = &"biomass"`, `unit_tags = [&"worker", &"mechanical"]`, `minimap_icon_shape = &"worker"`).
   * **Stats:** Slightly slower than `GENESIS_V2` Worker (`move_speed = 205`), tougher (`max_hp = 75`, `max_shield = 20`, `shield_regen_rate = 5.0`, `shield_regen_delay = 6.0`), repairs friendly buildings, builds all 7 `MONOLITH_OS` T0–T1 structures. Cost: `50B`, `bw = 1`, `train_time = 4.5s`.
2. **`ore_crawler` (*Ore-Crawler*)**
   * **Role:** Silica Harvester (`can_gather = true`, `allowed_resource = &"silica"`, `unit_tags = [&"harvester", &"mechanical"]`, `minimap_icon_shape = &"worker"`).
   * **Stats:** Heavily armored treads (`max_hp = 115`, `max_shield = 30`, `shield_regen_rate = 6.0`, `is_armored = true`), slightly higher carry capacity (`12` vs `10`) or standard gather cadence—pairs with `MONOLITH_OS`'s 3-slot Silica saturation bonus. Cost: `60B / 20S`, `bw = 1`, `train_time = 5.0s`.
3. **`grid_tech` (*Grid-Tech*)**
   * **Role:** Compute Specialist / Field Mechanic (`can_staff_compute = true`, `unit_tags = [&"engineer", &"mechanical"]`, `minimap_icon_shape = &"worker"`).
   * **Stats:** Staffs `Logic Monolith` vents, extracts `SalvageCore`s, repairs friendly `&"mechanical"` units and buildings (`RepairComponent`). `max_hp = 85`, `max_shield = 25`, `shield_regen_rate = 6.0`. Cost: `50B / 45S`, `bw = 1`, `train_time = 5.0s`.

### 6.2 Combat & Support Units (4)

4. **`bulwark_automaton` (*Bulwark Automaton*)** — *Assembly Bay*
   * **Role:** Slow, immovable frontline bruiser (`unit_tags = [&"mechanical", &"armored", &"frontline"]`, `is_armored = true`).
   * **Combat Feel:** Slow walk (`move_speed = 165`), heavy twin-slug cannon (`attack_damage = 34`, `attack_cooldown = 1.65s`, `attack_windup = 0.14s`, `attack_range = 195`, `weapon_tracer_style = &"heavy_slug"`, `weapon_sfx_id = &"weapon_mono_slug"`).
   * **Durability:** `max_hp = 230`, `max_shield = 55` (`8/s`, `6s` delay), **high hull armor** (shrugs off `Clone Trooper` / `Stinger` rapid chip damage once shield breaks).
   * **Cost:** `85B / 55S`, `bw = 2`, `train_time = 7.0s`.
5. **`picket_drone` (*Picket Drone*)** — *Assembly Bay*
   * **Role:** Early-game scout, skirmisher, and anti-swarm pin unit (`unit_tags = [&"mechanical", &"scout", &"control"]`).
   * **Combat Feel:** Moderately mobile (`move_speed = 245`), fires a focused **Arc-Tether** (`attack_damage = 16`, `attack_cooldown = 1.25s`, `attack_range = 215`, `weapon_tracer_style = &"arc_tether"`, `weapon_sfx_id = &"weapon_mono_tether"`).
   * **Signature Ability — `Suppressive Lock` (`resources/abilities/monolith_suppressive_lock.tres`):** Active/Auto-Cast ability (cooldown `10s`, range `230`) that blasts a target enemy (and small `65 px` radius) with a `3.5s` `40%` movement & `25%` attack-speed slow via `StatusEffectComponent.apply_slow_debuff(...)`—built specifically to punish `GENESIS_V2` `Stinger` flanks.
   * **Durability:** `max_hp = 115`, `max_shield = 35` (`7/s`, `5.5s` delay), moderate armor.
   * **Cost:** `60B / 40S`, `bw = 1`, `train_time = 5.5s`.
6. **`rail_sentinel` (*Rail-Sentinel*)** — *Ballistics Lab*
   * **Role:** Long-range, slow-firing anti-armor precision walker (`unit_tags = [&"mechanical", &"anti_armor", &"heavy"]`, `is_armored = true`, `minimap_icon_shape = &"triangle_heavy"`).
   * **Combat Feel:** Deliberate speed (`move_speed = 155`), high-windup rail shot (`attack_damage = 68`, `bonus_vs_armored = 35.0`, `attack_cooldown = 2.6s`, `attack_windup = 0.28s`, `attack_range = 310`, `line_pierce_width = 18.0`, `weapon_tracer_style = &"rail_lance"`, `weapon_sfx_id = &"weapon_mono_rail"`).
   * **Durability & Salvage:** `max_hp = 195`, `max_shield = 60` (`9/s`, `6s` delay), solid armor; drops `salvage_silica = 35`, `salvage_compute = 10` on death.
   * **Cost:** `80B / 115S / 20C`, `bw = 3`, `train_time = 9.5s`.
7. **`aegis_relay` (*Aegis Relay*)** — *Ballistics Lab*
   * **Role:** Unarmed hovering shield-support prism (`unit_tags = [&"mechanical", &"support"]`, `attack_damage = 0.0`).
   * **Signature Ability — `Shield Overcharge` (`resources/abilities/monolith_shield_overcharge.tres`):** Active & **right-click Auto-Cast** (default ON) ability (`cooldown = 8.0s`, `range = 240`, `radius = 120`):
     * Restores `+45` native shield (via `restore_shield(45.0)`) to friendly shielded units in the target area AND grants a temporary `+30` unmitigated `Barrier` (`6.0s`) via `StatusEffectComponent.add_damage_shield(...)`.
     * Auto-Cast triggers when any nearby friendly combat unit's shield drops below `50%` (or takes hull damage).
   * **Durability:** `max_hp = 150`, `max_shield = 75` (`12/s`, `5.5s` delay), `move_speed = 190`.
   * **Cost:** `65B / 95S / 20C`, `bw = 2`, `train_time = 8.0s`.

---

## 7. Tech Tree Overlay & Sandbox Integration

* **Tech Tree (`U`):** Verify `scripts/ui/tech_tree_overlay.gd` dynamically reads the local player's `FactionData` so pressing `U` as `MONOLITH_OS` displays the 7 Tier 0–1 buildings, their units, prerequisites, and Hazard Amber accent cleanly inside the `ScrollContainer` at `1280×720`.
* **Sandbox Spawner (`sandbox_debug_panel.gd`):** Ensure `MONOLITH_OS` units appear cleanly in the sandbox spawner (or faction-filtered dropdown) so you can run `Bulwark + Rail-Sentinel + Aegis Relay` vs `GENESIS_V2` squad tests on `milestone_0_test.tscn`.

---

## 8. Verification & Playtest Checklist

1. **Lobby & Validation:**
   * Launch Godot and open the Skirmish Lobby; verify `MONOLITH_OS — The Iron Axiom` appears in every team slot dropdown with zero console errors and zero `FactionData.validate()` warnings.
   * Start a match as `MONOLITH_OS` vs `GENESIS_V2` on `skirmish_arena_01.tscn`; verify the Hazard Amber HUD accent and `// AXIOM KERNEL LOCKED — MONOLITH_OS` boot banner.
2. **Economy & Saturation:**
   * Verify `Servo-Drone` harvests Biomass normally (`X/3`), `Ore-Crawler` harvests Silica up to **`3/3`** per `SilicaVein` (while `GENESIS_V2` remains `2/2`), and `Logic Monolith` accepts `+1` extra `Grid-Tech` on `ComputeVent`.
3. **Core Overclock:**
   * Select `Foundry Core`, cast **Overclock Facility** on `Assembly Bay`, and verify `2.0×` unit build speed, amber VFX pulse, and `50s` cooldown.
4. **Combat Feel & Visual Readability:**
   * Pit `Bulwark Automaton` + `Picket Drone` + `Rail-Sentinel` + `Aegis Relay` against a `GENESIS_V2` `Clone Trooper` / `Stinger` / `Goliath` wave in `milestone_0_test.tscn`.
   * Verify halftone neo-brutalist silhouettes read crisply at normal zoom, shields absorb unmitigated damage before high hull armor blunts chip fire, `Aegis Relay` auto-casts `Shield Overcharge`, and `Rail-Sentinel` telegraphs + pierces cleanly.
5. **Layout Audit (`1280×720`):**
   * Check Main Menu, `ResourceHUD`, `SelectionHUD` (Foundry Core, Servo-Drone build grid, Aegis Relay, multi-select), and `TechTreeOverlay` (`U`) in both Windowed `1280×720` and Fullscreen (`F11`) for zero clipping.