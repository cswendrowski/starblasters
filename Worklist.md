# Worklist

_Cleaned 2026-06-11 (round 3): the round-3 feedback batch (shaders, minefield, nebula,
sector map, weapons, patterns) landed and was verified in code — only genuinely-open items
remain. Shader tasks are front-loaded (current focus). Most items still want an in-game
**eyeball pass**._

---

## Shaders / VFX

### DONE 2026-06-11 (shader sprint — awaiting eyeball)
- ✅ **glow_effect_2d tuners** — 3 sliders (threshold/intensity/opacity) + 3 colour pickers
  (color1/color2/glow) wired live, Copy-GDScript emits the setup, values persist to the tuner JSON.
- ✅ **Ember-smoke variant** — new "smoke" entry in the Embers menu; shader `smoke` toggle desaturates
  the streaks to grey wisps; smoke uses a late `fade_start` so the tail holds to end-of-travel.
- ✅ **Debris-fire tuner** — Explosions tab now has 12 knobs (count/speed/gravity/drag/scale/burn +
  flame width/height/speed); `flame_size`/`flame_speed` exposed on `ship_debris_ember`; copy snippet.
- ✅ **Smoke orient-to-motion knob** — already wired end-to-end (Shader Lab knob → `smoke_trail_emitter`).
- ✅ **Ember lifetime-vs-distance** — `fade_start` is a tunable knob; smoke variant defaults it late (0.92).
- ✅ **Player damage = 50% current max** — verified correct (both consumers gate on `1-hull/max ≥ 0.5`).
- ✅ **Enemy damage-tell** — no active enemy fire/smoke (engine flame disabled); shared `engine_torch`
  fix covers any future re-enable. No-op.

### Still open
- ✅ **Smoke trail rebuilt 2026-06-11** — threw out the smoke_pulse strip (couldn't be tinted)
  and the per-frame angle hacks; clean GPUParticles2D per the canonical recipe (procedural white
  billow puff, two-tone ramp, real angular-velocity spin, emission follows motion). Awaiting eyeball.
- ✅ **Fire comet scrapped 2026-06-11** — `burning_smoke_fx.gd` (segmented-atlas comet) + its capture
  tools deleted; Shader Lab → Explosions now spawns `scenes/effects/burning_trail.tscn` (Roman's
  GPUParticles2D fire trail) instead. Awaiting eyeball.

### Eyeball decisions (need Roman)
- **Glow-halo redundancy.** Try removing the per-object diffuse halo on bullets/engines; if the env
  bloom reads well enough, drop it.

## Audio
- **Corpo-wave audio restart.** Against corporate waves the music abruptly stops then restarts when a
  round starts. (`music_manager.gd` — untouched so far)

## Weapons / data
- **Muzzle-flash-as-scenes refactor.** [suggestion] Establish the muzzle flashes we use as scenes with
  attach markers, instead of code-spawned per weapon. Optional architecture cleanup.
- **Dev bullet-speed editor.** Adjust enemy bullet speeds in absolute **rung** terms (1–8 = 60–480
  px/s, `Clarity`-snapped) and **save** them to `data/bullets/*.tres`. (Enemy Bench today only has a
  relative ×-multiplier per enemy.)
- **Codex armory label.** Rename the "Primary Cannons" category header (`enemy_codex.gd:58`) to
  "Blaster" — the only user-facing "Cannon" string left after the shop/manage-ship rename.
- **DPS report + `weapon_stats.csv`.** Regenerate to include Shredder + Pulse Laser. Fix the `.import`
  first (it's `csv_translation`, spawns `.translation` junk) before tracking. Then the (report-only)
  rebalance decision: Energy Blaster top DPS as the *free* fallback, Minigun far too weak, Autocannon
  scales backwards.

---

## Big / playtest-gated

- **Recycler — Pillar 2 (roster migration).** Not started. RecycleController step-2 (timing/look owner,
  zero-regression defaults) + the recycle dev tuner exist; the deep refactor remains — generalize
  edge-detection out of `enemy_base`, NONE-mode opt-in, `enemy_base` delegation, MidDepthPresentation
  shader-tint swap. Regression surface = the whole enemy roster → playtest-only. Spec:
  `docs/recycling_system_pillar2_2026-06-04.md`.

- **Supremacy Push globbing — Gap 2.** Core anti-glob (`_anchor_stagger_y`, descending cruisers) + the
  horizontal-cross overlap fix (Gap 1, height-aware crosser stagger) landed — **playtest first.**
  Remaining = make cruiser lane *selection* active (prefer a lane whose neighbours are clear, via
  `lane_traffic.is_lane_free`/`free_adjacent`) instead of the passive vertical-queue. Feel-dependent.
  (`director.gd`)

- **Mine Hazards → 300-enemy mark.** Background decoration + new art + black-box + cross-screen leak are
  now DONE. Remaining = DENSITY: numerous tight waves to weave/shoot through, bomblet clusters viable,
  higher per-lane mine/bomblet density (a place we can relax the on-screen enemy cap). (`levels_v2.gd`
  minefield + `director.gd`) [playtest]

## Renderer (report-only levers — eyeball)

- Forward+ polish levers from `docs/renderer_audit_2026-06-11.md`: `glow_hdr_threshold` tune,
  color-grade strength (contrast 1.08 / saturation 1.12), gate heat-haze (D1) to thrust-only, and push
  more FX into HDR-additive so they bloom (shield ring, beam cores, super flashes). All eyeball calls,
  none applied.
