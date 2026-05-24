# Starblaster Boss Roster Proposal — 2026-05-24

**Status:** research + design proposal, no code changes. Targets the new "sector clears when all 3 row bosses are beaten" flow (Sector Map V3). Current count: 3 bosses for 9 slots. This doc proposes how many to build, which to keep/rework, and what to add.

**Sources note:** External web sources were thin (Wikipedia stubs lack boss-mechanic detail; fan wikis 403'd). Figures below reflect designer/genre knowledge and are flagged where uncertain. No fabricated citations.

---

## 1. Genre research summary

**TTK norms (roguelite-shmup band, the relevant peer group):**
- Roguelite-shmup bosses run **45–90s** for early/midbosses, **90–150s** for late/final. Shorter than arcade Cave-style bullet-hell bosses (often 2–3 min, multi-phase) because (a) runs are repeated and a 3-min wall every attempt is fatigue, (b) part/build variance makes long fights swingy.
- Peer reference points: Steredenn's procedural bosses ~45–75s. ZeroRanger encounters 60–120s with the finale longer. Cobalt Core boss combats compress turns but feel ~60–90s of "fight" per phase.
- **Recommendation for Starblaster:** Sector-1 bosses **45–70s**, Sector-2 **60–90s**, Sector-3 **90–120s**. Per-sector total of 3 bosses ≈ 3–5 min combined, leaving 15–18 min for chaff + nodes inside a 20–24 min run target.

**Archetype taxonomy:**
- **Summoner** — spawns adds, you split priority. Ref: DonPachi end-area carriers.
- **Bullet-hell turret** — anchored, wide spreads. Ref: Cave stage-1 bosses, Touhou midbosses.
- **Mobile sweeper** — slides across the playfield laying patterns. Ref: ZeroRanger mid-game.
- **Multi-part / sectional** — destroy components first, then core. Ref: R-Type Dobkeratops, Gradius cores.
- **Transforming** — physical phase swap. Ref: Mushihimesama finale.
- **Beam-sweeper / area-denial** — wide column lasers, lane play. Ref: Ikaruga stage-3.
- **Mirror / predictive** — pre-aimed at the player; demands continuous motion. Ref: Touhou Sakuya.
- **Glass cannon duelist** — low HP, high pressure. Ref: Steredenn rival captains.
- **Black-hole / space-warper** — area you can't be in. Ref: ours (Commander).

**Phase transitions:** HP-gate dominates in roguelite shmups (66%/33% or 50%/0%). Time-gate escalates stale fights. Component-destruction is rare but signature. Telegraph 0.6–1.2s for screen-filling attacks; below 0.5s feels cheap, above 1.5s sluggish.

**Roguelite specifics:**
- Variety per **run** matters as much as per game — back-to-back summoners feel same-y.
- Difficulty scaling: Starblaster already does `× (1 + 0.05 × sectors_cleared)` on damage. For bosses, also bump HP ~1.4× per sector and add one attack-rotation entry per tier.
- Reward design: bounty + a guaranteed Part choice at boss clear is the genre convention.

---

## 2. Audit of existing 3 bosses

**Critical implementation note:** Reaver (`scripts/enemies/boss_reaver.gd`, 25 lines) and Sentinel (`scripts/enemies/boss_sentinel.gd`, 52 lines) **inherit from `boss.gd` and disable Commander's signature moves** (`black_hole_interval_min = 9999.0`). Architecturally we have **one boss with three stat presets**, not three bosses. Adding a real new boss = a new subclass with its own attack coroutines, not a stat tweak.

| Boss | Archetype(s) | HP | TTK est. | Phases | Signature | Strengths | Weaknesses |
|---|---|---|---|---|---|---|---|
| **Commander** (`boss.gd`) | Summoner + Area-denial | 160 | ~50–70s | 1 | Charge→fire→detonate black hole | Strong identity, BH read works | No phase transition; minion loop basic |
| **Reaver** | Aggro-pressure | 200 | ~60–80s | 1 | None — just shoots faster | Easy to grok | Archetypally weakest — "Commander but angry" |
| **Sentinel** | Turret + homing | 320 | ~80–110s | 1 | Drifting missile salvo every 6.5s | Highest HP feels like a wall | Static, no phase escalation; pattern reads same start-to-finish |

Common gaps: **no HP-gated phase transitions**, **no enrage shifts at thresholds**, **no telegraph cinematics**. All three use the same `boss_sweep.gd` movement.

---

## 3. Recommended target count: **6 bespoke bosses + 1 final = 7 total**

**Reasoning:**
- 9 slots/run × multi-run replay = need archetypal variety, not just count. 6 bespoke → 9-slot run pulls 6 unique + 3 repeats. With biome palette/attack-swap variants (cheap reskins), each bespoke can supply 2 visual variants → 12 visual flavors from 6 fights.
- Peer benchmarks: Cobalt Core ~4 finals + several midbosses; ZeroRanger ~6 named encounters. 6 is the solo-dev sweet spot.
- **Final is special** — sector-3 row-3, the run climax. Counted separately so it can be a bigger lift (3 phases, transforming).
- Below 5 = repeats feel obvious. Above 8 = production overrun.

---

## 4. Proposed roster

### Returning, KEEP: Commander (sector 1–2)
- **Visual:** existing. Slate-grey carrier silhouette.
- **Archetype:** Summoner + Area-denial.
- **TTK:** 60–75s. **HP:** 160 sector-1, 220 sector-2.
- **Phases:** add 50% HP gate — minion cadence doubles, BH charge time 2.5s → 1.8s.
- **Signature:** the charging black hole.
- **Never-pair-with:** Voidmaw.

### REWORK: Reaver → **Lash** (sector 1–2)
- **Why:** current Reaver has no archetypal identity.
- **Visual:** narrow, raked-back hull, hot orange thrusters. Reads as fighter, not capital.
- **Archetype:** Mobile sweeper (glass cannon). **TTK:** 45–60s. **HP:** 140.
- **Phases:** HP-gate 50%. P1 strafes in sin³ arcs firing 3-bullet fans. P2 dives — telegraphs with red lock-on reticle 0.9s, commits to straight-line strafe past player Y.
- **Signature:** *the dive.* Player has to clear the lane.
- **Never-pair-with:** Howler.

### REWORK: Sentinel → **Aegis** (sector 2–3)
- **Why:** promote to multi-part — its identity becomes "shielded."
- **Visual:** broad turret platform flanked by 2 destructible pylon nodes. Cyan energy.
- **Archetype:** Multi-part / sectional + turret. **TTK:** 90–120s. **HP:** core 240, each pylon 80.
- **Phases:** auto-gate on pylon kills. P1 (both pylons up): core **damage-immune**, pylons fire arcing crossfire. Destroying a pylon opens damage window + rage-fires from the other. P3 (core only): missile cadence 6.5s → 3.5s, adds 7-bullet aimed spread.
- **Signature:** *the pylons.* The "you can't even hurt it yet" beat.
- **Never-pair-with:** any other tank in same sector.

### NEW: **Howler** (sector 1)
- **Visual:** short, stubby gunboat with oversized exhaust cones. Yellow/black hazard stripes.
- **Archetype:** Bullet-hell turret. **TTK:** 45–60s. **HP:** 130.
- **Phases:** HP-gate 50%. P1: anchored, alternating 5-bullet aimed spread (1.4s) + 360° 12-bullet ring (4s). P2: ring cadence 2.5s, rotates 30° per fire.
- **Signature:** *the rotating ring.* Commit to a gap and follow it.
- **Never-pair-with:** Commander.
- **No new minion types needed.**

### NEW: **Voidmaw** (sector 2)
- **Visual:** organic, ribbed maw-shape sprite. Deep purple/black with glowing core.
- **Archetype:** Black-hole / area-denial — distinct from Commander because the BH is **stationary, drifts slowly toward player**.
- **TTK:** 75–95s. **HP:** 220.
- **Phases:** HP-gate 33%. P1: anchored, exhales slow-drifting BH every 8s (40 px/s toward player Y, despawns at bottom); concurrent 3-bullet fan fire. P2: 2 BHs alive at once, fans become 5-bullet.
- **Signature:** *the drifting hole.* Spatial chess.
- **Never-pair-with:** Commander.

### NEW: **Spinwright** (sector 2–3)
- **Visual:** segmented rotating ring around central hub. White/teal.
- **Archetype:** Transforming + beam-sweeper. **TTK:** 90–110s. **HP:** 260.
- **Phases:** HP-gate 66% and 33%. P1 (ring closed): rotating ring deflects bullets to its top hemisphere — must shoot from below. P2 (ring opens): slow horizontal beam sweep (telegraph 1.0s, duration 2.2s, one safe gap). P3: two beams, gap moves with sin easing.
- **Signature:** *the beam sweep with a moving gap.* Continuous repositioning.
- **Never-pair-with:** Aegis.

### NEW (FINAL): **The Conductor** (sector 3 row-3 only)
- **Visual:** asymmetric flagship, 1.5× scale, two satellite drones orbit it. Gold + black.
- **Archetype:** Mirror/predictive + multi-part + transforming.
- **TTK:** 120–150s. **HP:** core 380, two satellites 100 each.
- **Phases:** HP-gate 66% and 33%. P1: satellites mirror player X, fire pre-aimed 3-shot bursts (0.7s telegraph laser dot). P2 (one satellite gone OR 66%): core enrages, 18-bullet ring every 4s. P3 (33%): satellites gone, core transforms — sprite swap, becomes mobile, dashes Reaver-style firing aimed cones.
- **Signature:** *the satellites mirroring your X.* You can't sit still even before bullets fly.
- **New requirement:** tethered-orbit movement resource (~50 lines, `scripts/enemies/patterns/`).

---

## 5. Implementation order

1. **Howler** (sector-1 turret). Smallest scope, fills the "readable sector-1 boss" gap. ~1 day.
2. **Lash (rework Reaver)** — give Reaver a real signature. ~1 day.
3. **Voidmaw** — reuses existing black_hole hazard with tweaked params. ~1.5 days.
4. **Aegis (rework Sentinel)** — multi-part is most novel; biggest player-perception payoff. ~2 days.
5. **Spinwright** — beam sweep needs new VFX/hitbox. ~2 days.
6. **The Conductor** (final) — last; transforms + sprite-swap is heaviest. ~3 days.

After all 6 ship: **biome reskins** (palette + one attack tweak) per boss to double visual variety. ~0.5 day per reskin.

---

## 6. Open design questions

1. **Final exclusivity:** always Conductor sector-3 row-3, or pool of 2 finals for replay variety? Recommend always-Conductor for v1.
2. **Boss rewards:** bounty + **guaranteed Part choice** (vs combat-node 50% chance)? Convention says yes.
3. **Sector-scaling formula:** HP × 1.4 per sector across the board, or boss-specific?
4. **"Never-pair" enforcement:** `conflict_tags` array per boss resource (mirrors chaff system).
5. **Telegraph audio:** every new attack assumes a charge-up SFX. Reusable charge sound or 4+ new SFX assets needed?
6. **Phase-transition VFX:** scaffold a shared "boss enrage" flash + screen shake helper before boss #2 so transitions read consistently.

---

Relevant files:
- `scripts/boss.gd`
- `scripts/enemies/boss_reaver.gd`
- `scripts/enemies/boss_sentinel.gd`
- `scripts/enemies/enemy_base.gd`
