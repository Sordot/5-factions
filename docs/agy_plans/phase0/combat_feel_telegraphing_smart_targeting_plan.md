# Milestone 2.0 Plan: Combat Feel, Telegraphing & Smart Targeting Pass

**Target Directory:** `docs/agy_plans/21_combat_feel_telegraphing_and_smart_targeting.md`
**Primary Files:** `scripts/units/combat_component.gd`, `scripts/units/unit.gd`, `scripts/units/ability_component.gd`, `scripts/units/heal_aura_component.gd`, `ui/overlays/attack_tracer.gd`, `ui/overlays/ability_effect.gd`, `ui/overlays/entity_visuals.gd`, `scripts/systems/audio_manager.gd`, `ui/hud/selection_hud.gd`
**Reference Docs:** `docs/agy_plans/faction_01_genesis_v2_the_vat_born_plan.md`, `docs/agy_plans/genesis_v2_vertical_slice_completion_bundle.md`, `docs/agy_plans/macro_hud_scoreboard_main_menu_polish_plan.md`

## 1. Objective & Scope

Make every `GENESIS_V2` engagement feel crisp, legible, and tactically responsive before scaling up to Faction #2. This pass upgrades **auto-targeting intelligence**, gives every weapon and ability a **distinct Technozen/Y2K visual telegraph**, adds **status-effect & range-ring clarity**, and polishes **hit feedback and polyphonic combat audio**.

### In Scope

1. **Smart Threat-Priority Targeting (`scripts/units/combat_component.gd`, `scripts/units/unit.gd`):**
   * **Weighted Target Scoring (Auto-Acquisition Only):** Replace nearest-only auto-target selection during `ATTACK_MOVE`, `PATROL`, `HOLD_POSITION`, and idle aggro with a deterministic threat-priority score:
     * **Tier 1 (Highest Priority):** Active hostile combat units capable of dealing damage (with a bonus for enemies currently attacking this unit or nearby allies, plus a counter-affinity bonus so anti-armor units like **Lance-Rig** prefer armored/heavy targets like **Goliath Frame**, **Arc-Lancer**, and **Chrysalis Mortar**).
     * **Tier 2 (Medium Priority):** Hostile support/utility units (**Symbiote**, **Signal Jammer**) and economy units (**Worker**, **Silica Harvester**, **Engineer**).
     * **Tier 3 (Lowest Priority):** Hostile buildings (units will never waste time shooting a passive **Synapse Pylon** while enemy **Clone Troopers** or **Stingers** are in range).
   * **Explicit Focus-Fire Preservation:** Direct player right-click attack orders lock onto the player's chosen target and are never overridden by auto-targeting until that target dies, leaves valid state, or the player issues a new order.
   * **Mid-Fight Re-Evaluation:** When a unit is auto-attacking a Tier 3 structure (or out-of-band target) and a Tier 1 combat threat enters weapon range, re-acquire the Tier 1 threat cleanly on the next target scan (`~0.25s` cadence).
   * **`min_attack_range` & Dead-Target Hygiene:** Ensure **Chrysalis Mortar** skips targets inside its `min_attack_range` during auto-acquisition when valid targets exist in its firing band, and immediately drops freed/dead targets without wasting an attack cooldown cycle.

2. **Weapon Archetype VFX, Mortar Telegraphs & Impact Feedback (`ui/overlays/attack_tracer.gd`, `ui/overlays/ability_effect.gd`, `scripts/units/unit.gd`, `scripts/buildings/building.gd`):**
   * **Distinct Archetype Tracers & Projectiles:** Upgrade `attack_tracer.gd` (or add a lightweight `ui/overlays/combat_vfx.gd` helper) so every `GENESIS_V2` weapon reads at a glance:
     * **Clone Trooper:** Crisp rapid pulse-rifle bolt + brief muzzle flash.
     * **Stinger:** Fast directional melee/acid cleave arc at impact point.
     * **Lance-Rig:** High-voltage focused rail beam with lingering ionized core + distinct bright impact spark when anti-armor bonus damage applies.
     * **Arc-Lancer:** Wide piercing plasma/thermal lance beam with subtle line-of-fire flash along its sweep path.
     * **Chrysalis Mortar:** Visible lobbed parabolic shell arc + **ground impact telegraph ring** (dashed outer splash radius + filling inner pulse during shell flight) so players can read and micro-dodge incoming artillery splash.
     * **Goliath Frame:** Heavy twin-slug tracer + punchy radial shockwave ring on **Seismic Slam**.
   * **Hit-Flash & Procedural Death Bursts:**
     * Add a crisp `0.08s` emissive white hit-flash on struck units and buildings (`entity_visuals.gd` / `unit.gd` / `building.gd`).
     * Spawn a lightweight procedural vector death burst (scaled to footprint: quick spark scatter for infantry, layered ring/fragment rupture for **Goliath Frame**, **Arc-Lancer**, and destroyed buildings) with automatic self-cleanup.
   * **Subtle Heavy-Impact Camera Shake (`scripts/camera/rts_camera.gd`):**
     * Add a tiny, damped trauma shake (`2–5px` max, `0.15s` decay) triggered *only* by heavy events (**Chrysalis Mortar** splash on screen, **Seismic Slam**, and **Nexus Vat** destruction), with a `camera_shake_enabled` toggle in `SettingsManager` (`Gameplay` tab).

3. **Status Effects, Auras & Range Readability (`ui/overlays/entity_visuals.gd`, `scripts/units/heal_aura_component.gd`, `ui/overlays/ability_targeting_reticle.gd`):**
   * **Diegetic Status Indicators:** Render compact, readable visual cues on units under active buffs/debuffs:
     * **Adrenal Surge:** Pulsing emerald/gold rim accent + subtle upward chevron pip.
     * **Static Pulse (Disrupted / Slowed):** Flickering violet/cyan interference arcs around affected units.
     * **Symbiote Heal Aura:** Soft translucent emerald ring (`heal_radius`) drawn when a **Symbiote** is selected or actively healing, paired with subtle rising `+` ticks on healed allies (throttled to avoid clutter).
     * **Compute Overdrive:** Subtle luminous gold trim on upgraded heavy synthetics.
   * **Dual-Ring Mortar & Ability Range Previews:**
     * When a **Chrysalis Mortar** is selected (or while targeting abilities / Attack-Move), render a subtle dashed outer `attack_range` ring—and for units with `min_attack_range > 0`, render a faint crimson inner dead-zone ring so players immediately understand why a mortar won't fire point-blank.
     * When hovering ground-targeted abilities (**Seismic Slam**, **Static Pulse**, **Spore Barrage**), ensure `AbilityTargetingReticle` displays both cast range and AoE impact radius cleanly.

4. **Micro Cursor Feedback, Counter Tooltips & Audio Mix Polish (`scripts/controllers/selection_controller.gd`, `ui/hud/selection_hud.gd`, `scripts/systems/audio_manager.gd`):**
   * **Command-Mode Visual Feedback:** Clearly tint/highlight the active cursor or world reticle when in `Attack-Move` (crimson), `Patrol` (cyan/gold), or `Ability Target` (amber/violet) modes so players never misclick a smart order.
   * **Counter & Weapon Role Callouts (`SelectionHUD` / `CommandTooltip`):** Surface armor/unit class tags (`Light`, `Armored`, `Heavy Synthetic`, `Structure`) and key weapon traits (`+vs Armored`, `AoE Splash`, `Line Pierce`, `Min Range`) cleanly in the unit inspection card and production tooltips.
   * **Polyphonic Combat Audio Polish (`scripts/systems/audio_manager.gd`):**
     * Add subtle pitch randomization (`±6%`) to weapon and impact SFX.
     * Add per-sound-key cooldown throttling (`0.06s–0.10s`) so a full squad of 12 **Clone Troopers** firing simultaneously sounds crisp and punchy without harsh clipping or phase distortion.

### Out of Scope
* New factions, units, structures, or upgrades beyond `GENESIS_V2`.
* Unit formation/flocking pathing rewrites (keep the stable Milestone 1.6.3 worker/unit pathing intact).
* Persistent decals or heavy GPU particle shaders that could hurt frame pacing on large skirmishes.

---

## 2. File & Architecture Plan

### New Files to Create (Optional Helper)
* **`ui/overlays/combat_vfx.gd`** (Lightweight procedural `_draw()` effect node for mortar parabolic shells + ground splash telegraphs, melee cleave arcs, armor-pierce sparks, and scaled unit/building death bursts—keeps `attack_tracer.gd` and `unit.gd` clean and modular).

### Existing Files to Extend
* **`scripts/units/combat_component.gd`**:
  * Implement weighted threat-priority target scoring (`_score_auto_target()`), explicit vs. auto-acquired target distinction, Tier-1 interruption when auto-attacking Tier-3 structures, and `min_attack_range` filtering.
  * Spawn archetype-appropriate tracers/projectiles (including delayed splash damage for **Chrysalis Mortar** shells paired with the ground telegraph ring).
* **`scripts/units/unit.gd` & `scripts/buildings/building.gd`**:
  * Add `hit_flash_timer: float` (`0.08s` decay on `take_damage()`), trigger death-burst VFX on death, and expose active buff/debuff flags for `entity_visuals.gd`.
* **`scripts/units/heal_aura_component.gd`**:
  * Emit/trigger throttled subtle heal-tick visuals on healed allies and expose active healing state so the **Symbiote** aura ring pulses cleanly.
* **`ui/overlays/entity_visuals.gd`**:
  * Render `hit_flash` tint overlay, status pips/rings (**Adrenal Surge**, **Static Pulse**, **Compute Overdrive**), **Symbiote** heal aura ring, and selected-unit `attack_range` / `min_attack_range` subtle dashed rings.
* **`ui/overlays/attack_tracer.gd` & `ui/overlays/ability_effect.gd` & `ui/overlays/ability_targeting_reticle.gd`**:
  * Distinct weapon tracer styles (**Clone Trooper**, **Lance-Rig**, **Arc-Lancer**, **Goliath Frame**) and crisp cast-range + AoE radius rings on targeting reticles.
* **`scripts/camera/rts_camera.gd` & `scripts/systems/settings_manager.gd` & `scripts/ui/settings_menu.gd`**:
  * Add subtle damped `add_camera_shake(intensity: float, duration: float)` gated by `SettingsManager.camera_shake_enabled` (default `true`, toggleable in **Settings → Gameplay**).
* **`scripts/systems/audio_manager.gd`**:
  * Add per-cue pitch jitter (`0.94–1.06`) and minimum retrigger interval (`0.06s–0.10s`) for combat SFX.
* **`ui/hud/selection_hud.gd` & `ui/hud/command_tooltip.gd`**:
  * Display armor class and weapon trait tags (`+vs Armored`, `Splash AoE`, `Line Pierce`, `Min Range`) cleanly in the inspector and tooltips.

---

## 3. Verification Checklist for `agy`

Before concluding Milestone 2.0, verify in `scenes/test/milestone_0_test.tscn` and `scenes/maps/skirmish_arena_01.tscn`:

* [ ] **Smart Threat-Priority Targeting:** Attack-Move a squad of **Clone Troopers** past an enemy **Synapse Pylon** with enemy **Clone Troopers** standing behind it; verify they switch to and prioritize the enemy combat units over the passive building, while a direct right-click on the **Synapse Pylon** still forces focus-fire on the building.
* [ ] **Anti-Armor & Mortar Smarts:** Send **Lance-Rigs** against mixed **Clone Troopers** + **Goliath Frames** and verify they prioritize armored targets; verify **Chrysalis Mortars** fire lobbed shells with a visible ground splash telegraph ring and skip targets inside `min_attack_range` when valid outer targets exist.
* [ ] **Visual Telegraphing & Status Clarity:** Activate **Adrenal Surge**, **Static Pulse**, and **Seismic Slam** in combat, and place a **Symbiote** beside damaged allies; verify hit-flashes, distinct weapon beams/slashes, status rings/pips, heal-aura ticks, and scaled death bursts all read clearly without visual clutter.
* [ ] **Audio Mix & Camera Shake:** Fire 10–15 **Clone Troopers** + **Goliath Frames** + **Chrysalis Mortars** simultaneously; confirm combat SFX sound crisp with zero harsh clipping, and confirm **Settings → Gameplay → Camera Shake** toggles heavy-impact shake cleanly.
* [ ] **Performance & Debugger Hygiene:** Run a 5-minute skirmish with `Aggro AI: ON` (using `Fast-Tech Test` to stress late-game battles); verify smooth frame pacing via the Corner FPS Counter and zero Godot Debugger errors or leaked VFX nodes.