# Enemy Speeds — Audit & Proposal
*Date: 2026-05-24 · Branch: horizontal-rework*

## 1. Genre research summary

Source notes: hard-cited numbers for shmup pixel velocities are scarce because most genre references talk in terms of dodge-windows and "screens per second," not px/s.

### Coordinate-space normalization

Internal viewport is **480×270**, playfield band is **216 px wide** (X 132–348) by **270 tall**. Classic shmups target ~224×288 (CPS/Cave standard). **Our playfield short axis is essentially a Cave board**, so px/s figures port over almost 1:1.

Mental yardsticks:
- Player traversal: 216 px playfield at 220 px/s = ~1.0 s full crossing.
- Screen height 270 px. A 200 px/s bullet takes 1.35 s top→bottom.

### Reference bands (per-tier movement)

| Tier | Cave (DoDonPachi/Mushi) | Touhou mid | ZeroRanger/Steredenn | Recommend for us |
|------|-------------------------|-----------|----------------------|------------------|
| Chaff descent | ~120–160 | ~100–140 | ~140–200 | **140–180** |
| Chaff dive/dart | ~250–320 | n/a | ~280–360 | **300–360** |
| Mid striker (curving) | ~100–150 | ~120 | ~140–200 | **160–200** |
| Loiter/station-keep enter | ~60–90 | ~80 | ~100–140 | **100–140** |
| Tank/heavy | ~40–80 | ~50 | ~60–100 | **60–90** |
| Boss approach | ~80–120 | — | ~80–140 | **80–130** |

### Reference bands (bullet speeds)

| Kind | Cave | Touhou | Indie | Recommend |
|------|------|--------|-------|-----------|
| Aimed sniper | 350–500 | 220–300 | 280–380 | **280–340** |
| Spread arc | 180–260 | 150–220 | 200–280 | **200–240** |
| Dumb downward | 200–280 | 160–220 | 220–300 | **220–260** |
| Heavy/telegraphed | 120–180 | 100–160 | 140–200 | **140–180** |

---

## 2. Audit table

| Enemy | Pattern | Speed (px/s) | TOS (s) | Role | Notes |
|-------|---------|--------------|---------|------|-------|
| Firecore | straight | 220 | ~1.3 | chaff (gated S2/D5) | single shot |
| Dart | straight (fast) | 480 | ~0.6 | chaff dart | no shoot — kamikaze |
| Drifter | straight | 220 (default 125) | ~1.3 | chaff | brief said "slow descent" — currently identical to Firecore |
| Hunter Drone | beeline | enter 160 / hunt 230, accel 360 | ~2.0 | chaff hunter | |
| Burner | straight | 220 | ~1.3 | uncommon | no shoot |
| Weaver | s_curve | down 220 / amp 160 / freq 1.6 | ~1.3 | striker | aimed fire — too fast |
| Hover | loiter | enter 240 / hold 5 / exit accel 600 | ~6.5 | mid striker | |
| Frigate | slow_advance | enter 35 / drift 32 | indefinite | tank | very slow |
| Cutter | side_cut | enter 130 / cut 210 | ~1.8 | striker | single_fast |
| Skirmisher | advance_retreat | 180 adv / 260 ret / 240 break / 0.6 hold × 2 | ~4–5 | striker | aimed fire |
| Beam Shooter | loiter | enter 110 / hold 3 / exit 350 | ~5 | mid | beam, not shoot_pattern |
| Gunship | loiter (default) | enter 110 / hold 3 | ~5 | mid | hardcoded weapon |
| Sapper | omni | varies | varies | rare | melee |
| Crystal | loiter (default) | enter 110 / hold 3 | ~5 | rare | spread5 |
| Minelayer | side_traverse | 55 | ~9 | rare | drops mines |
| Interceptor | top_dive | 270 | ~1.0 | rare | no shoot |
| Bulwark | bulwark_drift | enter 25, drift 36 | indefinite | rare | shield projector |
| Cruiser / Drone Carrier | loiter | enter 110 / hold 3 | ~5 | rare | custom weapons |

### Per-shoot-pattern speed (bullet)
- **Base enemy_bullet**: 200 px/s (`scripts/weapons/enemy_bullet.gd`).
- All shoot patterns use this single bullet — **no per-pattern speed override exists**. Aimed, burst, spread all fire at 200.

---

## 3. Proposed tweaks

### Movement

| Enemy | Current | Proposed | Reasoning |
|-------|---------|----------|-----------|
| **Drifter** | straight 220 | **straight 110** (drift_x ±15) | Brief: "slow descent." Currently a Firecore clone. Make it linger so single_shot has tension. TOS ~2.5s. |
| **Firecore** | 220 | **180** | Mid-band fast; reads identical to Burner. Slow slightly so it sits between Drifter and dive types. |
| **Dart** | 480 | **360** | 480 crosses the 270 height in 0.56s, below human reaction floor when mid-dodge. 360 = 0.75s. |
| **Weaver** | down 220 / freq 1.6 | **down 160 / freq 1.2 / amp 110** | Fires aimed — aimed enemies need slower carriage for fairness. |
| **Hover** | enter 240 / hold 5 / exit accel 600 max 700 | **enter 180 / hold 3.0 / exit accel 400 max 480** | Exit at 700 rams a player drifting up. Trim. |
| **Skirmisher** | adv 180 / ret 260 / 0.6 hold | **adv 150 / ret 220 / 0.8 hold** | Aimed-fire pacing too quick. |
| **Hunter Drone** | hunt 230 / accel 360 | **hunt 190 / accel 280** | Beeline 230 snaps onto player faster than player can strafe. Should threaten, not connect. |
| **Interceptor** | 270 | **220** | Same family as Dart; differentiate by HP + trajectory, not raw speed. |
| **Frigate** | enter 35 | **enter 60** | 35 reads as stationary; player kills it before it reaches hold_y. |
| **Bulwark** | enter 25 | **enter 50, drift amp 50, speed 0.45** | "is this broken?" slow. |
| **Cutter** | enter 130 / cut 210 | **enter 160 / cut 250** | Identity is "snaps across screen"; current pace is a stroll. |
| **Minelayer** | 55 | **75** | 9s on screen is longer than most enemies' lifetime. Aim for ~6s. |
| **Loiter default** (Beam/Gunship/Crystal/Cruiser/Carrier) | enter 110 / hold 3 / exit accel 300 max 350 | **medium: 130 / 3 / 400-450; large: 90 / 4 / 280** | Currently 6 enemies share identical entry choreography. Split by tier. |

### Bullets

Big issue: **every enemy bullet is 200 px/s regardless of source**. Aimed shots should be ~280–340, dumb downward ~220–260, heavies ~140–180. Currently all bunched mid.

| Bullet context | Current | Proposed | Reasoning |
|----------------|---------|----------|-----------|
| Dumb straight (Drifter/Firecore/Hover) | 200 | **220** | Slight bump; current feels floaty. |
| Aimed (Weaver, Skirmisher) | 200 | **300** | Aimed bullets need to *threaten*; 200 = stationary at our pace. |
| Burst (Frigate) | 200 | **180** | Slower column lingers, forces lateral dodge. |
| Spread (Crystal spread5) | 200 | **210** | Mostly OK; tiny bump. |
| Cutter single_fast (0.3–0.5s interval) | 200 | **240** | Fast aggressive role rewards faster bullets. |

Implementation note: needs a per-shoot-pattern `bullet_speed` override. Cheapest path: `@export var bullet_speed: float = -1.0` on `shoot_pattern.gd`, override in `_spawn_bullet` if > 0. (Not in this doc's scope.)

---

## 4. Bullet speeds — separate considerations

- **Player bullets** at 1400 px/s. 7× the slowest enemy bullet. Healthy.
- **Lead factor** (`AimedShot.lead_factor`) defaults to 0 — no enemy aims with lead. Could flip to 0.15 on Skirmisher for "experienced gunner" feel without raising bullet speed.
- **Bullet hitbox**: 6×6. With proposed 300 px/s aimed + ~270 tall screen, player has ~0.9s reaction. Combined with 0.7–1.1s fire interval that's near-continuous. May need to lengthen Skirmisher interval to 1.0–1.4s after the bullet bump.

---

## 5. Open questions for designer

1. **Drifter identity**: slow Firecore variant (assumed) or fast-out-of-the-way fired projectile?
2. **Dart at 360 vs 480**: 480 is reaction-test tier. If "Dart is the unfair one, learn to predict spawns," keep 480. If just kamikaze chaff, 360.
3. **Per-shoot-pattern bullet speeds**: scope as a separate refactor (add override on `shoot_pattern.gd`) or accept one-bullet-scene limitation?
4. **Sector scaling**: should chaff speed scale with `sectors_cleared` like the (TODO) player damage scaling? Suggest +5%/sector cap at +25%.
5. **Loiter default rationalization**: 6 different rare enemies share identical movement. Worth giving Cruiser/Carrier/Beam-Shooter distinct loiter timings?
6. **Bulwark drift 25**: intentional ("immovable wall") or stale halved-res leftover?

---

Relevant files:
- `scripts/levels/enemy_roster.gd` (speed overrides per-entry)
- `scripts/enemies/patterns/` (per-pattern defaults)
- `scripts/weapons/enemy_bullet.gd` (bullet base speed = 200)
- `scripts/enemies/shoot_patterns/shoot_pattern.gd` (where a `bullet_speed` override would live)
