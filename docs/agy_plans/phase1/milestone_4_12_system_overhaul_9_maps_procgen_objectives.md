# Milestone 4.12 — System Overhaul #9: Next-Gen Maps, ProcGen & Objectives

**Prerequisite:** Milestone 4.11 (System Overhaul #8: Skirmish AI Commander) verified and working cleanly.

**Goal:** Overhaul procedural map generation, biome floor alignment, `HyperUplink`, and `SalvageCore` into a varied, fog-safe, high-performance objective and map pipeline across 2P, 3P FFA, and 4P matches:

1. **4 Distinct Procedural Map Archetypes & Inter-Node Spacing Guard (`ProceduralArenaGenerator`, `GameConfig`, `MainMenu`):** Expand procedural generation beyond a single layout template with 4 selectable tactical archetypes (`Open Macro`, `Twin Ridges`, `Bridge Chokepoints`, `Triad Observatory`, plus `Auto`) while keeping blind in-match scouting intact (zero lobby minimap preview), and enforce a `64 px` minimum inter-node spacing guard after arena-border clamping so corner resources never stack.

2. **Dynamic Anchor-Aware `MapBiomeBackdrop` (`scripts/world/map_biome_backdrop.gd`):** Replace hardcoded static arena coordinates with live reads of `spawn_anchors`, `hyper_uplinks`, and `destructible_barricades` (falling back cleanly to hand-crafted coordinates on static maps) so base pads, bio-conduits, circuit bus traces, and hazard strips align 1:1 with real bases on every procedural seed, plus subtle recessed perimeter framing.

3. **Combat-Only, Fog-Safe, Throttled `HyperUplink` (`scripts/world/hyper_uplink.gd`):** Restrict `HyperUplink` capture and contesting strictly to **combat units** (workers, harvesters, and engineers cannot capture or contest), move occupancy polling into `_physics_process()` at `0.15s` cadence, gate `queue_redraw()` to on-screen visibility, cache last-known fog state so `get_inspection_data()` never leaks live enemy capture progress through Fog of War, and format capture alerts dynamically from `production_bonus_pct`.

4. **Viewport-Culled, Faction-Agnostic `SalvageCore` (`scripts/world/salvage_core.gd`):** Skip off-screen and fog-hidden `queue_redraw()` calls while keeping decay timers deterministic, strip hardcoded `&"engineer"` IDs in favor of `can_staff_compute` / `&"engineer"` tags, and add a subtle pulsing extraction ring while channeling.

**Hard Design Guardrails (MUST PRESERVE):**

* **Blind Scouting & Discovery:** Do **not** add a pre-match procedural minimap preview to the lobby. Players must scout landmarks, chokepoints, high-ground ridges, and expansions in-match.

* **Strict Symmetry & Wide Assault Ramps:** Preserve exact 2-way (`180°`), 3-way (`120°`), and 4-way quadrant symmetry and `180–220 px` wide assault ramps across all procedural archetypes.

* **Combat-Only Hyper-Uplink:** Only units with `data.is_combat_unit() == true` can capture or contest `HyperUplink`.

* **Zero Stealth / Zero Auto-Formations / Zero Balance Stat Changes.**

## Phase A — Procedural Map Archetypes & Inter-Node Spacing Guard

### A.1 Archetype Config & Lobby Selector (`scripts/systems/game_config.gd`, `ui/menus/main_menu.gd`)

1. **`GameConfig`:**

   * Add `var proc_map_archetype: StringName = &"auto"` supporting:

     * `&"auto"` (seed-selected from the 4 archetypes)

     * `&"open_macro"` (Open Macro)

     * `&"twin_ridges"` (Twin Ridges)

     * `&"bridge_chokes"` (Bridge Chokepoints)

     * `&"triad_observatory"` (Triad Observatory)

2. **`MainMenu` (Procedural Arena Panel):**

   * Add a compact **Archetype** `OptionButton` alongside Biome / Chokes / High Ground / Richness (strictly **no** minimap preview widget), persisting selection cleanly to `GameConfig.proc_map_archetype`.

### A.2 Archetype-Driven Generation & Spacing Guard (`scripts/world/procedural_arena_generator.gd`)

1. **Resolve Archetype Deterministically:**

   * Add `const ARCHETYPE_POOL: Array = [&"open_macro", &"twin_ridges", &"bridge_chokes", &"triad_observatory"]` and `var generated_archetype: StringName = &"open_macro"`.

   * In `generate_arena()`: if `GameConfig.proc_map_archetype != &"auto"`, use it directly; otherwise select deterministically from `ARCHETYPE_POOL` via `_rng` (biasing `&"triad_observatory"` when `_symmetry_count == 3`).

2. **Distinct Tactical Geometry per Archetype:**

   * **`open_macro`:**

     * Wider base-to-center sightlines, reduced monolith count (`maxi(1, chokes)` clusters), generous High-Yield mid/flank expansion pockets, and 1 optional outer ridge when `hg_level >= 1`.

   * **`twin_ridges`:**

     * Guarantees paired dominant mid-field high-ground plateaus (`set_i = 0` forced even if `hg_level == 0` when explicitly selected, or 2 paired sets on `hg_level >= 1`) positioned to overlook the central Hyper-Uplink approach with dual `195–215 px` wide assault ramps.

   * **`bridge_chokes`:**

     * Spawns a structured pair of symmetric central causeway framing walls flanking `(0,0)` (leaving a generous `280–340 px` central bridge corridor cleanly open) plus guaranteed outer flank `DestructibleBarricade` bypasses.

   * **`triad_observatory`:**

     * Emphasizes radial mid-flank high-yield flashpoints, symmetric flank `SensorRelays`, and radial monolith cover arcs around the central observatory ring.

3. **Inter-Node Resource Spacing Guard (`_place_mirrored_resource`, `_spawn_single_resource`):**

   * Add helper `func _resolve_spaced_resource_pos(raw_pos: Vector2, margin: float, min_gap: float = 64.0) -> Vector2`:

     * Clamps `raw_pos` inside `generated_bounds` via `_clamp_inside_arena(raw_pos, margin)`.

     * Checks distance against all already-placed `_resource_positions`; if any existing node is within `min_gap`, nudges outward/tangentially in `8` small steps (`min_gap + 6.0`) inside `generated_bounds` so corner-clamped mineral arcs never overlap or stack on top of each other.

## Phase B — Dynamic Anchor-Aware `MapBiomeBackdrop` (`scripts/world/map_biome_backdrop.gd`)

1. **Live Anchor Collection (`_collect_dynamic_anchors()`):**

   * Add cached arrays populated in `_ready()` and refreshed on `queue_redraw()` / `refresh_anchors()`:

     * `_spawn_pts: Array[Vector2]` — read from `get_tree().get_nodes_in_group("spawn_anchors")` (falling back to each biome's classic hand-crafted coordinates if the group is empty!).

     * `_uplink_pt: Vector2` — read from `get_tree().get_first_node_in_group("hyper_uplinks")` (fallback `Vector2.ZERO`).

     * `_barricade_pts: Array[Dictionary]` — position + rotation of `destructible_barricades` (used by `twin_causeway` and `quad_nexus` to align hazard strips/gate alignment ticks directly under real barricades).

   * Update `ProceduralArenaGenerator._finalize_systems()` to call `backdrop.call("refresh_anchors")` right after all spawns, barricades, and uplinks are added so procedural maps get exact floor-to-base alignment on Frame 1!

2. **Anchor-Aligned Biome Treatments:**

   * **`vat_basin`:** Draw base pad contours and bio-conduit channels connecting each actual `_spawn_pts[i]` → `_uplink_pt` (instead of hardcoded `±900, ±560`).

   * **`twin_causeway`:** Draw industrial base pad frames around each actual `_spawn_pts[i]` and hazard warning strips aligned to actual `_barricade_pts` (falling back to classic coordinates on `skirmish_arena_02.tscn`).

   * **`quad_nexus`:** Draw neutral spawn sector brackets around each actual `_spawn_pts[i]` and diagonal circuit bus traces from each spawn corner toward `_uplink_pt`.

   * **`triad_sanctum`:** Draw 120° (or N-way) radial meridian lines and sanctum pad rings aligned to each actual `_spawn_pts[i]` around `_uplink_pt`.

3. **Zero-Cost Perimeter Depth Framing (`_draw_arena_perimeter_frame()`):**

   * At the end of `_draw()`, render a crisp subtle recessed perimeter border + `256 px` coordinate tick marks along `arena_bounds` so map edges read cleanly on every biome without hurting unit silhouette contrast.

## Phase C — Combat-Only, Fog-Safe, Throttled `HyperUplink` (`scripts/world/hyper_uplink.gd`)

### C.1 Combat-Only Capture & Contest Eligibility

* Move occupancy evaluation out of `_process(delta)` (60 Hz) into **`_physics_process(delta)`** on a clean **`SCAN_INTERVAL = 0.15`** cadence (accumulating `step_dt` so `capture_time = 8.0s` stays 100% exact).

* Inside occupancy evaluation, filter `SpatialGrid` candidates strictly to **living combat units**:

  ```
  if unit.is_dead or unit.is_staffed or unit.is_queued_for_deletion():
      continue
  if unit.data == null or not unit.data.is_combat_unit():
      continue
  
  ```

  * Workers, Silica Harvesters, and Compute Specialists/Engineers can no longer capture or contest `HyperUplink`.

* Update `get_inspection_data()` `"readonly_label"` to `"STRATEGIC OBJECTIVE — CAPTURE WITH COMBAT UNITS"`.

### C.2 Fog-Safe Inspection, Dynamic Bonus Alerts & Viewport-Gated Redraws

1. **Last-Known Fog State Cache (Zero Fog Leaks):**

   * Cache viewer-visible state fields:

     * `var _fog_cache: FogOfWarSystem = null`

     * `var _last_known_controller: int = -1`

     * `var _last_known_capturing: int = -1`

     * `var _last_known_progress: float = 0.0`

     * `var _last_known_contested: bool = false`

     * `var _last_known_occupants: int = 0`

   * Add `func is_live_visible_to_viewer() -> bool` (returns `true` if spectator mode, `_fog_cache == null`, `not _fog_cache.fog_enabled`, or `_fog_cache.is_world_pos_visible_strict(global_position)`).

   * Whenever `is_live_visible_to_viewer()` is `true`, sync `_last_known_*` from live state.

   * In `get_inspection_data()`: read strictly from live state when `is_live_visible_to_viewer()` else from `_last_known_*` (appending `" (LAST KNOWN)"` to status/subtitle when outside live vision so inspecting a fogged Hyper-Uplink never leaks live enemy capture % or unit counts!).

2. **Dynamic Bonus Percentage Alerts:**

   * In `_set_controller(next_team)`: compute `var pct_int: int = int(round(production_bonus_pct * 100.0))` and format `"Hyper-Uplink Captured (+%d%%)" % pct_int` and `"%s Captured Hyper-Uplink (+%d%%)" % [team_tag, pct_int]` instead of hardcoded `+5%`.

3. **Viewport-Gated `_process()` & Crisp Contest Visuals:**

   * In `_process(delta)`: advance `_pulse_time += delta`; only call `queue_redraw()` when `global_position` is within the active `Camera2D` world rect (padded by `capture_radius + 80.0`) or `is_selected` / `is_hovered`.

   * In `_draw()`: when `is_contested` (and live visible), render an alternating segmented warning ring around `capture_radius` so contested clashes read instantly at a glance.

## Phase D — Viewport-Culled, Faction-Agnostic `SalvageCore` (`scripts/world/salvage_core.gd`)

1. **Deterministic Decay & Viewport/Fog-Culled Redraws:**

   * Move `remaining_lifetime` countdown into `_physics_process(delta)` so salvage expiration stays deterministic with simulation ticks.

   * In `_process(delta)`: advance `_anim_time += delta`; skip `queue_redraw()` completely when `not visible` (hidden in unexplored fog) or outside the active `Camera2D` world rect (padded by `+64 px`).

2. **Faction-Agnostic Extractor Speed & Channeling Ring:**

   * In `advance_extraction(extractor, delta)`: replace `u.get_unit_type_id() == &"engineer"` with **`u.data.can_staff_compute or u.data.has_tag(&"engineer")`** so `Systems Engineer`, `Grid-Tech`, `Cantor`, and future Faction #4/#5 specialists all extract at the `1.8s` specialist rate automatically.

   * When `extraction_progress > 0.01`, draw a subtle animated inner energy ring pulsing inward to clearly communicate active extraction.

## Phase E — Verification & Stress-Test Checklist

1. **Zero Errors & Clean Boot Audit:**

   * Launch Godot (`F5`): confirm **0 parse errors**, **0 runtime errors**, and **0 `FactionAudit:` warnings**.

2. **Procedural Map Archetypes, Blind Scouting & Floor Alignment:**

   * Open Main Menu → Procedural Arena: confirm **no minimap preview** is shown (blind scouting preserved) and the new **Archetype** selector (`Auto`, `Open Macro`, `Twin Ridges`, `Bridge Chokepoints`, `Triad Observatory`) works cleanly.

   * Launch matches across all 4 archetypes in **2P**, **3P FFA**, and **4P FFA**:

     * Confirm distinct tactical layouts per archetype, exact symmetry, wide `180–220 px` assault ramps, and `>= 64 px` spacing on all corner-clamped mineral arcs.

     * Confirm `MapBiomeBackdrop` base pads, bio-conduits, circuit traces, and hazard strips align cleanly to the actual procedural spawns and barricades (and remain 100% intact on hand-crafted `skirmish_arena_01–04.tscn`).

3. **Combat-Only, Fog-Safe `HyperUplink`:**

   * Move `3×` Workers / Harvesters / Engineers into the neutral `HyperUplink` ring: confirm **0% capture progress** and **no contest** against an enemy combat unit.

   * Move a combat unit into the ring: confirm smooth capture over `8.0s`, dynamic `+%d%%` alert text, and crisp segmented contest ring when opposing combat units clash inside.

   * Pull units away so `HyperUplink` drops into `EXPLORED` fog and **left-click to inspect it**: confirm `SelectionHUD` shows last-known intel without leaking live enemy capture % or unit counts.

4. **`SalvageCore` Performance & Faction Parity:**

   * Destroy heavy units across `GENESIS_V2`, `MONOLITH_OS`, and `PRISMA_DEI`: confirm `SalvageCore`s decay accurately even off-screen, skip off-screen/fogged redraws, and extract in `1.8s` for all faction Compute Specialists (`Systems Engineer`, `Grid-Tech`, `Cantor`) and `2.5s` for standard workers.