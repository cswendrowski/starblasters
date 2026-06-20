# Enemy Locomotion — reference / field guide

A living reference for the chassis-locomotion system (shipped 2026-06-19). For the *why* + the
migration record see `enemy_locomotion_refactor_2026-06-19.md`; this doc is the *what each knob
means* guide for tuning.

---

## Mental model

> An enemy's motion = **a movement SHAPE** (the pattern: how it traces the screen) **× the
> CHASSIS** (the enemy's own speed / weight / turn / accel / depth).

The pattern owns only the *shape* (ratios, geometry, timing). The enemy owns the *scale*. So one
`straight` shape covers crawlers and blitzers; the difference is the enemy's `move_speed`.

Two axes you tune per enemy:

| Axis | What it controls | Unit | Comes from |
|---|---|---|---|
| **Speed** | How fast it moves | px/s on a clarity rung | `size base rung + engine offset` (or a raw override) |
| **Depth** | *Where on screen* it holds / turns / crosses | `band_progress` 0–1 (top→bottom of the engagement band) | enemy default (from its movement identity) + per-formation override |

Weight, turn-rate, and accel come from **size** and aren't on the speed/depth axes — they're the
"hull physics."

---

## Chassis stats (what each field is)

Set on every combat enemy (`scripts/enemies/enemy_base.gd`). Patterns read them through accessors
that fall back to a "medium" default when unset, so bosses / mines / dev dummies keep working.

| Stat | Unit | Meaning | Fallback (if unset) |
|---|---|---|---|
| `move_speed` | px/s | Base linear speed; the pattern's primary motion. Always snapped to a rung. | 180 (medium) |
| `weight` | mass | Inertia: heavier = laggier turns + slower accel + softer stops. (Was `display_scale`; now decoupled from visual size.) | 1.0 |
| `turn_rate` | deg/s | How fast steering patterns (jet / omni / inertial) swing the nose. | 300 |
| `accel` | px/s² | How fast accelerating patterns (charge / beeline / loiter-exit) build speed. | 600 |
| `depth_bp` | 0–1 | Default engagement depth (see Depth axis). `<0` = use the pattern's own default. | pattern default |

`display_scale` is now **purely visual** — change it for sprite size, not feel.

---

## Speed — size base + engine

`move_speed = clamp( snap_to_rung( size.base_rung + engine×60 ), 60, 480 )`

### Size base table (`SIZE_LOCOMOTION`, Enemy Bench → Locomotion tab)

Bigger = slower + heavier + lazier turns. Starting values (yours to tune):

| Size | base speed | weight | turn (deg/s) | accel (px/s²) |
|---|---|---|---|---|
| tiny | 300 (fast) | 0.5 | 360 | 900 |
| small | 240 (quick) | 0.8 | 320 | 800 |
| medium | 180 (medium) | 1.2 | 260 | 600 |
| large | 120 (slow) | 2.0 | 180 | 420 |
| huge | 60 (crawl) | 3.5 | 120 | 300 |
| giant | 60 (crawl) | 5.0 | 90 | 220 |

### Engine (per-enemy, the "speed modifier")

A **signed rung offset** that shifts *linear speed only* — weight/turn stay at the size value. `+1`
= one rung faster (+60 px/s), `-1` = one slower. This is how you make a "small heavy-engine"
blazing-but-nimble hull or a "large all-engine" fast-but-heavy hull.

- small (base 240) + `engine 1` → **300** (fast), still small weight 0.8 → nimble.
- large (base 120) + `engine 3` → **300** (fast), still large weight 2.0 → fast straight line, heavy turns.
- medium (base 180) + `engine -2` → **60** (crawl).

### Speed rungs (`SPEED_RUNGS`, names for px/s)

Speeds snap to these; the bench shows "Name (px/s)". 1 rung = 60 px/s = 1 px/frame.

| Name | px/s | px/frame |
|---|---|---|
| creep | 30 | 0.5 |
| crawl | 60 | 1 |
| slow | 120 | 2 |
| medium | 180 | 3 |
| quick | 240 | 4 |
| fast | 300 | 5 |
| reflex | 360 | 6 |
| blitz | 420 | 7 |
| max | 480 | 8 |

**8 px/f (480) is the hard readability ceiling** — past it objects strobe. Lasers sit at 8; chaff
1–3; fast movers ~5–6.

**creep (30) is the slow floor** — the one clean sub-1px/frame speed (1px every 2 frames). Whole
rungs (≥60) move every frame; 30 is the slowest that still reads as smooth drift. Reach it with a
negative `engine` (e.g. crawl-base − 1) or an explicit `move_speed: 30`. Don't author odd in-between
values (45, 78…) — they snap to a rung anyway and would shimmer.

---

## Depth — where the behavior happens

Measured as `band_progress` across the **engagement band** (screen Y 40 → 195): `0` = top/shallow,
`1` = bottom/deep. **high = shallow** (acts near the top), **low = deep** (near the bottom).

### Depth bands (`DEPTH_BANDS`, names for band_progress)

Calibrated to the old hold heights:

| Name | band_progress | screen Y | feel |
|---|---|---|---|
| high | 0.065 | ~50 | acts just inside the top |
| mid | 0.323 | ~90 | upper-middle |
| low | 0.58 | ~130 | mid-screen / deeper |

You can also give a raw `band_progress` number instead of a name. An enemy with **no** depth set
inherits the band from its movement identity (a `loiter_high` identity → `high`), and if it has no
banded identity it uses the pattern's own default.

### What depth means per shape

- **loiter / drift / skirmish** — the **hold** height.
- **lane_hook / lane_cut** — the **turn-off** depth (how far down before it curves away).
- **side_traverse / side_cut** — the **cross / entry** height.
- **loiter_sweep** — the **settle** band before raking.
- **advance_retreat** — the **dive** depth before retreating.
- Pure descenders (`straight`, `hunt_*`, `pendulum`, lane weave/shift/drift, `straight_charge`)
  **ignore** depth.

---

## Movement shapes (the keys)

Shape-only after the refactor — speed/depth are axes, not keys. Set an enemy's eligible shapes in
the Pattern Eligibility editor.

| Key | Shape | Depth-aware? |
|---|---|---|
| `straight` | Pure vertical descent (+ optional tiny x-drift). | — |
| `straight_charge` | Slow telegraphed entry, then accelerates hard to full `move_speed` and rushes the exit. Entry ≈ 0.14× the charge speed. | — |
| `skirmish_loop` / `skirmish_figure8` | Descend to a band, trace a circle / figure-8 for a few cycles, then exit. | hold |
| `drift` | Slow descent to a hold height, then a jiggled drift in place (tank/holder). | hold |
| `loiter` | Ease in, hold with a gentle bob/sway, then accelerate away downward. | hold |
| `lane_weave` | Wobble *within* its own lane while descending (Weaver). | — |
| `lane_drift` | One slow lane-to-lane slide timed to the fire zone (Drifter); lane-aware. | — |
| `lane_shift` | Descend, then a one-way commit to an adjacent lane, then hold it (Shifter). | — |
| `lane_hook` | Dive a lane, curve into the next lane at the turn-off depth, climb back up off the top (droppers). | turn-off |
| `lane_cut` | Dive a lane, curve left/right at the turn-off depth, run off the side. | turn-off |
| `side_turn` | Advance in horizontally, rounded turn down into a lane, descend to exit. | — |
| `side_dive` | Like `side_turn` but a shorter advance → a swifter plunge. | — |
| `side_traverse` | Slow horizontal cross at a fixed height (minelayer). | cross |
| `hunt_beeline` | Descend, then beeline straight at the player (`move_speed` = hunt speed). | — |
| `hunt_omni` | Hover/strafe holding a stand-off range, nose on the player; leaves after a few passes. | — |
| `pendulum` | Vertical ping-pong: dive → aim → fire → rise → aim → fire → repeat or exit. | — |
| `proximity_chase` | Drift straight until the player is near, telegraph, then a relentless accel-chase with wall bounce (smart mine). | — |
| `loiter_sweep` | Descend to a settle band, then rake left↔right (beam shooters). | settle |

> Exceptions kept fully bespoke: **bosses** (`boss_sweep`) and the pendulum aim-lerp don't use the
> chassis — they stay absolute on purpose.

---

## Where you author each thing

| You want to change… | Tool / place | Output |
|---|---|---|
| Size base speed / weight / turn / accel (the whole class) | **Enemy Bench → Locomotion** tab | Copy GDScript → `enemy_roster.gd` `SIZE_LOCOMOTION` |
| One enemy's speed (engine) + default depth | **Enemy Bench → Enemy** tab, "Locomotion (this enemy)" | Copy GDScript → that enemy's roster `ENTRY` |
| Which shapes an enemy may use | **Pattern Eligibility editor** (identity + eligible set) | exports `pattern_eligibility.gd` `DATA` |
| A formation's per-slot depth | **Wave Pattern editor** (depth brush: `def`/high/mid/low) | exports `authored_patterns.gd` `DATA` (`"depth"`) |
| Rung names / depth-band fractions | code consts (`clarity.gd` `SPEED_RUNGS`, `zones.gd` `DEPTH_BANDS`) | edit in source (no tab yet) |

### Per-enemy roster `ENTRY` fields (the data behind it all)

```gdscript
{
  "scene": "res://.../enemy_x.tscn",
  "size":  "small",      # → base speed/weight/turn/accel from SIZE_LOCOMOTION
  "engine": 1,           # optional: rung offset on the base speed (+1 = +60 px/s). default 0
  "depth": "high",       # optional: "high"/"mid"/"low" or a 0..1 band_progress. default = inherit
  # optional raw overrides (skip the size/engine math entirely):
  "move_speed": 300,     # absolute px/s (snapped to a rung)
  "weight": 0.6,
  "turn_rate": 340,
  "accel": 700,
  # ...existing fields (tier/tags/movement/vary/hp_override/...) unchanged
}
```

A formation placement (`authored_patterns.gd`) can also carry `"depth"` to override the enemy
default for that deployment (the hybrid axis).

---

## Gotchas / good to know

- **Speed is size-derived now** (engine defaults to 0). Until you set engines, every enemy moves at
  its size's base rung — that's the baseline to tune *from*, not a bug.
- **Vestigial exports**: the old `@export var speed/down_speed/…` on the pattern files are dead
  (ignored at runtime, commented as such). Tune speed on the *enemy*, not the pattern.
- **Sector scaling** still applies (+5%/cleared sector, cap 2×) — it scales the resolved
  `move_speed`/`accel` once at spawn, then re-snaps to a rung.
- **Legacy keys still resolve**: old movement keys (`straight_fast`, `loiter_high`, …) alias to the
  shape key, and the editors migrate them on load — but new authoring should use the shape keys.
- **Weight ≠ visual size**: `weight` drives feel, `display_scale` drives the sprite. A small sprite
  can be heavy, or vice-versa.
