# Hardpoint Unification — Design & Plan (2026-07-02)

**Status:** approved for build (Roman 2026-07-02). Supersedes the split mount/emitter model.

Merge the two enemy-spawner systems — the **gun/launcher mount** (`MountSpec` → `MountComponent`)
and the **emitter** (`EmitterComponent`) — into one **Hardpoint** spec + component, and add three
authoring features on top: rear/side aim directions, inward/outward muzzle ordering, and an opt-in
payload-toggle group (Delay / Inertia / Nose). Turret and beam stay as separate node realizations
that the same spec routes to.

---

## 1. Why

`MountComponent` (GUN/LAUNCHER) and `EmitterComponent` are the same operation — *"spawn payload × N
from an origin on a trigger, parented to the bullet world"* — expressed twice with disjoint feature
sets and duplicated-but-renamed concepts:

| Concept | Mount | Emitter |
|---|---|---|
| cadence | `fire_interval_min/max` | `cadence` |
| don't inherit velocity | `no_inertia` | `drop` |
| origin scatter | (marker spread only) | positional `spread` |
| count | `count` | `count` |
| off-screen hold | `_held` / `band_only`(no) | `band_only` |

Neither is a superset: only the emitter can fire **on death**, cap emits (`max_emits`), or gate to the
band; only the mount can **aim**, **burst**, **path-phase-fire**, or fan a **spread**. The gap is the
direct cause of the same enemy being modelled two ways (interceptor/wing: a *launcher mount* in the
bench vs a *missile emitter* in the roster — the divergence found during the 2026-07-02 bench-intake).

`EnemyTurret` and `BeamEmitter` are **not** duplicates — they are standalone nodes with their own aim
engines (turret = `atan2` + arc clamp; beam = a ~400-line FSM). They are kept as realizations the
unified spec *routes to*, sharing the spec + bench editor + aim vocabulary but not their internals
(Roman 2026-07-02: "keep them separated").

---

## 2. The unified model — five orthogonal axes

A hardpoint is fully described by:

1. **Payload** — *what* it produces. `payload_kind ∈ {BULLET, SCENE, TURRET, BEAM}`:
   - `BULLET` → a `BulletVariant` fired via the shared `Weapon` spawn helper (aim / homing / wobble /
     inertia / delay / muzzle flash / faction+sector mult scaling). Replaces mount kind GUN.
   - `SCENE` → instantiate a `PackedScene`. **Unifies launcher + emitter**: rockets/missiles (have
     `initial_dir`, aim + fan) and entities (mines/drones/bomblets/firecores/enemies, use `start(pos)`,
     drop/scatter) are the same "spawn a scene, place it, impart motion" path, duck-typed as today.
   - `TURRET` → an `EnemyTurret` node (builder-attached, unchanged internals).
   - `BEAM` → a `BeamEmitter` node (builder-attached, unchanged internals).
2. **Origin** — *where from*. `marker` (exact or glob; `""` = hull centre) + `marker_mode ∈
   {ALL, CYCLE, INWARD, OUTWARD}` + positional `scatter` (px, from the emitter).
3. **Trigger** — *when*. `trigger ∈ {CADENCE, PATH_PHASE, ON_PHASE, START, DEATH}`.
   `CADENCE` merges the mount timer and the emitter `timer` (one interval clock) with universal
   `max_emits` / `band_only` / `chance` sub-params. `START` = once at spawn. `DEATH` = on death by
   `chance`. `PATH_PHASE` / `ON_PHASE` = the existing band-progress / named-phase firing modes.
   (Turret `arc_gate` is turret-internal and stays there.)
4. **Motion** — *how it leaves*. `aim` (extended, see §3), `lead_factor`, `speed`, `count`,
   `spread_deg` (angular fan), `burst_interval`, `homing_rate`, `wobble_*`, and the payload toggles.
5. **Conditions** — *gates*. `zone_gated`, `nose_gated` (+ tol), `chance`, `max_emits`, `band_only` —
   all become universal opt-in gates regardless of payload kind.

`EmitterComponent`'s entire behaviour is then "a hardpoint where `payload_kind = SCENE` and
`trigger ∈ {START, CADENCE, DEATH}`." One component, one bench editor, one roster key.

---

## 3. The three new authoring features

### 3a. Aim — add `BACKWARD` / `LEFT` / `RIGHT`
`FORWARD` today is `Vector2.UP.rotated(enemy.global_rotation)` (`weapon.gd:75`), i.e. along the nose.
The three new directions are the same facing rotated:
```gdscript
Aim.BACKWARD: return Vector2.DOWN.rotated(enemy.global_rotation)   # opposite the nose
Aim.LEFT:     return Vector2.LEFT.rotated(enemy.global_rotation)   # enemy-relative port
Aim.RIGHT:    return Vector2.RIGHT.rotated(enemy.global_rotation)  # enemy-relative starboard
```
Extend the shared `Aim` enum (`weapon.gd:23`, mirrored in the spec). Turret/beam ignore these — they
aim via their own engines. Note: `LEFT`/`RIGHT` are relative to the enemy's *facing*, so a
downward-facing enemy's "left" is screen-right; this is intended (consistent with `FORWARD`).

### 3b. Muzzle order — add `INWARD` / `OUTWARD`
`_resolve_markers` (`mount_component.gd:147`) currently keeps scene-tree order. Sort the matched
markers by horizontal distance from the hull centre:
```gdscript
markers.sort_custom(func(a, b): return abs(a.global_position.x - cx) < abs(b.global_position.x - cx))
# INWARD  = nearest-first (as sorted);  OUTWARD = farthest-first (reversed)
```
Then walk them in that order (the existing `CYCLE` machinery, over the sorted list). Paired with
`burst_interval` and `count = marker count`, this produces the "outermost fires first, working inward"
ripple (and the reverse). `ALL` and `CYCLE` are unchanged.

### 3c. Payload toggles — opt-in, off by default (override-toggle UI style)
A grouped set in the editor, each a checkbox that is **off by default** and reveals its field when on:

- **Delay (ms)** — the payload holds position `X` ms before its motion begins. Bullets have no hold
  mechanism today (they move on frame 1, `base_bullet.gd:267`); add `motion_delay` gated in
  `_process`. Missiles already have `drift_time`, so it generalises. The spec carries
  `payload_delay_ms`, set on the spawned payload at fire time (alongside homing/wobble).
- **Inertia** — unifies mount `no_inertia` + emitter `drop`. **ON = the payload carries the enemy's
  velocity; OFF (default) = it drops / keeps its own speed** (Roman 2026-07-02). See §5 for the
  migration that preserves every existing hull despite the flipped default.
- **Nose** — the existing `fire_only_on_target` (+ `fire_aim_tol_deg`).

---

## 4. Spec schema (HardpointSpec, evolves MountSpec)

```
# Payload -----------------------------------------------------------------
payload_kind      : {BULLET, SCENE, TURRET, BEAM}
payload_variant   : BulletVariant     # BULLET
payload_scene     : PackedScene       # SCENE (projectile or entity)
# (turret_* fields + beam_config carry over 1:1 from MountSpec for TURRET/BEAM)
attach_to_enemy   : bool              # SCENE rides the enemy (turret-scene / carried)
# Origin ------------------------------------------------------------------
marker            : String            # exact or glob; "" = hull centre
marker_mode       : {ALL, CYCLE, INWARD, OUTWARD}
scatter           : float             # px positional jitter (was emitter `spread`)
# Trigger -----------------------------------------------------------------
trigger           : {CADENCE, PATH_PHASE, ON_PHASE, START, DEATH}
fire_interval_min : float             # CADENCE (== emitter cadence)
fire_interval_max : float
path_phases       : PackedFloat32Array
fire_beat_synced  : bool
on_phase          : String
max_emits         : int               # CADENCE cap (0 = unlimited)
band_only         : bool
chance            : float             # DEATH / CADENCE probability per emit
# Motion ------------------------------------------------------------------
aim               : {DOWN, TOWARD_CENTER, AT_PLAYER, FORWARD, BACKWARD, LEFT, RIGHT}
lead_factor       : float
speed             : float             # -1 = payload's own
count             : int
spread_deg        : float             # angular fan across the volley
burst_interval    : float
homing_rate       : float
wobble_amplitude  : float
wobble_frequency  : float
# Payload toggles (opt-in, default off) -----------------------------------
carries_inertia   : bool = false      # ON = inherit enemy velocity; OFF = drop/own speed
payload_delay_ms  : float = 0.0       # 0 = off
nose_gated        : bool = false
fire_aim_tol_deg  : float = 18.0
# Conditions --------------------------------------------------------------
zone_gated        : bool = false
```

`MountSpec` is renamed to `HardpointSpec` with a `const MountSpec = preload(...HardpointSpec)` alias
kept so existing `preload`/type references don't break (preload-const, not `class_name`).

---

## 5. Migration (zero required roster churn)

**Roster key.** Add `"hardpoints": [ {...}, ... ]`. The builder also keeps parsing legacy
`"mounts"` and `"emitters"` as aliases, converting each dict to a `HardpointSpec`, so no entry needs
rewriting. Entries migrate to `"hardpoints"` opportunistically.

**Legacy `mounts` dict → hardpoint:** `kind` gun→BULLET, launcher→SCENE, turret→TURRET, beam→BEAM.
`no_inertia:true → carries_inertia:false`; `no_inertia:false → carries_inertia:true`.
`fire_only_on_target → nose_gated`. Everything else (marker, marker_mode, aim, count, spread_deg,
burst_interval, fire_*, path_phases, on_phase, zone_gated, homing/wobble, turret_*/beam_config) is 1:1.

**Legacy `emitters` dict → hardpoint:** `payload_kind = SCENE`; `payload_scene` resolved from the
friendly payload name (existing emitter name→path map). `trigger` start→START, timer→CADENCE,
death→DEATH. `cadence → fire_interval_min = fire_interval_max`. `drop:true → carries_inertia:false`;
`drop:false → carries_inertia:true`. `spread → scatter`. `chance`, `max_emits`, `band_only`,
`attach_to_enemy`, `sfx`, `tag` are 1:1.

**Inertia polarity — the one behavioural trap.** The new default is `carries_inertia = false` (drop),
but the two legacy systems had *opposite* defaults (mounts inherit; emitters drop). The migration
above maps each existing hull to its current behaviour explicitly, so **nothing in production changes**
— the drop-by-default only applies to *newly authored* hardpoints (consistent with the recent "drop"
work). A migration self-check (see §8) asserts every legacy mount/emitter round-trips to the same
effective inheritance.

**Shared consts.** `GUNSHIP_MOUNTS`, `PUSH_MOUNTS`, `ROCKET_MOUNTS`, `BOMBER_TAIL_MOUNT`,
`MINELAYER_EMITTERS`, `BEAMER_*` etc. are dict-lists; they keep working through the legacy-alias
parse. No edits required.

---

## 6. Realization routing (builder)

`mount_builder.gd` (rename → `hardpoint_builder.gd`, keep alias) routes by `payload_kind`:

- `BULLET` / `SCENE` → a `HardpointComponent` (evolved `MountComponent`), registered in `_components`
  and ticked by `enemy_core` (unchanged plumbing).
- `TURRET` → an `EnemyTurret` node (existing `_build_turret`, unchanged).
- `BEAM` → a `BeamEmitter` node (existing `_attach_beam`, unchanged).

The `SCENE` path in `HardpointComponent` merges `_fire_launcher` and `EmitterComponent._emit`:
instantiate → set `initial_dir` if present and `aim != none` → resolve origin (markers / centre +
`scatter`) → add to the resolved `BulletWorld` → `start(pos)` if present else `global_position` →
impart velocity per `carries_inertia` → apply `payload_delay_ms`. **Preserve** the emitter's
`call_deferred` insertion (avoids the "changing state while flushing queries" crash when a DEATH
trigger fires inside a physics callback — `emitter_component.gd:120`).

---

## 7. Phased implementation plan

Each phase is independently shippable, compile-clean, and boot-verified before the next.

### Phase 1 — new firing features on the existing mount (immediate value)
Lands the three features on today's `MountSpec`/`MountComponent`, so every existing gun/launcher gets
them at once. No emitter/structural change yet.
- **Aim:** add `BACKWARD/LEFT/RIGHT` to `Weapon.Aim` + `_aim_dir` (`weapon.gd`); mirror in
  `MountSpec.Aim`; add to the roster aim-string map and the bench aim dropdown.
- **Muzzle order:** add `INWARD/OUTWARD` to `MountSpec.MarkerMode`; sort in
  `MountComponent._resolve_markers`; add to the roster map + bench dropdown.
- **Delay:** add `motion_delay` to `base_bullet` (+ a hold on `base_missile`); add
  `payload_delay_ms` to `MountSpec`; wire it at spawn (gun via the internal `Weapon`, launcher via the
  projectile); add the bench toggle.
- **Payload-toggle group (UI):** regroup the bench's `no_inertia` / `nose_gated` + new `delay` into an
  off-by-default toggle group labelled **Delay / Inertia / Nose**. Present `Inertia` with the agreed
  polarity (`Inertia = !no_inertia` under the hood for now); the saved-file loader maps the old
  `no_inertia` key so existing bench saves are preserved.
- **Verify:** `compile_check` PASS; `main.tscn` headless boot; a bench firing smoke exercising each new
  aim dir + inward/outward + a delayed shot.

### Phase 2 — fold the emitter into the component (structural unification)
- Introduce `payload_kind {BULLET, SCENE, TURRET, BEAM}`; build the merged `SCENE` fire path in the
  component (launcher + emitter behaviours: START/CADENCE/DEATH triggers, `scatter`, `chance`,
  `max_emits`, `band_only`, `attach_to_enemy`, `carries_inertia`, `payload_delay_ms`); keep the
  deferred-insert safety.
- Rename `MountSpec → HardpointSpec`, `MountComponent → HardpointComponent`,
  `mount_builder → hardpoint_builder` (keep `const` preload aliases; filenames may stay to avoid
  UID-cache churn — see `moving-uid-referenced-scripts`).
- Builder parses `"hardpoints"` + legacy `"mounts"`/`"emitters"`; routes by `payload_kind`.
  `EmitterComponent` retires (or becomes a thin shim); roster emitters flow through the unified path.
- **Verify:** `compile_check` PASS; boot; a minefield/hazard run (minelayer drops, interceptor/wing
  missile drop, firecore death-scatter) reproduces pre-refactor behaviour; the §8 inertia self-check.

### Phase 3 — merge the bench editors
- Replace the separate **Mounts** + **Emitters** editors with one **Hardpoints** list. A `payload`
  dropdown (bullet families + Drop + projectile scenes + entity scenes + Turret + Beam) drives
  `payload_kind` and shows/hides the relevant fields; the `trigger` dropdown gains START/TIMER/DEATH;
  the payload-toggle group + new aim/marker options carry over.
- Serializer emits the unified `"hardpoints"` dict; still reads legacy for backward load.
- Update `docs/contributing/enemy-bench-guide.md` and the enemy-bench user guide.
- **Verify:** author each payload kind + trigger in the bench, Copy GDScript, paste into a scratch
  entry, boot, confirm parity.

---

## 8. Risks & self-checks

- **Inertia polarity** (§5) — the highest-risk item. Add a headless self-check that, for every legacy
  `mounts`/`emitters` dict in the roster, asserts the converted `HardpointSpec.carries_inertia` equals
  the legacy effective inheritance. Must pass before Phase 2 lands.
- **Deferred insert** — the `SCENE` path MUST keep `call_deferred` insertion or DEATH-trigger spawns
  crash on the physics flush (`emitter_component.gd:120`).
- **Beat-sync / path-phase** — the `FiringScheduler` engine is shared with the hull; the component must
  keep the "no auto-populate `DEFAULT_PATH_PHASES`" rule (`mount_component.gd:26`).
- **Preload-const rename** — `HardpointSpec`/`HardpointComponent` stay preload-const (not
  `class_name`); keep aliases so `preload` refs and the bench's script-identity detection don't break.
- **Turret/beam untouched** — their nodes/FSMs are not refactored; only the builder routing + bench
  addressing change. A turret/beam enemy (push, helix, crusader, spear) must render + fire identically.

## 9. Out of scope
- Turret and beam internals (aim engines, FSM) — routed to, not rewritten.
- A universal `AimResolver` shared across Weapon/Turret/Beam — noted by the plumbing pass as possible,
  but deferred; the three aim engines stay independent for now.
- The bullet-variant families vs roster `BV_*` consolidation (separate follow-up).
