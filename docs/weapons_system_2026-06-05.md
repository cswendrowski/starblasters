# Weapons — Shared, Swappable Firing System (minor spec)

Status: **design spec, not built.** Parent: `m6_modular_enemies_design_2026-06-05.md`
§9.2 (first-class weapons) + §19 (distilled composer). Companion to the existing
`scripts/enemies/shoot_patterns/` code, which this evolves into.

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
