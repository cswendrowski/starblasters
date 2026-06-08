# Enemy Shield Unification — Spec

**Date:** 2026-06-08
**Status:** ✅ IMPLEMENTED (2026-06-08). Foundation (`ShieldComponent` CHARGE/POOL modes +
smart-bomb interaction) was built by the lead session; the spawn-path rewiring + per-enemy
migrations below are landed. Deviations from the spec, both deliberate:
- **enemy_bomber_wing.gd left bespoke** — it is UNWIRED dead code (preserved for a future
  wing-event overhaul that will re-fit it), so migrating it is churn that'll be redone. The
  base shield *vars* (`_shield_mat`/`_shield_ring`/`SHIELD_SHADER`) are retained solely so it
  still compiles; nothing in the live path uses them.
- **enemy_base simple shield made INERT, not deleted** — the consumption branch, `_ready`
  setup, and ring-helper methods are removed; the `max_shield`/`shield` fields + ring vars
  remain inert (spec allows "gone *or inert*") because the dead bomber-wing references them.
Verified: `tools/test_shield_component.gd` (absorb/deplete/regen pipeline) +
`tools/test_bomb_shields.gd` (CHARGE killed, POOL sapper survives iff pool ≥ bomb dmg) both PASS;
38/38 enemy scenes instantiate; combat boots clean.

## Why

There are **four** distinct enemy-shield implementations today, and the data-driven shield sources are
split across two of them:

| Shield source | Currently feeds | File:line |
|---|---|---|
| Roster `"shielded"` tag | enemy_base **simple** `max_shield` | `enemy_roster.gd:1141-1145` → `director.gd:555-557` |
| Sector modifier `"shielded"` | enemy_base **simple** `max_shield` | `director.gd:639-652` |
| Corporate faction overlay | **ShieldComponent** (runtime `_components`) | `factions.gd:152-167,204-226` → `director.gd:575-578` |
| Sapper | **simple** `max_shield` + bespoke steal | `enemy_sapper.gd:27-88` |
| Bulwark, bomber-wing | **bespoke** copy-pasted regen shields | `bulwark.gd:14-141`, `enemy_bomber_wing.gd:31-147` |
| Shielded mine | bespoke per-hit absorber | `mine_shielded.gd:13-24` |
| Boss Aegis | bespoke pylon-gated invuln (NOT a charge shield) | `boss_aegis.gd:244-257` |

Consequences: a corporate enemy in a `"shielded"`-sector level stacks **both** a simple shield AND a
ShieldComponent; the smart bomb has to special-case two systems; and four near-identical regen-shield
implementations drift independently.

## Target: one system — `ShieldComponent`, with modes

`ShieldComponent` (`scripts/enemies/components/shield_component.gd`) is the single shared shield. Its
own docstring already declared it the "HP-unify vehicle" meant to replace the bespoke regen shields —
this spec realizes that. **The lead session has extended it** with the modes below (already on disk):

### Modes (built)
- **`mode = CHARGE`** (default): per-HIT charge shield. Each hit consumes one charge regardless of
  damage magnitude (preserves today's feel). `capacity` charges.
  - **Regen:** `regen_interval > 0` regenerates one charge every interval (corporate / bulwark /
    bomber). **`regen_interval <= 0` ⇒ NO regen** — use this for chaff (roster `"shielded"` tag) and
    sector-modifier shields, per the design call "chaff shields don't regenerate."
- **`mode = POOL`** (the sapper): a banked **damage pool** (`_pool: float`). Absorbs a damage
  *amount* (not a per-hit pip), can exceed `capacity` via `bank(amount)`, never regenerates. This is
  the only mode that can "tank 18 damage" — exactly what the sapper needs.
  - `bank(amount: float)` adds to the pool (the sapper's steal calls this).
  - `on_hit` absorbs `min(damage, _pool)`, returns the integer remainder to hull.

Backward-compat: default `mode = CHARGE`, `regen_interval = 6.0` — the existing corporate usage
(`capacity 1`, regen 6.0) is unchanged.

## Migration work (combat session)

### 1. Spawn-path rewiring → attach a ShieldComponent instead of the simple shield
The simple `max_shield`/`shield` path in `enemy_base.gd` should be retired in favor of attaching a
`ShieldComponent`. Two producer sites set it today; both should attach a CHARGE/no-regen component:

- **Roster `"shielded"` tag** — `director.gd:555-557` currently `enemy.max_shield = wave.shield_charges`.
  Instead, append a `ShieldComponent.new()` with `mode = CHARGE`, `capacity = wave.shield_charges`,
  `regen_interval = 0` (no regen) to `enemy.components` BEFORE `add_child` (so `_init_components` dups
  it). (No live ENTRY uses `"shielded"` today, so this path is forward-looking — but wire it.)
- **Sector modifier `"shielded"`** — `director.gd:639-652` currently sets/scales `max_shield`. Instead,
  find an existing CHARGE ShieldComponent on the enemy and `+1` its `capacity` (or append one with
  `capacity 1`, `regen_interval 0`). This also fixes the stacking bug: if the enemy already has a
  corporate ShieldComponent, the sector mod boosts THAT instead of adding a parallel simple shield.

### 2. Retire the simple shield in `enemy_base.gd`
Once both producers attach components, remove (or hard-deprecate) the simple-shield branch:
- `enemy_base.gd:64` `max_shield`, `:162` `shield`, the consumption branch `:315-328`, and the ring
  helpers `_setup_shield_ring`/`_set_shield_alpha`/`_pulse_shield_hit` `:725-764`. The component owns
  its own ring, so these become dead once nothing sets `max_shield`.
- **Smart bomb note:** `smart_bomb_shockwave.gd` currently also zeros the simple `e.shield`. That line
  is harmless to keep during migration and becomes a no-op once the simple shield is gone — the lead
  session will drop it in the same change that lands here, or leave it as a harmless guard.

### 3. Migrate the bespoke regen shields onto ShieldComponent (CHARGE + regen)
Drop the hand-rolled `_shield`/ring/regen in each and attach a component in `_ready` (BEFORE
`super._ready()` so it's in `components` for dup):
- **Bulwark** (`bulwark.gd:14-141`): `ShieldComponent.new()` `capacity = 4`, `regen_interval = 6.0`.
- **Bomber-wing** (`enemy_bomber_wing.gd:31-147`): `capacity = 2`, `regen_interval = 6.0`.
- **Shielded mine** (`mine_shielded.gd:13-24`): `capacity = 2`, `regen_interval = 0` (no regen).
- Keep each enemy's `take_hit` override ONLY for behavior that isn't the shield itself; the shield
  absorption now comes from the component pipeline (`_components_hit`).

### 4. The sapper — POOL mode (the standout)
The sapper keeps its **unique interaction**; only its shield *storage* unifies. In
`enemy_sapper.gd`:
- `_ready`: replace `max_shield = 2` with a `ShieldComponent.new()` `mode = POOL`, `capacity = 2`
  (initial pool), attached to `components`.
- Steal (`_tick_drain:85-87`): instead of `shield = min(shield+1, max_shield)`, call
  `pool_component.bank(1.0)` per stolen charge — so stolen shield **accumulates past 2** into the
  damage pool. (Keep the `player.shield -= 1` + regen-suppression as-is.)
- `take_hit` redirect (`:64-75`): keep "shooting a draining sapper damages the player's shield" for
  **bullet** hits. BUT it must NOT redirect the **smart bomb** (a panic AoE shouldn't drain the
  player). The smart bomb bypasses `take_hit` for POOL-shield enemies (see "Smart-bomb interaction"),
  so the redirect simply never sees the bomb — no change needed on the sapper's redirect for this,
  but verify no other AoE relies on `take_hit` against a draining sapper.

### 5. Boss Aegis — leave bespoke
Aegis's pylon-gated invulnerability is not a charge shield; it stays as-is (exempt from this
unification). Other bosses have no shield.

## Smart-bomb interaction (built, lead session)

`smart_bomb_shockwave.gd` already ignores shields by stripping `_charges` on runtime `_components`
(the earlier crystal fix). With unification it gains POOL awareness:
- **CHARGE components** → stripped (`_charges = 0`) → the wave ignores them (kills the enemy).
- **POOL component (sapper)** → NOT stripped. The wave applies its damage to the pool directly via
  `on_hit` and deals any remainder straight to hull, **bypassing the enemy's `take_hit`** so the
  sapper's "redirect to player" never fires for the bomb. Net: the sapper **survives iff its banked
  pool ≥ the bomb damage (18 at Mk.1)** — exactly the requested behavior.

## Acceptance
- Exactly one shield class (`ShieldComponent`) absorbs hits; `enemy_base` simple `max_shield`/`shield`
  is gone (or inert).
- Roster `"shielded"`, sector-modifier `"shielded"`, and corporate faction all produce a
  `ShieldComponent`; sector-mod boosts an existing component instead of stacking a parallel shield.
- Chaff/sector shields don't regenerate; corporate/bulwark/bomber do.
- A smart bomb kills all CHARGE-shielded enemies (ignore-shields), and the sapper survives iff its
  stolen pool ≥ the bomb damage.
- Boss Aegis unchanged.
