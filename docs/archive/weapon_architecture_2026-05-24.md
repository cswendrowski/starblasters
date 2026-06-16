**⚠️ ARCHIVED 2026-06-15 — historical snapshot, not current design.** Superseded by: docs/weapon_data_centralization_2026-06-11.md.
Kept for design history; do not cite as the live spec.

# Weapons & Player Projectile Architecture Review

**Status: MOSTLY SHIPPED 2026-05-25.** Core refactor (WeaponPart base, SuperPart base, snapshot helper, Heavy Blaster `weapon_style` bug fix, dead-code cleanup) landed in `2083c59` + `cd8c939` + cleanup commits. Remaining outstanding items tracked in `TODO.md` §Weapons / Architecture (bullet script relocation, snapshot asymmetries, `fire_offset` per Part, Heavy cooldown lerp regression).

## 1. Current state inventory

### Weapon Parts (CANNON / HARDPOINT_WING / DEVICE_BAY_1)

| Part | File | Slot | LoC | Duplicated logic | Bespoke logic |
|---|---|---|---|---|---|
| Basic Blaster | `scripts/parts/basic_blaster_cannon.gd` | CANNON | 49 | `_prev_*` snapshot, `bullet_scene/cooldown/bullet_damage` triple, `GunCooldown.wait_time`, `+(mark-1)*per_mark` | sfx_kind `blaster_small`, `weapon_style "energy"` |
| Heavy Blaster | `scripts/parts/heavy_blaster.gd` | CANNON | 41 | Same as Basic Blaster | sfx_kind `blaster_large` (**no `weapon_style`!** — bug) |
| Machinegun | `scripts/parts/machinegun_cannon.gd` | CANNON | 64 | Same triple + Run-snapshot ammo seed | `weapon_style "machinegun"`, ammo |
| Rotary Laser | `scripts/parts/rotary_laser_cannon.gd` | CANNON | 71 | Same triple + Run-snapshot ammo seed | `weapon_style "rotary_laser"`, ammo, ammo_recharge_rate |
| Wave Gun | `scripts/parts/wave_gun_cannon.gd` | CANNON | 64 | Same triple | Multiplicative Mk scaling, override `effective_damage` |
| Laser Beam | `scripts/parts/laser_beam_cannon.gd` | CANNON | 51 | Same triple | `fire_sfx_kind = ""` (silent-fallback marker) |
| Spread Cannon | `scripts/parts/spread_cannon.gd` | CANNON | 89 | Same triple | `bullet_spread_count/_degrees`, count-based Mk scaling |
| Rocket Pod | `scripts/parts/rocket_pod_cannon.gd` | HARDPOINT_WING | 67 | Mirror triple on `secondary_*` + Run ammo seed | `secondary_homing=false`, `pod_count=1` reset |
| Seeking Missile | `scripts/parts/seeking_missile_cannon.gd` | HARDPOINT_WING | 70 | Same as Rocket Pod (line-for-line nearly) | `secondary_homing=true`, `pod_count=1` reset |
| Side Pods | `scripts/parts/side_pods.gd` | HARDPOINT_WING | 83 | Mirror triple on `secondary_*` | pod_count/halfspan scaling, `set_secondary_ammo(-1,-1)` |
| Particle Beam | `scripts/parts/particle_beam.gd` | HARDPOINT_WING | 54 | Common `set_secondary_ammo(-1,-1)` | `secondary_mode="beam"`, beam_dps/_width |
| Drone Bits | `scripts/parts/drone_bits.gd` | HARDPOINT_WING | 75 | None of the standard triple | Spawns orbiting `shield_drone.tscn` — **name misleads, not a weapon** |
| Smart Bomb | `scripts/parts/smart_bomb.gd` | DEVICE_BAY_1 | 100 | super_part/charges plumbing | screen-clear, damage burst, ExplosionFx |
| Hyper Mode | `scripts/parts/hyper_mode.gd` | DEVICE_BAY_1 | 77 | super_part/charges plumbing | `_hyper_t`, `_invuln_t` |
| Phase Shift | `scripts/parts/phase_shift.gd` | DEVICE_BAY_1 | 80 | super_part/charges plumbing | invuln + bullet cancel |
| Drone Swarm | `scripts/parts/drone_swarm.gd` | DEVICE_BAY_1 | 102 | super_part/charges plumbing | spawn N drones, scheduled cleanup |

### Player projectiles

| Scene | Script | Extends | Notes |
|---|---|---|---|
| bullet.tscn / bullet_fat / bullet_twin / bullet_laser / bullet_rotary_laser | `scripts/bullet.gd` | `base_bullet.gd` | **5 scenes, same script, different sprites** |
| bullet_heavy.tscn | `scripts/projectiles/bullet_heavy.gd` | `scripts/bullet.gd` | +12 lines for frame animation |
| bullet_wave.tscn | `scripts/bullet_wave.gd` | `base_bullet.gd` | Multi-hit override |
| bullet_minigun.tscn / bullet_tracer.tscn | `scenes/projectiles/bullet_minigun.gd` | `base_bullet.gd` | Random sprite frame on spawn |
| player_rocket.tscn / player_seeking_missile.tscn | `scripts/projectiles/base_missile.gd` | `enemy_base.gd` | dumb-fire vs seeker, target_group="enemies" |

**Player projectile code is already 90% unified.** Duplication lives in `.tscn` sprite variants, not scripts.

## 2. Duplication patterns

### Pattern A — "Cannon triple plumbing" (7 cannons × 7 lines)

Every CANNON Part does this verbatim:
```gdscript
_prev_bullet_scene = ship.bullet_scene
_prev_cooldown = ship.cooldown
_prev_damage = ship.bullet_damage
if bullet_scene != null:
    ship.bullet_scene = bullet_scene
ship.cooldown = base_cooldown
ship.bullet_damage = base_damage + (int(mark) - 1) * dmg_per_mark
if ship.has_node("GunCooldown"):
    ship.get_node("GunCooldown").wait_time = ship.cooldown
```
…and the symmetric unapply.

### Pattern B — "Secondary triple plumbing"

`rocket_pod` + `seeking_missile` differ only in `secondary_homing` and `pod_count=1`. Run-ammo snapshot block is **byte-for-byte identical**. Side Pods does the same shape with `set_secondary_ammo(-1,-1)`.

### Pattern C — "Super charge plumbing" (4 supers × 8 lines)

```gdscript
ship.super_part = self
ship.max_super_charges = base_charges + (int(mark) - 1) * charges_per_mark
ship.super_charges = ship.max_super_charges
if ship.has_signal("super_charges_changed"):
    ship.super_charges_changed.emit(ship.super_charges, ship.max_super_charges)
```

### Pattern D — "Camera trauma + Explosion VFX boilerplate"

Every super loads `explosion_fx.gd`, calls `play()` / `burst()`, then digs through `tree.get_current_scene().get_node("Camera2D").add_trauma(...)`. Four copies of the same lookup chain.

### Pattern E — "Mark-additive damage formula"

`Part.effective_damage()` already implements `base + (mark-1)*per_mark` generically. **Every cannon then recomputes the same expression inline** instead of calling `effective_damage(mark)`. Wave/Spread override the editor readout but recompute in apply too.

### Pattern F — "Silent fallback" risks (CLAUDE.md violation)

- `laser_beam_cannon.gd:36` sets `ship.fire_sfx_kind = ""` to fall through to legacy ShootSound.
- `heavy_blaster.gd:20-32` **never sets `weapon_style`** — equipping Heavy after Machinegun leaves `weapon_style = "machinegun"`, routing Heavy through MG audio loop. **Real bug.**

## 3. Proposed class hierarchy

```
Part (Resource)                                    [existing]
│   - display_name, description, slot_type, mark
│   - effective_damage(at_mark), apply(ship), unapply(ship)
│
├── WeaponPart (Resource, abstract)                [NEW]
│   │   - bullet_scene, base_damage, dmg_per_mark, base_cooldown
│   │   - _prev_* snapshot dict, _apply_common, _unapply_common
│   │
│   ├── PrimaryWeapon (Resource, abstract)         [NEW]
│   │   │   - weapon_style, fire_sfx_kind
│   │   │   - writes ship.bullet_scene / cooldown / bullet_damage
│   │   │
│   │   ├── BasicBlaster, HeavyBlaster, LaserBeam  [thin: defaults only]
│   │   ├── MeteredPrimary (abstract)              [NEW — MG, Rotary]
│   │   │   - base_ammo, ammo_recharge_rate
│   │   │   - Run.ammo seed/persist
│   │   │
│   │   └── SpreadPrimary, WavePrimary             [thin: scaling overrides]
│   │
│   └── SecondaryWeapon (Resource, abstract)       [NEW]
│       │   - writes ship.secondary_*
│       │   - homing, pod_count, ammo
│       │
│       ├── BulletSecondary (Rocket, SeekingMissile, SidePods)
│       └── BeamSecondary    (ParticleBeam — different mode)
│
├── SuperPart (Resource, abstract)                 [NEW]
│   │   - base_charges, charges_per_mark
│   │   - apply/unapply standardized: writes super_part / charges
│   │   - activate(ship) — subclass overrides
│   │   - _camera_trauma(ship, amount), _flash_at(ship, scale)   [shared]
│   │
│   └── SmartBomb, HyperMode, PhaseShift, DroneSwarm
│
├── DroneSupport (Resource)                        [NEW — drone_bits doesn't fit weapon]
│   └── ShieldDrones
│
└── Engine/Wing/Tail/Shield parts                  [unchanged]
```

### What `WeaponPart.apply` looks like (sketch)

Basic Blaster shrinks from 49 lines to ~8:
```gdscript
func apply(ship) -> void:
    super.apply(ship)                  # plumb the triple + snapshot
    _set_style(ship, "energy")         # base helper handles _prev_style
    _set_sfx(ship, "blaster_small")    # base helper handles _prev_sfx_kind
```

Heavy Blaster becomes data-only and **the silent-fallback bug from Pattern F disappears** because `_set_style` always snapshots+writes.

## 4. Core helpers / mixin proposals

1. **`PartSnapshot` (inner Dict helper on Part)** — `_snapshot(ship, ["bullet_scene","cooldown","bullet_damage"])` + `_restore(ship)`. Kills `_prev_*` per-field bookkeeping.

2. **`SuperFxHelper`** — `play_burst(ship, kind: int)` with kinds `TIGHT/RING/SCATTER/PUFF`. Replaces the four hand-rolled `ExplosionFx.play + burst + camera.add_trauma` blocks.

3. **`AmmoPersist`** — `seed_from_run(ship, "ammo", base)` + `clear(ship)`. Used by MG, Rotary, Rocket, Missile.

4. **No `WeaponStats` Resource needed yet.** Mk-scaling is already `base + (mark-1) * per_mark`. The fix is: weapon `apply()` should *call* `effective_damage(mark)` instead of re-inlining the formula. Wave's multiplicative and Spread's count-curve already override it, so they'd Just Work.

5. **`WeaponPart.fire_offset: Vector2`** — Part declares its muzzle offset, `player.fire_primary` reads it. So wing-mounted vs nose-mounted weapons don't all spawn at the same hardcoded `(0,-10)`.

## 5. Player projectile architecture

**The work the report-prompt asks about is mostly done.** `base_bullet.gd` is already a sound single-pipeline base. Subclasses are 10-30 line overrides doing only what they uniquely need.

**Remaining cleanup:**

- `scripts/bullet.gd` + `scripts/bullet_wave.gd` live at root of `scripts/` while siblings live in `scripts/projectiles/`. **Move them**, update `.tscn` paths.
- `scripts/weapons/heavy_cannon.gd` is a `Node2D` with its own input polling — **dead/legacy code** that predates the Part system. Confirm with grep before removing.
- `bullet_fat.tscn` + `bullet_twin.tscn` may be unused; audit before deleting.

**Don't variant-driven the .tscn library** — the .tscn-per-sprite pattern IS the variant system. Weapons swap `bullet_scene` PackedScene refs. This is the right shape.

## 6. Migration plan

1. **POC: convert Heavy Blaster** (smallest cannon, actual bug — missing `weapon_style` snapshot). Rewrite as `extends WeaponPart` with declarative fields. Verify equip → fire → un-equip → fire restores prior weapon. Validates the snapshot helper covers Pattern F.

2. **Convert vanilla cannons**: Basic Blaster, Laser Beam, Wave Gun. Wave Gun's override stays — only its damage formula differs.

3. **Add `MeteredPrimary`**, convert Machinegun + Rotary Laser. Pull `Run.ammo` seed code into the helper.

4. **Convert secondaries**: SeekingMissile + RocketPod first (near-identical pair). SidePods next. ParticleBeam last as `BeamSecondary`.

5. **Build `SuperPart` base**, convert SmartBomb / Hyper / Phase / DroneSwarm.

6. **Move bullet scripts to `scripts/projectiles/`**, update `.tscn` refs, run `parse_check`.

7. **Touch nothing in `player.gd::fire_primary/secondary`** during migration. Contract (Part writes to ship fields, player reads them) is sound.

Each step testable in isolation via dev menu equip + fire. `.tres` Weapon Editor resources should keep deserializing because field names don't change.

## 7. What stays bespoke

- **Particle Beam** — `secondary_mode="beam"` with hit-scan pipeline. Keep as `BeamSecondary`, sibling to `BulletSecondary`. Don't unify "fires bullets" and "draws a hit-scan line."
- **Smart Bomb's screen-clear** — the `for enemy in group: take_hit` loop is genuinely SmartBomb-specific.
- **Hyper Mode's `_hyper_t` integration** — player.gd checks `_hyper_t > 0` in fire_primary. Player-side coupling, not Part-side.
- **Drone Swarm's spawn/timer/cleanup** — instantiating + scheduling free is unique. Activation VFX is shared; spawn loop isn't.
- **Wave gun multiplicative scaling** — already overridden via `effective_damage`. Keep override; stop re-inlining in `apply`.
- **Drone Bits** — it's not a weapon. Either rename `drone_bits.gd → shield_drones.gd` or move to `DroneSupport` Part family. **Naming mismatch is itself a finding.**

## 8. Open questions for designer

1. **Mk scaling formulas** — happy with `base + (mark-1)*per_mark` as universal default, overrides only for Wave/Spread? Or tunable Resource the editor exposes?
2. **Heavy Blaster missing `weapon_style`** — intentional fallback or bug? Almost certainly bug; comment says "blaster_large" SFX.
3. **`weapon_style` strings** — Should become an enum/StringName since several Parts forget to reset it (silent fallback violation per CLAUDE.md).
4. **Drone Bits naming** — keep misleading filename, or rename to match display name?
5. **`scripts/weapons/heavy_cannon.gd`** — dead code, can delete?
6. **`bullet_fat.tscn`, `bullet_twin.tscn`** — currently equipped by any Part? Candidates for deletion?
