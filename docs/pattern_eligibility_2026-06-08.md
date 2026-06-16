# Pattern Eligibility — Spec

**Bespoke-enemy migration (2026-06-08):** a large pass moved most bespoke-movement enemies onto
enemy_core + the movement-pattern system, and extracted their firing into the shared weapon system.
- **Weapon system additions** (`weapon.gd`/`enemy_turret.gd`): `Aim.FORWARD` (fire along the nose),
  `FirePattern.BROADSIDE` (rolling player-facing flank ripple, salvaged from the frigate),
  `EnemyTurret.arc_gate` (blind-spot gunner that holds fire outside its cone). New `make_shoot`
  kinds: `"nose"`, `"broadside"`.
- **New movement patterns**: `pendulum` (crystal's dual-band dive-aim-fire), `strafe_run` (strafer's
  capped-turn pass), `proximity_chase` (smart mine/bomblet drift→proximity→chase), `beam_sweep`
  (beam shooter descend→rake). All in `make_movement` + `MOVEMENT_KEYS`.
- **Migrated to enemy_core**: bulwark, crystal, strafer (revived), bomber, cruiser, drone_carrier,
  mine, mine_shielded, mine_smart, beam shooter (+tracker/lock). Smart bomblet uses `proximity_chase`
  but stays bespoke for its flocking munition layer.
- **Left bespoke** (intentional): tether_mine (pulls the player), enemy_burner (paired beam),
  mine_cluster/firecore_hazard/firecore_drone/asteroids (payload timing), conductor/boss appendages,
  turret sub-units, missile_cruiser. **Frigate retired** (broadside salvaged to BROADSIDE).

**Date:** 2026-06-08
**Status:** **Phases 1 + 2 BUILT (2026-06-08).** P1: `scripts/levels/pattern_eligibility.gd` (seeded
from the roster) + `make_movement` resolves the movement key through it. **`resolve()` is now
MATRIX-AUTHORITATIVE** (changed 2026-06-08 with the pattern-set overhaul): a non-`vary` entry gets the
scene's matrix *identity* (not the roster entry's `movement`), so the eligibility tool actually controls
each enemy's movement; unmapped scenes still fall back to the entry's own `movement`. This supersedes the
original "behavior-preserving" lean — multi-entry scenes collapse to their single matrix identity, which
is what lets Roman fix assignments entirely in the tool. The DATA matrix + `make_movement` keys were
remapped to the 2026-06-08 pattern set (`straight_*` by speed, `skirmish_*`, `drift_*`, `hunt_*`,
`side_turn/dive`, `lane_hook/cut`). P2: standalone dev tool `scenes/dev/pattern_eligibility_editor.tscn` (Dev Menu
→ Pattern Eligibility) — faction filter → enemy nav → identity cycle + eligible checklist + live sprite
preview; Save → `user://tuners/pattern_eligibility.json`, Export → paste-ready DATA const (clipboard +
file) for the committed `pattern_eligibility.gd`. (Built standalone, not as a lane-viz tab, to avoid a
concurrent UI bug-hunt.) Leans locked: per-entry `"vary"`, flat-random among eligible, one shared
universal set. Phase 3 (expand eligibility + opt enemies into vary) remains.

**Editor fixes (2026-06-08, post-overhaul):** (1) the live preview now builds the LITERAL selected
key — `_set_preview` calls `make_movement({"movement": key})` WITHOUT a `scene`, since passing a scene
routes through the matrix-authoritative `resolve()` which would ignore the clicked key and return the
enemy's identity. (2) `_load_data` canonicalizes through a `KEY_REMAP` table + filters to live
`MOVEMENT_KEYS`, so a stale `user://tuners` JSON saved before the overhaul no longer surfaces retired
identities (e.g. `omni`, `bulwark_drift`, `top_dive`); retired keys remap to their replacement and
unknown keys are dropped. (3) `top_dive` RETIRED — `side_dive` (rounded side-entry turn into the lane
dive) does the same maneuver better and fits the `side_*` scheme; matrix + roster repointed.

Design below. Realizes
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
**NOTE:** This key list is illustrative; some older keys like `top_dive` were retired/renamed post-spec. The live `MOVEMENT_KEYS` in `scripts/levels/pattern_eligibility.gd` and the code are authoritative.

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
