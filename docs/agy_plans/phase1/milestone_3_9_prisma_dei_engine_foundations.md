# Milestone 3.9 — `PRISMA_DEI` Engine Foundations (Power Lattice, Optical Tethers & Beam Weapons)

**Prerequisite:** Milestones 3.7 (Modular Faction Architecture Refactor) and 3.8 (SC2 High-Ground FoW & Wide Ramps) verified and working cleanly.

**Goal:** Build and verify the three core engine systems required by **Faction #3 (`03 // PRISMA_DEI — The Divine Lattice`)** cleanly, generically, and data-driven *before* authoring Faction #3's roster in Milestone 4.0:

1. **Consecrated Power Lattice (`BuildingData`, `Building`, `CommandRouter`, `BuildGhostPreview`, `AIBuildPlanner`):** Support power-providing structures (`provides_power_grid`, `power_radius`) and power-dependent structures (`requires_power_grid`) built via **standard worker construction** (workers physically build scaffolds—no remote Protoss-style warp-in). If all overlapping power providers are lost, dependent structures enter an **Unpowered / Dormant** state (pausing training, research, turrets, Compute staffing, and tether emission) until repowered.
2. **Optical Tether Network (*Harmonic Communion* — `OpticalTetherSystem`, `OpticalTetherOverlay`, `StatusEffectComponent`):** `SpatialGrid`-backed link graph projecting visible gold/magenta hard-light tethers from emitter units/buildings to nearby allied combat units, granting stack-capped fire-rate, attack-range, and beam-ramp bonuses that snap immediately when out of range or when the anchor emitter is killed.
3. **Escalating Continuous Beams & Refracting Split-Beams (`UnitData`, `CombatComponent`, `AttackTracer`, `CombatVFX`, `AudioManager`):** Data-driven support for continuous ramp-up beams (rewarding sustained uptime on heavy targets) and refracting chain-split beams (bouncing reduced damage onto 1–2 adjacent enemies around the primary target).

**Hard Design Guardrails (MUST PRESERVE):**
* **Standard Worker Construction Only:** Workers must physically move to and construct lattice-dependent buildings; do **not** implement remote/workerless warp-in construction.
* **Zero Premature Faction #3 Assets in Main Menu:** Do **not** register `prisma_dei_faction.tres` yet; `MainMenu` must remain cleanly at `2 / 5 ACTIVE` (`GENESIS_V2` and `MONOLITH_OS`) until Milestone 4.0.
* **Zero Balance Changes & Zero Regressions:** Do not modify any `GENESIS_V2` or `MONOLITH_OS` stats, visuals, or behaviors.
* **Zero Skill-Cap Automation:** No overkill-prevention targeting automation; no auto-loop production; no stealth/cloaking; no role-sorted squad formations.
* **100% Procedural Pipeline & 4P FFA Performance Guard:** All lattice rings, tether beams, prism tracers, and crystalline SFX must be procedural, pooled via `VFXPool` where transient, and strictly Fog-of-War visibility-gated.

---

## Phase A — Consecrated Power Lattice & Unpowered Dormancy

### A.1 Schema Exports (`scripts/data/building_data.gd` & `scripts/buildings/building.gd`)

1. **`scripts/data/building_data.gd`:** Add under a new `# Optional Consecrated Power Lattice & Optical Tether (Milestone 3.9)` section:
   ```gdscript
   @export var provides_power_grid: bool = false
   @export var power_radius: float = 0.0
   @export var requires_power_grid: bool = false
   @export var tether_emit_radius: float = 0.0
   @export var tether_max_links: int = 0
   @export var tether_fire_rate_bonus: float = 0.0
   @export var tether_range_bonus: float = 0.0
   @export var tether_beam_ramp_bonus: float = 0.0
   ```
2. **`scripts/buildings/building.gd`:**
   * Add matching `@export` properties (`provides_power_grid`, `power_radius`, `requires_power_grid`, `tether_emit_radius`, `tether_max_links`, `tether_fire_rate_bonus`, `tether_range_bonus`, `tether_beam_ramp_bonus`) and runtime state `var is_powered: bool = true`.
   * Add `func _sync_lattice_and_tether_from_data(data: BuildingData, force_overwrite: bool = false) -> void` and call it in both `_ready()` and `begin_construction()` right alongside `_sync_defense_and_overclock_from_data(...)`.

### A.2 Team Power Lattice Queries & State Transitions (`scripts/buildings/building.gd`)

Mirror the exact `SpatialGrid` pattern already used in `Building.get_shield_regen_delay_speedup_at(...)`:

1. **`static func is_position_powered_for_team(tree: SceneTree, world_pos: Vector2, target_team: int, exclude_building: Building = null) -> bool`:**
   * Queries `SpatialGrid.query_buildings_in_radius(world_pos, 480.0)` (fallback `tree.get_nodes_in_group("buildings")`).
   * Returns `true` if any building `b` satisfies:
     * `is_instance_valid(b)`, `b != exclude_building`, `not b.is_destroyed`, `b.is_constructed`, `not b.is_salvaging`,
     * `int(b.team) == target_team` *(strictly same team so each player manages their own lattice)*,
     * `b.provides_power_grid and b.power_radius > 0.0`,
     * `world_pos.distance_squared_to(b.global_position) <= b.power_radius * b.power_radius`.
2. **`static func refresh_team_power_grid(tree: SceneTree, target_team: int, exclude_building: Building = null) -> void`:**
   * Iterates all constructed, non-destroyed buildings of `target_team` where `b.requires_power_grid == true`.
   * Recomputes `var next_powered: bool = Building.is_position_powered_for_team(tree, b.global_position, target_team, exclude_building)`.
   * On transition (`next_powered != b.is_powered`):
     * Updates `b.is_powered = next_powered`, calls `b.queue_redraw()`, and emits `b.status_changed.emit(b)`.
     * If `not next_powered` and `TeamManager.is_team_controlled_by_local_human(target_team)`: push a throttled tactical alert via `MatchManager.push_tactical_alert(b.global_position, &"under_attack", "%s Unpowered!" % b.display_name)`.
3. **Lifecycle Hooks in `Building`:**
   * In `_ready()` (if `is_constructed`) and `_complete_construction()`:
     * If `requires_power_grid`: evaluate `is_powered = Building.is_position_powered_for_team(get_tree(), global_position, int(team))`.
     * If `provides_power_grid`: call `Building.refresh_team_power_grid(get_tree(), int(team))`.
   * In `start_salvage()` and `cancel_salvage()`: if `provides_power_grid`, call `Building.refresh_team_power_grid(get_tree(), int(team))`.
   * In `_destroy()` and `_exit_tree()`: if `provides_power_grid`, call `Building.refresh_team_power_grid(get_tree(), int(team), self)`.
4. **Dormant / Unpowered Gating (Clean Pause, No Data Loss):**
   * In `_process(delta)`:
     * Gate `_tick_compute_generation(delta)`, `production_component.tick(self, delta)`, and `turret_component.tick(delta)` on **`is_powered`**. *(Active training/research queues pause gracefully in place rather than canceling; progress resumes automatically once a replacement power spire finishes!)*
   * In `can_train_unit(...)`, `can_train_unit_data(...)`, `can_research_upgrade(...)`, `can_cast_overclock()`, and `is_actively_producing()`: return `false` when `not is_powered`.
   * **Always Allowed While Unpowered:** `cancel_queued_unit`, `cancel_last_queued`, `eject_engineers`, `toggle_salvage`, `repair`, `take_damage`, `set_rally_*`, and worker construction progress (`advance_construction`) on unfinished scaffolds.
   * **Visuals & Inspection (`Building._draw()` & `get_inspection_data()`):**
     * When `is_selected and is_constructed and provides_power_grid and power_radius > 0.0`: draw a crisp geometric Bauhaus gold/magenta power lattice ring (`Color(0.98, 0.80, 0.08, 0.44)` dashed ring + `Color(0.85, 0.27, 0.94, 0.045)` soft interior wash + small diamond cardinal nodes).
     * When `is_constructed and requires_power_grid and not is_powered`: draw a pulsing magenta/amber `"UNPOWERED"` slash-diamond badge centered over the building and slightly dim `body_visual.modulate` (`Color(0.68, 0.62, 0.74, 1.0)`).
     * In `get_inspection_data()`: if `requires_power_grid and not is_powered`, append `{"label": "Lattice", "value": "UNPOWERED — Build Power Spire", "color": Color(1.0, 0.36, 0.48, 1.0)}` and set subtitle to `"UNPOWERED STRUCTURE"`.

### A.3 Placement Validation, Ghost Lattice Overlay & AI Placement Hook

1. **`scripts/controllers/command_router.gd` (`evaluate_build_placement`):**
   * Before the final `result["valid"] = true` return, add:
     ```gdscript
     if building_data.requires_power_grid:
         if not Building.is_position_powered_for_team(get_tree(), place_pos, int(target_team)):
             result["reason"] = "Requires Power Lattice"
             return result
     ```
2. **`ui/overlays/build_ghost_preview.gd` (`_draw()`):**
   * Add helper `_draw_power_lattice_preview(origin: Vector2)` called right after section `2.5` whenever `building_data.requires_power_grid` or `building_data.provides_power_grid`:
     * Iterate all friendly constructed `provides_power_grid` buildings (`int(b.team) == local_team`) and draw their crisp gold/magenta `power_radius` rings + subtle low-alpha fill so the player sees their entire valid consecrated build zone immediately.
     * If `building_data.provides_power_grid and building_data.power_radius > 0.0`: draw the ghost's own projected `power_radius` ring and crisp golden link lines to any currently **Unpowered** friendly buildings inside `power_radius` that placing this spire would restore!
     * If `building_data.requires_power_grid`: draw a crisp gold tether line from `origin` to the nearest covering power provider when valid (or a crimson dashed warning line when outside the lattice).
3. **`scripts/systems/ai_build_planner.gd`:**
   * In candidate build spot search, when planning a building with `b_data.requires_power_grid`: sample candidate spots around constructed friendly `provides_power_grid` buildings (within `power_radius - b_data.get_footprint_radius() - 12.0`), and if no valid powered spot exists, prioritize building a `provides_power_grid` supply/lattice structure first.

---

## Phase B — Optical Tether Network (*Harmonic Communion*)

### B.1 Schema Exports (`scripts/data/unit_data.gd`)

Add `# Optional Optical Tether Emitter (Milestone 3.9)` exports to `UnitData`:
```gdscript
@export var tether_emit_radius: float = 0.0
@export var tether_max_links: int = 0
@export var tether_fire_rate_bonus: float = 0.0
@export var tether_range_bonus: float = 0.0
@export var tether_beam_ramp_bonus: float = 0.0
```

### B.2 Status Effect & Unit Stat Hooks (`scripts/units/status_effect_component.gd`, `scripts/units/unit.gd`, `scripts/ui/inspection_helper.gd`)

1. **`scripts/units/status_effect_component.gd`:**
   * Support `&"optical_tether"` payload keys:
     * `"attack_speed_mult"` (existing or multiplicative with `get_attack_cooldown_multiplier()` — e.g. `1.0 / (1.0 + total_fire_rate_bonus)`),
     * `"bonus_attack_range"` (`float`, summed cleanly into new `func get_bonus_attack_range() -> float`),
     * `"beam_ramp_speed_mult"` (`float`, summed cleanly into new `func get_beam_ramp_speed_multiplier() -> float`, default `1.0`),
     * `"tether_stacks"` (`int`, exposed via `func get_optical_tether_stacks() -> int`).
2. **`scripts/units/unit.gd`:**
   * In `get_effective_attack_range()`: add `status_effect_component.get_bonus_attack_range()` when `status_effect_component != null` (only if base attack range `> 0.0`).
   * Add helper `func get_effective_beam_ramp_speed_multiplier() -> float` returning `status_effect_component.get_beam_ramp_speed_multiplier()` if present else `1.0`.
   * Add helper `func get_optical_tether_stacks() -> int`.
3. **`scripts/ui/inspection_helper.gd`:**
   * When inspecting any unit with `u.get_optical_tether_stacks() > 0`, append a crisp Liturgical Gold telemetry row: `{"label": "Lattice Link", "value": "x%d Active" % stacks, "color": Color(0.98, 0.80, 0.14, 1.0)}`.

### B.3 `OpticalTetherSystem` & `OpticalTetherOverlay`

1. **`scripts/systems/optical_tether_system.gd` (`class_name OpticalTetherSystem extends Node`):**
   * Added to group `"optical_tether_system"`; instanced automatically by `MatchManager` on every match/sandbox scene (same pattern as `HitFeedbackOverlay`).
   * Constant `const MAX_TETHER_STACKS: int = 2` (hard cap per recipient unit to prevent degenerate stacking) and `const UPDATE_INTERVAL: float = 0.20`.
   * Every `0.20s`:
     * Collect all active emitters:
       * Living, non-staffed `Unit`s with `data != null and data.tether_emit_radius > 0.0 and data.tether_max_links > 0`.
       * Constructed, non-destroyed, non-salvaging, **`is_powered`** `Building`s with `tether_emit_radius > 0.0 and tether_max_links > 0`.
     * Fast exit if `emitters.is_empty()` (zero CPU cost in pure `GENESIS_V2` vs. `MONOLITH_OS` matches!).
     * For each emitter (sorted deterministically by `get_instance_id()`):
       * Query `SpatialGrid.query_units_in_radius(emitter.global_position, emit_r)`.
       * Filter to living, non-staffed allied combat units (`u != emitter`, `u.data != null and u.data.is_combat_unit()`, `TeamManager.are_allies(emitter_team, int(u.team))`, current stacks `< MAX_TETHER_STACKS`).
       * Sort candidates by `(current_stacks ascending, distance_squared ascending)` so tethers distribute cleanly across a squad before double-stacking.
       * Claim up to `tether_max_links` recipients, accumulating each recipient's total `fire_rate_bonus`, `range_bonus`, `beam_ramp_bonus`, and `stacks`, and recording `{ "from": emitter, "to": recipient, "team": emitter_team, "stacks": next_stacks }` in `active_links`.
     * For each linked recipient, apply/refresh `status_effect_component.apply_effect(&"optical_tether", { ... }, 0.45)` (short `0.45s` TTL guarantees instant graceful drop when an emitter dies or moves out of range).
2. **`ui/overlays/optical_tether_overlay.gd` (`class_name OpticalTetherOverlay extends Node2D`):**
   * `z_index = 46` (cleanly above ground/plateaus and below units/tracers).
   * Only animates and redraws when `tether_system.active_links` is non-empty (zero idle cost when no emitters exist).
   * For each active link `(from_node, to_node)`:
     * **Strict Fog-of-War Gate:** Skip drawing if both `from_node` and `to_node` are hidden from the local viewer (`not from_node.visible and not to_node.visible` when Fog is ON and not Spectator Mode).
     * Render a crisp translucent Ultraviolet Magenta outer glow (`Color(0.85, 0.27, 0.94, 0.28)`, `3.4 px`), a razor-thin Liturgical Gold hairline core (`Color(0.98, 0.80, 0.14, 0.78)`, `1.3 px`), small diamond anchor pips at both endpoints, and 1–2 animated geometric diamond pulses flowing smoothly from `from_node` → `to_node`.

---

## Phase C — Escalating Continuous Beams & Refracting Split-Beams

### C.1 Weapon Schema Exports (`scripts/data/unit_data.gd`)

Add `# Optional Beam & Refraction Weapon Profile (Milestone 3.9)` exports to `UnitData`:
```gdscript
@export var is_continuous_beam: bool = false
@export var beam_ramp_max_multiplier: float = 1.0
@export var beam_ramp_duration: float = 3.5
@export var beam_ramp_decay_delay: float = 0.6
@export var beam_ramp_decay_rate: float = 1.5
@export var refract_max_bounces: int = 0
@export var refract_radius: float = 135.0
@export var refract_damage_ratio: float = 0.50
```

### C.2 Continuous Ramp-Up & Refraction Logic (`scripts/units/combat_component.gd` & `scripts/units/unit.gd`)

1. **Ramp State on `CombatComponent` (`scripts/units/combat_component.gd`):**
   * Add state fields:
     * `var _beam_lock_target: Node2D = null`
     * `var _beam_ramp_elapsed: float = 0.0`
     * `var _beam_grace_timer: float = 0.0`
   * Add `func get_beam_ramp_ratio(owner_unit: Unit) -> float`: returns `clampf(_beam_ramp_elapsed / maxf(0.1, owner_unit.data.beam_ramp_duration), 0.0, 1.0)` when `owner_unit.data.is_continuous_beam and owner_unit.data.beam_ramp_max_multiplier > 1.0`, else `0.0`.
   * Add `func tick_beam_decay(owner_unit: Unit, delta: float) -> void` called alongside `tick_cooldown(delta)` in `Unit`:
     * If `_beam_lock_target == null` and `_beam_ramp_elapsed <= 0.0`: return immediately.
     * Check if still actively locked (`is_instance_valid(_beam_lock_target)`, `owner_unit.current_target == _beam_lock_target`, `is_within_attack_envelope(owner_unit, _beam_lock_target)`, and not moving away).
     * If not locked: tick down `_beam_grace_timer`; once `<= 0.0`, decay `_beam_ramp_elapsed = maxf(0.0, _beam_ramp_elapsed - owner_unit.data.beam_ramp_decay_rate * delta)`. When `_beam_ramp_elapsed <= 0.0`, clear `_beam_lock_target = null`.
   * In `cancel_attack_animation()`: do *not* instantly wipe `_beam_ramp_elapsed` (let `_beam_grace_timer` handle brief micro-hesitations cleanly, while explicitly switching targets in `_execute_weapon_shot` resets `_beam_ramp_elapsed = 0.0`).
2. **Escalating Beam Execution in `CombatComponent._execute_weapon_shot(owner_unit, target_node)`:**
   * When `owner_unit.data.is_continuous_beam`:
     * If `target_node == _beam_lock_target`:
       * Advance `_beam_ramp_elapsed = minf(owner_unit.data.beam_ramp_duration, _beam_ramp_elapsed + owner_unit.get_effective_attack_cooldown() * owner_unit.get_effective_beam_ramp_speed_multiplier())`.
     * Else:
       * `_beam_lock_target = target_node`
       * `_beam_ramp_elapsed = 0.0`
     * `_beam_grace_timer = owner_unit.data.beam_ramp_decay_delay`
     * Compute `var ramp_t: float = get_beam_ramp_ratio(owner_unit)` and `var ramp_mult: float = lerpf(1.0, maxf(1.0, owner_unit.data.beam_ramp_max_multiplier), ramp_t)`.
     * Scale `base_dmg *= ramp_mult` (and `bonus_armored *= ramp_mult`).
     * Spawn `AttackTracer.TracerStyle.PRISM_BEAM` with duration `owner_unit.get_effective_attack_cooldown() + 0.07`, live node tracking (`from_node = owner_unit`, `to_node = target_node`, `from_offset = muzzle_offset`), and `intensity = ramp_t` so consecutive ticks fuse into a seamless, smoothly tracking, intensifying hard-light beam!
     * Apply primary damage via `_apply_damage_to_target(owner_unit, target_node, base_dmg, bonus_armored)`.
     * If `owner_unit.data.refract_max_bounces > 0`: invoke `_apply_refract_split_damage(owner_unit, target_node, base_dmg, bonus_armored, shot_col)`.
     * Return `true`.
   * Also allow **non-continuous** weapons with `refract_max_bounces > 0` (e.g., crisp snap-beam Prism skirmishers) to trigger `_apply_refract_split_damage(...)` right after their primary hit!
3. **Refracting Split-Beam Helper (`CombatComponent._apply_refract_split_damage`):**
   * Queries `SpatialGrid.query_units_in_radius(primary_target.global_position, refract_r)` (plus nearby hostile buildings if slots remain).
   * Filters via `can_target_entity(owner_unit, cand)` and `cand != primary_target`.
   * Sorts by distance to `primary_target.global_position` ascending and selects up to `owner_unit.data.refract_max_bounces` secondary targets.
   * For each secondary target:
     * Calls `_apply_damage_to_target(owner_unit, sec_target, base_dmg * refract_ratio, bonus_armored * refract_ratio)`.
     * Spawns a pooled `AttackTracer.TracerStyle.PRISM_REFRACT` tracer from `primary_target.global_position` → `sec_target.global_position` (respecting `_is_point_visible_local`).

### C.3 Hard-Light Beam Tracer Styles & Crystalline Audio (`ui/overlays/attack_tracer.gd`, `scripts/systems/audio_manager.gd`)

1. **`ui/overlays/attack_tracer.gd`:**
   * Extend `enum TracerStyle` with `PRISM_BEAM = 8` and `PRISM_REFRACT = 9`.
   * Add pool-resettable fields: `_from_node: Node2D = null`, `_to_node: Node2D = null`, `_from_offset: Vector2 = Vector2.ZERO`, `_beam_intensity: float = 0.0`.
   * Add helper `func attach_live_endpoints(from_node: Node2D, to_node: Node2D, intensity: float = 0.0, muzzle_dist: float = 0.0) -> void` (called cleanly right after `setup(...)`, keeping existing `setup(...)` signature 100% backward-compatible!).
   * In `_draw()`: if `_from_node` / `_to_node` are valid, refresh `start_world` / `end_world` live each frame so `PRISM_BEAM` stays locked cleanly onto moving units!
   * **Render `PRISM_BEAM`:**
     * Width and luminance scale smoothly with `_beam_intensity` (`0.0 → 1.0`): outer Ultraviolet Magenta glow (`#D946EF`), crisp Liturgical Gold mid-beam (`#FACC15`), and blinding white inner filament that widens from `1.2 px` to `3.6 px` at max ramp.
     * Draw 2–3 tiny rotated diamond focus-lens frames spaced along the beam + a hot geometric starburst at `p1` (respecting `_hide_origin_muzzle` for SC2 high-ground fog rules!).
   * **Render `PRISM_REFRACT`:**
     * Crisp crystalline gold-white split ray with a sharp diamond prism-refraction glint at the bounce vertex `p0` and bright magenta-white impact flash at `p1`.
   * Clear `_from_node = null`, `_to_node = null`, `_beam_intensity = 0.0`, `_from_offset = Vector2.ZERO` in `reset_for_pool()`.
2. **`scripts/systems/audio_manager.gd`:**
   * Register two lightweight procedural crystalline SFX buffers (`&"weapon_prism_beam"` — harmonic crystalline hum/chime transient that pitch-shifts gently higher as beam ramp increases; `&"weapon_prism_refract"` — sharp glass-prism harmonic snap) using `SynthPrimitives`, keeping full compliance with the 10-voice combat cap, spatial attenuation, and Master `AudioEffectLimiter`.

---

## Phase D — Zero-Leak Sandbox Test Harness & Verification Checklist

### D.1 Temporary Sandbox Foundation Tester (`ui/hud/sandbox_debug_panel.gd`)

Add a compact collapsible **"3.9 Engine Lab"** row inside `SandboxDebugPanel` (visible **only** in `scenes/test/milestone_0_test.tscn`, zero footprint in Skirmish or Main Menu) with 3 instant verification actions using runtime-cloned `UnitData` / `BuildingData` instances (zero premature Faction #3 `.tres` files polluting `resources/factions/`):
1. **`Spawn Lattice Pair`:** Spawns a test Power Spire (`provides_power_grid = true, power_radius = 260.0`) + a dependent test Turret/Factory (`requires_power_grid = true`) nearby so you can immediately verify power rings, worker placement validation, and power-loss dormancy when destroying/salvaging the spire.
2. **`Spawn Tether Squad`:** Spawns a test Tether Relay unit (`tether_emit_radius = 210.0, tether_max_links = 3, tether_fire_rate_bonus = 0.20, tether_range_bonus = 35.0, tether_beam_ramp_bonus = 0.40`) alongside 4 friendly combat units so you can move them in/out of range, inspect `"Lattice Link: x1"`, and kill the relay to verify instant drop.
3. **`Spawn Prism Beam Tester`:** Spawns a test escalating continuous-beam + 2-bounce refracting unit facing 3 clustered enemy `TargetDummy`s so you can watch beam width/color ramp up over `3.5s` on Dummy #1 while refracting secondary split-rays onto Dummies #2 and #3.

### D.2 Verification & Zero-Regression Checklist

1. **Startup & Main Menu Integrity:**
   * Launch Godot (`F5`): confirm **0 errors**, **0 `FactionData.validate()` warnings**, and `MainMenu` still cleanly displays **`2 / 5 ACTIVE`** (`GENESIS_V2` & `MONOLITH_OS`) unclipped at `1280×720`.
2. **Power Lattice Verification (`milestone_0_test.tscn`):**
   * Attempt to place a `requires_power_grid` structure outside the Power Spire's `260 px` ring: confirm `BuildGhostPreview` renders existing gold/magenta lattice rings and rejects placement with `"Requires Power Lattice"`.
   * Place inside the ring: confirm a **worker physically walks over and builds** the scaffold (no remote warp-in).
   * Destroy or salvage the Power Spire: confirm the dependent structure immediately flips to **Unpowered / Dormant** (pausing production/turret fire, displaying `"UNPOWERED"` badge & inspection status, while Cancel Queue and Salvage still work), then resumes cleanly once a new Power Spire finishes nearby.
3. **Optical Tether Verification:**
   * Spawn the Tether Squad: confirm glowing gold/magenta tethers render cleanly via `OpticalTetherOverlay` up to `tether_max_links`, `SelectionHUD` shows `Lattice Link: x1` (capped at `x2`), and moving out of range or destroying the emitter cleanly drops the link and stat bonus within `< 0.5s`.
   * Confirm enemy Optical Tethers hidden inside Fog of War never leak visuals.
4. **Escalating Beam & Refracting Split Verification:**
   * Fire the Prism Beam Tester at 3 clustered `TargetDummy`s: confirm continuous live-tracking `PRISM_BEAM` thickens and brightens from Magenta → Solar Gold/White over `3.5s` with rising DPS, refracts crisp `PRISM_REFRACT` rays onto 2 adjacent dummies, resets ramp cleanly when manually switching targets, and respects SC2 high-ground Fog of War rules (`_hide_origin_muzzle`).
5. **Two-Faction Zero-Regression Sweep:**
   * Run a quick `GENESIS_V2` vs. `MONOLITH_OS` skirmish (and 4P FFA Spectator on `Procedural Arena`) to verify identical gameplay, zero performance impact when no tether emitters exist, and zero leaked `VFXPool` nodes on Rematch / Main Menu.