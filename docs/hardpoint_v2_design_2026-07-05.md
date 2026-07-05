# Hardpoint v2 — Payload × Delivery × Trigger (2026-07-05)

**Status:** proposed (Roman greenlit examining the streamline; this is the plan). Follow-on to the
2026-07-02/03 hardpoint unification (`hardpoint_unification_design_2026-07-02.md`), which merged
mount + emitter into one `MountSpec`/`MountComponent`.

## Why

The v1 `MountSpec.Kind` (`GUN / TURRET / LAUNCHER / BEAM / ENTITY`) **conflates three independent
things**. Roman's observations (2026-07-04) each point at that conflation:
- "We don't need a *launcher* if a base gun can shoot a missile payload."
- "*Beams* should be a payload that can be fired."
- "*Rings* should be a type of hardpoint, not a separate thing."
- "Adding a *turret* just visually changes how it tracks/fires and adds a sprite — is it its own thing,
  or a toggle?"

Pull the axes apart and every one of those redundancies disappears.

## The model — three orthogonal axes

A hardpoint = **Payload** (what it fires) × **Delivery** (how it's presented) × **Trigger** (when).

| Axis | Options |
|---|---|
| **Payload** | `Bullet` (BulletVariant) · `Projectile` (missile/rocket scene) · `Entity` (mine/drone/enemy scene) · `Beam` (beam config) |
| **Delivery** | `Direct` (from the marker) · `Turret` (a tracking node + sprite that fires the payload) · `Ring` (orbit-hold, release on death/trigger) |
| **Trigger** | `Cadence` · `Start` · `Death` · `PathPhase` · `OnPhase` |

The universal firing settings (aim incl. Back/Left/Right, spread, `volleys`/`volley_gap`, `burst`,
`deviation`, `max_fires`, `no_inertia`, `payload_delay_ms`, marker mode incl. In/Out) apply to **every**
combination — so e.g. a turret-delivered gun gets deviation + volleys for free.

### How v1 kinds collapse
| v1 Kind | v2 = Payload × Delivery |
|---|---|
| GUN | Bullet × Direct |
| LAUNCHER | Projectile × Direct — **kind removed** |
| ENTITY | Entity × Direct, trigger Start/Death |
| TURRET | (any payload) × **Turret** — turret becomes a delivery **toggle**, not a kind |
| BEAM | **Beam** × Direct/Turret — beam becomes a **payload** |
| (bloom / cluster mine rings) | (any payload) × **Ring** — orbit becomes a delivery |

## Feasibility & cost per axis

- **Payload: Projectile & Beam** — LOW–MEDIUM. The component already spawns scenes (the ENTITY/launcher
  path). Merging LAUNCHER into "Bullet-or-Projectile-payload on a Direct gun" is mostly consolidating
  two existing fire paths + letting the bench offer projectile payloads on a gun. **Beam** is the
  wrinkle: it's *continuous* (an FSM), not a discrete shot — "firing" it = activating a `BeamEmitter`.
  It fits as a payload but with an on/off lifecycle rather than count/volleys.
- **Delivery: Turret** — MEDIUM–HIGH, the real work. `EnemyTurret` today fires its *own* `bullet_variant`
  with a narrow config. It must be reworked to **deliver the hardpoint's payload** and honour the shared
  firing settings. This is also the fix for "turrets need the rest of the firing settings."
- **Delivery: Ring** — MEDIUM. Generalise `OrbitComponent` (already touched for the bloom) into a
  delivery: hold `count` payloads in a ring, release on death/trigger. Folds the bloom + cluster/gravity
  mines onto one path.

## Phasing (each independently shippable + verified)

- **Phase A — Payload collapse.** GUN fires Bullet OR Projectile (payload type picks the spawn path);
  retire LAUNCHER (keep the roster/bench "launcher" key as an alias → Projectile×Direct). Add Beam as a
  payload (activate a BeamEmitter on fire). Lowest risk; removes a kind.
  **Launcher→gun collapse SHIPPED 2026-07-05** (`73aa69a2`): `MountComponent._fire` selects the path by
  `spec.payload_scene != null` instead of `kind == LAUNCHER`, so a gun carrying a projectile payload just
  works (the bench already offered projectile payloads on guns; they previously misfired down the bullet
  path). LAUNCHER kept as a zero-churn alias. **Remaining:** beam-as-payload — beams are a continuous
  `BeamEmitter` FSM node (routed by the builder), not a discrete shot, so folding them into the gun fire
  path is a deliberate follow-on, not done here.
- **Phase B — Turret as delivery.** Rework `EnemyTurret` to fire the hardpoint's payload + all shared
  firing settings; turret becomes a `delivery = turret` toggle (with its rotation/arc/sprite config).
  Retire the TURRET kind (alias → Bullet×Turret). The meaty phase.
- **Phase C — Ring as delivery.** `OrbitComponent` becomes `delivery = ring`; the bench ring editor
  authors it as a hardpoint delivery; bloom + cluster/gravity mines migrate.

## Migration / back-compat
- Keep the v1 roster keys/values parsing: a `"kind": "launcher"` maps to Projectile×Direct, `"turret"`
  to Bullet×Turret, `"beam"` to Beam×Direct. No forced roster rewrite (same approach that made v1
  zero-churn). The bench editor gains Payload + Delivery selectors; the `kind` dropdown is superseded.
- The **Hive** stays bespoke (its respawn-budget loop isn't a trigger); it already reads an ENTITY
  hardpoint for config (2026-07-04). A future "budget/maintain-N-alive" trigger could fold it in.

## Risks
- Touches three live node types (`EnemyTurret`, `BeamEmitter`, `OrbitComponent`) — phase + verify each
  (compile, hazard/turret/beam boot, per-enemy smoke) before the next.
- Turret aim model (atan2 + arc clamp) vs the shared `Aim` enum — the turret delivery keeps its own
  tracking; `aim` selects the target (at-player / forward / etc.), the turret rotates toward it.
- Beam's continuous lifecycle doesn't map to count/volleys/burst — gate those off for beam payloads.
