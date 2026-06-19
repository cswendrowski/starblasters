# MultiMesh bullets — design (2026-06-19)

Efficiency item #2 of the burst-reduction plan (asteroid bake was #1). Goal: cut the per-bullet
**draw call + node + `_process`** cost in dense combat. Today every bullet is its own `Area2D` +
Sprite/AnimatedSprite + CollisionShape, with `_process` movement; dense combat peaks ~100–250 live
bullets → ~200 draws + ~200 `_process` + ~200 Area2D pairs.

## Current system (from the projectile map)

- `scripts/projectiles/base_bullet.gd` — `Area2D`, `class_name BaseBullet`. Move in `_process`
  (vector integ; homing/wobble rare). Render = a Sprite/AnimatedSprite child + HDR `self_modulate`
  bloom (NO per-bullet shader). Lifetime = time or offscreen → `queue_free`.
- **Collision** = `area_entered` + **group filter** (`target_group` "enemies"/"player"); NO physics
  layers/masks (the group check is the only gate). On hit → `take_hit`/`take_damage`, bulwark-meta
  check, `ImpactFx`, `_kill`. `bullet_wave.gd` overrides for multi-hit drill-through.
- **Data** = `BulletVariant` (.tres) + `BulletCatalog.scene_for(variant)` → one of ~12–16 indexed
  bullet SCENES (each its own texture/hitbox).
- **Spawn** = `shoot_pattern.gd::_spawn_bullet` (enemy, central) + `player.gd::fire_primary` etc.
  Parent to spawner's container / `BulletWorld.resolve` (so they survive the spawner's free + share
  coord space).
- Player bullets `z_index=-1` (under ship); enemy bullets over.
- `base_missile.gd` = EnemyBase subclass, stateful, few → **stays node-based**. Beams + `guided`
  trail bullets too.

## Architecture (target)

A central **`BulletManager`** (Node2D, resolved into the combat/bench world like spawners via
`BulletWorld`), **two instances**: player-bullets (`z=-1`) and enemy-bullets (over) — which also
splits the collision group cleanly.

- **State = struct-of-arrays** with a free-list: `pos`, `dir`, `speed`, `life`, `damage`,
  `variant_idx`, `homing/wobble` knobs, `hits` (for multi-hit). Spawn = grab a free slot (replaces
  `instantiate`+`add_child`); despawn = free the slot (replaces `queue_free`).
- **Movement = one array loop per frame** (replaces N `_process`).
- **Render = one `MultiMeshInstance2D` per bullet texture/variant**, `TRANSFORM_2D`, transform-only.
  ~12–16 draws instead of ~200. Position must be `round()`-snapped (the engine's
  `snap_2d_transforms_to_pixel` won't apply to buffer writes → clarity-rung crispness).

### The hard constraint (same as baked asteroids)
A **2D-canvas MultiMesh shader does NOT receive per-instance color / custom data / UV** — only
per-instance `TRANSFORM_2D` is reliable. Consequences:
- **Per-bullet tint is impossible in one MultiMesh** → the crit-purple `modulate` (`player.gd`)
  needs a separate render path or is dropped.
- **Per-bullet animation frame / `random_frame` is impossible** → a variant's bullets share ONE
  global frame (they already loop in lockstep visually) or render static.
- HDR bloom gain (`BULLET_HDR_GAIN`=1.8, constant) → shared MultiMesh `self_modulate`. Fine.

## Collision — the fork

- **(A) Keep Area2Ds as render-less collision proxies.** The manager owns state + movement +
  MultiMesh render, and each frame writes each bullet's position into a sprite-less, `_process`-less
  Area2D used only for `area_entered`. Hit pipeline (`take_hit`/bulwark/`bullet_wave`/`ImpactFx`)
  is **untouched**. Wins: kills ~200 draws + ~200 script `_process`. Keeps: the Area2D broadphase.
  **Safest, incremental — validate the render win first.**
- **(B) Manual broadphase in the manager.** No Area2Ds; each frame AABB-test bullet arrays vs the
  opposing group's members (uniform grid; playfield is tiny 216×270). On overlap, call the existing
  hit logic directly. Biggest win (removes Area2D entirely), but a full port of
  `_apply_enemy_hit`/`_apply_player_hit`/bulwark/multi-hit. Genuinely viable here (group-only, no
  layers to lose) — but do it as **Phase 2** after (A) proves out.

## Phasing
1. **P1**: `BulletManager` + struct-of-arrays + MultiMesh render + collision **(A)**. Migrate
   PLAYER bullets first (one/few variants), then enemy bullets. Validate FPS + look + that hits
   still register, headless + on the real renderer.
2. **P2 (optional)**: swap collision (A)→(B) for the Area2D-removal win.
3. Out of scope: missiles, beams, `guided` trail bullets — stay node-based.

## Decisions (Roman, 2026-06-19) — LOCKED
- **Collision: Phase A first** (Area2D proxies positioned by the manager, hit pipeline untouched),
  then maybe Phase B (manual broadphase) once A proves out.
- **Fidelity: keep special bullets node-based.** Only PLAIN bolts (static texture, no per-bullet
  tint) get the MultiMesh; **crit-purple bolts and animated-sprite bullets stay individual nodes**
  on the current path, keeping their tint/animation. Zero visual change on those; the bulk (the
  common chaff/blaster bolts) gets the draw-call win.

## Build steps — DEV-BENCH FIRST, then flip live (the established pattern, same as the asteroid bake)
1. `scripts/projectiles/bullet_manager.gd` (Node2D, two instances player/enemy via `BulletWorld`):
   struct-of-arrays + free-list, `spawn(variant_idx, pos, dir, dmg, ...)`, per-frame move loop
   (round-snapped), `MultiMeshInstance2D` per plain-variant texture (TRANSFORM_2D), Area2D
   collision proxies positioned each frame → existing `_on_area_entered`/`take_hit` pipeline.
2. **Routing helper**: classify a variant as PLAIN (→ manager) vs SPECIAL (crit/animated/guided/
   homing/wobble → current node path). Start with the narrowest PLAIN set, widen as validated.
3. **DEV-MENU BENCH** ("Bullet Bench"): fire plain bullets through the manager at tunable rate/count
   with a live FPS + bullet-count + draw-call readout, and a manager-path-vs-node-path A/B toggle so
   Roman validates the look + the perf win side-by-side (like the Asteroid Field Test). Plus a
   headless self-test that RUNS it (spawn → tick → assert move/render/hit) — not compile-and-hope.
   **Roman iterates + signs off here before any live wiring.**
4. **FLIP LIVE behind a flag** (mirror `AsteroidBakeCache.enabled`, default-OFF): when on, route the
   PLAIN bullets at the two spawn sites (`player.gd::fire_primary` + `shoot_pattern::_spawn_bullet`)
   to the manager; crit/animated/missiles keep the node path. A/B-able in real combat.
5. Validate in real combat (Combat Lab + the crash loop), then default-on once proven. Then optional
   Phase B (manual broadphase, drop the Area2D proxies).
