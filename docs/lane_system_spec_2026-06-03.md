# Lane System — Design Spec (in progress)

> **CANONICAL SUPERSEDER:** `docs/combat_lane_wave_bridge_2026-06-03.md` unifies
> this spec with the wave-streaming spec. Where they conflict, **the bridge wins.**
> This doc remains the detailed movement/choreography rationale. Note especially:
> "row (lane)" terminology is retired — see the bridge §0 glossary (map = **route**,
> combat = **lane**/**row**).

Status: **design / not built**. Captures decisions from the 2026-06-03 design
conversation. Combat-level enemy movement organized around vertical lanes plus a
conducting director. Nothing in here is implemented yet.

---

## 1. Locked decisions

### 1.1 Lane geometry — 7 lanes
- Playfield band is **216 px wide** (X 132–348, see `scripts/playfield.gd`).
- **7 lanes, 24 px wide, 6 px gaps** including the two edge gaps:
  `6 + 7×24 + 6×6 + 6 = 216` (exact, no leftover).
- Gaps are uniform 6 px — inter-lane gaps and edge margins are identical.
- Lane centers (absolute X): **150, 180, 210, 240, 270, 300, 330**.
  - Lane 3 (0-indexed) center = **270 = `Playfield.CENTER`** → true center lane.
- Pitch (center-to-center) = **30 px** = the size of one horizontal "lane step."
- Lane width chosen against the roster: 16 px chaff sit roomy, 32 px mids kiss
  the gap (fine — gaps are visual, not walls), 64 px heavies span ~2 lanes
  (a feature: heavies read as "big").

### 1.2 Authority — conductor + enemy repertoire
- A central **lane conductor/director** owns choreography and the global view.
  (Name TBD — NOT `boss_conductor.gd`, which already exists.)
- **Enemies own a repertoire of parameterized path templates** (the *shape*);
  the conductor supplies the *parameters*: anchor/entry lane, target lane(s)/delta,
  mirror, tempo offset. This keeps each enemy **learnable** ("a dart always darts")
  while giving the conductor combinatorial variety.
- Paths are expressed in **lane-relative deltas** (`+2 weave`, `±6 hook`), never
  absolute lanes — reusable from any anchor, reads identically to the player.

### 1.3 Determinism → scheduling, not live collision
- Path-follower paths are **fully deterministic**, so the conductor can compute
  an enemy's **entire future lane footprint** at assignment time.
- Occupancy/deconfliction is therefore a **scheduling problem** (reservation table
  over lane × time), resolved **at assignment**, not via runtime rerouting.
  Paths always execute exactly as authored → predictability preserved.
- **Legal-placement-by-construction**: the conductor only assigns (anchor, mirror)
  combos that fit. Clamp/reflect-at-walls is a **dev-time safety net**, never a
  gameplay mechanic (a runtime bounce would break predictability). A deliberate
  edge-bounce, if ever wanted, is just another *named path* in a repertoire.

### 1.4 Mirroring — first-class
- Mirror is an assignment-time parameter: reflect the whole lane-relative template
  L↔R (`+6 hook` ↔ `−6 hook`).
- **Auto-rotate handles presentation for free**: velocity mirrors → rotation
  follows → banking emerges. `flip_h`/aim-mirroring is needed **only** for
  deliberately fixed-facing AND asymmetric enemies (e.g. nose-aim-gated shooters).
- Full-span paths (`±6`) have exactly **two** legal placements (anchor lane 1 and
  its mirror anchor lane 7) — both board-spanning. That rarity makes a full hook a
  *signature* move. Smaller-span paths roam across anchors.
- Mirror choice can be a conductor **heuristic** (mirror toward player lane =
  pressure; away = give an out) tied to the pursue/avoid flag.
- Reactive paths are **exempt** from the mirror parameter (they reflect off live
  player position, not a fixed axis).
- Nuance: hard hooks under auto-rotate swing the nose far off-vertical; **rotation
  tracking rate** is a tuner knob and interacts with the clarity speed ceiling
  (fast hook + slow rotation = visible skid).

### 1.5 Enemy taxonomy — three tiers
| Tier | On-path? | Occupancy | Conductor controls |
|---|---|---|---|
| **Path-follower** | Fully deterministic, lane-relative, mirrorable | Footprint known → fully scheduled/deconflicted | path, anchor, mirror, beat |
| **Reactive** | Mostly scripted + chase/dodge segment | Uncertain during reactive segment → reserve wider footprint | path, when it goes reactive |
| **Omni / free** | Entry spread only, then autonomous | Excluded (counted at spawn instant only) | count, timing, entry lanes |

- The lane grid is the shared **entry-distribution** layer for *all* tiers.
- The deterministic scheduler applies to **tier 1 only** ("scored vs improv").

### 1.6 Occupancy is composition, not physics (CONFIRMED)
- Enemy↔enemy contact is **purely aesthetic** — enemies never physically block
  each other, no enemy friendly-fire.
- **No enemy↔enemy collision at all** (not "cheap collision" — *none*). The planar
  render separation (§1.10) makes overlap read as "flying over," so there is
  nothing for collision to resolve. Collision budget is spent only where it changes
  an outcome: enemy↔player, enemy-bullets↔player, player-bullets↔enemy.
- Occupancy/reservation is therefore a **readability + choreography budget**
  (don't pile ships into an unreadable blob; enable sweeps/pincers/safe-lane), not
  collision avoidance. This is what lets omni-movers opt out cleanly.
- **No enemy ever tracks another.** Two matched deconfliction mechanisms, one per
  tier kind:
  | Tier | Why overlap is fine | Mechanism |
  |---|---|---|
  | Path-followers (deterministic) | Footprints known in advance | **Scheduled deconfliction** (conductor, at assignment) |
  | Omni / reactive / boss / crosser | Render above the lane deck | **Planar separation** (altitude shadow + z-order) |
  - The conductor deconflicts **only the deterministic tier** — it cannot
    pre-deconflict free movers (paths unknown), and doesn't need to.

### 1.7 Rows — sparse, opt-in primitive
- **No uniform N×M grid.** A lane is a *home*; a row is a *latitude you pass
  through* (the world flows down). They are not symmetric.
- Define a **lanes × rows coordinate system** for authoring/reference, but
  **snapping is per movement type**:
  - Vertical movers snap to lane (X), free in Y.
  - Horizontal crossers snap to row (Y), free in X. Rows reuse the lane spacing
    math, rotated onto Y.
  - Turrets/statics/parkers snap to both → a true cell `(lane, row)`.
- Vertical spacing within a lane (anti–conga-line) uses **spawn cadence**
  (time/distance gap), NOT row quantization.

### 1.8 Firing — phase + beat + Y-bands (not the grid)
- **When**: path-phase ("fire at 30%/70% through the path") + the shared **beat**.
- **Where-it's-safe contract**: 2–3 **Y trigger-bands** (entry / engagement /
  departure), NOT a fine row grid.

### 1.9 Two-tier bottom safe zone (LOCKED this session)
- **Tier 1 — hard no-stop floor (~24–32 px, leaning 32 = two ship-heights):**
  no enemy may *hold/park* here; pass-through only. Anti–body-pin.
  - Player ship is **16 px tall** (sheet `graphics/player/blue-fighter-sheet.png`
    is 48×16 = three 16×16 frames); clamps with 8 px margin (`player.gd:595`), so
    it rides to ~Y254 center against a 270 px playfield.
- **Tier 2 — shooter standoff = the departure Y-band (~60–80 px, bottom ~25–30%):**
  enemies that drop into it are **committed to exiting and cease fire** → parked
  shooters can't camp the player's pocket. This *is* the departure band from §1.8;
  the hard floor is its bottom edge.
- **The ban is on stopping/holding and firing-while-camped, never on passage.** A
  divebomber that screams through the pocket and exits the bottom is desired
  pressure; the stationary plinker is outlawed.

### 1.10 Render planes — altitude as a semantic cue (CONFIRMED)
- Drop-shadow offset **means height**, it is not just juice.
- **Lane-followers ride "on the deck"**: minimal/no shadow offset, base z-order.
- **Free-movers / bosses / horizontal crossers fly "above"**: clear shadow offset
  + higher `z_index`. Player-facing contract: *elevated + shadowed = not part of
  the formation, moves freely, treat it differently.*
- Infra exists (`scripts/effects/shadow_fx.gd` `attach_shadow`, `enemy_base.gd`
  parallax shadow). Work = make the offset **consistently encode altitude** rather
  than every enemy wearing an identical shadow, or the cue muddies.

---

## 2. Open items still to spec

(See conversation — these are the remaining sections to nail down.)

### 2.1 Decision-blockers (settle first — everything hangs on these)
- **Integration model**: is lane-movement a new `movement_pattern.gd` subclass
  (fits the enemy `movement`/`shoot_pattern` slot convention) with the conductor a
  layer above `director.gd`? Or a parallel system? CLAUDE.md convention pushes
  toward the Resource-pattern path.
- **Wave authoring format**: extend `WaveSpec`/`WaveGen` to request lane
  choreography, or a new format? How does a wave say "5 darts, weave path, spread
  lanes 1–5, staggered beat"?
- **Back-compat / default path**: existing enemies with no repertoire → default to
  a straight-down path so nothing breaks.
- **The beat/tempo clock**: does it exist, what drives it (music BPM? fixed?),
  where it lives.

### 2.2 Path vocabulary & data model
- Starter path set (straight, weave ±N, hook ±N, hold-then-go, reverse-up-exit-top,
  S-curve, dive-and-return…).
- Path representation (keyframes of lane-delta × Y-progress × duration? segments?).
- Path metadata fields: `lane_span`, `exit_side`, `duration`, `mirrorable`,
  `reactive`, `fire_phases`.
- Speed/duration vs sector scaling × clarity ceiling (clamp resultant vector).

### 2.3 Conductor internals
- Assignment interface (`assign(enemy, path, anchor, mirror, beat)`).
- Deconfliction algo (footprint sim → reservation table over lane×time).
- Density cap per lane + fairness safe-lane guarantee (never zero open lanes — knob).
- How reactive/omni tiers are accounted (exclude / wider footprint).

### 2.4 Spawn & entry
- Entry geometry (top above lane / sides for crossers; off-screen margin).
- Spawn cadence (the anti–conga-line gap number).
- Entry formation presets ("spread across lanes" + named patterns: sweep, pincer,
  checkerboard, every-other, wall, V).
- Telegraphed/warned spawns?

### 2.5 Player-lane tracking
- `nearest_lane(player_x)` + **hysteresis deadzone** (no flicker at boundaries).
- Consumers: lane-targeted attacks, pursue/avoid mirror choice.

### 2.6 Lane-targeted attacks & telegraphs
- Danger-lane telegraph vocabulary (column laser warn, "clear this lane").
- How an enemy/boss declares "attacking lane N."

### 2.7 Sub-lane detail
- Per-enemy jitter/offset so stacked ships don't pixel-overlap (magnitude;
  deterministic vs random).

### 2.8 Lifecycle / edge cases
- Free reservation on death mid-path.
- Reverse-exit via top → despawn vs recycle.
- Pause/slowmo vs the beat clock.
- Wave boundary / level-clear outro → conductor relinquishes control.
- Bosses/hazard levels (minefield/asteroid) → opt out of lanes?

### 2.9 Dev tooling (mandatory per CLAUDE.md — 3+ knob system)
- **Lane/choreography tuner**: visualize lanes/rows/bands/occupancy, test a path
  live, JSON persist, Copy-GDScript button.
- **Debug overlay**: draw lanes, occupancy/reservations, player-lane, safe zones.

### 2.10 Naming
- Conductor/director script + the path Resource class names.

---

## 3. Interaction with the wave-streaming spec

Companion: `docs/wave_streaming_variety_spec_2026-06-03.md`. Both specs
independently converged on the same division of labor:
**wave-gen = "what & how many over time" (type, faction, budget, cadence);
conductor = "where & how it moves" (placement, paths, deconfliction).**
(wave §10.2 ≡ lane §1.2.)

### 3.1 Confirmed gel points
- Seam division of labor matches both ways.
- Bosses/hazards opt out of both systems (wave §10.5 ≡ lane §2.8).
- Global cap ÷ 7 lanes ≈ 2/lane — natural fit.
- Faction palette/shadow (wave §6) is orthogonal to lane render planes (§1.10).

### 3.2 Frictions to resolve (cross-spec)
- **[CRITICAL] Streaming reframes §1.3.** Player-paced density-targeting
  (wave §1.2) means the conductor cannot batch-schedule a wave. Assignment becomes
  **per-spawn JIT placement against a live reservation table** — paths still
  deterministic, footprints still known, deconfliction guarantee preserved; only
  "schedule the whole wave up front" dies. *(Update §1.3 when the seam is settled.)*
- **[CRITICAL] Formations are bursts, not the baseline.** The trickle can't
  assemble a V/pincer. Conductor has **two modes**: trickle (JIT independent
  placement) + formation (deliberate synchronized burst spending cap headroom).
  Both specs must state this identically. *(Affects §2.4 presets.)*
- **[CRITICAL] Terminology collision.** "lane"/"row" mean different things in the
  sector map (3 traversal tracks, called "rows (lanes)" in wave §0.2 /
  `is_row_pois_complete`) vs combat-space (this spec). **Resolution: reserve
  lane/row for combat; rename sector-map tracks to "routes"/"branches"** before
  either ships.
- **[IMPORTANT] Global cap drives lane density.** Per-lane cap + safe-lane
  guarantee (§2.3) derive from the global cap=15 (wave §1.3), not set
  independently. Need a **lane-budget vs free-plane-budget split** so free movers
  (omni/boss/crosser) don't crowd the upper plane.
- **[IMPORTANT] Determinism boundary.** Deterministic at the *content* layer
  (enemies/factions/paths/budget) but NOT the execution timeline or exact
  positions (both player-paced). State in both docs so neither over-promises.
- **[IMPORTANT] One shared telegraph language** for incoming-wave/elite/faction
  (wave §10.10) AND danger-lane (§2.6), co-audited against the faction palette.
- **[MINOR] Pooling** — conductor spawns from the shared enemy/bullet pool
  (wave §10.10 perf). Tuners (wave §10.9 / §2.9) may stay separate initially.

### 3.3 Structural consequence
Wave §10.1 (wave→stream data model) + §10.2 (spawn/lane handoff) and lane §2.1
(integration model) + §2.4 (spawn & entry) are **the same decision from two
sides.** Neither doc can close its blockers alone → **co-design the wave↔lane
seam as one step.**
