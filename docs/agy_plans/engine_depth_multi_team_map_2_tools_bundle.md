# Milestone 2.2 Plan: Multi-Team Foundation, Destructible Barricades, Skirmish Arena 02, Building Lifecycle & Balance Tools

**Target Directory:** `docs/agy_plans/23_engine_depth_multiteam_and_tools_bundle.md`
**Primary Files:** `project.godot`, `scripts/systems/team_manager.gd` *(new)*, `scripts/world/destructible_barricade.gd` *(new)*, `scenes/maps/skirmish_arena_02.tscn` *(new)*, `scripts/units/repair_component.gd` *(new)*, `scenes/ui/tech_tree_overlay.tscn` *(new)*, `scripts/systems/game_config.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/economy_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/buildings/building.gd`, `scripts/units/unit.gd`, `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`, `scenes/ui/main_menu.tscn`, `ui/hud/resource_hud.tscn`, `ui/hud/selection_hud.gd`
**Reference Docs:** `docs/agy_plans/micro_feel_unit_rally_minimap_pings_veterancy_plan.md`, `docs/agy_plans/macro_hud_scoreboard_main_menu_polish_plan.md`, `docs/agy_plans/map_landmarks_depth_zone_removal_plan_updated.md`, `docs/agy_plans/keybinds_mouse_buttons_settings_polish_plan.md`

## 1. Objective & Scope

Strengthen the core RTS engine and testing workflow before introducing Faction #2 (`AETHER_PRIME` / `IRON_CONSENSUS` / etc.). This pass establishes a **multi-team / FFA architecture**, adds **Destructible Barricades** and a **second skirmish map**, completes **building lifecycle & army micro QoL** (Cancel/Salvage, Worker/Engineer Repair, Select All Army), and adds **player clarity & balance testing tools** (In-Game Tech Tree Overlay, Game Speed Controls, and AI-vs-AI Spectator Mode).

### In Scope

1. **Multi-Team, Faction & FFA Foundation (`TeamManager` Autoload):**
   * Replace hardcoded binary `PLAYER` vs `ENEMY` assumptions with a centralized `TeamManager` autoload supporting up to 4 active team slots (`0..3`) plus `NEUTRAL` (`-1`), alliance groups (supporting `1v1`, `2v2`, `FFA`, and `AI vs AI`), per-team faction IDs (`&"genesis_v2"`), per-team color palettes, and AI/Human control flags—while keeping `Team 0` (Player/Slot 0) and `Team 1` (Enemy/Slot 1) 100% backward-compatible with existing scenes.
2. **Destructible Barricades & Second Skirmish Map (`skirmish_arena_02.tscn`):**
   * Create a reusable `DestructibleBarricade` world obstacle (`StaticBody2D` integrated with `arena_nav_region.gd`) that blocks movement until destroyed, displays progressive structural damage states, rewards anti-armor/siege firepower, and dynamically rebakes the navmesh to open new flank routes or hidden resource pockets when breached.
   * Build `scenes/maps/skirmish_arena_02.tscn` (**Twin Causeway**), a distinct symmetric layout featuring a tighter central bridge/choke around the **Data Hyper-Uplink** and destructible-barricade-sealed flank bypasses and rich side pockets, selectable from `MainMenu`.
3. **Building Lifecycle & Army Micro QoL (Excluding Role-Sorted Formations):**
   * **Cancel Construction (75% Refund) & Salvage/Decommission (50% Refund):** Cancel unfinished scaffolds immediately for 75% resource return; trigger a cancelable `4.0s` Salvage/Decommission on completed buildings for 50% return.
   * **Worker & Engineer Repair (`scripts/units/repair_component.gd`):** Workers repair damaged friendly buildings; Engineers repair damaged friendly heavy synthetic units (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`, `Lance-Rig`, `Signal Jammer`) and buildings at a small Biomass/Silica trickle with Technozen nanite-beam VFX.
   * **Select All Army Hotkey (`cmd_select_all_army`):** Rebindable hotkey (default `F9`, compatible with Mouse 3/4/5) plus a compact clickable Army Count badge in `ResourceHUD` that selects all living friendly combat units (excluding Workers, Harvesters, and Engineers).
4. **Testing, Balance & Player Clarity Tools:**
   * **In-Game Tech Tree Overlay (`scenes/ui/tech_tree_overlay.tscn`):** Clean Technozen modal accessible from `ResourceHUD`, `PauseMenu`, and a rebindable hotkey (`U`), showing `GENESIS_V2` building prerequisites, trainable units, armor/counter tags, and upgrades—highlighting live unlocked/researched state mid-match.
   * **Game Speed Controls (`0.5x / 1x / 1.5x / 2x`):** Compact HUD speed selector (and `[` / `]` hotkeys) adjusting `Engine.time_scale` cleanly and resetting safely to `1.0x` on pause, match end, or return to `MainMenu`.
   * **AI-vs-AI Spectator Mode:** Lobby toggle in `MainMenu` allowing two `SkirmishAICommander` instances (`Team 0` vs `Team 1`, each with configurable Difficulty and Playstyle) to play out full matches while the user observes freely with camera panning, entity inspection, speed controls, and a Fog-of-War visibility toggle.

### Out of Scope
* Role-sorted squad formations.
* Capturable Sensor Relays.
* Playable rosters for Factions #2–#5.

---

## 2. Phase A: Multi-Team, Faction & FFA Foundation (`TeamManager`)

### A.1 `scripts/systems/team_manager.gd` (Autoload in `project.godot`)
Register `TeamManager` as an autoload before `EconomyManager`, `UpgradeManager`, and `MatchManager`:
* **Slot Metadata (`team_configs: Dictionary`):** Each active slot (`0..3`) stores:
  * `team_id: int` (`0`, `1`, `2`, `3`; `-1` reserved for `NEUTRAL`)
  * `alliance_id: int` (teams sharing an `alliance_id` are allies; distinct `alliance_id`s are enemies—enabling `1v1`, `2v2`, and `3–4 player FFA` without code changes)
  * `faction_id: StringName` (default `&"genesis_v2"`)
  * `controller_type: int` (`HUMAN = 0`, `AI = 1`, `NEUTRAL = 2`)
  * `display_name: String` (e.g., `"PLAYER // GENESIS_V2"`, `"AI-01 // GENESIS_V2"`, `"AI-02 // GENESIS_V2"`)
  * `primary_color: Color` & `accent_color: Color` (Team 0: Cyan/Emerald, Team 1: Crimson/Amber, Team 2: Violet/Magenta, Team 3: Solar Gold)
* **Core Query Helpers:**
  * `are_allies(team_a: int, team_b: int) -> bool` (returns `true` if `team_a == team_b` or both have matching `alliance_id >= 0`)
  * `are_enemies(team_a: int, team_b: int) -> bool` (returns `true` if both are valid active teams with different `alliance_id`s; `NEUTRAL` is never auto-enemy unless explicitly attack-targeted like a `DestructibleBarricade`)
  * `get_local_human_team() -> int` (returns `0` in standard play, or `-1` in `AI vs AI Spectator` mode)
  * `is_spectator_mode() -> bool`
  * `get_active_teams() -> Array[int]`
  * `get_team_color(team_id: int) -> Color` & `get_team_accent(team_id: int) -> Color`
  * `configure_match(mode: StringName, slot_configs: Array[Dictionary]) -> void`

### A.2 Refactoring Binary Team Checks Across Systems
Update existing systems to query `TeamManager` instead of assuming only `0` vs `1`:
* **`combat_component.gd`, `ability_component.gd`, `heal_aura_component.gd`:** Use `TeamManager.are_enemies(owner_unit.team, target.team)` and `TeamManager.are_allies(...)` for target acquisition, AoE splash damage, `Static Pulse`, `Seismic Slam`, and `Symbiote` heal aura.
* **`economy_manager.gd` & `upgrade_manager.gd`:** Dynamically initialize resource ledgers and upgrade sets for all `TeamManager.get_active_teams()` (instead of only `0` and `1`).
* **`match_manager.gd`:** Track telemetry and defeat/elimination per active team; end the match when only **one `alliance_id`** retains a living command hub (`Nexus Vat`) or achieves **Data Hyper-Uplink** mastery.
* **`skirmish_ai.gd`:** Ensure `SkirmishAICommander` reads its exported/assigned `ai_team: int` cleanly for all queries (workers, buildings, enemy target detection via `TeamManager.are_enemies(ai_team, other.team)`), allowing multiple `SkirmishAICommander` nodes to coexist cleanly in FFA or AI-vs-AI Spectator Mode.
* **`fog_of_war.gd`, `minimap.gd`, `entity_visuals.gd`:** Render team colors via `TeamManager.get_team_color(entity.team)`; in Spectator Mode, reveal all teams' vision (or toggleable full-map reveal).

---

## 3. Phase B: Destructible Barricades & Skirmish Arena 02

### B.1 Destructible Barricades (`scripts/world/destructible_barricade.gd` & `scenes/world/destructible_barricade.tscn`)
* **Node Architecture:** `StaticBody2D` added to groups `"destructible_barricades"` and the navigation obstacle group consumed by `arena_nav_region.gd` (so units route around intact barricades automatically).
* **Exported Properties:**
  * `barricade_name: String = "Reinforced Debris Gate"`
  * `max_hp: float = 650.0` (armored tag: `is_armored = true` so **Lance-Rigs** and **Chrysalis Mortars** breach them significantly faster than unupgraded infantry)
  * `footprint_size: Vector2 = Vector2(120, 44)` & `rotation_degrees`
* **Targeting & Combat Integration:**
  * **Explicit Target Only:** Auto-aggro (`Attack-Move`, `Patrol`, idle) ignores intact neutral barricades so armies never waste fire on rocks during a fight; **explicit Right-Click** (or `Attack-Move` directly onto the barricade) orders units to focus-fire and destroy it.
  * Supports `take_damage(amount: float, attacker: Node = null)` with `0.08s` hit-flash, progressive fracture cracks at `< 66%` and `< 33%` HP, and a procedural rubble/spark burst via `combat_vfx.gd` on destruction.
  * **Dynamic NavMesh Opening:** On destruction, disables collision, removes itself from the nav obstacle group, and immediately calls `arena_nav_region.request_rebake()` so units can immediately path through the newly opened corridor.
  * **Minimap & Inspection:** Renders as a distinct hashed amber/slate block on `Minimap` and is inspectable in `SelectionHUD` (showing HP and `"Destructible Obstacle — Armored"`).

### B.2 Second Skirmish Map (`scenes/maps/skirmish_arena_02.tscn` — *Twin Causeway*)
* **Distinct Tactical Geometry:**
  * **Main Bases (West-South-West & East-North-East):** Safe starter `Biomass`, `Silica`, and `ComputeVent` pockets.
  * **Central Bridge / Causeway (`Data Hyper-Uplink`):** A tighter, dramatic central crossing framed by structural pylons where **Goliath Frames**, **Arc-Lancers**, and **Chrysalis Mortars** create intense choke-point battles.
  * **Barricaded Backdoor Flanks & Rich Side Pockets:** Two outer lanes and two high-yield secondary **Silica / Compute** pockets sealed early-game by **Destructible Barricades**—creating a clear mid-game choice between pushing the central causeway or breaching a flank gate for surprise raids and expansions.
* **Lobby & Navigation Integration:**
  * Add `Twin Causeway (Skirmish Arena 02)` to `GameConfig` map catalog and `MainMenu` map selector dropdown.
  * Verify `arena_nav_region.gd`, `RTSCamera` bounds, `FogOfWar`, `Minimap`, and `SkirmishAICommander` all read the map's dimensions/nodes dynamically with zero hardcoded `skirmish_arena_01` coordinates.

---

## 4. Phase C: Building Lifecycle & Army Micro QoL

### C.1 Cancel Construction & Salvage / Decommission (`building.gd`, `selection_hud.gd`, `command_router.gd`)
* **Cancel Construction (While `not is_constructed`):**
  * Show a `[X] Cancel Build (75% Refund)` button on `SelectionHUD` for selected friendly unfinished buildings.
  * Refund `75%` of `biomass_cost`, `silica_cost`, and `compute_cost` to `EconomyManager`, release any assigned constructing workers cleanly (advancing their command queues), play a crisp cancel SFX, destroy the scaffold, and trigger `arena_nav_region.request_rebake()`.
* **Salvage / Decommission (While `is_constructed`):**
  * Show a `[X] Salvage (50% Refund)` button on `SelectionHUD` for completed friendly buildings (disabled with tooltip `"Cannot salvage last Nexus Vat"` if it is the team's sole remaining command hub).
  * Initiates a `4.0s` decommission countdown (drawn as a pulsing amber progress bar on the building; clicking again cancels the salvage).
  * On completion, refunds `50%` of resource costs, cancels/refunds any queued production items, ejects any staffed **Engineers** safely outside the footprint, frees Bandwidth, spawns a subtle disassembly VFX, and rebakes the navmesh.

### C.2 Worker & Engineer Repair (`scripts/units/repair_component.gd` *(new)*, `unit.gd`, `command_router.gd`, `combat_vfx.gd`)
Keep `unit.gd` lean by isolating repair logic in a dedicated `RepairComponent` (mirroring `GatherComponent` and `StaffComponent`):
* **Repair Eligibility:**
  * **Workers (`worker_unit`):** Can repair any damaged friendly **Building** (`is_constructed == true` and `current_hp < max_hp`).
  * **Engineers (`engineer_unit`):** Can repair damaged friendly **Heavy/Mechanical Synthetic Units** (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar`, `Lance-Rig`, `Signal Jammer`) *and* damaged friendly **Buildings**.
* **Command & Resource Trickle:**
  * Right-clicking a damaged eligible friendly building or synthetic unit with selected Workers/Engineers issues a `REPAIR` order (also supports `Shift`-queuing).
  * Restores `~18 HP/s` (Worker on building) or `~24 HP/s` (Engineer on synthetic/building) while draining a light resource trickle (`~2 Biomass/s` + `~1 Silica/s`, pausing gracefully if resources hit `0`).
  * Renders a crisp cyan/emerald Technozen nanite-welding beam and sparks via `combat_vfx.gd` while actively repairing, and automatically stops + advances `command_queue` once the target reaches `100%` HP.

### C.3 Select All Army Hotkey & HUD Badge (`settings_manager.gd`, `selection_controller.gd`, `resource_hud.gd/.tscn`)
* Register `cmd_select_all_army` in `project.godot` and `SettingsManager.KEYBIND_DEFS` (default **`F9`**, avoiding `F1–F4` bookmarks, `F5–F8` Godot editor, `F10` Aggro AI, and `F11` Fullscreen; fully rebindable including `Mouse 3/4/5`).
* Pressing `cmd_select_all_army` selects all living `TeamManager.get_local_human_team()` combat units (explicitly excluding Workers, Silica Harvesters, and Engineers); double-tapping centers `RTSCamera` on the army's centroid.
* Add a compact clickable **Army Count** badge (`ARMY: 14 [F9]`) beside the existing Idle Worker badge in `ResourceHUD` (hidden in Spectator Mode).

---

## 5. Phase D: Tech Tree Overlay, Game Speed Controls & AI-vs-AI Spectator Mode

### D.1 In-Game Tech Tree Overlay (`scenes/ui/tech_tree_overlay.tscn` & `scripts/ui/tech_tree_overlay.gd`)
* **Access Points:**
  * Compact `TECH [U]` button in `ResourceHUD`, a **Tech Tree** button in `PauseMenu`, and rebindable hotkey `ui_toggle_tech_tree` (default **`U`**).
  * Pressing `Esc` or `U` closes the overlay cleanly without leaking into gameplay commands.
* **Layout & Live Match State (`1280×720` Safe):**
  * Centered Technozen modal displaying `GENESIS_V2`'s clear tier flow:
    * **Tier 0 (Core):** `Nexus Vat` (`Worker`, `Silica Harvester`, `Engineer`) + `Synapse Pylon`, `Silica Condenser`, `Wetware Mainframe`.
    * **Tier 1 (Swarm & Counters):** `Cloning Vat` (`Clone Trooper x2`, `Stinger x2`, `Symbiote x2` + `Batch Efficiency`, `Adrenal Potency`) & `Calibration Foundry` (`Lance-Rig`, `Signal Jammer`).
    * **Tier 2 (Heavy Synthetics — Requires Cloning Vat):** `Synthetics Fabricator` (`Goliath Frame`, `Arc-Lancer`, `Chrysalis Mortar` + `Compute Overdrive`).
  * Shows cost pills, key role/counter tags (`+vs Armored`, `AoE Splash`, `Heal Aura`), and **dynamically highlights** structures the player currently owns and upgrades already researched in emerald/cyan!

### D.2 Game Speed Controls (`ui/hud/resource_hud.tscn/.gd`, `settings_manager.gd`, `match_manager.gd`)
* Add a compact speed selector strip (`0.5x | 1x | 1.5x | 2x`) in `ResourceHUD` plus rebindable `game_speed_down` (`[`) and `game_speed_up` (`]`) shortcuts.
* Applies `Engine.time_scale` to the active simulation (default `1.0x`), while keeping UI interactions snappy and **guaranteeing** `Engine.time_scale = 1.0` on `PauseMenu`, `MatchEndOverlay`, `Restart Skirmish`, and return to `MainMenu`.

### D.3 AI-vs-AI Spectator Mode (`scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`, `scripts/systems/game_config.gd`, `scenes/maps/skirmish_arena_*.tscn`)
* **Lobby Setup (`MainMenu`):**
  * Add a **Match Mode** toggle: `Player vs AI` *(default)* or `AI vs AI (Spectator)`.
  * When `AI vs AI (Spectator)` is selected, show compact **Team 1 AI** and **Team 2 AI** Difficulty + Playstyle selectors so you can pit e.g. `Swarm Rush (Brutal)` vs `Synthetics Tech (Brutal)` against each other.
* **In-Match Spectator Experience:**
  * Both Team `0` and Team `1` spawn with a `SkirmishAICommander` assigned to their respective `team_id`.
  * Local player cannot issue unit/building orders, but retains full camera control (`WASD`/Edge-Pan/Zoom/Bookmarks), entity inspection in `SelectionHUD`, **Game Speed Controls (`0.5x–2x`)**, **Tech Tree Overlay**, and a top-bar **Spectator HUD strip** showing both AIs' live Biomass/Silica/Compute/Bandwidth counts plus a **Toggle Fog of War** button (defaulting to full-map vision revealed).

---

## 6. File & Architecture Summary

### New Files to Create
* `scripts/systems/team_manager.gd` (Autoload for multi-team slots `0..3`, alliances/FFA, faction IDs, colors, and Spectator Mode state)
* `scripts/world/destructible_barricade.gd` & `scenes/world/destructible_barricade.tscn` (Armored destructible corridor/pocket blockers with progressive damage visuals and navmesh rebake on breach)
* `scenes/maps/skirmish_arena_02.tscn` (**Twin Causeway** — central choke bridge + barricade-sealed flank routes and expansion pockets)
* `scripts/units/repair_component.gd` (Modular Worker building-repair & Engineer synthetic/building-repair component with resource trickle)
* `scenes/ui/tech_tree_overlay.tscn` & `scripts/ui/tech_tree_overlay.gd` (Live `GENESIS_V2` interactive tech tree modal)

### Existing Files to Extend
* `project.godot` (Register `TeamManager` autoload; add `cmd_select_all_army`, `ui_toggle_tech_tree`, `game_speed_down`, `game_speed_up` actions)
* `scripts/systems/game_config.gd`, `scripts/systems/economy_manager.gd`, `scripts/systems/upgrade_manager.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/systems/fog_of_war.gd` (Multi-team `TeamManager` integration, Spectator dual-AI spawning, and speed-reset safety)
* `scripts/buildings/building.gd`, `scripts/units/unit.gd`, `scripts/units/combat_component.gd`, `scripts/units/ability_component.gd`, `scripts/units/heal_aura_component.gd`, `scripts/controllers/command_router.gd`, `scripts/controllers/selection_controller.gd` (Cancel/Salvage, Repair routing, explicit barricade targeting, `cmd_select_all_army`, and `TeamManager` alliance queries)
* `ui/overlays/combat_vfx.gd`, `ui/overlays/entity_visuals.gd`, `ui/hud/minimap.gd`, `ui/hud/selection_hud.gd`, `ui/hud/resource_hud.tscn/.gd`, `scripts/ui/pause_menu.gd`, `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`, `scripts/systems/settings_manager.gd`, `scripts/ui/settings_menu.gd` (Repair beam VFX, barricade rubble VFX, Cancel/Salvage buttons, Army Count badge, Tech Tree button, Speed selector, Spectator HUD bar, and Map 2 + Spectator lobby UI)

---

## 7. Verification Checklist for `agy`

Before concluding Milestone 2.2, verify in Godot (Windowed `1280×720` and Fullscreen `F11`):

* [ ] **Multi-Team & FFA Readiness:** Verify `TeamManager` powers team colors, enemy/ally checks, and resource ledgers cleanly with zero regressions in standard `1v1` `Player vs AI` play on both maps.
* [ ] **Destructible Barricades & Skirmish Arena 02:** Launch **Twin Causeway (`skirmish_arena_02.tscn`)** from `MainMenu`; verify units path around intact barricades without auto-shooting them, explicitly right-clicking a barricade destroys it (faster with **Lance-Rigs** / **Chrysalis Mortars**), and units immediately path through the newly opened lane after the navmesh rebake.
* [ ] **Cancel Construction & Salvage:** Start a **Cloning Vat**, click **Cancel Build** and confirm a 75% refund and clean navmesh rebake; click **Salvage** on a completed **Synapse Pylon**, confirm the 4s countdown (and that clicking again cancels it), and verify 50% refund upon completion (while last **Nexus Vat** cannot be salvaged).
* [ ] **Worker & Engineer Repair:** Damage a friendly building and a **Goliath Frame**; right-click the building with a **Worker** and the **Goliath Frame** with an **Engineer**; verify nanite-beam VFX, smooth HP restoration, light Biomass/Silica trickle, and automatic stop at 100% HP.
* [ ] **Select All Army (`F9`):** Press `F9` (or click the HUD Army badge) and verify only combat units are selected (no Workers/Harvesters/Engineers); verify rebinding to `Mouse 4` / `Mouse 5` works cleanly.
* [ ] **Tech Tree Overlay (`U`), Speed Controls & AI-vs-AI Spectator Mode:** Open the **Tech Tree** mid-match and confirm owned buildings/researched upgrades highlight live; test `0.5x / 1x / 1.5x / 2x` speed switching (and confirm `1.0x` restores on Pause/Main Menu); launch an **AI vs AI (Spectator)** match (`Swarm Rush` vs `Synthetics Tech`) at `2x` speed with Fog of War toggled off and verify both AIs gather, expand, fight, and complete a full match with zero Godot Debugger errors.