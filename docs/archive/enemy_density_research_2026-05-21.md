**⚠️ ARCHIVED 2026-06-15 — historical snapshot, not current design.** Superseded by: wave streaming model in scripts/levels/wave_generator.gd; CLAUDE.md "Combat flow".
Kept for design history; do not cite as the live spec.

# Enemy Density & Level Pacing Research — 2026-05-21

Research brief for Starblaster's wave/level cadence. Weighed against our
roguelite sector progression (multiple shorter combats between bosses)
versus typical arcade shmup pacing (4–6 long stages per run).

---

## Genre baselines (from web research)

### Stage length
- **Per-stage duration:** broad consensus 45 sec – 2 min 30 sec; most
  designs cluster at **~2 min for stage 1**, with later stages either
  flat or slightly longer.
- **Psikyo-style fast-pace:** ~1 min / stage or less. Used when the design
  is built for replayability + arcade quarter-flow.
- **Cave-style modern danmaku:** 3 min stage + 2 min boss is a common
  ratio (boss runs ~⅔ of the stage time).
- **Full run length:** consensus **24–45 min** for an enjoyable arcade run.
  Below 20 min feels too short; above 45 min causes player fatigue.

### Structure
- Cave's stage template: **stage → midboss → stage → boss**. The midboss
  resets pacing inside a long stage; substitutes for "more bosses" if
  full-on multi-boss structure isn't desired.
- Bullet-hell density is a quality-over-quantity choice. Number of
  enemies on screen matters less than *how* their bullets compose; a
  small, slow, predictable enemy delivering a thoughtful pattern is
  more interesting than a swarm of low-effort chaff.
- "Filler wave of trivial enemies" is a deliberate tool — gives the
  player a rest beat and signals an upcoming difficulty spike.

### Enemy counts per stage (extrapolated)
- No single published number — varies wildly by sub-genre.
- Cave-style: stages have ~15–30 enemy spawn events including the
  midboss, spread across 3 min.
- Psikyo / classic vertical shmup: 40–80 enemy spawns across a 1-min
  stage (much higher chaff density, lower bullet count per enemy).

---

## How this compares to Starblaster's current cadence

Eyeballing the live game (commit `984b20b`):

- A typical combat node generates 2–4 waves via `WaveGen.build()`, each
  wave 5–12 enemies, with a wave intermission ~1–2 sec.
- A single combat node lasts roughly **45 sec – 90 sec** depending on
  sector depth.
- A "sector" currently has ~5–8 combat nodes plus 1–2 events / outposts,
  then a sector boss.
- Total per-sector active-combat time: **~6–10 min**.
- A full 4-sector run: **30–40 min** active combat (not counting menu /
  outpost / signal-event time).

So Starblaster sits at the upper end of the "comfortable run length"
window. Within that window, each individual combat node is shorter than
a single arcade-style stage — closer to **a Cave midboss segment** than
a full stage.

---

## Implication for the 3-pick progression model

If we adopt the 3-pick proposal (`docs/progression_3pick_proposal_2026-05-21.md`):

- **6 nodes per sector** × 4 sectors = 24 picks per run.
- If each combat node averages 60 sec, that's 24 min of active combat
  + ~5 min outpost/event/boss intermission = **~30 min run**. Hits the
  sweet spot.
- If we trim to **8 sectors × 4 nodes** (Cobalt's "shorter levels with
  more of them" question), that's 32 picks per run. At 60 sec each,
  ~32 min. Still in range but the BOSS cadence becomes the dominant
  variable.

Cobalt's intuition is correct: **with bosses every sector and 4 sectors
per run, we're effectively delivering one boss every 7–10 min, which
matches the Cave-style "stage = midboss + stage + boss" pattern at a
sector scale.** Shortening individual combats (and increasing their
count) preserves the cadence while making each pick feel more discrete.

---

## Recommended density

For Starblaster specifically:

**Per combat node (the unit between picks):**
- Duration target: **45–60 sec** of active combat. Already roughly hit
  by current `WaveGen` output.
- Enemy spawn count: **15–25 enemies** distributed across 2–3 waves.
- Wave intermissions: **1.0–1.5 sec** beats (current setting is fine).
- Mid-node "filler wave" of trivial chaff for breath, every other node
  on average. WaveGen could expose this as a knob.

**Per sector (6 nodes + boss):**
- 6 picks × 60 sec = 6 min combat
- + outpost / signal-event time = ~1–2 min
- + boss = ~90–120 sec
- **Total sector ≈ 8–10 min**. Matches Cave-stage scale at the sector
  level.

**Per run (4 sectors):**
- 4 × 9 min ≈ **36 min total run**. Right in the recommended 24–45 min
  window.

**If 8 sectors × 4 nodes is desired** (shorter levels, more frequent
bosses):
- 4 nodes × 45 sec = 3 min combat + boss + intermission ≈ 5 min/sector.
- 8 × 5 = 40 min. Still in range but bosses become VERY frequent
  (one every 5 min). Could feel repetitive unless boss roster is
  expanded.

**My recommendation:** stay with the **6-node sector × 4 sectors** model.
It hits genre benchmarks for both per-stage density and total run
length without needing a much larger boss pool, and the 3-pick UI gives
us a tight choice cadence the sector map V2 lacks.

---

## Concrete WaveGen knobs to consider

If we lock in the 6-node sector + 60-sec-per-node target:

| Sector depth | Wave count | Total enemies | Notes |
|---|---|---|---|
| 1 (Position 1) | 2 | 12–15 | Easy intro — sells the player on the loop |
| 2 (Position 2–3) | 2–3 | 15–20 | Mid-density chaff with occasional elite |
| 3 (Position 4–5) | 3 | 20–25 | Near-boss tension; introduce the boss's enemy type as foreshadow |
| 4 (Boss) | 1 | 1 (the boss) + summons | Boss-specific roster |

This is roughly what `WaveGen.build()` already produces at the
`sector_depth` parameter; the new piece is **wave count per node staying
small and predictable** so each pick reads as a discrete 60-sec set
piece rather than a variable-length grind.

---

## Open questions

- **Elite combat node** — what's the actual elite-vs-normal difference
  budget? Could be: same chaff count + one elite mini-boss spawn, or:
  half chaff + boss-level enemy. Recommend the former so the pacing
  doesn't break.
- **Filler-wave knob in WaveGen** — would a "breath wave" flag tagged on
  some nodes help with pacing variance? Easy to wire if we want it.
- **Boss-foreshadow** — Cave-style does this by sprinkling boss-themed
  chaff into the preceding stage. Worth doing for our bosses to make
  each sector feel themed.

---

## Sources

- [Pacing: On Filler, Breaks, and Stage Length — shmups.system11.org](https://shmups.system11.org/viewtopic.php?f=9&t=60212)
- [How long do you prefer your stages/progression — shmups.system11.org](https://shmups.system11.org/viewtopic.php?t=57241)
- [How many levels in a Shmup? — shmups.system11.org](https://shmups.system11.org/viewtopic.php?t=68900)
- [Boghog's bullet hell shmup 101 — Shmups Wiki](https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101)
- [Designing Smart, Meaningful SHMUPs — Carotenuto, Game Developer](https://www.gamasutra.com/blogs/AttilioCarotenuto/20150930/254963/Designing_smart_meaningful_SHMUPs.php)
- [Sparen's Danmaku Design Studio — Guide A2](https://sparen.github.io/ph3tutorials/ddsga2.html)
