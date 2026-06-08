# Pattern Eligibility — Spec

**Date:** 2026-06-08
**Status:** **Phases 1 + 2 BUILT (2026-06-08).** P1: `scripts/levels/pattern_eligibility.gd` (seeded
from the roster) + `make_movement` resolves the movement key through it; behavior-preserving (no entry
opts into `vary` yet). P2: standalone dev tool `scenes/dev/pattern_eligibility_editor.tscn` (Dev Menu
→ Pattern Eligibility) — faction filter → enemy nav → identity cycle + eligible checklist + live sprite
preview; Save → `user://tuners/pattern_eligibility.json`, Export → paste-ready DATA const (clipboard +
file) for the committed `pattern_eligibility.gd`. (Built standalone, not as a lane-viz tab, to avoid a
concurrent UI bug-hunt.) Leans locked: per-entry `"vary"`, flat-random among eligible, one shared
universal set. Phase 3 (expand eligibility + opt enemies into vary) remains. Design below. Realizes
the M6 vision of
behavior as a swappable axis: a central, tool-edited matrix of which **movement patterns** each
enemy may take, that the conductor draws from — instead of each roster entry hard-coding one
movement. Decisions locked with Roman (2026-06-08): per-enemy authoring view (no 40×15 grid);
**separate identity field** per enemy.

## Why

Today an enemy's movement is hard-coded per roster ENTRY (`"movement": "top_dive"` in
`enemy_roster.gd`), scattered across ~50 entries; a scene that wants variety needs multiple
entries. There's no single place to see/balance "which enemies can do which behaviors," and the
conductor can't vary an enemy's movement for freshness. This inverts it: the conductor reads a
per-enemy eligibility set and assigns from it.

## Data model

Per enemy SCENE:
- `identity`: the enemy's signature/default movement key (always its baseline — e.g. Interceptor
  = `top_dive`, Minelayer = `side_traverse`). Used unless variation is requested. Protects
  signature units from being handed an off-character pattern.
- `eligible`: the set of movement keys this enemy MAY also be assigned (includes `identity`).

Movement keys are the existing `make_movement` strings (`straight`, `top_dive`, `lane_drift`,
`lane_weave`, `loiter`, `slow_advance`, `side_traverse`, `beeline`, `omni`, `dive_return`, …).

**Source of truth = committed code, NOT runtime `user://`.** A shipped/web build has no
`user://` tuner JSON, so the conductor must read baked data. Shape (matches the tuner contract —
"every tuner has a Copy GDScript / Export button"):
- `scripts/levels/pattern_eligibility.gd` — a committed const `DATA := { scene_path: {identity, eligible[]} }`
  (preload-referenced, headless-safe, like `factions.gd`). This is what the conductor reads.
- The tool edits `user://tuners/pattern_eligibility.json` for fast iteration, and an **Export**
  button regenerates the committed const. Production never touches `user://`.

## Authoring tool — lane-visualizer tab

Per-enemy view (Roman's call — a grid is too big for the UI):
- **Faction filter** (Supremacy / Privateer / Corporate / Zealot / Universal) → enemy picker.
- Selected enemy panel: an **`identity` dropdown** + a **checklist of the ~15 movement keys**
  (the `eligible` set), and a **live preview** spawning that enemy running the highlighted
  behavior so you can watch it before committing. (The lane visualizer already previews movement
  patterns, so this slots into its existing preview.)
- **Save** writes `user://tuners/pattern_eligibility.json`; **Export** regenerates
  `scripts/levels/pattern_eligibility.gd`. Cycle enemy→enemy to configure them all.

## Runtime / conductor integration

Recommended (minimally disruptive, backward-compatible):
- The roster entry's existing `"movement"` key becomes the enemy's **identity** (no entry rewrite
  needed). `make_movement` is unchanged — it still builds a pattern from a key.
- `eligible` defaults to `{identity}` until the tool expands it, so **behavior is unchanged on day
  one** (every enemy keeps doing exactly what it does now).
- When an entry opts into variety (a `"vary": true` key, or a global vary-chance), the conductor
  picks a **weighted-random eligible movement** for that spawn instead of the identity; otherwise
  it uses the identity. Fallback to identity (then `straight`) if eligibility is missing.
- This keeps the existing multi-entry-per-scene patterns valid and ships zero behavior change
  until you deliberately expand eligibility + enable variety.

Future consolidation (optional, later): drop hard-coded `"movement"` from entries entirely and let
eligibility fully drive selection — bigger roster refactor, deferred.

## Migration / seeding (behavior-preserving)

Seed `pattern_eligibility.gd` from the CURRENT roster: each scene's existing movement key(s) →
its `eligible` set; the primary/most-common → `identity`. Verify waves unchanged (identity ==
today's movement, vary off). Then expand in the tool.

## Phasing

1. **Data + plumbing (no behavior change):** add `pattern_eligibility.gd` seeded from current
   entries; wire the conductor to resolve movement via identity (+ off-by-default vary). Verify
   reorg + a wave-composition smoke is unchanged.
2. **Tool tab:** faction filter + enemy picker + identity dropdown + behavior checklist + live
   preview; `user://` save + Export-to-committed.
3. **Expand:** open the tool, broaden eligibility, enable variety where wanted (e.g. assign
   `dive_return` to the rocket/missile droppers — the immediate motivating case).

## Open decisions for Roman

- **Variety trigger:** per-entry `"vary": true`, or a global "X% of spawns vary," or both?
- **Selection weighting:** flat-random among eligible, or per-key weights in the matrix?
- **Universal enemies:** do they share one eligibility set across factions, or per-faction sets?
