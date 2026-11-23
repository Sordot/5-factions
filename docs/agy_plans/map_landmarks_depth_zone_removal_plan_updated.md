# Milestone 1.7 Plan: Map Landmarks, Tactical Depth & Circle/Zone Mechanic Removal

**Target Directory:** `docs/agy_plans/15_map_landmarks_depth_and_zone_removal.md`
**Primary Scene:** `res://scenes/maps/skirmish_arena_01.tscn`
**Reference Docs:** `docs/agy_plans/genesis_v2_vertical_slice_completion_bundle.md`, `docs/agy_plans/rts_micro_shortcuts_settings_menu_plan.md`, `docs/agy_plans/16_fullscreen_scaling_and_technical_cleanup.md`

## 1. Objective & Scope

Refine `skirmish_arena_01.tscn` into a richer, more readable symmetric 1v1 tactical arena by **completely removing the active encroaching circle/zone mechanic (`EncroachingZone`)** and adding **named Technozen/Y2K landmarks, natural/side resource expansions, choke points, and flanking corridors**.

With `GENESIS_V2`, `EntityVisuals`, `AudioManager`, `Patrol (P)`, `Camera Bookmarks (Ctrl+F1–F4)`, and `Last Alert Jump (Space)` now in place, removing the shrinking circle lets territory control, forward expansions, flanking lanes, and the central **Data Hyper-Uplink** naturally drive match pacing.

### In Scope

1. **Clean Removal of the Encroaching Circle / Zone Mechanic:**
   * Remove the `EncroachingZone` node and any connected signals from `scenes/maps/skirmish_arena_01.tscn`.
   * Strip active zone countdowns, phase timers, zone-damage ticks, and zone-retreat checks from:
     * `scripts/systems/match_manager.gd`
     * `ui/hud/resource_hud.gd` & `ui/hud/resource_hud.tscn`
     * `ui/hud/minimap.gd`
     * `ui/hud/sandbox_debug_panel.gd` & `ui/hud/sandbox_debug_panel.tscn`
     * `scripts/systems/skirmish_ai.gd`
   * Keep `scripts/systems/encroaching_zone.gd` safely unused in the repository (do not delete) in case a revised sudden-death mode is revisited later, while ensuring **zero** null-reference errors or debugger warnings during live play.

2. **Symmetric Multi-Tier Arena Layout (`scenes/maps/skirmish_arena_01.tscn`):**
   * **Main Bases — *Alpha Vat Basin* (Player BL) & *Omega Vat Basin* (Enemy TR):**
     * Starting `Nexus Vat`, safe starter `BiomassNode` cluster, `SilicaVein`, and a base `ComputeVent`.
     * Framed by clean terrain barriers with two generous exits (`>= 110px` clearance) so `Workers`, `Harvesters`, and `Goliath Frames` never bottleneck or snag.
   * **Natural / Side Expansion Pockets — *Cryo-Silica Terrace* (NW) & *Synapse Relay Yard* (SE):**
     * Exposed secondary resource clusters with extra **BiomassNodes**, **SilicaVeins**, and a contested **ComputeVent**.
     * Rewards expanding forward with **Silica Condensers**, **Wetware Mainframes**, and **Synapse Pylons** (and makes `Camera Bookmarks F1–F4` and `Last Alert Jump (Space)` immediately valuable for defending outposts).
   * **Central Contest Core — *Hyper-Uplink Plaza* `(0, 0)`:**
     * Keep the **Data Hyper-Uplink** as the primary central map objective, framed by 4 symmetrical angled Technozen cover pylons that create tactical sightlines and choke points for **Arc-Lancers**, **Goliath Frames**, **Signal Jammers**, and **Chrysalis Mortars**.
   * **Outer Flanking Corridors — *North Conduit* & *South Relay Trench*:**
     * Dedicated perimeter lanes bypassing the center plaza, ideal for `Shift + Right-Click` flanking routes, `Patrol (P)` perimeter guards, and **Stinger** economy raids.

3. **Technozen / Y2K Visual Landmarks (`scripts/world/map_landmark.gd` + `scenes/world/map_landmark.tscn`):**
   * Build a reusable `MapLandmark` node matching the crisp translucent-white/chrome + bioluminescent vector aesthetic established in `ui/overlays/entity_visuals.gd`.
   * Support `@export` customization so names and styles can be tweaked anytime in the Godot Inspector:
     * `landmark_name: String`
     * `visual_style: int` (`0 = Monolith Spire`, `1 = Relay Arch`, `2 = Capacitor Pylon`, `3 = Plaza Beacon`)
     * `accent_color: Color`
     * `has_collision: bool = true`
     * `show_on_minimap: bool = true`
   * Draw clean diegetic ground markings / subtle region labels that remain crisp under the `1280×720` `canvas_items` + `expand` viewport scaling.
   * Automatically register `MapLandmark` collision footprints (`has_collision == true`) with `scripts/world/arena_nav_region.gd` so `NavigationAgent2D` routes units and workers cleanly around every landmark.

4. **Skirmish AI Expansion & Objective Awareness (`scripts/systems/skirmish_ai.gd`):**
   * Remove any leftover `EncroachingZone` avoidance/retreat checks.
   * Teach `SkirmishAICommander` to recognize the NW/SE expansion nodes (`BiomassNode`, `SilicaVein`, `ComputeVent`) when starter resources saturate or deplete, and dispatch **Stinger** / **Clone Trooper** squads to contest **Hyper-Uplink Plaza** and patrol flank approaches.

5. **Minimap Clarity & Readability Pass (`ui/hud/minimap.gd`):**
   * Remove the shrinking zone circle overlay.
   * Render clean, distinct minimap markers compatible with Fog of War and `1280×720` / fullscreen scaling:
     * **Data Hyper-Uplink:** Pulsing central diamond colored by current owner (`Neutral` / `Player` / `Enemy`).
     * **Named Landmarks:** Subtle geometric Y2K pips (`show_on_minimap == true`).
     * **Resource Nodes:** Emerald (`Biomass`), Amber/Gold (`Silica`), Violet/Cyan (`ComputeVent`).
     * **Friendly & Enemy Entities:** Clear size hierarchy between command hubs (`Nexus Vat`), production buildings, and mobile units.

### Out of Scope
* New playable factions, units, or upgrades beyond `GENESIS_V2`.
* Additional selectable maps in `MainMenu` (keep `MainMenu` focused on `Skirmish Arena 01` and `Sandbox Testbed`).
* Re-introducing any shrinking-circle or sudden-death zone mechanic.

---

## 2. Landmark & Region Blueprint (`skirmish_arena_01.tscn`)

*(All landmark names are exported strings on `MapLandmark` nodes and can be adjusted anytime.)*

| Region / Landmark Name | Arena Position | Visual Style | Tactical Role & Features |
| :--- | :--- | :--- | :--- |
| **Alpha Vat Basin** *(Player Main)* | Bottom-Left | Plaza Beacon | Starting `Nexus Vat`, safe `Biomass` + `Silica` + `ComputeVent`, two wide exits (Main Lane & South Trench). |
| **Omega Vat Basin** *(Enemy Main)* | Top-Right | Plaza Beacon | Symmetric mirror of Alpha Vat Basin for `Team.ENEMY`. |
| **Hyper-Uplink Plaza** *(Center)* | Center `(0, 0)` | 4× Capacitor Pylons | Houses the **Data Hyper-Uplink**; angled barrier pylons create clean attack/defense angles for heavy units and mortars. |
| **Cryo-Silica Terrace** *(NW Expansion)* | Top-Left Quadrant | Monolith Spire | Exposed natural expansion with `SilicaVeins`, `BiomassNodes`, and a contested `ComputeVent`. |
| **Synapse Relay Yard** *(SE Expansion)* | Bottom-Right Quadrant | Monolith Spire | Symmetric counterpart to Cryo-Silica Terrace with high-value expansion nodes. |
| **North Conduit** *(Upper Flank)* | Top Edge Corridor | Relay Arch | Scenic perimeter lane linking NW Expansion to Enemy Main—built for **Stinger** raids and `Shift + Right-Click` flanks. |
| **South Relay Trench** *(Lower Flank)* | Bottom Edge Corridor | Relay Arch | Symmetric lower flank corridor linking Player Main to SE Expansion. |

---

## 3. File & Architecture Plan

### New Files to Create
* **`scripts/world/map_landmark.gd` & `scenes/world/map_landmark.tscn`**
  * Reusable `Node2D` landmark prop with optional `StaticBody2D` collider (added to the nav-obstacle group consumed by `arena_nav_region.gd`), procedural Technozen `_draw()` geometry matching `entity_visuals.gd`, subtle diegetic region nameplate, and minimap registration metadata.

### Existing Files to Extend
* **`scenes/maps/skirmish_arena_01.tscn`**
  * Remove `EncroachingZone` node and references.
  * Lay out the symmetric Main Bases, **Cryo-Silica Terrace (NW)**, **Synapse Relay Yard (SE)**, **Hyper-Uplink Plaza**, **North Conduit**, and **South Relay Trench** with generous `>= 110px` navigation clearances between obstacles.
* **`scripts/systems/match_manager.gd`**
  * Remove `EncroachingZone` references, timer ticks, and zone-damage hooks; keep **Data Hyper-Uplink** and **Command Hub (`Nexus Vat`) Destruction** cleanly driving match state and alerts (`jump_last_alert`).
* **`ui/hud/resource_hud.gd` & `ui/hud/resource_hud.tscn`**
  * Remove the Encroaching Zone countdown/phase badge while keeping the **Data Hyper-Uplink** status indicator, Idle Worker button, and Audio Mute toggle cleanly aligned in windowed and fullscreen modes.
* **`ui/hud/sandbox_debug_panel.gd` & `ui/hud/sandbox_debug_panel.tscn`**
  * Remove any zone phase/radius debug controls (preserving Aggro AI toggle and `GENESIS_V2` unit/building spawners).
* **`ui/hud/minimap.gd`**
  * Remove zone-ring rendering; add clean `MapLandmark` pips, enhanced `HyperUplink` status diamond, and color-coded resource nodes.
* **`scripts/world/arena_nav_region.gd`**
  * Include `MapLandmark` colliders (`has_collision == true`) alongside `TerrainObstacle` and dynamic `Building` footprints when baking the navigation polygon.
* **`scripts/systems/skirmish_ai.gd`**
  * Remove zone checks; support expanding economy/harvesters to NW/SE resource clusters and contesting **Hyper-Uplink Plaza** / flank approaches.

---

## 4. Verification Checklist for `agy`

Before concluding Milestone 1.7, verify in `scenes/maps/skirmish_arena_01.tscn` (both Windowed `1280×720` and Fullscreen `F11`):

* [ ] **Zero Zone / Circle Leftovers:** Run a skirmish for several minutes; confirm no shrinking circle renders on the map or minimap, no zone timer appears in `ResourceHUD` or `SandboxDebugPanel`, and zero errors/warnings appear in the Godot Debugger.
* [ ] **Distinct Landmarks & Visual Cohesion:** Pan across **Hyper-Uplink Plaza**, **Cryo-Silica Terrace (NW)**, **Synapse Relay Yard (SE)**, **North Conduit**, and **South Relay Trench**; confirm each landmark matches the Technozen/Y2K visual style, displays readable ground labels, and shows up cleanly on `Minimap`.
* [ ] **Smooth Pathing & Micro Synergy:** Send `Workers`, `Harvesters`, and mixed squads (`Clone Troopers`, `Stingers`, `Goliath Frames`, `Arc-Lancers`) through both flank corridors and around landmark colliders using `Shift + Right-Click` and `Patrol (P)`; verify zero snagging or stuck units.
* [ ] **Expansion & Alert Loop:** Build a forward **Silica Condenser** and **Wetware Mainframe** at the NW or SE expansion pocket; confirm local `Harvesters` and `Engineers` operate locally, and verify `Space` (`Last Alert Jump`) snaps cleanly to the expansion when attacked or completed.
* [ ] **AI Compatibility:** With `Aggro AI: ON`, confirm `SkirmishAICommander` gathers, builds, contests **Hyper-Uplink Plaza**, and expands cleanly without errors.