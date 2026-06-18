# Starblaster TODO

Captured from Cody's 2026-05-19 punch list. Ordered roughly by leverage.

> **2026-06-10 batch:** the overnight worklist run (branch `worklist-2026-06-10`, ~30 commits)
> landed: Minigun + Autocannon (Machinegun retired from the pool), full audio rewire (new weapon/
> outpost SFX + distance-based explosions, old death clip retired), music intensity ramp rework
> (+permanent per-boss step), the 7-item outpost UX overhaul, Phase/Hyper mode implementations,
> HUD weapon-light/ammo fixes, zealot ball-explosion routing, enemy-bench recycle tagging,
> manage-ship shift modes, onboarding refresh, off-screen-enemy hit immunity, Omni no-fly fix —
> plus post-playtest hotfixes and a hardened fail-closed parse gate. Per-item log + commits +
> the eyeball checklist: **`Worklog.md`**.
>
> **2026-06-11 session** (pushed to `origin/main`): DEV-tool cleanup (7 retired), Enemy Bench rework,
> Weapon Lab (3-tab HD bench), the HD play-area fixes (SubViewport HDR-2D parity + background z-order
> — closes the hangar "green muzzle / missing bullets"), Forward+ renderer locked in, and the
> Blaster-Replacement + weapons batch. The Worklist has been **cleared**; its still-open items are
> consolidated in **"Carried from Worklist (2026-06-11)"** immediately below.
> **Sector modifiers are PULLED** (kill-switch in run_state) pending re-eval — see below.
>
> **2026-06-12 session** (`3af593d`, `4f862fd` on main): a VFX/backdrop batch — centralized tunable
> explosions, ship damage-tell suite + progressive burn trails, smoke/spark/burning-trail rebuild,
> Sequence Lab, Enemy Bench (full roster + faction tabs + mines disarmed); the **dynamic-nebula** rework
> (swirl + per-POI re-enable + Shader Lab page + A/B alts); **glow-halo → bloom** (pulled projectile
> halos, HDR-bright bolts); the **`outline_1px` Forward+ crash fix**; and confirmation that renderer
> **levers A+B** are already live (lever C partial). Per-item status: **`Worklist.md`** (refreshed).

## Carried from Worklist (2026-06-11)

The Worklist was cleared this session. Items below were the active worklist; statuses updated.

**Still open** (detailed specs live in the deeper TODO sections — pointers given):
- [ ] **Recycler — Pillar 2** — NOT STARTED. RecycleTuner dev scene first, then `RecycleController`,
  then roster migration. Full build order under **"Recycling — Pillar 2"** below
  (spec: `docs/archive/recycling_system_pillar2_2026-06-04.md`). Prereq tooling (Enemy-Bench recycle/passes/
  flee tagging) landed 2026-06-10. Regression surface = whole roster → playtest-only.
- [ ] **Lane Hook not leaving the play area** — NEEDS REPRO. Code-side exit config verified correct
  (DIVE_RETURN frees on any edge after the U-turn climb); need the in-game symptom (stalls mid-climb?
  exits the wrong edge? recycles instead of leaving?). (`scripts/enemies/patterns/lane_path.gd`)
- [ ] **Supremacy Push globbing** — NEEDS STEER. Want controlled numbers (one to a lane / one per
  crossing). The push anchors bypass the existing lane-spread + crosser stagger; confirm whether the
  descenders stack or the side_traverse crossers overlap, then route just those through the spread.
- [ ] **wreck_layer** — BUILT 2026-06-10 (`9d99405`, test-gated); EM Torpedo is the testbed. NEEDS
  EYEBALL. Expand to more death styles (e.g. the bomber encounter) if it reads well — just tag those
  kills with `death_style="wreck"`.
- [ ] **EM Torpedo** — BUILT; electric-ball ring detonation reworked 2026-06-11 (`34b33be`). NEEDS
  FEEL PASS. NOT in the shop pool yet — promote by adding `_make_em_torpedo` to `part_catalog._all_pool`
  + authoring `resources/weapons/em_torpedo.tres`. (Behind Test Combat → "EM Torpedo + Wreck Test", fire C.)
- [ ] **Sector modifiers** — PULLED (kill-switch `Run.SECTOR_MODIFIERS_ENABLED = false` gates rolling +
  application; vocabulary + effect wiring kept). **FLAGGED FOR RE-EVAL + REIMPLEMENT.**

**Done this session** (were on the Worklist):
- [x] **Forward+ renderer + Windows-only build** — pivoted and locked in (non-negotiable per Roman 2026-06-11).
- [x] **Hangar "green muzzle / missing bullets"** — root-caused + fixed. Two stacked bugs: the play-area
  SubViewport rendered LDR under the now-HDR-2D root (additive blends composited wrong), and the opaque
  background sat at z=0 over the z=-1 bullets + glow halos. Fix = `use_hdr_2d` parity + background on a
  CanvasLayer behind the gameplay. Both guarded + documented (`docs/godot-patterns.md` "HD SubViewport host").

## M6c polish backlog (scoped 2026-06-07)

Remaining from Roman's batch after the engine-trail / reorg / weapon-fix / shader passes
landed. Grouped by effort.

**Bespoke per-enemy fixes (small, need eyeball):**
- [ ] **s_s_rush movement-based facing** — auto_rotate is on by default but Roman reports
  it's not facing its travel. Eyeball: not turning at all / faces down / spins? Likely an
  auto_rotate seed or the Engine-marker-under-CollisionShape transform. (`enemy_s_s_rush.tscn`)
  - _2026-06-08: STILL OPEN. 96733b8/cb3a807 fixed the **push** enemy's turret facing — unrelated.
    s_s_rush itself untouched. (Note: its `.tscn` embeds `straight_down(240)` but the matrix
    overrides it to `hunt_beeline` in real waves; check facing under BeelinePlayer.)_
- [x] **z_s_sword firing** — DONE (combat session, `35712ff` "sword rolling broadside firing").
- [x] **retro/hold turn-during-jiggle** — DONE (combat session, `cdf4b3a` "loiter holders don't turn
  the wrong way during the jiggle").

**Wave/pattern work (larger, director + wave-gen):**
- [ ] **Cohesive chaff waves** — bomb-drone/dart waves are too long + sparse. Want
  multi-layered walls, tightly-spaced walls with navigable lane gaps, L→R (and R→L) sweeps,
  and inward→out / outward→in patterns. (`scripts/levels/director.gd` + `wave_generator.gd`)
  - _2026-06-08: STILL OPEN. STEP-wall-with-gap exists (lane_path STEP + director step_wall);
    the broader wall/sweep composition is unbuilt beyond the hotrod no-recycle subitem._
- [ ] **Speed audit to the 1–8 px/f rungs** — `fast_straight` done (→300); audit every other
  movement key + sector scaling so nothing common sits past 6 px/f. >6 px/f = reflex tier:
  rare, mid/late only. (`enemy_roster.make_movement` + `enemy_core` sector scale + `clarity.gd`)
  - _2026-06-08: PARTIAL. The straight family is now rung-named in make_movement:
    crawl 60 / slow 120 / medium 180 / fast 300 / reflex 360 (the overhaul). A full per-enemy
    sweep (loiter exit speeds, side_dive 300, etc.) + the "chaff −1 rung" pass is still open._
- [x] **Midpoint heavies more common** — DONE (combat session, `f7c2038` "midpoint heavies more
  common (second anchor beat on long levels)").
- [x] **No-recycle + denser packing for high-count chaff** — DONE (combat session, `af9bb58`
  "hotrod no-recycle (high-count chaff)").

**Cleanup:**
- [x] **385 editor GDScript warnings** — CLEARED (Roman 2026-06-08: "largely handled, we can clear this").

## M6c polish backlog — round 2 (scoped 2026-06-08)

### Enemies
- [x] **Drop enemies — burst-once, no recycle.** DONE (combat session, `d70fd37` behavior batch — "drops").
- [x] **Sapper is double-shielded.** DONE (combat session, `d70fd37` "sapper shield").

### Bullets / weapons
- [ ] **Weapon-library audit** — confirm EVERY enemy fires via the new Weapon/BulletVariant
  library, not a bespoke holdover. Some projectiles read as wrong speed / old sprite. Sweep
  enemy scripts for hand-rolled bullet spawns + off-library variants.
  - _2026-06-08: LARGELY DONE via the migration — the known hand-rolled holdouts were removed:
    strafer (→ "nose" Weapon), bomber tail gun (→ arc-gated EnemyTurret), beam shooter (already
    shared BeamEmitter), frigate retired (→ BROADSIDE). BulletVariant library is in use everywhere
    (see B2 below). REMAINING gap = **Weapons 3b**: ◑ PRODUCERS DONE 2026-06-13 — `make_shoot`/`levels_v2`/
    `wave_generator` now build the unified `Weapon` (the bulk of enemy firing); the legacy classes survive only
    in ~6 designer `.tres` + ~5 enemy scenes (the deletion tail). A formal grep-sweep for any last hand-rolled
    spawns is still worthwhile._
- [ ] **Tracer art hframes/masking** — tracer sprites render doubled with an offset glow;
  check hframes + frame masking on the tracer textures (`enemy_tracer` / `tracer-*` + variants).
  - _2026-06-08: STILL OPEN — not touched by the migration (art/shader bug)._

### Patterns (director / wave-gen)
- [ ] **Minefield hazard = real wave numerics + dense navigable patterns.** Same enemy counts
  as a normal wave; dense waves with patterns demanding careful navigation / focus-threading /
  shoot-through. (`scripts/levels/levels_v2.gd` minefield + director)
  - _2026-06-08: PREP DONE. mine/mine_shielded → enemy_core + straight_down; smart-mine → enemy_core
    + proximity_chase (all conductor-spawnable now). REMAINING = the actual upgrade: levels_v2
    minefield wave numerics + dense navigable patterns (still `_haz_spec` formations)._
- [x] **p_s_green waves over-rely on curves** — DONE (combat session, `ab1b7e2` "p_s_green wave variety (drift + straight variants, less weave)").
- [ ] **Conductor must not repeat patterns** — if reused, reverse them on alternating waves or
  mix with lane patterning (L→R, R→L, in/out sweeps). (`director.gd` conductor choreography)
  - _2026-06-08: SUBSTRATE only. The eligibility matrix gives per-enemy identity + eligible set +
    a per-entry `vary` flag (flat-random among eligible). The no-repeat / reverse-on-alternating-
    waves ENFORCEMENT is NOT built — the conductor doesn't yet track/avoid recent patterns._
- [ ] **Bomb-drone waves too thin again** — come as walls with dodge gaps the player must enter,
  not 1–2 stragglers. (shared with round-1 "cohesive chaff waves")
  - _2026-06-08: STILL OPEN (shares status with "Cohesive chaff waves" above)._
- [ ] **Mix-and-match lane patterns** — different lanes running different patterns in one wave
  for visual texture.
  - _2026-06-08: PARTIAL. Different enemy TYPES in a wave already run their own matrix identities,
    so mixed waves get mixed patterns for free. Same-type-different-lanes variety needs the
    eligibility `vary` flag opted-in (no entry uses it yet) + conductor lane assignment._
- [x] **Beeline group cap** — DONE (combat session, `d70fd37` "beeline cap").
- [x] **Shiv also fast-down / straight-down** — DONE (combat session, `d70fd37` "shiv" + `4d5fb48` "shiv charger").
- [x] **New CHARGER behavior** (enter slowly → accelerate-out rush) — DONE (combat session, `5627b67`
  "new lane_charge behavior (slow telegraph -> accelerate-out rush)").
- [x] **Large enemies not exiting at the bottom** — DONE (combat session, `d70fd37` "large exit").

### Shields (combat session — spec ready)
- [x] **Unify enemy shield systems onto `ShieldComponent`** — DONE. Foundation by lead (`b5c9adf`:
  CHARGE no-regen + POOL sapper modes + smart-bomb POOL awareness); migration by combat session
  (`1ba0692` "Unify enemy shields onto ShieldComponent (CHARGE/POOL); bulwark/mine/sapper migrated"
  + `d973c31` smart bomb ignores all shields). Boss Aegis stays bespoke as specced.

### Recycling — Pillar 2 (spec: `docs/archive/recycling_system_pillar2_2026-06-04.md`)
**Pillar 1 + the recycle-delay bug fix SHIPPED (`8f99dd0`)**: `mid_depth_presentation.gd` + the
side-exit cleanup fix. Pillar 2 (the central controller) + its tuner are unbuilt. Build order per
the doc: **RecycleTuner dev scene FIRST** (recycle budget / fly-back scale / tint / hold are 3+
live knobs — JSON persist + Copy-GDScript), then the controller tuned against it. Regression
surface = the whole roster → playtest-only verification.
_2026-06-10: prereq tooling landed — the Enemy Bench now has per-enemy recycle/passes/flee-chance
tagging knobs (`a58f908`). Controller + tuner + roster migration still unbuilt; ALSO note the new
off-screen hit-immunity guard (`d313dd4`) keys off `is_recycling()`/`is_fully_offscreen()` — the
RecycleController must preserve those contracts._
- [ ] **RecycleTuner dev scene** (prerequisite) — `scripts/dev/` tuner for the recycle budget +
  fly-back look, registered in `dev_menu.gd`.
- [ ] **`RecycleController` helper** (preload-const, not `class_name`) — owns offscreen→recycle
  decisioning + ONE timing budget (replacing the scattered `0.4–0.9` hold + fixed `1.8s` tween),
  with the fly-back ghost reusing `MidDepthPresentation` instead of hardcoded scale/tint.
  `enemy_base._offscreen_cleanup_check` + `enemy_core._start_cycle` delegate to it; preserve
  `is_recycling()` / `recycle_passes` / `fleeing`. (= "unified pseudo-mid recycle layer".)
- [ ] **Formation-aware re-entry** — the conductor routes recycled units into the next wave pool /
  a fresh intervening pattern so composed pincer/wall patterns don't devolve into noise. (Combat
  session note 2026-06-08: migration only set `recycle_passes` per-enemy; this + the controller
  are both unbuilt.)

### Background (likely separate scope)
- [x] **Per-row planets are static** — DONE (lead 2026-06-08, `c36a044`). Live backdrop is the V4
  coordinator (`scripts/parallax/backdrop_coordinator.gd`), NOT `galaxy_backdrop.gd`. Folded
  `current_node_id` into the coordinator RNG so each node's decorative composition varies, and mixed
  `run_seed` into every per-POI planet/deco seed in `sector_map_v3.gd` (in lockstep so map↔combat
  planet parity holds). Per-row variety now keys off run + node identity. NEEDS EYEBALL across runs.

### Sector Map
- [ ] **(PINNED 2026-06-08) Optional authored node-slot layout** — POI placement is now procedural
  (`run_state._gen_row_pois`); the per-POI `row_N_poi_M` markers in `sector_map_v3.tscn` are dead.
  If hand-placed node slots are wanted back, add an optional marker-slot path the generator shuffles
  into (authored positions + un-biased distribution). Star/boss/label markers are still live. Deferred
  at Roman's request — "I might."
- [x] **Planet-kit range not exercised** — DONE (lead 2026-06-08, `c36a044`). Every per-POI
  deco/planet/moon seed in `sector_map_v3.gd` now xors `run_seed` (all sites in lockstep so the map
  planet still matches the combat planet). Varies across runs, stable within a run. NEEDS EYEBALL.
- [x] **Node placement not randomized** — DONE (lead 2026-06-08, `c36a044`). Dropped the fixed
  Marker2D override in `_build_pois_from_cache` that always filled markers 1..count from the left;
  POIs now use the already-jittered cache pos (icon + click + label aligned). NEEDS EYEBALL.
- [x] **Boss ring progress missing** — DONE (lead 2026-06-08, `c36a044`). The HD host
  (`sector_map_hd.gd`) was drawing a solid full ring; now draws a partial completion arc per row
  from POI `completed` counts. NEEDS EYEBALL.
- [x] **Retire the old sector map entirely** — DONE (the `main.gd` asteroid-hazard exit already
  routes through the HD host via `SectorMapRoute.SECTOR_MAP_SCENE` — verified 2026-06-08). Legacy
  `scenes/sector_map.tscn` deletion still DEFERRED (Roman: "leave it for now, flag for cleanup
  later" — still used by `feature_showcase.gd` + `parse_check.ps1`).
- [x] **Outpost-as-persistent-hub redesign** — DONE (lead 2026-06-08, `aa5a85a`..`daa8594`). Roman's
  call sheet #4/#6: outposts are no longer POIs — a "Visit Outpost" sector-map button (above Manage
  Ship; player status line cut) opens a persistent hub. Stock persists across visits + re-rolls on
  boss kill; repair + ammo are charge-limited (2d6 each, +1d6/boss, "·N left" / sold-out); the
  refresh-stock button is gone; active sector modifiers are shown in the outpost. Shop Mk cap is
  boss-driven (3 + 3×bosses). NEEDS EYEBALL in-game (button placement, hub flow, charge feel).
- [x] **Signal events not randomized** — DONE (lead 2026-06-08, `c36a044`). Seed was
  `run_seed + visited_nodes.size()*31`, but `visited_nodes` is dead (always 0) so every event rolled
  identically. Re-seeded off `current_node_id`. NEEDS EYEBALL (different nodes → different outcomes).

### Audio (likely separate scope)
- [x] **Music must keep cycling** — DONE (lead 2026-06-08, `c36a044`). Hardened the `finished`
  safety-net in `music_manager.gd` so an ending track re-arms even while the intensity-walk is frozen
  (continues current intensity); only CTX_SILENT / in-flight crossfade suppress it. NEEDS EYEBALL.
- [x] **Intensity ramp** — SUPERSEDED (lead 2026-06-10, `3760e89`): full ramp rework — combat opens
  at the per-run floor, FIRST wave lifts to I2, past wave 4 lifts to Main, level-clear ramps down to
  I1, boss pins Main, and the floor rises +1 PERMANENTLY per boss beaten (Run.bosses_defeated).
  Crossfades promptly now (the old version only took effect at track end — the "not ramping" bug).
  NEEDS EAR-TEST in real combat.
- [x] **Same-frame sound overrun** — DONE (lead 2026-06-08, `c36a044`). Per-frame voice limiter at
  the `Sfx.play_one_shot` chokepoint: beyond a 4-voice soft cap, attenuate ~2.5 dB/voice (floor
  −18 dB) so mass smart-bomb deaths don't blow out. NEEDS EYEBALL (tell me if it's now too quiet).


## Controls + Player

- [x] **Rebind to genre conventions** — `5d36dcc`. Z+Space = primary, C = secondary, X = super, Shift = focus, Q/E weapon swap.
- [x] **Focus Mode** — `5d36dcc`. Hold Shift → speed × 0.55 + hitbox dot at player center.
- [x] **Settings remap UI** — `1cf36be`. Options overlay Controls section, click-to-rebind per action. Keyboard only (gamepad rebind in-app still deferred).
- [x] **Cross-session keybind persistence** — `2cdc4cd`. Settings.keyboard_overrides dict JSON-serialised to settings.cfg + replayed on Settings._ready.
- [x] **Autofire toggle** — `fba545a`. Settings.autofire (checkbox in Options).
- [x] **Gamepad support** — `94be6ab`. D-pad / left stick for movement; A/B/X/Y + LB for action buttons.

## Weapons + Parts

- [x] **Secondary fire pipeline + shuffle missile/rocket to HARDPOINT_WING** — `278066e`.
- [x] **Spread Cannon** — `83cd9f5`. Fans bullets, Mk adds bullets.
- [x] **Smart Bomb** — `b9e3458`, `ee904d9`. Screen-clear + heavy damage + 0.6s invuln.
- [x] **Hyper Mode** — `073a709` (SUPERSEDED 2026-06-08 → now a Shift stance, not a super; see the Shift-Mode section).
- [x] **Phase Shift** — `073a709` (SUPERSEDED 2026-06-08 → now a Shift stance, no bullet-clear; see the Shift-Mode section).
- [x] **Particle Beam (secondary)** — `0c0042e`, `cffbc25`, `446f5c2`, `dad6669`. Continuous beam, pierces chaff, stops on tough/boss. Width scales per Mk; 3-layer halo/main/core visual.
- [x] **Side Pods (secondary)** — `cff4d38`. Multi-pod forward fire, Mk adds pods (2 → 8).
- [x] **Drone Bits (secondary)** — `7981440`. Gradius Options — companion drones piggyback primary fire.
- [x] **Drone Swarm (super)** — `b1b57b4`. 5 s burst of 4-6 drones; reuses PlayerDrone scene.
- [x] **Outpost refill for super charges** — `3cbfef0` (free on visit), `39c6f1b` (paid in-station button).
- [x] **HUD super_charges pip strip** — `e41cf49`.
- [x] **Filter Weapon Editor list by slot_type** — `ff47632`.
- [x] **Touhou death-bomb hook** — `e41cf49`, `ee904d9`.
- [x] **PartFactory consults `resources/weapons/*.tres`** — `c54befc`.

## Onboarding

- [x] **Updated for new keybinds + Mk system** — `57faad3`.

## Dev Menu Cleanup

- [x] **Remove obsolete buttons** — `35a66a2`.
- [x] **Shipyard + Ship Sizer merge** — `1f1fd8a`. Scale slider + flip toggle folded into Shipyard. Ship Sizer dropped from dev menu. Stat editor / sprite picker remains a follow-up.
- [x] **Unified Test Combat launcher** — `eb45a8f`.

## Asteroid Lab

- [x] **Fix slider wiring + visuals** — `7835360`, `b3abdbb`, `d9feb54`. Inner ColorRect sized from Size slider; pivot centered; tints applied to inner directly; numeric readouts; smaller rail; asteroid centered in right half.

## Visual / FX

- [x] **Outline shader + preset material** — `93f4763`. `shaders/outline_1px.gdshader` + `resources/materials/outline_1px_black.tres` (round, 1px black).
- [x] **Outline asteroids in the asteroid hazard playspace** — `0a16c51`.
- [ ] **Wire the ship damage-tell system into live combat** — `ShipDamageTells` is LAB-ONLY again
  (Shader Lab → Ship Damage). It was wired live in `enemy_base` on 2026-06-17 (deferred attach, take_hit
  drove the overlay + lazy sparks/burn trails, explode() delegated the per-size death VFX) but
  **fully REVERTED 2026-06-17** after repeated intermittent native crashes during combat — incl. a
  render-server `canvas_item_set_draw_index: null` draw-order race "right as an enemy was being
  destroyed" (the absolute-z `ShipDebrisEmber` in the death frame), and earlier signal-11s fitting the
  same stale-render-command-on-a-freed-CanvasItem class. None reproduced in isolation (needs the full
  main.tscn canvas). `enemy_base` is back to the plain `damage_noise` overlay ramp + proven death VFX.
  KEPT for the lab + a future retry: the per-size `SIZE_PRESETS` (small/medium/large; tiny→small),
  UNIFORM marker selection, lazy emitter creation, `quiet()`. **Before re-wiring: reproduce the
  draw-order/freed-node race inside a real main.tscn combat first** (isolated probes won't show it),
  then guard it — don't re-enable blind. See [[damage-tells-reverted-lab-only]].
- [ ] **Coordinated marker-name rename across all enemy scenes** — bring every Marker2D onto ONE
  scheme: `Engine*` / `Thruster*` / `Muzzle*` (weapons) / `Launcher*` / `Turret*`, plus the deliberate
  `turret_base`/`turret_mount` attach anchors and the broadside `GunLeft*`/`GunRight*` mechanic names.
  The damage-tell patterns were already BROADENED (`ship_damage_tells.gd::setup`) to capture today's
  variance, so this is a *consistency* cleanup, not a functional gap. **Load-bearing — rename scene +
  script together**, because these names also drive the live firing/mount/turret systems:
  `enemy_base._resolve_muzzles` fires from `Muzzle*`/`cannon_*`; mount globs match `spec.marker`;
  `enemy_base` excludes `turret_base`/`turret_mount` from muzzles; `weapon.gd` cycles `GunLeft/Right`.
  Non-conformers found in the 2026-06-17 audit:
  - `CannonR/L` (gunship) — verify the gunship mount glob before → `cannon_r/l` or `MuzzleR/L`.
  - `TailMuzzle` (bomber, ref `enemy_bomber.gd`) → `MuzzleTail`.
  - `weapon_nose`, `turret_1/2`, `missile_port_1/2`, `launch_direction` (boss_conductor — boss firing anchors).
  - `LaunchPoint*` (missile_cruiser, ref) / `launch_point*` (rocket, ref) → `Launcher*` + script update.
  - `beam_emit_*` vs `BeamEmitter` (burner / beam_shooter) → standardize to `Beam*` (not a tell category).
  - `GunRight*/GunLeft*` (frigate) — KEEP (broadside mechanic); already caught by the broadened patterns.
  - `turret_base` (gun_turret) — KEEP (intentional attach anchor).
  - `MissileL/R` on interceptor/wing already renamed → `LauncherL/R` (`80905ada`).
  Do it as a scene+script pass per enemy with a boot check; no rush — purely cosmetic consistency now.

## Follow-ups (not in scope this pass)

- [ ] **Shipyard stat editor / sprite picker** — full unit authoring tool (edit HP, bounty, speed, hitbox, sprite per enemy in-game). Deferred — bigger UI refactor than this pass. Godot inspector on enemy `.tscn` is the authoritative path until then.
- [ ] **Gamepad rebind in-app** — keyboard rebind UI persists across sessions, but gamepad button reassignment still requires editing `project.godot`.
- [x] **WaveGeneratorV2 + scene removal** — DONE (files already deleted: `wave_generator_v2.gd` +
  `dev/wave_tester.gd`/`.tscn` gone; no `wave_v2_knobs` references remain in code).
- [x] **Old Ship Sizer scene + script** — DONE (`dev/ship_sizer.gd`/`.tscn` gone).
- [ ] **Drone autonomy** — current Drone Bits + Drone Swarm drones only fire when the player fires primary (piggyback model). Truly independent target acquisition + cadence is a follow-up if the feel warrants. [PARTIAL: 2026-05-21 — Drone Swarm now autonomous, picks bosses then nearest enemy, fires basic blaster (commit `e6c42a6`). Drone Bits was redesigned into Shield Drones (ablative, non-firing) in the same commit.]

## Cobalt 2026-05-21 backlog

- [x] **Dynamic animated nebula** — DONE 2026-06-12 (`4f862fd`). `nebula2.gdshader` got a `swirl_speed`
  uniform (TIME-driven domain-warp churn = animated swirl), the nebula is re-ENABLED in combat per-POI
  (sector_map → coordinator → layer_stellar, from a rolled `nebula_band`/`nebula_tint`), and a Shader
  Lab → Nebula page tunes it live + A/B's it vs two godotshaders.com alternates (`nebula_alt1/2`,
  uncommitted). Also fixed the pixelation (square/native-aligned) + replaced the sin-hash (precision
  banding). FINALIZING: Roman picking the winning shader via the A/B before baking live defaults.
- [~] **V3 parallax color sliders + blend-mode dropdown** — the Brightness/Contrast/Colorization sliders
  are VERIFIED WORKING on the live V4 backdrop (per-layer `CanvasModulate` grade in `layer_base`; the
  "not working" was stale from the V3/CanvasGroup era). REMAINING = the **blend-mode dropdown** (Mix /
  Add / Multiply / Screen) — non-trivial: CanvasModulate is multiply-only, so Add/Screen need a
  per-layer overlay or grade shader. (`layer_base.gd` / `parallax_tuner.gd`)
- [x] **Phase Shift + Focus supers not working** — RESOLVED by the Shift-Mode rebuild (2026-06-08,
  `0ef66ad`..`9b55e47`). Hyper + Phase are no longer supers — they're SHIFT_MODE stances on Shift
  (Focus default), Smart Bomb is the only super. Phase now has a bright-blue glow tell (`9845725`).
  See `docs/shift_mode_system_2026-06-08.md`.
- [x] **Drone Swarm super emit point** — DONE (lead 2026-06-08, `024a117`). Drones spawned on a 16px
  ring off-center; now emit from `ship.global_position` (player center), keeping `angle_seed` for the
  post-spawn boids fan-out. (Note: Drone Swarm migrated SUPER→SECONDARY on 2026-05-30.)
- [x] **Direction-based player sprite rotation** — CONFIRMED FINE (Roman 2026-06-08): the banking
  frame-swap (`player.gd` 3-frame strip on horizontal input) is visibly banking in-game. Closed.

## Enemy rework backlog 2026-05-24

- [ ] **480-speed Dart reaction-test variant** ("Sprint Dart") — distinct enemy for late-game; reuses Dart sprite + faster movement (~480 px/s), no shoot. Spun off from the 2026-05-24 speed pass where Dart was dropped from 480 → 360 for fair-play; the 480 tier still wants to exist as a deliberate reaction test.
  - _2026-06-08: STILL OPEN — not built (note: `straight_reflex` = 360 now exists as a make_movement key, the building block for it)._
- [ ] ~~**Per-enemy-class loiter timing**~~ — _SUPERSEDED 2026-06-08._ The listed enemies all left the
  shared `Loiter` cadence in the bespoke-enemy migration: Crystal → `pendulum`, Cruiser & Drone Carrier
  → `drift`, Beam Shooter → `beam_sweep`/`drift`, Gunship → `hunt_omni`. None are on Loiter anymore, so
  the shared-cadence concern is moot for them. (Loiter is still used by other holders — p_m_cannon
  loiter_mid, p_m_pulse loiter_high, etc. — if a per-class loiter pass is still wanted, re-scope to those.)
- [x] **Bullet library refactor (B2)** — _DONE._ 10 `BulletVariant` `.tres` (Basic/Aimed Sniper/Heavy
  Slug/Spread Pellet/Plasma Orb/Tracker/Burst Round/Fast Pellet/Laser Bolt/Drop Pellet) +
  `BulletCatalog.scene_for()` map each variant to its own per-bullet scene; `shoot_pattern._spawn_bullet`
  resolves it, so every roster shoot_pattern fires a library variant (not the single 200 px/s scene).
  **Weapons 3b** — ◑ PRODUCERS DONE 2026-06-13: `make_shoot` + `levels_v2` + `wave_generator` now build the
  unified `Weapon` (dir+speed-equivalence proven via `tools/test_weapon_3b_equivalence.gd`; `burst_shot.tres`
  folded into Weapon BURST = moot; latent `Weapon.TOWARD_CENTER` sign bug fixed). The legacy
  SingleShot/AimedShot/SpreadShot/BurstShot/PairShot classes still exist — embedded in ~6 designer `.tres`
  (enemy_blaster/cannon/diamond_gun/laser_cannon/wave_cannon/mg) + ~5 enemy scenes
  (cutter/drifter/hover/weaver/skirmisher) + `test_wave_darts.tres`. Migrating those + deleting the classes is
  the remaining (playtest-gated) tail.
- [ ] ~~**Bulwark drift retune**~~ — _SUPERSEDED 2026-06-08._ `bulwark_drift` (25/36/0.35) was retired;
  the Bulwark now rides the new shared `drift` pattern (hover 90 / jiggle 6px / speed 1.4, randomized
  per instance). Re-author against `drift.gd` if a retune is still wanted.

## Hazard rework backlog 2026-05-24

- [ ] **Overhaul Asteroid Hazard** — current asteroid_field level needs a structural pass. Cody flagged background asteroids overlapping the playspace; APT confirmed the underlying behavior isn't what was described and the level wants a broader rework, not a spawn-range patch. Defer until the hazard rework slot opens.

## New 2026-05-25 (designer)

- [x] **Cull the sector V3 dev menu** — done in dev tooling cleanup (this commit). Also dropped WaveGeneratorV2 + dev/wave_tester + the old dev/ship_sizer in the same pass. Grid annotation pattern preserved in `scripts/dev/grid_overlay.gd` for the new UI Plotter.
- [x] **POI visited state — disable lights + decor on resolve** — `641cb79`. Completed POIs skip planet/asteroid/cluster decoration + pulse-glow / glitter / hover label.
- [x] **Grid-based screen designer** — shipped as `scripts/dev/ui_plotter.gd` + `scenes/dev/ui_plotter.tscn`. Pick a player screen from the modal, overlay 8/16/32px annotated grid (G/L hotkeys), live mouse-cell readout. Reuses the V3 sector map grid via `scripts/dev/grid_overlay.gd`.

## Outstanding 2026-05-25 (sweep)

Captured from research docs (`docs/*.md`), recent commit bodies, agent "Open" flags, and project memory. Existing entries above not duplicated.

### Bosses (`docs/archive/boss_proposals_2026-05-24.md`)

- [x] **Boss roster gaps — Spinwright + Conductor — DONE (verified 2026-06-07).** The 7-boss roster is COMPLETE and live: `boss.gd` (Commander), `boss_reaver` (Lash), `boss_sentinel`/`boss_aegis` (Aegis), `boss_howler`, `boss_voidmaw`, `boss_spinwright`, `boss_conductor` — all with `scenes/enemies/boss_*.tscn` + wired into `wave_generator._pick_boss`, `run_state._pick_row_bosses`, and the dev menu. (Source: `docs/archive/boss_proposals_2026-05-24.md` §4)
- [x] **Tethered-orbit movement — DONE (verified 2026-06-07).** The Conductor's two satellites mirror player X + orbit via `scripts/enemies/conductor_satellite.gd` (bespoke satellite script, not a `patterns/` movement resource — same end behavior). (Source: `docs/archive/boss_proposals_2026-05-24.md` §4 Conductor)
- [ ] **Biome reskins per boss** — palette + one attack tweak variants to double visual variety once base roster ships. (Source: `docs/archive/boss_proposals_2026-05-24.md` §5)
- [ ] **Shared boss-enrage VFX helper** — phase-transition flash + screen-shake helper so HP-gate transitions read consistently across bosses. (Source: `docs/archive/boss_proposals_2026-05-24.md` §6 open question 6)
- [x] **Boss `conflict_tags` "never-pair" enforcement** — DONE (already implemented; verified lead
  2026-06-09, `tools/test_boss_pairing.gd`). `run_state._BOSS_CONFLICTS` + the greedy skip in
  `_pick_row_bosses` produce 0 forbidden pairs in sectors 2/3 over 60 seeds each. (Caveat: sector 1's
  pool is exactly 3 bosses for 3 slots, so its pairs are pool-limited by design — relax/expand the
  sector-1 pool if that's unwanted; a balance call, not a bug.)
- [ ] **Bosses with omni-strafe** — designer-flagged variation idea, currently deferred. (Source: task list #12)
  - _2026-06-08: all three boss-polish items STILL OPEN — bosses were intentionally untouched by the
    bespoke-enemy migration._

### Enemies / Bullets

- [x] **Bullet library refactor (B2)** — _DONE (2026-06-08 confirm)._ `BulletVariant` Resource + 10 variants shipped (the 7 specced + Fast Pellet/Laser Bolt/Drop Pellet), `BulletCatalog.scene_for()` maps each to its own scene, used by `shoot_pattern._spawn_bullet`. Open piece is **Weapons 3b** (unify the legacy shoot classes onto `Weapon`). (Source: `docs/archive/bullet_library_2026-05-24.md`. See the Enemy-rework B2 entry above for detail.)
- [x] **Boss bullet primitives accept `bullet_variant`** — DONE (already shipped; verified 2026-06-13).
  `boss_base.fire_aimed_burst` / `fire_aimed_cone` / `fire_ring` all take `variant: BulletVariant = null`
  and route it through `_spawn_bullet` → `_resolve_variant`. (Source: `docs/archive/bullet_library_2026-05-24.md` §6 open question 4)
- [ ] **Wave-gen `bullet_variant_override` knob** — themed waves force all enemies to fire variant X. Add if themed waves land. (Source: `docs/archive/bullet_library_2026-05-24.md` §6 open question 2)
- [x] **Per-pattern `bullet_speed` override** — DONE (Wave 1, 2026-06-13). `@export var bullet_speed: float = -1.0`
  on `shoot_pattern.gd`, honored in `_spawn_bullet` (replaces the variant baseline BEFORE the faction/sector
  mult, clamped to the clarity ceiling). `enemy_roster.make_shoot` exposes a `"bullet_speed"` entry key. No
  enemy opts in yet — wired + ready. (Source: `docs/archive/enemy_speeds_2026-05-24.md` §3, §5)
- [ ] **Chaff-speed sector scaling** — `+5%/sector` cap `+25%` if player damage already scales. (Source: `docs/archive/enemy_speeds_2026-05-24.md` §5 open question 4)
- [x] **`AimedShot.lead_factor` on Skirmisher** — DONE (Wave 1, 2026-06-13). `make_shoot`'s `"aimed"` branch
  now honors a `"lead_factor"` entry key; applied 0.15 to the corp aimed-sniper skirmisher (`enemy_c_s_hold`
  advance/retreat, fires `BV_AimedSniper` — the spiritual "Skirmisher"). 👁 playtest the feel; easy to
  re-target/tune. (Source: `docs/archive/enemy_speeds_2026-05-24.md` §4)
- [x] **Hunter Drone kamikaze bounty cancel** — DONE (Wave 1, 2026-06-13). Was BROKEN: the cancel-on-hit
  path did NOT fire. A contact hit detonated via the drone's `_on_contact` → `explode()` → `died.emit(bounty)`,
  AND the player's ram (`player._on_area_entered` → `take_hit(6)`) one-shots its 2 HP and also explodes with
  bounty intact — either way the kamikaze paid out. Fixed by zeroing `bounty_value` in `_on_contact` AND in a
  `take_hit` override (checks for an overlapping `hull` ship), so whichever path wins the overlap race, the
  contact kill is worth 0. Off-screen `_leave()` path already paid nothing. (Source: `docs/archive/economy_2026-05-24.md` §5)

### Economy (`docs/archive/economy_2026-05-24.md`)

- [~] **Mk power asymmetry (P2)** — PARKED awaiting Roman's go (call sheet #1, elaborated 2026-06-08).
  The doc proposal is WRONG — `mark_multiplier()` is NOT the cannon-damage path; cannon damage is the
  per-cannon additive `base_damage + (mark-1)*dmg_per_mark`. The real flattening = re-key each
  cannon's two numbers to a ~3× ceiling (feel-defining; hand to part-author once Roman signs off).
- [x] **Boss bounty share (P3)** — boss bounty flattened to **500** each (call sheet #2, `9845725`).
  Broader rebalance (combat-clear bonus etc.) parked per Roman ("leave the econ edits to that for now").
- [x] **Mk-Gating** — SUPERSEDED by the boss-driven cap (#5): shop Mk cap is now `min(9, 3 + 3×bosses
  defeated)` (`9845725`), replacing the sector-based formula. Cannon/upgrade no longer split.
- [x] **Boss-clear unlock bumps** — DONE via the boss-driven Mk cap above (each boss +3).
- [x] **Smart Bomb auto-bomb has no economy cost (P10)** — STALE (verified lead 2026-06-08). The
  death-bomb consumes a charge (`player.gd:1504`) and outpost refill now costs 120
  (`outpost.gd:55`); the free auto-refill-on-visit was removed. Each death-save effectively costs
  ~120 bounty. Closing as already-costed (reopen only if 120/charge feels too cheap — a balance #).
- [x] **`wanted` / `dangerous` POI bounty multipliers** — CLOSED, then SUPERSEDED 2026-06-10:
  **sector modifiers are PULLED entirely** (Roman — kill-switch `Run.SECTOR_MODIFIERS_ENABLED =
  false` gates rolling AND application, `51d4313`; vocabulary + director/player effect wiring kept
  inert). **FLAGGED FOR RE-EVAL + REIMPLEMENTATION** as its own design pass.
- [x] **Outpost density** — SUPERSEDED by the outpost-hub redesign (#4): outposts are no longer POIs
  at all (a persistent sector-map button), so per-sector density is moot.
- [x] **Asteroid 0-bounty default** — DONE: flat **+25** hazard-clear bounty (call sheet #3, `aa5a85a`).
- [x] **Hull formula Mk-9 cliff** — STALE (verified lead 2026-06-08). The doc's `20 if Mk≥9 else
  10+Mk` is not in code; actual is `max_hull = 2 + min(hull_mk, 8)` (`player.gd:1661`, ratio 3.3×,
  in-band) with Mk.9 giving a repair discount instead of a pip. The proposed `10 + 2*hull_mk` would
  make Mk.9 = 28 pips — do NOT apply. Closing as already-resolved.
- [x] **Resale arbitrage** — DONE (lead 2026-06-08, `024a117`). Found outpost at 10% but
  signal-event at 20% (the 2026-06-01 2× cannon-price bump dropped outpost to 0.1 and missed the
  signal site, reopening the arbitrage). Realigned signal to 0.1; fixed the stale "20%" comments.
  Both venues now symmetric — neither is the better dump spot.
- [x] **Manage Ship modal PartTier badges + 10% sell UI** — modal now using 10% resale. (Source: commit `d16a58d` "Manage Ship modal: add Sell UI for spare parts (10% resale)", 2026-06-13)
  - _2026-06-10/13: the modal DID gain the SHIFT_MODE slot row (`db41620`) + 10% sell UI + module management (`c59ec58`). Tier badges deferred. — DONE (2026-06-13)_
- [x] **Outpost density hard clamp → probabilistic** — SUPERSEDED by the outpost-hub redesign (#4):
  outposts are a sector-map button now, not POIs, so there's no per-sector outpost count to tune.

### Visual / VFX

- [x] **Dynamic animated nebula** — DONE 2026-06-12 (`4f862fd`); see the Cobalt backlog entry above for detail.
- [~] **V3 parallax blend-mode dropdown** — sliders verified working; only the Mix/Add/Mul/Screen blend dropdown remains (see Cobalt entry above).
- [ ] **Galaxy Backdrop V3 missing debris sprite** — `scripts/parallax/galaxy_backdrop_v3.gd:392` `# TODO — needs a debris sprite`. (Source: `scripts/parallax/galaxy_backdrop_v3.gd:392`)
- [x] **Moon/planet drift off the bottom on long combats** — DONE (call sheet #10, `9845725`).
  Roman's call: ~4 min to drift fully off-screen, no wrap. Retuned the planet layer `scroll_rate`
  0.025 → 0.03 (planet layer only; global drift + other parallax untouched). NEEDS EYEBALL.
- [~] **`current_stellar` cleared per POI click** — likely MOOT after the planet-variety seed work
  (`c36a044`): each node now derives a distinct, stable `current_stellar`, so the combat backdrop no
  longer looks uniform across a sector. EYEBALL to confirm, then close.
- [x] **Shadow shaders cluster — retire prototypes** — DONE (lead 2026-06-08, `c36a044`). Deleted
  `masked_shadow`/`topdown_shadow_outofbounds`/`drop_shadow_canvas_group` shaders + all six
  `capture_shadow_*` drivers (+ `.uid`/`.ps1` + `capture_shadow_compare.ps1`). Zero live refs.
- [x] **Parallax shader cluster — retire** — DONE (lead 2026-06-08, `c36a044`). Removed the dead
  `TINT_SHADER` const from `galaxy_backdrop_v3.gd` and deleted `parallax_tint.gdshader` +
  `parallax_silhouette.gdshader` (+ `.uid`).
- [x] **`starstuff.gdshader` retire** — DONE (lead 2026-06-08, `c36a044`). Removed the unused
  `STARSTUFF_SHADER` const from `galaxy_backdrop.gd` and deleted the shader (the separate
  `SpaceBG/StarStuff.gdshader` is untouched).
- [x] **Audit `particle_trail.gdshader` + `bloom.gdshader` references** — DONE (lead 2026-06-08,
  `c36a044`). Confirmed zero refs (by path AND UID) → both deleted.
- [x] **NEBULA_SHADER preload dead in V3** — DONE (lead 2026-06-08, `c36a044`). Removed the dead
  `NEBULA_SHADER` const (V3 uses NEBULA2); left the `nebula.gdshader` file (V1 may use it).

### Weapons / Architecture (`docs/archive/weapon_architecture_2026-05-24.md`)

- [x] **`scripts/bullet.gd` + `scripts/bullet_wave.gd` live at `scripts/` root** — DONE (Wave 1, 2026-06-13).
  `git mv`'d both (+ their `.uid`) into `scripts/projectiles/`; updated 7 `.tscn` `path=` refs + `bullet_heavy.gd`
  extends + the contributing doc; ran a Godot `--import` to rebuild the UID cache (the `.tscn` resolve scripts by
  UID, so the move alone left a stale cache → parse failures until reimport). Parse + headless boot clean.
  (Source: `docs/archive/weapon_architecture_2026-05-24.md` §5)
- [x] **`drone_bits.apply()` doesn't snapshot prior `ship.drone_bits` array** — DONE (lead 2026-06-08, `85bf63c`). apply() snapshots, unapply() restores. (Impact nil today; contract now symmetric.)
- [x] **Heavy Blaster cooldown lerp** — STALE (lead 2026-06-09). Code now intentionally scales
  cooldown **0.28 → 0.18** Mk1→Mk9 (a deliberate "faster at top tier" cadence, per the script
  comments) — NOT the "0.20→0.18 drift" this item described. Reverting to constant 0.20 would remove
  the intended scaling. Closing as already-by-design.
- [x] **basic_blaster + spread_cannon snapshot/restore asymmetry** — STALE (verified lead 2026-06-08). The `weapon_part` base already snapshots + restores `weapon_style`/`fire_sfx_kind` via `_all_snapshot_keys()`; no asymmetry in current code. Closing.
- [x] **`drone_bits.tres` + `drone_swarm.tres` stale defaults** — DONE (Wave 1, 2026-06-13). `drone_bits.tres`
  held the OLD Gradius-Options numbers (`base_drones=1`, `max_drones=5`) — and since `_build_weapon` loads the
  `.tres` at runtime (Godot skips `_init` on disk resources), Intercept Drones was actually spawning **1 drone,
  not the 3** the redesign specifies — fixed to 3/3. `drone_swarm.tres` got explicit `base_charges=1`/
  `charges_per_mark=1` (matching its `.gd` + the script comment that claims the `.tres` sets them). `slot_type=5`
  was already correct (= HARDPOINT_WING). (Source: `docs/archive/redundancy_audit_2026-05-21.md` §Weapons action items)
- [ ] **Weapon mounts: per-Part `fire_offset: Vector2`** — so wing-mounted vs nose-mounted weapons don't all spawn at `(0,-10)`. (Source: `docs/archive/weapon_architecture_2026-05-24.md` §4 item 5)
- [x] **`burst_shot.tres` — author designer instance** — MOOT (decided 2026-06-13 during Weapons 3b). The
  roster's burst firing now builds `Weapon` with `FirePattern.BURST` (burst_count/burst_interval), so a
  standalone `BurstShot` `.tres` is no longer needed. (Source: `docs/archive/redundancy_audit_2026-05-21.md` §Enemy shoot patterns)

### Dev tools

- [x] **WaveGeneratorV2 + Ship Sizer removal** — DONE (files gone; see Follow-ups above).
- [ ] **`scenes/sector_map.tscn` orphan** — pre-existing V1 map, referenced by `feature_showcase.gd` + `tools/parse_check.ps1`. Roman: "leave it for now, flag for cleanup later." (Source: memory `project_sector_map_v3.md` §Known open issue 3)
- [ ] **`SmokeTrail.new(palette)` factory** — consolidate `damage_smoke_trail.gd` + `missile_smoke_trail.gd` (~90% shared code) once a third smoke emitter appears. Not urgent. (Source: `docs/archive/redundancy_audit_2026-05-21.md` §Particle effects)

## End-of-run summary + run history + run timer (rolled in 2026-06-08)

Full scoping in `docs/archive/run_summary_scope_2026-06-01.md` (re-audited 2026-06-05). Status: **Phase 4
(dated run-history index) DONE (`1c86ba2`); Phases 1–3 + the run timer still NOT built — no stats
instrumentation has landed** (re-confirmed 2026-06-08: the outpost-hub work did NOT add the
bounty-spend choke-point Phase 2 needs — the outpost still does bare `run.bounty -=` in several
places). Splits into a cheap core + an expensive tail. NOTE: most hooks live in
`player.gd` / `enemy_base.gd` / `main.gd` — shared / combat-arena files; coordinate with the combat
session before instrumenting those hot paths.

- [x] **Phase 1 — `RunStats` core + Run Timer** — DONE (lead autonomous, `aedc7a1`). `run_stats` +
  `run_time_seconds` on Run (reset/persisted/in history record); tallied off existing signals
  (Player.damaged, record_kill, asteroid counter); active-combat timer keyed on `playing`; death
  screen shows Time/Bosses/Bounty/Damage(shield·hull)/Asteroids. _(orig scope below; Phases 2/3 open.)_
- [~] **Phase 1 — `RunStats` core (~½–1 day, ship first).** Add a run-wide stats accumulator on the
  `Run` autoload; reset it in `new_run()` alongside the other run-scoped fields. Surface Tier-1 stats
  that already have signals: **damage taken** (shield vs hull, off `Player.damaged` 0/1), **bounty
  gained** (off `Run.record_kill()`), **asteroids destroyed** (roll up `_asteroids_killed_this_level`
  instead of resetting). Redo the death summary (`run_summary.gd`) to show them. Reuses
  `cleared_summary.gd`'s per-enemy-type tally + sprite previews. Proves the `RunStats` pattern before
  touching hot paths.
- [x] **Run Timer (fold into Phase 1 — near-zero marginal).** `run_time_seconds` on `Run`, **active
  combat time only** (recommended): a pausable delta-accumulator keyed on `playing` auto-excludes
  intro/outro/pause/map/shop/transitions. Zero in `new_run()`, accumulate in `_on_level_cleared`,
  flush in `_on_player_died`. Persist via `RunSave` (`_SAVE_FIELDS` + a `@export` mirror — both sides
  or it's silently dropped). Optional per-level breakdown into `RunStats`. **Open call:** also show
  wall-clock total (B), or active-only (A)? Stop-on-victory point doesn't exist yet (see Phase 3). — DONE (2026-06-13)
- [x] **Phase 2 — new instrumentation (~1–1.5 days).** Tier-2/3 hooks with no signal today:
  **shots fired** (hook `player.gd` fire fns — hot path, no per-shot alloc), **shots hit / accuracy**
  (hook `enemy_base.gd take_hit`; counting model LOCKED = per-projectile-spawned, multi-hit can
  exceed 100%), **bounty spent** (single choke-point over the outpost's bare `run.bounty -=`),
  **mines cleared** (via kill path / scene_path), **locations/stations/signals visited** (via reliable
  `mark_node_completed` + node-type counting — the V3 map bypasses `mark_node_visited`), **unique
  weapons used** (net-new hook on active-cannon change/fire). — DONE (2026-06-13)
- [x] **Phase 3 — victory / "patrol complete" path (~½ day).** NET-NEW code path: `run_summary.tscn`
  is reached only on death today; final-sector clear funnels through the endless-mode prompt. Need a
  real patrol-complete flow + screen, and `RunStats` must snapshot into history at BOTH exit points
  (death AND victory) before reset. This is also where the run timer's stop-on-victory wires in. — DONE (2026-06-13)
- [x] **Phase 4 — dated run-history index** — DONE (lead 2026-06-08, `1c86ba2`). `user://run_history.json`
  (capped to last 50) written on the death flow from stats Run already tracks; "Run History" main-menu
  button → `scenes/run_history.tscn` list. Victory hook will call the same `record_run_history()` once
  a patrol-complete path exists (Phase 3).

## Supers / Modes / Modules taxonomy refactor (rolled in 2026-06-08)

**STANCE part = BUILT** (`docs/shift_mode_system_2026-06-08.md`, `0ef66ad`..`9b55e47` + `9845725`).
One permanent Super (Smart Bomb, X) + a one-of-three stance slot (Focus default / Phase / Hyper) on
Shift, with per-mode resources, HUD meter, outpost purchase + signal-event finds. The old
`docs/archive/supers_modes_modules_2026-06-05.md` (Mode-Energy gauge / ace-chain) is SUPERSEDED.

- [x] **Super / stance-slot restructure** — DONE. Smart Bomb is the only super (DEVICE_BAY_1); a real
  SHIFT_MODE slot holds Focus/Phase/Hyper as ModeParts.
- [x] **Stance triangle (Focus | Phase | Hyper) on Shift** — DONE. Focus default; Phase = intangible
  reposition, no bullet-clear, kill-earned charges + blue glow tell; Hyper = +10% fire + unlimited
  ammo on a full-gated bar. Mk scaling per the design doc.
- [x] **Mode resource + recharge** — DONE, simpler than the old Mode-Energy spec: Phase charges refill
  on kills, Hyper bar recharges idle (gated to full). Mode-Energy gauge / dual-hitbox focus-save /
  ace-chain coupling were DROPPED.
- [x] **Mode HUD + outpost economy** — DONE. HUD mode meter (`db19a58`); modes bought at outposts
  (`2eb2c35`) + found via the Stance Module Cache signal event (`9b55e47`).

REMAINING — the **PASSIVE-MODULE layer** (the other half of `supers_modes_modules_2026-06-05.md` §2,
§12–13, §15; the stance half above is built). Modules = a 4-slot bay of automatic (no-input) Parts
that ADD a mechanic (vs Upgrades, which refine a number). Shield is default-equipped → real choice =
**3 of the rest** (or 4 if you go shieldless). All `Part` + `apply/unapply` + Mk.1–9 — no new part
infra needed (the SHIFT_MODE slot work proves the pattern; reserved `DEVICE_BAY_2`/`SHIELD`/wing
enums absorb the bay slots). Net-new = the bay UI + the reify refactor + the roster.

- [x] **A. Passive-module bay infrastructure** — a 4-slot module axis (separate from the stance slot),
  on the reserved `SlotTypes` enums; a `ModulePart` base (automatic apply/unapply, Mk.1–9); bay
  swap/buy/upgrade UI at outposts + Manage Ship + a HUD readout of equipped modules. — DONE (2026-06-13)
- [x] **B. Reify defensive systems as Modules** — Shield / Hull Regen (`self_repair_mk`) / Hull
  Plating (`hull_plating_mk`) from abstract `Run` int Mk-keys → passive Part Resources (OPEN: reify
  vs. keep `Run`-ints but *present* in the bay; cheaper). Shield = default-equipped (dropping it =
  deliberate glass-cannon). `shield_cap_mk` stays an Upgrade scaling the Shield module's capacity. — DONE (2026-06-13)
- [x] **C. Classification moves** — Intercept Drones (the ablative non-firing "Shield Drones",
  `e6c42a6`) HARDPOINT_WING-secondary → passive Module; Ammo Pods (pure +ammo%) → Upgrade per the §1
  corollary (a number, not a mechanic). — DONE (2026-06-14)
- [x] **D. The roster (§15) — ~10 picks for ~3 free slots** (4 def / 3 off / 3 risk-utility). Each
  adds a *mechanic*, Mk.1–9. **18 modules BUILT (2026-06-13/14):** Shield Core, Overcharge Core, Siphon Core, Repair Nanites, Ablative Plating, Targeting Computer, Overclock Core, Critical System De-Limiter, Reinforced Hull, Thrusters, Shield Capacitor, Intercept Drones, Backup Shield Capacitor, Reflective Shield Tuning, Internal Micro Fabricator, Passive Energy Routers, Blaster Smart Mount, Primary Smart Mount. Tractor Coil CUT (no pickup system). — DONE (2026-06-14)
- [x] **E. Build-archetype sanity check** (§15) — Fortress / Aggro-clear / Glass-Cannon / Economist
  should each be a real, distinct build once the bay + roster land (the proof the 4 slots "sing"). — DONE (2026-06-13)

## New features scoped (2026-06-08)

- [x] **Weapon/Item String Expansion + Armory tab** — DONE (lead autonomous, `518443a`). `armory_strings.gd`
  (codex blurbs for ~21 items, mirror approach) + an Armory folded into the codex (4 slot categories,
  rotating preview + blurb). Modes/super/beam show name+blurb only — placeholder-icon gap flagged for
  Roman. Headless-verified. _(orig scope below.)_
- [~] **Weapon/Item String Expansion + Armory tab** — every player item (primary cannon / secondary /
  super / Shift mode / passive module) needs a centralized **display name + codex blurb**, plus a new
  **Armory codex tab** (mirror the enemy codex: slow-rotating sprite + dropshadow + glowmap, name,
  blurb — pulled from the game). Today all part names/descriptions are hardcoded inline in each part's
  `_init`, none from a strings file. New `scripts/armory_strings.gd` (mirror `codex_strings.gd`
  convention) + categories/render branches in `enemy_codex.gd` + reuse `_add_preview`. ⚠️ modes /
  super / particle-beam have **no projectile sprite** → need placeholder icons. Scope + build surface
  + open decisions (strings authoritative vs mirror; icon art; tab granularity):
  **`docs/archive/armory_string_expansion_2026-06-08.md`**.

- [x] **New Secondary — Swarm Launcher** — DONE (lead autonomous, `4405b29`). Built per the spec doc;
  headless-verified (distinct-target round-robin, re-acquire-on-death, Mk 4/6/20, 6 ammo / 3s cd).
  Placeholder art (energy_bolt_small tinted) + feel pass flagged for Roman. _(orig spec below)_
- [~] **New Secondary — Swarm Launcher** — HARDPOINT_WING salvo of seeking missiles: **4 dmg** each,
  **4 missiles at Mk.1 (+2/Mk)**, prefer **distinct targets** (else all chase one; **re-acquire on
  target death**; fly on + explode **harmlessly** if none), **6 px/f** with a **tight turn arc**,
  bright **yellow-orange flickering pixel + diffuse glow + trail**, **6 ammo / 1 per salvo / 3s
  cooldown**. The two net-new bits = **distinct-target assignment** (round-robin; no helper exists)
  + **re-target-on-death** on a Swarm-specific missile subclass (current player missiles clump on
  nearest + fly straight on death). Everything else builds on `base_missile` + the secondary pipeline
  (DEPLOY-style own-spawn, or a new `SALVO` mode for the 3s cooldown). ⚠️ set `speed_lock_mult = 1.0`
  (else 6 px/f → 12 px/f post-lock, over the 480 ceiling). Full spec + build plan:
  **`docs/archive/swarm_launcher_secondary_2026-06-08.md`**.

## Faction gap units — sprites/enemies to commission (M6b, 2026-06-06)

End-state (Roman): each faction owns its FULL unit set; drop the universal-core stopgap.
The only thing truly cross-faction is **adding privateer units into another faction's pool**.
Below = the per-faction slots NOT yet covered by a faction-OWNED hull (currently filled by a
universal-core overlay). Each entry = **role / behavior @ size**. Get sprites worked up, then
they become data on the existing chassis/behavior/component/Weapon machinery (new art only).
Full context + the coverage matrix: `docs/m6b_faction_tagging_2026-06-06.md`.

> **STATUS 2026-06-07 (post-M6c):** three faction art packs + the gunship/interceptor
> move landed. Per-faction OWNED-exclusive counts now (on top of the 10 shared universal
> hulls): **supremacy 4, zealot 8, corporate 8, privateer 9.** ✓ = now covered by a
> faction-owned hull; remaining bullets still need art.

- [ ] **supremacy (Crimson Supremacy — faster fire)**
  - ✓ Charger (rush), ✓ Sweeper (plasma), ✓ Anchor (push — replaced frigate), ✓ fighter+Weaver (hotrod, dive/straight/weave; replaced strafer)
  - STILL: dedicated small **Drifter**, dedicated small **Crosser**, an **elite** event piece
  - (owns: Diver=bomb_drone, Holder=crystal, capital=cruiser, + rush/hotrod/plasma/push)
- [ ] **zealot (Evantian Theocracy — drops firecore)**
  - ✓ Holder + Skirmisher (retro), ✓ Drifter (manta — replaced drifter), ✓ Weaver-ish (run, unarmed weave), ✓ Crosser/pusher (sword)
  - STILL: a **non-elite Anchor @ medium**, a **non-elite capital @ large** (helix/beamers/burner are all RARE elites; sword is small)
  - (owns: Diver=spitter, pressure=firecore_drone(bloom), elite-capital=firecore_cruiser(helix), Sweepers=beamers, elite=burner, + retro/run/sword/manta)
- [ ] **privateer (Vertarine Armada — tough; the overlay faction)**
  - ✓ Weaver (green), ✓ medium Anchor (cannon / rocket / gunship), ✓ pressure (pulse), ✓ Dropper (drop), ✓ omni gunship + hold/weave/shift/skirmish variants
  - STILL: small **Holder** + small **Skirmisher** (only MEDIUM exist), a **large capital**, an **elite** event piece
  - (owns: Diver=dart, Crosser=cutter, Dropper=minelayer, Slider=interceptor[moved in], + green/gray/drop/cannon/pulse/gunship/rocket)
- [ ] **corporate (UltraGalactic — shielded)**
  - ✓ own Diver (gray), ✓ own chaff Weaver+Dropper (curve/drop), ✓ re-skinned Holder (hold — replaced hover)
  - **NEW GAPS from the M6c moves:** interceptor (Slider) + gunship (elite) LEFT for privateer; strafer (Striker) retired for supremacy hotrod. Corporate keeps Striker=hunter_drone, capital=bulwark, elite=drone_carrier — but lost its **Slider** role and one **elite**.
  - (owns: Weaver, Holder=hold, Skirmisher, Harrier=sapper[rare], Striker=hunter_drone, Anchor=bomber, capital=bulwark, elite=drone_carrier, + gray/curve/drop)

Also pending art/rename housekeeping: **spitter** (firecore popper rename, §12.5); a
**privateer/supremacy** large-capital silhouette if cruiser shouldn't be shared.

## Already-done (since this list was captured)

- Wave editor with full CRUD + playtest + state persistence.
- Movement Pattern Editor + Shoot Pattern Editor (reflection-driven, live preview).
- Weapon Editor (Mk slider, DPS readout, tracer preview).
- HD viewport pattern (`Window.content_scale_size` swap) for text-dense dev pages.
- Wave Editor → pattern editor round-trip via `pattern_editor_return_scene` meta.
