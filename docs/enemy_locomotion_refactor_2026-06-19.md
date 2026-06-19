# Enemy locomotion refactor — chassis owns speed/weight/turn/depth (2026-06-19)

## What changed

Movement-pattern Resources used to bake in their own kinematics (`speed`, `down_speed`,
`max_speed`, `accel`, `turn_rate_at_min`, `hover_y`, …). To get a "fast straight" vs a "crawling
straight" enemy we minted *different movement keys* that built the **same shape** at different
speeds/heights — `straight_crawl/slow/medium/fast/reflex`, `drift_low/mid/high`,
`loiter_low/mid/high`, `side_traverse_high/mid/low`.

Now **patterns own only SHAPE** (dimensionless ratios, geometry, timing) and the **enemy/chassis
owns the kinematics**. Two shared, named, numeric axes were pulled out of the key proliferation:

1. **Speed** (chassis-owned) — an absolute px/s `move_speed`, always snapped to a clarity rung.
   Derived from **size** (bigger = slower) and shifted by a per-enemy **engine** modifier that
   moves *linear speed only*. So a small heavy-engine hull is blazing **and** nimble; a large
   all-engine hull is fast in a straight line but still turns/decelerates like a heavy.
2. **Depth** (hybrid: enemy default + formation override) — *where on screen the behavior happens*,
   as `Zones.band_progress` (0 = top/shallow, 1 = bottom/deep): where loiter/drift **hold**, where
   `lane_hook`/`lane_cut` **turn off**, and where the horizontal crosser **crosses**.

Outcome: the speed-variant and depth-variant key families collapsed to one shape each; speed +
engagement-depth are tunable, named, numeric axes.

## The chassis stat block — `scripts/enemies/enemy_base.gd`

```
var move_speed: float = 0.0   # absolute px/s, a clarity rung once resolved
var weight:     float = 1.0   # mass: inertia smoothing + turn/accel damping (was display_scale)
var turn_rate:  float = 0.0   # deg/s base steering
var accel:      float = 0.0   # px/s² base
var depth_bp:   float = -1.0  # default engagement depth (band_progress 0..1); <0 = pattern default
```

`display_scale` is now **purely visual**; `weight` is the physics mass (inertia in `enemy_core`,
turn/accel damping in the steering patterns). An unset value (`0`, or `depth_bp < 0`) falls back to
a "medium" default in the pattern accessors, so bosses / mines / hazards without the block — and
the bare-`Node2D` dummies in dev tools and tests — keep working unchanged.

Patterns read the block via accessors on `scripts/enemies/movement_pattern.gd`:
`_move_speed(enemy)` (fallback 180), `_turn_rate(enemy)` (300 deg/s), `_accel(enemy)` (600 px/s²),
`_weight(enemy)` (1.0), `_depth_bp(enemy, pattern_default)`.

## Resolution — `scripts/levels/enemy_roster.gd`

`SIZE_LOCOMOTION` gives a base per size class: `{ base_rung, weight, turn_rate, accel }` (bigger
size → lower base rung, higher weight, lower turn/accel). `resolve_locomotion(entry)` (folded into
`compose_stats`) computes:

- `move_speed = snap_to_rung(clamp(base_rung + engine*60, 60, 480))`, or a raw `move_speed`
  override on the entry.
- `weight`/`turn_rate`/`accel` from the size class (per-entry overrides allowed).
- `depth_bp` from an explicit entry `"depth"` (preset name or band_progress), **else inherited from
  a legacy banded movement identity** (`loiter_high` → `high`, `drift_mid` → `mid`, …) so the
  key-collapse preserved each enemy's hold/cross height with no per-entry edits.

Named units live in `scripts/systems/clarity.gd` (`SPEED_RUNGS` + `label_for_speed` → "Fast (300)")
and `scripts/systems/zones.gd` (`DEPTH_BANDS` calibrated to the old hold heights: high≈Y50,
mid≈Y90, low≈Y130 + `y_for_progress` / `depth_to_bp` / `depth_label`).

## Data flow (mirrors the `max_health` channel)

`compose_stats` → `WaveSpec` fields (`move_speed`/`weight`/`turn_rate`/`accel`/`depth_override`),
populated by both producers (`wave_generator._make_wave_spec`, `authored_patterns._spec_for_placement`)
→ applied per-spawn in `director._spawn_enemy` **before `enemy.start()`**, where the sector
speed-scale also now lives (`_apply_sector_locomotion_scale` — the per-pattern float walk in
`enemy_core` was deleted). The crosser stagger seeds its cross latitude from the resolved depth.

## Pattern migration

All ~25 patterns in `scripts/enemies/patterns/` now read the chassis via the accessors; each
captured today's literals as **ratios of a base** (move_speed 180 / turn 300 / accel 600) so feel
is preserved at the fallback. State machines normalize their internal speeds as ratios of
`move_speed` (e.g. `lane_charge`/`beeline`: the chassis speed IS the charge/hunt speed, the slow
telegraph is a fraction of it; `loiter`: exit overshoots cruise by a ratio >1). Depth-aware patterns
resolve `hover_y`/`hold_y`/`travel_y`/`return_trigger_bp` from `_depth_bp`.

**Exceptions (intentionally absolute):** `boss_sweep.gd` (bosses have no chassis block) and
`pendulum.rot_lerp_rate` (an aim-lerp, not a steering cap).

## Key collapse

`make_movement` collapsed the variant families to shape keys (`straight`, `drift`, `loiter`,
`side_traverse`); `MOVEMENT_ALIASES` maps any straggler legacy key to its shape, so old DATA (saved
eligibility JSON, authored patterns) still resolves. Shape-distinct keys are unchanged
(`straight_charge`, `lane_*`, `skirmish_*`, `hunt_*`, `pendulum`, `proximity_chase`, `loiter_sweep`,
`side_turn`/`side_dive`).

## Authoring (Enemy Bench / dev tools)

- **Enemy Bench Locomotion tab** — tune `SIZE_LOCOMOTION` + `SPEED_RUNGS` + `DEPTH_BANDS`; per-enemy
  `engine`/`depth`/overrides, with Copy-GDScript back to `enemy_roster.gd` / `clarity.gd` / `ENTRIES`.
- **Pattern Eligibility editor** — `OFFERABLE` is the shape-only key set; a legacy→shape `_canon`
  remap migrates the committed matrix + saved JSON on load.
- **Wave Pattern editor** — per-placement `depth` override (the formation half of the hybrid axis).

## Intended behavior change + follow-ons

- **Speed is now size-derived** (engine defaults to 0). Enemies move at their size's base rung
  until the lead assigns per-enemy `engine` in the bench — this is the *point*, not a regression.
  The old per-key absolute speeds are gone; a "crawl phalanx" authored formation is now a phalanx
  at whatever speed its filled enemies carry (add a per-placement engine/speed override if a
  formation needs to force a tempo).
- **Depth** is preserved for banded-identity enemies and banded authored placements.
- Vestigial `@export` speed scalars remain on the patterns (commented) — a later cleanup can drop
  them once nothing authors them.
