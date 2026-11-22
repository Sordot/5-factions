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
| **Signal** | *(in `.gd`)* | An event emitted by a Node when something happens (e.g., `selection_changed`, `health_changed`, `died`, `ability_cooldown_updated`, `ability_executed`, `ability_targeting_changed`). Keeps UI (`SelectionHUD`) strictly signal-driven with zero `_process()` polling. |
| **Group** | *(runtime tag)* | A label attached to Nodes for fast lookup (live: `"units"`, `"selectable_units"`; future: `"buildings"`, `"faction_player"`). |
| **Physics Layers** | *(in `project.godot`)* | **Layer 1 (`World`)** for arena obstacles/walls; **Layer 2 (`Units`)** for `TestUnit`, `ScoutUnit`, and `TargetDummy`. Units mask `World + Units` (`3`) so `move_and_slide()` resolves unit-to-unit overlap cleanly. |
| **Component** | *(child Node `.gd`)* | Dedicated helper attached to an entity to avoid monolithic scripts (e.g., `AbilityComponent` on `Unit` handles cooldowns, range-check casts, and AoE/instant execution; `SubgroupHelper` handles subgroup sorting and ready-caster selection). |
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

`UnitData` (`scripts/data/unit_data.gd`) is the base stat sheet attached to every unit `.tscn` (live assets: `resources/units/test_unit_data.tres`, `resources/units/scout_unit_data.tres`, `resources/units/target_dummy_data.tres`). Items marked **[Live]** exist today; items marked **[M1]** are planned for Milestone 1.

### A. Identity, Subgroups & Economy
| Field Name | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `unit_type_id` | `StringName` | **[Live]** | Stable machine key used for `Tab` subgroup grouping and sorting (e.g., `&"test_unit"`, `&"scout_unit"`, `&"target_dummy"`). |
| `display_name` | `String` | **[Live]** | Player-facing name in `SelectionHUD` / tooltips. |
| `abilities` | `Array[AbilityData]` | **[Live]** | Active abilities bound to this unit type (populated on the Command Card when this subgroup is active). |
| `unit_tags` | `Array[StringName]` | [M1] | Classification tags used for counters and abilities (e.g., `BIOLOGICAL`, `MECHANICAL`, `WORKER`, `LIGHT`, `ARMORED`). |
| `biomass_cost` | `int` | [M1] | Biomass spent to train/produce. |
| `silica_cost` | `int` | [M1] | Silica spent to train/produce. |
| `compute_cost` | `int` | [M1] | Compute spent to train/produce. |
| `bandwidth_cost` | `int` | [M1] | Population cap consumed while alive. |
| `build_time` | `float` (`s`) | [M1] | Production duration in seconds. |

### B. Movement, Collision & Navigation
| Field Name | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `move_speed` | `float` (`px/s`) | **[Live]** | Top movement speed (`260 px/s` on `TestUnit`, `340 px/s` on `Recon Scout`, `0` on `TargetDummy`). |
| `acceleration` | `float` (`px/s²`) | **[Live]** | How quickly the unit reaches top speed and stops. |
| `turn_speed` | `float` (`rad/s`) | **[Live]** | Visual/facing rotation responsiveness. |
| `selection_radius` | `float` (`px`) | **[Live]** | Click-select hit radius around the unit center. |
| `collision_radius` | `float` (`px`) | **[Live]** | Physical footprint radius used for `CollisionShape2D`, overlap separation, concentric ring destination spacing (`2.6×`), and edge-to-edge combat range (`16 px` TestUnit, `14 px` Scout, `18 px` Dummy). |
| `agent_radius` / RVO | `float` (`px`) | **[Live]** | `NavigationAgent2D` `avoidance_enabled = true` (`velocity_computed`) + `NavigationObstacle2D` on stationary dummies for local steering around peers and dummies. |

### C. Health, Survivability & Defense
| Field Name | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `max_hp` | `float` (HP) | **[Live]** | Maximum hit points (`100` on `TestUnit`/`TargetDummy`, `70` on `Recon Scout`). Unit dies (`queue_free()`) when `current_hp <= 0`. |
| `armor` | `float` | [M1] | **Flat damage reduction per hit** (SC2/C&C style: `final_dmg = max(min_damage, raw_dmg - armor)`). Strong against rapid, low-damage attacks; weak against heavy single shots. |
| `damage_reduction_pct` | `float` (`0.0–1.0`) | Optional | **Percentage mitigation** (`final_dmg = raw_dmg * (1.0 - pct)`). Specify **flat armor** vs **% reduction** explicitly when designing mechanics. |
| `health_regen_rate` | `float` (`HP/s`) | Optional | Passive health restored per second (often biological-only or out-of-combat). |
| `sight_range` | `float` (`px`) | [M1] | Vision radius for fog-of-war / scouting. |

---

## 3. Combat & Weapon Specs (`UnitData` Live / `WeaponData` M1)

Core basic-attack fields are **[Live]** directly on `UnitData` today (`attack_damage`, `attack_range`, `aggro_range`, `attack_cooldown`, measured **edge-to-edge** with `AttackTracer` instant-hit feedback). In Milestone 1, advanced weapon profiles can move into a dedicated `WeaponData` resource if units need multi-weapon loadouts.

### A. Damage & Counters
| Term / Field | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `attack_damage` (`base_damage`) | `float` | **[Live]** | Raw damage dealt per hit (`20` on `TestUnit`, `12` on `Recon Scout`). |
| `bonus_damage_by_tag` | `Dictionary` | [M1] | Conditional bonus damage against specific tags (e.g., `{"ARMORED": 10.0}` or `{"STRUCTURE": 1.5x}`). Specify **flat (`+10`)** vs **multiplier (`1.5x`)**. |
| `damage_type` | `enum` | [M1] | Optional damage profile (`KINETIC`, `ENERGY`, `EXPLOSIVE`, `BIO`) if using a C&C-style damage-vs-armor matrix. |
| `splash_radius` | `float` (`px`) | [M1] | Area-of-Effect (AoE) radius (`0` = single-target). |
| `splash_falloff` | `float` (`0.0–1.0`) | [M1] | Damage multiplier at the outer edge of splash + `friendly_fire: bool`. |

### B. Attack Speed, Timing & Micro Feel (SC2-Style)
When talking about attack speed, be explicit about whether you mean **cooldown** or **attacks per second**:
* **`attack_cooldown` (`s`) [Live]:** Time between consecutive attacks (`0.7 s` on `TestUnit`, `0.5 s` on `Recon Scout`). *Lower = faster.*
* **`attacks_per_second` (`APS`):** Rate of fire (`1.0 / attack_cooldown`, e.g., `1.43 APS` on `TestUnit`, `2.0 APS` on `Recon Scout`). *Higher = faster.*
* **`DPS` (Damage Per Second):** `attack_damage / attack_cooldown` (`~28.6 DPS` on `TestUnit`, `24.0 DPS` on `Recon Scout`).
* **`windup_time` / `damage_point` (`s`) [M1]:** Delay from starting an attack animation until the damage/projectile actually fires (e.g., `0.10 s`). Short windup = snappy stutter-stepping.
* **`backswing_time` (`s`) [M1]:** Post-fire recovery animation that a player can cancel by issuing a Move command (enables SC2-style kiting/stutter-stepping without bypassing `attack_cooldown`).
* **`can_move_and_shoot` (`bool`) [M1]:** Whether the unit fires on the move or must stop to fire.

### C. Range & Targeting
| Term / Field | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `attack_range` | `float` (`px`) | **[Live]** | Max **edge-to-edge** distance to fire (`distance - attacker_radius - target_radius <= attack_range`; `180 px` TestUnit, `155 px` Scout). |
| `aggro_range` | `float` (`px`) | **[Live]** | Edge-to-edge auto-acquisition radius during `ATTACK_MOVING` (`280 px` TestUnit, `250 px` Scout). |
| `min_range` | `float` (`px`) | [M1] | Minimum firing distance (for artillery/siege units; `0` for normal units). |
| `delivery_type` | `enum` | [M1] | Currently `HITSCAN` with `AttackTracer`; M1 adds `PROJECTILE_HOMING`, `PROJECTILE_SKILLSHOT`, and `MELEE`. |
| `projectile_speed` | `float` (`px/s`) | [M1] | Travel speed if using a projectile scene. |

---

## 4. Unit State Machine, Commands, Subgroups & Active Abilities

### Standard RTS Command Vocabulary
| Command | Input | Status | Behavior |
| :--- | :--- | :--- | :--- |
| **Move** | `RMB` on ground | **[Live]** | Distributes concentric ring offsets on the navmesh; units navigate ignoring enemies and settle cleanly into `IDLE`. |
| **Attack Target (Focus Fire)** | `RMB` on enemy (or `A` over enemy) | **[Live]** | Pursues specific target into `attack_range` and fires until destroyed, then returns to `IDLE`. |
| **Attack-Move (`A-Move`)** | `A` at cursor (Smart-Cast) | **[Live]** | Immediate cursor-targeted Attack-Move (no left-click needed); engages enemies entering `aggro_range` and resumes to destination once clear. |
| **Hold Position** | `H` | **[Live]** | Locks position (`velocity = ZERO`); fires strictly at enemies inside `attack_range` without stepping forward. |
| **Stop** | `S` | **[Live]** | Immediately cancels active movement, target, or pending ability cast and returns to `IDLE`. |
| **Cycle Subgroup** | `Tab` (`ui_cycle_subgroup`) | **[Live]** | Cycles `active_subgroup_index` across mixed selected unit types (`unit_type_id`), updating `SelectionHUD` and Command Card abilities. |
| **Cast Ability** | `Q` (`cmd_ability_q`) or Command Card click | **[Live]** | Casts active subgroup's `Q` ability via the closest ready unit (`INSTANT` fires immediately; `POINT_AOE`/`UNIT_TARGET` shows range/AoE reticle until `LMB` confirms or `RMB`/`Esc` cancels). |
| **Control Groups** | `Ctrl/Shift/Alt + 1–9`, `1–9` | **[Live]** | Assign (`Ctrl`), append (`Shift`), remove (`Alt`), recall (`1–9` with dead-unit pruning), and double-tap to center `RTSCamera`. |
| **Patrol** | `P` + `LMB` | [M1] | Loop between origin and target waypoint, engaging enemies in `aggro_range` along the way. |

### Unit State Machine (`Unit.CommandState` — Live)
`IDLE` · `MOVING` · `ATTACK_MOVING` · `ATTACKING_TARGET` · `HOLD_POSITION` · `CASTING_ABILITY`
*(Planned M1 additions: `PATROLLING`, `GATHERING`, `CONSTRUCTING`)*

### Active Ability Schema (`AbilityData` Resource — **[Live]**)
Defined in `scripts/data/ability_data.gd` and executed by `scripts/units/ability_component.gd` (live assets: `resources/abilities/overcharge_pulse.tres`, `resources/abilities/nanite_surge.tres`):

| Field Name | Type | Status | Meaning |
| :--- | :--- | :--- | :--- |
| `ability_id` | `StringName` | **[Live]** | Unique identifier (e.g., `&"overcharge_pulse"`, `&"nanite_surge"`). |
| `display_name` | `String` | **[Live]** | Name displayed on Command Card buttons. |
| `hotkey_label` | `String` | **[Live]** | Bound hotkey label (e.g., `"Q"`). |
| `target_type` | `AbilityData.TargetType` | **[Live]** | `POINT_AOE` (ground AoE circle), `UNIT_TARGET` (enemy unit target), or `INSTANT` (immediate self/caster trigger). |
| `cast_range` | `float` (`px`) | **[Live]** | Max distance before casting; out-of-range orders walk into range (`CASTING_ABILITY`) and execute on arrival. |
| `cooldown_duration` | `float` (`s`) | **[Live]** | Per-unit cooldown tracked in `AbilityComponent.cooldowns`, emitting `ability_cooldown_updated` for `SelectionHUD`. |
| `damage_or_value` | `float` | **[Live]** | Primary magnitude (AoE/target damage for offensive abilities, heal amount for `INSTANT` self-repair). |
| `aoe_radius` | `float` (`px`) | **[Live]** | Blast or pulse radius in world pixels (also previewed by `AbilityTargetingReticle`). |
| `description` | `String` | **[Live]** | Tooltip description shown on the Command Card button. |
| `cast_time` / `cost` | `float` / `Dictionary` | [M1] | Optional windup channel duration or energy/resource cost per cast. |

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
