# Milestone 1.2 Plan: Faction #1 — `GENESIS_V2` (*The Vat-Born*)

**Target Directory:** `docs/agy_plans/10_faction_01_genesis_v2.md`
**Primary Scene:** `res://scenes/maps/skirmish_arena_01.tscn` (and `res://scenes/test/milestone_0_test.tscn`)
**Reference Docs:** `docs/project_reference_doc_gdd.md`, `docs/technical_glossary_and_specs.md`, `docs/agy_plans/skirmish_ai_fog_of_war_expanded_arena_plan.md`

---

## 1. Faction Identity & Core Design Philosophy

* **Faction / AI Lord Name:** `GENESIS_V2` (*The Vat-Born*)
* **Visual & Aesthetic Direction (Technozen / Y2K):** Translucent white/silver hardware casings, glowing bioluminescent culture vats, clean geometric monoliths, and cyan/emerald telemetry accents.
* **Mechanical Identity — Exponential Scaling:**
  * **Early-Game Swarm Tempo:** Outproduces opponents 1:1 through **Parallel Batch Cloning** at its Tier-1 **Cloning Vat** (spawning **2 units** per production cycle for **`1.75x`** the base single-unit resource cost and `2x` Bandwidth).
  * **Mid-Game Situational Counters:** Uses the **Calibration Foundry** for specialized, slower mechanized utility and anti-armor responses (**Lance-Rig** and **Signal Jammer**).
  * **Late-Game Heavy Pivot:** Transitions high **Compute + Biomass/Silica** economies into towering, high-impact bio-synthetic constructs at the **Synthetics Fabricator** (**Goliath Frame**, **Arc-Lancer**, and **Chrysalis Mortar**).

---

## 2. Economy & Infrastructure Structures

Keep **Worker**, **Harvester**, and **Engineer** unit names universal across factions for clarity, while theming `GENESIS_V2`'s economy and population buildings:

| Legacy Prototype | `GENESIS_V2` Structure | Resource Cost | Build Time | Role & Mechanics |
| :--- | :--- | :--- | :--- | :--- |
| `command_core` | **Nexus Vat** (`nexus_vat.tscn`) | `400 B` | `20.0s` | Primary hub, **Biomass** drop-off, provides `+10 Bandwidth`, trains `Worker`, `Harvester`, `Engineer`. |
| `bandwidth_relay` | **Synapse Pylon** (`synapse_pylon.tscn`) | `75 B` | `4.0s` | Increases **Bandwidth Cap** by `+8`. |
| `silica_refinery` | **Silica Condenser** (`silica_condenser.tscn`) | `100 B` | `5.0s` | **Silica** drop-off facility for automated `Harvester` units. |
| `compute_node` | **Wetware Mainframe** (`wetware_mainframe.tscn`) | `100 B, 50 S` | `6.0s` | Built on a `ComputeVent`; staffs up to `2 Engineers` to generate **Compute**. |

---

## 3. Military Structures & Unit Roster

### A. Tier 1: Cloning Vat (`cloning_vat.tscn`)
* **Build Cost:** `150 Biomass` | **Build Time:** `8.0s` | **Prerequisite:** `Nexus Vat`
* **Signature Mechanic — Parallel Batch Cloning:**
  * Every unit queued at the **Cloning Vat** is trained as a **2-unit batch** over a single build timer.
  * Batch resource cost equals **`1.75x`** single-unit cost (modified by the **Batch Efficiency** upgrade) and requires **`2x`** unit Bandwidth upfront.
  * On completion, **2 units** spawn side-by-side at the exit marker and execute the building's rally order.

| Unit | Base Single Cost (Batch `1.75x`) | Bandwidth (Per Unit / Batch) | Train Time | Role, Stats & Abilities |
| :--- | :--- | :--- | :--- | :--- |
| **Clone Trooper** (`clone_trooper.tscn`) | `50 B` (`88 B` batch) | `1` (`2` batch) | `5.0s` | Core rapid-fire bio-polymer infantry (`HP: 65`, `Dmg: 9`, `Range: 170`). **Active Ability (`Q` — Adrenal Surge):** Temporarily boosts move speed (`+35%`) and attack speed (`+30%`) for `4.0s` (`10.0s` cooldown). |
| **Stinger** (`stinger.tscn`) | `45 B, 15 S` (`79 B, 26 S` batch) | `1` (`2` batch) | `4.5s` | Fast, fragile melee/short-range flanker (`HP: 45`, `Dmg: 11`, `Range: 42`, high `move_speed` & `vision_range: 480`). **No active ability**—relies on speed for scouting, harassment, and contesting the Data Hyper-Uplink. |
| **Symbiote** (`symbiote.tscn`) | `60 B, 25 S` (`105 B, 44 S` batch) | `1` (`2` batch) | `6.0s` | Light support bio-drone (`HP: 55`, `Dmg: 4`, `Range: 110`). **Passive — Stacking Heal Aura:** Emits a weak regenerative pulse (`+2 HP/s` in `130px` radius) to nearby friendly units that **stacks** when multiple Symbiotes overlap. |

---

### B. Tier 1.5 (Situational Mech): Calibration Foundry (`calibration_foundry.tscn`)
* **Build Cost:** `150 Biomass, 75 Silica` | **Build Time:** `10.0s` | **Prerequisite:** `Nexus Vat`
* **Design Role:** Relatively weaker baseline generalist output than `GENESIS_V2`'s bio-synth buildings, providing **situational utility and hard counters** when enemy compositions demand them (standard single-unit production, no batch cloning).

| Unit | Cost | Bandwidth | Train Time | Role, Stats & Abilities |
| :--- | :--- | :--- | :--- | :--- |
| **Lance-Rig** (`lance_rig.tscn`) | `120 B, 90 S` | `2` | `8.0s` | Deliberate anti-armor mech (`HP: 160`, `Dmg: 28`, `Range: 220`, slow fire rate). Deals **bonus damage vs. Heavy/Armored & Structure targets** (`+15` bonus damage), acting as a situational counter to heavy frontlines. |
| **Signal Jammer** (`signal_jammer.tscn`) | `90 B, 80 S, 25 C` | `2` | `7.5s` | Tactical utility & disruption walker (`HP: 120`, `Dmg: 6`, `Range: 160`). **Active Ability (`Q` — Static Pulse):** Emits an interference field (`150px` radius, `12.0s` cooldown) that reduces enemy attack speed by `-30%` and move speed by `-25%` for `4.0s`. |

---

### C. Tier 2 (Heavy Tech): Synthetics Fabricator (`synthetics_fabricator.tscn`)
* **Build Cost:** `200 Biomass, 150 Silica, 50 Compute` | **Build Time:** `14.0s` | **Prerequisite:** `Cloning Vat`
* **Design Role:** High-Compute late-game powerhouse producing massive, punchy centerpieces (standard single-unit production, no batch cloning).

| Unit | Cost | Bandwidth | Train Time | Role, Stats & Abilities |
| :--- | :--- | :--- | :--- | :--- |
| **Goliath Frame** (`goliath_frame.tscn`) | `225 B, 150 S, 75 C` | `4` | `12.0s` | Towering front-line armored juggernaut (`HP: 420`, `Dmg: 34`, `Range: 140`, high armor/damage mitigation). **Active Ability (`Q` — Seismic Slam):** Heavy ground impact (`110px` radius, `10.0s` cooldown) dealing `55` AoE damage and briefly slowing nearby enemies. |
| **Arc-Lancer** (`arc_lancer.tscn`) | `200 B, 175 S, 100 C` | `4` | `13.0s` | Tall Y2K bio-capacitor strider (`HP: 260`, `Dmg: 48`, `Range: 280`). **Passive — Colossus Stride:** Bypasses unit-to-unit collision masks so it **walks cleanly over smaller friendly ground units** without body-blocking swarms. Fires a high-energy arc lance that pierces/splashes in a tight line. |
| **Chrysalis Mortar** (`chrysalis_mortar.tscn`) | `175 B, 150 S, 100 C` | `3` | `12.0s` | Heavy long-range bio-ordnance platform (`HP: 210`, `Dmg: 45` AoE, `Range: 420`, `min_range: 110`). Lobs arcing caustic bio-shells that devastate clustered infantry and static defenses. **Active Ability (`Q` — Spore Barrage):** Fires a high-impact cluster shell at target ground (`130px` radius, `14.0s` cooldown). |

---

## 4. Faction Tech & Upgrades

Upgrades are researched directly at their respective structures (using the same queue/progress system as unit production, deducting **Biomass / Silica / Compute** upfront and applying global team modifiers via a new `UpgradeManager` / `TechTree` tracker in `EconomyManager`):

1. **Batch Efficiency** *(Researched at **Cloning Vat** — Cost: `100 B, 75 S, 40 C`, Research Time: `12.0s`)*
   * **Effect:** Reduces the **Cloning Vat** parallel batch cost multiplier from **`1.75x` → `1.50x`** single-unit cost (and trims batch build time by `-10%`), supercharging mid-to-late swarm replenishment.
2. **Adrenal Potency** *(Researched at **Cloning Vat** — Cost: `100 B, 50 S, 50 C`, Research Time: `12.0s`)*
   * **Effect:** Increases **Clone Trooper** *Adrenal Surge* duration from `4.0s` → `6.0s` and adds `+15%` extra attack speed during the buff.
3. **Compute Overdrive** *(Researched at **Synthetics Fabricator** — Cost: `150 B, 125 S, 100 C`, Research Time: `15.0s`)*
   * **Effect:** Hardens **Goliath Frame** neural-chassis integration, granting **`+20%` movement speed** and **`-15%` incoming damage reduction** to all **Goliath Frames**.

---

## 5. Technical Architecture & File Plan

### New Data & System Files
* `scripts/data/upgrade_data.gd` (`class_name UpgradeData extends Resource`)
  * Exports: `upgrade_id: StringName`, `display_name: String`, `description: String`, `hotkey_label: String`, `biomass_cost: int`, `silica_cost: int`, `compute_cost: int`, `research_time: float`, `modifier_key: StringName`, `modifier_value: float`.
* `scripts/systems/upgrade_manager.gd` (or integrated cleanly into `EconomyManager` per team)
  * Tracks `researched_upgrades: Dictionary` (`team -> Array[StringName]`), emits `upgrade_completed(team, upgrade_id)`, and exposes helper queries (`has_upgrade(team, id)`, `get_batch_cost_multiplier(team)`).
* `resources/upgrades/`
  * `batch_efficiency.tres`, `adrenal_potency.tres`, `compute_overdrive.tres`

### Resource & Scene Extensions
* **Building Resources (`resources/buildings/`):**
  * Rename/update existing definitions and add new ones:
    * `nexus_vat_data.tres`, `synapse_pylon_data.tres`, `silica_condenser_data.tres`, `wetware_mainframe_data.tres`
    * `cloning_vat_data.tres` (`@export var batch_production_count: int = 2`, `@export var base_batch_cost_multiplier: float = 1.75`)
    * `calibration_foundry_data.tres`
    * `synthetics_fabricator_data.tres` (`@export var required_building_id: StringName = &"cloning_vat"`)
* **Worker Build Abilities (`resources/abilities/`):**
  * Update worker build slots (`Q`: **Nexus Vat / Silica Condenser**, `W`: **Wetware Mainframe**, `E`: **Synapse Pylon**, `R`: **Cloning Vat**, `T`: **Calibration Foundry**, `Y`: **Synthetics Fabricator** — or split into **Basic Structures** vs. **Advanced Structures** sub-card if exceeding 6 slots, checking `required_building_id` so `Synthetics Fabricator` unlocks once a `Cloning Vat` is constructed).
* **Unit Resources & Scenes (`resources/units/`, `scenes/units/`):**
  * `clone_trooper_data.tres` + `clone_trooper.tscn`
  * `stinger_data.tres` + `stinger.tscn`
  * `symbiote_data.tres` + `symbiote.tscn` (includes lightweight `HealAuraComponent` ticking every `0.5s` on nearby friendly units)
  * `lance_rig_data.tres` + `lance_rig.tscn` (`@export var bonus_vs_armored: float = 15.0`)
  * `signal_jammer_data.tres` + `signal_jammer.tscn`
  * `goliath_frame_data.tres` + `goliath_frame.tscn` (`@export var damage_reduction: float = 0.15`, boosted by `Compute Overdrive`)
  * `arc_lancer_data.tres` + `arc_lancer.tscn` (`@export var ignore_friendly_unit_collision: bool = true` — removes friendly `Units` collision mask bits while keeping `World` terrain collision so it walks smoothly over allied ground units)
  * `chrysalis_mortar_data.tres` + `chrysalis_mortar.tscn` (`@export var min_attack_range: float = 110.0`, `aoe_attack_radius: float = 72.0`)
* **Production Component (`scripts/buildings/production_component.gd`):**
  * Support queuing both `UnitData` (respecting `batch_production_count` and `get_batch_cost_multiplier(team)` for **Cloning Vat**) and `UpgradeData` (preventing duplicate queuing of already-researched or currently-queued upgrades).
* **Skirmish AI Update (`scripts/systems/skirmish_ai.gd`):**
  * Update building/unit references to use the new `GENESIS_V2` resource IDs (`cloning_vat`, `silica_condenser`, `synapse_pylon`, `clone_trooper`, `stinger`, and late-game `synthetics_fabricator` / `goliath_frame`).

---

## 6. Verification Checklist for `agy`

Before concluding this milestone, verify in `skirmish_arena_01.tscn` and `milestone_0_test.tscn`:

* [ ] **Renamed Economy & Infrastructure:** Workers construct **Nexus Vat**, **Synapse Pylon**, **Silica Condenser**, and **Wetware Mainframe**, and all three resource gathering loops (`Worker`, `Harvester`, `Engineer`) function cleanly.
* [ ] **Cloning Vat Batch Production:** Queuing a **Clone Trooper** (`50 B` base) at a **Cloning Vat** deducts `88 Biomass` (`1.75x`) and `2 Bandwidth`, and spawns **2 Clone Troopers** simultaneously upon completion.
* [ ] **Tier-1 Unit Mechanics:** **Clone Trooper** *Adrenal Surge* (`Q`) visibly boosts speed/fire rate; **Stinger** moves rapidly with high vision and no active ability; multiple **Symbiotes** stack their passive healing aura on wounded allies.
* [ ] **Calibration Foundry Counters:** **Lance-Rig** deals bonus damage to armored/heavy targets (`Goliath Frame` / buildings); **Signal Jammer** *Static Pulse* (`Q`) slows enemy movement and attack speed in radius.
* [ ] **Synthetics Fabricator Heavy Pivot:** Requires a completed **Cloning Vat** to build; **Arc-Lancer** walks directly over friendly Clone Troopers/Workers without colliding or getting stuck; **Goliath Frame** *Seismic Slam* and **Chrysalis Mortar** long-range AoE shells fire properly.
* [ ] **Upgrades:** Researching **Batch Efficiency** drops Cloning Vat batch cost from `1.75x` to `1.50x`; **Adrenal Potency** extends *Adrenal Surge*; **Compute Overdrive** visibly increases **Goliath Frame** movement speed and reduces incoming damage.