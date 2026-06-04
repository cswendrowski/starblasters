# Wave Composition Guide — Authoring Good CombatScores

Status: **research-grounded v2.** The **authoring** companion — *how to compose a
good level* — distinct from the mechanics (`combat_lane_wave_bridge_2026-06-03.md`)
and the rework rationale (`wave_streaming_variety_spec_2026-06-03.md`).

**Two jobs during construction:**
1. **Acceptance criteria** for the conductor capture checkpoints (v1+).
2. **Source of conductor defaults + tuner knob ranges.**

Numbers are **provisional** until `sim_wavegen`/`sim_stream` report (M5); principles
are firm. Vocabulary is ours: Lane, Row, Phrase (Formation/Filler/Breather), Beat,
Chassis, Faction, Tier (bridge §0). Genre grounding is cited inline; see §10.

> **Genre validation:** the canon independently lands on our core choices —
> Boghog recommends "divide the screen into **5–7 lanes**, avoid spawning at the
> edges," continuous overlapping waves, and cease-fire zones. We're on-canon; this
> guide tunes the specifics.

---

## 1. The tension curve (intra-level rhythm)

A stage balances **introductions, tests, and climaxes** — all-intro fails to
capitalize, all-test brings nothing new, all-climax (no breaks) can't land a climax
[system11]. So a level **breathes**:

- **Rise → peak → release.** Formations build pressure; a Breather or thin Filler
  stretch releases it. "Filler" is not wasted time — breaks make the intense
  sections *feel* meaningful [system11]. Cutting breathers "to keep it intense" is
  the most common pacing mistake.
- **Crescendo, don't plateau.** Present challenges as coherent crescendos —
  variations on established moments plus surprising new combinations [gamedeveloper].
- **Introduce → test → climax a mechanic.** Debut a chassis/faction at low density,
  *test* it, then a **midboss as the mid-level climax** rewards mastering it
  [gamedeveloper]. Ties directly to our intro schedule (wave §4.2).
- **Default cadence (provisional):** Formation burst → short Filler bridge →
  Breather every ~2–4 formations; longer gaps between waves than within a wave.

## 2. Enemy roles (functional taxonomy) — *new, Boghog*

Orthogonal to chassis (silhouette) and tier (HP). Every enemy plays a **role**;
compose with a mix, not all of one:

- **Popcorn** — weak, expendable; rhythm + flow + score fodder. Keep HP minimal:
  "popcorn enemies should not have much more HP than is needed" [Boghog].
- **Pressure** — shots force the player to keep moving.
- **Area-denial** — shots block off parts of the screen, constraining movement.
- **Direct-challenge** — elites posing dense, difficult patterns head-on.

A readable wave is mostly popcorn (flow) punctuated by a pressure/area-denial
anchor, with direct-challenge elites reserved for peaks. Map this onto our
tier/faction: tier sets HP/role weight, faction sets posture, role sets *intent*.

## 3. Placement & spawn rhythm — *conductor defaults, Boghog*

This is the **Toaplan pattern**, and it maps 1:1 onto our lane conductor:

- **Alternate anchors.** Spawn each enemy on the **opposite side from the previous**
  to force movement and create rhythm [Boghog]. → conductor default lane-anchor
  heuristic (alternate, biased by pursue/avoid).
- **Avoid the edges.** Never spawn at the play-area borders — it creates traps
  [Boghog]. → our 6px edge gaps already enforce this; keep it.
- **Gap scales with HP.** "Lower HP enemies can have smaller gaps between them,
  higher HP enemies require bigger ones" [Boghog]. → spawn cadence is a function of
  the spawned enemy's HP/role, not a constant.
- **Stagger heavies — never simultaneous.** "Spawning two or more higher-HP enemies
  at the exact same time creates confusion… spawn one-by-one with slight delays to
  create an obvious route" [Boghog]. → a Formation of heavies dispatches with
  intra-burst stagger, not one instant; popcorn formations can be tighter.
- **Quick succession.** Enemies spawn fast enough that the player can't linger in
  one spot [Boghog]. → the density-gated dispatch floor.
- **Overlap = flow + risk/reward.** Overlapping waves turn disconnected spawns into
  a cohesive level; killing a wave fast earns a cleaner screen before the next hits
  [Boghog]. → validates streaming/blended waves + density-gated dispatch exactly.

## 4. Formation vocabulary — when to use each shape

Lane-relative, mirrorable (the conductor anchors/flips). Pick by *the question you
pose the player*:

| Shape | Question posed | Notes |
|---|---|---|
| **Line sweep** (L→R / R→L) | "track across" | Gentle; good opener. The Toaplan alternation in line form. |
| **Wall** | "pick a gap NOW" | Forces a lane choice; MUST leave a safe lane. |
| **V / echelon** | "the center/edge is the threat" | Focal pressure; mirror toward/away from player. |
| **Pincer** (0 & N converge) | "the middle is safe… until it isn't" | Two-sided; don't overuse. |
| **Checkerboard / every-other** | "weave through" | Density without a wall; chaff swarms. |
| **Center-out** | "edges open, then close" | Readable build. |

Full-board shapes (all 7 lanes) are **signature moments** — sparing. Always leave
≥1 open lane (safe-lane guarantee).

## 5. Variety rules

- **≥3–4 distinct chassis on screen after the opener** (target; sim-validated).
- **~one new thing per level** — a chassis OR faction debut, paced off global
  combat-node count, never clustered (wave §4.2). Pair the debut with a test then a
  midboss climax (§1).
- **Don't repeat the opener trio** — widen the sector-1 pool; lean on faction
  variants for apparent variety.
- **Faction = consistent stat/posture modifier**, never random cosmetic (wave §6).

## 6. Difficulty escalation

- **Deeper = more, not fewer.** Budget grows with depth; elite fraction grows on a
  scaling chaff floor (fixes the inversion, wave §3).
- **Cap ramps slightly** (≈12 → ≈16). **Composition beats headcount** — drop count
  before breaking a formation or breather (bridge §4).
- **Enemy priority is a design lever** [Boghog]: high HP, dense patterns, wide-cone
  aimed shots, and high rate of fire all raise an enemy's "kill-me-first" priority.
  Use these to direct the player's attention, not just to add damage.
- **Bosses are the peak:** budget spike + lead-in + multi-phase boss, increasing to
  a final climax [gamedeveloper].

## 7. Readability & anti-frustration (non-negotiable)

- **Always leave an out** — safe-lane guarantee; never a gap-less 7-lane wall.
- **Bottom is sacred** — two-tier safe zone: hard no-stop floor (~32px) + departure
  band where low enemies cease fire and commit to leaving (bridge §1.9). This is the
  canon **ceasefire zone** [Boghog].
- **Dynamic enemy states** [Boghog] — author three outcomes per enemy:
  *optimal kill* (it should fire at least a little no matter how fast it dies),
  *average kill* (intended behavior), *slow kill* (a safety net — it flies away
  rather than trapping the player). Maps onto our path-phase firing + departure-band
  exit + recycle.
- **Bullet sealing** [Boghog] — weak enemies don't shoot when the player is right on
  top of them. Complements the departure-band cease-fire with a *point-blank* seal;
  together they kill the "point-blank plinker."
- **Top dead-zone** — don't force killing off-screen enemies; pairs with reverse-exit.
- **HP discipline** — popcorn HP only as high as its function needs [Boghog].
- **Hit feedback** — enemies must react to hits (flash/particles/shake) or they read
  as ethereal [Boghog]. We have hit_flash + damage overlay + the `hit_taken` hook.
- **Altitude reads as a plane** — free-movers above the deck w/ shadow (bridge §1.10).
- **One telegraph language** — color always means faction (bridge §6).
- **Killing should always beat ignoring** [Boghog] — approaching for a kill must not
  be disproportionately dangerous; never make letting enemies leave the better play
  (an economy/recycle constraint, ties to economy_spec).

## 8. Anti-patterns (capture-review red flags)

- **Conga line** — one lane fed into a tailgating column.
- **All-one-lane / dead lanes** — funneling while other lanes sit empty all level.
- **Unbroken pressure** — no breathers; the player never recovers or reads.
- **Popcorn soup** — random single spawns with no formation/identity.
- **Simultaneous heavies** — two+ high-HP enemies at the same instant = no obvious
  route [Boghog].
- **Drifting tanks overhead** — high-HP enemies drifting down into the player's
  space; being under them is inherently dangerous [Boghog].
- **Vertical tank stacks** — forcing endless back-and-forth in one spot [Boghog].
- **Border traps** — enemies hugging the play-area edges [Boghog].
- **Telegraph soup** — too many simultaneous warnings.
- **No-win wall** — full-board formation with no safe lane.

## 9. Provisional knob ranges (sim-gated — M5)

| Knob | Provisional | Firms at |
|---|---|---|
| Global cap | 12 → 16 by depth | sim_stream |
| Formation send-threshold | next when lane headroom ≥ formation size | sim_stream |
| Filler rate | ~1–3/s, cap-gated | sim_stream |
| Spawn gap (popcorn / heavy) | small / large — scales with HP [Boghog] | sim_stream |
| Intra-formation stagger (heavies) | slight per-member delay, not simultaneous | capture review |
| Breather length / cadence | ~1–2.5 s / every 2–4 formations | capture review |
| Level budget B | ~150 opener → ~300 mature → ~350 deep | sim_wavegen |
| Distinct types/level | ≥4 after node 2 | sim_wavegen |
| New-thing cadence | ≤1 node between debuts | sim_wavegen |

---

## 10. Sources

- Boghog, *Bullet Hell Shmup 101* (ENEMIES) — https://shmups.wiki/library/Boghog%27s_bullet_hell_shmup_101#ENEMIES
- system11 forums, "What does stage design mean to you?" / "Pacing: On Filler,
  Breaks, and Stage Length" — https://shmups.system11.org/viewtopic.php?f=9&t=60212
- Game Developer, "Designing smart, meaningful SHMUPs" —
  https://www.gamedeveloper.com/design/designing-smart-meaningful-shmups
