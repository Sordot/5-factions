# Milestone 3.7 — Pre-4.0 Modular Faction Architecture Refactor

**Prerequisite:** Milestones 3.1–3.6 verified and working cleanly.

**Goal:** Refactor the codebase's growing monoliths into clean, pluggable **per-faction registries and data-driven manifests** so that adding **Faction #3 (`03 // PRISMA_DEI — The Divine Lattice`)** in Milestone 4.0—and Factions #4–#5 afterward—requires authoring a self-contained faction module + `.tres` resources rather than stacking hardcoded `if faction_id ==` / `match entity_type_id:` branches across 60–90 KB core scripts.

**Non-Negotiable Constraints:**

* **Zero Balance Changes:** Do **NOT** modify any unit/building HP, shield, armor, damage, range, cooldown, speed, build time, or resource cost values on `GENESIS_V2` or `MONOLITH_OS`. Balance tuning is explicitly deferred until all factions are implemented.

* **Zero Behavioral Regressions:** Every existing visual silhouette, upgrade telltale, procedural SFX/ambient soundbed, HUD theme, hotkey, AI behavior, Procedural Arena, Uplink Holdout, Micro Gauntlet, and Spectator Mode must look, sound, and play identically after this refactor.

* **100% Procedural Pipeline & Strict `1280×720` UI Discipline:** All UI must remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).

* **Hard Guardrails (MUST PRESERVE):** No stealth/cloaking mechanics; no role-sorted squad formations; no overkill-prevention targeting automation; no auto-loop production.

---

## Target Architecture Overview

| Monolith / Bottleneck | Current Scaling Risk | Post-3.7 Modular Architecture |
| :--- | :--- | :--- |
| `ui/overlays/entity_visuals.gd` | Mixes core overlays (hover/marquee/blueprint/damage) with hardcoded `GENESIS_V2` and `MONOLITH_OS` unit/building/telltale draw functions. | Slim `EntityVisuals` coordinator dispatching to pluggable `FactionVisualRenderer` modules (`genesis_visual_renderer.gd`, `monolith_visual_renderer.gd`). |
| `scripts/systems/audio_manager.gd` | Combines playback arbitration, spatial attenuation, ducking, and every faction's procedural synth & ambient soundbed generators in one giant file. | Slim `AudioManager` playback/mix coordinator delegating waveform & soundbed synthesis to `FactionAudioProfile` modules (`genesis_audio_profile.gd`, `monolith_audio_profile.gd`). |
| `scripts/ui/faction_hud_theme.gd` & `ui/hud/command_icon_button.gd` | Hardcoded `if faction_id ==` palettes/overlays and growing `match icon_id:` glyph switches. | Pluggable `FactionHudTheme` style provider registry + dedicated `ui/hud/command_icon_glyphs.gd` vector glyph library. |
| `scripts/ui/main_menu.gd` & `scripts/systems/skirmish_ai.gd` | Hardcoded faction dossier descriptions/badges in `main_menu.gd` and hardcoded AI transmission tables in `skirmish_ai.gd`. | Moved directly onto `FactionData` `.tres` manifests (`genesis_v2_faction.tres`, `monolith_os_faction.tres`); `MainMenu` and `SkirmishAI` become 100% data-driven for 2–5 playable factions. |
| `scripts/buildings/building.gd`, `ui/hud/selection_hud.gd` | Scattered hardcoded `building_type_id` accent/cost/short-name chains. | Data-driven `short_display_name` and `hud_accent_color` exports on `UnitData`, `BuildingData`, and `UpgradeData`. |

---

## Phase A — Pluggable Faction Visual Renderer Pipeline

### A.1 Base Renderer Contract (`ui/overlays/renderers/faction_visual_renderer.gd`)

Create `class_name FactionVisualRenderer extends RefCounted` exposing shared geometry utilities (`poly_outlined`, `draw_closed_outline`, `scale_poly`, `build_chamfer_rect_poly`, `draw_active_conduit_sparks`) and clean virtual hooks:

* `func handles_unit(type_id: StringName) -> bool`
* `func handles_building(type_id: StringName) -> bool`
* `func get_building_outer_poly(type_id: StringName, radius: float) -> PackedVector2Array`
* `func draw_unit(canvas: CanvasItem, type_id: StringName, unit: Unit, ctx: Dictionary) -> void`
* `func draw_building(canvas: CanvasItem, type_id: StringName, building: Building, hull_poly: PackedVector2Array, ctx: Dictionary) -> void`
* `func draw_building_turret(canvas: CanvasItem, building: Building, ctx: Dictionary) -> bool` *(returns `true` if handled with a faction-specific turret overlay, else falls back to default turret draw)*
* `func is_mechanical_damage_style(type_id: StringName, is_building: bool) -> bool` *(drives damage spark/smoke style cleanly without hardcoded ID lists in `EntityVisuals`)*

*(Pass a single lightweight `ctx: Dictionary` containing `{ "palette": p, "team": team, "team_color": team_col, "anim_time": _anim_time, "pulse": pulse, "active_pulse": active_pulse, "upgrades": upgrade_lookup_callable }` so renderers never touch scene-tree queries per frame.)*

### A.2 Extract Faction #1 & Faction #2 Renderers

1. **`ui/overlays/renderers/genesis_visual_renderer.gd` (`class_name GenesisVisualRenderer extends FactionVisualRenderer`):**
   * Move all `GENESIS_V2` unit silhouettes (`worker`, `silica_harvester`, `engineer`, `clone_trooper`, `stinger`, `symbiote`, `lance_rig`, `signal_jammer`, `goliath_frame`, `arc_lancer`, `chrysalis_mortar`), building silhouettes (`nexus_vat`, `synapse_pylon`, `silica_condenser`, `wetware_mainframe`, `cloning_vat`, `calibration_foundry`, `synthetics_fabricator`, `defense_turret`), outer hull polygons, and `GENESIS_V2` upgrade telltales (`Batch Efficiency`, `Adrenal Potency`, `Compute Overdrive`) here verbatim.
2. **`ui/overlays/renderers/monolith_visual_renderer.gd` (`class_name MonolithVisualRenderer extends FactionVisualRenderer`):**
   * Move all `MONOLITH_OS` Neo-Brutalist Halftone helpers (`draw_brutalist_slab`, `draw_halftone_dots`, `draw_team_corner_brackets`), all 10 unit silhouettes, all 8 building silhouettes, `bastion_emplacement` turret overlay, chamfered building polygons, and `MONOLITH_OS` upgrade telltales (`Hardened Plating`, `Rapid Capacitors`, `Hyper-Velocity Rails`) here verbatim.

### A.3 Slim Coordinator (`ui/overlays/entity_visuals.gd`)

* Maintain a static renderer registry `_renderers: Array[FactionVisualRenderer]` initialized once lazily (`GenesisVisualRenderer.new()`, `MonolithVisualRenderer.new()`) with `static func register_renderer(renderer: FactionVisualRenderer) -> void`.
* Cache `_cached_renderer: FactionVisualRenderer` on `bind_unit()` / `bind_building()` (re-resolving only if `entity_type_id` changes) so `_draw()` does **O(1)** dispatch with zero per-frame linear scans or allocations.
* Keep shared engine-level visuals in `EntityVisuals`: hover rings, marquee preview rings, unit spawn flash, building construction blueprint fill, completion flash, hub saturation badge, low-HP damage states, and clean fallback silhouette for neutral/dummy units (`target_dummy`).

---

## Phase B — Modular Audio Synthesis & Faction Audio Profiles

### B.1 Procedural Synth Primitives & Profile Contract

Create a clean `scripts/systems/audio/` subdirectory:

1. **`scripts/systems/audio/synth_primitives.gd` (`class_name SynthPrimitives extends RefCounted`):**
   * Extract reusable pure-DSP buffer helpers from `audio_manager.gd` (e.g., `make_wav_from_samples`, oscillator/noise/envelope generators, low-pass/band-pass filter helpers, sub-bass transient punch mixer).
2. **`scripts/systems/audio/faction_audio_profile.gd` (`class_name FactionAudioProfile extends RefCounted`):**
   * Base contract for a faction's audio timbre:
     * `func get_profile_id() -> StringName`
     * `func build_weapon_and_ability_sfx(sfx_bank: Dictionary) -> void` *(registers faction-specific weapon/ability `AudioStreamWAV` buffers by `sfx_id`)*
     * `func build_bark_sfx(bark_bank: Dictionary) -> void` *(registers faction-specific selection/order bark buffers)*
     * `func build_ambient_layers() -> Dictionary` *(returns `{ &"macro": AudioStreamWAV, &"combat": AudioStreamWAV, &"uplink": AudioStreamWAV }` calibrated to existing `-14` to `-18 dB` headroom)*
3. **`scripts/systems/audio/genesis_audio_profile.gd` (`&"technozen_bio"`):**
   * Houses `GENESIS_V2`'s bio-synth weapon/ability waveforms, Technozen barks, and 3-layer organic-synth ambient soundbed verbatim.
4. **`scripts/systems/audio/monolith_audio_profile.gd` (`&"monolith_industrial"`):**
   * Houses `MONOLITH_OS`'s industrial slug/rail/siege/tether/barrier/grav-pulse/overclock/anchor waveforms, low-pitched quantized mechanical barks, and 3-layer industrial sub-bass ambient soundbed verbatim.

### B.2 Slim `AudioManager` Coordinator (`scripts/systems/audio_manager.gd`)

* Keep `AudioManager` strictly focused on:
  * Core UI & shared world SFX (`ui_click`, `error`, `build_complete`, `unit_ready`, `upgrade_complete`, `shield_shatter`, `tactical_alert`, explosions).
  * Profile registry (`_audio_profiles: Dictionary`) lazily synthesizing/caching each faction's ambient layers on demand via `FactionData.audio_timbre_profile`.
  * All Phase 0–3.6 mix safeguards: single-voice `_bark_player` priority arbitration, 10-voice combat cap, camera-distance spatial attenuation, `Time.get_ticks_msec()` real-time throttling at `2x` speed, dynamic combat ducking, and Master bus `AudioEffectLimiter`.

---

## Phase C — Pluggable Faction HUD Theme Registry & Command Icon Glyphs

### C.1 Extensible Faction HUD Theme Registry (`scripts/ui/faction_hud_theme.gd`)

* Refactor `FactionHudTheme` from hardcoded `match faction_id:` blocks into a clean provider map (`_theme_providers: Dictionary` mapping `faction_id -> Dictionary / RefCounted` defining palette, corner radii, border widths, button StyleBoxes, and frame overlay draw callable).
* Register `&"genesis_v2"`, `&"monolith_os"`, and `&"spectator"` providers cleanly at initialization, with automatic `FactionData.hud_accent_color` fallback for any unregistered faction ID.
* Ensure `SelectionHUD`, `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, and `TacticalEventFeed` all consume `FactionHudTheme` exclusively—zero duplicate faction `if/elif` styling blocks inside individual HUD scripts.

### C.2 Extract Command Card Vector Glyphs (`ui/hud/command_icon_glyphs.gd`)

* Extract the procedural `28×28 px` vector glyph drawing routines out of `ui/hud/command_icon_button.gd` into `class_name CommandIconGlyphs extends RefCounted` organized cleanly into:
  * Shared RTS command & utility glyphs (`cmd_move`, `cmd_stop`, `cmd_hold`, `cmd_defensive`, `cmd_patrol`, `cmd_amove`, `overclock`, `deploy`, `auto_repair`, `eject_engineers`, `salvage`, `cancel_build`).
  * Per-faction unit/building/ability/upgrade glyph dispatchers (so adding `PRISMA_DEI` glyphs in 4.0 is one clean section/helper without touching `CommandIconButton`'s interaction, cooldown sweep, hotkey badge, or Auto-Cast logic).

---

## Phase D — Fully Data-Driven `FactionData`, `MainMenu` Dossiers & Semantic Schema Cleanup

### D.1 Enrich `FactionData` (`scripts/data/faction_data.gd` & `resources/factions/*.tres`)

Add optional, backward-compatible metadata exports to `FactionData`:

* `@export var dossier_slot_number: int = 1` *(e.g., `1` for `GENESIS_V2`, `2` for `MONOLITH_OS`, `3` for `PRISMA_DEI`)*
* `@export var dossier_subtitle: String = ""` *(e.g., `"Bio-Synth Swarm  •  1.75x Parallel Batch Cloning  •  Heavy Synthetics Pivot"`)*
* `@export_multiline var dossier_description: String = ""` *(full featured-card tactical description)*
* `@export var signature_badges: PackedStringArray = PackedStringArray()` *(compact badge pills shown on the featured dossier card)*
* `@export var ai_transmissions: Dictionary = {}` *(maps event keys `&"wave_launch"`, `&"barricade_breach"`, `&"tier2_online"`, `&"uplink_contest"`, `&"expansion_lost"` → `Array[String]` radio dispatches)*

Populate these fields in both `resources/factions/genesis_v2_faction.tres` and `resources/factions/monolith_os_faction.tres`, and verify `FactionData.validate()` passes with **0 warnings**.

### D.2 Fully Data-Driven `MainMenu` Dossier Panel (`scripts/ui/main_menu.gd`)

* Remove all hardcoded `GENESIS_V2` and `MONOLITH_OS` dossier strings/badges from `main_menu.gd`.
* Sort `TeamManager.get_playable_factions()` by `dossier_slot_number` ascending.
* Render the top **Featured Dossier Card** purely from the currently selected `FactionData` (`dossier_slot_number`, `display_name`, `dossier_subtitle`, `dossier_description`, `signature_badges`, `hud_accent_color`, `primary_color`).
* Dynamically populate the 4 lower grid cards (`LockedSlot2..5` or a clean 4-slot `DossierGrid`):
  * For every playable faction other than the currently featured one (up to 4), render it as a **live selectable faction switcher card** tinted with its `FactionData.hud_accent_color`.
  * Fill the remaining unfilled slots up to `5` with the locked teaser dossiers (ensuring zero stealth/cloaking wording anywhere).
  * Update `FactionSectionHeader` dynamically to `"AI LORD FACTION DOSSIERS (%d / 5 ACTIVE)" % _playable_factions.size()`.
* Result: Dropping `prisma_dei_faction.tres` into `resources/factions/` in Milestone 4.0 automatically updates the Main Menu to `3 / 5 ACTIVE` with zero edits to `main_menu.gd`!

### D.3 Data-Driven AI Transmissions & Entity Short Names / Accents

1. **`scripts/systems/skirmish_ai.gd`:** Replace hardcoded `GENESIS_V2` / `MONOLITH_OS` radio transmission strings with lookups against `TeamManager.get_team_faction_data(ai_team).ai_transmissions` (with a clean generic fallback if empty).
2. **`scripts/data/unit_data.gd`, `building_data.gd`, `upgrade_data.gd`:**
   * Add `@export var short_display_name: String = ""` (with helper `get_short_name() -> String` returning `short_display_name` if non-empty else `display_name`). Populate concise names on existing `.tres` files so `SelectionHUD._shorten_unit_name()` no longer needs a 20-chain `.replace(...).replace(...)` hack!
   * Add `@export var hud_accent_color: Color = Color(0, 0, 0, 0)` on `BuildingData` (alpha `0` = fall back to owning team's `FactionData.hud_accent_color`). Populate distinct building accents where desired (e.g., gold for Silica Condensers, cyan for Compute structures) and strip the giant `elif building_type_id == &"..."` color ladder from `building.gd`.
   * Remove duplicate/hardcoded `Building.DEFAULT_BUILDING_COSTS` reliance wherever `building_data != null` (keep `building_data.get_cost_dict()` as single source of truth; retain only an empty-safe fallback lookup via `TeamManager.get_team_faction_data(team).get_building_by_id(building_type_id)`).
3. **`scripts/systems/economy_manager.gd` & `scripts/systems/upgrade_manager.gd`:**
   * Audit upgrade stat getters (`get_bonus_armor`, `get_shield_regen_delay_multiplier`, `get_shield_regen_rate_multiplier`, `get_batch_cost_multiplier`, rail/damage bonuses) to ensure they cleanly handle arbitrary `UpgradeData` resources (via `UpgradeData.modifier_key` / `modifier_value` or clean faction-agnostic queries) so Faction #3's 3 upgrades plug in cleanly without bloating `EconomyManager`.

---

## Phase E — Verification & Zero-Regression Audit Checklist

1. **Headless & Startup Integrity:**
   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionData.validate()` warnings**.
   * Verify code hygiene: confirm `entity_visuals.gd`, `audio_manager.gd`, `main_menu.gd`, and `selection_hud.gd` are noticeably leaner and contain zero hardcoded `MONOLITH_OS` / `GENESIS_V2` sprawl outside their dedicated faction modules and `.tres` manifests.
2. **Visual & Audio Parity Check:**
   * Run a `GENESIS_V2` vs. `MONOLITH_OS` skirmish on `skirmish_arena_01.tscn` and a Combat Lab test in `milestone_0_test.tscn`:
     * Confirm every `GENESIS_V2` unit (11), building (8), and upgrade telltale (3) renders identically via `GenesisVisualRenderer`.
     * Confirm every `MONOLITH_OS` unit (10), building (8), turret, and upgrade telltale (3) renders identically via `MonolithVisualRenderer`.
     * Confirm both adaptive 3-layer ambient soundbeds (`technozen_bio` and `monolith_industrial`), all weapon/ability SFX, shield-shatter, and single-voice bark arbitration sound identical with zero clipping at `2x` speed.
3. **HUD, Command Card & Main Menu Parity (`1280×720` Windowed & `F11` Fullscreen):**
   * Verify `MainMenu` dynamically displays `2 / 5 ACTIVE`, switches seamlessly between `GENESIS_V2` and `MONOLITH_OS` dossiers from both the left panel and right dropdowns, and stays 100% unclipped at `1280×720`.
   * Verify all 5 in-game HUD panels (`SelectionHUD`, `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, `TacticalEventFeed`) render the exact `GENESIS_V2` and `MONOLITH_OS` themes via `FactionHudTheme`, and every `CommandIconButton` glyph renders via `CommandIconGlyphs`.
4. **Full Mode Regression Sweep:**
   * Spot-check **Procedural Arena**, **Uplink Holdout**, **Micro Gauntlet**, and **4P FFA AI Spectator Mode** (including AI radio transmissions from `FactionData.ai_transmissions`) to confirm 100% behavioral parity and zero balance changes.