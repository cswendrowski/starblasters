**⚠️ ARCHIVED 2026-06-15 — historical snapshot, not current design.** Superseded by: scripts/levels/director.gd + CLAUDE.md "Combat flow".
Kept for design history; do not cite as the live spec.
> NOTE: the proposed row→route rename was NOT applied — code still uses `row`/`is_row_pois_complete`.

# Combat Bridge — Lanes × Wave Streaming (CANONICAL)

Status: **design / not built.** This is the **single source of truth** unifying:
- `docs/lane_system_spec_2026-06-03.md` — enemy *movement* / lane choreography.
- `docs/wave_streaming_variety_spec_2026-06-03.md` — enemy *volume / pacing /
  variety*.

**Where this doc conflicts with either parent, THIS WINS.** The parents remain the
detailed rationale; this is the reconciled contract that guides implementation.
Decisions here are locked (Roman, 2026-06-03) unless marked OPEN.

---

## 0. Canonical vocabulary (resolve once, never re-overload)

The word "lane" and "row" were colliding across map-space and combat-space. Fixed:

| Term | Meaning | Scope | Notes / code debt |
|---|---|---|---|
| **Route** | One of the **3 horizontal traversal tracks** of POIs on the sector map | Sector map | Was "row (lane)" in wave §0.2. **Rename `row`→`route`** in `run_state.gd` (`is_row_pois_complete`→`is_route_pois_complete`) — tracked debt. |
| **Lane** | One of the **7 vertical columns** in the combat playfield | Combat | 24px wide, 6px gaps. Lane spec §1.1. |
| **Row** | A **horizontal latitude** in the combat playfield (for crossers/statics) | Combat | Sparse, opt-in. Lane spec §1.7. |
| **Level** | One node's full combat encounter | Combat | |
| **Wave** | A **compositional section** of a level (5–8 per level), with an identity (enemy mix, banner, dominant faction) | Combat | Banners non-blocking. Waves blend. |
| **Phrase** | The **atomic dispatch unit** inside a wave: `Formation` \| `Filler` \| `Breather` | Combat | Replaces `WaveSpec.count`. See §2. |
| **Formation** | A **composed group** of enemies in a shape, sent together | Combat | The primary texture. §2.1. |
| **Filler** | Connective **single-enemy trickle** between formations | Combat | §2.2. |
| **Breather** | A deliberate **low/no-spawn gap** | Combat | §2.3. |
| **Beat** | The shared **tempo tick** (clock) for firing sync + formation timing | Combat | Tempo ONLY — never a composition unit (that's Phrase). |
| **Chassis** | An enemy's **silhouette = behavior** (dart, weaver…) | Combat | Threat axis 1. |
| **Faction** | An enemy's **color = stat/posture modifier**, applied across chassis | Combat | Threat axis 2. Wave §6. |
| **Tier** | COMMON/UNCOMMON/RARE → HP/role weight | Combat | Existing. |

**Rule: "route" is map-space; "lane"/"row" are combat-space. Never cross them.**

---

## 1. The unified combat model

**Texture = composed formations, sent whole; connected by filler trickle; punctuated
by breathers — all under a concurrency cap, with the conductor placing everything
onto lanes just-in-time.** (Reconciles lane §1.3 + wave §1.1–1.3 + Roman 2026-06-03.)

### 1.1 Dispatch is density-gated, at the PHRASE level (not per-enemy, not fixed-cadence)
- The atomic spawned thing the **dispatcher** reasons about is a **Phrase**, not a
  single enemy. This preserves the anti-bistability finding (wave §1.2: fixed time
  cadence is bistable on player kill rate) **because dispatch is gated by live
  density, not a clock** — but makes the *readable* unit a composed formation, not a
  dribble.
- **Formation phrase:** wait until lane-budget headroom ≥ formation size, then spawn
  the whole group. (Waiting naturally drains the screen → emergent breather.)
- **Filler phrase:** per-enemy trickle while `lane_alive < cap` (this is the only
  enemy-by-enemy spawning). Used to bridge dead air between formations or maintain a
  pressure floor.
- **Breather phrase:** withhold spawns for a duration (or until `alive ≤ floor`).
- **Dead-air guard:** while waiting to send a Formation, if the gap exceeds a
  tunable threshold AND the current phrase is not a Breather, inject Filler.

### 1.2 Placement is per-spawn JIT (the reframe — LOCKED)
- Paths are deterministic, so the conductor knows each enemy's full future footprint
  **the moment it spawns**. It places each spawn against the **live reservation
  table** (currently-live footprints), picking a legal (anchor, mirror) with no
  overlap. No batch pre-scheduling; no runtime rerouting. The deconfliction
  guarantee from lane §1.3 is fully preserved — only "schedule the whole wave up
  front" is retired.
- A **Formation** is placed as a coordinated multi-spawn: its shape defines relative
  lane anchors; the conductor anchors+mirrors the whole shape to fit current
  occupancy, then spawns its members together.

### 1.3 Concurrency cap = umbrella over two budgets (LOCKED)
Global cap **~12 (early) → ~16 (deep)** splits into:
- **Lane budget** — max path-followers occupying lanes. Per-lane density cap +
  **safe-lane guarantee** (≥1 lane always open) derive from this, NOT set
  independently. (e.g. cap 15, ≤6 occupied lanes → per-lane cap 3.)
- **Free-plane budget** — a separate sub-cap for omni/boss/crosser actors that fly
  "above the deck" (lane §1.10). They don't consume lane slots but DO consume visual
  attention, so they get their own ceiling to prevent upper-plane soup.
- Formation dispatch checks **lane-budget** headroom; free-plane actors are gated by
  the **free-plane** sub-cap.

---

## 2. The Phrase model (replaces `WaveSpec.count`)

A **Wave** holds an ordered list of **Phrases**. A level is `5–8 Waves` of blended
phrases. Counts EMERGE from formation sizes + filler rates; no fixed per-wave count.

### 2.1 Formation phrase
Composition the conductor must realize as a coordinated burst:
- `members`: list of `(chassis, tier, faction, count)`
- `shape`: a formation-pattern reference (V, wall, pincer, checkerboard, every-other,
  echelon…) expressed in **relative lane offsets** (so it anchors+mirrors)
- `entry`: top / side (for crossers)
- optional `lane_anchor_hint` (else conductor chooses by occupancy + pursue/avoid)

### 2.2 Filler phrase
- `pool`: eligible `(chassis, tier, faction)` weighted set
- `rate`: target trickle rate (gated by lane budget; per-enemy JIT placement)
- `until`: duration | budget-share | "until next formation has headroom"

### 2.3 Breather phrase
- `duration` (or `until alive ≤ floor`)
- no spawns; the readability "exhale" beat between intense waves

---

## 3. The seam contract (the joint decision, settled)

**wave-gen = WHAT & HOW MANY OVER TIME. conductor = WHERE & HOW IT MOVES.**
(wave §10.2 ≡ lane §1.2 — unified.)

### 3.1 What wave-gen emits — the "level score"
A deterministic, ordered structure for a given `(run_seed, sd, li)`:
```
Level
 └─ Wave[5..8]            (identity: mix, banner, dominant faction)
     └─ Phrase[*]         (Formation | Filler | Breather)
         └─ composition   (chassis, tier, faction, count, shape, entry)
```
wave-gen specifies **composition, order, shape, faction, tier, entry side** — and
NEVER exact positions or spawn times.

### 3.2 What the conductor consumes
The conductor reads phrases in order and is solely responsible for:
- **dispatch timing** (density-gated, §1.1)
- **placement** (lane anchors, mirror, JIT deconfliction, §1.2)
- **path assignment** (from each enemy's repertoire)
- **safe-lane + cap enforcement** (§1.3)
- **telegraphs** (§6)
- **pooling** (spawns from shared pools)

The conductor NEVER decides composition (what/how-many/which-faction).

### 3.3 The clean boundary, one line
> wave-gen authors the score; the conductor performs it.

---

## 4. Budget scheme — composition-first, totals flex (LOCKED intent)

**Decision (Roman): when budget and composition conflict, composition quality wins.**
Per-level / per-sector headcount totals may flex; wave/lane composition must stay
coherent and consistent.

- The allocator allocates **phrases and intensity along a difficulty curve**, not a
  raw headcount. Headcount is the **emergent sum**.
- `B(sd, li)` becomes a **soft target band** (≈150–200 opener → ≈300 mature →
  ≈350 deep ceiling), used to *shape the curve and validate in sim*, NOT a hard
  quota the dispatcher chases. If hitting ~300 would force an ugly formation or a
  broken breather cadence, **drop the count, keep the composition.**
- Difficulty curve still drives: budget growth with depth, growing elite fraction
  atop a scaling chaff floor, slight cap ramp, boss-level spike (wave §3) — but
  expressed as *more/bigger/denser formations*, not "N more enemies."

**OPEN (sim, not feel):** the curve's soft band per `(sd, li)`, the per-wave phrase
mix (front-light vs escalate), elite-fraction curve, deep ceiling. Set with
`sim_wavegen.gd` extended to report phrase/formation composition + distinct-types +
first-seen-node (wave §8 sim TODO).

---

## 5. Determinism boundary (unified — state in both parents)

- **Deterministic (content layer):** for a given `(run_seed, sd, li)` the **level
  score** (waves, phrases, compositions, eligible paths, factions, tiers) is
  identical. Retries of the same node reproduce the same score. `run_seed` is folded
  into the node seed (wave §7.2 / §10.8).
- **Non-deterministic (execution layer):** dispatch timing and exact spawn positions
  are **player-paced** (density-gated dispatch + JIT placement). The same score plays
  out on a different timeline per run.
- **Consequence:** composition bugs reproduce from seed; positional/timing bugs do
  not — they need live capture. Sims validate the **score layer** only.

---

## 6. Unified telegraph system (one vocabulary, palette-audited)

One language serves both "incoming volume/variety" (wave §10.10) and "lane danger"
(lane §2.6). **Non-blocking** (never halts the stream). Co-audited against the
faction palette + bullets + hit-flash + damage overlay in the 480×270 frame
(wave §6.6).

| Event | Telegraph | Lead time (knob) |
|---|---|---|
| **Incoming formation** | Brief edge/top markers at the lanes it will enter | short pre-spawn lead |
| **Elite / heavy** | Distinct marker (size + brighter rim), reuses tier read | on spawn |
| **Faction shift** (new dominant faction in a wave) | Banner tint + one-shot color sweep in the faction's palette | at wave banner |
| **New-enemy debut** | Codex ping + clean solo/■spotlight entry (wave §4.2) | at debut |
| **Lane-targeted attack** | Column/lane highlight ramp (the danger-lane warn) | telegraph→fire window |
| **Breather** | Absence of telegraphs + natural lull (no positive cue needed) | — |

**Rules:** color always means faction (wave §6.1/§6.6) — telegraphs must not reuse
faction hues for non-faction meaning. Danger-lane highlight uses a reserved
non-faction treatment (e.g. desaturated warn-pulse) so it can't be misread as a
green/purple enemy.

---

## 7. Render planes & altitude (carried from lane §1.10, unchanged)

- Shadow offset = altitude (semantic, not juice).
- Lane-followers on the deck (low/no offset, base z). Free-movers/bosses/crossers
  "above" (clear offset + higher z). Reinforces the lane-budget vs free-plane-budget
  split (§1.3) — the two budgets are also two visual planes.

---

## 8. Tuning — one knob surface (CLAUDE.md: 3+ knobs → tuner)

A **single combat tuner** (extend Wave Tester / `wave_editor.gd` or scaffold new;
Copy-GDScript button required) exposing the full reconciled knob set:

- **Cap:** global cap + depth ramp; lane-budget vs free-plane-budget split; per-lane
  density cap; safe-lane on/off.
- **Dispatch:** formation send-threshold; filler rate; dead-air guard; breather
  length/floor.
- **Budget/curve:** `B` soft-band per depth; per-wave phrase mix; elite-fraction
  curve; deep ceiling.
- **Variety:** weighted selection (wave §7.1); intro cadence (chassis + faction
  debut tracks); opener pool width.
- **Movement feel:** rotation tracking rate; sub-lane jitter magnitude.
- **Telegraph:** lead times per event type.

Pooling is mandatory under sustained dispatch (wave §10.10) — the conductor spawns
all actors (lane + free-plane) from shared pools.

---

## 9. What this resolves vs what stays open

### Resolved (locked above)
- ✅ JIT placement reframe (§1.2)
- ✅ Composed-formation + filler + breather model (§1.1, §2)
- ✅ Terminology untangle (§0)
- ✅ Budget = composition-first, flexible totals (§4)
- ✅ Determinism boundary unified (§5)
- ✅ One telegraph vocabulary (§6)
- ✅ Cap = umbrella over lane + free-plane budgets (§1.3)
- ✅ Pooling + single tuner surface (§8)

### Still open (joint, sim- or design-gated)
- ◻ **Formation roster** — the actual shape library + each shape's relative-lane
  layout, size range, mirrorability (feeds §2.1, lane §2.2 path vocab).
- ◻ **`B` soft-band curve + per-wave phrase mix + elite-fraction curve** (§4) — sim.
- ◻ **Integration code shape** — is a Phrase a Resource? is the conductor an autoload
  / a node under `main`? how it wires to `director.gd` + the `movement_pattern.gd`
  slot. (lane §2.1 / wave §10.1 — needs the architecture scan.)
- ◻ **Intro schedule data** (chassis + faction debut tracks, §6 / wave §4.2/§10.4).
- ◻ **Hazard/boss under this model** (wave §10.5 / lane §2.8) — lean: bespoke content
  but same cap governance + telegraph vocabulary.
- ◻ **Recycling vs cap/clear** (wave §10.6) — do recyclers count toward lane budget?
- ◻ **Node-type roster rework** for the sector-composition change (wave §5/§10.7).

### Next step
**Co-design the integration code shape** (the one ◻ that unblocks building): run the
read-only architecture scan of `director.gd` ↔ `WaveSpec`/`WaveGen` ↔
`movement_pattern.gd`, then decide where Phrase, the conductor, and the dispatcher
live. Everything else is content/curve tuning that this contract already frames.
