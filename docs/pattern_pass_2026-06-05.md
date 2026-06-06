# Lane / Pattern Pass — Visualizer Feedback (Roman, 2026-06-05)

Intake of Roman's visualizer pattern review. Reshapes the movement-pattern library (=
the behavior layer, m6 §13) BEFORE enemy conversions land on it. Each fix is verifiable
in the Lane Visualizer. Parent: `m6_modular_enemies_design_2026-06-05.md` §4/§13.

## Cross-cutting themes (the load-bearing ones)

1. **Terminology → align to the behavior taxonomy.** Pattern/movement names are
   inconsistent. Make pattern names = the §13 behavior names (Diver / Weaver / Shifter /
   Holder / Skirmisher / Crosser / Hunter / …), with speed/size as variants, not new
   names. (Renames in §"Terminology".)

2. **Lane-confinement + row-coordination (the big one).** Lateral-moving patterns
   (weave, step, drifter, s_curve) must **start and end anchored in a lane** and, in a
   ROW, **coordinate so they don't overlap a neighbor**. This is a CONDUCTOR upgrade:
   - edge-lane exclusion (weave/step rows skip lanes 0 and/or 6),
   - coordinated lateral motion (a stepping/drifting wall shifts together, not into each
     other; a lane-changer checks the target lane is free),
   - height stagger for side-entry rows (crossers at different Y so they don't run over
     each other).
   Today lanes are spawn-anchors only; a pattern that CHANGES lane collides. Fixing this
   is the meatiest piece — call it **lane-aware movement / row choreography**.

3. **Smoothing / inertia.** Several patterns stop/turn mechanically; add accel/decel
   easing (loiter in/out, advance_retreat endpoints) so motion reads as momentum.

## Per-pattern resolutions

| Pattern | Feedback | Resolution |
|---|---|---|
| **lane Straight** | OK | keep (= **Diver**) |
| **lane Weave** | OK single; in a row the outer lanes (0,6) don't get full weave width | **exclude lanes 0 & 6** for weave rows (conductor); keep full-width weave (= **Weaver**) |
| **+ Weave Narrow** | NEW variant | small-amplitude weave that **stays within its own lane** while wobbling down (= Weaver-narrow) |
| **lane Hook** | looks identical to straight — intent? | **OPEN — define.** Proposed: **Shifter** = descend, then a one-way COMMIT to an adjacent lane and hold (lane-commitment). Currently shift is unconfigured so it reads as straight. |
| **lane Step** | OK single; row → lanes merge | row behavior = **exclude one edge lane, then the whole wall STEPS left/right so the GAP suddenly shifts** (react-to-the-new-gap). Coordinated row step, any empty lane. (= Shifter/Stepper) |
| **straight_down** | OK | **rename → `straight_fast`** (straight but faster Diver) |
| **drifter** | less rigid; drift lane→lane, coordinated to avoid overlap | rework into a **lane-to-lane drift** (gentle one-lane slide), lane-aware (target lane free) (= Drifter) |
| **fast (dart)** | OK | **rename → `straight_reflex`** (fastest straight, reaction-test) |
| **s_curve** | confine to lane; start+end in a lane, curve is the transition; avoid overlap | **lane-confined lane-change curve** (anchored start lane → curve → target lane), lane-aware. Folds toward Shifter/Weaver. |
| **loiter** | needs in/out smoothing (accel/decel); hold-state jiggle like bombers; add low/mid/high | smooth enter/exit easing + a hold-jiggle; **3 variants (low/mid/high)** with different hold-Y in the fire band (= **Holder** low/mid/high) |
| **slow_advance** | it's side-to-side loiter, not an advance | rework → a **much slower lane-straight for large enemies**, drop the side-slide (= slow Diver / **Anchor** for big hulls) |
| **advance_retreat** | inertia/smoothing on up/down endpoints; exit = accelerate up & off | ease the advance/retreat endpoints; **exit = accelerate to top of screen and off** (= **Skirmisher**) |
| **top_dive** | just a curved lane-straight | **CULL** (subsumed by Diver) unless it should be more — OPEN confirm |
| **beeline** | OK | keep (= **Hunter**) |
| **side_traverse** | starts mid-screen (wrong); should enter just off-screen L/R, move in, exit; rows need height stagger | **enter from just off-screen on the spawn side**, traverse, exit; **row spawns at staggered Y** (= **Crosser**) |

## Terminology (rename map → behavior taxonomy)
`straight` → **Diver** (lane STRAIGHT) · `straight_down` → `straight_fast` · `fast_straight`
(dart) → `straight_reflex` · `s_curve` → folds into **Weaver/Shifter** · WEAVE → **Weaver**
(+narrow) · HOOK/STEP → **Shifter** variants · `loiter` → **Holder** (low/mid/high) ·
`slow_advance` → **Anchor** (slow Diver, big hulls) · `advance_retreat` → **Skirmisher** ·
`top_dive` → cull · `beeline` → **Hunter** · `side_traverse` → **Crosser**.
(Final names pending the terminology decision below.)

## Decisions (Roman left the calls to Claude, 2026-06-05 → recommendations adopted)
1. ✅ **HOOK = Shifter** — descend → one-way commit to an adjacent lane → hold.
2. ✅ **Terminology** — adopt the behavior-taxonomy names as the pattern names (one vocab).
3. ✅ **top_dive** — CULL (curved straight; interceptor → Diver/Slider).
4. ✅ **Row choreography** — in scope, sequenced as P2 (after the per-pattern P1 fixes).

## Progress
- ✅ **side_traverse → Crosser off-screen entry** (666c6bf). Awaiting Roman's eyeball.
- ✅ **loiter → Holder** (958882f): hold-jiggle (bob+sway), true ease-IN, low/mid/high
  hold band via `loiter_{low,mid,high}` roster keys; base `loiter` keeps the deep hold
  (existing users untouched). Visualizer shows all three. test_loiter_holder.gd PASS.
  Awaiting Roman's eyeball.
- ✅ **advance_retreat → Skirmisher** (12a3610): eased endpoints (accel out / decel into
  each turn, floored so the snap lands) + EXIT = accelerate up & off (requests
  FREE_ANY_EDGE so the up-leaver despawns). Awaiting eyeball.
- ✅ **Round 2 (Roman 06-06, 561534f):** Holder jiggle RANDOMIZED per instance (phase +
  freq jitter) → a row desyncs instead of lockstep (each enemy_core enemy already gets a
  duplicated _pattern, so randf() in on_start is independent). Skirmisher: slower
  (100/130), hold no longer a dead stop (jiggle), and the EXIT hitch fixed — final cycle is
  HOLD → PREP (wind-up jiggle) → EXIT accelerating up FROM REST (was retreat→snap→re-accel,
  a velocity discontinuity). Both holds use absolute repositioning (anchor+offset) = no drift.
- ✅ **slow_advance → Anchor** (12a3610): dropped the sine x-drift; slow STRAIGHT descent
  for big hulls (roster key uses deep hold_y = pure descent; on-screen hold_y still
  station-keeps for a patrol). Awaiting eyeball.
- ⚠️ **top_dive cull — RECLASSIFIED as a conversion, not a P1 tweak.** top_dive.gd is the
  embedded movement Resource in enemy_dart.tscn + enemy_bomb_drone.tscn AND used by
  levels_v2:481 + the interceptor roster key. "Cull" is the taxonomy call (it's a curved
  Diver/Slider); the file-level fold (repoint those call sites to a Slider) belongs with
  the enemy conversions (M6a.5+). Don't delete the file in isolation.
- ⬜ P1 remaining: weave_narrow (lane_path shape/variant — solo-testable); weave-row
  edge-lane exclusion (really P2 conductor work); terminology renames (cosmetic — batched
  last so visualizer labels + roster keys move together).

## Phased plan (after the opens)
- **P1 — terminology + cheap fixes:** renames; weave-row edge-lane exclusion; weave_narrow;
  loiter smoothing + jiggle + low/mid/high; advance_retreat easing + exit; slow_advance →
  slow Diver; cull top_dive; side_traverse off-screen entry. (Mostly per-pattern, testable
  solo in the visualizer.)
- **P2 — lane-aware movement / row choreography (conductor):** lane reservation for
  lane-CHANGING patterns; coordinated row step (gap-shift); lane-change target-free check;
  crosser height stagger. (The meatier conductor work; theme #2.)
- **P3 — HOOK/Shifter + s_curve as lane-confined lane-changers** (depends on P2's
  lane-awareness).
