# Project Handoff — Phase 2: Visual Polish, Hybrid Asset Pipeline & Factions #4–#5

Use this document to bootstrap a fresh chat session with full architectural context, completed Phase 1 milestones, hard design guardrails, and the exact Phase 2 roadmap for visual upgrades and new factions.

---

## 1. Project Overview & Workflow

* **Engine:** Godot 4.x (2D RTS, GDScript, deterministic `_physics_process` simulation).
* **Display Target:** Strictly verified for both **Windowed `1280×720`** and **Fullscreen (`F11`)** with zero HUD clipping or minimap overlap.
* **Development Workflow:** Strategy, audits, and implementation blueprints are authored here as structured `.md` milestone plans (stored under `docs/agy_plans/phase2/`), which are then executed in the codebase by **`agy`** (the coding agent) and verified via an in-game checklist.
* **Current Status:** **Phase 1 (Core Engine Architecture & All 9 System Overhauls, Milestones 4.3a–4.12) is COMPLETE.** The engine is deterministic, modular (`RefCounted` helpers), faction-agnostic, and stress-tested across 1v1, 2v2, 3P FFA, and 4P FFA matches.

---

## 2. Hard Design Guardrails (NON-NEGOTIABLE)

Every future visual upgrade, mechanic, and faction **must** strictly preserve these rules:

1. **Zero Auto-Formations / Role-Sorted Player Squads:** Player `CommandRouter` movement stays purely organic concentric rings + SC2 contagious settling. Never auto-sort player units into frontline/backline lines. *(AI-only backline support trailing stays strictly inside `scripts/systems/ai/`.)*
2. **Zero Overkill-Prevention Automation:** No smart incoming-lethal-damage reservation; manual target splitting remains a core player skill.
3. **Zero Stealth / Cloaking Mechanics:** No invisible units or detection minigames.
4. **Zero Auto-Loop Production & Standard Worker Construction Only:** Workers physically construct every structure on-site across all factions; no auto-repeating production queues.
5. **Strict SC2 High-Ground & Fair Fog of War:**
   * `Elevation 0` units cannot see or fire uphill onto `Elevation 1` plateaus without an elevated allied spotter or unobstructed `SensorRelay`.
   * AI commanders strictly obey Fog of War (zero map-hacking, zero hidden resource/stat cheats).
   * Explored enemy buildings freeze as left-clickable *StarCraft II* building ghosts until re-scouted.
   * **Blind Procedural Scouting:** No pre-match minimap preview in the lobby; players must scout landmarks, chokes, and expansions in-match.
6. **Combat-Only `HyperUplink`:** Workers, harvesters, and compute specialists cannot capture or contest the central Data Hyper-Uplink.
7. **100% Procedural Audio Pipeline:** Zero external `.ogg`/`.wav`/`.mp3` files; all SFX, barks, and stereo ambient beds are synthesized in GDScript via `SynthPrimitives` + `FactionAudioProfile`s.
8. **Zero Unintended Stat Rebalancing:** Do not alter existing unit/building HP, shields, armor, damage, ranges, speeds, or costs unless explicitly requested.

---

## 3. Completed Phase 1 Architecture Summary (Milestones 4.3a–4.12)

* **Modular Decomposition (4.3a & 4.3b):** Core monoliths split into focused `RefCounted` helpers (`UnitCommandQueue`, `UnitDeployController`, `UnitInspectionBuilder`, `UnitWorldOverlay`, `BuildingRallyController`, `BuildingPowerLattice`, `BoxSelectionResolver`, `ControlGroupManager`, `CommandCursorManager`, `CommandCardBuilder`, `SelectionTelemetryRenderer`, `AIScoutIntel`, `AIEconomyManager`, `AIArmyController`).
* **#1 Movement, Steering & Pathing (4.4):** World-only physics (`collision_mask = 1`, RVO2 disabled), 4-tier SC2 push-priority + mass solver, proactive idle-ally yielding ("parting the sea"), firm hostile body-blocking, frictionless worker mineral-walking, `move_group_id` contagious settling, async `ArenaNavRegion` baking (`bake_navigation_polygon(true)`) with resource cutouts, zero-alloc `SpatialGrid`.
* **#2 Combat Simulation & Abilities (4.5):** Unified `CombatTargeting`, zero-frame-loss cadence + `+12 px` windup completion grace, seamless post-lock continuous beam ticking (`Focus Alignment` pre-charge preserved), opt-in `UnitData.can_fire_while_moving` engine hook, deterministic `_physics_process` `CombatOrdnanceManager` with radial AoE damage falloff & inner-core telegraphs, multi-barrier dirty-cached `StatusEffectComponent` (with `stack_policy`, `category`, `dispel()`, `armor_delta`, `heal_received_mult`), fog/2v2-safe `AbilityComponent` (`AbilityData.TargetFilter`, `can_cast_while_moving`), O(1)-idle `OpticalTetherSystem` with `24 px` link hysteresis.
* **#3 Vision, Fog of War & Elevation (4.6):** 32 px dual-texture GPU-smoothed Fog of War (`assets/shaders/fog_of_war.gdshader`) with subtle Technozen grid strictly inside `UNEXPLORED`, authentic left-clickable SC2 frozen building ghosts (`FogGhostOverlay` + `ghost_desaturate.gdshader` + minimap parity), fog-safe `SensorRelay`, O(1) AABB-cached `HighGroundPlateau` elevation, 360° cliff readability.
* **#4 Economy, Harvesting & Structures (4.7):** Same-type cargo preservation, direct rim drop-offs, NavMesh-aligned harvest slots, mineral-line saturation bouncing, O(1) desync-proof `EconomyManager` (keyed per-building bandwidth reservations + constructed-tech cache), zero-churn `ProductionComponent` (`progress_updated` vs. `queue_changed`), immediate salvage queue refunds + Engineer ejection, NavMesh-validated perimeter spawning, capability-aware universal Command Hub rallies, single-pass `BuildingPowerLattice`.
* **#5 Selection, Input & Camera (4.8):** Unscaled real-time `RTSCamera` physics, pixel-locked zoom-to-cursor, instant `F1–F4` (`F5–F8` optional) bookmark snaps, sticky-free middle-drag, 10 control groups (`1–9, 0`), largest-cluster double-tap centering, seamless Fog-Ghost inspection handoff, rebindable `cmd_ability_g`, O(1) `SpatialGrid` hit-testing, Shift-chain ability multi-cast, parallel multi-worker build dispatch, `SelectionWireframeGrid` Right-Click camera focus + auto-paging + wheel-paging.
* **#6 HUD, Rendering & Clarity (4.9):** Smart building redraw gating (~85% idle reduction), mirror-match/zoom-out team contrast halos, viewport-culled `HitFeedbackOverlay` + soft micro-VFX budgeting, crash-free `Alt` `TacticalGlanceOverlay` with faction macro rings, zero-churn `SelectionHUD` telemetry + `44×44` procedural `SelectionEntityPortrait`, cached `FactionHudTheme`, 2–4 team `ResourceHUD` spectator strip + split alert/toast channels, cached static `TacticalMinimap` terrain + bookmark pips, interactive pooled `ProductionTicker`.
* **#7 Procedural Audio & Soundscape (4.10):** 7-bus mixer (`Master`, `SFX`, `SFX_Near`, `SFX_Far`, `UI`, `Barks`, `Ambience`), `±75%` camera-relative stereo panning + `2400 Hz` distant low-pass, 16-voice 4-tier priority-weighted combat pool, proximity cooldown override, click-free stereo ambient loops baked asynchronously via `WorkerThreadPool`, `0.65s` profile crossfades, Team 1 faction ambience in Spectator Mode.
* **#8 Skirmish AI Commander (4.11):** Deadlock-proof non-blocking budget reservation + Universal Hub Silica bootstrapping (fixing `MONOLITH_OS` stall), adaptive expansion/pressure defense turrets (`1` per expansion + extra under pressure), worker evacuation + base/heavy-unit repair, proportional home defense, flank raid squads, active Sensor Relay capture, shared per-tick vision cache, fair Fog-of-War targeting, 2v2 allied reinforcement.
* **#9 Maps, ProcGen & Objectives (4.12):** 4 distinct procedural map archetypes (`Open Macro`, `Twin Ridges`, `Bridge Chokepoints`, `Triad Observatory`), `64 px` inter-node resource spacing guard, dynamic anchor-aware `MapBiomeBackdrop`, combat-only fog-safe throttled `HyperUplink`, viewport-culled `SalvageCore`.

---

## 4. Established Factions (3 Playable)

| Faction | Aesthetic / Theme ID | Audio Profile | Core Identity & Signature Mechanics |
| :--- | :--- | :--- | :--- |
| **`GENESIS_V2`** | Technozen Bio-Synth (`technozen`, Teal `#20F5DC` / Emerald) | `technozen_bio` | Organic-synthetic balance, 2× Batch Cloning Vats, Adrenal Surge, Goliath Frame, Arc-Lancer (line pierce), Chrysalis Mortar (AoE), Symbiote (heal aura), Signal Jammer (`Grav-Pulse`). |
| **`MONOLITH_OS`** | Neo-Brutalist Machine-State (`brutalist`, Off-White `#F2EFE9` / Ink `#0A0D12` / Hazard Amber `#FF9F1C`) | `monolith_industrial` | Heavy armor + unmitigated regenerating shields, Capacitor Pylon shield-delay aura, Core Overclock (`2×` production), 3/vein Silica saturation, Bulwark Automaton, Picket Drone, Rail-Sentinel, Aegis Relay, Anvil Siege-Walker (Deploy), Monolith Dreadnought, Null-Grid Projector, Bastion Emplacement. |
| **`PRISMA_DEI`** | Bauhaus Sacred Geometry (`bauhaus_sacred`, Obsidian-Violet / Alabaster / Liturgical Gold `#FACC15` / Magenta `#D946EF`) | `prisma_cathedral` | Power Lattice (`Halo Spire`), Optical Tether ("Harmonic Communion") link buffs, escalating continuous beams & refraction split-beams, Acolyte, Prism Dredge, Cantor, Votary, Lumen Skiff, Lens Adjudicator (`Focus Alignment`), Prism Weaver, Solstice Lance (`Solar Convergence` orbital strike), Seraph Cruiser, Solar Obelisk. |

---

## 5. Phase 2 Roadmap

### Track A — Hybrid Visual Polish & Asset Pipeline

Because rendering is cleanly decoupled inside `EntityVisuals`, `MapBiomeBackdrop`, and `SelectionEntityPortrait`, visual upgrades should be rolled out **incrementally** with graceful fallback to existing procedural vector renderers whenever an asset is unassigned (keeping prototyping for Factions #4–#5 effortless).

1. **Stage 1 — Godot Lighting & AI-Generated Seamless Terrain Textures (Fastest Visual Jump):**
   * Generate seamless tileable floor textures for the 4 biomes (`vat_basin`, `twin_causeway`, `quad_nexus`, `triad_sanctum`) and optional cliff/plateau surface textures—keeping contrast dark and low-frequency so combat silhouettes pop.
   * Wire tiled `Texture2D` backgrounds underneath `MapBiomeBackdrop`'s existing dynamic anchor-aligned vector conduits, pads, and hazard strips.
   * Add a tuned `WorldEnvironment` (`Glow` / subtle Bloom with high threshold `> 1.05` and low intensity) so `PRISMA_DEI` beams, `GENESIS_V2` bio-cores, muzzle shocks, shield shatters, and `Solar Convergence` glow crisply without washing out HUD or floors.
   * Add soft grounded contact shadows under units, buildings, and high-ground plateaus.

2. **Stage 2 — AI-Generated 2D HUD Art (Portraits, Faction Emblems & Icons):**
   * Generate cohesive faction crests/emblems, stylized unit/building portraits for `SelectionEntityPortrait` (and `MainMenu` faction dossiers), and crisp command-card/tech-tree icons.
   * Add optional `@export var portrait_texture: Texture2D` and `@export var icon_texture: Texture2D` fields on `UnitData`, `BuildingData`, `AbilityData`, and `UpgradeData`, falling back cleanly to `CommandIconGlyphs` procedural glyphs when null.

3. **Stage 3 — Blender 3D-to-2D Pre-Rendered Sprite Pipeline (Units & Structures):**
   * Model low-poly geometric silhouettes in Blender matching each faction's art direction (Bio-Synth, Neo-Brutalist, Bauhaus Sacred, plus Factions #4–#5).
   * Render from a **locked orthographic top-down camera** with consistent lighting, exporting three synchronized maps per asset (or sprite sheet for turrets/deploy animations):
     1. **Albedo (`.png`):** Clean silhouette with neutral base panels.
     2. **Normal Map (`_n.png`):** Wired via Godot `CanvasTexture` so dynamic 2D `PointLight2D` bursts (explosions, rail shots, orbital strikes) light beveled armor plates in real time.
     3. **Team-Color Mask (`_m.png`):** Grayscale mask read by a lightweight Godot `CanvasItem` shader to tint designated stripes/emblems with `TeamManager.get_team_color(team)` (preserving 4P FFA and mirror-match clarity, plus full compatibility with 4.6's `ghost_desaturate.gdshader` for frozen enemy building ghosts).
   * Add optional `sprite_texture`, `normal_map`, `team_mask`, and `turret_sprite_texture` exports on `UnitData` / `BuildingData`, allowing `EntityVisuals` to render sprites when assigned and fall back cleanly to procedural vectors otherwise.

---

### Track B — Factions #4 & #5 Integration Checklist

The engine already has pluggable registries and next-gen hooks ready for **Faction #4** and **Faction #5** (including `UnitData.can_fire_while_moving`, `AbilityData.TargetFilter`, `AbilityData.can_cast_while_moving`, `StatusEffectComponent` `stack_policy`/`dispel`/`armor_delta`/`heal_received_mult`, and `SynthPrimitives` biquad filters):

1. **Data Manifest:** Create `resources/factions/<faction_id>_faction.tres` (`FactionData`) + `UnitData`, `BuildingData`, `AbilityData`, and `UpgradeData` resources + scenes.
2. **Visual Renderer:** Implement `<Faction>VisualRenderer extends FactionVisualRenderer` and register via `EntityVisuals.register_renderer(...)` *(supports both procedural vector prototyping and Stage 3 sprite overrides)*.
3. **HUD OS Theme:** Register custom palette/frame drawer via `FactionHudTheme.register_theme_provider(faction_id, palette_dict)`.
4. **Procedural Audio Profile:** Implement `<Faction>AudioProfile extends FactionAudioProfile` (weapons, abilities, barks, and stereo 4.0s ambient beds using `SynthPrimitives.make_stereo_widened_loop_wav`) and register via `AudioManager.register_audio_profile(...)`.
5. **AI Build Profile:** Populate `ai_build_profile` (`hub`, `supply`, `refinery`, `compute_hub`, `barracks_t1`, `counter_foundry`, `heavy_t2`, `turret`), `ai_scout_unit_id`, `ai_salvage_unit_ids`, `ai_counter_units`, and `ai_playstyle_weights`—`SkirmishAICommander` and `AIBuildPlanner` will play the new faction automatically with zero hardcoded engine changes.
6. **Boot Validation:** Confirm **0 `FactionAudit:` warnings** on launch and run a 3P/4P AI-vs-AI Spectator stress test at `2×` speed.

---

## 6. Suggested First Prompt for the New Chat

> "Read the attached Phase 2 Handoff document. Let's start Phase 2 by:
> 1. Generating seamless tileable terrain textures for our 4 biomes (`vat_basin`, `twin_causeway`, `quad_nexus`, `triad_sanctum`) and planning the Godot `MapBiomeBackdrop` + `WorldEnvironment` bloom/lighting integration, OR
> 2. Brainstorming Faction #4's core identity, silhouette language, and concept art before building its roster.
> Let's keep all Phase 1 guardrails intact."