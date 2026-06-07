# M6 — Modular Enemies: As-Built Audit + System Design

Status: **design / plot-out** (Roman, 2026-06-05). Supersedes the bolt-on "signature slot"
sketch in `combat_construction_plan_2026-06-03.md` §10 — that section's instinct was right
(compose, don't monolith) but the audit shows the unique behaviors are a small set of
**reusable components**, not one-off signatures, and that two base-layer fixes gate any
conversion. This doc is the M6 plan of record.

Parent: `combat_construction_plan_2026-06-03.md` (§10 modular idea, §5 milestones).
Grounded in a 5-front read-only audit (enemy base/core, monolith inventory, pattern
library, spawn pipeline, dev-tool conventions), 2026-06-05, with file:line citations
in the audit; key cites inline below.

---

## 0. TL;DR

- Composition is **already proven**: `sapper`, `hunter_drone`, `interceptor` extend
  `enemy_core` and run as movement+shoot compositions today. Template exists.
- **8 of 14 monoliths decompose cleanly; 6 don't.** The 6 (`burner`, `strafer`,
  `frigate`, `gunship`, `beam_shooter`, `firecore_cruiser`) couple weapon-fire to
  locomotion output — **leave them bespoke**. Don't force the abstraction.
- The clean enemies' "unique" parts are a **small reusable component set** (death-effect,
  spawner, shield, contact, dropper, drain-beam, carried-turrets), not bespoke signatures.
  → Model = **chassis + movement + weapon + components[]**, not a single signature slot.
  **LOCKED (Roman, 2026-06-05): components[] list.**
- **Two base-layer fixes gate everything:** (1) unify the two HP vocabularies
  (`health/max_health` vs `hull/max_hull/hull_changed`); (2) add a death hook to
  `explode()`/`_leave()` (no extensibility point exists today).
- **Pattern library**: `lane_path` is the backbone; collapse the `straight_down` presets +
  `s_curve` into it, add SWEEP + HOLD shapes to close the gunship/beamer/bomber gaps.
- **First build = the Lane/Pattern Dev Visualizer** (Roman's chosen verification surface).
  Independent of the enemy decisions, and it's the eval tool for all of them.

---

## 1. As-built reality

### 1.1 enemy_base / enemy_core
- `enemy_base.gd`: one HP system (`max_health`/`health`), one signal (`died(value)`),
  damage via `take_hit(dmg)->bool` (shield-charge first, then hull), death via
  `explode()` (emits `died`, plays VFX, awaits, `queue_free`). Offscreen → `_on_offscreen`
  (recycle hook) / `_leave` (free, **no `died`**). An **inert identity block**
  (`chassis/faction/tier/category/render_plane`) is declared but unused.
- `enemy_core.gd`: adds `movement: Resource` + `shoot_pattern: Resource` slots
  (duplicated per-instance), sector speed-scaling (the `_speed`-suffix scan), the parallax
  recycle cycle, and the legacy anchored path (`movement == null`). **Three parallel firing
  systems** (random ShootTimer, `phase_entered` event, path-phase + Beat) with duplicated
  precondition stacks.
- `movement_pattern` contract: `on_start(enemy)` (idempotent), `compute_step(enemy,delta)
  ->Vector2` (delta, never mutate position), `path_phase_capable()`, optional
  `phase_entered` signal. Speed exports MUST be named `speed`/`*_speed` for the clarity
  clamp; `accel`/`drift_x` scale unclamped; any other float knob is invisible to scaling.

### 1.2 The two HP vocabularies (BLOCKER)
`enemy_core` carries `health/max_health` only. Custom-hull enemies (`bulwark`, bosses)
declare a **parallel** `hull/max_hull` + `hull_changed` signal and override `take_hit`.
HUD/boss-bars bind to `hull_changed`, which the base never emits. **Consequence: a
custom-hull enemy cannot be an `enemy_core` instance.** Any modular system that wants
`bulwark` (a clean decomposition otherwise) must first unify HP.

**RESOLVED (Roman, 2026-06-05) — Shield component + `health_changed`:**
- The **simple base charge-shield** (`max_shield`/`shield` charges, used by lots of chaff
  via the wave `shield_charges` override) **stays as-is** on the base — widely used, no gain
  from migrating.
- The **player-style REGEN shield** (bulwark's self-recharging pool, reimplemented in
  `sapper` + bosses) becomes the **`Shield` component**.
- Add `signal health_changed(cur, max)` to `enemy_base`; **retire** the parallel
  `hull`/`max_hull` so bulwark/bosses use base `health` + the `Shield` component. One HP
  vocabulary; three regen-shield reimplementations collapse to one.

### 1.3 explode() has no death hook (BLOCKER)
`explode()` is inline (set `_dying`, emit `died`, VFX, `await 0.5s`, `queue_free`). Clean
components (`firecore_drone` ring-release, `burner` kill-partner, `cruiser`/`bulwark`
turret-bounty) need an `on_death(enemy)` callback. `_leave()` (recycle/escape) likewise
notifies nothing. **Required change:** a single hook call in `explode()` (after `_dying`,
before the await) and `_leave()` that fans out to the enemy's components.

### 1.4 Spawn pipeline (the composition application point)
`WaveGen._make_wave_spec` → `WaveSpec` (sets `movement_override`/`shoot_pattern_override`
via `Roster.make_movement/make_shoot`) → `ScoreAdapter` (transparent — copies the spec by
reference into a FORMATION phrase) → `director._spawn_enemy` (the **only** node-creation
site; applies overrides with `in`-guarded writes, places by lane/formation, wires signals).
- A `signature`/`components` override plugs in at `_spawn_enemy` next to
  `movement_override` as a 3-point additive change (WaveSpec field + producer factory +
  `enemy_core` slot). **Score/phrase layer needs no change.**
- `make_movement`/`make_shoot` are **giant hardcoded string→class+tuning matches**; the
  per-instance tuning (speeds/amplitudes/counts) lives in the match arms, not data. They
  also use bare `randf()` (non-deterministic — breaks run-seed reproducibility of any pick).
- `movement: null` is the **implicit** "bespoke self-driver" sentinel (~10 entries). A
  modular schema should make "pattern-composed vs self-driving" explicit (the `chassis`).

---

## 2. Decomposition verdict (per monolith)

| Enemy | Extends | Movement | Weapon | Unique part | Verdict |
|---|---|---|---|---|---|
| sapper | **enemy_core** | omni_thrust ✅ | drain-beam (effect) | shield-drain + reflect | DONE |
| hunter_drone | **enemy_core** | beeline ✅ | none | contact-detonate | DONE |
| interceptor | **enemy_core** | top_dive ✅ | missile-drop | periodic-dropper + no-recycle | DONE |
| firecore_drone | base | straight_down | none | death ring-release | **CLEAN** |
| cruiser | base | enter+drift (small) | child turrets | turret-bounty death | **CLEAN** |
| bulwark | base | inertial_thrust (inline dup) | child turret | self-regen shield | **CLEAN** (needs HP unify) |
| drone_carrier | base | enter+drift+leave | none | drone spawner | **CLEAN** |
| bomber | base | ~loiter hold+sway | aimed+rear-cone | tail-gun + plumes | **CLEAN-ish** |
| firecore_cruiser | base | side_traverse | turret | 130-line death descent | MESSY (death in _process) |
| frigate | base | straight/side (roll) | broadside | broadside ⟂ hull facing | MESSY |
| gunship | base | role sweep/oscillate | rockets + aimed burst | role drives move+fire | MESSY |
| beam_shooter | base | side sweep | beam (hull-rot aim) | beam aim rotates hull | MESSY |
| strafer | base | 3-phase strafe-steer | nose-gated MG burst | fire gated by steering | MESSY |
| burner | base | pair-coupled descent | beam BETWEEN pair | the pair IS the enemy | MESSY (irreducible) |

**The 6 MESSY share the failure mode:** weapon firing depends on locomotion output, so a
movement/weapon split adds indirection without removing coupling. Keep bespoke. They can
still gain the base-layer death hook + identity block, and optionally a `drives_locomotion`
component wrapper later — but that's not where the value is.

---

## 3. Proposed system model: chassis + movement + weapon + components[]

Refines §10. Five axes; **components is the new idea the audit surfaced.**

- **Chassis** — silhouette + stats + hitbox, identified by **size-class** (Escort/Frigate/
  Destroyer/Cruiser/Dreadnought — the px-width ladder, §8 naming) which drives stats/hitbox
  and subsumes today's scattered `size`/`tags`/`hp_override`/`heavy_class`. Plus the flag
  `composed` (pattern-driven) vs `self_driving` (bespoke). A concrete hull = faction × size.
- **Movement** — a `movement_pattern` Resource (existing slot). Parity-first: one per enemy.
- **Weapon** — a `shoot_pattern` Resource (existing slot), or a weapon-component for
  continuous effects (beam/drain).
- **Components[]** — a LIST of small reusable behavior Resources on `enemy_core`, each with
  optional hooks `on_start / on_process / on_death / on_hit`. The audit's reusable set:
  - `DeathEffect` (ring-release, death-glide, turret-bounty)
  - `Spawner` (drone_carrier)
  - `Shield` (bulwark + sapper + bosses — also the HP-unify vehicle, §1.2 option B)
  - `ContactDetonate` (hunter_drone)
  - `PeriodicDropper` (interceptor)
  - `DrainBeam` (sapper)
  - `CarriedTurrets` (cruiser/bulwark/firecore_cruiser)
  Most are **layered** (ride on top of movement). `drives_locomotion` is **deferred (YAGNI)**
  — the only enemies that would need it are the 6 we're leaving bespoke. Components are
  layer-only in v1.
- **Faction (M6b)** — stat/posture + tint modifier over the whole composition. Cheap once
  components exist.

**Why components beat a single "signature":** the unique behaviors recur across enemies
(shield ×3, turrets ×3, death-effects ×3). A list of shared components dedupes them; a
per-enemy signature would re-implement each. This is the actual payoff of the refactor.

### 3.1 Component framework — LOCKED architecture (Roman, 2026-06-05)

**Registry on `enemy_base`, per-frame tick on `enemy_core`:**
- The component LIST + the event-hook fan-out live on `enemy_base`, so **every** enemy
  (composed, boss, bespoke monolith) can host components — bosses get `Shield` +
  `DeathEffect` for free (the big dedup win) without per-frame coupling.
- `on_process(enemy, delta)` is ticked **only by `enemy_core`** (it owns the `_process`
  loop). Bosses/bespoke opt in via `_tick_components(delta)` if they ever need a per-frame
  component. Most components are event-driven and need no tick.

**Component contract** (`scripts/enemies/components/enemy_component.gd`, base Resource —
all hooks optional, duplicated per-instance like movement):
```
func on_start(enemy) -> void          # after movement.on_start + on recycle re-arm; build child nodes here
func on_process(enemy, delta) -> void # per-frame (enemy_core only)
func on_hit(enemy, damage) -> float   # return REMAINING damage (absorb/reduce/reflect); see below
func on_death(enemy) -> void          # from the base death hook (ring-release, kill-partner, turret-bounty)
func on_leave(enemy) -> void          # recycle / side-escape teardown
```

**Damage routes THROUGH components** — `enemy_base.take_hit` becomes:
```
var dmg := damage
for c in _components:
    dmg = c.on_hit(self, dmg)         # Shield consumes a charge + i-frames -> 0; armor reduces; reflect side-effects
    if dmg <= 0.0: hit(); return false
# ...then existing damage_reduction + health subtraction + explode/hit
```
So `Shield`/armor/reflect are first-class pipeline participants, not observers.

**Authoring / data flow:** roster entry gains `components: [ ... ]`; a `Roster.make_components(entry)`
factory builds the Resources (parity-first: a fixed list per enemy); `WaveSpec` gains
`components_override`; `director._spawn_enemy` gains one guarded write next to
`movement_override`. **Score/phrase layer unchanged** (it copies the spec by reference).
Timing note: components build their child nodes in `on_start` (called after `add_child`),
which dissolves `firecore_drone`'s "set ring_count before add_child" constraint.

**BUILT (M6a.1, commit pending):** the framework is live + inert in `enemy_base`
(`components: Array` untyped — typed `Array[Resource]` crashes on untyped assignment;
`health_changed` signal; `on_start` deferred-after-positioning; damage routes through
`_components_hit`; `on_death`/`on_leave` fan out from `explode()`/`_leave()`) + `enemy_core`
(`_tick_components` each frame + recycle re-fire). Verified: `tools/test_components_framework.gd`.
**Caveat:** enemies that OVERRIDE `explode()`/`_leave()` WITHOUT calling super (`mine`,
`firecore_cruiser`, …) won't fan out `on_death`/`on_leave` — route those through
`_components_death()`/`_components_leave()` when they get components at conversion.

### 3.2 Base-layer prerequisites (do FIRST, inert)
1. **HP unify** (§1.2 resolution): add `signal health_changed(cur,max)` to `enemy_base`;
   land the `Shield` component; retire bulwark/boss parallel `hull` → base `health`.
2. **Death hook**: `on_death`/`on_leave` fan-out in `explode()` (after `_dying`, before the
   await) and `_leave()`.
3. **Component registry + damage routing** on `enemy_base` (§3.1); `on_process` tick on
   `enemy_core`.
4. **Identity block**: populate `chassis/tier/category` in `_spawn_enemy` (cheap; feeds the
   run-summary hooks, construction plan §7).
These change no current behavior (no enemy sets `components` yet) → land on `main` early.

---

## 4. Pattern library consolidation (independent track)

`lane_path` (STRAIGHT/WEAVE/HOOK/STEP, lane-anchored, mirrorable, deterministic,
`path_phase_capable`) is the intended backbone but is **dev-tool-only** today.
- **Collapse into lane_path:** the 4 `straight_down` speed-presets (`make_movement` arms)
  → STRAIGHT + a `down_speed`; `s_curve` → WEAVE.
- **Unify near-dupes:** `slow_advance` ≡ `bulwark_drift`; `side_traverse`/`side_cut`/
  `side_pingpong` (the last is already orphaned — imported, no match arm) → one lane-traverse.
- **Add shapes to close monolith gaps:** `SWEEP` (settle-and-sweep — gunship/beamer/boss
  all hand-roll it) and `HOLD` (descend-then-hold + sway — bomber). Both fit lane_path's
  closed-form lane model.
- **Generalize `make_movement` for `allowed_movements[]` seed-pick:** move per-movement
  tuning out of the match arms into a string→knob-dict table, and use the **run-seed RNG**
  (not bare `randf()`). Parity-first: each enemy's `allowed_movements[]` is a singleton ==
  its current movement until M6a.3 deliberately turns on variety.

---

## 5. Lane / Pattern Dev Visualizer (FIRST BUILD — verification surface)

Roman's chosen way to verify parity + iterate. A fresh `Control` scene
(`scenes/dev/lane_visualizer.tscn` + `scripts/dev/lane_visualizer.gd`), NOT a mount of
`main.tscn` (drags in player/HUD/run-state — the documented trap). Two modes:

- **Run-Score mode:** instantiate `director.gd` under a world `Node2D`, drive it with
  `WaveGen.build_score(sd,li,boss)` or `CombatSlice.build()`. Watch the conductor stream a
  whole level. Overlays: the 7 lanes (from `Lanes`: centers 150–330, pitch 30) and the
  three Y-bands (from `Zones`: entry <40, engagement 40–195, departure ≥195). Highlight the
  live wall/pincer lane sets (`_formation_lanes`) and per-lane occupancy.
- **Single-Pattern mode:** reuse `movement_lab.TestEnemy` (ticks `compute_step`, clamps to
  band, can fire tracers) + `movement_test._resolve_movement_for` (loads the *production*
  movement via `EnemyRoster.make_movement`) + `EnemyManifest` enemy picker. Trace the path
  as overlaid Line2D across N runs.

Reuse the **tuner contract** from `ui_designer.gd`: left rail, JSON persist to
`user://tuners/lane_visualizer.json`, Esc-to-close, Copy-GDScript. Register one button in
`dev_menu.gd`. Coordinate note: `Lanes`/`Zones`/`Playfield` are **absolute** viewport
coords; `movement_lab` works **field-local** (−132 offset) — keep overlays absolute and
reparent/convert the reused TestEnemy, don't mix spaces. Guard autoloads (`Run`/`Music`)
with `has_node("/root/...")` (absent in headless).

---

## 6. Proposed build order

- **M6a.0 — Visualizer** (first; the eval surface, independent of all enemy decisions).
- **M6a.1 — Base-layer prereqs (inert):** HP unify (`health_changed`/`Shield` component),
  death hook in `explode()`/`_leave()`, populate identity block. Land on `main`.
- **M6a.2 — Component framework + Weapon/role plumbing (inert):** `components:
  Array[Resource]` on `enemy_base`/`enemy_core` + hook fan-out + the `_spawn_enemy` guarded
  write + WaveSpec/producer plumbing; **Weapon consolidation** (§9.2 — wrap existing
  shoot_patterns behavior-preserving, fire-rate single-sourced, **+ a projectile-movement
  axis (homing/wobble)** to restore the boss tracker/plasma signatures the 2026-06-05
  projectile pass stripped — `base_bullet.gd` still supports the flags); **role/`allowed_movements`
  schema** on roster entries (§9.1). All inert — nothing sets components/roles yet.
- **M6a.3 — Core roster curation + faction tagging (content pass, §10):** DRAFT tagging
  table → Roman redlines → the lean core set + per-enemy faction verdicts that drive
  everything below. No code; decides scope.
- **M6a.4 — File/scene reorg (§11):** rename into the final core-vs-faction structure ONCE,
  now that tagging is set (rename + roster edit + EnemyManifest together; `parse_check` +
  tests gate). Mechanical.
- **M6a.5 — Pilot conversion:** one CLEAN enemy end-to-end (recommend `firecore_drone`:
  straight_down + a `DeathEffect` ring-release component). Verify in the visualizer.
- **M6a.6 — Convert the remaining CLEAN enemies** + extract the shared components (Shield,
  CarriedTurrets, Spawner). One at a time, parity-checked. Leave the 6 MESSY bespoke. **Tag
  each converted chassis with `behaviors[]` (§14.1) + faction (§12)** as it lands.
- **M6a.6b — Gap derivation (§14.2):** lay tagged behaviors × faction assignments → coverage
  matrix → the prioritized new-enemy backlog. No code; defines M6b authoring scope.
- **M6a.7 — Pattern library consolidation** (collapse presets into lane_path; add SWEEP/HOLD;
  data-table tuning). Parity-first.
- **M6a.8 — Turn on movement variety** (`allowed_movements[]` multi-entry seed-pick) — the
  one deliberate gameplay change, gated on Roman's sign-off.
- **M6b — Faction layer (§8) + gap-fill authoring (§14):** the 4 factions as table entries —
  pool draw + modifier (Shield/DropFirecore components, tough stat, supremacy weapon-rate),
  Privateer overlay, tint, firecore lane-hazard scene. **Author the gap-filling new enemies**
  (Martyr/Manta/Hoplite/Harrier/…) from the §6a.6b backlog — as data on existing
  chassis/behaviors/components wherever possible, new art only for genuinely missing
  silhouettes. Cheap once components + Weapons + behaviors exist.

---

## 7. Decisions

**LOCKED (Roman, 2026-06-05):**
- ✅ **Behavior model:** `components[]` list (not a single signature slot).
- ✅ **Component layering:** registry + event hooks on `enemy_base`; per-frame tick on
  `enemy_core`.
- ✅ **HP unify:** `Shield` component + `health_changed` on base; retire parallel `hull`;
  keep the simple base charge-shield as-is.
- ✅ **Damage pipeline:** components participate via `on_hit(enemy,dmg)->remaining`.
- ✅ **`drives_locomotion`:** deferred (YAGNI).
- ✅ **The 6 messy enemies:** leave bespoke (they still get the death hook + identity block,
  and may host event-driven components like a `DeathEffect` later without touching movement).
- ✅ **First build:** the Lane/Pattern Dev Visualizer (verification surface).
- ✅ **Core chassis + faction overlay** (not a per-faction chaff roster): lean core set that
  mutates via overlays + faction-exclusive variants (§8, §10).
- ✅ **Faction tagging is a curation pass** (§10): existing enemies may retire/unhome; gaps
  surface needing new variants. DRAFT → Roman redline.
- ✅ **Behavior is the attach layer** (§13): chassis declare `behaviors[]`; conductor resolves
  behavior + faction pool → chassis + overlay + Weapon. "Roles" demoted to a pacing tag.
- ✅ **Convert-first, then gap-fill** (§14): convert existing → tag behaviors/faction → derive
  the behavior×faction coverage gaps → author new enemies only to fill them. No big-bang.
- ✅ **Faction ids + lore names** (§8): `supremacy`=Crimson Supremacy, `privateer`=Vertarine
  Armada, `corporate`=UltraGalactic Concerns, `zealot`=Evantian Theocracy. `zealot` (not
  `firecore`) is the faction id; "firecore" = the dropped hazard + lore only.
- ✅ **Naming convention** (§8/§11): **class-by-size** — internal `enemy_<faction>_<size-class>`
  (Escort 16 / Frigate 32 / Destroyer 64 / Cruiser 128 / Dreadnought 256) under the dir split;
  role lives in `behaviors[]`, not the name; evocative display/lore names player-facing only.
- ✅ **Faction-owned rosters, behaviors shared** (Roman, 2026-06-05): each faction owns its
  full roster (names/art/weapons/uniques); hulls are tagged with eligible behaviors; the
  conductor selects **(faction + behavior) → hull**. The shared layer is the machinery
  (behaviors/patterns/components/size-stats), NOT enemy scenes. Resolves home-vs-exclusive:
  not a runtime overlay on a neutral core — each faction has its own version of a slot.
- ✅ **STREAMLINE PASS** (§19, Roman 2026-06-05): (A) behavior = movement pattern (one concept,
  `patterns[]`); (B) components collapse to **Shield + Emitter** (beams/contact → weapons);
  (C) faction = pure data `{components, stat_mults, weapon_mults, tint}`; (D) **drop `tier`**;
  (E) **drop `role`** as an enemy axis. Authoritative axis list is §19; it supersedes the
  scattered framings in §3/§8/§9/§13 (→ §17 consolidation).
- 🟡 **Faction roster seeds** (§12.0): the home assignments seed each faction's roster;
  Roman-stated set recorded; unlisted homes proposed (?) pending redline; supremacy-empty +
  corporate-overload flagged.

- ✅ **Naming scheme (§11):** directory split — `scenes/enemies/core/` +
  `scenes/enemies/factions/<faction>/` (mirrored in `scripts/`). Rename once after tagging.
- ✅ **Tagging draft:** Claude drafts the core-set + faction-tag table (§12), Roman redlines.

**Still open:**
- **Scope of M6a conversions:** all 5 clean conversions + shared-component extraction in
  one pass, vs pilot (`firecore_drone`) then reassess. (Earlier lean: pilot-first.)
- **Pattern-library consolidation timing:** fold into M6a (§4) or run as a parallel track.
- **The §12 tagging draft itself** — pending Roman's redline.

---

## 8. Faction system (M6b content) — LOCKED (Roman, 2026-06-05)

Four factions. A faction = **{enemy pool} + {modifier} + {tint} + {lore name}**. The modifier
is implemented entirely via the §3 component/weapon axes — no new per-faction machinery,
which is the payoff of sequencing the refactor first.

| id (internal) | Display / lore name | Mechanic | Implementation |
|---|---|---|---|
| `supremacy` | **Crimson Supremacy** | faster fire **+ faster projectiles** (Roman, 2026-06-06) | **weapon_mods on the Weapon** (§9): fire_rate_mult 0.7 **+ bullet_speed_mult 1.25** (speed clamped to the clarity ceiling), not a per-enemy bool |
| `privateer` | **Vertarine Armada** | tough + mixes in | `tough` stat modifier (2× HP); the one faction that **overlays** others |
| `corporate` | **UltraGalactic Concerns** | shielded | every spawn gets the **`Shield` component** (§3 regen shield) |
| `zealot` | **Evantian Theocracy** | drops firecore | every spawn gets a **`DropFirecore` component** |

> **Internal id is `zealot`, NOT `firecore`** (Roman, 2026-06-05). The term "firecore" is
> reserved for the dropped lane HAZARD + lore; the faction that drops it is `zealot`. So the
> hazard scene stays `firecore_*`, the faction is `zealot`, and existing `firecore_drone`/
> `firecore_cruiser` become `enemy_zealot_*` (their fire theme is the zealot identity).

**Assignment — one faction/level + Privateer overlay:**
- The producer/conductor selects **one primary faction** per combat level (by sector
  progression / run-seed). The level's enemies are drawn from that faction's **pool**, and
  the faction **modifier is applied to every spawn** (attach Shield for corporate, attach
  DropFirecore for zealot, set tough for privateer, multiply weapon fire-rate for supremacy).
- **Privateer is the special overlay:** its tough enemies can be sprinkled into ANY other
  faction's level (a secondary pool draw + the tough modifier on those specific spawns),
  not just its own pure levels.
- A faction `tint` (modulate) is applied for instant visual read (M6b polish).

**`DropFirecore` component (firecore faction signature):**
- Hook: `on_death` — **by chance** (per-enemy probability knob), spawn a **firecore lane
  hazard** at the enemy's lane position.
- The firecore lane hazard is a NEW scene: lane-anchored, **explodes on contact with the
  player**, **destructible** (has health, killable). Model on the existing mines
  (`scripts/enemies/mine*.gd`) — it's a hazard (`is_hazard = true`) so it doesn't gate
  level-clear and rides the existing hazard pacing. Reuse/extend a firecore visual.
- Lives in `components[]`, so the firecore faction modifier just appends it to every spawn.

**Each faction OWNS its roster; behaviors are the shared layer (Roman, 2026-06-05):** a
faction's pool IS its own roster of enemies — own names, art, weapons, and any bespoke
uniques. There is **no faction-agnostic enemy reskinned at runtime** (supersedes the earlier
"core chassis + spawn-time overlay" framing). What's shared is the **machinery, not the
scenes**: the behavior taxonomy (§13), movement patterns, components (§3), and size-class
stats (§8). Each faction's hulls are **tagged with the behaviors they're eligible for**, so
the conductor selects by **(faction, behavior)**: "I need a privateer unit that can Dive" →
`Privateer Dart Drone` from the privateer roster. **Leanness comes from the size-class matrix
+ behavior reuse** (each faction ≈ one hull per size-class, multi-behavior — not 8 role-named
chaff), NOT from sharing enemy scenes. The faction MECHANIC (shielded/firecore/tough/fast-fire)
is the faction's inherent trait, expressed through the shared components/weapon-mods on its
own units. Privateer stays the exception — its units can appear in other factions' levels.

**Faction data home:** a `scripts/levels/factions.gd` (`class_name Factions`) table —
per-faction `{core_pool: [core chassis ids this faction fields], exclusives: [...],
modifier_components: [...], stat_mods: {}, weapon_mods: {}, tint, lore_name}`. The producer
composes a level by picking core chassis from `core_pool`, applying the overlay, and mixing
in `exclusives`. Privateer additionally overlays onto another faction's level.

**Naming convention (Roman, 2026-06-05) — class-by-SIZE, not role:** internal id/filename =
**`enemy_<faction>_<size-class>`**, where size-class is a pixel-width tier (role is NOT in the
name — it lives in `behaviors[]`):

SIZE-WORDS, not ship-classes (Roman, 2026-06-05 — supersedes Escort/Frigate/Destroyer/…):

| Size | px | Behaviors? | Role |
|---|---|---|---|
| **tiny** | 8 | yes | smallest chaff |
| **small** | 16 | yes | chaff / pressure |
| **medium** | 32 | yes | presence anchor |
| **large** | 64 | presence-only for now (≈2 lanes; dedicated large-unit behaviors are a future add) | capital / heavy |
| **elite** | 128 | no — bespoke/special | mini-boss; **home of the 6 bespoke** (beamers/burners) as special events |
| **boss** | 256 | no | boss pipeline (separate; keeps its own `hull` system) |

Behaviors (§13) apply to the **lane-scale** sizes (tiny/small/medium cleanly; large only for
2-lane presence behaviors). **elite (128) is where the bespoke single-behavior enemies live as
special elite EVENTS** (resolves §15.1 #1 — they stop being matrix filler). **boss (256)** stays
the existing boss pipeline. Filename: `enemy_<faction>_<size>` (e.g. `enemy_privateer_small`);
display/lore names stay evocative + player-facing only.

e.g. `enemy_privateer_escort`. With the §11 dir split:
`scenes/enemies/factions/<faction>/enemy_<faction>_<size>.tscn` (mirrored in `scripts/`).
**Display/lore names are evocative + player-facing only** — the Vertarine Corvette is
*displayed* "Corvette" but its file is `enemy_privateer_cruiser`; internal code keys off
faction+size, a `display_name` string is the only player-facing part. Size-class drives
stats/hitbox via the size table. **This simplifies naming**: no per-enemy role names to
invent; faction × size identifies the hull, behaviors/weapons/components supply the variation.

**Open items this raises (for redline):**
- **One chassis per (faction × size) cell, or multiples?** One = a clean 4×5 matrix (≤20
  hulls, very lean) where behavior tags do all differentiation. Multiples need a suffix
  (`enemy_privateer_escort_b`). Leaning one-per-cell.
- **Name collisions are now intentional:** the old `frigate`/`cruiser` *enemies* become
  size-*classes*. The existing `frigate` (32px) → a Frigate-class hull; the existing `cruiser`
  → likely a Destroyer (64) or Cruiser (128) by its real width — confirm each enemy's class.
- **§12.0 reframes into a faction × size-class matrix** — current enemies drop into cells +
  their `behaviors[]`. I'll rebuild it as a matrix once homes/supremacy (§12.0 flags) settle.
- Dreadnought (256) overlaps the existing boss system — likely "boss/special" stays the boss
  pipeline, not a regular spawn.

---

## 9. Roles + first-class weapons (M6a refinement — Roman, 2026-06-05)

These two refine the M6a axes so the faction layer (§8) and the conductor can do their jobs.

### 9.1 Roles → conductor eligibility (the "multi-use / old-enemies-new-tricks" goal)
- Chassis/roster entries declare `roles: [...]` (popcorn / pressure / anchor / area-denial /
  direct-challenge — comp guide §2) and `allowed_movements: [...]` (already planned, §4).
- The conductor selects enemies **by role + faction pool + depth**, not by rarity/chaff
  flags. One enemy can fill multiple roles → combinatorial variety with no new art.
- **Depth-gated role/pattern unlocks:** a deep-sector run can let an *existing* enemy take a
  harder role or a harder `allowed_movement` (e.g. a dart that gains a weave, a chaff that
  gains a weapon). "Reserve rare/elite/hard behaviors for deep sectors" = depth thresholds
  on specific (role, movement, weapon) eligibilities, same gating style as `unlock_depth`.
- This generalizes the producer's current rarity-roll + `eligible_pool`/`heavies_eligible`
  selection into a **role-and-faction-aware pool query**.

### 9.2 First-class, swappable weapons (the "weapons drive what they do" goal)
> **Spec'd separately:** `docs/weapons_system_2026-06-05.md` — the standalone weapon
> spec (payloads incl. beams/lob, timing-vs-content split, faction/sector tuning,
> authoring checklist). Use that when establishing weapons any enemy can carry.
- Promote weapons to a `Weapon` Resource (evolve `shoot_pattern`) that **owns the full
  firing identity**: `projectile` (bullet_variant/scene) + `fire_rate` (interval) +
  `fire_pattern` (single/aimed/spread/burst/beam) + telegraph.
- **Consolidates the scattered fire-interval** the audit flagged (today split across
  `enemy_core.fire_interval_min/max`, `shoot_pattern.fire_interval_min/max`, and the wave
  override — the pattern's copy is currently unconsumed). The Weapon becomes the single
  source of truth; enemy_core just drives it.
- **Swappable + modifiable** by: faction (supremacy → fire-rate ×k), sector modifiers
  (armed/aggressive → upgrade projectile or rate), and conductor need (hand a deep-sector
  enemy a nastier weapon). A weapon swap is a Resource reassignment at spawn — same seam as
  movement_override.
- `Roster.make_weapon(entry)` replaces `make_shoot`; the per-weapon tuning moves into a data
  table (out of the giant match arms) so it can be picked/modified, using the run-seed RNG.

### 9.3 Knock-on: build-order additions
- §6's "component framework (inert)" milestone grows the **`Weapon` consolidation** (inert:
  wrap the existing shoot_patterns; behavior-preserving) and the **role/`allowed_movements`
  schema** on roster entries (inert until the conductor query is switched on).
- §8 factions remain **M6b**, after the clean conversions + component extraction + the
  Weapon/role plumbing land — at which point a faction is just a table entry.

---

## 10. Core roster curation + faction tagging (Roman, 2026-06-05)

A dedicated **content pass** (not code) that decides the lean core set and assigns every
enemy to factions. Output is a per-enemy verdict:

- **core-agnostic** — a lean core chassis that any faction can field via overlay (most chaff
  + a few workhorse archetypes). The "we don't need 35 chaff" target: ~5–8 core chaff +
  a handful of core mediums/heavies.
- **faction-exclusive (which)** — belongs to one faction's identity (e.g. firecore_drone →
  firecore; a regen-shield heavy → corporate). Appears only in that faction's levels.
- **retire** — redundant once the core set + overlays exist (e.g. the `straight_down`
  speed-preset duplicates the audit flagged; chaff that's just another descender).
- **needs-new-variant** — a gap: a faction lacks an enemy for a role it should cover →
  author a new core chassis or faction exclusive.

**Consequence Roman called out:** tagging makes some **existing enemies unavailable** (retired
or unhomed) and **surfaces gaps** needing new faction variants. Expect the production pool to
get smaller-but-deeper before it grows back through overlays.

**Heuristic fit (mechanical starting point — final assignment is Roman's lore call):**
shielded-natural / armored silhouettes → `corporate`; death-burst / fire-themed (firecore_*,
ring-release) → `zealot`; tough / heavy bruisers → `privateer`-natural; aggressive /
fast-fire skirmishers → `supremacy`-natural; plain descender chaff → core-agnostic.

**Process:** produce a DRAFT tagging table (existing 14 monoliths + pattern-driven enemies +
the core chaff, each → verdict + faction + role[]), Roman redlines it, then it drives both
the conversions (§6) and the reorg (§11). Best done right after the visualizer + base-layer
prereqs, so we convert/rename into the FINAL shape once.

## 11. File / scene reorganization (Roman, 2026-06-05)

Once tagging settles, reorganize so the tree reflects core-vs-faction. **Do it as one
discrete mechanical pass AFTER tagging** (rename into the final structure once, not twice).

**Cost / blast radius** (the audit's pipeline trace): scene-path strings live in the roster
`ENTRIES` (`enemy_roster.gd`), the **hardcoded** `EnemyManifest` list (web export can't scan
dirs), `.tscn` instance/ext_resource refs, `.uid` files (auto), `Run.encountered_enemies`/
codex keys, dev tools + capture scripts. Godot's editor updates refs on an in-editor rename,
but **on-disk path strings in `.gd` (the roster) must be updated by hand** — so the rename +
the roster edit land together, then `parse_check` + the headless tests gate it.

**Naming-scheme options (decision below):**
- (A) **Directory split:** `scenes/enemies/core/<name>.tscn` + `scenes/enemies/factions/
  <faction>/<name>.tscn` (+ matching `scripts/enemies/...`). Clear core/faction read.
- (B) **Faction-prefixed flat:** `enemy_<faction>_<name>.tscn`, stay flat. Lower churn,
  greppable, but no structural grouping.
- (C) **Role/category dirs:** group by chaff/elite/hazard/boss rather than faction.
- (D) **Defer:** keep current names through M6a; reorg only at the M6b faction step.

**CHOSEN: (A) directory split** (Roman, 2026-06-05).

---

## 12. DRAFT faction-tagging table (Claude — FOR ROMAN REDLINE)

First-pass, mechanically reasoned from the audit. **Faction assignments are guesses for
the lore/design owner to correct.** Guiding principle: *composable (`enemy_core`) enemies →
core-agnostic (full overlay support); bespoke enemies → faction-exclusive or retire (overlays
apply only partially — event-components + tough/tint yes, Weapon swap no).*

### 12.0 Faction HOME assignments (Roman redline, 2026-06-05)
Each existing enemy gets a **home faction** (owns its art/identity → `enemy_<home>_<name>`).
HOME ≠ exclusive: **universal** encounters still appear under other factions via overlay/
reskin (e.g. dart's home is privateer, but "Corp Dart" exists). ✓ = Roman-stated; ? = my
proposed home for a Roman-unlisted enemy (REDLINE these).

| Enemy | Home | Src | Universal? | Note |
|---|---|---|---|---|
| dart | privateer | ✓ | **yes** (core chaff) | "Privateer/Corp Dart" |
| gunship | privateer | ✓ | maybe | bespoke; Sweeper/Skirmisher |
| bomber | corporate | ✓ | **yes** (§12.1) | universal artillery encounter |
| interceptor | corporate | ✓ | no | Slider/Dropper |
| weaver | corporate | ✓ | yes (core chaff) | |
| skirmisher | corporate | ✓ | yes (core chaff) | aggressive — see Q below |
| sapper | corporate | ✓ | no | Harrier; aggressive — see Q |
| strafer | corporate | ✓ | no | aggressive — see Q |
| beam_shooter | zealot | ✓ | no | Sweeper exclusive |
| burner | zealot | ✓ | no | beam-pair exclusive |
| firecore_drone | zealot | ✓ | no | → `enemy_zealot_*` |
| firecore_cruiser | zealot | ✓ | no | → `enemy_zealot_*` |
| firecore popper | zealot | ✓ | yes? (core chaff) | RENAME (not the hazard); home zealot? |
| drifter | privateer | ? | yes (core chaff) | groups with dart |
| frigate | privateer | ? | maybe | broadside merc anchor |
| hover | corporate | ? | yes (core chaff) | loiter gunner |
| crystal | zealot | ? | yes (core chaff) | or RETIRE (overlaps hover) |
| hunter_drone | corporate | ? | no | drone_carrier's spawn |
| minelayer | corporate | ? | no | Crosser/Dropper |
| bulwark | corporate | ? | no | regen shield = corp |
| beamer_tracker | zealot | ? | no | beam (with beam_shooter) |
| drone_carrier | corporate | ? | no | Spawner |
| cruiser | corporate | ? | **yes** (§12.1) | universal capital; home TBD |
| bomb_drone | — | — | — | **RETIRE** (dup of dart) |

**FINAL HOMES — Roman redline (2026-06-05), supersedes the `?` proposals above:**
- **privateer:** dart, minelayer
- **corporate:** gunship (elite), drone_carrier (elite), bomber, interceptor, weaver,
  skirmisher, sapper, strafer, hover, bulwark, **hunter_drone** (drone_carrier's spawn)
- **zealot:** firecore_drone, drifter, beamer_tracker, **spitter** (renamed popper, shooting
  chaff) + **elite:** beam_shooter, burner, firecore_cruiser
- **supremacy:** frigate, cruiser, crystal, **bomb_drone** (its small Diver — a dart reskin)
- `bomb_drone` RETAINED → **supremacy** CONFIRMED (Roman, 2026-06-05): a Diver reskin of dart
  (same behavior, different art), seeding supremacy's small-Diver slot with real art.
`hunter_drone`→corporate, `beamer_tracker`→zealot, and the firecore popper→**zealot**
(renamed `spitter`, shooting chaff) CONFIRMED (Roman, 2026-06-05). **All production enemies
now have a faction home** — the §12.0 redline (critical-path blocker, §15.3) is CLEARED.

Note: corporate is roster-heavy (~11) and privateer is light — but privateer is the overlay
faction (mixes into others), so a lean dedicated roster + overlay role is fine. Supremacy
seeds from frigate/cruiser/crystal + placeholders (no longer empty).

### 12.1 SHARED SIZE-CLASS / BEHAVIOR TEMPLATES (every faction fields its OWN version)
These are the common (size-class, behavior) slots every faction should have **its own hull**
for — NOT shared scenes. "Universal" = each faction owns a parallel hull (e.g. every faction
has an Escort that can Dive; a Destroyer/Cruiser presence piece). The existing enemies below
seed their HOME faction's version (§12.0); other factions get their own hull for the same
slot (existing one → convert; missing ones → gap, §14.2). The conductor picks by (faction,
behavior). Faction-specific identity pieces are §12.2.

| Enemy | Composable? | Role(s) | Note |
|---|---|---|---|
| `dart` | yes | popcorn | canonical fast chaff; the overlay workhorse |
| `drifter` | yes | popcorn | slow drifting shooter; distinct from dart |
| `weaver` | yes | pressure | s-curve + aimed; gentlest pressure |
| `hover` | yes | pressure / hold-lane | loiter gunner |
| `skirmisher` | yes | direct-challenge | aggressive advance/retreat (also supremacy-natural — see Q) |
| `crystal` | yes | pressure / area | loiter + 5-spread (candidate retire if it overlaps hover) |
| `cruiser` | bespoke→clean | **capital (presence)** | **universal encounter** — faction reskins, same behavior; fills the capital gap |
| `bomber` | bespoke→clean | **anchor / artillery** | **universal encounter** — faction reskins, same behavior; fills the anchor gap |

Residual presence gap: a *lighter* composable 32px anchor may still be wanted (the bespoke
`frigate` is the only other anchor) — minor; `bomber` covers the universal anchor slot.

### 12.2 FACTION-EXCLUSIVE (identity pieces; one faction only)
| Enemy | Faction | Role | Why |
|---|---|---|---|
| `firecore_drone` | zealot (Evantian) | pressure | ring-release IS the fire theme |
| `firecore_cruiser` | zealot (Evantian) | capital | huge fire elite |
| **firecore lane hazard** | zealot (Evantian) | area-denial | NEW scene; the faction signature |
| `bulwark` | corporate (UltraGalactic) | capital | self-regen shield = corporate hardware |
| `beam_shooter` | corporate (UltraGalactic) | anchor | tough beam platform |
| `beamer_tracker` | corporate (UltraGalactic) | anchor | tracking beam platform |
| `frigate` | privateer | anchor | broadside merc warship |
| `burner` | privateer | pressure | beam-pair merc duo |
| `strafer` | ~~supremacy~~ **corporate** | direct-challenge | head-on aggressive MG pass |
| `interceptor` | ~~supremacy~~ **corporate** | direct-challenge | dive-squad reaction test |
| `sapper` | ~~supremacy~~ **corporate** (RARE) | direct-challenge | aggressive shield-harrier |

> **SUPERSEDED (Roman redline, 2026-06-06 — see `m6b_faction_tagging_2026-06-06.md`):** strafer /
> interceptor / sapper are **corporate** (sapper a rare encounter, not chaff), per §12.0 FINAL HOMES.
> The code (`factions.gd` ENEMY_TAGS) matches this; the supremacy entries above are kept struck-through
> for history only.

### 12.3 RETIRE (redundant once core + overlays exist)
- `bomb_drone` — NOT retired (Roman 2026-06-05): retained as a **Diver reskin of dart** →
  homed to **supremacy** as its small-Diver (§12.0). Same behavior, different art.
- `gunship` / `drone_carrier` — **RESOLVED (Roman): → `elite` (128) tier, `corporate` home**
  for now (consistent with bespoke→elite, §15.4 #1). Corp elite events, not normal-wave
  presence. (`drone_carrier` is already pure-placeholder art — free to reskin. `cruiser`
  stays a universal presence piece.)
- `minelayer` — area-denial mine-dropper; could become a faction area piece or stay a hazard
  tool. Decision needed.
- `hunter_drone` — kamikaze; stays as drone_carrier's spawn OR a core direct-challenge. Keep.

### 12.4 GAPS / new variants needed
- **Composable presence tier** (12.1 gaps): the anchor + capital roles are currently all
  bespoke. To let factions field presence via overlay, we likely need 1 composable anchor +
  1 composable capital chassis (new, or convert a clean bespoke one).
- **Per-faction role coverage:** because core chaff is faction-agnostic, most per-faction
  chaff gaps are filled *automatically by overlay* (corporate dart = dart + Shield, no new
  art). Real gaps are the *exclusive identity pieces* — confirm each faction has at least one
  memorable exclusive (firecore ✓ drone/cruiser/hazard; corporate ✓ bulwark/beamers;
  privateer ✓ frigate/bomber/burner; supremacy ✓ strafer/interceptor/sapper).

### 12.5 NAMING COLLISION to resolve in the reorg (§11)
"firecore" is overloaded 4 ways: the **firecore faction** (Evantian), `firecore_drone` +
`firecore_cruiser` (fire-themed exclusives), the new **firecore lane hazard**, AND the COMMON
chaff `enemy_firecore.tscn` (a generic diagonal popper, thematically unrelated). Proposal:
rename the popper to a neutral name (e.g. `spitter`/`popper`) and keep `firecore_*` for the
firecore faction so the name finally means one thing. **Confirm.**

### 12.6 Open questions for the redline (see also §13 — behaviors)
1. The 12.2 faction assignments — correct the lore calls (esp. corporate vs privateer for the
   heavy hulls).
2. 12.3 `gunship`/`cruiser`/`drone_carrier` — re-home, rebuild composable, or retire?
3. 12.5 rename the `firecore` popper chaff?
4. Should `skirmisher`/`sapper`/`interceptor` be core direct-challenge (faction-agnostic) or
   supremacy-exclusive? (They're aggressive but composable.)

---

## 13. Behavior taxonomy — the attach layer (Roman, 2026-06-05)

**Decouple behavior from enemy.** A **behavior** is a first-class, named locomotion + firing
posture (≈ a consolidated movement pattern + a fire-window rule). **Chassis declare which
behaviors they're eligible for** (`behaviors: [...]`); the conductor requests a behavior for
a slot and resolves it to an eligible chassis from the active faction pool, then applies the
faction overlay + a Weapon (§9.2). This means: add a chassis to a behavior, add a behavior,
or reserve a hard behavior for deep sectors — all without touching enemy code. Replaces the
roster's single `movement` string with an eligibility list; supersedes the looser "roles"
sketch in §9.1 (roles survive only as a coarse *pacing* tag — popcorn/anchor/etc. — that the
conductor uses to structure a level; behavior is the concrete attach point).

**Behavior = {name, locomotion (movement pattern), fire-window posture, typical role}.**
Firing TIMING is the behavior's (path-phase vs on-hold); firing CONTENT (projectile/rate/
pattern) is the swappable Weapon's. Grounded in the existing pattern library (§4) so it's
directly implementable. Three structural kinds: **base behaviors** (a locomotion), **modifier
traits** (compose onto a base), and **hybrids** (a base + an exit behavior).

### 13.1 Base behaviors
| Behavior | Locomotion (pattern) | Fire window | Typical role |
|---|---|---|---|
| **Diver** | straight down a lane, no stop/switch (lane STRAIGHT) | path-phase | popcorn |
| **Drifter** | a *slow* Diver (lane STRAIGHT, low speed) | path-phase | popcorn |
| **Weaver** | continuous lateral weave while descending (lane WEAVE / s_curve) | path-phase | popcorn/pressure |
| **Shifter** | descend to a point, then a discrete horizontal SHIFT to a new lane — more horizontal than Weaver, not constant (lane HOOK/STEP) | path-phase | popcorn/pressure |
| **Skirmisher** | advance → stop → fall back (advance_retreat) | on-hold | pressure / direct-challenge |
| **Holder** | descend → loiter & fire → exit (loiter) | on-hold | pressure |
| **Anchor** | descend to a band & HOLD (presence) (slow_advance / lane HOLD) | sustained | anchor (presence) |
| **Sweeper** | settle at altitude, sweep L↔R (SWEEP — new §4) | sustained sweep | anchor / area-denial |
| **Crosser** | enter from a side, traverse across (side_traverse/cut) | broadside / none | area / pressure |
| **Striker** | move into the lane most likely to hit the player; wants to COLLIDE — non-omni lane-kamikaze (NEW: lane-seek + descend) | none / contact | direct-challenge |
| **Hunter** | omni pursuit toward the player, commits (beeline) | aimed / contact | direct-challenge |
| **Harrier** | omni: set a stand-off distance, hang & shoot, then exit via a lane OR pull back & leave (omni_thrust) | sustained | direct-challenge / pressure |
| **Charger** | wind-up → COMMITTED dive, follows through (jet_charger) | none / on-charge | direct-challenge |
| **Slider** | a Charger that DIVERTS off the player at the last second — feint (top_dive; interceptor's current) | none | direct-challenge |
| **Dropper** | descend a lane seeding hazards behind it (lane + Dropper/DropFirecore comp) | drop | area-denial |

### 13.2 Modifier traits (compose onto a base behavior)
- **Dodger** — reactive lateral shot-avoidance: sidesteps within lanes when an incoming
  bullet threatens. Rides on a descender (dodger-diver, dodger-weaver). **NEW capability** —
  reads incoming projectiles; no current pattern does shot-dodging (jet/omni only avoid
  walls). Likely a **component** (or a movement wrapper), not a standalone locomotion.

### 13.3 Hybrids / exit-chaining
Some behaviors are a primary/active phase + an **exit** phase that is itself another behavior
(Roman: harrier-diver, harrier-skirmisher). Modeled as `{primary, exit}` (e.g. Harrier hangs
& shoots, then exits as a Diver, or pulls back like a Skirmisher). lane_path/loiter already
expose enter/hold/exit phases, so this is a natural extension, not new machinery.

**Notes / open for redline:**
- A chassis lists *several* behaviors (a Gunship might be Skirmisher AND Sweeper); the
  conductor picks per slot. Deep-sector unlocks add harder behaviors to existing chassis
  ("old enemies do new things") via depth thresholds on the eligibility entry.
- The **firecore lane hazard** isn't a behavior — it's what the **Dropper** behavior +
  firecore overlay leaves behind.
- NAMING collision: **Harrier** is now a behavior, but "Corp Harrier" was used as a unit name
  in §12 — rename the unit or treat it as a Harrier-behavior unit. Flag for the redline.
- Faction-unit NAMING (Martyr/Manta/Hoplite/…) — faction-exclusive chassis get evocative
  names; core chassis read as "<Faction> <Core>" (Privateer Dart). Feeds §11 + codex.

---

## 14. Convert-first, then gap-fill (METHODOLOGY — Roman, 2026-06-05)

Many target units (the faction variants in §13/§12) **don't exist yet** — don't build them
up front. The path:

1. **Convert existing enemies** onto the system (chassis + behaviors + components + Weapon),
   per the §6 conversion order. Clean ones become composed; the 6 messy stay bespoke but get
   the death hook + identity + behavior tags.
2. **Tag each converted chassis** with the behaviors it can perform (§14.1) and its faction
   (§12).
3. **Derive the gaps:** build the **behavior × faction coverage matrix** from the converted,
   tagged set. Empty/weak cells = the new-enemy backlog, prioritized by what the conductor
   actually needs to compose levels.
4. **Author new enemies** (Martyr/Manta/Hoplite/Harrier/…) only to fill real gaps — as data
   on the existing chassis/behavior/component machinery wherever possible, new art only when
   a silhouette is genuinely missing.

So §12 + §13 describe the TARGET; this section is how we reach it incrementally without a
big-bang new-enemy push. Coverage grows mostly via **overlay** (core chaff × faction) +
**multi-behavior tagging** (one chassis fills several slots) before any new art.

### 14.1 DRAFT: existing chassis → behaviors it can do post-conversion
Mechanical, from the audit locomotions. (Bespoke = stays a bespoke script but still satisfies
the behavior slot; composable = behavior driven by a shared pattern.)

| Existing chassis | Composable? | Behaviors it can fill |
|---|---|---|
| dart | yes | Diver |
| drifter | yes | Drifter, Weaver (mild) |
| firecore popper (→rename) | yes | Diver |
| weaver | yes | Weaver |
| hover | yes | Holder |
| crystal | yes | Holder |
| skirmisher | yes | Skirmisher |
| sapper | yes | Harrier |
| hunter_drone | yes | Striker / Hunter |
| interceptor | yes | Slider, Dropper |
| minelayer | yes | Crosser, Dropper |
| firecore_drone | clean conv | Diver (+ DeathEffect comp) |
| gunship | bespoke | Sweeper, Skirmisher |
| frigate | bespoke | Anchor, Crosser |
| bomber | bespoke | Anchor, Holder |
| cruiser | bespoke→clean | Holder, Anchor |
| drone_carrier | bespoke→clean | Holder, Anchor (+ Spawner comp) |
| bulwark | bespoke→clean | Striker, Anchor |
| beam_shooter | bespoke | Sweeper |
| beamer_tracker | bespoke | Sweeper |
| firecore_cruiser | bespoke | Crosser |
| burner | bespoke | Diver/Anchor (pair) |

---

## 15. Design risks & standing questions (review, 2026-06-05)

The core model is sound; these are the tensions to resolve before/while building.

### 15.1 Real issues
1. **Bespoke enemies are single-behavior, weapon-locked exceptions.** The flexible
   faction/behavior/weapon promise assumes composable hulls. The 6 messy ones (`burner`,
   `strafer`, `frigate`, `gunship`, `beam_shooter`, `firecore_cruiser`) do ONE behavior and
   can't accept a Weapon swap (beam ⟂ locomotion). So zealot's `beam_shooter`/`burner` and
   others are inflexible cells in an otherwise-flexible matrix. **Acceptable, but make it
   explicit:** the system has two citizen classes (composable vs bespoke-single-behavior);
   don't promise the conductor it can retask a bespoke hull.
2. **Large size-classes break the lane/behavior model.** Lanes are 30px pitch (7 ≈ 216 band).
   A **Cruiser (128px) spans ~4 lanes**; a **Dreadnought (256px) exceeds the band**.
   Lane-anchored behaviors (Diver "on lane N", wall gaps) assume a hull fits ~1 lane. So
   Cruiser/Dreadnought can't use the lane/behavior system as-is. **Likely:** Cruiser =
   multi-lane mini-boss with its own movement; Dreadnought = boss/special pipeline, not a
   normal spawn. The behavior taxonomy effectively applies to Escort/Frigate/Destroyer.
3. **Supremacy is empty + aggressive units went to corporate.** Thematic incoherence (the
   fast-fire faction has no aggressors; corporate inherits the aggressive identity) + a big
   content gap + roster imbalance (~12 corporate homes, 0 supremacy). **Standing decision.**
4. **Boss HP-unify churn.** Retiring boss `hull`/`hull_changed` → base `health` + Shield
   component touches every boss + the boss HUD — risky change to a stable system for a dedup
   win. **Reconsider:** maybe bosses keep their hull; only new/converted regular enemies use
   the unified path. Add `health_changed` to base for the new path without forcing bosses off.
5. **Conversions are bigger than "parity."** Each enemy changes name + folder + faction + HP
   plumbing + behavior tags at once — "same enemy, now composed" is optimistic. Sequence so
   only ONE axis changes per commit where possible (e.g. convert behavior first, rename later).
6. **Conductor selection complexity + run-seed determinism.** Selecting by (faction pool ×
   behavior eligibility × depth × size × role-pacing) is a substantial producer rewrite, and
   the pick MUST use the run-seed RNG (the current `make_movement` uses bare `randf()` —
   non-deterministic). Real scope; easy to break reproducibility.

### 15.2 Lower-severity / interaction questions
7. **Intra-faction visual sameness (one-per-cell).** If one hull per (faction × size), a
   faction's Escort looks identical across all its Diver/Striker/Dropper appearances —
   behaviors vary motion, not silhouette. Is that enough variety, or allow 2 hulls per cell?
8. **Faction-mechanic monotony + readability.** Every corporate fight = chew shields; every
   zealot fight = firecore lanes. Risk of repetitive feel; tint helps read but mechanic
   sameness within a faction could grind. Worth a "secondary flavor" knob later.
9. **Privateer overlay underspecified.** In a privateer LEVEL, are all enemies tough, or only
   privateer's own units? When privateer units inject into another faction's level, do they
   gain that faction's mechanic too (tough + shielded)? Do mechanics STACK?
10. **Firecore flood + cap interaction.** Hazards are excluded from the concurrency cap
    (`director._alive_count`), so a dense zealot level dropping firecores on death could flood
    lanes. Needs a drop-rate + max-firecores-on-screen cap.
11. **Beams don't fit the swappable-Weapon model** (continuous-effect, no projectile/rate) —
    supremacy fast-fire can't modify them. Another bespoke exception to state explicitly.
12. **Codex / encountered-enemies churn.** Renames + new ids break `Run.encountered_enemies`
    keys + codex; the internal-id vs display-name split needs codex plumbing.

### 15.3 Critical path note
Reorg (§11) and conversions depend on the §12 tagging being LOCKED — which depends on the
supremacy decision (#3) + the `?`-home redline + one-per-cell (#7). **The §12.0 redline is the
critical-path blocker** for everything downstream of the (independent) visualizer + inert
base-layer work.

### 14.2 Gap derivation (run AFTER §12 + §13 are redlined)
Lay the §14.1 behaviors against the §12 faction assignments → a behavior × faction grid.
- Core-agnostic chaff covers **Diver/Drifter/Weaver/Holder/Skirmisher** for ALL factions via
  overlay (no new art); the universal `cruiser`/`bomber` encounters cover **Capital/Anchor**
  per faction via reskin (§12.1).
- Remaining gaps cluster in **Sweeper** (gunship/beamer are bespoke + not yet universal) and
  in each faction's **memorable exclusive**. Those empty cells become the prioritized
  new-enemy backlog → fed into M6b authoring.

---

## 15.4 Review resolutions (Roman, 2026-06-05)
- **#1 bespoke = two-class** — acknowledged; **bespoke enemies become `elite` (128) special
  EVENTS** (beamers/burners as elite encounters), not matrix filler. Resolves the tension.
- **#2 large sizes** — confirmed: behaviors apply to the small end (tiny/small/medium; large
  presence-only). Size ladder reworked to **tiny(8)/small(16)/medium(32)/large(64) +
  elite(128) + boss(256)** — size-WORDS, not ship-classes (§8). bespoke → elite (see #1).
- **#3 supremacy** — expected (least-developed faction). **Placeholder reskins + placeholder
  art for now** to keep moving; real supremacy sprites later. Placeholders are **multi-tagged
  for the common behaviors** (Diver/Skirmisher/Holder/…) to fill the matrix cheaply;
  carefully-authored unique units follow. Corporate keeps its homes.
- **#4 bosses** — **leave bosses as bosses**: no behavior assignment, **keep their `hull`
  system**. HP-unify (`health_changed`/Shield) applies ONLY to new/converted regular enemies.
- **#5/#6 over-complication** — resolved via the **distilled composer** (§16): composer thinks
  only in (size, behavior, count, pacing); faction = a table swap + one flat modifier;
  weapons/components ride on the hull, not the composer.
- **#7 sameness** — fine; sprites are semi-unique per faction, identity holds.
- **#8 monotony** — the tough/shield/fire-rate modifiers are meant to feel cohesive, not grind.
- **#9 privateer** — **privateer units are tough ONLY**; they do NOT make the units they're
  mixed with tough. Mechanics don't infect the host (adds built-in variety).
- **#10 firecore flood** — add a **firecore density meter**; density drives the drop chance
  (self-limiting). 
- **#11 beams** — make **beams more versatile, available to more factions** (not a one-off
  bespoke exception).
- **#12 codex** — **full overhaul later; disable the codex** until then.

---

## 16. Distilled composer model (Roman #5/#6 answer, 2026-06-05)

The composer does NOT juggle six axes. It reasons in **`(size, behavior, count, pacing)`** —
the wave/phrase structure we already have, re-expressed. Faction collapses to two cheap ops:

1. **Faction = one choice per level.** It provides a lookup **`(size, behavior) → that
   faction's own hull`**. Composer wants "a small Diver" → asks the active faction's table →
   `enemy_privateer_small` (tagged Diver-eligible). The composer never iterates factions.
2. **Faction mechanic = one flat level modifier**, applied uniformly to every spawn in ONE
   place: corporate→shielded, supremacy→×k fire-rate, zealot→drop-on-death, privateer→tough
   (privateer's own units only, #9).

What this REMOVES from the composer (kills the bloat):
- **Visual identity is automatic** — the resolved hull IS the faction's sprite. No runtime
  overlay/tint gymnastics.
- **Weapons + components ride on the hull** (authored in), not composer decisions. **Drop
  per-spawn weapon-swapping from the core loop** — it becomes an optional *sector-modifier*
  lever later. (Also dissolves the beam-swap problem for the core path.)

Result: composer juggles **4 things** (size, behavior, count, pacing) + a table lookup + a
flat modifier. Full faction identity, no combinatorial blowup. This supersedes §9.2's
"swappable weapon as a core composer axis" — weapons are hull data; faction fast-fire is the
only weapon-level modifier the composer applies, and it's flat.

**Pick determinism:** when multiple of a faction's hulls satisfy a (size, behavior) slot, the
choice uses the **run-seed RNG** (resolves #6's determinism trap; never bare `randf()`).

---

## 17. DOC HYGIENE — needs a consolidation pass
This doc grew across many design pivots and now has **superseded layers** that contradict the
current model — they should be reconciled before the doc is treated as final:
- §8/§10/§12 still carry the old **"core-agnostic shared scene + runtime overlay"** framing,
  which §8-rewrite + §16 (faction-owned rosters, per-faction hulls) SUPERSEDE.
- §12.0/§12.1/§12.2 (home/exclusive/universal columns) predate the faction-owned-roster +
  size-word model → should be rebuilt as the **faction × size matrix** (per-faction roster
  seeds + behavior tags) once supremacy + `?`-homes + one-per-cell settle.
- §11 naming options A–D + §8 ship-class names predate the **size-word** decision.
- §9.2 "swappable weapon as core axis" is demoted by §16.
Recommend a single consolidation pass to collapse §8/§10/§12 into one coherent
faction-roster + size + behavior + composer spec once the §12 redline lands.
**The consolidation target is §19 (streamlined model)** — rewrite §3/§8/§9/§13 to match it
(behavior=pattern, Shield+Emitter only, faction-as-data, no tier/role).

---

## 19. STREAMLINED MODEL — LOCKED (Roman, 2026-06-05)

A review-driven simplification. **This is the authoritative axis list; it supersedes the
scattered/earlier framings in §3/§8/§9/§13** (which the §17 consolidation should rewrite to
match). Net effect: leaner AND more extensible, no lost function.

### 19.1 Final axes (minimal)
- **Chassis = size-class** → stats/hitbox: tiny(8)/small(16)/medium(32)/large(64)/elite(128)/
  boss(256). No `tier`, no `role` (see 19.4).
- **Pattern (= behavior)** — a behavior IS a named movement pattern with its fire-window built
  in (path-phase / on-phase / sustained are pattern properties, already how `enemy_core`
  works). **(A)** Chassis declare `patterns: [...]` (the old `behaviors[]`/`allowed_movements[]`,
  now one concept). The conductor requests a pattern; the faction table resolves it to a hull.
  Hybrids = composite patterns (enter/exit phases). Removes the separate "behavior" layer.
- **Weapon** — hull-owned `{projectile, rate, fire-pattern}`. Beams + contact-detonate are
  **weapon types**, not components (see 19.2).
- **Components — just TWO: `Shield` + `Emitter`. (B)**
  - `Shield` — participates in the damage pipeline (regen pool, charges). The one defensive comp.
  - `Emitter` — **emit a payload on a trigger**, parameterized:
    `{payload ∈ {drone, turret, mine, firecore, bullet_ring}, trigger ∈ {start, timer, death},
    count, cadence, chance}`. Collapses Spawner / CarriedTurrets / Dropper / DropFirecore /
    DeathEffect-ring into one. A new "drops/spawns X" enemy = DATA, not a new component.
    (Keep the payload set a small explicit enum — not an arbitrary-scene god-object.)
- **Faction = pure DATA. (C)** `faction = {hull_roster, modifier:{components:[...],
  stat_mults:{}, weapon_mults:{}}, tint, lore_name}`. Examples: corporate
  `{components:[Shield]}` · zealot `{components:[Emitter(firecore,death,chance)]}` · privateer
  `{stat_mults:{hp:2}}` · supremacy `{weapon_mults:{rate:0.6}}`. A new faction or a rebalance =
  a data edit, ZERO code.

### 19.2 The composer (unchanged shape, smaller inputs)
`(size, pattern, count, pacing)` → faction table `(size, pattern) → hull` → apply the faction
modifier (data) → spawn. Determinism via run-seed RNG when multiple hulls match.

### 19.3 Authored vocabulary (the whole surface)
**size-class · pattern(=behavior) · weapon · {Shield, Emitter} · faction-data.** That's it —
small surface, large variety.

### 19.4 Dropped axes (D/E — confirmed redundant)
- **`tier` (COMMON/UNCOMMON/RARE) → DROP.** Bounty/threat = size-class; availability =
  depth/sector unlock + faction pool; "which size when" = composer pacing. (Replaces the
  producer's `_roll_tier` / `RARITY_BOUNTY_MULT` / `entries_eligible(tier)` in the rewrite.)
- **`role` (popcorn/anchor/…) → DROP as an enemy axis.** Derivable from (size, pattern);
  pacing INTENT (filler vs threat) lives in the composer's beat decisions, not a per-enemy tag.

### 19.5 Extensibility that falls out
- **Emitter** → new emit-behaviors are data.
- **Faction-as-data** → new factions are data.
- **Elite events reuse the M5 heavy-beat scheduler** (coda/midpoint beats) drawn from each
  faction's elite pool — no new scheduling system.
- **Components on `enemy_base`** → bosses can later opt into `Shield`/`Emitter` (shields,
  minion-spawning) without the behavior/composer system.

---

## 18. Sprite / asset inventory (audit, 2026-06-05)
What art each current enemy actually uses (drives reskin/home/art cost). Size inferred from
the asset's own name prefix — **the art is already size-prefixed** (small_/medium_/tiny_),
which aligns with the size-word scheme. Confirm real px dims at convert time.

**Dedicated art (real, purpose-made):** dart=`small_dart` · drifter=`small_manta` (= "Manta")
· firecore popper=`small_firecore` · hover=`small_hover` · weaver=`small_weaver` ·
skirmisher=`small_skirmisher` · sapper=`small_sapper` · strafer=`small_strafer` ·
bomb_drone=`drone_bomblet_jet` · hunter_drone=`drone_bomblet_omni` · firecore_drone=
`drone_firecore` · burner=`medium_burner` · beam_shooter(+beamer_tracker inherited)=
`enemy_beamer` · frigate=`enemy_frigate` · gunship=`enemy_gunship` · bomber=`enemy_bomber` ·
interceptor=`enemy_inteceptor`(sic) · minelayer=`enemy_minelayer` · firecore_cruiser=
`firecore_cruiser`.

**Generic / borrowed (semi-placeholder):** bulwark=`extra-ships/tiny_ship11` ·
crystal=`extra-ships/ship_4` (SHARED with boss_spinwright — not dedicated).

**Pure placeholder (no real art):** cruiser=`enemy_placeholder_64x` · drone_carrier=
`enemy_placeholder_64x` (SAME placeholder). → free to reskin/re-home; drone_carrier→elite/corp
costs nothing artistically; cruiser's universal-reskin is unconstrained.

Implication: the "dedicated" list is real move/reskin work; the generic + placeholder ones are
free to re-home. Asset names also seed display names (Manta, Dart, Skirmisher, …).
