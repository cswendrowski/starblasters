# Weapons — Shared, Swappable Firing System (minor spec)

Status: **base index BUILT (2026-06-05, commit `0939e94`)** — the 8 projectile
variants + 8 baseline `weapon_*.tres` exist (see the Index sections below). The
**swappable Weapon-resource layer** (beam/lob payloads, single-sourced rate,
faction/sector multipliers, projectile-movement axis) is **still to build** (M6a.2).
Parent: `m6_modular_enemies_design_2026-06-05.md` §9.2 (first-class weapons) + §19
(distilled composer). Companion to `scripts/enemies/shoot_patterns/`, which this evolves into.

> **⚠ Known regression (from the projectile pass):** baked bullet movement was stripped,
> so `tracker` (Conductor) lost homing and `plasma_orb` (Howler / Voidmaw /
> Firecore-Cruiser) lost wobble — those enemies fire straight now. `base_bullet.gd` still
> *supports* the flags; fix options (Roman's call): (a) **boss-specific homing/wobble
> variants** so the shared standard bullets stay pure [recommended], or (b) re-enable the
> flags on the shared `.tres` [contradicts the pure-bullet intent], or (c) re-add via the
> firing-layer **projectile-movement axis** once the Weapon layer lands.

## Purpose

A **weapon** is a self-contained, swappable firing identity that **any** enemy can
carry, independent of its chassis or faction. It owns **what** is fired, in **what
shape**, and **how fast** — and can fire **more than bullets** (beams, lobbed AoE).
Factions and sector modifiers *tune* weapons; they don't define them. One shared
vocabulary, mixed-and-matched onto hulls.

## The split: timing vs content

- The **behavior** (movement pattern) owns fire **timing** — *when* the enemy fires:
  path-phase at band-Y fractions (descenders), on-hold during a loiter, sustained
  while sweeping. (Already in `enemy_core`: path-phase / `fire_on_phase` / timer.)
- The **weapon** owns fire **content** — *what* comes out and in what shape.

These are orthogonal: **any behavior × any weapon.** The behavior pulls the trigger;
the weapon decides what leaves the muzzle.

## The Weapon resource

Evolves `shoot_pattern.gd` into the single source of truth for firing. Fields:

| Field | Meaning |
|---|---|
| `fire_pattern` | the volley shape: `single` / `aimed` / `spread` / `burst` / `beam` / `lob` |
| `payload` | what each shot IS — a `BulletVariant` (.tres: visual + speed + damage), a beam spec, or a lobbed-AoE spec |
| `rate` | fire interval (min/max). **The single source** — consolidates today's interval scattered across `enemy_core` / `shoot_pattern` / wave-override (§9.2). |
| `aim` | `straight_down` / `toward_center` / `at_player` (+ lead) |
| `telegraph` | optional wind-up before firing (beams telegraph; bullets usually don't) |

## Payloads — more than bullets

- **Projectiles** (common): `single` / `aimed` / `spread` / `burst`, each firing a
  `BulletVariant`. Already exist (`single_shot`, `aimed_fire`, `spread_shot`,
  `burst_shot`).
- **Beams**: a continuous-effect line weapon (windup → fire → cooldown), aimed down
  or at the player. **Currently bespoke** (`beam_shooter` / `burner`) — fold into the
  weapon system as a `beam` fire_pattern so ANY enemy can carry a beam (§19: beams
  become a versatile, multi-faction weapon, not a one-off).
- **Lob / AoE** (optional): an arcing shot or mortar that detonates in an area
  (missile-cruiser flavor).
- **NOT weapons:** dropping mines/firecores is the **`Emitter` component's** job
  (§19), not a weapon. Rule of thumb — a *weapon* aims/fires at the player; an
  *Emitter* seeds terrain behind the enemy.

## Swappable + faction/sector-modifiable

- **Slot:** every `enemy_core` carries one weapon (the `shoot_pattern` slot). Assigned
  in the scene/roster, or overridden per-wave by the materializer
  (`director._spawn_enemy` `shoot_pattern_override`).
- **Faction:** a **flat multiplier** on the weapon — e.g. Supremacy → `rate × k`.
  Applied uniformly; the weapon stays shared, the faction just tunes it (§8/§19).
- **Sector modifiers:** `armed` / `aggressive` can upgrade the projectile or rate.
- Because faction/sector are flat multipliers + the weapon rides on the hull, **the
  composer never picks weapons** (§19) — it only chooses size + behavior + count.

## Firing guards (reused, unchanged)

A weapon firing still passes `enemy_core`'s guards: the engagement-zone gate (hold in
entry / fire in engagement / cease in departure), and not-dying / not-cycling /
on-playfield / on-target. The behavior picks the fire *moment*; the guards decide if
it actually fires; the weapon supplies the *content*.

## Authoring a new weapon (checklist)

1. Pick `fire_pattern` + `aim`.
2. Pick `payload` — a `BulletVariant` .tres (most cases), or a beam / lob spec.
3. Set `rate` (min/max).
4. (beam/lob only) set `telegraph`.
5. Assign it to an enemy via roster/scene, or add it to a chassis's allowed-weapons —
   **it's now usable by any enemy, in any faction.**

## Migration note (today → target)

- **Today:** `shoot_pattern` (single/aimed/spread/burst) + **bespoke** beams
  (`beam_shooter`/`burner`) + fire-interval scattered across three places.
- **Target:** one Weapon resource per the above; **beams become a `beam`
  fire_pattern** (any enemy can carry one); **fire-rate single-sourced** on the weapon.
- Do it as part of the M6 component/Weapon plumbing milestone (§6 M6a.2),
  **behavior-preserving first** (wrap the existing shoot_patterns), then add beam/lob
  payloads + the faction/sector multipliers.

---

## Index: Enemy Projectiles

All eight enemy "bullets" are the **same shell** — `scenes/projectiles/enemy_bullet.tscn`
— plus a **`BulletVariant`** payload (`data/bullets/*.tres`) applied at fire time
(`_apply_variant()` sets speed, damage, hitbox, sprite/anim, and any baked movement).
The per-type `.tscn` (`enemy_bullet_spread.tscn`, etc.) are **orphaned/legacy** — not
referenced anywhere; the live definitions are the variants below.

| bullet (sprite id) | sprite png | variant `.tres` | speed px/f | dmg | hitbox | baked movement |
|---|---|---|---:|---:|---|---|
| `enemy_bullet` | `enemy_bullet` | `basic` | 2 | 1 | 6×6 | — |
| `enemy_bullet_small` | `enemy_bullet_small` | `spread_pellet` | 3 | 1 | 5×5 | — |
| `enemy_bullet_large` | `enemy_bullet_large` | `heavy_slug` | 1 | 2 | 10×10 | telegraph flash, explosive impact |
| `enemy_bullet_wave` | `enemy_bullet_wave` | `plasma_orb` | 1 | 1 | 8×8 | — |
| `enemy_bullet_laser` | `enemy_laser` | `laser_bolt` | 7 | 1 | 3×8 | — |
| `enemy_bullet_cannon` | `enemy_cannon` | `burst_round` | 4 | 1 | 5×5 | short life (1.5s) |
| `enemy_bullet_diamond` | `enemy_bullet_diamond` | `tracker` | 3 | 1 | 6×6 | — |
| `enemy_bullet_tracer` | `enemy_tracer` | `aimed_sniper` | 5 | 1 | 4×6 | random start frame |

**Rockets / missiles** (separate scripts, not the shared shell):

| projectile | sprite png | script | speed px/f | dmg | notes |
|---|---|---|---:|---:|---|
| `enemy_rocket` | `rocket` | `enemy_rocket.gd` | 3 | 2 | explosive, shoot-down-able (1 HP), smoke trail + engine flare |
| `enemy_rocket_large` | `rocket_large` | `enemy_rocket.gd` | 1 | 2 | as above, larger |
| `drifting_missile` | `missile` | `base_missile.gd` | 2 (cruise) | — | drift → ignite → home; Minelayer drop |
| `drifting_missile_large` | `missile_large` | `base_missile.gd` | 1 (cruise) | — | as above, larger |

> **Pure projectiles.** Speeds are on the 2026-06 spec (above) and all baked movement
> has been removed — `diamond`'s homing and `wave`'s wobble are gone, so every bullet now
> travels straight at constant speed. Movement is the firing/behavior layer's job.
> ⚠ **Side effect:** Conductor (tracker), Howler/Voidmaw/Firecore-Cruiser (plasma) share
> these variants and have **lost their homing/wobble** — re-add it on those enemies via the
> firing/movement layer when it lands.

## Index: Enemy Weapons

### Baseline weapons — `resources/patterns/shoot/weapon_*.tres`

One straight-firing `single_shot` weapon per bullet (`fire_pattern = single`,
`aim = straight_down`). These are the **baselines** offshoot weapons (spread / aimed /
burst / beam variants) derive from. Each = `enemy_bullet.tscn` shell + the payload below.

| weapon `.tres` | payload bullet | rate (s) |
|---|---|---|
| `weapon_bullet` | `enemy_bullet` (`basic`) | 1.0–1.8 |
| `weapon_bullet_small` | `enemy_bullet_small` (`spread_pellet`) | 0.9–1.6 |
| `weapon_bullet_large` | `enemy_bullet_large` (`heavy_slug`) | 1.6–2.6 |
| `weapon_bullet_wave` | `enemy_bullet_wave` (`plasma_orb`) | 1.4–2.4 |
| `weapon_bullet_laser` | `enemy_bullet_laser` (`laser_bolt`) | 0.8–1.4 |
| `weapon_bullet_cannon` | `enemy_bullet_cannon` (`burst_round`) | 1.0–1.8 |
| `weapon_bullet_diamond` | `enemy_bullet_diamond` (`tracker`) | 1.1–1.9 |
| `weapon_bullet_tracer` | `enemy_bullet_tracer` (`aimed_sniper`) | 0.9–1.6 |

### Pattern primitives (shape building-blocks) — `resources/patterns/shoot/`

| resource | fire_pattern | aim | notes |
|---|---|---|---|
| `single_shot` | single | straight_down | base; payload set by roster/enemy |
| `aimed_fire` | aimed | at_player | leads the player |
| `pair_shot` | single ×2 | straight_down | twin muzzle |
| `spread_shot_3` | spread | straight_down | 3-fan |
| `spread_shot_7` | spread | straight_down | 7-fan |

### Bespoke beams (not yet folded in — see §19)

`beam_shooter`, `burner` — continuous beam (telegraph → fire → cooldown). Target: a
`beam` fire_pattern any enemy can carry.

> The baseline weapons use today's `single_shot` shoot-pattern (which already owns
> `bullet_scene` + `bullet_variant` + `fire_interval`). When the unified **Weapon
> resource** (top of this doc) is built, these slot in as its `single` baselines unchanged.
