# Level Structure — 3-stretch levels + slot-weighted density

**Status: BUILT 2026-07-01 (steps 1-5), UNVERIFIED IN-GAME.** Shipped in five commits on branch
`wave-pattern-editor-2026-06-16` (slot cap `18ad6f5d` · 3-stretch loop `54317680` · pauses `7ebf4c14`
· climax+recycle `02930f3e`). Headless-verified (caps 16/26/36, ~300 enemies/level, chaff recycling,
climax elite pack); NOT yet playtested for feel/length. Numbers in §2-§4 are tunable knobs.

**⚠️ One reversal to review (§4):** the doc assumed chaff recycle unlimited and needed *capping*; the
roster actually sets high-count chaff to `recycle: 0` (leak off — Roman 2026-06-08). Enabling roll-back
(now `CHAFF_RECYCLE_PASSES = 2`) is what makes ~300 enemies fill ~3 min instead of leaking in ~60s, but
it **reverses that 2026-06-08 decision** — every dense chaff wave now does the parallax fly-back. If
that reads as visual noise (the reason it was disabled), set the constant back to 0.

Supersedes the flat-5-wave model in `WaveGenerator._build_combat_waves` and the headcount cap in
`director` (`max_concurrent`). Builds on the palette/formation/hazard-drift work (see
`wave_composition_guide_2026-06-03.md` + the 2026-06-23/27 commits) — that stays as the per-sub-wave
vocabulary; this is the STRUCTURE + DENSITY layer on top.

---

## 1. Goal

A combat level is a **~3-minute, three-part piece**:

1. **Opener** — a stretch of mid-tier enemy waves. Establishes the lane rhythm.
2. **Mid / obstacles** — tougher mid-stage: tankier units, elites, weave-forcing formations.
3. **Climax** — a boss (on boss nodes) or an elite / mini-boss stretch (on regular nodes).

Each stretch ≈ **1 minute** and ≈ **100+ enemies**, so a level totals **300+ enemies**. The player
should feel **outnumbered** — cutting through / dodging target-rich walls, occasionally sinking a
super-bomb to clear an overwhelming one. Recycling folds missed enemies forward so the screen stays
packed between kills.

**Locked decisions (Roman, 2026-07-01):**
- Every level is 3-part. Boss nodes: stretch 3 = the boss. Regular nodes: stretch 3 = elites /
  mini-bosses (mini-bosses don't exist yet — Roman will author them; until then, an elite pack).
- **Kill-paced** — 3 min is the target for the intended skill; a stronger player clearing faster is
  fine (no hard time-gate).
- Density is a **slot grid**, not a headcount — see §2.

---

## 2. The density engine — slot-weighted cap (replaces the headcount cap)

Today `director` caps on-screen enemies by **count** (`max_concurrent` = 12–16, gated via
`_alive_count()`). The playfield is a **7-lane grid**; we want to be able to fill every lane and
lane-space, so we cap by **occupied slots** instead.

**Footprint** (slots one enemy consumes), measured from its collision/sprite box against a 24 px
square cell (= `Lanes.WIDTH`):

```
slots(enemy) = ceil(width / 24) * ceil(height / 24)
```

| Enemy | Box | Slots |
|-------|-----|-------|
| small | ≤24×24 | **1** |
| tall / medium | 16×32 | **2** |
| large | 32×32 | **4** |
| huge / capital | 64×64 | **9** (≈8–12 band) |

**Cap = total live slots ≤ `slot_cap`.** With `slot_cap = 36`: up to **36 small**, or **18** tall,
or **9** large, or **~4** capitals — or any mix that fits the grid. A wall of chaff packs the
screen; a wave of cruisers thins itself automatically. This roughly **triples** small-enemy density
vs today (12–16 → 36), which is where the outnumbered feel comes from.

**Implementation:**
- Add `EnemyBase.slot_weight` — computed once in `_ready` from the collision box (fallback: roster
  `size` class → small 1 / medium 2 / large 4 / huge 9). The director already measures height
  (`_enemy_height`) for cruiser staggering, so a width companion is cheap.
- `director._alive_slots()` — sum `slot_weight` over live non-hazard "enemies". Replaces
  `_alive_count()` in every cap-gate (`while _alive_slots() >= slot_cap: await …`). Recyclers count
  (an on-screen body) as they do now.
- `WaveGenerator.cap_for` returns the **slot** cap, ramped per stretch (§3), not a headcount.

**Tunable (defaults):** cell = 24 px; huge = 9 (bump to 12 if capitals should dominate more); cap
ramp **16 → 26 → 36** across the three stretches (Roman 2026-07-01 — the opener stays near today's
~16 density and *builds* to a packed climax, rather than starting busy).

---

## 3. The 3-stretch level loop

Replace the flat `for i in COMBAT_WAVE_COUNT (5)` in `_build_combat_waves` with three
**stretch-builders**, each its own budget + slot cap + palette + tier band. A stretch is a run of
**sub-waves** (the existing START/MIDDLE/END-style beats + formations/accents) drawn from that
stretch's palette.

| Stretch | Budget (enemies) | Slot cap | Tier / character | Climax unit |
|---------|------------------|----------|------------------|-------------|
| 1 Opener | ~100 | 16 | mid chaff (common/uncommon), lighter palette | — |
| 2 Obstacles | ~100 | 26 | tankier + elites, weave-forcing walls/channels, higher HP bonus | heavy anchor |
| 3 Climax | ~100 | 36 | densest; regular = elite pack / mini-boss, boss node = the boss | elite/mini-boss/boss |

- **Budget** stays in **enemy count** (~100/stretch, ~300/level); the **slot cap** governs density
  independently. Chaff waves scale to hit the stretch budget (the existing `_apply_budget`
  chaff-flag logic, run per stretch).
- **Escalation** is per-stretch: the palette + `_roll_tier` bias + slot cap + per-wave HP bonus all
  step up stretch to stretch, so the level *builds*.
- **Boss nodes**: stretches 1–2 are the run-up (reuse the escalating lead-in from
  `_build_boss_waves`, now framed as two stretches), stretch 3 = `_make_boss_wave`. The
  kitchen-sink variety currently reserved for the boss lead-in lives in stretches 1–2.
- **Regular-node climax**: a new data-driven **climax slot** — a mini-boss scene if one is
  registered for this depth/faction, else an **elite pack** (several `heavy_class` units at the
  36-slot cap). The hook is a no-op-safe fallback so nothing breaks before mini-bosses exist.

`COMBAT_WAVE_COUNT` (flat 5) and the dead `_wave_count_for` (5–8, unused) both go away; wave count
falls out of "enough sub-waves to fill each stretch's ~1 minute at its pause cadence."

---

## 4. Pacing

- **Intra-stretch pause: a deliberate 1–2 s beat between sub-waves.** Today the between-wave breather
  (`ScoreAdapter._breather`: 2 s, `alive_floor 5`) *ends the instant the screen drains to ≤5* — so a
  competent player never feels it. The stretch pause must NOT self-cancel: a fixed ~1–2 s reposition
  beat (recycling keeps the screen populated across it).
- **Kill-paced.** Level length = budget ÷ kill rate. At ~300 enemies and the intended dodge-heavy
  ~1.7–2 kills/s, that's ~150–180 s + pauses ≈ 3 min. A stronger player finishes faster (accepted).
- **Recycling** (`recycle_controller`, default `recycle_passes = -1`) is the linchpin: missed enemies
  fly back instead of leaking off-bottom, so the budget is spent on **kills** and the screen stays
  full. Tuning: cap chaff passes at **2–3** (not unlimited) so a single perpetually-missed straggler
  can't drag out the stretch-end.

---

## 5. What stays vs changes

**Stays (the per-sub-wave vocabulary):** palette (`_pick_palette`), sweep-rows + row-clear gate,
geometric flocks (`formation_shapes`), escort, accents, hazard drift, the formation dispatch paths.

**Changes:**
- `director`: `slot_weight` + `_alive_slots()`; cap-gates switch to slots; a non-self-cancelling
  stretch pause.
- `WaveGenerator`: `_build_combat_waves` → 3 stretch-builders; `cap_for` → slot cap ramp; drop
  `COMBAT_WAVE_COUNT` / `_wave_count_for`; per-stretch budget (`_apply_budget` per stretch).
- `_build_boss_waves` → framed as stretches 1–2 + boss stretch 3.
- New: regular-node **climax slot** (mini-boss hook + elite-pack fallback).
- `EnemyBase`: `slot_weight` field.

---

## 6. Build order (each step verifiable in isolation)

1. **Slot-weighted cap** — `slot_weight` + `_alive_slots()` + slot cap. Headless test: spawn N smalls
   vs N larges, confirm the grid fills to the slot cap either way (not a flat headcount). Lowest risk,
   biggest feel payoff; independently shippable.
2. **3-stretch loop** — restructure `_build_combat_waves`; per-stretch budget/cap/tier/palette.
   Verify headcounts + per-stretch composition with `sim_wave_density.gd`.
3. **Stretch pause** — the deliberate 1–2 s non-cancelling beat.
4. **Climax slot** — mini-boss hook + elite-pack fallback (regular nodes); boss stretch (boss nodes).
5. **Recycle pass cap** — chaff `recycle_passes` 2–3.

Numbers in §2–§4 are **starting proposals** — density/budget/cadence are Roman's to tune (a tuner or
pasted values, per the human-iterated workflow). The doc fixes the STRUCTURE + KNOBS; Roman dials the
values.

---

## 7. Open items / hand-offs

- **Mini-bosses** — Roman authors the units; this design provides the climax slot + elite-pack
  fallback so regular-node climaxes work meanwhile.
- **Super-bomb** — the pressure-release for an overwhelming wall is assumed to exist / be wanted;
  not part of this doc.
- **Slot weights + cap ramp** — huge=9 vs 12: tune in playtest. Cap ramp set to 16→26→36 (Roman's
  pick); revisit if the opener feels too thin or the climax not overwhelming enough.
- **Consistency vs skill** — if "hard 3 min for everyone" ever becomes the goal, the alternative is
  time-gating the sub-wave release (cost: a strong player sees a sparser screen). Not chosen now.
