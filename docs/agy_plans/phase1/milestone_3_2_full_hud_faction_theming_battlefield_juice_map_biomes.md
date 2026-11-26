# Milestone 3.2 — Full-HUD Faction OS Theming, Damage/Shield-Break Juice & Procedural Map Biomes

**Prerequisite:** Milestone 3.1 (`39_milestone_3_1_building_hotkeys_and_icon_command_card.md`) verified and working cleanly.  
**Goal:** Elevate visual cohesion and battlefield readability across three linked pillars:
1. **Full-HUD Faction OS Theming:** Extend Milestone 3.1's `GENESIS_V2` (*Technozen Bio-Synth*) and `MONOLITH_OS` (*Neo-Brutalist Halftone*) styling across `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, and `TacticalEventFeed` via a shared, reusable faction HUD theme helper.
2. **Procedural Damage & Shield-Break States:** Add lightweight, zero-particle vector damage states (sparks/smoke vents below 40% HP, intensified warning flares below 20% HP) and a pooled **Shield-Shatter Burst** (visual + audio cue) whenever a unit or building's native shield breaks from `> 0` to `0`.
3. **Distinct Procedural Map Biome Identity:** Give `skirmish_arena_01.tscn` (*Vat Basin*), `skirmish_arena_02.tscn` (*Twin Causeway*), and `skirmish_arena_03.tscn` (*Quad Nexus*) distinct low-contrast procedural floor treatments so each arena has its own visual mood while keeping unit silhouettes and tracers 100% legible.

**Non-Negotiable Constraints:**
* **100% Procedural Pipeline:** All HUD flair, damage/shield VFX, SFX, and biome floors must use Godot 2D `_draw()`, `StyleBoxFlat`, and procedural synth audio—zero external image or audio assets.
* **Strict `1280×720` UI Discipline:** All themed HUD panels must preserve exact footprints and remain 100% unclipped in both Windowed `1280×720` and Fullscreen (`F11`).
* **4P FFA Performance Guard:** Route ephemeral shield-shatter bursts through `VFXPool`; keep per-entity damage vents lightweight (max 3–5 vector primitives per damaged entity); keep biome floors low-draw-call and non-redrawing per frame (draw once on ready/resize).
* **High Gameplay Contrast:** Biome floors must remain dark, low-saturation, and low-contrast so units, selection rings, hover outlines, Fog of War, and weapon tracers always pop cleanly.
* **Hard Exclusions:** No stealth/cloaking mechanics; no role-sorted squad formations.

---

## Phase A — Shared Faction HUD Theme Helper & Full-HUD Rollout

### A.1 Centralized Theme Utility (`scripts/ui/faction_hud_theme.gd`)
Create a lightweight reusable helper (`class_name FactionHudTheme`) so `SelectionHUD`, `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, and `TacticalEventFeed` share one source of truth instead of duplicating color tables or border-drawing code:

* **Theme Resolution:**
  * `static func resolve_local_faction_id() -> StringName`:
    * If `TeamManager != null` and `TeamManager.is_spectator_mode()`: return `&"spectator"`.
    * Else resolve `TeamManager.get_team_faction(TeamManager.get_local_human_team())` (falling back to `&"genesis_v2"`).
  * `static func get_palette(faction_id: StringName) -> Dictionary`:
    * **`&"genesis_v2"` (*Technozen Bio-Synth*):**
      * `bg`: `Color(0.04, 0.08, 0.12, 0.92)`
      * `border`: `Color(0.125, 0.961, 0.863, 0.88)` (`#20F5DC`)
      * `accent`: `Color(0.20, 0.96, 0.86, 1.0)`
      * `secondary`: `Color(0.28, 0.98, 0.62, 1.0)`
      * `corner_radius`: `6`, `border_width`: `1` (or `2`), `style`: `&"technozen"`
    * **`&"monolith_os"` (*Neo-Brutalist Halftone*):**
      * `bg`: `Color(0.15, 0.165, 0.185, 0.96)` (matte gunmetal/concrete)
      * `border`: `Color(0.04, 0.05, 0.07, 0.98)` (`#0A0D12` thick dark ink)
      * `inner_trim`: `Color(0.949, 0.937, 0.914, 0.88)` (`#F2EFE9` off-white)
      * `accent`: `Color(1.0, 0.624, 0.110, 1.0)` (`#FF9F1C` Hazard Amber)
      * `secondary`: `Color(0.220, 0.741, 0.973, 1.0)` (`#38BDF8` Shield Cyan)
      * `corner_radius`: `0`, `border_width`: `3`, `shadow_size`: `0`, `shadow_offset`: `Vector2(3, 3)`, `style`: `&"brutalist"`
    * **`&"spectator"` (*Neutral Observer Terminal*):**
      * `bg`: `Color(0.05, 0.07, 0.10, 0.92)`, `border`: `Color(0.36, 0.78, 0.96, 0.82)`, `accent`: `Color(0.42, 0.88, 1.0, 1.0)`, `corner_radius`: `4`, `border_width`: `1`, `style`: `&"technozen"`
    * **Future Factions (#3–#5 Fallback):**
      * Queries `TeamManager.get_faction_data(faction_id)` and tints a clean Technozen palette using `fac.hud_accent_color` and `fac.primary_color`.
* **Panel Styling & Overlay Drawing:**
  * `static func make_panel_style(faction_id: StringName, compact: bool = false) -> StyleBoxFlat`
  * `static func attach_frame_overlay(target_panel: Control, faction_id: StringName, variant: StringName = &"default") -> Control`
    * Attaches (or updates) a `mouse_filter = MOUSE_FILTER_IGNORE` child `Control` that draws faction-specific border flair in `_draw()`:
      * **`&"technozen"` (`GENESIS_V2`):** Subtle glowing top/bottom scanline accent, 3 px bioluminescent corner nodes with faint outer halos, and delicate inner hairline ticks.
      * **`&"brutalist"` (`MONOLITH_OS`):** Crisp off-white inner hairline inset (`3 px`), bold **Hazard Amber** top-left & bottom-right L-brackets, and a compact procedural halftone dot strip in one corner (strictly outside text margins so labels stay 100% crisp).

### A.2 Extend Faction OS Flair to All 4 Remaining Match HUD Panels
Wire `FactionHudTheme` cleanly into each HUD script (re-applying if `TeamManager.teams_reconfigured` emits) while **preserving exact `1280×720` widths, margins, and `blocks_edge_pan` groups**:

1. **`ui/hud/resource_hud.gd` (Top Resource Bar):**
   * Apply `FactionHudTheme.make_panel_style(fid, true)` + `attach_frame_overlay(panel, fid, &"top_bar")`.
   * For `MONOLITH_OS`: tint header separators and the `TECH [U]` / `?` utility button trims with Hazard Amber + off-white brutalist borders; keep Biomass (emerald), Silica (gold), Compute (cyan), and Bandwidth 3-state warning colors (Normal / Near-Cap Amber / Over-Cap Crimson) unmistakable.
   * For `GENESIS_V2`: crisp Technozen rounded glass top bar with glowing cyan corner nodes.
2. **`ui/hud/production_ticker.gd` (Top-Left Active Production Ticker):**
   * Style individual ticker rows with the active faction's `StyleBoxFlat` (rounded cyan-rimmed glass rows for `GENESIS_V2`; sharp ink-bordered concrete slabs with thin amber left accent bars and halftone corner pip for `MONOLITH_OS`).
   * Keep progress bars tinted with faction accent (and pulsing Hazard Amber when a structure is `Overclocked`).
3. **`ui/hud/minimap.gd` (Bottom-Left Tactical Minimap):**
   * Style the outer `TacticalMinimap` frame container using `FactionHudTheme`:
     * `GENESIS_V2`: Technozen beveled cyan bezel with subtle corner telemetry nodes.
     * `MONOLITH_OS`: Heavy dark-ink neo-brutalist frame with hard offset shadow, off-white inner trim, and bold Hazard Amber corner brackets (`L`-clamps) framing the map viewport.
   * Keep the minimap canvas size and `244 px` clearance budget for `SelectionHUD` unchanged.
4. **`ui/hud/tactical_event_feed.gd` (Bottom-Right Click-to-Jump Event Pills):**
   * Match pill geometry and borders to the active faction OS (rounded dark-teal pills for `GENESIS_V2`; sharp ink-bordered gunmetal slabs with hard offset drop shadow for `MONOLITH_OS`), while preserving category left-edge color bars (Combat Crimson, Objective Gold, Economy Cyan/Amber) so event severity reads instantly.
5. **Refactor `SelectionHUD` (`ui/hud/selection_hud.gd`):**
   * Keep 3.1's `SelectionHUD` styling visually intact (optionally delegating palette lookups to `FactionHudTheme` so all 5 HUD widgets stay in perfect lockstep).

---

## Phase B — Procedural Damage States & Shield-Shatter Feedback

### B.1 Pooled Shield-Shatter Burst (`ui/overlays/combat_vfx.gd`, `scripts/systems/vfx_pool.gd`, `scripts/systems/audio_manager.gd`)
Give shielded combat (especially `MONOLITH_OS` vs. `GENESIS_V2`) visceral, unmistakable threshold feedback when a unit or building's native shield breaks:

1. **Trigger Condition (`scripts/units/unit.gd` & `scripts/buildings/building.gd`):**
   * In `take_damage(...)`, record `var had_native_shield: bool = (current_shield > 0.001)` before subtracting Layer 2 native shield damage.
   * When `had_native_shield and current_shield <= 0.001`:
     * Spawn a pooled shield-shatter VFX via `VFXPool.acquire_combat_vfx(56)` (falling back to `CombatVFX.new()` if pool unavailable), gated on visibility (`is_friendly_view or visible` so hidden fog-of-war enemies never leak VFX/audio!).
     * Call `fx.setup_shield_shatter(global_position, radius, is_monolith_style)` where `radius` is `collision_radius * 1.25` for units and `footprint_radius * 1.05` for buildings.
     * Play procedural shatter audio: `AudioManager.play_sfx(&"shield_shatter", -4.5, 0.06, global_position, true)` (respecting camera-distance attenuation and real-time throttling).
2. **`CombatVFX.setup_shield_shatter(...)` (`ui/overlays/combat_vfx.gd`):**
   * Duration: `0.34s` (recycles cleanly to `VFXPool` on finish).
   * Visual:
     * Expanding fractured cyan-white (`#38BDF8` → `#F2EFE9`) ring that snaps open and fades out.
     * `6–8` sharp angular polygonal shard fragments flying outward along radial vectors with quick deceleration and alpha fade.
     * For `MONOLITH_OS` entities (`is_monolith_style = true`): mix in 3–4 crisp Hazard Amber / off-white halftone burst dots so the shatter matches their neo-brutalist aesthetic.
3. **Procedural Synth SFX (`scripts/systems/audio_manager.gd`):**
   * Add `&"shield_shatter"` procedural buffer: crisp crystalline high-frequency snap + rapid downward pitch sweep + brief filtered electric crackle (short ~`0.22s`, clean transient, zero clipping under the Master `AudioEffectLimiter`).

### B.2 Procedural Low-HP Damage States (`ui/overlays/entity_visuals.gd`)
Make wounded units and structures readable directly on the battlefield without needing health bars always on:

* **Thresholds:**
  * **Damaged (`HP <= 40%` and `> 20%`):** Light intermittent electrical sparks (1–2 crisp vector spark ticks) + 2 small rising translucent smoke/vapor rings.
  * **Critical (`HP <= 20%`):** Faster flickering warning sparks (2–3 jagged vector arcs + bright amber/crimson core flicker) + 3 rising dark-smoke puffs.
* **Lightweight Implementation (`ui/overlays/entity_visuals.gd`):**
  * Update `EntityVisuals._process(delta)` redraw guard for units to also include `(_owner_unit.current_hp / maxf(1.0, _owner_unit.get_max_hp())) <= 0.40` (buildings already redraw or tick cleanly).
  * Add `_draw_damage_state(hp_ratio: float, radius: float, is_mechanical: bool)` called at the end of `_draw_unit_silhouette()` and `_draw_building_completed()` (only for constructed buildings and living units when `hp_ratio <= 0.40`).
  * **Faction-Flavored Damage Detail:**
    * **Mechanical / `MONOLITH_OS` & Heavy Synthetics:** Sharp amber-white electrical arc ticks + dark charcoal oil-smoke puffs (small receding circles drifting upward via `_anim_time` phase).
    * **Organic / `GENESIS_V2` Bio-Units (`Clone Trooper`, `Stinger`, `Symbiote`):** Subtle pale bio-vapor wisps + faint emerald/crimson flicker (still crisp and understated so small infantry don't turn into visual noise).
  * Keep total primitives strictly **`<= 6` draw calls per damaged entity** so 4P FFA late-game battles stay locked at 60+ FPS.

---

## Phase C — Procedural Map Biome Identity (`scripts/world/map_biome_backdrop.gd`)

Give each of the three skirmish arenas a distinct, atmospheric procedural floor layer while maintaining maximum tactical contrast for units, selection rings, and Fog of War.

### C.1 Reusable Procedural Backdrop Node (`scripts/world/map_biome_backdrop.gd`)
Create `class_name MapBiomeBackdrop extends Node2D`:
* `@export var biome_id: StringName = &"vat_basin"` (`&"vat_basin"`, `&"twin_causeway"`, `&"quad_nexus"`)
* `@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)`
* Sets `z_index = -100` (strictly below terrain obstacles, battle scars, resource nodes, buildings, and units).
* **Zero Per-Frame CPU Cost:** Renders purely in static `_draw()` once on `_ready()` (no `_process()` animation loop needed).
* Auto-reads `arena_bounds` from the scene's `ArenaNavRegion` node if present, falling back to the exported `arena_bounds`.

### C.2 Three Distinct Biome Treatments

1. **`&"vat_basin"` — `scenes/maps/skirmish_arena_01.tscn` (*Vat Basin*):**
   * **Mood:** Clean Technozen bio-research basin — deep cool slate-teal base (`#081018`).
   * **Floor Detail:**
     * Subtle orthogonal laboratory grid (`128 px` major / `64 px` faint minor lines at `0.06–0.10` alpha).
     * Concentric organic-geometric **topographic basin contour rings** centered on the central Hyper-Uplink Plaza (`(0, 0)`) and soft circular pad contours around the two corner Vat Basins.
     * Faint diagonal bio-conduit channels connecting each main base toward the central plaza and NW/SE expansion terraces (low alpha `0.09` cyan-emerald).

2. **`&"twin_causeway"` — `scenes/maps/skirmish_arena_02.tscn` (*Twin Causeway*):**
   * **Mood:** Heavy industrial logistics causeway — matte charcoal-gunmetal deck (`#0D1014`).
   * **Floor Detail:**
     * Large rectangular **armored steel deck plating** seams (`160×120 px` offset brickwork pattern at `0.09` alpha) with tiny corner rivet dots at major plate intersections.
     * Subtle **industrial hazard striping** (muted dark amber `#FF9F1C` at `0.11` alpha) framing the central choke bridge lane and the barricade-sealed flank bypass corridors so key tactical lanes read immediately.
     * Subtle directional lane chevrons etched faintly into the causeway floor pointing toward the center objective.

3. **`&"quad_nexus"` — `scenes/maps/skirmish_arena_03.tscn` (*Quad Nexus*):**
   * **Mood:** Symmetrical Y2K sovereign mainframe arena — deep obsidian-indigo (`#090C14`).
   * **Floor Detail:**
     * Crisp **4-quadrant geometric circuit-nexus grid** radiating symmetrically from `(0, 0)` with clean 45° diagonal bus traces linking all 4 spawn corners to the central Hyper-Uplink ring.
     * Subtle concentric octagonal telemetry rings around the central plaza (`180 px`, `320 px`, `520 px`) and clean perimeter outer-corridor lane markers aligning with the 4 barricaded flank lanes.
     * Faint quadrant corner brackets marking each of the 4 spawn sectors cleanly without biasing toward any team color.

### C.3 Scene Integration
* Add a `MapBiomeBackdrop` child node (near the top of the scene tree, beneath `BattleScarsOverlay` and entities) to:
  * `scenes/maps/skirmish_arena_01.tscn` (`biome_id = &"vat_basin"`)
  * `scenes/maps/skirmish_arena_02.tscn` (`biome_id = &"twin_causeway"`)
  * `scenes/maps/skirmish_arena_03.tscn` (`biome_id = &"quad_nexus"`)
* Verify existing background `ColorRect` / floor polygons in those scenes do not obscure `MapBiomeBackdrop` (either place `MapBiomeBackdrop` immediately after the base background `ColorRect` with `z_index = -90`, or have `MapBiomeBackdrop` draw the base fill cleanly).
* Leave `scenes/test/milestone_0_test.tscn` cleanly untouched as the neutral sandbox testbed.

---

## Phase D — Verification & Playtest Checklist

1. **Full-HUD Faction OS Theming (`1280×720` Windowed & `F11` Fullscreen):**
   * Launch a skirmish as **`GENESIS_V2`**: confirm `ResourceHUD`, `ProductionTicker`, `TacticalMinimap`, `TacticalEventFeed`, and `SelectionHUD` all share the cohesive rounded Technozen cyan/emerald glass aesthetic with zero clipping or overlap.
   * Launch a skirmish as **`MONOLITH_OS`**: confirm all 5 HUD widgets switch cleanly to the sharp Neo-Brutalist gunmetal/concrete + thick dark-ink + Hazard Amber bracket + halftone aesthetic with zero clipping or overlap.
   * Launch an **AI-vs-AI Spectator** match: confirm the HUD renders cleanly in the neutral Spectator Terminal theme without errors.
2. **Shield-Shatter & Low-HP Damage Juice:**
   * In `milestone_0_test.tscn` or a `MONOLITH_OS` vs. `GENESIS_V2` skirmish, focus-fire a `Bulwark Automaton`, `Monolith Dreadnought`, and `Foundry Core`:
     * Verify the crisp cyan/amber **shield-shatter burst VFX** and procedural **`shield_shatter` SFX** fire once at the exact moment native shield hits `0` (and do **not** spam while taking hull damage at `0` shield).
     * Verify `VFXPool` recycles shield-shatter bursts cleanly with zero leaked nodes across Rematch / Main Menu transitions.
     * Drop both a `GENESIS_V2` and `MONOLITH_OS` unit/building below `40%` HP and below `20%` HP: confirm procedural sparks/smoke scale visibly across both thresholds and clear immediately when repaired/healed above `40%`.
     * Confirm enemy units/buildings hidden in Fog of War never emit visible shield-shatter bursts or damage sparks.
3. **Map Biome Identity & Contrast:**
   * Load all three arenas (`skirmish_arena_01`, `02`, `03`): confirm each map displays its distinct procedural biome floor (*Vat Basin* contours, *Twin Causeway* industrial plating & hazard lanes, *Quad Nexus* 4-way circuit nexus) cleanly below `BattleScarsOverlay`, `FogOfWar`, landmarks, units, and selection rings.
   * Run a 4P FFA Spectator match on `skirmish_arena_03.tscn` at `2x` speed and verify smooth frame pacing with zero console errors or warnings.