# Asteroid HDR-2D darkening — RESOLVED (2026-06-24)

**Status: FIXED** with a one-function shader change — no architectural change needed. The
two-viewport / LDR / clamp approaches below were exploratory and are NOT used.

## THE FIX (2026-06-24)
The asteroid darkened over HDR-bright content because its shader (`Planets/Asteroids/Asteroids.gdshader`)
wrote **alpha-0 fragments** for the transparent regions around the rock. In a `use_hdr_2d` viewport,
a canvas item that writes alpha<1 pixels crushes its OPAQUE pixels to black when drawn over HDR-bright
(>1) content. Normal sprites / ColorRects don't hit this (a plain opaque ColorRect renders fine over a
2.0 bar; only the asteroid shader went black — that's the tell Roman pointed at: "ships/enemy sprites
don't have this problem, asteroids do, same play space"). Confirmed by isolation: forcing the shader
fully opaque (`COLOR.a = 1.0`) rendered tan, not black → it's the alpha-0 fragments, not the colour.

**Fix:** the fragment now composites **opaque-or-discard** instead of writing alpha-0:
`inside → COLOR = vec4(col.rgb, 1.0)`, `outline → opaque outline_color`, `else → discard`. The
discarded pixels show the background exactly as alpha-0 did, so the LOOK is unchanged, but no alpha<1
fragment is written → no crush. Verified: asteroid renders clean over a glow-3.0 LandMasses planet in
a plain single-HDR viewport (the real play space), bullets keep their glow, bg/parallax asteroids
(same shader) unaffected. `Asteroid HDR Lab` (dev menu) is now a single-pane verification bench.

---
## Exploratory history (NOT the fix)

**Status (pre-fix):** root-caused; compare-lab built with two candidate architectural fixes.

## Compare-lab (BUILT 2026-06-24)
`scripts/dev/asteroid_hdr_lab.gd` + `scenes/dev/asteroid_hdr_lab.tscn`, dev-menu button
"Asteroid HDR Lab". Two live panes, same scene (bright planet via `PlanetGlowConfig` + 5 drifting
gameplay-style asteroids + 3 HDR-bright bullets):
- **LEFT** = current single-HDR viewport (the darkening).
- **RIGHT** = fix candidate(s), tunable:
  - `Backdrop clamp` slider — composites the backdrop (rendered+bloomed in an inner HDR SubViewport)
    through a `min(rgb, ceil)` clamp into the HDR gameplay viewport. Lower ceil = cleaner asteroids
    but dimmer planet.
  - `Right = LDR gameplay` checkbox — renders the gameplay pass LDR (`use_hdr_2d=false`) over the
    bloomed backdrop texture.
- Controls: planet picker, `Planet glow x` (crank to see the worst case), clamp slider, LDR toggle.

### Compare-lab findings (verified with a rock centred over a glow-3.0 LandMasses)
- **LDR-gameplay (right pane, checkbox ON) is the clean winner for asteroids:** planet stays FULL
  bright + asteroids render perfectly (no crush). **Cost: gameplay VFX in that pass don't self-bloom**
  (bullets render as plain rects). Backdrop bloom is preserved (it's baked into the inner-viewport
  texture).
- **Backdrop-clamp (HDR gameplay) only partially works:** clamping to ~0.8 reduces the crush but the
  very brightest backdrop pixels still darken rocks, AND it dims the planet glow Roman just tuned.
  Clamp ~1.0 ≈ no fix (same as left). So clamp is a compromise, not a clean fix.
- Net: the real choice is **"clean asteroids + bright planet but no gameplay-VFX self-bloom" (LDR
  gameplay)** vs **keeping gameplay-VFX bloom at the cost of asteroid crush / a dimmer planet**.
  The asteroid-over-**bullet** case is unaffected by either (bullets live in the gameplay pass).

---
**Original investigation (2026-06-23):** root-caused; the lab above was the agreed next step.

## Symptom
Gameplay asteroid enemies render dark / "negative-multiply" smear when they move over bright things
(planets, bullets, other asteroids). Reported by Roman after the planet-glow work made backdrops
HDR-bright.

## Root cause (CONFIRMED via isolation captures)
Pure **`use_hdr_2d`** engine behavior: **opaque canvas content drawn over HDR-bright (>1) content
renders dark** in an HDR-2D viewport. Not asteroid-specific (a plain opaque `ColorRect` also dims over
a bright bar) — the asteroid is just the worst victim (large, dark base colours + black outline crush
to near-black).

### Ruled OUT (each tested in isolation, still dark):
- **Bloom/glow** — `glow_enabled=false` → still dark.
- **WorldEnvironment** — no env at all → still dark.
- **Blend mode** — tried `render_mode blend_premul_alpha` + premultiplied COLOR → no change (reverted).
- **Black outline** — `draw_outline=false` → still dark.
- **Asteroid setup props** — CanvasLayer membership, dimming CanvasModulate, dither on/off, alpha<1,
  the `_tint_ramp` colour ramp — all still dark.
- **LDR** — `use_hdr_2d=false` → renders correctly. So HDR-2D is the sole trigger.

### Why the PARALLAX/background asteroids look fine (the key insight)
`layer_stellar.gd` uses the SAME `Planets/Asteroids/Asteroid.tscn` — it is NOT a render-property
difference. It's **layering**. Combat is ONE HDR viewport (`project.godot viewport/hdr_2d=true`):
- `LayerPlanet` = CanvasLayer **-8**
- bg-asteroid stellar layers = **-6 / -5 / -4**
- ALL gameplay (player, enemies, asteroids, bullets) = layer **0** (no CanvasLayer)

So bg asteroids sit at negative layers BEHIND the bright layer-0 bullets, are dimmed by their layer's
CanvasModulate, and rarely land on top of stark HDR-bright pixels. Gameplay asteroids (layer 0) land
directly on bright bullets + the bright planet edge → crush to black.

## Candidate fixes (to compare in the lab)
1. **Two-viewport composite (Roman's #2, leaning toward this):** render the backdrop
   (`backdrop_coordinator`, all the negative layers — planets/bg-asteroids/nebula) in its OWN HDR
   SubViewport that does its own bloom, then display its output as a plain LDR **texture** behind
   gameplay. Gameplay then renders over an LDR image, never blending over HDR-bright canvas pixels.
   - Fixes asteroid-over-**planet** (the big, obvious case).
   - Does NOT fix asteroid-over-bright-**bullet** (both stay in the gameplay HDR pass). Small/fast
     overlap, far less noticeable, but non-zero.
   - Risk: real change to core combat rendering. Needs two WorldEnvironments (backdrop bloom +
     gameplay bloom), parallax scroll + planet placement must still work in the SubViewport.
2. **Cap the brightest planet glow (mitigation):** `PlanetGlowConfig.DEFAULTS` BlackHole=3.0,
   Galaxy=2.75 are the worst; pulling the brightest toward ~1.6–1.8 reduces how hard asteroids crush.
   Reversible, single-viewport, may be "good enough". Doesn't fix bullets either.

## Plan for tomorrow — DEV LAB (Roman: "see both side by side live and make the call")
Build a dev lab (`scenes/dev/asteroid_hdr_lab.tscn` + `scripts/dev/asteroid_hdr_lab.gd`, register in
`scripts/dev/dev_menu.gd`) with **two live panes side by side**, same animated scene in each:
- a bright planet (use `PlanetGlowConfig` so it's genuinely HDR-bright; let a slider pick the type /
  glow so the BlackHole/Galaxy extremes are testable), plus a few **gameplay-style asteroids drifting
  over it** (mirror `asteroid.gd`'s visual setup), plus a couple of HDR-bright **bullets** for the
  secondary case.
- **LEFT pane** = current single-HDR-viewport rendering (shows the darkening).
- **RIGHT pane** = the two-viewport composite (backdrop SubViewport → texture behind gameplay).
- Live (asteroids drift) so the artifact + fix are visible in motion.
- Controls: planet-type/glow-multiplier slider (also previews the cap mitigation), maybe a 3rd pane or
  toggle for the capped-glow option. Follow the HD lab scaffold (`HdViewportScope` / SubViewport
  480×270 / SubViewportContainer stretch_shrink=4 NEAREST, `use_hdr_2d`), like `combat_vfx_lab.gd`.

## Relevant files
- `scripts/enemies/asteroid.gd` — gameplay asteroid (Area2D); visual setup ~lines 47-117 (procgen +
  baked paths), `set_colors`, roundness, `should_dither=false`, brightening `base*(0.82/mx)`.
- `Planets/Asteroids/Asteroids.gdshader` — `render_mode blend_mix`, opaque hard-edge `n_step`, black
  `outline_color`. (Premul edit was tried + reverted; it does nothing because the rock is opaque.)
- `scripts/parallax/layer_stellar.gd` — bg asteroid spawn (same Asteroid.tscn); ~lines 85-146.
- `scripts/parallax/backdrop_coordinator.gd` + `scenes/parallax/backdrop_coordinator.tscn` — the
  backdrop; layer values live in `scenes/parallax/layers/layer_*.tscn` (planet -8, stellar -6/-5/-4).
- `scenes/main.tscn` — combat scene; backdrop + gameplay + WorldEnvironment all in the ONE root
  viewport. `project.godot` `viewport/hdr_2d=true`.
- `scripts/effects/planet_glow_config.gd` — `DEFAULTS` drives planet HDR brightness (the cap knob).

## Already shipped this session (NOT part of this TODO)
- Engine **flame** (`enemy_engine_fx.gd`) now HDR-modulates by `prod_mult("engines")` so it blooms
  (the streak trail `engine_trail_fx` was already HDR). Done, parse-clean.
