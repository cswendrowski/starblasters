# Boss Encounter System (standardized)

**Status:** built 2026-06-16. Testbed: the **Shepherd** (`scripts/enemies/bosses/boss_shepherd.gd`).
Spec for the testbed boss: `docs/design/Boss - Shepherd.md`.

A reusable, opt-in **state-machine + destructible-parts** layer added to
`scripts/enemies/bosses/boss_base.gd`, so every boss can express lifecycle
encounters (scripted arrivals, invincible transitions, off-screen passes, loops)
that the old HP-ladder couldn't. Designed to be **expanded as needed** — start
minimal, add trigger types / helpers / part behaviours when a boss demands them.

The seven existing bosses are **untouched**: if a boss doesn't register a state
graph, the legacy `phases[]` HP-ladder runs exactly as before. The two models are
mutually exclusive per boss; migrate old bosses opportunistically, never forced.

---

## 1. Why

`boss_base`'s phase machine was **HP-threshold only and forward-only**. It can't
express: timer gates, looping back to an earlier phase, scripted arrival/exit
choreography, invincibility windows, or destructible sub-parts. Bosses were
already hacking around it (`boss_conductor._force_advance_phase` for satellite
kills; `conductor_satellite` as a bespoke destructible part). This system makes
those first-class and shared.

## 2. The state machine

A boss opts in by overriding `_build_states()` and registering a graph. States are
**code-defined** (behaviour in dispatch methods); transitions are **declarative**
(a trigger → next-state table evaluated every frame, first match wins).

### Authoring API (on `boss_base`)
- `add_state(&"NAME")` — register a state (first registered = initial, unless `_initial_state` set).
- `add_transition(&"FROM", trigger, &"TO")` — a trigger-gated edge.
- `go_to_state(&"NAME")` — force a jump (escape hatch for event-driven logic).
- `set_flag(&"name", true)` / `set_invincible(bool)` — runtime signals (flags auto-clear on each state change).

### Behaviour hooks (override per boss)
- `_state_enter(name)` — start the state's movement + a per-state attack coroutine.
- `_state_tick(name, delta)` — optional per-frame logic (usually unused; coroutines preferred).
- `_state_exit(name)` — optional teardown.
- `_on_part_lost(part)` — a destructible part died.

The idiom for a state's attack rotation is a coroutine started in `_state_enter`,
guarded so it self-cancels when the state changes:

```gdscript
func _state_enter(name):
    match name:
        &"PHASE_1":
            jiggle_hold()
            _phase1_loop(name)   # bare call (not awaited) — runs until its first await, then yields

func _phase1_loop(state):
    while _state == state and not _dying:
        await fire_something()
```

### Trigger library
Plain data dicts (inspectable, no closure capture), built by helpers and evaluated
by `_eval_trigger`:

| Helper | Fires when |
|---|---|
| `t_hp(pct)` | `health/max_health <= pct` |
| `t_after(sec)` | `sec` elapsed in the current state |
| `t_flag(&"name")` | the named flag is set |
| `t_any([...])` | any sub-trigger fires (OR) |
| `t_all([...])` | all sub-triggers fire (AND) |
| `t_pred(callable)` | a `Callable() -> bool`, evaluated live |

"75% HP **or** 20s" = `t_any([t_hp(0.75), t_after(20.0)])`.

### Lifecycle
`_build_states()` runs in `_ready()` (via `_init_phases`); the **initial state is
entered from `start()`** (once the director has placed the boss), so arrival
choreography sees a real position. `_process` pumps `_tick_state_machine` while
`_sm_active`. The boss death path is unchanged (`explode()` + `_on_boss_death`).

## 3. Invincibility

`set_invincible(true)` makes `take_hit` a no-op (with a cyan deflect tick). Used by
transition/arrival states so the boss can't be killed mid-animation. Cleared by the
state when its animation finishes.

## 4. Behaviour helpers (reusable, on `boss_base`)

Movement choreography is **awaitable** so a state coroutine can `await arrive_from(...)`
then `set_flag(&"arrived")` to drive its transition. `_scripted_move` lets these own
`position` and travel off the playfield (the normal pattern/clamp is suspended).

- `jiggle_hold(amp, period)` — gentle high-hold drift (small `sweep_horizontal`).
- `fly_offscreen(dir, speed)` — exit along a direction.
- `arrive_from(lane_x, speed)` — park below → sweep up & off the top → descend into the hold.
- `vertical_pass(speed, on_tick)` — top→bottom traverse; `on_tick(progress)` fires salvos along it.
- `flare_clear(radius, damage, flashes)` — invincible flare: N red flashes → nuke nearby projectiles + brief damage area.
- `fire_zone_strike(count, telegraph, radius, damage)` — telegraphed AoE strikes at random positions.
- `release_firecore(offset)` — drop a drifting zealot firecore hazard.

Plus the pre-existing primitives: `fire_aimed_burst/cone/spread/ring`,
`fire_beam_telegraphed`, `sweep_horizontal`, `anchor_at`, `dive_toward`,
`mirror_player_x`, `start_telegraph`, `_enrage_flash`, `_screen_shake`.

All spawns route through `_world()` (`BulletWorld.resolve`) so they render in the
right viewport inside the Enemy Bench / Combat Lab as well as production.

## 5. Destructible parts (`boss_part.gd` + `boss_turret_part.gd`)

`BossPart` is the standardized generalization of `conductor_satellite`: an `Area2D`
sub-component with its own HP, hit-flash, an explosion + optional burning trail on
death, and a `part_destroyed` signal. It joins `"enemies"` (so player fire collides)
but is `is_hazard` (so it doesn't gate wave-clear — the boss is the combatant; free
survivors in `_on_boss_death` via `free_parts()`).

`boss_turret_part.gd` extends it with a barrel sprite (recoil strip), `aim_to(dir)`
and `fire(dir)` — **commanded**, not autonomous, so a boss coordinator can run squad
patterns instead of N independent turrets.

### Part registry / threshold loss (on `boss_base`)
- `register_part(part)` — track + connect a part.
- `live_parts()` / `destroy_random_part()` / `free_parts()`.
- `set_part_loss_thresholds([0.75, 0.5, 0.25])` — blow a random part each time HP
  crosses a fraction. **Decoupled from the phase graph** (checked in `hit()`).

## 6. Recipe: a new boss on this system

1. `extends "res://scripts/enemies/bosses/boss_base.gd"`.
2. In `_ready()`: set `max_health` / `bounty_value` / `display_scale` / `boss_hover_y`
   **before** `super._ready()`. Optionally `set_part_loss_thresholds([...])` + build parts after.
3. Override `_build_states()` — `add_state` each state, `add_transition` the edges.
4. Override `_state_enter(name)` — install movement + start the state's attack coroutine.
5. (Parts) build `BossPart`/`boss_turret_part` on the scene's markers, `register_part`,
   and `free_parts()` in `_on_boss_death`.
6. Scene: root `Area2D` in group `"enemies"`, script = your boss, with `ShootTimer`/
   `MoveTimer` (wired to `_on_shoot_timer_timeout`/`_on_timer_timeout`) + a `Sprite2D`.
7. Register for dev launch in `combat_lab.gd` `BOSS_PICKS`; add to the production
   `wave_generator.BOSS_ROSTER` only when it's ship-ready.

## 7. The Shepherd (testbed) — concrete mapping

State graph (`boss_shepherd.gd`):

```
ARRIVAL ──t_flag(arrived)──▶ PHASE_1
PHASE_1 ──t_any[hp<.75, after 20s]──▶ TRANSITION_1*   (invincible flare)
TRANSITION_1 ──t_flag(anim_done)──▶ PHASE_2
PHASE_2 ──t_flag(loop_done)──▶ PHASE_1_5             (PHASE_2 ends by re-arriving)
PHASE_1_5 ──t_any[hp<.50, after 20s]──▶ TRANSITION_2* (invincible flare)
TRANSITION_2 ──t_flag(anim_done)──▶ PHASE_3           (holds until death)

Turret loss at 75/50/25% HP → set_part_loss_thresholds, INDEPENDENT of the graph.
```

- **Turrets do ALL cannon fire, in every combat phase** (1 / 1.5 / 3) via the
  coordinator (`_mode_cycle/_mode_salvo/_mode_sweep`, reshuffled per phase) commanding
  the 4 `boss_turret_part`s on `TurretL/R/L2/R2`; volume falls off as turrets are lost.
- **PHASE_1 / PHASE_1_5** share behaviour (jiggle hold + turrets) and differ only in
  their exit target — exactly what a state graph makes trivial.
- **PHASE_2 = untouchable missile-cruiser interlude:** invincible the whole phase,
  drops the hull into the pseudo-parallax (faked mid-depth) layer, and runs the shared
  **`MissileSalvo`** area attack (3 cycles, 2s gaps) — turrets hold fire. Then restores +
  exits off the bottom and `arrive_from`s again → loops to PHASE_1_5.
- **PHASE_3** flips the hull to face the player, sweeps L-R launching `enemy_rocket_large`
  from `LauncherL/R` (cycling L-R-L-R / L-L-R-R / (L+R)×2), keeps the turrets firing, and
  `release_firecore`s until the 4 cores are gone.

### First-pass / to tune
- Transition flare uses the `gun_muzzle_flash` strip at the engine markers (interim art).
- Phase 2's faked depth is a lightweight scale-down + tint + z-index; swap to
  `MidDepthPresentation.add_above_backdrop` for full parallax fidelity if wanted.
- Arrival lane is `Playfield.CENTER.x` — point at the real missile-cruiser lane.
- Cadences / counts / HP (260 base ×1.5) are first-pass; tune in the Combat Lab.
- The hull is a multi-layer sprite ("Sherpherd Hull"/"EngineLayer"/"Lower Hull"); the
  Shepherd flips/tints/flashes via `_hull_layers()` (type-discovered, rename-safe).

### Launch / iterate
Dev Menu → **Combat Lab** → encounter **Boss Fight** → **Shepherd** → Launch. It is
**not** in the production `BOSS_ROSTER` yet (testbed only).

## 8. File map

| File | Role |
|---|---|
| `scripts/enemies/bosses/boss_base.gd` | state machine + triggers + invincibility + behaviour helpers + part registry (added to the existing base) |
| `scripts/enemies/bosses/boss_part.gd` | reusable destructible part (generalizes `conductor_satellite`) |
| `scripts/enemies/bosses/boss_turret_part.gd` | turret part: barrel + commanded aim/fire |
| `scripts/effects/missile_salvo.gd` | reusable telegraph + lobbed-missile + AoE salvo, extracted from `missile_cruiser.gd` (used by the cruiser AND Shepherd Phase 2) |
| `scripts/enemies/bosses/boss_shepherd.gd` | the Shepherd (testbed) |
| `scenes/enemies/factions/zealot/boss_z_l_shepherd.tscn` | Shepherd scene (script swapped from `enemy_sword.gd`) |
| `scripts/dev/combat_lab.gd` | `BOSS_PICKS` dev launcher entry |
