# Project Reference Doc: Technozen / Y2K RTS (Working Title)

## 1. High-Level Vision & Core Pillars
* **Genre:** Desktop Real-Time Strategy (RTS)
* **Design Philosophy:** A deliberate middle ground between **StarCraft 2** (responsive unit micro, active abilities, scouting, tactical adaptation) and **Command & Conquer** (streamlined base macro so players check home frequently without drowning in worker micromanagement).
* **Core Pillars:**
  1. **Tactile Responsiveness:** Snappy unit acceleration, turning, pathfinding, and manual skill-shot/targeted abilities.
  2. **Streamlined Macro:** Meaningful economic choices and expansion pressure without excessive worker babysitting.
  3. **Forced Map Control:** Contested central objectives and an encroaching battle-royale-style hazard zone eliminate turtle/stalling strategies.

---

## 2. Setting, Aesthetics & Lore
* **Premise:** Distant future where AI has become ubiquitous and quietly governs human society. Five asymmetrical factions fight on behalf of five competing **AI Lords**.
* **Visual & Audio Direction:** **Technozen + Y2K Futurism**—glossy, clean, optimistic surfaces, translucent UI elements, serene ambient undertones, and sleek geometry on the outside, contrasted by unit dialogue, barks, and lore hints revealing dystopian control, hidden societal pressures, and algorithmic manipulation beneath the surface.
* **Perspective:** Top-down **2.5D Isometric** (inspired by *Command & Conquer: Red Alert 2* / *Tiberian Sun*) for crisp silhouette readability and manageable solo-dev 2D asset pipelines.

---

## 3. Core Gameplay Loop & Victory Conditions
* **Win Condition:** Destroy all enemy base structures or force the opponent to resign.
* **Anti-Stall Mechanic (Encroaching Zone):** A phased hazard boundary slowly shrinks inward from the map edges over match duration, compressing playable space and forcing decisive engagements.
* **Central Map Objectives (Data Hyper-Uplinks):** Contested capture points near the middle of maps (1 or multiple depending on map layout). Holding a Data Hyper-Uplink grants a **+5% global resource production bonus** while controlled, rewarding early aggression and map presence.

---

## 4. Economy & Resource Model
Three distinct resources plus a population cap, each tied to a different gathering mechanic and unit-tree emphasis:

| Resource / Stat | Gathering Mechanic | Strategic & Unit-Tree Role |
| :--- | :--- | :--- |
| **Biomass** | **Direct Worker Harvest** (No refinery/facility required; fast early gathering) | Primarily fuels **biological / human-augment units**, infantry, and early-game expansion. |
| **Silica** | **Automated Harvesters** (C&C-style autonomous crawlers shuttling deposits to a Refinery) | Primarily fuels **mechanical / hardware units**, vehicles, and defenses; creates vulnerable supply lines to raid/protect. |
| **Compute** | **Worker + Dedicated Facility** (Workers must staff specialized nodes/facilities built over rare vents) | High-value late-game bottleneck required for **top-tier units, AI protocols, and endgame upgrades**. |
| **Bandwidth** | **Population Cap** (Increased via infrastructure/relays) | Governs maximum active army size coordinated by your AI benefactor. |

---

## 5. Controls, Combat & Micro Mechanics
* **Core RTS Controls:** Box-select, control groups (`1–9`), minimap navigation, right-click context actions.
* **Command Set (Locked In):**
  * **Move / Attack-Move**
  * **Patrol:** Units loop between waypoints and automatically engage enemies entering aggro range.
  * **Hold Position:** Units remain stationary and attack enemies within weapon range without chasing.
* **Active Unit Abilities (SC2-Style):** Key units feature **player-activated, manually targeted abilities** (with occasional passive traits strictly for unit flavor).
* **Explicit Non-Goal (Out of Scope):** Automated formation splitting or auto-spread algorithms—unit positioning and splitting remain purely manual player skill.

---

## 6. Tech Stack & Development Workflow
* **Target Platform:** Desktop (PC)
* **Engine:** **Godot 4.7** (`Forward Plus`, strictly typed GDScript, `NavigationServer2D`, Node/Signal architecture, 2D lighting/shaders, and plain-text `.tscn`/`.tres`/`.gd` files for clean Git diffs).
* **Repository & Project Layout (Flattened Root):**
  * Godot project root (`project.godot`) lives directly at the repository root alongside `docs/`.
  * By-type top-level folder layout with feature subfolders:
    * `scenes/` (`test/`, `units/`, `maps/`, `buildings/`, `world/`)
    * `scripts/` (`camera/`, `controllers/`, `units/`, `buildings/`, `systems/`, `data/`)
    * `resources/` (`units/`, `abilities/`, `buildings/`, `themes/`) — data-driven `.tres` configs (`UnitData`, `AbilityData`, future `BuildingData`)
    * `ui/` (`hud/`, `overlays/`)
    * `assets/` (`sprites/`, `audio/`, `shaders/`)
* **IDE & AI Pipeline:**
  * **VS Code** configured as Godot's external editor.
  * **Gemini Notebook** for living GDD, balance tables, and lore/design specs.
  * **GitHub + `agy` CLI** inside VS Code for multi-file scaffolding, diff reviews (`/diff`), and version-controlled milestones.
  * See `docs/technical_glossary_and_specs.md` for shared engine/RTS stat terminology and data schemas.

---

## 7. Milestones & Scope Boundaries

### Milestone 0: Technical Spike & Combat Micro Sandbox — *Completed*
* **M0 Base Spike (`res://scenes/test/milestone_0_test.tscn`):**
  * Godot 4.7.2 project flattened to the repository root with clean starter folder hierarchy, named physics layers (`Layer 1: World`, `Layer 2: Units`), and `run/main_scene` configured.
  * **RTS Camera (`RTSCamera`):** Arrow-key pan (`camera_pan_*`), 1:1 middle-mouse drag pan, clamped smooth scroll-wheel zoom (`0.5`–`2.0`), bounds clamping, and `center_on()` for double-tap control-group centering.
  * **Navigation Arena (`NavigationRegion2D`):** `1280×720` walkable arena with a central `StaticBody2D` obstacle cutout, pre-baked into 4 convex polygons (`agent_radius = 20px`) with `CORRIDORFUNNEL` pathfinding.
* **M0.5 Combat, Target Dummies & Core Commands:**
  * **Team Ownership & Combat (`Unit` + `UnitData`):** `Team.PLAYER` vs `Team.ENEMY`, edge-to-edge weapon range/aggro checks, attack cooldowns, hit-flash, `AttackTracer` VFX, health bars, and safe freed-target cleanup.
  * **Command State Machine:** `IDLE`, `MOVING`, `ATTACK_MOVING`, `ATTACKING_TARGET`, `HOLD_POSITION`, `CASTING_ABILITY` with `RMB` Move/Focus Fire, `S` Stop, `H` Hold Position, and distinct cyan/red `MoveMarker` pulses.
  * **Sandbox Spawner & Debug Panel (`SandboxSpawner`, `SandboxDebugPanel`):** On-demand spawning of `TestUnit` (`F1`/`F2`), `Recon Scout` (`F5`), and stationary `TargetDummy` (`F3`/`F4`), plus `Del` clear dummies and `R` reset.
* **M0.6 Collision, Individual Pathing, Control Groups & Smart-Cast `A`:**
  * **Unit-to-Unit Collision & RVO Avoidance:** `NavigationAgent2D` RVO (`velocity_computed`) on player units, `NavigationObstacle2D` + tangential steering around stationary dummies, soft overlap separation, navmesh-projected concentric ring group destinations (`2.6×` radius spacing), and progress-based arrival settling without jitter.
  * **Control Groups (`1–9`):** `Ctrl+N` assign, `Shift+N` duplicate-free append, `Alt+N` subset remove, plain `N` recall (with automatic dead-unit pruning), and double-tap `N` camera centering.
  * **Smart-Cast Attack-Move (`A`):** Immediately Attack-Moves toward cursor (with ring spread) or focus-fires an enemy under cursor without a secondary left-click.
* **Plan 03 Abilities, Cooldowns, Subgroup `Tab` Cycling & Selection HUD:**
  * **Data-Driven Abilities (`AbilityData`, `AbilityComponent`, `AbilityEffect`, `AbilityTargetingReticle`):** Supports `POINT_AOE`, `UNIT_TARGET`, and `INSTANT` abilities with per-unit cooldowns, walk-into-range casting, and interrupt cancellation. Live test abilities: `Overcharge Pulse` (`Q`, `6.0s` AoE burst on `TestUnit`) and `Nanite Surge` (`Q`, `4.0s` instant heal on `Recon Scout`).
  * **Mixed-Unit Subgroup `Tab` Cycling (`SubgroupHelper` + `SelectionController`):** Deterministic grouping by `unit_type_id`, `Tab` (`ui_cycle_subgroup`) cycling, and smart-cast `Q` targeting (closest ready unit in active subgroup; `Esc`/RMB cancels cleanly).
  * **Signal-Driven Bottom HUD (`SelectionHUD`):** Strictly signal-driven (no `_process()` polling) 3-panel Technozen bar displaying active subgroup portrait/stats, clickable subgroup tabs & unit HP badges, and a Command Card with live ability cooldown countdowns.
* **Remaining Dev-Environment Step (Optional/Local):** Verify VS Code external editor integration and commit baseline to GitHub.

### Milestone 1: Vertical Slice (Design Validation Prototype)
* **Factions:** 1 playable faction (mirrored 1v1 against a basic scripted AI opponent on 1 symmetric map).
* **Units (4 Core Types):**
  1. *Worker* (gathers Biomass, constructs buildings, staffs Compute facilities)
  2. *Automated Harvester* (shuttles Silica to Refinery)
  3. *Basic Biological/Infantry Unit* (costs primarily Biomass; includes 1 manual targeted ability)
  4. *Core Mechanical Vehicle* (costs primarily Silica; counters infantry/structures)
* **Buildings (3–4 Core Structures):** Command Core (HQ), Barracks/Bio-Lab, Silica Refinery, Compute Node.
* **Map Mechanics:** 1 central **Data Hyper-Uplink** (+5% production) + working **phased encroaching zone** timer.
* **Controls:** Box-select, control groups, Move, Attack-Move, Patrol, Hold Position, and manual ability targeting.

### Explicit Cut List (Post-Vertical Slice)
* Factions 2 through 5 and asymmetrical tech trees
* Campaign mode, matchmaking/multiplayer netcode, and replay system
* Automated unit formations/splitting
* Final polished art, voice acting, and custom shaders (use greybox shapes + placeholder Nano Banana / Lyria assets during Milestone 1)