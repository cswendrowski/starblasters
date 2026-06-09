# Swarm Launcher — New Secondary — Scoping

**Date:** 2026-06-08
**Status:** Scoped, not built. Design locked by Roman; implementation TBD.

## Design (Roman, verbatim intent)
A HARDPOINT_WING **secondary** that releases a **burst of seeking missiles** that home onto targets
and explode against them.
- **4 damage** each; **4 missiles** in the salvo at Mk.1.
- **Prefer separate targets**; if there are none distinct, all chase the same target. If a missile's
  target **dies, it re-acquires** a new one. If there are **no targets, it flies on and explodes
  harmlessly** (fuse).
- **Appearance:** a bright **yellow-orange flickering pixel + a diffuse glow**, leaving a **missile
  trail** behind it. Simple.
- **Movement:** **6 px/f** (= 360 px/s, rung 6 — on the clarity scale, under the 8 px/f ceiling).
  Closes quickly on targets. **Small, tight turning arc** so it reads as a missile.
- **Mk scaling:** **+2 missiles per Mk** (Mk1 = 4, Mk2 = 6, … Mk9 = 20).
- **Ammo:** **6**; firing the salvo costs **1 ammo**. **3-second cooldown** after firing.

## What exists to build on
- **Secondary pipeline:** `player.gd._process` (`:716-731`) dispatches on `secondary_mode`
  (`WeaponStyle.gd` BULLET/BEAM/BURST/DEPLOY). A part configures `secondary_*` fields via its
  `_apply_visuals` (`secondary_weapon.gd:42-48`); ammo via `ship.set_secondary_ammo(seed, max)`
  seeded from `Run.secondary_ammo` (survives scene changes).
- **Homing missile base:** `scripts/projectiles/base_missile.gd` (`class_name BaseMissile`) — drift →
  ignite → home → detonate. Knobs: `homing_max_speed`, `homing_accel`, `seeker_cone_deg`,
  `speed_lock_mult`, `damage_on_contact`, `fuse`, `flame_trail`, `initial_dir`, `target_group`
  (="enemies" for player ordnance). Contact damage routes `area.take_hit(damage_on_contact)`;
  no-target → flies `initial_dir` until `fuse` → `explode()` (harmless if it hits nothing).
- **Salvo template:** `drone_swarm.gd.deploy()` (`:120-147`) loops N spawns, parents to
  `ship.bullet_parent` else `tree.root` (the seam I fixed for the Hangar), binds each.
- **Clarity:** 6 px/f = 360 px/s = rung 6 (`clarity.gd`). ⚠️ `speed_lock_mult` (default doubles
  post-lock) would push 360 → 720 = 12 px/f, **over the 480 ceiling** — set `speed_lock_mult = 1.0`.

## Two gaps vs. current missiles (NET-NEW, not configuration)
1. **Distinct-target assignment.** Current player missiles each independently pick nearest, so a
   salvo *clumps*. There is **no round-robin/distinct-target helper** anywhere. New: in the Swarm
   part's spawn loop, snapshot `get_tree().get_nodes_in_group("enemies")` once, sort (bosses first,
   then nearest), and hand each missile a **distinct assigned target** (wrap/round-robin when missile
   count > enemy count → "all chase same" falls out when there's 1 enemy, "harmless" when there are 0).
2. **Re-target on target death.** Current player missiles use a **one-shot lock** and fly *straight*
   when the target dies (`base_missile.gd:191-194`). The Swarm needs the enemy-missile-style
   re-acquire branch when `_locked_target` invalidates.

Both go on a **Swarm-specific missile subclass** (or guarded flags on `base_missile`) so the regular
Seeking/Anti-Ship missiles are untouched.

## Build plan
### 1. `scripts/projectiles/swarm_missile.gd` (extends BaseMissile, or flags on base)
- `assign_target(node)` setter — accept the part-assigned distinct target instead of self-acquiring.
- **Re-acquire on death:** when the assigned/locked target invalidates, re-scan for the nearest live
  enemy instead of flying straight; if none, continue on heading → `fuse` → harmless `explode()`.
- `homing_max_speed = 360`, **tight arc** via high `homing_accel` (turn radius = accel-vs-speed
  ratio; no explicit angular knob — start ~720+ and tune), `speed_lock_mult = 1.0` (clarity ceiling),
  `damage_on_contact = 4`, short `fuse`.
- VFX: a small yellow-orange `Sprite2D` (or ColorRect) with a per-frame **flicker** (modulate
  jitter), a **diffuse glow** (reuse `GlowShaderFx.apply` like the player Phase glow / focus aura),
  and the existing **missile flame/smoke trail** (`flame_trail` / `missile_smoke_trail.gd`).

### 2. `scenes/projectiles/player_swarm_missile.tscn`
- `swarm_missile.gd` scene, `Area2D` + `Sprite2D` + `CollisionShape2D` (tight, projectile-sized),
  the export knobs above set in the scene. `target_group = "enemies"`.

### 3. `scripts/parts/swarm_launcher.gd` (extends `secondary_weapon.gd`)
- `display_name = "Swarm Launcher"` + description; `base_damage = 4`, `dmg_per_mark = 0`.
- **Mode:** **DEPLOY-style own-spawn is the better fit** than BULLET mode — the part owns the spawn
  loop so it can assign distinct targets (BULLET mode `fire_secondary` spawns identical clumping
  missiles). Either reuse `SecondaryMode.DEPLOY` with a `deploy()` that fires the salvo, **or** add a
  new `SecondaryMode.SALVO` + `_tick_salvo` mirroring `_tick_deploy` (press-edge + ammo + cooldown).
  Note DEPLOY has **no built-in cooldown** today (gates on `_drones_active`) — the Swarm needs a real
  3s cooldown gate, so a small SALVO mode (or a cooldown timer added to the DEPLOY path) is cleanest.
- `salvo_count(mk) = 4 + (mk-1)*2`.
- **Salvo spawn:** snapshot enemies, sort (boss→nearest), spawn `salvo_count` swarm missiles, assign
  each a distinct target (round-robin), parent to `ship.bullet_parent` else `tree.root`, give each a
  slight spread `initial_dir` so they fan before homing.
- **Ammo:** 6 / `set_secondary_ammo(6, 6)`; 1 per salvo. **Cooldown:** `secondary_cooldown = 3.0`.

### 4. Registration (`part_catalog.gd`)
- `const SwarmLauncher = preload(".../swarm_launcher.gd")` + `const PlayerSwarmMissile =
  preload(".../player_swarm_missile.tscn")` (`:7-36`).
- `_all_pool` (`:40-73`): `{"factory":"_make_swarm_launcher","slot": Slots.SlotType.HARDPOINT_WING}`.
- `_make_by_name` (`:106-155`): `_build_weapon("res://resources/weapons/swarm_launcher.tres",
  SwarmLauncher, PlayerSwarmMissile)`.
- **No `bullet_catalog.gd` change** (enemy-only). **No `outpost.gd` change** — HARDPOINT_WING is
  already in `WEAPON_SLOT_WEIGHTS` and secondary-ammo refill is generic, so it auto-enters shop rolls
  + gets refills for free.
- Optional `resources/weapons/swarm_launcher.tres` for editor parity (remember: `.tres` skips
  `_init`, so behavior goes in virtual overrides, name/desc via the copy-back).

## Verify-before-build / risks
- **`speed_lock_mult`** must be 1.0 (or cap locked speed ≤ 480) — else 6 px/f → 12 px/f post-lock.
- **DEPLOY cooldown gap** — confirm whether to add a cooldown to DEPLOY or author a SALVO mode.
- **Turn arc** has no explicit angular-rate knob — it's the `homing_accel`/`max_speed` ratio;
  playtest for the "tight missile arc" feel (this is a tuner-ish knob — consider exposing it).
- **Distinct-target + re-acquire** are the two genuinely-new bits; everything else is configuration.
- **Clutter at high Mk** — Mk9 = 20 missiles/salvo; keep the sprite tiny + trail brief for
  motion-clarity at 480×270.

## Build surface (file:line)
- New: `scripts/parts/swarm_launcher.gd`, `scripts/projectiles/swarm_missile.gd`,
  `scenes/projectiles/player_swarm_missile.tscn`, (opt) `resources/weapons/swarm_launcher.tres`.
- `scripts/parts/part_catalog.gd:7-36, 40-73, 106-155` (registration).
- `scripts/weapons/WeaponStyle.gd:38-49` + `scripts/player.gd:716-731` + a `_tick_salvo`
  (only if adding a SALVO mode rather than reusing DEPLOY).
- Reuse: `base_missile.gd`, `GlowShaderFx`, `missile_smoke_trail.gd`, `impact_fx`/`explosion_fx`.
