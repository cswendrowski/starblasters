# Conductor / Wave / Patterning / Movement Systems Review — 2026-07-02

Four-system deep review: the conductor (`director.gd`), wave construction (`wave_generator.gd` + adapter + authored splice), enemy firing/patterning (`enemy_core` + shoot_patterns + mounts), and movement patterns (`patterns/*` + auto-rotation). Includes the requested study of the authored formation library → a formation grammar the conductor can compose from, plus designs for level progression/cohesion and ship-like movement.

Status: **review + design only — nothing implemented.**

---

## 1. Pipeline map (as-built)

```
main.gd:711  WaveGen.build(sd, li, false, faction)        ← content (enemy picks, counts, stats)
   └─ _build_combat_waves → 3× _build_stretch             ← 3-stretch structure (opener/obstacles/climax)
main.gd:760  ScoreAdapter.from_level_data(level)          ← Wave→Phrase lift, breathers
main.gd:767  AuthoredPatterns.maybe_inject(score, ...)    ← 22%/wave authored formation splice
main.gd:827  wave_director.start_score(score)             ← performance (lanes, timing, gates, spawn)
```

- **Phrase = scheduling, WaveSpec = materialization** (`phrase.gd:4-8`). Director decides WHEN/WHERE (`_pick_lane`, row gates, anchor stagger); `_spawn_enemy` (`director.gd:842`) applies the WHAT (stats stamp, faction overlay, movement mutation).
- Hazard nodes bypass WaveGen entirely (`levels_v2.gd` phrase-native scores + authored hazard splice).
- Boss nodes use a separate, older generator (`_build_boss_waves`, `wave_generator.gd:637`) — no stretches, no budget, no slot-cap ramp.

---

## 2. Bugs / unfair seams (fix-first list)

1. **Authored injection bypasses the slot-cap system.** `_dispatch_authored`/`_dispatch_geometric` raise the gate to `alive + specs.size() * 4` with no ceiling (`director.gd:584`, `:640`). `maybe_inject` is also invisible to `STRETCH_BUDGET` (`_apply_budget` never sees injected phrases). A 22% roll can land `charge_wall` (21 enemies, burst) or `straight_escort_wall` (33) **on top of** a capstone during the 36-cap climax — the single biggest "flood → unwinnable first level" seam. Fix: clamp injected pattern size to current cap headroom, and/or count injections against the stretch budget.
2. **Escort convoys never ship.** `WaveGen.build_score()` — the only caller of `_maybe_inject_escort` (`wave_generator.gd:455`) — is not on the production path (`main.gd` uses `build()` + adapter). The escort feature (`formation_shapes.escort`, `:125`) is dev-only dead despite comments saying otherwise. Fix: move escort injection to the `maybe_inject` chokepoint or route main through `build_score`.
3. **Mini-boss climax hook is empty** (`MINIBOSS_ROSTER: []`, `wave_generator.gd:340`) — every level's peak is the same elite-pack fallback.
4. **Hull weapon bursts can fire while dying/recycling.** `weapon._fire_burst` (`weapon.gd:128-138`) lacks the bail-if-held check the mount burst got on 2026-07-01 (`mount_component.gd:206`) — the exact bug, fixed on one path only.
5. **Cap authority is split four ways**: `cap_for()` (26-36) set at `main.gd:717`, immediately overwritten by stretch `slot_cap` 16 (`director.gd:366`); export default 14 (`director.gd:46`); hazard caps hardcoded separately (`main.gd:651/670`). Not a bug today, but a landmine.
6. Minor: enemy hull ShootTimer still quantizes intervals up per shot (`enemy_core.gd:277-279`) — ~0.9% slow at typical cadence, nothing like the fixed 16% player bug. Known deferral; leave unless unifying anyway (§6).

---

## 3. Dead code / duplication (consolidation list)

**Dead:**
- Pre-3-stretch generator remnants: `_wave_count_for`, `_level_budget`, `_should_intermingle`, `_pick_pair`, `_is_affinity_pair`, `WAVE_INTERMINGLE_PROBS`, empty `WAVE_AFFINITY` (`wave_generator.gd:43-48,154-161,593-622`) — unreferenced by the production build.
- Director v2 constants `BANNER_HOLD`/`POST_BANNER_GRACE`/`POST_CLEAR_GRACE` (`director.gd:31-36`).
- `Phrase.lane_anchor_hint` never consumed; `WaveSpec.formation_padding` never read by v3 dispatch; STEP_WALL and FILLER dispatchers unreachable from production (dev-only).
- `weapon.gd` LOB is a stub (`:63-64`); BROADSIDE (`:108-123`) was salvaged from the retired frigate — verify consumers before cutting.

**Duplicated (merge candidates):**
- Lockstep clamp ×2: `authored_patterns.gd:1025` ≡ `wave_generator.gd:536` (verbatim).
- Pre-stack row math ×4: `spawn_y = -12 − (max_row−row)·40` in four files, four constants, one value (`authored_patterns.gd:1070`, `director.gd:636`, `wave_generator.gd:526`, `levels_v2.gd:103`).
- Spec-builder ×2: `authored_patterns._spec_for_placement` hand-mirrors `wave_generator._make_wave_spec`'s stats/shoot/components/mounts block — every new roster override field must be added twice.
- Five burst dispatchers repeat one skeleton; `_dispatch_geometric` ≈ `_dispatch_authored`. **Direction: compile geometric shapes to authored placements at build time and keep ONE performer** (see §4 — the grammar work wants this anyway).
- Firing: path-phase + beat-sync logic duplicated wholesale between `enemy_core.gd:288-331` and `mount_component.gd:133-159` (with drift: the mount copy skips `DEFAULT_PATH_PHASES` auto-fill and the `_dying` check on pure enemy_base hosts). Nose-cone check ×3. Burst loop ×3. Fisher-Yates ×2. Escort concept ×3.
- Movement: descend-to-depth-and-arrive snap copy-pasted ~5×; `move_toward` pursuit steering ×4; drift/loiter/loiter_sweep are one "descend → hold → do X" family with three divergent anti-pop fixes; side_turn ↔ LANE_CUT are mirror quarter-turns implemented twice; beeline_player ≈ proximity_chase.CHASE with a different trigger.

**Cadence determinism divergence:** the 2026-07-02 consistency pass fixed only the hull path. `mount_component.gd:80-81` and `enemy_turret.gd:59-60,144` still `randf_range` per shot — an enemy with a steady hull gun and a wandering turret undercuts the readable-cadence goal.

---

## 4. Formation grammar — the authored-pattern study

Catalog: 23 baked combat formations + 15 hazard layouts (`authored_patterns.gd:45-928`); the live library (`user://tuners/wave_patterns.json`) is byte-equivalent plus **one real unbaked pattern**: `lane_cut_wave` (9 lane-cutters, lanes 1/3/5, per-row depth bands high→mid→low — the cleanest depth-banding exemplar; worth baking).

### Extracted motifs (quantified, zero authored violations)
1. **Mirror symmetry about lane 3** dominates (~18/23); exceptions are directional slashes that come in L/R *pairs*, and point-symmetric cross-pairs.
2. **Every-other-lane parity** ({0,2,4,6} or {1,3,5}) is the fundamental spacing rhythm (10+ patterns).
3. **Density tracks speed**: fast movers ≤4/row, never full-7 rows; full-7 rows only with loiter/crawl/slow families, separated by ≥1 empty row.
4. **Navigability by construction**: either ≥1 always-free lane, a 1–3-adjacent-lane corridor, or checkerboard parity (no lane blocked on consecutive rows). No pattern seals 7 lanes on adjacent rows.
5. **One movement key per zone** — zones are whole columns or roles (collapsing_line is the only mixed pattern, zoned by column), never per-unit random.
6. **Size is role-coded**: single medium at (lane 3, lead row) = leader tip; interior mediums = escorted core; corner medium pairs = crossers. Mixed-speed always sets `lockstep`.
7. **Depth bands map monotonically to rows** (lead rows = low band).
8. **Hazards are negative-space corridors** (13/15 defined by which lanes stay clear).

### Grammar (building blocks for a composer)
- **Primitives**: LINE, PICKET (parity row), FILE, SLASH, WEDGE/VEE, PILLAR (pincer arm), CORRIDOR (free-lane complement), CROSS-PAIR, TIER (row×depth band), CORE+SCREEN (escort).
- **Modifiers**: MIRROR (default-on; slashes emitted as L/R pairs), ECHO (+2-row repeat), PARITY-OFFSET (checkerboard), THICKEN, ZONE-ASSIGN (movement per column group), LEAD (promote (3,max_row) → medium + slower key + lockstep), DEPTH-BAND, DIRECTION, SUBCLUSTER (sub_x/sub_y — available, unused: free design space).
- **Constraints** (all derivable from the catalog): fast keys ≤4/row; full rows slow-only with ≥1 empty row cadence; global navigability rule (free lane | corridor | parity); movement zoned not per-unit; mixed-speed ⇒ lockstep; smalls default, mediums role-coded only; totals 2–24 (33 observed max) and respect the stretch `slot_cap` upstream; ZONE-ASSIGN keys must intersect each enemy's `pattern_eligibility` set (the authored wildcard path currently sidesteps this via `movement_override`).

### How the conductor consumes it — near-zero new dispatch code
Emit pattern dicts in the exact `AuthoredPatterns.DATA` schema and compile via **`build_phrase()`** (`authored_patterns.gd:994`) → `Phrase(shape=&"authored")` → the existing `_dispatch_authored` performer. The generator already proves procedural composition through this path (`_build_escort_phrase`, `wave_generator.gd:487-515`). For homogeneous single-type shapes the lighter `WaveSpec.shape_override` channel exists — but per §3, prefer compiling those to authored placements too and deleting `_dispatch_geometric`.

**Row-convention gotcha:** authored dicts lead from the HIGHEST row; `formation_shapes` cells lead from row 0 — flip (`row' = max_row − row`) when converting.

**Best seams**: (1) the END-capstone branch of `_build_stretch` (`wave_generator.gd:311-323` — the code itself names this "the seam more authored/parametric shapes plug into later"); it has palette, eff_depth, stretch index, budget, seeded RNG. (2) The `maybe_inject` slot for score-time splices. Dispatch-time composition is limited to lanes/rows/timing (content is frozen into specs by then) — use it only for live-occupancy anchoring/mirroring.

**Library consolidation**: vee/chevron/echelon/columns/diamond authored patterns are fixed instantiations the grammar regenerates — the baked library can shrink toward the genuinely bespoke pieces (collapsing_line, escort wall, corridors, cross-pairs).

---

## 5. Level progression & cohesion design

### What exists
Slot-cap ramp 16→26→36 per stretch; `eff_depth = level_index + stretch` deepens the palette per stretch; heavies from stretch 1+; climax finale (elite packs); chaff recycle passes; alternating sweep rhythm + accent stings + breathers; faction scoping + livery; dual seeding (content + dispatch) so retries reproduce.

### What's missing
- **No recurrence/motif memory** — capstone shapes and injected patterns are memoryless random draws; nothing repeats, inverts, or grows a formation the player already saw.
- **Palette is per-stretch, not per-level** (`_pick_palette` re-rolled at `wave_generator.gd:258` with a shuffled pool — doc comment says per-level; the three stretches can be disjoint). Cohesion is per-minute.
- **Intra-stretch escalation is flat** — the 4 units are structurally identical; tension rises in 3 steps, not a curve.
- **No continuous aggression knob** — fire cadence/density escalates only via discrete channels (roster picks, wave overrides, faction, modifier lottery). Nothing scales with wave index or run depth; and the mount side ignores even the existing wave interval override and `aggressive` modifier (`mount_component.gd:80-81` reads spec fields directly) — any future knob must route through mounts or elites won't scale.
- **Boss levels ignore the 3-stretch machine** entirely; boss pick is flat random.

### Proposed design: level motif + escalation ledger
Give each level a small persistent "identity" rolled once in `_build_combat_waves`:

```
LevelMotif {
    palette,                  # hoisted from per-stretch; stretches EXTEND (add 1 deeper entry) not re-roll
    signature_primitive,      # one grammar primitive (e.g. PILLAR pincer, SLASH pair, PICKET wall)
    signature_movement_key,   # the level's recurring behavior flavor
    escalation: [v1, v2, v3]  # three pre-composed variants of the signature, one per stretch:
                              #   v1 = bare primitive (opener, small N)
                              #   v2 = + ECHO/THICKEN/ZONE-ASSIGN (obstacles)
                              #   v3 = + LEAD/CORE+SCREEN + full density (climax capstone)
}
```

- Stretch capstones draw `escalation[stretch]` instead of a random shape — the player literally watches one formation idea grow across the level ("recurring/building patterns").
- `maybe_inject` filters its picks to patterns sharing the signature movement key or primitive family — injections reinforce the motif instead of randomizing it.
- **One-vs-many without flooding**: the grammar's navigability + density constraints are enforced at composition time (they already hold for every authored pattern), and injections count against cap headroom + budget (§2.1). Pressure comes from shape recurrence and tightening corridors, not raw count.
- **Continuous knob**: a per-level `aggression(t)` (0→1 across the 12 units) that scales the fire-interval resolution chain at `director.gd:910-924` and — routed through MountSpec cadence — mounts too. Alternatively/additionally a per-level `Beat.PERIOD` (currently a single global 0.45s constant) makes intensity musically tunable.
- **Boss run-up**: reuse stretch 0+1 of the same machine (motif v1/v2) then the boss — unifies the two generators and makes boss levels feel like the level they end.
- **Cross-node memory (later)**: persist the motif of the sector's first combat in Run meta; the sector's last combat can reprise it at +1 escalation ("rival formation" effect).

---

## 6. Firing/patterning consolidation

- **One FiringScheduler**: extract trigger resolution (path-phase / phase-event / cadence / beat-sync / gates) from `enemy_core.gd:238-347` + `mount_component.gd:46-159` into a shared RefCounted. MountSpec already carries every firing-condition field (`mount_spec.gd:46-51`) — the data model is done; only the two tick implementations need to merge. Hull weapon becomes "mount 0 with the hull's shoot_pattern as content" — the natural endpoint of the 2026-06-23 consolidation.
- Apply the deterministic-midpoint interval to `mount_component._roll_interval` + `enemy_turret`; give `weapon._fire_burst` the mount's held-bail (§2.4).
- Burner/Sapper/Cruiser stay bespoke (multi-entity, per the 2026-06-23 decision). `EnemyTurret` → MountComponent-with-rotation is plausible but a larger lift (arc gate, lock-to-fire, recoil).
- **Volley choreography already exists passively** — fixed path phases + global Beat mean a descending formation collapses into synced volleys at the same Y/beat. What's missing is an *active* conductor command; the plumbing is ~90% there (movement phases already fan into firing, `enemy_core.gd:334-347`) — a conductor-emitted synthetic phase or Beat-scheduled group trigger gives authored row-by-row volleys with no new per-enemy state.

---

## 7. Movement verisimilitude — ship kinematics layer

### Root causes of unnatural motion
- **Facing is an instant positional finite-difference** (`enemy_base._apply_auto_rotation`, `enemy_base.gd:1115-1150`): rotation set from the raw frame delta with **no turn-rate cap anywhere in the shared path**. `turn_rate` is stamped on every spawn and consumed by exactly one pattern (`omni_thrust`). Every velocity reversal is a one-frame 90–180° hull flip.
- Concrete offenders: loiter_sweep margin reversal + settle pivot (`loiter_sweep.gd:39-46`); skirmish loop→exit snap (`skirmish.gd:60-64`); STEP lane hops yawing the hull ~60° and back per 0.25s hop; unbounded WEAVE bank angle; proximity_chase's instant freeze (intentional telegraph — keep); loiter's auto_rotate-freeze **hack** existing precisely because jiggle deltas snap facing; hard arrive-at-depth snaps copy-pasted ~5×; the base `omni` facing branch has NO rate limit (instant perfect lock — the behavior Roman rejected 2026-06-10) unlike `omni_thrust`'s weight-lagged version.
- **omni/strafe/retro flags**: facing filters are live (`enemy_base.gd:1128-1147`) but **nobody sets the flags in production** (only the Enemy Bench checkboxes) and **no pattern queries** the `_can_omni/_can_strafe/_can_retro` accessors. Also a naming collision: the movement KEY "omni"/`hunt_omni` (gunship) vs the chassis FLAG.
- The good news: `enemy_core`'s inertia filter (`INERTIA_ACCEL/weight`, `enemy_core.gd:63-64,159-169`) is a working velocity-continuity layer — the patterns that need it most (loiter_sweep, skirmish, proximity_chase, STEP) just don't opt in.

### Design: generalize the existing hook (enemy_core._process:158-173)

```
desired_vel = compute_step(...) / dt          # pattern contract unchanged
applied_vel = filter(applied_vel → desired_vel, chassis accel/decel, weight)
facing      = rotate_toward(rotation, target_facing(applied_vel, omni/strafe/retro),
                            deg_to_rad(turn_rate)/weight * dt)
position   += applied_vel * dt
```

- Patterns declare a **fidelity class**: `EXACT` (bypass — telegraphs, side_traverse spawn teleport), `SMOOTH`, `EXACT_Y_SMOOTH_X` (lane patterns — lane geometry stays exact, lateral snapiness is the visual problem).
- Facing filter replaces `_apply_auto_rotation` outright: fixes flip-snaps with **zero pattern edits**, deletes the loiter freeze hack, gives WEAVE/STEP a natural bank character, and fixes the unlimited base-omni lock. Patterns that own rotation (omni_thrust, pendulum) keep their `auto_rotate=false` escape and migrate later.
- Ship as a callable module (Effects-statics style), not welded into enemy_core, so bespoke hosts (bosses, cruiser/burner, hazards) can adopt it.

**Hard constraints (why naive smoothing breaks things):**
1. Steady-state speeds must converge exactly to the rung (`move_toward`, never asymptotic lerp); transients off-rung are fine (lane_charge already does this); cap at `Clarity.ABS_MAX_SPEED`.
2. Lane geometry is sacred — LaneTraffic free-checks assume the enemy is where the closed form says; keep X lag error-bounded (<~4px) or exempt lane-locked phases.
3. **Never filter the vertical component of monotone descenders** (`path_phase_capable()` is a ready proxy) — path-phase firing + beat sync predict position from descent speed, and the 2026-07-02 firing pass just tuned those phases; crosser/anchor stagger timing also assumes distance/move_speed arrival.
4. step_wall row sync survives only if the filter is deterministic (same inputs → same outputs; no per-instance randomness).
5. Reset filter state on `on_start`/recycle; set `_last_move_vel` from applied_vel (wreck drift + beat prediction consume it).

**Flag gating to finish**: add omni/strafe/retro to the roster locomotion table (`SIZE_LOCOMOTION`/per-entry) → `resolve_locomotion` → director stamp; then let patterns branch (loiter_sweep rakes without flipping iff `strafe`; skirmish loop-top reverse iff `retro`; DIVE_RETURN climb likewise). Resolve the omni key-vs-flag naming collision while at it.

**Cheapest high-value increments (do first, zero choreography risk):**
1. Turn-rate-capped facing in `_apply_auto_rotation` alone (no translation changes).
2. Opt loiter_sweep/skirmish into the existing `uses_inertia()`.
3. Route the base `omni` branch through the same rate cap.

**Pattern merges** (post-layer, each deletes a divergent fix): drift+loiter(+loiter_sweep) → one Holder with hold-behavior enum; beeline_player+proximity_chase → one pursuit with trigger enum; shared `descend_to(depth)` + `quarter_turn()` helpers (side_turn ↔ LANE_CUT).

---

## 8. Prioritized roadmap

**P0 — fairness/correctness (small diffs):**
1. Clamp `maybe_inject` bursts to cap headroom + count against stretch budget (§2.1).
2. Held-bail in `weapon._fire_burst` (§2.4).
3. Bake `lane_cut_wave` from the JSON library.

**P1 — feel (the "ships not pixels" ask):**
4. Turn-rate-capped facing filter (increment 1–3 of §7) — biggest visual win per line of code.
5. Full kinematics layer + fidelity classes; then flag gating (roster plumb) and pattern merges.

**P2 — composition (the grammar + progression ask):**
6. Formation composer: grammar primitives/modifiers/constraints (§4) emitting authored-schema dicts through `build_phrase()`; compile `formation_shapes` + geometric dispatch into the same path (deletes a dispatcher, fixes ×4 row-math duplication).
7. LevelMotif + escalation ledger (§5): palette hoist, signature primitive growing v1→v2→v3 across stretches, motif-filtered injection.
8. Populate `MINIBOSS_ROSTER`; unify boss run-up onto the stretch machine; ship escort injection at the production chokepoint.

**P3 — internals:**
9. FiringScheduler unification + mount/turret cadence determinism (§6); conductor volley trigger.
10. Dead-code sweep (§3) + shared helpers (lockstep clamp, row math, spec builder, shuffle).
