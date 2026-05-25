# Weapon Mk Progression Audit — 2026-05-25

Inventory of every player-equippable weapon Part and the exact Mk.1 → Mk.9 curve each one drives. Source: `_mk_knobs()` (and bespoke `_apply_visuals` / `activate` for non-knob scaling) from each script under `scripts/parts/`.

Counts: **Primary 7**, **Secondary 5**, **Super 4** (16 weapons total).

## TL;DR — recurring gaps

- **Cooldown is flat on most weapons.** Only Heavy Blaster scales `cooldown` (0.28 → 0.18). Basic Blaster, Auto Laser, Machinegun, Rotary Laser, Spread Cannon, all secondaries, and Wave Gun (partially) leave cadence at its base value across all 9 Mks. Mk.9 "feels" like Mk.1 with bigger numbers, not a fundamentally faster gun.
- **Ammo caps don't scale on metered weapons.** Machinegun (1000), Rotary Laser (300), Rocket Pod (60), Seeking Missile (60), Smart Bomb starting charges all flat per Mk *except* charges (which scale on supers only). Metered primaries punish high-Mk uptime even though damage tripled.
- **Several weapons get only damage scaling.** Basic Blaster, Auto Laser, Machinegun, Rotary Laser, Rocket Pod, Seeking Missile add nothing but `damage += dmg_per_mark` per Mk. Mk.9 is a numeric upgrade, not a mechanical one.

---

## Primary (CANNON)

### Energy Blaster (`basic_blaster_cannon.gd`)
- Standard issue blue energy cannon. Infinite ammo, 2 damage, 0.22s cooldown — the reference balance weapon. Inherits the default `_mk_knobs()` from `primary_weapon.gd` (linear damage only).
- Mk 1: damage 2, cooldown 0.22s
- Mk 1-9 damage 2→18 linear (`base + 2 × (mk-1)`), cooldown flat 0.22s.

#### Recommended Changes
- Reference weapon — appropriate that it scales simply. Consider a small cooldown drop (0.22 → 0.18) by Mk.9 so even the baseline cannon "feels faster" late-run.
- No other changes; this is the yardstick.

### Heavy Blaster (`heavy_blaster.gd`)
- Slow-firing high-damage energy cannon. The ONLY primary that scales both damage and cooldown. Mk also drives `bullet_damage` 4 → 28 and `cooldown` 0.28 → 0.18 (~35% faster cadence at top tier).
- Mk 1: damage 4, cooldown 0.28s
- Mk 9: damage 28, cooldown 0.18s
- Mk 1-9 damage 4→28 linear, cooldown 0.28→0.18 linear.

#### Recommended Changes
- This is the model other weapons should follow. No changes recommended.

### Auto Laser (`laser_beam_cannon.gd`, formerly LaserBeam)
- Alternating left/right tandem energy bolts at moderate cadence (`fire_tandem_alternating=true`). Inherits default `_mk_knobs()` from primary_weapon.gd.
- Mk 1: damage 3, cooldown 0.18s
- Mk 1-9 damage 3→27 linear (`base + 3 × (mk-1)`), cooldown flat 0.18s.
- Visual: `use_rotary_laser_muzzle=true` constant across Mks (no visual tell that the weapon is upgraded).

#### Recommended Changes
- Mk 1-9 add only damage; consider widening tandem spacing or adding a third bolt slot at Mk.5 / Mk.8 so the visual signature changes.
- Cooldown stays flat — consider 0.18 → 0.13 over Mk 1-9 to differentiate from Heavy Blaster's pace shift.

### Machinegun Cannon (`machinegun_cannon.gd`)
- High rate of fire, limited ammo (1000 rounds). 1 damage, 0.10s cooldown. Refill at outposts. Inherits default `_mk_knobs()` (damage only).
- Mk 1: damage 1, cooldown 0.10s, ammo cap 1000
- Mk 1-9 damage 1→9 linear, cooldown flat 0.10s, ammo cap flat 1000.

#### Recommended Changes
- Ammo cap doesn't scale — at Mk.9 you're burning 1000 rounds in 100 seconds for 9 DPS. Consider +100 ammo per Mk (or +recharge_rate of 1-2/s past Mk.5) so sustained fights stay viable.
- No cooldown scaling — Machinegun should *feel* like cadence ramps. Drop 0.10 → 0.06 over the curve, or add `dmg_per_mark = 2` so the per-bullet trade-off makes ammo loss worth it.
- 9 damage at top tier loses to Heavy Blaster (28) per shot and per second. Either lower the dmg gap or buff Machinegun damage curve.

### Rotary Laser (`rotary_laser_cannon.gd`)
- Minigun-style energy weapon: 0.05s cooldown (20 shots/s), 300 ammo base, recharges 10/s when not firing. Inherits default `_mk_knobs()` (damage only).
- Mk 1: damage 1, cooldown 0.05s, ammo cap 300, recharge 10/s
- Mk 1-9 damage 1→9 linear; cooldown, ammo cap, and recharge all flat.

#### Recommended Changes
- Same damage curve as Machinegun (1 → 9) for a weapon advertised as "blistering rate of fire" — feels weak at high Mks vs. Heavy Blaster's 28.
- Consider scaling `ammo_recharge_rate` (10 → 18/s) so the weapon spins up faster late-run, matching the minigun fantasy.
- Or shorten the spin-down/cooldown formula (0.05 → 0.033) to push the burst-window higher.

### Wave Gun (`wave_gun_cannon.gd`)
- Wide piercing energy wave; slow + weak at Mk.1, fattens to a fast multi-hit pulse at Mk.9. The showcase Mk-knob weapon — scales damage, cooldown, speed, pierce, AND bullet sprite.
- Mk 1: damage 1, cooldown 0.85s, speed 600, pierce 1, small sprite
- Mk 5: damage 3, cooldown 0.55s, speed 900, pierce 4, large sprite (sprite switch happens here)
- Mk 9: damage 5, cooldown 0.35s, speed 1200, pierce 4 (capped), large sprite

#### Recommended Changes
- Top-end damage (5) is the lowest Mk.9 in the primary pool by a wide margin. The pierce + cadence story sells it, but a Mk.9 wave that does 5 damage per hit ×4 pierce = 20 "effective" still trails Heavy Blaster's 28×single-target. Consider damage 1→7 or 1→8.
- Pierce caps at Mk.5 — Mks 6-9 only get speed + damage + cadence. Consider raising the cap to 6 by Mk.9 to keep upgrade tempo.

### Spread Cannon (`spread_cannon.gd`)
- Fans bullets in a 30° forward arc. Mk alternates +1 bullet / +1 damage so every upgrade meaningfully shifts coverage or per-shot bite.
- Mk 1: 3 bullets × 1 damage = 3 total, cooldown 0.30s, spread 30°
- Mk 2: 4 bullets × 1 damage = 4
- Mk 3: 4 bullets × 2 damage = 8
- Mk 4: 5 bullets × 2 damage = 10
- Mk 5: 5 bullets × 3 damage = 15
- Mk 6: 6 bullets × 3 damage = 18
- Mk 7: 6 bullets × 4 damage = 24
- Mk 8: 7 bullets × 4 damage = 28
- Mk 9: 7 bullets × 5 damage = 35
- Cooldown + spread degrees flat across all Mks.

#### Recommended Changes
- Solid progression — clear alternating mechanical/numeric upgrade. No changes recommended on the count/damage axis.
- Consider widening the spread by 2° per Mk past Mk.5 (30° → 38° at Mk.9) so high-Mk Spread differentiates from Mk.1 visually + tactically (covers wider waves).

---

## Secondary (HARDPOINT_WING)

### Rocket Pod (`rocket_pod_cannon.gd`)
- Dumb-fire rockets, secondary slot. Fast straight-line, contact-detonate, slow cadence. 60 ammo, no homing. Inherits default secondary `_mk_knobs()` (damage only).
- Mk 1: damage 2, cooldown 0.55s, 60 ammo
- Mk 1-9 damage 2→18 linear (`base + 2 × (mk-1)`), cooldown flat 0.55s, ammo flat 60.

#### Recommended Changes
- 60 ammo across 9 Mks; at Mk.1 you burn through them in 33 s of constant fire and at Mk.9 you... still burn through in 33 s. Consider +10 ammo per Mk (60 → 140) so high-Mk Rocket Pod can actually sustain.
- Cooldown stays at 0.55s — consider 0.55 → 0.40 over the curve so the late-game Rocket Pod feels like a heavier cadence weapon, not just bigger numbers.
- Compare to Seeking Missile (3 base damage, similar curve) — Rocket Pod's identity is "raw damage to compensate for no homing," but Mk.9 it's only 18 dmg vs. Seeking's 27. Either bump Rocket's `dmg_per_mark` to 3 or drop Seeking's to 2.

### Seeking Missile (`seeking_missile_cannon.gd`)
- Homes onto nearest non-shielded enemy. Slow cadence, slow projectile, heavy damage. 60 ammo. Inherits default secondary `_mk_knobs()` (damage only).
- Mk 1: damage 3, cooldown 0.75s, 60 ammo
- Mk 1-9 damage 3→27 linear, cooldown flat 0.75s, ammo flat 60.

#### Recommended Changes
- Same ammo critique as Rocket Pod — 60 across all Mks. Add +10/Mk or refill scaling.
- Outclasses Rocket Pod at every Mk (more damage + tracking, same ammo, only 0.20s slower cadence). Rebalance: Rocket Pod should out-DPS Seeking on a fixed target by 25-40%, currently does not.

### Side Pods (`side_pods.gd`)
- Wing-mounted forward pods; hold shoot2 to fire. Spawns a symmetric pair (or more) of straight-forward bullets offset 12 px from centerline. Unmetered ammo.
- Mk 1: 2 pods × 1 damage = 2, cooldown 0.18s, halfspan 12 px
- Mk 2: 3 pods × 2 dmg = 6
- Mk 3: 4 pods × 3 dmg = 12
- Mk 4: 5 pods × 4 dmg = 20
- Mk 5: 6 pods × 5 dmg = 30
- Mk 6: 7 pods × 6 dmg = 42
- Mk 7: 8 pods × 7 dmg = 56 (pod count cap kicks in)
- Mk 8: 8 pods × 8 dmg = 64
- Mk 9: 8 pods × 9 dmg = 72
- Pod count: `min(2 + (mk-1), 8)`. Cooldown + halfspan flat.

#### Recommended Changes
- Effective damage per fire-press at Mk.9 (72) is higher than Mk.9 Heavy Blaster (28) and the second-highest weapon in the build. The pod cap at Mk.7 helps but the per-pod damage scaling on top of pod count is double-multiplicative. Consider: drop `dmg_per_mark` to 0 (pods scale count only, damage stays at 1) → Mk.9 = 8 dmg, or cap per-pod damage at +0.5/Mk (rounded). Otherwise this secondary out-damages every primary.
- Halfspan flat 12px — consider 12 → 20 px so the 8-pod fan at Mk.9 has visible coverage matching its lethality.

### Particle Beam (`particle_beam.gd`)
- Continuous secondary beam. Pierces chaff; stops at first tough/boss enemy. Flat 30 DPS, width scales 6 → 14 px.
- Mk 1: 30 DPS, 6 px width
- Mk 9: 30 DPS, 14 px width (`width + 1 × (mk-1)`)
- Damage flat across all 9 Mks (only width changes).

#### Recommended Changes
- DPS is identical at Mk.1 and Mk.9 — only the visual width grows. This is by far the weakest scaling in the game. Consider scaling `base_dps` 30 → 60 over Mks 1-9.
- Width grows linearly (8 px gain across 9 Mks); at Mk.9 a 14-px wide beam still misses most lateral movement. Consider 6 → 20 px.
- Alternative: add a pierce-through-tough condition at Mk.5 (currently *always* stops on tough/boss) so the mechanical identity shifts.

### Intercept Drones (`drone_bits.gd`, formerly DroneBits)
- Three drones orbit the player at 18 px radius and intercept incoming bullets/collisions. Each drone takes `2 + 1 × (mk-1)` hits. Doesn't fire offensively.
- Mk 1: 3 drones × 2 hits = 6 intercept hit pool
- Mk 9: 3 drones × 10 hits = 30 intercept hit pool
- Mk 1-9 hits per drone 2→10 linear (`base + 1 × (mk-1)`). Drone count flat 3 (capped by max_drones).

#### Recommended Changes
- Drone count is hard-capped at 3 (`max_drones`). Consider raising to 4 at Mk.5 and 5 at Mk.9 to add visual + tactical density at high Mks.
- Orbit radius + orbit speed flat — consider radius 18 → 26 at Mk.9 to widen the ablative shield arc as a tell.
- This is a defensive secondary with no offensive contribution — works conceptually but completely diverges from "weapon" framing. If keeping in the secondary pool, label clearly as defensive utility.

---

## Super (DEVICE_BAY_1)

All supers inherit charge scaling from `super_part.gd`: `_charges_at_mark(mk) = base_charges + (mk-1) × charges_per_mark`. Per-Part values noted below.

### Smart Bomb (`smart_bomb.gd`)
- Screen-clear + heavy global damage on activation. Cancels every enemy bullet, hits every enemy with damage, gives 0.6s i-frames. Charges scale; refill at outposts.
- Mk 1: 3 charges, 25 damage per activation
- Mk 9: 11 charges, 105 damage per activation
- Mk 1-9 damage 25→105 linear (`base + 10 × (mk-1)`), charges 3→11 (`+1 per Mk`).

#### Recommended Changes
- Both axes scale meaningfully — solid progression. No changes recommended.

### Hyper Mode (`hyper_mode.gd`)
- Brief invuln + supercharged primary (bypasses GunCooldown + 2× damage in `player.gd`). Offensive super.
- Mk 1: 2 charges, 3.0s duration
- Mk 9: 10 charges, 5.0s duration
- Mk 1-9 duration 3.0→5.0s linear (`+0.25s per Mk`), charges 2→10 (`+1 per Mk`).

#### Recommended Changes
- Duration gain is small in absolute terms (only +2.0s across 8 Mks). Consider `duration_per_mark = 0.4s` (Mk.9 = 6.2s) so the late-game Hyper window feels meaningfully longer, not 25% bigger.
- `HYPER_DAMAGE_MULT` lives in `player.gd` as a constant — consider exposing it as Mk-scaled (2× → 3× at Mk.9) so the super gets *more dangerous*, not just *longer*.

### Phase Shift (`phase_shift.gd`)
- Defensive super: invuln + screen-wide bullet cancel, no damage burst, no fire boost.
- Mk 1: 3 charges, 2.0s duration
- Mk 9: 11 charges, 3.6s duration
- Mk 1-9 duration 2.0→3.6s linear (`+0.2s per Mk`), charges 3→11.

#### Recommended Changes
- Same critique as Hyper — duration scaling is small. Acceptable for a defensive panic button, but Mk.9 (3.6s) might overlap awkwardly with Hyper Mode (5.0s) for less value.
- Consider adding a secondary effect at Mk.5: e.g., 1s of post-invuln slow-mo or a small "push" radial that buys spacing. Right now Mks 2-9 only add seconds + charges.

### Drone Swarm (`drone_swarm.gd`)
- Summons 4-6 player drones for 5+s; drones tether-orbit and auto-fire at bosses first / nearest enemy second.
- Mk 1: 1 charge, 4 drones, 5.0s duration
- Mk 9: 9 charges, 6 drones (capped at Mk.3 — `4 + (mk-1) × 0` since `drones_per_mark = 0`... wait)

Re-reading: `drones_per_mark = 0`, so the drone count *never increases with Mk*. Mk 9 still spawns 4 drones (`min(4 + 8×0, 6) = 4`). The `max_drones=6` cap is misleading — drone count is permanently 4 unless the export is overridden via .tres.

- Mk 1: 1 charge, 4 drones, 5.0s duration
- Mk 9: 9 charges, 4 drones, 9.0s duration
- Mk 1-9 duration 5.0→9.0s linear (`+0.5s per Mk`), charges 1→9 (`+1 per Mk`), drone count flat 4 (drones_per_mark = 0).

#### Recommended Changes
- **`drones_per_mark = 0` is almost certainly a bug or oversight.** The exposed `max_drones = 6` implies the design intent was 4 → 6 over Mks, but the increment is 0. Set `drones_per_mark = 1` and clamp at Mk.3+ (4→5 at Mk.3, 5→6 at Mk.5, then flat) — or `drones_per_mark` of 0.25 with int rounding for a 4→4→5→5→5→6→6→6→6 stagger.
- Drone damage is determined by the drone scene's own bullets (not Mk-scaled). Consider scaling drone fire damage with the super's Mk so high-Mk Swarm feels deadlier per drone.

---

## Weakest progressions (top 3)

1. **Particle Beam** — 0% damage growth across all 9 Mks. Mk.9 is identical DPS to Mk.1 with a slightly fatter beam visual. Worst scaling in the audit.
2. **Drone Swarm** — drone *count* never increases (`drones_per_mark = 0`), despite a `max_drones = 6` export implying it should. Mk only adds duration + charges. Likely an authoring oversight.
3. **Rocket Pod / Seeking Missile (tie)** — both inherit the default damage-only secondary curve. No ammo scaling (60 flat), no cadence change, and Seeking Missile invalidates Rocket Pod at every Mk. Rocket Pod especially feels deficient as a "raw damage trade-off" identity.

Honorable mention: **Machinegun & Rotary Laser** — both stuck at 9 damage at Mk.9 with no cadence/ammo scaling, far behind Heavy Blaster (28 dmg + faster cadence). Mk progression doesn't reinforce their high-RoF identity.
