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
* **Engine:** **Godot 4** (leveraging `NavigationServer2D`, Node/Signal architecture, 2D lighting/shaders, and plain-text `.tscn`/`.tres`/script files for clean Git diffs).
* **IDE & AI Pipeline:**
  * **VS Code** configured as Godot's external editor.
  * **Gemini Notebook** for living GDD, balance tables, and lore/design specs.
  * **GitHub + `agy` CLI** inside VS Code for multi-file scaffolding, diff reviews (`/diff`), and version-controlled milestones.

---

## 7. Milestones & Scope Boundaries

### Milestone 0: Technical Spike (Dev Setup)
* Install Godot 4, configure VS Code external editor integration, initialize GitHub repo with `docs/GDD.md`, and verify a basic test scene runs with box-selection and click-to-move on a `NavigationRegion2D`.

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