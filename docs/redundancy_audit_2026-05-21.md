# Redundancy Audit — 2026-05-21

**Status: PARTIALLY SHIPPED 2026-05-25.** Heavy_cannon.gd + bullet_fat.tscn + bullet_twin.tscn deleted; Drone Bits → Shield Drones rename done (#51). **Still outstanding** (confirmed on disk 2026-05-25): shadow-shader cluster + capture_shadow_* drivers, parallax_silhouette/parallax_tint/starstuff shaders, NEBULA_SHADER/TINT_SHADER dead preloads, `drone_bits.tres`/`drone_swarm.tres` stale defaults, `burst_shot.tres` authoring, `SmokeTrail` factory consolidation — tracked in `TODO.md` §Visual / VFX and §Dev tools.

Audit of weapons, projectiles, shaders, particle effects, and explosion assets
for cases where multiple instances exist for the same concept. Goal: identify
where a single source-of-truth should replace multiple parallel paths, and
flag anything dev-tool-only that should be retired.

---

## Weapons (parts)

Weapons live in two parallel layers:

1. **Behaviour script** under `scripts/parts/*.gd` (one file per weapon).
2. **Designer-tunable resource** under `resources/weapons/*.tres`.

These are NOT redundant. `PartCatalog._make_by_name(name, slot)` consults the
.tres if present and falls back to instantiating the .gd directly — the
.tres is the Weapon Editor's source of truth, the .gd is the code-defaults
fallback. This is the intended design.

| Weapon | .gd script | .tres resource | Status |
|---|---|---|---|
| Basic Blaster (energy) | `basic_blaster_cannon.gd` | `energy_blaster.tres` | OK |
| Heavy Blaster | `heavy_blaster.gd` | `heavy_blaster.tres` | OK |
| Machinegun | `machinegun_cannon.gd` | `machinegun.tres` | OK |
| Wave Gun | `wave_gun_cannon.gd` | `wave_gun.tres` | OK |
| Laser Beam | `laser_beam_cannon.gd` | `laser_beam.tres` | OK |
| Spread Cannon | `spread_cannon.gd` | `spread_cannon.tres` | OK |
| Rocket Pod | `rocket_pod_cannon.gd` | `rocket_pod.tres` | OK |
| Seeking Missile | `seeking_missile_cannon.gd` | `seeking_missile.tres` | OK |
| Smart Bomb | `smart_bomb.gd` | `smart_bomb.tres` | OK |
| Hyper Mode | `hyper_mode.gd` | `hyper_mode.tres` | OK |
| Phase Shift | `phase_shift.gd` | `phase_shift.tres` | OK |
| Particle Beam | `particle_beam.gd` | `particle_beam.tres` | OK |
| Side Pods | `side_pods.gd` | `side_pods.tres` | OK |
| Drone Bits (→ Shield Drones) | `drone_bits.gd` | `drone_bits.tres` | OK (.tres may be stale after redesign) |
| Drone Swarm | `drone_swarm.gd` | `drone_swarm.tres` | OK (.tres may be stale after autonomy redesign) |

**Action items:**
- `drone_bits.tres` and `drone_swarm.tres` should be re-saved against the
  current .gd defaults so the Weapon Editor doesn't surface stale values.
  No code change needed; open in editor, re-save.
- Otherwise this layer is healthy.

---

## Projectile scenes

| Scene | Used by | Status |
|---|---|---|
| `bullet.tscn` | Energy Blaster, Spread Cannon, fallback for many | Primary player bullet |
| `bullet_heavy.tscn` | Heavy Blaster | OK |
| `bullet_minigun.tscn` | Machinegun | OK |
| `bullet_wave.tscn` | Wave Gun | OK |
| `bullet_laser.tscn` | Laser Beam | OK |
| `bullet_fat.tscn` | NOT referenced in `scripts/parts/`; only seen in patterns? | **Potentially stale — investigate.** |
| `bullet_tracer.tscn` | NOT referenced in `scripts/parts/`; tracer preview? | **Likely Weapon Editor preview only.** |
| `bullet_twin.tscn` | NOT referenced in `scripts/parts/`; legacy? | **Likely stale.** |
| `enemy_bullet.tscn` | Enemy shoot patterns | OK |
| `player_rocket.tscn` | Rocket Pod | OK |
| `player_seeking_missile.tscn` | Seeking Missile | OK |
| `drifting_missile.tscn` | Enemy ordnance (Sentinel, Interceptor) | OK |

**Action items:**
- `bullet_fat.tscn`, `bullet_tracer.tscn`, `bullet_twin.tscn` — grep showed
  no `parts/` references. Confirm they aren't used by enemy patterns, dev
  tools, or signal events; if truly unused, retire.

---

## Enemy shoot patterns

`scripts/enemies/shoot_patterns/*.gd` (script) + `resources/patterns/shoot/*.tres`
(designer instances). Same layered model as weapons — script defines behavior,
.tres is a tunable instance.

| Pattern script | Resource(s) | Status |
|---|---|---|
| `single_shot.gd` | `single_shot.tres` | OK |
| `aimed_fire.gd` | `aimed_fire.tres` | OK |
| `spread_shot.gd` | `spread_shot_3.tres`, `spread_shot_7.tres` | OK — two .tres for variant spread counts is intentional |
| `burst_shot.gd` | *(no .tres)* | OK — code-defaults only, no designer instance authored yet |
| `shoot_pattern.gd` | n/a | Base class |

**Action items:** none. Pattern layer is healthy. If `burst_shot` needs
designer tuning, author a .tres alongside.

---

## Explosion FX

| Asset | Path | Role |
|---|---|---|
| Behavior script | `scripts/effects/explosion.gd` | Attached to `scenes/effects/explosion.tscn` — handles the visual + particles + light cast |
| Static spawner | `scripts/effects/explosion_fx.gd` | `ExplosionFx.play(pos, scale)` + `ExplosionFx.burst(pos, count, jitter, stagger)` |

Two files, but **not redundant** — one is the scene's runtime, the other is
the call-site helper. Same pattern as `HitFlashFx`, `ImpactFx`, etc.

**Action items:** none.

---

## Shadow shaders ⚠ MULTIPLE STALE

This is the biggest cluster of redundancy in the codebase.

| Shader | Used by | Status |
|---|---|---|
| `oblique_shadow.gdshader` | `scripts/shadow_fx.gd` (production path — every ship + large projectile shadow) | **Keep — primary** |
| `masked_shadow.gdshader` | Only `tools/capture_shadow_iterate.gd`, `tools/capture_shadow_mask.gd` | Capture-only prototype |
| `topdown_shadow_outofbounds.gdshader` | Only `tools/capture_shadow_a.gd`, `tools/capture_shadow_ray.gd`, `tools/capture_shadow_test.gd` | Capture-only prototype |
| `drop_shadow_canvas_group.gdshader` | Only `tools/capture_shadow_b.gd` | Capture-only prototype |

**Action items:**
- Retire `masked_shadow.gdshader`, `topdown_shadow_outofbounds.gdshader`,
  `drop_shadow_canvas_group.gdshader` along with their `tools/capture_shadow_*`
  drivers. These were prototypes during the shadow-research pass and
  oblique-shadow won. They have no production callers.
- Keep `oblique_shadow.gdshader` (canonical).

---

## Parallax shaders

| Shader | Used by | Status |
|---|---|---|
| `nebula.gdshader` | `galaxy_backdrop.gd` (V1, far + near passes), `galaxy_backdrop_v2.gd` (Nebula layer) | **Keep — primary FBM nebula** |
| `nebula2.gdshader` | `galaxy_backdrop_v3.gd` (Far/Mid/Near `_spawn_nebula_in`) | **Keep — domain-warped variant** |
| `starfield.gdshader` | `galaxy_backdrop.gd` (StarsFoundation1 + 2 in V1) | **Keep — V1 procedural starfield** |
| `starstuff.gdshader` | Legacy. Toggled by V1's `use_starstuff` @export (default false). | **Stale — remove if `use_starstuff` flag stays disabled.** |
| `parallax_silhouette.gdshader` | V2's silhouette pass was removed earlier this week; shader file still on disk. `grep` shows no `.gd` references. | **Retire — file exists but unused.** |
| `parallax_tint.gdshader` | V3 used this through the CanvasGroup wrapper which was REMOVED today (2026-05-21). `TINT_SHADER` const in V3 is still preloaded but no longer referenced. | **Retire — file + the V3 const both safe to remove.** |

**Action items:**
- Remove `parallax_silhouette.gdshader` and its .uid.
- Remove `parallax_tint.gdshader` and its .uid; delete the `TINT_SHADER`
  preload in `galaxy_backdrop_v3.gd`.
- Remove `starstuff.gdshader` if Cody confirms `use_starstuff` is not coming
  back. Currently a legacy fallback.

---

## Other shaders (single-owner, all production)

| Shader | Owner | Status |
|---|---|---|
| `pixelated_burn.gdshader` | `scripts/burn_fx.gd` | OK |
| `particle_trail.gdshader` | Not preloaded anywhere — possibly assigned via scene materials. Investigate. |
| `sci_fi_shield.gdshader` | Player + bulwark + bomber + mine_shielded | OK |
| `scene_transition.gdshader` | `scripts/scene_transition.gd` | OK |
| `hologram.gdshader` | `scripts/enemy_codex.gd` | OK |
| `hit_flash.gdshader` | `hit_flash_fx.gd` | OK |
| `bloom.gdshader` | Not preloaded — investigate. |
| `pulse_glow.gdshader` | `galaxy_backdrop.gd` (BlackHole pulse glow) | OK |
| `damage_overlay.gdshader` | `enemy_base.gd` | OK |
| `torch_fire.gdshader` | `engine_torch.gd` | OK |
| `black_hole.gdshader` | Likely `scenes/hazards/black_hole.tscn` material | OK |
| `billow_smoke.gdshader` | `damage_smoke_trail.gd` | OK |

**Action items:**
- Confirm `particle_trail.gdshader` and `bloom.gdshader` are still
  referenced by scenes; if not, retire.

---

## Particle effects

`scripts/effects/*.gd` — static helpers (call-site singletons) for FX surfaces.
No duplicates found. Each helper owns one concept (impact, muzzle, hit-flash,
explosion, shield SFX, weapon SFX, engine torch, damage smoke trail,
missile smoke trail). The newly-added `missile_smoke_trail.gd` is a tuned
sibling of `damage_smoke_trail.gd`, which Cobalt explicitly asked for
("create a copy of the player damage smoke effect, recoloured"). They share
~90% of code; consolidating them behind a `SmokeTrail.new(palette)` factory
would be cleaner but isn't urgent.

**Action items:** none urgent. Future consolidation candidate noted.

---

## Dev-menu vs main-game forks

`scripts/dev/*` was audited for cases where a dev tool spawns its own copy
of a gameplay element instead of using the live one. Findings:

| Tool | Notes |
|---|---|
| Hangar | Now uses live `galaxy_backdrop.gd` + live `player.tscn` + live `PartCatalog._make_by_name`. Single source. ✓ |
| Parallax Tuner | Spawns V1/V2/V3 backdrop scripts directly — same scripts the live game uses. ✓ |
| Ship Sizer / Shipyard | Reads enemy `.tscn` scenes via `enemy_manifest.gd` (hardcoded const list — necessary for web-export DirAccess trap). ✓ |
| Asteroid Lab | Uses `Planets/Asteroids/Asteroid.tscn` (same addon scene as gameplay + parallax band asteroids). ✓ |
| Movement Lab / Wave Editor / Pattern Editor / Weapon Editor | Operate on `.tres` resources and live scripts. ✓ |
| Feature Showcase | Borrows real player, enemy, boss scenes. Hardcodes a couple of demo seeds but otherwise uses gameplay assets. ✓ |

**Action items:** none. Dev tooling is well-disciplined here.

---

## Summary — recommended deletions

If approved, this audit recommends retiring:

**Shaders (with .uid):**
- `graphics/masked_shadow.gdshader`
- `graphics/topdown_shadow_outofbounds.gdshader`
- `graphics/drop_shadow_canvas_group.gdshader`
- `graphics/parallax_silhouette.gdshader`
- `graphics/parallax_tint.gdshader`
- `graphics/starstuff.gdshader` (pending Cody's confirmation)

**Capture scripts driven by retired shaders:**
- `tools/capture_shadow_a.gd` / `.ps1`
- `tools/capture_shadow_b.gd`
- `tools/capture_shadow_test.gd` / `.ps1`
- `tools/capture_shadow_ray.gd` / `.ps1`
- `tools/capture_shadow_mask.gd` / `.ps1`
- `tools/capture_shadow_iterate.gd` / `.ps1`

**Projectile scenes (pending confirmation):**
- `scenes/projectiles/bullet_fat.tscn`
- `scenes/projectiles/bullet_tracer.tscn`
- `scenes/projectiles/bullet_twin.tscn`

**Code refs to clean up:**
- `TINT_SHADER` preload const + comment block in `scripts/parallax/galaxy_backdrop_v3.gd`
- `NEBULA_SHADER` preload const in `galaxy_backdrop_v3.gd` (V3 uses NEBULA2; the V1 shader preload is dead in V3 specifically)

**Consolidation candidates (no rush):**
- `damage_smoke_trail.gd` + `missile_smoke_trail.gd` share ~90% of code. Could
  be unified behind a `SmokeTrail.new(palette)` factory once we add more
  smoke-trail emitters.

No "main game uses one weapon, dev menu uses another" duplicates found —
that risk is contained by the `PartCatalog` + `.tres` pipeline being the
single source for both surfaces.
