**✅ ARCHIVED 2026-06-15 — this shipped; historical design doc.** Current behavior: merged to main; see CLAUDE.md "Combat flow".
Do not cite as a to-do.

# Combat Construction Plan — Lanes × Streaming

Status: **construction layout.** Turns the canonical contract
(`docs/combat_lane_wave_bridge_2026-06-03.md`) into concrete files, classes, and an
incremental build order, anchored to the current code (read-only scans, 2026-06-03).

Parents: bridge (canonical) · `lane_system_spec_2026-06-03.md` ·
`wave_streaming_variety_spec_2026-06-03.md`.

---

## 0. Key architectural findings (from the scans)

1. **The materializer is salvageable.** `director.gd:110-248` (`_spawn_enemy`)
   instantiates, applies overrides, applies `_apply_sector_modifiers`
   (`director.gd:253-282`), places by formation (`director.gd:170-224`), emits
   `enemy_spawned`. **It has no coupling to the walk** → keep it; replace only the
   walk around it.
2. **The walk is the replaceable part:** `_advance_to_next_wave`
   (`director.gd:45-68`), `_spawn_next` (`director.gd:70-95`),
   `_wait_for_clear_then_advance` (`director.gd:98-108`), and the level-complete
   watcher in `_process` (`director.gd:284-288`). The `silent`-flag chaining
   (`director.gd:82-83`) is a de-facto "phrase" already.
3. **`lane_path` needs no base-class change.** `movement_pattern.gd:29-44` contract
   (`on_start`, `compute_step→Vector2` position-delta) is satisfied by the
   boss_sweep pattern (`patterns/boss_sweep.gd:24-46`, anchor in `on_start`, returns
   `target-position`). Mirror has precedent (`patterns/s_curve.gd:13` `mirrored:bool`).
4. **Per-instance isolation already happens:** `enemy_core.gd:68`
   `_pattern = movement.duplicate()` — so per-spawn params (anchor, mirror) must be
   set on a **duplicated** Resource before `start()` (precedent: side direction dup
   at `director.gd:218-221`).
5. **Speed clamp is name-driven:** `_apply_sector_speed_scale`
   (`enemy_core.gd:91-118`) only scales+clarity-clamps exports named
   `speed`/`*_speed`/`accel`/`drift_x`. **lane_path's speed export MUST end in
   `_speed`** or the 8 px/f ceiling won't apply.
6. **No render-plane field exists.** Enemies have no `z_index` (scene-tree order
   only); both shadow systems are globally OFF (`parallax_shadow.gd:22`,
   `shadow_fx.gd:12`). Altitude cue (bridge §7) is genuinely new work.
7. **No pooling** anywhere; single spawn site `director.gd:114`. Streaming wants a
   pool eventually — additive, one site to change.
8. **Signal contract to preserve verbatim:** `enemy_died`, `enemy_spawned`,
   `wave_started(idx,total,silent,text)`, `level_cleared` (`director.gd:7-10`),
   consumed by `main.gd:77-84` AND `ui.gd:436-439`. `wave_started.total` feeds
   banners + music progress — do not change its meaning.
9. **Single producer chokepoint:** every `LevelData` originates in `main.gd`
   `new_game()` (`main.gd:404-487`) — WaveGen and all `Levels.build_*`. An adapter
   here can lift flat arrays into the new score with hazards/showcases untouched.

---

## 1. Component inventory

### New files
| File | Role |
|---|---|
| `scripts/lanes.gd` | `class_name Lanes` (mirrors `playfield.gd`): `COUNT=7`, `WIDTH=24`, `GAP=6`, `lane_center(i)`, `nearest_lane(x)` + hysteresis, `lane_span_fits(anchor, delta)`. Pure static math. |
| `scripts/enemies/patterns/lane_path.gd` | `extends movement_pattern.gd`. Deterministic lane-relative path; `mirrored:bool`; `traverse_speed` (note `_speed`); reads lane anchor from enemy instance; returns `target-position` deltas. |
| `scripts/levels/phrase.gd` | `class_name Phrase extends Resource`. `kind: {FORMATION,FILLER,BREATHER}` + the per-kind fields (bridge §2). |
| `scripts/levels/combat_score.gd` | `class_name CombatScore extends Resource`. `waves: Array[ScoreWave]`; each ScoreWave = identity (banner/faction/mix) + `phrases: Array[Phrase]`. The "level score" (bridge §3.1). |
| `scripts/levels/conductor.gd` | The dispatcher + lane reservation table + cap budgets. Replaces the walk; **calls the kept materializer**. (See §3 — likely lives *inside* the evolved director, not a separate node.) |
| `scripts/levels/score_adapter.gd` | Lifts a flat `LevelData.waves` array → `CombatScore` (back-compat for WaveGen v1 + all hazard/showcase builders). |

### Modified files
| File | Change |
|---|---|
| `scripts/levels/director.gd` | Replace the walk (`:45-108`, `:284-288`) with the conductor/dispatcher; **keep `_spawn_enemy` `:110-248`**; keep signals `:7-10`. Add lane-formation placement case in `_compute_spawn_pos` (`:170-224`). Add per-enemy `z_index`/plane assignment near `:227`. |
| `scripts/main.gd` | In `new_game()` (`:404-487`): wrap every produced `LevelData` through `score_adapter` (or have WaveGen v2 emit `CombatScore` directly); pass score to `start_level` (`:552`). Behind the rollout flag. |
| `scripts/run_state.gd` | Terminology debt: `is_row_pois_complete`→`is_route_pois_complete` etc. (bridge §0). Mechanical rename. |
| `scripts/levels/wave_generator.gd` | v2: emit phrase-structured `CombatScore`; replace `clamp(count,…)` ceiling (`:439`) with composition-first budget (bridge §4). Big, later milestone. |

### Kept as-is (do not touch in early milestones)
- `_spawn_enemy` + `_apply_sector_modifiers` (`director.gd:110-282`) — the materializer.
- `movement_pattern.gd` base contract — unchanged (lane state rides on the enemy
  instance, not a new arg).
- `enemy_core.gd` `_process` apply-step + sector-scale + clarity clamp.
- `WaveSpec` (`wave_def.gd`) + `Formation` enum — reused; lane is a new placement case.
- All `Levels.build_*` hazard/showcase builders — they flow through the adapter.

---

## 2. The lane_path movement Resource (LANE side, isolated)

Slots into the existing override path (`director.gd:126-127` sets `enemy.movement`),
so it is **testable with zero conductor code**:
- `on_start(enemy)`: capture lane anchor (either from `enemy.position.x` boss_sweep-
  style after the conductor places the enemy on a lane, or from an export set on the
  duplicated copy). Idempotent (re-called after recycle fly-back).
- `compute_step(enemy, delta)`: advance local `_t`; `target_x = anchor_x +
  sign*lane_offset(_t)`; `target_y = ... + traverse_speed*...`; return
  `Vector2(target_x, target_y) - enemy.position`.
- `mirrored: bool` → `sign = -1 if mirrored else 1` (s_curve precedent).
- Path itself: start with a **closed-form** set (straight, weave ±N, hook ±N, hold-
  then-go) before a keyframe format. Lane-span metadata (bridge open item) lives as
  exports the conductor reads for legal placement.
- **Gotchas:** name the velocity export `traverse_speed` (for clarity clamp, finding
  §0.5); set `enemy.allow_side_exit`/`offscreen_mode` if a path exits a side
  (`side_traverse.gd:15` precedent); if the path drives its own heading, leave
  `auto_rotate=true` so banking is free (lane spec §1.4) — only omni/jet patterns
  disable it.

---

## 3. The conductor / dispatcher (the walk replacement)

**Recommendation: evolve `director.gd` in place** rather than add a parallel node —
because it already owns the materializer, the signals, and the `$WaveDirector` scene
slot (`main.gd:57`). The conductor logic becomes the director's new "brain."

Responsibilities (replacing `director.gd:45-108` + `:284-288`):
- **Density-gated phrase dispatch** (bridge §1.1): walk `CombatScore` phrases; for a
  Formation, wait until lane-budget headroom ≥ size then spawn the group; Filler
  trickles per-enemy while `lane_alive < cap`; Breather withholds; dead-air guard
  injects Filler.
- **JIT placement** (bridge §1.2): maintain a **lane reservation table** (live
  footprints); pick legal `(anchor, mirror)` per spawn; call the kept `_spawn_enemy`
  with the chosen lane → it materializes.
- **Cap budgets** (bridge §1.3): `lane_budget` + `free_plane_budget` under the
  global cap (ramp 12→16); per-lane density cap + safe-lane derive from it.
- **Level-complete** (replaces `:47-50`/`:284-288`): "**score exhausted** AND no
  live combatant AND no hazard" → emit `level_cleared` (reuse
  `_live_combatants_present`/`_hazards_present` `:297-312` verbatim).
- **Signals unchanged.** Map `wave_started(idx,total,…)` to the ScoreWave level so
  `total` = wave count (banners/music keep working).

---

## 4. Rollout strategy — inert-to-main + atomic branch swap

**Decision (Roman, 2026-06-03): no incremental gameplay rollout.** Half-built combat
states are regressions, so they never ship to `main`. The work splits:

- **Inert foundations → land on `main` as normal commits (no flags, no risk).**
  New files/fields that change NO current behavior: `lanes.gd`, `lane_path.gd` (a
  Resource nothing references yet), enemy identity fields + `hit_taken` signal,
  render-plane plumbing, the `row→route` rename. Landing these early kills branch
  drift and delivers the run-summary hooks (§7) immediately.
- **Behavioral core → a worktree branch, merged atomically when whole.** The
  conductor (replacing the walk), `CombatScore` (replacing the flat array), WaveGen
  v2, and the hazard conversion. This is the part that changes the game; it swaps in
  as one piece.
- **No A/B flag.** Dropped — it only existed to support incremental rollout. Removing
  it keeps `main.gd` single-path.
- **Adapter is transient, internal to the branch.** `score_adapter` may lift
  not-yet-converted builders DURING the branch build, but the END STATE converts
  every producer (incl. hazards, §4.1) to emit `CombatScore` natively. No permanent
  back-compat layer.
- **Verification replaces live-rollout feedback:** the combat tuner (bridge §8), the
  `sim_wavegen`/`sim_stream` sims, capture GIFs, and the headless smoke test are the
  gates between branch milestones.

### 4.1 Hazards are first-class under the new system (Roman, 2026-06-03)
Minefield/asteroid levels are **converted to `CombatScore`**, not kept bespoke behind
an adapter. Their enemy composition + identity stays unique (specific mine/asteroid
mixes), but they run through the **same conductor** so the lane system + dispatch make
them interesting (revises wave §10.5 / bridge open item). `Levels.build_*`
(`levels_v2.gd`) get rewritten to emit phrase-structured scores.

**DONE (2026-06-05):** `build_minefield_score()` / `build_asteroid_field_score()` emit
phrase-native `CombatScore`s (lane-shaped WALL/PINCER/SPREAD drops + BREATHERs, one banner)
routed via `main.gd` `_current_score`; the old `formation_padding` template catalog (which the
conductor lane-snapped away) is retired. Mines/asteroids self-drift, so no movement_override.
Tests: `tools/test_hazard_score.gd` (well-formed) + `tools/test_hazard_run.gd` (streams via the
real director). Open knob: hazards stay excluded from the concurrency cap (terrain pacing).

---

## 5. Build order (each milestone independently testable)

**Rollout split (§4):** M0–M2 are **inert → land on `main`**; M3–M6 are the
**behavioral core → worktree branch, atomic merge.**

- **M0 — Foundations (no behavior change):** `lanes.gd` + unit-ish checks; the
  `row→route` rename (`run_state.gd`); add per-enemy `z_index`/plane field plumbing
  (default = current order). Ship-safe.
- **M1 — lane_path movement (visible, isolated):** `lane_path.gd` + lane-formation
  placement case in `_compute_spawn_pos`. Test via a hand-authored WaveSpec with
  `movement_override` — **proves lane movement with no conductor**. First GIF.
- **M2 — Altitude render plane (parallel, optional):** per-enemy z by tier; re-enable
  a shadow path for the "above the deck" cue (bridge §7). Cosmetic, low-risk.
- **M3 — Score model + adapter:** `phrase.gd`, `combat_score.gd`, `score_adapter.gd`;
  route all `LevelData` through it at `main.gd` chokepoint. Director still walks the
  lifted structure transparently — **no gameplay change**, just the new data spine.
- **M4 — Conductor/dispatcher (behind flag):** the §3 brain. Density-gated dispatch,
  JIT reservation placement, cap budgets, new level-complete. A/B vs legacy walk.
- **M5 — Budget allocator + curve + hazards: ✅ DONE (2026-06-04).** Composition-first
  soft-band budget + difficulty curve + heavy beats (merged). **Native emission:**
  `WaveGen.build_score()` emits `CombatScore`; the producer chokepoint (`main.gd`
  new_game) lifts every level (combat/boss/hazard/custom) and `start_score`s it, so
  the director no longer transiently lifts `LevelData` on the production path
  (`start_level` is now a compat shim; `ScoreAdapter` is the shared producer-side
  builder, kept as the DRY assembly home). `build()`/`start_level`/`from_level_data`
  retained for tests + `sim_wavegen`. (`sim_wavegen` phrase/variety metrics live in the
  other session.)
- **M6 — Variety/faction/telegraph/tuner layers:** intro schedule, faction tint,
  unified telegraph (bridge §6), the single combat tuner (bridge §8), pooling
  (finding §0.7). **Split: M6a modular enemy refactor → M6b faction layer (§10)** —
  composable behavior is the prerequisite that makes factions cheap.

---

## 6. Decisions — locked vs still open

**Locked (Roman, 2026-06-03 — deferred to recommendations):**
- ✅ **Fork A — Conductor placement:** evolve `director.gd` in place (§3).
- ✅ **Fork B — Score model:** new `Phrase`/`CombatScore` Resources; adapter is
  transient-internal only (§4).
- ✅ **Rollout:** inert foundations → `main`; behavioral core → atomic branch (§4).
- ✅ **Hazards:** converted to `CombatScore`, run through the conductor (§4.1).
- ✅ **lane_path representation:** closed-form curves first; keyframe format deferred.
- ✅ **Altitude render:** re-enable an existing (disabled) shadow path for the cue.

**Still open (content/curve — needed by M5/M6, not M0–M4):** formation roster, the
`B` soft-band curve + per-wave phrase mix + elite-fraction curve, intro schedule,
recycling-vs-cap accounting, node-type roster rework (bridge §9).

**Deferred architecture (post-M5, pre-faction — §10):** modular enemy model
(chassis + movement repertoire + weapon set + signature + faction), which means
**re-classing enemies as compositions** rather than bespoke monoliths. Logged §10;
slotted as M6a before the faction layer.

---

## 7. Run-summary accommodations (cheap hooks only — NOT the feature)

Cross-ref `docs/run_summary_scope_2026-06-01.md`. We are **not building the
summary.** But our combat work already stands in the code paths its "new
instrumentation" tier needs, so we leave clean hooks now to shrink that future build
(its Phase 2 is ~1–1.5 days, much of it removable by these). Scope discipline:
**define the hook, do not accumulate, do not surface.**

### 7.1 Canonical enemy identity — HIGH value, ~free (in our path already)
We already assign chassis/faction/tier at spawn (materializer `director.gd:110-248`
+ the faction system, bridge §6). Standardize a small identity block on
`enemy_base` and set it **once in the materializer**:
- `chassis: StringName`, `faction: StringName`, `tier: int`,
  `category: enum {CHAFF, ELITE, MINE, ASTEROID, BOSS, …}` (folds in the existing
  `is_hazard`/hazard subtype).
- **Pays off for the summary:** "unique enemy types", per-type tally (reuses
  `cleared_summary.gd` sprite-preview UI), "mines cleared", "asteroids destroyed",
  "boss kills" all become **field reads instead of `scene_path` string-matching**
  (the run-summary Tier-2/Tier-3 pain, scope §50/§53). Also feeds the existing
  `Run.encountered_enemies` codex consistently.
- **Milestone:** define the fields in **M0–M2** (the tier→plane mapping in M2 needs
  `tier`/`category` anyway); populate progressively (tier/category early — they
  exist today; faction at M6). The win is **fixing the SHAPE now** so later systems
  just fill it.

### 7.2 Keep `enemy_spawned`/`enemy_died` as the single combat firehose — free
We already preserve these verbatim (finding §0.8). Make it an explicit rule: the
conductor is the one choke-point every combat enemy passes, so a future `RunStats`
combat-side accumulator subscribes **here only** — don't fragment kill/bounty
accounting across systems. If 7.1 lands, category rides these signals (or is read
off the dying node), so kills-by-category needs no extra instrumentation.

### 7.3 Optional: `hit_taken` signal on `enemy_base.take_hit` — cheap IFF already in M2
`take_hit` (`enemy_base.gd:202`) returns a bool and emits nothing — the exact hook
the summary's accuracy stat needs ("1 hit = 1 contact in take_hit", scope §48/§67).
M2 already edits `enemy_base`; adding `signal hit_taken(damage, fatal)` is near-free.
**Hot-path discipline (scope §47 warns):** emit only, **no per-hit allocation**;
with no listener connected it's negligible. Mark optional — only if M2 is already in
this neighborhood; don't make a special trip.

### 7.4 Explicitly OUT of scope (not in our path — leave for the summary build)
Player shots-fired (`player.gd` fire), damage-taken (`Player.damaged` exists),
bounty-spent (outpost), locations/stations/signals visited (sector map), unique
weapons used (loadout). Our work never touches these — do **not** bolt them on here.

---

## 8. Playtest-driven refinements (Combat Slice feedback, 2026-06-04)

Slice playtest confirmed conductor v0–v3 + shapes working. Open refinements
surfaced (Roman):

- **[conductor] Speed-aware / clear-time pacing.** Phrases advance on spawn-count,
  not on whether prior enemies have cleared — so a faster unit (dart) overruns a
  slower formation. The conductor should reason about clear-time (speed × screen
  distance) to pace phrases. *Interim slice fix:* filler uses a slower `lane_path`
  + a breather gap so it trails the formation instead of overtaking it.
- **[firing] Path-phase firing model — NEXT conductor-side milestone.** Enemies
  fire on their default random timers ("too late"). Implement path-phase firing
  (e.g. fire at 30%/70% of the path) + the shared beat (bridge §1.8).
- **[roster] Enemy role taxonomy.** Dart + bomb_drone are *reaction-testers*
  (direct-challenge role), NOT chaff/filler — fast units that overtake and demand
  reaction. WaveGen v2 should assign roles (popcorn/pressure/area-denial/
  direct-challenge, comp guide §2) and keep fast units out of filler pools.
- **[shapes] `lane_path` HOOK for forced lane commitment.** WEAVE = visual
  distraction (keep); HOOK (move-to-lane-and-hold) forces a commit. Needs the
  conductor to pick hook direction per spawn lane (toward/away from center).
- **[cap] Depth-ramp not wired.** `max_concurrent` is flat 14; ramp 12→16 by depth
  (comp guide §9). The ceiling is clarity (480×270 + 8px/f), and it's tunable. *(DONE
  2026-06-04: `WaveGen.cap_for` → `max_concurrent` in main.gd.)*
- **[shapes] Production fast-chaff waves can't form WALLS — they trickle.** (Roman,
  live test 0.1.113: a big dart wave near the tail of node 2 is sparse + lasts ~13s,
  killing end-of-level momentum.) Root cause: the producer sets
  `WaveSpec.formation = randi()%4`, which `ScoreAdapter._shape_id` maps to spread
  shapes (left_to_right/right_to_left/random/center_out) → the conductor's SPREAD
  path spawns one-at-a-time at `spawn_interval`. The wall machinery
  (`_dispatch_shaped` + `_formation_lanes(&"wall")`) EXISTS but is only reachable
  from hand-authored scores, not the WaveGen→adapter seam. **Fix (two parts):**
  (1) bridge the seam — add a WALL (and PINCER) value to `WaveSpec.Formation` +
  `ScoreAdapter._shape_id` so the producer can request a wall; have WaveGen tag fast
  chaff (dart/bomb_drone) waves as WALL. (2) Make wall dispatch chunk a large wave
  into SUCCESSIVE walls (rows of ~5 across the 7 lanes leaving **1–2 gap lanes**,
  a beat between walls) instead of one mega-burst that wraps lanes — so it reads as
  "pick a gap, NOW" repeated, not a fill. Pairs with the role-taxonomy item (darts
  are direct-challenge, not filler). Touches the conductor hot path → playtest the
  whole roster after.

---

## 9. Current status (2026-06-04)

**Merged to `main`:** conductor v0–v3 (streaming cap + blended waves + lane spawn
placement + phrase-native FORMATION/FILLER/BREATHER + wall/pincer shapes),
`lane_path` movement (STRAIGHT/WEAVE/HOOK/STEP), firing zones (engagement-band
gating + first-shot-on-entry + no-fire-when-dying + recycle re-fire), enemy
identity/render_plane hooks, Combat Slice dev showcase.

**M5 producer — ALL merged to `main`:** 5–8 depth-scaled waves; budget allocator
(~140–350, `_level_budget`/`_apply_budget`); breathers; anti-repetition; run-seed
variety; cap depth-ramp 12→16 (`WaveGen.cap_for`); widened opener (firecore+strafer →
`unlock_depth 0`); **heavy beats** (per-node CODA cap + node-2 MIDPOINT, `heavy_class`
anchor/capital, sector ramp); **native CombatScore emission** (`WaveGen.build_score` +
producer-chokepoint `start_score`; adapter→shared builder, `start_level`→compat shim).

**Firing model — merged to `main`:** path-phase firing (band-Y phases) + shared beat
(`scripts/beat.gd`, cross-formation volley quantization).

**Shipped:** itch `0.1.113`.

**Next:** **M6a modular enemy refactor (§10) → M6b factions.** Queued §8 refinements:
fast-chaff WALL dispatch (dart-trickle bug — now a small WaveSpec.Formation+adapter
addition on the native seam), speed-aware/clear-time pacing, role taxonomy, lane_path
HOOK.

**Test harness:** `tools/test_*.gd` headless (`godot --headless --script
res://tools/test_X.gd` → writes `tools/_X_result.txt`); `tools/parse_check.ps1`
after edits. Gotchas captured in user memory (`combat-overhaul-status.md`).

---

## 10. Modular enemy architecture (post-M5 foundation for factions) — Roman, 2026-06-04

**Idea:** stop classing enemies as bespoke monoliths. Treat an enemy as a
*composition* of orthogonal, swappable parts, so behaviors **overlap across chassis**
and new variants become **data, not code**:

- **Chassis** — silhouette + stats + hitbox + size class (the 16/32/64px read; ties
  to `heavy_class`). The "what it looks like / how much it soaks."
- **Movement repertoire** — a shared, *tagged* library a chassis may draw from:
  drift, strafe, weave, charge/dive, hold-lane, omni-harry, side-traverse, … (the
  `lane_path` STRAIGHT/WEAVE/HOOK/STEP set is the seed of this library).
- **Weapon / shoot set** — shared, swappable (single / aimed / spread / burst /
  beam / none).
- **Signature** — the one thing a chassis does that nothing else does (strafer's
  weave-strafe pass, firecore_drone's death ring-release, burner's beam-pair,
  bomber's tail-gun hold). The **only** part that stays bespoke.
- **Faction** — a stat/posture modifier layered over the whole composition (M6).

**Roman's worked examples (the target behavior):**
- drifter / firecore / strafer all share drift + strafe + weave + charge; strafer
  keeps its weave-strafe as a *signature*.
- hover / beamer / gunship can all "hold a lane, fire downward."
- sapper / beamer / gunship can all go "omni, harry the player directly."
→ implies each **chassis declares a permitted movement/weapon set**, and the
generator (or a faction) picks within it. Variety explodes **combinatorially, with
zero new art**.

**Why this is sequenced where it is:** factions (M6) are only cheap **if behavior is
composable** — a faction should be "this chassis + movement + weapon, tinted and
tuned," not a fresh script. So this refactor is the **foundation the faction layer
sits on**, best tackled immediately before it.

**What it requires (the "rethink classing"):**
- `enemy_core` **already** has `movement` + `shoot` Resource slots — composition is
  half-built. The gap is the **bespoke monoliths** (strafer, burner, gunship,
  frigate, bomber, beam_shooter, firecore_drone, firecore_cruiser) that own
  locomotion + weapons inline with `movement: null, shoot: null`.
- Refactor path: extract each monolith's locomotion into reusable movement patterns;
  promote the genuinely-unique remainder to a new **`signature: Resource` slot** (a
  third behavior axis on `enemy_core`). Honor CLAUDE.md's rule — bespoke only for
  what truly can't be a pattern (multi-phase state machines, continuous-effect
  weapons), now expressed as a signature Resource rather than a whole enemy script.
- Roster entries evolve from a fixed `movement`/`shoot` string into
  `{chassis, allowed_movements[], allowed_weapons[], signature, tier,
  size/heavy_class, faction-eligibility}`. `Roster.make_movement/make_shoot`
  generalize to "seed-pick from the chassis's allowed set."
- Migration is **incremental + independently testable**: convert one monolith at a
  time onto the slot system; each conversion is "same enemy, now composed."

**Milestone slotting:** split M6 into **M6a (modular enemy refactor) → M6b (faction
layer)** — the refactor is the enabler. Do **not** start mid-M5: it touches the very
enemy scripts the producer is still being tuned against. Begin **after `combat-m5`
merges** and live-patrol pacing has settled.

**Watch-outs:** don't over-abstract (a signature used by exactly one chassis is fine
as a bespoke Resource — that's the point of the slot); keep the `movement_pattern`
contract (`on_start` / `compute_step → delta`) unchanged so existing patterns drop
in untouched; movement-speed exports still need the `_speed` suffix for sector-scale
+ the clarity clamp.
