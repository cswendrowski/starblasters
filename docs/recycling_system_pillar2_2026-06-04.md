# Unified Recycling System — Pillar 2: Central Recycle Controller — Handoff Spec

**Date:** 2026-06-04
**Status:** Scoped, not built. Pillar 1 + the recycle-delay bug fix shipped (commit `8f99dd0`); this doc is the handoff for the remaining work.

## Context: where this fits

Roman wants a unified **Recycling System** with two pillars that share one idea —
*both* the missile cruiser and the normal-enemy fly-back are "fake mid-depth by
living in world space and tinting/scaling down." Agreed direction: **both,
unified**.

- **Pillar 1 — mid-depth presentation. DONE (commit `8f99dd0`).** The missile
  cruiser's faked-depth recipe was extracted into
  `scripts/effects/mid_depth_presentation.gd` (static helpers
  `add_above_backdrop` / `apply_body_tint` / `apply_glow` /
  `read_mid_layer_grade`). The depth-tint shader moved to
  `scripts/effects/depth_tint.gdshader`. The cruiser, `main.gd`
  `_spawn_missile_cruiser`, and `boss_base.add_world_node_above_backdrop` all
  consume it.
- **Recycle-delay bug — DONE (same commit).** The narrow, contained fix:
  `enemy_base._offscreen_cleanup_check()`'s `CYCLE_BOTTOM` branch now also fires
  `_on_offscreen()` on a full **side** exit when `allow_side_exit` is set.
- **Pillar 2 — central recycle controller. THIS DOC.** Not started.
- **Prerequisite — RecycleTuner dev scene.** Not started. See "Build it in this
  order" below.

## TL;DR

Today there is no single owner of "an enemy left the screen → when and how does
it come back." The behavior is spread across `enemy_base` (edge detection) and
`enemy_core` (the fly-back tween), the *timing* is a mix of a random hold + a
fixed tween + however long each movement pattern happens to take to reach the
bottom, and bespoke `NONE`-mode enemies don't recycle at all. The contained bug
fix already shipped stops the worst symptom (the ~14 s sideways drift), but the
deeper goal — **consistent, centrally-owned recycle timing every enemy uses, with
the fly-back ghost reusing Pillar 1's mid-depth look** — is still open.

Effort: **~1–2 focused sessions of implementation + a playtest-heavy tail.** The
risk is concentrated here because it touches `enemy_base` + `enemy_core`, which
every enemy inherits — the regression surface is the whole roster, and only
playtesting (not parse/headless) can clear it.

## How it works today

### The edge detection — `enemy_base.gd`

`_offscreen_cleanup_check()` runs each frame and branches on the per-enemy
`offscreen_mode` (`OffscreenMode` enum: `CYCLE_BOTTOM`, `FREE_ANY_EDGE`,
`FREE_OPPOSITE_SIDE`, `NONE`):

- `CYCLE_BOTTOM` (the default for pattern enemies) → bottom exit, **plus** a
  side exit when `allow_side_exit` (added by the bug fix), calls
  `_on_offscreen()`.
- `FREE_ANY_EDGE` / `FREE_OPPOSITE_SIDE` → calls `_leave()` (queue_free, no
  `died` signal).
- `NONE` → nothing; the enemy owns its own lifecycle (bosses, mines, asteroids,
  bomblets, strafers, beam-shooters, firecore cruiser, bomber wing).

`_on_offscreen()` is a hook; the base default just calls `_leave()`.
`recycle_passes` (`-1` unlimited / `0` leave / `N` count) and `is_recycling()`
(default `false`) also live on the base.

### The fly-back — `enemy_core.gd`

`enemy_core` overrides `_on_offscreen()` → `_start_cycle()`, which is the only
actual "recycle" implementation:

1. Decrement/check `recycle_passes` (`0` → `_leave()` instead).
2. Stop shooting, drop monitorable/monitoring, hide.
3. **Random pre-cycle hold** `randf_range(0.4, 0.9)` s.
4. Reposition to a random X in the playfield band at the bottom
   (`screensize.y + 12`).
5. Shrink to **45 %** scale, tint **`Color(0.75, 0.85, 1.0, 0.55)`**, face up.
6. **Fixed 1.8 s linear tween** flying up to `y = -20`.
7. Restore scale/modulate, re-arm shooting, re-run the pattern's `on_start`.

`is_recycling()` returns `_cycling` so the director's wave-advance gate can skip
a lone recycler.

### The director gates — `director.gd`

`_live_combatants_present(ignore_recycling)` counts live, non-hazard `enemies`.
The **wave-advance** gate passes `ignore_recycling = true` (a lone recycler
doesn't stall the next wave); the **level-clear** gate
(`_check_clear` → `level_cleared`) stays strict (`false`) so a level never ends
mid-recycle. The `fleeing` sector modifier sets `recycle_passes = 0`.

## The problems Pillar 2 solves

1. **No central timing budget.** Time from "left the screen" to "back in play"
   is `(pattern's time to reach the bottom)` + `random hold 0.4–0.9 s` +
   `fixed 1.8 s tween`. The first term varies wildly by pattern, so there is no
   consistent, tunable "recycle budget" anywhere. The shipped bug fix narrowed
   *one* pathological case; it did not make timing uniform.

2. **Two scattered owners.** Edge detection lives in `enemy_base`, the fly-back
   in `enemy_core`. Adding a third behavior (e.g. a background-depth recycler)
   means touching both or reimplementing.

3. **The fly-back hardcodes its own depth look.** `_start_cycle()` open-codes
   `scale * 0.45` + `Color(0.75, 0.85, 1.0, 0.55)`. This is the *same fake-mid-
   depth idea* Pillar 1 now owns — it should call `MidDepthPresentation` so the
   ghost-pass and the cruiser read consistently and tune from one place.

4. **`NONE`-mode enemies can't recycle.** Bespoke enemies each reimplement (or
   skip) lifecycle. There's no opt-in path to the shared recycle behavior.

## Proposed design

A single **recycle controller** that owns offscreen→recycle decisioning and
timing, callable by any enemy regardless of base class.

### Shape (one viable approach — confirm with Roman before building)

- **A `RecycleController` helper** (mirror the `scripts/effects/` static-helper
  convention, preload-based — *not* `class_name`; a global `class_name` did not
  resolve in headless `-s` runs during Pillar 1, so preload consts are the
  house pattern). It owns:
  - **Edge-aware trigger:** given an enemy + its `offscreen_mode` +
    `allow_side_exit`, decide recycle vs free vs ignore on the *actual* exit
    edge — generalizing the bug fix's bottom-or-side logic into one place
    instead of the per-mode `match` in `_offscreen_cleanup_check`.
  - **One timing budget:** a single tunable "offscreen → back-in-play seconds"
    (replacing the `0.4–0.9` random hold + `1.8` fixed tween with values driven
    from the budget) so the *visible* recycle duration is consistent no matter
    which edge/pattern the enemy left from.
  - **The fly-back itself:** reposition + tween, calling
    `MidDepthPresentation.apply_body_tint` / scale for the ghost look instead of
    the hardcoded constants.
- **`enemy_base` delegates** its `_offscreen_cleanup_check` decision to the
  controller; `enemy_core._start_cycle` becomes a thin call into the controller.
- **`NONE`-mode bespoke enemies** can opt in by calling the controller directly.

### Must preserve (don't regress)

- `is_recycling()` must stay accurate for the whole fly-back window — the
  director's wave-advance gate (`ignore_recycling = true`) depends on it, and the
  level-clear gate must still count a recycler as live.
- `recycle_passes` semantics (`-1` / `0` / `N`) and the `fleeing` modifier
  (`recycle_passes = 0`) must keep working.
- Shooting/monitorable/monitoring must drop during the cycle and restore after
  (current `_start_cycle` does this).
- The re-entry must re-run the movement pattern's `on_start` (patterns hold
  phase state).
- **No top-edge trigger** for `CYCLE_BOTTOM`: patterns legitimately spawn and
  retreat near `y = 0` (e.g. `advance_retreat` retreats to `y = 24`, `top_dive`
  spawns above the screen). The shipped fix watches bottom + sides only — keep
  that invariant.

## Build it in this order

1. **RecycleTuner dev scene first.** Per CLAUDE.md's human-iterated rule, the
   recycle budget / fly-back scale / tint / hold are 3+ knobs Roman will want to
   fiddle with live. Scaffold a tuner (follow `scripts/dev/ui_designer.gd` —
   JSON persist to `user://tuners/<name>.json`, **Copy-GDScript button
   mandatory**) so Pillar 2's timing is tuned by Roman, not by agent
   edit-capture-guess. Add it to `scripts/dev_menu.gd`.
2. **Then the controller**, tuned against the scene above, landing on top of the
   already-shipped Pillar 1 + bug fix.

## Risks / gotchas

- **Regression surface = the entire enemy roster.** Parse-check and a headless
  boot will *not* catch recycle-feel regressions; this needs a multi-pattern
  playtest pass (Skirmisher, Cutter variants, Interceptor/top-dive, plus a few
  `CYCLE_BOTTOM` chaff).
- **Headless `class_name` trap (learned in Pillar 1):** a freshly-added global
  `class_name` does not resolve in a headless `-s` run (stale
  `global_script_class_cache.cfg`). Use preload consts for the controller, as
  Pillar 1 does.
- **Composition wrinkle:** the fly-back ghost is a *transient disguise* on an
  `Area2D` enemy; the cruiser is a *permanent* plain `Node2D`. They share the
  Pillar 1 *visual* helper cleanly but **not** lifecycle — the controller must
  not assume a permanent host.
- **Bespoke `NONE`-mode enemies** (`enemy_strafer`, `enemy_beam_shooter`,
  `enemy_firecore_cruiser`, `enemy_bomber_wing`, bosses, mines) each manage their
  own offscreen logic; opting them into the controller is *optional* scope — do
  it deliberately, not wholesale, to avoid changing boss/mine behavior.

## File map

| File | Role |
|---|---|
| `scripts/enemies/enemy_base.gd` | `_offscreen_cleanup_check`, `_on_offscreen`, `_leave`, `is_recycling`, `recycle_passes`, `OffscreenMode` |
| `scripts/enemy_core.gd` | `_start_cycle` (the only fly-back today), `is_recycling` override |
| `scripts/levels/director.gd` | `_live_combatants_present(ignore_recycling)`, `_check_clear`/`level_cleared`, `fleeing` → `recycle_passes = 0` |
| `scripts/effects/mid_depth_presentation.gd` | Pillar 1 helper the fly-back should reuse for its ghost look |
| `scripts/dev/ui_designer.gd` | Reference pattern for the RecycleTuner |
| `scripts/dev_menu.gd` | Register the new tuner button |
