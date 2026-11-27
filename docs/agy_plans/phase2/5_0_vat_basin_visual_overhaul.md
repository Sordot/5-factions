# Milestone 5.0 Plan: Vat Basin Visual Overhaul, HDR Bloom & Grounded Contact Shadows

**Target Directory:** `docs/agy_plans/phase2/milestone_5_0_vat_basin_visual_overhaul.md`  
**Primary Scenes & Assets:** `assets/textures/biomes/vat_basin_ground.png` *(drop-in)*, `scenes/maps/skirmish_arena_01.tscn`, `scenes/maps/skirmish_arena_procedural.tscn` *(if applicable)*  
**Primary Scripts & Shaders:** `project.godot`, `scripts/world/map_biome_backdrop.gd`, `scripts/world/high_ground_plateau.gd`, `ui/overlays/entity_visuals.gd`, `assets/shaders/vat_basin_floor.gdshader` *(new)*  
**Reference Docs:** `docs/phase_2_handoff_visual_polish_asset_pipeline_factions_4_5.md`, `docs/agy_plans/phase1/milestone_3_2_full_hud_faction_theming_battlefield_juice_map_biomes.md`, `docs/agy_plans/phase1/milestone_3_4_high_ground_upgrade_telltales_hyper_uplink_victory.md`, `docs/agy_plans/phase1/milestone_4_9_system_overhaul_6_hud_rendering_battlefield_clarity.md`

---

## 1. Objective & Scope

Execute **Phase 2 — Track A (Stage 1)** for the **Vat Basin (`vat_basin`)** biome (`GENESIS_V2` home map) to elevate battlefield visual richness and grounding while keeping unit silhouettes, team colors, Fog of War, and 1280×720 / F11 HUD readability rock-solid.

### In Scope
1. **Seamless Textured Ground & Anti-Repetition Shader (`vat_basin`):**
   * Wire `res://assets/textures/biomes/vat_basin_ground.png` into `MapBiomeBackdrop` when `biome_id == &"vat_basin"`, using repeat/tiling import settings and a lightweight `CanvasItem` shader (`assets/shaders/vat_basin_floor.gdshader`) that blends tiled samples with subtle world-space macro tonal/moss modulation so repeated conduits and panels do not read as an obvious grid across large arenas.
   * Keep graceful, zero-error fallback to existing procedural `_draw_vat_basin()` vector drawing whenever `vat_basin_ground.png` is missing or unassigned.
   * Refine procedural conduit/contour alpha and contrast on `vat_basin` so the underlying Frutiger Eco / Techno-Zen slate, velvety moss, and aqua coolant conduits remain crisp and readable without washing out units.
2. **Tuned `WorldEnvironment` 2D Glow / Bloom (`project.godot` + Skirmish Scenes):**
   * Enable HDR 2D rendering (`rendering/viewport/hdr_2d = true`) in `project.godot` for Godot 4.7 Forward Plus.
   * Add a tuned `WorldEnvironment` node with `background_mode = WorldEnvironment.BG_CANVAS` and subtle 2D Glow (`glow_enabled = true`, high `glow_hdr_threshold > 1.08`, controlled `glow_intensity` around `0.25–0.40`, `glow_bloom` around `0.08–0.18`) so `PRISMA_DEI` beams, `GENESIS_V2` bio-cores, muzzle flashes, shield shatters, and `Solar Convergence` glow crisply without washing out floors, UI text, or `CanvasLayer` HUD panels.
3. **Grounded Contact Shadows (`EntityVisuals`):**
   * Render soft, low-alpha grounded contact shadows under all visible units and constructed buildings in `EntityVisuals`, with a slightly larger/offset grounding shadow when a unit is on `Elevation 1` (`HighGroundPlateau`) so every entity feels physically anchored to the textured terrain.

### Out of Scope
* Textures for `twin_causeway`, `quad_nexus`, or `triad_sanctum` (handled in follow-up passes).
* Stage 2 2D HUD portraits/emblems/icons or Stage 3 Blender 3D-to-2D unit/building sprites.
* Faction #4 or Faction #5 roster/mechanics work.
* Any changes to unit/building combat stats, ranges, speeds, costs, or hard design guardrails (no stealth/cloaking, no auto-formations, no overkill automation, no auto-loop production, standard worker construction only, strict SC2 high-ground/FoW & blind procedural scouting, combat-only `HyperUplink`, 100% procedural audio).

---

## 2. File & Architecture Plan

### New Files
* `assets/textures/biomes/vat_basin_ground.png` *(placed by user; configured with repeat enabled in `.import`)*
* `assets/shaders/vat_basin_floor.gdshader` — Lightweight tiling + world-space macro tonal variation shader for `vat_basin` floor rendering.

### Existing Files to Extend
* `project.godot` — Enable `rendering/viewport/hdr_2d=true` under `[rendering]`.
* `scripts/world/map_biome_backdrop.gd` — Add optional `@export var vat_basin_texture: Texture2D` (defaulting/loading `res://assets/textures/biomes/vat_basin_ground.png` safely if present), render the textured floor pass below dynamic conduits/contours for `&"vat_basin"`, and fall back seamlessly to procedural floor fill when `vat_basin_texture == null`.
* `ui/overlays/entity_visuals.gd` — Add a clean, low-cost grounded contact shadow pass for units and buildings (respecting existing elevation shadow behavior and camera/mirror halos without breaking zero-cost idle/off-screen rules).
* `scenes/maps/skirmish_arena_01.tscn` *(and any other active skirmish/procedural arena scene using `MapBiomeBackdrop`)* — Add the `WorldEnvironment` node configured for subtle HDR 2D glow.

---

## 3. Implementation Details & Guardrails

1. **Asset & Shader Safety:**
   * Use `ResourceLoader.exists("res://assets/textures/biomes/vat_basin_ground.png")` before `load(...)` so missing assets never trigger load errors during headless or pre-drop-in runs.
   * Ensure `.import` sets `compress/mode` cleanly and repeat/wrap mode is enabled (`REPEAT`) so UV tiling across `arena_bounds` works without clamping artifacts.
   * Keep the floor shader subtle: gentle world-space low-frequency tonal/hue variation (`~4–8%` modulation) so unit silhouettes, health bars, selection rings, and attack tracers maintain strong figure-ground separation.
2. **Fog of War & Overlay Order:**
   * Keep `MapBiomeBackdrop` at `z_index = -100` underneath `HighGroundPlateaus` (`-50`), `BattleScarsOverlay` (`-6`), entities, and `FogOverlay` (`35`).
   * Ensure `FogOverlay` (`fog_of_war.gdshader`) and `FogGhostOverlay` continue to shroud `UNEXPLORED` and `EXPLORED` areas cleanly without bloom bleeding through fogged/unexplored space.
3. **Performance & Lifecycle Hygiene:**
   * Keep `MapBiomeBackdrop` `_process(false)` and `_physics_process(false)` (redrawing only on `_ready()` or `refresh_anchors()`).
   * Ensure `EntityVisuals` contact shadows incur zero extra per-frame allocations and clean up cleanly on scene reload, Rematch, and return to `MainMenu`.

---

## 4. Verification & Playtest Checklist

1. **Startup & Zero-Regression Check:**
   * Launch Godot (`F5`) and confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.
   * Verify `1280×720` Windowed and `F11` Fullscreen have zero HUD clipping, minimap overlap, or washed-out HUD elements.
2. **`vat_basin` Textured Floor & Fallback:**
   * Load `skirmish_arena_01.tscn` with `vat_basin_ground.png` in place: verify the Frutiger Eco / Techno-Zen slate, moss, and aqua conduits render across the arena with subtle macro variation and dynamic anchor-aligned conduits/rings still lined up to bases, barricades, and `HyperUplink`.
   * Temporarily move/rename `vat_basin_ground.png` and re-test: confirm `MapBiomeBackdrop` falls back cleanly to procedural vector drawing with zero errors.
3. **HDR Bloom & Grounded Contact Shadows:**
   * Trigger combat, `PRISMA_DEI` beams / `Solar Convergence`, `GENESIS_V2` / `MONOLITH_OS` shields & shield-shatter bursts, and `HighGroundPlateau` movement: verify crisp subtle bloom on bright energy effects and clear grounded shadows beneath units and buildings across both `Elevation 0` and `Elevation 1` without hurting unit readability.