# Technical Glossary & RTS Stat Specifications (Godot 4.7)

This reference defines the exact terminology, units of measurement, and Godot data structures used in **5-factions**. Use these terms when describing units, combat feel, abilities, economy, or balance changes so design notes in Gemini Notebook map 1-to-1 to code and `.tres` data files.

---

## 1. Godot 4 Architecture Vocabulary (How Our Project Works)

| Term | File Extension | What It Means in This Project |
| :--- | :--- | :--- |
| **Scene** | `.tscn` | A reusable tree of Nodes (e.g., `scenes/units/test_unit.tscn`, `scenes/test/milestone_0_test.tscn`). Think of a scene as a prefab or level. |
| **Script** | `.gd` | Strictly typed GDScript logic attached to a Node or defining a custom data class (e.g., `scripts/units/unit.gd`). |
| **Resource** | `.tres` | A plain-text, inspector-editable **data asset** (e.g., `resources/units/test_unit_data.tres`). All tunable balance numbers (HP, speed, damage, costs) live here so you can balance units without editing code. |
| **Node** | *(inside `.tscn`)* | A building block with one job (e.g., `CharacterBody2D` for physics movement, `NavigationAgent2D` for pathfinding, `Area2D` for range detection). |
| **Signal** | *(in `.gd`)* | An event emitted by a Node when something happens (e.g., `selection_changed`, `health_changed`, `died`). Keeps UI and gameplay loosely coupled. |
| **Group** | *(runtime tag)* | A label attached to Nodes for fast lookup (e.g., `"selectable_units"`, future `"damageable"`, `"buildings"`, `"faction_player"`). |
| **Autoload (Singleton)** | *(in `project.godot`)* | A globally accessible Node always present across scenes (e.g., future `EconomyManager`, `MatchManager`, `EventBus`). |
| **`_unhandled_input`** | *(callback)* | Input hook used by world controllers (`SelectionController`, `RTSCamera`) so clicking on HUD/UI elements automatically blocks clicks from leaking through to the battlefield. |

### Measurement Conventions (Always Explicit)
* **Distance / Range / Radius:** **World pixels (`px`)**. For scale reference: our Milestone 0 arena is `1280 × 720 px`, and `TestUnit`'s collision body is `16 px` radius (`32 px` diameter).
* **Time / Cooldowns / Durations:** **Seconds (`s`)**.
* **Linear Speed:** **Pixels per second (`px/s`)**. (`TestUnit` currently moves at `260 px/s`, crossing `1280 px` in ~`4.9 s`.)
* **Acceleration:** **Pixels per second squared (`px/s²`)**. Higher = snappier SC2-style instant starts/stops (currently `1800 px/s²`).
* **Turn Speed:** **Radians per second (`rad/s`)**. Higher = crisper rotation toward movement or target (currently `14 rad/s`).

---

## 2. Unit Data Schema (`UnitData` Resource)

`UnitData` (`scripts/data/unit_data.gd`) is the base stat sheet attached to every unit `.tscn`. Items marked **[Live]** exist in Milestone 0; items marked **[M1]** are the planned schema for Milestone 1.

### A. Identity & Economy
| Field Name | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `unit_id` | `StringName` | [M1] | Stable machine key (e.g., `&"worker"`, `&"infantry_basic"`). |
| `display_name` | `String` | **[Live]** | Player-facing name in HUD/tooltips. |
| `unit_tags` | `Array[StringName]` | [M1] | Classification tags used for counters and abilities (e.g., `BIOLOGICAL`, `MECHANICAL`, `WORKER`, `LIGHT`, `ARMORED`). |
| `biomass_cost` | `int` | [M1] | Biomass spent to train/produce. |
| `silica_cost` | `int` | [M1] | Silica spent to train/produce. |
| `compute_cost` | `int` | [M1] | Compute spent to train/produce. |
| `bandwidth_cost` | `int` | [M1] | Population cap consumed while alive. |
| `build_time` | `float` (`s`) | [M1] | Production duration in seconds. |

### B. Movement & Navigation
| Field Name | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `move_speed` | `float` (`px/s`) | **[Live]** | Top movement speed. |
| `acceleration` | `float` (`px/s²`) | **[Live]** | How quickly the unit reaches top speed and stops. |
| `turn_speed` | `float` (`rad/s`) | **[Live]** | Visual/facing rotation responsiveness. |
| `selection_radius` | `float` (`px`) | **[Live]** | Click-select hit radius around the unit center. |
| `collision_radius` | `float` (`px`) | **[Live]** (`CollisionShape2D`) | Physical body radius (`16 px` on `TestUnit`). |
| `agent_radius` | `float` (`px`) | **[Live]** (`NavigationPolygon`) | Clearance kept from obstacles during pathfinding (`20 px` in M0). |

### C. Health, Survivability & Defense
| Field Name | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `max_health` | `float` (HP) | [M1] | Maximum hit points. Unit dies when `current_health <= 0`. |
| `armor` | `float` | [M1] | **Flat damage reduction per hit** (SC2/C&C style: `final_dmg = max(min_damage, raw_dmg - armor)`). Strong against rapid, low-damage attacks; weak against heavy single shots. |
| `damage_reduction_pct` | `float` (`0.0–1.0`) | Optional | **Percentage mitigation** (`final_dmg = raw_dmg * (1.0 - pct)`). Specify **flat armor** vs **% reduction** explicitly when designing mechanics. |
| `health_regen_rate` | `float` (`HP/s`) | Optional | Passive health restored per second (often biological-only or out-of-combat). |
| `sight_range` | `float` (`px`) | [M1] | Vision radius for fog-of-war / scouting. |

---

## 3. Combat & Weapon Schema (`WeaponData` Resource — M1)

Keeping weapons in a dedicated `WeaponData` resource lets a single unit swap weapons, have separate anti-ground/anti-structure stats, or share weapon definitions cleanly.

### A. Damage & Counters
| Term / Field | Type | Meaning |
| :--- | :--- | :--- |
| `base_damage` | `float` | Raw damage dealt per hit before armor or tag modifiers. |
| `bonus_damage_by_tag` | `Dictionary` | Conditional bonus damage against specific tags (e.g., `{"ARMORED": 10.0}` or `{"STRUCTURE": 1.5x}`). Specify whether a bonus is **flat (`+10`)** or **multiplier (`1.5x`)**. |
| `damage_type` | `enum` | Optional damage profile (`KINETIC`, `ENERGY`, `EXPLOSIVE`, `BIO`) if using a C&C-style damage-vs-armor matrix. |
| `splash_radius` | `float` (`px`) | Area-of-Effect (AoE) radius (`0` = single-target). |
| `splash_falloff` | `float` (`0.0–1.0`) | Damage multiplier at the outer edge of splash (e.g., `0.5` = 50% at edge) + `friendly_fire: bool`. |

### B. Attack Speed, Timing & Micro Feel (SC2-Style)
When talking about attack speed, be explicit about whether you mean **cooldown** or **attacks per second**:
* **`attack_cooldown` (`s`):** Time between consecutive attacks (e.g., `0.8 s`). *Lower = faster.*
* **`attacks_per_second` (`APS`):** Rate of fire (`1.0 / attack_cooldown`, e.g., `1.25 APS`). *Higher = faster.*
* **`DPS` (Damage Per Second):** `base_damage / attack_cooldown` (or `base_damage * APS`).
* **`windup_time` / `damage_point` (`s`):** Delay from starting an attack animation until the damage/projectile actually fires (e.g., `0.10 s`). Short windup = snappy stutter-stepping.
* **`backswing_time` (`s`):** Post-fire recovery animation that a player can cancel by issuing a Move command (enables SC2-style kiting/stutter-stepping without bypassing `attack_cooldown`).
* **`can_move_and_shoot` (`bool`):** Whether the unit fires on the move (e.g., fast harassment units) or must stop to fire.

### C. Range & Targeting
| Term / Field | Type | Meaning |
| :--- | :--- | :--- |
| `attack_range` | `float` (`px`) | Max distance to fire at a target. **Important:** specify **edge-to-edge** (standard RTS: `distance - attacker_radius - target_radius <= attack_range`, so large buildings don't feel "out of range") vs **center-to-center**. Edge-to-edge is recommended. |
| `min_range` | `float` (`px`) | Minimum firing distance (for artillery/siege units; `0` for normal units). |
| `aggro_range` | `float` (`px`) | Auto-acquisition radius when Idle, Attack-Moving, or Patrolling (typically `>= attack_range`, e.g., `attack_range + 80 px`). |
| `delivery_type` | `enum` | `HITSCAN` (instant damage on fire), `PROJECTILE_HOMING` (tracks target), `PROJECTILE_SKILLSHOT` (travels to point/direction, dodgeable), or `MELEE`. |
| `projectile_speed` | `float` (`px/s`) | Travel speed if using a projectile scene. |

---

## 4. Unit State Machine, Commands & Active Abilities

### Standard RTS Command Vocabulary (Locked in GDD)
| Command | Input (Planned) | Behavior |
| :--- | :--- | :--- |
| **Move** | `RMB` on ground | Navigate to destination ignoring enemies (implemented in M0). |
| **Attack Target** | `RMB` on enemy | Move into `attack_range` of that specific target and focus-fire until dead or re-ordered. |
| **Attack-Move (`A-Move`)** | `A` + `LMB` | Move toward destination; stop and engage any enemy entering `aggro_range`, then resume moving. |
| **Patrol** | `P` + `LMB` | Loop between origin and target waypoint, engaging enemies in `aggro_range` along the way. |
| **Hold Position** | `H` | Do not move or chase; fire at enemies that enter `attack_range`. |
| **Stop** | `S` | Cancel active order and return to `IDLE` (auto-acquire nearby threats). |

### Unit State Machine (`UnitState`)
When discussing bugs or edge cases, refer to states explicitly:
`IDLE` · `MOVING` · `ATTACK_MOVING` · `PATROLLING` · `HOLDING_POSITION` · `CHASING` · `ATTACKING` · `GATHERING` · `CONSTRUCTING` · `CASTING`

### Active Ability Schema (`AbilityData` Resource — M1)
| Field Name | Type | Meaning |
| :--- | :--- | :--- |
| `ability_id` | `StringName` | Unique identifier (e.g., `&"emp_pulse"`, `&"stim_protocol"`). |
| `targeting_mode` | `enum` | `INSTANT_SELF`, `GROUND_POINT`, `UNIT_TARGET`, or `DIRECTION_LINE` (skill-shot). |
| `cast_range` | `float` (`px`) | Max distance from caster to target point/unit. |
| `cooldown` | `float` (`s`) | Time before ability can be cast again. |
| `cast_time` | `float` (`s`) | Channel/windup delay (`0.0` = instant). |
| `effect_radius` | `float` (`px`) | AoE radius at target point (`0` = single target). |
| `duration` | `float` (`s`) | Length of buff, debuff, or zone effect. |
| `cost` | `Dictionary` | Optional energy, health, or resource cost per cast. |

---

## 5. Buildings, Economy & Map Mechanics Vocabulary (M1)

* **Buildings (`BuildingData`):** `max_health`, `armor`, `footprint_size` (`Vector2` in `px` for placement grid & navmesh obstacle cutout), `build_time`, `bandwidth_provided` (pop cap added), `production_list` (trainable `UnitData` array), `rally_point`.
* **Gathering & Economy:**
  * **Biomass (Direct Worker Harvest):** `gather_rate` (`amount/s`), `node_capacity` (total resource before depletion).
  * **Silica (Automated Harvester Shuttle):** `harvest_time`, `carry_capacity`, `unload_time`, linked `Refinery` drop-off.
  * **Compute (Staffed Facility):** `max_workers` (staffing slots), `income_per_worker_per_sec`.
* **Data Hyper-Uplink (Central Objective):** `capture_radius` (`px`), `capture_time` (`s`), `contest_behavior` (pauses or reverses when both factions present), `production_bonus_pct` (`+0.05` = `+5%`).
* **Encroaching Hazard Zone:** `phase_list` (array of `{wait_time, shrink_duration, target_radius}`), `hazard_dps` (damage per second outside safe boundary), `tick_interval` (`s`).

---

## 6. Quick Prompt Template (Copy/Paste for Design & Balance Requests)

When asking to create or tune a unit, ability, or combat system, you can drop in a concise spec like this:

```markdown
### Unit Spec: <Unit Name>
- **Role / Tags:** BIOLOGICAL, LIGHT | Costs: 50 Biomass, 0 Silica, 0 Compute, 1 Bandwidth | Build: 12s
- **Survivability:** 65 HP | 0 flat armor | Sight: 380 px | Collision: 14 px
- **Movement:** 240 px/s | Accel: 1800 px/s² | Turn: 14 rad/s
- **Weapon:** 8 damage (+4 vs LIGHT) | Cooldown: 0.75s (1.33 APS) | Windup: 0.08s | Range: 220 px (edge-to-edge) | Aggro: 300 px | Delivery: HITSCAN
- **Active Ability:** <Name> — GROUND_POINT skill-shot | Range: 280 px | Radius: 75 px | Cooldown: 14s | Effect: <what it does>
```
