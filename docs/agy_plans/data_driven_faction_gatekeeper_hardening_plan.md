# Milestone 2.8 Plan: The 3.0 Gatekeeper — Data-Driven Faction Architecture & Engine Hardening

**Target Directory:** `docs/agy_plans/34_faction_data_driven_gatekeeper_and_hardening.md`
**Primary New Files:** `scripts/systems/ai_build_planner.gd`
**Primary Extended Files:** `scripts/data/faction_data.gd`, `scripts/data/unit_data.gd`, `scripts/data/building_data.gd`, `resources/factions/genesis_v2_faction.tres`, `resources/units/*.tres`, `resources/buildings/*.tres`, `scripts/systems/team_manager.gd`, `scripts/systems/match_manager.gd`, `scripts/systems/skirmish_ai.gd`, `scripts/systems/audio_manager.gd`, `scripts/units/combat_component.gd`, `scripts/units/gather_component.gd`, `scripts/units/repair_component.gd`, `scripts/units/unit.gd`, `scripts/buildings/building.gd`, `scripts/controllers/selection_controller.gd`, `scripts/controllers/command_router.gd`, `scripts/ui/main_menu.gd`, `scripts/ui/tech_tree_overlay.gd`, `ui/hud/resource_hud.gd`, `ui/hud/minimap.gd`, `ui/hud/selection_hud.gd`, `ui/hud/tactical_event_feed.gd`, `ui/hud/sandbox_debug_panel.gd`, `ui/overlays/build_ghost_preview.gd`, `ui/overlays/entity_visuals.gd`
**Reference Docs:** `docs/agy_plans/engine_hardening_salvage_auto_cast_los_audio_polish.md`, `docs/agy_plans/32_ai_tactics_staging_scouting_and_map_awareness.md`, `docs/agy_plans/33_tactical_depth_relays_defensive_stance_and_placement.md`

## 1. Codebase Audit & Objective

With Milestones 2.1–2.7 complete, the core RTS gameplay loop is feature-rich, but a review of the current codebase highlights **four structural bottlenecks** that must be cleared before designing Faction #2 in Milestone 3.0:

1. **Pre-Placed `GENESIS_V2` Starters in Skirmish Maps:** `skirmish_arena_01.tscn`, `02.tscn`, and `03.tscn` currently place `Nexus Vat` and `Worker` scenes directly in the map tree. If a player or AI selects Faction #2 in 3.0, the map bootstrap must dynamically spawn each active team's `FactionData` starting hub and starting units at its corner anchor rather than hardcoding `GENESIS_V2` scenes.
2. **Scattered Hardcoded Entity IDs:** Multiple core systems (`combat_component.gd`, `audio_manager.gd`, `gather_component.gd`, `repair_component.gd`, `selection_controller.gd`, `resource_hud.gd`, `minimap.gd`, `build_ghost_preview.gd`, `match_manager.gd`, `tactical_event_feed.gd`, `tech_tree_overlay.gd`) still branch on hardcoded `GENESIS_V2` IDs like `&"nexus_vat"`, `&"cloning_vat"`, `&"silica_condenser"`, `&"worker_unit"`, or `&"goliath_frame"`.
3. **Oversized AI Monolith (`skirmish_ai.gd` at 88.2 KB):** `SkirmishAICommander` has grown to 88 KB mixing tactical state machines with hardcoded `GENESIS_V2` build orders and counter-unit lookups. Extracting a clean data-driven `AIBuildPlanner` helper makes Faction #2 AI work automatically via `.tres` profiles.
4. **Faction-Agnostic Identity & Authoring Validation:** Adding Faction #2 should feel immediately distinct in the Lobby, Boot Sequence, HUD accents, Tech Tree, and Audio Barks—backed by an automated startup validator (`FactionData.validate()`) so broken `.tres` links are caught instantly.

### In Scope
* **Phase A:** Expand `UnitData`, `BuildingData`, and `FactionData` with semantic tags, weapon/VFX/audio profiles, drop-off & production role flags, tech-tree metadata, HUD/audio identity, and `FactionData.validate()`.
* **Phase B:** Faction-agnostic skirmish map starting-loadout spawning in `MatchManager`, live per-slot Faction dropdowns in `MainMenu`, and per-faction HUD/boot-banner accents.
* **Phase C:** Scrub hardcoded `GENESIS_V2` ID checks across all core engine systems, replacing them with semantic `UnitData` / `BuildingData` queries.
* **Phase D:** Fully data-driven `TechTreeOverlay` (with multi-faction tab viewing) and `SkirmishAI` decoupling via `scripts/systems/ai_build_planner.gd`.
* **Phase E:** Startup `FactionData.validate()` integrity check and Faction-aware `SandboxDebugPanel` spawning.

### Out of Scope
* Creating Faction #2's actual units, buildings, or `.tres` roster (reserved for Milestone 3.0).
* Major rewrites of `selection_controller.gd` or `unit.gd` movement/input logic (only targeted semantic helper swaps).
* Modifying `milestone_0_test.tscn` pre-placed sandbox test entities.

## 2. Phase A: Semantic Data Model Upgrade

### A.1 `UnitData` Weapon, VFX, Audio & Role Profiles (`scripts/data/unit_data.gd` & `resources/units/*.tres`)
Add clean, Inspector-editable exports with safe defaults so `CombatComponent`, `AudioManager`, `Minimap`, and `SelectionController` never need `match unit_id:` switches:

* **Weapon & VFX Profile:**
  * `@export var weapon_tracer_style: StringName = &"pulse"` (`&"pulse"`, `&"rail"`, `&"mortar"`, `&"arc"`, `&"bio"`, `&"heavy"`)
  * `@export var weapon_tracer_color: Color = Color(0.22, 0.74, 0.97, 1.0)`
  * `@export var weapon_tracer_width: float = 2.0`
  * `@export var weapon_sfx_id: StringName = &"pulse_rifle"`
* **Audio & UI Identity:**
  * `@export var audio_bark_class: StringName = &"swarm"` (`&"worker"`, `&"swarm"`, `&"counter"`, `&"support"`, `&"heavy"`)
  * `@export var minimap_icon_shape: StringName = &"dot"` (`&"dot"`, `&"worker"`, `&"triangle_heavy"`)
  * `@export var role_tags_display: String = ""` (concise tag string shown in `TechTreeOverlay` & `SelectionHUD`, e.g., `"+vs Armored • Anti-Heavy"`)
* **Semantic Helpers on `UnitData`:**
  * `has_tag(tag: StringName) -> bool` (queries `unit_tags`)
  * `is_worker_class() -> bool` (`has_tag(&"worker") or has_tag(&"harvester") or has_tag(&"engineer")`)
  * `is_combat_unit() -> bool` (`not is_worker_class() and attack_damage > 0.0` or `has_tag(&"support")`)
  * `is_heavy_unit() -> bool` (`has_tag(&"heavy")`)
* **Populate All `GENESIS_V2` `.tres` Files:** Fill `unit_tags`, `weapon_tracer_style`, `weapon_tracer_color`, `weapon_sfx_id`, `audio_bark_class`, `minimap_icon_shape`, and `role_tags_display` across all active `GENESIS_V2` unit `.tres` files (`worker_unit`, `silica_harvester`, `engineer`, `clone_trooper`, `stinger`, `symbiote`, `lance_rig`, `signal_jammer`, `goliath_frame`, `arc_lancer`, `chrysalis_mortar`).

### A.2 `BuildingData` Role, Tech Tier & Drop-Off Metadata (`scripts/data/building_data.gd` & `resources/buildings/*.tres`)
Replace hardcoded building-ID checks with explicit semantic exports:

* `@export var is_command_hub: bool = false` (`true` on `nexus_vat_data.tres` & `command_core_data.tres`)
* `@export var is_military_production: bool = false` (`true` on `cloning_vat`, `calibration_foundry`, `synthetics_fabricator`)
* `@export var is_supply_provider: bool = false` (`true` on `synapse_pylon`, `bandwidth_relay`, `nexus_vat`)
* `@export var accepted_dropoff_resources: Array[StringName] = []` (`[&"biomass", &"silica"]` on `nexus_vat`; `[&"silica"]` on `silica_condenser`)
* `@export var tech_tier: int = 0` (`0` = Core/Econ, `1` = Tier 1 Production/Counter, `2` = Tier 2 Heavy/Elite)
* `@export var prerequisite_building_ids: Array[StringName] = []` (e.g., `[&"cloning_vat"]` on `synthetics_fabricator_data.tres`)
* `@export var audio_select_class: StringName = &"utility"` (`&"hub"`, `&"production"`, `&"tech"`, `&"defense"`, `&"utility"`)
* `@export var tech_tree_summary: String = ""` (short role blurb for `TechTreeOverlay`)

### A.3 Expanded `FactionData` Manifest (`scripts/data/faction_data.gd` & `resources/factions/genesis_v2_faction.tres`)
Extend `FactionData` to serve as the single source of truth for an entire playable faction:

* **Identity & Presentation:**
  * `@export var short_code: String = "GEN-V2"`
  * `@export var hud_accent_color: Color = Color(0.20, 0.83, 0.60, 1.0)` (subtle Technozen accent tint for boot banner, Tech Tree header, and HUD accents)
  * `@export var boot_banner_text: String = "// NEURAL LINK ONLINE — GENESIS_V2"`
  * `@export var audio_bark_pitch_bias: float = 1.0` & `@export var audio_timbre_profile: StringName = &"technozen_bio"` (lets Faction #2 use a distinct procedural synth timbre/pitch character immediately)
* **Starting Match Loadout:**
  * `@export var starting_biomass: int = 250`
  * `@export var starting_silica: int = 75`
  * `@export var starting_compute: int = 0`
  * `@export var starting_worker_count: int = 3` (spawns `worker_scene` around `starting_hub_scene`, plus optional `@export var extra_starting_units: Array[PackedScene] = []`)
* **Data-Driven AI Composition & Counter Profile:**
  * `@export var ai_scout_unit_id: StringName = &"stinger"`
  * `@export var ai_salvage_unit_ids: Array[StringName] = [&"engineer_unit", &"worker_unit"]`
  * `@export var ai_counter_units: Dictionary` mapping tactical postures (`&"ANTI_ARMOR"`, `&"ANTI_SWARM"`, `&"ANTI_SIEGE"`, `&"BREACH"`) to preferred `unit_id` arrays (e.g., `&"ANTI_ARMOR": [&"lance_rig", &"arc_lancer"]`).
  * `@export var ai_playstyle_weights: Dictionary` mapping playstyles (`&"balanced"`, `&"swarm_rush"`, `&"synthetics_tech"`) to unit composition weights.
* **Self-Validation (`validate() -> Array[String]`):**
  * Verifies `faction_id != &""`, `starting_hub_scene != null`, `worker_scene != null`, all `building_roster` prerequisites exist in the roster, and required `ai_build_profile` keys are valid. Returns an array of human-readable warning strings (empty = clean).

## 3. Phase B: Faction-Agnostic Map Spawning & Lobby Selection

### B.1 Dynamic Starting Loadout Bootstrap (`scripts/systems/match_manager.gd`)
Make all three skirmish arenas (`skirmish_arena_01`, `02`, `03`) 100% faction-agnostic without needing to tear up existing `.tscn` map layouts:

* **Anchor Extraction & Swap on Skirmish Start (Skip on `milestone_0_test.tscn`):**
  1. On match init (before `ArenaNavRegion` initial rebake and before starting-worker auto-harvest), scan pre-placed command hubs (`building.data.is_command_hub`) in the scene to record each `team_id`'s exact spawn anchor `Vector2` (`_spawn_anchors[team_id]`).
  2. For any `team_id` **not** in `TeamManager.get_active_teams()`, free its pre-placed starter hub and starter units (preserving existing 2P/3P cleanup on `skirmish_arena_03`).
  3. For each **active** `team_id`:
     * Fetch `var faction := TeamManager.get_team_faction_data(team_id)`.
     * Check if the pre-placed hub already matches `faction.starting_hub_scene` (if `GENESIS_V2` is selected and the map already has a matching `Nexus Vat`, keep it or respawn cleanly; if a different faction is selected in 3.0, free the placeholder hub & placeholder starter workers and instantiate `faction.starting_hub_scene` + `faction.starting_worker_count` instances of `faction.worker_scene` + `extra_starting_units` arranged cleanly around the hub facing the nearest `BiomassNode` cluster).
     * Seed `EconomyManager` starting resources for `team_id` from `faction.starting_biomass`, `starting_silica`, and `starting_compute`.
  4. Request one clean `ArenaNavRegion` rebake if any hub was swapped, then run the existing deferred auto-harvest dispatch (using `unit.data.has_tag(&"worker")` rather than hardcoded `&"worker_unit"`).

### B.2 Live Faction Selector in `MainMenu` (`scripts/ui/main_menu.gd`, `scripts/systems/team_manager.gd`, `scripts/systems/game_config.gd`)
* In `TeamManager`, auto-discover/register all `FactionData` resources in `resources/factions/` (or a clean manifest array) and expose `get_playable_factions() -> Array[FactionData]`.
* In `MainMenu`'s Skirmish Slot Roster (`P1..P4`), include a compact **Faction** `OptionButton` populated dynamically from `TeamManager.get_playable_factions()` (displaying `GENESIS_V2` today; disabled/read-only tooltip `"More factions unlocking in 3.0"` only if `playable_factions.size() == 1`, and automatically interactive the moment Faction #2 is added!).
* Wire each slot's chosen `faction_id` through `GameConfig.slot_configs` → `TeamManager.configure_match()`.

### B.3 Per-Faction Boot Banner & HUD Accent (`scripts/systems/match_manager.gd`, `ui/hud/resource_hud.gd`)
* Update the Milestone 2.5.3 match-start boot sequence banner to read `faction.boot_banner_text` and tint its scanline/accent bar with `faction.hud_accent_color` (keeping the Spectator banner when in Spectator Mode).
* Apply a subtle `faction.hud_accent_color` trim/pip on the `TECH [U]` button or top HUD accent strip in `ResourceHUD`.

## 4. Phase C: Scrubbing Hardcoded `GENESIS_V2` Branches Across Engine Systems

Audit and migrate every remaining hardcoded unit/building ID check across core systems to semantic `UnitData` / `BuildingData` properties (preserving safe fallbacks so `milestone_0_test.tscn` legacy prototypes never break):

| System File | Hardcoded Pattern to Replace | New Semantic Data-Driven Query |
| :--- | :--- | :--- |
| `combat_component.gd` | `match unit_id:` for tracer color, width, style, and weapon SFX | `data.weapon_tracer_style`, `data.weapon_tracer_color`, `data.weapon_tracer_width`, `data.weapon_sfx_id` |
| `audio_manager.gd` | Hardcoded `unit_id` / `building_id` class mapping | `unit.data.audio_bark_class`, `building.data.audio_select_class`, plus `faction.audio_bark_pitch_bias` & `audio_timbre_profile` |
| `gather_component.gd` | Checking `&"nexus_vat"` / `&"silica_condenser"` for drop-off | `building.data.accepted_dropoff_resources.has(resource_type)` |
| `repair_component.gd` | Checking hardcoded synthetic unit IDs for Engineer repair | `target.data.has_tag(&"synthetic") or target.data.has_tag(&"heavy")` (plus `target is Building`) |
| `selection_controller.gd` | Checking hardcoded worker/combat IDs & production building IDs | `unit.data.is_worker_class()`, `unit.data.is_combat_unit()`, `building.data.is_military_production` |
| `resource_hud.gd` | Counting Army / Idle Workers / Idle Production by string IDs | `unit.data.is_combat_unit()`, `unit.data.is_worker_class()`, `building.data.is_military_production` |
| `build_ghost_preview.gd` | Checking `&"nexus_vat"` / `&"silica_condenser"` for resource tethers | `building_data.accepted_dropoff_resources` (automatically draws Biomass/Silica tethers for any faction's economy hubs!) |
| `minimap.gd` | Checking hub / heavy unit IDs for icon shapes | `building.data.is_command_hub`, `unit.data.minimap_icon_shape` / `unit.data.is_heavy_unit()` |
| `match_manager.gd` & `building.gd` | Checking `&"nexus_vat"` for defeat condition, last-hub salvage lock, and heavy-kill telemetry | `building.data.is_command_hub`, `unit.data.is_heavy_unit()` |
| `tactical_event_feed.gd` | Checking heavy unit / Tier 2 building IDs for feed alerts | `unit.data.is_heavy_unit()`, `building.data.tech_tier >= 2` |

## 5. Phase D: Data-Driven `TechTreeOverlay` & `SkirmishAI` Modularization

### D.1 Fully Data-Driven `TechTreeOverlay` (`scripts/ui/tech_tree_overlay.gd`)
* Refactor `TechTreeOverlay` to build its entire Tier 0 / Tier 1 / Tier 2 layout dynamically from any given `FactionData`:
  * Group `faction.building_roster` by `building_data.tech_tier` (`0`, `1`, `2`) into crisp columns.
  * For each building card, dynamically display:
    * Building name, cost pills (`Biomass / Silica / Compute`), and `prerequisite_building_ids` badges (resolved to display names).
    * Trainable units from `building_data.trainable_units` with their `role_tags_display`.
    * Researchable upgrades from `building_data.researchable_upgrades`.
  * Highlight currently owned structures and completed upgrades live for the inspected team (`TeamManager.get_local_human_team()`, or the selected faction tab in Spectator Mode).
* If multiple playable factions exist (in 3.0+), show a compact faction switcher pill bar at the top of the modal so players can inspect enemy faction tech trees mid-match too.

### D.2 `SkirmishAI` Decoupling & `AIBuildPlanner` Extraction (`scripts/systems/ai_build_planner.gd` *(new)* & `scripts/systems/skirmish_ai.gd`)
Trim `skirmish_ai.gd` (currently **88.2 KB**) and eliminate all hardcoded `GENESIS_V2` build-order assumptions:

* **Extract `scripts/systems/ai_build_planner.gd` (`AIBuildPlanner`, RefCounted helper):**
  * Owns all faction-driven macro/production decision math:
    * Resolves next building to construct from `faction.ai_build_profile` (`&"hub"`, `&"supply"`, `&"refinery"`, `&"compute_hub"`, `&"barracks_t1"`, `&"counter_foundry"`, `&"heavy_t2"`), checking `BuildingData.prerequisite_building_ids` dynamically before queuing a Tier-2 building.
    * Resolves next military unit to train by blending `faction.ai_playstyle_weights[playstyle]` with `faction.ai_counter_units[counter_posture]` and filtering by which production buildings are currently online and affordable.
    * Resolves next upgrade to research dynamically from `faction.upgrade_roster`.
    * Resolves scout unit (`faction.ai_scout_unit_id`), salvage unit (`faction.ai_salvage_unit_ids`), and heavy/anti-armor breaching units (`unit.data.has_tag(&"anti_armor") or unit.data.has_tag(&"heavy")`).
* **`SkirmishAICommander` (`scripts/systems/skirmish_ai.gd`):**
  * Delegates build-order and unit-composition choices to `AIBuildPlanner`, keeping `skirmish_ai.gd` focused cleanly on real-time tactical execution (`STAGING`, `ATTACKING`, `DEFENDING`, `RETREATING`, `BREACHING`, scouting, and worker/salvage micro).
  * Preserve 100% of Milestone 2.6 tactical behavior and Difficulty/Playstyle tuning.

## 6. Phase E: Authoring Safety & Sandbox Faction Readiness

* **Startup `FactionData.validate()` Check (`scripts/systems/team_manager.gd`):**
  * On `TeamManager._ready()`, run `validate()` on every registered `FactionData` and emit clear `push_warning(...)` diagnostics if any scene, prerequisite, or AI role reference is missing.
* **Faction-Aware `SandboxDebugPanel` (`ui/hud/sandbox_debug_panel.gd`):**
  * Populate unit/building spawn buttons dynamically from the active faction's `FactionData` (keeping a compact faction selector dropdown ready for 3.0 when multiple factions are registered) so testing Faction #1 vs. Faction #2 in the **Combat Lab** requires zero extra UI wiring.

## 7. File & Architecture Summary

### New Files to Create
* `scripts/systems/ai_build_planner.gd` (Extracted faction-driven macro, prerequisite, counter-unit, and upgrade planner for `SkirmishAICommander`)

### Existing Files to Extend
* `scripts/data/unit_data.gd`, `scripts/data/building_data.gd`, `scripts/data/faction_data.gd`, `resources/factions/genesis_v2_faction.tres`, `resources/units/*.tres`, `resources/buildings/*.tres` (Complete semantic metadata, weapon/VFX/audio profiles, drop-off & production flags, tech tiers, starting loadouts, AI counter/playstyle profiles, and `validate()`)
* `scripts/systems/team_manager.gd`, `scripts/systems/game_config.gd`, `scripts/ui/main_menu.gd` (Faction registry auto-discovery, startup validation, and per-slot Faction dropdown)
* `scripts/systems/match_manager.gd`, `ui/hud/resource_hud.gd` (Faction-agnostic dynamic starting-loadout spawning, per-faction starting resources, boot banner text & HUD accent color)
* `scripts/systems/skirmish_ai.gd` (Delegate build/composition planning to `AIBuildPlanner`; use semantic tags for scouting/breaching/salvage)
* `scripts/ui/tech_tree_overlay.gd` (100% data-driven tier rendering from `FactionData`)
* `scripts/units/combat_component.gd`, `scripts/units/gather_component.gd`, `scripts/units/repair_component.gd`, `scripts/systems/audio_manager.gd`, `scripts/controllers/selection_controller.gd`, `ui/overlays/build_ghost_preview.gd`, `ui/hud/minimap.gd`, `ui/hud/tactical_event_feed.gd`, `ui/hud/sandbox_debug_panel.gd`, `scripts/buildings/building.gd` (Scrub hardcoded `GENESIS_V2` string IDs in favor of semantic `UnitData` / `BuildingData` / `FactionData` queries)

## 8. Verification Checklist for `agy`

Before concluding Milestone 2.8, verify in Godot (`skirmish_arena_01.tscn`, `skirmish_arena_02.tscn`, `skirmish_arena_03.tscn`, and `milestone_0_test.tscn`):

* [ ] **Zero Validation Warnings:** Launch the project and confirm `TeamManager` validates `genesis_v2_faction.tres` with zero warnings or missing references in the Godot Output/Debugger.
* [ ] **Dynamic Map Bootstrap & Starting Resources:** Launch `1v1` on `skirmish_arena_01`, `2v2` on `skirmish_arena_03`, and `4-Way FFA (Spectator)` at `2x` speed; confirm starting hubs, starting workers, starting resources, and auto-harvesting initialize identically from `FactionData` with zero regressions or duplicate units.
* [ ] **Data-Driven Combat, Audio, Minimap & Placement:** Verify every `GENESIS_V2` unit fires its exact tracer color/style and weapon SFX from `UnitData`, plays its exact prioritized audio bark from `UnitData.audio_bark_class`, renders the right minimap silhouette (`triangle_heavy` for heavies, bordered hub squares), and displays emerald/cyan placement drop-off tethers on `Nexus Vat` and `Silica Condenser` via `accepted_dropoff_resources`.
* [ ] **Data-Driven `TechTreeOverlay` (`U`):** Open the Tech Tree mid-match; confirm Tier 0 / Tier 1 / Tier 2 columns, costs, prerequisites, unit role tags, and live green/cyan owned/researched highlights generate cleanly from `genesis_v2_faction.tres` with zero clipping at `1280×720` and Fullscreen.
* [ ] **Modular `AIBuildPlanner` & `SkirmishAI` Parity:** Run a `2x` `AI vs AI (Spectator)` match (`Swarm Rush` vs. `Synthetics Tech`) to completion; verify both AIs expand, tech to Tier 2, research upgrades, react to scouted intel (`ANTI_ARMOR` / `ANTI_SWARM`), breach barricades, and finish the match cleanly while `skirmish_ai.gd` is noticeably leaner and free of hardcoded `GENESIS_V2` IDs.
* [ ] **Zero `GENESIS_V2` Leakage Audit:** Search core engine scripts (`combat_component.gd`, `gather_component.gd`, `repair_component.gd`, `selection_controller.gd`, `resource_hud.gd`, `minimap.gd`, `build_ghost_preview.gd`, `tech_tree_overlay.gd`, `skirmish_ai.gd`) to verify zero hardcoded `GENESIS_V2` unit/building IDs remain in core simulation logic, and verify `milestone_0_test.tscn` still runs with zero Godot Debugger errors.